/// Physiotherapy repository tests over the local projection (Module 20).
///
/// The repository is the only path the presentation layer has to the
/// physiotherapy tables, so round trips must preserve every column the
/// entities decode and the read scopes (by patient and by session) must
/// filter correctly.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';
import 'package:nodex_hms/domain/physio/physio.dart';
import 'package:nodex_hms/domain/physio/physio_repository.dart';

/// In-memory stand-in for the PowerSync-backed patient store.
final class FakePhysioStore implements PatientLocalStore {
  /// Tables keyed by name, then row id.
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
    if (sql.contains(LocalTables.physioSessions)) {
      final Iterable<Map<String, Object?>> rows = _table(
        LocalTables.physioSessions,
      ).values;
      if (sql.contains('where patient_id = ?')) {
        return _by(rows, 'patient_id', parameters[0]! as String);
      }
      return rows.toList(growable: false);
    }
    if (sql.contains(LocalTables.physioExercisePlans)) {
      final Iterable<Map<String, Object?>> rows = _table(
        LocalTables.physioExercisePlans,
      ).values;
      if (sql.contains('where patient_id = ?')) {
        return _by(rows, 'patient_id', parameters[0]! as String);
      }
      throw UnimplementedError('FakePhysioStore cannot run: $sql');
    }
    if (sql.contains(LocalTables.physioRecoveryNotes)) {
      final Iterable<Map<String, Object?>> rows = _table(
        LocalTables.physioRecoveryNotes,
      ).values;
      if (sql.contains('where session_id = ?')) {
        return _by(rows, 'session_id', parameters[0]! as String);
      }
      throw UnimplementedError('FakePhysioStore cannot run: $sql');
    }
    throw UnimplementedError('FakePhysioStore cannot run: $sql');
  }

  List<Map<String, Object?>> _by(
    Iterable<Map<String, Object?>> rows,
    String column,
    String value,
  ) => rows
      .where((Map<String, Object?> row) => row[column] == value)
      .toList(growable: false);

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
    existing.addAll(changes);
  }
}

void main() {
  late FakePhysioStore store;
  late DefaultPhysioRepository repository;

  setUp(() {
    store = FakePhysioStore();
    repository = DefaultPhysioRepository(
      store: store,
      logger: NodexLogger(
        sinks: <NodexLogSink>[InMemoryLogSink()],
        minimumLevel: NodexLogLevel.trace,
      ),
    );
  });

  PhysioSession session({
    String id = 'session-1',
    String patientId = 'patient-1',
    PhysioSessionStatus status = PhysioSessionStatus.scheduled,
  }) => PhysioSession(
    id: id,
    tenantId: 'tenant-1',
    patientId: patientId,
    physiotherapistId: 'user-1',
    sessionCode: 'PHY-00$id',
    sessionType: PhysioSessionType.therapy,
    bodyArea: 'Left knee',
    status: status,
    scheduledAt: DateTime.utc(2026, 9, 20, 9),
    createdAt: DateTime.utc(2026, 9, 19),
    updatedAt: DateTime.utc(2026, 9, 19),
  );

  PhysioExercisePlan plan({
    String id = 'plan-1',
    String patientId = 'patient-1',
  }) => PhysioExercisePlan(
    id: id,
    tenantId: 'tenant-1',
    patientId: patientId,
    sessionId: 'session-1',
    prescribedBy: 'doctor-1',
    exerciseName: 'Straight leg raise',
    setsCount: 3,
    repsCount: 12,
    frequencyPerWeek: 5,
    durationWeeks: 6,
    status: PhysioPlanStatus.active,
    createdAt: DateTime.utc(2026, 9, 20),
    updatedAt: DateTime.utc(2026, 9, 20),
  );

  PhysioRecoveryNote note({
    String id = 'note-1',
    String sessionId = 'session-1',
    int? painScore = 3,
  }) => PhysioRecoveryNote(
    id: id,
    tenantId: 'tenant-1',
    sessionId: sessionId,
    recordedBy: 'nurse-1',
    content: 'Tolerated exercises well.',
    painScore: painScore,
    recordedAt: DateTime.utc(2026, 9, 20, 10),
    createdAt: DateTime.utc(2026, 9, 20, 10),
    updatedAt: DateTime.utc(2026, 9, 20, 10),
  );

  group('sessions', () {
    test('missing sessions read as null', () async {
      expect(await repository.sessionById('absent'), isNull);
    });

    test('upsert inserts then updates in place', () async {
      await repository.upsertSession(session());
      final PhysioSession? created = await repository.sessionById('session-1');
      expect(created, isNotNull);
      expect(created!.status, PhysioSessionStatus.scheduled);

      await repository.upsertSession(
        session(status: PhysioSessionStatus.inProgress),
      );
      final PhysioSession? updated = await repository.sessionById('session-1');
      expect(updated!.status, PhysioSessionStatus.inProgress);
      expect(store.tables[LocalTables.physioSessions]!.length, 1);
    });

    test(
      'patient scope filters sessions and allSessions returns every row',
      () async {
        await repository.upsertSession(session(id: 'session-1'));
        await repository.upsertSession(
          session(id: 'session-2', patientId: 'patient-2'),
        );

        expect(
          (await repository.sessionsForPatient('patient-1'))
              .map((PhysioSession s) => s.id),
          <String>['session-1'],
        );
        expect((await repository.allSessions()).length, 2);
      },
    );
  });

  group('exercise plans', () {
    test('missing plans read as null', () async {
      expect(await repository.planById('absent'), isNull);
    });

    test('plan round-trips counts through the patient scope', () async {
      await repository.upsertPlan(plan());
      final List<PhysioExercisePlan> loaded = await repository.plansForPatient(
        'patient-1',
      );

      expect(loaded.single.id, 'plan-1');
      expect(loaded.single.setsCount, 3);
      expect((await repository.planById('plan-1'))!.repsCount, 12);
      expect(await repository.plansForPatient('patient-2'), isEmpty);
    });
  });

  group('recovery notes', () {
    test('a session without notes reads empty', () async {
      expect(await repository.notesForSession('absent'), isEmpty);
    });

    test('note round-trips content and pain score', () async {
      await repository.upsertNote(note());
      await repository.upsertNote(note(id: 'note-2', painScore: null));

      final List<PhysioRecoveryNote> loaded = await repository.notesForSession(
        'session-1',
      );
      expect(loaded.length, 2);
      expect(loaded.first.content, 'Tolerated exercises well.');
      expect(loaded.first.painScore, 3);
      expect(
        loaded.firstWhere((PhysioRecoveryNote n) => n.id == 'note-2').painScore,
        isNull,
      );
      expect(await repository.notesForSession('session-2'), isEmpty);
    });
  });

  group('failure mapping', () {
    test('a closed database surfaces as a persistence error', () async {
      store.closed = true;
      expect(repository.allSessions, throwsA(isA<PersistenceError>()));
    });
  });
}
