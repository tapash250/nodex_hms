-- NODEX Phase 1: user provisioning from administrative invites.
--
-- Closes the first-sign-in gap: an authenticated principal previously had no
-- app_users row and therefore no membership, so authorization snapshot issuance
-- failed with "no active membership in tenant".
--
-- Model: access is granted by invitation, never by signup. An administrator
-- holding user.administer creates a user_invites row; when the invited email
-- signs up through Supabase Auth, an AFTER INSERT trigger on auth.users
-- provisions the app_users row and the granted membership. A user signing up
-- without an invite is provisioned with nothing: fail closed.
--
-- This mirrors the real hospital workflow (HR creates the employee record
-- before day one) and keeps tenant admission an auditable administrative act.

create table public.user_invites (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references public.tenants (id) on delete cascade,
  email            text not null
                   check (email ~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'),
  full_name        text not null check (length(btrim(full_name)) > 0),
  display_name     text,
  phone            text,
  designation      text,
  registration_no  text,
  employee_code    text,
  role_key         text not null references public.roles (key) on delete restrict,
  facility_id      uuid references public.facilities (id) on delete set null,
  department_id    uuid references public.departments (id) on delete set null,
  ward_id          uuid references public.wards (id) on delete set null,
  status           text not null default 'pending'
                   check (status in ('pending', 'accepted', 'cancelled', 'expired')),
  invited_by       uuid references public.app_users (id) on delete set null,
  valid_until      timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

comment on table public.user_invites is
  'Administrative invitation granting a role and scope to an email address. Provisioning happens when the invited principal first signs in.';
comment on column public.user_invites.status is
  'pending: awaiting first sign-in. accepted: consumed by provisioning. cancelled/expired: never granted or withdrawn before use.';

-- One pending invite per (tenant, email, role, scope): duplicate invites are a
-- data-entry error, but the same email may hold different roles, and may be
-- invited independently by several tenants.
create unique index user_invites_one_pending
  on public.user_invites (
    tenant_id,
    lower(email),
    role_key,
    coalesce(facility_id,   '00000000-0000-0000-0000-000000000000'::uuid),
    coalesce(department_id, '00000000-0000-0000-0000-000000000000'::uuid),
    coalesce(ward_id,       '00000000-0000-0000-0000-000000000000'::uuid)
  )
  where status = 'pending';

create index user_invites_tenant_idx     on public.user_invites (tenant_id, status, created_at desc);
create index user_invites_email_idx      on public.user_invites (lower(email));

-- ---------------------------------------------------------------------------
-- Row defaults and governance triggers
-- ---------------------------------------------------------------------------

create or replace function nodex.tg_user_invite_defaults()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.email := lower(btrim(new.email));
  if new.invited_by is null then
    new.invited_by := auth.uid();
  end if;
  return new;
end;
$$;

comment on function nodex.tg_user_invite_defaults() is
  'BEFORE INSERT: normalizes the invite email and attributes the invitation to the calling administrator.';

create trigger user_invites_set_defaults
  before insert on public.user_invites
  for each row execute function nodex.tg_user_invite_defaults();

-- Invite creation is a privilege grant waiting to happen: audit it even when
-- created from a client, which cannot write audit_events directly by design.
create or replace function nodex.tg_user_invite_audit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.audit_events (
    tenant_id, actor_id, action, resource_type, resource_id,
    origin, outcome, risk_tier, metadata
  )
  values (
    new.tenant_id, new.invited_by, 'user_invite.created', 'user_invite', new.id,
    'online', 'succeeded', 'elevated',
    jsonb_build_object(
      'role_key', new.role_key,
      'facility_id', new.facility_id,
      'department_id', new.department_id,
      'ward_id', new.ward_id
    )
  );
  return new;
end;
$$;

comment on function nodex.tg_user_invite_audit() is
  'AFTER INSERT: records every invitation as an elevated audit event so privilege grants are traceable before first sign-in.';

create trigger user_invites_audit_created
  after insert on public.user_invites
  for each row execute function nodex.tg_user_invite_audit();

create or replace function nodex.tg_user_invite_freeze()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.status = 'accepted' then
    raise exception using
      message = 'NODEX: user invite ' || old.id || ' has been consumed by provisioning and is immutable',
      errcode = '42501';
  end if;

  if old.status = 'pending' and new.status = 'pending' then
    raise exception using
      message = 'NODEX: a pending user invite may only be cancelled or expired, not edited',
      errcode = '42501';
  end if;

  new.id          := old.id;
  new.tenant_id   := old.tenant_id;
  new.email       := old.email;
  new.full_name   := old.full_name;
  new.role_key    := old.role_key;
  new.invited_by  := old.invited_by;
  new.created_at  := old.created_at;

  return new;
end;
$$;

comment on function nodex.tg_user_invite_freeze() is
  'BEFORE UPDATE: a pending invite may only transition to cancelled/expired; an accepted invite is frozen evidence.';

create trigger user_invites_freeze
  before update on public.user_invites
  for each row execute function nodex.tg_user_invite_freeze();

-- ---------------------------------------------------------------------------
-- Provisioning trigger on auth.users
-- ---------------------------------------------------------------------------

create or replace function nodex.tg_provision_invited_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_invite record;
  v_window_cap integer;
begin
  -- Phone-only signups carry no email and can never match an invite.
  if new.email is null or btrim(new.email) = '' then
    return new;
  end if;

  for v_invite in
    select *
    from public.user_invites i
    where lower(i.email) = lower(new.email)
      and i.status = 'pending'
      and (i.valid_until is null or i.valid_until > now())
    order by i.created_at asc
    for update
  loop
    -- The authorization subject. primary_tenant_id is filled only when absent so
    -- a later invitation from another tenant cannot silently move the account.
    insert into public.app_users (
      id, primary_tenant_id, full_name, display_name, email, phone,
      designation, registration_no, employee_code, status
    )
    values (
      new.id, v_invite.tenant_id, v_invite.full_name, v_invite.display_name,
      new.email, v_invite.phone, v_invite.designation, v_invite.registration_no,
      v_invite.employee_code, 'active'
    )
    on conflict (id) do update
      set primary_tenant_id = coalesce(
            public.app_users.primary_tenant_id,
            excluded.primary_tenant_id
          ),
          updated_at = now();

    if not exists (
      select 1
      from public.memberships m
      where m.tenant_id = v_invite.tenant_id
        and m.user_id = new.id
        and m.role_key = v_invite.role_key
        and coalesce(m.facility_id,   '00000000-0000-0000-0000-000000000000'::uuid)
            = coalesce(v_invite.facility_id,   '00000000-0000-0000-0000-000000000000'::uuid)
        and coalesce(m.department_id, '00000000-0000-0000-0000-000000000000'::uuid)
            = coalesce(v_invite.department_id, '00000000-0000-0000-0000-000000000000'::uuid)
        and coalesce(m.ward_id,       '00000000-0000-0000-0000-000000000000'::uuid)
            = coalesce(v_invite.ward_id,       '00000000-0000-0000-0000-000000000000'::uuid)
    ) then
      insert into public.memberships (
        tenant_id, user_id, role_key, facility_id, department_id, ward_id,
        status, granted_by
      )
      values (
        v_invite.tenant_id, new.id, v_invite.role_key, v_invite.facility_id,
        v_invite.department_id, v_invite.ward_id, 'active', v_invite.invited_by
      );
    end if;

    update public.user_invites
       set status = 'accepted',
           updated_at = now()
     where id = v_invite.id;

    insert into public.audit_events (
      tenant_id, actor_id, action, resource_type, resource_id,
      origin, outcome, risk_tier, metadata
    )
    values (
      v_invite.tenant_id, new.id, 'user.provisioned', 'user_invite', v_invite.id,
      'backend', 'succeeded', 'elevated',
      jsonb_build_object(
        'role_key', v_invite.role_key,
        'facility_id', v_invite.facility_id,
        'department_id', v_invite.department_id,
        'ward_id', v_invite.ward_id
      )
    );
  end loop;

  return new;
end;
$$;

comment on function nodex.tg_provision_invited_user() is
  'AFTER INSERT ON auth.users: provisions app_users and the invited membership for every pending invite matching the signup email. Without an invite nothing is granted.';

create trigger on_auth_user_created_provision
  after insert on auth.users
  for each row execute function nodex.tg_provision_invited_user();

-- The signup path inserts into auth.users as supabase_auth_admin; the trigger
-- function must be executable by that role. Never by anon or authenticated:
-- clients do not create users.
grant execute on function nodex.tg_provision_invited_user() to supabase_auth_admin;
revoke execute on function nodex.tg_provision_invited_user() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------------

alter table public.user_invites enable row level security;
alter table public.user_invites force row level security;

create policy user_invites_admin on public.user_invites
  for all to authenticated
  using (nodex.has_permission(tenant_id, 'user.administer'))
  with check (nodex.has_permission(tenant_id, 'user.administer'));
