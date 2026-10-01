/// Floor map use cases (Module 24).
///
/// Layout maintenance needs `ward_room.write`; the map itself is read with
/// `ward_floor.read`. Occupancy is composed here from beds and assignments
/// rather than stored, so a bed is attributed to exactly one room and the map
/// can never contradict the ward.
library;

import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/floormap/floormap.dart';
import 'package:nodex_hms/domain/floormap/floormap_repository.dart';
import 'package:uuid/uuid.dart';

/// Registers a room on the floor plan. Requires `ward_room.write`.
final class RegisterWardRoomUseCase {
  /// Creates the use case.
  RegisterWardRoomUseCase({required this._repository});

  final FloorMapRepository _repository;

  /// Registers [roomCode] on [floorLabel].
  Future<WardRoom> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String facilityId,
    required String roomCode,
    required String roomName,
    required WardRoomType roomType,
    required String floorLabel,
    required int capacity,
    String? wardId,
    int gridX = 0,
    int gridY = 0,
    int gridSpanX = 1,
    int gridSpanY = 1,
  }) async {
    policy.require(NodexPermissions.wardRoomWrite);
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (facilityId.isEmpty) {
      fieldErrors['facility_id'] = 'Facility is required.';
    }
    if (roomCode.trim().isEmpty) {
      fieldErrors['room_code'] = 'Room code is required.';
    }
    if (roomName.trim().isEmpty) {
      fieldErrors['room_name'] = 'Room name is required.';
    }
    if (floorLabel.trim().isEmpty) {
      fieldErrors['floor_label'] = 'Floor label is required.';
    }
    if (capacity < 1 || capacity > 500) {
      fieldErrors['capacity'] = 'Capacity must be 1 to 500.';
    }
    if (gridX < 0 || gridX >= 200) {
      fieldErrors['grid_x'] = 'Grid column must be 0 to 199.';
    }
    if (gridY < 0 || gridY >= 200) {
      fieldErrors['grid_y'] = 'Grid row must be 0 to 199.';
    }
    if (gridSpanX < 1 || gridSpanX > 20) {
      fieldErrors['grid_span_x'] = 'Width must be 1 to 20 cells.';
    }
    if (gridSpanY < 1 || gridSpanY > 20) {
      fieldErrors['grid_span_y'] = 'Height must be 1 to 20 cells.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Ward room failed validation.',
        fieldErrors: fieldErrors,
        code: 'ward_room_invalid',
      );
    }
    // Offline-first means two devices can both try to claim a code. Catching it
    // here keeps the failure on the form instead of surfacing as a rejected
    // upload after the clinician has moved on.
    final WardRoom? clash = await _repository.roomByCode(
      facilityId,
      roomCode.trim(),
    );
    if (clash != null) {
      throw const ValidationError(
        message: 'Room code already used in this facility.',
        fieldErrors: <String, String>{
          'room_code': 'Room code already used in this facility.',
        },
        code: 'ward_room_code_taken',
      );
    }
    final DateTime now = DateTime.now().toUtc();
    return _repository.upsertRoom(
      WardRoom(
        id: const Uuid().v4(),
        tenantId: tenantId,
        facilityId: facilityId,
        wardId: wardId,
        roomCode: roomCode.trim(),
        roomName: roomName.trim(),
        roomType: roomType,
        floorLabel: floorLabel.trim(),
        capacity: capacity,
        gridX: gridX,
        gridY: gridY,
        gridSpanX: gridSpanX,
        gridSpanY: gridSpanY,
        status: WardRoomStatus.active,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }
}

/// Changes a room's declared capacity or position. Requires
/// `ward_room.write`.
final class UpdateWardRoomUseCase {
  /// Creates the use case.
  UpdateWardRoomUseCase({required this._repository});

  final FloorMapRepository _repository;

  /// Updates [original], refusing a room already out of the layout.
  Future<WardRoom> call({
    required AuthorizationPolicy policy,
    required WardRoom original,
    required int capacity,
    int? gridX,
    int? gridY,
    int? gridSpanX,
    int? gridSpanY,
    String? roomName,
  }) async {
    policy.require(NodexPermissions.wardRoomWrite);
    if (original.isRetired) {
      throw const AuthorizationError(
        message: 'Retired rooms are frozen and cannot be edited.',
        code: 'ward_room_closed',
      );
    }
    final Map<String, String> fieldErrors = <String, String>{};
    if (capacity < 1 || capacity > 500) {
      fieldErrors['capacity'] = 'Capacity must be 1 to 500.';
    }
    final int? spanX = gridSpanX;
    final int? spanY = gridSpanY;
    if (spanX != null && (spanX < 1 || spanX > 20)) {
      fieldErrors['grid_span_x'] = 'Width must be 1 to 20 cells.';
    }
    if (spanY != null && (spanY < 1 || spanY > 20)) {
      fieldErrors['grid_span_y'] = 'Height must be 1 to 20 cells.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Ward room update failed validation.',
        fieldErrors: fieldErrors,
        code: 'ward_room_invalid',
      );
    }
    final DateTime now = DateTime.now().toUtc();
    final String? name = roomName?.trim();
    return _repository.upsertRoom(
      WardRoom(
        id: original.id,
        tenantId: original.tenantId,
        facilityId: original.facilityId,
        wardId: original.wardId,
        roomCode: original.roomCode,
        roomName: name == null || name.isEmpty ? original.roomName : name,
        roomType: original.roomType,
        floorLabel: original.floorLabel,
        capacity: capacity,
        gridX: gridX ?? original.gridX,
        gridY: gridY ?? original.gridY,
        gridSpanX: gridSpanX ?? original.gridSpanX,
        gridSpanY: gridSpanY ?? original.gridSpanY,
        status: original.status,
        createdAt: original.createdAt,
        updatedAt: now,
      ),
    );
  }
}

/// Retires a room with a reason. Requires `ward_room.write`.
///
/// Retiring rather than deleting keeps historical floor maps readable and
/// stops the room appearing in current occupancy.
final class RetireWardRoomUseCase {
  /// Creates the use case.
  RetireWardRoomUseCase({required this._repository});

  final FloorMapRepository _repository;

  /// Retires [original], recording who and why.
  Future<WardRoom> call({
    required AuthorizationPolicy policy,
    required WardRoom original,
    required String retiredBy,
    required String reason,
  }) async {
    policy.require(NodexPermissions.wardRoomWrite);
    if (original.isRetired) {
      throw const AuthorizationError(
        message: 'This room is already retired.',
        code: 'ward_room_closed',
      );
    }
    if (reason.trim().isEmpty) {
      throw const ValidationError(
        message: 'Retiring a room requires a reason.',
        code: 'ward_room_retirement_reason_required',
      );
    }
    final DateTime now = DateTime.now().toUtc();
    return _repository.upsertRoom(
      WardRoom(
        id: original.id,
        tenantId: original.tenantId,
        facilityId: original.facilityId,
        wardId: original.wardId,
        roomCode: original.roomCode,
        roomName: original.roomName,
        roomType: original.roomType,
        floorLabel: original.floorLabel,
        capacity: original.capacity,
        gridX: original.gridX,
        gridY: original.gridY,
        gridSpanX: original.gridSpanX,
        gridSpanY: original.gridSpanY,
        status: WardRoomStatus.retired,
        retiredBy: retiredBy,
        retiredAt: now,
        retirementReason: reason.trim(),
        createdAt: original.createdAt,
        updatedAt: now,
      ),
    );
  }
}

/// Composes the live occupancy of one floor. Requires `ward_floor.read`.
///
/// Each bed is attributed to exactly one room: a ward's beds belong to the
/// lowest-coded occupiable room mapped to that ward. Without that rule a ward
/// drawn as several rooms would report its beds once per room and the floor
/// would appear busier than it is.
final class FloorOccupancyUseCase {
  /// Creates the use case.
  FloorOccupancyUseCase({required this._repository});

  final FloorMapRepository _repository;

  /// Reads [floorLabel] and returns its rooms with live occupancy.
  Future<FloorOccupancy> call({
    required AuthorizationPolicy policy,
    required String floorLabel,
  }) async {
    policy.require(NodexPermissions.wardFloorRead);
    final String floor = floorLabel.trim();
    if (floor.isEmpty) {
      throw const ValidationError(
        message: 'A floor label is required.',
        fieldErrors: <String, String>{'floor_label': 'Enter a floor.'},
        code: 'floor_label_required',
      );
    }
    final List<WardRoom> rooms = await _repository.roomsForFloor(floor);
    final List<FloorSpace> spaces = await _repository.spacesForFloor(floor);
    final List<BedOccupancy> beds = await _repository.bedsForFloor(floor);

    // The first occupiable room per ward, in code order, owns that ward's beds.
    final Map<String, WardRoom> ownerByWard = <String, WardRoom>{};
    for (final WardRoom room in rooms) {
      final String? wardId = room.wardId;
      if (wardId == null || !room.isOccupiable) continue;
      ownerByWard.putIfAbsent(wardId, () => room);
    }

    final Map<String, List<BedOccupancy>> bedsByRoom =
        <String, List<BedOccupancy>>{};
    for (final BedOccupancy bed in beds) {
      final String? wardId = bed.wardId;
      // A bed whose ward has no room drawn on this layout is omitted rather
      // than attributed to an arbitrary room.
      if (wardId == null) continue;
      final WardRoom? owner = ownerByWard[wardId];
      if (owner == null) continue;
      bedsByRoom.putIfAbsent(owner.id, () => <BedOccupancy>[]).add(bed);
    }

    return FloorOccupancy(
      floorLabel: floor,
      rooms: rooms
          .map(
            (WardRoom room) => RoomOccupancy(
              room: room,
              beds: bedsByRoom[room.id] ?? const <BedOccupancy>[],
            ),
          )
          .toList(growable: false),
      spaces: spaces,
    );
  }
}
