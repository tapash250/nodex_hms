/// Tests for the workforce repository over a fake local store.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';
import 'package:nodex_hms/domain/workforce/workforce.dart';
import 'package:nodex_hms/domain/workforce/workforce_repository.dart';

final class FakeWorkforceStore implements PatientLocalStore {
  final Map<String, Map<String, Map<String, Object?>>> tables =
      <String, Map<String, Map<String, Object?>>>{};
  bool closed = false;

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
    if (sql.contains(LocalTables.staffShifts)) {
      Iterable<Map<String, Object?>> rows = _table(LocalTables.staffShifts)
          .values;
      rows = rows.where(
        (Map<String, Object?> r) => r['tenant_id'] == parameters[0],
      );
      int next = 1;
      if (sql.contains('facility_id = ?')) {
        final int index = next++;
        rows = rows.where(
          (Map<String, Object?> r) => r['facility_id'] == parameters[index],
        );
      }
      if (sql.contains('shift_date = ?')) {
        final int index = next++;
        rows = rows.where(
          (Map<String, Object?> r) => r['shift_date'] == parameters[index],
        );
      }
      final int limit = parameters.last! as int;
      return rows.take(limit).toList(growable: false);
    }
    if (sql.contains(LocalTables.dutyAllocations)) {
      Iterable<Map<String, Object?>> rows = _table(LocalTables.dutyAllocations)
          .values;
      rows = rows.where(
        (Map<String, Object?> r) => r['tenant_id'] == parameters[0],
      );
      int next = 1;
      if (sql.contains('shift_id = ?')) {
        final int index = next++;
        rows = rows.where(
          (Map<String, Object?> r) => r['shift_id'] == parameters[index],
        );
      }
      if (sql.contains('staff_user_id = ?')) {
        final int index = next++;
        rows = rows.where(
          (Map<String, Object?> r) => r['staff_user_id'] == parameters[index],
        );
      }
      final int limit = parameters.last! as int;
      return rows.take(limit).toList(growable: false);
    }
    if (sql.contains(LocalTables.attendanceLogs)) {
      return _table(LocalTables.attendanceLogs).values
          .where(
            (Map<String, Object?> r) => r['allocation_id'] == parameters[0],
          )
          .toList(growable: false);
    }
    throw UnimplementedError('FakeWorkforceStore cannot run: $sql');
  }

  @override
  Future<Map<String, Object?>?> getById(String table, String id) async {
    _guard();
    return _table(table)[id];
  }

  @override
  Future<void> insert(String table, Map<String, Object?> row) async {
    _guard();
    final String id = row['id']! as String;
    _table(table)[id] = <String, Object?>{...row};
  }

  @override
  Future<void> update(
    String table,
    String id,
    Map<String, Object?> changes,
  ) async {
    _guard();
    final Map<String, Object?>? existing = _table(table)[id];
    if (existing == null) {
      throw StateError('missing row $id');
    }
    existing.addAll(changes);
  }
}

void main() {
  late FakeWorkforceStore store;
  late DefaultWorkforceRepository repository;

  setUp(() {
    store = FakeWorkforceStore();
    repository = DefaultWorkforceRepository(
      store: store,
      logger: NodexLogger(
        sinks: <NodexLogSink>[InMemoryLogSink()],
        minimumLevel: NodexLogLevel.trace,
      ),
    );
  });

  test('registerShift stores and returns an id', () async {
    final String id = await repository.registerShift(<String, Object?>{
      'tenant_id': 'tenant-1',
      'facility_id': 'facility-1',
      'shift_date': '2026-10-16',
      'shift_code': 'DAY',
      'display_name': 'Day shift',
      'staff_category': 'nursing',
      'starts_at': DateTime.utc(2026, 10, 16, 8).toIso8601String(),
      'ends_at': DateTime.utc(2026, 10, 16, 16).toIso8601String(),
      'required_headcount': 3,
      'status': 'scheduled',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    final StaffShift? shift = await repository.shiftById(id);
    expect(shift, isNotNull);
    expect(shift!.displayName, 'Day shift');
    expect(shift.requiredHeadcount, 3);
  });

  test('listShifts filters by facility and date', () async {
    await repository.registerShift(<String, Object?>{
      'id': 's-1',
      'tenant_id': 'tenant-1',
      'facility_id': 'f-1',
      'shift_date': '2026-10-16',
      'shift_code': 'DAY',
      'display_name': 'Day shift',
      'staff_category': 'nursing',
      'starts_at': DateTime.utc(2026, 10, 16, 8).toIso8601String(),
      'ends_at': DateTime.utc(2026, 10, 16, 16).toIso8601String(),
      'required_headcount': 1,
      'status': 'scheduled',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    await repository.registerShift(<String, Object?>{
      'id': 's-2',
      'tenant_id': 'tenant-1',
      'facility_id': 'f-1',
      'shift_date': '2026-10-17',
      'shift_code': 'DAY',
      'display_name': 'Day shift',
      'staff_category': 'nursing',
      'starts_at': DateTime.utc(2026, 10, 17, 8).toIso8601String(),
      'ends_at': DateTime.utc(2026, 10, 17, 16).toIso8601String(),
      'required_headcount': 1,
      'status': 'scheduled',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    final List<StaffShift> result = await repository.listShifts(
      'tenant-1',
      facilityId: 'f-1',
      onDate: '2026-10-16',
    );
    expect(result, hasLength(1));
    expect(result.first.id, 's-1');
  });

  test('registerAllocation and listAttendance round-trip', () async {
    final String allocationId = await repository.registerAllocation(
      <String, Object?>{
        'tenant_id': 'tenant-1',
        'shift_id': 's-1',
        'staff_user_id': 'u-1',
        'allocation_role': 'primary',
        'status': 'allocated',
        'allocated_by': 'admin-1',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
    );
    await repository.registerAttendance(<String, Object?>{
      'tenant_id': 'tenant-1',
      'allocation_id': allocationId,
      'staff_user_id': 'u-1',
      'event_type': 'clock_in',
      'occurred_at': DateTime.utc(2026, 10, 16, 8).toIso8601String(),
      'recorded_by': 'admin-1',
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
    final List<AttendanceLog> events = await repository.listAttendance(
      allocationId,
    );
    expect(events, hasLength(1));
    expect(events.first.eventType, AttendanceEventType.clockIn);
  });

  test('closed store raises and maps', () async {
    store.closed = true;
    expect(() => repository.listShifts('tenant-1'), throwsA(isA<NodexError>()));
  });
}
