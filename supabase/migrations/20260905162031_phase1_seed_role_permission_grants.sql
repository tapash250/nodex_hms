-- NODEX Phase 1: role to permission grants implementing the specification role matrix.

-- Hospital Super Admin: full enterprise administration.
insert into public.role_permissions (role_key, permission_key)
select 'hospital_super_admin', key from public.permissions;

-- Medical Officer / Doctor
insert into public.role_permissions (role_key, permission_key)
values
  ('medical_officer', 'staff_directory.read'),
  ('medical_officer', 'patient.read'),
  ('medical_officer', 'patient.write'),
  ('medical_officer', 'encounter.read'),
  ('medical_officer', 'encounter.write'),
  ('medical_officer', 'prescription.draft'),
  ('medical_officer', 'prescription.finalize'),
  ('medical_officer', 'lab_order.write'),
  ('medical_officer', 'lab_result.verify'),
  ('medical_officer', 'bed.assign'),
  ('medical_officer', 'vitals.record'),
  ('medical_officer', 'triage.escalate'),
  ('medical_officer', 'discharge.finalize'),
  ('medical_officer', 'transfusion.finalize'),
  ('medical_officer', 'appointment.read'),
  ('medical_officer', 'appointment.write'),
  ('medical_officer', 'report.read'),
  ('medical_officer', 'ai_output.review'),
  ('medical_officer', 'clinical_event.read');

-- Nursing Staff
insert into public.role_permissions (role_key, permission_key)
values
  ('nursing_staff', 'staff_directory.read'),
  ('nursing_staff', 'patient.read'),
  ('nursing_staff', 'encounter.read'),
  ('nursing_staff', 'vitals.record'),
  ('nursing_staff', 'medication.administer'),
  ('nursing_staff', 'bed.assign'),
  ('nursing_staff', 'triage.escalate'),
  ('nursing_staff', 'lab_order.write'),
  ('nursing_staff', 'appointment.read'),
  ('nursing_staff', 'ai_output.review');

-- Diagnostic / Lab Technician
insert into public.role_permissions (role_key, permission_key)
values
  ('lab_technician', 'patient.read'),
  ('lab_technician', 'lab_order.write'),
  ('lab_technician', 'lab_result.enter'),
  ('lab_technician', 'inventory.movement'),
  ('lab_technician', 'appointment.read');

-- Pharmacist
insert into public.role_permissions (role_key, permission_key)
values
  ('pharmacist', 'patient.read'),
  ('pharmacist', 'encounter.read'),
  ('pharmacist', 'pharmacy.dispense'),
  ('pharmacist', 'inventory.movement'),
  ('pharmacist', 'billing.read'),
  ('pharmacist', 'ai_output.review');

-- Billing & Accounts
insert into public.role_permissions (role_key, permission_key)
values
  ('billing_accounts', 'patient.read'),
  ('billing_accounts', 'billing.read'),
  ('billing_accounts', 'billing.settle'),
  ('billing_accounts', 'appointment.read'),
  ('billing_accounts', 'report.read');

-- Patient: own-record scope is additionally constrained by per-module RLS.
insert into public.role_permissions (role_key, permission_key)
values
  ('patient', 'patient.read'),
  ('patient', 'encounter.read'),
  ('patient', 'appointment.read'),
  ('patient', 'appointment.write'),
  ('patient', 'billing.read');

-- Auditor / Compliance: read-only.
insert into public.role_permissions (role_key, permission_key)
values
  ('auditor', 'audit.read'),
  ('auditor', 'clinical_event.read'),
  ('auditor', 'ai_governance.read'),
  ('auditor', 'report.read'),
  ('auditor', 'membership.read'),
  ('auditor', 'staff_directory.read'),
  ('auditor', 'patient.read');

-- System / Integration Service: narrow, explicit scope.
insert into public.role_permissions (role_key, permission_key)
values
  ('integration_service', 'patient.read'),
  ('integration_service', 'lab_result.enter'),
  ('integration_service', 'inventory.movement');
