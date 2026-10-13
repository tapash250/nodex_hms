-- NODEX Phase 3: correct permission module codes for ER/triage and ICU.
--
-- The permissions seed labelled the emergency and critical-care permissions
-- M05 and M06. The specification's Module 05 is the Patient Personal Portal
-- and Module 06 is the Nurse Ward Station; Emergency Department & Triage is
-- Module 14 and Intensive Care Unit is Module 15. The labels are traceability
-- metadata, not identity — nothing joins or authorizes on module_code — but an
-- audited system must be able to trace a permission back to the clause that
-- requires it.
--
-- Only the permissions that belong to those two modules move. Medication
-- administration and standard vitals stay on M06: the specification's Nurse
-- Ward Station is where the MAR and routine observations happen, and the ICU's
-- own continuous vitals carry their own permission.
--
-- user.administer stays put: it was labelled M13, which the specification
-- assigns to Human Resources & Payroll, but the correction depends on a policy
-- decision about where platform user administration is tracked, and inventing
-- that mapping from a label alone would be a guess rather than a fix.

-- Module 14: Emergency Department & Triage (AI-Triage).
update public.permissions set module_code = 'M14'
  where module_code = 'M05'
    and key in ('triage.read', 'triage.write', 'triage.escalate', 'er.visit.write');

-- Module 15: Intensive Care Unit (AI-Predictive).
update public.permissions set module_code = 'M15'
  where module_code = 'M06'
    and key in (
      'icu.bed.assign',
      'icu.vitals.record',
      'icu.handover.record',
      'ventilator.event.record'
    );
