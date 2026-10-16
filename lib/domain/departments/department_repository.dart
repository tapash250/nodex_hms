/// Department registry repository contract and local implementation
/// (Module 12).
library;

import 'package:nodex_hms/core/errors/error_mapper.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/departments/department.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';
import 'package:uuid/uuid.dart';

abstract interface class DepartmentRepository {
  Future<List<Department>> listDepartments(
    String tenantId, {
    String? facilityId,
    int limit = 200,
  });
  Future<Department?> departmentById(String id);
  Future<Department?> departmentByCode(
    String tenantId,
    String facilityId,
    String code,
  );
  Future<String> registerDepartment(Map<String, Object?> row);
  Future<void> updateDepartment(String id, Map<String, Object?> changes);
}

final class DefaultDepartmentRepository implements DepartmentRepository {
  DefaultDepartmentRepository({required this._store, required this._logger});

  static const String _module = 'domain.departments';
  final PatientLocalStore _store;
  final NodexLogger _logger;

  @override
  Future<List<Department>> listDepartments(
    String tenantId, {
    String? facilityId,
    int limit = 200,
  }) async {
    try {
      final String sql = facilityId == null
          ? 'select * from ${LocalTables.departments} '
                'where tenant_id = ? order by display_name limit ?'
          : 'select * from ${LocalTables.departments} '
                'where tenant_id = ? and facility_id = ? '
                'order by display_name limit ?';
      final List<Object?> params = facilityId == null
          ? <Object?>[tenantId, limit]
          : <Object?>[tenantId, facilityId, limit];
      final List<Map<String, Object?>> rows = await _store.query(sql, params);
      return rows.map(Department.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'departments.listDepartments');
    }
  }

  @override
  Future<Department?> departmentById(String id) async {
    try {
      final Map<String, Object?>? row = await _store.getById(
        LocalTables.departments,
        id,
      );
      return row == null ? null : Department.fromRow(row);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'departments.departmentById');
    }
  }

  @override
  Future<Department?> departmentByCode(
    String tenantId,
    String facilityId,
    String code,
  ) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select * from ${LocalTables.departments} '
        'where tenant_id = ? and facility_id = ? and code = ?',
        <Object?>[tenantId, facilityId, code],
      );
      return rows.isEmpty ? null : Department.fromRow(rows.first);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'departments.departmentByCode');
    }
  }

  @override
  Future<String> registerDepartment(Map<String, Object?> row) async {
    final String id = (row['id'] as String?) ?? const Uuid().v4();
    try {
      await _store.insert(LocalTables.departments, <String, Object?>{
        ...row,
        'id': id,
      });
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'departments.registerDepartment');
    }
  }

  @override
  Future<void> updateDepartment(String id, Map<String, Object?> changes) async {
    try {
      await _store.update(LocalTables.departments, id, changes);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'departments.updateDepartment');
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
