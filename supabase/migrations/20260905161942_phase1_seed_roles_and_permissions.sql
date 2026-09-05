-- NODEX Phase 1: seed the role and permission catalogue from the specification
-- role matrix. Roles and permissions are configuration, not tenant data, so they
-- are seeded here rather than created per tenant.

insert into public.roles (key, display_name, description, role_class, is_privileged, offline_capable)
values
  ('hospital_super_admin', 'Hospital Super Admin',
   'Full enterprise administration across tenants, facilities, RBAC and configuration.',
   'administrative', true, false),
  ('medical_officer', 'Medical Officer / Doctor',
   'Doctor cockpit, EMR/EHR, OT, ICU, OPD, telehealth, prescription and lab review.',
   'clinical', true, true),
  ('nursing_staff', 'Nursing Staff',
   'Ward station, beds, vitals, handover and triage.',
   'nursing', false, true),
  ('lab_technician', 'Diagnostic / Lab Technician',
   'Laboratory workflows, barcode sample tracking and result entry.',
   'diagnostic', false, true),
  ('pharmacist', 'Pharmacist',
   'Pharmacy, POS dispensing, formulary and inventory.',
   'pharmacy', true, true),
  ('billing_accounts', 'Billing & Accounts',
   'Billing, invoices, insurance and financial reporting.',
   'financial', true, true),
  ('patient', 'Patient',
   'Patient portal, reports, prescriptions, timeline and telehealth.',
   'patient', false, true),
  ('integration_service', 'System / Integration Service',
   'Narrow service-to-service operations with explicit scoped credentials.',
   'service', true, false),
  ('auditor', 'Auditor / Compliance',
   'Read-only audit, compliance and reporting scope.',
   'audit', false, true);

insert into public.permissions (key, display_name, description, module_code, risk_tier, requires_online)
values
  -- Enterprise administration
  ('tenant.administer',        'Administer tenant',            'Modify tenant-level configuration and branding.',            'M39', 'high_risk', true),
  ('facility.administer',      'Administer facilities',        'Create and modify facilities.',                              'M39', 'elevated',  true),
  ('department.administer',    'Administer departments',       'Create and modify clinical departments.',                     'M12', 'elevated',  true),
  ('ward.administer',          'Administer wards',            'Create and modify wards and bed capacity.',                   'M11', 'elevated',  true),
  ('user.administer',          'Administer users',            'Create, suspend and deactivate application users.',           'M13', 'high_risk', true),
  ('membership.read',          'Read memberships',            'View role assignments within the tenant.',                    'M39', 'standard',  false),
  ('membership.grant',         'Grant memberships',           'Assign or revoke roles and scopes.',                          'M39', 'high_risk', true),
  ('staff_directory.read',     'Read staff directory',        'Browse the staff and specialist directory.',                  'M08', 'standard',  false),
  ('device.administer',        'Administer devices',          'Enrol, suspend, revoke and wipe client devices.',              'M52', 'high_risk', true),
  -- Governance and diagnostics
  ('audit.read',               'Read audit trail',            'Query and export the append-only audit history.',              'M35', 'standard',  false),
  ('clinical_event.read',      'Read clinical events',        'Inspect the immutable clinical event stream.',                 'M35', 'standard',  false),
  ('sync.administer',          'Administer synchronization',  'Inspect queue depth, retries and permanent sync failures.',    'M53', 'elevated',  false),
  ('conflict.review',          'Review sync conflicts',       'Adjudicate entity-specific offline conflicts.',                'M53', 'elevated',  false),
  -- AI governance
  ('ai_governance.read',       'Read AI governance records',  'Inspect AI requests, responses, safety decisions and reviews.', 'M39', 'standard',  false),
  ('ai_governance.administer', 'Administer AI governance',    'Approve models and activate deployment profiles.',             'M39', 'high_risk', true),
  ('ai_output.review',         'Review AI output',            'Accept, edit or reject clinically material AI output.',        'M39', 'elevated',  false),
  -- Core clinical (Phase 2 surfaces, catalogued now so the snapshot is stable)
  ('patient.read',             'Read patient records',        'View patient demographics and clinical summary.',              'M10', 'standard',  false),
  ('patient.write',            'Write patient records',       'Create and amend patient demographic records.',                'M10', 'elevated',  false),
  ('encounter.read',           'Read encounters',             'View clinical encounters and notes.',                          'M16', 'standard',  false),
  ('encounter.write',          'Write encounters',            'Create encounters and clinical notes.',                        'M16', 'elevated',  false),
  ('prescription.draft',       'Draft prescriptions',         'Create an unauthorized prescription draft.',                   'M16', 'elevated',  false),
  ('prescription.finalize',    'Finalize prescriptions',      'Apply clinical authorization to a prescription.',              'M16', 'high_risk', true),
  ('medication.administer',    'Administer medication',       'Record medication administration against the MAR.',            'M06', 'high_risk', false),
  ('lab_order.write',          'Order laboratory tests',      'Raise laboratory orders.',                                    'M17', 'elevated',  false),
  ('lab_result.enter',         'Enter laboratory results',    'Record laboratory results prior to validation.',               'M17', 'elevated',  false),
  ('lab_result.verify',        'Verify laboratory results',   'Clinically validate and release laboratory results.',           'M17', 'high_risk', true),
  ('pharmacy.dispense',        'Dispense medication',        'Dispense against an authorized prescription.',                 'M25', 'high_risk', false),
  ('inventory.movement',       'Record stock movement',       'Record inventory transactions and adjustments.',               'M28', 'elevated',  false),
  ('bed.assign',               'Assign beds',                 'Allocate and transfer inpatient beds.',                       'M11', 'elevated',  false),
  ('vitals.record',            'Record vitals',               'Record vital sign observations.',                              'M06', 'standard',  false),
  ('triage.escalate',          'Escalate triage',             'Change triage acuity or escalate to resuscitation.',           'M14', 'high_risk', false),
  ('discharge.finalize',       'Finalize discharge',          'Approve and finalize a patient discharge.',                    'M23', 'high_risk', true),
  ('transfusion.finalize',     'Finalize transfusion',        'Authorize blood component issue and transfusion.',             'M26', 'high_risk', true),
  ('billing.read',             'Read billing records',        'View invoices, payments and financial summaries.',              'M31', 'standard',  false),
  ('billing.settle',           'Settle billing',              'Finalize invoices, payments and refunds.',                    'M31', 'high_risk', true),
  ('appointment.read',         'Read appointments',           'View appointment calendars and schedules.',                    'M07', 'standard',  false),
  ('appointment.write',        'Write appointments',          'Book, reschedule and cancel appointments.',                    'M07', 'standard',  false),
  ('report.read',              'Read reports',                'View operational and clinical analytics.',                     'M38', 'standard',  false);
