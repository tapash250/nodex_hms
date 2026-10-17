/// Biomedical assets & calibration entities (Module 29).
///
/// Specification scope: "Equipment registry, maintenance, breakdown tickets,
/// calibration, lifecycle."
///
/// This is the serialized equipment estate behind the clinical work — the
/// monitor, the ventilator, the infusion pump, the analyser. It is distinct
/// from central inventory (Module 28), which holds consumable stock: an asset
/// is an individually accountable instrument with a location, a lifecycle and a
/// calibration obligation, not a quantity on a shelf.
///
/// Three records, mirroring the scope: the [BiomedicalAsset] registry, the
/// [BreakdownTicket] fault report (a guarded state machine), and the
/// append-only [MaintenanceRecord] service history that covers both maintenance
/// and calibration. The calibration-due state ([calibrationDueState]) is
/// *derived* from the latest record's next-due date rather than stored twice.
// ignore_for_file: sort_constructors_first
library;

import 'package:meta/meta.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';

/// How much a failure of an instrument matters.
enum AssetCriticality {
  /// Convenience equipment; failure is an inconvenience.
  low('low'),

  /// Routine clinical equipment.
  medium('medium'),

  /// Equipment whose failure disrupts a service.
  high('high'),

  /// Life-support equipment; failure is a patient-safety event.
  lifeSupport('life_support');

  const AssetCriticality(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    AssetCriticality.low => 'Low',
    AssetCriticality.medium => 'Medium',
    AssetCriticality.high => 'High',
    AssetCriticality.lifeSupport => 'Life support',
  };

  /// Parses a stored value.
  static AssetCriticality fromWire(String value) =>
      AssetCriticality.values.firstWhere(
        (AssetCriticality criticality) => criticality.wireValue == value,
        orElse: () => AssetCriticality.medium,
      );
}

/// Lifecycle status of an asset.
enum AssetStatus {
  /// Available for clinical use.
  inService('in_service'),

  /// In the estate but withdrawn from use.
  outOfService('out_of_service'),

  /// Out of use while a fault is being repaired.
  underRepair('under_repair'),

  /// Retired; retained as a historical record and frozen.
  decommissioned('decommissioned');

  const AssetStatus(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    AssetStatus.inService => 'In service',
    AssetStatus.outOfService => 'Out of service',
    AssetStatus.underRepair => 'Under repair',
    AssetStatus.decommissioned => 'Decommissioned',
  };

  /// Parses a stored value.
  static AssetStatus fromWire(String value) => AssetStatus.values.firstWhere(
    (AssetStatus status) => status.wireValue == value,
    orElse: () => AssetStatus.inService,
  );

  /// Whether the asset is retired and therefore frozen.
  bool get isDecommissioned => this == AssetStatus.decommissioned;
}

/// The kind of service a maintenance record describes.
enum MaintenanceKind {
  /// A calibration against a reference standard.
  calibration('calibration'),

  /// Scheduled preventive maintenance.
  preventive('preventive'),

  /// A repair, usually against a breakdown ticket.
  repair('repair'),

  /// An electrical-safety or functional-safety test.
  safetyTest('safety_test'),

  /// A general inspection.
  inspection('inspection');

  const MaintenanceKind(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    MaintenanceKind.calibration => 'Calibration',
    MaintenanceKind.preventive => 'Preventive maintenance',
    MaintenanceKind.repair => 'Repair',
    MaintenanceKind.safetyTest => 'Safety test',
    MaintenanceKind.inspection => 'Inspection',
  };

  /// Parses a stored value.
  static MaintenanceKind fromWire(String value) =>
      MaintenanceKind.values.firstWhere(
        (MaintenanceKind kind) => kind.wireValue == value,
        orElse: () => MaintenanceKind.calibration,
      );
}

/// The outcome of a service event.
enum MaintenanceResult {
  /// The instrument passed.
  pass('pass'),

  /// The instrument passed after adjustment.
  passAdjusted('pass_adjusted'),

  /// The instrument failed and remains unfit.
  fail('fail');

  const MaintenanceResult(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    MaintenanceResult.pass => 'Pass',
    MaintenanceResult.passAdjusted => 'Pass (adjusted)',
    MaintenanceResult.fail => 'Fail',
  };

  /// Parses a stored value.
  static MaintenanceResult fromWire(String value) =>
      MaintenanceResult.values.firstWhere(
        (MaintenanceResult result) => result.wireValue == value,
        orElse: () => MaintenanceResult.pass,
      );

  /// Whether the instrument can return to service.
  bool get isFit => this != MaintenanceResult.fail;
}

/// Urgency of a breakdown ticket.
enum TicketPriority {
  /// Cosmetic or non-clinical.
  low('low'),

  /// Routine.
  medium('medium'),

  /// Service-affecting.
  high('high'),

  /// Patient-safety.
  critical('critical');

  const TicketPriority(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    TicketPriority.low => 'Low',
    TicketPriority.medium => 'Medium',
    TicketPriority.high => 'High',
    TicketPriority.critical => 'Critical',
  };

  /// Parses a stored value.
  static TicketPriority fromWire(String value) =>
      TicketPriority.values.firstWhere(
        (TicketPriority priority) => priority.wireValue == value,
        orElse: () => TicketPriority.medium,
      );
}

/// The breakdown state machine's states.
enum TicketStatus {
  /// Reported, not yet looked at.
  reported('reported'),

  /// Seen and owned by a responder.
  acknowledged('acknowledged'),

  /// Being repaired.
  inRepair('in_repair'),

  /// Repaired; retained and frozen.
  resolved('resolved'),

  /// Called off; retained and frozen.
  cancelled('cancelled');

  const TicketStatus(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    TicketStatus.reported => 'Reported',
    TicketStatus.acknowledged => 'Acknowledged',
    TicketStatus.inRepair => 'In repair',
    TicketStatus.resolved => 'Resolved',
    TicketStatus.cancelled => 'Cancelled',
  };

  /// Parses a stored value.
  static TicketStatus fromWire(String value) => TicketStatus.values.firstWhere(
    (TicketStatus status) => status.wireValue == value,
    orElse: () => TicketStatus.reported,
  );

  /// Whether the ticket is closed and therefore frozen.
  bool get isTerminal =>
      this == TicketStatus.resolved || this == TicketStatus.cancelled;

  /// Whether the ticket is live and awaiting progress.
  bool get isLive => !isTerminal;
}

/// Whether a breakdown ticket may move from [from] to [to]. The ticket advances
/// one stage at a time and may be cancelled from any live stage. This is the
/// same rule the database enforces.
bool breakdownCanAdvance(TicketStatus from, TicketStatus to) {
  if (from.isTerminal || from == to) {
    return false;
  }
  if (to == TicketStatus.cancelled) {
    return true;
  }
  return switch (from) {
    TicketStatus.reported => to == TicketStatus.acknowledged,
    TicketStatus.acknowledged => to == TicketStatus.inRepair,
    TicketStatus.inRepair => to == TicketStatus.resolved,
    TicketStatus.resolved || TicketStatus.cancelled => false,
  };
}

/// How a calibration obligation stands right now.
enum CalibrationDueState {
  /// No next-due date has been recorded.
  notScheduled('not_scheduled'),

  /// The next due date is comfortably ahead.
  current('current'),

  /// Due within the reminder window.
  dueSoon('due_soon'),

  /// Past due.
  overdue('overdue');

  const CalibrationDueState(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    CalibrationDueState.notScheduled => 'Not scheduled',
    CalibrationDueState.current => 'Current',
    CalibrationDueState.dueSoon => 'Due soon',
    CalibrationDueState.overdue => 'Overdue',
  };

  /// Whether the instrument needs attention.
  bool get needsAttention =>
      this == CalibrationDueState.dueSoon ||
      this == CalibrationDueState.overdue;
}

/// The default reminder window before a calibration falls due.
const Duration kCalibrationReminderWindow = Duration(days: 30);

/// Derives the calibration-due state from the next-due date.
CalibrationDueState calibrationDueState({
  required DateTime? nextDueAt,
  required DateTime now,
  Duration reminderWindow = kCalibrationReminderWindow,
}) {
  if (nextDueAt == null) {
    return CalibrationDueState.notScheduled;
  }
  final DateTime due = nextDueAt.toUtc();
  final DateTime asOf = now.toUtc();
  if (!due.isAfter(asOf)) {
    return CalibrationDueState.overdue;
  }
  if (due.isBefore(asOf.add(reminderWindow))) {
    return CalibrationDueState.dueSoon;
  }
  return CalibrationDueState.current;
}

/// A serialized instrument in the registry.
@immutable
final class BiomedicalAsset {
  /// Creates an asset.
  const BiomedicalAsset({
    required this.id,
    required this.tenantId,
    required this.facilityId,
    required this.assetTag,
    required this.name,
    required this.criticality,
    required this.status,
    required this.createdBy,
    required this.updatedAt,
    this.departmentId,
    this.category,
    this.manufacturer,
    this.modelNo,
    this.serialNo,
    this.commissionedOn,
    this.warrantyUntil,
    this.notes,
    this.createdAt,
  });

  /// Validates and builds a new asset row.
  static Map<String, Object?> registerRow({
    required String tenantId,
    required String createdBy,
    required String facilityId,
    required String assetTag,
    required String name,
    String? departmentId,
    String? category,
    String? manufacturer,
    String? modelNo,
    String? serialNo,
    AssetCriticality criticality = AssetCriticality.medium,
    AssetStatus status = AssetStatus.inService,
    DateTime? commissionedOn,
    DateTime? warrantyUntil,
    String? notes,
    String assetId = '',
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (createdBy.isEmpty) {
      fieldErrors['created_by'] = 'Creator is required.';
    }
    if (facilityId.isEmpty) {
      fieldErrors['facility_id'] = 'A facility is required.';
    }
    if (assetTag.trim().isEmpty) {
      fieldErrors['asset_tag'] = 'An asset tag is required.';
    }
    if (name.trim().isEmpty) {
      fieldErrors['name'] = 'A name is required.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Asset entry failed validation.',
        fieldErrors: fieldErrors,
        code: 'biomedical_asset_invalid',
      );
    }
    final String now = DateTime.now().toUtc().toIso8601String();
    return <String, Object?>{
      if (assetId.isNotEmpty) 'id': assetId,
      'tenant_id': tenantId,
      'facility_id': facilityId,
      'department_id': _trimmed(departmentId),
      'asset_tag': assetTag.trim(),
      'name': name.trim(),
      'category': _trimmed(category),
      'manufacturer': _trimmed(manufacturer),
      'model_no': _trimmed(modelNo),
      'serial_no': _trimmed(serialNo),
      'criticality': criticality.wireValue,
      'status': status.wireValue,
      'commissioned_on': _dateOnly(commissionedOn),
      'warranty_until': _dateOnly(warrantyUntil),
      'notes': _trimmed(notes),
      'created_by': createdBy,
      'created_at': now,
      'updated_at': now,
    };
  }

  /// Materializes an asset from a local row.
  factory BiomedicalAsset.fromRow(Map<String, Object?> row) => BiomedicalAsset(
    id: row['id']! as String,
    tenantId: row['tenant_id']! as String,
    facilityId: row['facility_id']! as String,
    assetTag: row['asset_tag']! as String,
    name: row['name']! as String,
    criticality: AssetCriticality.fromWire(
      (row['criticality'] as String?) ?? AssetCriticality.medium.wireValue,
    ),
    status: AssetStatus.fromWire(
      (row['status'] as String?) ?? AssetStatus.inService.wireValue,
    ),
    createdBy: row['created_by']! as String,
    updatedAt: _parse(row['updated_at']),
    departmentId: row['department_id'] as String?,
    category: row['category'] as String?,
    manufacturer: row['manufacturer'] as String?,
    modelNo: row['model_no'] as String?,
    serialNo: row['serial_no'] as String?,
    commissionedOn: _parseNullableDate(row['commissioned_on']),
    warrantyUntil: _parseNullableDate(row['warranty_until']),
    notes: row['notes'] as String?,
    createdAt: _parseNullable(row['created_at']),
  );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// Facility the asset belongs to.
  final String facilityId;

  /// Owning department, when known.
  final String? departmentId;

  /// Unique asset tag.
  final String assetTag;

  /// Display name.
  final String name;

  /// Free-text category.
  final String? category;

  /// Manufacturer.
  final String? manufacturer;

  /// Model number.
  final String? modelNo;

  /// Serial number.
  final String? serialNo;

  /// Criticality class.
  final AssetCriticality criticality;

  /// Lifecycle status.
  final AssetStatus status;

  /// Commissioning date, UTC.
  final DateTime? commissionedOn;

  /// Warranty expiry, UTC.
  final DateTime? warrantyUntil;

  /// Free-text note.
  final String? notes;

  /// Who registered the asset.
  final String createdBy;

  /// Last change, UTC.
  final DateTime updatedAt;

  /// When the asset was registered, UTC.
  final DateTime? createdAt;

  /// Whether the asset may be edited or decommissioned.
  bool get isEditable => !status.isDecommissioned;
}

/// The full editable change set for an asset.
Map<String, Object?> biomedicalAssetChanges({
  required String facilityId,
  required String assetTag,
  required String name,
  String? departmentId,
  String? category,
  String? manufacturer,
  String? modelNo,
  String? serialNo,
  AssetCriticality? criticality,
  AssetStatus? status,
  DateTime? commissionedOn,
  DateTime? warrantyUntil,
  String? notes,
}) => <String, Object?>{
  'facility_id': facilityId,
  'asset_tag': assetTag.trim(),
  'name': name.trim(),
  'department_id': _trimmed(departmentId),
  'category': _trimmed(category),
  'manufacturer': _trimmed(manufacturer),
  'model_no': _trimmed(modelNo),
  'serial_no': _trimmed(serialNo),
  'commissioned_on': _dateOnly(commissionedOn),
  'warranty_until': _dateOnly(warrantyUntil),
  'notes': _trimmed(notes),
  if (criticality != null) 'criticality': criticality.wireValue,
  if (status != null) 'status': status.wireValue,
  'updated_at': DateTime.now().toUtc().toIso8601String(),
};

/// The change set for decommissioning an asset. The row is retained and frozen.
Map<String, Object?> biomedicalAssetDecommissionChanges() => <String, Object?>{
  'status': AssetStatus.decommissioned.wireValue,
  'updated_at': DateTime.now().toUtc().toIso8601String(),
};

/// The change set for moving an asset's lifecycle status.
Map<String, Object?> biomedicalAssetStatusChanges(AssetStatus status) =>
    <String, Object?>{
      'status': status.wireValue,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

/// A fault report against an instrument.
@immutable
final class BreakdownTicket {
  /// Creates a ticket.
  const BreakdownTicket({
    required this.id,
    required this.tenantId,
    required this.assetId,
    required this.facilityId,
    required this.reportedBy,
    required this.reportedAt,
    required this.priority,
    required this.symptom,
    required this.status,
    required this.createdBy,
    required this.updatedAt,
    this.acknowledgedAt,
    this.resolvedAt,
    this.resolutionNotes,
    this.cancellationReason,
    this.createdAt,
  });

  /// Validates and builds a new ticket row.
  static Map<String, Object?> registerRow({
    required String tenantId,
    required String createdBy,
    required String assetId,
    required String facilityId,
    required String reportedBy,
    required String symptom,
    TicketPriority priority = TicketPriority.medium,
    DateTime? reportedAt,
    String ticketId = '',
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (createdBy.isEmpty) {
      fieldErrors['created_by'] = 'Creator is required.';
    }
    if (assetId.isEmpty) {
      fieldErrors['asset_id'] = 'An asset is required.';
    }
    if (facilityId.isEmpty) {
      fieldErrors['facility_id'] = 'A facility is required.';
    }
    if (reportedBy.isEmpty) {
      fieldErrors['reported_by'] = 'A reporter is required.';
    }
    if (symptom.trim().isEmpty) {
      fieldErrors['symptom'] = 'Describe the fault.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Breakdown ticket failed validation.',
        fieldErrors: fieldErrors,
        code: 'biomedical_ticket_invalid',
      );
    }
    final String now = (reportedAt ?? DateTime.now().toUtc())
        .toUtc()
        .toIso8601String();
    return <String, Object?>{
      if (ticketId.isNotEmpty) 'id': ticketId,
      'tenant_id': tenantId,
      'asset_id': assetId,
      'facility_id': facilityId,
      'reported_by': reportedBy,
      'reported_at': now,
      'priority': priority.wireValue,
      'symptom': symptom.trim(),
      'status': TicketStatus.reported.wireValue,
      'created_by': createdBy,
      'created_at': now,
      'updated_at': now,
    };
  }

  /// Materializes a ticket from a local row.
  factory BreakdownTicket.fromRow(Map<String, Object?> row) => BreakdownTicket(
    id: row['id']! as String,
    tenantId: row['tenant_id']! as String,
    assetId: row['asset_id']! as String,
    facilityId: row['facility_id']! as String,
    reportedBy: row['reported_by']! as String,
    reportedAt: _parse(row['reported_at']),
    priority: TicketPriority.fromWire(
      (row['priority'] as String?) ?? TicketPriority.medium.wireValue,
    ),
    symptom: row['symptom']! as String,
    status: TicketStatus.fromWire(
      (row['status'] as String?) ?? TicketStatus.reported.wireValue,
    ),
    createdBy: row['created_by']! as String,
    updatedAt: _parse(row['updated_at']),
    acknowledgedAt: _parseNullable(row['acknowledged_at']),
    resolvedAt: _parseNullable(row['resolved_at']),
    resolutionNotes: row['resolution_notes'] as String?,
    cancellationReason: row['cancellation_reason'] as String?,
    createdAt: _parseNullable(row['created_at']),
  );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// Instrument that failed.
  final String assetId;

  /// Facility.
  final String facilityId;

  /// Who reported the fault.
  final String reportedBy;

  /// When it was reported, UTC.
  final DateTime reportedAt;

  /// Urgency.
  final TicketPriority priority;

  /// Reported symptom.
  final String symptom;

  /// Fault stage.
  final TicketStatus status;

  /// Who acknowledged the fault.
  final DateTime? acknowledgedAt;

  /// When the fault was resolved, UTC.
  final DateTime? resolvedAt;

  /// What was done to resolve it.
  final String? resolutionNotes;

  /// Why it was cancelled.
  final String? cancellationReason;

  /// Who raised the ticket.
  final String createdBy;

  /// Last change, UTC.
  final DateTime updatedAt;

  /// When the ticket was created, UTC.
  final DateTime? createdAt;

  /// Whether the ticket may still be progressed.
  bool get isLive => !status.isTerminal;
}

/// The transition change set for a breakdown ticket. Sets the new status,
/// stamps the stage timestamp the new status implies, and carries the resolution
/// note or cancellation reason the transition requires.
Map<String, Object?> ticketTransitionChanges({
  required TicketStatus to,
  DateTime? at,
  String? resolutionNotes,
  String? cancellationReason,
}) {
  final String now = (at ?? DateTime.now().toUtc()).toUtc().toIso8601String();
  return <String, Object?>{
    'status': to.wireValue,
    if (to == TicketStatus.acknowledged) 'acknowledged_at': now,
    if (to == TicketStatus.resolved) 'resolved_at': now,
    if (to == TicketStatus.resolved)
      'resolution_notes': _trimmed(resolutionNotes),
    if (to == TicketStatus.cancelled)
      'cancellation_reason': _trimmed(cancellationReason),
    'updated_at': now,
  };
}

/// An append-only service event: maintenance or calibration.
@immutable
final class MaintenanceRecord {
  /// Creates a service record.
  const MaintenanceRecord({
    required this.id,
    required this.tenantId,
    required this.assetId,
    required this.kind,
    required this.result,
    required this.performedAt,
    required this.createdAt,
    this.ticketId,
    this.performedBy,
    this.provider,
    this.nextDueAt,
    this.reference,
    this.notes,
  });

  /// Validates and builds a new service record row.
  static Map<String, Object?> registerRow({
    required String tenantId,
    required String assetId,
    required MaintenanceKind kind,
    required MaintenanceResult result,
    DateTime? performedAt,
    String? ticketId,
    String? performedBy,
    String? provider,
    DateTime? nextDueAt,
    String? reference,
    String? notes,
    String recordId = '',
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (assetId.isEmpty) {
      fieldErrors['asset_id'] = 'An asset is required.';
    }
    final DateTime when = (performedAt ?? DateTime.now().toUtc()).toUtc();
    if (nextDueAt != null && !nextDueAt.toUtc().isAfter(when)) {
      fieldErrors['next_due_at'] = 'Must fall after the service date.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Service record failed validation.',
        fieldErrors: fieldErrors,
        code: 'biomedical_maintenance_invalid',
      );
    }
    final String now = when.toIso8601String();
    return <String, Object?>{
      if (recordId.isNotEmpty) 'id': recordId,
      'tenant_id': tenantId,
      'asset_id': assetId,
      'ticket_id': _trimmed(ticketId),
      'kind': kind.wireValue,
      'result': result.wireValue,
      'performed_at': now,
      'performed_by': _trimmed(performedBy),
      'provider': _trimmed(provider),
      'next_due_at': nextDueAt?.toUtc().toIso8601String(),
      'reference': _trimmed(reference),
      'notes': _trimmed(notes),
      'created_at': now,
    };
  }

  /// Materializes a service record from a local row.
  factory MaintenanceRecord.fromRow(Map<String, Object?> row) =>
      MaintenanceRecord(
        id: row['id']! as String,
        tenantId: row['tenant_id']! as String,
        assetId: row['asset_id']! as String,
        kind: MaintenanceKind.fromWire(
          (row['kind'] as String?) ?? MaintenanceKind.calibration.wireValue,
        ),
        result: MaintenanceResult.fromWire(
          (row['result'] as String?) ?? MaintenanceResult.pass.wireValue,
        ),
        performedAt: _parse(row['performed_at']),
        createdAt: _parse(row['created_at']),
        ticketId: row['ticket_id'] as String?,
        performedBy: row['performed_by'] as String?,
        provider: row['provider'] as String?,
        nextDueAt: _parseNullable(row['next_due_at']),
        reference: row['reference'] as String?,
        notes: row['notes'] as String?,
      );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// Instrument serviced.
  final String assetId;

  /// Related breakdown ticket, when the service closed one.
  final String? ticketId;

  /// What was done.
  final MaintenanceKind kind;

  /// Outcome.
  final MaintenanceResult result;

  /// When the service happened, UTC.
  final DateTime performedAt;

  /// Who performed it, when an internal user.
  final String? performedBy;

  /// External provider, when service was contracted out.
  final String? provider;

  /// Next due date this service schedules, when any.
  final DateTime? nextDueAt;

  /// Reference or certificate number.
  final String? reference;

  /// Free-text note.
  final String? notes;

  /// When the record was captured locally, UTC.
  final DateTime createdAt;
}

String? _trimmed(String? value) {
  final String? trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

String? _dateOnly(DateTime? value) {
  if (value == null) {
    return null;
  }
  final DateTime utc = value.toUtc();
  return '${utc.year.toString().padLeft(4, '0')}-'
      '${utc.month.toString().padLeft(2, '0')}-'
      '${utc.day.toString().padLeft(2, '0')}';
}

DateTime _parse(Object? value) => value is String
    ? DateTime.parse(value).toUtc()
    : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

DateTime? _parseNullable(Object? value) =>
    value is String ? DateTime.parse(value).toUtc() : null;

DateTime? _parseNullableDate(Object? value) {
  if (value is! String || value.isEmpty) {
    return null;
  }
  final String normalised = value.contains('T') ? value : '${value}T00:00:00Z';
  return DateTime.tryParse(normalised)?.toUtc();
}
