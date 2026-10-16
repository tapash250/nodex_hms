/// Tests for the HR repository over a fake local store (Module 13).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/hr/hr.dart';
import 'package:nodex_hms/domain/hr/hr_repository.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';

/// A minimal in-memory store covering the five HR tables and their indexes.
final class FakeHrStore implements PatientLocalStore {
  final Map<String, Map<String, Map<String, Object?>>> tables =
      <String, Map<String, Map<String, Object?>>>{};
  bool closed = false;

  static const List<String> _tables = <String>[
    LocalTables.hrEmployees,
    LocalTables.hrLeaveRequests,
    LocalTables.hrHolidays,
    LocalTables.hrPayrollPeriods,
    LocalTables.hrPayslips,
  ];

  static const List<String> _filterColumns = <String>[
    'department_id',
    'employment_status',
    'employee_id',
    'period_id',
    'facility_id',
    'user_id',
    'status',
  ];

  Map<String, Map<String, Object?>> _table(String name) =>
      tables.putIfAbsent(name, () => <String, Map<String, Object?>>{});

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
    final String table = _tables.firstWhere(
      sql.contains,
      orElse: () => throw UnimplementedError('FakeHrStore cannot run: $sql'),
    );
    Iterable<Map<String, Object?>> rows = _table(table).values
        .where((Map<String, Object?> r) => r['tenant_id'] == parameters[0]);
    int next = 1;
    if (sql.contains('holiday_date >= ?')) {
      final int index = next++;
      rows = rows.where(
        (Map<String, Object?> r) =>
            (r['holiday_date']! as String).compareTo(
              parameters[index]! as String,
            ) >=
            0,
      );
    }
    for (final String column in _filterColumns) {
      if (sql.contains(' and $column = ?')) {
        final int index = next++;
        rows = rows.where(
          (Map<String, Object?> r) => r[column] == parameters[index],
        );
      }
    }
    if (sql.contains('limit ?')) {
      final int limit = parameters.last! as int;
      rows = rows.take(limit);
    }
    return rows.toList(growable: false);
  }

  @override
  Future<Map<String, Object?>?> getById(String table, String id) async {
    _guard();
    return _table(table)[id];
  }

  @override
  Future<void> insert(String table, Map<String, Object?> row) async {
    _guard();
    _table(table)[row['id']! as String] = <String, Object?>{...row};
  }

  @override
  Future<void> update(
    String table,
    String id,
    Map<String, Object?> changes,
  ) async {
    _guard();
    final Map<String, Object?>? row = _table(table)[id];
    if (row == null) {
      throw StateError('missing row $id');
    }
    row.addAll(changes);
  }
}

void main() {
  late FakeHrStore store;
  late DefaultHrRepository repository;

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

  test('registerEmployee round-trips and resolves by user', () async {
    final String id = await repository.registerEmployee(<String, Object?>{
      'tenant_id': 'tenant-1',
      'user_id': 'user-1',
      'employee_code': 'EMP-001',
      'department_id': 'dept-1',
      'designation': 'Staff Nurse',
      'employment_type': 'permanent',
      'employment_status': 'probation',
      'grade': 'G5',
      'reports_to': null,
      'joined_on': '2026-01-05',
      'confirmation_on': null,
      'separated_on': null,
      'notes': null,
      'created_at': now(),
      'updated_at': now(),
    });
    expect((await repository.employeeById(id))!.employeeCode, 'EMP-001');
    final byUser = await repository.employeeForUser('tenant-1', 'user-1');
    expect(byUser, isNotNull);
    expect(byUser!.id, id);
  });

  test('listEmployees filters by department and status', () async {
    for (final (String code, String dept, String status)
        in <(String, String, String)>[
          ('EMP-1', 'dept-1', 'active'),
          ('EMP-2', 'dept-2', 'active'),
          ('EMP-3', 'dept-1', 'probation'),
        ]) {
      await repository.registerEmployee(<String, Object?>{
        'id': code,
        'tenant_id': 'tenant-1',
        'user_id': 'user-$code',
        'employee_code': code,
        'department_id': dept,
        'employment_type': 'permanent',
        'employment_status': status,
        'joined_on': '2026-01-05',
        'created_at': now(),
        'updated_at': now(),
      });
    }
    final result = await repository.listEmployees(
      'tenant-1',
      departmentId: 'dept-1',
      status: EmploymentStatus.active,
    );
    expect(result, hasLength(1));
    expect(result.first.employeeCode, 'EMP-1');
  });

  test('leave requests list by employee', () async {
    await repository.registerLeaveRequest(<String, Object?>{
      'id': 'leave-1',
      'tenant_id': 'tenant-1',
      'employee_id': 'emp-1',
      'leave_type': 'annual',
      'starts_on': '2026-11-01',
      'ends_on': '2026-11-05',
      'status': 'requested',
      'requested_by': 'user-1',
      'created_at': now(),
      'updated_at': now(),
    });
    final rows = await repository.listLeaveRequests(
      'tenant-1',
      employeeId: 'emp-1',
    );
    expect(rows, hasLength(1));
    expect(rows.first.leaveType.label, 'Annual');
  });

  test('listHolidays honours a from-date', () async {
    for (final String date in <String>['2026-01-01', '2026-12-25']) {
      await repository.registerHoliday(<String, Object?>{
        'id': 'h-$date',
        'tenant_id': 'tenant-1',
        'facility_id': null,
        'holiday_date': date,
        'display_name': 'Holiday $date',
        'holiday_type': 'public',
        'is_paid': 1,
        'created_at': now(),
        'updated_at': now(),
      });
    }
    final rows = await repository.listHolidays(
      'tenant-1',
      fromDate: '2026-06-01',
    );
    expect(rows, hasLength(1));
    expect(rows.first.holidayDate, '2026-12-25');
    expect(rows.first.isPaid, isTrue);
  });

  test('payroll periods and payslips round-trip', () async {
    await repository.registerPayrollPeriod(<String, Object?>{
      'id': 'period-1',
      'tenant_id': 'tenant-1',
      'facility_id': 'facility-1',
      'period_start': '2026-10-01',
      'period_end': '2026-10-31',
      'pay_date': '2026-11-05',
      'currency': 'BDT',
      'status': 'draft',
      'created_at': now(),
      'updated_at': now(),
    });
    await repository.registerPayslip(<String, Object?>{
      'id': 'slip-1',
      'tenant_id': 'tenant-1',
      'period_id': 'period-1',
      'employee_id': 'emp-1',
      'gross_minor': 5000000,
      'deductions_minor': 500000,
      'net_minor': 4500000,
      'status': 'draft',
      'created_at': now(),
      'updated_at': now(),
    });
    final periods = await repository.listPayrollPeriods(
      'tenant-1',
      status: PayrollStatus.draft,
    );
    expect(periods, hasLength(1));
    final slips = await repository.listPayslips(
      'tenant-1',
      periodId: 'period-1',
    );
    expect(slips, hasLength(1));
    expect(slips.first.netMinor, 4500000);
  });

  test('closed store raises and maps', () async {
    store.closed = true;
    expect(
      () => repository.listEmployees('tenant-1'),
      throwsA(isA<NodexError>()),
    );
  });
}
