-- Module 03: Performance Analytics Dashboard (DB2)
--
-- The clinical quality indicators: how long a laboratory test took, how long
-- a theatre took between cases, how many patients came back within thirty
-- days. Each indicator is a reading against a baseline, and the baseline
-- travels with it — an indicator without its baseline is a number, not a
-- judgement.
--
-- Access is narrow on purpose. These figures describe how the hospital is
-- performing, so they are read by the people accountable for it rather than
-- by everybody.

create table public.clinical_performance_indices (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  indicator_code text not null check (length(btrim(indicator_code)) > 0),
  indicator_name text not null check (length(btrim(indicator_name)) > 0),
  category text not null default 'clinical_quality'
    check (category in ('laboratory', 'surgery', 'readmission', 'clinical_quality')),
  period_start timestamptz not null,
  period_end timestamptz not null,
  value numeric(14,4) not null,
  baseline_mean numeric(14,4),
  baseline_stddev numeric(14,4),
  sample_size integer not null default 0 check (sample_size >= 0),
  lower_is_better boolean not null default true,
  created_at timestamptz not null default now(),
  unique (tenant_id, indicator_code, period_start)
);

comment on table public.clinical_performance_indices is
  'A performance indicator for a period, read against its own baseline. A reading of a period is written once: a corrected figure is a later period, not an edit of the old one.';

create index performance_indices_tenant_idx
  on public.clinical_performance_indices (tenant_id, category, period_start desc);
create index performance_indices_code_idx
  on public.clinical_performance_indices (tenant_id, indicator_code, period_end desc);

create trigger performance_indices_retain
  before delete on public.clinical_performance_indices
  for each row execute function nodex.tg_block_mutation();

alter table public.clinical_performance_indices enable row level security;
alter table public.clinical_performance_indices force row level security;

create policy performance_indices_select_reader
  on public.clinical_performance_indices
  for select to authenticated
  using (nodex.has_permission(tenant_id, 'performance.read'));
create policy performance_indices_insert_writer
  on public.clinical_performance_indices
  for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'performance.manage'));

insert into public.permissions
  (key, display_name, description, module_code, risk_tier, requires_online)
values
  ('performance.read', 'Read performance indicators',
   'View clinical quality indicators such as turnaround times and readmissions against their baseline.',
   'M03', 'standard', false),
  ('performance.manage', 'Record performance indicators',
   'Write the clinical quality indicators the performance dashboard reads.',
   'M03', 'standard', false)
on conflict (key) do nothing;

insert into public.role_permissions (role_key, permission_key)
values
  ('hospital_super_admin', 'performance.read'),
  ('hospital_super_admin', 'performance.manage'),
  ('medical_officer',      'performance.read'),
  ('nursing_staff',        'performance.read'),
  ('auditor',              'performance.read')
on conflict do nothing;
