-- NODEX Phase 4 follow-up: reconcile the permission catalogue with the
-- role matrix the migrations and mutation rules already depend on.
--
-- The remote development database was provisioned from an earlier revision
-- of 20260905161942_phase1_seed_roles_and_permissions.sql. That revision did
-- not contain the Phase 2/3 permission keys (triage, ER, ICU, OT, imaging,
-- physiotherapy, diet, telemedicine, transfusion, discharge and ward
-- layout). The Phase 4 mutation-scope rules name those keys, so writes to
-- the corresponding tables were refused with 42501 even for the intended
-- roles. This forward migration inserts only the missing catalogue rows and
-- grants. It never deletes or rewrites an existing permission or grant.
--
-- Module codes use the Phase 3 correction: Emergency Department & Triage is
-- M14 and Intensive Care Unit is M15.

insert into public.permissions
  (key, display_name, description, module_code, risk_tier, requires_online)
values
  ('blood_unit.write', 'Write blood units', 'Register, label, reserve, quarantine and discard blood units.', 'M26', 'elevated', false),
  ('diet_assessment.write', 'Write diet assessments', 'Record and finalize clinical nutrition assessments.', 'M21', 'elevated', false),
  ('diet_intake.record', 'Record diet intake', 'Record the portion of planned meals actually taken.', 'M21', 'elevated', false),
  ('diet_plan.approve', 'Approve meal plans', 'Approve or reject generated and authored meal plans.', 'M21', 'high_risk', true),
  ('diet_plan.write', 'Write meal plans', 'Author seven-day meal plans and their daily menus.', 'M21', 'elevated', false),
  ('discharge_clearance.write', 'Clear for discharge', 'Record and grant clinical clearance before a patient leaves.', 'M23', 'elevated', false),
  ('discharge_reconciliation.write', 'Reconcile medications', 'Record the discharge medication review and its decisions.', 'M23', 'elevated', false),
  ('discharge_summary.review', 'Review discharge summaries', 'Accept or reject an AI-generated discharge summary.', 'M23', 'high_risk', true),
  ('er.visit.write', 'Write ER visit', 'Create and update ER visit records.', 'M14', 'elevated', false),
  ('icu.bed.assign', 'Assign ICU beds', 'Allocate and manage ICU bed assignments.', 'M15', 'elevated', false),
  ('icu.handover.record', 'Record ICU handover', 'Record nursing handover for ICU patients.', 'M15', 'elevated', false),
  ('icu.vitals.record', 'Record ICU vitals', 'Record continuous ICU vital signs.', 'M15', 'elevated', false),
  ('imaging_order.write', 'Order imaging studies', 'Raise radiology imaging orders.', 'M18', 'elevated', false),
  ('imaging_report.enter', 'Enter imaging reports', 'Draft imaging reports prior to verification.', 'M18', 'elevated', false),
  ('imaging_report.verify', 'Verify imaging reports', 'Clinically validate and release imaging reports.', 'M18', 'high_risk', true),
  ('imaging_study.record', 'Record imaging studies', 'Record imaging study acquisition and PACS references.', 'M18', 'elevated', false),
  ('ot.finalize', 'Finalize OT case', 'Complete an operation theatre case.', 'M19', 'high_risk', true),
  ('ot.record', 'Record OT clinical data', 'Record pre-op, anesthesia, procedure and post-op theatre data.', 'M19', 'elevated', false),
  ('ot.schedule', 'Schedule OT cases', 'Book, reschedule and cancel operation theatre cases.', 'M19', 'elevated', false),
  ('physio_exercise.write', 'Write exercise regimens', 'Prescribe and finish physiotherapy exercise regimens.', 'M20', 'elevated', false),
  ('physio_note.write', 'Write recovery notes', 'Record physiotherapy recovery and progress notes.', 'M20', 'elevated', false),
  ('physio_session.write', 'Write physiotherapy sessions', 'Schedule, start, complete and cancel physiotherapy sessions.', 'M20', 'elevated', false),
  ('tele_archive.write', 'Archive consultations', 'Archive a completed virtual consultation with recorded consent.', 'M22', 'high_risk', true),
  ('tele_consultation.write', 'Write telemedicine visits', 'Schedule, admit, run and close virtual consultations.', 'M22', 'elevated', false),
  ('tele_vitals.record', 'Record call vitals', 'Record live vitals observed during a virtual consultation.', 'M22', 'elevated', false),
  ('transfusion.administer', 'Administer transfusion', 'Issue, administer and record transfusion outcomes.', 'M26', 'high_risk', false),
  ('transfusion.request', 'Request transfusion', 'Raise transfusion requests and record crossmatch results.', 'M26', 'elevated', false),
  ('triage.read', 'Read triage', 'View triage assessments and acuity.', 'M14', 'standard', false),
  ('triage.write', 'Write triage', 'Create and update triage assessments.', 'M14', 'elevated', false),
  ('ventilator.event.record', 'Record ventilator event', 'Record ventilator events and mode changes.', 'M15', 'elevated', false),
  ('ward_floor.read', 'Read floor maps', 'View floor layouts, room capacity and live patient locations.', 'M24', 'standard', false),
  ('ward_room.write', 'Write ward rooms', 'Register rooms and maintain floor layout capacity.', 'M24', 'elevated', false)
on conflict (key) do nothing;

-- The super-admin grant was a snapshot taken when the catalogue was first
-- seeded. Re-run it so newly catalogued permissions are not orphaned.
insert into public.role_permissions (role_key, permission_key)
select 'hospital_super_admin', key from public.permissions
on conflict do nothing;

-- The remaining Phase 1 grants are the intended role matrix. Re-inserting
-- them is idempotent and repairs roles that missed the later additions.
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
  ('medical_officer', 'discharge_clearance.write'),
  ('medical_officer', 'discharge_reconciliation.write'),
  ('medical_officer', 'discharge_summary.review'),
  ('medical_officer', 'ward_floor.read'),
  ('medical_officer', 'ward_room.write'),
  ('medical_officer', 'ot.schedule'),
  ('medical_officer', 'ot.record'),
  ('medical_officer', 'ot.finalize'),
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
  ('nursing_staff', 'discharge_reconciliation.write'),
  ('nursing_staff', 'ward_floor.read'),
  ('nursing_staff', 'ward_room.write'),
  ('nursing_staff', 'ot.record'),
  ('lab_technician', 'patient.read'),
  ('lab_technician', 'lab_order.write'),
  ('lab_technician', 'lab_result.enter'),
  ('lab_technician', 'inventory.movement'),
  ('lab_technician', 'appointment.read'),
  ('lab_technician', 'imaging_order.write'),
  ('lab_technician', 'imaging_study.record'),
  ('lab_technician', 'imaging_report.enter'),
  ('lab_technician', 'blood_unit.write'),
  ('pharmacist', 'patient.read'),
  ('pharmacist', 'encounter.read'),
  ('pharmacist', 'pharmacy.dispense'),
  ('pharmacist', 'inventory.movement'),
  ('pharmacist', 'billing.read'),
  ('pharmacist', 'ai_output.review'),
  ('pharmacist', 'triage.read'),
  ('pharmacist', 'er.visit.write'),
  ('billing_accounts', 'patient.read'),
  ('billing_accounts', 'billing.read'),
  ('billing_accounts', 'billing.settle'),
  ('billing_accounts', 'appointment.read'),
  ('billing_accounts', 'report.read'),
  -- The patient role is intentionally excluded here: Phase 4's portal scope
  -- guard forbids granting staff-style record permissions to that role.
  ('auditor', 'audit.read'),
  ('auditor', 'clinical_event.read'),
  ('auditor', 'ai_governance.read'),
  ('auditor', 'report.read'),
  ('auditor', 'membership.read'),
  ('auditor', 'staff_directory.read'),
  ('auditor', 'patient.read'),
  ('integration_service', 'patient.read'),
  ('integration_service', 'lab_result.enter'),
  ('integration_service', 'inventory.movement'),
  ('integration_service', 'imaging_study.record'),
  ('integration_service', 'imaging_report.enter'),
  ('integration_service', 'blood_unit.write')
on conflict do nothing;
