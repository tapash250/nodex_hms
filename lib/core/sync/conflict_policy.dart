/// Per-entity offline conflict policies.
///
/// The specification is explicit that NODEX must not use an undocumented global
/// "last write wins" policy for clinical data. Each entity declares a
/// deterministic, auditable strategy, and every strategy is covered by automated
/// tests.
///
/// This file is the single registry consulted by the sync layer when the backend
/// reports a conflicting write. Adding a clinical entity without registering its
/// policy is a defect, and [ConflictPolicyRegistry.policyFor] fails loudly rather
/// than defaulting to a permissive merge.
library;

import 'package:meta/meta.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';

/// Postgres SQLSTATE for an exclusion-constraint violation.
///
/// The registry needs it to state which policy arbitrates a rejected offline
/// write: `23P01` is how the server refuses a double-booked slot, a
/// double-held bed or an over-settled invoice, and no other SQLSTATE does.
const String exclusionViolationSqlState = '23P01';

/// Deterministic conflict resolution strategies.
///
/// The wire values match the `entity_policy` check constraint on
/// `public.conflict_records`, so a client-detected conflict and a
/// server-recorded one describe the same strategy.
enum ConflictPolicy {
  /// Merge non-overlapping field changes; overlapping edits go to human review.
  ///
  /// Used for patient demographics, where two clerks may legitimately edit
  /// different fields of the same record while offline.
  fieldLevelMerge('field_level_merge'),

  /// Retain both versions as ordered revisions; nothing is overwritten.
  ///
  /// Used for clinical notes.
  versionedRevision('versioned_revision'),

  /// Append the new entry; existing entries are immutable.
  appendOnly('append_only'),

  /// Orders are immutable once issued; a change produces a new version.
  ///
  /// Used for prescriptions, so a superseded order remains readable exactly as
  /// it was authorized.
  immutableVersion('immutable_version'),

  /// Model the action as an event; duplicate events are deduplicated by identity.
  ///
  /// Used for medication administration, where the clinically meaningful fact is
  /// "this dose was given at this time by this nurse".
  eventTransaction('event_transaction'),

  /// Results are immutable; a change is recorded as an explicit correction.
  ///
  /// Used for laboratory results, preserving the original released value.
  immutableWithCorrection('immutable_with_correction'),

  /// Resolve by replaying the transaction against current server state.
  ///
  /// Used for inventory and billing, where the invariant is a balance rather
  /// than a field value.
  transactional('transactional'),

  /// The server's value wins unconditionally and the client is reconciled.
  ///
  /// Used for bed assignment: two devices cannot both be right about who
  /// occupies a bed, and the server holds the allocation.
  serverAuthoritative('server_authoritative');

  const ConflictPolicy(this.wireValue);

  /// Value persisted in `public.conflict_records.entity_policy`.
  final String wireValue;

  /// Whether this policy can complete without a human decision.
  bool get isAutomatic => switch (this) {
    ConflictPolicy.appendOnly => true,
    ConflictPolicy.versionedRevision => true,
    ConflictPolicy.immutableVersion => true,
    ConflictPolicy.eventTransaction => true,
    ConflictPolicy.transactional => true,
    ConflictPolicy.serverAuthoritative => true,
    // A field-level merge is automatic only when edits do not overlap; the
    // registry reports it as review-requiring so the caller must decide
    // explicitly rather than assuming a silent merge.
    ConflictPolicy.fieldLevelMerge => false,
    ConflictPolicy.immutableWithCorrection => false,
  };

  /// Whether resolving under this policy discards any client-committed data.
  ///
  /// Only [serverAuthoritative] does, and only for a projection the device does
  /// not own. No policy discards a clinical fact the device recorded.
  bool get discardsClientState => this == ConflictPolicy.serverAuthoritative;

  /// Parses a wire value, or null when unrecognised.
  static ConflictPolicy? fromWire(String value) {
    for (final ConflictPolicy policy in ConflictPolicy.values) {
      if (policy.wireValue == value) {
        return policy;
      }
    }
    return null;
  }
}

/// Registration of an entity's conflict behavior.
@immutable
final class ConflictPolicyEntry {
  /// Registers [policy] for [resourceType].
  const ConflictPolicyEntry({
    required this.resourceType,
    required this.policy,
    required this.rationale,
    this.mergeableFields = const <String>{},
  });

  /// The resource type as used by repositories and the mutation ledger.
  final String resourceType;

  /// The strategy that governs this resource type.
  final ConflictPolicy policy;

  /// Why this strategy is correct for this entity, for reviewers and ADRs.
  final String rationale;

  /// Fields eligible for automatic merge under [ConflictPolicy.fieldLevelMerge].
  ///
  /// Fields outside this set escalate to human review even when the policy
  /// permits merging, so an unlisted field is never merged by default.
  final Set<String> mergeableFields;
}

/// The authoritative mapping from resource type to conflict policy.
abstract final class ConflictPolicyRegistry {
  /// Patient demographic record.
  static const String patient = 'patient';

  /// Clinical note.
  static const String clinicalNote = 'clinical_note';

  /// Prescription order.
  static const String prescription = 'prescription';

  /// Medication administration event.
  static const String medicationAdministration = 'medication_administration';

  /// Laboratory result.
  static const String labResult = 'lab_result';

  /// Inventory stock movement.
  static const String stockMovement = 'stock_movement';

  /// Bed assignment.
  static const String bedAssignment = 'bed_assignment';

  /// Invoice or payment record.
  static const String billing = 'billing';

  /// Appointment booking.
  static const String appointment = 'appointment';

  /// Clinical encounter shell.
  static const String encounter = 'encounter';

  /// Discharge record.
  static const String discharge = 'discharge';

  /// Triage assessment.
  static const String triageAssessment = 'triage_assessment';

  /// Emergency department visit.
  static const String erVisit = 'er_visit';

  /// ICU bed occupancy projection.
  static const String icuBed = 'icu_bed';

  /// ICU vital sign observation.
  static const String icuVitals = 'icu_vitals';

  /// ICU nursing handover record.
  static const String icuHandover = 'icu_handover';

  /// Ventilator event.
  static const String ventilatorEvent = 'ventilator_event';

  /// Blood bank unit.
  static const String bloodUnit = 'blood_unit';

  /// Transfusion request.
  static const String transfusionRequest = 'transfusion_request';

  /// Transfusion administration record.
  static const String transfusion = 'transfusion';

  /// Operation theatre booking.
  static const String otBooking = 'ot_booking';

  /// Operation theatre pre-op fitness assessment.
  static const String otPreOpAssessment = 'ot_preop_assessment';

  /// Operation theatre anesthesia record.
  static const String otAnesthesiaRecord = 'ot_anesthesia_record';

  /// Operation theatre intra-op procedure log.
  static const String otProcedureLog = 'ot_procedure_log';

  /// Operation theatre post-op recovery record.
  static const String otPostOpRecord = 'ot_postop_record';

  /// Radiology imaging order.
  static const String imagingOrder = 'imaging_order';

  /// Radiology imaging study acquisition.
  static const String imagingStudy = 'imaging_study';

  /// Radiology imaging report.
  static const String imagingReport = 'imaging_report';

  /// Physiotherapy session.
  static const String physioSession = 'physio_session';

  /// Physiotherapy exercise regimen.
  static const String physioExercisePlan = 'physio_exercise_plan';

  /// Physiotherapy recovery note.
  static const String physioRecoveryNote = 'physio_recovery_note';

  /// Clinical nutrition assessment.
  static const String dietAssessment = 'diet_assessment';

  /// Clinical nutrition meal plan.
  static const String dietMealPlan = 'diet_meal_plan';

  /// Meal plan day menu.
  static const String dietMealPlanDay = 'diet_meal_plan_day';

  /// Recorded dietary intake.
  static const String dietIntakeLog = 'diet_intake_log';

  /// Telemedicine consultation.
  static const String teleConsultation = 'tele_consultation';

  /// Live vitals observed during a call.
  static const String teleVitalsOverlay = 'tele_vitals_overlay';

  /// Archived telemedicine consultation.
  static const String teleConsultationArchive = 'tele_consultation_archive';

  /// Clinical discharge clearance.
  static const String dischargeClearance = 'discharge_clearance';

  /// Discharge medication reconciliation.
  static const String dischargeReconciliation = 'discharge_reconciliation';

  /// One discharge medication decision.
  static const String dischargeReconciliationItem =
      'discharge_reconciliation_item';

  /// Discharge billing settlement.
  static const String dischargeSettlement = 'discharge_settlement';

  /// AI-generated discharge summary.
  static const String dischargeAiSummary = 'discharge_ai_summary';

  /// Ward room in the floor layout.
  static const String wardRoom = 'ward_room';

  /// Practitioner directory profile.
  static const String practitionerProfile = 'practitioner_profile';

  /// Practitioner on-call rotation.
  static const String practitionerOnCall = 'practitioner_on_call';

  /// Clinical or administrative department.
  static const String department = 'department';

  /// Hospital contact directory entry.
  static const String contact = 'contact';

  /// Institutional calendar event.
  static const String calendarEvent = 'calendar_event';

  /// Ambulance fleet vehicle registry entry.
  static const String ambulance = 'ambulance';

  /// Ambulance driver duty assignment.
  static const String ambulanceDuty = 'ambulance_duty';

  /// Ambulance dispatch job.
  static const String ambulanceDispatch = 'ambulance_dispatch';

  /// Ambulance last-known position ping.
  static const String ambulanceTrackingPing = 'ambulance_tracking_ping';

  /// Biomedical equipment registry entry.
  static const String biomedicalAsset = 'biomedical_asset';

  /// Biomedical equipment breakdown ticket.
  static const String biomedicalBreakdownTicket = 'biomedical_breakdown_ticket';

  /// Biomedical maintenance or calibration record.
  static const String biomedicalMaintenanceRecord =
      'biomedical_maintenance_record';

  /// Biomedical waste category catalogue entry.
  static const String wasteCategory = 'waste_category';

  /// Biomedical waste generation log entry.
  static const String wasteGenerationLog = 'waste_generation_log';

  /// Biomedical waste disposal certificate.
  static const String wasteDisposalCertificate = 'waste_disposal_certificate';

  /// Insurance or TPA payer registry entry.
  static const String insurancePayer = 'insurance_payer';

  /// Patient insurance policy.
  static const String insurancePolicy = 'insurance_policy';

  /// Cashless pre-authorisation request.
  static const String preAuthorisation = 'pre_authorisation';

  /// Electronic insurance claim.
  static const String insuranceClaim = 'insurance_claim';

  /// A versioned consent template (Module 33).
  static const String consentTemplate = 'consent_template';

  /// A patient's consent decision (Module 33).
  static const String consentRecord = 'consent_record';

  /// An artefact indexed in the document vault (Module 33).
  static const String vaultDocument = 'vault_document';

  /// A statutory birth registration (Module 34).
  static const String birthRecord = 'birth_record';

  /// A statutory death registration (Module 34).
  static const String deathRecord = 'death_record';

  /// A medico-legal case police intimation (Module 34).
  static const String mlcIntimation = 'mlc_intimation';

  /// An append-only statutory correction (Module 34).
  static const String statutoryAmendment = 'statutory_amendment';

  /// An accreditation compliance audit (Module 35).
  static const String complianceAudit = 'compliance_audit';

  /// A patient safety incident report (Module 35).
  static const String incidentReport = 'incident_report';

  /// A measured clinical indicator (Module 35).
  static const String clinicalIndicator = 'clinical_indicator';

  /// A Net Promoter Score survey response (Module 36).
  static const String feedbackSurvey = 'feedback_survey';

  /// A grievance (Module 36).
  static const String feedbackComplaint = 'feedback_complaint';

  /// An append-only grievance routing event (Module 36).
  static const String complaintRoutingEvent = 'complaint_routing_event';

  /// A ward visiting window (Module 37).
  static const String wardVisitingWindow = 'ward_visiting_window';

  /// A visitor registration at the gate (Module 37).
  static const String visitorRegistration = 'visitor_registration';

  /// A digital entry pass (Module 37).
  static const String visitorPass = 'visitor_pass';

  /// An append-only thermal badge print (Module 37).
  static const String visitorBadgePrint = 'visitor_badge_print';

  /// A report definition (Module 38).
  static const String analyticsReportDefinition = 'analytics_report_definition';

  /// A materialised rolling rollup (Module 38).
  static const String analyticsRollup = 'analytics_rollup';

  /// A report run (Module 38).
  static const String analyticsReportRun = 'analytics_report_run';

  /// An append-only export (Module 38).
  static const String analyticsExport = 'analytics_export';

  /// A versioned hospital settings profile (Module 39).
  static const String settingsProfile = 'settings_profile';

  /// A branding asset (Module 39).
  static const String brandingAsset = 'branding_asset';

  /// An entry in the departmental tree (Module 39).
  static const String departmentTree = 'department_tree';

  /// A billing tariff (Module 39).
  static const String billingTariff = 'billing_tariff';

  /// An AI routing profile (Module 39).
  static const String aiRoutingProfile = 'ai_routing_profile';

  /// Dated staff shift block.
  static const String staffShift = 'staff_shift';

  /// Staff commitment to a shift.
  static const String dutyAllocation = 'duty_allocation';

  /// Appended attendance event.
  static const String attendanceLog = 'attendance_log';

  /// Employment record.
  static const String hrEmployee = 'hr_employee';

  /// Leave application and its decision.
  static const String hrLeaveRequest = 'hr_leave_request';

  /// Calendar holiday.
  static const String hrHoliday = 'hr_holiday';

  /// Monthly payroll run.
  static const String payrollPeriod = 'payroll_period';

  /// Payslip under a payroll run.
  static const String payslip = 'payslip';

  /// General ward vital sign observation.
  static const String wardVital = 'ward_vital';

  /// Ward shift nursing handover.
  static const String wardHandover = 'ward_handover';

  /// Ward nursing task.
  static const String wardTask = 'ward_task';

  /// Bed registry entry (code, type and lifecycle status).
  static const String bed = 'bed';

  /// Append-only correction against a signed encounter.
  static const String encounterAmendment = 'encounter_amendment';

  /// Entry on a patient's longitudinal problem list.
  static const String clinicalProblem = 'clinical_problem';

  /// Ambient AI scribe draft awaiting review.
  static const String scribeDraft = 'scribe_draft';

  /// Invoice header.
  static const String invoice = 'invoice';

  /// Invoice charge line.
  static const String invoiceLine = 'invoice_line';

  /// Payment against an invoice.
  static const String payment = 'payment';

  /// Refund against a payment.
  static const String refund = 'refund';

  /// Running patient account balance (Module 31).
  static const String patientAccount = 'patient_account';

  /// Append-only financial journal entry (Module 31).
  static const String ledgerEntry = 'ledger_entry';

  /// Part of a split payment applied to one invoice (Module 31).
  static const String paymentAllocation = 'payment_allocation';

  /// Laboratory order.
  static const String labOrder = 'lab_order';

  /// Laboratory specimen and its accession barcode.
  static const String labSpecimen = 'lab_specimen';

  /// Recorded patient allergy.
  static const String patientAllergy = 'patient_allergy';

  /// Patient merge decision history.
  static const String patientMergeHistory = 'patient_merge_history';

  /// Pharmacy dispense event.
  static const String pharmacyDispense = 'pharmacy_dispense';

  /// A single prescribed item.
  static const String prescriptionItem = 'prescription_item';

  /// Inventory stock batch.
  static const String stockBatch = 'stock_batch';

  /// Inventory stock item.
  static const String stockItem = 'stock_item';

  /// Inventory storage location.
  static const String stockLocation = 'stock_location';

  /// A single reconciliation decision on a discharge medication review.
  static const String dischargeMedicationReconciliationItem =
      'discharge_medication_reconciliation_item';

  static const Map<String, ConflictPolicyEntry>
  _entries = <String, ConflictPolicyEntry>{
    patient: ConflictPolicyEntry(
      resourceType: patient,
      policy: ConflictPolicy.fieldLevelMerge,
      rationale:
          'Two registration desks may legitimately edit different '
          'demographic fields while offline. Overlapping edits to the same '
          'field are a human decision, not a merge.',
      mergeableFields: <String>{
        'phone_number',
        'email',
        'address',
        'next_of_kin',
        'occupation',
        'marital_status',
        'preferred_language',
      },
    ),
    clinicalNote: ConflictPolicyEntry(
      resourceType: clinicalNote,
      policy: ConflictPolicy.versionedRevision,
      rationale:
          'A clinical note is a signed narrative. Concurrent authoring '
          'produces ordered revisions; no revision is overwritten.',
    ),
    prescription: ConflictPolicyEntry(
      resourceType: prescription,
      policy: ConflictPolicy.immutableVersion,
      rationale:
          'An authorized order must remain readable exactly as issued. A '
          'change creates a new version that supersedes, never mutates, '
          'the prior order.',
    ),
    medicationAdministration: ConflictPolicyEntry(
      resourceType: medicationAdministration,
      policy: ConflictPolicy.eventTransaction,
      rationale:
          'Administration is an event: a dose given at a time by a '
          'clinician. Duplicate uploads deduplicate by event identity so a '
          'retry cannot record a second dose.',
    ),
    labResult: ConflictPolicyEntry(
      resourceType: labResult,
      policy: ConflictPolicy.immutableWithCorrection,
      rationale:
          'A released result is a clinical fact others may have acted on. '
          'Corrections are additive and explicitly attributed.',
    ),
    stockMovement: ConflictPolicyEntry(
      resourceType: stockMovement,
      policy: ConflictPolicy.transactional,
      rationale:
          'The invariant is the resulting balance, not the field value. '
          'Movements replay against current stock rather than overwriting '
          'a quantity.',
    ),
    bedAssignment: ConflictPolicyEntry(
      resourceType: bedAssignment,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'Two devices cannot both be correct about bed occupancy. The '
          'server holds the allocation and the client reconciles to it.',
    ),
    billing: ConflictPolicyEntry(
      resourceType: billing,
      policy: ConflictPolicy.transactional,
      rationale:
          'Financial records reconcile as ledger transactions so that '
          'concurrent payments do not overwrite one another.',
    ),
    appointment: ConflictPolicyEntry(
      resourceType: appointment,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'Slot allocation is a scarce shared resource arbitrated by the '
          'server; the client cannot claim a slot unilaterally.',
    ),
    encounter: ConflictPolicyEntry(
      resourceType: encounter,
      policy: ConflictPolicy.versionedRevision,
      rationale:
          'The encounter shell carries clinical context that must not be '
          'silently replaced while a colleague is documenting.',
    ),
    discharge: ConflictPolicyEntry(
      resourceType: discharge,
      policy: ConflictPolicy.immutableVersion,
      rationale:
          'A finalized discharge is the authorized record of the '
          'episode and must remain readable exactly as issued. A '
          'readmission is a new encounter with its own discharge, so no '
          'version chain is needed.',
    ),
    triageAssessment: ConflictPolicyEntry(
      resourceType: triageAssessment,
      policy: ConflictPolicy.versionedRevision,
      rationale:
          'Triage documentation is clinical narrative that may be refined '
          'before disposition. Concurrent refinements become ordered '
          'revisions; escalation is one-way and never rewritten.',
    ),
    erVisit: ConflictPolicyEntry(
      resourceType: erVisit,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'ER visit status is a guarded state machine the server owns. '
          'Two devices cannot both be correct about who is still in the '
          'department; the client reconciles to server state.',
    ),
    icuBed: ConflictPolicyEntry(
      resourceType: icuBed,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'ICU bed occupancy, like Module 11 beds, is a scarce shared '
          'resource. The server holds the allocation and the client '
          'reconciles rather than claiming a bed unilaterally.',
    ),
    icuVitals: ConflictPolicyEntry(
      resourceType: icuVitals,
      policy: ConflictPolicy.appendOnly,
      rationale:
          'ICU observations are timestamped facts. Two nurses recording '
          'vitals produce two observations, not a conflict.',
    ),
    icuHandover: ConflictPolicyEntry(
      resourceType: icuHandover,
      policy: ConflictPolicy.appendOnly,
      rationale:
          'A nursing handover is an immutable shift record. Concurrent '
          'handovers append; nothing is overwritten.',
    ),
    ventilatorEvent: ConflictPolicyEntry(
      resourceType: ventilatorEvent,
      policy: ConflictPolicy.eventTransaction,
      rationale:
          'A ventilator event is an event with an identity. Duplicate '
          'uploads deduplicate so a retry cannot record a second '
          'connection or mode change.',
    ),
    bloodUnit: ConflictPolicyEntry(
      resourceType: bloodUnit,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'A blood unit is a scarce shared resource. Two devices cannot '
          'both reserve or issue the same bag; the server holds the unit '
          'state and the client reconciles rather than claiming it.',
    ),
    transfusionRequest: ConflictPolicyEntry(
      resourceType: transfusionRequest,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'A transfusion request is a guarded state machine the server '
          'owns: crossmatch, approval, and completion are arbitrated by '
          'triggers. The client reconciles to server status.',
    ),
    transfusion: ConflictPolicyEntry(
      resourceType: transfusion,
      policy: ConflictPolicy.eventTransaction,
      rationale:
          'A transfusion is an event with an identity: a unit given to a '
          'patient at a time by a clinician. Duplicate uploads '
          'deduplicate so a retry cannot record a second administration.',
    ),
    otBooking: ConflictPolicyEntry(
      resourceType: otBooking,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'A theatre slot is a scarce shared resource. Two schedulers '
          'cannot both book the same room and hour; the server holds the '
          'booking state and the client reconciles rather than claiming '
          'the slot.',
    ),
    otPreOpAssessment: ConflictPolicyEntry(
      resourceType: otPreOpAssessment,
      policy: ConflictPolicy.eventTransaction,
      rationale:
          'A pre-op assessment is an event with an identity: a fitness '
          'judgement by a clinician for one booking. Duplicate uploads '
          'deduplicate so a retry cannot record a second assessment.',
    ),
    otAnesthesiaRecord: ConflictPolicyEntry(
      resourceType: otAnesthesiaRecord,
      policy: ConflictPolicy.eventTransaction,
      rationale:
          'An anesthesia record is an event with an identity: one '
          'anesthetic for one case. Duplicate uploads deduplicate so a '
          'retry cannot record a second administration.',
    ),
    otProcedureLog: ConflictPolicyEntry(
      resourceType: otProcedureLog,
      policy: ConflictPolicy.eventTransaction,
      rationale:
          'A procedure log is an event with an identity: one operation '
          'performed for one booking. Duplicate uploads deduplicate so a '
          'retry cannot replay the procedure.',
    ),
    otPostOpRecord: ConflictPolicyEntry(
      resourceType: otPostOpRecord,
      policy: ConflictPolicy.eventTransaction,
      rationale:
          'A post-op record is an event with an identity: the recovery '
          'state of one patient after one case. Duplicate uploads '
          'deduplicate so a retry cannot record a second recovery note.',
    ),
    imagingOrder: ConflictPolicyEntry(
      resourceType: imagingOrder,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'An imaging order is a shared request with a lifecycle: '
          'ordered, completed or cancelled. Two devices cannot both '
          'cancel or complete it; the server holds the order state and '
          'the client reconciles rather than resurrecting it.',
    ),
    imagingStudy: ConflictPolicyEntry(
      resourceType: imagingStudy,
      policy: ConflictPolicy.eventTransaction,
      rationale:
          'An imaging study is an event with an identity: an acquisition '
          'performed at a time by a performer under one PACS study '
          'identifier. Duplicate uploads deduplicate so a retry cannot '
          'register a second study.',
    ),
    imagingReport: ConflictPolicyEntry(
      resourceType: imagingReport,
      policy: ConflictPolicy.immutableWithCorrection,
      rationale:
          'A released report is a clinical fact others may have acted '
          'on. Verified reports are frozen; any future amendment is '
          'additive and explicitly attributed.',
    ),
    physioSession: ConflictPolicyEntry(
      resourceType: physioSession,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'A physiotherapy session is a guarded state machine: '
          'scheduled, in progress, completed or cancelled. Two devices '
          'cannot both start, complete or cancel it; the server holds '
          'the session state and the client reconciles.',
    ),
    physioExercisePlan: ConflictPolicyEntry(
      resourceType: physioExercisePlan,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'An exercise regimen belongs to the prescribing clinician. '
          'The server arbitrates edits to sets, reps and frequency so '
          'two devices cannot overwrite each other\'s prescription.',
    ),
    physioRecoveryNote: ConflictPolicyEntry(
      resourceType: physioRecoveryNote,
      policy: ConflictPolicy.versionedRevision,
      rationale:
          'A recovery note is clinical narrative that may be refined as '
          'the patient progresses. Concurrent refinements become ordered '
          'revisions; no revision is overwritten.',
    ),
    dietAssessment: ConflictPolicyEntry(
      resourceType: dietAssessment,
      policy: ConflictPolicy.versionedRevision,
      rationale:
          'A nutrition assessment is refined until it is finalized. '
          'Concurrent refinements become ordered revisions; once '
          'finalized the server freezes it and the client reconciles.',
    ),
    dietMealPlan: ConflictPolicyEntry(
      resourceType: dietMealPlan,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'A meal plan is a decision, not a draft: generated or '
          'authored, it takes effect only once approved or rejected. '
          'Two devices cannot both decide a plan, so the server holds '
          'the plan status and the client reconciles.',
    ),
    dietMealPlanDay: ConflictPolicyEntry(
      resourceType: dietMealPlanDay,
      policy: ConflictPolicy.immutableVersion,
      rationale:
          'Day menus are authored as a seven-day set and frozen with '
          'their plan. A change is a new plan rather than an edit to a '
          'menu the ward may already be administering.',
    ),
    dietIntakeLog: ConflictPolicyEntry(
      resourceType: dietIntakeLog,
      policy: ConflictPolicy.eventTransaction,
      rationale:
          'Intake is an event with an identity: a portion of a meal '
          'taken at a time by a nurse. Duplicate uploads deduplicate so '
          'a retry cannot record a second meal.',
    ),
    teleConsultation: ConflictPolicyEntry(
      resourceType: teleConsultation,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'A consultation is a guarded state machine: scheduled, waiting, '
          'in call, then completed, cancelled or a no-show. The waiting '
          'room and the call are single-occupancy, so two devices cannot '
          'both admit or close the visit; the server holds the state and '
          'the client reconciles.',
    ),
    teleVitalsOverlay: ConflictPolicyEntry(
      resourceType: teleVitalsOverlay,
      policy: ConflictPolicy.appendOnly,
      rationale:
          'An overlay reading is a timestamped observation. Two '
          'clinicians reading vitals during the same call produce two '
          'observations, not a conflict, and neither overwrites the '
          'other.',
    ),
    teleConsultationArchive: ConflictPolicyEntry(
      resourceType: teleConsultationArchive,
      policy: ConflictPolicy.immutableVersion,
      rationale:
          'An archive is the retained record of a completed visit, '
          'including the consent that justified keeping it. It must '
          'remain readable exactly as archived; a correction is a new '
          'version, never a rewrite.',
    ),
    dischargeClearance: ConflictPolicyEntry(
      resourceType: dischargeClearance,
      policy: ConflictPolicy.versionedRevision,
      rationale:
          'Clearance is refined while outstanding items remain and is '
          'frozen once granted, because a granted clearance is what '
          'authorizes the patient to leave. Concurrent refinements '
          'become ordered revisions rather than overwriting each other.',
    ),
    dischargeReconciliation: ConflictPolicyEntry(
      resourceType: dischargeReconciliation,
      policy: ConflictPolicy.immutableVersion,
      rationale:
          'A completed reconciliation is the authorized account of which '
          'medications were reviewed before discharge. It stays readable '
          'exactly as signed off; a later correction is a new '
          'reconciliation, not a rewrite.',
    ),
    dischargeReconciliationItem: ConflictPolicyEntry(
      resourceType: dischargeReconciliationItem,
      policy: ConflictPolicy.versionedRevision,
      rationale:
          'Each medication decision is clinical narrative reviewed during '
          'a reconciliation. Decisions are appended as they are made and '
          'freeze with the reconciliation they belong to.',
    ),
    dischargeSettlement: ConflictPolicyEntry(
      resourceType: dischargeSettlement,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'Settlement records money actually collected and is a financial '
          'fact the server arbitrates. Two devices cannot both settle an '
          'episode, so the server holds the settlement and the client '
          'reconciles rather than claiming it.',
    ),
    dischargeAiSummary: ConflictPolicyEntry(
      resourceType: dischargeAiSummary,
      policy: ConflictPolicy.immutableWithCorrection,
      rationale:
          'A reviewed AI summary is a clinical narrative a clinician has '
          'signed off, and machine output must not rewrite itself. Any '
          'future correction is additive and explicitly attributed to a '
          'human reviewer.',
    ),
    wardRoom: ConflictPolicyEntry(
      resourceType: wardRoom,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'A room\'s identity, capacity and position on the floor plan are '
          'shared hospital configuration. Two devices cannot both claim a '
          'room code or disagree about a capacity the ward is staffed '
          'against, so the server holds the layout and the client '
          'reconciles.',
    ),
    practitionerProfile: ConflictPolicyEntry(
      resourceType: practitionerProfile,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'A practitioner\'s directory facts and credential record are '
          'reconciled against the credentialing authority. Two devices '
          'cannot both rewrite a retirement or disagree about a specialty, '
          'so the server holds the registry and the client reconciles.',
    ),
    practitionerOnCall: ConflictPolicyEntry(
      resourceType: practitionerOnCall,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'On-call cover is shared administrative configuration. Two '
          'devices cannot both claim or rewrite a rotation, so the server '
          'holds the rota and the client reconciles.',
    ),
    department: ConflictPolicyEntry(
      resourceType: department,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'A department code and its head are shared hospital '
          'configuration that scopes wards, staff and reports. Two devices '
          'cannot disagree about the structure of a department, so the '
          'server holds the registry and the client reconciles.',
    ),
    contact: ConflictPolicyEntry(
      resourceType: contact,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'A contact number is shared operational configuration: a ward '
          'help desk must not show two different extensions depending on '
          'which tablet read it. The server owns the directory and the '
          'client reconciles.',
    ),
    calendarEvent: ConflictPolicyEntry(
      resourceType: calendarEvent,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'An institutional event is shared scheduling configuration. Two '
          'devices cannot both hold different times for the same training '
          'day, so the server owns the calendar and the client reconciles.',
    ),
    ambulance: ConflictPolicyEntry(
      resourceType: ambulance,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'A vehicle call sign and registration are shared fleet '
          'configuration that dispatches and records name. Two devices '
          'cannot disagree about which vehicle is on the road, so the '
          'server owns the registry and the client reconciles.',
    ),
    ambulanceDuty: ConflictPolicyEntry(
      resourceType: ambulanceDuty,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'A duty assignment books a vehicle and a driver for a window, and '
          'the database forbids overlapping duties. Two offline devices must '
          'not both claim the same vehicle, so the server authorises the '
          'booking and the client reconciles.',
    ),
    ambulanceDispatch: ConflictPolicyEntry(
      resourceType: ambulanceDispatch,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'A dispatch claims a specific vehicle for a live transit. Two '
          'devices cannot both send the same ambulance, and the stage times '
          'are what an incident review turns on, so the server holds the '
          'dispatch and the client reconciles.',
    ),
    ambulanceTrackingPing: ConflictPolicyEntry(
      resourceType: ambulanceTrackingPing,
      policy: ConflictPolicy.appendOnly,
      rationale:
          'A position ping is a moment the vehicle was seen. A later ping is '
          'a later row, not a correction of the earlier one, so pings '
          'resolve without conflict and form the last-known-position trail.',
    ),
    biomedicalAsset: ConflictPolicyEntry(
      resourceType: biomedicalAsset,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'An asset tag and serial identify one instrument that breakdown '
          'tickets and service records name. Two devices cannot disagree '
          'about where a serialized unit is or whether it is in service, so '
          'the server owns the registry and the client reconciles.',
    ),
    biomedicalBreakdownTicket: ConflictPolicyEntry(
      resourceType: biomedicalBreakdownTicket,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'A breakdown ticket is claimed and progressed by one responder. Two '
          'offline devices must not both acknowledge and repair the same '
          'fault, so the server holds the ticket and the client reconciles.',
    ),
    biomedicalMaintenanceRecord: ConflictPolicyEntry(
      resourceType: biomedicalMaintenanceRecord,
      policy: ConflictPolicy.appendOnly,
      rationale:
          'A calibration, service or repair is a thing that happened at a '
          'time. A later service is a later row, not an edit of the earlier '
          'one, so the service history resolves without conflict.',
    ),
    wasteCategory: ConflictPolicyEntry(
      resourceType: wasteCategory,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'A waste category is governed configuration that generation logs '
          'and disposal certificates name. Two devices cannot disagree about '
          'the hazard class or colour of a stream, so the server owns the '
          'catalogue and the client reconciles.',
    ),
    wasteGenerationLog: ConflictPolicyEntry(
      resourceType: wasteGenerationLog,
      policy: ConflictPolicy.appendOnly,
      rationale:
          'A generation log is a quantity that left a place at a time. A '
          'correction is a new row, not an edit of the earlier one, so the '
          'generation record resolves without conflict.',
    ),
    wasteDisposalCertificate: ConflictPolicyEntry(
      resourceType: wasteDisposalCertificate,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'A disposal certificate is the compliance assertion that a batch '
          'was destroyed. Two offline devices must not both issue or void the '
          'same certificate, so the server holds it and the client reconciles.',
    ),
    insurancePayer: ConflictPolicyEntry(
      resourceType: insurancePayer,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'A payer is governed configuration that policies and claims name. '
          'Two devices cannot disagree about the identity or the portal '
          'reference of an insurer, so the server owns the registry.',
    ),
    insurancePolicy: ConflictPolicyEntry(
      resourceType: insurancePolicy,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'The cover a patient holds is a fact agreed with the payer, and its '
          'verification and cancellation are consequential. Two offline '
          'devices must not both cancel one policy, so the server owns it and '
          'the client reconciles.',
    ),
    preAuthorisation: ConflictPolicyEntry(
      resourceType: preAuthorisation,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'The payer answers a pre-authorisation request, and the answer is '
          'what the ward acts on. The decision is the payer\'s, so the server '
          'is authoritative and the client reconciles rather than merging.',
    ),
    insuranceClaim: ConflictPolicyEntry(
      resourceType: insuranceClaim,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'A claim is a submission to an external payer with a single payer '
          'reference and a single decision. Two offline devices must not both '
          'submit or settle it, so the server is authoritative and the client '
          'reconciles.',
    ),
    consentTemplate: ConflictPolicyEntry(
      resourceType: consentTemplate,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'A template version is the text a patient signed. Two devices cannot '
          'each be holding a different wording of the same version, so the '
          'server owns the catalogue and the client reconciles rather than '
          'merging.',
    ),
    consentRecord: ConflictPolicyEntry(
      resourceType: consentRecord,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'A consent is the record of one signature at one moment, with one '
          'artefact carrying it. Two offline devices must not both sign or '
          'revoke it, so the server is authoritative and the client '
          'reconciles.',
    ),
    vaultDocument: ConflictPolicyEntry(
      resourceType: vaultDocument,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'A vault entry asserts a content digest for one object path. Because '
          'the address and the digest are immutable once issued, the server '
          'holds the index and the client reconciles rather than merging two '
          'claims about the same bytes.',
    ),
    birthRecord: ConflictPolicyEntry(
      resourceType: birthRecord,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'A birth is registered once, under one register number, and the entry '
          'freezes when it is registered. Two offline devices must not both '
          'assign the number, so the server is authoritative and the client '
          'reconciles.',
    ),
    deathRecord: ConflictPolicyEntry(
      resourceType: deathRecord,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'A death is registered once with one coded cause. The coding is what a '
          'mortality review and an inquest turn on, so the server owns the row '
          'and the client reconciles rather than merging two causes of death.',
    ),
    mlcIntimation: ConflictPolicyEntry(
      resourceType: mlcIntimation,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'A medico-legal case is one file with one police reference and one '
          'acknowledgement. The server owns the intimation record so two devices '
          'cannot both report it to different stations.',
    ),
    statutoryAmendment: ConflictPolicyEntry(
      resourceType: statutoryAmendment,
      policy: ConflictPolicy.appendOnly,
      rationale:
          'An amendment is an appended event, never an edit: the value a reader '
          'acts on is the latest amendment for a field. Appending both versions '
          'keeps the whole correction history legible and lets the derived value '
          'be recomputed on every device.',
    ),
    complianceAudit: ConflictPolicyEntry(
      resourceType: complianceAudit,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'An audit score is evidence presented to an accreditation body. Two '
          'devices must not both settle the same chapter, so the server owns the '
          'row and the client reconciles rather than merging two scores.',
    ),
    incidentReport: ConflictPolicyEntry(
      resourceType: incidentReport,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'An incident report is one file with one investigation, one action '
          'plan and one closure. The server owns the row so two investigators '
          'cannot diverge on what happened and what was agreed.',
    ),
    clinicalIndicator: ConflictPolicyEntry(
      resourceType: clinicalIndicator,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'A published indicator is a figure an accreditation body has read, and '
          'its value is derived from the counts it carries. The server owns the '
          'reading so two devices cannot publish two figures for one period.',
    ),
    feedbackSurvey: ConflictPolicyEntry(
      resourceType: feedbackSurvey,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'A survey response is one answer from one patient, and the net '
          'promoter score is derived from the set of them. A duplicated response '
          'would move the headline number, so the server owns the row.',
    ),
    feedbackComplaint: ConflictPolicyEntry(
      resourceType: feedbackComplaint,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'A grievance is one file with one owner and one answer, and its '
          'deadlines are measured from the moment it was received. The server '
          'owns the row so two desks cannot both resolve the same complaint.',
    ),
    complaintRoutingEvent: ConflictPolicyEntry(
      resourceType: complaintRoutingEvent,
      policy: ConflictPolicy.appendOnly,
      rationale:
          'A routing event is a thing that happened: the case went to that '
          'department, on that day, for that reason. Appending both versions '
          'keeps the history legible, and a reader answers "who had this and '
          'when" from the log rather than from an overwritten column.',
    ),
    wardVisitingWindow: ConflictPolicyEntry(
      resourceType: wardVisitingWindow,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'A visiting window is the rule a ward admits visitors under, and a '
          'device may hold a stale copy of it. One row per ward per day is what '
          'makes resolution unambiguous, so the server owns the rule and the '
          'client reconciles rather than both inserting a window.',
    ),
    visitorRegistration: ConflictPolicyEntry(
      resourceType: visitorRegistration,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'A registration is one person at one gate, with the identity they '
          'showed and the moment they were taken, and its number is unique per '
          'tenant. The server owns the row so two desks cannot both admit the '
          'same visitor.',
    ),
    visitorPass: ConflictPolicyEntry(
      resourceType: visitorPass,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'A pass is an authority with one badge number and one validity '
          'window, and a badge number identifies one badge. The server owns it '
          'so a revocation on one device cannot be undone by an activation on '
          'another.',
    ),
    visitorBadgePrint: ConflictPolicyEntry(
      resourceType: visitorBadgePrint,
      policy: ConflictPolicy.appendOnly,
      rationale:
          'A badge print is a physical object made at a named printer at a '
          'moment, numbered by ordinal. Appending both keeps a reprint visible '
          'as a reprint, and the ordinal is what makes the count a fact rather '
          'than a race.',
    ),
    analyticsReportDefinition: ConflictPolicyEntry(
      resourceType: analyticsReportDefinition,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'A report definition is a contract: a period grain and a source that '
          'the rollups behind it were materialised against. A device that '
          're-scoped one locally would silently change what every figure it '
          'holds means, so the server owns the definition and the client '
          'reconciles.',
    ),
    analyticsRollup: ConflictPolicyEntry(
      resourceType: analyticsRollup,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'A rollup is a figure the hospital may already have been shown, '
          'stapled to one period. Two devices materialising the same period '
          'would produce two answers to one question, so the server owns the '
          'row and a re-materialisation is a supersession rather than an edit.',
    ),
    analyticsReportRun: ConflictPolicyEntry(
      resourceType: analyticsReportRun,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'A run is progress that only the warehouse can observe: what it read, '
          'how many rows came back and whether the rolling rollup or the read '
          'replica answered. A device holding its own copy of a running report '
          'would invent results, so the server owns the run.',
    ),
    analyticsExport: ConflictPolicyEntry(
      resourceType: analyticsExport,
      policy: ConflictPolicy.appendOnly,
      rationale:
          'An export is a thing that left the building at a moment, to a named '
          'destination. Appending both keeps a second download visible as a '
          'second download, which is the whole point of keeping the log: '
          '"who has a copy of the balance sheet" is answered by the records, '
          'not by the last writer winning.',
    ),
    // Module 39's five resources are all server-authoritative, and for one
    // reason rather than five: every change to them is made online with a
    // second factor, so there is no offline edit to reconcile. A device cannot
    // hold a divergent currency, tree or price, because it was never allowed to
    // author one.
    settingsProfile: ConflictPolicyEntry(
      resourceType: settingsProfile,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'The configuration in force is what every figure and every timestamp '
          'on every device means. A device that edited its own copy would write '
          'money and time differently from the rest of the hospital, so the '
          'server owns the profile and a new version supersedes the old one.',
    ),
    brandingAsset: ConflictPolicyEntry(
      resourceType: brandingAsset,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'Branding is a published file plus the two colours a theme is built '
          'from, and both are chosen at a desk with a second factor. A device '
          'holding its own colours would render a screen nobody signed off, so '
          'the server owns the asset.',
    ),
    departmentTree: ConflictPolicyEntry(
      resourceType: departmentTree,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'The department tree is one structure: ancestry, and therefore every '
          'cost centre and every rollup by department, is read from it. Two '
          'devices each editing a branch could parent each other and make every '
          'read of the tree non-terminating, so the server owns the tree.',
    ),
    billingTariff: ConflictPolicyEntry(
      resourceType: billingTariff,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'A tariff is a price an approver put their name to. A device holding '
          'its own price would bill a patient from a rule nobody approved, so '
          'the server owns the tariff and an approved one is retired rather '
          'than rewritten.',
    ),
    aiRoutingProfile: ConflictPolicyEntry(
      resourceType: aiRoutingProfile,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'A routing profile decides which model sees a note and whether that '
          'payload is redacted before it leaves the country. That decision is '
          'not one a device may make for itself, so the server owns the profile '
          'and the client reconciles.',
    ),
    staffShift: ConflictPolicyEntry(
      resourceType: staffShift,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'A shift window and headcount are the roster a ward is staffed '
          'against. Two devices cannot both close or cancel the same block, '
          'so the server holds the shift and the client reconciles.',
    ),
    dutyAllocation: ConflictPolicyEntry(
      resourceType: dutyAllocation,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'An allocation commits a named person to a window, and the server '
          'refuses two overlapping commitments with an exclusion violation. '
          'The allocation is therefore server-held so a stale offline roster '
          'cannot double-book a clinician.',
    ),
    attendanceLog: ConflictPolicyEntry(
      resourceType: attendanceLog,
      policy: ConflictPolicy.appendOnly,
      rationale:
          'Attendance is a fact: a clock-in happened at a time and cannot be '
          'rewritten. A correction is a further event, so the record of who '
          'was where survives every sync.',
    ),
    bed: ConflictPolicyEntry(
      resourceType: bed,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'A bed code identifies a physical place on a ward. Two devices '
          'cannot both claim the same code for different beds, and a stale '
          'bed status would misreport where a patient is lying, so the '
          'server holds the registry and the client reconciles.',
    ),
    encounterAmendment: ConflictPolicyEntry(
      resourceType: encounterAmendment,
      policy: ConflictPolicy.appendOnly,
      rationale:
          'An amendment is the only legal correction to a signed '
          'encounter. It is an event in the record\'s history, so it is '
          'appended and never rewritten or reordered.',
    ),
    clinicalProblem: ConflictPolicyEntry(
      resourceType: clinicalProblem,
      policy: ConflictPolicy.immutableWithCorrection,
      rationale:
          'A recorded problem is a clinical assertion about a patient that '
          'other clinicians have already acted on. It is never rewritten: '
          'ending it appends an attributed resolution, so the history of what '
          'the patient has had survives every sync.',
    ),
    scribeDraft: ConflictPolicyEntry(
      resourceType: scribeDraft,
      policy: ConflictPolicy.immutableWithCorrection,
      rationale:
          'A reviewed dictation is the record of what machine output was shown '
          'to a clinician and what they signed off. It is never rewritten, by '
          'the model or by a later device; a dictation the clinician disliked '
          'is superseded by a new one rather than edited.',
    ),
    invoice: ConflictPolicyEntry(
      resourceType: invoice,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'Invoice totals are computed server-side from billable events. A '
          'client-computed total is not a competing opinion, it is a '
          'different number, so the server value wins.',
    ),
    invoiceLine: ConflictPolicyEntry(
      resourceType: invoiceLine,
      policy: ConflictPolicy.appendOnly,
      rationale:
          'A charge line records that something was billed once. Editing it '
          'in place would erase the history of what a patient was charged.',
    ),
    payment: ConflictPolicyEntry(
      resourceType: payment,
      policy: ConflictPolicy.immutableVersion,
      rationale:
          'A payment is money that moved. It is never edited after capture; '
          'a mistake is corrected by a refund against the same payment.',
    ),
    refund: ConflictPolicyEntry(
      resourceType: refund,
      policy: ConflictPolicy.immutableVersion,
      rationale:
          'A refund returns money against a specific payment. It is a '
          'recorded event, and reversing it requires another refund rather '
          'than an edit.',
    ),
    patientAccount: ConflictPolicyEntry(
      resourceType: patientAccount,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'The balance is a projection over the journal, maintained by the '
          'server. A client that computed a different balance is not making a '
          'competing claim, it is out of date, so the server value wins.',
    ),
    ledgerEntry: ConflictPolicyEntry(
      resourceType: ledgerEntry,
      policy: ConflictPolicy.appendOnly,
      rationale:
          'A journal entry records that money moved once. Two concurrent '
          'charges are two entries, never a conflict, and a correction is a '
          'new compensating entry.',
    ),
    paymentAllocation: ConflictPolicyEntry(
      resourceType: paymentAllocation,
      policy: ConflictPolicy.transactional,
      rationale:
          'Splitting one payment across invoices is a financial allocation. '
          'The server arbitrates the sum so two devices cannot allocate the '
          'same money twice.',
    ),
    labOrder: ConflictPolicyEntry(
      resourceType: labOrder,
      policy: ConflictPolicy.appendOnly,
      rationale:
          'An order is a clinical request that happened. Cancelling or '
          'amending it appends a new state change; the original request '
          'stays legible for the audit trail.',
    ),
    labSpecimen: ConflictPolicyEntry(
      resourceType: labSpecimen,
      policy: ConflictPolicy.appendOnly,
      rationale:
          'A specimen carries an accession barcode that identifies physical '
          'material. Two devices cannot both claim the same barcode, and the '
          'barcode-to-result chain must stay unbroken.',
    ),
    patientAllergy: ConflictPolicyEntry(
      resourceType: patientAllergy,
      policy: ConflictPolicy.immutableWithCorrection,
      rationale:
          'An allergy is a safety-critical assertion. Once a clinician has '
          'reviewed it, the machine and future devices must not rewrite it; '
          'a later change is additive and attributed to the human who made '
          'it.',
    ),
    patientMergeHistory: ConflictPolicyEntry(
      resourceType: patientMergeHistory,
      policy: ConflictPolicy.appendOnly,
      rationale:
          'Merge decisions explain why two records became one. Rewriting '
          'that history would make an MPI decision unexplainable after the '
          'fact.',
    ),
    pharmacyDispense: ConflictPolicyEntry(
      resourceType: pharmacyDispense,
      policy: ConflictPolicy.immutableVersion,
      rationale:
          'A dispense means medication physically left the shelf for a '
          'named patient. It is a done event; a mistake is a new reversal, '
          'not an edit.',
    ),
    prescriptionItem: ConflictPolicyEntry(
      resourceType: prescriptionItem,
      policy: ConflictPolicy.appendOnly,
      rationale:
          'Each prescribed item is part of the signed prescription and '
          'cannot drift from it, so the line is appended with the '
          'prescription and never edited independently.',
    ),
    stockBatch: ConflictPolicyEntry(
      resourceType: stockBatch,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'A batch and its expiry are shared pharmacy configuration. Two '
          'devices cannot both define the same batch differently, and '
          'recalled stock must read identically everywhere.',
    ),
    stockItem: ConflictPolicyEntry(
      resourceType: stockItem,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'A stock item is shared inventory configuration keyed by code '
          'within its tenant, so the server holds the definition and '
          'quantities move through movements rather than by overwriting the '
          'item.',
    ),
    stockLocation: ConflictPolicyEntry(
      resourceType: stockLocation,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'A storage location is shared configuration that stock is counted '
          'against, so two devices cannot disagree about where a bin is.',
    ),
    dischargeMedicationReconciliationItem: ConflictPolicyEntry(
      resourceType: dischargeMedicationReconciliationItem,
      policy: ConflictPolicy.appendOnly,
      rationale:
          'Each reconciliation decision is a review action a clinician took '
          'on a specific medication. The decision history is append-only so '
          'the review cannot be quietly rewritten.',
    ),
    hrEmployee: ConflictPolicyEntry(
      resourceType: hrEmployee,
      policy: ConflictPolicy.fieldLevelMerge,
      rationale:
          'Two HR clerks may legitimately edit different attributes of the '
          'same employment record while offline, so non-overlapping field '
          'changes merge. Lifecycle transitions (confirmation, separation) '
          'are deliberately outside the mergeable set: they change status and '
          'must be reviewed rather than merged.',
      mergeableFields: <String>{
        'department_id',
        'designation',
        'grade',
        'reports_to',
        'notes',
        'employment_type',
      },
    ),
    hrLeaveRequest: ConflictPolicyEntry(
      resourceType: hrLeaveRequest,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'A leave decision is the employer agreeing to a dated absence, and '
          'the server refuses overlapping live applications. The application '
          'is therefore server-held so a stale offline copy cannot approve '
          'leave the roster already conflicts with.',
    ),
    hrHoliday: ConflictPolicyEntry(
      resourceType: hrHoliday,
      policy: ConflictPolicy.fieldLevelMerge,
      rationale:
          'A holiday is shared calendar configuration; renaming it or '
          'changing its paid flag on one device is not contradicted by an '
          'edit to a different attribute elsewhere, so those fields merge '
          'while the date stays fixed.',
      mergeableFields: <String>{'display_name', 'holiday_type', 'is_paid'},
    ),
    payrollPeriod: ConflictPolicyEntry(
      resourceType: payrollPeriod,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'A payroll run is a financial state machine (draft, finalized, '
          'paid) whose transitions must be singular. The server holds it so '
          'two devices cannot both finalize or pay the same period.',
    ),
    payslip: ConflictPolicyEntry(
      resourceType: payslip,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'A payslip is an exact monetary total that must satisfy '
          'net = gross - deductions everywhere. The server owns the figure so '
          'a merged or overwritten amount cannot produce a payroll that does '
          'not add up.',
    ),
    wardVital: ConflictPolicyEntry(
      resourceType: wardVital,
      policy: ConflictPolicy.appendOnly,
      rationale:
          'A ward observation is a timestamped fact. Two nurses taking '
          'observations produce two rows, not a conflict, so nothing is '
          'merged or overwritten.',
    ),
    wardHandover: ConflictPolicyEntry(
      resourceType: wardHandover,
      policy: ConflictPolicy.appendOnly,
      rationale:
          'A shift handover is a record of what was said at handover time. It '
          'is immutable: a correction is a new handover, not a rewrite of the '
          'one the incoming shift relied on.',
    ),
    wardTask: ConflictPolicyEntry(
      resourceType: wardTask,
      policy: ConflictPolicy.serverAuthoritative,
      rationale:
          'A ward task has one owner and one completion record. The server '
          'holds it so two devices cannot both claim the task or record two '
          'different closers for the same piece of work.',
    ),
  };

  /// Maps a replicated table name onto its registered resource type.
  ///
  /// The sync connector learns about a conflict from the server as a table
  /// name (`clinical_encounters`), while the registry is keyed by the singular
  /// clinical resource it governs (`encounter`). Without this resolution a real
  /// conflict on a plural table would raise `unregistered_conflict_policy` at
  /// exactly the moment the policy was needed, turning a recoverable conflict
  /// into a hard sync failure.
  static const Map<String, String> _tableToResource = <String, String>{
    'appointments': appointment,
    'bed_assignments': bedAssignment,
    'beds': bed,
    'blood_units': bloodUnit,
    'clinical_encounters': encounter,
    'clinical_problems': clinicalProblem,
    'diet_assessments': dietAssessment,
    'diet_intake_logs': dietIntakeLog,
    'diet_meal_plan_days': dietMealPlanDay,
    'diet_meal_plans': dietMealPlan,
    'discharge_ai_summaries': dischargeAiSummary,
    'discharge_clearances': dischargeClearance,
    'discharge_medication_reconciliation_items':
        dischargeMedicationReconciliationItem,
    'discharge_medication_reconciliations': dischargeReconciliation,
    'discharge_settlements': dischargeSettlement,
    'discharges': discharge,
    'encounter_amendments': encounterAmendment,
    'encounter_scribe_drafts': scribeDraft,
    'er_visits': erVisit,
    'icu_beds': icuBed,
    'icu_nursing_handover': icuHandover,
    'icu_vitals': icuVitals,
    'imaging_orders': imagingOrder,
    'imaging_reports': imagingReport,
    'imaging_studies': imagingStudy,
    'invoice_lines': invoiceLine,
    'invoices': invoice,
    'lab_orders': labOrder,
    'lab_results': labResult,
    'lab_specimens': labSpecimen,
    'medication_administrations': medicationAdministration,
    'ot_anesthesia_records': otAnesthesiaRecord,
    'ot_bookings': otBooking,
    'ot_postop_records': otPostOpRecord,
    'ot_preop_assessments': otPreOpAssessment,
    'ot_procedure_logs': otProcedureLog,
    'patient_allergies': patientAllergy,
    'patient_merge_history': patientMergeHistory,
    'patient_accounts': patientAccount,
    'ledger_entries': ledgerEntry,
    'payment_allocations': paymentAllocation,
    'patients': patient,
    'payments': payment,
    'pharmacy_dispenses': pharmacyDispense,
    'physio_exercise_plans': physioExercisePlan,
    'physio_recovery_notes': physioRecoveryNote,
    'physio_sessions': physioSession,
    'prescription_items': prescriptionItem,
    'prescriptions': prescription,
    'refunds': refund,
    'stock_batches': stockBatch,
    'stock_items': stockItem,
    'stock_locations': stockLocation,
    'stock_movements': stockMovement,
    'tele_consultation_archives': teleConsultationArchive,
    'tele_consultations': teleConsultation,
    'tele_vitals_overlays': teleVitalsOverlay,
    'transfusion_requests': transfusionRequest,
    'transfusions': transfusion,
    'triage_assessments': triageAssessment,
    'ventilator_events': ventilatorEvent,
    'ward_rooms': wardRoom,
    'practitioner_profiles': practitionerProfile,
    'practitioner_on_calls': practitionerOnCall,
    'departments': department,
    'directory_contacts': contact,
    'calendar_events': calendarEvent,
    'ambulances': ambulance,
    'ambulance_duty_assignments': ambulanceDuty,
    'ambulance_dispatches': ambulanceDispatch,
    'ambulance_tracking_pings': ambulanceTrackingPing,
    'biomedical_assets': biomedicalAsset,
    'biomedical_breakdown_tickets': biomedicalBreakdownTicket,
    'biomedical_maintenance_records': biomedicalMaintenanceRecord,
    'waste_categories': wasteCategory,
    'waste_generation_logs': wasteGenerationLog,
    'waste_disposal_certificates': wasteDisposalCertificate,
    'insurance_payers': insurancePayer,
    'insurance_policies': insurancePolicy,
    'pre_authorisation_requests': preAuthorisation,
    'insurance_claims': insuranceClaim,
    'consent_templates': consentTemplate,
    'consent_records': consentRecord,
    'document_vault_documents': vaultDocument,
    'statutory_birth_records': birthRecord,
    'statutory_death_records': deathRecord,
    'statutory_mlc_intimations': mlcIntimation,
    'statutory_record_amendments': statutoryAmendment,
    'compliance_audits': complianceAudit,
    'incident_reports': incidentReport,
    'clinical_indicators': clinicalIndicator,
    'feedback_surveys': feedbackSurvey,
    'feedback_complaints': feedbackComplaint,
    'complaint_routing_events': complaintRoutingEvent,
    'ward_visiting_windows': wardVisitingWindow,
    'visitor_registrations': visitorRegistration,
    'visitor_passes': visitorPass,
    'visitor_badge_prints': visitorBadgePrint,
    'analytics_report_definitions': analyticsReportDefinition,
    'analytics_rollups': analyticsRollup,
    'analytics_report_runs': analyticsReportRun,
    'analytics_exports': analyticsExport,
    'settings_profiles': settingsProfile,
    'branding_assets': brandingAsset,
    'department_hierarchies': departmentTree,
    'billing_tariffs': billingTariff,
    'ai_routing_profiles': aiRoutingProfile,
    'staff_shifts': staffShift,
    'duty_allocations': dutyAllocation,
    'attendance_logs': attendanceLog,
    'hr_employees': hrEmployee,
    'hr_leave_requests': hrLeaveRequest,
    'hr_holidays': hrHoliday,
    'hr_payroll_periods': payrollPeriod,
    'hr_payslips': payslip,
    'ward_vitals': wardVital,
    'ward_handovers': wardHandover,
    'ward_tasks': wardTask,
  };

  /// Resolves [resourceType], which may be a table name, to its entry.
  ///
  /// [resourceType] is accepted either as a registered resource type or as the
  /// name of a replicated table. Unknown values still throw: an undeclared
  /// clinical entity must fail loudly rather than fall back to last-write-wins.
  static ConflictPolicyEntry policyFor(String resourceType) {
    final ConflictPolicyEntry? entry =
        _entries[resourceType] ?? _entries[_tableToResource[resourceType]];
    if (entry == null) {
      throw IntegrityError(
        message:
            'No conflict policy is registered for resource type '
            '"$resourceType". A clinical entity must declare a deterministic '
            'conflict strategy before it can synchronize.',
        subject: 'conflict_policy',
        code: 'unregistered_conflict_policy',
        context: <String, Object?>{'resource_type': resourceType},
      );
    }
    return entry;
  }

  /// Whether [resourceType] has a registered policy, by resource type or by
  /// the name of a replicated table.
  static bool isRegistered(String resourceType) =>
      _entries.containsKey(resourceType) ||
      _entries.containsKey(_tableToResource[resourceType]);

  /// The registered resource type governing [resourceType].
  ///
  /// Throws [IntegrityError] when nothing is registered, matching
  /// [policyFor].
  static String resourceTypeFor(String resourceType) {
    if (_entries.containsKey(resourceType)) return resourceType;
    final String? resolved = _tableToResource[resourceType];
    if (resolved == null) {
      throw IntegrityError(
        message:
            'No conflict policy is registered for resource type '
            '"$resourceType".',
        subject: 'conflict_policy',
        code: 'unregistered_conflict_policy',
        context: <String, Object?>{'resource_type': resourceType},
      );
    }
    return resolved;
  }

  /// Every registered entry, keyed by resource type.
  static Map<String, ConflictPolicyEntry> get entries =>
      Map<String, ConflictPolicyEntry>.unmodifiable(_entries);

  /// Resource types with a registered policy.
  static Iterable<String> get registeredResourceTypes => _entries.keys;

  /// Whether a conflict on [resourceType] can be resolved without human review.
  ///
  /// For [ConflictPolicy.fieldLevelMerge], resolution is automatic only when
  /// every changed field is registered as mergeable and no field was edited on
  /// both sides.
  static bool canResolveAutomatically(
    String resourceType, {
    Set<String> clientChangedFields = const <String>{},
    Set<String> serverChangedFields = const <String>{},
  }) {
    final ConflictPolicyEntry entry = policyFor(resourceType);
    if (entry.policy != ConflictPolicy.fieldLevelMerge) {
      return entry.policy.isAutomatic;
    }

    final bool allMergeable = clientChangedFields.every(
      entry.mergeableFields.contains,
    );
    final bool overlapping = clientChangedFields
        .intersection(serverChangedFields)
        .isNotEmpty;
    return allMergeable && !overlapping;
  }
}
