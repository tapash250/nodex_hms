/// Tests for the department registry repository over a fake local store.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/departments/department.dart';
import 'package:nodex_hms/domain/departments/department_repository.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';

final class FakeDepartmentStore implements PatientLocalStore {
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
    if (!sql.contains(LocalTables.departments)) {
      throw UnimplementedError('FakeDepartmentStore cannot run: $sql');
    }
    Iterable<Map<String, Object?>> rows = _table(LocalTables.departments)
        .values;
    if (sql.contains('tenant_id = ?')) {
      final String tid = parameters[0]! as String;
      rows = rows.where((Map<String, Object?> r) => r['tenant_id'] == tid);
    }
    if (sql.contains('facility_id = ?')) {
      final String fid = parameters[1]! as String;
      rows = rows.where((Map<String, Object?> r) => r['facility_id'] == fid);
    }
    if (sql.contains('code = ?')) {
      final String code = parameters[2]! as String;
      rows = rows.where((Map<String, Object?> r) => r['code'] == code);
    }
    final int limit = (parameters.last is int) ? parameters.last! as int : 200;
    return rows.take(limit).toList(growable: false);
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
  late FakeDepartmentStore store;
  late DefaultDepartmentRepository repository;

  setUp(() {
    store = FakeDepartmentStore();
    repository = DefaultDepartmentRepository(
      store: store,
      logger: NodexLogger(
        sinks: <NodexLogSink>[InMemoryLogSink()],
        minimumLevel: NodexLogLevel.trace,
      ),
    );
  });

  test('registerDepartment stores and returns an id', () async {
    final String id = await repository.registerDepartment(<String, Object?>{
      'tenant_id': 'tenant-1',
      'facility_id': 'facility-1',
      'code': 'CARD',
      'display_name': 'Cardiology',
      'status': 'active',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    final Department? department = await repository.departmentById(id);
    expect(department, isNotNull);
    expect(department!.displayName, 'Cardiology');
  });

  test('listDepartments filters by facility', () async {
    await repository.registerDepartment(<String, Object?>{
      'id': 'd-1',
      'tenant_id': 'tenant-1',
      'facility_id': 'f-1',
      'code': 'CARD',
      'display_name': 'Cardiology',
      'status': 'active',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    await repository.registerDepartment(<String, Object?>{
      'id': 'd-2',
      'tenant_id': 'tenant-1',
      'facility_id': 'f-2',
      'code': 'NEURO',
      'display_name': 'Neurology',
      'status': 'active',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    final List<Department> result = await repository.listDepartments(
      'tenant-1',
      facilityId: 'f-1',
    );
    expect(result, hasLength(1));
    expect(result.first.id, 'd-1');
  });

  test('departmentByCode finds the facility row', () async {
    await repository.registerDepartment(<String, Object?>{
      'id': 'd-3',
      'tenant_id': 'tenant-1',
      'facility_id': 'f-1',
      'code': 'ORTHO',
      'display_name': 'Orthopaedics',
      'status': 'active',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    final Department? found = await repository.departmentByCode(
      'tenant-1',
      'f-1',
      'ORTHO',
    );
    expect(found?.id, 'd-3');
    expect(
      await repository.departmentByCode('tenant-1', 'f-1', 'NONE'),
      isNull,
    );
  });

  test('closed store raises and maps', () async {
    store.closed = true;
    expect(
      () => repository.listDepartments('tenant-1'),
      throwsA(isA<NodexError>()),
    );
  });
}
