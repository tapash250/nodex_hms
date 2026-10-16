/// Tests for the workforce use-case gates and roster invariants (Module 09).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/authorization_snapshot.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/domain/workforce/workforce.dart';
import 'package:nodex_hms/domain/workforce/workforce_repository.dart';
import 'package:nodex_hms/domain/workforce/workforce_use_cases.dart';

import 'workforce_repository_test.dart' show FakeWorkforceStore;

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
      roles: const <String>{NodexRoles.nursingStaff},
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
  late FakeWorkforceStore store;
  late DefaultWorkforceRepository repository;
  late ScheduleStaffShiftUseCase schedule;
  late UpdateStaffShiftUseCase update;
  late CancelStaffShiftUseCase cancel;
  late CloseStaffShiftUseCase close;
  late AllocateDutyUseCase allocate;
  late WithdrawAllocationUseCase withdraw;
  late RecordAttendanceUseCase record;
  late ReadWorkforceUseCase read;

  const Set<String> manage = <String>{NodexPermissions.workforceManage};
  const Set<String> reader = <String>{NodexPermissions.workforceRead};

  setUp(() {
    store = FakeWorkforceStore();
    repository = DefaultWorkforceRepository(
      store: store,
      logger: NodexLogger(
        sinks: <NodexLogSink>[InMemoryLogSink()],
        minimumLevel: NodexLogLevel.trace,
      ),
    );
    schedule = ScheduleStaffShiftUseCase(repository: repository);
    update = UpdateStaffShiftUseCase(repository: repository);
    cancel = CancelStaffShiftUseCase(repository: repository);
    close = CloseStaffShiftUseCase(repository: repository);
    allocate = AllocateDutyUseCase(repository: repository);
    withdraw = WithdrawAllocationUseCase(repository: repository);
    record = RecordAttendanceUseCase(repository: repository);
    read = ReadWorkforceUseCase(repository: repository);
  });

  Future<StaffShift> seedShift({
    String code = 'DAY',
    int headcount = 1,
    int startHour = 8,
    int endHour = 16,
  }) async {
    final String id = await repository.registerShift(<String, Object?>{
      'tenant_id': 'tenant-1',
      'facility_id': 'f-1',
      'shift_date': '2026-10-16',
      'shift_code': code,
      'display_name': '$code shift',
      'staff_category': 'nursing',
      'starts_at': DateTime.utc(2026, 10, 16, startHour).toIso8601String(),
      'ends_at': DateTime.utc(2026, 10, 16, endHour).toIso8601String(),
      'required_headcount': headcount,
      'status': 'scheduled',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    return (await repository.shiftById(id))!;
  }

  test('schedule requires manage permission', () async {
    final String id = await schedule(
      policy: policyWith(manage),
      tenantId: 'tenant-1',
      facilityId: 'f-1',
      shiftDate: '2026-10-16',
      shiftCode: 'DAY',
      displayName: 'Day shift',
      staffCategory: StaffCategory.nursing,
      startsAt: DateTime.utc(2026, 10, 16, 8),
      endsAt: DateTime.utc(2026, 10, 16, 16),
    );
    expect(id, isNotEmpty);

    expect(
      () => schedule(
        policy: policyWith(reader),
        tenantId: 'tenant-1',
        facilityId: 'f-1',
        shiftDate: '2026-10-16',
        shiftCode: 'EVE',
        displayName: 'Evening shift',
        staffCategory: StaffCategory.nursing,
        startsAt: DateTime.utc(2026, 10, 16, 16),
        endsAt: DateTime.utc(2026, 10, 17),
      ),
      throwsA(isA<NodexError>()),
    );
  });

  test('schedule rejects a window that ends before it starts', () async {
    expect(
      () => schedule(
        policy: policyWith(manage),
        tenantId: 'tenant-1',
        facilityId: 'f-1',
        shiftDate: '2026-10-16',
        shiftCode: 'BAD',
        displayName: 'Bad shift',
        staffCategory: StaffCategory.nursing,
        startsAt: DateTime.utc(2026, 10, 16, 16),
        endsAt: DateTime.utc(2026, 10, 16, 8),
      ),
      throwsA(isA<NodexError>()),
    );
  });

  test('close freezes the shift against edits and cancellation', () async {
    final StaffShift shift = await seedShift();
    await close(policy: policyWith(manage), shift: shift);
    final StaffShift closed = (await repository.shiftById(shift.id))!;
    expect(closed.status, ShiftStatus.closed);
    expect(
      () => update(
        policy: policyWith(manage),
        shift: closed,
        displayName: 'Renamed',
      ),
      throwsA(isA<NodexError>()),
    );
    expect(
      () => cancel(policy: policyWith(manage), shift: closed),
      throwsA(isA<NodexError>()),
    );
  });

  test('allocation refuses an overlapping shift', () async {
    final StaffShift day = await seedShift(headcount: 5);
    final StaffShift evening = await seedShift(
      code: 'EVE',
      headcount: 5,
      startHour: 12,
      endHour: 20,
    );
    await allocate(
      policy: policyWith(manage),
      shift: day,
      staffUserId: 'nurse-1',
      allocatedBy: 'admin-1',
    );
    expect(
      () => allocate(
        policy: policyWith(manage),
        shift: evening,
        staffUserId: 'nurse-1',
        allocatedBy: 'admin-1',
      ),
      throwsA(isA<NodexError>()),
    );
  });

  test('allocation refuses a shift already fully staffed', () async {
    final StaffShift shift = await seedShift(headcount: 1);
    await allocate(
      policy: policyWith(manage),
      shift: shift,
      staffUserId: 'nurse-1',
      allocatedBy: 'admin-1',
    );
    expect(
      () => allocate(
        policy: policyWith(manage),
        shift: shift,
        staffUserId: 'nurse-2',
        allocatedBy: 'admin-1',
      ),
      throwsA(isA<NodexError>()),
    );
  });

  test('approved leave blocks an overlapping duty allocation', () async {
    final StaffShift shift = await seedShift(headcount: 5);
    await allocate(
      policy: policyWith(manage),
      shift: shift,
      staffUserId: 'nurse-1',
      allocatedBy: 'admin-1',
      allocationRole: DutyRole.leave,
    );
    final List<DutyAllocation> allocations = await repository.listAllocations(
      'tenant-1',
      staffUserId: 'nurse-1',
    );
    expect(allocations.first.status, DutyStatus.leave);
    expect(
      () => allocate(
        policy: policyWith(manage),
        shift: shift,
        staffUserId: 'nurse-1',
        allocatedBy: 'admin-1',
      ),
      throwsA(isA<NodexError>()),
    );
  });

  test('withdrawing an allocation frees the window', () async {
    final StaffShift day = await seedShift(headcount: 5);
    final StaffShift evening = await seedShift(
      code: 'EVE',
      headcount: 5,
      startHour: 12,
      endHour: 20,
    );
    final String id = await allocate(
      policy: policyWith(manage),
      shift: day,
      staffUserId: 'nurse-1',
      allocatedBy: 'admin-1',
    );
    final DutyAllocation allocation = (await repository.allocationById(id))!;
    await withdraw(policy: policyWith(manage), allocation: allocation);
    final String moved = await allocate(
      policy: policyWith(manage),
      shift: evening,
      staffUserId: 'nurse-1',
      allocatedBy: 'admin-1',
    );
    expect(moved, isNotEmpty);
  });

  test(
    'attendance is appended and refused on a withdrawn allocation',
    () async {
      final StaffShift shift = await seedShift(headcount: 5);
      final String id = await allocate(
        policy: policyWith(manage),
        shift: shift,
        staffUserId: 'nurse-1',
        allocatedBy: 'admin-1',
      );
      final DutyAllocation allocation = (await repository.allocationById(id))!;
      await record(
        policy: policyWith(manage),
        allocation: allocation,
        eventType: AttendanceEventType.clockIn,
        occurredAt: DateTime.utc(2026, 10, 16, 8),
        recordedBy: 'admin-1',
      );
      await withdraw(policy: policyWith(manage), allocation: allocation);
      final DutyAllocation withdrawn = (await repository.allocationById(id))!;
      expect(
        () => record(
          policy: policyWith(manage),
          allocation: withdrawn,
          eventType: AttendanceEventType.clockOut,
          occurredAt: DateTime.utc(2026, 10, 16, 16),
          recordedBy: 'admin-1',
        ),
        throwsA(isA<NodexError>()),
      );
      expect(repository, isNotNull);
    },
  );

  test('read requires only the read permission', () async {
    expect(
      () => read.shifts(policy: policyWith(<String>{}), tenantId: 'tenant-1'),
      throwsA(isA<NodexError>()),
    );
    final List<StaffShift> shifts = await read.shifts(
      policy: policyWith(reader),
      tenantId: 'tenant-1',
    );
    expect(shifts, isEmpty);
  });
}
