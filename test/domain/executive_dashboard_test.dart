/// Tests for the executive dashboard (Module 01).
///
/// The dashboard exists to put four figures in front of somebody who can act
/// on them, each against the facility's own trailing baseline. The tests are
/// therefore about the derivation: which reading is critical, which is merely
/// worth watching, and whether the sentence cites the figure it came from.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/authorization_snapshot.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/executive/executive_kpi.dart';
import 'package:nodex_hms/domain/executive/executive_repository.dart';

/// A repository that returns a fixed set of readings.
final class _FixedExecutiveRepository implements ExecutiveKpiRepository {
  _FixedExecutiveRepository(this.snapshots);

  final List<ExecutiveKpiSnapshot> snapshots;

  @override
  Future<List<ExecutiveKpiSnapshot>> listRecent({
    required String facilityId,
    required DateTime since,
  }) async => snapshots
      .where(
        (ExecutiveKpiSnapshot snapshot) => snapshot.facilityId == facilityId,
      )
      .toList(growable: false);
}

/// A policy holding the given permissions and facility scope.
AuthorizationPolicy _policy(
  Set<String> permissions, {
  Set<String> facilityIds = const <String>{'facility-1'},
}) {
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
      facilityIds: facilityIds,
      departmentIds: const <String>{},
      wardIds: const <String>{},
    ),
    connectivity: ConnectivityState.online,
  );
}

ExecutiveKpiSnapshot _snapshot({
  required DateTime at,
  double occupancy = 80,
  int inpatients = 80,
  int erWaiting = 5,
  double gross = 1000,
  double net = 1000,
  double turnover = 10,
  double alos = 4,
  Map<String, Object?>? summary,
}) => ExecutiveKpiSnapshot(
  id: 'snapshot-${at.toIso8601String()}',
  tenantId: 'tenant-1',
  facilityId: 'facility-1',
  at: at,
  occupancyRate: occupancy,
  activeInpatients: inpatients,
  erWaitingCount: erWaiting,
  dailyGrossRevenue: gross,
  dailyNetRevenue: net,
  bedTurnoverRate: turnover,
  averageLengthOfStayDays: alos,
  aiExecutiveSummary: summary,
);

void main() {
  group('reading a snapshot', () {
    test('numeric strings from SQLite become numbers', () {
      final ExecutiveKpiSnapshot snapshot = ExecutiveKpiSnapshot.fromRow(
        const <String, Object?>{
          'id': 'snapshot-1',
          'tenant_id': 'tenant-1',
          'facility_id': 'facility-1',
          'snapshot_timestamp': '2026-09-18T09:00:00.000Z',
          'occupancy_rate': '91.25',
          'active_inpatients': 73,
          'er_waiting_count': 11,
          'daily_gross_revenue': '12000.50',
          'daily_net_revenue': '11500.25',
          'bed_turnover_rate': '12.50',
          'average_length_of_stay_days': '4.20',
          'ai_executive_summary': '{"summary":"Occupancy is the pressure."}',
        },
      );
      expect(snapshot.occupancyRate, 91.25);
      expect(snapshot.activeInpatients, 73);
      expect(snapshot.dailyNetRevenue, 11500.25);
      expect(
        snapshot.aiExecutiveSummary?['summary'],
        'Occupancy is the pressure.',
      );
    });

    test('a snapshot without a narrative has no summary', () {
      final ExecutiveKpiSnapshot snapshot = _snapshot(
        at: DateTime.utc(2026, 9, 18),
      );
      expect(snapshot.aiExecutiveSummary, isNull);
    });
  });

  group('the four risk points', () {
    test('the latest reading is not part of its own baseline', () {
      final ExecutiveKpiState state = ExecutiveKpiState(
        facilityId: 'facility-1',
        snapshots: <ExecutiveKpiSnapshot>[
          _snapshot(at: DateTime.utc(2026, 9, 18)),
          _snapshot(at: DateTime.utc(2026, 9, 17)),
          _snapshot(at: DateTime.utc(2026, 9, 16)),
        ],
      );
      expect(state.baseline.length, 2);
    });

    test('exactly four points are always stated', () {
      final ExecutiveKpiState state = ExecutiveKpiState(
        facilityId: 'facility-1',
        snapshots: <ExecutiveKpiSnapshot>[
          _snapshot(at: DateTime.utc(2026, 9, 18)),
          _snapshot(at: DateTime.utc(2026, 9, 17)),
        ],
      );
      expect(state.risks.length, 4);
      expect(state.risks.map((ExecutiveRisk risk) => risk.code), <String>[
        'occupancy',
        'emergency',
        'revenue',
        'length_of_stay',
      ]);
    });

    test('a high occupancy reading is critical and cites the baseline', () {
      final ExecutiveKpiState state = ExecutiveKpiState(
        facilityId: 'facility-1',
        snapshots: <ExecutiveKpiSnapshot>[
          _snapshot(at: DateTime.utc(2026, 9, 18), occupancy: 92),
          _snapshot(at: DateTime.utc(2026, 9, 17), occupancy: 70),
          _snapshot(at: DateTime.utc(2026, 9, 16), occupancy: 72),
        ],
      );
      final ExecutiveRisk occupancy = state.risks.first;
      expect(occupancy.level, ExecutiveRiskLevel.critical);
      expect(occupancy.detail, contains('92.00%'));
      expect(occupancy.detail, contains('71.00%'));
    });

    test('a revenue collapse is critical against its own mean', () {
      final ExecutiveKpiState state = ExecutiveKpiState(
        facilityId: 'facility-1',
        snapshots: <ExecutiveKpiSnapshot>[
          _snapshot(at: DateTime.utc(2026, 9, 18), net: 700),
          _snapshot(at: DateTime.utc(2026, 9, 17), net: 1000),
          _snapshot(at: DateTime.utc(2026, 9, 16), net: 1010),
        ],
      );
      final ExecutiveRisk revenue = state.risks[2];
      expect(revenue.level, ExecutiveRiskLevel.critical);
      expect(revenue.detail, contains('700.00'));
    });

    test('a quiet facility reports four normal points', () {
      final ExecutiveKpiState state = ExecutiveKpiState(
        facilityId: 'facility-1',
        snapshots: <ExecutiveKpiSnapshot>[
          _snapshot(at: DateTime.utc(2026, 9, 18), occupancy: 80, erWaiting: 5),
          _snapshot(at: DateTime.utc(2026, 9, 17), occupancy: 80, erWaiting: 5),
        ],
      );
      expect(
        state.risks.every(
          (ExecutiveRisk risk) => risk.level == ExecutiveRiskLevel.normal,
        ),
        isTrue,
      );
    });

    test('an approved narrative is surfaced verbatim', () {
      final ExecutiveKpiState state = ExecutiveKpiState(
        facilityId: 'facility-1',
        snapshots: <ExecutiveKpiSnapshot>[
          _snapshot(
            at: DateTime.utc(2026, 9, 18),
            summary: <String, Object?>{
              'summary': 'Occupancy and the emergency queue are the pressure.',
            },
          ),
        ],
      );
      expect(
        state.aiSummary,
        'Occupancy and the emergency queue are the pressure.',
      );
    });
  });

  group('reading the dashboard', () {
    test('it requires the executive read permission', () async {
      await expectLater(
        ReadExecutiveKpiUseCase(
          repository: _FixedExecutiveRepository(const <ExecutiveKpiSnapshot>[]),
        ).call(
          policy: _policy(<String>{NodexPermissions.operationsRead}),
          facilityId: 'facility-1',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('a facility outside the session scope is refused', () async {
      await expectLater(
        ReadExecutiveKpiUseCase(
          repository: _FixedExecutiveRepository(const <ExecutiveKpiSnapshot>[]),
        ).call(
          policy: _policy(
            <String>{NodexPermissions.executiveRead},
            facilityIds: const <String>{'facility-2'},
          ),
          facilityId: 'facility-1',
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'facility_out_of_scope',
          ),
        ),
      );
    });

    test('the use case returns only the requested facility', () async {
      final ReadExecutiveKpiUseCase useCase = ReadExecutiveKpiUseCase(
        repository: _FixedExecutiveRepository(<ExecutiveKpiSnapshot>[
          _snapshot(at: DateTime.utc(2026, 9, 18)),
        ]),
      );
      final ExecutiveKpiState state = await useCase.call(
        policy: _policy(<String>{NodexPermissions.executiveRead}),
        facilityId: 'facility-1',
        now: DateTime.utc(2026, 9, 18, 12),
      );
      expect(state.facilityId, 'facility-1');
      expect(state.snapshots.length, 1);
    });
  });
}
