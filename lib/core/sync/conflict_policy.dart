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

  /// Vital sign observation.
  static const String vitalObservation = 'vital_observation';

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

  /// Bed registry entry (code, type and lifecycle status).
  static const String bed = 'bed';

  /// Append-only correction against a signed encounter.
  static const String encounterAmendment = 'encounter_amendment';

  /// Invoice header.
  static const String invoice = 'invoice';

  /// Invoice charge line.
  static const String invoiceLine = 'invoice_line';

  /// Payment against an invoice.
  static const String payment = 'payment';

  /// Refund against a payment.
  static const String refund = 'refund';

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
    vitalObservation: ConflictPolicyEntry(
      resourceType: vitalObservation,
      policy: ConflictPolicy.appendOnly,
      rationale:
          'Observations are timestamped facts. Two nurses recording '
          'vitals produce two observations, not a conflict.',
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
    'vital_observations': vitalObservation,
    'ward_rooms': wardRoom,
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
