/// Nurse ward station repository contract and local implementation (Module 06).
library;

import 'package:nodex_hms/core/errors/error_mapper.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/nursing_station/nursing_station.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';
import 'package:uuid/uuid.dart';

abstract interface class NursingStationRepository {
  Future<List<WardVital>> listVitals(
    String tenantId, {
    String? patientId,
    String? wardId,
    int limit = 200,
  });
  Future<WardVital?> vitalById(String id);
  Future<String> recordVitals(Map<String, Object?> row);

  Future<List<WardHandover>> listHandovers(
    String tenantId, {
    String? wardId,
    int limit = 100,
  });
  Future<WardHandover?> handoverById(String id);
  Future<String> recordHandover(Map<String, Object?> row);

  Future<List<WardTask>> listTasks(
    String tenantId, {
    String? wardId,
    String? assignedTo,
    WardTaskStatus? status,
    String? patientId,
    int limit = 200,
  });
  Future<WardTask?> taskById(String id);
  Future<String> createTask(Map<String, Object?> row);
  Future<void> updateTask(String id, Map<String, Object?> changes);
}

final class DefaultNursingStationRepository
    implements NursingStationRepository {
  DefaultNursingStationRepository({
    required this._store,
    required this._logger,
  });

  static const String _module = 'domain.nursing_station';
  final PatientLocalStore _store;
  final NodexLogger _logger;

  @override
  Future<List<WardVital>> listVitals(
    String tenantId, {
    String? patientId,
    String? wardId,
    int limit = 200,
  }) => _list<WardVital>(
    table: LocalTables.wardVitals,
    tenantId: tenantId,
    filters: <String, Object?>{'patient_id': patientId, 'ward_id': wardId},
    orderBy: 'observed_at',
    descending: true,
    limit: limit,
    map: WardVital.fromRow,
    operation: 'nursing.listVitals',
  );

  @override
  Future<WardVital?> vitalById(String id) => _byId(
    table: LocalTables.wardVitals,
    id: id,
    map: WardVital.fromRow,
    operation: 'nursing.vitalById',
  );

  @override
  Future<String> recordVitals(Map<String, Object?> row) =>
      _insert(LocalTables.wardVitals, row, 'nursing.recordVitals');

  @override
  Future<List<WardHandover>> listHandovers(
    String tenantId, {
    String? wardId,
    int limit = 100,
  }) => _list<WardHandover>(
    table: LocalTables.wardHandovers,
    tenantId: tenantId,
    filters: <String, Object?>{'ward_id': wardId},
    orderBy: 'handover_at',
    descending: true,
    limit: limit,
    map: WardHandover.fromRow,
    operation: 'nursing.listHandovers',
  );

  @override
  Future<WardHandover?> handoverById(String id) => _byId(
    table: LocalTables.wardHandovers,
    id: id,
    map: WardHandover.fromRow,
    operation: 'nursing.handoverById',
  );

  @override
  Future<String> recordHandover(Map<String, Object?> row) =>
      _insert(LocalTables.wardHandovers, row, 'nursing.recordHandover');

  @override
  Future<List<WardTask>> listTasks(
    String tenantId, {
    String? wardId,
    String? assignedTo,
    WardTaskStatus? status,
    String? patientId,
    int limit = 200,
  }) => _list<WardTask>(
    table: LocalTables.wardTasks,
    tenantId: tenantId,
    filters: <String, Object?>{
      'ward_id': wardId,
      'assigned_to': assignedTo,
      'status': status?.wireValue,
      'patient_id': patientId,
    },
    orderBy: 'due_at',
    limit: limit,
    map: WardTask.fromRow,
    operation: 'nursing.listTasks',
  );

  @override
  Future<WardTask?> taskById(String id) => _byId(
    table: LocalTables.wardTasks,
    id: id,
    map: WardTask.fromRow,
    operation: 'nursing.taskById',
  );

  @override
  Future<String> createTask(Map<String, Object?> row) =>
      _insert(LocalTables.wardTasks, row, 'nursing.createTask');

  @override
  Future<void> updateTask(String id, Map<String, Object?> changes) =>
      _update(LocalTables.wardTasks, id, changes, 'nursing.updateTask');

  Future<List<T>> _list<T>({
    required String table,
    required String tenantId,
    required Map<String, Object?> filters,
    required String orderBy,
    required int limit,
    required T Function(Map<String, Object?>) map,
    required String operation,
    bool descending = false,
  }) async {
    try {
      final StringBuffer sql = StringBuffer(
        'select * from $table where tenant_id = ?',
      );
      final List<Object?> params = <Object?>[tenantId];
      for (final MapEntry<String, Object?> filter in filters.entries) {
        if (filter.value != null) {
          sql.write(' and ${filter.key} = ?');
          params.add(filter.value);
        }
      }
      sql.write(' order by $orderBy${descending ? ' desc' : ''} limit ?');
      params.add(limit);
      final List<Map<String, Object?>> rows = await _store.query(
        sql.toString(),
        params,
      );
      return rows.map(map).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, operation);
    }
  }

  Future<T?> _byId<T>({
    required String table,
    required String id,
    required T Function(Map<String, Object?>) map,
    required String operation,
  }) async {
    try {
      final Map<String, Object?>? row = await _store.getById(table, id);
      return row == null ? null : map(row);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, operation);
    }
  }

  Future<String> _insert(
    String table,
    Map<String, Object?> row,
    String operation,
  ) async {
    final String id = (row['id'] as String?) ?? const Uuid().v4();
    try {
      await _store.insert(table, <String, Object?>{...row, 'id': id});
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, operation);
    }
  }

  Future<void> _update(
    String table,
    String id,
    Map<String, Object?> changes,
    String operation,
  ) async {
    try {
      await _store.update(table, id, changes);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, operation);
    }
  }

  NodexError _mapped(Object error, StackTrace stackTrace, String operation) {
    if (error is NodexError) {
      return error;
    }
    final NodexError mapped = NodexErrorMapper.map(error, operation: operation);
    _logger.error(
      _module,
      'Local store operation failed.',
      operation: operation,
      errorCode: mapped.code,
      stackTrace: stackTrace,
    );
    return mapped;
  }
}
