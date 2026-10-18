/// Analytics warehouse repository contract and local implementation
/// (Module 38).
library;

import 'package:nodex_hms/core/errors/error_mapper.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/analytics/analytics.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';
import 'package:uuid/uuid.dart';

abstract interface class AnalyticsRepository {
  /// Lists the report catalogue, by code.
  Future<List<ReportDefinition>> listDefinitions(
    String tenantId, {
    String? category,
    String? status,
    int limit = 500,
  });
  Future<ReportDefinition?> definitionById(String id);
  Future<String> registerDefinition(Map<String, Object?> row);
  Future<void> updateDefinition(String id, Map<String, Object?> changes);

  /// Lists materialised rollups, newest period first.
  Future<List<AnalyticsRollup>> listRollups(
    String tenantId, {
    String? definitionId,
    String? grain,
    String? status,
    int limit = 500,
  });
  Future<AnalyticsRollup?> rollupById(String id);
  Future<String> registerRollup(Map<String, Object?> row);
  Future<void> updateRollup(String id, Map<String, Object?> changes);

  /// Lists report runs, newest first.
  Future<List<ReportRun>> listRuns(
    String tenantId, {
    String? definitionId,
    String? status,
    int limit = 500,
  });
  Future<ReportRun?> runById(String id);
  Future<String> registerRun(Map<String, Object?> row);
  Future<void> updateRun(String id, Map<String, Object?> changes);

  /// Lists the export log, oldest first.
  Future<List<AnalyticsExport>> listExports(
    String tenantId, {
    String? runId,
    int limit = 500,
  });
  Future<String> appendExport(Map<String, Object?> row);
}

final class DefaultAnalyticsRepository implements AnalyticsRepository {
  DefaultAnalyticsRepository({required this._store, required this._logger});

  static const String _module = 'domain.analytics';
  final PatientLocalStore _store;
  final NodexLogger _logger;

  @override
  Future<List<ReportDefinition>> listDefinitions(
    String tenantId, {
    String? category,
    String? status,
    int limit = 500,
  }) async {
    try {
      final List<Object?> params = <Object?>[tenantId];
      final List<String> conditions = <String>['tenant_id = ?'];
      if (category != null) {
        conditions.add('category = ?');
        params.add(category);
      }
      if (status != null) {
        conditions.add('status = ?');
        params.add(status);
      }
      final String sql =
          'select * from ${LocalTables.analyticsReportDefinitions} '
          'where ${conditions.join(' and ')} '
          'order by code asc limit ?';
      params.add(limit);
      final List<Map<String, Object?>> rows = await _store.query(sql, params);
      return rows.map(ReportDefinition.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'analytics.listDefinitions');
    }
  }

  @override
  Future<ReportDefinition?> definitionById(String id) async {
    try {
      final Map<String, Object?>? row = await _store.getById(
        LocalTables.analyticsReportDefinitions,
        id,
      );
      return row == null ? null : ReportDefinition.fromRow(row);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'analytics.definitionById');
    }
  }

  @override
  Future<String> registerDefinition(Map<String, Object?> row) async {
    final String id = (row['id'] as String?) ?? const Uuid().v4();
    try {
      await _store.insert(
        LocalTables.analyticsReportDefinitions,
        <String, Object?>{...row, 'id': id},
      );
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'analytics.registerDefinition');
    }
  }

  @override
  Future<void> updateDefinition(String id, Map<String, Object?> changes) async {
    try {
      await _store.update(LocalTables.analyticsReportDefinitions, id, changes);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'analytics.updateDefinition');
    }
  }

  @override
  Future<List<AnalyticsRollup>> listRollups(
    String tenantId, {
    String? definitionId,
    String? grain,
    String? status,
    int limit = 500,
  }) async {
    try {
      final List<Object?> params = <Object?>[tenantId];
      final List<String> conditions = <String>['tenant_id = ?'];
      if (definitionId != null) {
        conditions.add('definition_id = ?');
        params.add(definitionId);
      }
      if (grain != null) {
        conditions.add('grain = ?');
        params.add(grain);
      }
      if (status != null) {
        conditions.add('status = ?');
        params.add(status);
      }
      final String sql =
          'select * from ${LocalTables.analyticsRollups} '
          'where ${conditions.join(' and ')} '
          'order by period_start desc limit ?';
      params.add(limit);
      final List<Map<String, Object?>> rows = await _store.query(sql, params);
      return rows.map(AnalyticsRollup.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'analytics.listRollups');
    }
  }

  @override
  Future<AnalyticsRollup?> rollupById(String id) async {
    try {
      final Map<String, Object?>? row = await _store.getById(
        LocalTables.analyticsRollups,
        id,
      );
      return row == null ? null : AnalyticsRollup.fromRow(row);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'analytics.rollupById');
    }
  }

  @override
  Future<String> registerRollup(Map<String, Object?> row) async {
    final String id = (row['id'] as String?) ?? const Uuid().v4();
    try {
      await _store.insert(LocalTables.analyticsRollups, <String, Object?>{
        ...row,
        'id': id,
      });
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'analytics.registerRollup');
    }
  }

  @override
  Future<void> updateRollup(String id, Map<String, Object?> changes) async {
    try {
      await _store.update(LocalTables.analyticsRollups, id, changes);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'analytics.updateRollup');
    }
  }

  @override
  Future<List<ReportRun>> listRuns(
    String tenantId, {
    String? definitionId,
    String? status,
    int limit = 500,
  }) async {
    try {
      final List<Object?> params = <Object?>[tenantId];
      final List<String> conditions = <String>['tenant_id = ?'];
      if (definitionId != null) {
        conditions.add('definition_id = ?');
        params.add(definitionId);
      }
      if (status != null) {
        conditions.add('status = ?');
        params.add(status);
      }
      final String sql =
          'select * from ${LocalTables.analyticsReportRuns} '
          'where ${conditions.join(' and ')} '
          'order by created_at desc limit ?';
      params.add(limit);
      final List<Map<String, Object?>> rows = await _store.query(sql, params);
      return rows.map(ReportRun.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'analytics.listRuns');
    }
  }

  @override
  Future<ReportRun?> runById(String id) async {
    try {
      final Map<String, Object?>? row = await _store.getById(
        LocalTables.analyticsReportRuns,
        id,
      );
      return row == null ? null : ReportRun.fromRow(row);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'analytics.runById');
    }
  }

  @override
  Future<String> registerRun(Map<String, Object?> row) async {
    final String id = (row['id'] as String?) ?? const Uuid().v4();
    try {
      await _store.insert(LocalTables.analyticsReportRuns, <String, Object?>{
        ...row,
        'id': id,
      });
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'analytics.registerRun');
    }
  }

  @override
  Future<void> updateRun(String id, Map<String, Object?> changes) async {
    try {
      await _store.update(LocalTables.analyticsReportRuns, id, changes);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'analytics.updateRun');
    }
  }

  @override
  Future<List<AnalyticsExport>> listExports(
    String tenantId, {
    String? runId,
    int limit = 500,
  }) async {
    try {
      final List<Object?> params = <Object?>[tenantId];
      final List<String> conditions = <String>['tenant_id = ?'];
      if (runId != null) {
        conditions.add('run_id = ?');
        params.add(runId);
      }
      final String sql =
          'select * from ${LocalTables.analyticsExports} '
          'where ${conditions.join(' and ')} '
          'order by exported_at asc limit ?';
      params.add(limit);
      final List<Map<String, Object?>> rows = await _store.query(sql, params);
      return rows.map(AnalyticsExport.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'analytics.listExports');
    }
  }

  @override
  Future<String> appendExport(Map<String, Object?> row) async {
    final String id = (row['id'] as String?) ?? const Uuid().v4();
    try {
      await _store.insert(LocalTables.analyticsExports, <String, Object?>{
        ...row,
        'id': id,
      });
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'analytics.appendExport');
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
