/// Tests for the nurse ward station repository over a fake local store
/// (Module 06).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/nursing_station/nursing_station.dart';
import 'package:nodex_hms/domain/nursing_station/nursing_station_repository.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';

/// A minimal in-memory store covering the three ward-station tables.
final class FakeNursingStore implements PatientLocalStore {
  final Map<String, Map<String, Map<String, Object?>>> tables =
      <String, Map<String, Map<String, Object?>>>{};
  bool closed = false;

  static final RegExp _filterPattern = RegExp(r' and (\w+) = \?');

  static const List<String> _tables = <String>[
    LocalTables.wardVitals,
    LocalTables.wardHandovers,
    LocalTables.wardTasks,
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
      orElse: () =>
          throw UnimplementedError('FakeNursingStore cannot run: $sql'),
    );
    Iterable<Map<String, Object?>> rows = _table(table).values
        .where((Map<String, Object?> r) => r['tenant_id'] == parameters[0]);
    int next = 1;
    for (final RegExpMatch match in _filterPattern.allMatches(sql)) {
      final String column = match.group(1)!;
      final Object? expected = parameters[next++];
      rows = rows.where((Map<String, Object?> r) => r[column] == expected);
    }
    if (sql.contains('limit ?')) {
      rows = rows.take(parameters.last! as int);
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
  late FakeNursingStore store;
  late DefaultNursingStationRepository repository;

  setUp(() {
    store = FakeNursingStore();
    repository = DefaultNursingStationRepository(
      store: store,
      logger: NodexLogger(
        sinks: <NodexLogSink>[InMemoryLogSink()],
        minimumLevel: NodexLogLevel.trace,
      ),
    );
  });

  String now() => DateTime.now().toUtc().toIso8601String();

  test('vitals append, resolve by id and filter by ward', () async {
    final String id = await repository.recordVitals(<String, Object?>{
      'tenant_id': 'tenant-1',
      'patient_id': 'patient-1',
      'ward_id': 'ward-1',
      'recorded_by': 'nurse-1',
      'observed_at': '2026-10-16T09:00:00.000Z',
      'temperature_celsius': 38.4,
      'pulse_bpm': 96,
      'respiratory_rate': null,
      'systolic_bp': 118,
      'diastolic_bp': 76,
      'spo2': 96,
      'pain_score': null,
      'consciousness': 'alert',
      'on_oxygen': 0,
      'notes': null,
      'created_at': now(),
    });
    await repository.recordVitals(<String, Object?>{
      'id': 'vital-other',
      'tenant_id': 'tenant-1',
      'patient_id': 'patient-2',
      'ward_id': 'ward-2',
      'recorded_by': 'nurse-1',
      'observed_at': '2026-10-16T09:05:00.000Z',
      'spo2': 99,
      'consciousness': 'alert',
      'on_oxygen': 0,
      'created_at': now(),
    });

    final WardVital stored = (await repository.vitalById(id))!;
    expect(stored.temperatureCelsius, 38.4);
    expect(stored.alert, VitalAlert.warning);

    final List<WardVital> wardOne = await repository.listVitals(
      'tenant-1',
      wardId: 'ward-1',
    );
    expect(wardOne, hasLength(1));
    expect(wardOne.first.id, id);
  });

  test('handovers append and list by ward', () async {
    await repository.recordHandover(<String, Object?>{
      'id': 'handover-1',
      'tenant_id': 'tenant-1',
      'ward_id': 'ward-1',
      'from_user': 'nurse-1',
      'to_user': 'nurse-2',
      'handover_at': '2026-10-16T20:00:00.000Z',
      'summary': 'Stable shift',
      'pending_items': 'Chase bloods on bed 4',
      'created_at': now(),
    });
    final List<WardHandover> rows = await repository.listHandovers(
      'tenant-1',
      wardId: 'ward-1',
    );
    expect(rows, hasLength(1));
    expect(rows.first.summary, 'Stable shift');
    expect(rows.first.pendingItems, 'Chase bloods on bed 4');
  });

  test('tasks create, filter and update', () async {
    final String id = await repository.createTask(<String, Object?>{
      'tenant_id': 'tenant-1',
      'ward_id': 'ward-1',
      'title': 'Repeat obs',
      'task_type': 'observation',
      'priority': 'urgent',
      'due_at': '2026-10-16T10:00:00.000Z',
      'assigned_to': 'nurse-1',
      'status': 'open',
      'created_by': 'nurse-1',
      'created_at': now(),
      'updated_at': now(),
    });
    final List<WardTask> open = await repository.listTasks(
      'tenant-1',
      wardId: 'ward-1',
      status: WardTaskStatus.open,
    );
    expect(open, hasLength(1));
    expect(open.first.title, 'Repeat obs');

    await repository.updateTask(id, <String, Object?>{
      'status': 'done',
      'completed_by': 'nurse-1',
      'completed_at': now(),
    });
    final WardTask stored = (await repository.taskById(id))!;
    expect(stored.status, WardTaskStatus.done);

    final List<WardTask> stillOpen = await repository.listTasks(
      'tenant-1',
      wardId: 'ward-1',
      status: WardTaskStatus.open,
    );
    expect(stillOpen, isEmpty);
  });

  test('closed store raises and maps', () async {
    store.closed = true;
    expect(() => repository.listTasks('tenant-1'), throwsA(isA<NodexError>()));
  });
}
