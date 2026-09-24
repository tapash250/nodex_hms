-- NODEX Phase 3, Module 05: Emergency Department & Triage.
--
-- Triage assessment -> ER visit -> admission/discharge/transfer.
-- Triage acuity uses ESI 1-5 scale; escalation requires triage.escalate permission.
-- RLS uses membership-derived permissions; FKs target app_users.

create table public.triage_assessments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  patient_id uuid not null references public.patients(id) on delete restrict,
  encounter_id uuid references public.clinical_encounters(id) on delete restrict,
  assessed_by uuid not null references public.app_users(id) on delete restrict,
  acuity text not null check (acuity in ('esi1','esi2','esi3','esi4','esi5')),
  chief_complaint text not null check (length(btrim(chief_complaint)) > 0),
  vitals jsonb not null default '{}'::jsonb,
  red_flags jsonb not null default '[]'::jsonb,
  disposition text not null check (disposition in ('discharge','admit','transfer','left_against_medical_advice','deceased')),
  escalated boolean not null default false,
  escalated_by uuid references public.app_users(id) on delete restrict,
  escalated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint triage_escalation_ck check ((escalated = true and escalated_by is not null and escalated_at is not null) or escalated = false)
);
create index triage_patient_idx on public.triage_assessments(tenant_id, patient_id, created_at desc);
create index triage_encounter_idx on public.triage_assessments(encounter_id);
create index triage_acuity_idx on public.triage_assessments(tenant_id, acuity, created_at desc);

create table public.er_visits (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  patient_id uuid not null references public.patients(id) on delete restrict,
  triage_id uuid not null references public.triage_assessments(id) on delete restrict,
  encounter_id uuid references public.clinical_encounters(id) on delete restrict,
  provider_id uuid not null references public.app_users(id) on delete restrict,
  status text not null default 'in_progress' check (status in ('in_progress','discharged','admitted','transferred','left_ama','deceased')),
  arrival_mode text check (arrival_mode in ('walk_in','ambulance','helicopter','police','transfer')),
  bed_id uuid references public.beds(id) on delete set null,
  started_at timestamptz not null default now(),
  disposition text,
  disposition_reason text,
  discharged_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint er_visit_disposition_ck check ((status in ('discharged','admitted','transferred','left_ama','deceased') and discharged_at is not null) or status = 'in_progress'),
  constraint er_visit_admission_ck check ((status = 'admitted' and disposition is not null) or status <> 'admitted')
);
create index er_visits_patient_idx on public.er_visits(tenant_id, patient_id, started_at desc);
create index er_visits_triage_idx on public.er_visits(triage_id);
create index er_visits_status_idx on public.er_visits(tenant_id, status, started_at desc);

create trigger triage_assessments_set_updated_at before update on public.triage_assessments for each row execute function nodex.tg_set_updated_at();
create trigger er_visits_set_updated_at before update on public.er_visits for each row execute function nodex.tg_set_updated_at();

create or replace function nodex.tg_triage_escalation_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.escalated = true and new.escalated = false then
    raise exception using message = 'NODEX: triage escalation cannot be reverted', errcode = '42501';
  end if;
  if new.escalated = true and old.escalated = false then
    if new.escalated_by is null or new.escalated_at is null then
      raise exception using message = 'NODEX: triage escalation requires authorizer and timestamp', errcode = '22000';
    end if;
    -- Enforce triage.escalate permission at trigger level (RLS alone cannot distinguish)
    if auth.uid() is not null and not nodex.has_permission(new.tenant_id, 'triage.escalate') then
      raise exception using message = 'NODEX: triage escalation requires triage.escalate permission', errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;
create trigger triage_escalation_guard before update on public.triage_assessments for each row execute function nodex.tg_triage_escalation_guard();

create or replace function nodex.tg_er_visit_transition_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status in ('discharged','admitted','transferred','left_ama','deceased') and new.status <> old.status then
    raise exception using message = 'NODEX: terminal ER visit status cannot transition', errcode = '42501';
  end if;
  if new.status <> old.status and not (
    (old.status = 'in_progress' and new.status in ('discharged','admitted','transferred','left_ama','deceased')) or
    (old.status = 'admitted' and new.status in ('discharged','transferred','deceased'))
  ) then
    raise exception using message = 'NODEX: ER visit transition is not permitted', errcode = '42501';
  end if;
  if new.status in ('discharged','admitted','transferred','left_ama','deceased') and (new.discharged_at is null or new.disposition is null) then
    raise exception using message = 'NODEX: ER visit disposition requires timestamp and reason', errcode = '22000';
  end if;
  if new.status = 'admitted' and old.status = 'in_progress' and (new.disposition is null or new.disposition_reason is null) then
    raise exception using message = 'NODEX: admitting an ER visit requires disposition and reason', errcode = '22000';
  end if;
  return new;
end;
$$;
create trigger er_visit_transition_guard before update on public.er_visits for each row execute function nodex.tg_er_visit_transition_guard();

alter table public.triage_assessments enable row level security;
alter table public.triage_assessments force row level security;
alter table public.er_visits enable row level security;
alter table public.er_visits force row level security;

create policy triage_select_member on public.triage_assessments for select to authenticated using (nodex.has_permission(tenant_id,'patient.read'));
create policy triage_insert_writer on public.triage_assessments for insert to authenticated with check (nodex.has_permission(tenant_id,'triage.write'));
create policy triage_update_writer on public.triage_assessments for update to authenticated using (nodex.has_permission(tenant_id,'triage.write')) with check (nodex.has_permission(tenant_id,'triage.write'));
-- Escalation requires special permission
create policy triage_update_escalate on public.triage_assessments for update to authenticated using (nodex.has_permission(tenant_id,'triage.escalate')) with check (nodex.has_permission(tenant_id,'triage.escalate'));

create policy er_visits_select_member on public.er_visits for select to authenticated using (nodex.has_permission(tenant_id,'patient.read'));
create policy er_visits_insert_writer on public.er_visits for insert to authenticated with check (nodex.has_permission(tenant_id,'er.visit.write'));
create policy er_visits_update_writer on public.er_visits for update to authenticated using (nodex.has_permission(tenant_id,'er.visit.write')) with check (nodex.has_permission(tenant_id,'er.visit.write'));