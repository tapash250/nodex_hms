/// Tests for the floor map use cases (Module 24).
///
/// Layout maintenance needs `ward_room.write`; reading the map needs
/// `ward_floor.read`. Occupancy is derived, never stored, and a ward drawn as
/// several rooms must not report its beds once per room.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/authorization_snapshot.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/floormap/floormap.dart';
import 'package:nodex_hms/domain/floormap/floormap_repository.dart';
import 'package:nodex_hms/domain/floormap/floormap_use_cases.dart';

import 'floormap_repository_test.dart' show FakeFloorMapStore;

/// Builds a policy holding exactly [permissions].
AuthorizationPolicy policyWith(Set<String> permissions) {
  final DateTime issuedAt = DateTime.now().toUtc();
  return AuthorizationPolicy(
    snapshot: AuthorizationSnapshot(
      snapshotId: 'snapshot-1',
      tenantId: 'tenant-1',
      userId: 'clinician-1',
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

void main() {
  late FakeFloorMapStore store;
  late RegisterWardRoomUseCase register;
  late UpdateWardRoomUseCase update;
  late RetireWardRoomUseCase retire;
  late FloorOccupancyUseCase occupancy;

  const Set<String> admin = <String>{NodexPermissions.wardRoomWrite};
  const Set<String> viewer = <String>{NodexPermissions.wardFloorRead};

  setUp(() {
    store = FakeFloorMapStore();
    final repository = DefaultFloorMapRepository(
      store: store,
      logger: NodexLogger(
        sinks: <NodexLogSink>[InMemoryLogSink()],
        minimumLevel: NodexLogLevel.trace,
      ),
    );
    register = RegisterWardRoomUseCase(repository: repository);
    update = UpdateWardRoomUseCase(repository: repository);
    retire = RetireWardRoomUseCase(repository: repository);
    occupancy = FloorOccupancyUseCase(repository: repository);
  });

  void seedWard({String id = 'ward-1', String floor = 'First'}) {
    store.seedRow(LocalTables.wards, id, <String, Object?>{
      'id': id,
      'code': 'W-$id',
      'display_name': 'Ward $id',
      'ward_type': 'general',
      'floor_label': floor,
    });
  }

  void seedBed({
    required String id,
    required String wardId,
    String code = 'A-01',
    String? patientId,
  }) {
    store.seedRow(LocalTables.beds, id, <String, Object?>{
      'id': id,
      'ward_id': wardId,
      'bed_code': code,
      'status': patientId == null ? 'available' : 'occupied',
    });
    if (patientId != null) {
      store.seedRow(
        LocalTables.bedAssignments,
        'assignment-$id',
        <String, Object?>{
          'id': 'assignment-$id',
          'bed_id': id,
          'patient_id': patientId,
          'status': 'active',
        },
      );
    }
  }

  Future<WardRoom> seedRoom({
    String id = 'room-1',
    String code = 'A-101',
    String? wardId = 'ward-1',
    int capacity = 4,
    WardRoomType type = WardRoomType.ward,
    String floor = 'First',
  }) async {
    final WardRoom room = WardRoom(
      id: id,
      tenantId: 'tenant-1',
      facilityId: 'facility-1',
      wardId: wardId,
      roomCode: code,
      roomName: 'Room $code',
      roomType: type,
      floorLabel: floor,
      capacity: capacity,
      gridX: 0,
      gridY: 0,
      gridSpanX: 1,
      gridSpanY: 1,
      status: WardRoomStatus.active,
      createdAt: DateTime.utc(2026, 9, 1),
      updatedAt: DateTime.utc(2026, 9, 1),
    );
    store.seedRow(LocalTables.wardRooms, id, <String, Object?>{
      'id': id,
      'tenant_id': 'tenant-1',
      'facility_id': 'facility-1',
      'ward_id': wardId,
      'room_code': code,
      'room_name': room.roomName,
      'room_type': type.wireValue,
      'floor_label': floor,
      'capacity': capacity,
      'grid_x': 0,
      'grid_y': 0,
      'grid_span_x': 1,
      'grid_span_y': 1,
      'status': 'active',
      'retired_by': null,
      'retired_at': null,
      'retirement_reason': null,
      'created_at': room.createdAt,
      'updated_at': room.updatedAt,
    });
    return room;
  }

  group('registration', () {
    test('registering a room requires ward_room.write', () {
      expect(
        register.call(
          policy: policyWith(viewer),
          tenantId: 'tenant-1',
          facilityId: 'facility-1',
          roomCode: 'A-101',
          roomName: 'Ashford Wing',
          roomType: WardRoomType.ward,
          floorLabel: 'First',
          capacity: 24,
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('identity, naming, floor and capacity are validated', () {
      expect(
        register.call(
          policy: policyWith(admin),
          tenantId: 'tenant-1',
          facilityId: 'facility-1',
          roomCode: '  ',
          roomName: '  ',
          roomType: WardRoomType.ward,
          floorLabel: '  ',
          capacity: 0,
        ),
        throwsA(
          isA<ValidationError>()
              .having(
                (ValidationError error) => error.code,
                'code',
                'ward_room_invalid',
              )
              .having(
                (ValidationError error) => error.fieldErrors.keys,
                'fields',
                containsAll(<String>{
                  'room_code',
                  'room_name',
                  'floor_label',
                  'capacity',
                }),
              ),
        ),
      );
    });

    test('grid geometry outside the plan is rejected', () {
      expect(
        register.call(
          policy: policyWith(admin),
          tenantId: 'tenant-1',
          facilityId: 'facility-1',
          roomCode: 'A-101',
          roomName: 'Ashford Wing',
          roomType: WardRoomType.ward,
          floorLabel: 'First',
          capacity: 4,
          gridX: 500,
          gridSpanY: 0,
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.fieldErrors.keys,
            'fields',
            containsAll(<String>{'grid_x', 'grid_span_y'}),
          ),
        ),
      );
    });

    test('a code already drawn in the facility is rejected', () async {
      await seedRoom(id: 'room-1', code: 'A-101');
      expect(
        register.call(
          policy: policyWith(admin),
          tenantId: 'tenant-1',
          facilityId: 'facility-1',
          roomCode: 'A-101',
          roomName: 'Duplicate',
          roomType: WardRoomType.ward,
          floorLabel: 'First',
          capacity: 4,
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'ward_room_code_taken',
          ),
        ),
      );
    });

    test('the same code in another facility is allowed', () async {
      await seedRoom(id: 'room-1', code: 'A-101');
      final WardRoom room = await register.call(
        policy: policyWith(admin),
        tenantId: 'tenant-1',
        facilityId: 'facility-2',
        roomCode: 'A-101',
        roomName: 'Other building',
        roomType: WardRoomType.ward,
        floorLabel: 'First',
        capacity: 4,
      );
      expect(room.facilityId, 'facility-2');
    });

    test('a room is registered active with trimmed text', () async {
      final WardRoom room = await register.call(
        policy: policyWith(admin),
        tenantId: 'tenant-1',
        facilityId: 'facility-1',
        roomCode: ' A-101 ',
        roomName: ' Ashford Wing ',
        roomType: WardRoomType.icu,
        floorLabel: ' First ',
        capacity: 12,
        gridX: 2,
        gridY: 3,
      );

      expect(room.status, WardRoomStatus.active);
      expect(room.roomCode, 'A-101');
      expect(room.roomName, 'Ashford Wing');
      expect(room.floorLabel, 'First');
      expect(room.capacity, 12);
      expect(room.gridX, 2);
      expect(room.isOccupiable, isTrue);
    });
  });

  group('layout maintenance', () {
    test('updating requires ward_room.write', () async {
      final WardRoom room = await seedRoom();
      expect(
        update.call(policy: policyWith(viewer), original: room, capacity: 8),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('capacity is updated and untouched fields are preserved', () async {
      final WardRoom room = await seedRoom();
      final WardRoom updated = await update.call(
        policy: policyWith(admin),
        original: room,
        capacity: 30,
        roomName: '  Ashford North  ',
      );

      expect(updated.capacity, 30);
      expect(updated.roomName, 'Ashford North');
      expect(updated.roomCode, room.roomCode);
      expect(updated.floorLabel, room.floorLabel);
      expect(updated.createdAt, room.createdAt);
    });

    test('an out-of-range capacity is rejected', () async {
      final WardRoom room = await seedRoom();
      expect(
        update.call(policy: policyWith(admin), original: room, capacity: 0),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.fieldErrors.keys,
            'fields',
            contains('capacity'),
          ),
        ),
      );
    });

    test('a retired room is frozen against updates', () async {
      final WardRoom room = await seedRoom();
      final WardRoom retired = await retire.call(
        policy: policyWith(admin),
        original: room,
        retiredBy: 'admin-1',
        reason: 'Refurbishment.',
      );
      expect(
        update.call(policy: policyWith(admin), original: retired, capacity: 40),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'ward_room_closed',
          ),
        ),
      );
    });

    test('retiring requires a reason and freezes the room', () async {
      final WardRoom room = await seedRoom();
      expect(
        retire.call(
          policy: policyWith(admin),
          original: room,
          retiredBy: 'admin-1',
          reason: ' ',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'ward_room_retirement_reason_required',
          ),
        ),
      );

      final WardRoom retired = await retire.call(
        policy: policyWith(admin),
        original: room,
        retiredBy: 'admin-1',
        reason: '  Refurbishment.  ',
      );
      expect(retired.status, WardRoomStatus.retired);
      expect(retired.retirementReason, 'Refurbishment.');
      expect(retired.retiredBy, 'admin-1');
      expect(
        retire.call(
          policy: policyWith(admin),
          original: retired,
          retiredBy: 'admin-2',
          reason: 'Again.',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });
  });

  group('occupancy', () {
    test('reading the map requires ward_floor.read', () {
      expect(
        occupancy.call(policy: policyWith(admin), floorLabel: 'First'),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('a floor label is required', () {
      expect(
        occupancy.call(policy: policyWith(viewer), floorLabel: '  '),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'floor_label_required',
          ),
        ),
      );
    });

    test('an undrawn floor reports nothing', () async {
      final FloorOccupancy floor = await occupancy.call(
        policy: policyWith(viewer),
        floorLabel: 'Third',
      );
      expect(floor.rooms, isEmpty);
      expect(floor.totalBeds, 0);
      expect(floor.isFull, isFalse);
    });

    test('a room reports the live occupancy of its ward', () async {
      seedWard();
      await seedRoom();
      seedBed(id: 'bed-1', wardId: 'ward-1', code: 'A-01', patientId: 'p1');
      seedBed(id: 'bed-2', wardId: 'ward-1', code: 'A-02');

      final FloorOccupancy floor = await occupancy.call(
        policy: policyWith(viewer),
        floorLabel: 'First',
      );
      expect(floor.totalBeds, 2);
      expect(floor.occupiedBeds, 1);
      expect(floor.availableBeds, 1);
      expect(floor.occupancyRate, 0.5);
      expect(floor.rooms.single.mappedBeds, 2);
      expect(floor.spaces.single.wardId, 'ward-1');
    });

    test('a ward drawn as several rooms reports its beds once', () async {
      seedWard();
      await seedRoom(id: 'room-1', code: 'A-101', wardId: 'ward-1');
      await seedRoom(id: 'room-2', code: 'A-102', wardId: 'ward-1');
      seedBed(id: 'bed-1', wardId: 'ward-1', code: 'A-01', patientId: 'p1');
      seedBed(id: 'bed-2', wardId: 'ward-1', code: 'A-02');

      final FloorOccupancy floor = await occupancy.call(
        policy: policyWith(viewer),
        floorLabel: 'First',
      );

      expect(
        floor.totalBeds,
        2,
        reason: 'the ward beds belong to one room, not one room each',
      );
      expect(
        floor.rooms.where((RoomOccupancy room) => room.mappedBeds > 0).length,
        1,
      );
    });

    test('a non-clinical room holds no beds', () async {
      seedWard();
      await seedRoom(
        id: 'room-pharmacy',
        code: 'P-001',
        wardId: null,
        type: WardRoomType.pharmacy,
      );
      await seedRoom(id: 'room-ward', code: 'A-101', wardId: 'ward-1');
      seedBed(id: 'bed-1', wardId: 'ward-1', code: 'A-01');

      final FloorOccupancy floor = await occupancy.call(
        policy: policyWith(viewer),
        floorLabel: 'First',
      );
      final RoomOccupancy pharmacy = floor.rooms.firstWhere(
        (RoomOccupancy room) => room.room.roomType == WardRoomType.pharmacy,
      );
      expect(pharmacy.mappedBeds, 0);
      expect(floor.totalBeds, 1);
    });

    test('a bed whose ward is not drawn is not attributed to a room', () async {
      seedWard(id: 'ward-1', floor: 'First');
      seedWard(id: 'ward-2', floor: 'First');
      await seedRoom(id: 'room-1', code: 'A-101', wardId: 'ward-1');
      seedBed(id: 'bed-1', wardId: 'ward-2', code: 'B-01', patientId: 'p1');

      final FloorOccupancy floor = await occupancy.call(
        policy: policyWith(viewer),
        floorLabel: 'First',
      );
      expect(floor.totalBeds, 0);
      expect(floor.rooms.single.mappedBeds, 0);
    });

    test('a retired room leaves current occupancy', () async {
      seedWard();
      final WardRoom room = await seedRoom();
      seedBed(id: 'bed-1', wardId: 'ward-1', code: 'A-01', patientId: 'p1');
      await retire.call(
        policy: policyWith(admin),
        original: room,
        retiredBy: 'admin-1',
        reason: 'Refurbishment.',
      );

      final FloorOccupancy floor = await occupancy.call(
        policy: policyWith(viewer),
        floorLabel: 'First',
      );
      expect(floor.totalBeds, 0);
      expect(floor.rooms.single.room.isRetired, isTrue);
    });

    test('a full floor is reported as full', () async {
      seedWard();
      await seedRoom(capacity: 2);
      seedBed(id: 'bed-1', wardId: 'ward-1', code: 'A-01', patientId: 'p1');
      seedBed(id: 'bed-2', wardId: 'ward-1', code: 'A-02', patientId: 'p2');

      final FloorOccupancy floor = await occupancy.call(
        policy: policyWith(viewer),
        floorLabel: 'First',
      );
      expect(floor.isFull, isTrue);
      expect(floor.roomsAtCapacity, 1);
      expect(floor.occupancyRate, 1);
    });
  });
}
