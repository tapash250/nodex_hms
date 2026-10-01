/// Discharge management entities (Module 23).
///
/// Extends the discharge record with the artifacts the specification requires
/// before a patient may leave: clinical clearance, medication reconciliation,
/// billing settlement and a reviewed AI summary. Clearance freezes once
/// granted, a completed reconciliation is the authorized account of the
/// medication review, and a reviewed AI summary never rewrites itself.
// ignore_for_file: sort_constructors_first
library;

import 'package:meta/meta.dart';

/// Lifecycle of a clinical clearance.
enum DischargeClearanceStatus {
  pending('pending'),
  cleared('cleared');

  const DischargeClearanceStatus(this.wireValue);

  final String wireValue;

  String get label => switch (this) {
    DischargeClearanceStatus.pending => 'Pending',
    DischargeClearanceStatus.cleared => 'Cleared',
  };

  bool get isCleared => this == cleared;

  bool get isPending => this == pending;

  static DischargeClearanceStatus fromWire(String value) =>
      DischargeClearanceStatus.values.firstWhere(
        (DischargeClearanceStatus status) => status.wireValue == value,
        orElse: () => DischargeClearanceStatus.pending,
      );
}

/// Lifecycle of a medication reconciliation.
enum DischargeReconciliationStatus {
  pending('pending'),
  reconciled('reconciled');

  const DischargeReconciliationStatus(this.wireValue);

  final String wireValue;

  String get label => switch (this) {
    DischargeReconciliationStatus.pending => 'Pending',
    DischargeReconciliationStatus.reconciled => 'Reconciled',
  };

  bool get isReconciled => this == reconciled;

  bool get isPending => this == pending;

  static DischargeReconciliationStatus fromWire(String value) =>
      DischargeReconciliationStatus.values.firstWhere(
        (DischargeReconciliationStatus status) => status.wireValue == value,
        orElse: () => DischargeReconciliationStatus.pending,
      );
}

/// Decision taken for one medication at discharge.
enum DischargeMedicationAction {
  continueMedication('continue'),
  stop('stop'),
  change('change'),
  hold('hold');

  const DischargeMedicationAction(this.wireValue);

  final String wireValue;

  String get label => switch (this) {
    DischargeMedicationAction.continueMedication => 'Continue',
    DischargeMedicationAction.stop => 'Stop',
    DischargeMedicationAction.change => 'Change',
    DischargeMedicationAction.hold => 'Hold',
  };

  /// Whether the decision is a divergence from the prescribed regimen.
  bool get isDiscrepancy => this != continueMedication;

  static DischargeMedicationAction fromWire(String value) =>
      DischargeMedicationAction.values.firstWhere(
        (DischargeMedicationAction action) => action.wireValue == value,
        orElse: () => DischargeMedicationAction.continueMedication,
      );
}

/// Review state of an AI-generated discharge summary.
enum DischargeAiSummaryStatus {
  pendingReview('pending_review'),
  accepted('accepted'),
  rejected('rejected');

  const DischargeAiSummaryStatus(this.wireValue);

  final String wireValue;

  String get label => switch (this) {
    DischargeAiSummaryStatus.pendingReview => 'Pending review',
    DischargeAiSummaryStatus.accepted => 'Accepted',
    DischargeAiSummaryStatus.rejected => 'Rejected',
  };

  bool get isPendingReview => this == pendingReview;

  bool get isAccepted => this == accepted;

  bool get isReviewed => this != pendingReview;

  static DischargeAiSummaryStatus fromWire(String value) =>
      DischargeAiSummaryStatus.values.firstWhere(
        (DischargeAiSummaryStatus status) => status.wireValue == value,
        orElse: () => DischargeAiSummaryStatus.pendingReview,
      );
}

/// Clinical sign-off that a patient is fit to leave.
@immutable
final class DischargeClearance {
  const DischargeClearance({
    required this.id,
    required this.tenantId,
    required this.dischargeId,
    required this.reviewedBy,
    required this.status,
    required this.outstandingItems,
    required this.createdAt,
    required this.updatedAt,
    this.notes,
    this.clearedBy,
    this.clearedAt,
  });

  factory DischargeClearance.fromRow(Map<String, Object?> row) {
    final Object? notes = row['notes'];
    final Object? clearedBy = row['cleared_by'];
    final Object? clearedAt = row['cleared_at'];
    return DischargeClearance(
      id: row['id']! as String,
      tenantId: row['tenant_id']! as String,
      dischargeId: row['discharge_id']! as String,
      reviewedBy: row['reviewed_by']! as String,
      status: DischargeClearanceStatus.fromWire(row['status']! as String),
      outstandingItems: (row['outstanding_items']! as num).toInt(),
      notes: notes is String ? notes : null,
      clearedBy: clearedBy is String ? clearedBy : null,
      clearedAt: clearedAt is DateTime ? clearedAt : null,
      createdAt: row['created_at']! as DateTime,
      updatedAt: row['updated_at']! as DateTime,
    );
  }

  final String id;
  final String tenantId;
  final String dischargeId;
  final String reviewedBy;
  final DischargeClearanceStatus status;
  final int outstandingItems;
  final String? notes;
  final String? clearedBy;
  final DateTime? clearedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isCleared => status.isCleared;

  bool get hasOutstandingItems => outstandingItems > 0;
}

/// The medication review performed before discharge.
@immutable
final class DischargeMedicationReconciliation {
  const DischargeMedicationReconciliation({
    required this.id,
    required this.tenantId,
    required this.dischargeId,
    required this.status,
    required this.medicationsReviewed,
    required this.discrepanciesFound,
    required this.createdAt,
    required this.updatedAt,
    this.reviewedBy,
    this.reviewedAt,
    this.notes,
  });

  factory DischargeMedicationReconciliation.fromRow(Map<String, Object?> row) {
    final Object? reviewedBy = row['reviewed_by'];
    final Object? reviewedAt = row['reviewed_at'];
    final Object? notes = row['notes'];
    return DischargeMedicationReconciliation(
      id: row['id']! as String,
      tenantId: row['tenant_id']! as String,
      dischargeId: row['discharge_id']! as String,
      status: DischargeReconciliationStatus.fromWire(row['status']! as String),
      medicationsReviewed: (row['medications_reviewed']! as num).toInt(),
      discrepanciesFound: (row['discrepancies_found']! as num).toInt(),
      reviewedBy: reviewedBy is String ? reviewedBy : null,
      reviewedAt: reviewedAt is DateTime ? reviewedAt : null,
      notes: notes is String ? notes : null,
      createdAt: row['created_at']! as DateTime,
      updatedAt: row['updated_at']! as DateTime,
    );
  }

  final String id;
  final String tenantId;
  final String dischargeId;
  final DischargeReconciliationStatus status;
  final int medicationsReviewed;
  final int discrepanciesFound;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isReconciled => status.isReconciled;
}

/// One medication decision recorded during reconciliation.
@immutable
final class DischargeMedicationReconciliationItem {
  const DischargeMedicationReconciliationItem({
    required this.id,
    required this.tenantId,
    required this.reconciliationId,
    required this.medicationName,
    required this.action,
    required this.discrepancy,
    required this.recordedBy,
    required this.recordedAt,
    required this.createdAt,
    required this.updatedAt,
    this.detail,
  });

  factory DischargeMedicationReconciliationItem.fromRow(
    Map<String, Object?> row,
  ) {
    final Object? detail = row['detail'];
    final Object? discrepancy = row['discrepancy'];
    return DischargeMedicationReconciliationItem(
      id: row['id']! as String,
      tenantId: row['tenant_id']! as String,
      reconciliationId: row['reconciliation_id']! as String,
      medicationName: row['medication_name']! as String,
      action: DischargeMedicationAction.fromWire(row['action']! as String),
      discrepancy: discrepancy == 1 || discrepancy == true,
      detail: detail is String ? detail : null,
      recordedBy: row['recorded_by']! as String,
      recordedAt: row['recorded_at']! as DateTime,
      createdAt: row['created_at']! as DateTime,
      updatedAt: row['updated_at']! as DateTime,
    );
  }

  final String id;
  final String tenantId;
  final String reconciliationId;
  final String medicationName;
  final DischargeMedicationAction action;
  final bool discrepancy;
  final String? detail;
  final String recordedBy;
  final DateTime recordedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
}

/// Record that the episode invoice was settled before discharge.
@immutable
final class DischargeSettlement {
  const DischargeSettlement({
    required this.id,
    required this.tenantId,
    required this.dischargeId,
    required this.invoiceId,
    required this.amountMinor,
    required this.settledBy,
    required this.settledAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DischargeSettlement.fromRow(Map<String, Object?> row) =>
      DischargeSettlement(
        id: row['id']! as String,
        tenantId: row['tenant_id']! as String,
        dischargeId: row['discharge_id']! as String,
        invoiceId: row['invoice_id']! as String,
        amountMinor: (row['amount_minor']! as num).toInt(),
        settledBy: row['settled_by']! as String,
        settledAt: row['settled_at']! as DateTime,
        createdAt: row['created_at']! as DateTime,
        updatedAt: row['updated_at']! as DateTime,
      );

  final String id;
  final String tenantId;
  final String dischargeId;
  final String invoiceId;
  final int amountMinor;
  final String settledBy;
  final DateTime settledAt;
  final DateTime createdAt;
  final DateTime updatedAt;
}

/// An AI-generated discharge summary awaiting human review.
@immutable
final class DischargeAiSummary {
  const DischargeAiSummary({
    required this.id,
    required this.tenantId,
    required this.dischargeId,
    required this.modelId,
    required this.summaryText,
    required this.status,
    required this.safetyDecision,
    required this.requestedBy,
    required this.createdAt,
    required this.updatedAt,
    this.reviewedBy,
    this.reviewedAt,
    this.rejectionReason,
  });

  factory DischargeAiSummary.fromRow(Map<String, Object?> row) {
    final Object? reviewedBy = row['reviewed_by'];
    final Object? reviewedAt = row['reviewed_at'];
    final Object? rejectionReason = row['rejection_reason'];
    return DischargeAiSummary(
      id: row['id']! as String,
      tenantId: row['tenant_id']! as String,
      dischargeId: row['discharge_id']! as String,
      modelId: row['model_id']! as String,
      summaryText: row['summary_text']! as String,
      status: DischargeAiSummaryStatus.fromWire(row['status']! as String),
      safetyDecision: row['safety_decision']! as String,
      requestedBy: row['requested_by']! as String,
      reviewedBy: reviewedBy is String ? reviewedBy : null,
      reviewedAt: reviewedAt is DateTime ? reviewedAt : null,
      rejectionReason: rejectionReason is String ? rejectionReason : null,
      createdAt: row['created_at']! as DateTime,
      updatedAt: row['updated_at']! as DateTime,
    );
  }

  final String id;
  final String tenantId;
  final String dischargeId;
  final String modelId;
  final String summaryText;
  final DischargeAiSummaryStatus status;
  final String safetyDecision;
  final String requestedBy;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final String? rejectionReason;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isPendingReview => status.isPendingReview;

  bool get isAccepted => status.isAccepted;
}

/// What still stands between a draft discharge and its authorization.
///
/// Surfaced so the ward can see exactly which artifact is missing instead of
/// discovering it as a failed authorization.
@immutable
final class DischargeReadiness {
  /// Creates a readiness snapshot.
  const DischargeReadiness({
    required this.cleared,
    required this.reconciled,
    required this.settled,
    required this.outstandingClearanceItems,
    required this.pendingMedications,
    this.aiSummaryReviewed = false,
  });

  /// Whether clinical clearance has been granted.
  final bool cleared;

  /// Whether medication reconciliation has completed.
  final bool reconciled;

  /// Whether the episode invoice has been settled.
  final bool settled;

  /// Outstanding clinical items reported by the reviewing clinician.
  final int outstandingClearanceItems;

  /// Medications recorded but not yet signed off.
  final int pendingMedications;

  /// Whether a generated summary has been reviewed, when one exists.
  final bool aiSummaryReviewed;

  /// Whether the discharge may be authorized.
  ///
  /// An AI summary is deliberately not required: it is documentation, whereas
  /// clearance, reconciliation and settlement are what make leaving safe.
  bool get canFinalize => cleared && reconciled && settled;
}
