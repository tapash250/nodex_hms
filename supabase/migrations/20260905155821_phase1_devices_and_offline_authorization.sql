-- NODEX Phase 1: device registry and device-bound offline authorization snapshots.
--
-- Specification: offline access is based on a last-known, device-bound
-- authorization snapshot with a defined validity window containing only the
-- minimum information required to continue approved offline workflows.

create table public.devices (
  id                    uuid primary key default gen_random_uuid(),
  tenant_id             uuid not null references public.tenants (id) on delete restrict,
  device_fingerprint    text not null,
  display_name          text,
  platform              text not null default 'android'
                        check (platform in ('android', 'ios', 'web', 'other')),
  form_factor           text not null default 'phone'
                        check (form_factor in ('phone', 'tablet_compact', 'tablet_large', 'other')),
  os_version            text,
  app_version           text,
  enrolled_by           uuid references public.app_users (id) on delete set null,
  assigned_user_id      uuid references public.app_users (id) on delete set null,
  assigned_facility_id  uuid references public.facilities (id) on delete set null,
  status                text not null default 'pending'
                        check (status in ('pending', 'active', 'suspended', 'revoked', 'wiped')),
  offline_window_minutes integer not null default 720
                        check (offline_window_minutes between 0 and 20160),
  last_seen_at          timestamptz,
  last_sync_at          timestamptz,
  revoked_at            timestamptz,
  revoked_reason        text,
  wipe_requested_at     timestamptz,
  wipe_confirmed_at     timestamptz,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  unique (tenant_id, device_fingerprint)
);

comment on table public.devices is
  'Registered client device. Revocation here is the enforcement point for lost/stolen device procedures.';
comment on column public.devices.offline_window_minutes is
  'Maximum validity of an offline authorization snapshot issued to this device.';
comment on column public.devices.wipe_requested_at is
  'Set by an administrator to request selective local database deletion on next contact.';

create index devices_tenant_idx        on public.devices (tenant_id);
create index devices_assigned_user_idx on public.devices (assigned_user_id);
create index devices_status_idx        on public.devices (tenant_id, status);

-- Snapshot issued to a device at online authorization refresh. Append-only:
-- a superseded snapshot is never edited, only marked via a newer row.
create table public.authorization_snapshots (
  id                  uuid primary key default gen_random_uuid(),
  tenant_id           uuid not null references public.tenants (id) on delete restrict,
  user_id             uuid not null references public.app_users (id) on delete restrict,
  device_id           uuid not null references public.devices (id) on delete cascade,
  snapshot_revision   integer not null default 1 check (snapshot_revision > 0),
  roles               text[] not null default '{}',
  permissions         text[] not null default '{}',
  facility_ids        uuid[] not null default '{}',
  department_ids      uuid[] not null default '{}',
  ward_ids            uuid[] not null default '{}',
  offline_permissions text[] not null default '{}',
  payload_digest      text not null,
  issued_at           timestamptz not null default now(),
  expires_at          timestamptz not null,
  issued_session_id   text,
  revoked_at          timestamptz,
  revoked_reason      text,
  created_at          timestamptz not null default now(),
  constraint authorization_snapshots_window_ck check (expires_at > issued_at)
);

comment on table public.authorization_snapshots is
  'Device-bound, time-bounded authorization snapshot. Does not override RLS; it only bounds what the client may attempt offline.';
comment on column public.authorization_snapshots.offline_permissions is
  'Subset of permissions where requires_online = false. Privileged actions are excluded by construction.';
comment on column public.authorization_snapshots.payload_digest is
  'Digest of the issued payload so the client can detect local tampering of its cached snapshot.';

create index authorization_snapshots_device_idx
  on public.authorization_snapshots (device_id, issued_at desc);
create index authorization_snapshots_user_idx
  on public.authorization_snapshots (user_id, tenant_id, issued_at desc);
create index authorization_snapshots_active_idx
  on public.authorization_snapshots (device_id, expires_at)
  where revoked_at is null;

create trigger devices_set_updated_at
  before update on public.devices
  for each row execute function nodex.tg_set_updated_at();

-- Snapshots are historical evidence: no UPDATE, no DELETE from application roles.
create trigger authorization_snapshots_append_only_update
  before update on public.authorization_snapshots
  for each row execute function nodex.tg_block_mutation();

create trigger authorization_snapshots_append_only_delete
  before delete on public.authorization_snapshots
  for each row execute function nodex.tg_block_mutation();
