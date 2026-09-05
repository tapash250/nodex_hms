-- NODEX Phase 1: tenancy, facility and organisational hierarchy.
-- Tenant is the top-level isolation boundary for every clinical record.

create table public.tenants (
  id            uuid primary key default gen_random_uuid(),
  slug          text not null unique
                check (slug ~ '^[a-z0-9]([a-z0-9-]{1,61}[a-z0-9])$'),
  display_name  text not null check (length(btrim(display_name)) > 0),
  legal_name    text,
  country_code  char(2),
  timezone      text not null default 'UTC',
  locale        text not null default 'en',
  status        text not null default 'active'
                check (status in ('active', 'suspended', 'archived')),
  settings      jsonb not null default '{}'::jsonb,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

comment on table public.tenants is
  'Top-level isolation boundary. Every clinical, operational and financial row is tenant-scoped.';

create table public.facilities (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references public.tenants (id) on delete restrict,
  code          text not null check (length(btrim(code)) > 0),
  display_name  text not null check (length(btrim(display_name)) > 0),
  facility_type text not null default 'hospital'
                check (facility_type in ('hospital', 'clinic', 'diagnostic_centre',
                                         'pharmacy', 'blood_bank', 'other')),
  timezone      text,
  address       jsonb not null default '{}'::jsonb,
  status        text not null default 'active'
                check (status in ('active', 'inactive', 'archived')),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (tenant_id, code)
);

comment on table public.facilities is
  'Physical site within a tenant. Second-level scope for device replication and role assignment.';

create table public.departments (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references public.tenants (id) on delete restrict,
  facility_id   uuid not null references public.facilities (id) on delete restrict,
  code          text not null check (length(btrim(code)) > 0),
  display_name  text not null check (length(btrim(display_name)) > 0),
  specialty     text,
  head_user_id  uuid,
  status        text not null default 'active'
                check (status in ('active', 'inactive', 'archived')),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (tenant_id, facility_id, code)
);

comment on table public.departments is
  'Clinical or administrative department. Drives department-scoped sync streams (module 12).';

create table public.wards (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references public.tenants (id) on delete restrict,
  facility_id    uuid not null references public.facilities (id) on delete restrict,
  department_id  uuid references public.departments (id) on delete set null,
  code           text not null check (length(btrim(code)) > 0),
  display_name   text not null check (length(btrim(display_name)) > 0),
  ward_type      text not null default 'general'
                 check (ward_type in ('general', 'private', 'icu', 'hdu', 'emergency',
                                      'maternity', 'paediatric', 'isolation', 'other')),
  floor_label    text,
  bed_capacity   integer not null default 0 check (bed_capacity >= 0),
  status         text not null default 'active'
                 check (status in ('active', 'inactive', 'archived')),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  unique (tenant_id, facility_id, code)
);

comment on table public.wards is
  'Inpatient ward. Assignment scope for nursing roles (modules 06, 11).';

-- Indexes for tenant-scoped reads and sync stream parameter lookups.
create index facilities_tenant_id_idx    on public.facilities (tenant_id);
create index departments_tenant_id_idx   on public.departments (tenant_id);
create index departments_facility_id_idx on public.departments (facility_id);
create index wards_tenant_id_idx         on public.wards (tenant_id);
create index wards_facility_id_idx       on public.wards (facility_id);
create index wards_department_id_idx     on public.wards (department_id);

create trigger tenants_set_updated_at
  before update on public.tenants
  for each row execute function nodex.tg_set_updated_at();

create trigger facilities_set_updated_at
  before update on public.facilities
  for each row execute function nodex.tg_set_updated_at();

create trigger departments_set_updated_at
  before update on public.departments
  for each row execute function nodex.tg_set_updated_at();

create trigger wards_set_updated_at
  before update on public.wards
  for each row execute function nodex.tg_set_updated_at();
