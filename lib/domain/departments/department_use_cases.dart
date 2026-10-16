/// Department registry use cases (Module 12).
library;

import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/departments/department.dart';
import 'package:nodex_hms/domain/departments/department_repository.dart';

/// Registers a department into the registry.
final class RegisterDepartmentUseCase {
  /// Creates the use case.
  RegisterDepartmentUseCase({required this._repository});

  final DepartmentRepository _repository;

  /// Records the entry locally, gated on department administration.
  Future<String> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String facilityId,
    required String code,
    required String displayName,
    String? specialty,
    String? headUserId,
    String departmentId = '',
  }) async {
    policy.require(NodexPermissions.departmentAdminister);
    final Map<String, Object?> row = Department.registerRow(
      tenantId: tenantId,
      facilityId: facilityId,
      code: code,
      displayName: displayName,
      specialty: specialty,
      headUserId: headUserId,
      departmentId: departmentId,
    );
    return _repository.registerDepartment(row);
  }
}

/// Updates a department's directory facts (name, specialty, head).
final class UpdateDepartmentUseCase {
  /// Creates the use case.
  UpdateDepartmentUseCase({required this._repository});

  final DepartmentRepository _repository;

  /// Applies the edits, gated on administration and only on mutable rows.
  Future<void> call({
    required AuthorizationPolicy policy,
    required Department department,
    String? displayName,
    String? specialty,
    String? headUserId,
  }) async {
    policy.require(NodexPermissions.departmentAdminister);
    if (!department.isEditable) {
      throw const AuthorizationError(
        message:
            'An archived department is retained as a historical reference.',
        code: 'department_archived_immutable',
      );
    }
    await _repository.updateDepartment(
      department.id,
      departmentChanges(
        displayName: displayName,
        specialty: specialty,
        headUserId: headUserId,
      ),
    );
  }
}

/// Archives a department. The row is retained because historical records name
/// the department they were recorded under.
final class ArchiveDepartmentUseCase {
  /// Creates the use case.
  ArchiveDepartmentUseCase({required this._repository});

  final DepartmentRepository _repository;

  /// Transitions the department to archived, gated on administration.
  Future<void> call({
    required AuthorizationPolicy policy,
    required Department department,
  }) async {
    policy.require(NodexPermissions.departmentAdminister);
    if (department.status == DepartmentStatus.archived) {
      throw const AuthorizationError(
        message: 'This department is already archived.',
        code: 'department_already_archived',
      );
    }
    await _repository.updateDepartment(
      department.id,
      departmentArchiveChanges(),
    );
  }
}

/// Reads the department registry.
final class ListDepartmentsUseCase {
  /// Creates the use case.
  ListDepartmentsUseCase({required this._repository});

  final DepartmentRepository _repository;

  /// Lists the tenant's departments, optionally within one facility.
  Future<List<Department>> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    String? facilityId,
    int limit = 200,
  }) async {
    policy.require(NodexPermissions.departmentAdminister);
    return _repository.listDepartments(
      tenantId,
      facilityId: facilityId,
      limit: limit,
    );
  }
}
