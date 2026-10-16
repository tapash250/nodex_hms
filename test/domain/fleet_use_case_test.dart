/// Tests for the fleet use cases, state machine and helpers (Module 27).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/authorization_snapshot.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/domain/fleet/fleet.dart';
import 'package:nodex_hms/domain/fleet/fleet_repository.dart';
import 'package:nodex_hms/domain/fleet/fleet_use_cases.dart';

import 'fleet_repository_test.dart' show FakeFleetStore;

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
  late FakeFleetStore store;
  late DefaultFleetRepository repository;
  late RegisterAmbulanceUseCase registerVehicle;
  late UpdateAmbulanceUseCase updateVehicle;
  late ArchiveAmbulanceUseCase archiveVehicle;
  late ScheduleDutyUseCase scheduleDuty;
  late CloseDutyUseCase closeDuty;
  late RaiseDispatchUseCase raiseDispatch;
  late AdvanceDispatchUseCase advanceDispatch;
  late CancelDispatchUseCase cancelDispatch;
  late RecordPingUseCase recordPing;
  late ReadFleetUseCase readFleet;

  const Set<String> manage = <String>{NodexPermissions.fleetManage};
  const Set<String> dispatch = <String>{NodexPermissions.fleetDispatch};
  const Set<String> reader = <String>{NodexPermissions.fleetRead};

  setUp(() {
    store = FakeFleetStore();
    repository = DefaultFleetRepository(
      store: store,
      logger: NodexLogger(
        sinks: <NodexLogSink>[InMemoryLogSink()],
        minimumLevel: NodexLogLevel.trace,
      ),
    );
    registerVehicle = RegisterAmbulanceUseCase(repository: repository);
    updateVehicle = UpdateAmbulanceUseCase(repository: repository);
    archiveVehicle = ArchiveAmbulanceUseCase(repository: repository);
    scheduleDuty = ScheduleDutyUseCase(repository: repository);
    closeDuty = CloseDutyUseCase(repository: repository);
    raiseDispatch = RaiseDispatchUseCase(repository: repository);
    advanceDispatch = AdvanceDispatchUseCase(repository: repository);
    cancelDispatch = CancelDispatchUseCase(repository: repository);
    recordPing = RecordPingUseCase(repository: repository);
    readFleet = ReadFleetUseCase(repository: repository);
  });

  Future<String> vehicle({String callSign = 'UNIT-1'}) => registerVehicle(
    policy: policyWith(manage),
    tenantId: 'tenant-1',
    createdBy: 'user-1',
    facilityId: 'f-1',
    callSign: callSign,
  );

  test(
    'register vehicle requires fleet.manage and validates the call sign',
    () async {
      expect(
        () => registerVehicle(
          policy: policyWith(<String>{}),
          tenantId: 'tenant-1',
          createdBy: 'user-1',
          facilityId: 'f-1',
          callSign: 'UNIT-1',
        ),
        throwsA(isA<NodexError>()),
      );
      expect(() => vehicle(callSign: '   '), throwsA(isA<NodexError>()));
      expect(await vehicle(), isNotEmpty);
    },
  );

  test(
    'archive is terminal and an archived vehicle cannot be edited',
    () async {
      final String id = await vehicle();
      final Ambulance created = (await repository.ambulanceById(id))!;
      await archiveVehicle(policy: policyWith(manage), ambulance: created);
      final Ambulance archived = (await repository.ambulanceById(id))!;
      expect(archived.serviceStatus, AmbulanceServiceStatus.archived);
      expect(
        () => archiveVehicle(policy: policyWith(manage), ambulance: archived),
        throwsA(isA<NodexError>()),
      );
      expect(
        () => updateVehicle(
          policy: policyWith(manage),
          ambulance: archived,
          facilityId: 'f-1',
          callSign: 'UNIT-9',
        ),
        throwsA(isA<NodexError>()),
      );
    },
  );

  test(
    'schedule duty forbids overlapping vehicle and driver windows',
    () async {
      final String a1 = await vehicle(callSign: 'UNIT-1');
      final String a2 = await vehicle(callSign: 'UNIT-2');
      await scheduleDuty(
        policy: policyWith(manage),
        tenantId: 'tenant-1',
        createdBy: 'user-1',
        ambulanceId: a1,
        driverUserId: 'driver-1',
        startsAt: DateTime.utc(2026, 10, 20, 8),
        endsAt: DateTime.utc(2026, 10, 20, 16),
      );
      // Same vehicle, overlapping.
      expect(
        () => scheduleDuty(
          policy: policyWith(manage),
          tenantId: 'tenant-1',
          createdBy: 'user-1',
          ambulanceId: a1,
          driverUserId: 'driver-2',
          startsAt: DateTime.utc(2026, 10, 20, 12),
          endsAt: DateTime.utc(2026, 10, 20, 20),
        ),
        throwsA(isA<NodexError>()),
      );
      // Same driver, different vehicle, overlapping.
      expect(
        () => scheduleDuty(
          policy: policyWith(manage),
          tenantId: 'tenant-1',
          createdBy: 'user-1',
          ambulanceId: a2,
          driverUserId: 'driver-1',
          startsAt: DateTime.utc(2026, 10, 20, 12),
          endsAt: DateTime.utc(2026, 10, 20, 20),
        ),
        throwsA(isA<NodexError>()),
      );
      // Adjacent windows do not overlap.
      final String id = await scheduleDuty(
        policy: policyWith(manage),
        tenantId: 'tenant-1',
        createdBy: 'user-1',
        ambulanceId: a1,
        driverUserId: 'driver-1',
        startsAt: DateTime.utc(2026, 10, 20, 16),
        endsAt: DateTime.utc(2026, 10, 20, 20),
      );
      expect(id, isNotEmpty);
    },
  );

  test('close duty is terminal and one-way', () async {
    final String a1 = await vehicle();
    final String id = await scheduleDuty(
      policy: policyWith(manage),
      tenantId: 'tenant-1',
      createdBy: 'user-1',
      ambulanceId: a1,
      driverUserId: 'driver-1',
      startsAt: DateTime.utc(2026, 10, 20, 8),
      endsAt: DateTime.utc(2026, 10, 20, 16),
    );
    final List<AmbulanceDuty> duties = await repository.listDuties(
      'tenant-1',
      ambulanceId: a1,
    );
    final AmbulanceDuty duty = duties.firstWhere(
      (AmbulanceDuty d) => d.id == id,
    );
    await closeDuty(
      policy: policyWith(manage),
      duty: duty,
      status: DutyStatus.completed,
    );
    final AmbulanceDuty closed = (await repository.listDuties(
      'tenant-1',
      ambulanceId: a1,
    )).firstWhere((AmbulanceDuty d) => d.id == id);
    expect(closed.status, DutyStatus.completed);
    expect(
      () => closeDuty(
        policy: policyWith(manage),
        duty: closed,
        status: DutyStatus.cancelled,
      ),
      throwsA(isA<NodexError>()),
    );
    expect(
      () => closeDuty(
        policy: policyWith(manage),
        duty: closed,
        status: DutyStatus.active,
      ),
      throwsA(isA<NodexError>()),
    );
  });

  test('dispatch lifecycle advances one stage at a time', () async {
    await vehicle();
    expect(
      () => raiseDispatch(
        policy: policyWith(<String>{}),
        tenantId: 'tenant-1',
        createdBy: 'user-1',
        facilityId: 'f-1',
        pickupAddress: '12 Main St',
        patientNameText: 'Unknown',
      ),
      throwsA(isA<NodexError>()),
    );
    // A dispatch must name a patient.
    expect(
      () => raiseDispatch(
        policy: policyWith(dispatch),
        tenantId: 'tenant-1',
        createdBy: 'user-1',
        facilityId: 'f-1',
        pickupAddress: '12 Main St',
      ),
      throwsA(isA<NodexError>()),
    );

    final String id = await raiseDispatch(
      policy: policyWith(dispatch),
      tenantId: 'tenant-1',
      createdBy: 'user-1',
      facilityId: 'f-1',
      pickupAddress: '12 Main St',
      patientNameText: 'Scene call',
    );
    AmbulanceDispatch job = (await repository.dispatchById(id))!;
    expect(job.status, DispatchStatus.requested);

    // Cannot skip a stage, and cannot assign without a vehicle.
    expect(
      () => advanceDispatch(
        policy: policyWith(dispatch),
        dispatch: job,
        to: DispatchStatus.enRoute,
      ),
      throwsA(isA<NodexError>()),
    );
    expect(
      () => advanceDispatch(
        policy: policyWith(dispatch),
        dispatch: job,
        to: DispatchStatus.assigned,
      ),
      throwsA(isA<NodexError>()),
    );

    final List<Ambulance> vehicles = await readFleet.ambulances(
      policy: policyWith(reader),
      tenantId: 'tenant-1',
    );
    final String ambulanceId = vehicles.first.id;

    await advanceDispatch(
      policy: policyWith(dispatch),
      dispatch: job,
      to: DispatchStatus.assigned,
      ambulanceId: ambulanceId,
    );
    job = (await repository.dispatchById(id))!;
    expect(job.status, DispatchStatus.assigned);
    expect(job.dispatchedAt, isNotNull);

    await advanceDispatch(
      policy: policyWith(dispatch),
      dispatch: job,
      to: DispatchStatus.enRoute,
    );
    job = (await repository.dispatchById(id))!;
    await advanceDispatch(
      policy: policyWith(dispatch),
      dispatch: job,
      to: DispatchStatus.onScene,
    );
    job = (await repository.dispatchById(id))!;
    expect(job.onSceneAt, isNotNull);
    await advanceDispatch(
      policy: policyWith(dispatch),
      dispatch: job,
      to: DispatchStatus.completed,
    );
    job = (await repository.dispatchById(id))!;
    expect(job.status, DispatchStatus.completed);
    expect(job.completedAt, isNotNull);
    // A closed dispatch is frozen.
    expect(
      () => cancelDispatch(policy: policyWith(dispatch), dispatch: job),
      throwsA(isA<NodexError>()),
    );
  });

  test('cancel closes a live dispatch and requires fleet.dispatch', () async {
    final String id = await raiseDispatch(
      policy: policyWith(dispatch),
      tenantId: 'tenant-1',
      createdBy: 'user-1',
      facilityId: 'f-1',
      pickupAddress: '12 Main St',
      patientNameText: 'Scene call',
    );
    final AmbulanceDispatch job = (await repository.dispatchById(id))!;
    expect(
      () => cancelDispatch(policy: policyWith(<String>{}), dispatch: job),
      throwsA(isA<NodexError>()),
    );
    await cancelDispatch(policy: policyWith(dispatch), dispatch: job);
    final AmbulanceDispatch cancelled = (await repository.dispatchById(id))!;
    expect(cancelled.status, DispatchStatus.cancelled);
    expect(
      () => cancelDispatch(policy: policyWith(dispatch), dispatch: cancelled),
      throwsA(isA<NodexError>()),
    );
  });

  test(
    'record ping validates coordinates and requires fleet.dispatch',
    () async {
      expect(
        () => recordPing(
          policy: policyWith(<String>{}),
          tenantId: 'tenant-1',
          ambulanceId: 'a-1',
          latitude: 0,
          longitude: 0,
        ),
        throwsA(isA<NodexError>()),
      );
      expect(
        () => recordPing(
          policy: policyWith(dispatch),
          tenantId: 'tenant-1',
          ambulanceId: 'a-1',
          latitude: 200,
          longitude: 0,
        ),
        throwsA(isA<NodexError>()),
      );
      final String id = await recordPing(
        policy: policyWith(dispatch),
        tenantId: 'tenant-1',
        ambulanceId: 'a-1',
        latitude: 23.81,
        longitude: 90.41,
        speedKph: 35,
      );
      expect(id, isNotEmpty);
    },
  );

  test(
    'read fleet requires fleet.read and hides archived by default',
    () async {
      expect(
        () => readFleet.ambulances(
          policy: policyWith(<String>{}),
          tenantId: 'tenant-1',
        ),
        throwsA(isA<NodexError>()),
      );
      final String id = await vehicle();
      final Ambulance created = (await repository.ambulanceById(id))!;
      await archiveVehicle(policy: policyWith(manage), ambulance: created);
      final List<Ambulance> visible = await readFleet.ambulances(
        policy: policyWith(reader),
        tenantId: 'tenant-1',
      );
      expect(visible, isEmpty);
      final List<Ambulance> all = await readFleet.ambulances(
        policy: policyWith(reader),
        tenantId: 'tenant-1',
        includeArchived: true,
      );
      expect(all, hasLength(1));
    },
  );

  test('dispatch state machine and window helpers behave as documented', () {
    expect(
      dispatchCanAdvance(DispatchStatus.requested, DispatchStatus.assigned),
      isTrue,
    );
    expect(
      dispatchCanAdvance(DispatchStatus.requested, DispatchStatus.enRoute),
      isFalse,
    );
    expect(
      dispatchCanAdvance(DispatchStatus.onScene, DispatchStatus.completed),
      isTrue,
    );
    expect(
      dispatchCanAdvance(DispatchStatus.assigned, DispatchStatus.cancelled),
      isTrue,
    );
    expect(
      dispatchCanAdvance(DispatchStatus.completed, DispatchStatus.cancelled),
      isFalse,
    );
    expect(
      dispatchCanAdvance(DispatchStatus.requested, DispatchStatus.requested),
      isFalse,
    );

    expect(
      dutyWindowsOverlap(
        aStart: DateTime.utc(2026, 10, 20, 8),
        aEnd: DateTime.utc(2026, 10, 20, 16),
        bStart: DateTime.utc(2026, 10, 20, 16),
        bEnd: DateTime.utc(2026, 10, 20, 20),
      ),
      isFalse,
    );
    expect(
      dutyWindowsOverlap(
        aStart: DateTime.utc(2026, 10, 20, 8),
        aEnd: DateTime.utc(2026, 10, 20, 16),
        bStart: DateTime.utc(2026, 10, 20, 15),
        bEnd: DateTime.utc(2026, 10, 20, 20),
      ),
      isTrue,
    );

    expect(VehicleType.fromWire('als'), VehicleType.als);
    expect(VehicleType.fromWire('nonsense'), VehicleType.other);
    expect(
      AmbulanceServiceStatus.fromWire('archived'),
      AmbulanceServiceStatus.archived,
    );
    expect(DispatchStatus.fromWire('on_scene'), DispatchStatus.onScene);
    expect(DispatchPriority.fromWire('routine'), DispatchPriority.routine);
    expect(DutyStatus.fromWire('completed').isTerminal, isTrue);
  });
}
