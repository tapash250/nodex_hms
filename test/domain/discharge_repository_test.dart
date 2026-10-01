/// Tests for the discharge repository over a fake local store.
///
/// Mirrors the bed repository tests: the SQL surface is faked with just
/// enough understanding for the repository's queries.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/discharge/discharge.dart';
import 'package:nodex_hms/domain/discharge/discharge_repository.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';

/// In-memory [PatientLocalStore] extended with the discharges table.
final class FakeDischargeStore implements PatientLocalStore {
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
    if (sql.contains(LocalTables.discharges)) {
      if (sql.contains('encounter_id = ?')) {
        final String encounterId = parameters[0]! as String;
        return _table(LocalTables.discharges).values
            .where((Map<String, Object?> r) => r['encounter_id'] == encounterId)
            .toList(growable: false);
      }
      final String patientId = parameters[0]! as String;
      return _table(LocalTables.discharges).values
          .where((Map<String, Object?> r) => r['patient_id'] == patientId)
          .toList(growable: false);
    }
    // The discharge-management artifacts are read through the same store.
    for (final (String table, String column) in <(String, String)>[
      (LocalTables.dischargeClearances, 'discharge_id'),
      (LocalTables.dischargeReconciliations, 'discharge_id'),
      (LocalTables.dischargeReconciliationItems, 'reconciliation_id'),
      (LocalTables.dischargeSettlements, 'discharge_id'),
      (LocalTables.dischargeAiSummaries, 'discharge_id'),
    ]) {
      if (!sql.contains(table)) continue;
      return _table(table).values
          .where((Map<String, Object?> r) => r[column] == parameters[0])
          .toList(growable: false);
    }
    throw UnimplementedError('FakeDischargeStore cannot run: $sql');
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
  late FakeDischargeStore store;
  late DefaultDischargeRepository repository;

  setUp(() {
    store = FakeDischargeStore();
    repository = DefaultDischargeRepository(
      store: store,
      logger: NodexLogger(
        sinks: <NodexLogSink>[InMemoryLogSink()],
        minimumLevel: NodexLogLevel.trace,
      ),
    );
  });

  Future<String> seedDraft({String encounterId = 'enc-1'}) =>
      repository.createDischarge(
        Discharge.draftRow(
          tenantId: 'tenant-1',
          patientId: 'patient-1',
          encounterId: encounterId,
          createdBy: 'doctor-1',
          dischargeCode: 'D-001',
          dischargeType: DischargeType.routine,
        ),
      );

  group('records', () {
    test('creates and lists drafts for a patient', () async {
      final String id = await seedDraft();

      final List<Discharge> records = await repository.listForPatient(
        'patient-1',
      );
      expect(records.map((Discharge d) => d.id), contains(id));
    });

    test('getByEncounter finds the single record', () async {
      final String id = await seedDraft();
      expect((await repository.getByEncounter('enc-1'))!.id, id);
      expect(await repository.getByEncounter('enc-9'), isNull);
    });

    test('getDischarge returns null when absent', () async {
      expect(await repository.getDischarge('missing'), isNull);
    });

    test('a closed store surfaces PersistenceError', () async {
      store.closed = true;
      await expectLater(
        repository.listForPatient('patient-1'),
        throwsA(isA<PersistenceError>()),
      );
    });
  });
}
