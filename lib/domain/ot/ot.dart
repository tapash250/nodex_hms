/// Operation theatre entities (Module 19).
///
/// Case flow: schedule (conflict-checked room allocation) → pre-op fitness →
/// start → anesthesia and procedure records → post-op → completion. A booking
/// freezes once completed or cancelled; cancellation carries a reason.
// ignore_for_file: sort_constructors_first
library;

import 'package:meta/meta.dart';

/// Workflow status of an operation theatre booking.
enum OtBookingStatus {
  scheduled('scheduled'),
  inProgress('in_progress'),
  completed('completed'),
  cancelled('cancelled');

  const OtBookingStatus(this.wireValue);

  final String wireValue;

  String get label => switch (this) {
    OtBookingStatus.scheduled => 'Scheduled',
    OtBookingStatus.inProgress => 'In progress',
    OtBookingStatus.completed => 'Completed',
    OtBookingStatus.cancelled => 'Cancelled',
  };

  bool get isTerminal => this == completed || this == cancelled;

  static OtBookingStatus fromWire(String value) =>
      OtBookingStatus.values.firstWhere(
        (OtBookingStatus status) => status.wireValue == value,
        orElse: () => OtBookingStatus.scheduled,
      );
}

/// Scheduling priority tier of a case.
enum OtPriority {
  routine('routine'),
  urgent('urgent'),
  emergency('emergency');

  const OtPriority(this.wireValue);

  final String wireValue;

  String get label => switch (this) {
    OtPriority.routine => 'Routine',
    OtPriority.urgent => 'Urgent',
    OtPriority.emergency => 'Emergency',
  };

  bool get isEmergency => this == emergency;

  static OtPriority fromWire(String value) => OtPriority.values.firstWhere(
    (OtPriority priority) => priority.wireValue == value,
    orElse: () => OtPriority.routine,
  );
}

/// Pre-operative fitness judgement.
enum OtFitness {
  fit('fit'),
  fitWithConditions('fit_with_conditions'),
  unfit('unfit');

  const OtFitness(this.wireValue);

  final String wireValue;

  String get label => switch (this) {
    OtFitness.fit => 'Fit',
    OtFitness.fitWithConditions => 'Fit with conditions',
    OtFitness.unfit => 'Unfit',
  };

  bool get allowsSurgery => this != unfit;

  static OtFitness fromWire(String value) => OtFitness.values.firstWhere(
    (OtFitness fitness) => fitness.wireValue == value,
    orElse: () => OtFitness.fit,
  );
}

/// Anesthetic technique used for a case.
enum OtAnesthesiaType {
  general('general'),
  regional('regional'),
  local('local'),
  sedation('sedation');

  const OtAnesthesiaType(this.wireValue);

  final String wireValue;

  String get label => switch (this) {
    OtAnesthesiaType.general => 'General',
    OtAnesthesiaType.regional => 'Regional',
    OtAnesthesiaType.local => 'Local',
    OtAnesthesiaType.sedation => 'Sedation',
  };

  static OtAnesthesiaType fromWire(String value) =>
      OtAnesthesiaType.values.firstWhere(
        (OtAnesthesiaType type) => type.wireValue == value,
        orElse: () => OtAnesthesiaType.general,
      );
}

/// Patient condition recorded at post-op recovery.
enum OtPostOpCondition {
  stable('stable'),
  watch('watch'),
  critical('critical');

  const OtPostOpCondition(this.wireValue);

  final String wireValue;

  String get label => switch (this) {
    OtPostOpCondition.stable => 'Stable',
    OtPostOpCondition.watch => 'Watch',
    OtPostOpCondition.critical => 'Critical',
  };

  bool get isCritical => this == critical;

  static OtPostOpCondition fromWire(String value) =>
      OtPostOpCondition.values.firstWhere(
        (OtPostOpCondition condition) => condition.wireValue == value,
        orElse: () => OtPostOpCondition.stable,
      );
}

/// A scheduled theatre case with room allocation and conflict-checked times.
@immutable
final class OtBooking {
  const OtBooking({
    required this.id,
    required this.tenantId,
    required this.patientId,
    required this.theatreRoom,
    required this.procedureName,
    required this.scheduledStart,
    required this.scheduledEnd,
    required this.surgeonId,
    required this.status,
    required this.priority,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.encounterId,
    this.anesthesiologistId,
    this.cancellationReason,
  });

  final String id;
  final String tenantId;
  final String patientId;
  final String? encounterId;
  final String theatreRoom;
  final String procedureName;
  final DateTime scheduledStart;
  final DateTime scheduledEnd;
  final String surgeonId;
  final String? anesthesiologistId;
  final OtBookingStatus status;
  final OtPriority priority;
  final String? cancellationReason;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isScheduled => status == OtBookingStatus.scheduled;

  bool get isInProgress => status == OtBookingStatus.inProgress;

  bool get isTerminal => status.isTerminal;

  /// Whether this booking's time slot clashes with [start]–[end].
  bool overlaps(DateTime start, DateTime end) =>
      scheduledStart.isBefore(end) && start.isBefore(scheduledEnd);

  factory OtBooking.fromRow(Map<String, Object?> row) {
    final Object? encounter = row['encounter_id'];
    final Object? anesthesiologist = row['anesthesiologist_id'];
    final Object? cancellation = row['cancellation_reason'];
    return OtBooking(
      id: row['id']! as String,
      tenantId: row['tenant_id']! as String,
      patientId: row['patient_id']! as String,
      encounterId: encounter is String ? encounter : null,
      theatreRoom: row['theatre_room']! as String,
      procedureName: row['procedure_name']! as String,
      scheduledStart: row['scheduled_start']! as DateTime,
      scheduledEnd: row['scheduled_end']! as DateTime,
      surgeonId: row['surgeon_id']! as String,
      anesthesiologistId: anesthesiologist is String ? anesthesiologist : null,
      status: OtBookingStatus.fromWire(row['status']! as String),
      priority: OtPriority.fromWire(row['priority']! as String),
      cancellationReason: cancellation is String ? cancellation : null,
      createdBy: row['created_by']! as String,
      createdAt: row['created_at']! as DateTime,
      updatedAt: row['updated_at']! as DateTime,
    );
  }
}

/// A one-time pre-operative fitness assessment for a booking.
@immutable
final class OtPreOpAssessment {
  const OtPreOpAssessment({
    required this.id,
    required this.tenantId,
    required this.bookingId,
    required this.patientId,
    required this.assessedBy,
    required this.assessedAt,
    required this.fitness,
    required this.createdAt,
    required this.updatedAt,
    this.asaClass,
    this.notes,
  });

  final String id;
  final String tenantId;
  final String bookingId;
  final String patientId;
  final String assessedBy;
  final DateTime assessedAt;
  final OtFitness fitness;
  final int? asaClass;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get fitForSurgery => fitness.allowsSurgery;

  factory OtPreOpAssessment.fromRow(Map<String, Object?> row) {
    int? asInt(Object? value) => value is num ? value.toInt() : null;
    final Object? notes = row['notes'];
    return OtPreOpAssessment(
      id: row['id']! as String,
      tenantId: row['tenant_id']! as String,
      bookingId: row['booking_id']! as String,
      patientId: row['patient_id']! as String,
      assessedBy: row['assessed_by']! as String,
      assessedAt: row['assessed_at']! as DateTime,
      fitness: OtFitness.fromWire(row['fitness']! as String),
      asaClass: asInt(row['asa_class']),
      notes: notes is String ? notes : null,
      createdAt: row['created_at']! as DateTime,
      updatedAt: row['updated_at']! as DateTime,
    );
  }
}

/// The anesthetic administered for a booking, one record per case.
@immutable
final class OtAnesthesiaRecord {
  const OtAnesthesiaRecord({
    required this.id,
    required this.tenantId,
    required this.bookingId,
    required this.patientId,
    required this.anesthesiaType,
    required this.recordedBy,
    required this.startedAt,
    required this.createdAt,
    required this.updatedAt,
    this.endedAt,
    this.notes,
  });

  final String id;
  final String tenantId;
  final String bookingId;
  final String patientId;
  final OtAnesthesiaType anesthesiaType;
  final String recordedBy;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isComplete => endedAt != null;

  factory OtAnesthesiaRecord.fromRow(Map<String, Object?> row) {
    final Object? ended = row['ended_at'];
    final Object? notes = row['notes'];
    return OtAnesthesiaRecord(
      id: row['id']! as String,
      tenantId: row['tenant_id']! as String,
      bookingId: row['booking_id']! as String,
      patientId: row['patient_id']! as String,
      anesthesiaType: OtAnesthesiaType.fromWire(
        row['anesthesia_type']! as String,
      ),
      recordedBy: row['recorded_by']! as String,
      startedAt: row['started_at']! as DateTime,
      endedAt: ended is DateTime ? ended : null,
      notes: notes is String ? notes : null,
      createdAt: row['created_at']! as DateTime,
      updatedAt: row['updated_at']! as DateTime,
    );
  }
}

/// The procedure performed for a booking, one log per case.
@immutable
final class OtProcedureLog {
  const OtProcedureLog({
    required this.id,
    required this.tenantId,
    required this.bookingId,
    required this.patientId,
    required this.procedureName,
    required this.performedBy,
    required this.startedAt,
    required this.createdAt,
    required this.updatedAt,
    this.completedAt,
    this.findings,
  });

  final String id;
  final String tenantId;
  final String bookingId;
  final String patientId;
  final String procedureName;
  final String performedBy;
  final DateTime startedAt;
  final DateTime? completedAt;
  final String? findings;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isComplete => completedAt != null;

  factory OtProcedureLog.fromRow(Map<String, Object?> row) {
    final Object? completed = row['completed_at'];
    final Object? findings = row['findings'];
    return OtProcedureLog(
      id: row['id']! as String,
      tenantId: row['tenant_id']! as String,
      bookingId: row['booking_id']! as String,
      patientId: row['patient_id']! as String,
      procedureName: row['procedure_name']! as String,
      performedBy: row['performed_by']! as String,
      startedAt: row['started_at']! as DateTime,
      completedAt: completed is DateTime ? completed : null,
      findings: findings is String ? findings : null,
      createdAt: row['created_at']! as DateTime,
      updatedAt: row['updated_at']! as DateTime,
    );
  }
}

/// The post-operative recovery state recorded for a booking.
@immutable
final class OtPostOpRecord {
  const OtPostOpRecord({
    required this.id,
    required this.tenantId,
    required this.bookingId,
    required this.patientId,
    required this.recordedBy,
    required this.recordedAt,
    required this.condition,
    required this.createdAt,
    required this.updatedAt,
    this.painScore,
    this.complications,
    this.notes,
  });

  final String id;
  final String tenantId;
  final String bookingId;
  final String patientId;
  final String recordedBy;
  final DateTime recordedAt;
  final OtPostOpCondition condition;
  final int? painScore;
  final String? complications;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isCritical => condition.isCritical;

  factory OtPostOpRecord.fromRow(Map<String, Object?> row) {
    int? asInt(Object? value) => value is num ? value.toInt() : null;
    final Object? complications = row['complications'];
    final Object? notes = row['notes'];
    return OtPostOpRecord(
      id: row['id']! as String,
      tenantId: row['tenant_id']! as String,
      bookingId: row['booking_id']! as String,
      patientId: row['patient_id']! as String,
      recordedBy: row['recorded_by']! as String,
      recordedAt: row['recorded_at']! as DateTime,
      condition: OtPostOpCondition.fromWire(row['condition']! as String),
      painScore: asInt(row['pain_score']),
      complications: complications is String ? complications : null,
      notes: notes is String ? notes : null,
      createdAt: row['created_at']! as DateTime,
      updatedAt: row['updated_at']! as DateTime,
    );
  }
}
