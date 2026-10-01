/// Floor map entity decoding and occupancy arithmetic tests (Module 24).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/domain/floormap/floormap.dart';

void main() {
  group('WardRoomType wire decoding', () {
    test('round-trips every wire value', () {
      for (final WardRoomType type in WardRoomType.values) {
        expect(WardRoomType.fromWire(type.wireValue), type);
      }
    });

    test('falls back to ward for unknown values', () {
      expect(WardRoomType.fromWire('rooftop'), WardRoomType.ward);
    });

    test('only clinical areas hold beds', () {
      expect(WardRoomType.ward.holdsBeds, isTrue);
      expect(WardRoomType.icu.holdsBeds, isTrue);
      expect(WardRoomType.emergency.holdsBeds, isTrue);
      expect(WardRoomType.theatre.holdsBeds, isFalse);
      expect(WardRoomType.pharmacy.holdsBeds, isFalse);
      expect(WardRoomType.utility.holdsBeds, isFalse);
      expect(WardRoomType.office.holdsBeds, isFalse);
      expect(WardRoomType.diagnostics.holdsBeds, isFalse);
    });
  });

  group('WardRoomStatus wire decoding', () {
    test('round-trips every wire value', () {
      for (final WardRoomStatus status in WardRoomStatus.values) {
        expect(WardRoomStatus.fromWire(status.wireValue), status);
      }
    });

    test('falls back to active for unknown values', () {
      expect(WardRoomStatus.fromWire('demolished'), WardRoomStatus.active);
    });
  });

  group('WardRoom.fromRow', () {
    test('decodes an active ward room', () {
      final WardRoom room = WardRoom.fromRow(<String, Object?>{
        'id': 'room-1',
        'tenant_id': 'tenant-1',
        'facility_id': 'facility-1',
        'ward_id': 'ward-1',
        'room_code': 'A-101',
        'room_name': 'Ashford Wing',
        'room_type': 'ward',
        'floor_label': 'First',
        'capacity': 24,
        'grid_x': 2,
        'grid_y': 3,
        'grid_span_x': 4,
        'grid_span_y': 2,
        'status': 'active',
        'retired_by': null,
        'retired_at': null,
        'retirement_reason': null,
        'created_at': DateTime.utc(2026, 9, 1),
        'updated_at': DateTime.utc(2026, 9, 1),
      });

      expect(room.wardId, 'ward-1');
      expect(room.roomType, WardRoomType.ward);
      expect(room.capacity, 24);
      expect(room.gridSpanX, 4);
      expect(room.isRetired, isFalse);
      expect(room.isOccupiable, isTrue);
      expect(room.retirementReason, isNull);
    });

    test('decodes a retired non-clinical room', () {
      final WardRoom room = WardRoom.fromRow(<String, Object?>{
        'id': 'room-2',
        'tenant_id': 'tenant-1',
        'facility_id': 'facility-1',
        'ward_id': null,
        'room_code': 'S-002',
        'room_name': 'Old Store',
        'room_type': 'utility',
        'floor_label': 'Ground',
        'capacity': 1,
        'grid_x': 0,
        'grid_y': 0,
        'grid_span_x': 1,
        'grid_span_y': 1,
        'status': 'retired',
        'retired_by': 'admin-1',
        'retired_at': DateTime.utc(2026, 9, 10),
        'retirement_reason': 'Decommissioned.',
        'created_at': DateTime.utc(2026, 8, 1),
        'updated_at': DateTime.utc(2026, 9, 10),
      });

      expect(room.wardId, isNull);
      expect(room.isRetired, isTrue);
      expect(room.retiredBy, 'admin-1');
      expect(
        room.isOccupiable,
        isFalse,
        reason: 'a retired room leaves current occupancy',
      );
    });
  });

  group('BedOccupancy', () {
    test('a bed with a patient is occupied', () {
      const BedOccupancy bed = BedOccupancy(
        bedId: 'bed-1',
        bedCode: 'A-01',
        bedStatus: 'occupied',
        wardId: 'ward-1',
        patientId: 'patient-1',
      );
      expect(bed.isOccupied, isTrue);
    });

    test('a bed without a patient is free', () {
      const BedOccupancy bed = BedOccupancy(
        bedId: 'bed-2',
        bedCode: 'A-02',
        bedStatus: 'available',
        wardId: 'ward-1',
      );
      expect(bed.isOccupied, isFalse);
      expect(bed.wardId, 'ward-1');
    });
  });

  group('RoomOccupancy arithmetic', () {
    WardRoom room({int capacity = 4, WardRoomType type = WardRoomType.ward}) =>
        WardRoom(
          id: 'room-1',
          tenantId: 'tenant-1',
          facilityId: 'facility-1',
          roomCode: 'A-101',
          roomName: 'Ashford Wing',
          roomType: type,
          floorLabel: 'First',
          capacity: capacity,
          gridX: 0,
          gridY: 0,
          gridSpanX: 1,
          gridSpanY: 1,
          status: WardRoomStatus.active,
          createdAt: DateTime.utc(2026, 9, 1),
          updatedAt: DateTime.utc(2026, 9, 1),
        );

    test('counts occupancy against mapped beds', () {
      final RoomOccupancy occupancy = RoomOccupancy(
        room: room(),
        beds: const <BedOccupancy>[
          BedOccupancy(
            bedId: 'b1',
            bedCode: 'A-01',
            bedStatus: 'occupied',
            patientId: 'p1',
          ),
          BedOccupancy(
            bedId: 'b2',
            bedCode: 'A-02',
            bedStatus: 'occupied',
            patientId: 'p2',
          ),
          BedOccupancy(bedId: 'b3', bedCode: 'A-03', bedStatus: 'available'),
          BedOccupancy(bedId: 'b4', bedCode: 'A-04', bedStatus: 'available'),
        ],
      );

      expect(occupancy.mappedBeds, 4);
      expect(occupancy.occupiedBeds, 2);
      expect(occupancy.availableBeds, 2);
      expect(occupancy.bedOccupancyRate, 0.5);
      expect(occupancy.isAtCapacity, isFalse);
    });

    test('a room with no mapped beds is not at capacity', () {
      final RoomOccupancy occupancy = RoomOccupancy(
        room: room(type: WardRoomType.pharmacy),
        beds: const <BedOccupancy>[],
      );
      expect(occupancy.bedOccupancyRate, 0);
      expect(occupancy.isAtCapacity, isFalse);
    });

    test('occupancy reaches the declared capacity', () {
      final RoomOccupancy occupancy = RoomOccupancy(
        room: room(capacity: 2),
        beds: const <BedOccupancy>[
          BedOccupancy(
            bedId: 'b1',
            bedCode: 'A-01',
            bedStatus: 'occupied',
            patientId: 'p1',
          ),
          BedOccupancy(
            bedId: 'b2',
            bedCode: 'A-02',
            bedStatus: 'occupied',
            patientId: 'p2',
          ),
        ],
      );
      expect(occupancy.isAtCapacity, isTrue);
      expect(occupancy.availableBeds, 0);
    });
  });

  group('FloorOccupancy arithmetic', () {
    WardRoom room(String id, {int capacity = 2}) => WardRoom(
      id: id,
      tenantId: 'tenant-1',
      facilityId: 'facility-1',
      roomCode: id,
      roomName: id,
      roomType: WardRoomType.ward,
      floorLabel: 'First',
      capacity: capacity,
      gridX: 0,
      gridY: 0,
      gridSpanX: 1,
      gridSpanY: 1,
      status: WardRoomStatus.active,
      createdAt: DateTime.utc(2026, 9, 1),
      updatedAt: DateTime.utc(2026, 9, 1),
    );

    test('aggregates every room on the floor', () {
      final FloorOccupancy floor = FloorOccupancy(
        floorLabel: 'First',
        rooms: <RoomOccupancy>[
          RoomOccupancy(
            room: room('r1'),
            beds: const <BedOccupancy>[
              BedOccupancy(
                bedId: 'b1',
                bedCode: 'A-01',
                bedStatus: 'occupied',
                patientId: 'p1',
              ),
              BedOccupancy(
                bedId: 'b2',
                bedCode: 'A-02',
                bedStatus: 'available',
              ),
            ],
          ),
          RoomOccupancy(
            room: room('r2'),
            beds: const <BedOccupancy>[
              BedOccupancy(
                bedId: 'b3',
                bedCode: 'B-01',
                bedStatus: 'occupied',
                patientId: 'p2',
              ),
            ],
          ),
        ],
        spaces: const <FloorSpace>[],
      );

      expect(floor.totalBeds, 3);
      expect(floor.occupiedBeds, 2);
      expect(floor.availableBeds, 1);
      expect(floor.occupancyRate, closeTo(2 / 3, 0.0001));
      expect(floor.roomsAtCapacity, 0);
      expect(floor.isFull, isFalse);
    });

    test('a floor with no beds is not full', () {
      const FloorOccupancy floor = FloorOccupancy(
        floorLabel: 'Ground',
        rooms: <RoomOccupancy>[],
        spaces: <FloorSpace>[],
      );
      expect(floor.totalBeds, 0);
      expect(floor.occupancyRate, 0);
      expect(floor.isFull, isFalse);
    });

    test('a floor whose beds are all taken is full', () {
      final FloorOccupancy floor = FloorOccupancy(
        floorLabel: 'First',
        rooms: <RoomOccupancy>[
          RoomOccupancy(
            room: room('r1', capacity: 1),
            beds: const <BedOccupancy>[
              BedOccupancy(
                bedId: 'b1',
                bedCode: 'A-01',
                bedStatus: 'occupied',
                patientId: 'p1',
              ),
            ],
          ),
        ],
        spaces: const <FloorSpace>[],
      );
      expect(floor.isFull, isTrue);
      expect(floor.roomsAtCapacity, 1);
    });
  });
}
