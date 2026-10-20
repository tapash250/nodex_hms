-- Module 05: Patient Personal Portal
--
-- A patient seeing their own record: their appointments, their finalized
-- results, the medicines they are taking. The link between a portal account
-- and a patient is a row, so the link can be granted, audited and revoked.
--
-- Two boundaries matter here.
--
-- First, the portal reads through its own replication bucket, which selects
-- only the rows belonging to the linked patient. The direct API surface is
-- closed to the patient role by permission: no clinical read permission is
-- granted to it, so the bucket is the only path.
--
-- Second, only finalized results are shown. A preliminary result is a
-- work in progress — it may be corrected, and a patient reading a value that
-- later changes is worse off than a patient waiting for the final one.

create table public.patient_portal_links (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  patient_id uuid not null references public.patients(id) on delete cascade,
  portal_user_id uuid not null references public.app_users(id) on delete cascade,
  created_by uuid not null references public.app_users(id) on delete restrict,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  unique (tenant_id, patient_id),
  unique (tenant_id, portal_user_id)
);

comment on table public.patient_portal_links is
  'The link between a portal account and the patient whose record it may read. A link is a row so that it can be granted, audited and revoked; a revoked link keeps its row because the fact that access was given is itself a fact.';

create index patient_portal_links_user_idx
  on public.patient_portal_links (tenant_id, portal_user_id);

create trigger patient_portal_links_retain before delete on public.patient_portal_links
  for each row execute function nodex.tg_block_mutation();

alter table public.patient_portal_links enable row level security;
alter table public.patient_portal_links force row level security;

-- A patient reads their own link. Staff manage links, which is a separate
-- permission from reading them.
create policy patient_portal_links_select_self on public.patient_portal_links
  for select to authenticated
  using (
    portal_user_id = auth.uid()
    or nodex.has_permission(tenant_id, 'portal.manage')
  );
create policy patient_portal_links_insert_writer on public.patient_portal_links
  for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'portal.manage'));
create policy patient_portal_links_update_writer on public.patient_portal_links
  for update to authenticated
  using (nodex.has_permission(tenant_id, 'portal.manage'))
  with check (nodex.has_permission(tenant_id, 'portal.manage'));

insert into public.permissions
  (key, display_name, description, module_code, risk_tier, requires_online)
values
  ('portal.access', 'Use the patient portal',
   'Read your own appointments, finalized results and active medicines through the patient portal.',
   'M05', 'standard', false),
  ('portal.manage', 'Manage patient portal access',
   'Link a portal account to a patient record, and revoke that link.',
   'M05', 'high', false)
on conflict (key) do nothing;

insert into public.role_permissions (role_key, permission_key)
values
  ('patient',           'portal.access'),
  ('hospital_super_admin', 'portal.manage')
on conflict do nothing;
