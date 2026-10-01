/// Discharge management use cases (Module 23).
///
/// The chain a patient passes through before leaving: clinical clearance,
/// medication reconciliation, billing settlement and — optionally — a reviewed
/// AI summary. Each step gates on the authorization policy first, and each
/// refuses to proceed while the previous step is unfinished.
library;

import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/discharge/discharge.dart';
import 'package:nodex_hms/domain/discharge/discharge_management.dart';
import 'package:nodex_hms/domain/discharge/discharge_management_repository.dart';
import 'package:uuid/uuid.dart';

/// Records the clinical review that decides whether a patient may leave.
///
/// Requires `discharge_clearance.write`. Starting or restating the review is
/// allowed only while the discharge is still a draft; a granted clearance is
/// never withdrawn.
final class RecordDischargeClearanceUseCase {
  /// Creates the use case.
  RecordDischargeClearanceUseCase({required this._repository});

  final DischargeManagementRepository _repository;

  /// Records or updates the pending clinical review.
  Future<DischargeClearance> call({
    required AuthorizationPolicy policy,
    required Discharge discharge,
    required String reviewedBy,
    required int outstandingItems,
    String? notes,
  }) async {
    policy.require(NodexPermissions.dischargeClearanceWrite);
    _requireDraft(discharge);
    if (outstandingItems < 0) {
      throw const ValidationError(
        message: 'Outstanding items cannot be negative.',
        fieldErrors: <String, String>{
          'outstanding_items': 'Expected zero or more.',
        },
        code: 'discharge_clearance_invalid',
      );
    }
    final DischargeClearance? existing = await _repository
        .clearanceForDischarge(discharge.id);
    if (existing != null && existing.isCleared) {
      throw const AuthorizationError(
        message: 'Granted clearance cannot be restated.',
        code: 'discharge_clearance_closed',
      );
    }
    final DateTime now = DateTime.now().toUtc();
    final String? cleanNotes = notes?.trim();
    return _repository.upsertClearance(
      DischargeClearance(
        id: existing?.id ?? const Uuid().v4(),
        tenantId: discharge.tenantId,
        dischargeId: discharge.id,
        reviewedBy: reviewedBy,
        status: DischargeClearanceStatus.pending,
        outstandingItems: outstandingItems,
        notes: cleanNotes == null || cleanNotes.isEmpty ? null : cleanNotes,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
      ),
    );
  }
}

/// Grants clinical clearance. Requires `discharge_clearance.write`.
///
/// Refuses while any clinical item is still outstanding: clearance means the
/// patient is fit to leave, not that the review has started.
final class GrantDischargeClearanceUseCase {
  /// Creates the use case.
  GrantDischargeClearanceUseCase({required this._repository});

  final DischargeManagementRepository _repository;

  /// Grants clearance on a pending review with nothing outstanding.
  Future<DischargeClearance> call({
    required AuthorizationPolicy policy,
    required Discharge discharge,
    required String clearedBy,
  }) async {
    policy.require(NodexPermissions.dischargeClearanceWrite);
    _requireDraft(discharge);
    final DischargeClearance? clearance = await _repository
        .clearanceForDischarge(discharge.id);
    if (clearance == null) {
      throw const AuthorizationError(
        message: 'Record the clinical review before granting clearance.',
        code: 'discharge_clearance_missing',
      );
    }
    if (clearance.isCleared) {
      throw const AuthorizationError(
        message: 'This discharge is already cleared.',
        code: 'discharge_clearance_closed',
      );
    }
    if (clearance.hasOutstandingItems) {
      throw const AuthorizationError(
        message: 'Outstanding clinical items must be resolved first.',
        code: 'discharge_clearance_outstanding',
      );
    }
    final DateTime now = DateTime.now().toUtc();
    return _repository.upsertClearance(
      DischargeClearance(
        id: clearance.id,
        tenantId: clearance.tenantId,
        dischargeId: clearance.dischargeId,
        reviewedBy: clearance.reviewedBy,
        status: DischargeClearanceStatus.cleared,
        outstandingItems: 0,
        notes: clearance.notes,
        clearedBy: clearedBy,
        clearedAt: now,
        createdAt: clearance.createdAt,
        updatedAt: now,
      ),
    );
  }
}

/// Opens the medication review for a discharge. Requires
/// `discharge_reconciliation.write`.
final class StartDischargeReconciliationUseCase {
  /// Creates the use case.
  StartDischargeReconciliationUseCase({required this._repository});

  final DischargeManagementRepository _repository;

  /// Starts a reconciliation, refusing a second one for the same discharge.
  Future<DischargeMedicationReconciliation> call({
    required AuthorizationPolicy policy,
    required Discharge discharge,
  }) async {
    policy.require(NodexPermissions.dischargeReconciliationWrite);
    _requireDraft(discharge);
    final DischargeMedicationReconciliation? existing = await _repository
        .reconciliationForDischarge(discharge.id);
    if (existing != null) {
      throw const AuthorizationError(
        message: 'This discharge already has a medication reconciliation.',
        code: 'discharge_reconciliation_exists',
      );
    }
    final DateTime now = DateTime.now().toUtc();
    return _repository.upsertReconciliation(
      DischargeMedicationReconciliation(
        id: const Uuid().v4(),
        tenantId: discharge.tenantId,
        dischargeId: discharge.id,
        status: DischargeReconciliationStatus.pending,
        medicationsReviewed: 0,
        discrepanciesFound: 0,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }
}

/// Records one medication decision. Requires `discharge_reconciliation.write`.
final class RecordDischargeMedicationUseCase {
  /// Creates the use case.
  RecordDischargeMedicationUseCase({required this._repository});

  final DischargeManagementRepository _repository;

  /// Records a decision against a pending reconciliation.
  Future<DischargeMedicationReconciliationItem> call({
    required AuthorizationPolicy policy,
    required Discharge discharge,
    required String medicationName,
    required DischargeMedicationAction action,
    required String recordedBy,
    String? detail,
  }) async {
    policy.require(NodexPermissions.dischargeReconciliationWrite);
    _requireDraft(discharge);
    if (medicationName.trim().isEmpty) {
      throw const ValidationError(
        message: 'A medication decision needs the medication name.',
        fieldErrors: <String, String>{'medication_name': 'Enter the name.'},
        code: 'discharge_medication_invalid',
      );
    }
    final DischargeMedicationReconciliation? reconciliation = await _repository
        .reconciliationForDischarge(discharge.id);
    if (reconciliation == null) {
      throw const AuthorizationError(
        message: 'Start the medication reconciliation first.',
        code: 'discharge_reconciliation_missing',
      );
    }
    if (reconciliation.isReconciled) {
      throw const AuthorizationError(
        message: 'A completed reconciliation cannot take more decisions.',
        code: 'discharge_reconciliation_closed',
      );
    }
    final DateTime now = DateTime.now().toUtc();
    final String? cleanDetail = detail?.trim();
    return _repository.upsertReconciliationItem(
      DischargeMedicationReconciliationItem(
        id: const Uuid().v4(),
        tenantId: discharge.tenantId,
        reconciliationId: reconciliation.id,
        medicationName: medicationName.trim(),
        action: action,
        // A decision is a discrepancy unless the medication simply continues.
        discrepancy: action.isDiscrepancy,
        detail: cleanDetail == null || cleanDetail.isEmpty ? null : cleanDetail,
        recordedBy: recordedBy,
        recordedAt: now,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }
}

/// Signs off the medication review. Requires `discharge_reconciliation.write`.
///
/// At least one medication must have been reviewed: a reconciliation that
/// reviewed nothing is not a reconciliation.
final class CompleteDischargeReconciliationUseCase {
  /// Creates the use case.
  CompleteDischargeReconciliationUseCase({required this._repository});

  final DischargeManagementRepository _repository;

  /// Completes the reconciliation and records the reviewed counts.
  Future<DischargeMedicationReconciliation> call({
    required AuthorizationPolicy policy,
    required Discharge discharge,
    required String reviewedBy,
    String? notes,
  }) async {
    policy.require(NodexPermissions.dischargeReconciliationWrite);
    _requireDraft(discharge);
    final DischargeMedicationReconciliation? reconciliation = await _repository
        .reconciliationForDischarge(discharge.id);
    if (reconciliation == null) {
      throw const AuthorizationError(
        message: 'Start the medication reconciliation first.',
        code: 'discharge_reconciliation_missing',
      );
    }
    if (reconciliation.isReconciled) {
      throw const AuthorizationError(
        message: 'This reconciliation is already complete.',
        code: 'discharge_reconciliation_closed',
      );
    }
    final List<DischargeMedicationReconciliationItem> items = await _repository
        .itemsForReconciliation(reconciliation.id);
    if (items.isEmpty) {
      throw const AuthorizationError(
        message: 'Review at least one medication before completing.',
        code: 'discharge_reconciliation_empty',
      );
    }
    final int discrepancies = items
        .where((DischargeMedicationReconciliationItem item) => item.discrepancy)
        .length;
    final DateTime now = DateTime.now().toUtc();
    final String? cleanNotes = notes?.trim();
    return _repository.upsertReconciliation(
      DischargeMedicationReconciliation(
        id: reconciliation.id,
        tenantId: reconciliation.tenantId,
        dischargeId: reconciliation.dischargeId,
        status: DischargeReconciliationStatus.reconciled,
        medicationsReviewed: items.length,
        discrepanciesFound: discrepancies,
        reviewedBy: reviewedBy,
        reviewedAt: now,
        notes: cleanNotes == null || cleanNotes.isEmpty
            ? reconciliation.notes
            : cleanNotes,
        createdAt: reconciliation.createdAt,
        updatedAt: now,
      ),
    );
  }
}

/// Records that the episode invoice was settled. Requires `billing.settle`.
///
/// Settlement is a financial action, so it deliberately rides on the billing
/// authority rather than a discharge-specific permission, and it requires the
/// medication review to be complete first.
final class SettleDischargeBillingUseCase {
  /// Creates the use case.
  SettleDischargeBillingUseCase({required this._repository});

  final DischargeManagementRepository _repository;

  /// Records the settlement against the discharge.
  Future<DischargeSettlement> call({
    required AuthorizationPolicy policy,
    required Discharge discharge,
    required String invoiceId,
    required int amountMinor,
    required String settledBy,
  }) async {
    policy.require(NodexPermissions.billingSettle);
    _requireDraft(discharge);
    if (invoiceId.trim().isEmpty) {
      throw const ValidationError(
        message: 'Settling a discharge needs the episode invoice.',
        fieldErrors: <String, String>{'invoice_id': 'Enter the invoice.'},
        code: 'discharge_settlement_invalid',
      );
    }
    if (amountMinor < 0) {
      throw const ValidationError(
        message: 'A settled amount cannot be negative.',
        fieldErrors: <String, String>{'amount_minor': 'Expected zero or more.'},
        code: 'discharge_settlement_invalid',
      );
    }
    final DischargeMedicationReconciliation? reconciliation = await _repository
        .reconciliationForDischarge(discharge.id);
    if (reconciliation == null || !reconciliation.isReconciled) {
      throw const AuthorizationError(
        message: 'Complete medication reconciliation before settling.',
        code: 'discharge_reconciliation_required',
      );
    }
    final DischargeSettlement? existing = await _repository
        .settlementForDischarge(discharge.id);
    if (existing != null) {
      throw const AuthorizationError(
        message: 'This discharge is already settled.',
        code: 'discharge_settlement_exists',
      );
    }
    final DateTime now = DateTime.now().toUtc();
    return _repository.upsertSettlement(
      DischargeSettlement(
        id: const Uuid().v4(),
        tenantId: discharge.tenantId,
        dischargeId: discharge.id,
        invoiceId: invoiceId.trim(),
        amountMinor: amountMinor,
        settledBy: settledBy,
        settledAt: now,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }
}

/// Files an AI-generated discharge summary for review. Requires
/// `discharge_clearance.write`.
///
/// The summary is machine output, so it arrives as `pending_review` and carries
/// the model's safety decision rather than asserting clinical authority.
final class RecordDischargeAiSummaryUseCase {
  /// Creates the use case.
  RecordDischargeAiSummaryUseCase({required this._repository});

  final DischargeManagementRepository _repository;

  /// Files the generated summary against a cleared discharge.
  Future<DischargeAiSummary> call({
    required AuthorizationPolicy policy,
    required Discharge discharge,
    required String modelId,
    required String summaryText,
    required String safetyDecision,
    required String requestedBy,
  }) async {
    policy.require(NodexPermissions.dischargeClearanceWrite);
    _requireDraft(discharge);
    final Map<String, String> fieldErrors = <String, String>{};
    if (modelId.trim().isEmpty) {
      fieldErrors['model_id'] = 'The generating model is required.';
    }
    if (summaryText.trim().isEmpty) {
      fieldErrors['summary_text'] = 'The generated summary is required.';
    }
    if (safetyDecision.trim().isEmpty) {
      fieldErrors['safety_decision'] = 'The safety decision is required.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Discharge summary failed validation.',
        fieldErrors: fieldErrors,
        code: 'discharge_ai_summary_invalid',
      );
    }
    final DischargeClearance? clearance = await _repository
        .clearanceForDischarge(discharge.id);
    if (clearance == null || !clearance.isCleared) {
      throw const AuthorizationError(
        message: 'Clear the patient clinically before generating a summary.',
        code: 'discharge_clearance_required',
      );
    }
    final DischargeAiSummary? existing = await _repository
        .aiSummaryForDischarge(discharge.id);
    if (existing != null) {
      throw const AuthorizationError(
        message: 'This discharge already has a generated summary.',
        code: 'discharge_ai_summary_exists',
      );
    }
    final DateTime now = DateTime.now().toUtc();
    return _repository.upsertAiSummary(
      DischargeAiSummary(
        id: const Uuid().v4(),
        tenantId: discharge.tenantId,
        dischargeId: discharge.id,
        modelId: modelId.trim(),
        summaryText: summaryText.trim(),
        status: DischargeAiSummaryStatus.pendingReview,
        safetyDecision: safetyDecision.trim(),
        requestedBy: requestedBy,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }
}

/// Accepts a reviewed AI summary as the discharge narrative. Requires
/// `discharge_summary.review`.
final class AcceptDischargeAiSummaryUseCase {
  /// Creates the use case.
  AcceptDischargeAiSummaryUseCase({required this._repository});

  final DischargeManagementRepository _repository;

  /// Accepts a summary that is awaiting review.
  Future<DischargeAiSummary> call({
    required AuthorizationPolicy policy,
    required Discharge discharge,
    required String reviewedBy,
  }) async {
    policy.require(NodexPermissions.dischargeSummaryReview);
    _requireDraft(discharge);
    final DischargeAiSummary? summary = await _repository.aiSummaryForDischarge(
      discharge.id,
    );
    if (summary == null) {
      throw const AuthorizationError(
        message: 'This discharge has no generated summary to review.',
        code: 'discharge_ai_summary_missing',
      );
    }
    if (!summary.isPendingReview) {
      throw const AuthorizationError(
        message: 'This summary has already been reviewed.',
        code: 'discharge_ai_summary_reviewed',
      );
    }
    final DateTime now = DateTime.now().toUtc();
    return _repository.upsertAiSummary(
      _withReview(
        summary,
        status: DischargeAiSummaryStatus.accepted,
        reviewedBy: reviewedBy,
        reviewedAt: now,
      ),
    );
  }
}

/// Rejects a generated summary with a reason. Requires
/// `discharge_summary.review`.
final class RejectDischargeAiSummaryUseCase {
  /// Creates the use case.
  RejectDischargeAiSummaryUseCase({required this._repository});

  final DischargeManagementRepository _repository;

  /// Rejects a summary that is awaiting review.
  Future<DischargeAiSummary> call({
    required AuthorizationPolicy policy,
    required Discharge discharge,
    required String reviewedBy,
    required String reason,
  }) async {
    policy.require(NodexPermissions.dischargeSummaryReview);
    _requireDraft(discharge);
    if (reason.trim().isEmpty) {
      throw const ValidationError(
        message: 'Rejecting a generated summary requires a reason.',
        fieldErrors: <String, String>{'reason': 'Enter the reason.'},
        code: 'discharge_ai_summary_rejection_reason_required',
      );
    }
    final DischargeAiSummary? summary = await _repository.aiSummaryForDischarge(
      discharge.id,
    );
    if (summary == null) {
      throw const AuthorizationError(
        message: 'This discharge has no generated summary to review.',
        code: 'discharge_ai_summary_missing',
      );
    }
    if (!summary.isPendingReview) {
      throw const AuthorizationError(
        message: 'This summary has already been reviewed.',
        code: 'discharge_ai_summary_reviewed',
      );
    }
    final DateTime now = DateTime.now().toUtc();
    return _repository.upsertAiSummary(
      _withReview(
        summary,
        status: DischargeAiSummaryStatus.rejected,
        reviewedBy: reviewedBy,
        reviewedAt: now,
        rejectionReason: reason.trim(),
      ),
    );
  }
}

/// Reports what still stands between a draft discharge and its authorization.
final class CheckDischargeReadinessUseCase {
  /// Creates the use case.
  CheckDischargeReadinessUseCase({required this._repository});

  final DischargeManagementRepository _repository;

  /// Reads the readiness artifacts for [discharge].
  Future<DischargeReadiness> call(Discharge discharge) async {
    final DischargeClearance? clearance = await _repository
        .clearanceForDischarge(discharge.id);
    final DischargeMedicationReconciliation? reconciliation = await _repository
        .reconciliationForDischarge(discharge.id);
    final DischargeSettlement? settlement = await _repository
        .settlementForDischarge(discharge.id);
    final DischargeAiSummary? summary = await _repository.aiSummaryForDischarge(
      discharge.id,
    );
    final int pendingMedications =
        reconciliation == null || reconciliation.isReconciled
        ? 0
        : (await _repository.itemsForReconciliation(reconciliation.id)).length;
    return DischargeReadiness(
      cleared: clearance?.isCleared ?? false,
      reconciled: reconciliation?.isReconciled ?? false,
      settled: settlement != null,
      outstandingClearanceItems: clearance?.outstandingItems ?? 0,
      pendingMedications: pendingMedications,
      aiSummaryReviewed: summary?.isAccepted ?? false,
    );
  }
}

/// Copies a summary forward with a review decision, preserving the generated
/// text so a review never rewrites machine output.
DischargeAiSummary _withReview(
  DischargeAiSummary summary, {
  required DischargeAiSummaryStatus status,
  required String reviewedBy,
  required DateTime reviewedAt,
  String? rejectionReason,
}) => DischargeAiSummary(
  id: summary.id,
  tenantId: summary.tenantId,
  dischargeId: summary.dischargeId,
  modelId: summary.modelId,
  summaryText: summary.summaryText,
  status: status,
  safetyDecision: summary.safetyDecision,
  requestedBy: summary.requestedBy,
  reviewedBy: reviewedBy,
  reviewedAt: reviewedAt,
  rejectionReason: rejectionReason,
  createdAt: summary.createdAt,
  updatedAt: reviewedAt,
);

/// Discharge management only happens while the discharge is still a draft: a
/// finalized or cancelled episode cannot accrue readiness artifacts.
void _requireDraft(Discharge discharge) {
  if (!discharge.status.isEditable) {
    throw const AuthorizationError(
      message: 'Closed discharges cannot take discharge management actions.',
      code: 'discharge_closed',
    );
  }
}
