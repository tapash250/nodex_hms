-- NODEX Phase 1: AI governance tables.
--
-- The registry is configuration, not business logic. Provider/model identifiers
-- are deployment configuration and must never be hard-coded into Flutter
-- clinical workflow code. An available model is not an approved model.

create table public.ai_model_registry (
  id                       uuid primary key default gen_random_uuid(),
  model_key                text not null unique
                           check (model_key ~ '^[a-z][a-z0-9_]{2,63}$'),
  provider                 text not null,
  provider_model_id        text not null,
  display_name             text not null,
  modality                 text[] not null default '{}',
  clinical_risk_tier       text not null
                           check (clinical_risk_tier in ('low', 'standard', 'elevated', 'high')),
  privacy_class            text not null
                           check (privacy_class in ('public', 'de_identified', 'phi_permitted', 'on_device_only')),
  context_window           integer check (context_window is null or context_window > 0),
  max_output_tokens        integer check (max_output_tokens is null or max_output_tokens > 0),
  supports_structured_json boolean not null default false,
  supports_tool_calling    boolean not null default false,
  supports_vision          boolean not null default false,
  latency_target_ms        integer check (latency_target_ms is null or latency_target_ms > 0),
  memory_requirement_mb    integer check (memory_requirement_mb is null or memory_requirement_mb > 0),
  model_revision           text not null,
  evaluation_set_revision  text,
  evaluation_status        text not null default 'not_evaluated'
                           check (evaluation_status in ('not_evaluated', 'in_progress', 'passed', 'failed')),
  lifecycle_status         text not null default 'discovered'
                           check (lifecycle_status in ('discovered', 'evaluating', 'approved',
                                                       'active', 'deprecated', 'retired')),
  enabled                  boolean not null default false,
  priority                 integer not null default 100,
  approved_by              uuid references public.app_users (id) on delete set null,
  approved_at              timestamptz,
  intended_use             text,
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now(),
  -- Governance invariant: a model cannot be active without a passed evaluation
  -- and recorded clinical governance approval.
  constraint ai_model_registry_activation_ck check (
    lifecycle_status not in ('approved', 'active')
    or (evaluation_status = 'passed'
        and evaluation_set_revision is not null
        and approved_by is not null
        and approved_at is not null)
  ),
  constraint ai_model_registry_enabled_ck check (
    not enabled or lifecycle_status = 'active'
  )
);

comment on table public.ai_model_registry is
  'Versioned, capability-aware, lifecycle-aware model registry. Provider catalog discovery may not transition a model straight to ACTIVE.';
comment on constraint ai_model_registry_activation_ck on public.ai_model_registry is
  'Enforces the model lifecycle gate: evaluation evidence and governance approval must exist before APPROVED/ACTIVE.';

create index ai_model_registry_lifecycle_idx on public.ai_model_registry (lifecycle_status, priority);
create index ai_model_registry_provider_idx  on public.ai_model_registry (provider);

create table public.ai_routing_policies (
  id                          uuid primary key default gen_random_uuid(),
  engine_key                  text not null
                              check (engine_key ~ '^ai_[a-z][a-z0-9_]{2,63}$'),
  environment                 text not null default 'production'
                              check (environment in ('development', 'staging', 'production')),
  primary_model_key           text not null references public.ai_model_registry (model_key) on delete restrict,
  secondary_model_key         text references public.ai_model_registry (model_key) on delete restrict,
  tertiary_model_key          text references public.ai_model_registry (model_key) on delete restrict,
  offline_fallback_model_key  text references public.ai_model_registry (model_key) on delete restrict,
  timeout_ms                  integer not null default 12000 check (timeout_ms between 500 and 300000),
  max_attempts                integer not null default 1 check (max_attempts between 1 and 10),
  circuit_breaker_threshold   integer not null default 3 check (circuit_breaker_threshold between 1 and 100),
  circuit_breaker_seconds     integer not null default 300 check (circuit_breaker_seconds between 1 and 86400),
  require_structured_output   boolean not null default true,
  require_human_review        boolean not null default true,
  minimum_risk_capability     text not null default 'standard'
                              check (minimum_risk_capability in ('low', 'standard', 'elevated', 'high')),
  allow_manual_fallback       boolean not null default true,
  policy_revision             text not null,
  enabled                     boolean not null default true,
  updated_at                  timestamptz not null default now(),
  created_at                  timestamptz not null default now(),
  unique (engine_key, environment)
);

comment on table public.ai_routing_policies is
  'Per-engine deterministic candidate chain. There is no single universal fallback chain shared by all engines.';
comment on column public.ai_routing_policies.require_human_review is
  'Failover may never silently clear this flag; the safety boundary is independent of execution source.';

create table public.ai_deployment_profiles (
  id                 uuid primary key default gen_random_uuid(),
  name               text not null,
  environment        text not null
                     check (environment in ('development', 'staging', 'production')),
  profile_revision   text not null,
  providers          jsonb not null default '{}'::jsonb,
  is_active          boolean not null default false,
  activated_at       timestamptz,
  activated_by       uuid references public.app_users (id) on delete set null,
  rollback_target_id uuid references public.ai_deployment_profiles (id) on delete set null,
  notes              text,
  created_at         timestamptz not null default now(),
  unique (environment, profile_revision)
);

comment on table public.ai_deployment_profiles is
  'Version-controlled environment profile. Routing must be reproducible from profile revision, policy revision and runtime health state.';

create unique index ai_deployment_profiles_one_active_per_env
  on public.ai_deployment_profiles (environment)
  where is_active;

create trigger ai_model_registry_set_updated_at
  before update on public.ai_model_registry
  for each row execute function nodex.tg_set_updated_at();

create trigger ai_routing_policies_set_updated_at
  before update on public.ai_routing_policies
  for each row execute function nodex.tg_set_updated_at();
