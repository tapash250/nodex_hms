-- NODEX Phase 1: enable RLS on every table and define tenant-scoped policies.
--
-- Tier 3 boundary. Even if the Android client is decompiled or modified, these
-- policies remain responsible for enforcing cloud access policy.
--
-- Convention: writes to clinical/audit/sync/AI-execution tables go through the
-- authorized backend path (service_role), never directly from the device.

alter table public.tenants                 enable row level security;
alter table public.facilities              enable row level security;
alter table public.departments             enable row level security;
alter table public.wards                   enable row level security;
alter table public.app_users               enable row level security;
alter table public.roles                   enable row level security;
alter table public.permissions             enable row level security;
alter table public.role_permissions        enable row level security;
alter table public.memberships             enable row level security;
alter table public.devices                 enable row level security;
alter table public.authorization_snapshots enable row level security;
alter table public.audit_events            enable row level security;
alter table public.clinical_events         enable row level security;
alter table public.mutations               enable row level security;
alter table public.mutation_attempts       enable row level security;
alter table public.conflict_records        enable row level security;
alter table public.sync_cursors            enable row level security;
alter table public.ai_model_registry       enable row level security;
alter table public.ai_routing_policies     enable row level security;
alter table public.ai_deployment_profiles  enable row level security;
alter table public.ai_requests             enable row level security;
alter table public.ai_responses            enable row level security;
alter table public.ai_safety_decisions     enable row level security;
alter table public.ai_reviews              enable row level security;

-- Force RLS for table owners too, so a compromised owner connection cannot
-- bypass tenant isolation. service_role is BYPASSRLS and remains unaffected.
alter table public.tenants                 force row level security;
alter table public.facilities              force row level security;
alter table public.departments             force row level security;
alter table public.wards                   force row level security;
alter table public.app_users               force row level security;
alter table public.memberships             force row level security;
alter table public.devices                 force row level security;
alter table public.authorization_snapshots force row level security;
alter table public.audit_events            force row level security;
alter table public.clinical_events         force row level security;

-- ---------------------------------------------------------------------------
-- Tenancy hierarchy: read within membership scope, administer with permission.
-- ---------------------------------------------------------------------------

create policy tenants_select_member on public.tenants
  for select to authenticated
  using (nodex.has_tenant_access(id));

create policy tenants_update_admin on public.tenants
  for update to authenticated
  using (nodex.has_permission(id, 'tenant.administer'))
  with check (nodex.has_permission(id, 'tenant.administer'));

create policy facilities_select_scope on public.facilities
  for select to authenticated
  using (nodex.has_facility_access(tenant_id, id));

create policy facilities_write_admin on public.facilities
  for all to authenticated
  using (nodex.has_permission(tenant_id, 'facility.administer'))
  with check (nodex.has_permission(tenant_id, 'facility.administer'));

create policy departments_select_scope on public.departments
  for select to authenticated
  using (nodex.has_tenant_access(tenant_id)
         and nodex.has_facility_access(tenant_id, facility_id));

create policy departments_write_admin on public.departments
  for all to authenticated
  using (nodex.has_permission(tenant_id, 'department.administer'))
  with check (nodex.has_permission(tenant_id, 'department.administer'));

create policy wards_select_scope on public.wards
  for select to authenticated
  using (nodex.has_tenant_access(tenant_id)
         and nodex.has_facility_access(tenant_id, facility_id));

create policy wards_write_admin on public.wards
  for all to authenticated
  using (nodex.has_permission(tenant_id, 'ward.administer'))
  with check (nodex.has_permission(tenant_id, 'ward.administer'));

-- ---------------------------------------------------------------------------
-- Identity and RBAC
-- ---------------------------------------------------------------------------

-- A user always sees their own record; directory visibility requires a shared
-- tenant plus the staff directory read permission (module 08/42).
create policy app_users_select_self on public.app_users
  for select to authenticated
  using (id = auth.uid());

create policy app_users_select_directory on public.app_users
  for select to authenticated
  using (
    exists (
      select 1
      from public.memberships viewer
      join public.memberships subject
        on subject.tenant_id = viewer.tenant_id
      where viewer.user_id = auth.uid()
        and viewer.status = 'active'
        and subject.user_id = public.app_users.id
        and subject.status = 'active'
        and nodex.has_permission(viewer.tenant_id, 'staff_directory.read')
    )
  );

-- Self-service profile edits only. Status, tenant binding and registration
-- number are administrative fields guarded by the trigger below.
create policy app_users_update_self on public.app_users
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- Role and permission catalogues are readable by any authenticated principal so
-- the client can render role-aware navigation; they are configuration, not PHI.
create policy roles_select_all on public.roles
  for select to authenticated using (true);

create policy permissions_select_all on public.permissions
  for select to authenticated using (true);

create policy role_permissions_select_all on public.role_permissions
  for select to authenticated using (true);

-- Memberships: see your own, plus all memberships in tenants where you may
-- administer users. Granting a membership requires membership.grant.
create policy memberships_select_self on public.memberships
  for select to authenticated
  using (user_id = auth.uid());

create policy memberships_select_admin on public.memberships
  for select to authenticated
  using (nodex.has_permission(tenant_id, 'membership.read'));

create policy memberships_insert_admin on public.memberships
  for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'membership.grant'));

create policy memberships_update_admin on public.memberships
  for update to authenticated
  using (nodex.has_permission(tenant_id, 'membership.grant'))
  with check (nodex.has_permission(tenant_id, 'membership.grant'));
