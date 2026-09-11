/// Tests for the MPI repository over a fake local store.
///
/// The repository never touches SQLite here: [FakePatientStore] stands in for
/// the PowerSync projection, so these tests pin query construction, mapping,
/// validation gating and error surfacing without native dependencies.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/patients/patient.dart';
import 'package:nodex_hms/domain/patients/patient_merge.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';

/// In-memory [PatientLocalStore] with just enough SQL understanding for the
/// repository's queries: equality filters, LIKE matching, ordering and limits
/// are evaluated by hand, not parsed.
final class FakePatientStore implements PatientLocalStore {
  final Map<String, Map<String, Map<String, Object?>>> tables =
      <String, Map<String, Map<String, Object?>>>{};

  /// When true, every operation throws to simulate a closed database.
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
    if (sql.contains(LocalTables.patientAllergies)) {
      final String patientId = parameters[0]! as String;
      final bool activeOnly = sql.contains("status = 'active'");
      return _table(LocalTables.patientAllergies).values
          .where(
            (Map<String, Object?> r) =>
                r['patient_id'] == patientId &&
                (!activeOnly || r['status'] == 'active'),
          )
          .toList(growable: false);
    }
    if (sql.contains(LocalTables.patients)) {
      final String tenantId = parameters[0]! as String;
      Iterable<Map<String, Object?>> rows = _table(LocalTables.patients).values
          .where(
            (Map<String, Object?> r) =>
                r['tenant_id'] == tenantId && r['is_active'] == 1,
          );
      if (parameters.length == 1) {
        // Empty-query listing without an explicit limit.
        final List<Map<String, Object?>> listed = rows.toList(growable: false);
        const int limit = 50;
        return listed.take(limit).toList(growable: false);
      }
      if (parameters.length == 2 && sql.contains('mrn = ?')) {
        // MRN existence probe: (tenant, mrn).
        final String mrn = parameters[1]! as String;
        return rows
            .where((Map<String, Object?> r) => r['mrn'] == mrn)
            .take(1)
            .toList(growable: false);
      }
      if (parameters.length == 2) {
        // Empty-query listing: (tenant, limit).
        final int limit = parameters[1]! as int;
        return rows.take(limit).toList(growable: false);
      }
      // Full search: (tenant, mrn, like, like, like, phonePrefix, limit).
      final String mrn = parameters[1]! as String;
      final String like = (parameters[2]! as String)
          .replaceAll('%', '')
          .toLowerCase();
      final String phonePrefix = (parameters[5]! as String).replaceAll('%', '');
      final int limit = parameters[6]! as int;
      rows = rows.where((Map<String, Object?> r) {
        final String first = (r['first_name']! as String).toLowerCase();
        final String last = (r['last_name']! as String).toLowerCase();
        final String phone = (r['phone_number'] as String?) ?? '';
        return r['mrn'] == mrn ||
            first.contains(like) ||
            last.contains(like) ||
            '$first $last'.contains(like) ||
            phone.startsWith(phonePrefix);
      });
      final List<Map<String, Object?>> sorted = rows.toList(growable: false)
        ..sort((Map<String, Object?> a, Map<String, Object?> b) {
          final int byLast = (a['last_name']! as String).compareTo(
            b['last_name']! as String,
          );
          if (byLast != 0) {
            return byLast;
          }
          return (a['first_name']! as String).compareTo(
            b['first_name']! as String,
          );
        });
      return sorted.take(limit).toList(growable: false);
    }
    throw UnimplementedError('FakePatientStore cannot run: $sql');
  }

  @override
  Future<Map<String, Object?>?> getById(String table, String id) async {
    _guard();
    return _table(table)[id];
  }

  @override
  Future<void> insert(String table, Map<String, Object?> row) async {
    _guard();
    _table(table)[row['id']! as String] = Map<String, Object?>.from(row);
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
      throw StateError('row $id not found in $table');
    }
    _table(table)[id] = <String, Object?>{...existing, ...changes};
  }
}

void main() {
  late FakePatientStore store;
  late DefaultPatientRepository repository;

  Map<String, Object?> seedRow({
    String id = 'patient-1',
    String mrn = 'MRN-001',
    String first = 'Abdul',
    String last = 'Karim',
    String phone = '01700000000',
  }) => <String, Object?>{
    ...Patient.registrationRow(
      tenantId: 'tenant-1',
      mrn: mrn,
      firstName: first,
      lastName: last,
      dateOfBirth: DateTime.utc(1984, 3, 17),
      gender: PatientGender.male,
      phoneNumber: phone,
    ),
    'id': id,
  };

  setUp(() {
    store = FakePatientStore();
    repository = DefaultPatientRepository(
      store: store,
      logger: NodexLogger(
        sinks: <NodexLogSink>[InMemoryLogSink()],
        minimumLevel: NodexLogLevel.trace,
      ),
    );
  });

  group('searchPatients', () {
    test('lists active patients when the query is empty', () async {
      await store.insert(LocalTables.patients, seedRow());
      await store.insert(
        LocalTables.patients,
        seedRow(
          id: 'patient-2',
          mrn: 'MRN-002',
          first: 'Fatima',
          last: 'Begum',
        ),
      );

      final List<Patient> results = await repository.searchPatients(
        tenantId: 'tenant-1',
      );

      // Order is recency by updated_at; assert membership, not order.
      expect(results.map((Patient p) => p.mrn).toSet(), <String>{
        'MRN-002',
        'MRN-001',
      });
    });

    test('matches by MRN, name and phone', () async {
      await store.insert(LocalTables.patients, seedRow());

      expect(
        (await repository.searchPatients(
          tenantId: 'tenant-1',
          query: 'MRN-001',
        )).map((Patient p) => p.id),
        <String>['patient-1'],
      );
      expect(
        (await repository.searchPatients(
          tenantId: 'tenant-1',
          query: 'karim',
        )).map((Patient p) => p.id),
        <String>['patient-1'],
      );
      expect(
        (await repository.searchPatients(
          tenantId: 'tenant-1',
          query: '0170',
        )).map((Patient p) => p.id),
        <String>['patient-1'],
      );
      expect(
        await repository.searchPatients(
          tenantId: 'tenant-1',
          query: 'nonexistent',
        ),
        isEmpty,
      );
    });

    test('isolates tenants', () async {
      await store.insert(LocalTables.patients, seedRow());
      await store.insert(LocalTables.patients, <String, Object?>{
        ...seedRow(id: 'patient-x', mrn: 'MRN-001'),
        'tenant_id': 'tenant-2',
      });

      final List<Patient> results = await repository.searchPatients(
        tenantId: 'tenant-2',
      );

      expect(results.map((Patient p) => p.id), <String>['patient-x']);
    });

    test('surfaces a closed database as PersistenceError', () async {
      store.closed = true;

      expect(
        repository.searchPatients(tenantId: 'tenant-1'),
        throwsA(isA<PersistenceError>()),
      );
    });
  });

  group('registration', () {
    test('mrnExists detects a local duplicate', () async {
      await store.insert(LocalTables.patients, seedRow());

      expect(
        await repository.mrnExists(tenantId: 'tenant-1', mrn: 'MRN-001'),
        isTrue,
      );
      expect(
        await repository.mrnExists(tenantId: 'tenant-1', mrn: 'MRN-999'),
        isFalse,
      );
    });

    test('insertPatient persists and returns the id', () async {
      final String id = await repository.insertPatient(seedRow(id: 'x'));

      expect(id, isNotEmpty);
      expect(await repository.getPatient(id), isNotNull);
    });

    test('getPatient returns null for an unknown id', () async {
      expect(await repository.getPatient('missing'), isNull);
    });
  });

  group('contact updates', () {
    test('applies validated changes', () async {
      await store.insert(LocalTables.patients, seedRow());

      await repository.updatePatientContact('patient-1', <String, Object?>{
        'phone_number': '01800000000',
        'preferred_language': 'bn',
        'updated_at': '2026-09-11T00:00:00.000Z',
      });

      final Patient? updated = await repository.getPatient('patient-1');
      expect(updated?.phoneNumber, '01800000000');
      expect(updated?.preferredLanguage, 'bn');
    });
  });

  group('allergies', () {
    test('records and lists allergies', () async {
      final String id = await repository.insertAllergy(
        PatientAllergy.reportRow(
          tenantId: 'tenant-1',
          patientId: 'patient-1',
          substance: 'Penicillin',
          severity: AllergySeverity.severe,
          recordedBy: 'user-1',
        ),
      );

      final List<PatientAllergy> allergies = await repository.getAllergies(
        'patient-1',
      );

      expect(allergies.map((PatientAllergy a) => a.id), <String>[id]);
      expect(allergies.single.isActive, isTrue);
    });

    test('retires with a reason', () async {
      final String id = await repository.insertAllergy(
        PatientAllergy.reportRow(
          tenantId: 'tenant-1',
          patientId: 'patient-1',
          substance: 'Sulfa',
          severity: AllergySeverity.mild,
        ),
      );

      await repository.retireAllergy(allergyId: id, reason: 'Entered in error');

      expect(await repository.getAllergies('patient-1'), isEmpty);
      final List<PatientAllergy> all = await repository.getAllergies(
        'patient-1',
        activeOnly: false,
      );
      expect(all.single.status, 'retired');
      expect(all.single.retiredReason, 'Entered in error');
    });

    test('retire without a reason throws ValidationError', () async {
      expect(
        repository.retireAllergy(allergyId: 'a', reason: '  '),
        throwsA(isA<ValidationError>()),
      );
    });
  });

  group('merge workflow', () {
    test('records the merge and deactivates the absorbed record', () async {
      await store.insert(LocalTables.patients, seedRow());
      await store.insert(
        LocalTables.patients,
        seedRow(id: 'patient-2', mrn: 'MRN-002'),
      );

      await repository.recordMerge(
        tenantId: 'tenant-1',
        survivingPatientId: 'patient-1',
        mergedPatientId: 'patient-2',
        reason: 'Same person, duplicate registration',
        fieldChoices: const <String, Object?>{'phone_number': 'patient-1'},
        mergedBy: 'user-1',
      );
      await repository.deactivatePatient('patient-2');

      expect((await repository.getPatient('patient-2'))?.isActive, isFalse);
      expect(
        (await repository.searchPatients(tenantId: 'tenant-1'))
            .map((Patient p) => p.id),
        <String>['patient-1'],
      );
    });

    test('merge without a reason throws ValidationError', () async {
      expect(
        repository.recordMerge(
          tenantId: 't',
          survivingPatientId: 'a',
          mergedPatientId: 'b',
          reason: '  ',
          fieldChoices: const <String, Object?>{},
          mergedBy: 'u',
        ),
        throwsA(isA<ValidationError>()),
      );
    });

    test('previewMerge delegates to the merge engine', () {
      final Map<String, Object?> base = <String, Object?>{'phone_number': '1'};
      final Map<String, Object?> local = <String, Object?>{'phone_number': '2'};
      final Map<String, Object?> server = <String, Object?>{
        'phone_number': '3',
      };

      final PatientMergeResult result = repository.previewMerge(
        base: base,
        local: local,
        server: server,
      );

      expect(result.automatic, isFalse);
    });
  });
}
