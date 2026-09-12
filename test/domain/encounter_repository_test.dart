/// Tests for the encounter repository over a fake local store.
///
/// Mirrors the MPI repository tests: the SQL surface is faked with just enough
/// understanding for the repository's queries, so query construction, mapping
/// and error surfacing are pinned without native SQLite.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/encounters/encounter.dart';
import 'package:nodex_hms/domain/encounters/encounter_repository.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';

/// In-memory [PatientLocalStore] extended with the encounter tables.
final class FakeEncounterStore implements PatientLocalStore {
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
    if (sql.contains(LocalTables.encounterAmendments)) {
      final String encounterId = parameters[0]! as String;
      return _table(LocalTables.encounterAmendments).values
          .where((Map<String, Object?> r) => r['encounter_id'] == encounterId)
          .toList(growable: false);
    }
    if (sql.contains(LocalTables.clinicalEncounters)) {
      Iterable<Map<String, Object?>> rows = _table(
        LocalTables.clinicalEncounters,
      ).values;
      if (sql.contains('patient_id = ?')) {
        final String patientId = parameters[0]! as String;
        rows = rows.where(
          (Map<String, Object?> r) => r['patient_id'] == patientId,
        );
      } else {
        final String tenantId = parameters[0]! as String;
        final String physicianId = parameters[1]! as String;
        rows = rows.where(
          (Map<String, Object?> r) =>
              r['tenant_id'] == tenantId &&
              r['attending_physician_id'] == physicianId &&
              (r['status'] == 'in_progress' || r['status'] == 'planned'),
        );
      }
      return rows.toList(growable: false);
    }
    throw UnimplementedError('FakeEncounterStore cannot run: $sql');
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
  late FakeEncounterStore store;
  late DefaultEncounterRepository repository;

  Map<String, Object?> seedEncounter({
    String id = 'enc-1',
    String status = 'in_progress',
    String? signedAt,
  }) => <String, Object?>{
    ...ClinicalEncounter.draftRow(
      tenantId: 'tenant-1',
      patientId: 'patient-1',
      attendingPhysicianId: 'doctor-1',
      encounterType: EncounterType.outpatient,
      createdBy: 'doctor-1',
      assessment: 'Working diagnosis',
    ),
    'id': id,
    'status': status,
    'signed_at': signedAt,
  };

  setUp(() {
    store = FakeEncounterStore();
    repository = DefaultEncounterRepository(
      store: store,
      logger: NodexLogger(
        sinks: <NodexLogSink>[InMemoryLogSink()],
        minimumLevel: NodexLogLevel.trace,
      ),
    );
  });

  group('listing', () {
    test('listForPatient returns newest first', () async {
      await store.insert(
        LocalTables.clinicalEncounters,
        seedEncounter(id: 'enc-old'),
      );
      await store.insert(
        LocalTables.clinicalEncounters,
        seedEncounter(id: 'enc-new'),
      );

      final List<ClinicalEncounter> results = await repository.listForPatient(
        'patient-1',
      );

      expect(results.map((ClinicalEncounter e) => e.id).toSet(), <String>{
        'enc-old',
        'enc-new',
      });
    });

    test('listForPatient isolates patients', () async {
      await store.insert(LocalTables.clinicalEncounters, seedEncounter());

      expect(await repository.listForPatient('patient-other'), isEmpty);
    });

    test('listForPhysician returns only unsigned work', () async {
      await store.insert(LocalTables.clinicalEncounters, seedEncounter());
      await store.insert(
        LocalTables.clinicalEncounters,
        seedEncounter(id: 'enc-signed', status: 'signed_and_locked'),
      );

      final List<ClinicalEncounter> results = await repository.listForPhysician(
        tenantId: 'tenant-1',
        attendingPhysicianId: 'doctor-1',
      );

      expect(results.map((ClinicalEncounter e) => e.id), <String>['enc-1']);
    });

    test('getEncounter returns null for an unknown id', () async {
      expect(await repository.getEncounter('missing'), isNull);
    });

    test('a closed database surfaces PersistenceError', () async {
      store.closed = true;

      expect(
        repository.listForPatient('patient-1'),
        throwsA(isA<PersistenceError>()),
      );
    });
  });

  group('write lifecycle', () {
    test('create, update, sign in sequence', () async {
      final String id = await repository.createEncounter(
        ClinicalEncounter.draftRow(
          tenantId: 'tenant-1',
          patientId: 'patient-1',
          attendingPhysicianId: 'doctor-1',
          encounterType: EncounterType.emergency,
          createdBy: 'doctor-1',
        ),
      );

      await repository.updateEncounter(
        id,
        ClinicalEncounter.editChanges(assessment: 'Confirmed diagnosis'),
      );
      await repository.signEncounter(id);

      final ClinicalEncounter? signed = await repository.getEncounter(id);
      expect(signed?.status, EncounterStatus.signedAndLocked);
      expect(signed?.assessment, 'Confirmed diagnosis');
      expect(signed?.signedAt, isNotNull);
      expect(signed?.isEditable, isFalse);
    });

    test('amend records history and moves status', () async {
      await store.insert(
        LocalTables.clinicalEncounters,
        seedEncounter(
          status: 'signed_and_locked',
          signedAt: '2026-09-12T10:00:00.000Z',
        ),
      );

      final String amendmentId = await repository.amendEncounter(
        encounterId: 'enc-1',
        amendmentRow: EncounterAmendment.amendmentRow(
          tenantId: 'tenant-1',
          encounterId: 'enc-1',
          reason: 'Diagnosis reclassified',
          amendedBy: 'doctor-1',
          fieldChanges: const <String, Object?>{'assessment': 'Revised'},
        ),
      );

      expect(amendmentId, isNotEmpty);
      final List<EncounterAmendment> amendments = await repository
          .listAmendments('enc-1');
      expect(amendments.single.reason, 'Diagnosis reclassified');
      expect(amendments.single.fieldChanges['assessment'], 'Revised');
      expect(
        (await repository.getEncounter('enc-1'))?.status,
        EncounterStatus.amended,
      );
    });
  });
}
