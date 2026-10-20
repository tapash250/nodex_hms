/// Clinical dashboard repository and use cases (Module 04).
library;

import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/error_mapper.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/clinical_dashboard/doctor_assignment.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';

/// Repository operations for the clinical dashboard.
abstract interface class ClinicalDashboardRepository {
  /// The assignments of one clinician, newest first.
  Future<List<DoctorAssignment>> listAssignments(String doctorId);

  /// The assignments of every clinician in the tenant.
  Future<List<DoctorAssignment>> listAllAssignments();
}

/// PowerSync-backed clinical dashboard repository.
final class DefaultClinicalDashboardRepository
    implements ClinicalDashboardRepository {
  /// Creates a repository over a local store.
  DefaultClinicalDashboardRepository({
    required this._store,
    required this._logger,
  });

  static const String _module = 'domain.clinical_dashboard';

  final PatientLocalStore _store;
  final NodexLogger _logger;

  @override
  Future<List<DoctorAssignment>> listAssignments(String doctorId) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'SELECT * FROM ${LocalTables.doctorAssignments} WHERE doctor_id = ? '
        'ORDER BY assigned_at DESC',
        <Object?>[doctorId],
      );
      return rows.map(DoctorAssignment.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'clinical_dashboard.assignments');
    }
  }

  @override
  Future<List<DoctorAssignment>> listAllAssignments() async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'SELECT * FROM ${LocalTables.doctorAssignments} '
        'ORDER BY assigned_at DESC',
        const <Object?>[],
      );
      return rows.map(DoctorAssignment.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'clinical_dashboard.allAssignments');
    }
  }

  Never _mapped(Object error, StackTrace stackTrace, String operation) {
    if (error is NodexError) throw error;
    final NodexError mapped = NodexErrorMapper.map(error, operation: operation);
    _logger.error(
      _module,
      'Clinical dashboard repository failure.',
      operation: operation,
      outcome: 'failed',
      errorCode: mapped.code,
      stackTrace: stackTrace,
    );
    throw mapped;
  }
}

/// Reads the patients a clinician is responsible for.
final class ListDoctorAssignmentsUseCase {
  /// Creates the use case.
  const ListDoctorAssignmentsUseCase({required this._repository});

  final ClinicalDashboardRepository _repository;

  /// Reads the assignments.
  Future<List<DoctorAssignment>> call({
    required AuthorizationPolicy policy,
    required String doctorId,
  }) async {
    policy.require(NodexPermissions.clinicalDashboardRead);
    return _repository.listAssignments(doctorId);
  }
}
