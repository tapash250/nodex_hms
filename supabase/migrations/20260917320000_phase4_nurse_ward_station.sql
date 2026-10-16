-- NODEX Phase 4, Module 06: Nurse Ward Station.
--
-- Specification scope: "Beds, vitals, handover, task queues, MAR, urgent
-- alerts."
--
-- Beds and MAR already exist: occupancy is the Module 11 bed assignment and the
-- MAR event is the Module 25 medication administration. The ward station does
-- not copy either — it reads them. What is missing, and what this slice adds, is
-- the routine general-ward observation (the ICU keeps its own continuous
-- `icu_vitals`), the shift nursing handover for a general ward, and the ward
-- task queue that turns a plan into names and times.
--
-- Two of the three tables are append-only facts. A vital sign and a handover are
-- things that happened at a time: recording a second set of observations is a
-- second row, not an edit of the first. Only the task queue is a living record,
-- and it is a guarded state machine (open -> in_progress -> done/cancelled)
-- because "this task is finished, by this person, at this time" is an assertion
-- a ward is audited on.
--
-- `vitals.record` already exists and is granted to nursing staff; this slice
-- reuses it rather than inventing a second vitals permission. The two new
-- permissions (`nursing.handover.record`, `nursing_task.write`) plus the read
-- permission (`nursing_station.read`) are granted explicitly, since the Phase 1
-- all-permissions seed predates these keys.

create table public.ward_vitals (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  patient_id uuid not null references public.patients(id) on delete restrict,
  encounter_id uuid references public.clinical_encounters(id) on delete restrict,
  ward_id uuid not null references public.wards(id) on delete restrict,
  bed_id uuid references public.beds(id) on delete set null,
  recorded_by uuid not null references public.app_users(id) on delete restrict,
  observed_at timestamptz not null default now(),
  temperature_celsius numeric(4,1)
    check (temperature_celsius is null or temperature_celsius between 25 and 45),
  pulse_bpm int check (pulse_bpm is null or pulse_bpm between 20 and 300),
  respiratory_rate int
    check (respiratory_rate is null or respiratory_rate between 4 and 80),
  systolic_bp int check (systolic_bp is null or systolic_bp between 40 and 300),
  diastolic_bp int check (diastolic_bp is null or diastolic_bp between 20 and 200),
  spo2 int check (spo2 is null or spo2 between 1 and 100),
  pain_score int check (pain_score is null or pain_score between 0 and 10),
  consciousness text not null default 'alert'
    check (consciousness in ('alert','voice','pain','unresponsive')),
  on_oxygen boolean not null default false,
  notes text check (notes is null or length(btrim(notes)) > 0),
  created_at timestamptz not null default now(),
  -- An observation with no measurement is noise on the board and in the record.
  constraint ward_vitals_measurement_ck check (
    temperature_celsius is not null
    or pulse_bpm is not null
    or respiratory_rate is not null
    or systolic_bp is not null
    or diastolic_bp is not null
    or spo2 is not null
    or pain_score is not null
  ),
  constraint ward_vitals_bp_ck check (
    systolic_bp is null or diastolic_bp is null or systolic_bp > diastolic_bp
  )
);
create index ward_vitals_patient_idx
  on public.ward_vitals(tenant_id, patient_id, observed_at desc);
create index ward_vitals_ward_idx
  on public.ward_vitals(tenant_id, ward_id, observed_at desc);
create trigger ward_vitals_append_only before update or delete on public.ward_vitals
  for each row execute function nodex.tg_block_mutation();

-- A shift handover for a general ward. Like the ICU handover it is an immutable
-- shift record: it names who handed over, to whom, when, and what is pending.
create table public.ward_handovers (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  ward_id uuid not null references public.wards(id) on delete restrict,
  shift_id uuid references public.staff_shifts(id) on delete set null,
  from_user uuid not null references public.app_users(id) on delete restrict,
  to_user uuid references public.app_users(id) on delete set null,
  handover_at timestamptz not null default now(),
  summary text not null check (length(btrim(summary)) > 0),
  pending_items text check (pending_items is null or length(btrim(pending_items)) > 0),
  created_at timestamptz not null default now()
);
create index ward_handovers_ward_idx
  on public.ward_handovers(tenant_id, ward_id, handover_at desc);
create trigger ward_handovers_append_only before update or delete on public.ward_handovers
  for each row execute function nodex.tg_block_mutation();

-- The ward task queue: a delegated piece of nursing work with an owner and a
-- time. Terminal tasks (done, cancelled) are frozen so the completion record —
-- who, when — cannot be rewritten after the fact.
create table public.ward_tasks (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  ward_id uuid not null references public.wards(id) on delete restrict,
  patient_id uuid references public.patients(id) on delete set null,
  encounter_id uuid references public.clinical_encounters(id) on delete restrict,
  title text not null check (length(btrim(title)) > 0),
  detail text check (detail is null or length(btrim(detail)) > 0),
  task_type text not null default 'observation'
    check (task_type in ('observation','medication','sample','mobility','hygiene','documentation','other')),
  priority text not null default 'routine'
    check (priority in ('routine','urgent','stat')),
  due_at timestamptz,
  assigned_to uuid references public.app_users(id) on delete set null,
  status text not null default 'open'
    check (status in ('open','in_progress','done','cancelled')),
  created_by uuid not null references public.app_users(id) on delete restrict,
  completed_by uuid references public.app_users(id) on delete set null,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ward_task_completion_ck check (
    (status in ('done','cancelled') and completed_by is not null and completed_at is not null)
    or (status in ('open','in_progress') and completed_by is null and completed_at is null)
  )
);
create index ward_tasks_ward_idx
  on public.ward_tasks(tenant_id, ward_id, status, due_at);
create index ward_tasks_assignee_idx
  on public.ward_tasks(assigned_to, status, due_at);
create trigger ward_tasks_set_updated_at before update on public.ward_tasks
  for each row execute function nodex.tg_set_updated_at();
create trigger ward_tasks_retain before delete on public.ward_tasks
  for each row execute function nodex.tg_block_mutation();

create or replace function nodex.tg_ward_task_transition_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status in ('done', 'cancelled') then
    raise exception using
      message = 'NODEX: a closed ward task is immutable',
      errcode = '42501';
  end if;
  if new.status = old.status then
    return new;
  end if;
  if new.status = 'in_progress' and old.status <> 'open' then
    raise exception using
      message = 'NODEX: only an open task may be started',
      errcode = '42501';
  end if;
  if new.status in ('done', 'cancelled')
    and old.status not in ('open', 'in_progress') then
    raise exception using
      message = 'NODEX: only an open or in-progress task may be closed',
      errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger ward_tasks_transition_guard
  before update on public.ward_tasks
  for each row execute function nodex.tg_ward_task_transition_guard();

alter table public.ward_vitals enable row level security;
alter table public.ward_vitals force row level security;
alter table public.ward_handovers enable row level security;
alter table public.ward_handovers force row level security;
alter table public.ward_tasks enable row level security;
alter table public.ward_tasks force row level security;

-- Reading the station board is its own permission, which is also what scopes
-- the sync bucket. Writing vitals reuses `vitals.record`; handover and task
-- writes carry their own keys.
create policy ward_vitals_select_member on public.ward_vitals for select to authenticated
  using (nodex.has_permission(tenant_id, 'nursing_station.read'));
create policy ward_vitals_insert_writer on public.ward_vitals for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'vitals.record'));

create policy ward_handovers_select_member on public.ward_handovers for select to authenticated
  using (nodex.has_permission(tenant_id, 'nursing_station.read'));
create policy ward_handovers_insert_writer on public.ward_handovers for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'nursing.handover.record'));

create policy ward_tasks_select_member on public.ward_tasks for select to authenticated
  using (nodex.has_permission(tenant_id, 'nursing_station.read'));
create policy ward_tasks_insert_writer on public.ward_tasks for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'nursing_task.write'));
create policy ward_tasks_update_writer on public.ward_tasks for update to authenticated
  using (nodex.has_permission(tenant_id, 'nursing_task.write'))
  with check (nodex.has_permission(tenant_id, 'nursing_task.write'));

insert into public.permissions (key, name, description, module_code, risk_tier, requires_online)
values
  ('nursing_station.read',     'Read ward station',   'View the ward observation, handover and task board.', 'M06', 'standard', false),
  ('nursing.handover.record',  'Record ward handover','Record the shift nursing handover for a ward.',        'M06', 'elevated', false),
  ('nursing_task.write',       'Manage ward tasks',   'Create, delegate and close ward nursing tasks.',       'M06', 'standard', false)
on conflict (key) do nothing;

insert into public.role_permissions (role_key, permission_key)
values
  ('hospital_super_admin', 'nursing_station.read'),
  ('hospital_super_admin', 'nursing.handover.record'),
  ('hospital_super_admin', 'nursing_task.write'),
  ('medical_officer',      'nursing_station.read'),
  ('medical_officer',      'nursing_task.write'),
  ('nursing_staff',        'nursing_station.read'),
  ('nursing_staff',        'nursing.handover.record'),
  ('nursing_staff',        'nursing_task.write')
on conflict do nothing;
