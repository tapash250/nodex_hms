/// Productivity use cases (Module 44).
library;

import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/productivity/productivity_repository.dart';
import 'package:nodex_hms/domain/productivity/work_item.dart';

/// Reads a working board.
final class ReadBoardUseCase {
  /// Creates the use case.
  const ReadBoardUseCase({required this._repository});

  final ProductivityRepository _repository;

  /// Reads the cards on the board.
  Future<List<WorkItem>> call({
    required AuthorizationPolicy policy,
    required String boardKey,
  }) async {
    policy.require(NodexPermissions.workItemsRead);
    return _repository.listBoard(boardKey);
  }
}

/// Adds a card to a board.
final class RaiseWorkItemUseCase {
  /// Creates the use case.
  const RaiseWorkItemUseCase({required this._repository});

  final ProductivityRepository _repository;

  /// Adds the card.
  Future<String> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String boardKey,
    required String title,
    required String createdBy,
    String? detail,
    WorkPriority priority = WorkPriority.medium,
    String? patientId,
    String? wardId,
    String? departmentId,
    String? dueAt,
  }) async {
    policy.require(NodexPermissions.workItemsManage);
    return _repository.addWorkItem(
      WorkItem.raiseRow(
        tenantId: tenantId,
        boardKey: boardKey,
        title: title,
        createdBy: createdBy,
        detail: detail,
        priority: priority,
        patientId: patientId,
        wardId: wardId,
        departmentId: departmentId,
        dueAt: dueAt,
      ),
    );
  }
}

/// Moves a card between lanes.
final class MoveWorkItemUseCase {
  /// Creates the use case.
  const MoveWorkItemUseCase({required this._repository});

  final ProductivityRepository _repository;

  /// Moves the card.
  Future<void> call({
    required AuthorizationPolicy policy,
    required WorkItem item,
    required WorkLane lane,
  }) async {
    policy.require(NodexPermissions.workItemsManage);
    final Map<String, Object?>? changes = WorkItem.moveChanges(
      from: item.lane,
      to: lane,
    );
    if (changes == null) return;
    await _repository.moveWorkItem(item.id, changes);
  }
}

/// Reads the service requests.
final class ReadTicketsUseCase {
  /// Creates the use case.
  const ReadTicketsUseCase({required this._repository});

  final ProductivityRepository _repository;

  /// Reads the tickets.
  Future<List<ItTicket>> call({required AuthorizationPolicy policy}) async {
    policy.require(NodexPermissions.ticketsRead);
    return _repository.listTickets();
  }
}

/// Opens a service request.
final class RaiseTicketUseCase {
  /// Creates the use case.
  const RaiseTicketUseCase({required this._repository});

  final ProductivityRepository _repository;

  /// Opens the ticket.
  Future<String> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String ticketCode,
    required String title,
    required String reportedBy,
    String? detail,
    String category = 'general',
    String priority = 'medium',
  }) async {
    policy.require(NodexPermissions.ticketsSubmit);
    return _repository.addTicket(
      ItTicket.raiseRow(
        tenantId: tenantId,
        ticketCode: ticketCode,
        title: title,
        reportedBy: reportedBy,
        detail: detail,
        category: category,
        priority: priority,
      ),
    );
  }
}

/// Resolves a service request.
final class ResolveTicketUseCase {
  /// Creates the use case.
  const ResolveTicketUseCase({required this._repository});

  final ProductivityRepository _repository;

  /// Closes the ticket with the note that says what was done.
  Future<void> call({
    required AuthorizationPolicy policy,
    required ItTicket ticket,
    required String note,
  }) async {
    policy.require(NodexPermissions.ticketsManage);
    if (ticket.isClosed) {
      throw const ValidationError(
        message: 'This ticket is already closed.',
        fieldErrors: <String, String>{'status': 'Nothing left to close.'},
        code: 'it_ticket_closed',
      );
    }
    await _repository.updateTicket(
      ticket.id,
      ItTicket.resolveChanges(note: note),
    );
  }
}

/// Reads the clinician's own notes.
final class ReadScratchpadUseCase {
  /// Creates the use case.
  const ReadScratchpadUseCase({required this._repository});

  final ProductivityRepository _repository;

  /// Reads the notes.
  ///
  /// The scratchpad holds nothing but the clinician's own words on the
  /// device, so there is nothing here to be permitted beyond being signed in.
  Future<String?> call() async => _repository.readScratchpad();
}

/// Writes the clinician's own notes.
final class WriteScratchpadUseCase {
  /// Creates the use case.
  const WriteScratchpadUseCase({required this._repository});

  final ProductivityRepository _repository;

  /// Writes the notes.
  Future<void> call({required String note}) =>
      _repository.writeScratchpad(note);
}
