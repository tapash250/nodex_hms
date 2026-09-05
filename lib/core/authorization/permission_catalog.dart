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

  /// Approve and finalize a patient discharge.
  static const String dischargeFinalize = 'discharge.finalize';

  /// Authorize blood component issue and transfusion.
  static const String transfusionFinalize = 'transfusion.finalize';

  /// View invoices, payments and financial summaries.
  static const String billingRead = 'billing.read';

  /// Finalize invoices, payments and refunds.
  static const String billingSettle = 'billing.settle';

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
    billingSettle,
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
    billingSettle,
  };
}
