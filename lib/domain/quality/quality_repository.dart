/// Quality & NABH Compliance Hub repository contract and local implementation
/// (Module 35).
library;

import 'package:nodex_hms/core/errors/error_mapper.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';
import 'package:nodex_hms/domain/quality/quality.dart';
import 'package:uuid/uuid.dart';

abstract interface class QualityRepository {
  /// Lists compliance audits, newest scheduled first, optionally for one status.
  Future<List<ComplianceAudit>> listAudits(
    String tenantId, {
    String? status,
    int limit = 500,
  });
  Future<ComplianceAudit?> auditById(String id);
  Future<String> registerAudit(Map<String, Object?> row);
  Future<void> updateAudit(String id, Map<String, Object?> changes);

  /// Lists incident reports, newest occurrence first, optionally for one status.
  Future<List<IncidentReport>> listIncidents(
    String tenantId, {
    String? status,
    int limit = 500,
  });
  Future<IncidentReport?> incidentById(String id);
  Future<String> registerIncident(Map<String, Object?> row);
  Future<void> updateIncident(String id, Map<String, Object?> changes);

  /// Lists clinical indicators, newest period first, optionally for one status.
  Future<List<ClinicalIndicator>> listIndicators(
    String tenantId, {
    String? status,
    int limit = 500,
  });
  Future<ClinicalIndicator?> indicatorById(String id);
  Future<String> registerIndicator(Map<String, Object?> row);
  Future<void> updateIndicator(String id, Map<String, Object?> changes);
}

final class DefaultQualityRepository implements QualityRepository {
  DefaultQualityRepository({required this._store, required this._logger});

  static const String _module = 'domain.quality';
  final PatientLocalStore _store;
  final NodexLogger _logger;

  @override
  Future<List<ComplianceAudit>> listAudits(
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
          'select * from ${LocalTables.complianceAudits} '
          'where ${conditions.join(' and ')} '
          'order by scheduled_for desc limit ?';
      params.add(limit);
      final List<Map<String, Object?>> rows = await _store.query(sql, params);
      return rows.map(ComplianceAudit.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'quality.listAudits');
    }
  }

  @override
  Future<ComplianceAudit?> auditById(String id) async {
    try {
      final Map<String, Object?>? row = await _store.getById(
        LocalTables.complianceAudits,
        id,
      );
      return row == null ? null : ComplianceAudit.fromRow(row);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'quality.auditById');
    }
  }

  @override
  Future<String> registerAudit(Map<String, Object?> row) async {
    final String id = (row['id'] as String?) ?? const Uuid().v4();
    try {
      await _store.insert(LocalTables.complianceAudits, <String, Object?>{
        ...row,
        'id': id,
      });
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'quality.registerAudit');
    }
  }

  @override
  Future<void> updateAudit(String id, Map<String, Object?> changes) async {
    try {
      await _store.update(LocalTables.complianceAudits, id, changes);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'quality.updateAudit');
    }
  }

  @override
  Future<List<IncidentReport>> listIncidents(
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
          'select * from ${LocalTables.incidentReports} '
          'where ${conditions.join(' and ')} '
          'order by occurred_at desc limit ?';
      params.add(limit);
      final List<Map<String, Object?>> rows = await _store.query(sql, params);
      return rows.map(IncidentReport.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'quality.listIncidents');
    }
  }

  @override
  Future<IncidentReport?> incidentById(String id) async {
    try {
      final Map<String, Object?>? row = await _store.getById(
        LocalTables.incidentReports,
        id,
      );
      return row == null ? null : IncidentReport.fromRow(row);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'quality.incidentById');
    }
  }

  @override
  Future<String> registerIncident(Map<String, Object?> row) async {
    final String id = (row['id'] as String?) ?? const Uuid().v4();
    try {
      await _store.insert(LocalTables.incidentReports, <String, Object?>{
        ...row,
        'id': id,
      });
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'quality.registerIncident');
    }
  }

  @override
  Future<void> updateIncident(String id, Map<String, Object?> changes) async {
    try {
      await _store.update(LocalTables.incidentReports, id, changes);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'quality.updateIncident');
    }
  }

  @override
  Future<List<ClinicalIndicator>> listIndicators(
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
          'select * from ${LocalTables.clinicalIndicators} '
          'where ${conditions.join(' and ')} '
          'order by period_start desc limit ?';
      params.add(limit);
      final List<Map<String, Object?>> rows = await _store.query(sql, params);
      return rows.map(ClinicalIndicator.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'quality.listIndicators');
    }
  }

  @override
  Future<ClinicalIndicator?> indicatorById(String id) async {
    try {
      final Map<String, Object?>? row = await _store.getById(
        LocalTables.clinicalIndicators,
        id,
      );
      return row == null ? null : ClinicalIndicator.fromRow(row);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'quality.indicatorById');
    }
  }

  @override
  Future<String> registerIndicator(Map<String, Object?> row) async {
    final String id = (row['id'] as String?) ?? const Uuid().v4();
    try {
      await _store.insert(LocalTables.clinicalIndicators, <String, Object?>{
        ...row,
        'id': id,
      });
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'quality.registerIndicator');
    }
  }

  @override
  Future<void> updateIndicator(String id, Map<String, Object?> changes) async {
    try {
      await _store.update(LocalTables.clinicalIndicators, id, changes);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'quality.updateIndicator');
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
