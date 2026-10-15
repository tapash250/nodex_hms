/// Tests for the practitioner directory repository over a fake local store.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';
import 'package:nodex_hms/domain/roster/practitioner.dart';
import 'package:nodex_hms/domain/roster/practitioner_repository.dart';

final class FakePractitionerStore implements PatientLocalStore {
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
    if (sql.contains(LocalTables.practitionerProfiles)) {
      Iterable<Map<String, Object?>> rows = _table(
        LocalTables.practitionerProfiles,
      ).values;
      if (sql.contains('tenant_id = ?')) {
        final String tid = parameters[0]! as String;
        rows = rows.where((Map<String, Object?> r) => r['tenant_id'] == tid);
      }
      if (sql.contains('user_id = ?')) {
        final String uid = parameters[1]! as String;
        rows = rows.where((Map<String, Object?> r) => r['user_id'] == uid);
      }
      if (sql.contains('specialty = ?')) {
        // locate specialty param: tenant, specialty, limit
        final String spec = parameters[1]! as String;
        rows = rows.where((Map<String, Object?> r) => r['specialty'] == spec);
      }
      final int limit = (parameters.last is int)
          ? parameters.last! as int
          : 200;
      return rows.take(limit).toList(growable: false);
    }
    if (sql.contains(LocalTables.practitionerOnCalls)) {
      Iterable<Map<String, Object?>> rows = _table(
        LocalTables.practitionerOnCalls,
      ).values;
      if (sql.contains('practitioner_id = ?')) {
        final String pid = parameters[0]! as String;
        rows = rows.where(
          (Map<String, Object?> r) => r['practitioner_id'] == pid,
        );
      } else if (sql.contains('tenant_id = ?')) {
        final String tid = parameters[0]! as String;
        rows = rows.where((Map<String, Object?> r) => r['tenant_id'] == tid);
        final String cutoff = parameters[1]! as String;
        rows = rows.where(
          (Map<String, Object?> r) =>
              (r['ends_at'] as String).compareTo(cutoff) >= 0,
        );
      }
      return rows.toList(growable: false);
    }
    throw UnimplementedError('FakePractitionerStore cannot run: $sql');
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
  late FakePractitionerStore store;
  late DefaultPractitionerRepository repository;

  setUp(() {
    store = FakePractitionerStore();
    repository = DefaultPractitionerRepository(
      store: store,
      logger: NodexLogger(
        sinks: <NodexLogSink>[InMemoryLogSink()],
        minimumLevel: NodexLogLevel.trace,
      ),
    );
  });

  test('registerProfile stores and returns an id', () async {
    final String id = await repository.registerProfile(<String, Object?>{
      'tenant_id': 'tenant-1',
      'user_id': 'user-1',
      'facility_id': 'facility-1',
      'specialty': 'Cardiology',
      'years_experience': 12,
      'accepting_referrals': 1,
      'status': 'active',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    final PractitionerProfile? profile = await repository.profileById(id);
    expect(profile, isNotNull);
    expect(profile!.specialty, 'Cardiology');
  });

  test('listProfiles filters by specialty', () async {
    await repository.registerProfile(<String, Object?>{
      'id': 'p-1',
      'tenant_id': 'tenant-1',
      'user_id': 'u-1',
      'facility_id': 'f-1',
      'specialty': 'Cardiology',
      'years_experience': 0,
      'accepting_referrals': 1,
      'status': 'active',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    await repository.registerProfile(<String, Object?>{
      'id': 'p-2',
      'tenant_id': 'tenant-1',
      'user_id': 'u-2',
      'facility_id': 'f-1',
      'specialty': 'Neurology',
      'years_experience': 0,
      'accepting_referrals': 1,
      'status': 'active',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    final List<PractitionerProfile> cardios = await repository.listProfiles(
      'tenant-1',
      specialty: 'Cardiology',
    );
    expect(cardios, hasLength(1));
    expect(cardios.first.id, 'p-1');
  });

  test('profileForUser returns matching row', () async {
    await repository.registerProfile(<String, Object?>{
      'id': 'p-3',
      'tenant_id': 'tenant-1',
      'user_id': 'target-user',
      'facility_id': 'f-1',
      'specialty': 'Pediatrics',
      'years_experience': 5,
      'accepting_referrals': 1,
      'status': 'active',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    final PractitionerProfile? profile = await repository.profileForUser(
      'tenant-1',
      'target-user',
    );
    expect(profile?.id, 'p-3');
    final PractitionerProfile? none = await repository.profileForUser(
      'tenant-1',
      'unknown',
    );
    expect(none, isNull);
  });

  test('upcomingOnCalls filters by cutoff', () async {
    final String pid = await repository.registerProfile(<String, Object?>{
      'id': 'p-4',
      'tenant_id': 'tenant-1',
      'user_id': 'u-4',
      'facility_id': 'f-1',
      'specialty': 'Surgery',
      'years_experience': 0,
      'accepting_referrals': 1,
      'status': 'active',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    final DateTime now = DateTime.now().toUtc();
    await repository.registerOnCall(<String, Object?>{
      'id': 'oc-1',
      'tenant_id': 'tenant-1',
      'practitioner_id': pid,
      'rotation_type': 'primary',
      'starts_at': now.subtract(const Duration(hours: 1)).toIso8601String(),
      'ends_at': now.add(const Duration(hours: 2)).toIso8601String(),
      'recorded_by': 'rec',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
    final List<OnCallRotation> upcoming = await repository.upcomingOnCalls(
      'tenant-1',
      now,
    );
    expect(upcoming, hasLength(1));
  });

  test('registerOnCall returns id', () async {
    final String id = await repository.registerOnCall(<String, Object?>{
      'tenant_id': 'tenant-1',
      'practitioner_id': 'p-x',
      'rotation_type': 'ward',
      'starts_at': DateTime.now().toUtc().toIso8601String(),
      'ends_at': DateTime.now()
          .toUtc()
          .add(const Duration(hours: 4))
          .toIso8601String(),
      'recorded_by': 'rec',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    expect(id, isNotEmpty);
  });

  test('closed store raises and maps', () async {
    store.closed = true;
    expect(
      () => repository.listProfiles('tenant-1'),
      throwsA(isA<NodexError>()),
    );
  });
}
