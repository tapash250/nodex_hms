/// Biomedical waste management repository contract and local implementation
/// (Module 30).
library;

import 'package:nodex_hms/core/errors/error_mapper.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';
import 'package:nodex_hms/domain/waste/waste.dart';
import 'package:uuid/uuid.dart';

abstract interface class WasteRepository {
  /// Lists waste categories by tenant, by code.
  Future<List<WasteCategory>> listCategories(
    String tenantId, {
    int limit = 300,
  });
  Future<WasteCategory?> categoryById(String id);
  Future<String> registerCategory(Map<String, Object?> row);
  Future<void> updateCategory(String id, Map<String, Object?> changes);

  /// Lists generation logs, newest first, optionally for one category or
  /// facility.
  Future<List<WasteGenerationLog>> listGenerationLogs(
    String tenantId, {
    String? categoryId,
    String? facilityId,
    int limit = 1000,
  });
  Future<String> registerGenerationLog(Map<String, Object?> row);

  /// Lists disposal certificates, newest first, optionally for one category or
  /// facility.
  Future<List<DisposalCertificate>> listCertificates(
    String tenantId, {
    String? categoryId,
    String? facilityId,
    int limit = 1000,
  });
  Future<DisposalCertificate?> certificateById(String id);
  Future<String> registerCertificate(Map<String, Object?> row);
  Future<void> updateCertificate(String id, Map<String, Object?> changes);
}

final class DefaultWasteRepository implements WasteRepository {
  DefaultWasteRepository({required this._store, required this._logger});

  static const String _module = 'domain.waste';
  final PatientLocalStore _store;
  final NodexLogger _logger;

  @override
  Future<List<WasteCategory>> listCategories(
    String tenantId, {
    int limit = 300,
  }) async {
    try {
      const String sql =
          'select * from ${LocalTables.wasteCategories} '
          'where tenant_id = ? order by code asc limit ?';
      final List<Map<String, Object?>> rows = await _store.query(sql, <Object?>[
        tenantId,
        limit,
      ]);
      return rows.map(WasteCategory.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'waste.listCategories');
    }
  }

  @override
  Future<WasteCategory?> categoryById(String id) async {
    try {
      final Map<String, Object?>? row = await _store.getById(
        LocalTables.wasteCategories,
        id,
      );
      return row == null ? null : WasteCategory.fromRow(row);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'waste.categoryById');
    }
  }

  @override
  Future<String> registerCategory(Map<String, Object?> row) async {
    final String id = (row['id'] as String?) ?? const Uuid().v4();
    try {
      await _store.insert(LocalTables.wasteCategories, <String, Object?>{
        ...row,
        'id': id,
      });
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'waste.registerCategory');
    }
  }

  @override
  Future<void> updateCategory(String id, Map<String, Object?> changes) async {
    try {
      await _store.update(LocalTables.wasteCategories, id, changes);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'waste.updateCategory');
    }
  }

  @override
  Future<List<WasteGenerationLog>> listGenerationLogs(
    String tenantId, {
    String? categoryId,
    String? facilityId,
    int limit = 1000,
  }) async {
    try {
      final List<String> conditions = <String>['tenant_id = ?'];
      final List<Object?> params = <Object?>[tenantId];
      if (categoryId != null) {
        conditions.add('category_id = ?');
        params.add(categoryId);
      }
      if (facilityId != null) {
        conditions.add('facility_id = ?');
        params.add(facilityId);
      }
      final String sql =
          'select * from ${LocalTables.wasteGenerationLogs} '
          'where ${conditions.join(' and ')} '
          'order by logged_at desc limit ?';
      params.add(limit);
      final List<Map<String, Object?>> rows = await _store.query(sql, params);
      return rows.map(WasteGenerationLog.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'waste.listGenerationLogs');
    }
  }

  @override
  Future<String> registerGenerationLog(Map<String, Object?> row) async {
    final String id = (row['id'] as String?) ?? const Uuid().v4();
    try {
      await _store.insert(LocalTables.wasteGenerationLogs, <String, Object?>{
        ...row,
        'id': id,
      });
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'waste.registerGenerationLog');
    }
  }

  @override
  Future<List<DisposalCertificate>> listCertificates(
    String tenantId, {
    String? categoryId,
    String? facilityId,
    int limit = 1000,
  }) async {
    try {
      final List<String> conditions = <String>['tenant_id = ?'];
      final List<Object?> params = <Object?>[tenantId];
      if (categoryId != null) {
        conditions.add('category_id = ?');
        params.add(categoryId);
      }
      if (facilityId != null) {
        conditions.add('facility_id = ?');
        params.add(facilityId);
      }
      final String sql =
          'select * from ${LocalTables.wasteDisposalCertificates} '
          'where ${conditions.join(' and ')} '
          'order by disposed_at desc limit ?';
      params.add(limit);
      final List<Map<String, Object?>> rows = await _store.query(sql, params);
      return rows.map(DisposalCertificate.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'waste.listCertificates');
    }
  }

  @override
  Future<DisposalCertificate?> certificateById(String id) async {
    try {
      final Map<String, Object?>? row = await _store.getById(
        LocalTables.wasteDisposalCertificates,
        id,
      );
      return row == null ? null : DisposalCertificate.fromRow(row);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'waste.certificateById');
    }
  }

  @override
  Future<String> registerCertificate(Map<String, Object?> row) async {
    final String id = (row['id'] as String?) ?? const Uuid().v4();
    try {
      await _store.insert(
        LocalTables.wasteDisposalCertificates,
        <String, Object?>{...row, 'id': id},
      );
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'waste.registerCertificate');
    }
  }

  @override
  Future<void> updateCertificate(
    String id,
    Map<String, Object?> changes,
  ) async {
    try {
      await _store.update(LocalTables.wasteDisposalCertificates, id, changes);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'waste.updateCertificate');
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
