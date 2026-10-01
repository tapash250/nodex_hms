/// Floor map repository contract and PowerSync-backed implementation
/// (Module 24).
///
/// Rooms are stored; occupancy is derived. The repository never persists an
/// occupancy figure, because occupancy lives in bed assignments and a cached
/// copy on the floor plan would eventually contradict the ward.
library;

import 'package:nodex_hms/core/errors/error_mapper.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/beds/bed.dart';
import 'package:nodex_hms/domain/floormap/floormap.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';

/// Read and write access to the floor layout and its derived occupancy.
abstract interface class FloorMapRepository {
  /// One room by id, or null.
  Future<WardRoom?> roomById(String id);

  /// Rooms on one floor, ordered by code.
  Future<List<WardRoom>> roomsForFloor(String floorLabel);

  /// Every room on the device, ordered by floor then code.
  Future<List<WardRoom>> allRooms();

  /// The room already holding [roomCode] within a facility, if any.
  ///
  /// Room codes repeat across buildings, so the same code is only a clash
  /// within one facility.
  Future<WardRoom?> roomByCode(String facilityId, String roomCode);

  /// Inserts or updates a room row.
  Future<WardRoom> upsertRoom(WardRoom room);

  /// Wards sitting on one floor, ordered by code.
  Future<List<FloorSpace>> spacesForFloor(String floorLabel);

  /// Beds on one floor with their current occupant, if any.
  ///
  /// Derived from beds and active bed assignments rather than stored, so the
  /// map cannot drift from the allocation the ward is actually running.
  Future<List<BedOccupancy>> bedsForFloor(String floorLabel);
}

/// Default repository over the encrypted local projection.
final class DefaultFloorMapRepository implements FloorMapRepository {
  const DefaultFloorMapRepository({
    required this._store,
    required this._logger,
  });

  static const String _module = 'domain.floormap';

  final PatientLocalStore _store;
  final NodexLogger _logger;

  @override
  Future<WardRoom?> roomByCode(String facilityId, String roomCode) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select * from ${LocalTables.wardRooms} '
        'where facility_id = ? and room_code = ? limit 1',
        <Object?>[facilityId, roomCode],
      );
      return rows.isEmpty ? null : WardRoom.fromRow(rows.first);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'floormap.roomByCode');
    }
  }

  @override
  Future<WardRoom?> roomById(String id) async {
    try {
      final Map<String, Object?>? row = await _store.getById(
        LocalTables.wardRooms,
        id,
      );
      return row == null ? null : WardRoom.fromRow(row);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'floormap.roomById');
    }
  }

  @override
  Future<List<WardRoom>> roomsForFloor(String floorLabel) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select * from ${LocalTables.wardRooms} where floor_label = ? '
        'order by room_code',
        <Object?>[floorLabel],
      );
      return rows.map(WardRoom.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'floormap.roomsForFloor');
    }
  }

  @override
  Future<List<WardRoom>> allRooms() async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select * from ${LocalTables.wardRooms} '
        'order by floor_label, room_code',
        const <Object?>[],
      );
      return rows.map(WardRoom.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'floormap.allRooms');
    }
  }

  @override
  Future<WardRoom> upsertRoom(WardRoom room) async {
    try {
      final Map<String, Object?>? existing = await _store.getById(
        LocalTables.wardRooms,
        room.id,
      );
      final Map<String, Object?> changes = <String, Object?>{
        'facility_id': room.facilityId,
        'ward_id': room.wardId,
        'room_code': room.roomCode,
        'room_name': room.roomName,
        'room_type': room.roomType.wireValue,
        'floor_label': room.floorLabel,
        'capacity': room.capacity,
        'grid_x': room.gridX,
        'grid_y': room.gridY,
        'grid_span_x': room.gridSpanX,
        'grid_span_y': room.gridSpanY,
        'status': room.status.wireValue,
        'retired_by': room.retiredBy,
        'retired_at': room.retiredAt,
        'retirement_reason': room.retirementReason,
        'updated_at': room.updatedAt,
      };
      if (existing == null) {
        await _store.insert(LocalTables.wardRooms, <String, Object?>{
          ...changes,
          'id': room.id,
          'tenant_id': room.tenantId,
          'created_at': room.createdAt,
        });
      } else {
        await _store.update(LocalTables.wardRooms, room.id, changes);
      }
      return room;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'floormap.upsertRoom');
    }
  }

  @override
  Future<List<FloorSpace>> spacesForFloor(String floorLabel) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select id, code, display_name, ward_type, floor_label '
        'from ${LocalTables.wards} where floor_label = ? order by code',
        <Object?>[floorLabel],
      );
      return rows
          .map(
            (Map<String, Object?> row) => FloorSpace(
              wardId: row['id']! as String,
              code: row['code']! as String,
              displayName: row['display_name']! as String,
              wardType: row['ward_type']! as String,
              floorLabel: row['floor_label']! as String,
            ),
          )
          .toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'floormap.spacesForFloor');
    }
  }

  @override
  Future<List<BedOccupancy>> bedsForFloor(String floorLabel) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select b.id as bed_id, b.bed_code as bed_code, b.status as '
        'bed_status, b.ward_id as ward_id, a.patient_id as patient_id '
        'from ${LocalTables.beds} b '
        'join ${LocalTables.wards} w on w.id = b.ward_id '
        'left join ${LocalTables.bedAssignments} a '
        'on a.bed_id = b.id and a.status = ? '
        'where w.floor_label = ? order by b.bed_code',
        <Object?>[BedAssignmentStatus.active.wireValue, floorLabel],
      );
      return rows
          .map(
            (Map<String, Object?> row) => BedOccupancy(
              bedId: row['bed_id']! as String,
              bedCode: row['bed_code']! as String,
              bedStatus: row['bed_status']! as String,
              wardId: row['ward_id'] is String
                  ? row['ward_id']! as String
                  : null,
              patientId: row['patient_id'] is String
                  ? row['patient_id']! as String
                  : null,
            ),
          )
          .toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'floormap.bedsForFloor');
    }
  }

  Never _mapped(Object error, StackTrace stackTrace, String operation) {
    if (error is NodexError) throw error;
    final NodexError mapped = NodexErrorMapper.map(error, operation: operation);
    _logger.error(
      _module,
      'Floor map repository failure.',
      operation: operation,
      outcome: 'failed',
      errorCode: mapped.code,
      stackTrace: stackTrace,
    );
    throw mapped;
  }
}
