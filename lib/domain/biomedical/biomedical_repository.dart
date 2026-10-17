/// Biomedical assets & calibration repository contract and local implementation
/// (Module 29).
library;

import 'package:nodex_hms/core/errors/error_mapper.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/biomedical/biomedical.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';
import 'package:uuid/uuid.dart';

abstract interface class BiomedicalRepository {
  /// Lists assets by tenant, optionally for one facility or department.
  Future<List<BiomedicalAsset>> listAssets(
    String tenantId, {
    String? facilityId,
    String? departmentId,
    int limit = 500,
  });
  Future<BiomedicalAsset?> assetById(String id);
  Future<String> registerAsset(Map<String, Object?> row);
  Future<void> updateAsset(String id, Map<String, Object?> changes);

  /// Lists breakdown tickets by tenant, optionally for one asset.
  Future<List<BreakdownTicket>> listTickets(
    String tenantId, {
    String? assetId,
    int limit = 500,
  });
  Future<BreakdownTicket?> ticketById(String id);
  Future<String> registerTicket(Map<String, Object?> row);
  Future<void> updateTicket(String id, Map<String, Object?> changes);

  /// Lists the service history by tenant, optionally for one asset, newest
  /// first.
  Future<List<MaintenanceRecord>> listMaintenanceRecords(
    String tenantId, {
    String? assetId,
    int limit = 500,
  });
  Future<String> registerMaintenanceRecord(Map<String, Object?> row);
}

final class DefaultBiomedicalRepository implements BiomedicalRepository {
  DefaultBiomedicalRepository({required this._store, required this._logger});

  static const String _module = 'domain.biomedical';
  final PatientLocalStore _store;
  final NodexLogger _logger;

  @override
  Future<List<BiomedicalAsset>> listAssets(
    String tenantId, {
    String? facilityId,
    String? departmentId,
    int limit = 500,
  }) async {
    try {
      final List<String> conditions = <String>['tenant_id = ?'];
      final List<Object?> params = <Object?>[tenantId];
      if (facilityId != null) {
        conditions.add('facility_id = ?');
        params.add(facilityId);
      }
      if (departmentId != null) {
        conditions.add('department_id = ?');
        params.add(departmentId);
      }
      final String sql =
          'select * from ${LocalTables.biomedicalAssets} '
          'where ${conditions.join(' and ')} '
          'order by asset_tag asc limit ?';
      params.add(limit);
      final List<Map<String, Object?>> rows = await _store.query(sql, params);
      return rows.map(BiomedicalAsset.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'biomedical.listAssets');
    }
  }

  @override
  Future<BiomedicalAsset?> assetById(String id) async {
    try {
      final Map<String, Object?>? row = await _store.getById(
        LocalTables.biomedicalAssets,
        id,
      );
      return row == null ? null : BiomedicalAsset.fromRow(row);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'biomedical.assetById');
    }
  }

  @override
  Future<String> registerAsset(Map<String, Object?> row) async {
    final String id = (row['id'] as String?) ?? const Uuid().v4();
    try {
      await _store.insert(LocalTables.biomedicalAssets, <String, Object?>{
        ...row,
        'id': id,
      });
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'biomedical.registerAsset');
    }
  }

  @override
  Future<void> updateAsset(String id, Map<String, Object?> changes) async {
    try {
      await _store.update(LocalTables.biomedicalAssets, id, changes);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'biomedical.updateAsset');
    }
  }

  @override
  Future<List<BreakdownTicket>> listTickets(
    String tenantId, {
    String? assetId,
    int limit = 500,
  }) async {
    try {
      final List<String> conditions = <String>['tenant_id = ?'];
      final List<Object?> params = <Object?>[tenantId];
      if (assetId != null) {
        conditions.add('asset_id = ?');
        params.add(assetId);
      }
      final String sql =
          'select * from ${LocalTables.biomedicalBreakdownTickets} '
          'where ${conditions.join(' and ')} '
          'order by reported_at desc limit ?';
      params.add(limit);
      final List<Map<String, Object?>> rows = await _store.query(sql, params);
      return rows.map(BreakdownTicket.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'biomedical.listTickets');
    }
  }

  @override
  Future<BreakdownTicket?> ticketById(String id) async {
    try {
      final Map<String, Object?>? row = await _store.getById(
        LocalTables.biomedicalBreakdownTickets,
        id,
      );
      return row == null ? null : BreakdownTicket.fromRow(row);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'biomedical.ticketById');
    }
  }

  @override
  Future<String> registerTicket(Map<String, Object?> row) async {
    final String id = (row['id'] as String?) ?? const Uuid().v4();
    try {
      await _store.insert(
        LocalTables.biomedicalBreakdownTickets,
        <String, Object?>{...row, 'id': id},
      );
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'biomedical.registerTicket');
    }
  }

  @override
  Future<void> updateTicket(String id, Map<String, Object?> changes) async {
    try {
      await _store.update(LocalTables.biomedicalBreakdownTickets, id, changes);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'biomedical.updateTicket');
    }
  }

  @override
  Future<List<MaintenanceRecord>> listMaintenanceRecords(
    String tenantId, {
    String? assetId,
    int limit = 500,
  }) async {
    try {
      final List<String> conditions = <String>['tenant_id = ?'];
      final List<Object?> params = <Object?>[tenantId];
      if (assetId != null) {
        conditions.add('asset_id = ?');
        params.add(assetId);
      }
      final String sql =
          'select * from ${LocalTables.biomedicalMaintenanceRecords} '
          'where ${conditions.join(' and ')} '
          'order by performed_at desc limit ?';
      params.add(limit);
      final List<Map<String, Object?>> rows = await _store.query(sql, params);
      return rows.map(MaintenanceRecord.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'biomedical.listMaintenanceRecords');
    }
  }

  @override
  Future<String> registerMaintenanceRecord(Map<String, Object?> row) async {
    final String id = (row['id'] as String?) ?? const Uuid().v4();
    try {
      await _store.insert(
        LocalTables.biomedicalMaintenanceRecords,
        <String, Object?>{...row, 'id': id},
      );
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'biomedical.registerMaintenanceRecord');
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
