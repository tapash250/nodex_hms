/// Tests for the operations dashboard (Module 02).
///
/// The dashboard exists to answer one question — where is the queue building —
/// so the tests are about the judgement it derives from the figures and the
/// order it puts them in.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/authorization_snapshot.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/operations/department_metric.dart';
import 'package:nodex_hms/domain/operations/operations_repository.dart';

/// A repository that returns a fixed set of readings.
final class _FixedOperationsRepository implements OperationsRepository {
  _FixedOperationsRepository(this.metrics);

  final List<DepartmentMetric> metrics;

  @override
  Future<List<DepartmentMetric>> listLatest() async => metrics;

  @override
  Future<List<DepartmentMetric>> listForDepartment(String departmentId) async =>
      metrics
          .where((DepartmentMetric m) => m.departmentId == departmentId)
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

DepartmentMetric _metric({
  required String departmentId,
  int waiting = 0,
  int completed = 0,
  int registrations = 0,
  double? wait,
  String? bottleneck,
  DateTime? at,
}) => DepartmentMetric(
  id: 'metric-$departmentId',
  tenantId: 'tenant-1',
  facilityId: 'facility-1',
  departmentId: departmentId,
  at: at ?? DateTime.utc(2026, 9, 12, 9),
  waitingCount: waiting,
  completedCount: completed,
  registrations: registrations,
  averageWaitMinutes: wait,
  bottleneck: bottleneck,
);

void main() {
  group('reading a reading', () {
    test('a reading is read from a local row', () {
      final DepartmentMetric metric = DepartmentMetric.fromRow(
        const <String, Object?>{
          'id': 'metric-1',
          'tenant_id': 'tenant-1',
          'facility_id': 'facility-1',
          'department_id': 'department-1',
          'metric_timestamp': '2026-09-12T09:00:00.000Z',
          'registrations': 12,
          'waiting_count': 5,
          'completed_count': 7,
          'average_wait_minutes': 42.5,
          'bottleneck': 'Only one registrar on the desk',
        },
      );
      expect(metric.waitingCount, 5);
      expect(metric.averageWaitMinutes, 42.5);
      expect(metric.bottleneck, 'Only one registrar on the desk');
    });

    test('the waiting share is derived from the counts', () {
      final DepartmentMetric metric = _metric(
        departmentId: 'a',
        waiting: 5,
        completed: 5,
      );
      expect(metric.waitingShare, 0.5);
    });

    test('a department with no patients has no waiting share', () {
      expect(_metric(departmentId: 'a').waitingShare, 0);
    });
  });

  group('judging a queue', () {
    test('a long wait is a backlog', () {
      final DepartmentMetric metric = _metric(
        departmentId: 'a',
        waiting: 3,
        wait: 75,
      );
      expect(metric.isBacklogged(), isTrue);
    });

    test('a short wait is not a backlog', () {
      final DepartmentMetric metric = _metric(
        departmentId: 'a',
        waiting: 3,
        completed: 27,
        wait: 20,
      );
      expect(metric.isBacklogged(), isFalse);
    });

    test('most of the department waiting is a backlog', () {
      final DepartmentMetric metric = _metric(
        departmentId: 'a',
        waiting: 8,
        completed: 2,
      );
      expect(metric.isBacklogged(), isTrue);
    });

    test('an empty department is not a backlog', () {
      expect(_metric(departmentId: 'a').isBacklogged(), isFalse);
    });

    test('the summary states the figures it was derived from', () {
      final DepartmentMetric metric = _metric(
        departmentId: 'a',
        waiting: 4,
        registrations: 9,
        wait: 30,
      );
      expect(metric.summary, '4 waiting · 9 registered · 30 min average wait');
    });
  });

  group('the dashboard', () {
    test('reading it requires the read permission', () async {
      await expectLater(
        ReadOperationsDashboardUseCase(
          repository: _FixedOperationsRepository(const <DepartmentMetric>[]),
        ).call(policy: _policy(<String>{NodexPermissions.operationsManage})),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('the department with the longest queue comes first', () async {
      final _FixedOperationsRepository repository = _FixedOperationsRepository(
        <DepartmentMetric>[
          _metric(departmentId: 'a', waiting: 2),
          _metric(departmentId: 'b', waiting: 9),
          _metric(departmentId: 'c', waiting: 5),
        ],
      );
      final List<DepartmentMetric> metrics =
          await ReadOperationsDashboardUseCase(repository: repository)
              .call(policy: _policy(<String>{NodexPermissions.operationsRead}));
      expect(metrics.map((DepartmentMetric m) => m.departmentId), <String>[
        'b',
        'c',
        'a',
      ]);
    });
  });
}
