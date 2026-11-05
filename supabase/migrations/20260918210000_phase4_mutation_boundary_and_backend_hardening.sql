-- NODEX Phase 4 follow-up: backend write boundary and backend hardening.
--
-- The client audit found that `authenticated` still held INSERT/UPDATE/DELETE
-- on clinical tables, so a compromised or buggy client could bypass the
-- mutation handler, its column validators, the idempotency ledger and the audit
-- trail with a direct PostgREST call. It also found four backend defects that
-- the handler alone could not close:
--
--   * ledger, row apply and audit were three separate requests, so a crash
--     between them left a clinical write with no audit row, or an audit row for
--     a write that rolled back;
--   * a retry that reused an idempotency key with different contents was
--     reported as already applied instead of rejected;
--   * the snapshot issuance RPC could not revoke the prior snapshot because the
--     revocation guard only admitted service_role;
--   * signed consent evidence was only partly frozen.
--
-- This migration makes the backend path the only write path and makes its
-- three records atomic.

-- ---------------------------------------------------------------------------
-- 1. The authorized mutation path.
--
-- A transaction-local GUC marks the connection as executing an authorized
-- mutation. The handler reaches this path through a SECURITY DEFINER RPC that
-- is executable only by service_role. The RPC installs the caller's identity
-- into the transaction-local JWT claims, so auth.uid() and every helper built
-- on it see the real clinician, not the service account. The patient-scope
-- trigger therefore still runs in full; it only knows that this is not a
-- direct client write.
-- ---------------------------------------------------------------------------

create or replace function nodex.is_authorized_mutation_path()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(current_setting('nodex.authorized_mutation', true), '') = 'on';
$$;

comment on function nodex.is_authorized_mutation_path() is
  'True only inside public.apply_authorized_mutation, which is executable by service_role alone.';

-- The tables the handler may write. Kept in the database so the atomic RPC
-- cannot be pointed at an arbitrary relation even if the TypeScript registry
-- and this migration drift. The static configuration test compares the two.
create table if not exists nodex.authorized_mutation_tables (
  table_name text primary key
);

comment on table nodex.authorized_mutation_tables is
  'Allowlist for public.apply_authorized_mutation. Mirrors WRITABLE_TABLES in the mutation-handler.';

insert into nodex.authorized_mutation_tables (table_name)
values
  ('patients'), ('patient_allergies'), ('patient_merge_history'),
  ('clinical_encounters'), ('clinical_problems'), ('encounter_scribe_drafts'),
  ('encounter_amendments'), ('lab_orders'), ('lab_specimens'), ('lab_results'),
  ('prescriptions'), ('prescription_items'), ('pharmacy_dispenses'),
  ('medication_administrations'), ('appointments'), ('beds'),
  ('bed_assignments'), ('discharges'), ('invoices'), ('invoice_lines'),
  ('payments'), ('patient_accounts'), ('ledger_entries'),
  ('payment_allocations'), ('refunds'), ('stock_items'), ('stock_locations'),
  ('stock_batches'), ('stock_movements'), ('triage_assessments'), ('er_visits'),
  ('icu_beds'), ('icu_vitals'), ('icu_nursing_handover'), ('ventilator_events'),
  ('transfusion_requests'), ('blood_units'), ('transfusions'), ('ot_bookings'),
  ('ot_preop_assessments'), ('ot_anesthesia_records'), ('ot_procedure_logs'),
  ('ot_postop_records'), ('imaging_orders'), ('imaging_studies'),
  ('imaging_reports'), ('physio_sessions'), ('physio_exercise_plans'),
  ('physio_recovery_notes'), ('diet_assessments'), ('diet_meal_plans'),
  ('diet_meal_plan_days'), ('diet_intake_logs'), ('tele_consultations'),
  ('tele_vitals_overlays'), ('tele_consultation_archives'),
  ('discharge_clearances'), ('discharge_medication_reconciliations'),
  ('discharge_medication_reconciliation_items'), ('discharge_settlements'),
  ('ward_rooms'), ('ward_vitals'), ('ward_handovers'), ('ward_tasks'),
  ('hospital_tasks'), ('form_templates'), ('form_responses'),
  ('operational_department_metrics'), ('clinical_performance_indices'),
  ('doctor_assignments'), ('patient_portal_links'), ('clinical_threads'),
  ('clinical_messages'), ('clinical_attachments'), ('work_items'),
  ('it_tickets'), ('hr_employees'), ('hr_leave_requests'), ('hr_holidays'),
  ('hr_payroll_periods'), ('hr_payslips'), ('staff_shifts'),
  ('duty_allocations'), ('attendance_logs'), ('departments'),
  ('directory_contacts'), ('calendar_events'), ('ambulances'),
  ('ambulance_duty_assignments'), ('ambulance_dispatches'),
  ('ambulance_tracking_pings'), ('biomedical_assets'),
  ('biomedical_breakdown_tickets'), ('biomedical_maintenance_records'),
  ('waste_categories'), ('waste_generation_logs'),
  ('waste_disposal_certificates'), ('insurance_payers'),
  ('insurance_policies'), ('pre_authorisation_requests'), ('insurance_claims'),
  ('consent_templates'), ('consent_records'), ('document_vault_documents'),
  ('statutory_birth_records'), ('statutory_death_records'),
  ('statutory_mlc_intimations'), ('statutory_record_amendments'),
  ('compliance_audits'), ('incident_reports'), ('clinical_indicators'),
  ('feedback_surveys'), ('feedback_complaints'), ('complaint_routing_events'),
  ('ward_visiting_windows'), ('visitor_registrations'), ('visitor_passes'),
  ('visitor_badge_prints'), ('analytics_report_definitions'),
  ('analytics_rollups'), ('analytics_report_runs'), ('analytics_exports'),
  ('settings_profiles'), ('branding_assets'), ('department_hierarchies'),
  ('billing_tariffs'), ('ai_routing_profiles'), ('ai_model_registry'),
  ('practitioner_profiles'), ('practitioner_on_calls'),
  ('discharge_ai_summaries')
on conflict (table_name) do nothing;

-- ---------------------------------------------------------------------------
-- 2. Close direct PostgREST DML on every table the handler owns.
--
-- SELECT stays: RLS still governs reads and PowerSync still replicates. What
-- disappears is the ability to write a clinical, ledger or audit row without
-- the handler's validators, ledger, audit and patient-scope trigger.
-- ---------------------------------------------------------------------------

do $$
declare
  t text;
begin
  for t in
    select table_name from nodex.authorized_mutation_tables
    union
    select unnest(array[
      'audit_events', 'clinical_events', 'mutations',
      'mutation_attempts', 'conflict_records'
    ])
  loop
    execute format(
      'revoke insert, update, delete on public.%I from public, anon, authenticated',
      t
    );
  end loop;
end;
$$;

-- Append-only ledgers additionally refuse UPDATE/DELETE for every non-owner
-- role. The trigger already blocks them; removing the privilege keeps the
-- boundary legible in the grant table as well as at runtime.
revoke update, delete on public.audit_events from public, anon, authenticated;
revoke update, delete on public.clinical_events from public, anon, authenticated;
revoke update, delete on public.operational_department_metrics from public, anon, authenticated;

-- The row apply must still run under RLS. A SECURITY DEFINER RPC owned by the
-- migration role would bypass every policy, including the messaging
-- participant check and the AI governance permission. A dedicated, non-login
-- writer role is a member of `authenticated`, so every policy written for that
-- role still applies, but the role holds DML only on the allowlist. The main
-- RPC owns the transaction; this role owns only the row apply.
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'nodex_mutation_writer') then
    execute 'create role nodex_mutation_writer nologin';
  end if;
end;
$$;

-- PostgreSQL requires the current role to be a member of the new owner before
-- ALTER FUNCTION ... OWNER TO. The migration role is the one that creates and
-- later maintains the helper, so it keeps this membership; the writer role is
-- NOLOGIN and holds no privilege the migration role does not already have.
do $$
begin
  execute format('grant nodex_mutation_writer to %I', current_user);
end;
$$;

alter role nodex_mutation_writer inherit;
grant authenticated to nodex_mutation_writer;
grant usage on schema public, nodex to nodex_mutation_writer;
grant select on nodex.authorized_mutation_tables to nodex_mutation_writer;

do $$
declare
  t text;
begin
  for t in select table_name from nodex.authorized_mutation_tables loop
    execute format(
      'grant insert, update on public.%I to nodex_mutation_writer',
      t
    );
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. The row apply, executed under RLS.
-- ---------------------------------------------------------------------------

create or replace function nodex.apply_authorized_mutation_row(
  p_table     text,
  p_operation text,
  p_row_id    uuid,
  p_data      jsonb
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row  jsonb := p_data || jsonb_build_object('id', p_row_id);
  v_cols text;
  v_sets text;
  v_rows integer := 0;
begin
  if coalesce(current_setting('nodex.authorized_mutation', true), '') <> 'on' then
    raise exception 'NODEX: the authorized mutation row helper is backend-only'
      using errcode = '42501';
  end if;

  if p_operation not in ('upsert', 'patch') then
    raise exception 'NODEX: unsupported authorized mutation operation %', p_operation
      using errcode = '22023';
  end if;

  if not exists (
    select 1 from nodex.authorized_mutation_tables t where t.table_name = p_table
  ) then
    raise exception 'NODEX: % has no authorized mutation path', p_table
      using errcode = '42501';
  end if;

  select
    coalesce(string_agg(format('%I', a.attname), ', ' order by a.attnum), ''),
    coalesce(
      string_agg(
        format('%I = r.%I', a.attname, a.attname),
        ', ' order by a.attnum
      ),
      ''
    )
    into v_cols, v_sets
    from pg_attribute a
   where a.attrelid = to_regclass(format('public.%I', p_table))
     and a.attnum > 0
     and not a.attisdropped
     and a.attname <> 'id'
     and (p_data ? a.attname);

  if p_operation = 'upsert' then
    if v_cols = '' then
      execute format(
        'insert into public.%I (id) values ($1) on conflict (id) do nothing',
        p_table
      ) using p_row_id;
    else
      execute format(
        'insert into public.%I (id, %s) '
        'select r.id, %s from jsonb_populate_record(null::public.%I, $1) r '
        'on conflict (id) do update set %s',
        p_table, v_cols, v_cols, p_table, v_sets
      ) using v_row;
    end if;
    v_rows := 1;
  else
    if v_sets = '' then
      v_rows := 0;
    else
      execute format(
        'update public.%I t set %s '
        'from (select %s from jsonb_populate_record(null::public.%I, $1)) r '
        'where t.id = $2',
        p_table, v_sets, v_cols, p_table
      ) using v_row, p_row_id;
      get diagnostics v_rows = row_count;
    end if;
  end if;

  return v_rows;
end;
$$;

comment on function nodex.apply_authorized_mutation_row(text, text, uuid, jsonb) is
  'Applies one authorized row as nodex_mutation_writer, so RLS policies still apply. Called only by public.apply_authorized_mutation.';

-- Grants are made while the migration role still owns the helper. After the
-- ownership transfer below, the migration role no longer has grant option on
-- it, so the order matters.
revoke all on function nodex.apply_authorized_mutation_row(text, text, uuid, jsonb)
  from public, anon, authenticated;
grant execute on function nodex.apply_authorized_mutation_row(text, text, uuid, jsonb)
  to service_role;

-- The main RPC is SECURITY DEFINER owned by the migration role. Grant that
-- owner execute explicitly, while the migration role still owns the helper, so
-- the call does not depend on superuser bypass.
do $$
begin
  execute format(
    'grant execute on function nodex.apply_authorized_mutation_row(text, text, uuid, jsonb) to %I',
    current_user
  );
end;
$$;

-- The helper runs as the writer role. That role is not the table owner and
-- does not have BYPASSRLS, so RLS, its policies and every trigger still run.
--
-- PostgreSQL requires the new owner to hold CREATE on the function's schema
-- for the transfer. Grant it for the transfer, then remove it: ownership needs
-- USAGE, not CREATE.
grant create on schema nodex to nodex_mutation_writer;
alter function nodex.apply_authorized_mutation_row(text, text, uuid, jsonb)
  owner to nodex_mutation_writer;
revoke create on schema nodex from nodex_mutation_writer;

-- ---------------------------------------------------------------------------
-- 4. Atomic ledger + apply + audit.
--
-- The handler computes payload_digest and the audit action; this function owns
-- the transaction. Every failure inside the apply rolls the apply back. A
-- failure writing the ledger or the audit row rolls the whole function back,
-- so a committed clinical write always has both records, and a rolled-back
-- write never leaves either behind.
-- ---------------------------------------------------------------------------

create or replace function public.apply_authorized_mutation(
  p_actor    uuid,
  p_mutation jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_table       text := p_mutation ->> 'table';
  v_operation   text := p_mutation ->> 'operation';
  v_mutation_id uuid := (p_mutation ->> 'id')::uuid;
  v_row_id      uuid := (p_mutation ->> 'row_id')::uuid;
  v_key         text := p_mutation ->> 'idempotency_key';
  v_tenant      uuid := (p_mutation ->> 'tenant_id')::uuid;
  v_device      uuid := nullif(p_mutation ->> 'device_id', '')::uuid;
  v_digest      text := p_mutation ->> 'payload_digest';
  v_action      text := p_mutation ->> 'audit_action';
  v_origin      text := p_mutation ->> 'origin';
  v_data        jsonb := p_mutation -> 'data';
  v_rows        integer := 0;
  v_existing    record;
  v_message     text;
  v_sqlstate    text;
  v_class       text;
  v_rejection   text;
  v_patient     uuid;
  v_encounter   uuid;
begin
  -- Only the handler's service-role client may call this function. A client
  -- that somehow obtains its name still cannot execute it.
  if not nodex.is_service_role() then
    raise exception 'NODEX: the authorized mutation path is backend-only'
      using errcode = '42501';
  end if;

  if p_actor is null then
    raise exception 'NODEX: an authenticated actor is required'
      using errcode = '28000';
  end if;

  if v_table is null or v_operation not in ('upsert', 'patch')
     or v_mutation_id is null or v_row_id is null or v_key is null
     or v_tenant is null or v_digest is null or length(v_digest) <> 64
     or v_action is null or v_origin not in ('online', 'offline')
     or v_data is null or jsonb_typeof(v_data) <> 'object' then
    raise exception 'NODEX: malformed authorized mutation'
      using errcode = '22023';
  end if;

  if not exists (
    select 1 from nodex.authorized_mutation_tables t where t.table_name = v_table
  ) then
    raise exception 'NODEX: % has no authorized mutation path', v_table
      using errcode = '42501';
  end if;

  -- A mutation without a device is not attributable. The handler rejects it
  -- before calling this function; the check is repeated here because this
  -- function is the transaction that records provenance.
  if v_device is null then
    raise exception 'NODEX: an enrolled device is required for a mutation'
      using errcode = '42501';
  end if;

  perform 1
     from public.app_users u
    where u.id = p_actor
      and u.status = 'active'
    for share;
  if not found then
    raise exception 'NODEX: the account is not active'
      using errcode = '42501';
  end if;

  perform 1
     from public.memberships m
    where m.user_id = p_actor
      and m.tenant_id = v_tenant
      and m.status = 'active'
      and m.valid_from <= clock_timestamp()
      and (m.valid_until is null or m.valid_until > clock_timestamp())
    for share;
  if not found then
    raise exception 'NODEX: no active, unexpired membership in this tenant'
      using errcode = '42501';
  end if;

  perform 1
     from public.devices d
    where d.id = v_device
      and d.tenant_id = v_tenant
      and d.assigned_user_id = p_actor
      and d.status = 'active'
      and d.revoked_at is null
      and d.wipe_requested_at is null
    for share;
  if not found then
    raise exception 'NODEX: the device is not authorized for this tenant or user'
      using errcode = '42501';
  end if;

  -- The patient-scope trigger reads auth.uid() and request.headers. Install
  -- the actor and device into transaction-local claims so the trigger makes
  -- the same decision it would make for a direct request by this clinician.
  perform set_config('request.jwt.claim.sub', p_actor::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', p_actor, 'role', 'authenticated')::text,
    true
  );
  perform set_config('nodex.authorized_mutation', 'on', true);
  perform set_config(
    'request.headers',
    jsonb_build_object('x-device-id', v_device::text)::text,
    true
  );

  -- Idempotency. A key reused with different contents is not a retry; it is
  -- either a client bug or an attempt to mask a second write behind a key the
  -- ledger already trusts. It is rejected, never reported as already applied.
  select m.id, m.status, m.payload_digest
    into v_existing
    from public.mutations m
   where m.tenant_id = v_tenant
     and m.idempotency_key = v_key
   for update;

  if found then
    if v_existing.payload_digest is distinct from v_digest then
      return jsonb_build_object(
        'outcome', 'rejected',
        'rejection_class', 'validation',
        'detail', 'idempotency_key reused with a different payload'
      );
    end if;
    if v_existing.status = 'applied' then
      return jsonb_build_object(
        'outcome', 'already_applied',
        'detail', 'mutation already applied'
      );
    end if;
    return jsonb_build_object(
      'outcome', 'rejected',
      'rejection_class', 'validation',
      'detail', format('original mutation is %s', v_existing.status)
    );
  end if;

  insert into public.mutations (
    id, tenant_id, user_id, device_id, operation, resource_type, resource_id,
    idempotency_key, client_created_at, origin, payload_digest, status
  )
  values (
    v_mutation_id, v_tenant, p_actor, v_device, v_operation, v_table, v_row_id,
    v_key, (p_mutation ->> 'client_created_at')::timestamptz, v_origin,
    v_digest, 'received'
  )
  on conflict (tenant_id, idempotency_key) do nothing;

  get diagnostics v_rows = row_count;
  if v_rows = 0 then
    -- A concurrent request inserted the same key between the SELECT and the
    -- INSERT. Only the idempotency constraint reaches this branch; a unique
    -- violation on the target table is handled by the apply block below.
    select m.id, m.status, m.payload_digest
      into v_existing
      from public.mutations m
     where m.tenant_id = v_tenant
       and m.idempotency_key = v_key
     for update;

    if v_existing.payload_digest is distinct from v_digest then
      return jsonb_build_object(
        'outcome', 'rejected',
        'rejection_class', 'validation',
        'detail', 'idempotency_key reused with a different payload'
      );
    end if;
    if v_existing.status = 'applied' then
      return jsonb_build_object(
        'outcome', 'already_applied',
        'detail', 'mutation already applied'
      );
    end if;
    return jsonb_build_object(
      'outcome', 'rejected',
      'rejection_class', 'validation',
      'detail', format('original mutation is %s', v_existing.status)
    );
  end if;

  begin
    v_rows := nodex.apply_authorized_mutation_row(
      v_table, v_operation, v_row_id, v_data
    );
  exception when others then
    get stacked diagnostics v_message = message_text, v_sqlstate = returned_sqlstate;
    v_class := case
      when v_sqlstate in ('42501', '28000') or position('NODEX:' in v_message) > 0
        then 'forbidden'
      when v_sqlstate in ('23505', '23P01') then 'conflict'
      when v_sqlstate in ('23503', '23514', '22P02', '22000') then 'validation'
      else 'internal'
    end;
    v_rejection := case
      when v_class = 'forbidden' then 'authorization'
      when v_class in ('conflict', 'validation') then v_class
      else 'internal'
    end;

    update public.mutations
       set status = 'rejected',
           rejection_class = v_rejection,
           rejection_detail = v_message,
           applied_at = null,
           attempt_count = attempt_count + 1
     where id = v_mutation_id;

    v_patient := nullif(v_data ->> 'patient_id', '')::uuid;
    v_encounter := nullif(v_data ->> 'encounter_id', '')::uuid;

    insert into public.audit_events (
      tenant_id, actor_id, device_id, action, resource_type, resource_id,
      patient_id, encounter_id, mutation_id, origin, outcome, risk_tier, reason
    )
    values (
      v_tenant, p_actor, v_device, v_action, v_table, v_row_id,
      v_patient, v_encounter, v_mutation_id, v_origin, 'failed',
      'standard', v_message
    );

    return jsonb_build_object(
      'outcome', 'rejected',
      'rejection_class', v_rejection,
      'detail', format('apply failed: %s', v_message)
    );
  end;

  if v_rows = 0 then
    update public.mutations
       set status = 'rejected',
           rejection_class = 'validation',
           rejection_detail = 'no row with that id is visible to this account',
           applied_at = null,
           attempt_count = attempt_count + 1
     where id = v_mutation_id;

    v_patient := nullif(v_data ->> 'patient_id', '')::uuid;
    v_encounter := nullif(v_data ->> 'encounter_id', '')::uuid;

    insert into public.audit_events (
      tenant_id, actor_id, device_id, action, resource_type, resource_id,
      patient_id, encounter_id, mutation_id, origin, outcome, risk_tier, reason
    )
    values (
      v_tenant, p_actor, v_device, v_action, v_table, v_row_id,
      v_patient, v_encounter, v_mutation_id, v_origin, 'rejected',
      'standard', 'no row with that id is visible to this account'
    );

    return jsonb_build_object(
      'outcome', 'rejected',
      'rejection_class', 'validation',
      'detail', 'no row with that id is visible to this account'
    );
  end if;

  update public.mutations
     set status = 'applied',
         applied_at = now(),
         attempt_count = attempt_count + 1,
         rejection_class = null,
         rejection_detail = null
   where id = v_mutation_id;

  v_patient := nullif(v_data ->> 'patient_id', '')::uuid;
  v_encounter := nullif(v_data ->> 'encounter_id', '')::uuid;

  -- The audit row is in the same transaction as the write. If this insert
  -- fails, the apply and the ledger transition roll back together.
  insert into public.audit_events (
    tenant_id, actor_id, device_id, action, resource_type, resource_id,
    patient_id, encounter_id, mutation_id, origin, outcome, risk_tier
  )
  values (
    v_tenant, p_actor, v_device, v_action, v_table, v_row_id,
    v_patient, v_encounter, v_mutation_id, v_origin, 'succeeded', 'standard'
  );

  return jsonb_build_object('outcome', 'applied');
end;
$$;

comment on function public.apply_authorized_mutation(uuid, jsonb) is
  'Atomic authorized mutation: idempotency ledger, row apply and audit row commit or roll back together. Backend-only.';

revoke all on function public.apply_authorized_mutation(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.apply_authorized_mutation(uuid, jsonb) to service_role;

-- ---------------------------------------------------------------------------
-- 5. Snapshot re-issuance.
--
-- The issuance RPC is SECURITY DEFINER, so the revocation UPDATE runs as the
-- function owner. The old guard required nodex.is_service_role(), which reads
-- the JWT role and is still 'authenticated' inside the RPC. Permit the
-- function-owner path while continuing to refuse a direct client UPDATE.
-- ---------------------------------------------------------------------------

create or replace function nodex.tg_snapshot_revocation_only()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if not (
    nodex.is_service_role()
    or current_user not in ('authenticated', 'anon', 'authenticated_user')
  ) then
    raise exception
      'NODEX: authorization snapshots may only be revoked through the authorized backend path'
      using errcode = '42501';
  end if;

  if old.revoked_at is not null then
    raise exception 'NODEX: authorization snapshot % is already revoked', old.id
      using errcode = '22000';
  end if;

  if new.revoked_at is null then
    raise exception 'NODEX: the only permitted update is setting revoked_at'
      using errcode = '22000';
  end if;

  -- Immutable projection of the issued snapshot.
  new.id                  := old.id;
  new.tenant_id           := old.tenant_id;
  new.user_id             := old.user_id;
  new.device_id           := old.device_id;
  new.snapshot_revision   := old.snapshot_revision;
  new.roles               := old.roles;
  new.permissions         := old.permissions;
  new.facility_ids        := old.facility_ids;
  new.department_ids      := old.department_ids;
  new.ward_ids            := old.ward_ids;
  new.offline_permissions := old.offline_permissions;
  new.payload_digest      := old.payload_digest;
  new.issued_at           := old.issued_at;
  new.expires_at          := old.expires_at;
  new.issued_session_id   := old.issued_session_id;
  new.created_at          := old.created_at;

  return new;
end;
$$;

comment on function nodex.tg_snapshot_revocation_only() is
  'BEFORE UPDATE guard on authorization_snapshots: permits one-way revocation from the backend path (service_role or a SECURITY DEFINER owner) and freezes all issued fields.';

-- ---------------------------------------------------------------------------
-- 6. Signed consent immutability.
--
-- The original guard froze the signature, signer and document. It did not
-- freeze the biometric attestation, the witness, the scope columns or the
-- expiry, so a signed record could be edited while still claiming the same
-- signature. This replacement freezes every column except the revocation
-- fields.
-- ---------------------------------------------------------------------------

create or replace function nodex.tg_consent_record_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.status in ('declined', 'revoked') then
    raise exception using
      message = 'NODEX: a closed consent record is immutable',
      errcode = '42501';
  end if;

  if old.status = 'signed' or old.signed_at is not null then
    if new.status <> 'revoked' then
      raise exception using
        message = 'NODEX: a signed consent is revoked or left alone',
        errcode = '42501';
    end if;
    if new.id is distinct from old.id
      or new.tenant_id is distinct from old.tenant_id
      or new.patient_id is distinct from old.patient_id
      or new.facility_id is distinct from old.facility_id
      or new.encounter_id is distinct from old.encounter_id
      or new.template_id is distinct from old.template_id
      or new.procedure_text is distinct from old.procedure_text
      or new.signer_name is distinct from old.signer_name
      or new.signer_relationship is distinct from old.signer_relationship
      or new.signature_sha256 is distinct from old.signature_sha256
      or new.signature_point_count is distinct from old.signature_point_count
      or new.signature_captured_at is distinct from old.signature_captured_at
      or new.biometric_method is distinct from old.biometric_method
      or new.biometric_template_sha256 is distinct from old.biometric_template_sha256
      or new.biometric_captured_at is distinct from old.biometric_captured_at
      or new.biometric_quality is distinct from old.biometric_quality
      or new.witnessed_by is distinct from old.witnessed_by
      or new.witnessed_at is distinct from old.witnessed_at
      or new.document_id is distinct from old.document_id
      or new.signed_at is distinct from old.signed_at
      or new.expires_at is distinct from old.expires_at
      or new.declined_at is distinct from old.declined_at
      or new.decline_reason is distinct from old.decline_reason
      or new.created_by is distinct from old.created_by
      or new.created_at is distinct from old.created_at then
      raise exception using
        message = 'NODEX: what a signed consent attests is immutable',
        errcode = '42501';
    end if;
    return new;
  end if;

  if new.status = old.status then
    return new;
  end if;

  if (old.status = 'drafted'
      and new.status in ('awaiting_signature', 'signed', 'declined'))
    or (old.status = 'awaiting_signature'
        and new.status in ('signed', 'declined')) then
    return new;
  end if;

  raise exception using
    message = 'NODEX: a consent record may not skip a stage',
    errcode = '42501';
end;
$$;

comment on function nodex.tg_consent_record_guard() is
  'BEFORE UPDATE guard on consent_records: signed clinical content and all signature evidence are immutable; only revocation may follow.';

-- ---------------------------------------------------------------------------
-- 7. Messaging participant and attachment boundaries.
--
-- The thread access list is the authorization boundary. Growing it was
-- unchecked, so a participant could add any UUID and grant that account read
-- access to the discussion. Every added participant must now hold an active,
-- unexpired membership in the thread's tenant with a messaging permission.
-- ---------------------------------------------------------------------------

-- A participant is only meaningful if they can already read or write the
-- discussion. Validate the user id and the membership in one place so the
-- INSERT and UPDATE paths cannot drift.
create or replace function nodex.assert_thread_participant(
  p_tenant uuid,
  p_user   text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_user !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception using
      message = 'NODEX: a participant must be a user id',
      errcode = '42501';
  end if;

  perform 1
    from public.memberships m
    join public.role_permissions rp on rp.role_key = m.role_key
   where m.user_id = p_user::uuid
     and m.tenant_id = p_tenant
     and m.status = 'active'
     and m.valid_from <= clock_timestamp()
     and (m.valid_until is null or m.valid_until > clock_timestamp())
     and rp.permission_key in ('messaging.read', 'messaging.send')
   for share of m;
  if not found then
    raise exception using
      message = format(
        'NODEX: participant %s has no active messaging membership in this tenant',
        p_user
      ),
      errcode = '42501';
  end if;
end;
$$;

comment on function nodex.assert_thread_participant(uuid, text) is
  'Raises 42501 unless the user holds an active, unexpired membership in the tenant with a messaging permission.';

revoke all on function nodex.assert_thread_participant(uuid, text)
  from public, anon, authenticated;

create or replace function nodex.tg_clinical_thread_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_participant text;
begin
  if tg_op = 'INSERT' then
    if not (new.participants @> jsonb_build_array(auth.uid()::text)) then
      raise exception using
        message = 'NODEX: the author of a thread is one of its participants',
        errcode = '42501';
    end if;

    -- A new thread has no old participant list, so every name in it is a
    -- grant of read access and must be validated.
    for v_participant in
      select value from jsonb_array_elements_text(new.participants)
    loop
      perform nodex.assert_thread_participant(new.tenant_id, v_participant);
    end loop;

    return new;
  end if;

  if new.tenant_id is distinct from old.tenant_id
     or new.created_by is distinct from old.created_by then
    raise exception using
      message = 'NODEX: the identity of a thread is immutable',
      errcode = '42501';
  end if;

  -- The participant list can grow but never shrink: a person who was in a
  -- clinical discussion stays in it, because what they were told cannot be
  -- un-told. Containment, not length, is the test: replacing one participant
  -- with another keeps the length but still removes a person.
  if not (new.participants @> old.participants) then
    raise exception using
      message = 'NODEX: a participant cannot be removed from a thread',
      errcode = '42501';
  end if;

  -- Every newly added participant must be an active member of this tenant
  -- whose role grants a messaging permission. Without this, a participant
  -- could hand the thread to an arbitrary account, including one in another
  -- tenant.
  for v_participant in
    select value
      from jsonb_array_elements_text(new.participants)
     where not old.participants @> jsonb_build_array(value)
  loop
    perform nodex.assert_thread_participant(new.tenant_id, v_participant);
  end loop;

  if new.status = 'archived' and old.status <> 'archived' then
    new.last_message_at := coalesce(new.last_message_at, now());
  end if;

  return new;
end;
$$;

comment on function nodex.tg_clinical_thread_guard() is
  'BEFORE INSERT/UPDATE guard on clinical_threads: every participant must hold an active messaging membership, and participants are never removed.';

create policy clinical_attachments_insert_participant
  on public.clinical_attachments
  for insert to authenticated
  with check (
    nodex.has_permission(clinical_attachments.tenant_id, 'messaging.send')
    and exists (
      select 1
      from public.clinical_messages m
      join public.clinical_threads t on t.id = m.thread_id
      where m.id = clinical_attachments.message_id
        and m.tenant_id = clinical_attachments.tenant_id
        and t.tenant_id = clinical_attachments.tenant_id
        and t.participants @> jsonb_build_array(auth.uid()::text)
    )
  );

comment on policy clinical_attachments_insert_participant on public.clinical_attachments is
  'Only an active participant of the message thread may attach a file to it.';

-- ---------------------------------------------------------------------------
-- 8. Membership audit.
--
-- Role and status changes are privilege changes. They were not audited, so a
-- grant or revocation left no trace in the audit envelope. This trigger writes
-- one row per change; the actor is the authenticated administrator, or NULL
-- for a migration/service operation.
-- ---------------------------------------------------------------------------

create or replace function nodex.tg_membership_audit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_action text;
begin
  v_action := case
    when tg_op = 'INSERT' then 'membership.granted'
    when new.status = 'revoked' and old.status <> 'revoked' then 'membership.revoked'
    when new.status = 'suspended' and old.status <> 'suspended' then 'membership.suspended'
    when new.status = 'active' and old.status <> 'active' then 'membership.reactivated'
    else 'membership.updated'
  end;

  insert into public.audit_events (
    tenant_id, actor_id, action, resource_type, resource_id,
    origin, outcome, risk_tier, metadata
  )
  values (
    new.tenant_id,
    auth.uid(),
    v_action,
    'membership',
    new.id,
    'backend',
    'succeeded',
    'elevated',
    jsonb_build_object(
      'user_id', new.user_id,
      'role_key', new.role_key,
      'status', new.status,
      'facility_id', new.facility_id,
      'department_id', new.department_id,
      'ward_id', new.ward_id,
      'valid_from', new.valid_from,
      'valid_until', new.valid_until,
      'previous_status', case when tg_op = 'UPDATE' then old.status else null end,
      'previous_role_key', case when tg_op = 'UPDATE' then old.role_key else null end
    )
  );

  return new;
end;
$$;

comment on function nodex.tg_membership_audit() is
  'AFTER INSERT/UPDATE trigger on memberships: every grant, revocation, suspension and scope change writes an audit row.';

drop trigger if exists memberships_audit on public.memberships;
create trigger memberships_audit
  after insert or update on public.memberships
  for each row execute function nodex.tg_membership_audit();

-- ---------------------------------------------------------------------------
-- 9. clinical_events: documented, not silently empty.
--
-- The table exists and is replicated, but no trigger or handler path emits
-- rows. Leaving that implicit invites a dashboard to read an empty stream as
-- "no clinical activity". State the contract instead: the CRUD projections and
-- audit_events are authoritative until emission is implemented.
-- ---------------------------------------------------------------------------

comment on table public.clinical_events is
  'Reserved clinical event stream. No trigger currently emits rows; the CRUD projections and audit_events are authoritative. Do not treat an empty stream as evidence of no activity.';

comment on column public.clinical_events.sequence_no is
  'Monotonic per-aggregate sequence for the future event emitter. Gaps are not permitted once emission is enabled.';
