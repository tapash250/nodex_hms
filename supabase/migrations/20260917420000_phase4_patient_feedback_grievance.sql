-- NODEX Phase 4, Module 36: Patient Feedback & Grievance Redressal.
--
-- Specification scope: "Patient Net Promoter Score (NPS) surveys, complaints
-- registry, departmental routing, and resolution SLA tracking."
--
-- This is the patient's voice: what the hospital hears about itself after the
-- care is delivered. It is distinct from the clinical record (an encounter
-- records what was done; a survey records how it was received) and from the
-- quality hub (an incident is a harm the hospital found in itself; a complaint is
-- a harm the patient brought to it).
--
-- Three tables:
--
--   * `feedback_surveys` is one Net Promoter Score response: the score, where it
--     was collected and whether the patient chose to say more. The band a score
--     falls in, whether the response is a detractor and the net promoter score
--     itself are all derived from the scores, so the headline number cannot
--     disagree with the responses behind it.
--   * `feedback_complaints` is one grievance, routed to a department and owned by
--     a person. It runs `logged → acknowledged → investigating → resolved →
--     closed`, with `dismissed` and `voided` as the two ways out. What was
--     complained about freezes once it is logged, because the acknowledgement and
--     resolution deadlines are measured from that moment and from the severity;
--     routing stays editable while the case is live, because re-routing a
--     grievance to the right department is the point of the registry.
--   * `complaint_routing_events` is the append-only routing history: where the
--     case went, who took it and why. An update or a delete is blocked by the
--     table and by RLS, so the history of who had the case is legible.
--
-- The deadlines are derived, not stored: 24 hours to acknowledge and, by
-- severity, three days to resolve a high-severity grievance, seven a medium one
-- and fourteen a low one. Changing a threshold re-derives every marker on every
-- device instead of leaving a stale flag behind.
--
-- Three permissions are granted explicitly because the Phase 1 all-permissions
-- seed predates these keys. Reading is standard and offline. Recording is the
-- front desk's tier and resolving is the clinical tier, so the person who takes a
-- complaint at the counter cannot also be the person who decides it was
-- unfounded. Nothing here is a legal finalization, so nothing requires a network.

create table public.feedback_surveys (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  facility_id uuid not null references public.facilities(id) on delete restrict,
  survey_number text not null check (length(btrim(survey_number)) > 0),
  -- Nullable: a response may be anonymous, which is what makes an honest score
  -- more likely than an identified one.
  patient_id uuid references public.patients(id) on delete set null,
  encounter_id uuid references public.clinical_encounters(id) on delete set null,
  touchpoint text not null
    check (touchpoint in ('opd','ipd','emergency','diagnostics','pharmacy',
                          'billing','telemedicine','discharge','other')),
  nps_score integer not null check (nps_score between 0 and 10),
  comment text check (comment is null or length(btrim(comment)) > 0),
  recorded_at timestamptz not null default now(),
  status text not null default 'recorded'
    check (status in ('recorded','actioned','voided')),
  action_note text check (action_note is null or length(btrim(action_note)) > 0),
  actioned_by uuid references public.app_users(id) on delete set null,
  actioned_at timestamptz,
  voided_at timestamptz,
  void_reason text check (void_reason is null or length(btrim(void_reason)) > 0),
  recorded_by uuid not null references public.app_users(id) on delete restrict,
  created_by uuid not null references public.app_users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- One response number per tenant: a response filed twice would double-count in
  -- the net promoter score.
  unique (tenant_id, survey_number),
  constraint survey_actioned_ck check (
    status <> 'actioned'
    or (action_note is not null and actioned_by is not null
        and actioned_at is not null)
  ),
  constraint survey_voided_ck check (
    status <> 'voided'
    or (voided_at is not null and void_reason is not null
        and length(btrim(void_reason)) > 0)
  )
);
create index feedback_survey_tenant_idx
  on public.feedback_surveys(tenant_id, status, recorded_at desc);
create index feedback_survey_touchpoint_idx
  on public.feedback_surveys(tenant_id, touchpoint, nps_score);

create table public.feedback_complaints (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  facility_id uuid not null references public.facilities(id) on delete restrict,
  complaint_number text not null check (length(btrim(complaint_number)) > 0),
  patient_id uuid references public.patients(id) on delete set null,
  complainant_name text not null check (length(btrim(complainant_name)) > 0),
  complainant_contact text
    check (complainant_contact is null
           or length(btrim(complainant_contact)) > 0),
  channel text not null
    check (channel in ('counter','phone','email','portal','letter','staff',
                       'other')),
  category text not null
    check (category in ('waiting_time','staff_behaviour','billing',
                        'clinical_care','cleanliness','food','facility',
                        'privacy','other')),
  severity text not null check (severity in ('low','medium','high')),
  description text not null check (length(btrim(description)) > 0),
  received_at timestamptz not null default now(),
  routed_department_id uuid references public.departments(id) on delete set null,
  routed_to uuid references public.app_users(id) on delete set null,
  routed_at timestamptz,
  status text not null default 'logged'
    check (status in ('logged','acknowledged','investigating','resolved',
                      'closed','dismissed','voided')),
  acknowledged_at timestamptz,
  investigation_started_at timestamptz,
  resolved_at timestamptz,
  resolved_by uuid references public.app_users(id) on delete set null,
  resolution_summary text
    check (resolution_summary is null or length(btrim(resolution_summary)) > 0),
  closed_at timestamptz,
  closure_note text check (closure_note is null or length(btrim(closure_note)) > 0),
  dismissed_at timestamptz,
  dismiss_reason text
    check (dismiss_reason is null or length(btrim(dismiss_reason)) > 0),
  voided_at timestamptz,
  void_reason text check (void_reason is null or length(btrim(void_reason)) > 0),
  logged_by uuid not null references public.app_users(id) on delete restrict,
  created_by uuid not null references public.app_users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- One complaint number per tenant: two files for one grievance split the
  -- deadline and the answer.
  unique (tenant_id, complaint_number),
  constraint complaint_acknowledged_ck check (
    status not in ('acknowledged','investigating','resolved','closed')
    or acknowledged_at is not null
  ),
  constraint complaint_investigating_ck check (
    status <> 'investigating' or investigation_started_at is not null
  ),
  -- A grievance cannot be resolved or closed before anyone acknowledged it.
  constraint complaint_resolved_ck check (
    status not in ('resolved','closed')
    or (acknowledged_at is not null and resolved_at is not null
        and resolved_by is not null and resolution_summary is not null)
  ),
  constraint complaint_closed_ck check (
    status <> 'closed'
    or (closed_at is not null and closure_note is not null
        and length(btrim(closure_note)) > 0)
  ),
  constraint complaint_dismissed_ck check (
    status <> 'dismissed'
    or (dismissed_at is not null and dismiss_reason is not null
        and length(btrim(dismiss_reason)) > 0)
  ),
  constraint complaint_voided_ck check (
    status <> 'voided'
    or (voided_at is not null and void_reason is not null
        and length(btrim(void_reason)) > 0)
  )
);
create index feedback_complaint_tenant_idx
  on public.feedback_complaints(tenant_id, status, received_at desc);
create index feedback_complaint_department_idx
  on public.feedback_complaints(tenant_id, routed_department_id, status);
create index feedback_complaint_severity_idx
  on public.feedback_complaints(tenant_id, severity, status);
create index feedback_complaint_patient_idx
  on public.feedback_complaints(tenant_id, patient_id);

create table public.complaint_routing_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  complaint_id uuid not null
    references public.feedback_complaints(id) on delete restrict,
  event_type text not null
    check (event_type in ('logged','routed','rerouted','escalated','contacted')),
  from_department_id uuid references public.departments(id) on delete set null,
  to_department_id uuid references public.departments(id) on delete set null,
  assigned_to uuid references public.app_users(id) on delete set null,
  note text not null check (length(btrim(note)) > 0),
  occurred_at timestamptz not null default now(),
  recorded_by uuid not null references public.app_users(id) on delete restrict,
  created_at timestamptz not null default now()
);
create index complaint_routing_event_idx
  on public.complaint_routing_events(tenant_id, complaint_id, occurred_at);

comment on table public.complaint_routing_events is
  'Append-only routing history for a grievance. Where the case went, who took it and why, recorded as events: the answer to "who had this and when" is a query over the log, not a column that overwrites its own past.';

create trigger feedback_surveys_set_updated_at
  before update on public.feedback_surveys
  for each row execute function nodex.tg_set_updated_at();
create trigger feedback_complaints_set_updated_at
  before update on public.feedback_complaints
  for each row execute function nodex.tg_set_updated_at();

-- A survey is a captured answer, and the routing log is a history: neither is
-- rewritten, and a hard delete is refused at the table as well as by RLS.
create trigger feedback_surveys_retain
  before delete on public.feedback_surveys
  for each row execute function nodex.tg_block_mutation();
create trigger feedback_complaints_retain
  before delete on public.feedback_complaints
  for each row execute function nodex.tg_block_mutation();
create trigger complaint_routing_events_append_only
  before update or delete on public.complaint_routing_events
  for each row execute function nodex.tg_block_mutation();

-- A survey is edited only from recorded: actioning it settles it, and a voided
-- response is settled too.
create or replace function nodex.tg_feedback_survey_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status <> 'recorded' then
    raise exception using
      message = 'NODEX: a settled survey response is immutable',
      errcode = '42501';
  end if;
  if new.survey_number is distinct from old.survey_number
    or new.nps_score is distinct from old.nps_score
    or new.touchpoint is distinct from old.touchpoint
    or new.patient_id is distinct from old.patient_id
    or new.encounter_id is distinct from old.encounter_id
    or new.recorded_at is distinct from old.recorded_at
    or new.recorded_by is distinct from old.recorded_by
    or new.comment is distinct from old.comment then
    raise exception using
      message = 'NODEX: a survey response is not rewritten',
      errcode = '42501';
  end if;
  if new.status = old.status then
    return new;
  end if;
  if new.status in ('actioned','voided') then
    return new;
  end if;
  raise exception using
    message = 'NODEX: a survey response may not skip a stage',
    errcode = '42501';
end;
$$;
create trigger feedback_surveys_guard
  before update on public.feedback_surveys
  for each row execute function nodex.tg_feedback_survey_guard();

-- What a grievance is about freezes once it is logged, because the
-- acknowledgement and resolution deadlines are measured from it. Where it is
-- routed stays editable while the case is live: re-routing is the point.
create or replace function nodex.tg_feedback_complaint_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status in ('closed','dismissed','voided') then
    raise exception using
      message = 'NODEX: a settled grievance is immutable',
      errcode = '42501';
  end if;
  if old.status <> 'logged' then
    if new.complaint_number is distinct from old.complaint_number
      or new.complainant_name is distinct from old.complainant_name
      or new.complainant_contact is distinct from old.complainant_contact
      or new.channel is distinct from old.channel
      or new.category is distinct from old.category
      or new.severity is distinct from old.severity
      or new.description is distinct from old.description
      or new.received_at is distinct from old.received_at
      or new.patient_id is distinct from old.patient_id
      or new.logged_by is distinct from old.logged_by then
      raise exception using
        message = 'NODEX: what a grievance records is immutable',
        errcode = '42501';
    end if;
  end if;
  if new.status = old.status then
    return new;
  end if;
  if (old.status = 'logged'
        and new.status in ('acknowledged','dismissed','voided'))
    or (old.status = 'acknowledged'
        and new.status in ('investigating','dismissed'))
    or (old.status = 'investigating'
        and new.status in ('resolved','dismissed'))
    or (old.status = 'resolved' and new.status = 'closed') then
    return new;
  end if;
  raise exception using
    message = 'NODEX: a grievance may not skip a stage',
    errcode = '42501';
end;
$$;
create trigger feedback_complaints_guard
  before update on public.feedback_complaints
  for each row execute function nodex.tg_feedback_complaint_guard();

alter table public.feedback_surveys enable row level security;
alter table public.feedback_surveys force row level security;
alter table public.feedback_complaints enable row level security;
alter table public.feedback_complaints force row level security;
alter table public.complaint_routing_events enable row level security;
alter table public.complaint_routing_events force row level security;

create policy feedback_survey_select_member on public.feedback_surveys for select to authenticated
  using (nodex.has_permission(tenant_id, 'feedback.read'));
create policy feedback_survey_insert_recorder on public.feedback_surveys for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'feedback.record'));
create policy feedback_survey_update_resolver on public.feedback_surveys for update to authenticated
  using (nodex.has_permission(tenant_id, 'feedback.resolve'))
  with check (nodex.has_permission(tenant_id, 'feedback.resolve'));

create policy feedback_complaint_select_member on public.feedback_complaints for select to authenticated
  using (nodex.has_permission(tenant_id, 'feedback.read'));
create policy feedback_complaint_insert_recorder on public.feedback_complaints for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'feedback.record'));
create policy feedback_complaint_update_resolver on public.feedback_complaints for update to authenticated
  using (nodex.has_permission(tenant_id, 'feedback.resolve'))
  with check (nodex.has_permission(tenant_id, 'feedback.resolve'));

create policy complaint_routing_event_select_member on public.complaint_routing_events for select to authenticated
  using (nodex.has_permission(tenant_id, 'feedback.read'));
create policy complaint_routing_event_insert_writer on public.complaint_routing_events for insert to authenticated
  with check (
    nodex.has_permission(tenant_id, 'feedback.record')
    or nodex.has_permission(tenant_id, 'feedback.resolve')
  );

insert into public.permissions (key, display_name, description, module_code, risk_tier, requires_online)
values
  ('feedback.read',    'Read patient feedback',   'View Net Promoter Score surveys, the complaints registry and their routing history.', 'M36', 'standard', false),
  ('feedback.record',  'Record patient feedback', 'Capture a survey response and log a grievance.', 'M36', 'elevated', false),
  ('feedback.resolve', 'Resolve grievances',      'Acknowledge, route and re-route, investigate, resolve, dismiss and close a grievance.', 'M36', 'elevated', false)
on conflict (key) do nothing;

insert into public.role_permissions (role_key, permission_key)
values
  ('hospital_super_admin', 'feedback.read'),
  ('hospital_super_admin', 'feedback.record'),
  ('hospital_super_admin', 'feedback.resolve'),
  ('medical_officer',      'feedback.read'),
  ('medical_officer',      'feedback.record'),
  ('medical_officer',      'feedback.resolve'),
  ('nursing_staff',        'feedback.read'),
  ('nursing_staff',        'feedback.record'),
  ('nursing_staff',        'feedback.resolve'),
  ('billing_accounts',     'feedback.read'),
  ('billing_accounts',     'feedback.record'),
  ('auditor',              'feedback.read')
on conflict do nothing;
