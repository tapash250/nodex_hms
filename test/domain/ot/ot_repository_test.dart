/// Operation theatre repository tests over the local projection (Module 19).
///
/// The repository is the only path the presentation layer has to the theatre
/// tables, so round trips must preserve every column the entities decode and
/// the read scopes (by id, patient, room, and booking) must filter correctly.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/ot/ot.dart';
import 'package:nodex_hms/domain/ot/ot_repository.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';

/// In-memory stand-in for the PowerSync-backed patient store.
final class FakeOtStore implements PatientLocalStore {
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
    if (sql.contains(LocalTables.otBookings)) {
      final Iterable<Map<String, Object?>> rows = _table(LocalTables.otBookings)
          .values;
      if (sql.contains('where id = ?')) {
        return _by(rows, 'id', parameters[0]! as String);
      }
      if (sql.contains('where patient_id = ?')) {
        return _by(rows, 'patient_id', parameters[0]! as String);
      }
      if (sql.contains('where theatre_room = ?')) {
        return _by(rows, 'theatre_room', parameters[0]! as String);
      }
      return rows.toList(growable: false);
    }
    if (sql.contains(LocalTables.otPreOpAssessments)) {
      return _child(LocalTables.otPreOpAssessments, sql, parameters);
    }
    if (sql.contains(LocalTables.otAnesthesiaRecords)) {
      return _child(LocalTables.otAnesthesiaRecords, sql, parameters);
    }
    if (sql.contains(LocalTables.otProcedureLogs)) {
      return _child(LocalTables.otProcedureLogs, sql, parameters);
    }
    if (sql.contains(LocalTables.otPostOpRecords)) {
      return _child(LocalTables.otPostOpRecords, sql, parameters);
    }
    throw UnimplementedError('FakeOtStore cannot run: $sql');
  }

  List<Map<String, Object?>> _child(
    String table,
    String sql,
    List<Object?> parameters,
  ) {
    final Iterable<Map<String, Object?>> rows = _table(table).values;
    if (sql.contains('where booking_id = ?')) {
      return _by(rows, 'booking_id', parameters[0]! as String);
    }
    if (sql.contains('where id = ?')) {
      return _by(rows, 'id', parameters[0]! as String);
    }
    return rows.toList(growable: false);
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
  late FakeOtStore store;
  late DefaultOtRepository repository;

  setUp(() {
    store = FakeOtStore();
    repository = DefaultOtRepository(
      store: store,
      logger: NodexLogger(
        sinks: <NodexLogSink>[InMemoryLogSink()],
        minimumLevel: NodexLogLevel.trace,
      ),
    );
  });

  DateTime start() => DateTime.utc(2026, 9, 20, 9);

  OtBooking booking({
    String id = 'booking-1',
    String patientId = 'patient-1',
    String room = 'OT 1',
    OtBookingStatus status = OtBookingStatus.scheduled,
  }) => OtBooking(
    id: id,
    tenantId: 'tenant-1',
    patientId: patientId,
    theatreRoom: room,
    procedureName: 'Appendectomy',
    scheduledStart: start(),
    scheduledEnd: start().add(const Duration(hours: 2)),
    surgeonId: 'doctor-1',
    status: status,
    priority: OtPriority.routine,
    createdBy: 'doctor-1',
    createdAt: start(),
    updatedAt: start(),
  );

  group('bookings', () {
    test('missing rows read as null', () async {
      expect(await repository.bookingById('absent'), isNull);
    });

    test('upsert inserts then updates in place', () async {
      await repository.upsertBooking(booking());
      final OtBooking? created = await repository.bookingById('booking-1');
      expect(created, isNotNull);
      expect(created!.status, OtBookingStatus.scheduled);

      await repository.upsertBooking(
        booking(status: OtBookingStatus.inProgress),
      );
      final OtBooking? updated = await repository.bookingById('booking-1');
      expect(updated!.status, OtBookingStatus.inProgress);
      expect(store.tables[LocalTables.otBookings]!.length, 1);
    });

    test('patient, room and full-list scopes filter correctly', () async {
      await repository.upsertBooking(booking(id: 'booking-1', room: 'OT 1'));
      await repository.upsertBooking(
        booking(id: 'booking-2', patientId: 'patient-2', room: 'OT 2'),
      );

      expect(
        (await repository.bookingsForPatient('patient-1'))
            .map((OtBooking b) => b.id),
        <String>['booking-1'],
      );
      expect(
        (await repository.bookingsForRoom('OT 2')).map((OtBooking b) => b.id),
        <String>['booking-2'],
      );
      expect((await repository.allBookings()).length, 2);
    });
  });

  group('per-case records', () {
    test('missing records read as null', () async {
      expect(await repository.preOpForBooking('absent'), isNull);
      expect(await repository.anesthesiaForBooking('absent'), isNull);
      expect(await repository.procedureLogForBooking('absent'), isNull);
      expect(await repository.postOpForBooking('absent'), isNull);
    });

    test('pre-op round-trips fitness and ASA class', () async {
      await repository.upsertBooking(booking());
      final OtPreOpAssessment assessment = OtPreOpAssessment(
        id: 'preop-1',
        tenantId: 'tenant-1',
        bookingId: 'booking-1',
        patientId: 'patient-1',
        assessedBy: 'doctor-1',
        assessedAt: start(),
        fitness: OtFitness.fit,
        asaClass: 2,
        notes: 'Fit for surgery.',
        createdAt: start(),
        updatedAt: start(),
      );
      await repository.upsertPreOpAssessment(assessment);

      final OtPreOpAssessment? loaded = await repository.preOpForBooking(
        'booking-1',
      );
      expect(loaded!.fitness, OtFitness.fit);
      expect(loaded.asaClass, 2);
      expect(loaded.notes, 'Fit for surgery.');
    });

    test('anesthesia, procedure and post-op round-trip by booking', () async {
      await repository.upsertBooking(booking());
      await repository.upsertAnesthesiaRecord(
        OtAnesthesiaRecord(
          id: 'anesthesia-1',
          tenantId: 'tenant-1',
          bookingId: 'booking-1',
          patientId: 'patient-1',
          anesthesiaType: OtAnesthesiaType.general,
          recordedBy: 'doctor-2',
          startedAt: start(),
          endedAt: start().add(const Duration(hours: 2)),
          createdAt: start(),
          updatedAt: start(),
        ),
      );
      await repository.upsertProcedureLog(
        OtProcedureLog(
          id: 'procedure-1',
          tenantId: 'tenant-1',
          bookingId: 'booking-1',
          patientId: 'patient-1',
          procedureName: 'Appendectomy',
          performedBy: 'doctor-1',
          startedAt: start(),
          completedAt: start().add(const Duration(hours: 1)),
          createdAt: start(),
          updatedAt: start(),
        ),
      );
      await repository.upsertPostOpRecord(
        OtPostOpRecord(
          id: 'postop-1',
          tenantId: 'tenant-1',
          bookingId: 'booking-1',
          patientId: 'patient-1',
          recordedBy: 'nurse-1',
          recordedAt: start(),
          condition: OtPostOpCondition.stable,
          painScore: 3,
          createdAt: start(),
          updatedAt: start(),
        ),
      );

      expect(
        (await repository.anesthesiaForBooking('booking-1'))!.isComplete,
        isTrue,
      );
      expect(
        (await repository.procedureLogForBooking('booking-1'))!.isComplete,
        isTrue,
      );
      expect((await repository.postOpForBooking('booking-1'))!.painScore, 3);
      expect(await repository.preOpForBooking('booking-2'), isNull);
    });
  });

  group('failure mapping', () {
    test('a closed database surfaces as a persistence error', () async {
      store.closed = true;
      expect(repository.allBookings, throwsA(isA<PersistenceError>()));
    });
  });
}
