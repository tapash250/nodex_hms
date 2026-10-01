/// Hospital floor map entities (Module 24).
///
/// A room is the unit the floor plan draws: it belongs to a facility, belongs
/// optionally to a ward, and carries its floor, grid geometry and declared
/// capacity. Occupancy is never stored here — it is derived from beds and bed
/// assignments so the map can never disagree with the authoritative
/// allocation.
// ignore_for_file: sort_constructors_first
library;

import 'package:meta/meta.dart';

/// What a room is used for.
enum WardRoomType {
  ward('ward'),
  icu('icu'),
  theatre('theatre'),
  emergency('emergency'),
  diagnostics('diagnostics'),
  pharmacy('pharmacy'),
  utility('utility'),
  office('office');

  const WardRoomType(this.wireValue);

  final String wireValue;

  String get label => switch (this) {
    WardRoomType.ward => 'Ward',
    WardRoomType.icu => 'ICU',
    WardRoomType.theatre => 'Theatre',
    WardRoomType.emergency => 'Emergency',
    WardRoomType.diagnostics => 'Diagnostics',
    WardRoomType.pharmacy => 'Pharmacy',
    WardRoomType.utility => 'Utility',
    WardRoomType.office => 'Office',
  };

  /// Whether the room holds beds, and so participates in occupancy.
  bool get holdsBeds => this == ward || this == icu || this == emergency;

  static WardRoomType fromWire(String value) => WardRoomType.values.firstWhere(
    (WardRoomType type) => type.wireValue == value,
    orElse: () => WardRoomType.ward,
  );
}

/// Whether a room is still part of the layout.
enum WardRoomStatus {
  active('active'),
  retired('retired');

  const WardRoomStatus(this.wireValue);

  final String wireValue;

  String get label => switch (this) {
    WardRoomStatus.active => 'Active',
    WardRoomStatus.retired => 'Retired',
  };

  bool get isRetired => this == retired;

  static WardRoomStatus fromWire(String value) =>
      WardRoomStatus.values.firstWhere(
        (WardRoomStatus status) => status.wireValue == value,
        orElse: () => WardRoomStatus.active,
      );
}

/// A room on the floor plan.
@immutable
final class WardRoom {
  const WardRoom({
    required this.id,
    required this.tenantId,
    required this.facilityId,
    required this.roomCode,
    required this.roomName,
    required this.roomType,
    required this.floorLabel,
    required this.capacity,
    required this.gridX,
    required this.gridY,
    required this.gridSpanX,
    required this.gridSpanY,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.wardId,
    this.retiredBy,
    this.retiredAt,
    this.retirementReason,
  });

  factory WardRoom.fromRow(Map<String, Object?> row) {
    final Object? wardId = row['ward_id'];
    final Object? retiredBy = row['retired_by'];
    final Object? retiredAt = row['retired_at'];
    final Object? retirementReason = row['retirement_reason'];
    return WardRoom(
      id: row['id']! as String,
      tenantId: row['tenant_id']! as String,
      facilityId: row['facility_id']! as String,
      wardId: wardId is String ? wardId : null,
      roomCode: row['room_code']! as String,
      roomName: row['room_name']! as String,
      roomType: WardRoomType.fromWire(row['room_type']! as String),
      floorLabel: row['floor_label']! as String,
      capacity: (row['capacity']! as num).toInt(),
      gridX: (row['grid_x']! as num).toInt(),
      gridY: (row['grid_y']! as num).toInt(),
      gridSpanX: (row['grid_span_x']! as num).toInt(),
      gridSpanY: (row['grid_span_y']! as num).toInt(),
      status: WardRoomStatus.fromWire(row['status']! as String),
      retiredBy: retiredBy is String ? retiredBy : null,
      retiredAt: retiredAt is DateTime ? retiredAt : null,
      retirementReason: retirementReason is String ? retirementReason : null,
      createdAt: row['created_at']! as DateTime,
      updatedAt: row['updated_at']! as DateTime,
    );
  }

  final String id;
  final String tenantId;
  final String facilityId;
  final String? wardId;
  final String roomCode;
  final String roomName;
  final WardRoomType roomType;
  final String floorLabel;
  final int capacity;
  final int gridX;
  final int gridY;
  final int gridSpanX;
  final int gridSpanY;
  final WardRoomStatus status;
  final String? retiredBy;
  final DateTime? retiredAt;
  final String? retirementReason;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isRetired => status.isRetired;

  /// Whether occupancy is meaningful for this room.
  bool get isOccupiable => roomType.holdsBeds && !isRetired;
}

/// A ward as the floor map sees it: a named area on a floor.
@immutable
final class FloorSpace {
  /// Creates a floor space.
  const FloorSpace({
    required this.wardId,
    required this.code,
    required this.displayName,
    required this.wardType,
    required this.floorLabel,
  });

  /// Ward identifier.
  final String wardId;

  /// Ward code.
  final String code;

  /// Human-readable ward name.
  final String displayName;

  /// Ward classification.
  final String wardType;

  /// The floor the ward sits on.
  final String floorLabel;
}

/// One bed and who, if anyone, occupies it.
@immutable
final class BedOccupancy {
  /// Creates a bed occupancy reading.
  const BedOccupancy({
    required this.bedId,
    required this.bedCode,
    required this.bedStatus,
    this.wardId,
    this.patientId,
  });

  /// Bed identifier.
  final String bedId;

  /// Bed code as labelled in the ward.
  final String bedCode;

  /// Stored bed status, for example available or occupied.
  final String bedStatus;

  /// The ward the bed belongs to, which is what the layout maps it by.
  final String? wardId;

  /// The patient currently allocated to the bed, when there is one.
  final String? patientId;

  /// Whether the bed currently holds a patient.
  bool get isOccupied => patientId != null;
}

/// A room with the beds inside it and how full it is.
@immutable
final class RoomOccupancy {
  /// Creates a room occupancy reading.
  const RoomOccupancy({required this.room, required this.beds});

  /// The room itself.
  final WardRoom room;

  /// Beds mapped to the room.
  final List<BedOccupancy> beds;

  /// Beds currently holding a patient.
  int get occupiedBeds =>
      beds.where((BedOccupancy bed) => bed.isOccupied).length;

  /// Beds currently free.
  int get availableBeds => beds.length - occupiedBeds;

  /// Beds mapped to the room, whether occupied or not.
  int get mappedBeds => beds.length;

  /// Occupancy against the beds actually mapped, not the declared capacity.
  ///
  /// Declared capacity is what the room is staffed for; mapped beds are what
  /// the census knows about, and conflating them would hide a layout that has
  /// drifted from the beds configured against it.
  double get bedOccupancyRate => beds.isEmpty ? 0 : occupiedBeds / beds.length;

  /// Whether occupancy has reached the declared capacity.
  bool get isAtCapacity => occupiedBeds >= room.capacity;
}

/// One floor and everything drawn on it.
@immutable
final class FloorOccupancy {
  /// Creates a floor reading.
  const FloorOccupancy({
    required this.floorLabel,
    required this.rooms,
    required this.spaces,
  });

  /// The floor being shown.
  final String floorLabel;

  /// Rooms on the floor.
  final List<RoomOccupancy> rooms;

  /// Wards on the floor.
  final List<FloorSpace> spaces;

  /// Every bed mapped on this floor.
  int get totalBeds =>
      rooms.fold(0, (int sum, RoomOccupancy room) => sum + room.mappedBeds);

  /// Every bed on this floor currently holding a patient.
  int get occupiedBeds =>
      rooms.fold(0, (int sum, RoomOccupancy room) => sum + room.occupiedBeds);

  /// Every bed on this floor currently free.
  int get availableBeds => totalBeds - occupiedBeds;

  /// Whole-floor occupancy against mapped beds.
  double get occupancyRate => totalBeds == 0 ? 0 : occupiedBeds / totalBeds;

  /// Rooms currently at their declared capacity.
  int get roomsAtCapacity =>
      rooms.where((RoomOccupancy room) => room.isAtCapacity).length;

  /// Whether the floor is full.
  bool get isFull => totalBeds > 0 && availableBeds == 0;
}
