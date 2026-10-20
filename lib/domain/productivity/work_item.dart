/// Working boards, scratchpads and service requests (Module 44).
///
/// The tools that sit between the clinical modules: a board of work a team
/// moves across lanes, a private scratchpad that never leaves the device, and
/// a ticket to the people who keep the building running.
// ignore_for_file: sort_constructors_first
library;

import 'package:meta/meta.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';

/// A lane of a working board.
enum WorkLane {
  /// Not started.
  todo('todo', 'To do'),

  /// Being worked on.
  doing('doing', 'Doing'),

  /// Waiting on something else.
  blocked('blocked', 'Blocked'),

  /// Finished.
  done('done', 'Done');

  const WorkLane(this.wireValue, this.label);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  final String label;

  /// The lane in reading order.
  int get order => WorkLane.values.indexOf(this);

  /// Parses a stored value.
  static WorkLane fromWire(String value) => WorkLane.values.firstWhere(
    (WorkLane lane) => lane.wireValue == value,
    orElse: () => WorkLane.todo,
  );
}

/// How urgent a card is.
enum WorkPriority {
  /// Whenever it can be done.
  low('low'),

  /// The default.
  medium('medium'),

  /// Needed before the next round.
  high('high');

  const WorkPriority(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Parses a stored value.
  static WorkPriority fromWire(String value) => WorkPriority.values.firstWhere(
    (WorkPriority priority) => priority.wireValue == value,
    orElse: () => WorkPriority.medium,
  );
}

/// A card on a working board.
@immutable
final class WorkItem {
  /// Creates a card.
  const WorkItem({
    required this.id,
    required this.tenantId,
    required this.boardKey,
    required this.title,
    required this.lane,
    required this.priority,
    required this.createdBy,
    this.detail,
    this.position = 0,
    this.patientId,
    this.wardId,
    this.departmentId,
    this.assignedTo,
    this.dueAt,
    this.completedAt,
    this.createdAt,
  });

  /// Validates and builds a new card row.
  static Map<String, Object?> raiseRow({
    required String tenantId,
    required String boardKey,
    required String title,
    required String createdBy,
    String? detail,
    WorkPriority priority = WorkPriority.medium,
    String? patientId,
    String? wardId,
    String? departmentId,
    String? assignedTo,
    String? dueAt,
    int position = 0,
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.trim().isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (boardKey.trim().isEmpty) {
      fieldErrors['board_key'] = 'Say which board the card belongs to.';
    }
    if (title.trim().isEmpty) {
      fieldErrors['title'] = 'Say what needs doing.';
    }
    if (createdBy.trim().isEmpty) {
      fieldErrors['created_by'] = 'The author is required.';
    }
    if (dueAt != null && DateTime.tryParse(dueAt) == null) {
      fieldErrors['due_at'] = 'Expected an ISO-8601 timestamp.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Adding a card to the board failed validation.',
        fieldErrors: fieldErrors,
        code: 'work_item_invalid',
      );
    }
    final String now = DateTime.now().toUtc().toIso8601String();
    return <String, Object?>{
      'tenant_id': tenantId,
      'board_key': boardKey.trim(),
      'title': title.trim(),
      'detail': detail?.trim().isEmpty ?? true ? null : detail!.trim(),
      'lane': WorkLane.todo.wireValue,
      'position': position,
      'priority': priority.wireValue,
      'patient_id': patientId,
      'ward_id': wardId,
      'department_id': departmentId,
      'created_by': createdBy,
      'assigned_to': assignedTo,
      'due_at': dueAt,
      'completed_at': null,
      'created_at': now,
      'updated_at': now,
    };
  }

  /// The changes that move a card to another lane.
  ///
  /// A card that has been done does not go back to the board: the work did not
  /// become unfinished, and a card that is quietly reopened is a card nobody
  /// is watching any more.
  static Map<String, Object?>? moveChanges({
    required WorkLane from,
    required WorkLane to,
  }) {
    if (from == to) return null;
    if (from == WorkLane.done) {
      throw const ValidationError(
        message: 'A completed card does not go back to the board.',
        fieldErrors: <String, String>{'lane': 'Raise a new card instead.'},
        code: 'work_item_completed',
      );
    }
    return <String, Object?>{'lane': to.wireValue};
  }

  /// Reads a card from a local row.
  factory WorkItem.fromRow(Map<String, Object?> row) => WorkItem(
    id: row['id']! as String,
    tenantId: row['tenant_id']! as String,
    boardKey: row['board_key']! as String,
    title: row['title']! as String,
    detail: row['detail'] as String?,
    lane: WorkLane.fromWire(row['lane']! as String),
    position: (row['position'] as int?) ?? 0,
    priority: WorkPriority.fromWire(row['priority']! as String),
    patientId: row['patient_id'] as String?,
    wardId: row['ward_id'] as String?,
    departmentId: row['department_id'] as String?,
    createdBy: row['created_by']! as String,
    assignedTo: row['assigned_to'] as String?,
    dueAt: _parse(row['due_at']),
    completedAt: _parse(row['completed_at']),
    createdAt: _parse(row['created_at']),
  );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// The board the card sits on.
  final String boardKey;

  /// What needs doing.
  final String title;

  /// The detail of the request.
  final String? detail;

  /// The lane the card is in.
  final WorkLane lane;

  /// Where the card sits within its lane.
  final int position;

  /// How urgent it is.
  final WorkPriority priority;

  /// The patient the card concerns, when it concerns one.
  final String? patientId;

  /// The ward the card belongs to.
  final String? wardId;

  /// The department the card belongs to.
  final String? departmentId;

  /// The author.
  final String createdBy;

  /// The person the card is with.
  final String? assignedTo;

  /// When it is needed.
  final DateTime? dueAt;

  /// When it was finished.
  final DateTime? completedAt;

  /// When it was raised.
  final DateTime? createdAt;

  /// Whether the card is past its due time at [now].
  bool isOverdueAt(DateTime now) =>
      lane != WorkLane.done && dueAt != null && dueAt!.isBefore(now);
}

/// A service request to the hospital IT team.
@immutable
final class ItTicket {
  /// Creates a ticket.
  const ItTicket({
    required this.id,
    required this.tenantId,
    required this.ticketCode,
    required this.title,
    required this.category,
    required this.priority,
    required this.status,
    required this.reportedBy,
    this.detail,
    this.assignedTo,
    this.resolutionNote,
    this.openedAt,
    this.closedAt,
  });

  /// Validates and builds a new ticket row.
  static Map<String, Object?> raiseRow({
    required String tenantId,
    required String ticketCode,
    required String title,
    required String reportedBy,
    String? detail,
    String category = 'general',
    String priority = 'medium',
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.trim().isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (ticketCode.trim().isEmpty) {
      fieldErrors['ticket_code'] = 'A ticket code is required.';
    }
    if (title.trim().isEmpty) {
      fieldErrors['title'] = 'Say what is wrong.';
    }
    if (reportedBy.trim().isEmpty) {
      fieldErrors['reported_by'] = 'The reporter is required.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Raising a ticket failed validation.',
        fieldErrors: fieldErrors,
        code: 'it_ticket_invalid',
      );
    }
    final String now = DateTime.now().toUtc().toIso8601String();
    return <String, Object?>{
      'tenant_id': tenantId,
      'ticket_code': ticketCode.trim(),
      'title': title.trim(),
      'detail': detail?.trim().isEmpty ?? true ? null : detail!.trim(),
      'category': category,
      'priority': priority,
      'status': 'open',
      'reported_by': reportedBy,
      'assigned_to': null,
      'resolution_note': null,
      'opened_at': now,
      'closed_at': null,
      'created_at': now,
      'updated_at': now,
    };
  }

  /// The changes that resolve a ticket, with the note that says what was done.
  static Map<String, Object?> resolveChanges({required String note}) {
    if (note.trim().isEmpty) {
      throw const ValidationError(
        message: 'Say what was done before closing the ticket.',
        fieldErrors: <String, String>{'resolution_note': 'A note is required.'},
        code: 'it_ticket_resolution_required',
      );
    }
    return <String, Object?>{
      'status': 'resolved',
      'resolution_note': note.trim(),
    };
  }

  /// Reads a ticket from a local row.
  factory ItTicket.fromRow(Map<String, Object?> row) => ItTicket(
    id: row['id']! as String,
    tenantId: row['tenant_id']! as String,
    ticketCode: row['ticket_code']! as String,
    title: row['title']! as String,
    detail: row['detail'] as String?,
    category: row['category']! as String,
    priority: row['priority']! as String,
    status: row['status']! as String,
    reportedBy: row['reported_by']! as String,
    assignedTo: row['assigned_to'] as String?,
    resolutionNote: row['resolution_note'] as String?,
    openedAt: _parse(row['opened_at']),
    closedAt: _parse(row['closed_at']),
  );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// The code the ticket is referred to by.
  final String ticketCode;

  /// What is wrong.
  final String title;

  /// The detail of the report.
  final String? detail;

  /// The kind of problem.
  final String category;

  /// How urgent it is.
  final String priority;

  /// Where the ticket stands.
  final String status;

  /// The person who raised it.
  final String reportedBy;

  /// The person working on it.
  final String? assignedTo;

  /// What was done, stated at resolution.
  final String? resolutionNote;

  /// When it was raised.
  final DateTime? openedAt;

  /// When it was closed.
  final DateTime? closedAt;

  /// Whether the ticket is finished.
  bool get isClosed => status == 'resolved' || status == 'closed';
}

DateTime? _parse(Object? value) =>
    value == null ? null : DateTime.parse(value as String);
