/// Statutory Records & Birth/Death Registry repository contract and local
/// implementation (Module 34).
library;

import 'package:nodex_hms/core/errors/error_mapper.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';
import 'package:nodex_hms/domain/statutory/statutory.dart';
import 'package:uuid/uuid.dart';

abstract interface class StatutoryRepository {
  /// Lists birth registrations, newest event first, optionally for one status.
  Future<List<BirthRecord>> listBirths(
    String tenantId, {
    String? status,
    int limit = 500,
  });
  Future<BirthRecord?> birthById(String id);
  Future<String> registerBirth(Map<String, Object?> row);
  Future<void> updateBirth(String id, Map<String, Object?> changes);

  /// Lists death registrations, newest event first, optionally for one status.
  Future<List<DeathRecord>> listDeaths(
    String tenantId, {
    String? status,
    int limit = 500,
  });
  Future<DeathRecord?> deathById(String id);
  Future<String> registerDeath(Map<String, Object?> row);
  Future<void> updateDeath(String id, Map<String, Object?> changes);

  /// Lists medico-legal cases, newest report first, optionally for one status.
  Future<List<MlcIntimation>> listMlcIntimations(
    String tenantId, {
    String? status,
    int limit = 500,
  });
  Future<MlcIntimation?> mlcIntimationById(String id);
  Future<String> registerMlcIntimation(Map<String, Object?> row);
  Future<void> updateMlcIntimation(String id, Map<String, Object?> changes);

  /// Lists the amendment log, newest first, optionally for one register row.
  Future<List<StatutoryAmendment>> listAmendments(
    String tenantId, {
    StatutoryRegistryKind? kind,
    String? recordId,
    int limit = 500,
  });
  Future<String> registerAmendment(Map<String, Object?> row);
}

final class DefaultStatutoryRepository implements StatutoryRepository {
  DefaultStatutoryRepository({required this._store, required this._logger});

  static const String _module = 'domain.statutory';
  final PatientLocalStore _store;
  final NodexLogger _logger;

  @override
  Future<List<BirthRecord>> listBirths(
    String tenantId, {
    String? status,
    int limit = 500,
  }) async {
    try {
      final List<String> conditions = <String>['tenant_id = ?'];
      final List<Object?> params = <Object?>[tenantId];
      if (status != null) {
        conditions.add('status = ?');
        params.add(status);
      }
      final String sql =
          'select * from ${LocalTables.statutoryBirthRecords} '
          'where ${conditions.join(' and ')} '
          'order by birth_at desc limit ?';
      params.add(limit);
      final List<Map<String, Object?>> rows = await _store.query(sql, params);
      return rows.map(BirthRecord.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'statutory.listBirths');
    }
  }

  @override
  Future<BirthRecord?> birthById(String id) async {
    try {
      final Map<String, Object?>? row = await _store.getById(
        LocalTables.statutoryBirthRecords,
        id,
      );
      return row == null ? null : BirthRecord.fromRow(row);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'statutory.birthById');
    }
  }

  @override
  Future<String> registerBirth(Map<String, Object?> row) async {
    final String id = (row['id'] as String?) ?? const Uuid().v4();
    try {
      await _store.insert(LocalTables.statutoryBirthRecords, <String, Object?>{
        ...row,
        'id': id,
      });
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'statutory.registerBirth');
    }
  }

  @override
  Future<void> updateBirth(String id, Map<String, Object?> changes) async {
    try {
      await _store.update(LocalTables.statutoryBirthRecords, id, changes);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'statutory.updateBirth');
    }
  }

  @override
  Future<List<DeathRecord>> listDeaths(
    String tenantId, {
    String? status,
    int limit = 500,
  }) async {
    try {
      final List<String> conditions = <String>['tenant_id = ?'];
      final List<Object?> params = <Object?>[tenantId];
      if (status != null) {
        conditions.add('status = ?');
        params.add(status);
      }
      final String sql =
          'select * from ${LocalTables.statutoryDeathRecords} '
          'where ${conditions.join(' and ')} '
          'order by death_at desc limit ?';
      params.add(limit);
      final List<Map<String, Object?>> rows = await _store.query(sql, params);
      return rows.map(DeathRecord.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'statutory.listDeaths');
    }
  }

  @override
  Future<DeathRecord?> deathById(String id) async {
    try {
      final Map<String, Object?>? row = await _store.getById(
        LocalTables.statutoryDeathRecords,
        id,
      );
      return row == null ? null : DeathRecord.fromRow(row);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'statutory.deathById');
    }
  }

  @override
  Future<String> registerDeath(Map<String, Object?> row) async {
    final String id = (row['id'] as String?) ?? const Uuid().v4();
    try {
      await _store.insert(LocalTables.statutoryDeathRecords, <String, Object?>{
        ...row,
        'id': id,
      });
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'statutory.registerDeath');
    }
  }

  @override
  Future<void> updateDeath(String id, Map<String, Object?> changes) async {
    try {
      await _store.update(LocalTables.statutoryDeathRecords, id, changes);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'statutory.updateDeath');
    }
  }

  @override
  Future<List<MlcIntimation>> listMlcIntimations(
    String tenantId, {
    String? status,
    int limit = 500,
  }) async {
    try {
      final List<String> conditions = <String>['tenant_id = ?'];
      final List<Object?> params = <Object?>[tenantId];
      if (status != null) {
        conditions.add('status = ?');
        params.add(status);
      }
      final String sql =
          'select * from ${LocalTables.statutoryMlcIntimations} '
          'where ${conditions.join(' and ')} '
          'order by reported_at desc limit ?';
      params.add(limit);
      final List<Map<String, Object?>> rows = await _store.query(sql, params);
      return rows.map(MlcIntimation.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'statutory.listMlcIntimations');
    }
  }

  @override
  Future<MlcIntimation?> mlcIntimationById(String id) async {
    try {
      final Map<String, Object?>? row = await _store.getById(
        LocalTables.statutoryMlcIntimations,
        id,
      );
      return row == null ? null : MlcIntimation.fromRow(row);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'statutory.mlcIntimationById');
    }
  }

  @override
  Future<String> registerMlcIntimation(Map<String, Object?> row) async {
    final String id = (row['id'] as String?) ?? const Uuid().v4();
    try {
      await _store.insert(
        LocalTables.statutoryMlcIntimations,
        <String, Object?>{...row, 'id': id},
      );
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'statutory.registerMlcIntimation');
    }
  }

  @override
  Future<void> updateMlcIntimation(
    String id,
    Map<String, Object?> changes,
  ) async {
    try {
      await _store.update(LocalTables.statutoryMlcIntimations, id, changes);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'statutory.updateMlcIntimation');
    }
  }

  @override
  Future<List<StatutoryAmendment>> listAmendments(
    String tenantId, {
    StatutoryRegistryKind? kind,
    String? recordId,
    int limit = 500,
  }) async {
    try {
      final List<String> conditions = <String>['tenant_id = ?'];
      final List<Object?> params = <Object?>[tenantId];
      if (recordId != null) {
        conditions.add('${_subjectColumn(kind)} = ?');
        params.add(recordId);
      }
      final String sql =
          'select * from ${LocalTables.statutoryRecordAmendments} '
          'where ${conditions.join(' and ')} '
          'order by created_at desc limit ?';
      params.add(limit);
      final List<Map<String, Object?>> rows = await _store.query(sql, params);
      return rows.map(StatutoryAmendment.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'statutory.listAmendments');
    }
  }

  @override
  Future<String> registerAmendment(Map<String, Object?> row) async {
    final String id = (row['id'] as String?) ?? const Uuid().v4();
    try {
      await _store.insert(
        LocalTables.statutoryRecordAmendments,
        <String, Object?>{...row, 'id': id},
      );
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'statutory.registerAmendment');
    }
  }

  /// The column that links an amendment to its register row.
  static String _subjectColumn(StatutoryRegistryKind? kind) => switch (kind) {
    StatutoryRegistryKind.death => 'death_record_id',
    StatutoryRegistryKind.mlc => 'mlc_intimation_id',
    StatutoryRegistryKind.birth || null => 'birth_record_id',
  };

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
