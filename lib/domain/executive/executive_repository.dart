/// Executive dashboard repository and use cases (Module 01).
library;

import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/error_mapper.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/executive/executive_kpi.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';

/// Repository operations for the executive dashboard.
abstract interface class ExecutiveKpiRepository {
  /// Readings for one facility, newest first, bounded to [since].
  Future<List<ExecutiveKpiSnapshot>> listRecent({
    required String facilityId,
    required DateTime since,
  });
}

/// PowerSync-backed executive repository.
final class DefaultExecutiveKpiRepository implements ExecutiveKpiRepository {
  /// Creates a repository over a local store.
  DefaultExecutiveKpiRepository({required this._store, required this._logger});

  static const String _module = 'domain.executive';

  final PatientLocalStore _store;
  final NodexLogger _logger;

  @override
  Future<List<ExecutiveKpiSnapshot>> listRecent({
    required String facilityId,
    required DateTime since,
  }) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'SELECT * FROM ${LocalTables.executiveKpiSnapshots} '
        'WHERE facility_id = ? AND snapshot_timestamp >= ? '
        'ORDER BY snapshot_timestamp DESC LIMIT 720',
        <Object?>[facilityId, since.toUtc().toIso8601String()],
      );
      return rows.map(ExecutiveKpiSnapshot.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'executive.recent');
    }
  }

  Never _mapped(Object error, StackTrace stackTrace, String operation) {
    if (error is NodexError) throw error;
    final NodexError mapped = NodexErrorMapper.map(error, operation: operation);
    _logger.error(
      _module,
      'Executive repository failure.',
      operation: operation,
      outcome: 'failed',
      errorCode: mapped.code,
      stackTrace: stackTrace,
    );
    throw mapped;
  }
}

/// Reads the executive dashboard for one facility.
final class ReadExecutiveKpiUseCase {
  /// Creates the use case.
  const ReadExecutiveKpiUseCase({required this._repository});

  final ExecutiveKpiRepository _repository;

  /// The trailing window the device holds.
  static const Duration window = Duration(days: 30);

  /// Reads the latest facility reading and the baseline behind it.
  Future<ExecutiveKpiState> call({
    required AuthorizationPolicy policy,
    required String facilityId,
    DateTime? now,
  }) async {
    policy.require(NodexPermissions.executiveRead);
    final Set<String> scopedFacilities =
        policy.snapshot?.facilityIds ?? const <String>{};
    if (scopedFacilities.isNotEmpty && !scopedFacilities.contains(facilityId)) {
      throw const AuthorizationError(
        message: 'This facility is outside the session authorization scope.',
        code: 'facility_out_of_scope',
      );
    }
    final DateTime at = now ?? DateTime.now().toUtc();
    final List<ExecutiveKpiSnapshot> snapshots = await _repository.listRecent(
      facilityId: facilityId,
      since: at.subtract(window),
    );
    return ExecutiveKpiState(facilityId: facilityId, snapshots: snapshots);
  }
}
