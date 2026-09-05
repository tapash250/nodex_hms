-- NODEX Phase 1: synchronization bookkeeping.
--
-- The PowerSync upload queue lives on the device. These tables are the
-- server-side record of what the backend accepted, so that reconnection
-- produces exactly-once business effect for idempotent mutations and failed
-- synchronization is visible rather than silently discarded.

create table public.mutations (
  id                 uuid primary key,
  tenant_id          uuid not null references public.tenants (id) on delete restrict,
  user_id            uuid not null references public.app_users (id) on delete restrict,
  device_id          uuid not null references public.devices (id) on delete restrict,
  operation          text not null check (length(btrim(operation)) > 0),
  resource_type      text not null check (length(btrim(resource_type)) > 0),
  resource_id        uuid,
  idempotency_key    text not null,
  client_created_at  timestamptz not null,
  received_at        timestamptz not null default now(),
  applied_at         timestamptz,
  status             text not null default 'received'
                     check (status in ('received', 'applied', 'rejected', 'conflicted', 'abandoned')),
  attempt_count      integer not null default 0 check (attempt_count >= 0),
  origin             text not null default 'offline'
                     check (origin in ('online', 'offline')),
  payload_digest     text not null,
  rejection_class    text
                     check (rejection_class is null or rejection_class in (
                       'validation', 'authorization', 'conflict', 'integrity',
                       'stale_authorization', 'unsupported', 'internal')),
  rejection_detail   text,
  correlation_id     uuid,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  unique (tenant_id, idempotency_key)
);

comment on table public.mutations is
  'Server-side ledger of client mutations. The idempotency key guarantees exactly-once business effect across retries.';
comment on column public.mutations.id is
  'Client-generated mutation id. Supplied by the device so retries after a lost response are recognised.';

create index mutations_device_status_idx on public.mutations (device_id, status, received_at desc);
create index mutations_tenant_status_idx on public.mutations (tenant_id, status, received_at desc);
create index mutations_pending_idx       on public.mutations (tenant_id, received_at)
  where status in ('received', 'conflicted');
create index mutations_resource_idx      on public.mutations (tenant_id, resource_type, resource_id);

create table public.mutation_attempts (
  id             uuid primary key default gen_random_uuid(),
  mutation_id    uuid not null references public.mutations (id) on delete cascade,
  attempt_number integer not null check (attempt_number > 0),
  attempted_at   timestamptz not null default now(),
  outcome        text not null
                 check (outcome in ('applied', 'rejected', 'conflicted', 'transient_failure')),
  failure_class  text,
  failure_detail text,
  duration_ms    integer check (duration_ms is null or duration_ms >= 0),
  unique (mutation_id, attempt_number)
);

comment on table public.mutation_attempts is
  'Per-attempt history for a mutation. Distinguishes transient failures from permanent rejections.';

create table public.conflict_records (
  id                uuid primary key default gen_random_uuid(),
  tenant_id         uuid not null references public.tenants (id) on delete restrict,
  mutation_id       uuid references public.mutations (id) on delete set null,
  resource_type     text not null,
  resource_id       uuid,
  entity_policy     text not null
                    check (entity_policy in (
                      'field_level_merge', 'versioned_revision', 'append_only',
                      'immutable_version', 'event_transaction', 'immutable_with_correction',
                      'transactional', 'server_authoritative')),
  detected_at       timestamptz not null default now(),
  resolved_at       timestamptz,
  resolution        text
                    check (resolution is null or resolution in (
                      'client_accepted', 'server_retained', 'merged',
                      'superseded', 'manual_review', 'rejected')),
  resolved_by       uuid references public.app_users (id) on delete set null,
  requires_review   boolean not null default false,
  client_state      jsonb,
  server_state      jsonb,
  merged_state      jsonb,
  notes             text,
  audit_event_id    uuid references public.audit_events (id) on delete set null,
  constraint conflict_records_resolution_ck check (
    (resolved_at is null and resolution is null)
    or (resolved_at is not null and resolution is not null)
  )
);

comment on table public.conflict_records is
  'Deterministic, auditable conflict resolution record. entity_policy names the per-entity strategy from the specification conflict matrix.';
comment on column public.conflict_records.entity_policy is
  'Per-entity conflict strategy. There is no global last-write-wins policy for clinical data.';

create index conflict_records_tenant_idx    on public.conflict_records (tenant_id, detected_at desc);
create index conflict_records_unresolved_idx on public.conflict_records (tenant_id, detected_at)
  where resolved_at is null;
create index conflict_records_resource_idx  on public.conflict_records (tenant_id, resource_type, resource_id);

create table public.sync_cursors (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null references public.tenants (id) on delete restrict,
  device_id       uuid not null references public.devices (id) on delete cascade,
  stream_name     text not null,
  last_synced_at  timestamptz,
  checkpoint      text,
  queue_depth     integer not null default 0 check (queue_depth >= 0),
  oldest_pending_at timestamptz,
  health          text not null default 'healthy'
                  check (health in ('healthy', 'degraded', 'stalled', 'error')),
  last_error      text,
  updated_at      timestamptz not null default now(),
  unique (device_id, stream_name)
);

comment on table public.sync_cursors is
  'Per-device, per-stream sync health. Backs the sync diagnostics screen (module 53) and queue-depth observability.';

create trigger mutations_set_updated_at
  before update on public.mutations
  for each row execute function nodex.tg_set_updated_at();

create trigger sync_cursors_set_updated_at
  before update on public.sync_cursors
  for each row execute function nodex.tg_set_updated_at();

create trigger mutation_attempts_append_only_update
  before update on public.mutation_attempts
  for each row execute function nodex.tg_block_mutation();
