-- NODEX Phase 1: server-side issuance of the device-bound authorization snapshot.
--
-- This RPC is the authorized backend path for snapshot issuance. It runs
-- SECURITY DEFINER so it can read the membership graph, but it derives every
-- value from the authenticated principal and never trusts client-supplied
-- roles, permissions or scopes.
--
-- offline_permissions is computed as the subset where permissions.requires_online
-- is false, so privileged actions are excluded from the offline snapshot by
-- construction rather than by client-side filtering.

create or replace function public.issue_authorization_snapshot(
  p_tenant_id          uuid,
  p_device_fingerprint text,
  p_session_id         text default null,
  p_app_version        text default null,
  p_os_version         text default null
)
returns table (
  snapshot_id         uuid,
  tenant_id           uuid,
  device_id           uuid,
  snapshot_revision   integer,
  roles               text[],
  permissions         text[],
  offline_permissions text[],
  facility_ids        uuid[],
  department_ids      uuid[],
  ward_ids            uuid[],
  payload_digest      text,
  issued_at           timestamptz,
  expires_at          timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id       uuid := auth.uid();
  v_device        public.devices;
  v_roles         text[];
  v_permissions   text[];
  v_offline_perms text[];
  v_facilities    uuid[];
  v_departments   uuid[];
  v_wards         uuid[];
  v_revision      integer;
  v_digest        text;
  v_issued_at     timestamptz := now();
  v_expires_at    timestamptz;
  v_snapshot_id   uuid;
begin
  if v_user_id is null then
    raise exception 'NODEX: authentication required' using errcode = '28000';
  end if;

  if p_device_fingerprint is null or length(btrim(p_device_fingerprint)) = 0 then
    raise exception 'NODEX: device fingerprint required' using errcode = '22023';
  end if;

  -- The caller must hold an active, unexpired membership in the tenant.
  if not exists (
    select 1
    from public.memberships m
    where m.user_id = v_user_id
      and m.tenant_id = p_tenant_id
      and m.status = 'active'
      and m.valid_from <= v_issued_at
      and (m.valid_until is null or m.valid_until > v_issued_at)
  ) then
    raise exception 'NODEX: no active membership in tenant %', p_tenant_id
      using errcode = '42501';
  end if;

  -- Enrol on first contact; an existing device must be active and, when already
  -- bound to a user, must be bound to this user.
  select * into v_device
  from public.devices d
  where d.tenant_id = p_tenant_id
    and d.device_fingerprint = p_device_fingerprint;

  if not found then
    insert into public.devices (
      tenant_id, device_fingerprint, assigned_user_id, status,
      app_version, os_version, last_seen_at
    )
    values (
      p_tenant_id, p_device_fingerprint, v_user_id, 'pending',
      p_app_version, p_os_version, v_issued_at
    )
    returning * into v_device;
  else
    if v_device.status not in ('pending', 'active') then
      raise exception 'NODEX: device % is %', v_device.id, v_device.status
        using errcode = '42501';
    end if;

    if v_device.assigned_user_id is not null
       and v_device.assigned_user_id <> v_user_id then
      raise exception 'NODEX: device % is assigned to another user', v_device.id
        using errcode = '42501';
    end if;

    update public.devices d
       set assigned_user_id = coalesce(d.assigned_user_id, v_user_id),
           app_version      = coalesce(p_app_version, d.app_version),
           os_version       = coalesce(p_os_version, d.os_version),
           last_seen_at     = v_issued_at
     where d.id = v_device.id
    returning * into v_device;
  end if;

  if v_device.wipe_requested_at is not null
     and v_device.wipe_confirmed_at is null then
    raise exception 'NODEX: device % has a pending wipe request', v_device.id
      using errcode = '42501';
  end if;

  -- Resolve effective roles and scopes from active memberships.
  select
    coalesce(array_agg(distinct m.role_key), '{}'),
    coalesce(array_agg(distinct m.facility_id)   filter (where m.facility_id is not null), '{}'),
    coalesce(array_agg(distinct m.department_id) filter (where m.department_id is not null), '{}'),
    coalesce(array_agg(distinct m.ward_id)       filter (where m.ward_id is not null), '{}')
  into v_roles, v_facilities, v_departments, v_wards
  from public.memberships m
  where m.user_id = v_user_id
    and m.tenant_id = p_tenant_id
    and m.status = 'active'
    and m.valid_from <= v_issued_at
    and (m.valid_until is null or m.valid_until > v_issued_at);

  select
    coalesce(array_agg(distinct p.key), '{}'),
    coalesce(array_agg(distinct p.key) filter (where not p.requires_online), '{}')
  into v_permissions, v_offline_perms
  from public.memberships m
  join public.role_permissions rp on rp.role_key = m.role_key
  join public.permissions p       on p.key = rp.permission_key
  where m.user_id = v_user_id
    and m.tenant_id = p_tenant_id
    and m.status = 'active'
    and m.valid_from <= v_issued_at
    and (m.valid_until is null or m.valid_until > v_issued_at);

  -- A role marked offline_capable = false cannot operate from a cached snapshot.
  if exists (
    select 1
    from public.roles r
    where r.key = any (v_roles)
      and not r.offline_capable
  ) then
    v_offline_perms := '{}';
  end if;

  v_expires_at := v_issued_at
                  + make_interval(mins => greatest(v_device.offline_window_minutes, 1));

  select coalesce(max(s.snapshot_revision), 0) + 1
    into v_revision
  from public.authorization_snapshots s
  where s.device_id = v_device.id
    and s.user_id = v_user_id;

  v_digest := encode(
    extensions.digest(
      concat_ws(
        '|',
        v_user_id::text,
        p_tenant_id::text,
        v_device.id::text,
        v_revision::text,
        array_to_string(v_roles, ','),
        array_to_string(v_permissions, ','),
        array_to_string(v_offline_perms, ','),
        array_to_string(v_facilities, ','),
        array_to_string(v_departments, ','),
        array_to_string(v_wards, ','),
        v_issued_at::text,
        v_expires_at::text
      ),
      'sha256'
    ),
    'hex'
  );

  -- Supersede any live snapshot for this device/user pair.
  update public.authorization_snapshots s
     set revoked_at = v_issued_at,
         revoked_reason = 'superseded'
   where s.device_id = v_device.id
     and s.user_id = v_user_id
     and s.revoked_at is null;

  insert into public.authorization_snapshots (
    tenant_id, user_id, device_id, snapshot_revision,
    roles, permissions, facility_ids, department_ids, ward_ids,
    offline_permissions, payload_digest, issued_at, expires_at, issued_session_id
  )
  values (
    p_tenant_id, v_user_id, v_device.id, v_revision,
    v_roles, v_permissions, v_facilities, v_departments, v_wards,
    v_offline_perms, v_digest, v_issued_at, v_expires_at, p_session_id
  )
  returning id into v_snapshot_id;

  update public.app_users u
     set last_login_at = v_issued_at
   where u.id = v_user_id;

  insert into public.audit_events (
    tenant_id, actor_id, device_id, session_reference, action,
    resource_type, resource_id, origin, outcome, risk_tier, metadata
  )
  values (
    p_tenant_id, v_user_id, v_device.id, p_session_id,
    'authorization_snapshot.issued',
    'authorization_snapshot', v_snapshot_id, 'online', 'succeeded', 'elevated',
    jsonb_build_object(
      'snapshot_revision', v_revision,
      'role_count', coalesce(array_length(v_roles, 1), 0),
      'permission_count', coalesce(array_length(v_permissions, 1), 0),
      'offline_permission_count', coalesce(array_length(v_offline_perms, 1), 0),
      'expires_at', v_expires_at
    )
  );

  return query
  select
    v_snapshot_id, p_tenant_id, v_device.id, v_revision,
    v_roles, v_permissions, v_offline_perms,
    v_facilities, v_departments, v_wards,
    v_digest, v_issued_at, v_expires_at;
end;
$$;

comment on function public.issue_authorization_snapshot(uuid, text, text, text, text) is
  'Authorized backend path for issuing a device-bound, time-bounded offline authorization snapshot. Derives all scopes server-side; never trusts client-supplied authorization input.';

revoke all on function public.issue_authorization_snapshot(uuid, text, text, text, text) from public;
grant execute on function public.issue_authorization_snapshot(uuid, text, text, text, text) to authenticated;
