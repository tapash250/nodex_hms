-- NODEX Phase 4, Module 38: Reports & Operational Analytics Warehouse.
--
-- Specification scope: "Hospital-wide analytics: morbidity reports, department
-- productivity, pharmacy burn rate, and financial balance sheets." with the
-- performance clause "offloaded from operational tables to read-replicas with
-- materialized rolling rollups."
--
-- The warehouse stores conclusions, not facts. An encounter, a dispense and an
-- invoice live in the modules that own them; what lives here is what those
-- modules add up to over a period, and the record of who asked. That is why
-- nothing here is a foreign key away from a clinical table: a rollup must stay
-- readable when the operational rows behind it have been corrected, because the
-- number the board was shown is itself a fact worth keeping.
--
-- Four tables, one per clause of the scope:
--
--   * `analytics_report_definitions` is the catalogue: what the hospital can
--     report, over which grain, drawn from which operational source. It is
--     configuration, so it is retired rather than deleted, and its query contract
--     freezes when it is published.
--   * `analytics_rollups` is the materialized rolling rollup: one row per
--     definition, grain and period, carrying the four shapes the named reports
--     need -- a row count, the two terms of a ratio, and the two sides of a
--     balance sheet. Re-materialising a period supersedes the previous row rather
--     than overwriting it, so a figure that was published can still be explained.
--   * `analytics_report_runs` is one execution of a definition over a window: who
--     asked, when it started and finished, how many rows came back, and -- the
--     clause the specification names -- whether it was answered from the rolling
--     rollup or sent through to the read replica.
--   * `analytics_exports` is the append-only record of what left the building: the
--     artefact, its format, where it went and who took it. A balance sheet is the
--     most sensitive thing this module can produce, and the answer to "who has
--     one" has to be a query rather than a memory.
--
-- Materialising a rollup and exporting a run require a network, because both read
-- the read replica. A device's local projection is a copy of the operational
-- tables, not a replica, and a rollup computed from a stale copy would be a
-- number no other device agrees with. Reading and defining stay offline.
--
-- Money is integer minor units throughout, as everywhere else in NODEX: a balance
-- sheet that has rounded twice is a balance sheet that does not balance.

create table public.analytics_report_definitions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  -- Null means the report is hospital-wide rather than one facility's.
  facility_id uuid references public.facilities(id) on delete restrict,
  code text not null check (length(btrim(code)) > 0),
  display_name text not null check (length(btrim(display_name)) > 0),
  description text check (description is null or length(btrim(description)) > 0),
  category text not null
    check (category in ('morbidity','productivity','pharmacy','financial',
                        'operational')),
  -- The operational module the rollup draws on. Named rather than free text so
  -- the warehouse can say where a number came from.
  primary_source text not null
    check (primary_source in ('encounters','pharmacy','billing','workforce',
                              'inventory','laboratory','mixed')),
  grain text not null check (grain in ('day','week','month','quarter','year')),
  retention_days integer not null default 3650 check (retention_days between 30 and 36500),
  status text not null default 'draft'
    check (status in ('draft','published','retired')),
  published_at timestamptz,
  published_by uuid references public.app_users(id) on delete restrict,
  retired_at timestamptz,
  created_by uuid not null references public.app_users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- A report code is how the rest of the hospital names the figure, so two
  -- definitions may not share one.
  unique (tenant_id, code),
  constraint analytics_definition_published_ck check (
    status = 'draft'
    or (published_at is not null and published_by is not null)
  ),
  constraint analytics_definition_retired_ck check (
    status <> 'retired' or retired_at is not null
  )
);
create index analytics_definition_category_idx
  on public.analytics_report_definitions(tenant_id, category, status);

create table public.analytics_rollups (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  definition_id uuid not null
    references public.analytics_report_definitions(id) on delete restrict,
  facility_id uuid references public.facilities(id) on delete restrict,
  grain text not null check (grain in ('day','week','month','quarter','year')),
  period_start date not null,
  period_end date not null,
  -- How many operational rows the period added up to, so a figure can be weighed
  -- as well as read.
  row_count integer not null default 0 check (row_count >= 0),
  -- The two terms of a ratio: a morbidity rate, a productivity index, a burn rate.
  numerator integer not null default 0,
  denominator integer not null default 0 check (denominator >= 0),
  -- The two sides of a balance sheet, in minor units.
  income_minor integer not null default 0,
  expenditure_minor integer not null default 0,
  materialised_at timestamptz not null default now(),
  materialised_by uuid references public.app_users(id) on delete restrict,
  status text not null default 'materialised'
    check (status in ('materialised','superseded','voided')),
  superseded_at timestamptz,
  supersede_note text check (supersede_note is null or length(btrim(supersede_note)) > 0),
  voided_at timestamptz,
  void_reason text check (void_reason is null or length(btrim(void_reason)) > 0),
  created_by uuid not null references public.app_users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- One rollup per definition, grain and period. A second materialisation
  -- supersedes the first rather than sitting beside it, because two rows for one
  -- period are two answers to one question.
  unique (tenant_id, definition_id, grain, period_start),
  constraint analytics_rollup_period_ck check (period_end >= period_start),
  constraint analytics_rollup_superseded_ck check (
    status <> 'superseded' or superseded_at is not null
  ),
  constraint analytics_rollup_voided_ck check (
    status <> 'voided'
    or (voided_at is not null and void_reason is not null
        and length(btrim(void_reason)) > 0)
  )
);
create index analytics_rollup_period_idx
  on public.analytics_rollups(tenant_id, definition_id, grain, period_start desc);
create index analytics_rollup_status_idx
  on public.analytics_rollups(tenant_id, status, materialised_at desc);

create table public.analytics_report_runs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  definition_id uuid not null
    references public.analytics_report_definitions(id) on delete restrict,
  facility_id uuid references public.facilities(id) on delete restrict,
  run_number text not null check (length(btrim(run_number)) > 0),
  grain text not null check (grain in ('day','week','month','quarter','year')),
  period_start date not null,
  period_end date not null,
  filter_note text check (filter_note is null or length(btrim(filter_note)) > 0),
  status text not null default 'queued'
    check (status in ('queued','running','succeeded','failed','cancelled')),
  -- Which side of the warehouse answered: the rolling rollup, or a query sent
  -- through to the read replica. The specification's performance clause, made
  -- visible on the record rather than assumed.
  served_from text check (served_from in ('rollup','replica')),
  row_count integer check (row_count is null or row_count >= 0),
  requested_by uuid not null references public.app_users(id) on delete restrict,
  started_at timestamptz,
  finished_at timestamptz,
  failure_reason text check (failure_reason is null or length(btrim(failure_reason)) > 0),
  cancelled_at timestamptz,
  cancel_reason text check (cancel_reason is null or length(btrim(cancel_reason)) > 0),
  created_by uuid not null references public.app_users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, run_number),
  constraint analytics_run_period_ck check (period_end >= period_start),
  constraint analytics_run_running_ck check (
    status <> 'running' or started_at is not null
  ),
  constraint analytics_run_succeeded_ck check (
    status <> 'succeeded'
    or (started_at is not null and finished_at is not null
        and served_from is not null and row_count is not null)
  ),
  constraint analytics_run_failed_ck check (
    status <> 'failed'
    or (finished_at is not null and failure_reason is not null
        and length(btrim(failure_reason)) > 0)
  ),
  constraint analytics_run_cancelled_ck check (
    status <> 'cancelled'
    or (cancelled_at is not null and cancel_reason is not null
        and length(btrim(cancel_reason)) > 0)
  )
);
create index analytics_run_status_idx
  on public.analytics_report_runs(tenant_id, status, created_at desc);
create index analytics_run_definition_idx
  on public.analytics_report_runs(tenant_id, definition_id, period_start desc);

create table public.analytics_exports (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  run_id uuid not null references public.analytics_report_runs(id) on delete restrict,
  artifact_label text not null check (length(btrim(artifact_label)) > 0),
  format text not null check (format in ('csv','pdf','xlsx','json')),
  destination text not null
    check (destination in ('download','email','secure_link','print')),
  byte_size integer check (byte_size is null or byte_size >= 0),
  checksum text check (checksum is null or length(btrim(checksum)) > 0),
  note text check (note is null or length(btrim(note)) > 0),
  exported_at timestamptz not null default now(),
  exported_by uuid not null references public.app_users(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (run_id, artifact_label)
);
create index analytics_export_run_idx
  on public.analytics_exports(tenant_id, run_id, exported_at desc);

comment on table public.analytics_rollups is
  'Materialized rolling rollups. One row per definition, grain and period; a re-materialisation supersedes rather than overwrites, so a published figure stays explainable.';

create trigger analytics_report_definitions_set_updated_at
  before update on public.analytics_report_definitions
  for each row execute function nodex.tg_set_updated_at();
create trigger analytics_rollups_set_updated_at
  before update on public.analytics_rollups
  for each row execute function nodex.tg_set_updated_at();
create trigger analytics_report_runs_set_updated_at
  before update on public.analytics_report_runs
  for each row execute function nodex.tg_set_updated_at();

-- Nothing here is deleted: a definition is retired, a rollup is superseded or
-- voided, a run is cancelled, and the export log only takes appends.
create trigger analytics_report_definitions_retain
  before delete on public.analytics_report_definitions
  for each row execute function nodex.tg_block_mutation();
create trigger analytics_rollups_retain
  before delete on public.analytics_rollups
  for each row execute function nodex.tg_block_mutation();
create trigger analytics_report_runs_retain
  before delete on public.analytics_report_runs
  for each row execute function nodex.tg_block_mutation();
create trigger analytics_exports_append_only
  before update or delete on public.analytics_exports
  for each row execute function nodex.tg_block_mutation();

-- The query contract of a published definition is what the rollups behind it were
-- materialised against, so it freezes on publication.
create or replace function nodex.tg_analytics_definition_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status = 'retired' then
    raise exception using
      message = 'NODEX: a retired report definition is immutable',
      errcode = '42501';
  end if;
  if old.status <> 'draft' then
    if new.code is distinct from old.code
      or new.category is distinct from old.category
      or new.primary_source is distinct from old.primary_source
      or new.grain is distinct from old.grain
      or new.facility_id is distinct from old.facility_id then
      raise exception using
        message = 'NODEX: a published report definition is not re-scoped',
        errcode = '42501';
    end if;
  end if;
  if new.status = old.status then
    return new;
  end if;
  if (old.status = 'draft' and new.status = 'published')
    or (old.status = 'published' and new.status = 'retired') then
    return new;
  end if;
  raise exception using
    message = 'NODEX: a report definition may not skip a stage',
    errcode = '42501';
end;
$$;
create trigger analytics_report_definitions_guard
  before update on public.analytics_report_definitions
  for each row execute function nodex.tg_analytics_definition_guard();

-- A rollup is a figure the hospital may have been shown. It is superseded or
-- voided, never rewritten, and never un-superseded.
create or replace function nodex.tg_analytics_rollup_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status <> 'materialised' then
    raise exception using
      message = 'NODEX: a settled rollup is immutable',
      errcode = '42501';
  end if;
  if new.status = old.status and old.status = 'materialised' then
    return new;
  end if;
  if new.status in ('superseded','voided') then
    return new;
  end if;
  raise exception using
    message = 'NODEX: a rollup may not be reopened',
    errcode = '42501';
end;
$$;
create trigger analytics_rollups_guard
  before update on public.analytics_rollups
  for each row execute function nodex.tg_analytics_rollup_guard();

-- A run moves forward: queued, running, then one of the three ends.
create or replace function nodex.tg_analytics_run_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status in ('succeeded','failed','cancelled') then
    raise exception using
      message = 'NODEX: a settled report run is immutable',
      errcode = '42501';
  end if;
  if old.status <> 'queued'
    and (new.definition_id is distinct from old.definition_id
      or new.grain is distinct from old.grain
      or new.period_start is distinct from old.period_start
      or new.period_end is distinct from old.period_end
      or new.facility_id is distinct from old.facility_id
      or new.run_number is distinct from old.run_number) then
    raise exception using
      message = 'NODEX: a started run is not re-scoped',
      errcode = '42501';
  end if;
  if new.status = old.status then
    return new;
  end if;
  if (old.status = 'queued' and new.status in ('running','cancelled'))
    or (old.status = 'running'
        and new.status in ('succeeded','failed','cancelled')) then
    return new;
  end if;
  raise exception using
    message = 'NODEX: a report run may not skip a stage',
    errcode = '42501';
end;
$$;
create trigger analytics_report_runs_guard
  before update on public.analytics_report_runs
  for each row execute function nodex.tg_analytics_run_guard();

alter table public.analytics_report_definitions enable row level security;
alter table public.analytics_report_definitions force row level security;
alter table public.analytics_rollups enable row level security;
alter table public.analytics_rollups force row level security;
alter table public.analytics_report_runs enable row level security;
alter table public.analytics_report_runs force row level security;
alter table public.analytics_exports enable row level security;
alter table public.analytics_exports force row level security;

create policy analytics_definition_select_member on public.analytics_report_definitions for select to authenticated
  using (nodex.has_permission(tenant_id, 'analytics.read'));
create policy analytics_definition_insert_definer on public.analytics_report_definitions for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'analytics.define'));
create policy analytics_definition_update_definer on public.analytics_report_definitions for update to authenticated
  using (nodex.has_permission(tenant_id, 'analytics.define'))
  with check (nodex.has_permission(tenant_id, 'analytics.define'));

create policy analytics_rollup_select_member on public.analytics_rollups for select to authenticated
  using (nodex.has_permission(tenant_id, 'analytics.read'));
create policy analytics_rollup_insert_materialiser on public.analytics_rollups for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'analytics.materialise'));
create policy analytics_rollup_update_materialiser on public.analytics_rollups for update to authenticated
  using (nodex.has_permission(tenant_id, 'analytics.materialise'))
  with check (nodex.has_permission(tenant_id, 'analytics.materialise'));

create policy analytics_run_select_member on public.analytics_report_runs for select to authenticated
  using (nodex.has_permission(tenant_id, 'analytics.read'));
-- The person asking for a report may queue one without being able to materialise
-- a rollup: running is reading, and materialising is the warehouse's own work.
create policy analytics_run_insert_requester on public.analytics_report_runs for insert to authenticated
  with check (
    nodex.has_permission(tenant_id, 'analytics.read')
    or nodex.has_permission(tenant_id, 'analytics.materialise')
  );
create policy analytics_run_update_requester on public.analytics_report_runs for update to authenticated
  using (
    nodex.has_permission(tenant_id, 'analytics.read')
    or nodex.has_permission(tenant_id, 'analytics.materialise')
  )
  with check (
    nodex.has_permission(tenant_id, 'analytics.read')
    or nodex.has_permission(tenant_id, 'analytics.materialise')
  );

create policy analytics_export_select_member on public.analytics_exports for select to authenticated
  using (nodex.has_permission(tenant_id, 'analytics.read'));
create policy analytics_export_insert_exporter on public.analytics_exports for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'analytics.export'));

insert into public.permissions (key, display_name, description, module_code, risk_tier, requires_online)
values
  ('analytics.read',        'Read operational analytics',  'View report definitions, materialised rollups, report runs and the export log.', 'M38', 'standard', false),
  ('analytics.define',      'Define reports',              'Create and publish a report definition and retire one.',                        'M38', 'elevated', false),
  ('analytics.materialise', 'Materialise rollups',         'Run a report and write its rolling rollup against the read replica.',           'M38', 'elevated', true),
  ('analytics.export',      'Export report artefacts',     'Take a finished report out of the hospital, and record where it went.',         'M38', 'elevated', true)
on conflict (key) do nothing;

insert into public.role_permissions (role_key, permission_key)
values
  ('hospital_super_admin', 'analytics.read'),
  ('hospital_super_admin', 'analytics.define'),
  ('hospital_super_admin', 'analytics.materialise'),
  ('hospital_super_admin', 'analytics.export'),
  ('medical_officer',      'analytics.read'),
  ('medical_officer',      'analytics.materialise'),
  ('nursing_staff',        'analytics.read'),
  ('billing_accounts',     'analytics.read'),
  ('billing_accounts',     'analytics.export'),
  ('pharmacist',           'analytics.read'),
  ('auditor',              'analytics.read'),
  ('auditor',              'analytics.export')
on conflict do nothing;
