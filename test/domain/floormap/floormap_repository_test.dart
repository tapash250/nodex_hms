/// Floor map repository tests over the local projection (Module 24).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/floormap/floormap.dart';
import 'package:nodex_hms/domain/floormap/floormap_repository.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';

/// In-memory stand-in for the PowerSync-backed patient store.
final class FakeFloorMapStore implements PatientLocalStore {
  /// Tables keyed by name, then row id.
  final Map<String, Map<String, Map<String, Object?>>> tables =
      <String, Map<String, Map<String, Object?>>>{};

  /// When true, every operation throws to simulate a closed database.
  bool closed = false;

  Map<String, Map<String, Object?>> _table(String name) =>
      tables.putIfAbsent(name, () => <String, Map<String, Object?>>{});

  /// Seeds one row into a table, creating the table if needed.
  void seedRow(String table, String id, Map<String, Object?> row) =>
      _table(table)[id] = row;

  void _guard() {
    if (closed) {
      throw const PersistenceError(
        message: 'The local clinical database has not been opened.',
        code: 'database_not_open',
      );
    }
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String sql,
    List<Object?> parameters,
  ) async {
    _guard();
    if (sql.contains(LocalTables.wardRooms)) {
      final Iterable<Map<String, Object?>> rows = _table(LocalTables.wardRooms)
          .values;
      if (sql.contains('where facility_id = ? and room_code = ?')) {
        final Iterable<Map<String, Object?>> rows = _table(
          LocalTables.wardRooms,
        ).values;
        return rows
            .where(
              (Map<String, Object?> row) =>
                  row['facility_id'] == parameters[0] &&
                  row['room_code'] == parameters[1],
            )
            .take(1)
            .toList(growable: false);
      }
      if (sql.contains('where floor_label = ?')) {
        return rows
            .where(
              (Map<String, Object?> row) => row['floor_label'] == parameters[0],
            )
            .toList(growable: false);
      }
      return rows.toList(growable: false);
    }
    if (sql.contains('from ${LocalTables.wards}')) {
      final Iterable<Map<String, Object?>> rows = _table(LocalTables.wards)
          .values;
      return rows
          .where(
            (Map<String, Object?> row) => row['floor_label'] == parameters[0],
          )
          .toList(growable: false);
    }
    if (sql.contains('from ${LocalTables.beds} b')) {
      // The bed/assignment join, resolved in memory.
      final String floor = parameters[1]! as String;
      final List<Map<String, Object?>> out = <Map<String, Object?>>[];
      for (final Map<String, Object?> bed in _table(LocalTables.beds).values) {
        final String wardId = bed['ward_id']! as String;
        final Map<String, Object?>? ward = _table(LocalTables.wards)[wardId];
        if (ward == null || ward['floor_label'] != floor) continue;
        final Iterable<Map<String, Object?>> assignments = _table(
          LocalTables.bedAssignments,
        ).values.where((Map<String, Object?> a) => a['bed_id'] == bed['id']);
        String? patientId;
        for (final Map<String, Object?> assignment in assignments) {
          if (assignment['status'] == parameters[0]) {
            patientId = assignment['patient_id'] as String?;
          }
        }
        out.add(<String, Object?>{
          'bed_id': bed['id'],
          'bed_code': bed['bed_code'],
          'bed_status': bed['status'],
          'ward_id': wardId,
          'patient_id': patientId,
        });
      }
      return out;
    }
    throw UnimplementedError('FakeFloorMapStore cannot run: $sql');
  }

  @override
  Future<Map<String, Object?>?> getById(String table, String id) async {
    _guard();
    return _table(table)[id];
  }

  @override
  Future<void> insert(String table, Map<String, Object?> row) async {
    _guard();
    _table(table)[row['id']! as String] = Map<String, Object?>.from(row);
  }

  @override
  Future<void> update(
    String table,
    String id,
    Map<String, Object?> changes,
  ) async {
    _guard();
    final Map<String, Object?>? existing = _table(table)[id];
    if (existing == null) {
      throw StateError('row $id not found in $table');
    }
    existing.addAll(changes);
  }
}

void main() {
  late FakeFloorMapStore store;
  late DefaultFloorMapRepository repository;

  setUp(() {
    store = FakeFloorMapStore();
    repository = DefaultFloorMapRepository(
      store: store,
      logger: NodexLogger(
        sinks: <NodexLogSink>[InMemoryLogSink()],
        minimumLevel: NodexLogLevel.trace,
      ),
    );
  });

  WardRoom room({
    String id = 'room-1',
    String code = 'A-101',
    String facilityId = 'facility-1',
    String floor = 'First',
    String? wardId = 'ward-1',
    int capacity = 4,
    WardRoomType type = WardRoomType.ward,
    WardRoomStatus status = WardRoomStatus.active,
  }) => WardRoom(
    id: id,
    tenantId: 'tenant-1',
    facilityId: facilityId,
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
    status: status,
    createdAt: DateTime.utc(2026, 9, 1),
    updatedAt: DateTime.utc(2026, 9, 1),
  );

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
    String status = 'available',
    String? patientId,
  }) {
    store.seedRow(LocalTables.beds, id, <String, Object?>{
      'id': id,
      'ward_id': wardId,
      'bed_code': code,
      'status': status,
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

  group('rooms', () {
    test('missing rooms read as null', () async {
      expect(await repository.roomById('absent'), isNull);
    });

    test('upsert inserts then updates in place', () async {
      await repository.upsertRoom(room());
      expect((await repository.roomById('room-1'))!.capacity, 4);

      await repository.upsertRoom(room(capacity: 12));
      expect((await repository.roomById('room-1'))!.capacity, 12);
      expect(store.tables[LocalTables.wardRooms]!.length, 1);
    });

    test('roomByCode is scoped to one facility', () async {
      await repository.upsertRoom(room(id: 'room-1', code: 'A-101'));
      // The same code in another building is not a clash.
      await repository.upsertRoom(
        room(id: 'room-2', code: 'A-101', facilityId: 'facility-2'),
      );

      expect(
        (await repository.roomByCode('facility-1', 'A-101'))!.id,
        'room-1',
      );
      expect(
        (await repository.roomByCode('facility-2', 'A-101'))!.id,
        'room-2',
      );
      expect(await repository.roomByCode('facility-1', 'A-999'), isNull);
    });

    test('floor scope filters and allRooms returns everything', () async {
      await repository.upsertRoom(room(id: 'room-1', code: 'A-101'));
      await repository.upsertRoom(
        room(id: 'room-2', code: 'B-201', floor: 'Second'),
      );

      expect((await repository.roomsForFloor('First')).single.id, 'room-1');
      expect(await repository.roomsForFloor('Third'), isEmpty);
      expect((await repository.allRooms()).length, 2);
    });
  });

  group('floor spaces', () {
    test('spaces are read from the wards on the floor', () async {
      seedWard(id: 'ward-1', floor: 'First');
      seedWard(id: 'ward-2', floor: 'Second');

      final List<FloorSpace> spaces = await repository.spacesForFloor('First');
      expect(spaces.single.wardId, 'ward-1');
      expect(spaces.single.displayName, 'Ward ward-1');
      expect(spaces.single.floorLabel, 'First');
    });
  });

  group('bed occupancy', () {
    test('a floor with no beds reads empty', () async {
      expect(await repository.bedsForFloor('First'), isEmpty);
    });

    test('only active assignments mark a bed occupied', () async {
      seedWard();
      seedBed(id: 'bed-1', wardId: 'ward-1', code: 'A-01');
      seedBed(
        id: 'bed-2',
        wardId: 'ward-1',
        code: 'A-02',
        patientId: 'patient-1',
      );
      // A released assignment must not keep the bed looking occupied.
      store.seedRow(
        LocalTables.bedAssignments,
        'assignment-bed-2',
        <String, Object?>{
          'id': 'assignment-bed-2',
          'bed_id': 'bed-2',
          'patient_id': 'patient-1',
          'status': 'released',
        },
      );

      final List<BedOccupancy> beds = await repository.bedsForFloor('First');
      expect(beds.length, 2);
      expect(
        beds.firstWhere((BedOccupancy b) => b.bedId == 'bed-1').isOccupied,
        isFalse,
      );
      expect(
        beds.firstWhere((BedOccupancy b) => b.bedId == 'bed-2').isOccupied,
        isFalse,
      );
      expect(beds.every((BedOccupancy b) => b.wardId == 'ward-1'), isTrue);
    });

    test('beds on another floor are excluded', () async {
      seedWard(id: 'ward-1', floor: 'First');
      seedWard(id: 'ward-2', floor: 'Second');
      seedBed(id: 'bed-1', wardId: 'ward-1', code: 'A-01');
      seedBed(id: 'bed-2', wardId: 'ward-2', code: 'B-01');

      final List<BedOccupancy> beds = await repository.bedsForFloor('First');
      expect(beds.single.bedId, 'bed-1');
    });
  });

  group('failure mapping', () {
    test('a closed database surfaces as a persistence error', () async {
      store.closed = true;
      expect(repository.allRooms, throwsA(isA<PersistenceError>()));
    });
  });
}
