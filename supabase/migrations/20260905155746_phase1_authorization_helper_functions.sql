-- NODEX Phase 1: SECURITY DEFINER authorization helpers.
--
-- These are the single source of truth consumed by every RLS policy. They are
-- SECURITY DEFINER with a locked empty search_path so that membership lookups
-- performed inside a policy do not re-enter RLS and recurse.

create or replace function nodex.has_tenant_access(p_tenant_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.memberships m
    where m.user_id = auth.uid()
      and m.tenant_id = p_tenant_id
      and m.status = 'active'
      and m.valid_from <= now()
      and (m.valid_until is null or m.valid_until > now())
  );
$$;

comment on function nodex.has_tenant_access(uuid) is
  'True when the caller holds any active, unexpired membership in the tenant.';

create or replace function nodex.accessible_tenant_ids()
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select distinct m.tenant_id
  from public.memberships m
  where m.user_id = auth.uid()
    and m.status = 'active'
    and m.valid_from <= now()
    and (m.valid_until is null or m.valid_until > now());
$$;

comment on function nodex.accessible_tenant_ids() is
  'Tenant ids the caller may read. Used by policies on tenant-scoped catalogue tables.';

create or replace function nodex.has_permission(p_tenant_id uuid, p_permission_key text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.memberships m
    join public.role_permissions rp on rp.role_key = m.role_key
    where m.user_id = auth.uid()
      and m.tenant_id = p_tenant_id
      and m.status = 'active'
      and m.valid_from <= now()
      and (m.valid_until is null or m.valid_until > now())
      and rp.permission_key = p_permission_key
  );
$$;

comment on function nodex.has_permission(uuid, text) is
  'Authoritative server-side permission check. Client-side route guards are UX only.';

create or replace function nodex.has_role(p_tenant_id uuid, p_role_key text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.memberships m
    where m.user_id = auth.uid()
      and m.tenant_id = p_tenant_id
      and m.role_key = p_role_key
      and m.status = 'active'
      and m.valid_from <= now()
      and (m.valid_until is null or m.valid_until > now())
  );
$$;

comment on function nodex.has_role(uuid, text) is
  'True when the caller holds the named role anywhere in the tenant.';

-- Facility / department / ward scope resolution.
-- A membership with a NULL narrower scope is tenant-wide for that role, which is
-- how Hospital Super Admin and Auditor roles are represented.

create or replace function nodex.has_facility_access(p_tenant_id uuid, p_facility_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.memberships m
    where m.user_id = auth.uid()
      and m.tenant_id = p_tenant_id
      and m.status = 'active'
      and m.valid_from <= now()
      and (m.valid_until is null or m.valid_until > now())
      and (m.facility_id is null or m.facility_id = p_facility_id)
  );
$$;

comment on function nodex.has_facility_access(uuid, uuid) is
  'True when the caller has a tenant-wide membership or one bound to the given facility.';

create or replace function nodex.has_department_access(p_tenant_id uuid, p_department_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.memberships m
    where m.user_id = auth.uid()
      and m.tenant_id = p_tenant_id
      and m.status = 'active'
      and m.valid_from <= now()
      and (m.valid_until is null or m.valid_until > now())
      and (m.department_id is null or m.department_id = p_department_id)
  );
$$;

comment on function nodex.has_department_access(uuid, uuid) is
  'True when the caller has a department-agnostic membership or one bound to the given department.';

create or replace function nodex.has_ward_access(p_tenant_id uuid, p_ward_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.memberships m
    where m.user_id = auth.uid()
      and m.tenant_id = p_tenant_id
      and m.status = 'active'
      and m.valid_from <= now()
      and (m.valid_until is null or m.valid_until > now())
      and (m.ward_id is null or m.ward_id = p_ward_id)
  );
$$;

comment on function nodex.has_ward_access(uuid, uuid) is
  'True when the caller has a ward-agnostic membership or one bound to the given ward.';

create or replace function nodex.is_tenant_admin(p_tenant_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select nodex.has_role(p_tenant_id, 'hospital_super_admin');
$$;

comment on function nodex.is_tenant_admin(uuid) is
  'Convenience predicate for enterprise administration policies.';

grant execute on function
  nodex.current_user_id(),
  nodex.is_service_role(),
  nodex.has_tenant_access(uuid),
  nodex.accessible_tenant_ids(),
  nodex.has_permission(uuid, text),
  nodex.has_role(uuid, text),
  nodex.has_facility_access(uuid, uuid),
  nodex.has_department_access(uuid, uuid),
  nodex.has_ward_access(uuid, uuid),
  nodex.is_tenant_admin(uuid)
to authenticated;
