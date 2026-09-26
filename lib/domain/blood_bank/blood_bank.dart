/// Blood bank entities (Module 26).
///
/// Transfusion flow: request → crossmatch → approval → issue → administration.
/// Blood units carry the reserved-for-patient lifecycle and expire on a
/// hard timestamp.
// ignore_for_file: sort_constructors_first
library;

import 'package:meta/meta.dart';

/// ABO/Rhesus blood group.
enum BloodGroup {
  aPositive('A+'),
  aNegative('A-'),
  bPositive('B+'),
  bNegative('B-'),
  abPositive('AB+'),
  abNegative('AB-'),
  oPositive('O+'),
  oNegative('O-');

  const BloodGroup(this.wireValue);

  final String wireValue;

  String get label => switch (this) {
    BloodGroup.aPositive => 'A positive',
    BloodGroup.aNegative => 'A negative',
    BloodGroup.bPositive => 'B positive',
    BloodGroup.bNegative => 'B negative',
    BloodGroup.abPositive => 'AB positive',
    BloodGroup.abNegative => 'AB negative',
    BloodGroup.oPositive => 'O positive',
    BloodGroup.oNegative => 'O negative',
  };

  static BloodGroup fromWire(String value) => BloodGroup.values.firstWhere(
    (BloodGroup group) => group.wireValue == value,
    orElse: () => BloodGroup.oPositive,
  );
}

/// Blood product component.
enum BloodComponent {
  wholeBlood('whole_blood'),
  redCells('red_cells'),
  platelets('platelets'),
  plasma('plasma'),
  cryoprecipitate('cryoprecipitate'),
  doubleRedCells('double_red_cells');

  const BloodComponent(this.wireValue);

  final String wireValue;

  String get label => switch (this) {
    BloodComponent.wholeBlood => 'Whole blood',
    BloodComponent.redCells => 'Red cells',
    BloodComponent.platelets => 'Platelets',
    BloodComponent.plasma => 'Plasma',
    BloodComponent.cryoprecipitate => 'Cryoprecipitate',
    BloodComponent.doubleRedCells => 'Double red cells',
  };

  static BloodComponent fromWire(String value) =>
      BloodComponent.values.firstWhere(
        (BloodComponent component) => component.wireValue == value,
        orElse: () => BloodComponent.redCells,
      );
}

/// Inventory status of a blood unit.
enum BloodUnitStatus {
  available('available'),
  reserved('reserved'),
  issued('issued'),
  quarantined('quarantined'),
  expired('expired'),
  discarded('discarded');

  const BloodUnitStatus(this.wireValue);

  final String wireValue;

  String get label => switch (this) {
    BloodUnitStatus.available => 'Available',
    BloodUnitStatus.reserved => 'Reserved',
    BloodUnitStatus.issued => 'Issued',
    BloodUnitStatus.quarantined => 'Quarantined',
    BloodUnitStatus.expired => 'Expired',
    BloodUnitStatus.discarded => 'Discarded',
  };

  bool get isTerminal => this == expired || this == discarded;

  static BloodUnitStatus fromWire(String value) =>
      BloodUnitStatus.values.firstWhere(
        (BloodUnitStatus status) => status.wireValue == value,
        orElse: () => BloodUnitStatus.available,
      );
}

/// Workflow status of a transfusion request.
enum TransfusionRequestStatus {
  pending('pending'),
  crossmatched('crossmatched'),
  approved('approved'),
  rejected('rejected'),
  cancelled('cancelled'),
  completed('completed');

  const TransfusionRequestStatus(this.wireValue);

  final String wireValue;

  String get label => switch (this) {
    TransfusionRequestStatus.pending => 'Pending',
    TransfusionRequestStatus.crossmatched => 'Crossmatched',
    TransfusionRequestStatus.approved => 'Approved',
    TransfusionRequestStatus.rejected => 'Rejected',
    TransfusionRequestStatus.cancelled => 'Cancelled',
    TransfusionRequestStatus.completed => 'Completed',
  };

  bool get isTerminal =>
      this == completed || this == cancelled || this == rejected;

  static TransfusionRequestStatus fromWire(String value) =>
      TransfusionRequestStatus.values.firstWhere(
        (TransfusionRequestStatus status) => status.wireValue == value,
        orElse: () => TransfusionRequestStatus.pending,
      );
}

/// Result of the crossmatch between request and unit.
enum CrossmatchResult {
  pending('pending'),
  compatible('compatible'),
  incompatible('incompatible');

  const CrossmatchResult(this.wireValue);

  final String wireValue;

  String get label => switch (this) {
    CrossmatchResult.pending => 'Pending',
    CrossmatchResult.compatible => 'Compatible',
    CrossmatchResult.incompatible => 'Incompatible',
  };

  bool get isCompatible => this == compatible;

  static CrossmatchResult fromWire(String value) =>
      CrossmatchResult.values.firstWhere(
        (CrossmatchResult result) => result.wireValue == value,
        orElse: () => CrossmatchResult.pending,
      );
}

/// Request urgency tier.
enum TransfusionUrgency {
  routine('routine'),
  urgent('urgent'),
  emergency('emergency');

  const TransfusionUrgency(this.wireValue);

  final String wireValue;

  String get label => switch (this) {
    TransfusionUrgency.routine => 'Routine',
    TransfusionUrgency.urgent => 'Urgent',
    TransfusionUrgency.emergency => 'Emergency',
  };

  bool get isEmergency => this == emergency;

  static TransfusionUrgency fromWire(String value) =>
      TransfusionUrgency.values.firstWhere(
        (TransfusionUrgency urgency) => urgency.wireValue == value,
        orElse: () => TransfusionUrgency.routine,
      );
}

/// Administration outcome of a transfusion.
enum TransfusionStatus {
  started('started'),
  transfused('transfused'),
  stopped('stopped'),
  returned('returned'),
  reaction('reaction');

  const TransfusionStatus(this.wireValue);

  final String wireValue;

  String get label => switch (this) {
    TransfusionStatus.started => 'Started',
    TransfusionStatus.transfused => 'Transfused',
    TransfusionStatus.stopped => 'Stopped',
    TransfusionStatus.returned => 'Returned',
    TransfusionStatus.reaction => 'Reaction',
  };

  static TransfusionStatus fromWire(String value) =>
      TransfusionStatus.values.firstWhere(
        (TransfusionStatus status) => status.wireValue == value,
        orElse: () => TransfusionStatus.started,
      );
}

/// A doctor-ordered transfusion request awaiting crossmatch and approval.
@immutable
final class TransfusionRequest {
  const TransfusionRequest({
    required this.id,
    required this.tenantId,
    required this.patientId,
    required this.requestedBy,
    required this.requestedBloodGroup,
    required this.component,
    required this.unitsRequested,
    required this.urgency,
    required this.status,
    required this.crossmatchResult,
    required this.requestedAt,
    required this.createdAt,
    required this.updatedAt,
    this.encounterId,
    this.indication,
    this.approvedBy,
    this.approvedAt,
  });

  final String id;
  final String tenantId;
  final String patientId;
  final String? encounterId;
  final String requestedBy;
  final BloodGroup requestedBloodGroup;
  final BloodComponent component;
  final int unitsRequested;
  final String? indication;
  final TransfusionUrgency urgency;
  final TransfusionRequestStatus status;
  final CrossmatchResult crossmatchResult;
  final DateTime requestedAt;
  final String? approvedBy;
  final DateTime? approvedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isApproved => status == TransfusionRequestStatus.approved;

  bool get isTerminal => status.isTerminal;

  factory TransfusionRequest.fromRow(Map<String, Object?> row) {
    int? asInt(Object? value) => value is num ? value.toInt() : null;
    final Object? encounter = row['encounter_id'];
    final Object? indication = row['indication'];
    final Object? approvedBy = row['approved_by'];
    final Object? approvedAt = row['approved_at'];
    return TransfusionRequest(
      id: row['id']! as String,
      tenantId: row['tenant_id']! as String,
      patientId: row['patient_id']! as String,
      encounterId: encounter is String ? encounter : null,
      requestedBy: row['requested_by']! as String,
      requestedBloodGroup: BloodGroup.fromWire(
        row['requested_blood_group']! as String,
      ),
      component: BloodComponent.fromWire(row['component']! as String),
      unitsRequested: asInt(row['units_requested']) ?? 0,
      indication: indication is String ? indication : null,
      urgency: TransfusionUrgency.fromWire(row['urgency']! as String),
      status: TransfusionRequestStatus.fromWire(row['status']! as String),
      crossmatchResult: CrossmatchResult.fromWire(
        row['crossmatch_result']! as String,
      ),
      requestedAt: row['requested_at']! as DateTime,
      approvedBy: approvedBy is String ? approvedBy : null,
      approvedAt: approvedAt is DateTime ? approvedAt : null,
      createdAt: row['created_at']! as DateTime,
      updatedAt: row['updated_at']! as DateTime,
    );
  }
}

/// A single collected blood unit held in inventory.
@immutable
final class BloodUnit {
  const BloodUnit({
    required this.id,
    required this.tenantId,
    required this.unitNumber,
    required this.bloodGroup,
    required this.component,
    required this.collectedAt,
    required this.expiresAt,
    required this.status,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.volumeMl,
    this.locationId,
    this.patientId,
    this.transfusionRequestId,
  });

  final String id;
  final String tenantId;
  final String unitNumber;
  final BloodGroup bloodGroup;
  final BloodComponent component;
  final int? volumeMl;
  final DateTime collectedAt;
  final DateTime expiresAt;
  final BloodUnitStatus status;
  final String? locationId;
  final String? patientId;
  final String? transfusionRequestId;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isAvailable => status == BloodUnitStatus.available;

  bool get isReserved => status == BloodUnitStatus.reserved;

  bool get isIssued => status == BloodUnitStatus.issued;

  bool get isTerminal => status.isTerminal;

  factory BloodUnit.fromRow(Map<String, Object?> row) {
    int? asInt(Object? value) => value is num ? value.toInt() : null;
    final Object? location = row['location_id'];
    final Object? patient = row['patient_id'];
    final Object? request = row['transfusion_request_id'];
    return BloodUnit(
      id: row['id']! as String,
      tenantId: row['tenant_id']! as String,
      unitNumber: row['unit_number']! as String,
      bloodGroup: BloodGroup.fromWire(row['blood_group']! as String),
      component: BloodComponent.fromWire(row['component']! as String),
      volumeMl: asInt(row['volume_ml']),
      collectedAt: row['collected_at']! as DateTime,
      expiresAt: row['expires_at']! as DateTime,
      status: BloodUnitStatus.fromWire(row['status']! as String),
      locationId: location is String ? location : null,
      patientId: patient is String ? patient : null,
      transfusionRequestId: request is String ? request : null,
      createdBy: row['created_by']! as String,
      createdAt: row['created_at']! as DateTime,
      updatedAt: row['updated_at']! as DateTime,
    );
  }
}

/// A recorded transfusion administration against one blood unit.
@immutable
final class Transfusion {
  const Transfusion({
    required this.id,
    required this.tenantId,
    required this.transfusionRequestId,
    required this.bloodUnitId,
    required this.patientId,
    required this.recordedBy,
    required this.startedAt,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.finishedAt,
    this.volumeMl,
    this.reactionNotes,
  });

  final String id;
  final String tenantId;
  final String transfusionRequestId;
  final String bloodUnitId;
  final String patientId;
  final String recordedBy;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final TransfusionStatus status;
  final int? volumeMl;
  final String? reactionNotes;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get hasReaction => status == TransfusionStatus.reaction;

  bool get isComplete => finishedAt != null;

  factory Transfusion.fromRow(Map<String, Object?> row) {
    int? asInt(Object? value) => value is num ? value.toInt() : null;
    final Object? finished = row['finished_at'];
    final Object? reaction = row['reaction_notes'];
    return Transfusion(
      id: row['id']! as String,
      tenantId: row['tenant_id']! as String,
      transfusionRequestId: row['transfusion_request_id']! as String,
      bloodUnitId: row['blood_unit_id']! as String,
      patientId: row['patient_id']! as String,
      recordedBy: row['recorded_by']! as String,
      startedAt: row['started_at']! as DateTime,
      finishedAt: finished is DateTime ? finished : null,
      status: TransfusionStatus.fromWire(row['status']! as String),
      volumeMl: asInt(row['volume_ml']),
      reactionNotes: reaction is String ? reaction : null,
      createdAt: row['created_at']! as DateTime,
      updatedAt: row['updated_at']! as DateTime,
    );
  }
}
