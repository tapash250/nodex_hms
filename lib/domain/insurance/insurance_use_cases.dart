/// Health Insurance & TPA use cases (Module 32).
library;

import 'package:meta/meta.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/insurance/insurance.dart';
import 'package:nodex_hms/domain/insurance/insurance_repository.dart';

/// Registers an insurer, TPA, corporate or government scheme.
final class RegisterPayerUseCase {
  /// Creates the use case.
  RegisterPayerUseCase({required this._repository});

  final InsuranceRepository _repository;

  Future<String> call({
    required AuthorizationPolicy policy,
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
  }) async {
    policy.require(NodexPermissions.insuranceManage);
    await _requireFreeCode(tenantId, code, exceptId: payerId);
    return _repository.registerPayer(
      InsurancePayer.registerRow(
        tenantId: tenantId,
        createdBy: createdBy,
        code: code,
        name: name,
        payerType: payerType,
        claimPortalRef: claimPortalRef,
        contactPhone: contactPhone,
        contactEmail: contactEmail,
        isActive: isActive,
        notes: notes,
        payerId: payerId,
      ),
    );
  }

  /// The code is unique within the tenant, a rule the database enforces; this
  /// checks the same rule against the rows already on the device, so a
  /// duplicate is refused immediately offline.
  Future<void> _requireFreeCode(
    String tenantId,
    String code, {
    required String exceptId,
  }) async {
    final List<InsurancePayer> payers = await _repository.listPayers(tenantId);
    for (final InsurancePayer payer in payers) {
      if (payer.code == code.trim() && payer.id != exceptId) {
        throw const ValidationError(
          message: 'Payer failed validation.',
          fieldErrors: <String, String>{
            'code': 'That payer code is already used.',
          },
          code: 'insurance_payer_duplicate',
        );
      }
    }
  }
}

/// Updates a payer registry entry.
final class UpdatePayerUseCase {
  /// Creates the use case.
  UpdatePayerUseCase({required this._repository});

  final InsuranceRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required InsurancePayer payer,
    required String code,
    required String name,
    PayerType? payerType,
    String? claimPortalRef,
    String? contactPhone,
    String? contactEmail,
    bool? isActive,
    String? notes,
  }) async {
    policy.require(NodexPermissions.insuranceManage);
    await _repository.updatePayer(
      payer.id,
      payerChanges(
        code: code,
        name: name,
        payerType: payerType,
        claimPortalRef: claimPortalRef,
        contactPhone: contactPhone,
        contactEmail: contactEmail,
        isActive: isActive,
        notes: notes,
      ),
    );
  }
}

/// Registers a patient's cover.
final class RegisterPolicyUseCase {
  /// Creates the use case.
  RegisterPolicyUseCase({required this._repository});

  final InsuranceRepository _repository;

  Future<String> call({
    required AuthorizationPolicy policy,
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
  }) async {
    policy.require(NodexPermissions.insuranceManage);
    await _requireActivePayer(payerId);
    final List<InsurancePolicy> existing = await _repository.listPolicies(
      tenantId,
    );
    for (final InsurancePolicy other in existing) {
      if (other.policyNo == policyNo.trim() && other.id != policyId) {
        throw const ValidationError(
          message: 'Insurance policy failed validation.',
          fieldErrors: <String, String>{
            'policy_no': 'That policy number is already used.',
          },
          code: 'insurance_policy_duplicate',
        );
      }
    }
    return _repository.registerPolicy(
      InsurancePolicy.registerRow(
        tenantId: tenantId,
        patientId: patientId,
        payerId: payerId,
        createdBy: createdBy,
        policyNo: policyNo,
        validFrom: validFrom,
        validTo: validTo,
        coverageType: coverageType,
        currency: currency,
        sumInsuredMinor: sumInsuredMinor,
        memberId: memberId,
        planName: planName,
        notes: notes,
        policyId: policyId,
      ),
    );
  }

  Future<void> _requireActivePayer(String payerId) async {
    final InsurancePayer? payer = await _repository.payerById(payerId);
    if (payer == null) {
      throw const ValidationError(
        message: 'Insurance policy failed validation.',
        fieldErrors: <String, String>{'payer_id': 'That payer does not exist.'},
        code: 'insurance_payer_missing',
      );
    }
    if (!payer.isActive) {
      throw const ValidationError(
        message: 'Insurance policy failed validation.',
        fieldErrors: <String, String>{
          'payer_id': 'That payer is no longer contracted with.',
        },
        code: 'insurance_payer_inactive',
      );
    }
  }
}

/// Edits a policy that is still in force.
final class UpdatePolicyUseCase {
  /// Creates the use case.
  UpdatePolicyUseCase({required this._repository});

  final InsuranceRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required InsurancePolicy insurancePolicy,
    required String policyNo,
    required DateTime validFrom,
    required DateTime validTo,
    CoverageType? coverageType,
    int? sumInsuredMinor,
    String? memberId,
    String? planName,
    String? notes,
  }) async {
    policy.require(NodexPermissions.insuranceManage);
    if (!insurancePolicy.isEditable) {
      throw const AuthorizationError(
        message: 'A cancelled policy cannot be changed.',
        code: 'insurance_policy_not_editable',
      );
    }
    await _repository.updatePolicy(
      insurancePolicy.id,
      policyChanges(
        policyNo: policyNo,
        validFrom: validFrom,
        validTo: validTo,
        coverageType: coverageType,
        sumInsuredMinor: sumInsuredMinor,
        memberId: memberId,
        planName: planName,
        notes: notes,
      ),
    );
  }
}

/// Records that the cover was checked with the payer.
final class VerifyPolicyUseCase {
  /// Creates the use case.
  VerifyPolicyUseCase({required this._repository});

  final InsuranceRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required InsurancePolicy insurancePolicy,
    required String verifiedBy,
    String? reference,
  }) async {
    policy.require(NodexPermissions.insuranceVerify);
    if (!insurancePolicy.isEditable) {
      throw const AuthorizationError(
        message: 'A cancelled policy cannot be verified.',
        code: 'insurance_policy_not_editable',
      );
    }
    await _repository.updatePolicy(
      insurancePolicy.id,
      policyVerifyChanges(verifiedBy: verifiedBy, reference: reference),
    );
  }
}

/// Cancels a policy. Cancellation is one-way and freezes the row.
final class CancelPolicyUseCase {
  /// Creates the use case.
  CancelPolicyUseCase({required this._repository});

  final InsuranceRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required InsurancePolicy insurancePolicy,
    required String reason,
  }) async {
    policy.require(NodexPermissions.insuranceManage);
    if (!insurancePolicy.isEditable) {
      throw const AuthorizationError(
        message: 'This policy is already cancelled and cannot be changed.',
        code: 'insurance_policy_already_cancelled',
      );
    }
    await _repository.updatePolicy(
      insurancePolicy.id,
      policyCancelChanges(reason: reason),
    );
  }
}

/// Raises a cashless pre-authorisation request.
///
/// The cover need not have been verified first: an emergency pre-authorisation
/// is raised on the cover the patient presents, and the board marks the policy
/// unverified until the desk confirms it. A cancelled policy, however, is
/// refused — there is no cover to authorise against.
final class RaisePreAuthorisationUseCase {
  /// Creates the use case.
  RaisePreAuthorisationUseCase({required this._repository});

  final InsuranceRepository _repository;

  Future<String> call({
    required AuthorizationPolicy policy,
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
  }) async {
    policy.require(NodexPermissions.insuranceVerify);
    final InsurancePolicy? cover = await _repository.policyById(policyId);
    if (cover == null) {
      throw const ValidationError(
        message: 'Pre-authorisation request failed validation.',
        fieldErrors: <String, String>{
          'policy_id': 'That policy does not exist.',
        },
        code: 'insurance_policy_missing',
      );
    }
    if (!cover.isEditable) {
      throw const ValidationError(
        message: 'Pre-authorisation request failed validation.',
        fieldErrors: <String, String>{
          'policy_id': 'That policy is cancelled and authorises nothing.',
        },
        code: 'insurance_policy_cancelled',
      );
    }
    return _repository.registerPreAuthorisation(
      PreAuthorisationRequest.registerRow(
        tenantId: tenantId,
        policyId: policyId,
        patientId: patientId,
        facilityId: facilityId,
        requestedBy: requestedBy,
        diagnosis: diagnosis,
        procedureText: procedureText,
        estimatedCostMinor: estimatedCostMinor,
        currency: currency,
        encounterId: encounterId,
        requestedAt: requestedAt,
        preAuthId: preAuthId,
      ),
    );
  }
}

/// Moves a pre-authorisation request through its stages, or records the payer's
/// answer.
final class AdvancePreAuthorisationUseCase {
  /// Creates the use case.
  AdvancePreAuthorisationUseCase({required this._repository});

  final InsuranceRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required PreAuthorisationRequest request,
    required PreAuthStatus to,
    int? approvedAmountMinor,
    String? payerReference,
    DateTime? validUntil,
    String? decisionNotes,
    String? cancellationReason,
  }) async {
    policy.require(NodexPermissions.insuranceVerify);
    if (!preAuthCanTransition(request.status, to)) {
      throw ValidationError(
        message: 'Pre-authorisation request failed validation.',
        fieldErrors: <String, String>{
          'status':
              'A request at ${request.status.label.toLowerCase()} '
              'cannot become ${to.label.toLowerCase()}.',
        },
        code: 'pre_authorisation_transition_invalid',
      );
    }
    if (to == PreAuthStatus.submitted) {
      await _repository.updatePreAuthorisation(
        request.id,
        preAuthSubmitChanges(payerReference: payerReference),
      );
      return;
    }
    if (to == PreAuthStatus.cancelled) {
      await _repository.updatePreAuthorisation(
        request.id,
        preAuthCancelChanges(reason: cancellationReason ?? ''),
      );
      return;
    }
    await _repository.updatePreAuthorisation(
      request.id,
      preAuthAnswerChanges(
        decision: to,
        estimatedCostMinor: request.estimatedCostMinor,
        approvedAmountMinor: approvedAmountMinor,
        payerReference: payerReference,
        validUntil: validUntil,
        decisionNotes: decisionNotes,
      ),
    );
  }
}

/// Creates an electronic claim.
final class CreateClaimUseCase {
  /// Creates the use case.
  CreateClaimUseCase({required this._repository});

  final InsuranceRepository _repository;

  Future<String> call({
    required AuthorizationPolicy policy,
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
  }) async {
    policy.require(NodexPermissions.insuranceClaim);
    final InsurancePolicy? cover = await _repository.policyById(policyId);
    if (cover == null) {
      throw const ValidationError(
        message: 'Insurance claim failed validation.',
        fieldErrors: <String, String>{
          'policy_id': 'That policy does not exist.',
        },
        code: 'insurance_policy_missing',
      );
    }
    final List<InsuranceClaim> existing = await _repository.listClaims(
      tenantId,
    );
    for (final InsuranceClaim other in existing) {
      if (other.claimNo == claimNo.trim() && other.id != claimId) {
        throw const ValidationError(
          message: 'Insurance claim failed validation.',
          fieldErrors: <String, String>{
            'claim_no': 'That claim number is already used.',
          },
          code: 'insurance_claim_duplicate',
        );
      }
    }
    return _repository.registerClaim(
      InsuranceClaim.registerRow(
        tenantId: tenantId,
        policyId: policyId,
        patientId: patientId,
        facilityId: facilityId,
        createdBy: createdBy,
        claimNo: claimNo,
        claimedAmountMinor: claimedAmountMinor,
        currency: currency,
        preAuthorisationId: preAuthorisationId,
        invoiceId: invoiceId,
        notes: notes,
        claimId: claimId,
      ),
    );
  }
}

/// Moves a claim through its stages, records the payer's decision, or records
/// the settlement.
final class AdvanceClaimUseCase {
  /// Creates the use case.
  AdvanceClaimUseCase({required this._repository});

  final InsuranceRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required InsuranceClaim claim,
    required ClaimStatus to,
    int? approvedAmountMinor,
    int? settledAmountMinor,
    String? payerReference,
    String? rejectionReason,
    String? notes,
    String? cancellationReason,
  }) async {
    policy.require(NodexPermissions.insuranceClaim);
    if (!claimCanTransition(claim.status, to)) {
      throw ValidationError(
        message: 'Insurance claim failed validation.',
        fieldErrors: <String, String>{
          'status':
              'A claim at ${claim.status.label.toLowerCase()} cannot '
              'become ${to.label.toLowerCase()}.',
        },
        code: 'insurance_claim_transition_invalid',
      );
    }
    if (to == ClaimStatus.submitted) {
      await _repository.updateClaim(
        claim.id,
        claimSubmitChanges(payerReference: payerReference),
      );
      return;
    }
    if (to == ClaimStatus.underReview) {
      await _repository.updateClaim(claim.id, claimReviewChanges());
      return;
    }
    if (to == ClaimStatus.cancelled) {
      await _repository.updateClaim(
        claim.id,
        claimCancelChanges(reason: cancellationReason ?? ''),
      );
      return;
    }
    if (to == ClaimStatus.settled) {
      await _repository.updateClaim(
        claim.id,
        claimSettleChanges(
          settledAmountMinor:
              settledAmountMinor ?? claim.approvedAmountMinor ?? 0,
          approvedAmountMinor: claim.approvedAmountMinor,
          payerReference: payerReference,
          notes: notes,
        ),
      );
      return;
    }
    await _repository.updateClaim(
      claim.id,
      claimDecisionChanges(
        decision: to,
        claimedAmountMinor: claim.claimedAmountMinor,
        approvedAmountMinor: approvedAmountMinor,
        payerReference: payerReference,
        rejectionReason: rejectionReason,
        notes: notes,
      ),
    );
  }
}

/// A policy as the insurance board shows it: where the cover stands, what is
/// still waiting on the payer, and what is still to be recovered.
@immutable
final class PolicyBoardEntry {
  /// Creates a board row.
  const PolicyBoardEntry({
    required this.policy,
    required this.coverState,
    required this.openPreAuthorisationCount,
    required this.openClaimCount,
    required this.recoveryGapMinor,
  });

  /// The cover.
  final InsurancePolicy policy;

  /// Where the cover stands against its validity window.
  final PolicyCoverState coverState;

  /// Requests the payer has still to answer.
  final int openPreAuthorisationCount;

  /// Claims the payer has still to decide or pay.
  final int openClaimCount;

  /// Claimed but not yet settled, in minor units, over the claims that are
  /// neither refused nor withdrawn.
  final int recoveryGapMinor;

  /// Whether the cover needs an attention marker.
  bool get needsAttention => coverState.needsAttention || !policy.isVerified;
}

/// Reads the insurance board, registry, requests and claims.
final class ReadInsuranceUseCase {
  /// Creates the use case.
  ReadInsuranceUseCase({required this._repository});

  final InsuranceRepository _repository;

  /// The payer registry, by code.
  Future<List<InsurancePayer>> payers({
    required AuthorizationPolicy policy,
    required String tenantId,
    bool includeInactive = false,
  }) async {
    policy.require(NodexPermissions.insuranceRead);
    final List<InsurancePayer> payers = await _repository.listPayers(tenantId);
    return payers
        .where((InsurancePayer payer) => includeInactive || payer.isActive)
        .toList(growable: false);
  }

  /// Policies, newest validity first.
  Future<List<InsurancePolicy>> policies({
    required AuthorizationPolicy policy,
    required String tenantId,
    String? patientId,
    String? payerId,
  }) async {
    policy.require(NodexPermissions.insuranceRead);
    return _repository.listPolicies(
      tenantId,
      patientId: patientId,
      payerId: payerId,
    );
  }

  /// Pre-authorisation requests, newest first.
  Future<List<PreAuthorisationRequest>> preAuthorisations({
    required AuthorizationPolicy policy,
    required String tenantId,
    String? policyId,
    String? patientId,
    bool includeClosed = true,
  }) async {
    policy.require(NodexPermissions.insuranceRead);
    final List<PreAuthorisationRequest> requests = await _repository
        .listPreAuthorisations(
          tenantId,
          policyId: policyId,
          patientId: patientId,
        );
    return requests
        .where(
          (PreAuthorisationRequest request) => includeClosed || request.isLive,
        )
        .toList(growable: false);
  }

  /// Claims, newest first.
  Future<List<InsuranceClaim>> claims({
    required AuthorizationPolicy policy,
    required String tenantId,
    String? policyId,
    String? patientId,
    ClaimStatus? status,
    bool includeClosed = true,
  }) async {
    policy.require(NodexPermissions.insuranceRead);
    final List<InsuranceClaim> claims = await _repository.listClaims(
      tenantId,
      policyId: policyId,
      patientId: patientId,
      status: status?.wireValue,
    );
    return claims
        .where((InsuranceClaim claim) => includeClosed || claim.isOpen)
        .toList(growable: false);
  }

  /// The insurance board: every policy with its derived cover state, what is
  /// waiting on the payer and what is still to be recovered, most needing
  /// attention first.
  Future<List<PolicyBoardEntry>> board({
    required AuthorizationPolicy policy,
    required String tenantId,
    DateTime? now,
  }) async {
    policy.require(NodexPermissions.insuranceRead);
    final DateTime asOf = (now ?? DateTime.now().toUtc()).toUtc();
    final List<InsurancePolicy> policies = await _repository.listPolicies(
      tenantId,
    );
    final List<PreAuthorisationRequest> requests = await _repository
        .listPreAuthorisations(tenantId);
    final List<InsuranceClaim> claims = await _repository.listClaims(tenantId);

    final Map<String, int> openPreAuths = <String, int>{};
    for (final PreAuthorisationRequest request in requests) {
      if (request.isLive) {
        openPreAuths.update(
          request.policyId,
          (int value) => value + 1,
          ifAbsent: () => 1,
        );
      }
    }
    final Map<String, int> openClaims = <String, int>{};
    final Map<String, int> gapByPolicy = <String, int>{};
    for (final InsuranceClaim claim in claims) {
      if (claim.isOpen) {
        openClaims.update(
          claim.policyId,
          (int value) => value + 1,
          ifAbsent: () => 1,
        );
      }
      if (claim.status != ClaimStatus.cancelled &&
          claim.status != ClaimStatus.rejected) {
        gapByPolicy.update(
          claim.policyId,
          (int value) => value + claim.recoveryGapMinor,
          ifAbsent: () => claim.recoveryGapMinor,
        );
      }
    }

    final List<PolicyBoardEntry> board = <PolicyBoardEntry>[
      for (final InsurancePolicy cover in policies)
        PolicyBoardEntry(
          policy: cover,
          coverState: policyCoverState(
            validTo: cover.validTo,
            now: asOf,
            cancelled: cover.status == PolicyStatus.cancelled,
          ),
          openPreAuthorisationCount: openPreAuths[cover.id] ?? 0,
          openClaimCount: openClaims[cover.id] ?? 0,
          recoveryGapMinor: gapByPolicy[cover.id] ?? 0,
        ),
    ];
    board.sort((PolicyBoardEntry a, PolicyBoardEntry b) {
      final int rank = _coverRank(a.coverState) - _coverRank(b.coverState);
      if (rank != 0) {
        return rank;
      }
      return a.policy.policyNo.compareTo(b.policy.policyNo);
    });
    return board;
  }

  static int _coverRank(PolicyCoverState state) => switch (state) {
    PolicyCoverState.expired => 0,
    PolicyCoverState.expiringSoon => 1,
    PolicyCoverState.active => 2,
    PolicyCoverState.cancelled => 3,
  };
}
