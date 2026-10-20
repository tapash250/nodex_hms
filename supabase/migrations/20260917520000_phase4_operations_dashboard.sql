-- Module 02: Operations Dashboard (DB1)
--
-- The flow of patients through a department: how many are waiting, how long
-- they have waited, and where the queue is building up. The figures are
-- written by the operational systems and read here, so the dashboard is a
-- reading of what happened rather than a second opinion of it.

create table public.operational_department_metrics (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  facility_id uuid not null references public.facilities(id) on delete restrict,
  department_id uuid not null references public.departments(id) on delete restrict,
  metric_timestamp timestamptz not null,
  registrations integer not null default 0 check (registrations >= 0),
  waiting_count integer not null default 0 check (waiting_count >= 0),
  completed_count integer not null default 0 check (completed_count >= 0),
  average_wait_minutes numeric(8,2) check (average_wait_minutes is null or average_wait_minutes >= 0),
  bottleneck text check (bottleneck is null or length(btrim(bottleneck)) > 0),
  created_at timestamptz not null default now(),
  unique (department_id, metric_timestamp)
);

comment on table public.operational_department_metrics is
  'Department flow at a moment in time: how many patients registered, how many are waiting, how long the wait has been and where the queue is building. A reading of operations, not a second record of them.';

create index operational_metrics_department_idx
  on public.operational_department_metrics (tenant_id, department_id, metric_timestamp desc);
create index operational_metrics_facility_idx
  on public.operational_department_metrics (tenant_id, facility_id, metric_timestamp desc);

create trigger operational_metrics_set_updated_at
  before update on public.operational_department_metrics
  for each row execute function nodex.tg_set_updated_at();

-- A reading of a moment is not edited: a later reading replaces it by being
-- a later reading, and a corrected figure is written with its own timestamp.
create trigger operational_metrics_retain
  before delete on public.operational_department_metrics
  for each row execute function nodex.tg_block_mutation();

alter table public.operational_department_metrics enable row level security;
alter table public.operational_department_metrics force row level security;

create policy operational_metrics_select_reader
  on public.operational_department_metrics
  for select to authenticated
  using (nodex.has_permission(tenant_id, 'operations.read'));
create policy operational_metrics_insert_writer
  on public.operational_department_metrics
  for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'operations.manage'));
create policy operational_metrics_update_writer
  on public.operational_department_metrics
  for update to authenticated
  using (nodex.has_permission(tenant_id, 'operations.manage'))
  with check (nodex.has_permission(tenant_id, 'operations.manage'));

insert into public.permissions
  (key, display_name, description, module_code, risk_tier, requires_online)
values
  ('operations.read', 'Read operational flow',
   'View department waiting times, registration counts and bottlenecks.',
   'M02', 'standard', false),
  ('operations.manage', 'Record operational flow',
   'Write the departmental flow figures the operations dashboard reads.',
   'M02', 'standard', false)
on conflict (key) do nothing;

insert into public.role_permissions (role_key, permission_key)
values
  ('hospital_super_admin', 'operations.read'),
  ('hospital_super_admin', 'operations.manage'),
  ('medical_officer',      'operations.read'),
  ('nursing_staff',        'operations.read'),
  ('billing_accounts',     'operations.read'),
  ('auditor',              'operations.read')
on conflict do nothing;
