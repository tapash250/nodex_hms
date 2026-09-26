/// Radiology repository tests over the local projection (Module 18).
///
/// The repository is the only path the presentation layer has to the imaging
/// tables, so round trips must preserve every column the entities decode and
/// the read scopes (by order, patient, and study identifier) must filter
/// correctly.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';
import 'package:nodex_hms/domain/radiology/radiology.dart';
import 'package:nodex_hms/domain/radiology/radiology_repository.dart';

/// In-memory stand-in for the PowerSync-backed patient store.
final class FakeRadiologyStore implements PatientLocalStore {
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
    if (sql.contains(LocalTables.imagingOrders)) {
      final Iterable<Map<String, Object?>> rows = _table(
        LocalTables.imagingOrders,
      ).values;
      if (sql.contains('where patient_id = ?')) {
        return _by(rows, 'patient_id', parameters[0]! as String);
      }
      return rows.toList(growable: false);
    }
    if (sql.contains(LocalTables.imagingStudies)) {
      final Iterable<Map<String, Object?>> rows = _table(
        LocalTables.imagingStudies,
      ).values;
      if (sql.contains('where imaging_order_id = ?')) {
        return _by(rows, 'imaging_order_id', parameters[0]! as String);
      }
      if (sql.contains('where study_uid = ?')) {
        return _by(rows, 'study_uid', parameters[0]! as String);
      }
      throw UnimplementedError('FakeRadiologyStore cannot run: $sql');
    }
    if (sql.contains(LocalTables.imagingReports)) {
      final Iterable<Map<String, Object?>> rows = _table(
        LocalTables.imagingReports,
      ).values;
      if (sql.contains('where imaging_order_id = ?')) {
        return _by(rows, 'imaging_order_id', parameters[0]! as String);
      }
      throw UnimplementedError('FakeRadiologyStore cannot run: $sql');
    }
    throw UnimplementedError('FakeRadiologyStore cannot run: $sql');
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
  late FakeRadiologyStore store;
  late DefaultRadiologyRepository repository;

  setUp(() {
    store = FakeRadiologyStore();
    repository = DefaultRadiologyRepository(
      store: store,
      logger: NodexLogger(
        sinks: <NodexLogSink>[InMemoryLogSink()],
        minimumLevel: NodexLogLevel.trace,
      ),
    );
  });

  DateTime at() => DateTime.utc(2026, 9, 20, 9);

  ImagingOrder order({
    String id = 'order-1',
    String patientId = 'patient-1',
    ImagingOrderStatus status = ImagingOrderStatus.ordered,
  }) => ImagingOrder(
    id: id,
    tenantId: 'tenant-1',
    patientId: patientId,
    orderedBy: 'doctor-1',
    orderCode: 'IMG-00$id',
    modality: ImagingModality.xray,
    bodyRegion: 'Chest',
    priority: ImagingPriority.routine,
    status: status,
    orderedAt: at(),
    createdAt: at(),
    updatedAt: at(),
  );

  ImagingStudy study({String orderId = 'order-1', String uid = '1.2.3'}) =>
      ImagingStudy(
        id: 'study-$orderId',
        tenantId: 'tenant-1',
        imagingOrderId: orderId,
        studyUid: uid,
        modality: ImagingModality.xray,
        bodyRegion: 'Chest',
        performedBy: 'tech-1',
        performedAt: at(),
        createdAt: at(),
        updatedAt: at(),
      );

  ImagingReport report({String orderId = 'order-1'}) => ImagingReport(
    id: 'report-$orderId',
    tenantId: 'tenant-1',
    imagingOrderId: orderId,
    studyId: 'study-$orderId',
    findings: 'Clear lungs.',
    impression: 'Normal.',
    status: ImagingReportStatus.draft,
    enteredBy: 'doctor-1',
    enteredAt: at(),
    createdAt: at(),
    updatedAt: at(),
  );

  group('orders', () {
    test('missing orders read as null', () async {
      expect(await repository.orderById('absent'), isNull);
    });

    test('upsert inserts then updates in place', () async {
      await repository.upsertOrder(order());
      final ImagingOrder? created = await repository.orderById('order-1');
      expect(created, isNotNull);
      expect(created!.status, ImagingOrderStatus.ordered);

      await repository.upsertOrder(order(status: ImagingOrderStatus.completed));
      final ImagingOrder? updated = await repository.orderById('order-1');
      expect(updated!.status, ImagingOrderStatus.completed);
      expect(store.tables[LocalTables.imagingOrders]!.length, 1);
    });

    test('patient scope filters orders', () async {
      await repository.upsertOrder(order(id: 'order-1'));
      await repository.upsertOrder(
        order(id: 'order-2', patientId: 'patient-2'),
      );

      expect(
        (await repository.ordersForPatient('patient-1'))
            .map((ImagingOrder o) => o.id),
        <String>['order-1'],
      );
      expect((await repository.allOrders()).length, 2);
    });
  });

  group('studies and reports', () {
    test('missing records read as null', () async {
      expect(await repository.studyForOrder('absent'), isNull);
      expect(await repository.studyByUid('absent'), isNull);
      expect(await repository.reportForOrder('absent'), isNull);
    });

    test('study round-trips by order and by uid', () async {
      await repository.upsertOrder(order());
      await repository.upsertStudy(study(uid: '1.2.840.1'));

      final ImagingStudy? loaded = await repository.studyForOrder('order-1');
      expect(loaded!.studyUid, '1.2.840.1');
      expect(loaded.modality, ImagingModality.xray);
      expect((await repository.studyByUid('1.2.840.1'))!.id, loaded.id);
      expect(await repository.studyByUid('9.9.9'), isNull);
    });

    test('report round-trips findings and status', () async {
      await repository.upsertOrder(order());
      await repository.upsertReport(report());

      final ImagingReport? loaded = await repository.reportForOrder('order-1');
      expect(loaded!.findings, 'Clear lungs.');
      expect(loaded.status, ImagingReportStatus.draft);
      expect(loaded.isDraft, isTrue);
      expect(await repository.reportForOrder('order-2'), isNull);
    });
  });

  group('failure mapping', () {
    test('a closed database surfaces as a persistence error', () async {
      store.closed = true;
      expect(repository.allOrders, throwsA(isA<PersistenceError>()));
    });
  });
}
