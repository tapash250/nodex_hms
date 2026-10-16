/// Clinical department registry entities (Module 12).
///
/// Specification scope: the clinical and administrative departments a
/// facility organizes its staff, beds and directories around. The PostgreSQL
/// `departments` table has existed since Phase 1 because it scopes sync
/// streams and ward organisation; this module owns the client-side registry
/// lifecycle over that row.
///
/// Departments are retired, never deleted: an archived department still names
/// the place a historical record belongs to, so the row is retained and only
/// its status transitions. Codes identify a department within one facility,
/// matching the `(tenant_id, facility_id, code)` uniqueness the database
/// enforces.
// ignore_for_file: sort_constructors_first
library;

import 'package:meta/meta.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';

/// Registry status of a department.
enum DepartmentStatus {
  /// Open and accepting staff and referrals.
  active('active'),

  /// Temporarily closed; the department is retained.
  inactive('inactive'),

  /// Retired; the registry keeps the row as a historical reference.
  archived('archived');

  const DepartmentStatus(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Parses a stored value.
  static DepartmentStatus fromWire(String value) =>
      DepartmentStatus.values.firstWhere(
        (DepartmentStatus status) => status.wireValue == value,
        orElse: () => DepartmentStatus.active,
      );

  /// Whether the department may still be edited.
  bool get isEditable => this != DepartmentStatus.archived;
}

/// A clinical or administrative department.
@immutable
final class Department {
  /// Creates a department.
  const Department({
    required this.id,
    required this.tenantId,
    required this.facilityId,
    required this.code,
    required this.displayName,
    required this.status,
    required this.updatedAt,
    this.specialty,
    this.headUserId,
  });

  /// Validates and builds a new department row.
  static Map<String, Object?> registerRow({
    required String tenantId,
    required String facilityId,
    required String code,
    required String displayName,
    String? specialty,
    String? headUserId,
    String departmentId = '',
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (facilityId.isEmpty) {
      fieldErrors['facility_id'] = 'Facility is required.';
    }
    if (code.trim().isEmpty) {
      fieldErrors['code'] = 'Department code is required.';
    }
    if (displayName.trim().isEmpty) {
      fieldErrors['display_name'] = 'Department name is required.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Department entry failed validation.',
        fieldErrors: fieldErrors,
        code: 'department_invalid',
      );
    }

    final String now = DateTime.now().toUtc().toIso8601String();
    final String? special = specialty?.trim();
    final String? head = headUserId?.trim();

    return <String, Object?>{
      if (departmentId.isNotEmpty) 'id': departmentId,
      'tenant_id': tenantId,
      'facility_id': facilityId,
      'code': code.trim(),
      'display_name': displayName.trim(),
      'specialty': special == null || special.isEmpty ? null : special,
      'head_user_id': head == null || head.isEmpty ? null : head,
      'status': DepartmentStatus.active.wireValue,
      'updated_at': now,
    };
  }

  /// Materializes a department from a local row.
  factory Department.fromRow(Map<String, Object?> row) => Department(
    id: row['id']! as String,
    tenantId: row['tenant_id']! as String,
    facilityId: row['facility_id']! as String,
    code: row['code']! as String,
    displayName: row['display_name']! as String,
    status: DepartmentStatus.fromWire(
      (row['status'] as String?) ?? DepartmentStatus.active.wireValue,
    ),
    updatedAt: row['updated_at'] is String
        ? DateTime.parse(row['updated_at']! as String).toUtc()
        : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    specialty: row['specialty'] as String?,
    headUserId: row['head_user_id'] as String?,
  );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// Facility the department belongs to.
  final String facilityId;

  /// Short code, unique within the facility.
  final String code;

  /// Human-readable name.
  final String displayName;

  /// Primary specialty, when the department is clinical.
  final String? specialty;

  /// The app user who heads the department, when assigned.
  final String? headUserId;

  /// Registry status.
  final DepartmentStatus status;

  /// Last change, UTC.
  final DateTime updatedAt;

  /// Whether the department may be edited or archived.
  bool get isEditable => status.isEditable;
}

/// Column changes for a department edit.
Map<String, Object?> departmentChanges({
  String? displayName,
  String? specialty,
  String? headUserId,
}) => <String, Object?>{
  if (displayName != null) 'display_name': displayName.trim(),
  'specialty': specialty?.trim(),
  'head_user_id': headUserId?.trim(),
  'updated_at': DateTime.now().toUtc().toIso8601String(),
};

/// The full change set for archiving a department.
Map<String, Object?> departmentArchiveChanges() => <String, Object?>{
  'status': DepartmentStatus.archived.wireValue,
  'updated_at': DateTime.now().toUtc().toIso8601String(),
};
