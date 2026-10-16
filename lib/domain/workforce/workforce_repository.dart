/// Workforce repository contract and local implementation (Module 09).
library;

import 'package:nodex_hms/core/errors/error_mapper.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';
import 'package:nodex_hms/domain/workforce/workforce.dart';
import 'package:uuid/uuid.dart';

abstract interface class WorkforceRepository {
  Future<List<StaffShift>> listShifts(
    String tenantId, {
    String? facilityId,
    String? onDate,
    int limit = 200,
  });
  Future<StaffShift?> shiftById(String id);
  Future<String> registerShift(Map<String, Object?> row);
  Future<void> updateShift(String id, Map<String, Object?> changes);
  Future<List<DutyAllocation>> listAllocations(
    String tenantId, {
    String? shiftId,
    String? staffUserId,
    int limit = 500,
  });
  Future<DutyAllocation?> allocationById(String id);
  Future<String> registerAllocation(Map<String, Object?> row);
  Future<void> updateAllocation(String id, Map<String, Object?> changes);
  Future<List<AttendanceLog>> listAttendance(String allocationId);
  Future<String> registerAttendance(Map<String, Object?> row);
}

final class DefaultWorkforceRepository implements WorkforceRepository {
  DefaultWorkforceRepository({required this._store, required this._logger});

  static const String _module = 'domain.workforce';
  final PatientLocalStore _store;
  final NodexLogger _logger;

  @override
  Future<List<StaffShift>> listShifts(
    String tenantId, {
    String? facilityId,
    String? onDate,
    int limit = 200,
  }) async {
    try {
      final StringBuffer sql = StringBuffer(
        'select * from ${LocalTables.staffShifts} where tenant_id = ?',
      );
      final List<Object?> params = <Object?>[tenantId];
      if (facilityId != null) {
        sql.write(' and facility_id = ?');
        params.add(facilityId);
      }
      if (onDate != null) {
        sql.write(' and shift_date = ?');
        params.add(onDate);
      }
      sql.write(' order by shift_date, starts_at limit ?');
      params.add(limit);
      final List<Map<String, Object?>> rows = await _store.query(
        sql.toString(),
        params,
      );
      return rows.map(StaffShift.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'workforce.listShifts');
    }
  }

  @override
  Future<StaffShift?> shiftById(String id) async {
    try {
      final Map<String, Object?>? row = await _store.getById(
        LocalTables.staffShifts,
        id,
      );
      return row == null ? null : StaffShift.fromRow(row);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'workforce.shiftById');
    }
  }

  @override
  Future<String> registerShift(Map<String, Object?> row) async {
    final String id = (row['id'] as String?) ?? const Uuid().v4();
    try {
      await _store.insert(LocalTables.staffShifts, <String, Object?>{
        ...row,
        'id': id,
      });
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'workforce.registerShift');
    }
  }

  @override
  Future<void> updateShift(String id, Map<String, Object?> changes) async {
    try {
      await _store.update(LocalTables.staffShifts, id, changes);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'workforce.updateShift');
    }
  }

  @override
  Future<List<DutyAllocation>> listAllocations(
    String tenantId, {
    String? shiftId,
    String? staffUserId,
    int limit = 500,
  }) async {
    try {
      final StringBuffer sql = StringBuffer(
        'select * from ${LocalTables.dutyAllocations} where tenant_id = ?',
      );
      final List<Object?> params = <Object?>[tenantId];
      if (shiftId != null) {
        sql.write(' and shift_id = ?');
        params.add(shiftId);
      }
      if (staffUserId != null) {
        sql.write(' and staff_user_id = ?');
        params.add(staffUserId);
      }
      sql.write(' order by created_at limit ?');
      params.add(limit);
      final List<Map<String, Object?>> rows = await _store.query(
        sql.toString(),
        params,
      );
      return rows.map(DutyAllocation.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'workforce.listAllocations');
    }
  }

  @override
  Future<DutyAllocation?> allocationById(String id) async {
    try {
      final Map<String, Object?>? row = await _store.getById(
        LocalTables.dutyAllocations,
        id,
      );
      return row == null ? null : DutyAllocation.fromRow(row);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'workforce.allocationById');
    }
  }

  @override
  Future<String> registerAllocation(Map<String, Object?> row) async {
    final String id = (row['id'] as String?) ?? const Uuid().v4();
    try {
      await _store.insert(LocalTables.dutyAllocations, <String, Object?>{
        ...row,
        'id': id,
      });
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'workforce.registerAllocation');
    }
  }

  @override
  Future<void> updateAllocation(String id, Map<String, Object?> changes) async {
    try {
      await _store.update(LocalTables.dutyAllocations, id, changes);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'workforce.updateAllocation');
    }
  }

  @override
  Future<List<AttendanceLog>> listAttendance(String allocationId) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select * from ${LocalTables.attendanceLogs} '
        'where allocation_id = ? order by occurred_at',
        <Object?>[allocationId],
      );
      return rows.map(AttendanceLog.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'workforce.listAttendance');
    }
  }

  @override
  Future<String> registerAttendance(Map<String, Object?> row) async {
    final String id = (row['id'] as String?) ?? const Uuid().v4();
    try {
      await _store.insert(LocalTables.attendanceLogs, <String, Object?>{
        ...row,
        'id': id,
      });
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'workforce.registerAttendance');
    }
  }

  NodexError _mapped(Object error, StackTrace stackTrace, String operation) {
    if (error is NodexError) {
      return error;
    }
    final NodexError mapped = NodexErrorMapper.map(error, operation: operation);
    _logger.error(
      _module,
      'Local store operation failed.',
      operation: operation,
      errorCode: mapped.code,
      stackTrace: stackTrace,
    );
    return mapped;
  }
}
