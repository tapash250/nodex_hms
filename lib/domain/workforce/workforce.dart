/// Allied staff & workforce manager entities (Module 09).
///
/// Specification scope: "Shift management, duty rosters, task delegation, and
/// leave tracking for nursing, technicians, and orderlies", over the entities
/// `staff_shifts`, `duty_allocations` and `attendance_logs`.
///
/// Three different kinds of fact live here and they are deliberately not
/// collapsed:
///
/// * a [StaffShift] is configuration — a dated block of cover the ward needs;
/// * a [DutyAllocation] is a commitment — a named person filling it, or an
///   approved leave block that duty must avoid;
/// * an [AttendanceLog] is a fact — what actually happened, appended and never
///   rewritten.
///
/// A closed shift is a historical roster: its window and headcount freeze so an
/// attendance report can always be explained. Attendance never changes a shift
/// or an allocation; a correction is a further event.
// ignore_for_file: sort_constructors_first
library;

import 'package:meta/meta.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';

/// The staff group a shift is staffed from.
enum StaffCategory {
  /// Registered and auxiliary nursing.
  nursing('nursing'),

  /// Laboratory, radiology and theatre technicians.
  technician('technician'),

  /// Ward orderlies and patient porters.
  orderly('orderly'),

  /// Other allied-health staff.
  allied('allied'),

  /// Administrative cover.
  admin('admin');

  const StaffCategory(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    StaffCategory.nursing => 'Nursing',
    StaffCategory.technician => 'Technician',
    StaffCategory.orderly => 'Orderly',
    StaffCategory.allied => 'Allied health',
    StaffCategory.admin => 'Administrative',
  };

  /// Parses a stored value.
  static StaffCategory fromWire(String value) =>
      StaffCategory.values.firstWhere(
        (StaffCategory category) => category.wireValue == value,
        orElse: () => StaffCategory.nursing,
      );
}

/// Lifecycle of a shift block.
enum ShiftStatus {
  /// Open for allocation.
  scheduled('scheduled'),

  /// Called off; retained so the roster history is complete.
  cancelled('cancelled'),

  /// Finished and frozen as a historical roster.
  closed('closed');

  const ShiftStatus(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Parses a stored value.
  static ShiftStatus fromWire(String value) => ShiftStatus.values.firstWhere(
    (ShiftStatus status) => status.wireValue == value,
    orElse: () => ShiftStatus.scheduled,
  );

  /// Whether allocations may still be made against the shift.
  bool get acceptsAllocations => this == ShiftStatus.scheduled;
}

/// The role a person holds on a rota block.
enum DutyRole {
  /// The person covering the block.
  primary('primary'),

  /// Backup cover alongside the primary.
  relief('relief'),

  /// The shift supervisor.
  supervisor('supervisor'),

  /// Approved leave, blocking duty over the window.
  leave('leave');

  const DutyRole(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    DutyRole.primary => 'Primary',
    DutyRole.relief => 'Relief',
    DutyRole.supervisor => 'Supervisor',
    DutyRole.leave => 'Leave',
  };

  /// Parses a stored value.
  static DutyRole fromWire(String value) => DutyRole.values.firstWhere(
    (DutyRole role) => role.wireValue == value,
    orElse: () => DutyRole.primary,
  );
}

/// Lifecycle of a duty allocation.
enum DutyStatus {
  /// Committed and expected to be worked.
  allocated('allocated'),

  /// Worked and reconciled against attendance.
  completed('completed'),

  /// Released by the ward or the staff member.
  withdrawn('withdrawn'),

  /// Approved leave; paired with [DutyRole.leave].
  leave('leave');

  const DutyStatus(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Parses a stored value.
  static DutyStatus fromWire(String value) => DutyStatus.values.firstWhere(
    (DutyStatus status) => status.wireValue == value,
    orElse: () => DutyStatus.allocated,
  );

  /// Whether the allocation still holds its window.
  bool get holdsWindow =>
      this == DutyStatus.allocated || this == DutyStatus.completed;
}

/// Kind of attendance event.
enum AttendanceEventType {
  /// Arrived for the shift.
  clockIn('clock_in'),

  /// Left at the end of the shift.
  clockOut('clock_out'),

  /// Started a break.
  breakStart('break_start'),

  /// Ended a break.
  breakEnd('break_end'),

  /// Did not attend as rostered.
  absence('absence');

  const AttendanceEventType(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    AttendanceEventType.clockIn => 'Clock in',
    AttendanceEventType.clockOut => 'Clock out',
    AttendanceEventType.breakStart => 'Break start',
    AttendanceEventType.breakEnd => 'Break end',
    AttendanceEventType.absence => 'Absence',
  };

  /// Parses a stored value.
  static AttendanceEventType fromWire(String value) =>
      AttendanceEventType.values.firstWhere(
        (AttendanceEventType type) => type.wireValue == value,
        orElse: () => AttendanceEventType.clockIn,
      );
}

/// A dated block of cover the ward needs.
@immutable
final class StaffShift {
  /// Creates a shift.
  const StaffShift({
    required this.id,
    required this.tenantId,
    required this.facilityId,
    required this.shiftDate,
    required this.shiftCode,
    required this.displayName,
    required this.staffCategory,
    required this.startsAt,
    required this.endsAt,
    required this.requiredHeadcount,
    required this.status,
    this.departmentId,
    this.createdAt,
    this.updatedAt,
  });

  /// Validates and builds a new shift row.
  static Map<String, Object?> registerRow({
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
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (facilityId.isEmpty) {
      fieldErrors['facility_id'] = 'Facility is required.';
    }
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(shiftDate)) {
      fieldErrors['shift_date'] = 'Expected an ISO-8601 date.';
    }
    if (shiftCode.trim().isEmpty) {
      fieldErrors['shift_code'] = 'Shift code is required.';
    }
    if (displayName.trim().isEmpty) {
      fieldErrors['display_name'] = 'Shift name is required.';
    }
    if (!endsAt.isAfter(startsAt)) {
      fieldErrors['ends_at'] = 'Must end after it starts.';
    }
    if (requiredHeadcount < 1 || requiredHeadcount > 200) {
      fieldErrors['required_headcount'] = 'Expected 1 to 200.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Shift failed validation.',
        fieldErrors: fieldErrors,
        code: 'staff_shift_invalid',
      );
    }

    final String now = DateTime.now().toUtc().toIso8601String();
    return <String, Object?>{
      if (shiftId.isNotEmpty) 'id': shiftId,
      'tenant_id': tenantId,
      'facility_id': facilityId,
      'department_id': departmentId,
      'shift_date': shiftDate,
      'shift_code': shiftCode.trim(),
      'display_name': displayName.trim(),
      'staff_category': staffCategory.wireValue,
      'starts_at': startsAt.toUtc().toIso8601String(),
      'ends_at': endsAt.toUtc().toIso8601String(),
      'required_headcount': requiredHeadcount,
      'status': ShiftStatus.scheduled.wireValue,
      'created_at': now,
      'updated_at': now,
    };
  }

  /// Materializes a shift from a local row.
  factory StaffShift.fromRow(Map<String, Object?> row) => StaffShift(
    id: row['id']! as String,
    tenantId: row['tenant_id']! as String,
    facilityId: row['facility_id']! as String,
    shiftDate: row['shift_date']! as String,
    shiftCode: row['shift_code']! as String,
    displayName: row['display_name']! as String,
    staffCategory: StaffCategory.fromWire(row['staff_category']! as String),
    startsAt: DateTime.parse(row['starts_at']! as String).toUtc(),
    endsAt: DateTime.parse(row['ends_at']! as String).toUtc(),
    requiredHeadcount: (row['required_headcount'] as num?)?.toInt() ?? 1,
    status: ShiftStatus.fromWire(row['status']! as String),
    departmentId: row['department_id'] as String?,
    createdAt: row['created_at'] is String
        ? DateTime.parse(row['created_at']! as String).toUtc()
        : null,
    updatedAt: row['updated_at'] is String
        ? DateTime.parse(row['updated_at']! as String).toUtc()
        : null,
  );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// Facility the shift is staffed at.
  final String facilityId;

  /// Owning department, when the cover is department-specific.
  final String? departmentId;

  /// Calendar date the shift belongs to, as `YYYY-MM-DD`.
  final String shiftDate;

  /// Short code, unique within a facility and day.
  final String shiftCode;

  /// Human-readable name.
  final String displayName;

  /// Staff group the shift is staffed from.
  final StaffCategory staffCategory;

  /// Cover start, UTC.
  final DateTime startsAt;

  /// Cover end, UTC.
  final DateTime endsAt;

  /// People the shift needs.
  final int requiredHeadcount;

  /// Lifecycle status.
  final ShiftStatus status;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Whether the shift still accepts allocations.
  bool get acceptsAllocations => status.acceptsAllocations;

  /// Whether the shift overlaps [other].
  bool overlaps(StaffShift other) =>
      startsAt.isBefore(other.endsAt) && other.startsAt.isBefore(endsAt);

  /// Whether the shift covers [moment].
  bool covers(DateTime moment) =>
      !moment.isBefore(startsAt) && moment.isBefore(endsAt);
}

/// Column changes for a shift edit.
Map<String, Object?> staffShiftChanges({
  String? displayName,
  int? requiredHeadcount,
  String? departmentId,
}) => <String, Object?>{
  if (displayName != null) 'display_name': displayName.trim(),
  'required_headcount': ?requiredHeadcount,
  'department_id': departmentId,
  'updated_at': DateTime.now().toUtc().toIso8601String(),
};

/// The change set for cancelling a shift.
Map<String, Object?> staffShiftCancellationChanges() => <String, Object?>{
  'status': ShiftStatus.cancelled.wireValue,
  'updated_at': DateTime.now().toUtc().toIso8601String(),
};

/// The change set for closing a shift at the end of its window.
Map<String, Object?> staffShiftClosureChanges() => <String, Object?>{
  'status': ShiftStatus.closed.wireValue,
  'updated_at': DateTime.now().toUtc().toIso8601String(),
};

/// A person's commitment to a shift, or an approved leave block.
@immutable
final class DutyAllocation {
  /// Creates an allocation.
  const DutyAllocation({
    required this.id,
    required this.tenantId,
    required this.shiftId,
    required this.staffUserId,
    required this.allocationRole,
    required this.status,
    this.note,
    this.allocatedBy,
    this.createdAt,
    this.updatedAt,
  });

  /// Validates and builds a new allocation row.
  static Map<String, Object?> registerRow({
    required String tenantId,
    required String shiftId,
    required String staffUserId,
    required DutyRole allocationRole,
    required String allocatedBy,
    String? note,
    String allocationId = '',
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (shiftId.isEmpty) {
      fieldErrors['shift_id'] = 'Shift is required.';
    }
    if (staffUserId.isEmpty) {
      fieldErrors['staff_user_id'] = 'Staff member is required.';
    }
    if (allocatedBy.isEmpty) {
      fieldErrors['allocated_by'] = 'Allocator is required.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Duty allocation failed validation.',
        fieldErrors: fieldErrors,
        code: 'duty_allocation_invalid',
      );
    }

    final String now = DateTime.now().toUtc().toIso8601String();
    final String? trimmed = note?.trim();
    final bool isLeave = allocationRole == DutyRole.leave;
    return <String, Object?>{
      if (allocationId.isNotEmpty) 'id': allocationId,
      'tenant_id': tenantId,
      'shift_id': shiftId,
      'staff_user_id': staffUserId,
      'allocation_role': allocationRole.wireValue,
      'status': isLeave
          ? DutyStatus.leave.wireValue
          : DutyStatus.allocated.wireValue,
      'note': trimmed == null || trimmed.isEmpty ? null : trimmed,
      'allocated_by': allocatedBy,
      'created_at': now,
      'updated_at': now,
    };
  }

  /// Materializes an allocation from a local row.
  factory DutyAllocation.fromRow(Map<String, Object?> row) => DutyAllocation(
    id: row['id']! as String,
    tenantId: row['tenant_id']! as String,
    shiftId: row['shift_id']! as String,
    staffUserId: row['staff_user_id']! as String,
    allocationRole: DutyRole.fromWire(row['allocation_role']! as String),
    status: DutyStatus.fromWire(row['status']! as String),
    note: row['note'] as String?,
    allocatedBy: row['allocated_by'] as String?,
    createdAt: row['created_at'] is String
        ? DateTime.parse(row['created_at']! as String).toUtc()
        : null,
    updatedAt: row['updated_at'] is String
        ? DateTime.parse(row['updated_at']! as String).toUtc()
        : null,
  );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// The shift being covered.
  final String shiftId;

  /// The app user committed to the block.
  final String staffUserId;

  /// Role held on the block.
  final DutyRole allocationRole;

  /// Lifecycle status.
  final DutyStatus status;

  /// Optional allocation note.
  final String? note;

  /// Who made the allocation.
  final String? allocatedBy;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Whether the allocation still holds its window against other duty.
  bool get holdsWindow => status.holdsWindow;

  /// Whether the allocation may be edited.
  bool get isEditable => status == DutyStatus.allocated;
}

/// Column changes for a duty allocation edit.
Map<String, Object?> dutyAllocationChanges({
  DutyStatus? status,
  String? note,
}) => <String, Object?>{
  if (status != null) 'status': status.wireValue,
  'note': note?.trim(),
  'updated_at': DateTime.now().toUtc().toIso8601String(),
};

/// An appended attendance event.
@immutable
final class AttendanceLog {
  /// Creates an attendance event.
  const AttendanceLog({
    required this.id,
    required this.tenantId,
    required this.allocationId,
    required this.staffUserId,
    required this.eventType,
    required this.occurredAt,
    this.recordedBy,
    this.note,
    this.createdAt,
  });

  /// Validates and builds a new attendance row.
  static Map<String, Object?> eventRow({
    required String tenantId,
    required String allocationId,
    required String staffUserId,
    required AttendanceEventType eventType,
    required DateTime occurredAt,
    required String recordedBy,
    String? note,
    String attendanceId = '',
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (allocationId.isEmpty) {
      fieldErrors['allocation_id'] = 'Allocation is required.';
    }
    if (staffUserId.isEmpty) {
      fieldErrors['staff_user_id'] = 'Staff member is required.';
    }
    if (recordedBy.isEmpty) {
      fieldErrors['recorded_by'] = 'Recorder is required.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Attendance event failed validation.',
        fieldErrors: fieldErrors,
        code: 'attendance_log_invalid',
      );
    }

    final String now = DateTime.now().toUtc().toIso8601String();
    final String? trimmed = note?.trim();
    return <String, Object?>{
      if (attendanceId.isNotEmpty) 'id': attendanceId,
      'tenant_id': tenantId,
      'allocation_id': allocationId,
      'staff_user_id': staffUserId,
      'event_type': eventType.wireValue,
      'occurred_at': occurredAt.toUtc().toIso8601String(),
      'recorded_by': recordedBy,
      'note': trimmed == null || trimmed.isEmpty ? null : trimmed,
      'created_at': now,
    };
  }

  /// Materializes an attendance event from a local row.
  factory AttendanceLog.fromRow(Map<String, Object?> row) => AttendanceLog(
    id: row['id']! as String,
    tenantId: row['tenant_id']! as String,
    allocationId: row['allocation_id']! as String,
    staffUserId: row['staff_user_id']! as String,
    eventType: AttendanceEventType.fromWire(row['event_type']! as String),
    occurredAt: DateTime.parse(row['occurred_at']! as String).toUtc(),
    recordedBy: row['recorded_by'] as String?,
    note: row['note'] as String?,
    createdAt: row['created_at'] is String
        ? DateTime.parse(row['created_at']! as String).toUtc()
        : null,
  );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// The allocation this event belongs to.
  final String allocationId;

  /// The app user the event describes.
  final String staffUserId;

  /// What happened.
  final AttendanceEventType eventType;

  /// When it happened, UTC.
  final DateTime occurredAt;

  /// Who recorded it.
  final String? recordedBy;

  /// Optional note.
  final String? note;

  final DateTime? createdAt;
}
