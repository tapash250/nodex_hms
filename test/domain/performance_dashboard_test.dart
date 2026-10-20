/// Tests for the performance dashboard (Module 03).
///
/// An indicator is a number until it is read against its baseline. These tests
/// pin the reading: how far the value sits from the baseline, which direction
/// is worse, and what the screen says when there is no baseline to compare
/// against.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/authorization_snapshot.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/performance/performance_index.dart';
import 'package:nodex_hms/domain/performance/performance_repository.dart';

/// A repository that returns fixed readings.
final class _FixedPerformanceRepository implements PerformanceRepository {
  _FixedPerformanceRepository(this.readings);

  final List<PerformanceIndex> readings;

  @override
  Future<List<PerformanceIndex>> listLatest() async => readings;

  @override
  Future<List<PerformanceIndex>> listForIndicator(String indicatorCode) async =>
      readings
          .where((PerformanceIndex r) => r.indicatorCode == indicatorCode)
          .toList(growable: false);
}

/// A policy holding the given permissions.
AuthorizationPolicy _policy(Set<String> permissions) {
  final DateTime issuedAt = DateTime.now().toUtc();
  return AuthorizationPolicy(
    snapshot: AuthorizationSnapshot(
      snapshotId: 'snapshot-1',
      tenantId: 'tenant-1',
      userId: 'user-1',
      deviceId: 'device-1',
      revision: 1,
      issuedAt: issuedAt,
      expiresAt: issuedAt.add(const Duration(days: 30)),
      payloadDigest: 'digest',
      roles: const <String>{NodexRoles.medicalOfficer},
      permissions: permissions,
      offlinePermissions: permissions,
      facilityIds: const <String>{},
      departmentIds: const <String>{},
      wardIds: const <String>{},
    ),
    connectivity: ConnectivityState.online,
  );
}

PerformanceIndex _index({
  required String code,
  required String name,
  double value = 40,
  double? baselineMean = 40,
  double? baselineStddev = 5,
  bool lowerIsBetter = true,
  int sampleSize = 20,
}) => PerformanceIndex(
  id: 'index-$code',
  tenantId: 'tenant-1',
  indicatorCode: code,
  indicatorName: name,
  category: 'laboratory',
  periodStart: DateTime.utc(2026, 9, 1),
  periodEnd: DateTime.utc(2026, 9, 30),
  value: value,
  baselineMean: baselineMean,
  baselineStddev: baselineStddev,
  sampleSize: sampleSize,
  lowerIsBetter: lowerIsBetter,
);

void main() {
  group('reading an indicator', () {
    test('a reading is read from a local row', () {
      final PerformanceIndex reading = PerformanceIndex.fromRow(
        const <String, Object?>{
          'id': 'index-1',
          'tenant_id': 'tenant-1',
          'indicator_code': 'LAB_TAT',
          'indicator_name': 'Laboratory turnaround',
          'category': 'laboratory',
          'period_start': '2026-09-01T00:00:00.000Z',
          'period_end': '2026-09-30T00:00:00.000Z',
          'value': 52.5,
          'baseline_mean': 40.0,
          'baseline_stddev': 5.0,
          'sample_size': 120,
          'lower_is_better': 1,
        },
      );
      expect(reading.value, 52.5);
      expect(reading.sampleSize, 120);
      expect(reading.lowerIsBetter, isTrue);
    });

    test('the deviation is measured in standard deviations', () {
      final PerformanceIndex reading = _index(
        code: 'LAB_TAT',
        name: 'Laboratory turnaround',
        value: 50,
        baselineMean: 40,
        baselineStddev: 5,
      );
      expect(reading.deviation, 2);
    });

    test('a flat baseline says nothing about what is usual', () {
      final PerformanceIndex reading = _index(
        code: 'LAB_TAT',
        name: 'Laboratory turnaround',
        value: 50,
        baselineMean: 40,
        baselineStddev: 0,
      );
      expect(reading.deviation, isNull);
      expect(reading.standing, IndicatorStanding.withinBaseline);
    });

    test('no baseline at all is stated', () {
      final PerformanceIndex reading = _index(
        code: 'NEW',
        name: 'A new indicator',
        baselineMean: null,
        baselineStddev: null,
      );
      expect(reading.standing, IndicatorStanding.noBaseline);
      expect(reading.summary, contains('no baseline'));
    });
  });

  group('judging an indicator', () {
    test('a turnaround time that is climbing is worse', () {
      final PerformanceIndex reading = _index(
        code: 'LAB_TAT',
        name: 'Laboratory turnaround',
        value: 55,
        baselineMean: 40,
        baselineStddev: 5,
      );
      expect(reading.isWorseThanBaseline, isTrue);
      expect(reading.standing, IndicatorStanding.beyondBaseline);
    });

    test('a survival rate that is falling is worse', () {
      final PerformanceIndex reading = _index(
        code: 'SURVIVAL',
        name: 'Survival rate',
        value: 90,
        baselineMean: 96,
        baselineStddev: 2,
        lowerIsBetter: false,
      );
      expect(reading.isWorseThanBaseline, isTrue);
    });

    test('a survival rate that is rising is not worse', () {
      final PerformanceIndex reading = _index(
        code: 'SURVIVAL',
        name: 'Survival rate',
        value: 99,
        baselineMean: 96,
        baselineStddev: 2,
        lowerIsBetter: false,
      );
      expect(reading.isWorseThanBaseline, isFalse);
      expect(reading.standing, IndicatorStanding.withinBaseline);
    });

    test('a small movement stays within the baseline', () {
      final PerformanceIndex reading = _index(
        code: 'LAB_TAT',
        name: 'Laboratory turnaround',
        value: 44,
        baselineMean: 40,
        baselineStddev: 5,
      );
      expect(reading.isWorseThanBaseline, isTrue);
      expect(reading.standing, IndicatorStanding.withinBaseline);
    });
  });

  group('the dashboard', () {
    test('reading it requires the read permission', () async {
      await expectLater(
        ReadPerformanceDashboardUseCase(
          repository: _FixedPerformanceRepository(const <PerformanceIndex>[]),
        ).call(policy: _policy(<String>{NodexPermissions.performanceManage})),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('the indicator that has drifted comes first', () async {
      final _FixedPerformanceRepository repository =
          _FixedPerformanceRepository(<PerformanceIndex>[
            _index(code: 'A', name: 'Alpha', value: 41),
            _index(code: 'B', name: 'Bravo', value: 60),
          ]);
      final List<PerformanceIndex> readings =
          await ReadPerformanceDashboardUseCase(
            repository: repository,
          ).call(policy: _policy(<String>{NodexPermissions.performanceRead}));
      expect(readings.first.indicatorCode, 'B');
    });
  });
}
