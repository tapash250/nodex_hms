/// Hospital task repository contract and local implementation (Module 41).
library;

import 'package:nodex_hms/core/errors/error_mapper.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';
import 'package:nodex_hms/domain/tasks/hospital_task.dart';
import 'package:uuid/uuid.dart';

/// Repository operations for the hospital task board.
abstract interface class TaskRepository {
  /// Tasks matching the given filters, newest first.
  Future<List<HospitalTask>> listBoard({
    TaskStatus? status,
    TaskPriority? priority,
    String? assignedTo,
    String? requestedBy,
    String? patientId,
    int limit,
  });

  /// One task by id, or null.
  Future<HospitalTask?> getTask(String id);

  /// Tasks that are still live and either unowned or owned by [userId].
  Future<List<HospitalTask>> listClaimable(String userId);

  /// Raises a task.
  Future<String> raiseTask(Map<String, Object?> row);

  /// Applies a transition to a task.
  Future<void> updateTask(String id, Map<String, Object?> changes);
}

/// PowerSync-backed task repository.
final class DefaultTaskRepository implements TaskRepository {
  /// Creates a repository over a local store.
  DefaultTaskRepository({required this._store, required this._logger});

  static const String _module = 'domain.tasks';

  final PatientLocalStore _store;
  final NodexLogger _logger;

  @override
  Future<List<HospitalTask>> listBoard({
    TaskStatus? status,
    TaskPriority? priority,
    String? assignedTo,
    String? requestedBy,
    String? patientId,
    int limit = 200,
  }) async {
    try {
      final StringBuffer sql = StringBuffer(
        'SELECT * FROM ${LocalTables.hospitalTasks}',
      );
      final List<Object?> parameters = <Object?>[];
      final List<String> filters = <String>[];
      if (status != null) {
        filters.add('status = ?');
        parameters.add(status.wireValue);
      }
      if (priority != null) {
        filters.add('priority = ?');
        parameters.add(priority.wireValue);
      }
      if (assignedTo != null) {
        filters.add('assigned_to = ?');
        parameters.add(assignedTo);
      }
      if (requestedBy != null) {
        filters.add('requested_by = ?');
        parameters.add(requestedBy);
      }
      if (patientId != null) {
        filters.add('patient_id = ?');
        parameters.add(patientId);
      }
      if (filters.isNotEmpty) {
        sql.write(' WHERE ${filters.join(' AND ')}');
      }
      // Priority first, then the clock: a STAT errand raised a minute ago
      // outranks a routine one raised this morning.
      sql.write(' ORDER BY created_at DESC');

      final List<Map<String, Object?>> rows = await _store.query(
        sql.toString(),
        parameters,
      );
      final List<HospitalTask> tasks = rows
          .map(HospitalTask.fromRow)
          .toList(growable: false);
      tasks.sort(_boardOrder);
      return tasks.take(limit).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'tasks.board');
    }
  }

  @override
  Future<HospitalTask?> getTask(String id) async {
    final Map<String, Object?>? row = await _store.getById(
      LocalTables.hospitalTasks,
      id,
    );
    return row == null ? null : HospitalTask.fromRow(row);
  }

  @override
  Future<List<HospitalTask>> listClaimable(String userId) async {
    final List<HospitalTask> tasks = await listBoard(limit: 500);
    return tasks
        .where(
          (HospitalTask task) =>
              task.status.isLive &&
              (task.assignedTo == null || task.assignedTo == userId),
        )
        .toList(growable: false);
  }

  @override
  Future<String> raiseTask(Map<String, Object?> row) async {
    final String id = const Uuid().v4();
    try {
      await _store.insert(LocalTables.hospitalTasks, <String, Object?>{
        ...row,
        'id': id,
      });
      _logger.info(
        _module,
        'Hospital task raised locally.',
        operation: 'tasks.raise',
        outcome: 'queued',
      );
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'tasks.raise');
    }
  }

  @override
  Future<void> updateTask(String id, Map<String, Object?> changes) async {
    try {
      await _store.update(LocalTables.hospitalTasks, id, changes);
      _logger.info(
        _module,
        'Hospital task transitioned locally.',
        operation: 'tasks.transition',
        outcome: 'queued',
      );
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'tasks.transition');
    }
  }

  /// Most urgent first, then nearest due, then newest.
  static int _boardOrder(HospitalTask a, HospitalTask b) {
    final int byPriority = b.priority.weight.compareTo(a.priority.weight);
    if (byPriority != 0) return byPriority;
    final DateTime? dueA = a.dueAt;
    final DateTime? dueB = b.dueAt;
    if (dueA != null && dueB != null) {
      final int byDue = dueA.compareTo(dueB);
      if (byDue != 0) return byDue;
    } else if (dueA != null) {
      return -1;
    } else if (dueB != null) {
      return 1;
    }
    final DateTime createdA =
        a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final DateTime createdB =
        b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return createdB.compareTo(createdA);
  }

  Never _mapped(Object error, StackTrace stackTrace, String operation) {
    if (error is NodexError) throw error;
    final NodexError mapped = NodexErrorMapper.map(error, operation: operation);
    _logger.error(
      _module,
      'Task repository failure.',
      operation: operation,
      outcome: 'failed',
      errorCode: mapped.code,
      stackTrace: stackTrace,
    );
    throw mapped;
  }
}
