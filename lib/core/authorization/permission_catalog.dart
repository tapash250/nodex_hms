/// Permission and role catalogue mirrored from the authoritative database.
///
/// The server is the source of truth: these constants exist so that client code
/// references a permission by a checked identifier instead of an inline string
/// literal that can drift from the `public.permissions` table.
///
/// Nothing here grants access. Every value is a key used to interrogate the
/// authorization snapshot, which itself is issued and bounded server-side.
library;

/// Role keys defined in `public.roles`.
abstract final class NodexRoles {
  /// Full enterprise administration.
  static const String hospitalSuperAdmin = 'hospital_super_admin';

  /// Doctor cockpit, EMR/EHR, OT, ICU, OPD, telehealth, prescription, lab review.
  static const String medicalOfficer = 'medical_officer';

  /// Ward station, beds, vitals, handover, triage.
  static const String nursingStaff = 'nursing_staff';

  /// Laboratory workflows, barcode sample tracking, result entry.
  static const String labTechnician = 'lab_technician';

  /// Pharmacy, POS dispensing, formulary, inventory.
  static const String pharmacist = 'pharmacist';

  /// Billing, invoices, insurance, financial reporting.
  static const String billingAccounts = 'billing_accounts';

  /// Patient portal, reports, prescriptions, timeline, telehealth.
  static const String patient = 'patient';

  /// Narrow service-to-service operations with explicit scoped credentials.
  static const String integrationService = 'integration_service';

  /// Read-only audit, compliance and reporting scope.
  static const String auditor = 'auditor';

  /// Every role key known to the client.
  static const Set<String> all = <String>{
    hospitalSuperAdmin,
    medicalOfficer,
    nursingStaff,
    labTechnician,
    pharmacist,
    billingAccounts,
    patient,
    integrationService,
    auditor,
  };
}

/// Permission keys defined in `public.permissions`.
///
/// Permissions marked in [requiresOnline] must not be exercised from a cached
/// offline authorization snapshot; the server excludes them from the snapshot's
/// offline subset, and [NodexPermissions.requiresOnline] lets the UI explain why
/// a control is unavailable before the user attempts the action.
abstract final class NodexPermissions {
  // Enterprise administration
  /// Modify tenant-level configuration and branding.
  static const String tenantAdminister = 'tenant.administer';

  /// Create and modify facilities.
  static const String facilityAdminister = 'facility.administer';

  /// Create and modify clinical departments.
  static const String departmentAdminister = 'department.administer';

  /// Create and modify wards and bed capacity.
  static const String wardAdminister = 'ward.administer';

  /// Create, suspend and deactivate application users.
  static const String userAdminister = 'user.administer';

  /// View role assignments within the tenant.
  static const String membershipRead = 'membership.read';

  /// Assign or revoke roles and scopes.
  static const String membershipGrant = 'membership.grant';

  /// Browse the staff and specialist directory.
  static const String staffDirectoryRead = 'staff_directory.read';

  /// Create and maintain practitioner directory entries and on-call rota.
  static const String staffDirectoryAdminister = 'staff_directory.administer';

  /// Browse the hospital contacts directory.
  static const String contactsRead = 'contacts.read';

  /// Register, maintain and archive hospital contacts.
  static const String contactsAdminister = 'contacts.administer';

  /// View institutional calendar events and the shift overlay.
  static const String calendarRead = 'calendar.read';

  /// Create, edit and cancel institutional calendar events.
  static const String calendarManage = 'calendar.manage';

  /// View vehicles, driver rosters, dispatches and tracking.
  static const String fleetRead = 'fleet.read';

  /// Raise, progress and cancel emergency ambulance dispatches.
  static const String fleetDispatch = 'fleet.dispatch';

  /// Register vehicles and maintain driver duty rosters.
  static const String fleetManage = 'fleet.manage';

  /// View the equipment registry, breakdown tickets and service history.
  static const String biomedicalRead = 'biomedical.read';

  /// Raise and progress breakdown tickets and record maintenance.
  static const String biomedicalMaintain = 'biomedical.maintain';

  /// Register, update and decommission equipment.
  static const String biomedicalManage = 'biomedical.manage';

  /// View waste categories, generation logs and disposal certificates.
  static const String wasteRead = 'waste.read';

  /// Record the weight and containers of waste generated.
  static const String wasteRecord = 'waste.record';

  /// Maintain waste categories and issue or void disposal certificates.
  static const String wasteManage = 'waste.manage';

  /// View payers, policies, pre-authorisation requests and claims.
  static const String insuranceRead = 'insurance.read';

  /// Record policy verification and raise and submit pre-authorisation
  /// requests.
  static const String insuranceVerify = 'insurance.verify';

  /// Submit electronic claims and record payer decisions and settlements.
  static const String insuranceClaim = 'insurance.claim';

  /// Maintain the payer registry and register or cancel patient policies.
  static const String insuranceManage = 'insurance.manage';

  /// View consent templates, consent records and the document vault index.
  static const String documentsRead = 'documents.read';

  /// Raise consent records and capture stylus and biometric attestations.
  static const String documentsConsent = 'documents.consent';

  /// Register vaulted artefacts and supersede or void them.
  static const String documentsVault = 'documents.vault';

  /// Publish consent template versions and activate or retire them.
  static const String documentsManage = 'documents.manage';

  /// View the statutory birth and death registers and medico-legal cases.
  static const String statutoryRead = 'statutory.read';

  /// Raise statutory entries, record cause-of-death coding and log cases.
  static const String statutoryRegister = 'statutory.register';

  /// Issue birth and death certificates against a registered entry.
  static const String statutoryCertify = 'statutory.certify';

  /// Append a correction to a registered fact and void a withdrawn entry.
  static const String statutoryAmend = 'statutory.amend';

  /// View accreditation audits, incident reports and clinical indicators.
  static const String qualityRead = 'quality.read';

  /// Plan, conduct, score, complete and cancel an accreditation audit.
  static const String qualityAudit = 'quality.audit';

  /// Raise, investigate, action-plan and close an incident report.
  static const String qualityIncident = 'quality.incident';

  /// Record, publish and retract a measured clinical indicator.
  static const String qualityIndicator = 'quality.indicator';

  /// View Net Promoter Score surveys, grievances and their routing history.
  static const String feedbackRead = 'feedback.read';

  /// Capture a survey response and log a grievance.
  static const String feedbackRecord = 'feedback.record';

  /// Acknowledge, route, investigate, resolve, dismiss and close a grievance.
  static const String feedbackResolve = 'feedback.resolve';

  /// View visitor registrations, entry passes and ward visiting windows.
  static const String visitorRead = 'visitor.read';

  /// Register a visitor at the gate, admit them and record their departure.
  static const String visitorRegister = 'visitor.register';

  /// Issue, activate, return and revoke a digital entry pass, and print the badge.
  static const String visitorPass = 'visitor.pass';

  /// Set and retire a ward's visiting window and its visitor limit.
  static const String visitorConfigure = 'visitor.configure';

  /// View report definitions, materialised rollups, report runs and exports.
  static const String analyticsRead = 'analytics.read';

  /// Add a report to the catalogue, publish it and retire it.
  static const String analyticsDefine = 'analytics.define';

  /// Run a report and write its rolling rollup against the read replica.
  static const String analyticsMaterialise = 'analytics.materialise';

  /// Take a finished report out of the hospital.
  static const String analyticsExport = 'analytics.export';

  /// View master settings: configuration, branding, the tree, tariffs and routing.
  static const String settingsRead = 'settings.read';

  /// Change hospital configuration and branding, and maintain the tree.
  static const String settingsConfigure = 'settings.configure';

  /// Draft, approve and retire billing tariffs.
  static const String settingsTariff = 'settings.tariff';

  /// Draft, activate and retire AI routing profiles.
  static const String aiConfigure = 'ai.configure';

  /// View shift rosters, duty allocations and attendance.
  static const String workforceRead = 'workforce.read';

  /// Create shifts, allocate duties and record attendance.
  static const String workforceManage = 'workforce.manage';

  /// View employee records, leave applications and holidays.
  static const String hrRead = 'hr.read';

  /// Maintain employee records, decide leave and set holidays.
  static const String hrManage = 'hr.manage';

  /// View payroll periods and payslips.
  static const String payrollRead = 'payroll.read';

  /// Create and finalize payroll runs and payslips.
  static const String payrollManage = 'payroll.manage';

  /// Enrol, suspend, revoke and wipe client devices.
  static const String deviceAdminister = 'device.administer';

  // Governance and diagnostics
  /// Query and export the append-only audit history.
  static const String auditRead = 'audit.read';

  /// Inspect the immutable clinical event stream.
  static const String clinicalEventRead = 'clinical_event.read';

  /// Inspect queue depth, retries and permanent sync failures.
  static const String syncAdminister = 'sync.administer';

  /// Adjudicate entity-specific offline conflicts.
  static const String conflictReview = 'conflict.review';

  // AI governance
  /// Inspect AI requests, responses, safety decisions and reviews.
  static const String aiGovernanceRead = 'ai_governance.read';

  /// Approve models and activate deployment profiles.
  static const String aiGovernanceAdminister = 'ai_governance.administer';

  /// Accept, edit or reject clinically material AI output.
  static const String aiOutputReview = 'ai_output.review';

  // Core clinical
  /// View patient demographics and clinical summary.
  static const String patientRead = 'patient.read';

  /// Create and amend patient demographic records.
  static const String patientWrite = 'patient.write';

  /// View clinical encounters and notes.
  static const String encounterRead = 'encounter.read';

  /// Create encounters and clinical notes.
  static const String encounterWrite = 'encounter.write';

  /// Create an unauthorized prescription draft.
  static const String prescriptionDraft = 'prescription.draft';

  /// Apply clinical authorization to a prescription.
  static const String prescriptionFinalize = 'prescription.finalize';

  /// Record medication administration against the MAR.
  static const String medicationAdminister = 'medication.administer';

  /// Raise laboratory orders.
  static const String labOrderWrite = 'lab_order.write';

  /// Record laboratory results prior to validation.
  static const String labResultEnter = 'lab_result.enter';

  /// Clinically validate and release laboratory results.
  static const String labResultVerify = 'lab_result.verify';

  /// Raise radiology imaging orders.
  static const String imagingOrderWrite = 'imaging_order.write';

  /// Record imaging study acquisition.
  static const String imagingStudyRecord = 'imaging_study.record';

  /// Draft imaging reports prior to verification.
  static const String imagingReportEnter = 'imaging_report.enter';

  /// Clinically validate and release imaging reports.
  static const String imagingReportVerify = 'imaging_report.verify';

  /// Schedule, start, complete and cancel physiotherapy sessions.
  static const String physioSessionWrite = 'physio_session.write';

  /// Prescribe and finish physiotherapy exercise regimens.
  static const String physioExerciseWrite = 'physio_exercise.write';

  /// Record physiotherapy recovery and progress notes.
  static const String physioNoteWrite = 'physio_note.write';

  /// Record and finalize clinical nutrition assessments.
  static const String dietAssessmentWrite = 'diet_assessment.write';

  /// Author seven-day meal plans and their daily menus.
  static const String dietPlanWrite = 'diet_plan.write';

  /// Approve or reject generated and authored meal plans.
  static const String dietPlanApprove = 'diet_plan.approve';

  /// Record the portion of planned meals actually taken.
  static const String dietIntakeRecord = 'diet_intake.record';

  /// Schedule, admit, run and close virtual consultations.
  static const String teleConsultationWrite = 'tele_consultation.write';

  /// Record live vitals observed during a virtual consultation.
  static const String teleVitalsRecord = 'tele_vitals.record';

  /// Archive a completed virtual consultation with recorded consent.
  static const String teleArchiveWrite = 'tele_archive.write';

  /// Record and grant clinical clearance before a patient leaves.
  static const String dischargeClearanceWrite = 'discharge_clearance.write';

  /// Record the discharge medication review and its decisions.
  static const String dischargeReconciliationWrite =
      'discharge_reconciliation.write';

  /// Accept or reject an AI-generated discharge summary.
  static const String dischargeSummaryReview = 'discharge_summary.review';

  /// View floor layouts, room capacity and live patient locations.
  static const String wardFloorRead = 'ward_floor.read';

  /// Register rooms and maintain floor layout capacity.
  static const String wardRoomWrite = 'ward_room.write';

  /// Dispense against an authorized prescription.
  static const String pharmacyDispense = 'pharmacy.dispense';

  /// Record inventory transactions and adjustments.
  static const String inventoryMovement = 'inventory.movement';

  /// Allocate and transfer inpatient beds.
  static const String bedAssign = 'bed.assign';

  /// Record vital sign observations.
  static const String vitalsRecord = 'vitals.record';

  /// Change triage acuity or escalate to resuscitation.
  static const String triageEscalate = 'triage.escalate';

  /// Create and update triage assessments.
  static const String triageWrite = 'triage.write';

  /// View triage assessments.
  static const String triageRead = 'triage.read';

  /// Create and update ER visits.
  static const String erVisitWrite = 'er.visit.write';

  /// ICU bed assignment and management.
  static const String icuBedAssign = 'icu.bed.assign';

  /// Record ICU vitals.
  static const String icuVitalsRecord = 'icu.vitals.record';

  /// Record nursing handover.
  static const String icuHandoverRecord = 'icu.handover.record';

  /// Record ventilator events.
  static const String ventilatorEventRecord = 'ventilator.event.record';

  /// View the ward observation, handover and task board.
  static const String nursingStationRead = 'nursing_station.read';

  /// Record the shift nursing handover for a ward.
  static const String nursingHandoverRecord = 'nursing.handover.record';

  /// Create, delegate and close ward nursing tasks.
  static const String nursingTaskWrite = 'nursing_task.write';

  /// Read the cross-department task board (Module 41).
  static const String tasksRead = 'tasks.read';

  /// Raise, claim, reprioritise and close hospital tasks (Module 41).
  static const String tasksManage = 'tasks.manage';

  /// Read clinical form templates and recorded responses (Module 47).
  static const String formsRead = 'forms.read';

  /// Author, version and publish clinical form templates (Module 47).
  static const String formsManage = 'forms.manage';

  /// Record a filled clinical form (Module 47).
  static const String formsSubmit = 'forms.submit';

  /// Read the clinical dashboard (Module 04).
  static const String clinicalDashboardRead = 'clinical.dashboard.read';

  /// Manage clinical assignments (Module 04).
  static const String clinicalDashboardManage = 'clinical.dashboard.manage';

  /// Read clinical performance indicators (Module 03).
  static const String performanceRead = 'performance.read';

  /// Record clinical performance indicators (Module 03).
  static const String performanceManage = 'performance.manage';

  /// Read departmental flow (Module 02).
  static const String operationsRead = 'operations.read';

  /// Record departmental flow (Module 02).
  static const String operationsManage = 'operations.manage';

  /// Read the clinical discussion threads (Module 43).
  static const String messagingRead = 'messaging.read';

  /// Start a clinical thread and post to it (Module 43).
  static const String messagingSend = 'messaging.send';

  /// Read the working boards (Module 44).
  static const String workItemsRead = 'workitems.read';

  /// Add cards to a board and move them between lanes (Module 44).
  static const String workItemsManage = 'workitems.manage';

  /// Read internal service requests (Module 44).
  static const String ticketsRead = 'tickets.read';

  /// Raise an internal service request (Module 44).
  static const String ticketsSubmit = 'tickets.submit';

  /// Work on internal service requests (Module 44).
  static const String ticketsManage = 'tickets.manage';

  /// Approve and finalize a patient discharge.
  static const String dischargeFinalize = 'discharge.finalize';

  /// Authorize blood component issue and transfusion.
  static const String transfusionFinalize = 'transfusion.finalize';

  /// Register, label, reserve, quarantine and discard blood units.
  static const String bloodUnitWrite = 'blood_unit.write';

  /// Raise transfusion requests and record crossmatch results.
  static const String transfusionRequest = 'transfusion.request';

  /// Issue, administer and record transfusion outcomes.
  static const String transfusionAdminister = 'transfusion.administer';

  /// Schedule, reschedule and cancel operation theatre cases.
  static const String otSchedule = 'ot.schedule';

  /// Record pre-op, anesthesia, procedure and post-op theatre data.
  static const String otRecord = 'ot.record';

  /// Complete an operation theatre case after post-op documentation.
  static const String otFinalize = 'ot.finalize';

  /// View invoices, payments and financial summaries.
  static const String billingRead = 'billing.read';

  /// Finalize invoices, payments and refunds.
  static const String billingSettle = 'billing.settle';

  /// Post charges, discounts, tax and adjustments to a patient account.
  static const String billingLedger = 'billing.ledger';

  /// View appointment calendars and schedules.
  static const String appointmentRead = 'appointment.read';

  /// Book, reschedule and cancel appointments.
  static const String appointmentWrite = 'appointment.write';

  /// View operational and clinical analytics.
  static const String reportRead = 'report.read';

  /// Permissions that require online revalidation.
  ///
  /// Mirrors `public.permissions.requires_online = true`. These correspond to
  /// the specification's list of operations that may require online
  /// revalidation or elevated controls: role/permission changes, tenant
  /// administration, high-risk medication actions, transfusion finalization,
  /// financial settlement, discharge finalization and user deactivation.
  static const Set<String> requiresOnline = <String>{
    tenantAdminister,
    facilityAdminister,
    departmentAdminister,
    wardAdminister,
    userAdminister,
    membershipGrant,
    deviceAdminister,
    aiGovernanceAdminister,
    prescriptionFinalize,
    labResultVerify,
    dischargeFinalize,
    transfusionFinalize,
    otFinalize,
    imagingReportVerify,
    dietPlanApprove,
    teleArchiveWrite,
    dischargeSummaryReview,
    billingSettle,

    icuBedAssign,
    icuVitalsRecord,
    icuHandoverRecord,
    ventilatorEventRecord,
    staffDirectoryAdminister,
    payrollManage,
    statutoryCertify,
  };

  /// Permissions classified `high_risk` in the database catalogue.
  ///
  /// High-risk actions additionally require backend/domain authorization beyond
  /// generic row-level access control, and always produce an audit event.
  static const Set<String> highRisk = <String>{
    tenantAdminister,
    userAdminister,
    membershipGrant,
    deviceAdminister,
    aiGovernanceAdminister,
    prescriptionFinalize,
    medicationAdminister,
    labResultVerify,
    pharmacyDispense,
    triageEscalate,

    dischargeFinalize,
    transfusionFinalize,
    transfusionAdminister,
    otFinalize,
    imagingReportVerify,
    dietPlanApprove,
    teleArchiveWrite,
    dischargeSummaryReview,
    billingSettle,
    icuBedAssign,
    icuVitalsRecord,
    icuHandoverRecord,
    ventilatorEventRecord,
  };
}
