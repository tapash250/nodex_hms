-- NODEX Phase 4 authorization integration tests.
--
-- NOT A MIGRATION. Run only on a dedicated development database after:
--   1. all migrations through 20260918170000 are applied;
--   2. powersync/dev-seed.sql has been applied.
--
-- The test runs as the `postgres` role and rolls back at the end. It sets the
-- same request GUCs Supabase sets for an authenticated request, so the trigger
-- sees a real auth.uid() and a real x-device-id. It does NOT exercise RLS:
-- `postgres` bypasses row-level security. RLS behaviour is covered by the
-- separate live-service checklist in tests/README.md.
--
-- Expected failures are caught in subtransactions, so one rejected statement
-- does not abort the rest of the test.

\set ON_ERROR_STOP on

begin;

-- ---------------------------------------------------------------------------
-- Request-context helpers.
-- ---------------------------------------------------------------------------

create or replace function pg_temp.actor(p_user uuid, p_device text default null)
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_user::text, ''), true);
  perform set_config(
    'request.jwt.claim.role',
    case when p_user is null then 'service_role' else 'authenticated' end,
    true
  );
  perform set_config(
    'request.jwt.claims',
    case
      when p_user is null then '{"role":"service_role"}'
      else json_build_object('sub', p_user::text, 'role', 'authenticated')::text
    end,
    true
  );
  perform set_config(
    'request.headers',
    case
      when p_device is null then '{}'
      else json_build_object('x-device-id', p_device)::text
    end,
    true
  );
end;
$$;

create or replace function pg_temp.expect_forbidden(p_sql text, p_label text)
returns void
language plpgsql
as $$
declare
  v_message text;
begin
  begin
    execute p_sql;
  exception
    when insufficient_privilege then
      get stacked diagnostics v_message = message_text;
      if v_message not like 'NODEX:%' then
        raise exception 'FAIL %: expected a NODEX authorization error, got %', p_label, v_message;
      end if;
      raise notice 'ok forbidden: %', p_label;
      return;
  end;

  raise exception 'FAIL %: statement succeeded but must be forbidden', p_label;
end;
$$;

create or replace function pg_temp.expect_ok(p_sql text, p_label text)
returns void
language plpgsql
as $$
begin
  begin
    execute p_sql;
  exception when others then
    raise exception 'FAIL %: expected success, got % (%)', p_label, sqlerrm, sqlstate;
  end;
  raise notice 'ok allowed: %', p_label;
end;
$$;

create or replace function pg_temp.expect_state(p_state text, p_sql text, p_label text)
returns void
language plpgsql
as $$
declare
  v_state text;
begin
  begin
    execute p_sql;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate;
    if v_state = p_state then
      raise notice 'ok %: %', p_state, p_label;
      return;
    end if;
    raise exception 'FAIL %: expected SQLSTATE %, got % (%)', p_label, p_state, v_state, sqlerrm;
  end;

  raise exception 'FAIL %: expected SQLSTATE % but statement succeeded', p_label, p_state;
end;
$$;

-- ---------------------------------------------------------------------------
-- Fixtures used only by this test. The seed supplies the rest.
-- ---------------------------------------------------------------------------

select pg_temp.actor(null);

-- A second appointment slot used by the conflict test. It is created by the
-- first half of the test, not here, so the exclusion constraint is exercised.

-- ---------------------------------------------------------------------------
-- Tests.
-- ---------------------------------------------------------------------------

do $test$
declare
  v_before timestamptz;
  v_after  timestamptz;
  v_status text;
begin
  -- 1. Assigned doctor may edit the assigned patient.
  perform pg_temp.actor('d1000000-0000-4000-8000-000000000002');
  perform pg_temp.expect_ok(
    $sql$update public.patients
            set phone_number = '+8801700099999'
          where id = 'd4000000-0000-4000-8000-000000000001'$sql$,
    'assigned doctor edits assigned patient'
  );

  -- 1b. Registration is the one patient write with no assignment to check.
  --     A medical officer with patient.write may create the patient; a billing
  --     user with patient.read but no patient.write may not.
  perform pg_temp.expect_ok(
    $sql$insert into public.patients
           (id, tenant_id, mrn, first_name, last_name, date_of_birth, gender,
            created_by)
         values
           ('de000000-0000-4000-8000-000000000070',
            'd0000000-0000-4000-8000-000000000001',
            'DEV-NEW-1', 'New', 'Patient', '1990-01-01', 'female',
            'd1000000-0000-4000-8000-000000000002')$sql$,
    'medical officer registers a new patient'
  );
  perform pg_temp.actor('d1000000-0000-4000-8000-000000000005');
  perform pg_temp.expect_forbidden(
    $sql$insert into public.patients
           (id, tenant_id, mrn, first_name, last_name, date_of_birth, gender,
            created_by)
         values
           ('de000000-0000-4000-8000-000000000071',
            'd0000000-0000-4000-8000-000000000001',
            'DEV-NEW-2', 'No', 'Permission', '1990-01-01', 'male',
            'd1000000-0000-4000-8000-000000000005')$sql$,
    'billing user without patient.write cannot register a patient'
  );

  -- 1c. Triage is the pre-assignment intake surface. The nurse holds
  --     triage.write and covers only ward DEV-W1; patient A is not in that
  --     ward and has no assignment to the nurse. The assessment update must
  --     still pass, because triage happens before a bed exists. A billing user
  --     without triage.write must fail.
  perform pg_temp.actor('d1000000-0000-4000-8000-000000000004');
  perform pg_temp.expect_ok(
    $sql$update public.triage_assessments
            set chief_complaint = 'Chest pain, reassessed'
          where id = 'd9000000-0000-4000-8000-000000000001'$sql$,
    'triage nurse amends pre-assignment triage'
  );
  perform pg_temp.actor('d1000000-0000-4000-8000-000000000005');
  perform pg_temp.expect_forbidden(
    $sql$update public.triage_assessments
            set chief_complaint = 'unauthorized'
          where id = 'd9000000-0000-4000-8000-000000000001'$sql$,
    'billing user cannot amend triage'
  );

  -- 2. A clinician with the permission but no assignment is refused.
  perform pg_temp.actor('d1000000-0000-4000-8000-000000000003');
  perform pg_temp.expect_forbidden(
    $sql$update public.patients
            set phone_number = '+8801700099998'
          where id = 'd4000000-0000-4000-8000-000000000001'$sql$,
    'unassigned doctor edits patient'
  );

  -- 3. An encounter the caller neither attends nor created is refused.
  perform pg_temp.actor('d1000000-0000-4000-8000-000000000002');
  perform pg_temp.expect_forbidden(
    $sql$update public.clinical_encounters
            set assessment = 'unauthorized'
          where id = 'd6000000-0000-4000-8000-000000000002'$sql$,
    'doctor edits another doctor''s encounter'
  );

  -- 4. The attending doctor may open a planned encounter without a dashboard
  --    assignment. Patient C has ENC-C, attended by doctor D.
  perform pg_temp.expect_ok(
    $sql$update public.clinical_encounters
            set assessment = 'planned review'
          where id = 'd6000000-0000-4000-8000-000000000003'$sql$,
    'attending doctor edits own planned encounter'
  );

  -- 5. Parent-child spoofing: patient A in patient_id, patient B's encounter.
  perform pg_temp.expect_forbidden(
    $sql$insert into public.clinical_problems
           (id, tenant_id, patient_id, encounter_id, problem_code, description,
            recorded_by)
         values
           ('de000000-0000-4000-8000-000000000001',
            'd0000000-0000-4000-8000-000000000001',
            'd4000000-0000-4000-8000-000000000001',
            'd6000000-0000-4000-8000-000000000002',
            'DEV-SPOOF', 'Encounter belongs to another patient',
            'd1000000-0000-4000-8000-000000000002')$sql$,
    'problem names patient A but encounter of patient B'
  );

  -- 6. Parent-child spoofing through a workflow table: the prescription header
  --    belongs to patient A, the item to patient B. The row names no patient,
  --    so the generic resolver must compare both chains.
  perform pg_temp.actor('d1000000-0000-4000-8000-000000000008');
  perform pg_temp.expect_forbidden(
    $sql$insert into public.pharmacy_dispenses
           (id, tenant_id, prescription_id, item_id, dispensed_by,
            quantity_dispensed)
         values
           ('de000000-0000-4000-8000-000000000002',
            'd0000000-0000-4000-8000-000000000001',
            'da000000-0000-4000-8000-000000000001',
            'db000000-0000-4000-8000-000000000002',
            'd1000000-0000-4000-8000-000000000008', 1)$sql$,
    'dispense mixes prescription A with item B'
  );

  -- 7. Parent-child spoofing through two financial parents.
  perform pg_temp.actor('d1000000-0000-4000-8000-000000000005');
  perform pg_temp.expect_forbidden(
    $sql$insert into public.payment_allocations
           (id, tenant_id, payment_id, invoice_id, amount_minor)
         values
           ('de000000-0000-4000-8000-000000000003',
            'd0000000-0000-4000-8000-000000000001',
            'dd000000-0000-4000-8000-000000000001',
            'dc000000-0000-4000-8000-000000000002', 50)$sql$,
    'allocation mixes payment for A with invoice for B'
  );

  -- 8. Nursing scope: the nurse covers ward DEV-W1. Patient D occupies a bed
  --    there; patient A does not. The permission is vitals.record.
  perform pg_temp.actor('d1000000-0000-4000-8000-000000000004');
  perform pg_temp.expect_ok(
    $sql$insert into public.ward_vitals
           (id, tenant_id, patient_id, encounter_id, ward_id, recorded_by,
            pulse_bpm)
         values
           ('de000000-0000-4000-8000-000000000010',
            'd0000000-0000-4000-8000-000000000001',
            'd4000000-0000-4000-8000-000000000004',
            'd6000000-0000-4000-8000-000000000004',
            'd0000000-0000-4000-8000-000000000004',
            'd1000000-0000-4000-8000-000000000004', 72)$sql$,
    'ward nurse records vitals for bed patient'
  );
  perform pg_temp.expect_forbidden(
    $sql$insert into public.ward_vitals
           (id, tenant_id, patient_id, ward_id, recorded_by, pulse_bpm)
         values
           ('de000000-0000-4000-8000-000000000011',
            'd0000000-0000-4000-8000-000000000001',
            'd4000000-0000-4000-8000-000000000001',
            'd0000000-0000-4000-8000-000000000004',
            'd1000000-0000-4000-8000-000000000004', 72)$sql$,
    'ward nurse records vitals for patient outside ward assignment'
  );

  -- 9. Device authorization. The same patient write succeeds with the active
  --    device, and is refused with revoked, suspended, another user's and
  --    another tenant's device.
  perform pg_temp.actor(
    'd1000000-0000-4000-8000-000000000002',
    'd3000000-0000-4000-8000-000000000001'
  );
  perform pg_temp.expect_ok(
    $sql$update public.patients set phone_number = '+8801700099997'
          where id = 'd4000000-0000-4000-8000-000000000001'$sql$,
    'active device authorizes patient write'
  );

  perform pg_temp.actor(
    'd1000000-0000-4000-8000-000000000002',
    'd3000000-0000-4000-8000-000000000002'
  );
  perform pg_temp.expect_forbidden(
    $sql$update public.patients set phone_number = '+8801700099996'
          where id = 'd4000000-0000-4000-8000-000000000001'$sql$,
    'revoked device is refused'
  );

  perform pg_temp.actor(
    'd1000000-0000-4000-8000-000000000002',
    'd3000000-0000-4000-8000-000000000003'
  );
  perform pg_temp.expect_forbidden(
    $sql$update public.patients set phone_number = '+8801700099995'
          where id = 'd4000000-0000-4000-8000-000000000001'$sql$,
    'suspended device is refused'
  );

  perform pg_temp.actor(
    'd1000000-0000-4000-8000-000000000002',
    'd3000000-0000-4000-8000-000000000004'
  );
  perform pg_temp.expect_forbidden(
    $sql$update public.patients set phone_number = '+8801700099994'
          where id = 'd4000000-0000-4000-8000-000000000001'$sql$,
    'another user''s device is refused'
  );

  perform pg_temp.actor(
    'd1000000-0000-4000-8000-000000000002',
    'd3000000-0000-4000-8000-000000000005'
  );
  perform pg_temp.expect_forbidden(
    $sql$update public.patients set phone_number = '+8801700099993'
          where id = 'd4000000-0000-4000-8000-000000000001'$sql$,
    'another tenant''s device is refused'
  );

  -- 10. Suspended membership.
  perform pg_temp.actor('d1000000-0000-4000-8000-000000000009');
  perform pg_temp.expect_forbidden(
    $sql$update public.patients set phone_number = '+8801700099992'
          where id = 'd4000000-0000-4000-8000-000000000001'$sql$,
    'suspended membership is refused'
  );

  -- 11. Expired valid_until with status still active: the exact-instant guard
  --     must refuse before the sweep runs.
  --
  --     Reset E's fixture inside this transaction. The one-minute pg_cron
  --     sweep may already have expired the seeded row between the seed and
  --     this test; without the reset, the later sweep assertion would find no
  --     active row and would not be testing the WAL event.
  perform pg_temp.actor(null);
  update public.memberships
     set status = 'active',
         valid_until = clock_timestamp() - interval '1 second'
   where id = 'd2000000-0000-4000-8000-00000000000a';

  perform pg_temp.actor('d1000000-0000-4000-8000-00000000000a');
  perform pg_temp.expect_forbidden(
    $sql$update public.patients set phone_number = '+8801700099991'
          where id = 'd4000000-0000-4000-8000-000000000001'$sql$,
    'past valid_until is refused before the sweep'
  );

  -- 12. Role grant revocation is effective immediately, and the grant can be
  --     restored without restarting anything.
  delete from public.role_permissions
   where role_key = 'medical_officer' and permission_key = 'patient.write';
  perform pg_temp.actor('d1000000-0000-4000-8000-000000000002');
  perform pg_temp.expect_forbidden(
    $sql$update public.patients set phone_number = '+8801700099990'
          where id = 'd4000000-0000-4000-8000-000000000001'$sql$,
    'revoked patient.write grant is refused'
  );
  insert into public.role_permissions (role_key, permission_key)
  values ('medical_officer', 'patient.write')
  on conflict do nothing;

  -- 13. Self-escalation is refused. A second administrator can grant, and can
  --     renew the window, because the guard is about self-service only.
  perform pg_temp.actor('d1000000-0000-4000-8000-000000000002');
  perform pg_temp.expect_forbidden(
    $sql$insert into public.memberships
           (id, tenant_id, user_id, role_key, status, valid_from)
         values
           ('de000000-0000-4000-8000-000000000020',
            'd0000000-0000-4000-8000-000000000001',
            'd1000000-0000-4000-8000-000000000002',
            'hospital_super_admin', 'active', now())$sql$,
    'self-granted super-admin membership is refused'
  );
  perform pg_temp.expect_forbidden(
    $sql$update public.memberships
            set valid_until = now() + interval '1 year'
          where id = 'd2000000-0000-4000-8000-000000000002'$sql$,
    'self-extension of membership is refused'
  );
  perform pg_temp.expect_forbidden(
    $sql$update public.memberships
            set status = 'suspended'
          where id = 'd2000000-0000-4000-8000-000000000002'$sql$,
    'self-suspension of membership is refused'
  );
  perform pg_temp.expect_forbidden(
    $sql$update public.memberships
            set user_id = 'd1000000-0000-4000-8000-000000000001'
          where id = 'd2000000-0000-4000-8000-000000000002'$sql$,
    'membership subject cannot be moved onto another identity'
  );

  perform pg_temp.actor('d1000000-0000-4000-8000-000000000001');
  perform pg_temp.expect_ok(
    $sql$update public.memberships
            set valid_until = now() + interval '1 year'
          where id = 'd2000000-0000-4000-8000-000000000002'$sql$,
    'second administrator renews membership'
  );
  perform pg_temp.expect_ok(
    $sql$insert into public.memberships
           (id, tenant_id, user_id, role_key, status, valid_from)
         values
           ('de000000-0000-4000-8000-000000000021',
            'd0000000-0000-4000-8000-000000000001',
            'd1000000-0000-4000-8000-000000000003',
            'auditor', 'active', now())$sql$,
    'second administrator grants a membership'
  );

  -- 14. Cross-tenant writes are refused, and the second tenant's own doctor is
  --     allowed. A row cannot be moved between tenants or patients in place.
  perform pg_temp.actor('d1000000-0000-4000-8000-000000000002');
  perform pg_temp.expect_forbidden(
    $sql$update public.patients set phone_number = '+8801700099989'
          where id = 'd4000000-0000-4000-8000-000000000005'$sql$,
    'doctor writes a patient in another tenant'
  );
  perform pg_temp.expect_forbidden(
    $sql$insert into public.appointments
           (id, tenant_id, facility_id, patient_id, provider_id, booked_by,
            appointment_code, scheduled_start, scheduled_end)
         values
           ('de000000-0000-4000-8000-000000000030',
            'd0000000-0000-4000-8000-000000000001',
            'd0000000-0000-4000-8000-000000000002',
            'd4000000-0000-4000-8000-000000000005',
            'd1000000-0000-4000-8000-000000000002',
            'd1000000-0000-4000-8000-000000000002',
            'DEV-CROSS', now() + interval '2 days',
            now() + interval '2 days 1 hour')$sql$,
    'appointment in tenant A names a patient in tenant B'
  );
  perform pg_temp.expect_forbidden(
    $sql$update public.patients
            set tenant_id = 'd0000000-0000-4000-8000-000000000011'
          where id = 'd4000000-0000-4000-8000-000000000001'$sql$,
    'tenant_id is immutable'
  );
  perform pg_temp.expect_forbidden(
    $sql$update public.clinical_encounters
            set patient_id = 'd4000000-0000-4000-8000-000000000002'
          where id = 'd6000000-0000-4000-8000-000000000001'$sql$,
    'patient_id is immutable'
  );

  perform pg_temp.actor('d1000000-0000-4000-8000-00000000000b');
  perform pg_temp.expect_ok(
    $sql$update public.patients set phone_number = '+8801700099988'
          where id = 'd4000000-0000-4000-8000-000000000005'$sql$,
    'tenant B doctor edits tenant B patient'
  );

  -- 15. A merge names two patients. The caller must be in scope for both; an
  --     administrator is. Doctor D is assigned patient A but not patient D.
  perform pg_temp.actor('d1000000-0000-4000-8000-000000000002');
  perform pg_temp.expect_forbidden(
    $sql$insert into public.patient_merge_history
           (id, tenant_id, surviving_patient_id, merged_patient_id, merged_by,
            reason)
         values
           ('de000000-0000-4000-8000-000000000040',
            'd0000000-0000-4000-8000-000000000001',
            'd4000000-0000-4000-8000-000000000001',
            'd4000000-0000-4000-8000-000000000004',
            'd1000000-0000-4000-8000-000000000002',
            'Synthetic merge authorization test')$sql$,
    'doctor merges a patient outside assignment scope'
  );
  perform pg_temp.actor('d1000000-0000-4000-8000-000000000001');
  perform pg_temp.expect_ok(
    $sql$insert into public.patient_merge_history
           (id, tenant_id, surviving_patient_id, merged_patient_id, merged_by,
            reason)
         values
           ('de000000-0000-4000-8000-000000000041',
            'd0000000-0000-4000-8000-000000000001',
            'd4000000-0000-4000-8000-000000000001',
            'd4000000-0000-4000-8000-000000000004',
            'd1000000-0000-4000-8000-000000000001',
            'Synthetic merge authorization test')$sql$,
    'administrator merges two tenant patients'
  );

  -- 16. The patient role has no staff write permission. A portal link alone
  --     does not bypass the permission gate; portal-scoped writes would need a
  --     new portal permission and a matching RLS policy.
  perform pg_temp.actor('d1000000-0000-4000-8000-000000000006');
  perform pg_temp.expect_forbidden(
    $sql$update public.patients set phone_number = '+8801700099987'
          where id = 'd4000000-0000-4000-8000-000000000001'$sql$,
    'portal patient cannot write a staff patient row'
  );
  perform pg_temp.expect_forbidden(
    $sql$insert into public.appointments
           (id, tenant_id, facility_id, patient_id, provider_id, booked_by,
            appointment_code, scheduled_start, scheduled_end)
         values
           ('de000000-0000-4000-8000-000000000050',
            'd0000000-0000-4000-8000-000000000001',
            'd0000000-0000-4000-8000-000000000002',
            'd4000000-0000-4000-8000-000000000001',
            'd1000000-0000-4000-8000-000000000002',
            'd1000000-0000-4000-8000-000000000006',
            'DEV-PORTAL', now() + interval '3 days',
            now() + interval '3 days 30 minutes')$sql$,
    'portal patient cannot book without appointment.write'
  );

  -- 17. Clinical conflict: the second overlapping booking is refused by the
  --     exclusion constraint with SQLSTATE 23P01, which the handler classifies
  --     as a conflict rather than an internal error.
  perform pg_temp.actor('d1000000-0000-4000-8000-000000000002');
  perform pg_temp.expect_ok(
    $sql$insert into public.appointments
           (id, tenant_id, facility_id, patient_id, provider_id, booked_by,
            appointment_code, scheduled_start, scheduled_end)
         values
           ('de000000-0000-4000-8000-000000000060',
            'd0000000-0000-4000-8000-000000000001',
            'd0000000-0000-4000-8000-000000000002',
            'd4000000-0000-4000-8000-000000000001',
            'd1000000-0000-4000-8000-000000000002',
            'd1000000-0000-4000-8000-000000000002',
            'DEV-APPT-1', now() + interval '4 days',
            now() + interval '4 days 1 hour')$sql$,
    'first appointment books the slot'
  );
  perform pg_temp.expect_state(
    '23P01',
    $sql$insert into public.appointments
           (id, tenant_id, facility_id, patient_id, provider_id, booked_by,
            appointment_code, scheduled_start, scheduled_end)
         values
           ('de000000-0000-4000-8000-000000000061',
            'd0000000-0000-4000-8000-000000000001',
            'd0000000-0000-4000-8000-000000000002',
            'd4000000-0000-4000-8000-000000000001',
            'd1000000-0000-4000-8000-000000000002',
            'd1000000-0000-4000-8000-000000000002',
            'DEV-APPT-2', now() + interval '4 days 30 minutes',
            now() + interval '4 days 1 hour 30 minutes')$sql$,
    'overlapping appointment is a conflict'
  );

  -- 18. The sweep turns an elapsed active membership into a WAL event. Before
  --     the sweep, E's write was refused by the exact-instant guard; after it,
  --     status is expired and updated_at moved.
  select updated_at into v_before
    from public.memberships
   where id = 'd2000000-0000-4000-8000-00000000000a';

  perform pg_temp.actor(null);
  perform nodex.expire_memberships();

  select status, updated_at into v_status, v_after
    from public.memberships
   where id = 'd2000000-0000-4000-8000-00000000000a';

  if v_status <> 'expired' then
    raise exception 'FAIL expiry sweep: expected expired, got %', v_status;
  end if;
  if v_after <= v_before then
    raise exception 'FAIL expiry sweep: updated_at did not advance (% -> %)', v_before, v_after;
  end if;
  raise notice 'ok expiry sweep: status=expired and updated_at advanced';

  perform pg_temp.actor('d1000000-0000-4000-8000-00000000000a');
  perform pg_temp.expect_forbidden(
    $sql$update public.patients set phone_number = '+8801700099986'
          where id = 'd4000000-0000-4000-8000-000000000001'$sql$,
    'write after expiry sweep is refused'
  );

  raise notice 'all authorization integration assertions passed';
end;
$test$;

rollback;
