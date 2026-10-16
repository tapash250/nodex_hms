/// Tests for the hospital contacts repository over a fake local store
/// (Module 42).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/contacts/contact.dart';
import 'package:nodex_hms/domain/contacts/contact_repository.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';

/// A minimal in-memory store covering the contacts table.
final class FakeContactStore implements PatientLocalStore {
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
    if (!sql.contains(LocalTables.directoryContacts)) {
      throw UnimplementedError('FakeContactStore cannot run: $sql');
    }
    Iterable<Map<String, Object?>> rows = _table(LocalTables.directoryContacts)
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
  late FakeContactStore store;
  late DefaultContactRepository repository;

  setUp(() {
    store = FakeContactStore();
    repository = DefaultContactRepository(
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
    String category = 'support',
    String status = 'active',
    String? facilityId,
    bool isEmergency = false,
    int displayOrder = 100,
    String name = 'Contact',
  }) => repository.registerContact(<String, Object?>{
    'id': id,
    'tenant_id': 'tenant-1',
    'facility_id': facilityId,
    'name': name,
    'category': category,
    'phone_primary': '555-0000',
    'is_emergency': isEmergency,
    'available_24_7': 0,
    'display_order': displayOrder,
    'status': status,
    'created_by': 'user-1',
    'created_at': now(),
    'updated_at': now(),
  });

  test('registerContact stores and resolves by id', () async {
    final String id = await seed(id: 'c-1', name: 'Blood bank');
    final DirectoryContact? contact = await repository.contactById(id);
    expect(contact, isNotNull);
    expect(contact!.name, 'Blood bank');
    expect(contact.category, ContactCategory.support);
    expect(contact.isEmergency, isFalse);
  });

  test(
    'listContacts excludes archived by default and honours the flag',
    () async {
      await seed(id: 'c-active', name: 'Active');
      await seed(id: 'c-archived', name: 'Archived', status: 'archived');

      final List<DirectoryContact> active = await repository.listContacts(
        'tenant-1',
      );
      expect(active.map((DirectoryContact c) => c.id), contains('c-active'));
      expect(
        active.map((DirectoryContact c) => c.id),
        isNot(contains('c-archived')),
      );

      final List<DirectoryContact> all = await repository.listContacts(
        'tenant-1',
        includeArchived: true,
      );
      expect(all, hasLength(2));
    },
  );

  test('listContacts filters by category and facility', () async {
    await seed(id: 'c-1', category: 'emergency', isEmergency: true);
    await seed(id: 'c-2', category: 'external', facilityId: 'f-1');

    final List<DirectoryContact> emergencies = await repository.listContacts(
      'tenant-1',
      category: ContactCategory.emergency,
    );
    expect(emergencies, hasLength(1));
    expect(emergencies.first.id, 'c-1');

    final List<DirectoryContact> facilityOne = await repository.listContacts(
      'tenant-1',
      facilityId: 'f-1',
    );
    expect(facilityOne, hasLength(1));
    expect(facilityOne.first.id, 'c-2');
  });

  test('updateContact applies changes', () async {
    await seed(id: 'c-1');
    await repository.updateContact('c-1', <String, Object?>{
      'name': 'Renamed',
      'updated_at': now(),
    });
    expect((await repository.contactById('c-1'))!.name, 'Renamed');
  });

  test('closed store raises and maps', () async {
    store.closed = true;
    expect(
      () => repository.listContacts('tenant-1'),
      throwsA(isA<NodexError>()),
    );
  });
}
