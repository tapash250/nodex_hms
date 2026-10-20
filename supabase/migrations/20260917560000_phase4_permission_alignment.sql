-- Permission alignment: the server enforces the keys the client already uses
--
-- Three permissions were granted to roles but never enforced by the thing they
-- were named for:
--
--   * triage.read   the client gates the emergency and triage surface on it,
--                   while the server gated the triage table on patient.read —
--                   a wider set than the client shows, so a clinician with
--                   patient.read but no triage.read was reading rows the
--                   client would not have opened;
--   * report.read   granted to the roles that read reports, while the report
--                   tables were gated on analytics.read — a different key, so
--                   the permission that says "you may read reports" was not
--                   the one that let you;
--   * portal.access granted to the patient role, but the portal's replication
--                   bucket was scoped by the link alone, so the permission
--                   said nothing.
--
-- This migration makes the server enforce the same keys the client checks. It
-- is a separate migration rather than an edit because the earlier files may
-- already be applied, and a later migration is the only way to change a
-- policy a database has already recorded.

-- ---------------------------------------------------------------------------
-- Triage: the client's gate, on the server
-- ---------------------------------------------------------------------------

-- Triage acuity is clinical. The client has always hidden the surface from
-- anyone without triage.read, and the server now agrees: reading a triage
-- assessment requires the permission the client's gate names.
drop policy if exists triage_select_member on public.triage_assessments;
create policy triage_select_member on public.triage_assessments
  for select to authenticated
  using (nodex.has_permission(tenant_id, 'triage.read'));

-- ---------------------------------------------------------------------------
-- The staff directory had no writer at all
-- ---------------------------------------------------------------------------

-- staff_directory.administer was seeded and used by the policies that let a
-- practitioner profile be registered, amended and put on call — and it was
-- granted to no role, so the directory could be read by a clinician and
-- written by nobody. The holders are the two roles that manage the
-- workforce, which is the same desk.
insert into public.role_permissions (role_key, permission_key)
values
  ('hospital_super_admin', 'staff_directory.administer'),
  ('nursing_staff',        'staff_directory.administer')
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- Reports: both report keys are honoured
-- ---------------------------------------------------------------------------

-- report.read is the clinical and financial reporting key; analytics.read is
-- the broader operational key. Either one opens the report tables, and the
-- client's gate is one of them.
drop policy if exists analytics_definition_select_member on public.analytics_report_definitions;
drop policy if exists analytics_rollup_select_member on public.analytics_rollups;
drop policy if exists analytics_run_select_member on public.analytics_report_runs;
drop policy if exists analytics_export_select_member on public.analytics_exports;

create policy analytics_definition_select_member on public.analytics_report_definitions
  for select to authenticated
  using (
    nodex.has_permission(tenant_id, 'analytics.read')
    or nodex.has_permission(tenant_id, 'report.read')
  );
create policy analytics_rollup_select_member on public.analytics_rollups
  for select to authenticated
  using (
    nodex.has_permission(tenant_id, 'analytics.read')
    or nodex.has_permission(tenant_id, 'report.read')
  );
create policy analytics_run_select_member on public.analytics_report_runs
  for select to authenticated
  using (
    nodex.has_permission(tenant_id, 'analytics.read')
    or nodex.has_permission(tenant_id, 'report.read')
  );
create policy analytics_export_select_member on public.analytics_exports
  for select to authenticated
  using (
    nodex.has_permission(tenant_id, 'analytics.read')
    or nodex.has_permission(tenant_id, 'report.read')
  );
