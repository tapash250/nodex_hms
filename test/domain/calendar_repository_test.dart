/// Tests for the institutional calendar repository over a fake local store
/// (Module 40).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/calendar/calendar.dart';
import 'package:nodex_hms/domain/calendar/calendar_repository.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';

/// A minimal in-memory store covering the calendar table.
final class FakeCalendarStore implements PatientLocalStore {
  final Map<String, Map<String, Map<String, Object?>>> tables =
      <String, Map<String, Map<String, Object?>>>{};
  bool closed = false;

  static final RegExp _filterPattern = RegExp(r' and (\w+) = \?');

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
    if (!sql.contains(LocalTables.calendarEvents)) {
      throw UnimplementedError('FakeCalendarStore cannot run: $sql');
    }
    Iterable<Map<String, Object?>> rows = _table(LocalTables.calendarEvents)
        .values
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
  late FakeCalendarStore store;
  late DefaultCalendarRepository repository;

  setUp(() {
    store = FakeCalendarStore();
    repository = DefaultCalendarRepository(
      store: store,
      logger: NodexLogger(
        sinks: <NodexLogSink>[InMemoryLogSink()],
        minimumLevel: NodexLogLevel.trace,
      ),
    );
  });

  String now() => DateTime.now().toUtc().toIso8601String();

  Future<String> seed({
    required String id,
    String eventType = 'training',
    String status = 'scheduled',
    String? facilityId,
    String startsAt = '2026-10-20T09:00:00.000Z',
    String endsAt = '2026-10-20T17:00:00.000Z',
    String title = 'Event',
  }) => repository.createEvent(<String, Object?>{
    'id': id,
    'tenant_id': 'tenant-1',
    'facility_id': facilityId,
    'title': title,
    'event_type': eventType,
    'starts_at': startsAt,
    'ends_at': endsAt,
    'all_day': 0,
    'status': status,
    'created_by': 'user-1',
    'created_at': now(),
    'updated_at': now(),
  });

  test('createEvent stores and resolves by id', () async {
    final String id = await seed(id: 'e-1', title: 'Fire drill');
    final CalendarEvent? event = await repository.eventById(id);
    expect(event, isNotNull);
    expect(event!.title, 'Fire drill');
    expect(event.eventType, CalendarEventType.training);
    expect(event.isScheduled, isTrue);
  });

  test(
    'listEvents excludes cancelled by default and honours the flag',
    () async {
      await seed(id: 'e-scheduled');
      await seed(id: 'e-cancelled', status: 'cancelled');

      final List<CalendarEvent> scheduled = await repository.listEvents(
        'tenant-1',
      );
      expect(scheduled.map((CalendarEvent e) => e.id), contains('e-scheduled'));
      expect(
        scheduled.map((CalendarEvent e) => e.id),
        isNot(contains('e-cancelled')),
      );

      final List<CalendarEvent> all = await repository.listEvents(
        'tenant-1',
        includeCancelled: true,
      );
      expect(all, hasLength(2));
    },
  );

  test('listEvents filters by type and facility', () async {
    await seed(id: 'e-1', eventType: 'maintenance');
    await seed(id: 'e-2', eventType: 'holiday', facilityId: 'f-1');

    final List<CalendarEvent> maintenance = await repository.listEvents(
      'tenant-1',
      eventType: CalendarEventType.maintenance,
    );
    expect(maintenance, hasLength(1));
    expect(maintenance.first.id, 'e-1');

    final List<CalendarEvent> facilityOne = await repository.listEvents(
      'tenant-1',
      facilityId: 'f-1',
    );
    expect(facilityOne, hasLength(1));
    expect(facilityOne.first.id, 'e-2');
  });

  test('updateEvent applies changes', () async {
    await seed(id: 'e-1', title: 'Original');
    await repository.updateEvent('e-1', <String, Object?>{
      'title': 'Updated',
      'updated_at': now(),
    });
    expect((await repository.eventById('e-1'))!.title, 'Updated');
  });

  test('closed store raises and maps', () async {
    store.closed = true;
    expect(() => repository.listEvents('tenant-1'), throwsA(isA<NodexError>()));
  });
}
