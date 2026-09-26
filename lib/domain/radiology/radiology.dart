/// Radiology & PACS entities (Module 18).
///
/// Case flow: order (modality, region, priority) -> study acquisition with a
/// PACS/DICOM reference -> draft report -> verified report. A verified report
/// freezes; images themselves live in encrypted object storage, and the local
/// projection only carries metadata and ownership references.
// ignore_for_file: sort_constructors_first
library;

import 'package:meta/meta.dart';

/// Imaging modality of an order or study.
enum ImagingModality {
  xray('xray'),
  ct('ct'),
  mri('mri'),
  ultrasound('ultrasound');

  const ImagingModality(this.wireValue);

  final String wireValue;

  String get label => switch (this) {
    ImagingModality.xray => 'X-ray',
    ImagingModality.ct => 'CT',
    ImagingModality.mri => 'MRI',
    ImagingModality.ultrasound => 'Ultrasound',
  };

  static ImagingModality fromWire(String value) =>
      ImagingModality.values.firstWhere(
        (ImagingModality modality) => modality.wireValue == value,
        orElse: () => ImagingModality.xray,
      );
}

/// Turnaround priority of an imaging order.
enum ImagingPriority {
  routine('routine'),
  urgent('urgent'),
  stat('stat');

  const ImagingPriority(this.wireValue);

  final String wireValue;

  String get label => switch (this) {
    ImagingPriority.routine => 'Routine',
    ImagingPriority.urgent => 'Urgent',
    ImagingPriority.stat => 'STAT',
  };

  bool get isStat => this == stat;

  static ImagingPriority fromWire(String value) =>
      ImagingPriority.values.firstWhere(
        (ImagingPriority priority) => priority.wireValue == value,
        orElse: () => ImagingPriority.routine,
      );
}

/// Lifecycle of an imaging order.
enum ImagingOrderStatus {
  ordered('ordered'),
  completed('completed'),
  cancelled('cancelled');

  const ImagingOrderStatus(this.wireValue);

  final String wireValue;

  String get label => switch (this) {
    ImagingOrderStatus.ordered => 'Ordered',
    ImagingOrderStatus.completed => 'Completed',
    ImagingOrderStatus.cancelled => 'Cancelled',
  };

  bool get isTerminal => this == completed || this == cancelled;

  static ImagingOrderStatus fromWire(String value) =>
      ImagingOrderStatus.values.firstWhere(
        (ImagingOrderStatus status) => status.wireValue == value,
        orElse: () => ImagingOrderStatus.ordered,
      );
}

/// Lifecycle of an imaging report.
enum ImagingReportStatus {
  draft('draft'),
  verified('verified');

  const ImagingReportStatus(this.wireValue);

  final String wireValue;

  String get label => switch (this) {
    ImagingReportStatus.draft => 'Draft',
    ImagingReportStatus.verified => 'Verified',
  };

  bool get isEditable => this == draft;

  bool get isVerified => this == verified;

  static ImagingReportStatus fromWire(String value) =>
      ImagingReportStatus.values.firstWhere(
        (ImagingReportStatus status) => status.wireValue == value,
        orElse: () => ImagingReportStatus.draft,
      );
}

/// A requested imaging study.
@immutable
final class ImagingOrder {
  const ImagingOrder({
    required this.id,
    required this.tenantId,
    required this.patientId,
    required this.orderedBy,
    required this.orderCode,
    required this.modality,
    required this.bodyRegion,
    required this.priority,
    required this.status,
    required this.orderedAt,
    required this.createdAt,
    required this.updatedAt,
    this.encounterId,
    this.clinicalIndication,
    this.cancelledAt,
    this.cancelledReason,
  });

  factory ImagingOrder.fromRow(Map<String, Object?> row) {
    final Object? encounter = row['encounter_id'];
    final Object? indication = row['clinical_indication'];
    final Object? cancelledAt = row['cancelled_at'];
    final Object? cancelledReason = row['cancelled_reason'];
    return ImagingOrder(
      id: row['id']! as String,
      tenantId: row['tenant_id']! as String,
      patientId: row['patient_id']! as String,
      encounterId: encounter is String ? encounter : null,
      orderedBy: row['ordered_by']! as String,
      orderCode: row['order_code']! as String,
      modality: ImagingModality.fromWire(row['modality']! as String),
      bodyRegion: row['body_region']! as String,
      priority: ImagingPriority.fromWire(row['priority']! as String),
      status: ImagingOrderStatus.fromWire(row['status']! as String),
      clinicalIndication: indication is String ? indication : null,
      orderedAt: row['ordered_at']! as DateTime,
      cancelledAt: cancelledAt is DateTime ? cancelledAt : null,
      cancelledReason: cancelledReason is String ? cancelledReason : null,
      createdAt: row['created_at']! as DateTime,
      updatedAt: row['updated_at']! as DateTime,
    );
  }

  final String id;
  final String tenantId;
  final String patientId;
  final String? encounterId;
  final String orderedBy;
  final String orderCode;
  final ImagingModality modality;
  final String bodyRegion;
  final ImagingPriority priority;
  final ImagingOrderStatus status;
  final String? clinicalIndication;
  final DateTime orderedAt;
  final DateTime? cancelledAt;
  final String? cancelledReason;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isOrdered => status == ImagingOrderStatus.ordered;

  bool get isTerminal => status.isTerminal;
}

/// An acquired imaging study with its PACS/DICOM reference.
@immutable
final class ImagingStudy {
  const ImagingStudy({
    required this.id,
    required this.tenantId,
    required this.imagingOrderId,
    required this.studyUid,
    required this.modality,
    required this.bodyRegion,
    required this.performedBy,
    required this.performedAt,
    required this.createdAt,
    required this.updatedAt,
    this.acquisitionNotes,
  });

  factory ImagingStudy.fromRow(Map<String, Object?> row) {
    final Object? notes = row['acquisition_notes'];
    return ImagingStudy(
      id: row['id']! as String,
      tenantId: row['tenant_id']! as String,
      imagingOrderId: row['imaging_order_id']! as String,
      studyUid: row['study_uid']! as String,
      modality: ImagingModality.fromWire(row['modality']! as String),
      bodyRegion: row['body_region']! as String,
      performedBy: row['performed_by']! as String,
      performedAt: row['performed_at']! as DateTime,
      acquisitionNotes: notes is String ? notes : null,
      createdAt: row['created_at']! as DateTime,
      updatedAt: row['updated_at']! as DateTime,
    );
  }

  final String id;
  final String tenantId;
  final String imagingOrderId;
  final String studyUid;
  final ImagingModality modality;
  final String bodyRegion;
  final String performedBy;
  final DateTime performedAt;
  final String? acquisitionNotes;
  final DateTime createdAt;
  final DateTime updatedAt;
}

/// A radiology report for one study, immutable once verified.
@immutable
final class ImagingReport {
  const ImagingReport({
    required this.id,
    required this.tenantId,
    required this.imagingOrderId,
    required this.studyId,
    required this.findings,
    required this.impression,
    required this.status,
    required this.enteredBy,
    required this.enteredAt,
    required this.createdAt,
    required this.updatedAt,
    this.verifiedBy,
    this.verifiedAt,
  });

  factory ImagingReport.fromRow(Map<String, Object?> row) {
    final Object? verifiedBy = row['verified_by'];
    final Object? verifiedAt = row['verified_at'];
    return ImagingReport(
      id: row['id']! as String,
      tenantId: row['tenant_id']! as String,
      imagingOrderId: row['imaging_order_id']! as String,
      studyId: row['study_id']! as String,
      findings: row['findings']! as String,
      impression: row['impression']! as String,
      status: ImagingReportStatus.fromWire(row['status']! as String),
      enteredBy: row['entered_by']! as String,
      enteredAt: row['entered_at']! as DateTime,
      verifiedBy: verifiedBy is String ? verifiedBy : null,
      verifiedAt: verifiedAt is DateTime ? verifiedAt : null,
      createdAt: row['created_at']! as DateTime,
      updatedAt: row['updated_at']! as DateTime,
    );
  }

  final String id;
  final String tenantId;
  final String imagingOrderId;
  final String studyId;
  final String findings;
  final String impression;
  final ImagingReportStatus status;
  final String enteredBy;
  final DateTime enteredAt;
  final String? verifiedBy;
  final DateTime? verifiedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isDraft => status.isEditable;

  bool get isVerified => status.isVerified;
}
