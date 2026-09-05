-- NODEX Phase 1: AI execution audit, safety decisions and human review records.
--
-- Specification: AI output cannot silently become a finalized clinical decision.
-- Every execution records engine, policy revision, profile revision, model,
-- provider, attempt number, failure class, circuit state and final outcome.

create table public.ai_requests (
  id                          uuid primary key default gen_random_uuid(),
  tenant_id                   uuid not null references public.tenants (id) on delete restrict,
  facility_id                 uuid references public.facilities (id) on delete set null,
  requested_by                uuid references public.app_users (id) on delete set null,
  device_id                   uuid references public.devices (id) on delete set null,
  engine_key                  text not null,
  routing_policy_revision     text not null,
  deployment_profile_revision text not null,
  clinical_risk_level         text not null
                              check (clinical_risk_level in ('low', 'standard', 'elevated', 'high')),
  privacy_class               text not null
                              check (privacy_class in ('public', 'de_identified', 'phi_permitted', 'on_device_only')),
  modality                    text not null
                              check (modality in ('text', 'audio', 'image', 'multimodal')),
  patient_id                  uuid,
  encounter_id                uuid,
  correlation_id              uuid,
  requires_structured_output  boolean not null default true,
  timeout_ms                  integer not null check (timeout_ms > 0),
  context_digest              text not null,
  requested_at                timestamptz not null default now(),
  completed_at                timestamptz,
  final_outcome               text
                              check (final_outcome is null or final_outcome in (
                                'completed', 'rejected', 'abstained', 'failed', 'manual_workflow')),
  total_attempts              integer not null default 0 check (total_attempts >= 0),
  origin                      text not null default 'online'
                              check (origin in ('online', 'offline'))
);

comment on table public.ai_requests is
  'One row per orchestrated AI task. context_digest records the sanitized context without persisting PHI in the AI audit trail.';
comment on column public.ai_requests.final_outcome is
  'manual_workflow means the system refused silent degradation and handed the task to a human process.';

create index ai_requests_tenant_time_idx on public.ai_requests (tenant_id, requested_at desc);
create index ai_requests_engine_idx      on public.ai_requests (tenant_id, engine_key, requested_at desc);
create index ai_requests_patient_idx     on public.ai_requests (patient_id, requested_at desc)
  where patient_id is not null;

create table public.ai_responses (
  id                      uuid primary key default gen_random_uuid(),
  request_id              uuid not null references public.ai_requests (id) on delete cascade,
  attempt_number          integer not null check (attempt_number > 0),
  model_key               text not null,
  model_revision          text not null,
  provider                text not null,
  provider_revision       text,
  evaluation_set_revision text,
  circuit_state           text not null default 'healthy'
                          check (circuit_state in ('healthy', 'degraded', 'open', 'half_open')),
  started_at              timestamptz not null default now(),
  finished_at             timestamptz,
  latency_ms              integer check (latency_ms is null or latency_ms >= 0),
  input_tokens            integer check (input_tokens is null or input_tokens >= 0),
  output_tokens           integer check (output_tokens is null or output_tokens >= 0),
  status                  text not null
                          check (status in ('succeeded', 'failed', 'blocked', 'abstained')),
  failure_class           text
                          check (failure_class is null or failure_class in (
                            'connectivity', 'timeout', 'rate_limit', 'provider_server',
                            'authorization', 'invalid_input', 'schema_validation',
                            'safety_blocked', 'unsupported_modality', 'model_not_approved',
                            'unknown')),
  failure_detail          text,
  schema_valid            boolean,
  confidence              numeric(4, 3) check (confidence is null or (confidence >= 0 and confidence <= 1)),
  response_digest         text,
  structured_output       jsonb,
  unique (request_id, attempt_number)
);

comment on table public.ai_responses is
  'Per-attempt provider execution record. The failover sequence is reconstructable from attempt_number and failure_class.';

create index ai_responses_request_idx on public.ai_responses (request_id, attempt_number);
create index ai_responses_model_idx   on public.ai_responses (model_key, started_at desc);

create table public.ai_safety_decisions (
  id                  uuid primary key default gen_random_uuid(),
  request_id          uuid not null references public.ai_requests (id) on delete cascade,
  response_id         uuid references public.ai_responses (id) on delete set null,
  rule_engine_revision text not null,
  decision            text not null
                      check (decision in ('allow', 'allow_with_warnings', 'require_review', 'block')),
  severity            text not null default 'info'
                      check (severity in ('info', 'low', 'moderate', 'high', 'critical')),
  triggered_rules     text[] not null default '{}',
  uncertain_fields    text[] not null default '{}',
  requires_human_confirmation boolean not null default true,
  rationale           text,
  decided_at          timestamptz not null default now()
);

comment on table public.ai_safety_decisions is
  'Deterministic safety engine verdict. The safety engine remains authoritative after any provider failover.';

create index ai_safety_decisions_request_idx on public.ai_safety_decisions (request_id);

create table public.ai_reviews (
  id                  uuid primary key default gen_random_uuid(),
  tenant_id           uuid not null references public.tenants (id) on delete restrict,
  request_id          uuid not null references public.ai_requests (id) on delete cascade,
  response_id         uuid references public.ai_responses (id) on delete set null,
  safety_decision_id  uuid references public.ai_safety_decisions (id) on delete set null,
  reviewer_id         uuid not null references public.app_users (id) on delete restrict,
  reviewer_role_key   text,
  decision            text not null
                      check (decision in ('accepted', 'accepted_with_edits', 'rejected', 'deferred')),
  edited_fields       text[] not null default '{}',
  correction_count    integer not null default 0 check (correction_count >= 0),
  review_duration_ms  integer check (review_duration_ms is null or review_duration_ms >= 0),
  notes               text,
  reviewed_at         timestamptz not null default now(),
  resulting_audit_event_id uuid references public.audit_events (id) on delete set null
);

comment on table public.ai_reviews is
  'Human-in-the-loop record. Links a clinically material AI output to the clinician who accepted, edited or rejected it.';

create index ai_reviews_tenant_idx   on public.ai_reviews (tenant_id, reviewed_at desc);
create index ai_reviews_request_idx  on public.ai_reviews (request_id);
create index ai_reviews_reviewer_idx on public.ai_reviews (reviewer_id, reviewed_at desc);

-- AI execution history is evidence: append-only for application roles.
create trigger ai_requests_append_only_delete
  before delete on public.ai_requests
  for each row execute function nodex.tg_block_mutation();

create trigger ai_responses_append_only_update
  before update on public.ai_responses
  for each row execute function nodex.tg_block_mutation();

create trigger ai_safety_decisions_append_only_update
  before update on public.ai_safety_decisions
  for each row execute function nodex.tg_block_mutation();

create trigger ai_reviews_append_only_update
  before update on public.ai_reviews
  for each row execute function nodex.tg_block_mutation();
