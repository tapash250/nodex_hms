/// Operations repository and use cases (Module 02).
library;

import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/error_mapper.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/operations/department_metric.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';

/// Repository operations for the operations dashboard.
abstract interface class OperationsRepository {
  /// The latest reading for each department, newest first.
  Future<List<DepartmentMetric>> listLatest();

  /// Every reading for one department, newest first.
  Future<List<DepartmentMetric>> listForDepartment(String departmentId);
}

/// PowerSync-backed operations repository.
final class DefaultOperationsRepository implements OperationsRepository {
  /// Creates a repository over a local store.
  DefaultOperationsRepository({required this._store, required this._logger});

  static const String _module = 'domain.operations';

  final PatientLocalStore _store;
  final NodexLogger _logger;

  @override
  Future<List<DepartmentMetric>> listLatest() async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'SELECT * FROM ${LocalTables.operationalDepartmentMetrics} '
        'ORDER BY metric_timestamp DESC',
        const <Object?>[],
      );
      return _latestPerDepartment(rows);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'operations.latest');
    }
  }

  @override
  Future<List<DepartmentMetric>> listForDepartment(String departmentId) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'SELECT * FROM ${LocalTables.operationalDepartmentMetrics} '
        'WHERE department_id = ? ORDER BY metric_timestamp DESC',
        <Object?>[departmentId],
      );
      return rows.map(DepartmentMetric.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'operations.department');
    }
  }

  /// Keeps the newest reading for each department.
  ///
  /// The device holds a trailing window of readings, and a dashboard that
  /// showed all of them would show a department twice rather than showing
  /// where it is now.
  static List<DepartmentMetric> _latestPerDepartment(
    List<Map<String, Object?>> rows,
  ) {
    final List<DepartmentMetric> metrics = rows
        .map(DepartmentMetric.fromRow)
        .toList(growable: false);
    final Map<String, DepartmentMetric> latest = <String, DepartmentMetric>{};
    for (final DepartmentMetric metric in metrics) {
      final DepartmentMetric? current = latest[metric.departmentId];
      if (current == null || metric.at.isAfter(current.at)) {
        latest[metric.departmentId] = metric;
      }
    }
    final List<DepartmentMetric> result = latest.values.toList(growable: false);
    result.sort(
      (DepartmentMetric a, DepartmentMetric b) =>
          b.waitingCount.compareTo(a.waitingCount),
    );
    return result;
  }

  Never _mapped(Object error, StackTrace stackTrace, String operation) {
    if (error is NodexError) throw error;
    final NodexError mapped = NodexErrorMapper.map(error, operation: operation);
    _logger.error(
      _module,
      'Operations repository failure.',
      operation: operation,
      outcome: 'failed',
      errorCode: mapped.code,
      stackTrace: stackTrace,
    );
    throw mapped;
  }
}

/// Reads the operations dashboard.
final class ReadOperationsDashboardUseCase {
  /// Creates the use case.
  const ReadOperationsDashboardUseCase({required this._repository});

  final OperationsRepository _repository;

  /// Reads the latest reading for each department.
  Future<List<DepartmentMetric>> call({
    required AuthorizationPolicy policy,
  }) async {
    policy.require(NodexPermissions.operationsRead);
    final List<DepartmentMetric> metrics = await _repository.listLatest();
    // The department with the longest queue comes first: the dashboard is
    // read under pressure, and the first card should be the one that needs
    // somebody.
    final List<DepartmentMetric> ordered = List<DepartmentMetric>.of(metrics);
    ordered.sort(
      (DepartmentMetric a, DepartmentMetric b) =>
          b.waitingCount.compareTo(a.waitingCount),
    );
    return ordered;
  }
}
