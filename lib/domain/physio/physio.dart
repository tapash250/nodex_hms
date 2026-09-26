/// Physiotherapy & rehabilitation entities (Module 20).
///
/// Session flow: schedule -> start -> complete, or cancel with a reason.
/// Exercise regimens are prescribed per patient, and recovery notes document
/// progress against a session while it runs or after it finishes.
// ignore_for_file: sort_constructors_first
library;

import 'package:meta/meta.dart';

/// Purpose of a physiotherapy session.
enum PhysioSessionType {
  assessment('assessment'),
  therapy('therapy'),
  reassessment('reassessment');

  const PhysioSessionType(this.wireValue);

  final String wireValue;

  String get label => switch (this) {
    PhysioSessionType.assessment => 'Assessment',
    PhysioSessionType.therapy => 'Therapy',
    PhysioSessionType.reassessment => 'Reassessment',
  };

  static PhysioSessionType fromWire(String value) =>
      PhysioSessionType.values.firstWhere(
        (PhysioSessionType type) => type.wireValue == value,
        orElse: () => PhysioSessionType.therapy,
      );
}

/// Lifecycle of a physiotherapy session.
enum PhysioSessionStatus {
  scheduled('scheduled'),
  inProgress('in_progress'),
  completed('completed'),
  cancelled('cancelled');

  const PhysioSessionStatus(this.wireValue);

  final String wireValue;

  String get label => switch (this) {
    PhysioSessionStatus.scheduled => 'Scheduled',
    PhysioSessionStatus.inProgress => 'In progress',
    PhysioSessionStatus.completed => 'Completed',
    PhysioSessionStatus.cancelled => 'Cancelled',
  };

  bool get isTerminal => this == completed || this == cancelled;

  bool get isScheduled => this == scheduled;

  bool get isRunning => this == inProgress;

  bool get isCompleted => this == completed;

  static PhysioSessionStatus fromWire(String value) =>
      PhysioSessionStatus.values.firstWhere(
        (PhysioSessionStatus status) => status.wireValue == value,
        orElse: () => PhysioSessionStatus.scheduled,
      );
}

/// Lifecycle of a prescribed exercise regimen.
enum PhysioPlanStatus {
  active('active'),
  completed('completed'),
  stopped('stopped');

  const PhysioPlanStatus(this.wireValue);

  final String wireValue;

  String get label => switch (this) {
    PhysioPlanStatus.active => 'Active',
    PhysioPlanStatus.completed => 'Completed',
    PhysioPlanStatus.stopped => 'Stopped',
  };

  bool get isTerminal => this != active;

  bool get isActive => this == active;

  static PhysioPlanStatus fromWire(String value) =>
      PhysioPlanStatus.values.firstWhere(
        (PhysioPlanStatus status) => status.wireValue == value,
        orElse: () => PhysioPlanStatus.active,
      );
}

/// A scheduled physiotherapy session with its lifecycle timestamps.
@immutable
final class PhysioSession {
  const PhysioSession({
    required this.id,
    required this.tenantId,
    required this.patientId,
    required this.physiotherapistId,
    required this.sessionCode,
    required this.sessionType,
    required this.bodyArea,
    required this.status,
    required this.scheduledAt,
    required this.createdAt,
    required this.updatedAt,
    this.encounterId,
    this.startedAt,
    this.completedAt,
    this.cancelledAt,
    this.cancellationReason,
    this.equipmentUsed,
  });

  factory PhysioSession.fromRow(Map<String, Object?> row) {
    final Object? encounter = row['encounter_id'];
    final Object? startedAt = row['started_at'];
    final Object? completedAt = row['completed_at'];
    final Object? cancelledAt = row['cancelled_at'];
    final Object? cancellationReason = row['cancellation_reason'];
    final Object? equipmentUsed = row['equipment_used'];
    return PhysioSession(
      id: row['id']! as String,
      tenantId: row['tenant_id']! as String,
      patientId: row['patient_id']! as String,
      encounterId: encounter is String ? encounter : null,
      physiotherapistId: row['physiotherapist_id']! as String,
      sessionCode: row['session_code']! as String,
      sessionType: PhysioSessionType.fromWire(row['session_type']! as String),
      bodyArea: row['body_area']! as String,
      status: PhysioSessionStatus.fromWire(row['status']! as String),
      scheduledAt: row['scheduled_at']! as DateTime,
      startedAt: startedAt is DateTime ? startedAt : null,
      completedAt: completedAt is DateTime ? completedAt : null,
      cancelledAt: cancelledAt is DateTime ? cancelledAt : null,
      cancellationReason: cancellationReason is String
          ? cancellationReason
          : null,
      equipmentUsed: equipmentUsed is String ? equipmentUsed : null,
      createdAt: row['created_at']! as DateTime,
      updatedAt: row['updated_at']! as DateTime,
    );
  }

  final String id;
  final String tenantId;
  final String patientId;
  final String? encounterId;
  final String physiotherapistId;
  final String sessionCode;
  final PhysioSessionType sessionType;
  final String bodyArea;
  final PhysioSessionStatus status;
  final DateTime scheduledAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime? cancelledAt;
  final String? cancellationReason;
  final String? equipmentUsed;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isTerminal => status.isTerminal;

  bool get isScheduled => status.isScheduled;

  bool get isRunning => status.isRunning;
}

/// A prescribed physiotherapy exercise regimen.
@immutable
final class PhysioExercisePlan {
  const PhysioExercisePlan({
    required this.id,
    required this.tenantId,
    required this.patientId,
    required this.prescribedBy,
    required this.exerciseName,
    required this.setsCount,
    required this.repsCount,
    required this.frequencyPerWeek,
    required this.durationWeeks,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.sessionId,
    this.instructions,
  });

  factory PhysioExercisePlan.fromRow(Map<String, Object?> row) {
    final Object? sessionId = row['session_id'];
    final Object? instructions = row['instructions'];
    return PhysioExercisePlan(
      id: row['id']! as String,
      tenantId: row['tenant_id']! as String,
      patientId: row['patient_id']! as String,
      sessionId: sessionId is String ? sessionId : null,
      prescribedBy: row['prescribed_by']! as String,
      exerciseName: row['exercise_name']! as String,
      setsCount: (row['sets_count']! as num).toInt(),
      repsCount: (row['reps_count']! as num).toInt(),
      frequencyPerWeek: (row['frequency_per_week']! as num).toInt(),
      durationWeeks: (row['duration_weeks']! as num).toInt(),
      instructions: instructions is String ? instructions : null,
      status: PhysioPlanStatus.fromWire(row['status']! as String),
      createdAt: row['created_at']! as DateTime,
      updatedAt: row['updated_at']! as DateTime,
    );
  }

  final String id;
  final String tenantId;
  final String patientId;
  final String? sessionId;
  final String prescribedBy;
  final String exerciseName;
  final int setsCount;
  final int repsCount;
  final int frequencyPerWeek;
  final int durationWeeks;
  final String? instructions;
  final PhysioPlanStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isActive => status.isActive;

  bool get isFinished => status.isTerminal;
}

/// A recovery or progress note recorded against a session.
@immutable
final class PhysioRecoveryNote {
  const PhysioRecoveryNote({
    required this.id,
    required this.tenantId,
    required this.sessionId,
    required this.recordedBy,
    required this.content,
    required this.recordedAt,
    required this.createdAt,
    required this.updatedAt,
    this.painScore,
  });

  factory PhysioRecoveryNote.fromRow(Map<String, Object?> row) {
    final Object? painScore = row['pain_score'];
    return PhysioRecoveryNote(
      id: row['id']! as String,
      tenantId: row['tenant_id']! as String,
      sessionId: row['session_id']! as String,
      recordedBy: row['recorded_by']! as String,
      content: row['content']! as String,
      painScore: painScore is num ? painScore.toInt() : null,
      recordedAt: row['recorded_at']! as DateTime,
      createdAt: row['created_at']! as DateTime,
      updatedAt: row['updated_at']! as DateTime,
    );
  }

  final String id;
  final String tenantId;
  final String sessionId;
  final String recordedBy;
  final String content;
  final int? painScore;
  final DateTime recordedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
}
