-- NODEX Phase 1 RLS, part 2: devices, audit, sync bookkeeping and AI governance.
--
-- Write access to audit, clinical events, mutation ledger and AI execution
-- records is intentionally absent for `authenticated`. Those rows are created by
-- the authorized backend mutation path (service_role), which is never shipped in
-- an Android build. Clients read them; they do not author them directly.

-- ---------------------------------------------------------------------------
-- Devices
-- ---------------------------------------------------------------------------

create policy devices_select_own on public.devices
  for select to authenticated
  using (assigned_user_id = auth.uid());

create policy devices_select_admin on public.devices
  for select to authenticated
  using (nodex.has_permission(tenant_id, 'device.administer'));

create policy devices_write_admin on public.devices
  for all to authenticated
  using (nodex.has_permission(tenant_id, 'device.administer'))
  with check (nodex.has_permission(tenant_id, 'device.administer'));

-- ---------------------------------------------------------------------------
-- Authorization snapshots
-- ---------------------------------------------------------------------------

-- A device may read the snapshots issued to its own user so the client can
-- verify its cached snapshot digest and expiry. Issuance is backend-only.
create policy authorization_snapshots_select_own on public.authorization_snapshots
  for select to authenticated
  using (user_id = auth.uid());

create policy authorization_snapshots_select_admin on public.authorization_snapshots
  for select to authenticated
  using (nodex.has_permission(tenant_id, 'device.administer'));

-- ---------------------------------------------------------------------------
-- Audit and clinical events (read-only for clients)
-- ---------------------------------------------------------------------------

create policy audit_events_select_auditor on public.audit_events
  for select to authenticated
  using (nodex.has_permission(tenant_id, 'audit.read'));

-- Actors may always review their own action history.
create policy audit_events_select_own_actions on public.audit_events
  for select to authenticated
  using (actor_id = auth.uid());

create policy clinical_events_select_scope on public.clinical_events
  for select to authenticated
  using (nodex.has_permission(tenant_id, 'clinical_event.read'));

-- ---------------------------------------------------------------------------
-- Sync bookkeeping
-- ---------------------------------------------------------------------------

-- A user sees the mutations they authored; sync administrators see the tenant
-- queue so that failed synchronization is visible and recoverable.
create policy mutations_select_own on public.mutations
  for select to authenticated
  using (user_id = auth.uid());

create policy mutations_select_admin on public.mutations
  for select to authenticated
  using (nodex.has_permission(tenant_id, 'sync.administer'));

create policy mutation_attempts_select_scope on public.mutation_attempts
  for select to authenticated
  using (
    exists (
      select 1
      from public.mutations m
      where m.id = public.mutation_attempts.mutation_id
        and (m.user_id = auth.uid()
             or nodex.has_permission(m.tenant_id, 'sync.administer'))
    )
  );

create policy conflict_records_select_scope on public.conflict_records
  for select to authenticated
  using (nodex.has_permission(tenant_id, 'sync.administer')
         or nodex.has_permission(tenant_id, 'conflict.review'));

-- Conflict resolution is a human decision recorded by a reviewer.
create policy conflict_records_update_reviewer on public.conflict_records
  for update to authenticated
  using (nodex.has_permission(tenant_id, 'conflict.review'))
  with check (nodex.has_permission(tenant_id, 'conflict.review'));

create policy sync_cursors_select_own on public.sync_cursors
  for select to authenticated
  using (
    exists (
      select 1
      from public.devices d
      where d.id = public.sync_cursors.device_id
        and (d.assigned_user_id = auth.uid()
             or nodex.has_permission(d.tenant_id, 'sync.administer'))
    )
  );

-- ---------------------------------------------------------------------------
-- AI governance configuration
-- ---------------------------------------------------------------------------

-- Registry, routing and profiles are global configuration. They contain no PHI
-- and no credentials; provider secrets live outside the client entirely.
create policy ai_model_registry_select_all on public.ai_model_registry
  for select to authenticated using (true);

create policy ai_routing_policies_select_all on public.ai_routing_policies
  for select to authenticated using (true);

create policy ai_deployment_profiles_select_all on public.ai_deployment_profiles
  for select to authenticated using (true);

-- ---------------------------------------------------------------------------
-- AI execution records
-- ---------------------------------------------------------------------------

create policy ai_requests_select_own on public.ai_requests
  for select to authenticated
  using (requested_by = auth.uid());

create policy ai_requests_select_governance on public.ai_requests
  for select to authenticated
  using (nodex.has_permission(tenant_id, 'ai_governance.read'));

create policy ai_responses_select_scope on public.ai_responses
  for select to authenticated
  using (
    exists (
      select 1
      from public.ai_requests r
      where r.id = public.ai_responses.request_id
        and (r.requested_by = auth.uid()
             or nodex.has_permission(r.tenant_id, 'ai_governance.read'))
    )
  );

create policy ai_safety_decisions_select_scope on public.ai_safety_decisions
  for select to authenticated
  using (
    exists (
      select 1
      from public.ai_requests r
      where r.id = public.ai_safety_decisions.request_id
        and (r.requested_by = auth.uid()
             or nodex.has_permission(r.tenant_id, 'ai_governance.read'))
    )
  );

create policy ai_reviews_select_scope on public.ai_reviews
  for select to authenticated
  using (reviewer_id = auth.uid()
         or nodex.has_permission(tenant_id, 'ai_governance.read'));

-- Reviewers record their own human-in-the-loop decision. The review row is
-- immutable afterwards (append-only trigger), so a decision cannot be rewritten.
create policy ai_reviews_insert_reviewer on public.ai_reviews
  for insert to authenticated
  with check (reviewer_id = auth.uid()
              and nodex.has_permission(tenant_id, 'ai_output.review'));
