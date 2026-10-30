-- NODEX Phase 4 follow-up: transactional patient-assignment authorization.
--
-- The mutation handler already validates columns, records an idempotency ledger
-- row and writes an audit event. It did not prove that the caller was entitled
-- to the patient named by the row. RLS is tenant-wide for most clinical tables:
-- a receptionist and a doctor with an active membership could both update the
-- same patient, and a child row could name a parent in another tenant because a
-- foreign key does not enforce tenant equality.
--
-- This migration closes that gap at the database boundary:
--
--   1. A BEFORE INSERT OR UPDATE trigger runs in the same transaction as the
--      write. Authorization and mutation cannot be separated by a TOCTOU race.
--   2. The trigger locks the membership, role grants, device, patient and
--      encounter rows FOR SHARE before deciding. A concurrent revocation,
--      expiry or reassignment waits for this write to commit.
--   3. The patient is resolved through the relational chain, not trusted from
--      the payload. An encounter must belong to the named patient and tenant;
--      a child row must reach a patient through its foreign keys.
--   4. Domain policy is permission-first, then assignment-aware:
--        - clinical and nursing roles need an active doctor assignment,
--          attending encounter, bed assignment or ward scope;
--        - triage/reception may register a patient and open initial intake;
--        - diagnostic, pharmacy, financial and administrative workflow roles
--          operate through their scoped permissions;
--        - hospital super admin and tenant.administer are tenant-wide.
--
-- The trigger is defense in depth. The handler still returns a clean rejection
-- and the ledger still records the attempt.

-- ---------------------------------------------------------------------------
-- 1. Table rules. Only tables in this catalogue receive the guard trigger.
-- ---------------------------------------------------------------------------

create table if not exists nodex.mutation_scope_rules (
  table_name        text primary key,
  write_permissions text[] not null check (cardinality(write_permissions) > 0),
  registration_table boolean not null default false,
  triage_table       boolean not null default false
);

comment on table nodex.mutation_scope_rules is
  'Tables whose writes must resolve a patient and pass the patient-assignment policy. The permission list mirrors the table RLS write gate.';

insert into nodex.mutation_scope_rules
  (table_name, write_permissions, registration_table, triage_table)
values
  ('patients', array['patient.write']::text[], true, false),
  ('patient_allergies', array['patient.write']::text[], false, false),
  ('patient_merge_history', array['patient.write']::text[], false, false),
  ('clinical_encounters', array['encounter.write']::text[], true, false),
  ('clinical_problems', array['encounter.write']::text[], false, false),
  ('encounter_scribe_drafts', array['encounter.write']::text[], false, false),
  ('encounter_amendments', array['encounter.write']::text[], false, false),
  ('lab_orders', array['lab_order.write']::text[], false, false),
  ('lab_specimens', array['lab_order.write']::text[], false, false),
  ('lab_results', array['lab_result.enter','lab_result.verify']::text[], false, false),
  ('prescriptions', array['prescription.draft']::text[], false, false),
  ('prescription_items', array['prescription.draft']::text[], false, false),
  ('pharmacy_dispenses', array['pharmacy.dispense']::text[], false, false),
  ('medication_administrations', array['medication.administer']::text[], false, false),
  ('appointments', array['appointment.write']::text[], false, false),
  ('bed_assignments', array['bed.assign']::text[], false, false),
  ('discharges', array['discharge.finalize']::text[], false, false),
  ('invoices', array['billing.settle']::text[], false, false),
  ('invoice_lines', array['billing.settle']::text[], false, false),
  ('payments', array['billing.settle']::text[], false, false),
  ('patient_accounts', array['billing.settle']::text[], false, false),
  ('ledger_entries', array['billing.settle']::text[], false, false),
  ('payment_allocations', array['billing.settle']::text[], false, false),
  ('refunds', array['billing.settle']::text[], false, false),
  ('triage_assessments', array['triage.write']::text[], false, true),
  ('er_visits', array['er.visit.write']::text[], false, true),
  ('icu_beds', array['icu.bed.assign']::text[], false, false),
  ('icu_vitals', array['icu.vitals.record']::text[], false, false),
  ('icu_nursing_handover', array['icu.handover.record']::text[], false, false),
  ('ventilator_events', array['ventilator.event.record']::text[], false, false),
  ('transfusion_requests', array['transfusion.request']::text[], false, false),
  ('blood_units', array['blood_unit.write']::text[], false, false),
  ('transfusions', array['transfusion.administer','transfusion.finalize']::text[], false, false),
  ('ot_bookings', array['ot.schedule']::text[], false, false),
  ('ot_preop_assessments', array['ot.record']::text[], false, false),
  ('ot_anesthesia_records', array['ot.record']::text[], false, false),
  ('ot_procedure_logs', array['ot.record']::text[], false, false),
  ('ot_postop_records', array['ot.record']::text[], false, false),
  ('imaging_orders', array['imaging_order.write']::text[], false, false),
  ('imaging_studies', array['imaging_study.record']::text[], false, false),
  ('imaging_reports', array['imaging_report.enter','imaging_report.verify']::text[], false, false),
  ('physio_sessions', array['physio_session.write']::text[], false, false),
  ('physio_exercise_plans', array['physio_exercise.write']::text[], false, false),
  ('physio_recovery_notes', array['physio_note.write']::text[], false, false),
  ('diet_assessments', array['diet_assessment.write']::text[], false, false),
  ('diet_meal_plans', array['diet_plan.write']::text[], false, false),
  ('diet_meal_plan_days', array['diet_plan.write']::text[], false, false),
  ('diet_intake_logs', array['diet_intake.record']::text[], false, false),
  ('tele_consultations', array['tele_consultation.write']::text[], false, false),
  ('tele_vitals_overlays', array['tele_vitals.record']::text[], false, false),
  ('tele_consultation_archives', array['tele_archive.write']::text[], false, false),
  ('discharge_clearances', array['discharge_clearance.write']::text[], false, false),
  ('discharge_medication_reconciliations', array['discharge_reconciliation.write']::text[], false, false),
  ('discharge_medication_reconciliation_items', array['discharge_reconciliation.write']::text[], false, false),
  ('discharge_settlements', array['discharge.finalize','billing.settle']::text[], false, false),
  ('ward_vitals', array['vitals.record']::text[], false, false),
  ('ward_tasks', array['nursing_task.write']::text[], false, false),
  ('hospital_tasks', array['tasks.manage']::text[], false, false),
  ('form_responses', array['forms.submit']::text[], false, false),
  ('doctor_assignments', array['clinical.dashboard.manage']::text[], false, false),
  ('patient_portal_links', array['portal.manage']::text[], false, false),
  ('clinical_threads', array['messaging.send']::text[], false, false),
  ('clinical_messages', array['messaging.send']::text[], false, false),
  ('clinical_attachments', array['messaging.send']::text[], false, false),
  ('work_items', array['workitems.manage']::text[], false, false),
  ('ambulance_dispatches', array['fleet.dispatch']::text[], false, false),
  ('insurance_policies', array['insurance.manage']::text[], false, false),
  ('pre_authorisation_requests', array['insurance.claim','insurance.verify']::text[], false, false),
  ('insurance_claims', array['insurance.claim','insurance.verify']::text[], false, false),
  ('consent_records', array['documents.consent']::text[], false, false),
  ('document_vault_documents', array['documents.vault']::text[], false, false),
  ('statutory_birth_records', array['statutory.register']::text[], false, false),
  ('statutory_death_records', array['statutory.register']::text[], false, false),
  ('statutory_mlc_intimations', array['statutory.register']::text[], false, false),
  ('statutory_record_amendments', array['statutory.amend']::text[], false, false),
  ('incident_reports', array['quality.incident']::text[], false, false),
  ('feedback_surveys', array['feedback.record']::text[], false, false),
  ('feedback_complaints', array['feedback.record']::text[], false, false),
  ('complaint_routing_events', array['feedback.resolve']::text[], false, false),
  ('visitor_registrations', array['visitor.register']::text[], false, false),
  ('visitor_passes', array['visitor.pass']::text[], false, false),
  ('visitor_badge_prints', array['visitor.pass']::text[], false, false),
  ('discharge_ai_summaries', array['discharge_summary.review']::text[], false, false)
on conflict (table_name) do update
set write_permissions = excluded.write_permissions,
    registration_table = excluded.registration_table,
    triage_table = excluded.triage_table;

-- ---------------------------------------------------------------------------
-- 2. Resolve the patient through the relational chain.
--
-- Direct patient_id wins. encounter_id resolves to its patient. A child row
-- (specimen, item, line, report, message, amendment) walks its single-column
-- foreign keys up to four levels. The walk is bounded so a cycle cannot spin.
-- ---------------------------------------------------------------------------

create or replace function nodex.resolve_mutation_patient(
  p_table  regclass,
  p_row    jsonb,
  p_tenant uuid,
  p_depth  integer default 0
)
returns table (patient_id uuid, encounter_id uuid)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_patient         uuid;
  v_encounter       uuid;
  v_parent          jsonb;
  v_parent_patient  uuid;
  v_parent_encounter uuid;
  rec               record;
begin
  if p_depth > 5 then
    return;
  end if;

  if p_row ? 'patient_id' then
    v_patient := nullif(p_row ->> 'patient_id', '')::uuid;
  end if;
  -- A few tables name the patient with a qualified column instead of the
  -- generic patient_id: an ICU bed's current occupant, and a birth record's
  -- mother. Both are patient-linked rows and must resolve to the same scope.
  if v_patient is null and p_row ? 'current_patient_id' then
    v_patient := nullif(p_row ->> 'current_patient_id', '')::uuid;
  end if;
  if v_patient is null and p_row ? 'mother_patient_id' then
    v_patient := nullif(p_row ->> 'mother_patient_id', '')::uuid;
  end if;
  if p_row ? 'encounter_id' then
    v_encounter := nullif(p_row ->> 'encounter_id', '')::uuid;
  end if;

  if v_patient is not null then
    return query select v_patient, v_encounter;
    return;
  end if;

  if v_encounter is not null then
    select e.patient_id
      into v_patient
      from public.clinical_encounters e
     where e.id = v_encounter
       and e.tenant_id = p_tenant;
    if v_patient is not null then
      return query select v_patient, v_encounter;
      return;
    end if;
  end if;

  -- Single-column foreign keys only. Composite keys are not used by the
  -- clinical graph this guard covers, and skipping them avoids ambiguity.
  for rec in
    select a.attname            as local_col,
           fn.nspname           as ref_schema,
           fc.relname           as ref_table,
           fa.attname           as ref_col
      from pg_constraint c
      join pg_class t       on t.oid = c.conrelid
      join pg_attribute a   on a.attrelid = t.oid and a.attnum = c.conkey[1]
      join pg_class fc      on fc.oid = c.confrelid
      join pg_namespace fn  on fn.oid = fc.relnamespace
      join pg_attribute fa  on fa.attrelid = fc.oid and fa.attnum = c.confkey[1]
     where c.contype = 'f'
       and c.conrelid = p_table
       and cardinality(c.conkey) = 1
       and a.atttypid = 'uuid'::regtype
       and fa.atttypid = 'uuid'::regtype
       and fn.nspname = 'public'
       and p_row ? a.attname
       and nullif(p_row ->> a.attname, '') is not null
  loop
    execute format(
      'select to_jsonb(x) from %I.%I x where x.%I = $1 limit 1',
      rec.ref_schema, rec.ref_table, rec.ref_col
    )
    into v_parent
    using (p_row ->> rec.local_col)::uuid;

    if v_parent is not null then
      select *
        into v_parent_patient, v_parent_encounter
        from nodex.resolve_mutation_patient(
          (quote_ident(rec.ref_schema) || '.' || quote_ident(rec.ref_table))::regclass,
          v_parent,
          p_tenant,
          p_depth + 1
        );

      if v_parent_patient is not null then
        return query
          select v_parent_patient, coalesce(v_parent_encounter, v_encounter);
        return;
      end if;
    end if;
  end loop;

  return;
end;
$$;

comment on function nodex.resolve_mutation_patient(regclass, jsonb, uuid, integer) is
  'Resolves the patient a row belongs to, directly or through its parent chain. Returns NULL when no patient is reachable.';

-- A row that names a patient directly must not also hang from a parent that
-- belongs to a different patient. Without this check, a caller assigned to
-- patient A could insert a child row against patient B's order by putting A in
-- patient_id: the foreign key proves the order exists, not that it is A's.
-- Every single-column parent chain is walked and compared. patient_merge_history
-- is the one deliberate exception: it names two patients because a merge joins
-- them, and the trigger authorizes both explicitly.
create or replace function nodex.assert_patient_chain_consistency(
  p_table   regclass,
  p_row     jsonb,
  p_tenant  uuid,
  p_patient uuid,
  p_depth   integer default 0
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  rec                record;
  v_parent           jsonb;
  v_parent_patient   uuid;
  v_parent_encounter uuid;
begin
  if p_patient is null or p_depth > 5 then
    return;
  end if;

  for rec in
    select a.attname   as local_col,
           fn.nspname  as ref_schema,
           fc.relname  as ref_table,
           fa.attname  as ref_col
      from pg_constraint c
      join pg_class t       on t.oid = c.conrelid
      join pg_attribute a   on a.attrelid = t.oid and a.attnum = c.conkey[1]
      join pg_class fc      on fc.oid = c.confrelid
      join pg_namespace fn  on fn.oid = fc.relnamespace
      join pg_attribute fa  on fa.attrelid = fc.oid and fa.attnum = c.confkey[1]
     where c.contype = 'f'
       and c.conrelid = p_table
       and cardinality(c.conkey) = 1
       and a.atttypid = 'uuid'::regtype
       and fa.atttypid = 'uuid'::regtype
       and fn.nspname = 'public'
       and a.attname <> 'patient_id'
       and p_row ? a.attname
       and nullif(p_row ->> a.attname, '') is not null
  loop
    execute format(
      'select to_jsonb(x) from %I.%I x where x.%I = $1 limit 1',
      rec.ref_schema, rec.ref_table, rec.ref_col
    )
    into v_parent
    using (p_row ->> rec.local_col)::uuid;

    if v_parent is not null then
      select *
        into v_parent_patient, v_parent_encounter
        from nodex.resolve_mutation_patient(
          (quote_ident(rec.ref_schema) || '.' || quote_ident(rec.ref_table))::regclass,
          v_parent,
          p_tenant,
          p_depth + 1
        );

      if v_parent_patient is not null and v_parent_patient <> p_patient then
        raise exception using
          message = format(
            'NODEX: %s links to patient %s but the row names patient %s',
            p_table::text, v_parent_patient, p_patient
          ),
          errcode = '42501';
      end if;

      perform nodex.assert_patient_chain_consistency(
        (quote_ident(rec.ref_schema) || '.' || quote_ident(rec.ref_table))::regclass,
        v_parent,
        p_tenant,
        p_patient,
        p_depth + 1
      );
    end if;
  end loop;
end;
$$;

comment on function nodex.assert_patient_chain_consistency(regclass, jsonb, uuid, uuid, integer) is
  'Rejects a row whose direct patient differs from any patient reachable through its foreign-key parents.';

-- ---------------------------------------------------------------------------
-- 3. Foreign-key tenant integrity.
--
-- A foreign key proves the parent exists, not that it belongs to the same
-- tenant. Every single-column FK to a tenant-bearing table is checked here.
-- ---------------------------------------------------------------------------

create or replace function nodex.assert_fk_tenant(
  p_table     regclass,
  p_row       jsonb,
  p_tenant    uuid,
  p_operation text default 'insert',
  p_old       jsonb default null
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  rec  record;
  v_ok integer;
begin
  for rec in
    select a.attname   as local_col,
           fn.nspname  as ref_schema,
           fc.relname  as ref_table,
           fa.attname  as ref_col
      from pg_constraint c
      join pg_class t       on t.oid = c.conrelid
      join pg_attribute a   on a.attrelid = t.oid and a.attnum = c.conkey[1]
      join pg_class fc      on fc.oid = c.confrelid
      join pg_namespace fn  on fn.oid = fc.relnamespace
      join pg_attribute fa  on fa.attrelid = fc.oid and fa.attnum = c.confkey[1]
     where c.contype = 'f'
       and c.conrelid = p_table
       and cardinality(c.conkey) = 1
       and a.atttypid = 'uuid'::regtype
       and fa.atttypid = 'uuid'::regtype
       and fn.nspname = 'public'
       and p_row ? a.attname
       and nullif(p_row ->> a.attname, '') is not null
       and (
         exists (
           select 1
             from pg_attribute ta
            where ta.attrelid = fc.oid
              and ta.attname = 'tenant_id'
              and ta.attnum > 0
              and not ta.attisdropped
         )
         -- app_users has no tenant_id because an identity may work in several
         -- tenants. On insert, and whenever the reference itself changes,
         -- require an active membership in the row's tenant. An unchanged
         -- historical actor is not re-checked: a later revocation must not
         -- block an unrelated edit to an old row.
         or (fn.nspname = 'public'
             and fc.relname = 'app_users'
             and (
               p_operation = 'insert'
               or (p_old is not null
                   and (p_old ->> a.attname) is distinct from (p_row ->> a.attname))
             ))
       )
  loop
    if rec.ref_schema = 'public' and rec.ref_table = 'app_users' then
      execute format(
        'select 1 from public.memberships
          where user_id = $1
            and tenant_id = $2
            and status = ''active''
            and valid_from <= clock_timestamp()
            and (valid_until is null or valid_until > clock_timestamp())
          limit 1
          for share'
      )
      into v_ok
      using (p_row ->> rec.local_col)::uuid, p_tenant;
    else
      execute format(
        'select 1 from %I.%I where %I = $1 and tenant_id = $2',
        rec.ref_schema, rec.ref_table, rec.ref_col
      )
      into v_ok
      using (p_row ->> rec.local_col)::uuid, p_tenant;
    end if;

    if v_ok is null then
      raise exception using
        message = format(
          'NODEX: %s references %s outside the tenant',
          p_table::text, rec.ref_table
        ),
        errcode = '42501';
    end if;
  end loop;
end;
$$;

comment on function nodex.assert_fk_tenant(regclass, jsonb, uuid, text, jsonb) is
  'Rejects a row whose tenant-bearing foreign-key parent is in another tenant. A changed app_users reference must also hold a current membership in that tenant.';

-- ---------------------------------------------------------------------------
-- 4. Domain policy.
-- ---------------------------------------------------------------------------

create or replace function nodex.assert_patient_mutation_scope(
  p_tenant    uuid,
  p_patient   uuid,
  p_encounter uuid,
  p_table     text,
  p_operation text,
  p_row       jsonb
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid            uuid := auth.uid();
  v_rule           nodex.mutation_scope_rules;
  v_permitted      boolean;
  v_is_admin       boolean;
  v_is_clinical    boolean;
  v_is_nursing     boolean;
  v_assigned       boolean;
  v_ward_id        uuid;
  v_facility_id    uuid;
begin
  if v_uid is null then
    raise exception 'NODEX: authentication required' using errcode = '28000';
  end if;

  select *
    into v_rule
    from nodex.mutation_scope_rules
   where table_name = p_table;

  if not found then
    raise exception using
      message = format('NODEX: no mutation scope rule for %s', p_table),
      errcode = '42501';
  end if;

  -- Lock the role grants this decision reads. A concurrent revocation of a
  -- permission cannot land between the check and the write.
  perform 1
     from public.role_permissions rp
     join public.memberships m on m.role_key = rp.role_key
    where m.user_id = v_uid
      and m.tenant_id = p_tenant
      and m.status = 'active'
      and m.valid_from <= clock_timestamp()
      and (m.valid_until is null or m.valid_until > clock_timestamp())
    for share of rp;

  -- The role class decides which policy branch applies. Lock the catalogue
  -- rows too, so a concurrent role-class edit cannot change the branch between
  -- this decision and the write.
  perform 1
     from public.roles r
     join public.memberships m on m.role_key = r.key
    where m.user_id = v_uid
      and m.tenant_id = p_tenant
      and m.status = 'active'
      and m.valid_from <= clock_timestamp()
      and (m.valid_until is null or m.valid_until > clock_timestamp())
    for share of r;

  -- Exact-instant permission check. The Phase 1 RLS helpers are STABLE and
  -- evaluate now() at transaction start; a long transaction could otherwise
  -- pass this guard after valid_until has already elapsed. clock_timestamp()
  -- is evaluated per call, so the write is refused at the expiry instant.
  select exists (
    select 1
      from public.memberships m
      join public.role_permissions rp on rp.role_key = m.role_key
     where m.user_id = v_uid
       and m.tenant_id = p_tenant
       and m.status = 'active'
       and m.valid_from <= clock_timestamp()
       and (m.valid_until is null or m.valid_until > clock_timestamp())
       and rp.permission_key = any(v_rule.write_permissions)
  ) into v_permitted;

  if not v_permitted then
    raise exception using
      message = format('NODEX: missing write permission for %s', p_table),
      errcode = '42501';
  end if;

  select exists (
    select 1
      from public.memberships m
      left join public.role_permissions rp
        on rp.role_key = m.role_key
       and rp.permission_key = 'tenant.administer'
     where m.user_id = v_uid
       and m.tenant_id = p_tenant
       and m.status = 'active'
       and m.valid_from <= clock_timestamp()
       and (m.valid_until is null or m.valid_until > clock_timestamp())
       and (m.role_key = 'hospital_super_admin' or rp.permission_key is not null)
  ) into v_is_admin;

  if v_is_admin then
    return;
  end if;

  select bool_or(r.role_class = 'clinical'),
         bool_or(r.role_class = 'nursing')
    into v_is_clinical, v_is_nursing
    from public.memberships m
    join public.roles r on r.key = m.role_key
   where m.user_id = v_uid
     and m.tenant_id = p_tenant
     and m.status = 'active'
     and m.valid_from <= clock_timestamp()
     and (m.valid_until is null or m.valid_until > clock_timestamp());

  -- Facility and ward narrowing applies when the row names them. The same
  -- membership must grant the table write permission and cover the row's
  -- facility/ward: two separate EXISTS checks would let a facility-A grant
  -- combine with an unrelated facility-B membership to write at B. This is a
  -- direct, exact-instant check for the same reason as the permission check.
  if (p_row ? 'facility_id' and nullif(p_row ->> 'facility_id', '') is not null)
     or (p_row ? 'ward_id' and nullif(p_row ->> 'ward_id', '') is not null) then
    v_facility_id := nullif(p_row ->> 'facility_id', '')::uuid;
    v_ward_id := nullif(p_row ->> 'ward_id', '')::uuid;

    if not exists (
      select 1
        from public.memberships m
        join public.role_permissions rp on rp.role_key = m.role_key
       where m.user_id = v_uid
         and m.tenant_id = p_tenant
         and m.status = 'active'
         and m.valid_from <= clock_timestamp()
         and (m.valid_until is null or m.valid_until > clock_timestamp())
         and rp.permission_key = any(v_rule.write_permissions)
         and (v_facility_id is null
              or m.facility_id is null
              or m.facility_id = v_facility_id)
         and (v_ward_id is null
              or m.ward_id is null
              or m.ward_id = v_ward_id)
    ) then
      raise exception using
        message = 'NODEX: the row is outside the caller''s membership scope',
        errcode = '42501';
    end if;
  end if;

  -- A bed assignment or ICU bed names a bed, not a ward. Resolve the bed's
  -- ward and apply the same membership narrowing the generic ward check would
  -- apply. This runs before the no-patient return: an ICU bed with no current
  -- occupant is still a location write and must stay inside the caller's ward.
  -- Occupying a bed is the act that creates the location relationship, so it is
  -- gated by the table permission plus ward scope rather than by an assignment
  -- that does not exist yet.
  if p_table in ('bed_assignments', 'icu_beds') then
    if not exists (
      select 1
        from public.beds b
        join public.memberships m
          on m.tenant_id = b.tenant_id
         and m.user_id = v_uid
         and m.status = 'active'
         and m.valid_from <= clock_timestamp()
         and (m.valid_until is null or m.valid_until > clock_timestamp())
         and (m.ward_id is null or m.ward_id = b.ward_id)
        join public.role_permissions rp
          on rp.role_key = m.role_key
         and rp.permission_key = any(v_rule.write_permissions)
       where b.id = nullif(p_row ->> 'bed_id', '')::uuid
         and b.tenant_id = p_tenant
    ) then
      raise exception 'NODEX: the bed is outside the caller''s ward scope'
        using errcode = '42501';
    end if;
    if p_operation = 'insert' or p_table = 'icu_beds' then
      return;
    end if;
  end if;

  -- A row that names no patient is tenant-level (for example a thread with no
  -- patient). The permission gate above is the whole policy for it.
  if p_patient is null then
    return;
  end if;

  -- Non-clinical workflow roles operate through the table's scoped permission.
  -- The permission key is the grant; a lab technician, pharmacist, billing
  -- officer or integration service does not need a doctor assignment to act on
  -- a record the hospital already created. Cross-cutting tables (tasks, forms,
  -- messaging, insurance, feedback) are used by several workflow roles, so the
  -- role class is not narrowed to a single domain. The grant must come from a
  -- workflow membership: a user who also holds a clinical role cannot use a
  -- workflow role to bypass the assignment rule for a permission the workflow
  -- role does not itself grant.
  if exists (
    select 1
      from public.memberships m
      join public.roles r on r.key = m.role_key
      join public.role_permissions rp on rp.role_key = m.role_key
     where m.user_id = v_uid
       and m.tenant_id = p_tenant
       and m.status = 'active'
       and m.valid_from <= clock_timestamp()
       and (m.valid_until is null or m.valid_until > clock_timestamp())
       and r.role_class in ('diagnostic', 'pharmacy', 'financial',
                            'administrative', 'service')
       and rp.permission_key = any(v_rule.write_permissions)
  ) then
    return;
  end if;

  -- Patient self-service. The portal link is the scope; the permission gate
  -- above still decides which tables the patient role may write. A link is
  -- revoked by setting revoked_at, so it cannot outlive the relationship. The
  -- row is locked so a concurrent revocation waits for this write to commit.
  perform 1
     from public.patient_portal_links l
    where l.tenant_id = p_tenant
      and l.patient_id = p_patient
      and l.portal_user_id = v_uid
      and l.revoked_at is null
    for share;
  if found then
    return;
  end if;

  -- Initial intake: the attending doctor may open the encounter that creates
  -- the care relationship. Administrative and service workflow roles already
  -- returned through their permission above.
  if v_rule.registration_table and p_table = 'clinical_encounters' and p_operation = 'insert' then
    if nullif(p_row ->> 'attending_physician_id', '')::uuid = v_uid then
      return;
    end if;
  end if;

  -- Triage is the one clinical surface that must work before an assignment
  -- exists. The table's write permission (triage.write for triage, er.visit.write
  -- for an ER visit) is the scope; the encounter/patient chain is still verified
  -- by the trigger. This covers update as well as insert: a triage assessment is
  -- amended during the same pre-assignment encounter, and denying the update
  -- would break the intake workflow the insert branch exists to permit.
  if v_rule.triage_table then
    return;
  end if;

  -- Creating a dashboard assignment is the act that establishes the clinical
  -- relationship. Requiring an existing assignment would be circular. The
  -- permission and tenant/facility checks above are the gate; the patient and
  -- doctor foreign keys are tenant-checked, and the doctor must hold a current
  -- membership in this tenant.
  if p_table = 'doctor_assignments' and p_operation = 'insert' then
    return;
  end if;

  -- Registration: a member with patient.write may create a patient. There is
  -- no assignment to check yet, and a new patient has no facility/ward column.
  -- Updates still require an assignment unless the actor is an administrative
  -- workflow role, which the branch above already allowed. This must run before
  -- the clinical branch: a medical officer with patient.write would otherwise
  -- fail the assignment check for the patient they are about to create.
  if v_rule.registration_table and p_table = 'patients' and p_operation = 'insert' then
    return;
  end if;

  -- Doctor policy: active assignment, active attending/creating encounter, or
  -- a consulting/rounding assignment (the referral case). The assignment rows
  -- are locked so a conclusion cannot race the write.
  if v_is_clinical then
    -- An encounter-linked write is also in scope when the caller is the
    -- attending or creator of that encounter. This is what lets a clinician
    -- amend or add an order to a signed encounter after the dashboard
    -- assignment has concluded.
    if p_encounter is not null and exists (
      select 1
        from public.clinical_encounters e
       where e.id = p_encounter
         and e.tenant_id = p_tenant
         and (e.attending_physician_id = v_uid or e.created_by = v_uid)
    ) then
      return;
    end if;

    perform 1
       from public.doctor_assignments da
      where da.tenant_id = p_tenant
        and da.patient_id = p_patient
        and da.doctor_id = v_uid
        and da.status = 'active'
      for share;
    v_assigned := found;

    if not v_assigned then
      select exists (
        select 1
          from public.clinical_encounters e
         where e.tenant_id = p_tenant
           and e.patient_id = p_patient
           and (e.attending_physician_id = v_uid or e.created_by = v_uid)
           and e.status in ('planned', 'in_progress')
      ) into v_assigned;
    end if;

    if v_assigned then
      return;
    end if;
  end if;

  -- Nursing policy: an active bed assignment in a ward the membership covers.
  if v_is_nursing then
    perform 1
       from public.bed_assignments ba
       join public.beds b on b.id = ba.bed_id
       join public.memberships m
         on m.tenant_id = ba.tenant_id
        and m.user_id = v_uid
        and m.status = 'active'
        and m.valid_from <= clock_timestamp()
        and (m.valid_until is null or m.valid_until > clock_timestamp())
        and (m.ward_id is null or m.ward_id = b.ward_id)
       join public.role_permissions rp
         on rp.role_key = m.role_key
        and rp.permission_key = any(v_rule.write_permissions)
      where ba.tenant_id = p_tenant
        and ba.patient_id = p_patient
        and ba.status = 'active'
        and b.tenant_id = ba.tenant_id
      for share of ba, b;
    v_assigned := found;

    -- An ICU occupant may not have a bed_assignments row; the ICU bed itself
    -- is the location record. Accept that occupancy when it is in a ward the
    -- membership covers.
    if not v_assigned then
      perform 1
         from public.icu_beds ib
         join public.beds b on b.id = ib.bed_id
         join public.memberships m
           on m.tenant_id = ib.tenant_id
          and m.user_id = v_uid
          and m.status = 'active'
          and m.valid_from <= clock_timestamp()
          and (m.valid_until is null or m.valid_until > clock_timestamp())
          and (m.ward_id is null or m.ward_id = b.ward_id)
         join public.role_permissions rp
           on rp.role_key = m.role_key
          and rp.permission_key = any(v_rule.write_permissions)
        where ib.tenant_id = p_tenant
          and ib.current_patient_id = p_patient
          and b.tenant_id = ib.tenant_id
        for share of ib, b;
      v_assigned := found;
    end if;

    if v_assigned then
      return;
    end if;
  end if;

  raise exception using
    message = format(
      'NODEX: patient %s is outside the caller''s current assignment scope',
      p_patient
    ),
    errcode = '42501';
end;
$$;

comment on function nodex.assert_patient_mutation_scope(uuid, uuid, uuid, text, text, jsonb) is
  'Domain policy for a patient-linked write. Raises 42501 when the actor lacks permission, tenant scope or a current assignment.';

-- ---------------------------------------------------------------------------
-- 5. Trigger. Authorization, locking and the write share one transaction.
-- ---------------------------------------------------------------------------

create or replace function nodex.tg_patient_mutation_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid       uuid := auth.uid();
  v_row       jsonb;
  v_old       jsonb;
  v_tenant    uuid;
  v_patient   uuid;
  v_encounter uuid;
  v_device    uuid;
  v_headers   jsonb;
  v_count     integer;
  v_col       text;
begin
  -- Server-side service_role is the only bypass. The mutation handler uses the
  -- caller-scoped client, so a client request never reaches this branch.
  if nodex.is_service_role() then
    return new;
  end if;

  if v_uid is null then
    raise exception 'NODEX: authentication required' using errcode = '28000';
  end if;

  v_row := to_jsonb(new);
  v_tenant := nullif(v_row ->> 'tenant_id', '')::uuid;

  if v_tenant is null then
    raise exception 'NODEX: tenant_id is required on a guarded write' using errcode = '42501';
  end if;

  if tg_op = 'UPDATE' then
    v_old := to_jsonb(old);
    if (v_old ->> 'tenant_id') is distinct from (v_row ->> 'tenant_id') then
      raise exception 'NODEX: tenant_id is immutable' using errcode = '42501';
    end if;
    if (v_old ->> 'id') is distinct from (v_row ->> 'id') then
      raise exception 'NODEX: row identity is immutable' using errcode = '42501';
    end if;
    if v_row ? 'patient_id'
       and (v_old ->> 'patient_id') is distinct from (v_row ->> 'patient_id') then
      raise exception 'NODEX: patient_id is immutable; transfer the record through its own workflow'
        using errcode = '42501';
    end if;
    if v_row ? 'encounter_id'
       and (v_old ->> 'encounter_id') is distinct from (v_row ->> 'encounter_id') then
      raise exception 'NODEX: encounter_id is immutable; link a new record instead'
        using errcode = '42501';
    end if;

    -- Creation attribution is provenance, not editable content. A later
    -- verifier or signer has its own column; the person who created the row
    -- must not be rewritten. This is the database half of the audit trail.
    foreach v_col in array array[
      'created_by', 'recorded_by', 'prescribed_by', 'dispensed_by',
      'booked_by', 'assigned_by', 'amended_by', 'requested_by',
      'reported_by', 'merged_by', 'uploaded_by', 'submitted_by',
      'enrolled_by', 'assessed_by'
    ] loop
      if v_row ? v_col
         and (v_old ->> v_col) is distinct from (v_row ->> v_col) then
        raise exception using
          message = format('NODEX: %s is immutable', v_col),
          errcode = '42501';
      end if;
    end loop;
  end if;

  -- Lock the actor's current memberships. A suspension or expiry transition
  -- cannot commit between this check and the write.
  perform 1
     from public.memberships m
    where m.user_id = v_uid
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
     from public.app_users u
    where u.id = v_uid
      and u.status = 'active'
    for share;
  if not found then
    raise exception 'NODEX: the account is not active' using errcode = '42501';
  end if;

  -- Device authorization is carried on the PostgREST request. An absent
  -- device header remains the existing unbound-mutation path; a supplied but
  -- invalid, suspended or revoked device is rejected.
  v_headers := nullif(current_setting('request.headers', true), '')::jsonb;
  v_device := nullif(v_headers ->> 'x-device-id', '')::uuid;
  if v_device is not null then
    perform 1
       from public.devices d
      where d.id = v_device
        and d.tenant_id = v_tenant
        and d.assigned_user_id = v_uid
        and d.status = 'active'
        and d.revoked_at is null
      for share;
    if not found then
      raise exception 'NODEX: the device is not authorized for this tenant or user'
        using errcode = '42501';
    end if;
  end if;

  perform nodex.assert_fk_tenant(tg_relid::regclass, v_row, v_tenant, lower(tg_op), v_old);

  select *
    into v_patient, v_encounter
    from nodex.resolve_mutation_patient(tg_relid::regclass, v_row, v_tenant);

  -- The patients row is its own patient. The generic resolver cannot infer
  -- that from a patient_id column because the table does not have one.
  if tg_table_name = 'patients' then
    v_patient := (v_row ->> 'id')::uuid;
  end if;

  -- A merge names two patients on purpose. It is the only table in the
  -- catalogue with two patient foreign keys; the generic resolver returns the
  -- first, so the trigger authorizes both explicitly below.
  if tg_table_name = 'patient_merge_history' then
    v_patient := (v_row ->> 'surviving_patient_id')::uuid;
  end if;

  if tg_table_name = 'patient_merge_history' then
    perform 1
       from public.patients p
      where p.id in (
              (v_row ->> 'surviving_patient_id')::uuid,
              (v_row ->> 'merged_patient_id')::uuid
            )
        and p.tenant_id = v_tenant
      for share;
    get diagnostics v_count = row_count;
    if v_count <> 2 then
      raise exception 'NODEX: both patients in a merge must exist in this tenant'
        using errcode = '42501';
    end if;
  elsif v_patient is not null
        and not (tg_table_name = 'patients' and tg_op = 'INSERT') then
    perform 1
       from public.patients p
      where p.id = v_patient
        and p.tenant_id = v_tenant
      for share;
    if not found then
      raise exception 'NODEX: the patient is not in this tenant' using errcode = '42501';
    end if;
  end if;

  if v_encounter is not null
     and not (tg_table_name = 'clinical_encounters' and tg_op = 'INSERT') then
    perform 1
       from public.clinical_encounters e
      where e.id = v_encounter
        and e.tenant_id = v_tenant
        and e.patient_id = v_patient
      for share;
    if not found then
      raise exception 'NODEX: the encounter is not in this tenant or does not belong to the patient'
        using errcode = '42501';
    end if;
  end if;

  if tg_table_name = 'patient_merge_history' then
    perform nodex.assert_patient_mutation_scope(
      v_tenant, (v_row ->> 'surviving_patient_id')::uuid, null,
      tg_table_name, lower(tg_op), v_row
    );
    perform nodex.assert_patient_mutation_scope(
      v_tenant, (v_row ->> 'merged_patient_id')::uuid, null,
      tg_table_name, lower(tg_op), v_row
    );
  else
    perform nodex.assert_patient_chain_consistency(
      tg_relid::regclass, v_row, v_tenant, v_patient
    );
    perform nodex.assert_patient_mutation_scope(
      v_tenant, v_patient, v_encounter, tg_table_name, lower(tg_op), v_row
    );
  end if;

  return new;
end;
$$;

comment on function nodex.tg_patient_mutation_guard() is
  'BEFORE INSERT/UPDATE: locks and authorizes the patient chain in the same transaction as the write.';

-- ---------------------------------------------------------------------------
-- 6. Attach the guard to every patient-linked writable table.
-- ---------------------------------------------------------------------------

do $$
declare
  t text;
begin
  foreach t in array array[
    'patients', 'patient_allergies', 'patient_merge_history',
    'clinical_encounters', 'clinical_problems', 'encounter_scribe_drafts',
    'encounter_amendments', 'lab_orders', 'lab_specimens', 'lab_results',
    'prescriptions', 'prescription_items', 'pharmacy_dispenses',
    'medication_administrations', 'appointments', 'bed_assignments',
    'discharges', 'invoices', 'invoice_lines', 'payments', 'patient_accounts',
    'ledger_entries', 'payment_allocations', 'refunds', 'triage_assessments',
    'er_visits', 'icu_beds', 'icu_vitals', 'icu_nursing_handover',
    'ventilator_events', 'transfusion_requests', 'blood_units', 'transfusions',
    'ot_bookings', 'ot_preop_assessments', 'ot_anesthesia_records',
    'ot_procedure_logs', 'ot_postop_records', 'imaging_orders',
    'imaging_studies', 'imaging_reports', 'physio_sessions',
    'physio_exercise_plans', 'physio_recovery_notes', 'diet_assessments',
    'diet_meal_plans', 'diet_meal_plan_days', 'diet_intake_logs',
    'tele_consultations', 'tele_vitals_overlays', 'tele_consultation_archives',
    'discharge_clearances', 'discharge_medication_reconciliations',
    'discharge_medication_reconciliation_items', 'discharge_settlements',
    'ward_vitals', 'ward_tasks', 'hospital_tasks', 'form_responses',
    'doctor_assignments', 'patient_portal_links', 'clinical_threads',
    'clinical_messages', 'clinical_attachments', 'work_items',
    'ambulance_dispatches', 'insurance_policies', 'pre_authorisation_requests',
    'insurance_claims', 'consent_records', 'document_vault_documents',
    'statutory_birth_records', 'statutory_death_records',
    'statutory_mlc_intimations', 'statutory_record_amendments',
    'incident_reports', 'feedback_surveys',
    'feedback_complaints', 'complaint_routing_events', 'visitor_registrations',
    'visitor_passes', 'visitor_badge_prints', 'discharge_ai_summaries'
  ] loop
    execute format('drop trigger if exists patient_scope_guard on public.%I', t);
    execute format(
      'create trigger patient_scope_guard before insert or update on public.%I '
      'for each row execute function nodex.tg_patient_mutation_guard()',
      t
    );
  end loop;
end;
$$;

-- The guard is invoked by the table owner through the trigger. The helper
-- functions are not a client-facing API.
revoke all on function nodex.resolve_mutation_patient(regclass, jsonb, uuid, integer) from public;
revoke all on function nodex.assert_patient_chain_consistency(regclass, jsonb, uuid, uuid, integer) from public;
revoke all on function nodex.assert_fk_tenant(regclass, jsonb, uuid, text, jsonb) from public;
revoke all on function nodex.assert_patient_mutation_scope(uuid, uuid, uuid, text, text, jsonb) from public;
revoke all on function nodex.tg_patient_mutation_guard() from public;
