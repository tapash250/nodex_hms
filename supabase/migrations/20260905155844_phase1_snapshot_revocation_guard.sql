-- Refine append-only enforcement on authorization_snapshots.
--
-- A blanket UPDATE block also blocked legitimate revocation, which is the
-- primary control for lost/stolen devices and role changes. Replace it with a
-- guard that permits exactly one transition: setting revoked_at / revoked_reason
-- once, from the authorized backend path only. Every other column stays immutable.

drop trigger if exists authorization_snapshots_append_only_update
  on public.authorization_snapshots;

create or replace function nodex.tg_snapshot_revocation_only()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if not nodex.is_service_role() then
    raise exception
      'NODEX: authorization snapshots may only be revoked through the authorized backend path'
      using errcode = '42501';
  end if;

  if old.revoked_at is not null then
    raise exception 'NODEX: authorization snapshot % is already revoked', old.id
      using errcode = '22000';
  end if;

  if new.revoked_at is null then
    raise exception 'NODEX: the only permitted update is setting revoked_at'
      using errcode = '22000';
  end if;

  -- Immutable projection of the issued snapshot.
  new.id                  := old.id;
  new.tenant_id           := old.tenant_id;
  new.user_id             := old.user_id;
  new.device_id           := old.device_id;
  new.snapshot_revision   := old.snapshot_revision;
  new.roles               := old.roles;
  new.permissions         := old.permissions;
  new.facility_ids        := old.facility_ids;
  new.department_ids      := old.department_ids;
  new.ward_ids            := old.ward_ids;
  new.offline_permissions := old.offline_permissions;
  new.payload_digest      := old.payload_digest;
  new.issued_at           := old.issued_at;
  new.expires_at          := old.expires_at;
  new.issued_session_id   := old.issued_session_id;
  new.created_at          := old.created_at;

  return new;
end;
$$;

comment on function nodex.tg_snapshot_revocation_only() is
  'BEFORE UPDATE guard on authorization_snapshots: permits one-way revocation from the backend path and freezes all issued fields.';

create trigger authorization_snapshots_revocation_only
  before update on public.authorization_snapshots
  for each row execute function nodex.tg_snapshot_revocation_only();
