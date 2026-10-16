/// Allied staff & workforce use cases (Module 09).
library;

import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/workforce/workforce.dart';
import 'package:nodex_hms/domain/workforce/workforce_repository.dart';

/// Schedules a dated shift block.
final class ScheduleStaffShiftUseCase {
  /// Creates the use case.
  ScheduleStaffShiftUseCase({required this._repository});

  final WorkforceRepository _repository;

  Future<String> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String facilityId,
    required String shiftDate,
    required String shiftCode,
    required String displayName,
    required StaffCategory staffCategory,
    required DateTime startsAt,
    required DateTime endsAt,
    int requiredHeadcount = 1,
    String? departmentId,
    String shiftId = '',
  }) async {
    policy.require(NodexPermissions.workforceManage);
    final Map<String, Object?> row = StaffShift.registerRow(
      tenantId: tenantId,
      facilityId: facilityId,
      shiftDate: shiftDate,
      shiftCode: shiftCode,
      displayName: displayName,
      staffCategory: staffCategory,
      startsAt: startsAt,
      endsAt: endsAt,
      requiredHeadcount: requiredHeadcount,
      departmentId: departmentId,
      shiftId: shiftId,
    );
    return _repository.registerShift(row);
  }
}

/// Edits a scheduled shift's display name, headcount or department.
final class UpdateStaffShiftUseCase {
  /// Creates the use case.
  UpdateStaffShiftUseCase({required this._repository});

  final WorkforceRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required StaffShift shift,
    String? displayName,
    int? requiredHeadcount,
    String? departmentId,
  }) async {
    policy.require(NodexPermissions.workforceManage);
    if (shift.status == ShiftStatus.closed) {
      throw const AuthorizationError(
        message: 'A closed shift is frozen as the historical roster.',
        code: 'staff_shift_closed_immutable',
      );
    }
    await _repository.updateShift(
      shift.id,
      staffShiftChanges(
        displayName: displayName,
        requiredHeadcount: requiredHeadcount,
        departmentId: departmentId,
      ),
    );
  }
}

/// Cancels a scheduled shift. The row is retained so the roster history is
/// complete.
final class CancelStaffShiftUseCase {
  /// Creates the use case.
  CancelStaffShiftUseCase({required this._repository});

  final WorkforceRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required StaffShift shift,
  }) async {
    policy.require(NodexPermissions.workforceManage);
    if (shift.status != ShiftStatus.scheduled) {
      throw const AuthorizationError(
        message: 'Only a scheduled shift can be cancelled.',
        code: 'staff_shift_not_cancellable',
      );
    }
    await _repository.updateShift(shift.id, staffShiftCancellationChanges());
  }
}

/// Closes a shift once its window has passed, freezing it as a roster.
final class CloseStaffShiftUseCase {
  /// Creates the use case.
  CloseStaffShiftUseCase({required this._repository});

  final WorkforceRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required StaffShift shift,
  }) async {
    policy.require(NodexPermissions.workforceManage);
    if (shift.status != ShiftStatus.scheduled) {
      throw const AuthorizationError(
        message: 'Only a scheduled shift can be closed.',
        code: 'staff_shift_not_closable',
      );
    }
    await _repository.updateShift(shift.id, staffShiftClosureChanges());
  }
}

/// Allocates a staff member to a shift, or records approved leave.
///
/// The overlap and headcount checks run against the local projection so an
/// offline clash is caught on the device; the database repeats the overlap
/// check in a trigger, so a stale projection cannot slip a double booking
/// through.
final class AllocateDutyUseCase {
  /// Creates the use case.
  AllocateDutyUseCase({required this._repository});

  final WorkforceRepository _repository;

  Future<String> call({
    required AuthorizationPolicy policy,
    required StaffShift shift,
    required String staffUserId,
    required String allocatedBy,
    DutyRole allocationRole = DutyRole.primary,
    String? note,
    String allocationId = '',
  }) async {
    policy.require(NodexPermissions.workforceManage);
    if (!shift.acceptsAllocations) {
      throw const AuthorizationError(
        message: 'This shift no longer accepts allocations.',
        code: 'staff_shift_not_allocatable',
      );
    }

    if (allocationRole != DutyRole.leave) {
      final List<DutyAllocation> onShift = await _repository.listAllocations(
        shift.tenantId,
        shiftId: shift.id,
      );
      final int filled = onShift
          .where(
            (DutyAllocation a) =>
                a.holdsWindow && a.allocationRole != DutyRole.leave,
          )
          .length;
      if (filled >= shift.requiredHeadcount) {
        throw ValidationError(
          message: 'The shift is already fully staffed.',
          code: 'staff_shift_headcount_reached',
          fieldErrors: <String, String>{
            'staff_user_id':
                '${shift.requiredHeadcount} of '
                '${shift.requiredHeadcount} places are filled.',
          },
        );
      }
    }

    final List<DutyAllocation> existing = await _repository.listAllocations(
      shift.tenantId,
      staffUserId: staffUserId,
    );
    // Approved leave is the block duty must avoid, not a duty itself, so it is
    // exempt from the overlap guard — matching the database trigger.
    if (allocationRole != DutyRole.leave) {
      for (final DutyAllocation other in existing) {
        if (other.status == DutyStatus.withdrawn) {
          continue;
        }
        final StaffShift? otherShift = await _repository.shiftById(
          other.shiftId,
        );
        if (otherShift != null && otherShift.overlaps(shift)) {
          throw ValidationError(
            message:
                'This staff member already holds an overlapping allocation.',
            code: 'duty_allocation_overlap',
            fieldErrors: <String, String>{
              'staff_user_id':
                  'Overlaps ${otherShift.displayName} '
                  'on ${otherShift.shiftDate}.',
            },
          );
        }
      }
    }

    final Map<String, Object?> row = DutyAllocation.registerRow(
      tenantId: shift.tenantId,
      shiftId: shift.id,
      staffUserId: staffUserId,
      allocationRole: allocationRole,
      allocatedBy: allocatedBy,
      note: note,
      allocationId: allocationId,
    );
    return _repository.registerAllocation(row);
  }
}

/// Releases an allocation, freeing its window.
final class WithdrawAllocationUseCase {
  /// Creates the use case.
  WithdrawAllocationUseCase({required this._repository});

  final WorkforceRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required DutyAllocation allocation,
    String? note,
  }) async {
    policy.require(NodexPermissions.workforceManage);
    if (allocation.status == DutyStatus.withdrawn) {
      throw const AuthorizationError(
        message: 'This allocation is already withdrawn.',
        code: 'duty_allocation_already_withdrawn',
      );
    }
    await _repository.updateAllocation(
      allocation.id,
      dutyAllocationChanges(status: DutyStatus.withdrawn, note: note),
    );
  }
}

/// Appends an attendance event against an allocation.
final class RecordAttendanceUseCase {
  /// Creates the use case.
  RecordAttendanceUseCase({required this._repository});

  final WorkforceRepository _repository;

  Future<String> call({
    required AuthorizationPolicy policy,
    required DutyAllocation allocation,
    required AttendanceEventType eventType,
    required DateTime occurredAt,
    required String recordedBy,
    String? note,
    String attendanceId = '',
  }) async {
    policy.require(NodexPermissions.workforceManage);
    if (allocation.status == DutyStatus.withdrawn) {
      throw const AuthorizationError(
        message:
            'Attendance cannot be recorded against a withdrawn allocation.',
        code: 'duty_allocation_withdrawn',
      );
    }
    final Map<String, Object?> row = AttendanceLog.eventRow(
      tenantId: allocation.tenantId,
      allocationId: allocation.id,
      staffUserId: allocation.staffUserId,
      eventType: eventType,
      occurredAt: occurredAt,
      recordedBy: recordedBy,
      note: note,
      attendanceId: attendanceId,
    );
    return _repository.registerAttendance(row);
  }
}

/// Reads the workforce rosters. Gated on the read permission instead of manage.
final class ReadWorkforceUseCase {
  /// Creates the use case.
  ReadWorkforceUseCase({required this._repository});

  final WorkforceRepository _repository;

  Future<List<StaffShift>> shifts({
    required AuthorizationPolicy policy,
    required String tenantId,
    String? facilityId,
    String? onDate,
    int limit = 200,
  }) async {
    policy.require(NodexPermissions.workforceRead);
    return _repository.listShifts(
      tenantId,
      facilityId: facilityId,
      onDate: onDate,
      limit: limit,
    );
  }

  Future<List<DutyAllocation>> allocations({
    required AuthorizationPolicy policy,
    required String tenantId,
    String? shiftId,
    String? staffUserId,
    int limit = 500,
  }) async {
    policy.require(NodexPermissions.workforceRead);
    return _repository.listAllocations(
      tenantId,
      shiftId: shiftId,
      staffUserId: staffUserId,
      limit: limit,
    );
  }

  Future<List<AttendanceLog>> attendance({
    required AuthorizationPolicy policy,
    required String allocationId,
  }) async {
    policy.require(NodexPermissions.workforceRead);
    return _repository.listAttendance(allocationId);
  }
}
