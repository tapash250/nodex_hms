-- NODEX development seed for PowerSync and authorization tests.
--
-- THIS FILE IS NOT A MIGRATION AND MUST NEVER RUN AGAINST PRODUCTION.
--
-- It creates a self-contained development tenant with deterministic ids:
-- staff, portal user, patients, beds, encounters, assignments, devices,
-- prescriptions and billing rows. Every statement is idempotent; rerunning it
-- does not duplicate rows and does not reset clinical rows that a test changed.
--
-- Preconditions:
--   1. All migrations through 20260918170000 are applied.
--   2. The caller is the Supabase `postgres` role (or another role that owns
--      public tables and may insert into auth.users).
--   3. The session explicitly opts in:
--
--          set nodex.dev_seed = 'on';
--
--      Then run this file as one transaction. The guard below refuses without
--      that opt-in, so a stray `db push` or production SQL editor paste fails
--      before the first insert.
--
-- The seed sets a transaction-local service_role claim. The patient-scope
-- trigger deliberately rejects a session with no authenticated identity, and a
-- seed is an administrative backfill, not a clinical actor. The claim is local
-- to this transaction and is not a substitute for application authorization.

do $$
begin
  if coalesce(current_setting('nodex.dev_seed', true), '') <> 'on' then
    raise exception using
      message = 'NODEX: development seed refused; run "set nodex.dev_seed = ''on'';" first',
      errcode = '42501';
  end if;
end;
$$;

begin;

select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claim.role', 'service_role', true);
select set_config('request.headers', '{}', true);

-- ---------------------------------------------------------------------------
-- 1. Tenants, facilities, departments and wards.
-- ---------------------------------------------------------------------------

insert into public.tenants
  (id, slug, display_name, legal_name, country_code, timezone, locale, status)
values
  ('d0000000-0000-4000-8000-000000000001', 'nodex-development',
   'NODEX Development Hospital', 'NODEX Development Tenant', 'BD',
   'Asia/Dhaka', 'en', 'active'),
  ('d0000000-0000-4000-8000-000000000011', 'nodex-development-b',
   'NODEX Development Hospital B', 'NODEX Development Tenant B', 'BD',
   'Asia/Dhaka', 'en', 'active')
on conflict (id) do update
  set display_name = excluded.display_name,
      legal_name = excluded.legal_name,
      status = excluded.status;

insert into public.facilities
  (id, tenant_id, code, display_name, facility_type, timezone, status)
values
  ('d0000000-0000-4000-8000-000000000002',
   'd0000000-0000-4000-8000-000000000001',
   'DEV-MAIN', 'Development Main Hospital', 'hospital', 'Asia/Dhaka', 'active'),
  ('d0000000-0000-4000-8000-000000000012',
   'd0000000-0000-4000-8000-000000000011',
   'DEV-B', 'Development Hospital B', 'hospital', 'Asia/Dhaka', 'active')
on conflict (id) do update
  set display_name = excluded.display_name,
      status = excluded.status;

insert into public.departments
  (id, tenant_id, facility_id, code, display_name, specialty, status)
values
  ('d0000000-0000-4000-8000-000000000003',
   'd0000000-0000-4000-8000-000000000001',
   'd0000000-0000-4000-8000-000000000002',
   'DEV-MED', 'Development Medicine', 'Internal Medicine', 'active')
on conflict (id) do update
  set display_name = excluded.display_name,
      status = excluded.status;

insert into public.wards
  (id, tenant_id, facility_id, department_id, code, display_name, ward_type,
   floor_label, bed_capacity, status)
values
  ('d0000000-0000-4000-8000-000000000004',
   'd0000000-0000-4000-8000-000000000001',
   'd0000000-0000-4000-8000-000000000002',
   'd0000000-0000-4000-8000-000000000003',
   'DEV-W1', 'Development Ward 1', 'general', 'Level 1', 4, 'active'),
  ('d0000000-0000-4000-8000-000000000005',
   'd0000000-0000-4000-8000-000000000001',
   'd0000000-0000-4000-8000-000000000002',
   'd0000000-0000-4000-8000-000000000003',
   'DEV-W2', 'Development Ward 2', 'general', 'Level 2', 4, 'active'),
  ('d0000000-0000-4000-8000-000000000013',
   'd0000000-0000-4000-8000-000000000011',
   'd0000000-0000-4000-8000-000000000012',
   null,
   'DEV-B1', 'Development Ward B1', 'general', 'Level 1', 2, 'active')
on conflict (id) do update
  set display_name = excluded.display_name,
      status = excluded.status;

-- ---------------------------------------------------------------------------
-- 2. Auth stubs and application identities.
--
-- These are identities without passwords. They exist so auth.users satisfies
-- the app_users foreign key and so a test can mint a JWT for the subject. Do
-- not use them to sign in interactively.
-- ---------------------------------------------------------------------------

insert into auth.users
  (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
   raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('d1000000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'dev.admin@nodex.test', '', now(),
   '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('d1000000-0000-4000-8000-000000000002', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'dev.doctor@nodex.test', '', now(),
   '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('d1000000-0000-4000-8000-000000000003', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'dev.doctor.unassigned@nodex.test', '', now(),
   '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('d1000000-0000-4000-8000-000000000004', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'dev.nurse@nodex.test', '', now(),
   '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('d1000000-0000-4000-8000-000000000005', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'dev.billing@nodex.test', '', now(),
   '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('d1000000-0000-4000-8000-000000000006', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'dev.portal@nodex.test', '', now(),
   '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('d1000000-0000-4000-8000-000000000007', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'dev.lab@nodex.test', '', now(),
   '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('d1000000-0000-4000-8000-000000000008', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'dev.pharmacist@nodex.test', '', now(),
   '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('d1000000-0000-4000-8000-000000000009', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'dev.doctor.suspended@nodex.test', '', now(),
   '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('d1000000-0000-4000-8000-00000000000a', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'dev.doctor.expired@nodex.test', '', now(),
   '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('d1000000-0000-4000-8000-00000000000b', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'dev.doctor.b@nodex.test', '', now(),
   '{"provider":"email","providers":["email"]}', '{}', now(), now())
on conflict do nothing;

-- GoTrue scans these token columns into Go strings. A NULL value makes the
-- password grant fail with "converting NULL to string is unsupported", even
-- though the row is otherwise valid. The seed inserts the minimum auth row, so
-- normalise the token columns to empty strings. This also repairs rows created
-- by an earlier run of the seed.
update auth.users
   set confirmation_token = coalesce(confirmation_token, ''),
       recovery_token = coalesce(recovery_token, ''),
       email_change_token_new = coalesce(email_change_token_new, ''),
       email_change = coalesce(email_change, ''),
       phone_change = coalesce(phone_change, ''),
       phone_change_token = coalesce(phone_change_token, ''),
       email_change_token_current = coalesce(email_change_token_current, ''),
       reauthentication_token = coalesce(reauthentication_token, '')
 where email like 'dev.%@nodex.test';

insert into public.app_users
  (id, primary_tenant_id, employee_code, full_name, display_name, email,
   designation, status)
values
  ('d1000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-000000000001',
   'DEV-ADMIN', 'Development Administrator', 'Dev Admin', 'dev.admin@nodex.test',
   'Hospital Administrator', 'active'),
  ('d1000000-0000-4000-8000-000000000002', 'd0000000-0000-4000-8000-000000000001',
   'DEV-DOC', 'Development Doctor', 'Dev Doctor', 'dev.doctor@nodex.test',
   'Medical Officer', 'active'),
  ('d1000000-0000-4000-8000-000000000003', 'd0000000-0000-4000-8000-000000000001',
   'DEV-DOC-U', 'Unassigned Development Doctor', 'Dev Doctor U',
   'dev.doctor.unassigned@nodex.test', 'Medical Officer', 'active'),
  ('d1000000-0000-4000-8000-000000000004', 'd0000000-0000-4000-8000-000000000001',
   'DEV-NURSE', 'Development Nurse', 'Dev Nurse', 'dev.nurse@nodex.test',
   'Nursing Staff', 'active'),
  ('d1000000-0000-4000-8000-000000000005', 'd0000000-0000-4000-8000-000000000001',
   'DEV-BILL', 'Development Billing', 'Dev Billing', 'dev.billing@nodex.test',
   'Billing Officer', 'active'),
  ('d1000000-0000-4000-8000-000000000006', 'd0000000-0000-4000-8000-000000000001',
   'DEV-PORTAL', 'Development Portal Patient', 'Dev Portal',
   'dev.portal@nodex.test', 'Patient', 'active'),
  ('d1000000-0000-4000-8000-000000000007', 'd0000000-0000-4000-8000-000000000001',
   'DEV-LAB', 'Development Lab Technician', 'Dev Lab', 'dev.lab@nodex.test',
   'Lab Technician', 'active'),
  ('d1000000-0000-4000-8000-000000000008', 'd0000000-0000-4000-8000-000000000001',
   'DEV-PHARM', 'Development Pharmacist', 'Dev Pharmacist',
   'dev.pharmacist@nodex.test', 'Pharmacist', 'active'),
  ('d1000000-0000-4000-8000-000000000009', 'd0000000-0000-4000-8000-000000000001',
   'DEV-DOC-S', 'Suspended Development Doctor', 'Dev Doctor S',
   'dev.doctor.suspended@nodex.test', 'Medical Officer', 'active'),
  ('d1000000-0000-4000-8000-00000000000a', 'd0000000-0000-4000-8000-000000000001',
   'DEV-DOC-E', 'Expired Development Doctor', 'Dev Doctor E',
   'dev.doctor.expired@nodex.test', 'Medical Officer', 'active'),
  ('d1000000-0000-4000-8000-00000000000b', 'd0000000-0000-4000-8000-000000000011',
   'DEV-DOC-B', 'Development Doctor B', 'Dev Doctor B',
   'dev.doctor.b@nodex.test', 'Medical Officer', 'active')
on conflict (id) do update
  set primary_tenant_id = excluded.primary_tenant_id,
      full_name = excluded.full_name,
      status = excluded.status;

-- ---------------------------------------------------------------------------
-- 3. Memberships. The validity windows are deliberate:
--    - expired doctor: status still active, valid_until in the past, so the
--      sweep has work to do and the write guard is tested before the sweep;
--    - suspended doctor: status suspended;
--    - nurse: facility and ward narrowed to DEV-MAIN / DEV-W1.
-- ---------------------------------------------------------------------------

insert into public.memberships
  (id, tenant_id, user_id, role_key, facility_id, ward_id, status,
   valid_from, valid_until, granted_by)
values
  ('d2000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-000000000001',
   'd1000000-0000-4000-8000-000000000001', 'hospital_super_admin',
   null, null, 'active', now() - interval '1 day', null,
   'd1000000-0000-4000-8000-000000000001'),
  ('d2000000-0000-4000-8000-000000000002', 'd0000000-0000-4000-8000-000000000001',
   'd1000000-0000-4000-8000-000000000002', 'medical_officer',
   null, null, 'active', now() - interval '1 day', null,
   'd1000000-0000-4000-8000-000000000001'),
  ('d2000000-0000-4000-8000-000000000003', 'd0000000-0000-4000-8000-000000000001',
   'd1000000-0000-4000-8000-000000000003', 'medical_officer',
   null, null, 'active', now() - interval '1 day', null,
   'd1000000-0000-4000-8000-000000000001'),
  ('d2000000-0000-4000-8000-000000000004', 'd0000000-0000-4000-8000-000000000001',
   'd1000000-0000-4000-8000-000000000004', 'nursing_staff',
   'd0000000-0000-4000-8000-000000000002', 'd0000000-0000-4000-8000-000000000004',
   'active', now() - interval '1 day', null,
   'd1000000-0000-4000-8000-000000000001'),
  ('d2000000-0000-4000-8000-000000000005', 'd0000000-0000-4000-8000-000000000001',
   'd1000000-0000-4000-8000-000000000005', 'billing_accounts',
   null, null, 'active', now() - interval '1 day', null,
   'd1000000-0000-4000-8000-000000000001'),
  ('d2000000-0000-4000-8000-000000000006', 'd0000000-0000-4000-8000-000000000001',
   'd1000000-0000-4000-8000-000000000006', 'patient',
   null, null, 'active', now() - interval '1 day', null,
   'd1000000-0000-4000-8000-000000000001'),
  ('d2000000-0000-4000-8000-000000000007', 'd0000000-0000-4000-8000-000000000001',
   'd1000000-0000-4000-8000-000000000007', 'lab_technician',
   null, null, 'active', now() - interval '1 day', null,
   'd1000000-0000-4000-8000-000000000001'),
  ('d2000000-0000-4000-8000-000000000008', 'd0000000-0000-4000-8000-000000000001',
   'd1000000-0000-4000-8000-000000000008', 'pharmacist',
   null, null, 'active', now() - interval '1 day', null,
   'd1000000-0000-4000-8000-000000000001'),
  ('d2000000-0000-4000-8000-000000000009', 'd0000000-0000-4000-8000-000000000001',
   'd1000000-0000-4000-8000-000000000009', 'medical_officer',
   null, null, 'suspended', now() - interval '1 day', null,
   'd1000000-0000-4000-8000-000000000001'),
  ('d2000000-0000-4000-8000-00000000000a', 'd0000000-0000-4000-8000-000000000001',
   'd1000000-0000-4000-8000-00000000000a', 'medical_officer',
   null, null, 'active', now() - interval '2 days', now() - interval '1 hour',
   'd1000000-0000-4000-8000-000000000001'),
  ('d2000000-0000-4000-8000-00000000000b', 'd0000000-0000-4000-8000-000000000011',
   'd1000000-0000-4000-8000-00000000000b', 'medical_officer',
   null, null, 'active', now() - interval '1 day', null,
   'd1000000-0000-4000-8000-000000000001')
on conflict (id) do update
  set status = excluded.status,
      valid_from = excluded.valid_from,
      valid_until = excluded.valid_until,
      facility_id = excluded.facility_id,
      ward_id = excluded.ward_id;

-- ---------------------------------------------------------------------------
-- 4. Devices. The revoked and suspended rows exist so the upload path can be
--    tested against them. They remain in the identity stream on purpose: the
--    client learns that its device was revoked from that row and wipes local
--    data; the server refuses every upload from the same device.
-- ---------------------------------------------------------------------------

insert into public.devices
  (id, tenant_id, device_fingerprint, display_name, platform, form_factor,
   enrolled_by, assigned_user_id, assigned_facility_id, status, revoked_at,
   revoked_reason)
values
  ('d3000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-000000000001',
   'dev-doctor-active', 'Doctor active device', 'android', 'phone',
   'd1000000-0000-4000-8000-000000000001', 'd1000000-0000-4000-8000-000000000002',
   'd0000000-0000-4000-8000-000000000002', 'active', null, null),
  ('d3000000-0000-4000-8000-000000000002', 'd0000000-0000-4000-8000-000000000001',
   'dev-doctor-revoked', 'Doctor revoked device', 'android', 'phone',
   'd1000000-0000-4000-8000-000000000001', 'd1000000-0000-4000-8000-000000000002',
   'd0000000-0000-4000-8000-000000000002', 'revoked', now() - interval '1 day',
   'Synthetic revocation fixture'),
  ('d3000000-0000-4000-8000-000000000003', 'd0000000-0000-4000-8000-000000000001',
   'dev-doctor-suspended', 'Doctor suspended device', 'android', 'phone',
   'd1000000-0000-4000-8000-000000000001', 'd1000000-0000-4000-8000-000000000002',
   'd0000000-0000-4000-8000-000000000002', 'suspended', null, null),
  ('d3000000-0000-4000-8000-000000000004', 'd0000000-0000-4000-8000-000000000001',
   'dev-doctor-u', 'Unassigned doctor device', 'android', 'phone',
   'd1000000-0000-4000-8000-000000000001', 'd1000000-0000-4000-8000-000000000003',
   'd0000000-0000-4000-8000-000000000002', 'active', null, null),
  ('d3000000-0000-4000-8000-000000000005', 'd0000000-0000-4000-8000-000000000011',
   'dev-doctor-b', 'Tenant B doctor device', 'android', 'phone',
   'd1000000-0000-4000-8000-00000000000b', 'd1000000-0000-4000-8000-00000000000b',
   'd0000000-0000-4000-8000-000000000012', 'active', null, null)
on conflict (id) do update
  set status = excluded.status,
      revoked_at = excluded.revoked_at,
      revoked_reason = excluded.revoked_reason;

-- ---------------------------------------------------------------------------
-- 5. Patients, beds and encounters.
-- ---------------------------------------------------------------------------

insert into public.patients
  (id, tenant_id, mrn, first_name, last_name, date_of_birth, gender,
   phone_number, is_active, created_by)
values
  ('d4000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-000000000001',
   'DEV-MRN-001', 'Amina', 'Rahman', '1980-01-01', 'female', '+8801700000001', true,
   'd1000000-0000-4000-8000-000000000001'),
  ('d4000000-0000-4000-8000-000000000002', 'd0000000-0000-4000-8000-000000000001',
   'DEV-MRN-002', 'Bashir', 'Ahmed', '1975-05-12', 'male', '+8801700000002', true,
   'd1000000-0000-4000-8000-000000000001'),
  ('d4000000-0000-4000-8000-000000000003', 'd0000000-0000-4000-8000-000000000001',
   'DEV-MRN-003', 'Chandni', 'Das', '1990-09-23', 'female', '+8801700000003', true,
   'd1000000-0000-4000-8000-000000000001'),
  ('d4000000-0000-4000-8000-000000000004', 'd0000000-0000-4000-8000-000000000001',
   'DEV-MRN-004', 'Daud', 'Karim', '1968-03-04', 'male', '+8801700000004', true,
   'd1000000-0000-4000-8000-000000000001'),
  ('d4000000-0000-4000-8000-000000000005', 'd0000000-0000-4000-8000-000000000011',
   'DEV-MRN-005', 'Esha', 'Binte', '1985-11-30', 'female', '+8801700000005', true,
   'd1000000-0000-4000-8000-00000000000b')
on conflict do nothing;

insert into public.beds
  (id, tenant_id, ward_id, bed_code, bed_type, status)
values
  ('d5000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-000000000001',
   'd0000000-0000-4000-8000-000000000004', 'DEV-BED-1', 'general', 'available'),
  ('d5000000-0000-4000-8000-000000000002', 'd0000000-0000-4000-8000-000000000001',
   'd0000000-0000-4000-8000-000000000005', 'DEV-BED-2', 'general', 'available'),
  ('d5000000-0000-4000-8000-000000000003', 'd0000000-0000-4000-8000-000000000011',
   'd0000000-0000-4000-8000-000000000013', 'DEV-BED-B1', 'general', 'available')
on conflict (id) do update
  set status = excluded.status;

insert into public.clinical_encounters
  (id, tenant_id, patient_id, attending_physician_id, encounter_type, status,
   signed_at, created_by)
values
  ('d6000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-000000000001',
   'd4000000-0000-4000-8000-000000000001', 'd1000000-0000-4000-8000-000000000002',
   'outpatient', 'in_progress', null, 'd1000000-0000-4000-8000-000000000002'),
  ('d6000000-0000-4000-8000-000000000002', 'd0000000-0000-4000-8000-000000000001',
   'd4000000-0000-4000-8000-000000000002', 'd1000000-0000-4000-8000-000000000003',
   'outpatient', 'in_progress', null, 'd1000000-0000-4000-8000-000000000003'),
  ('d6000000-0000-4000-8000-000000000003', 'd0000000-0000-4000-8000-000000000001',
   'd4000000-0000-4000-8000-000000000003', 'd1000000-0000-4000-8000-000000000002',
   'outpatient', 'planned', null, 'd1000000-0000-4000-8000-000000000002'),
  ('d6000000-0000-4000-8000-000000000004', 'd0000000-0000-4000-8000-000000000001',
   'd4000000-0000-4000-8000-000000000004', 'd1000000-0000-4000-8000-000000000003',
   'inpatient', 'signed_and_locked', now() - interval '1 day',
   'd1000000-0000-4000-8000-000000000003'),
  ('d6000000-0000-4000-8000-000000000005', 'd0000000-0000-4000-8000-000000000011',
   'd4000000-0000-4000-8000-000000000005', 'd1000000-0000-4000-8000-00000000000b',
   'outpatient', 'in_progress', null, 'd1000000-0000-4000-8000-00000000000b')
on conflict do nothing;

-- Triage is the pre-assignment intake surface. The row lets the authorization
-- tests prove that a triage writer may amend an assessment before any
-- bed assignment exists.
insert into public.triage_assessments
  (id, tenant_id, patient_id, encounter_id, assessed_by, acuity,
   chief_complaint, disposition)
values
  ('d9000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-000000000001',
   'd4000000-0000-4000-8000-000000000001', 'd6000000-0000-4000-8000-000000000001',
   'd1000000-0000-4000-8000-000000000002', 'esi3', 'Development chest pain',
   'admit')
on conflict do nothing;

-- A concluded assignment is inserted active and then concluded: the assignment
-- guard refuses to create a concluded row directly.
insert into public.doctor_assignments
  (id, tenant_id, doctor_id, patient_id, assignment_type, status, assigned_at)
values
  ('d7000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-000000000001',
   'd1000000-0000-4000-8000-000000000002', 'd4000000-0000-4000-8000-000000000001',
   'primary_attending', 'active', now() - interval '2 days'),
  ('d7000000-0000-4000-8000-000000000002', 'd0000000-0000-4000-8000-000000000001',
   'd1000000-0000-4000-8000-000000000003', 'd4000000-0000-4000-8000-000000000002',
   'primary_attending', 'active', now() - interval '2 days'),
  ('d7000000-0000-4000-8000-000000000003', 'd0000000-0000-4000-8000-000000000001',
   'd1000000-0000-4000-8000-000000000002', 'd4000000-0000-4000-8000-000000000004',
   'primary_attending', 'active', now() - interval '3 days'),
  ('d7000000-0000-4000-8000-000000000004', 'd0000000-0000-4000-8000-000000000011',
   'd1000000-0000-4000-8000-00000000000b', 'd4000000-0000-4000-8000-000000000005',
   'primary_attending', 'active', now() - interval '2 days'),
  ('d7000000-0000-4000-8000-000000000005', 'd0000000-0000-4000-8000-000000000001',
   'd1000000-0000-4000-8000-000000000009', 'd4000000-0000-4000-8000-000000000001',
   'primary_attending', 'active', now() - interval '2 days'),
  ('d7000000-0000-4000-8000-000000000006', 'd0000000-0000-4000-8000-000000000001',
   'd1000000-0000-4000-8000-00000000000a', 'd4000000-0000-4000-8000-000000000001',
   'primary_attending', 'active', now() - interval '2 days')
on conflict do nothing;

update public.doctor_assignments
   set status = 'concluded',
       concluded_at = now() - interval '1 day'
 where id = 'd7000000-0000-4000-8000-000000000003'
   and status = 'active';

insert into public.bed_assignments
  (id, tenant_id, bed_id, patient_id, encounter_id, assigned_by, status,
   admitted_at)
values
  ('d8000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-000000000001',
   'd5000000-0000-4000-8000-000000000001', 'd4000000-0000-4000-8000-000000000004',
   'd6000000-0000-4000-8000-000000000004', 'd1000000-0000-4000-8000-000000000004',
   'active', now() - interval '1 day')
on conflict do nothing;

-- The portal link is the patient's read scope and, if a portal-scoped write
-- permission is added later, the write scope. It is revoked by timestamp, not
-- by deleting the row.
insert into public.patient_portal_links
  (id, tenant_id, patient_id, portal_user_id, created_by)
values
  ('d9000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-000000000001',
   'd4000000-0000-4000-8000-000000000001', 'd1000000-0000-4000-8000-000000000006',
   'd1000000-0000-4000-8000-000000000001')
on conflict (id) do update
  set revoked_at = null;

-- ---------------------------------------------------------------------------
-- 6. Pharmacy and billing fixtures for the parent-child spoof test.
--    RX-A belongs to patient A; RX-B belongs to patient B. A dispense that
--    names RX-A but an item from RX-B must be refused by the chain check.
-- ---------------------------------------------------------------------------

insert into public.prescriptions
  (id, tenant_id, patient_id, encounter_id, prescribed_by, prescription_code,
   version, status)
values
  ('da000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-000000000001',
   'd4000000-0000-4000-8000-000000000001', 'd6000000-0000-4000-8000-000000000001',
   'd1000000-0000-4000-8000-000000000002', 'DEV-RX-A', 1, 'draft'),
  ('da000000-0000-4000-8000-000000000002', 'd0000000-0000-4000-8000-000000000001',
   'd4000000-0000-4000-8000-000000000002', 'd6000000-0000-4000-8000-000000000002',
   'd1000000-0000-4000-8000-000000000003', 'DEV-RX-B', 1, 'draft')
on conflict do nothing;

insert into public.prescription_items
  (id, tenant_id, prescription_id, line_number, drug_code, drug_name,
   dosage_text, quantity_prescribed, status)
values
  ('db000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-000000000001',
   'da000000-0000-4000-8000-000000000001', 1, 'DEV-DRUG-A', 'Development Drug A',
   '1 tablet daily', 10, 'draft'),
  ('db000000-0000-4000-8000-000000000002', 'd0000000-0000-4000-8000-000000000001',
   'da000000-0000-4000-8000-000000000002', 1, 'DEV-DRUG-B', 'Development Drug B',
   '1 tablet daily', 10, 'draft')
on conflict do nothing;

insert into public.invoices
  (id, tenant_id, patient_id, encounter_id, created_by, invoice_code, status,
   total_minor)
values
  ('dc000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-000000000001',
   'd4000000-0000-4000-8000-000000000001', 'd6000000-0000-4000-8000-000000000001',
   'd1000000-0000-4000-8000-000000000005', 'DEV-INV-A', 'draft', 1000),
  ('dc000000-0000-4000-8000-000000000002', 'd0000000-0000-4000-8000-000000000001',
   'd4000000-0000-4000-8000-000000000002', 'd6000000-0000-4000-8000-000000000002',
   'd1000000-0000-4000-8000-000000000005', 'DEV-INV-B', 'draft', 1000)
on conflict do nothing;

insert into public.payments
  (id, tenant_id, invoice_id, recorded_by, amount_minor, method)
values
  ('dd000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-000000000001',
   'dc000000-0000-4000-8000-000000000001', 'd1000000-0000-4000-8000-000000000005',
   1000, 'cash')
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- 7. Leave the session as it was found.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims', '', true);
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claim.role', '', true);
select set_config('request.headers', '{}', true);

commit;
