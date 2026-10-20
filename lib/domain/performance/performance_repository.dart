/// Performance repository and use cases (Module 03).
library;

import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/error_mapper.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';
import 'package:nodex_hms/domain/performance/performance_index.dart';

/// Repository operations for the performance dashboard.
abstract interface class PerformanceRepository {
  /// The latest reading for each indicator.
  Future<List<PerformanceIndex>> listLatest();

  /// Every reading for one indicator, newest first.
  Future<List<PerformanceIndex>> listForIndicator(String indicatorCode);
}

/// PowerSync-backed performance repository.
final class DefaultPerformanceRepository implements PerformanceRepository {
  /// Creates a repository over a local store.
  DefaultPerformanceRepository({required this._store, required this._logger});

  static const String _module = 'domain.performance';

  final PatientLocalStore _store;
  final NodexLogger _logger;

  @override
  Future<List<PerformanceIndex>> listLatest() async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'SELECT * FROM ${LocalTables.clinicalPerformanceIndices} '
        'ORDER BY period_start DESC',
        const <Object?>[],
      );
      final List<PerformanceIndex> readings = rows
          .map(PerformanceIndex.fromRow)
          .toList(growable: false);
      final Map<String, PerformanceIndex> latest = <String, PerformanceIndex>{};
      for (final PerformanceIndex reading in readings) {
        final PerformanceIndex? current = latest[reading.indicatorCode];
        if (current == null || reading.periodEnd.isAfter(current.periodEnd)) {
          latest[reading.indicatorCode] = reading;
        }
      }
      return List<PerformanceIndex>.unmodifiable(latest.values);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'performance.latest');
    }
  }

  @override
  Future<List<PerformanceIndex>> listForIndicator(String indicatorCode) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'SELECT * FROM ${LocalTables.clinicalPerformanceIndices} '
        'WHERE indicator_code = ? ORDER BY period_start DESC',
        <Object?>[indicatorCode],
      );
      return rows.map(PerformanceIndex.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'performance.indicator');
    }
  }

  Never _mapped(Object error, StackTrace stackTrace, String operation) {
    if (error is NodexError) throw error;
    final NodexError mapped = NodexErrorMapper.map(error, operation: operation);
    _logger.error(
      _module,
      'Performance repository failure.',
      operation: operation,
      outcome: 'failed',
      errorCode: mapped.code,
      stackTrace: stackTrace,
    );
    throw mapped;
  }
}

/// Reads the performance dashboard.
final class ReadPerformanceDashboardUseCase {
  /// Creates the use case.
  const ReadPerformanceDashboardUseCase({required this._repository});

  final PerformanceRepository _repository;

  /// Reads the latest reading for each indicator.
  ///
  /// The indicators that have gone beyond their baseline come first: the
  /// dashboard is read by the people who can act on it, and the ones that
  /// have drifted are the reason they are reading it.
  Future<List<PerformanceIndex>> call({
    required AuthorizationPolicy policy,
  }) async {
    policy.require(NodexPermissions.performanceRead);
    final List<PerformanceIndex> readings = await _repository.listLatest();
    final List<PerformanceIndex> ordered = List<PerformanceIndex>.of(readings);
    ordered.sort((PerformanceIndex a, PerformanceIndex b) {
      // Beyond the baseline first, then merely worse than it, then the rest
      // in name order.
      final int byStanding = _rank(a).compareTo(_rank(b));
      if (byStanding != 0) return byStanding;
      return a.indicatorName.toLowerCase().compareTo(
        b.indicatorName.toLowerCase(),
      );
    });
    return ordered;
  }

  static int _rank(PerformanceIndex reading) {
    if (reading.standing == IndicatorStanding.beyondBaseline &&
        reading.isWorseThanBaseline) {
      return 0;
    }
    if (reading.isWorseThanBaseline) return 1;
    return 2;
  }
}
