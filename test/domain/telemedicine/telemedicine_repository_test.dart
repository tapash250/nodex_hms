/// Telemedicine repository tests over the local projection (Module 22).
///
/// The repository is the only path the presentation layer has to the
/// telemedicine tables, so round trips must preserve every column the entities
/// decode and the read scopes (by patient and by consultation) must filter
/// correctly.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';
import 'package:nodex_hms/domain/telemedicine/telemedicine.dart';
import 'package:nodex_hms/domain/telemedicine/telemedicine_repository.dart';

/// In-memory stand-in for the PowerSync-backed patient store.
final class FakeTelemedicineStore implements PatientLocalStore {
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
    if (sql.contains(LocalTables.teleConsultations)) {
      final Iterable<Map<String, Object?>> rows = _table(
        LocalTables.teleConsultations,
      ).values;
      if (sql.contains('where patient_id = ?')) {
        return _by(rows, 'patient_id', parameters[0]! as String);
      }
      return rows.toList(growable: false);
    }
    if (sql.contains(LocalTables.teleVitalsOverlays)) {
      final Iterable<Map<String, Object?>> rows = _table(
        LocalTables.teleVitalsOverlays,
      ).values;
      if (sql.contains('where consultation_id = ?')) {
        return _by(rows, 'consultation_id', parameters[0]! as String);
      }
      throw UnimplementedError('FakeTelemedicineStore cannot run: $sql');
    }
    if (sql.contains(LocalTables.teleConsultationArchives)) {
      final Iterable<Map<String, Object?>> rows = _table(
        LocalTables.teleConsultationArchives,
      ).values;
      if (sql.contains('where consultation_id = ?')) {
        return _by(rows, 'consultation_id', parameters[0]! as String);
      }
      throw UnimplementedError('FakeTelemedicineStore cannot run: $sql');
    }
    throw UnimplementedError('FakeTelemedicineStore cannot run: $sql');
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
  late FakeTelemedicineStore store;
  late DefaultTelemedicineRepository repository;

  setUp(() {
    store = FakeTelemedicineStore();
    repository = DefaultTelemedicineRepository(
      store: store,
      logger: NodexLogger(
        sinks: <NodexLogSink>[InMemoryLogSink()],
        minimumLevel: NodexLogLevel.trace,
      ),
    );
  });

  TeleConsultation consultation({
    String id = 'consultation-1',
    String patientId = 'patient-1',
    TeleConsultationStatus status = TeleConsultationStatus.scheduled,
  }) => TeleConsultation(
    id: id,
    tenantId: 'tenant-1',
    patientId: patientId,
    clinicianId: 'doctor-1',
    bookedBy: 'doctor-1',
    visitCode: 'TEL-00$id',
    channel: TeleChannel.video,
    status: status,
    reason: 'Post-op review',
    scheduledAt: DateTime.utc(2026, 9, 20, 9),
    createdAt: DateTime.utc(2026, 9, 19),
    updatedAt: DateTime.utc(2026, 9, 19),
  );

  TeleVitalsOverlay overlay({
    String id = 'overlay-1',
    String consultationId = 'consultation-1',
  }) => TeleVitalsOverlay(
    id: id,
    tenantId: 'tenant-1',
    consultationId: consultationId,
    observedBy: 'nurse-1',
    heartRateBpm: 88,
    spo2Pct: 97,
    observedAt: DateTime.utc(2026, 9, 20, 9, 10),
    createdAt: DateTime.utc(2026, 9, 20, 9, 10),
    updatedAt: DateTime.utc(2026, 9, 20, 9, 10),
  );

  TeleConsultationArchive archive({
    String id = 'archive-1',
    String consultationId = 'consultation-1',
  }) => TeleConsultationArchive(
    id: id,
    tenantId: 'tenant-1',
    consultationId: consultationId,
    archivedBy: 'doctor-1',
    durationSeconds: 1200,
    recordingReference: 'object://tele/$consultationId.m4a',
    consentRecorded: true,
    archivedAt: DateTime.utc(2026, 9, 20, 10),
    createdAt: DateTime.utc(2026, 9, 20, 10),
    updatedAt: DateTime.utc(2026, 9, 20, 10),
  );

  group('consultations', () {
    test('missing consultations read as null', () async {
      expect(await repository.consultationById('absent'), isNull);
    });

    test('upsert inserts then updates in place', () async {
      await repository.upsertConsultation(consultation());
      expect(
        (await repository.consultationById('consultation-1'))!.status,
        TeleConsultationStatus.scheduled,
      );

      await repository.upsertConsultation(
        consultation(status: TeleConsultationStatus.waiting),
      );
      expect(
        (await repository.consultationById('consultation-1'))!.status,
        TeleConsultationStatus.waiting,
      );
      expect(store.tables[LocalTables.teleConsultations]!.length, 1);
    });

    test(
      'patient scope filters and allConsultations returns every row',
      () async {
        await repository.upsertConsultation(consultation(id: 'consultation-1'));
        await repository.upsertConsultation(
          consultation(id: 'consultation-2', patientId: 'patient-2'),
        );

        expect(
          (await repository.consultationsForPatient('patient-1'))
              .map((TeleConsultation c) => c.id),
          <String>['consultation-1'],
        );
        expect((await repository.allConsultations()).length, 2);
      },
    );
  });

  group('vitals overlays', () {
    test('a consultation without readings reads empty', () async {
      expect(await repository.overlaysForConsultation('absent'), isEmpty);
    });

    test('overlays round-trip against the consultation scope', () async {
      await repository.upsertOverlay(overlay());
      await repository.upsertOverlay(
        overlay(id: 'overlay-2', consultationId: 'consultation-2'),
      );

      final List<TeleVitalsOverlay> loaded = await repository
          .overlaysForConsultation('consultation-1');
      expect(loaded.single.id, 'overlay-1');
      expect(loaded.single.heartRateBpm, 88);
      expect(loaded.single.spo2Pct, 97);
      expect(
        await repository.overlaysForConsultation('consultation-2'),
        hasLength(1),
      );
      expect(
        await repository.overlaysForConsultation('consultation-3'),
        isEmpty,
      );
    });
  });

  group('archives', () {
    test('a consultation without an archive reads null', () async {
      expect(await repository.archiveForConsultation('absent'), isNull);
    });

    test('archive round-trips consent and duration', () async {
      await repository.upsertArchive(archive());

      final TeleConsultationArchive? loaded = await repository
          .archiveForConsultation('consultation-1');
      expect(loaded!.durationSeconds, 1200);
      expect(loaded.consentRecorded, isTrue);
      expect(loaded.recordingReference, 'object://tele/consultation-1.m4a');
      expect(await repository.archiveForConsultation('consultation-2'), isNull);
    });
  });

  group('failure mapping', () {
    test('a closed database surfaces as a persistence error', () async {
      store.closed = true;
      expect(repository.allConsultations, throwsA(isA<PersistenceError>()));
    });
  });
}
