/// Tests for the HR & payroll use-case gates and invariants (Module 13).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/authorization_snapshot.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/domain/hr/hr.dart';
import 'package:nodex_hms/domain/hr/hr_repository.dart';
import 'package:nodex_hms/domain/hr/hr_use_cases.dart';

import 'hr_repository_test.dart' show FakeHrStore;

AuthorizationPolicy policyWith(
  Set<String> permissions, {
  ConnectivityState connectivity = ConnectivityState.online,
}) {
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
      roles: const <String>{NodexRoles.hospitalSuperAdmin},
      permissions: permissions,
      offlinePermissions: permissions,
      facilityIds: const <String>{'facility-1'},
      departmentIds: const <String>{},
      wardIds: const <String>{},
    ),
    connectivity: connectivity,
  );
}

void main() {
  late FakeHrStore store;
  late DefaultHrRepository repository;

  const Set<String> manageHr = <String>{NodexPermissions.hrManage};
  const Set<String> managePayroll = <String>{NodexPermissions.payrollManage};
  const Set<String> readHr = <String>{NodexPermissions.hrRead};
  const Set<String> readPayroll = <String>{NodexPermissions.payrollRead};

  setUp(() {
    store = FakeHrStore();
    repository = DefaultHrRepository(
      store: store,
      logger: NodexLogger(
        sinks: <NodexLogSink>[InMemoryLogSink()],
        minimumLevel: NodexLogLevel.trace,
      ),
    );
  });

  String now() => DateTime.now().toUtc().toIso8601String();

  Future<HrEmployee> seedEmployee({
    String id = 'emp-1',
    EmploymentStatus status = EmploymentStatus.probation,
  }) async {
    final String stored = await repository.registerEmployee(<String, Object?>{
      'id': id,
      'tenant_id': 'tenant-1',
      'user_id': 'user-$id',
      'employee_code': 'CODE-$id',
      'department_id': 'dept-1',
      'designation': 'Staff Nurse',
      'employment_type': 'permanent',
      'employment_status': status.wireValue,
      'joined_on': '2026-01-05',
      'created_at': now(),
      'updated_at': now(),
    });
    return (await repository.employeeById(stored))!;
  }

  Future<HrPayrollPeriod> seedPeriod({String id = 'period-1'}) async {
    final String stored = await repository.registerPayrollPeriod(
      <String, Object?>{
        'id': id,
        'tenant_id': 'tenant-1',
        'facility_id': 'facility-1',
        'period_start': '2026-10-01',
        'period_end': '2026-10-31',
        'pay_date': '2026-11-05',
        'currency': 'BDT',
        'status': 'draft',
        'created_at': now(),
        'updated_at': now(),
      },
    );
    return (await repository.payrollPeriodById(stored))!;
  }

  test('registering an employee requires hr.manage', () async {
    final useCase = RegisterEmployeeUseCase(repository: repository);
    expect(
      () => useCase.call(
        policy: policyWith(readHr),
        tenantId: 'tenant-1',
        userId: 'user-1',
        employeeCode: 'E-1',
        joinedOn: '2026-01-05',
      ),
      throwsA(isA<NodexError>()),
    );
    final String id = await useCase.call(
      policy: policyWith(manageHr),
      tenantId: 'tenant-1',
      userId: 'user-1',
      employeeCode: 'E-1',
      joinedOn: '2026-01-05',
    );
    expect(id, isNotEmpty);
  });

  test(
    'employee confirmation and separation are guarded transitions',
    () async {
      final HrEmployee employee = await seedEmployee();
      final confirm = ConfirmEmployeeUseCase(repository: repository);
      final separate = SeparateEmployeeUseCase(repository: repository);

      await confirm.call(
        policy: policyWith(manageHr),
        employee: employee,
        confirmedOn: '2026-07-05',
      );
      final confirmed = (await repository.employeeById(employee.id))!;
      expect(confirmed.isConfirmed, isTrue);
      expect(confirmed.employmentStatus, EmploymentStatus.active);
      expect(
        () => confirm.call(
          policy: policyWith(manageHr),
          employee: confirmed,
          confirmedOn: '2026-08-05',
        ),
        throwsA(isA<NodexError>()),
      );

      await separate.call(
        policy: policyWith(manageHr),
        employee: confirmed,
        separatedOn: '2027-01-31',
      );
      final separated = (await repository.employeeById(employee.id))!;
      expect(separated.employmentStatus, EmploymentStatus.separated);
      expect(
        () => separate.call(
          policy: policyWith(manageHr),
          employee: separated,
          separatedOn: '2027-02-28',
        ),
        throwsA(isA<NodexError>()),
      );
    },
  );

  test('separating before joining is refused', () async {
    final HrEmployee employee = await seedEmployee();
    final separate = SeparateEmployeeUseCase(repository: repository);
    expect(
      () => separate.call(
        policy: policyWith(manageHr),
        employee: employee,
        separatedOn: '2025-12-31',
      ),
      throwsA(isA<NodexError>()),
    );
  });

  test('an overlapping live leave application is refused', () async {
    final request = RequestLeaveUseCase(repository: repository);
    await request.call(
      policy: policyWith(manageHr),
      tenantId: 'tenant-1',
      employeeId: 'emp-1',
      startsOn: '2026-11-01',
      endsOn: '2026-11-05',
      requestedBy: 'admin-1',
    );
    expect(
      () => request.call(
        policy: policyWith(manageHr),
        tenantId: 'tenant-1',
        employeeId: 'emp-1',
        startsOn: '2026-11-04',
        endsOn: '2026-11-08',
        requestedBy: 'admin-1',
      ),
      throwsA(isA<NodexError>()),
    );
  });

  test('a decided leave application cannot be decided again', () async {
    final request = RequestLeaveUseCase(repository: repository);
    final id = await request.call(
      policy: policyWith(manageHr),
      tenantId: 'tenant-1',
      employeeId: 'emp-1',
      startsOn: '2026-11-01',
      endsOn: '2026-11-05',
      requestedBy: 'admin-1',
    );
    final HrLeaveRequest pending = (await repository.leaveRequestById(id))!;
    final decide = DecideLeaveUseCase(repository: repository);
    await decide.call(
      policy: policyWith(manageHr),
      request: pending,
      decision: LeaveStatus.approved,
      decidedBy: 'admin-1',
    );
    final approved = (await repository.leaveRequestById(id))!;
    expect(approved.status, LeaveStatus.approved);
    expect(
      () => decide.call(
        policy: policyWith(manageHr),
        request: approved,
        decision: LeaveStatus.rejected,
        decidedBy: 'admin-1',
      ),
      throwsA(isA<NodexError>()),
    );
  });

  test('a payslip derives net pay and refuses a separated employee', () async {
    final HrPayrollPeriod period = await seedPeriod();
    final HrEmployee employee = await seedEmployee();
    final create = CreatePayslipUseCase(repository: repository);
    final String id = await create.call(
      policy: policyWith(managePayroll),
      period: period,
      employee: employee,
      grossMinor: 5000000,
      deductionsMinor: 500000,
    );
    final slip = (await repository.payslipById(id))!;
    expect(slip.netMinor, 4500000);

    final separated = await seedEmployee(
      id: 'emp-2',
      status: EmploymentStatus.separated,
    );
    expect(
      () => create.call(
        policy: policyWith(managePayroll),
        period: period,
        employee: separated,
        grossMinor: 100000,
      ),
      throwsA(isA<NodexError>()),
    );
  });

  test('finalizing an empty payroll run is refused', () async {
    final HrPayrollPeriod period = await seedPeriod();
    final finalize = FinalizePayrollPeriodUseCase(repository: repository);
    expect(
      () => finalize.call(
        policy: policyWith(managePayroll),
        period: period,
        finalizedBy: 'admin-1',
      ),
      throwsA(isA<NodexError>()),
    );
  });

  test('finalizing freezes the run and its payslips', () async {
    final HrPayrollPeriod period = await seedPeriod();
    final HrEmployee employee = await seedEmployee();
    await CreatePayslipUseCase(repository: repository).call(
      policy: policyWith(managePayroll),
      period: period,
      employee: employee,
      grossMinor: 100000,
    );
    final finalize = FinalizePayrollPeriodUseCase(repository: repository);
    await finalize.call(
      policy: policyWith(managePayroll),
      period: period,
      finalizedBy: 'admin-1',
    );
    final frozen = (await repository.payrollPeriodById(period.id))!;
    expect(frozen.status, PayrollStatus.finalized);
    final slips = await repository.listPayslips(
      'tenant-1',
      periodId: period.id,
    );
    expect(slips.first.status, PayrollStatus.finalized);
    expect(
      () => finalize.call(
        policy: policyWith(managePayroll),
        period: frozen,
        finalizedBy: 'admin-1',
      ),
      throwsA(isA<NodexError>()),
    );
  });

  test('payroll management cannot run offline', () async {
    final HrPayrollPeriod period = await seedPeriod();
    final finalize = FinalizePayrollPeriodUseCase(repository: repository);
    expect(
      () => finalize.call(
        policy: policyWith(
          managePayroll,
          connectivity: ConnectivityState.offline,
        ),
        period: period,
        finalizedBy: 'admin-1',
      ),
      throwsA(isA<NodexError>()),
    );
  });

  test('reads are gated on their own permission', () async {
    final readHrUseCase = ReadHrUseCase(repository: repository);
    expect(
      () => readHrUseCase.employees(
        policy: policyWith(const <String>{}),
        tenantId: 'tenant-1',
      ),
      throwsA(isA<NodexError>()),
    );
    final readPayrollUseCase = ReadPayrollUseCase(repository: repository);
    expect(
      () => readPayrollUseCase.periods(
        policy: policyWith(readHr),
        tenantId: 'tenant-1',
      ),
      throwsA(isA<NodexError>()),
    );
    final periods = await readPayrollUseCase.periods(
      policy: policyWith(readPayroll),
      tenantId: 'tenant-1',
    );
    expect(periods, isEmpty);
  });
}
