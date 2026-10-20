-- Module 04: Doctor Clinical Dashboard (AI-Assisted)
--
-- The attending's cockpit: who is under my care, what is on today, and what
-- is waiting for a signature. The assignment is the spine of it — a patient
-- is "mine" because there is an assignment, not because a dashboard says so.
--
-- The AI part of this module is a summary of what is already on the screen.
-- Nothing in this table is written by a model: the assignments are the
-- record, and a summary that cannot be traced back to them would be a
-- clinical statement with no source.

create table public.doctor_assignments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  doctor_id uuid not null references public.app_users(id) on delete restrict,
  patient_id uuid not null references public.patients(id) on delete cascade,
  assignment_type text not null default 'primary_attending'
    check (assignment_type in ('primary_attending', 'consulting', 'rounding')),
  status text not null default 'active' check (status in ('active', 'concluded')),
  assigned_at timestamptz not null default now(),
  concluded_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.doctor_assignments is
  'The patients a clinician is responsible for. A patient is on the doctor''s dashboard because there is an assignment row, and the row says who is responsible and for what.';

create index doctor_assignments_doctor_idx
  on public.doctor_assignments (tenant_id, doctor_id, status, assigned_at desc);
create index doctor_assignments_patient_idx
  on public.doctor_assignments (patient_id, status);

create trigger doctor_assignments_set_updated_at before update on public.doctor_assignments
  for each row execute function nodex.tg_set_updated_at();

create trigger doctor_assignments_retain before delete on public.doctor_assignments
  for each row execute function nodex.tg_block_mutation();

create or replace function nodex.tg_doctor_assignment_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if new.status <> 'active' then
      raise exception using
        message = 'NODEX: a new assignment is active',
        errcode = '22000';
    end if;
    return new;
  end if;

  if new.tenant_id is distinct from old.tenant_id
     or new.doctor_id is distinct from old.doctor_id
     or new.patient_id is distinct from old.patient_id
     or new.assignment_type is distinct from old.assignment_type then
    raise exception using
      message = 'NODEX: the identity of an assignment is immutable',
      errcode = '42501';
  end if;

  if new.status = 'concluded' and old.status <> 'concluded' then
    new.concluded_at := coalesce(new.concluded_at, now());
  end if;
  if new.status = 'active' then
    new.concluded_at := null;
  end if;

  return new;
end;
$$;

create trigger doctor_assignments_guard
  before insert or update on public.doctor_assignments
  for each row execute function nodex.tg_doctor_assignment_guard();

alter table public.doctor_assignments enable row level security;
alter table public.doctor_assignments force row level security;

-- A clinician sees their own patients. The people who are accountable for
-- the whole hospital see all of them, which is the same rule the other
-- modules use for their own records.
create policy doctor_assignments_select_own on public.doctor_assignments
  for select to authenticated
  using (
    doctor_id = auth.uid()
    or nodex.has_permission(tenant_id, 'clinical.dashboard.read')
  );
create policy doctor_assignments_insert_writer on public.doctor_assignments
  for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'clinical.dashboard.manage'));
create policy doctor_assignments_update_writer on public.doctor_assignments
  for update to authenticated
  using (nodex.has_permission(tenant_id, 'clinical.dashboard.manage'))
  with check (nodex.has_permission(tenant_id, 'clinical.dashboard.manage'));

insert into public.permissions
  (key, display_name, description, module_code, risk_tier, requires_online)
values
  ('clinical.dashboard.read', 'Read the clinical dashboard',
   'View the patients a clinician is responsible for across the hospital.',
   'M04', 'standard', false),
  ('clinical.dashboard.manage', 'Manage clinical assignments',
   'Assign and conclude the responsibility a clinician has for a patient.',
   'M04', 'standard', false)
on conflict (key) do nothing;

insert into public.role_permissions (role_key, permission_key)
values
  ('hospital_super_admin', 'clinical.dashboard.read'),
  ('hospital_super_admin', 'clinical.dashboard.manage'),
  ('medical_officer',      'clinical.dashboard.read'),
  ('medical_officer',      'clinical.dashboard.manage'),
  ('nursing_staff',        'clinical.dashboard.read')
on conflict do nothing;
