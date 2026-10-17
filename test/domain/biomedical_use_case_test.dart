/// Tests for the biomedical use cases, state machine and helpers (Module 29).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/authorization_snapshot.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/domain/biomedical/biomedical.dart';
import 'package:nodex_hms/domain/biomedical/biomedical_repository.dart';
import 'package:nodex_hms/domain/biomedical/biomedical_use_cases.dart';

import 'biomedical_repository_test.dart' show FakeBiomedicalStore;

AuthorizationPolicy policyWith(Set<String> permissions) {
  final DateTime issuedAt = DateTime.now().toUtc();
  return AuthorizationPolicy(
    snapshot: AuthorizationSnapshot(
      snapshotId: 'snapshot-1',
      tenantId: 'tenant-1',
      userId: 'admin-1',
      deviceId: 'device-1',
      revision: 1,
      issuedAt: issuedAt,
      expiresAt: issuedAt.add(const Duration(days: 30)),
      payloadDigest: 'digest',
      roles: const <String>{NodexRoles.hospitalSuperAdmin},
      permissions: permissions,
      offlinePermissions: permissions,
      facilityIds: const <String>{'f-1'},
      departmentIds: const <String>{},
      wardIds: const <String>{},
    ),
    connectivity: ConnectivityState.online,
  );
}

void main() {
  late FakeBiomedicalStore store;
  late DefaultBiomedicalRepository repository;
  late RegisterAssetUseCase registerAsset;
  late UpdateAssetUseCase updateAsset;
  late SetAssetStatusUseCase setAssetStatus;
  late DecommissionAssetUseCase decommissionAsset;
  late RaiseBreakdownUseCase raiseBreakdown;
  late AdvanceBreakdownUseCase advanceBreakdown;
  late RecordMaintenanceUseCase recordMaintenance;
  late ReadBiomedicalUseCase readBiomedical;

  const Set<String> manage = <String>{NodexPermissions.biomedicalManage};
  const Set<String> maintain = <String>{NodexPermissions.biomedicalMaintain};
  const Set<String> reader = <String>{NodexPermissions.biomedicalRead};

  setUp(() {
    store = FakeBiomedicalStore();
    repository = DefaultBiomedicalRepository(
      store: store,
      logger: NodexLogger(
        sinks: <NodexLogSink>[InMemoryLogSink()],
        minimumLevel: NodexLogLevel.trace,
      ),
    );
    registerAsset = RegisterAssetUseCase(repository: repository);
    updateAsset = UpdateAssetUseCase(repository: repository);
    setAssetStatus = SetAssetStatusUseCase(repository: repository);
    decommissionAsset = DecommissionAssetUseCase(repository: repository);
    raiseBreakdown = RaiseBreakdownUseCase(repository: repository);
    advanceBreakdown = AdvanceBreakdownUseCase(repository: repository);
    recordMaintenance = RecordMaintenanceUseCase(repository: repository);
    readBiomedical = ReadBiomedicalUseCase(repository: repository);
  });

  Future<String> asset({String tag = 'A-1'}) => registerAsset(
    policy: policyWith(manage),
    tenantId: 'tenant-1',
    createdBy: 'user-1',
    facilityId: 'f-1',
    assetTag: tag,
    name: 'Infusion pump',
  );

  Future<String> ticketFor(String assetId) => raiseBreakdown(
    policy: policyWith(maintain),
    tenantId: 'tenant-1',
    createdBy: 'user-1',
    assetId: assetId,
    facilityId: 'f-1',
    reportedBy: 'user-1',
    symptom: 'Alarm on every start',
  );

  Future<BreakdownTicket> readTicket(String id) async =>
      (await repository.ticketById(id))!;

  Future<BiomedicalAsset> readAsset(String id) async =>
      (await repository.assetById(id))!;

  test('register asset requires biomedical.manage and a tag', () async {
    expect(
      () => registerAsset(
        policy: policyWith(<String>{}),
        tenantId: 'tenant-1',
        createdBy: 'user-1',
        facilityId: 'f-1',
        assetTag: 'A-1',
        name: 'Pump',
      ),
      throwsA(isA<NodexError>()),
    );
    expect(() => asset(tag: '   '), throwsA(isA<NodexError>()));
    expect(await asset(), isNotEmpty);
  });

  test('status moves between live states but not to decommissioned', () async {
    final String id = await asset();
    final BiomedicalAsset created = await readAsset(id);
    await setAssetStatus(
      policy: policyWith(manage),
      asset: created,
      status: AssetStatus.outOfService,
    );
    expect((await readAsset(id)).status, AssetStatus.outOfService);
    final BiomedicalAsset moved = await readAsset(id);
    expect(
      () => setAssetStatus(
        policy: policyWith(manage),
        asset: moved,
        status: AssetStatus.decommissioned,
      ),
      throwsA(isA<NodexError>()),
    );
  });

  test('decommission is terminal and an open ticket blocks it', () async {
    final String id = await asset();
    final String ticketId = await ticketFor(id);
    final BiomedicalAsset blocked = await readAsset(id);
    expect(
      () => decommissionAsset(policy: policyWith(manage), asset: blocked),
      throwsA(isA<NodexError>()),
    );
    await advanceBreakdown(
      policy: policyWith(maintain),
      ticket: await readTicket(ticketId),
      to: TicketStatus.cancelled,
      cancellationReason: 'No fault found',
    );
    await decommissionAsset(
      policy: policyWith(manage),
      asset: await readAsset(id),
    );
    final BiomedicalAsset retired = await readAsset(id);
    expect(retired.status, AssetStatus.decommissioned);
    expect(
      () => decommissionAsset(policy: policyWith(manage), asset: retired),
      throwsA(isA<NodexError>()),
    );
    expect(
      () => updateAsset(
        policy: policyWith(manage),
        asset: retired,
        facilityId: 'f-1',
        assetTag: 'A-9',
        name: 'Pump',
      ),
      throwsA(isA<NodexError>()),
    );
  });

  test(
    'raise breakdown validates the asset and refuses a retired one',
    () async {
      expect(
        () => raiseBreakdown(
          policy: policyWith(<String>{}),
          tenantId: 'tenant-1',
          createdBy: 'user-1',
          assetId: 'missing',
          facilityId: 'f-1',
          reportedBy: 'user-1',
          symptom: 'Broken',
        ),
        throwsA(isA<NodexError>()),
      );
      expect(
        () => raiseBreakdown(
          policy: policyWith(maintain),
          tenantId: 'tenant-1',
          createdBy: 'user-1',
          assetId: 'missing',
          facilityId: 'f-1',
          reportedBy: 'user-1',
          symptom: 'Broken',
        ),
        throwsA(isA<NodexError>()),
      );
      final String id = await asset();
      await decommissionAsset(
        policy: policyWith(manage),
        asset: await readAsset(id),
      );
      expect(() => ticketFor(id), throwsA(isA<NodexError>()));
    },
  );

  test(
    'the fault lifecycle advances stage by stage and drives the asset',
    () async {
      final String id = await asset();
      final String ticketId = await ticketFor(id);
      BreakdownTicket ticket = await readTicket(ticketId);
      expect(ticket.status, TicketStatus.reported);

      // Cannot skip a stage.
      expect(
        () => advanceBreakdown(
          policy: policyWith(maintain),
          ticket: ticket,
          to: TicketStatus.inRepair,
        ),
        throwsA(isA<NodexError>()),
      );

      await advanceBreakdown(
        policy: policyWith(maintain),
        ticket: ticket,
        to: TicketStatus.acknowledged,
      );
      ticket = await readTicket(ticketId);
      expect(ticket.status, TicketStatus.acknowledged);
      expect(ticket.acknowledgedAt, isNotNull);

      await advanceBreakdown(
        policy: policyWith(maintain),
        ticket: ticket,
        to: TicketStatus.inRepair,
      );
      ticket = await readTicket(ticketId);
      expect((await readAsset(id)).status, AssetStatus.underRepair);

      // Resolving needs an account of the repair.
      expect(
        () => advanceBreakdown(
          policy: policyWith(maintain),
          ticket: ticket,
          to: TicketStatus.resolved,
        ),
        throwsA(isA<NodexError>()),
      );
      await advanceBreakdown(
        policy: policyWith(maintain),
        ticket: ticket,
        to: TicketStatus.resolved,
        resolutionNotes: 'Replaced pressure sensor',
      );
      ticket = await readTicket(ticketId);
      expect(ticket.status, TicketStatus.resolved);
      expect(ticket.resolvedAt, isNotNull);
      expect(ticket.resolutionNotes, 'Replaced pressure sensor');
      // The instrument returns to service with the repair.
      expect((await readAsset(id)).status, AssetStatus.inService);

      // A closed ticket is frozen.
      expect(
        () => advanceBreakdown(
          policy: policyWith(maintain),
          ticket: ticket,
          to: TicketStatus.cancelled,
        ),
        throwsA(isA<NodexError>()),
      );
    },
  );

  test('record maintenance validates the schedule and the asset', () async {
    expect(
      () => recordMaintenance(
        policy: policyWith(maintain),
        tenantId: 'tenant-1',
        assetId: 'missing',
        kind: MaintenanceKind.calibration,
        result: MaintenanceResult.pass,
      ),
      throwsA(isA<NodexError>()),
    );
    final String id = await asset();
    // Next due cannot precede the service.
    expect(
      () => recordMaintenance(
        policy: policyWith(maintain),
        tenantId: 'tenant-1',
        assetId: id,
        kind: MaintenanceKind.calibration,
        result: MaintenanceResult.pass,
        performedAt: DateTime.utc(2026, 6, 1),
        nextDueAt: DateTime.utc(2026, 1, 1),
      ),
      throwsA(isA<NodexError>()),
    );
    final String recordId = await recordMaintenance(
      policy: policyWith(maintain),
      tenantId: 'tenant-1',
      assetId: id,
      kind: MaintenanceKind.calibration,
      result: MaintenanceResult.pass,
      performedAt: DateTime.utc(2026, 1, 1),
      nextDueAt: DateTime.utc(2026, 7, 1),
      reference: 'CERT-1',
    );
    expect(recordId, isNotEmpty);
    final List<MaintenanceRecord> history = await readBiomedical
        .maintenanceHistory(
          policy: policyWith(reader),
          tenantId: 'tenant-1',
          assetId: id,
        );
    expect(history, hasLength(1));
    expect(history.first.nextDueAt, DateTime.utc(2026, 7, 1));
  });

  test('the board derives calibration state and open tickets, most urgent '
      'first', () async {
    final String overdue = await asset(tag: 'B-1');
    final String dueSoon = await asset(tag: 'A-1');
    final String current = await asset(tag: 'D-1');
    await asset(tag: 'C-1');

    Future<void> calibration(String assetId, String due) =>
        repository.registerMaintenanceRecord(<String, Object?>{
          'id': 'm-$assetId',
          'tenant_id': 'tenant-1',
          'asset_id': assetId,
          'ticket_id': null,
          'kind': 'calibration',
          'result': 'pass',
          'performed_at': '2026-01-01T00:00:00.000Z',
          'performed_by': null,
          'provider': null,
          'next_due_at': due,
          'reference': null,
          'notes': null,
          'created_at': '2026-01-01T00:00:00.000Z',
        });

    await calibration(overdue, '2026-01-01T00:00:00.000Z');
    await calibration(dueSoon, '2026-02-01T00:00:00.000Z');
    await calibration(current, '2026-06-01T00:00:00.000Z');
    await ticketFor(dueSoon);

    final List<AssetBoardEntry> board = await readBiomedical.board(
      policy: policyWith(reader),
      tenantId: 'tenant-1',
      now: DateTime.utc(2026, 1, 15),
    );
    expect(
      board.map((AssetBoardEntry e) => e.asset.assetTag).toList(),
      <String>['B-1', 'A-1', 'D-1', 'C-1'],
    );
    expect(board[0].dueState, CalibrationDueState.overdue);
    expect(board[1].dueState, CalibrationDueState.dueSoon);
    expect(board[2].dueState, CalibrationDueState.current);
    expect(board[3].dueState, CalibrationDueState.notScheduled);
    expect(board[1].openTicketCount, 1);
    expect(board[0].lastService, isNotNull);
    expect(board[3].lastService, isNull);

    // Reading the board requires biomedical.read.
    expect(
      () => readBiomedical.board(
        policy: policyWith(<String>{}),
        tenantId: 'tenant-1',
      ),
      throwsA(isA<NodexError>()),
    );
  });

  test('the fault state machine and due helper behave as documented', () {
    expect(
      breakdownCanAdvance(TicketStatus.reported, TicketStatus.acknowledged),
      isTrue,
    );
    expect(
      breakdownCanAdvance(TicketStatus.reported, TicketStatus.inRepair),
      isFalse,
    );
    expect(
      breakdownCanAdvance(TicketStatus.acknowledged, TicketStatus.cancelled),
      isTrue,
    );
    expect(
      breakdownCanAdvance(TicketStatus.inRepair, TicketStatus.resolved),
      isTrue,
    );
    expect(
      breakdownCanAdvance(TicketStatus.resolved, TicketStatus.cancelled),
      isFalse,
    );

    final DateTime asOf = DateTime.utc(2026, 1, 15);
    expect(
      calibrationDueState(nextDueAt: null, now: asOf),
      CalibrationDueState.notScheduled,
    );
    expect(
      calibrationDueState(nextDueAt: DateTime.utc(2026, 6, 1), now: asOf),
      CalibrationDueState.current,
    );
    expect(
      calibrationDueState(nextDueAt: DateTime.utc(2026, 2, 1), now: asOf),
      CalibrationDueState.dueSoon,
    );
    expect(
      calibrationDueState(nextDueAt: DateTime.utc(2026, 1, 1), now: asOf),
      CalibrationDueState.overdue,
    );

    expect(MaintenanceKind.fromWire('safety_test'), MaintenanceKind.safetyTest);
    expect(AssetStatus.fromWire('under_repair'), AssetStatus.underRepair);
    expect(
      AssetCriticality.fromWire('life_support'),
      AssetCriticality.lifeSupport,
    );
    expect(TicketPriority.fromWire('critical'), TicketPriority.critical);
    expect(TicketStatus.fromWire('resolved').isTerminal, isTrue);
  });
}
