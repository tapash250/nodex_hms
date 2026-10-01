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
  ('medical_officer', 'triage.write'),
  ('medical_officer', 'triage.read'),
  ('medical_officer', 'er.visit.write'),
  ('medical_officer', 'discharge.finalize'),
  ('medical_officer', 'transfusion.finalize'),
  ('medical_officer', 'appointment.read'),
  ('medical_officer', 'appointment.write'),
  ('medical_officer', 'report.read'),
  ('medical_officer', 'ai_output.review'),
  ('medical_officer', 'clinical_event.read'),
  ('medical_officer', 'icu.bed.assign'),
  ('medical_officer', 'icu.vitals.record'),
  ('medical_officer', 'icu.handover.record'),
  ('medical_officer', 'ventilator.event.record'),
  ('medical_officer', 'transfusion.request'),
  ('medical_officer', 'transfusion.administer'),
  ('medical_officer', 'imaging_order.write'),
  ('medical_officer', 'imaging_report.enter'),
  ('medical_officer', 'imaging_report.verify'),
  ('medical_officer', 'physio_session.write'),
  ('medical_officer', 'physio_exercise.write'),
  ('medical_officer', 'physio_note.write'),
  ('medical_officer', 'diet_assessment.write'),
  ('medical_officer', 'diet_plan.write'),
  ('medical_officer', 'diet_plan.approve'),
  ('medical_officer', 'tele_consultation.write'),
  ('medical_officer', 'tele_vitals.record'),
  ('medical_officer', 'tele_archive.write'),
  ('medical_officer', 'ot.schedule'),
  ('medical_officer', 'ot.record'),
  ('medical_officer', 'ot.finalize');

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
  ('nursing_staff', 'triage.write'),
  ('nursing_staff', 'triage.read'),
  ('nursing_staff', 'er.visit.write'),
  ('nursing_staff', 'lab_order.write'),
  ('nursing_staff', 'appointment.read'),
  ('nursing_staff', 'ai_output.review'),
  ('nursing_staff', 'icu.vitals.record'),
  ('nursing_staff', 'icu.handover.record'),
  ('nursing_staff', 'ventilator.event.record'),
  ('nursing_staff', 'transfusion.administer'),
  ('nursing_staff', 'imaging_order.write'),
  ('nursing_staff', 'physio_session.write'),
  ('nursing_staff', 'physio_note.write'),
  ('nursing_staff', 'diet_intake.record'),
  ('nursing_staff', 'tele_vitals.record'),
  ('nursing_staff', 'ot.record');

-- Diagnostic / Lab Technician
insert into public.role_permissions (role_key, permission_key)
values
  ('lab_technician', 'patient.read'),
  ('lab_technician', 'lab_order.write'),
  ('lab_technician', 'lab_result.enter'),
  ('lab_technician', 'inventory.movement'),
  ('lab_technician', 'appointment.read'),
  ('lab_technician', 'imaging_order.write'),
  ('lab_technician', 'imaging_study.record'),
  ('lab_technician', 'imaging_report.enter'),
  ('lab_technician', 'blood_unit.write');

-- Pharmacist
insert into public.role_permissions (role_key, permission_key)
values
  ('pharmacist', 'patient.read'),
  ('pharmacist', 'encounter.read'),
  ('pharmacist', 'pharmacy.dispense'),
  ('pharmacist', 'inventory.movement'),
  ('pharmacist', 'billing.read'),
  ('pharmacist', 'ai_output.review'),
  ('pharmacist', 'triage.read'),
  ('pharmacist', 'er.visit.write');

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
  ('integration_service', 'inventory.movement'),
  ('integration_service', 'imaging_study.record'),
  ('integration_service', 'imaging_report.enter'),
  ('integration_service', 'blood_unit.write');
