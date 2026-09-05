-- NODEX Phase 1: append-only audit envelope and immutable clinical event log.
--
-- Specification: safety-critical clinical actions retain immutable event history.
-- Application-facing audit records are append-only; administrative tools may
-- query and export history but must not silently rewrite it.

create table public.audit_events (
  id                       uuid primary key default gen_random_uuid(),
  tenant_id                uuid not null references public.tenants (id) on delete restrict,
  facility_id              uuid references public.facilities (id) on delete set null,
  actor_id                 uuid references public.app_users (id) on delete set null,
  actor_role_key           text,
  on_behalf_of_id          uuid references public.app_users (id) on delete set null,
  device_id                uuid references public.devices (id) on delete set null,
  session_reference        text,
  occurred_at              timestamptz not null default now(),
  recorded_at              timestamptz not null default now(),
  action                   text not null check (length(btrim(action)) > 0),
  resource_type            text not null check (length(btrim(resource_type)) > 0),
  resource_id              uuid,
  patient_id               uuid,
  encounter_id             uuid,
  correlation_id           uuid,
  mutation_id              uuid,
  origin                   text not null default 'online'
                           check (origin in ('online', 'offline', 'backend', 'system')),
  outcome                  text not null default 'succeeded'
                           check (outcome in ('succeeded', 'rejected', 'failed', 'partial')),
  risk_tier                text not null default 'standard'
                           check (risk_tier in ('standard', 'elevated', 'high_risk')),
  before_state             jsonb,
  after_state              jsonb,
  event_reference          uuid,
  reason                   text,
  ai_involved              boolean not null default false,
  ai_request_id            uuid,
  ai_engine_key            text,
  ai_model_key             text,
  ai_model_revision        text,
  ai_provider              text,
  rule_engine_revision     text,
  human_reviewer_id        uuid references public.app_users (id) on delete set null,
  review_decision          text
                           check (review_decision is null
                                  or review_decision in ('accepted', 'edited', 'rejected', 'not_applicable')),
  safety_decision_id       uuid,
  metadata                 jsonb not null default '{}'::jsonb
);

comment on table public.audit_events is
  'Append-only high-risk audit envelope. Every clinical mutation is traceable from device action through sync to authoritative persistence.';
comment on column public.audit_events.origin is
  'Whether the action was initiated while the device was online, offline, or by a backend/system process.';
comment on column public.audit_events.mutation_id is
  'Client-generated idempotency key linking this audit row to the originating PowerSync mutation.';

create index audit_events_tenant_time_idx    on public.audit_events (tenant_id, occurred_at desc);
create index audit_events_resource_idx       on public.audit_events (tenant_id, resource_type, resource_id);
create index audit_events_actor_idx          on public.audit_events (actor_id, occurred_at desc);
create index audit_events_patient_idx        on public.audit_events (patient_id, occurred_at desc)
  where patient_id is not null;
create index audit_events_correlation_idx    on public.audit_events (correlation_id)
  where correlation_id is not null;
create index audit_events_mutation_idx       on public.audit_events (mutation_id)
  where mutation_id is not null;
create index audit_events_ai_idx             on public.audit_events (tenant_id, occurred_at desc)
  where ai_involved;
create index audit_events_high_risk_idx      on public.audit_events (tenant_id, occurred_at desc)
  where risk_tier = 'high_risk';

create trigger audit_events_append_only_update
  before update on public.audit_events
  for each row execute function nodex.tg_block_mutation();

create trigger audit_events_append_only_delete
  before delete on public.audit_events
  for each row execute function nodex.tg_block_mutation();

-- Clinical event log: immutable domain events behind the CRUD projections.
create table public.clinical_events (
  id                 uuid primary key default gen_random_uuid(),
  tenant_id          uuid not null references public.tenants (id) on delete restrict,
  facility_id        uuid references public.facilities (id) on delete set null,
  aggregate_type     text not null check (length(btrim(aggregate_type)) > 0),
  aggregate_id       uuid not null,
  sequence_no        bigint not null check (sequence_no > 0),
  event_type         text not null check (length(btrim(event_type)) > 0),
  event_revision     integer not null default 1 check (event_revision > 0),
  patient_id         uuid,
  encounter_id       uuid,
  actor_id           uuid references public.app_users (id) on delete set null,
  device_id          uuid references public.devices (id) on delete set null,
  occurred_at        timestamptz not null default now(),
  recorded_at        timestamptz not null default now(),
  origin             text not null default 'online'
                     check (origin in ('online', 'offline', 'backend', 'system')),
  mutation_id        uuid,
  correlation_id     uuid,
  payload            jsonb not null,
  audit_event_id     uuid references public.audit_events (id) on delete restrict,
  unique (tenant_id, aggregate_type, aggregate_id, sequence_no)
);

comment on table public.clinical_events is
  'Immutable clinical event stream for safety-critical aggregates (diagnosis, prescription, dispensing, allergy, lab verification, consent, discharge).';
comment on column public.clinical_events.sequence_no is
  'Monotonic per-aggregate sequence. Gaps are not permitted; concurrent writers reconcile through the backend mutation path.';

create index clinical_events_aggregate_idx on public.clinical_events (tenant_id, aggregate_type, aggregate_id, sequence_no);
create index clinical_events_patient_idx   on public.clinical_events (patient_id, occurred_at desc)
  where patient_id is not null;
create index clinical_events_type_idx      on public.clinical_events (tenant_id, event_type, occurred_at desc);

create trigger clinical_events_append_only_update
  before update on public.clinical_events
  for each row execute function nodex.tg_block_mutation();

create trigger clinical_events_append_only_delete
  before delete on public.clinical_events
  for each row execute function nodex.tg_block_mutation();
