/// Productivity repository (Module 44).
library;

import 'package:nodex_hms/core/errors/error_mapper.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';
import 'package:nodex_hms/domain/productivity/work_item.dart';
import 'package:uuid/uuid.dart';

/// Repository operations for boards, scratchpads and service requests.
abstract interface class ProductivityRepository {
  /// The cards on a board, lane by lane.
  Future<List<WorkItem>> listBoard(String boardKey);

  /// Adds a card.
  Future<String> addWorkItem(Map<String, Object?> row);

  /// Moves a card.
  Future<void> moveWorkItem(String id, Map<String, Object?> changes);

  /// The service requests.
  Future<List<ItTicket>> listTickets();

  /// Opens a service request.
  Future<String> addTicket(Map<String, Object?> row);

  /// Works on a service request.
  Future<void> updateTicket(String id, Map<String, Object?> changes);

  /// The clinician's own notes, which never leave the device.
  Future<String?> readScratchpad();

  /// Writes the clinician's own notes.
  Future<void> writeScratchpad(String note);
}

/// PowerSync-backed productivity repository.
final class DefaultProductivityRepository implements ProductivityRepository {
  /// Creates a repository over a local store.
  DefaultProductivityRepository({required this._store, required this._logger});

  static const String _module = 'domain.productivity';

  final PatientLocalStore _store;
  final NodexLogger _logger;

  @override
  Future<List<WorkItem>> listBoard(String boardKey) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'SELECT * FROM ${LocalTables.workItems} WHERE board_key = ? '
        'ORDER BY position',
        <Object?>[boardKey],
      );
      return rows.map(WorkItem.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'productivity.board');
    }
  }

  @override
  Future<String> addWorkItem(Map<String, Object?> row) async {
    final String id = const Uuid().v4();
    try {
      await _store.insert(LocalTables.workItems, <String, Object?>{
        ...row,
        'id': id,
      });
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'productivity.addCard');
    }
  }

  @override
  Future<void> moveWorkItem(String id, Map<String, Object?> changes) async {
    try {
      await _store.update(LocalTables.workItems, id, changes);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'productivity.moveCard');
    }
  }

  @override
  Future<List<ItTicket>> listTickets() async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'SELECT * FROM ${LocalTables.itTickets} ORDER BY opened_at DESC',
        const <Object?>[],
      );
      return rows.map(ItTicket.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'productivity.tickets');
    }
  }

  @override
  Future<String> addTicket(Map<String, Object?> row) async {
    final String id = const Uuid().v4();
    try {
      await _store.insert(LocalTables.itTickets, <String, Object?>{
        ...row,
        'id': id,
      });
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'productivity.addTicket');
    }
  }

  @override
  Future<void> updateTicket(String id, Map<String, Object?> changes) async {
    try {
      await _store.update(LocalTables.itTickets, id, changes);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'productivity.updateTicket');
    }
  }

  @override
  Future<String?> readScratchpad() async {
    final List<Map<String, Object?>> rows = await _store.query(
      'SELECT * FROM ${LocalTables.scratchpads} LIMIT 1',
      const <Object?>[],
    );
    if (rows.isEmpty) return null;
    return rows.first['note'] as String?;
  }

  @override
  Future<void> writeScratchpad(String note) async {
    final List<Map<String, Object?>> rows = await _store.query(
      'SELECT * FROM ${LocalTables.scratchpads} LIMIT 1',
      const <Object?>[],
    );
    if (rows.isEmpty) {
      await _store.insert(LocalTables.scratchpads, <String, Object?>{
        'note': note,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      return;
    }
    await _store.update(LocalTables.scratchpads, rows.first['id']! as String, {
      'note': note,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Never _mapped(Object error, StackTrace stackTrace, String operation) {
    if (error is NodexError) throw error;
    final NodexError mapped = NodexErrorMapper.map(error, operation: operation);
    _logger.error(
      _module,
      'Productivity repository failure.',
      operation: operation,
      outcome: 'failed',
      errorCode: mapped.code,
      stackTrace: stackTrace,
    );
    throw mapped;
  }
}
