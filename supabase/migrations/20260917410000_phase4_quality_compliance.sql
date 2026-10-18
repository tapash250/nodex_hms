-- NODEX Phase 4, Module 35: Quality & NABH Compliance Hub.
--
-- Specification scope: "Accreditation compliance checklists (NABH / JCI),
-- Hospital Acquired Infection (HAI) tracking, and needle-stick incident audits."
-- Entities: "compliance_audits, incident_reports, and clinical_indicators."
--
-- This is the quality estate: the evidence a hospital presents to an
-- accreditation body and the incident and indicator record that evidence is
-- built from. It is distinct from the clinical record (an encounter records the
-- care; an audit records whether the care met a standard) and from the statutory
-- register (the law requires a birth certificate; an accreditation body requires
-- a hand-hygiene rate).
--
-- Three tables, matching the entities named in the scope:
--
--   * `compliance_audits` is one audit of one framework chapter on one date,
--     scoring how many criteria were met. It runs
--     `planned → in_progress → completed`, cancellable with a reason from either
--     live stage, and a completed audit is frozen because the score is what was
--     presented. The compliance score itself is derived from the two counts, so
--     it cannot disagree with them.
--   * `incident_reports` is a patient safety incident, including the
--     needle-stick injuries and HAI events the scope names. It runs
--     `reported → investigating → action_plan → closed`, voidable from either of
--     the two live stages with a reason. The severity sets the response window,
--     which is derived rather than stored so changing a threshold re-derives
--     every overdue marker.
--   * `clinical_indicators` is a measured indicator over a period: the numerator,
--     the denominator, the unit and the target. Its value is derived from the
--     counts and the unit multiplier, and whether it meets the target is derived
--     from the direction, never stored. A published indicator is a figure an
--     accreditation body has read, so it is frozen but for a retraction with a
--     reason.
--
-- Nothing here is a legal finalization, so no permission is `requires_online`:
-- the ward records a needle-stick at the bedside and an audit is scored where it
-- was conducted. Correctness is preserved by the guards and by the derived
-- values, not by requiring a network.
--
-- Four permissions are granted explicitly because the Phase 1 all-permissions
-- seed predates these keys. Reading is separated from each of the three working
-- tiers so an auditor can read the evidence without being able to score an audit
-- or close an incident.

create table public.compliance_audits (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  facility_id uuid not null references public.facilities(id) on delete restrict,
  framework text not null
    check (framework in ('nabh','jci','iso','internal')),
  chapter text not null check (length(btrim(chapter)) > 0),
  title text not null check (length(btrim(title)) > 0),
  standard_reference text
    check (standard_reference is null or length(btrim(standard_reference)) > 0),
  auditor_id uuid references public.app_users(id) on delete set null,
  scheduled_for timestamptz not null,
  status text not null default 'planned'
    check (status in ('planned','in_progress','completed','cancelled')),
  conducted_at timestamptz,
  total_criteria integer check (total_criteria is null or total_criteria > 0),
  compliant_criteria integer check (compliant_criteria is null
                                      or compliant_criteria >= 0),
  findings text check (findings is null or length(btrim(findings)) > 0),
  corrective_action_due_at timestamptz,
  completed_by uuid references public.app_users(id) on delete set null,
  cancelled_at timestamptz,
  cancel_reason text check (cancel_reason is null or length(btrim(cancel_reason)) > 0),
  created_by uuid not null references public.app_users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- The score cannot exceed what was assessed.
  constraint audit_score_ck check (
    compliant_criteria is null or total_criteria is null
    or compliant_criteria <= total_criteria
  ),
  -- A started audit knows when it started.
  constraint audit_progress_ck check (
    status <> 'in_progress' or conducted_at is not null
  ),
  -- A completed audit is a scored, attested fact.
  constraint audit_completed_ck check (
    status <> 'completed'
    or (conducted_at is not null and completed_by is not null
        and total_criteria is not null and compliant_criteria is not null)
  ),
  constraint audit_cancelled_ck check (
    status <> 'cancelled'
    or (cancelled_at is not null and cancel_reason is not null
        and length(btrim(cancel_reason)) > 0)
  )
);
create index compliance_audit_tenant_idx
  on public.compliance_audits(tenant_id, status, scheduled_for desc);
create index compliance_audit_framework_idx
  on public.compliance_audits(tenant_id, framework, chapter);

create table public.incident_reports (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  facility_id uuid not null references public.facilities(id) on delete restrict,
  report_number text not null check (length(btrim(report_number)) > 0),
  category text not null
    check (category in ('needle_stick','medication_error','patient_fall','hai',
                        'transfusion_reaction','surgical','equipment','violence',
                        'other')),
  severity text not null
    check (severity in ('near_miss','minor','moderate','major','sentinel')),
  title text not null check (length(btrim(title)) > 0),
  description text not null check (length(btrim(description)) > 0),
  occurred_at timestamptz not null,
  reported_at timestamptz not null default now(),
  location text check (location is null or length(btrim(location)) > 0),
  patient_id uuid references public.patients(id) on delete set null,
  reported_by uuid not null references public.app_users(id) on delete restrict,
  assigned_to uuid references public.app_users(id) on delete set null,
  immediate_action text
    check (immediate_action is null or length(btrim(immediate_action)) > 0),
  status text not null default 'reported'
    check (status in ('reported','investigating','action_plan','closed','voided')),
  investigation_started_at timestamptz,
  action_plan text check (action_plan is null or length(btrim(action_plan)) > 0),
  action_plan_due_at timestamptz,
  follow_up_due_at timestamptz,
  closed_at timestamptz,
  closure_note text check (closure_note is null or length(btrim(closure_note)) > 0),
  voided_at timestamptz,
  void_reason text check (void_reason is null or length(btrim(void_reason)) > 0),
  created_by uuid not null references public.app_users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- One report number per tenant: two files for one incident are one incident.
  unique (tenant_id, report_number),
  constraint incident_investigating_ck check (
    status not in ('investigating','action_plan','closed')
    or investigation_started_at is not null
  ),
  -- An action plan is an action with a date, not a sentence with none.
  constraint incident_action_ck check (
    status not in ('action_plan','closed')
    or (action_plan is not null and action_plan_due_at is not null)
  ),
  constraint incident_closed_ck check (
    status <> 'closed'
    or (closed_at is not null and closure_note is not null
        and length(btrim(closure_note)) > 0)
  ),
  constraint incident_voided_ck check (
    status <> 'voided'
    or (voided_at is not null and void_reason is not null
        and length(btrim(void_reason)) > 0)
  )
);
create index incident_report_tenant_idx
  on public.incident_reports(tenant_id, status, occurred_at desc);
create index incident_report_category_idx
  on public.incident_reports(tenant_id, category, severity);
create index incident_report_patient_idx
  on public.incident_reports(tenant_id, patient_id);

create table public.clinical_indicators (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  facility_id uuid not null references public.facilities(id) on delete restrict,
  code text not null check (length(btrim(code)) > 0),
  name text not null check (length(btrim(name)) > 0),
  category text not null
    check (category in ('infection_control','patient_safety','clinical_outcome',
                        'operational','accreditation')),
  unit text not null
    check (unit in ('percent','per_1000_patient_days','per_1000_device_days',
                    'count','ratio','hours')),
  direction text not null
    check (direction in ('higher_is_better','lower_is_better')),
  period_start date not null,
  period_end date not null,
  numerator integer not null check (numerator >= 0),
  denominator integer not null check (denominator >= 0),
  target_value integer check (target_value is null or target_value >= 0),
  source_note text check (source_note is null or length(btrim(source_note)) > 0),
  status text not null default 'draft'
    check (status in ('draft','published','retracted')),
  published_by uuid references public.app_users(id) on delete set null,
  published_at timestamptz,
  retracted_at timestamptz,
  retract_reason text
    check (retract_reason is null or length(btrim(retract_reason)) > 0),
  created_by uuid not null references public.app_users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- One reading of one indicator for one period.
  unique (tenant_id, code, period_start),
  constraint indicator_period_ck check (period_end >= period_start),
  constraint indicator_published_ck check (
    status <> 'published'
    or (published_at is not null and published_by is not null)
  ),
  constraint indicator_retracted_ck check (
    status <> 'retracted'
    or (retracted_at is not null and retract_reason is not null
        and length(btrim(retract_reason)) > 0)
  )
);
create index clinical_indicator_tenant_idx
  on public.clinical_indicators(tenant_id, status, period_start desc);
create index clinical_indicator_category_idx
  on public.clinical_indicators(tenant_id, category, code);

comment on table public.clinical_indicators is
  'One measured quality indicator over one period. The value and whether it meets the target are derived from the counts, the unit and the direction, never stored, so a published figure cannot disagree with its own numerator.';

create trigger compliance_audits_set_updated_at
  before update on public.compliance_audits
  for each row execute function nodex.tg_set_updated_at();
create trigger incident_reports_set_updated_at
  before update on public.incident_reports
  for each row execute function nodex.tg_set_updated_at();
create trigger clinical_indicators_set_updated_at
  before update on public.clinical_indicators
  for each row execute function nodex.tg_set_updated_at();

-- Hard deletions are blocked at the table as well as by RLS: an incident report
-- and an audit score are evidence, and evidence is not deleted.
create trigger compliance_audits_retain
  before delete on public.compliance_audits
  for each row execute function nodex.tg_block_mutation();
create trigger incident_reports_retain
  before delete on public.incident_reports
  for each row execute function nodex.tg_block_mutation();
create trigger clinical_indicators_retain
  before delete on public.clinical_indicators
  for each row execute function nodex.tg_block_mutation();

-- An audit is edited freely while planned, re-scoped only until it starts, and
-- frozen with its score once completed.
create or replace function nodex.tg_compliance_audit_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status in ('completed','cancelled') then
    raise exception using
      message = 'NODEX: a settled compliance audit is immutable',
      errcode = '42501';
  end if;
  if old.status <> 'planned' then
    if new.framework is distinct from old.framework
      or new.chapter is distinct from old.chapter
      or new.title is distinct from old.title
      or new.standard_reference is distinct from old.standard_reference
      or new.scheduled_for is distinct from old.scheduled_for
      or new.auditor_id is distinct from old.auditor_id then
      raise exception using
        message = 'NODEX: a started audit is not re-scoped',
        errcode = '42501';
    end if;
  end if;
  if new.status = old.status then
    return new;
  end if;
  if (old.status = 'planned' and new.status in ('in_progress','cancelled'))
    or (old.status = 'in_progress' and new.status in ('completed','cancelled')) then
    return new;
  end if;
  raise exception using
    message = 'NODEX: a compliance audit may not skip a stage',
    errcode = '42501';
end;
$$;
create trigger compliance_audits_guard
  before update on public.compliance_audits
  for each row execute function nodex.tg_compliance_audit_guard();

-- An incident is edited freely while reported; what happened then freezes, and
-- the investigation, the action plan and the closure are what move it on.
create or replace function nodex.tg_incident_report_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status in ('closed','voided') then
    raise exception using
      message = 'NODEX: a closed incident report is immutable',
      errcode = '42501';
  end if;
  if old.status <> 'reported' then
    if new.report_number is distinct from old.report_number
      or new.category is distinct from old.category
      or new.severity is distinct from old.severity
      or new.title is distinct from old.title
      or new.description is distinct from old.description
      or new.occurred_at is distinct from old.occurred_at
      or new.reported_at is distinct from old.reported_at
      or new.location is distinct from old.location
      or new.patient_id is distinct from old.patient_id
      or new.reported_by is distinct from old.reported_by then
      raise exception using
        message = 'NODEX: what an investigated incident records is immutable',
        errcode = '42501';
    end if;
  end if;
  if new.status = old.status then
    return new;
  end if;
  if (old.status = 'reported' and new.status in ('investigating','voided'))
    or (old.status = 'investigating' and new.status in ('action_plan','voided'))
    or (old.status = 'action_plan' and new.status = 'closed') then
    return new;
  end if;
  raise exception using
    message = 'NODEX: an incident report may not skip a stage',
    errcode = '42501';
end;
$$;
create trigger incident_reports_guard
  before update on public.incident_reports
  for each row execute function nodex.tg_incident_report_guard();

-- An indicator is editable while a draft, and a published figure is frozen but
-- for the retraction that withdraws it.
create or replace function nodex.tg_clinical_indicator_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status = 'retracted' then
    raise exception using
      message = 'NODEX: a retracted indicator is immutable',
      errcode = '42501';
  end if;
  if old.status = 'published' then
    if new.status <> 'retracted' then
      raise exception using
        message = 'NODEX: a published indicator is retracted, not edited',
        errcode = '42501';
    end if;
    if new.code is distinct from old.code
      or new.name is distinct from old.name
      or new.category is distinct from old.category
      or new.unit is distinct from old.unit
      or new.direction is distinct from old.direction
      or new.period_start is distinct from old.period_start
      or new.period_end is distinct from old.period_end
      or new.numerator is distinct from old.numerator
      or new.denominator is distinct from old.denominator
      or new.target_value is distinct from old.target_value
      or new.published_at is distinct from old.published_at
      or new.published_by is distinct from old.published_by then
      raise exception using
        message = 'NODEX: the figures a published indicator asserts are immutable',
        errcode = '42501';
    end if;
    return new;
  end if;
  if new.status = old.status then
    return new;
  end if;
  if new.status = 'published' then
    return new;
  end if;
  raise exception using
    message = 'NODEX: a clinical indicator may not skip a stage',
    errcode = '42501';
end;
$$;
create trigger clinical_indicators_guard
  before update on public.clinical_indicators
  for each row execute function nodex.tg_clinical_indicator_guard();

alter table public.compliance_audits enable row level security;
alter table public.compliance_audits force row level security;
alter table public.incident_reports enable row level security;
alter table public.incident_reports force row level security;
alter table public.clinical_indicators enable row level security;
alter table public.clinical_indicators force row level security;

create policy compliance_audit_select_member on public.compliance_audits for select to authenticated
  using (nodex.has_permission(tenant_id, 'quality.read'));
create policy compliance_audit_insert_auditor on public.compliance_audits for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'quality.audit'));
create policy compliance_audit_update_auditor on public.compliance_audits for update to authenticated
  using (nodex.has_permission(tenant_id, 'quality.audit'))
  with check (nodex.has_permission(tenant_id, 'quality.audit'));

create policy incident_report_select_member on public.incident_reports for select to authenticated
  using (nodex.has_permission(tenant_id, 'quality.read'));
create policy incident_report_insert_reporter on public.incident_reports for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'quality.incident'));
create policy incident_report_update_reporter on public.incident_reports for update to authenticated
  using (nodex.has_permission(tenant_id, 'quality.incident'))
  with check (nodex.has_permission(tenant_id, 'quality.incident'));

create policy clinical_indicator_select_member on public.clinical_indicators for select to authenticated
  using (nodex.has_permission(tenant_id, 'quality.read'));
create policy clinical_indicator_insert_analyst on public.clinical_indicators for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'quality.indicator'));
create policy clinical_indicator_update_analyst on public.clinical_indicators for update to authenticated
  using (nodex.has_permission(tenant_id, 'quality.indicator'))
  with check (nodex.has_permission(tenant_id, 'quality.indicator'));

insert into public.permissions (key, display_name, description, module_code, risk_tier, requires_online)
values
  ('quality.read',      'Read quality records',    'View accreditation audits, incident reports and clinical indicators.', 'M35', 'standard', false),
  ('quality.audit',     'Run compliance audits',   'Plan, conduct, score, complete and cancel an accreditation audit.', 'M35', 'elevated', false),
  ('quality.incident',  'Report and investigate incidents', 'Raise an incident report, investigate it, plan corrective action and close it.', 'M35', 'elevated', false),
  ('quality.indicator', 'Record clinical indicators', 'Record, publish and retract a measured clinical indicator.', 'M35', 'elevated', false)
on conflict (key) do nothing;

insert into public.role_permissions (role_key, permission_key)
values
  ('hospital_super_admin', 'quality.read'),
  ('hospital_super_admin', 'quality.audit'),
  ('hospital_super_admin', 'quality.incident'),
  ('hospital_super_admin', 'quality.indicator'),
  ('medical_officer',      'quality.read'),
  ('medical_officer',      'quality.audit'),
  ('medical_officer',      'quality.incident'),
  ('medical_officer',      'quality.indicator'),
  ('nursing_staff',        'quality.read'),
  ('nursing_staff',        'quality.incident'),
  ('auditor',              'quality.read'),
  ('auditor',              'quality.audit')
on conflict do nothing;
