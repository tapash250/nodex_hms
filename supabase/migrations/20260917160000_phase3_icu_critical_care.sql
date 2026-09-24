-- NODEX Phase 3, Module 06: ICU & Critical Care Monitoring.
--
-- ICU bed management, vitals monitoring, ventilator management, nursing handover.
-- Continuous vitals streaming with gap detection; nursing handover immutable record.
-- RLS uses membership-derived permissions; FKs target app_users.

create table public.icu_beds (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  bed_id uuid not null references public.beds(id) on delete restrict,
  ventilator_id uuid references public.stock_items(id) on delete set null,
  status text not null default 'available' check (status in ('available','occupied','maintenance','isolation')),
  current_patient_id uuid references public.patients(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (bed_id)
);
create index icu_beds_tenant_idx on public.icu_beds(tenant_id, status);

create table public.icu_vitals (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  patient_id uuid not null references public.patients(id) on delete restrict,
  icu_bed_id uuid not null references public.icu_beds(id) on delete restrict,
  recorded_by uuid not null references public.app_users(id) on delete restrict,
  recorded_at timestamptz not null default now(),
  heart_rate int,
  spo2 int,
  respiratory_rate int,
  temperature_celsius numeric(4,1),
  systolic_bp int,
  diastolic_bp int,
  map int,
  cvp numeric(4,1),
  etco2 int,
  gcs_total int check (gcs_total between 3 and 15),
  gcs_eye int check (gcs_eye between 1 and 4),
  gcs_verbal int check (gcs_verbal between 1 and 5),
  gcs_motor int check (gcs_motor between 1 and 6),
  fi_o2 numeric(4,1),
  peep int,
  tidal_volume int,
  respiratory_mode text,
  created_at timestamptz not null default now()
);
create index icu_vitals_patient_idx on public.icu_vitals(tenant_id, patient_id, recorded_at desc);
create index icu_vitals_bed_idx on public.icu_vitals(icu_bed_id, recorded_at desc);

create table public.icu_nursing_handover (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  patient_id uuid not null references public.patients(id) on delete restrict,
  icu_bed_id uuid not null references public.icu_beds(id) on delete restrict,
  outgoing_nurse uuid not null references public.app_users(id) on delete restrict,
  incoming_nurse uuid not null references public.app_users(id) on delete restrict,
  handover_time timestamptz not null default now(),
  summary text,
  concerns jsonb not null default '[]'::jsonb,
  plan jsonb not null default '[]'::jsonb,
  alerts jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now()
);
create index nursing_handover_patient_idx on public.icu_nursing_handover(tenant_id, patient_id, handover_time desc);
create index nursing_handover_nurse_idx on public.icu_nursing_handover(outgoing_nurse, incoming_nurse, handover_time desc);

create table public.ventilator_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  patient_id uuid not null references public.patients(id) on delete restrict,
  icu_bed_id uuid not null references public.icu_beds(id) on delete restrict,
  ventilator_id uuid not null references public.stock_items(id) on delete restrict,
  event_type text not null check (event_type in ('connected','disconnected','mode_change','alarm','weaning','extubation')),
  mode text,
  settings jsonb not null default '{}'::jsonb,
  recorded_by uuid not null references public.app_users(id) on delete restrict,
  recorded_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);
create index ventilator_events_patient_idx on public.ventilator_events(patient_id, recorded_at desc);
create index ventilator_events_bed_idx on public.ventilator_events(icu_bed_id, recorded_at desc);

create trigger icu_beds_set_updated_at before update on public.icu_beds for each row execute function nodex.tg_set_updated_at();

alter table public.icu_beds enable row level security;
alter table public.icu_beds force row level security;
alter table public.icu_vitals enable row level security;
alter table public.icu_vitals force row level security;
alter table public.icu_nursing_handover enable row level security;
alter table public.icu_nursing_handover force row level security;
alter table public.ventilator_events enable row level security;
alter table public.ventilator_events force row level security;

create policy icu_beds_select_member on public.icu_beds for select to authenticated using (nodex.has_permission(tenant_id,'patient.read'));
create policy icu_beds_insert_admin on public.icu_beds for insert to authenticated with check (nodex.has_permission(tenant_id,'icu.bed.assign'));
create policy icu_beds_update_admin on public.icu_beds for update to authenticated using (nodex.has_permission(tenant_id,'icu.bed.assign')) with check (nodex.has_permission(tenant_id,'icu.bed.assign'));

create policy icu_vitals_select_member on public.icu_vitals for select to authenticated using (nodex.has_permission(tenant_id,'patient.read'));
create policy icu_vitals_insert_writer on public.icu_vitals for insert to authenticated with check (nodex.has_permission(tenant_id,'icu.vitals.record'));
create policy icu_vitals_update_writer on public.icu_vitals for update to authenticated using (nodex.has_permission(tenant_id,'icu.vitals.record')) with check (nodex.has_permission(tenant_id,'icu.vitals.record'));

create policy nursing_handover_select_member on public.icu_nursing_handover for select to authenticated using (nodex.has_permission(tenant_id,'patient.read'));
create policy nursing_handover_insert_writer on public.icu_nursing_handover for insert to authenticated with check (nodex.has_permission(tenant_id,'icu.handover.record'));
create policy nursing_handover_update_writer on public.icu_nursing_handover for update to authenticated using (nodex.has_permission(tenant_id,'icu.handover.record')) with check (nodex.has_permission(tenant_id,'icu.handover.record'));

create policy ventilator_events_select_member on public.ventilator_events for select to authenticated using (nodex.has_permission(tenant_id,'patient.read'));
create policy ventilator_events_insert_writer on public.ventilator_events for insert to authenticated with check (nodex.has_permission(tenant_id,'ventilator.event.record'));
create policy ventilator_events_update_writer on public.ventilator_events for update to authenticated using (nodex.has_permission(tenant_id,'ventilator.event.record')) with check (nodex.has_permission(tenant_id,'ventilator.event.record'));