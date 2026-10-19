/// Cross-department task entities (Module 41).
///
/// A hospital task is a request one part of the hospital makes of another:
/// carry this specimen, clean this bay, remind this nurse, run this STAT
/// errand. The request is a record, so its substance never changes after it was
/// raised; what changes is who owns it and whether it finished.
// ignore_for_file: sort_constructors_first
library;

import 'package:meta/meta.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';

/// The kind of errand a task describes.
enum TaskCategory {
  /// Move a specimen from where it was taken to where it is analysed.
  specimenTransport('specimen_transport'),

  /// Clean and prepare a bay, theatre or equipment between uses.
  sanitization('sanitization'),

  /// A reminder to a named nurse about a patient.
  nursingReminder('nursing_reminder'),

  /// An urgent clinical errand, usually with a clock on it.
  statErrand('stat_errand'),

  /// Fetch equipment that lives elsewhere in the building.
  equipmentRetrieval('equipment_retrieval'),

  /// Move notes, consent forms or results between desks.
  documentDelivery('document_delivery'),

  /// Anything the ladder does not name.
  other('other');

  const TaskCategory(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    TaskCategory.specimenTransport => 'Specimen transport',
    TaskCategory.sanitization => 'Sanitization',
    TaskCategory.nursingReminder => 'Nursing reminder',
    TaskCategory.statErrand => 'STAT errand',
    TaskCategory.equipmentRetrieval => 'Equipment retrieval',
    TaskCategory.documentDelivery => 'Document delivery',
    TaskCategory.other => 'Other',
  };

  /// Parses a stored value.
  static TaskCategory fromWire(String value) => TaskCategory.values.firstWhere(
    (TaskCategory category) => category.wireValue == value,
    orElse: () => TaskCategory.other,
  );
}

/// How soon a task is needed.
///
/// The ladder is ordered: a task may be raised urgent later, but never lowered
/// back to routine because the assignee is busy. A STAT errand that cannot be
/// run is cancelled with a reason, which is a clinical statement, rather than
/// quietly de-escalated.
enum TaskPriority {
  /// Whenever somebody is free.
  low('low', 1),

  /// The default.
  medium('medium', 2),

  /// Needs attention before the next routine round.
  urgent('urgent', 3),

  /// Needed now.
  stat('stat', 4);

  const TaskPriority(this.wireValue, this.weight);

  /// Stored value.
  final String wireValue;

  /// Ordering of the ladder; higher means more urgent.
  final int weight;

  /// Human-readable label.
  String get label => switch (this) {
    TaskPriority.low => 'Low',
    TaskPriority.medium => 'Medium',
    TaskPriority.urgent => 'Urgent',
    TaskPriority.stat => 'STAT',
  };

  /// Whether this priority is at least as urgent as [other].
  bool isAtLeast(TaskPriority other) => weight >= other.weight;

  /// Parses a stored value.
  static TaskPriority fromWire(String value) => TaskPriority.values.firstWhere(
    (TaskPriority priority) => priority.wireValue == value,
    orElse: () => TaskPriority.medium,
  );
}

/// Where a task stands.
enum TaskStatus {
  /// Raised, nobody owns it yet.
  open('open'),

  /// Somebody picked it up.
  claimed('claimed'),

  /// Work has started.
  inProgress('in_progress'),

  /// Finished, with a note saying what was done.
  completed('completed'),

  /// Abandoned, with a reason.
  cancelled('cancelled');

  const TaskStatus(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    TaskStatus.open => 'Open',
    TaskStatus.claimed => 'Claimed',
    TaskStatus.inProgress => 'In progress',
    TaskStatus.completed => 'Completed',
    TaskStatus.cancelled => 'Cancelled',
  };

  /// Whether the task is finished in any sense.
  bool get isTerminal =>
      this == TaskStatus.completed || this == TaskStatus.cancelled;

  /// Whether the task still needs work.
  bool get isLive => !isTerminal;

  /// Whether this status can be reached from [from].
  bool isReachableFrom(TaskStatus from) => switch (this) {
    TaskStatus.open => false,
    TaskStatus.claimed => from == TaskStatus.open,
    TaskStatus.inProgress => from == TaskStatus.claimed,
    TaskStatus.completed =>
      from == TaskStatus.claimed || from == TaskStatus.inProgress,
    TaskStatus.cancelled => from.isLive,
  };

  /// Parses a stored value.
  static TaskStatus fromWire(String value) => TaskStatus.values.firstWhere(
    (TaskStatus status) => status.wireValue == value,
    orElse: () => TaskStatus.open,
  );
}

/// A hospital task as the device holds it.
@immutable
final class HospitalTask {
  /// Creates a task.
  const HospitalTask({
    required this.id,
    required this.tenantId,
    required this.taskCode,
    required this.title,
    required this.category,
    required this.priority,
    required this.status,
    required this.requestedBy,
    this.detail,
    this.patientId,
    this.encounterId,
    this.fromLocation,
    this.toLocation,
    this.dueAt,
    this.assignedTo,
    this.claimedAt,
    this.startedAt,
    this.completedBy,
    this.completedAt,
    this.completionNote,
    this.cancellationReason,
    this.createdAt,
    this.updatedAt,
  });

  /// Validates and builds a new task row.
  ///
  /// A task is raised open and unowned: assignment happens when somebody
  /// claims it, which is what makes the claim a fact rather than an intention.
  static Map<String, Object?> raiseRow({
    required String tenantId,
    required String taskCode,
    required String title,
    required String requestedBy,
    TaskCategory category = TaskCategory.other,
    TaskPriority priority = TaskPriority.medium,
    String? detail,
    String? patientId,
    String? encounterId,
    String? fromLocation,
    String? toLocation,
    String? dueAt,
    String taskId = '',
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.trim().isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (taskCode.trim().isEmpty) {
      fieldErrors['task_code'] = 'A task code is required.';
    }
    if (title.trim().isEmpty) {
      fieldErrors['title'] = 'Say what needs doing.';
    }
    if (requestedBy.trim().isEmpty) {
      fieldErrors['requested_by'] = 'The requester is required.';
    }
    if (dueAt != null && DateTime.tryParse(dueAt) == null) {
      fieldErrors['due_at'] = 'Expected an ISO-8601 timestamp.';
    }
    // A transport or retrieval that does not say where it is going cannot be
    // run by anybody who was not standing there when it was raised.
    if ((category == TaskCategory.specimenTransport ||
            category == TaskCategory.equipmentRetrieval ||
            category == TaskCategory.documentDelivery) &&
        (toLocation == null || toLocation.trim().isEmpty)) {
      fieldErrors['to_location'] = 'Say where the errand ends.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Raising a hospital task failed validation.',
        fieldErrors: fieldErrors,
        code: 'hospital_task_invalid',
      );
    }

    final String now = DateTime.now().toUtc().toIso8601String();
    return <String, Object?>{
      if (taskId.isNotEmpty) 'id': taskId,
      'tenant_id': tenantId,
      'task_code': taskCode.trim(),
      'title': title.trim(),
      'detail': _trimmed(detail),
      'category': category.wireValue,
      'priority': priority.wireValue,
      'status': TaskStatus.open.wireValue,
      'patient_id': patientId,
      'encounter_id': encounterId,
      'from_location': _trimmed(fromLocation),
      'to_location': _trimmed(toLocation),
      'requested_by': requestedBy,
      'assigned_to': null,
      'due_at': dueAt,
      'claimed_at': null,
      'started_at': null,
      'completed_by': null,
      'completed_at': null,
      'completion_note': null,
      'cancellation_reason': null,
      'created_at': now,
      'updated_at': now,
    };
  }

  /// Materializes a task from a local row.
  factory HospitalTask.fromRow(Map<String, Object?> row) => HospitalTask(
    id: row['id']! as String,
    tenantId: row['tenant_id']! as String,
    taskCode: row['task_code']! as String,
    title: row['title']! as String,
    category: TaskCategory.fromWire(row['category']! as String),
    priority: TaskPriority.fromWire(row['priority']! as String),
    status: TaskStatus.fromWire(row['status']! as String),
    requestedBy: row['requested_by']! as String,
    detail: row['detail'] as String?,
    patientId: row['patient_id'] as String?,
    encounterId: row['encounter_id'] as String?,
    fromLocation: row['from_location'] as String?,
    toLocation: row['to_location'] as String?,
    dueAt: _parse(row['due_at']),
    assignedTo: row['assigned_to'] as String?,
    claimedAt: _parse(row['claimed_at']),
    startedAt: _parse(row['started_at']),
    completedBy: row['completed_by'] as String?,
    completedAt: _parse(row['completed_at']),
    completionNote: row['completion_note'] as String?,
    cancellationReason: row['cancellation_reason'] as String?,
    createdAt: _parse(row['created_at']),
    updatedAt: _parse(row['updated_at']),
  );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// Human-facing code, unique per tenant.
  final String taskCode;

  /// What needs doing.
  final String title;

  /// Kind of errand.
  final TaskCategory category;

  /// How soon it is needed.
  final TaskPriority priority;

  /// Where the task stands.
  final TaskStatus status;

  /// The user who asked for it.
  final String requestedBy;

  /// Detail or instructions.
  final String? detail;

  /// The patient, when the errand concerns one.
  final String? patientId;

  /// The linked encounter, when any.
  final String? encounterId;

  /// Where the errand starts.
  final String? fromLocation;

  /// Where the errand ends.
  final String? toLocation;

  /// When it is needed.
  final DateTime? dueAt;

  /// The user who owns it, set by the claim.
  final String? assignedTo;

  /// When it was claimed.
  final DateTime? claimedAt;

  /// When work started.
  final DateTime? startedAt;

  /// The user who closed it.
  final String? completedBy;

  /// When it was closed.
  final DateTime? completedAt;

  /// What was done, stated at completion.
  final String? completionNote;

  /// Why it was abandoned, stated at cancellation.
  final String? cancellationReason;

  /// When it was raised.
  final DateTime? createdAt;

  /// When it last changed.
  final DateTime? updatedAt;

  /// Whether the task is past due at [now].
  bool isOverdueAt(DateTime now) =>
      status.isLive && dueAt != null && dueAt!.isBefore(now);

  /// Whether [user] may close the task.
  ///
  /// The claimer closes their own errand; the requester may always cancel, and
  /// an unclaimed task can be cancelled by anyone who can manage tasks, which
  /// the policy layer has already established.
  bool isClosableBy(String user) =>
      status.isLive && (assignedTo == null || assignedTo == user);

  /// The changes that claim the task for [user].
  static Map<String, Object?> claimChanges({required String user}) =>
      <String, Object?>{
        'status': TaskStatus.claimed.wireValue,
        'assigned_to': user,
      };

  /// The changes that start work.
  static Map<String, Object?> startChanges() => <String, Object?>{
    'status': TaskStatus.inProgress.wireValue,
  };

  /// The changes that complete the task, with the note that says what was done.
  static Map<String, Object?> completeChanges({
    required String completedBy,
    required String note,
  }) {
    if (note.trim().isEmpty) {
      throw const ValidationError(
        message: 'Say what was done before completing the task.',
        fieldErrors: <String, String>{'completion_note': 'A note is required.'},
        code: 'task_completion_note_required',
      );
    }
    return <String, Object?>{
      'status': TaskStatus.completed.wireValue,
      'completed_by': completedBy,
      'completion_note': note.trim(),
    };
  }

  /// The changes that cancel the task, with the reason it was abandoned.
  static Map<String, Object?> cancelChanges({required String reason}) {
    if (reason.trim().isEmpty) {
      throw const ValidationError(
        message: 'Say why the task is being cancelled.',
        fieldErrors: <String, String>{
          'cancellation_reason':
              'A reason is '
              'required.',
        },
        code: 'task_cancellation_reason_required',
      );
    }
    return <String, Object?>{
      'status': TaskStatus.cancelled.wireValue,
      'cancellation_reason': reason.trim(),
    };
  }

  /// The changes that raise the priority, refusing a downgrade.
  ///
  /// Returns null when nothing would change, so a screen can skip the write.
  static Map<String, Object?>? reprioritise({
    required TaskPriority from,
    required TaskPriority to,
  }) {
    if (to == from) return null;
    if (!to.isAtLeast(from)) {
      throw const ValidationError(
        message: 'A task priority can be raised but never lowered.',
        fieldErrors: <String, String>{
          'priority': 'Cancel the task with a reason instead.',
        },
        code: 'task_priority_downgrade_refused',
      );
    }
    return <String, Object?>{'priority': to.wireValue};
  }

  /// The transitions offered from the current status.
  List<TaskStatus> get availableTransitions => TaskStatus.values
      .where((TaskStatus status) => status.isReachableFrom(this.status))
      .toList(growable: false);
}

String? _trimmed(String? value) {
  final String? trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

DateTime? _parse(Object? value) =>
    value == null ? null : DateTime.parse(value as String);
