/// Master settings repository contract and local implementation (Module 39).
library;

import 'package:nodex_hms/core/errors/error_mapper.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';
import 'package:nodex_hms/domain/settings/settings.dart';
import 'package:uuid/uuid.dart';

abstract interface class SettingsRepository {
  /// Lists settings profiles, newest version first.
  Future<List<SettingsProfile>> listSettingsProfiles(
    String tenantId, {
    String? status,
    String? facilityId,
    int limit = 500,
  });
  Future<SettingsProfile?> settingsProfileById(String id);
  Future<String> registerSettingsProfile(Map<String, Object?> row);
  Future<void> updateSettingsProfile(String id, Map<String, Object?> changes);

  /// Lists branding assets, by kind then label.
  Future<List<BrandingAsset>> listBrandingAssets(
    String tenantId, {
    String? assetKind,
    String? status,
    int limit = 500,
  });
  Future<BrandingAsset?> brandingAssetById(String id);
  Future<String> registerBrandingAsset(Map<String, Object?> row);
  Future<void> updateBrandingAsset(String id, Map<String, Object?> changes);

  /// Lists the department tree, by sort order then code.
  Future<List<DepartmentNode>> listDepartments(
    String tenantId, {
    String? status,
    String? kind,
    int limit = 1000,
  });
  Future<DepartmentNode?> departmentById(String id);
  Future<String> registerDepartment(Map<String, Object?> row);
  Future<void> updateDepartment(String id, Map<String, Object?> changes);

  /// Lists tariffs, newest window first.
  Future<List<BillingTariff>> listTariffs(
    String tenantId, {
    String? code,
    String? departmentId,
    String? status,
    int limit = 1000,
  });
  Future<BillingTariff?> tariffById(String id);
  Future<String> registerTariff(Map<String, Object?> row);
  Future<void> updateTariff(String id, Map<String, Object?> changes);

  /// Lists routing profiles, by code.
  Future<List<AiRoutingProfile>> listRoutingProfiles(
    String tenantId, {
    String? taskKind,
    String? status,
    int limit = 500,
  });
  Future<AiRoutingProfile?> routingProfileById(String id);
  Future<String> registerRoutingProfile(Map<String, Object?> row);
  Future<void> updateRoutingProfile(String id, Map<String, Object?> changes);
}

final class DefaultSettingsRepository implements SettingsRepository {
  DefaultSettingsRepository({required this._store, required this._logger});

  static const String _module = 'domain.settings';
  final PatientLocalStore _store;
  final NodexLogger _logger;

  @override
  Future<List<SettingsProfile>> listSettingsProfiles(
    String tenantId, {
    String? status,
    String? facilityId,
    int limit = 500,
  }) async {
    try {
      final List<Object?> params = <Object?>[tenantId];
      final List<String> conditions = <String>['tenant_id = ?'];
      if (status != null) {
        conditions.add('status = ?');
        params.add(status);
      }
      if (facilityId != null) {
        conditions.add('facility_id = ?');
        params.add(facilityId);
      }
      final String sql =
          'select * from ${LocalTables.settingsProfiles} '
          'where ${conditions.join(' and ')} '
          'order by version desc limit ?';
      params.add(limit);
      final List<Map<String, Object?>> rows = await _store.query(sql, params);
      return rows.map(SettingsProfile.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'settings.listSettingsProfiles');
    }
  }

  @override
  Future<SettingsProfile?> settingsProfileById(String id) async {
    try {
      final Map<String, Object?>? row = await _store.getById(
        LocalTables.settingsProfiles,
        id,
      );
      return row == null ? null : SettingsProfile.fromRow(row);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'settings.settingsProfileById');
    }
  }

  @override
  Future<String> registerSettingsProfile(Map<String, Object?> row) async {
    final String id = (row['id'] as String?) ?? const Uuid().v4();
    try {
      await _store.insert(LocalTables.settingsProfiles, <String, Object?>{
        ...row,
        'id': id,
      });
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'settings.registerSettingsProfile');
    }
  }

  @override
  Future<void> updateSettingsProfile(
    String id,
    Map<String, Object?> changes,
  ) async {
    try {
      await _store.update(LocalTables.settingsProfiles, id, changes);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'settings.updateSettingsProfile');
    }
  }

  @override
  Future<List<BrandingAsset>> listBrandingAssets(
    String tenantId, {
    String? assetKind,
    String? status,
    int limit = 500,
  }) async {
    try {
      final List<Object?> params = <Object?>[tenantId];
      final List<String> conditions = <String>['tenant_id = ?'];
      if (assetKind != null) {
        conditions.add('asset_kind = ?');
        params.add(assetKind);
      }
      if (status != null) {
        conditions.add('status = ?');
        params.add(status);
      }
      final String sql =
          'select * from ${LocalTables.brandingAssets} '
          'where ${conditions.join(' and ')} '
          'order by asset_kind asc, label asc limit ?';
      params.add(limit);
      final List<Map<String, Object?>> rows = await _store.query(sql, params);
      return rows.map(BrandingAsset.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'settings.listBrandingAssets');
    }
  }

  @override
  Future<BrandingAsset?> brandingAssetById(String id) async {
    try {
      final Map<String, Object?>? row = await _store.getById(
        LocalTables.brandingAssets,
        id,
      );
      return row == null ? null : BrandingAsset.fromRow(row);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'settings.brandingAssetById');
    }
  }

  @override
  Future<String> registerBrandingAsset(Map<String, Object?> row) async {
    final String id = (row['id'] as String?) ?? const Uuid().v4();
    try {
      await _store.insert(LocalTables.brandingAssets, <String, Object?>{
        ...row,
        'id': id,
      });
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'settings.registerBrandingAsset');
    }
  }

  @override
  Future<void> updateBrandingAsset(
    String id,
    Map<String, Object?> changes,
  ) async {
    try {
      await _store.update(LocalTables.brandingAssets, id, changes);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'settings.updateBrandingAsset');
    }
  }

  @override
  Future<List<DepartmentNode>> listDepartments(
    String tenantId, {
    String? status,
    String? kind,
    int limit = 1000,
  }) async {
    try {
      final List<Object?> params = <Object?>[tenantId];
      final List<String> conditions = <String>['tenant_id = ?'];
      if (status != null) {
        conditions.add('status = ?');
        params.add(status);
      }
      if (kind != null) {
        conditions.add('kind = ?');
        params.add(kind);
      }
      final String sql =
          'select * from ${LocalTables.departmentHierarchies} '
          'where ${conditions.join(' and ')} '
          'order by sort_order asc, code asc limit ?';
      params.add(limit);
      final List<Map<String, Object?>> rows = await _store.query(sql, params);
      return rows.map(DepartmentNode.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'settings.listDepartments');
    }
  }

  @override
  Future<DepartmentNode?> departmentById(String id) async {
    try {
      final Map<String, Object?>? row = await _store.getById(
        LocalTables.departmentHierarchies,
        id,
      );
      return row == null ? null : DepartmentNode.fromRow(row);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'settings.departmentById');
    }
  }

  @override
  Future<String> registerDepartment(Map<String, Object?> row) async {
    final String id = (row['id'] as String?) ?? const Uuid().v4();
    try {
      await _store.insert(LocalTables.departmentHierarchies, <String, Object?>{
        ...row,
        'id': id,
      });
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'settings.registerDepartment');
    }
  }

  @override
  Future<void> updateDepartment(String id, Map<String, Object?> changes) async {
    try {
      await _store.update(LocalTables.departmentHierarchies, id, changes);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'settings.updateDepartment');
    }
  }

  @override
  Future<List<BillingTariff>> listTariffs(
    String tenantId, {
    String? code,
    String? departmentId,
    String? status,
    int limit = 1000,
  }) async {
    try {
      final List<Object?> params = <Object?>[tenantId];
      final List<String> conditions = <String>['tenant_id = ?'];
      if (code != null) {
        conditions.add('code = ?');
        params.add(code);
      }
      if (departmentId != null) {
        conditions.add('department_id = ?');
        params.add(departmentId);
      }
      if (status != null) {
        conditions.add('status = ?');
        params.add(status);
      }
      final String sql =
          'select * from ${LocalTables.billingTariffs} '
          'where ${conditions.join(' and ')} '
          'order by effective_from desc limit ?';
      params.add(limit);
      final List<Map<String, Object?>> rows = await _store.query(sql, params);
      return rows.map(BillingTariff.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'settings.listTariffs');
    }
  }

  @override
  Future<BillingTariff?> tariffById(String id) async {
    try {
      final Map<String, Object?>? row = await _store.getById(
        LocalTables.billingTariffs,
        id,
      );
      return row == null ? null : BillingTariff.fromRow(row);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'settings.tariffById');
    }
  }

  @override
  Future<String> registerTariff(Map<String, Object?> row) async {
    final String id = (row['id'] as String?) ?? const Uuid().v4();
    try {
      await _store.insert(LocalTables.billingTariffs, <String, Object?>{
        ...row,
        'id': id,
      });
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'settings.registerTariff');
    }
  }

  @override
  Future<void> updateTariff(String id, Map<String, Object?> changes) async {
    try {
      await _store.update(LocalTables.billingTariffs, id, changes);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'settings.updateTariff');
    }
  }

  @override
  Future<List<AiRoutingProfile>> listRoutingProfiles(
    String tenantId, {
    String? taskKind,
    String? status,
    int limit = 500,
  }) async {
    try {
      final List<Object?> params = <Object?>[tenantId];
      final List<String> conditions = <String>['tenant_id = ?'];
      if (taskKind != null) {
        conditions.add('task_kind = ?');
        params.add(taskKind);
      }
      if (status != null) {
        conditions.add('status = ?');
        params.add(status);
      }
      final String sql =
          'select * from ${LocalTables.aiRoutingProfiles} '
          'where ${conditions.join(' and ')} '
          'order by profile_code asc limit ?';
      params.add(limit);
      final List<Map<String, Object?>> rows = await _store.query(sql, params);
      return rows.map(AiRoutingProfile.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'settings.listRoutingProfiles');
    }
  }

  @override
  Future<AiRoutingProfile?> routingProfileById(String id) async {
    try {
      final Map<String, Object?>? row = await _store.getById(
        LocalTables.aiRoutingProfiles,
        id,
      );
      return row == null ? null : AiRoutingProfile.fromRow(row);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'settings.routingProfileById');
    }
  }

  @override
  Future<String> registerRoutingProfile(Map<String, Object?> row) async {
    final String id = (row['id'] as String?) ?? const Uuid().v4();
    try {
      await _store.insert(LocalTables.aiRoutingProfiles, <String, Object?>{
        ...row,
        'id': id,
      });
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'settings.registerRoutingProfile');
    }
  }

  @override
  Future<void> updateRoutingProfile(
    String id,
    Map<String, Object?> changes,
  ) async {
    try {
      await _store.update(LocalTables.aiRoutingProfiles, id, changes);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'settings.updateRoutingProfile');
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
