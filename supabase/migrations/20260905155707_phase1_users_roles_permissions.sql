-- NODEX Phase 1: application identity, RBAC catalogue and memberships.
--
-- app_users mirrors auth.users with clinical/HR attributes. auth.users remains
-- the authentication record of truth; app_users is the authorization subject.

create table public.app_users (
  id                uuid primary key references auth.users (id) on delete restrict,
  primary_tenant_id uuid references public.tenants (id) on delete restrict,
  employee_code     text,
  full_name         text not null check (length(btrim(full_name)) > 0),
  display_name      text,
  email             text,
  phone             text,
  designation       text,
  registration_no   text,
  status            text not null default 'active'
                    check (status in ('invited', 'active', 'suspended', 'deactivated')),
  locale            text not null default 'en',
  avatar_path       text,
  last_login_at     timestamptz,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

comment on table public.app_users is
  'Application identity for an authenticated principal. Authorization subject for memberships and RLS.';
comment on column public.app_users.registration_no is
  'Professional registration/licence number for clinician roles (module 08 credentials).';

create unique index app_users_employee_code_key
  on public.app_users (primary_tenant_id, employee_code)
  where employee_code is not null;

-- Role catalogue. Roles are global definitions; scope is applied per membership.
create table public.roles (
  key            text primary key
                 check (key ~ '^[a-z][a-z0-9_]{2,49}$'),
  display_name   text not null,
  description    text,
  role_class     text not null
                 check (role_class in ('administrative', 'clinical', 'nursing',
                                       'diagnostic', 'pharmacy', 'financial',
                                       'patient', 'service', 'audit')),
  is_privileged  boolean not null default false,
  offline_capable boolean not null default true,
  created_at     timestamptz not null default now()
);

comment on table public.roles is
  'Role catalogue from the specification role matrix. is_privileged roles require online revalidation for high-risk actions.';
comment on column public.roles.offline_capable is
  'False when the role may not operate from a cached offline authorization snapshot.';

create table public.permissions (
  key           text primary key
                check (key ~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$'),
  display_name  text not null,
  description   text,
  module_code   text,
  risk_tier     text not null default 'standard'
                check (risk_tier in ('standard', 'elevated', 'high_risk')),
  requires_online boolean not null default false,
  created_at    timestamptz not null default now()
);

comment on table public.permissions is
  'Fine-grained permission catalogue. requires_online marks actions that must not execute from an offline snapshot.';
comment on column public.permissions.key is
  'Dotted permission identifier, e.g. patient.read, prescription.finalize.';

create table public.role_permissions (
  role_key       text not null references public.roles (key) on delete cascade,
  permission_key text not null references public.permissions (key) on delete cascade,
  created_at     timestamptz not null default now(),
  primary key (role_key, permission_key)
);

comment on table public.role_permissions is
  'Role to permission grants. Resolved into the offline authorization snapshot at sign-in.';

-- Membership binds a user to a role within a tenant and optional narrower scope.
create table public.memberships (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references public.tenants (id) on delete restrict,
  user_id        uuid not null references public.app_users (id) on delete restrict,
  role_key       text not null references public.roles (key) on delete restrict,
  facility_id    uuid references public.facilities (id) on delete cascade,
  department_id  uuid references public.departments (id) on delete cascade,
  ward_id        uuid references public.wards (id) on delete cascade,
  status         text not null default 'active'
                 check (status in ('active', 'suspended', 'revoked')),
  valid_from     timestamptz not null default now(),
  valid_until    timestamptz,
  granted_by     uuid references public.app_users (id) on delete set null,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  constraint memberships_scope_chain_ck check (
    (department_id is null or facility_id is not null)
    and (ward_id is null or facility_id is not null)
  ),
  constraint memberships_validity_ck check (
    valid_until is null or valid_until > valid_from
  )
);

comment on table public.memberships is
  'Tenant/role assignment with optional facility, department and ward narrowing. Basis for both RLS and PowerSync sync stream scope.';

create unique index memberships_unique_scope
  on public.memberships (
    tenant_id,
    user_id,
    role_key,
    coalesce(facility_id, '00000000-0000-0000-0000-000000000000'::uuid),
    coalesce(department_id, '00000000-0000-0000-0000-000000000000'::uuid),
    coalesce(ward_id, '00000000-0000-0000-0000-000000000000'::uuid)
  );

create index memberships_user_active_idx
  on public.memberships (user_id, tenant_id)
  where status = 'active';
create index memberships_tenant_idx     on public.memberships (tenant_id);
create index memberships_facility_idx   on public.memberships (facility_id);
create index memberships_department_idx on public.memberships (department_id);
create index memberships_ward_idx       on public.memberships (ward_id);

create trigger app_users_set_updated_at
  before update on public.app_users
  for each row execute function nodex.tg_set_updated_at();

create trigger memberships_set_updated_at
  before update on public.memberships
  for each row execute function nodex.tg_set_updated_at();

alter table public.departments
  add constraint departments_head_user_id_fkey
  foreign key (head_user_id) references public.app_users (id) on delete set null;
