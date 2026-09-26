/// Blood bank repository tests over the local projection (Module 26).
///
/// The repository is the only path the presentation layer has to the blood
/// bank tables, so round trips must preserve every column the entities decode
/// and the read scopes (by id, patient, and request) must filter correctly.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/blood_bank/blood_bank.dart';
import 'package:nodex_hms/domain/blood_bank/blood_bank_repository.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';

/// In-memory stand-in for the PowerSync-backed patient store.
final class FakeBloodBankStore implements PatientLocalStore {
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
    if (sql.contains(LocalTables.transfusionRequests)) {
      return _read(
        sql: sql,
        parameters: parameters,
        rows: _table(LocalTables.transfusionRequests).values,
        idColumn: 'id',
        patientColumn: 'patient_id',
      );
    }
    if (sql.contains(LocalTables.bloodUnits)) {
      final Iterable<Map<String, Object?>> rows = _table(LocalTables.bloodUnits)
          .values;
      if (sql.contains('transfusion_request_id = ?')) {
        final String requestId = parameters[0]! as String;
        return rows
            .where(
              (Map<String, Object?> row) =>
                  row['transfusion_request_id'] == requestId,
            )
            .toList(growable: false);
      }
      return _read(
        sql: sql,
        parameters: parameters,
        rows: rows,
        idColumn: 'id',
        patientColumn: 'patient_id',
      );
    }
    if (sql.contains(LocalTables.transfusions)) {
      return _read(
        sql: sql,
        parameters: parameters,
        rows: _table(LocalTables.transfusions).values,
        idColumn: 'id',
        patientColumn: 'patient_id',
      );
    }
    throw UnimplementedError('FakeBloodBankStore cannot run: $sql');
  }

  List<Map<String, Object?>> _read({
    required String sql,
    required List<Object?> parameters,
    required Iterable<Map<String, Object?>> rows,
    required String idColumn,
    required String patientColumn,
  }) {
    if (sql.contains('where $idColumn = ?')) {
      final String id = parameters[0]! as String;
      return rows
          .where((Map<String, Object?> row) => row[idColumn] == id)
          .toList(growable: false);
    }
    if (sql.contains('$patientColumn = ?')) {
      final String patientId = parameters[0]! as String;
      return rows
          .where((Map<String, Object?> row) => row[patientColumn] == patientId)
          .toList(growable: false);
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
  late FakeBloodBankStore store;
  late DefaultBloodBankRepository repository;

  setUp(() {
    store = FakeBloodBankStore();
    repository = DefaultBloodBankRepository(
      store: store,
      logger: NodexLogger(
        sinks: <NodexLogSink>[InMemoryLogSink()],
        minimumLevel: NodexLogLevel.trace,
      ),
    );
  });

  DateTime at(int hour) => DateTime.utc(2026, 10, 1, hour);

  TransfusionRequest request({
    String id = 'req-1',
    String patientId = 'patient-1',
    TransfusionRequestStatus status = TransfusionRequestStatus.pending,
  }) => TransfusionRequest(
    id: id,
    tenantId: 'tenant-1',
    patientId: patientId,
    requestedBy: 'doctor-1',
    requestedBloodGroup: BloodGroup.oPositive,
    component: BloodComponent.redCells,
    unitsRequested: 1,
    urgency: TransfusionUrgency.routine,
    status: status,
    crossmatchResult: CrossmatchResult.pending,
    requestedAt: at(8),
    createdAt: at(8),
    updatedAt: at(8),
  );

  BloodUnit unit({
    String id = 'unit-1',
    String patientId = 'patient-1',
    String? requestId = 'req-1',
    BloodUnitStatus status = BloodUnitStatus.available,
  }) => BloodUnit(
    id: id,
    tenantId: 'tenant-1',
    unitNumber: 'BU-0001',
    bloodGroup: BloodGroup.oPositive,
    component: BloodComponent.redCells,
    collectedAt: at(6),
    expiresAt: at(6).add(const Duration(days: 21)),
    status: status,
    patientId: patientId,
    transfusionRequestId: requestId,
    createdBy: 'lab-1',
    createdAt: at(6),
    updatedAt: at(6),
  );

  group('transfusion requests', () {
    test('missing rows read as null', () async {
      expect(await repository.requestById('absent'), isNull);
    });

    test('upsert inserts then updates in place', () async {
      await repository.upsertRequest(request());
      final TransfusionRequest? created = await repository.requestById('req-1');
      expect(created, isNotNull);
      expect(created!.status, TransfusionRequestStatus.pending);

      final TransfusionRequest approved = TransfusionRequest(
        id: created.id,
        tenantId: created.tenantId,
        patientId: created.patientId,
        requestedBy: created.requestedBy,
        requestedBloodGroup: created.requestedBloodGroup,
        component: created.component,
        unitsRequested: created.unitsRequested,
        urgency: created.urgency,
        status: TransfusionRequestStatus.approved,
        crossmatchResult: created.crossmatchResult,
        requestedAt: created.requestedAt,
        approvedBy: 'doctor-2',
        approvedAt: at(9),
        createdAt: created.createdAt,
        updatedAt: at(9),
      );
      await repository.upsertRequest(approved);

      final TransfusionRequest? updated = await repository.requestById('req-1');
      expect(updated!.status, TransfusionRequestStatus.approved);
      expect(updated.approvedBy, 'doctor-2');
      expect(store.tables[LocalTables.transfusionRequests]!.length, 1);
    });

    test('patient and full-list scopes filter correctly', () async {
      await repository.upsertRequest(request(id: 'req-1'));
      await repository.upsertRequest(
        request(id: 'req-2', patientId: 'patient-2'),
      );

      final List<TransfusionRequest> forPatient = await repository
          .requestsForPatient('patient-1');
      expect(forPatient.map((TransfusionRequest r) => r.id), <String>['req-1']);
      expect((await repository.allRequests()).length, 2);
    });
  });

  group('blood units', () {
    test('missing rows read as null', () async {
      expect(await repository.bloodUnitById('absent'), isNull);
    });

    test('upsert round-trips every column', () async {
      await repository.upsertBloodUnit(unit());
      final BloodUnit? created = await repository.bloodUnitById('unit-1');
      expect(created, isNotNull);
      expect(created!.unitNumber, 'BU-0001');
      expect(created.status, BloodUnitStatus.available);
      expect(created.volumeMl, isNull);
      expect(created.transfusionRequestId, 'req-1');
    });

    test('request and patient scopes filter correctly', () async {
      await repository.upsertBloodUnit(unit(id: 'unit-1'));
      await repository.upsertBloodUnit(
        unit(id: 'unit-2', patientId: 'patient-2', requestId: null),
      );

      final List<BloodUnit> forRequest = await repository.bloodUnitsForRequest(
        'req-1',
      );
      expect(forRequest.map((BloodUnit b) => b.id), <String>['unit-1']);
      expect(
        (await repository.bloodUnitsForPatient('patient-2'))
            .map((BloodUnit b) => b.id),
        <String>['unit-2'],
      );
      expect((await repository.allBloodUnits()).length, 2);
    });
  });

  group('transfusions', () {
    test('missing rows read as null', () async {
      expect(await repository.transfusionById('absent'), isNull);
    });

    test('outcome updates land on the same row', () async {
      final Transfusion started = Transfusion(
        id: 'tr-1',
        tenantId: 'tenant-1',
        transfusionRequestId: 'req-1',
        bloodUnitId: 'unit-1',
        patientId: 'patient-1',
        recordedBy: 'nurse-1',
        startedAt: at(10),
        status: TransfusionStatus.started,
        createdAt: at(10),
        updatedAt: at(10),
      );
      await repository.upsertTransfusion(started);
      expect(
        (await repository.transfusionsForPatient('patient-1')).single.status,
        TransfusionStatus.started,
      );

      final Transfusion closed = Transfusion(
        id: started.id,
        tenantId: started.tenantId,
        transfusionRequestId: started.transfusionRequestId,
        bloodUnitId: started.bloodUnitId,
        patientId: started.patientId,
        recordedBy: started.recordedBy,
        startedAt: started.startedAt,
        finishedAt: at(12),
        status: TransfusionStatus.transfused,
        volumeMl: 450,
        createdAt: started.createdAt,
        updatedAt: at(12),
      );
      await repository.upsertTransfusion(closed);

      final Transfusion? updated = await repository.transfusionById('tr-1');
      expect(updated!.status, TransfusionStatus.transfused);
      expect(updated.volumeMl, 450);
      expect(updated.isComplete, isTrue);
      expect(store.tables[LocalTables.transfusions]!.length, 1);
    });

    test('patient scope returns only that patient', () async {
      await repository.upsertTransfusion(
        Transfusion(
          id: 'tr-1',
          tenantId: 'tenant-1',
          transfusionRequestId: 'req-1',
          bloodUnitId: 'unit-1',
          patientId: 'patient-1',
          recordedBy: 'nurse-1',
          startedAt: at(10),
          status: TransfusionStatus.started,
          createdAt: at(10),
          updatedAt: at(10),
        ),
      );
      await repository.upsertTransfusion(
        Transfusion(
          id: 'tr-2',
          tenantId: 'tenant-1',
          transfusionRequestId: 'req-2',
          bloodUnitId: 'unit-2',
          patientId: 'patient-2',
          recordedBy: 'nurse-1',
          startedAt: at(11),
          status: TransfusionStatus.started,
          createdAt: at(11),
          updatedAt: at(11),
        ),
      );

      final List<Transfusion> forPatient = await repository
          .transfusionsForPatient('patient-1');
      expect(forPatient.map((Transfusion t) => t.id), <String>['tr-1']);
    });
  });

  group('failure mapping', () {
    test('a closed database surfaces as a persistence error', () async {
      store.closed = true;
      expect(repository.allBloodUnits, throwsA(isA<PersistenceError>()));
    });
  });
}
