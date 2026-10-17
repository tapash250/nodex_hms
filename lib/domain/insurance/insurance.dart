/// Health Insurance & TPA entities (Module 32).
///
/// Specification scope: "Policy verification, pre-auth, electronic claims."
///
/// This is the payer side of the money: the cover a patient holds, the
/// authorisation a payer gives before treatment, and the claim the hospital
/// submits afterwards. It is distinct from Module 31 (Patient Accounts &
/// Billing), which bills the patient: here the counterparty is an insurer or
/// TPA and the money is recovered rather than collected.
///
/// Four records, mirroring the scope: the governed [InsurancePayer] registry,
/// the patient's [InsurancePolicy], the [PreAuthorisationRequest] the payer
/// answers, and the electronic [InsuranceClaim]. Two facts are *derived*
/// rather than stored, so they cannot drift: the cover state of a policy
/// ([policyCoverState]) and the recovery gap of a claim
/// ([claimRecoveryGap]). Money is an integer number of minor units with an
/// ISO-4217 currency code, matching Module 31 — no float on a recovery figure.
// ignore_for_file: sort_constructors_first
library;

import 'package:meta/meta.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';

/// The nature of a payer.
enum PayerType {
  /// A commercial insurer.
  insurer('insurer'),

  /// A third-party administrator acting for an insurer.
  tpa('tpa'),

  /// A corporate or employer scheme.
  corporate('corporate'),

  /// A government scheme.
  government('government'),

  /// Anything else.
  other('other');

  const PayerType(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    PayerType.insurer => 'Insurer',
    PayerType.tpa => 'TPA',
    PayerType.corporate => 'Corporate',
    PayerType.government => 'Government',
    PayerType.other => 'Other',
  };

  /// Parses a stored value.
  static PayerType fromWire(String value) => PayerType.values.firstWhere(
    (PayerType type) => type.wireValue == value,
    orElse: () => PayerType.other,
  );
}

/// How the cover pays out.
enum CoverageType {
  /// The payer is billed directly.
  cashless('cashless'),

  /// The patient pays and claims back.
  reimbursement('reimbursement'),

  /// Either route is available.
  both('both');

  const CoverageType(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    CoverageType.cashless => 'Cashless',
    CoverageType.reimbursement => 'Reimbursement',
    CoverageType.both => 'Cashless or reimbursement',
  };

  /// Parses a stored value.
  static CoverageType fromWire(String value) => CoverageType.values.firstWhere(
    (CoverageType type) => type.wireValue == value,
    orElse: () => CoverageType.cashless,
  );
}

/// Lifecycle status of a policy.
enum PolicyStatus {
  /// In force.
  active('active'),

  /// Withdrawn; retained and frozen.
  cancelled('cancelled');

  const PolicyStatus(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    PolicyStatus.active => 'Active',
    PolicyStatus.cancelled => 'Cancelled',
  };

  /// Parses a stored value.
  static PolicyStatus fromWire(String value) => PolicyStatus.values.firstWhere(
    (PolicyStatus status) => status.wireValue == value,
    orElse: () => PolicyStatus.active,
  );
}

/// Where a policy stands against its validity window.
///
/// Derived from the window rather than stored, so a policy cannot be marked
/// current while its dates say otherwise.
enum PolicyCoverState {
  /// Withdrawn by the payer or the patient.
  cancelled('cancelled'),

  /// The window has closed.
  expired('expired'),

  /// The window closes soon.
  expiringSoon('expiring soon'),

  /// In force.
  active('active');

  const PolicyCoverState(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    PolicyCoverState.cancelled => 'Cancelled',
    PolicyCoverState.expired => 'Expired',
    PolicyCoverState.expiringSoon => 'Expiring soon',
    PolicyCoverState.active => 'Active',
  };

  /// Whether the cover needs an attention marker on the board.
  bool get needsAttention =>
      this == PolicyCoverState.expired || this == PolicyCoverState.expiringSoon;
}

/// The cover state of a policy, derived from its validity window.
///
/// Cancellation wins over the dates: a cancelled policy is cancelled whatever
/// the window says.
PolicyCoverState policyCoverState({
  required DateTime validTo,
  required DateTime now,
  bool cancelled = false,
  int expiringWithinDays = 30,
}) {
  if (cancelled) {
    return PolicyCoverState.cancelled;
  }
  final DateTime today = _dayOf(now);
  final DateTime end = _dayOf(validTo);
  if (end.isBefore(today)) {
    return PolicyCoverState.expired;
  }
  if (!end.isAfter(today.add(Duration(days: expiringWithinDays)))) {
    return PolicyCoverState.expiringSoon;
  }
  return PolicyCoverState.active;
}

/// Lifecycle status of a pre-authorisation request.
enum PreAuthStatus {
  /// Raised, not yet sent to the payer.
  requested('requested'),

  /// With the payer.
  submitted('submitted'),

  /// Approved in full.
  approved('approved'),

  /// Approved in part.
  partiallyApproved('partially_approved'),

  /// Refused.
  rejected('rejected'),

  /// Withdrawn before an answer.
  cancelled('cancelled');

  const PreAuthStatus(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    PreAuthStatus.requested => 'Requested',
    PreAuthStatus.submitted => 'Submitted',
    PreAuthStatus.approved => 'Approved',
    PreAuthStatus.partiallyApproved => 'Partially approved',
    PreAuthStatus.rejected => 'Rejected',
    PreAuthStatus.cancelled => 'Cancelled',
  };

  /// Parses a stored value.
  static PreAuthStatus fromWire(String value) =>
      PreAuthStatus.values.firstWhere(
        (PreAuthStatus status) => status.wireValue == value,
        orElse: () => PreAuthStatus.requested,
      );

  /// Whether the payer is still to answer.
  bool get isLive =>
      this == PreAuthStatus.requested || this == PreAuthStatus.submitted;

  /// Whether an approval, full or partial, was given.
  bool get isApproved =>
      this == PreAuthStatus.approved || this == PreAuthStatus.partiallyApproved;

  /// Whether the request is closed.
  bool get isTerminal => !isLive;
}

/// Whether a pre-authorisation request may move from [from] to [to].
///
/// One stage at a time, cancellable from either live stage. This is the same
/// rule the database enforces.
bool preAuthCanTransition(PreAuthStatus from, PreAuthStatus to) {
  if (!from.isLive) {
    return false;
  }
  if (to == PreAuthStatus.cancelled) {
    return true;
  }
  return switch (from) {
    PreAuthStatus.requested => to == PreAuthStatus.submitted,
    PreAuthStatus.submitted =>
      to == PreAuthStatus.approved ||
          to == PreAuthStatus.partiallyApproved ||
          to == PreAuthStatus.rejected,
    _ => false,
  };
}

/// Lifecycle status of a claim.
enum ClaimStatus {
  /// Prepared, not yet sent.
  draft('draft'),

  /// Sent to the payer.
  submitted('submitted'),

  /// With the payer.
  underReview('under_review'),

  /// Approved in full.
  approved('approved'),

  /// Approved in part.
  partiallyApproved('partially_approved'),

  /// Refused.
  rejected('rejected'),

  /// Paid.
  settled('settled'),

  /// Withdrawn before a decision.
  cancelled('cancelled');

  const ClaimStatus(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    ClaimStatus.draft => 'Draft',
    ClaimStatus.submitted => 'Submitted',
    ClaimStatus.underReview => 'Under review',
    ClaimStatus.approved => 'Approved',
    ClaimStatus.partiallyApproved => 'Partially approved',
    ClaimStatus.rejected => 'Rejected',
    ClaimStatus.settled => 'Settled',
    ClaimStatus.cancelled => 'Cancelled',
  };

  /// Parses a stored value.
  static ClaimStatus fromWire(String value) => ClaimStatus.values.firstWhere(
    (ClaimStatus status) => status.wireValue == value,
    orElse: () => ClaimStatus.draft,
  );

  /// Whether an approval, full or partial, was given.
  bool get isApproved =>
      this == ClaimStatus.approved || this == ClaimStatus.partiallyApproved;

  /// Whether the claim still has an outcome ahead of it: a decision, or the
  /// payment that follows one.
  bool get isOpen =>
      this == ClaimStatus.draft ||
      this == ClaimStatus.submitted ||
      this == ClaimStatus.underReview ||
      this == ClaimStatus.approved ||
      this == ClaimStatus.partiallyApproved;

  /// Whether the claim is closed.
  bool get isTerminal => !isOpen;
}

/// Whether a claim may move from [from] to [to].
///
/// One stage at a time, cancellable while the claim is open, and settlement
/// only after a decision. This is the same rule the database enforces.
bool claimCanTransition(ClaimStatus from, ClaimStatus to) {
  if (from.isTerminal) {
    return false;
  }
  if (to == ClaimStatus.cancelled) {
    return true;
  }
  return switch (from) {
    ClaimStatus.draft => to == ClaimStatus.submitted,
    ClaimStatus.submitted => to == ClaimStatus.underReview,
    ClaimStatus.underReview =>
      to == ClaimStatus.approved ||
          to == ClaimStatus.partiallyApproved ||
          to == ClaimStatus.rejected,
    ClaimStatus.approved ||
    ClaimStatus.partiallyApproved => to == ClaimStatus.settled,
    _ => false,
  };
}

/// The amount of a claim still to be recovered: what was claimed against what
/// the payer has settled.
///
/// Negative results are impossible — a settlement for more than the claim is a
/// prior claim's money, not a negative gap — so the floor is zero.
int claimRecoveryGap({required int claimedMinor, required int settledMinor}) {
  final int gap = claimedMinor - settledMinor;
  return gap > 0 ? gap : 0;
}

/// An insurer, TPA, corporate or government scheme.
@immutable
final class InsurancePayer {
  /// Creates a payer.
  const InsurancePayer({
    required this.id,
    required this.tenantId,
    required this.code,
    required this.name,
    required this.payerType,
    required this.isActive,
    required this.createdBy,
    required this.updatedAt,
    this.claimPortalRef,
    this.contactPhone,
    this.contactEmail,
    this.notes,
    this.createdAt,
  });

  /// Validates and builds a new payer row.
  static Map<String, Object?> registerRow({
    required String tenantId,
    required String createdBy,
    required String code,
    required String name,
    PayerType payerType = PayerType.insurer,
    String? claimPortalRef,
    String? contactPhone,
    String? contactEmail,
    bool isActive = true,
    String? notes,
    String payerId = '',
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (createdBy.isEmpty) {
      fieldErrors['created_by'] = 'Creator is required.';
    }
    if (code.trim().isEmpty) {
      fieldErrors['code'] = 'A code is required.';
    }
    if (name.trim().isEmpty) {
      fieldErrors['name'] = 'A name is required.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Payer failed validation.',
        fieldErrors: fieldErrors,
        code: 'insurance_payer_invalid',
      );
    }
    final String now = DateTime.now().toUtc().toIso8601String();
    return <String, Object?>{
      if (payerId.isNotEmpty) 'id': payerId,
      'tenant_id': tenantId,
      'code': code.trim(),
      'name': name.trim(),
      'payer_type': payerType.wireValue,
      'claim_portal_ref': _trimmed(claimPortalRef),
      'contact_phone': _trimmed(contactPhone),
      'contact_email': _trimmed(contactEmail),
      'is_active': isActive ? 1 : 0,
      'notes': _trimmed(notes),
      'created_by': createdBy,
      'created_at': now,
      'updated_at': now,
    };
  }

  /// Materializes a payer from a local row.
  factory InsurancePayer.fromRow(Map<String, Object?> row) => InsurancePayer(
    id: row['id']! as String,
    tenantId: row['tenant_id']! as String,
    code: row['code']! as String,
    name: row['name']! as String,
    payerType: PayerType.fromWire(
      (row['payer_type'] as String?) ?? PayerType.other.wireValue,
    ),
    isActive: _asBool(row['is_active']),
    createdBy: row['created_by']! as String,
    updatedAt: _parse(row['updated_at']),
    claimPortalRef: row['claim_portal_ref'] as String?,
    contactPhone: row['contact_phone'] as String?,
    contactEmail: row['contact_email'] as String?,
    notes: row['notes'] as String?,
    createdAt: _parseNullable(row['created_at']),
  );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// Unique short code.
  final String code;

  /// Display name.
  final String name;

  /// Nature of the payer.
  final PayerType payerType;

  /// Whether the payer is currently contracted with.
  final bool isActive;

  /// Who created the record.
  final String createdBy;

  /// Last change, UTC.
  final DateTime updatedAt;

  /// Reference the payer uses on its claim portal.
  final String? claimPortalRef;

  /// Contact telephone.
  final String? contactPhone;

  /// Contact email.
  final String? contactEmail;

  /// Free-text note.
  final String? notes;

  /// When the record was created, UTC.
  final DateTime? createdAt;
}

/// The change set for a payer.
Map<String, Object?> payerChanges({
  required String code,
  required String name,
  PayerType? payerType,
  String? claimPortalRef,
  String? contactPhone,
  String? contactEmail,
  bool? isActive,
  String? notes,
}) => <String, Object?>{
  'code': code.trim(),
  'name': name.trim(),
  'claim_portal_ref': _trimmed(claimPortalRef),
  'contact_phone': _trimmed(contactPhone),
  'contact_email': _trimmed(contactEmail),
  'notes': _trimmed(notes),
  if (payerType != null) 'payer_type': payerType.wireValue,
  if (isActive != null) 'is_active': isActive ? 1 : 0,
  'updated_at': DateTime.now().toUtc().toIso8601String(),
};

/// The cover a patient holds with a payer.
@immutable
final class InsurancePolicy {
  /// Creates a policy.
  const InsurancePolicy({
    required this.id,
    required this.tenantId,
    required this.patientId,
    required this.payerId,
    required this.policyNo,
    required this.coverageType,
    required this.currency,
    required this.sumInsuredMinor,
    required this.validFrom,
    required this.validTo,
    required this.status,
    required this.createdBy,
    required this.updatedAt,
    this.memberId,
    this.planName,
    this.verifiedAt,
    this.verifiedBy,
    this.verificationReference,
    this.cancelledAt,
    this.cancellationReason,
    this.notes,
    this.createdAt,
  });

  /// Validates and builds a new policy row.
  static Map<String, Object?> registerRow({
    required String tenantId,
    required String patientId,
    required String payerId,
    required String createdBy,
    required String policyNo,
    required DateTime validFrom,
    required DateTime validTo,
    CoverageType coverageType = CoverageType.cashless,
    String currency = 'BDT',
    int sumInsuredMinor = 0,
    String? memberId,
    String? planName,
    String? notes,
    String policyId = '',
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (patientId.isEmpty) {
      fieldErrors['patient_id'] = 'A patient is required.';
    }
    if (payerId.isEmpty) {
      fieldErrors['payer_id'] = 'A payer is required.';
    }
    if (createdBy.isEmpty) {
      fieldErrors['created_by'] = 'Creator is required.';
    }
    if (policyNo.trim().isEmpty) {
      fieldErrors['policy_no'] = 'A policy number is required.';
    }
    if (sumInsuredMinor < 0) {
      fieldErrors['sum_insured_minor'] = 'Expected zero or more.';
    }
    if (validTo.isBefore(validFrom)) {
      fieldErrors['valid_to'] = 'The window cannot close before it opens.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Insurance policy failed validation.',
        fieldErrors: fieldErrors,
        code: 'insurance_policy_invalid',
      );
    }
    final String now = DateTime.now().toUtc().toIso8601String();
    return <String, Object?>{
      if (policyId.isNotEmpty) 'id': policyId,
      'tenant_id': tenantId,
      'patient_id': patientId,
      'payer_id': payerId,
      'policy_no': policyNo.trim(),
      'member_id': _trimmed(memberId),
      'plan_name': _trimmed(planName),
      'coverage_type': coverageType.wireValue,
      'currency': currency,
      'sum_insured_minor': sumInsuredMinor,
      'valid_from': _dateOnly(validFrom),
      'valid_to': _dateOnly(validTo),
      'status': PolicyStatus.active.wireValue,
      'verified_at': null,
      'verified_by': null,
      'verification_reference': null,
      'cancelled_at': null,
      'cancellation_reason': null,
      'notes': _trimmed(notes),
      'created_by': createdBy,
      'created_at': now,
      'updated_at': now,
    };
  }

  /// Materializes a policy from a local row.
  factory InsurancePolicy.fromRow(Map<String, Object?> row) => InsurancePolicy(
    id: row['id']! as String,
    tenantId: row['tenant_id']! as String,
    patientId: row['patient_id']! as String,
    payerId: row['payer_id']! as String,
    policyNo: row['policy_no']! as String,
    coverageType: CoverageType.fromWire(
      (row['coverage_type'] as String?) ?? CoverageType.cashless.wireValue,
    ),
    currency: (row['currency'] as String?) ?? 'BDT',
    sumInsuredMinor: _asInt(row['sum_insured_minor']),
    validFrom: _parseDate(row['valid_from']),
    validTo: _parseDate(row['valid_to']),
    status: PolicyStatus.fromWire(
      (row['status'] as String?) ?? PolicyStatus.active.wireValue,
    ),
    createdBy: row['created_by']! as String,
    updatedAt: _parse(row['updated_at']),
    memberId: row['member_id'] as String?,
    planName: row['plan_name'] as String?,
    verifiedAt: _parseNullable(row['verified_at']),
    verifiedBy: row['verified_by'] as String?,
    verificationReference: row['verification_reference'] as String?,
    cancelledAt: _parseNullable(row['cancelled_at']),
    cancellationReason: row['cancellation_reason'] as String?,
    notes: row['notes'] as String?,
    createdAt: _parseNullable(row['created_at']),
  );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// The covered patient.
  final String patientId;

  /// The payer.
  final String payerId;

  /// The payer's policy number.
  final String policyNo;

  /// How the cover pays out.
  final CoverageType coverageType;

  /// ISO-4217 currency of the sums.
  final String currency;

  /// Sum insured, in minor units.
  final int sumInsuredMinor;

  /// First day of cover, UTC midnight.
  final DateTime validFrom;

  /// Last day of cover, UTC midnight.
  final DateTime validTo;

  /// Lifecycle status.
  final PolicyStatus status;

  /// Who created the record.
  final String createdBy;

  /// Last change, UTC.
  final DateTime updatedAt;

  /// The payer's member identifier.
  final String? memberId;

  /// Plan name as the payer states it.
  final String? planName;

  /// When the cover was verified, UTC.
  final DateTime? verifiedAt;

  /// Who verified the cover.
  final String? verifiedBy;

  /// The payer's verification reference.
  final String? verificationReference;

  /// When the policy was cancelled, UTC.
  final DateTime? cancelledAt;

  /// Why the policy was cancelled.
  final String? cancellationReason;

  /// Free-text note.
  final String? notes;

  /// When the record was created, UTC.
  final DateTime? createdAt;

  /// Whether the cover has been verified with the payer.
  bool get isVerified => verifiedAt != null && verifiedBy != null;

  /// Whether the policy can still be changed.
  bool get isEditable => status == PolicyStatus.active;
}

/// The change set for editing a policy before cancellation.
Map<String, Object?> policyChanges({
  required String policyNo,
  required DateTime validFrom,
  required DateTime validTo,
  CoverageType? coverageType,
  int? sumInsuredMinor,
  String? memberId,
  String? planName,
  String? notes,
}) {
  if (validTo.isBefore(validFrom)) {
    throw const ValidationError(
      message: 'Insurance policy failed validation.',
      fieldErrors: <String, String>{
        'valid_to': 'The window cannot close before it opens.',
      },
      code: 'insurance_policy_invalid',
    );
  }
  return <String, Object?>{
    'policy_no': policyNo.trim(),
    'member_id': _trimmed(memberId),
    'plan_name': _trimmed(planName),
    'valid_from': _dateOnly(validFrom),
    'valid_to': _dateOnly(validTo),
    'notes': _trimmed(notes),
    if (coverageType != null) 'coverage_type': coverageType.wireValue,
    'sum_insured_minor': ?sumInsuredMinor,
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  };
}

/// The change set for recording verification of a policy.
Map<String, Object?> policyVerifyChanges({
  required String verifiedBy,
  String? reference,
}) {
  if (verifiedBy.isEmpty) {
    throw const ValidationError(
      message: 'Insurance policy failed validation.',
      fieldErrors: <String, String>{'verified_by': 'A verifier is required.'},
      code: 'insurance_policy_invalid',
    );
  }
  final String now = DateTime.now().toUtc().toIso8601String();
  return <String, Object?>{
    'verified_at': now,
    'verified_by': verifiedBy,
    'verification_reference': _trimmed(reference),
    'updated_at': now,
  };
}

/// The change set for cancelling a policy. The row is retained and frozen.
Map<String, Object?> policyCancelChanges({required String reason}) {
  if (reason.trim().isEmpty) {
    throw const ValidationError(
      message: 'Insurance policy failed validation.',
      fieldErrors: <String, String>{
        'cancellation_reason': 'Say why the cover is cancelled.',
      },
      code: 'insurance_policy_reason_required',
    );
  }
  final String now = DateTime.now().toUtc().toIso8601String();
  return <String, Object?>{
    'status': PolicyStatus.cancelled.wireValue,
    'cancelled_at': now,
    'cancellation_reason': reason.trim(),
    'updated_at': now,
  };
}

/// A request for the payer's authorisation before treatment.
@immutable
final class PreAuthorisationRequest {
  /// Creates a pre-authorisation request.
  const PreAuthorisationRequest({
    required this.id,
    required this.tenantId,
    required this.policyId,
    required this.patientId,
    required this.facilityId,
    required this.requestedBy,
    required this.requestedAt,
    required this.diagnosis,
    required this.procedureText,
    required this.currency,
    required this.estimatedCostMinor,
    required this.status,
    required this.createdBy,
    required this.updatedAt,
    this.encounterId,
    this.payerReference,
    this.answeredAt,
    this.approvedAmountMinor,
    this.validUntil,
    this.decisionNotes,
    this.cancellationReason,
    this.createdAt,
  });

  /// Validates and builds a new request row.
  static Map<String, Object?> registerRow({
    required String tenantId,
    required String policyId,
    required String patientId,
    required String facilityId,
    required String requestedBy,
    required String diagnosis,
    required String procedureText,
    required int estimatedCostMinor,
    String currency = 'BDT',
    String? encounterId,
    DateTime? requestedAt,
    String preAuthId = '',
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (policyId.isEmpty) {
      fieldErrors['policy_id'] = 'A policy is required.';
    }
    if (patientId.isEmpty) {
      fieldErrors['patient_id'] = 'A patient is required.';
    }
    if (facilityId.isEmpty) {
      fieldErrors['facility_id'] = 'A facility is required.';
    }
    if (requestedBy.isEmpty) {
      fieldErrors['requested_by'] = 'A requester is required.';
    }
    if (diagnosis.trim().isEmpty) {
      fieldErrors['diagnosis'] = 'A diagnosis is required.';
    }
    if (procedureText.trim().isEmpty) {
      fieldErrors['procedure_text'] = 'A procedure is required.';
    }
    if (estimatedCostMinor <= 0) {
      fieldErrors['estimated_cost_minor'] =
          'Expected an estimate greater than zero.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Pre-authorisation request failed validation.',
        fieldErrors: fieldErrors,
        code: 'pre_authorisation_invalid',
      );
    }
    final String now = (requestedAt ?? DateTime.now().toUtc())
        .toUtc()
        .toIso8601String();
    return <String, Object?>{
      if (preAuthId.isNotEmpty) 'id': preAuthId,
      'tenant_id': tenantId,
      'policy_id': policyId,
      'patient_id': patientId,
      'facility_id': facilityId,
      'encounter_id': _trimmed(encounterId),
      'requested_by': requestedBy,
      'requested_at': now,
      'diagnosis': diagnosis.trim(),
      'procedure_text': procedureText.trim(),
      'currency': currency,
      'estimated_cost_minor': estimatedCostMinor,
      'status': PreAuthStatus.requested.wireValue,
      'payer_reference': null,
      'answered_at': null,
      'approved_amount_minor': null,
      'valid_until': null,
      'decision_notes': null,
      'cancellation_reason': null,
      'created_by': requestedBy,
      'created_at': now,
      'updated_at': now,
    };
  }

  /// Materializes a request from a local row.
  factory PreAuthorisationRequest.fromRow(Map<String, Object?> row) =>
      PreAuthorisationRequest(
        id: row['id']! as String,
        tenantId: row['tenant_id']! as String,
        policyId: row['policy_id']! as String,
        patientId: row['patient_id']! as String,
        facilityId: row['facility_id']! as String,
        requestedBy: row['requested_by']! as String,
        requestedAt: _parse(row['requested_at']),
        diagnosis: row['diagnosis']! as String,
        procedureText: row['procedure_text']! as String,
        currency: (row['currency'] as String?) ?? 'BDT',
        estimatedCostMinor: _asInt(row['estimated_cost_minor']),
        status: PreAuthStatus.fromWire(
          (row['status'] as String?) ?? PreAuthStatus.requested.wireValue,
        ),
        createdBy: row['created_by']! as String,
        updatedAt: _parse(row['updated_at']),
        encounterId: row['encounter_id'] as String?,
        payerReference: row['payer_reference'] as String?,
        answeredAt: _parseNullable(row['answered_at']),
        approvedAmountMinor: row['approved_amount_minor'] == null
            ? null
            : _asInt(row['approved_amount_minor']),
        validUntil: _parseNullable(row['valid_until']),
        decisionNotes: row['decision_notes'] as String?,
        cancellationReason: row['cancellation_reason'] as String?,
        createdAt: _parseNullable(row['created_at']),
      );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// The policy authorisation is sought under.
  final String policyId;

  /// The patient.
  final String patientId;

  /// The facility.
  final String facilityId;

  /// Who raised the request.
  final String requestedBy;

  /// When the request was raised, UTC.
  final DateTime requestedAt;

  /// Working diagnosis.
  final String diagnosis;

  /// Procedure or treatment being authorised.
  final String procedureText;

  /// ISO-4217 currency of the sums.
  final String currency;

  /// Estimated cost, in minor units.
  final int estimatedCostMinor;

  /// Lifecycle status.
  final PreAuthStatus status;

  /// Who created the record.
  final String createdBy;

  /// Last change, UTC.
  final DateTime updatedAt;

  /// The encounter the request relates to, when known.
  final String? encounterId;

  /// The payer's own reference.
  final String? payerReference;

  /// When the payer answered, UTC.
  final DateTime? answeredAt;

  /// Amount approved, in minor units.
  final int? approvedAmountMinor;

  /// How long the authorisation is valid, UTC.
  final DateTime? validUntil;

  /// The payer's notes on the decision.
  final String? decisionNotes;

  /// Why the request was withdrawn.
  final String? cancellationReason;

  /// When the record was created, UTC.
  final DateTime? createdAt;

  /// Whether the request can still move.
  bool get isLive => status.isLive;

  /// The amount the payer did not approve, when there is an answer.
  int? get shortfallMinor => approvedAmountMinor == null
      ? null
      : (estimatedCostMinor - approvedAmountMinor!) > 0
      ? estimatedCostMinor - approvedAmountMinor!
      : 0;
}

/// The change set for submitting a request to the payer.
Map<String, Object?> preAuthSubmitChanges({String? payerReference}) =>
    <String, Object?>{
      'status': PreAuthStatus.submitted.wireValue,
      'payer_reference': _trimmed(payerReference),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

/// The change set for recording the payer's answer.
///
/// An approval carries an amount; a rejection carries a reason. The database
/// enforces the same pair, so the two cannot drift.
Map<String, Object?> preAuthAnswerChanges({
  required PreAuthStatus decision,
  required int estimatedCostMinor,
  int? approvedAmountMinor,
  String? payerReference,
  DateTime? validUntil,
  String? decisionNotes,
}) {
  if (!decision.isApproved && decision != PreAuthStatus.rejected) {
    throw const ValidationError(
      message: 'Pre-authorisation request failed validation.',
      fieldErrors: <String, String>{
        'status': 'The payer either approves, partly approves or rejects.',
      },
      code: 'pre_authorisation_invalid',
    );
  }
  final Map<String, String> fieldErrors = <String, String>{};
  if (decision.isApproved) {
    if (approvedAmountMinor == null || approvedAmountMinor <= 0) {
      fieldErrors['approved_amount_minor'] =
          'An approval carries an amount greater than zero.';
    } else if (approvedAmountMinor > estimatedCostMinor) {
      fieldErrors['approved_amount_minor'] =
          'The payer cannot approve more than was estimated.';
    }
  }
  if (decision == PreAuthStatus.rejected &&
      (decisionNotes == null || decisionNotes.trim().isEmpty)) {
    fieldErrors['decision_notes'] = 'A refusal must say why.';
  }
  if (fieldErrors.isNotEmpty) {
    throw ValidationError(
      message: 'Pre-authorisation request failed validation.',
      fieldErrors: fieldErrors,
      code: 'pre_authorisation_invalid',
    );
  }
  final String now = DateTime.now().toUtc().toIso8601String();
  return <String, Object?>{
    'status': decision.wireValue,
    'answered_at': now,
    'approved_amount_minor': decision.isApproved ? approvedAmountMinor : null,
    'payer_reference': _trimmed(payerReference),
    'valid_until': validUntil?.toUtc().toIso8601String(),
    'decision_notes': _trimmed(decisionNotes),
    'updated_at': now,
  };
}

/// The change set for withdrawing a request before an answer.
Map<String, Object?> preAuthCancelChanges({required String reason}) {
  if (reason.trim().isEmpty) {
    throw const ValidationError(
      message: 'Pre-authorisation request failed validation.',
      fieldErrors: <String, String>{
        'cancellation_reason': 'Say why the request is withdrawn.',
      },
      code: 'pre_authorisation_reason_required',
    );
  }
  return <String, Object?>{
    'status': PreAuthStatus.cancelled.wireValue,
    'cancellation_reason': reason.trim(),
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  };
}

/// A claim submitted to the payer.
@immutable
final class InsuranceClaim {
  /// Creates a claim.
  const InsuranceClaim({
    required this.id,
    required this.tenantId,
    required this.policyId,
    required this.patientId,
    required this.facilityId,
    required this.claimNo,
    required this.currency,
    required this.claimedAmountMinor,
    required this.status,
    required this.createdBy,
    required this.updatedAt,
    this.preAuthorisationId,
    this.invoiceId,
    this.approvedAmountMinor,
    this.settledAmountMinor,
    this.payerReference,
    this.submittedAt,
    this.decidedAt,
    this.settledAt,
    this.rejectionReason,
    this.cancellationReason,
    this.notes,
    this.createdAt,
  });

  /// Validates and builds a new claim row.
  static Map<String, Object?> registerRow({
    required String tenantId,
    required String policyId,
    required String patientId,
    required String facilityId,
    required String createdBy,
    required String claimNo,
    required int claimedAmountMinor,
    String currency = 'BDT',
    String? preAuthorisationId,
    String? invoiceId,
    String? notes,
    String claimId = '',
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (policyId.isEmpty) {
      fieldErrors['policy_id'] = 'A policy is required.';
    }
    if (patientId.isEmpty) {
      fieldErrors['patient_id'] = 'A patient is required.';
    }
    if (facilityId.isEmpty) {
      fieldErrors['facility_id'] = 'A facility is required.';
    }
    if (createdBy.isEmpty) {
      fieldErrors['created_by'] = 'A creator is required.';
    }
    if (claimNo.trim().isEmpty) {
      fieldErrors['claim_no'] = 'A claim number is required.';
    }
    if (claimedAmountMinor <= 0) {
      fieldErrors['claimed_amount_minor'] =
          'Expected a claim greater than zero.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Insurance claim failed validation.',
        fieldErrors: fieldErrors,
        code: 'insurance_claim_invalid',
      );
    }
    final String now = DateTime.now().toUtc().toIso8601String();
    return <String, Object?>{
      if (claimId.isNotEmpty) 'id': claimId,
      'tenant_id': tenantId,
      'policy_id': policyId,
      'patient_id': patientId,
      'facility_id': facilityId,
      'pre_authorisation_id': _trimmed(preAuthorisationId),
      'invoice_id': _trimmed(invoiceId),
      'claim_no': claimNo.trim(),
      'currency': currency,
      'claimed_amount_minor': claimedAmountMinor,
      'approved_amount_minor': null,
      'settled_amount_minor': null,
      'status': ClaimStatus.draft.wireValue,
      'payer_reference': null,
      'submitted_at': null,
      'decided_at': null,
      'settled_at': null,
      'rejection_reason': null,
      'cancellation_reason': null,
      'notes': _trimmed(notes),
      'created_by': createdBy,
      'created_at': now,
      'updated_at': now,
    };
  }

  /// Materializes a claim from a local row.
  factory InsuranceClaim.fromRow(Map<String, Object?> row) => InsuranceClaim(
    id: row['id']! as String,
    tenantId: row['tenant_id']! as String,
    policyId: row['policy_id']! as String,
    patientId: row['patient_id']! as String,
    facilityId: row['facility_id']! as String,
    claimNo: row['claim_no']! as String,
    currency: (row['currency'] as String?) ?? 'BDT',
    claimedAmountMinor: _asInt(row['claimed_amount_minor']),
    status: ClaimStatus.fromWire(
      (row['status'] as String?) ?? ClaimStatus.draft.wireValue,
    ),
    createdBy: row['created_by']! as String,
    updatedAt: _parse(row['updated_at']),
    preAuthorisationId: row['pre_authorisation_id'] as String?,
    invoiceId: row['invoice_id'] as String?,
    approvedAmountMinor: row['approved_amount_minor'] == null
        ? null
        : _asInt(row['approved_amount_minor']),
    settledAmountMinor: row['settled_amount_minor'] == null
        ? null
        : _asInt(row['settled_amount_minor']),
    payerReference: row['payer_reference'] as String?,
    submittedAt: _parseNullable(row['submitted_at']),
    decidedAt: _parseNullable(row['decided_at']),
    settledAt: _parseNullable(row['settled_at']),
    rejectionReason: row['rejection_reason'] as String?,
    cancellationReason: row['cancellation_reason'] as String?,
    notes: row['notes'] as String?,
    createdAt: _parseNullable(row['created_at']),
  );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// The policy claimed under.
  final String policyId;

  /// The patient.
  final String patientId;

  /// The facility.
  final String facilityId;

  /// The hospital's claim number.
  final String claimNo;

  /// ISO-4217 currency of the sums.
  final String currency;

  /// Amount claimed, in minor units.
  final int claimedAmountMinor;

  /// Lifecycle status.
  final ClaimStatus status;

  /// Who created the record.
  final String createdBy;

  /// Last change, UTC.
  final DateTime updatedAt;

  /// The authorisation that preceded the claim, when there was one.
  final String? preAuthorisationId;

  /// The Module 31 invoice the claim recovers, when there is one.
  final String? invoiceId;

  /// Amount the payer approved, in minor units.
  final int? approvedAmountMinor;

  /// Amount the payer paid, in minor units.
  final int? settledAmountMinor;

  /// The payer's own reference.
  final String? payerReference;

  /// When the claim was sent, UTC.
  final DateTime? submittedAt;

  /// When the payer decided, UTC.
  final DateTime? decidedAt;

  /// When the payer paid, UTC.
  final DateTime? settledAt;

  /// Why the payer refused.
  final String? rejectionReason;

  /// Why the claim was withdrawn.
  final String? cancellationReason;

  /// Free-text note.
  final String? notes;

  /// When the record was created, UTC.
  final DateTime? createdAt;

  /// Whether the claim can still move.
  bool get isOpen => status.isOpen;

  /// The amount still to be recovered, in minor units.
  int get recoveryGapMinor => claimRecoveryGap(
    claimedMinor: claimedAmountMinor,
    settledMinor: settledAmountMinor ?? 0,
  );
}

/// The change set for sending a claim to the payer.
Map<String, Object?> claimSubmitChanges({String? payerReference}) {
  final String now = DateTime.now().toUtc().toIso8601String();
  return <String, Object?>{
    'status': ClaimStatus.submitted.wireValue,
    'submitted_at': now,
    'payer_reference': _trimmed(payerReference),
    'updated_at': now,
  };
}

/// The change set for moving a submitted claim into review.
Map<String, Object?> claimReviewChanges() => <String, Object?>{
  'status': ClaimStatus.underReview.wireValue,
  'updated_at': DateTime.now().toUtc().toIso8601String(),
};

/// The change set for recording the payer's decision.
///
/// An approval carries an amount no greater than the claim; a rejection carries
/// a reason. The database enforces the same pair.
Map<String, Object?> claimDecisionChanges({
  required ClaimStatus decision,
  required int claimedAmountMinor,
  int? approvedAmountMinor,
  String? payerReference,
  String? rejectionReason,
  String? notes,
}) {
  if (!decision.isApproved && decision != ClaimStatus.rejected) {
    throw const ValidationError(
      message: 'Insurance claim failed validation.',
      fieldErrors: <String, String>{
        'status': 'The payer either approves, partly approves or rejects.',
      },
      code: 'insurance_claim_invalid',
    );
  }
  final Map<String, String> fieldErrors = <String, String>{};
  if (decision.isApproved) {
    if (approvedAmountMinor == null || approvedAmountMinor <= 0) {
      fieldErrors['approved_amount_minor'] =
          'An approval carries an amount greater than zero.';
    } else if (approvedAmountMinor > claimedAmountMinor) {
      fieldErrors['approved_amount_minor'] =
          'The payer cannot approve more than was claimed.';
    }
  }
  if (decision == ClaimStatus.rejected &&
      (rejectionReason == null || rejectionReason.trim().isEmpty)) {
    fieldErrors['rejection_reason'] = 'A refusal must say why.';
  }
  if (fieldErrors.isNotEmpty) {
    throw ValidationError(
      message: 'Insurance claim failed validation.',
      fieldErrors: fieldErrors,
      code: 'insurance_claim_invalid',
    );
  }
  final String now = DateTime.now().toUtc().toIso8601String();
  return <String, Object?>{
    'status': decision.wireValue,
    'decided_at': now,
    'approved_amount_minor': decision.isApproved ? approvedAmountMinor : null,
    'payer_reference': _trimmed(payerReference),
    'rejection_reason': _trimmed(rejectionReason),
    'notes': _trimmed(notes),
    'updated_at': now,
  };
}

/// The change set for recording a settlement.
Map<String, Object?> claimSettleChanges({
  required int settledAmountMinor,
  int? approvedAmountMinor,
  String? payerReference,
  String? notes,
}) {
  final Map<String, String> fieldErrors = <String, String>{};
  if (settledAmountMinor <= 0) {
    fieldErrors['settled_amount_minor'] = 'A settlement is greater than zero.';
  } else if (approvedAmountMinor != null &&
      settledAmountMinor > approvedAmountMinor) {
    fieldErrors['settled_amount_minor'] =
        'A payer cannot settle more than it approved.';
  }
  if (fieldErrors.isNotEmpty) {
    throw ValidationError(
      message: 'Insurance claim failed validation.',
      fieldErrors: fieldErrors,
      code: 'insurance_claim_invalid',
    );
  }
  final String now = DateTime.now().toUtc().toIso8601String();
  return <String, Object?>{
    'status': ClaimStatus.settled.wireValue,
    'settled_at': now,
    'settled_amount_minor': settledAmountMinor,
    'payer_reference': _trimmed(payerReference),
    'notes': _trimmed(notes),
    'updated_at': now,
  };
}

/// The change set for withdrawing a claim before a decision.
Map<String, Object?> claimCancelChanges({required String reason}) {
  if (reason.trim().isEmpty) {
    throw const ValidationError(
      message: 'Insurance claim failed validation.',
      fieldErrors: <String, String>{
        'cancellation_reason': 'Say why the claim is withdrawn.',
      },
      code: 'insurance_claim_reason_required',
    );
  }
  return <String, Object?>{
    'status': ClaimStatus.cancelled.wireValue,
    'cancellation_reason': reason.trim(),
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  };
}

String? _trimmed(String? value) {
  final String? trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

DateTime _dayOf(DateTime value) {
  final DateTime utc = value.toUtc();
  return DateTime.utc(utc.year, utc.month, utc.day);
}

String _dateOnly(DateTime value) {
  final DateTime day = _dayOf(value);
  return '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';
}

DateTime _parse(Object? value) => value is String
    ? DateTime.parse(value).toUtc()
    : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

/// Parses a store date.
///
/// The validity window is a calendar date, not an instant: a row holding
/// `2026-01-01` means the first of January, so it is read as UTC midnight and
/// not shifted by the device's timezone into the previous day.
DateTime _parseDate(Object? value) {
  if (value is! String) {
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }
  final List<String> parts = value.split('-');
  if (parts.length == 3) {
    final int? year = int.tryParse(parts[0]);
    final int? month = int.tryParse(parts[1]);
    final int? day = int.tryParse(
      parts[2].length > 2 ? parts[2].substring(0, 2) : parts[2],
    );
    if (year != null && month != null && day != null) {
      return DateTime.utc(year, month, day);
    }
  }
  return DateTime.parse(value).toUtc();
}

DateTime? _parseNullable(Object? value) =>
    value is String ? DateTime.parse(value).toUtc() : null;

int _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.parse(value);
  }
  return 0;
}

bool _asBool(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  if (value is String) {
    return value == '1' || value.toLowerCase() == 'true';
  }
  return false;
}
