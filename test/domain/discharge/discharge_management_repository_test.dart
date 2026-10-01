/// Discharge management repository tests over the local projection
/// (Module 23).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/discharge/discharge_management.dart';
import 'package:nodex_hms/domain/discharge/discharge_management_repository.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';

/// In-memory stand-in for the PowerSync-backed patient store.
final class FakeDischargeStore implements PatientLocalStore {
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
    for (final (String table, String column) in <(String, String)>[
      (LocalTables.dischargeClearances, 'discharge_id'),
      (LocalTables.dischargeReconciliations, 'discharge_id'),
      (LocalTables.dischargeReconciliationItems, 'reconciliation_id'),
      (LocalTables.dischargeSettlements, 'discharge_id'),
      (LocalTables.dischargeAiSummaries, 'discharge_id'),
    ]) {
      if (!sql.contains(table)) continue;
      return _table(table).values
          .where((Map<String, Object?> row) => row[column] == parameters[0])
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
    existing.addAll(changes);
  }
}

void main() {
  late FakeDischargeStore store;
  late DefaultDischargeManagementRepository repository;

  setUp(() {
    store = FakeDischargeStore();
    repository = DefaultDischargeManagementRepository(
      store: store,
      logger: NodexLogger(
        sinks: <NodexLogSink>[InMemoryLogSink()],
        minimumLevel: NodexLogLevel.trace,
      ),
    );
  });

  DischargeClearance clearance({
    String id = 'clearance-1',
    DischargeClearanceStatus status = DischargeClearanceStatus.pending,
    int outstandingItems = 0,
  }) => DischargeClearance(
    id: id,
    tenantId: 'tenant-1',
    dischargeId: 'discharge-1',
    reviewedBy: 'doctor-1',
    status: status,
    outstandingItems: outstandingItems,
    createdAt: DateTime.utc(2026, 9, 19),
    updatedAt: DateTime.utc(2026, 9, 19),
  );

  DischargeMedicationReconciliation reconciliation({
    String id = 'reconciliation-1',
    DischargeReconciliationStatus status =
        DischargeReconciliationStatus.pending,
  }) => DischargeMedicationReconciliation(
    id: id,
    tenantId: 'tenant-1',
    dischargeId: 'discharge-1',
    status: status,
    medicationsReviewed: status == DischargeReconciliationStatus.reconciled
        ? 2
        : 0,
    discrepanciesFound: status == DischargeReconciliationStatus.reconciled
        ? 1
        : 0,
    createdAt: DateTime.utc(2026, 9, 19),
    updatedAt: DateTime.utc(2026, 9, 19),
  );

  DischargeMedicationReconciliationItem item({
    String id = 'item-1',
    String reconciliationId = 'reconciliation-1',
    DischargeMedicationAction action = DischargeMedicationAction.stop,
  }) => DischargeMedicationReconciliationItem(
    id: id,
    tenantId: 'tenant-1',
    reconciliationId: reconciliationId,
    medicationName: 'Warfarin',
    action: action,
    discrepancy: action.isDiscrepancy,
    recordedBy: 'nurse-1',
    recordedAt: DateTime.utc(2026, 9, 20, 10),
    createdAt: DateTime.utc(2026, 9, 20, 10),
    updatedAt: DateTime.utc(2026, 9, 20, 10),
  );

  group('clearance', () {
    test('missing clearance reads null', () async {
      expect(await repository.clearanceForDischarge('absent'), isNull);
    });

    test('upsert inserts then updates in place', () async {
      await repository.upsertClearance(clearance(outstandingItems: 2));
      expect(
        (await repository.clearanceForDischarge('discharge-1'))!
            .outstandingItems,
        2,
      );

      await repository.upsertClearance(
        clearance(status: DischargeClearanceStatus.cleared),
      );
      expect(
        (await repository.clearanceForDischarge('discharge-1'))!.isCleared,
        isTrue,
      );
      expect(store.tables[LocalTables.dischargeClearances]!.length, 1);
    });
  });

  group('reconciliation', () {
    test('missing reconciliation reads null', () async {
      expect(await repository.reconciliationForDischarge('absent'), isNull);
    });

    test('reconciliation round-trips its counts', () async {
      await repository.upsertReconciliation(
        reconciliation(status: DischargeReconciliationStatus.reconciled),
      );

      final DischargeMedicationReconciliation? loaded = await repository
          .reconciliationForDischarge('discharge-1');
      expect(loaded!.medicationsReviewed, 2);
      expect(loaded.discrepanciesFound, 1);
      expect(loaded.isReconciled, isTrue);
    });

    test('items are scoped to their reconciliation', () async {
      await repository.upsertReconciliation(reconciliation());
      await repository.upsertReconciliation(
        reconciliation(id: 'reconciliation-2'),
      );
      await repository.upsertReconciliationItem(item());
      await repository.upsertReconciliationItem(
        item(id: 'item-2', reconciliationId: 'reconciliation-2'),
      );

      expect(
        (await repository.itemsForReconciliation('reconciliation-1')).single.id,
        'item-1',
      );
      expect(
        (await repository.itemsForReconciliation('reconciliation-2')).single.id,
        'item-2',
      );
      expect(
        await repository.itemsForReconciliation('reconciliation-3'),
        isEmpty,
      );
    });

    test('an item round-trips its discrepancy flag', () async {
      await repository.upsertReconciliation(reconciliation());
      await repository.upsertReconciliationItem(
        item(action: DischargeMedicationAction.continueMedication),
      );

      final loaded = await repository.itemsForReconciliation(
        'reconciliation-1',
      );
      expect(loaded.single.discrepancy, isFalse);
      expect(
        loaded.single.action,
        DischargeMedicationAction.continueMedication,
      );
    });
  });

  group('settlement', () {
    test('missing settlement reads null', () async {
      expect(await repository.settlementForDischarge('absent'), isNull);
    });

    test('settlement round-trips the amount', () async {
      await repository.upsertSettlement(
        DischargeSettlement(
          id: 'settlement-1',
          tenantId: 'tenant-1',
          dischargeId: 'discharge-1',
          invoiceId: 'invoice-1',
          amountMinor: 450000,
          settledBy: 'accounts-1',
          settledAt: DateTime.utc(2026, 9, 20, 13),
          createdAt: DateTime.utc(2026, 9, 20, 13),
          updatedAt: DateTime.utc(2026, 9, 20, 13),
        ),
      );

      final DischargeSettlement? loaded = await repository
          .settlementForDischarge('discharge-1');
      expect(loaded!.amountMinor, 450000);
      expect(loaded.invoiceId, 'invoice-1');
    });
  });

  group('AI summary', () {
    test('missing summary reads null', () async {
      expect(await repository.aiSummaryForDischarge('absent'), isNull);
    });

    test('summary round-trips model and review state', () async {
      await repository.upsertAiSummary(
        DischargeAiSummary(
          id: 'summary-1',
          tenantId: 'tenant-1',
          dischargeId: 'discharge-1',
          modelId: 'clinical-summarizer-v2',
          summaryText: 'Admitted with pneumonia.',
          status: DischargeAiSummaryStatus.accepted,
          safetyDecision: 'allow',
          requestedBy: 'doctor-1',
          reviewedBy: 'doctor-2',
          reviewedAt: DateTime.utc(2026, 9, 20, 15),
          createdAt: DateTime.utc(2026, 9, 20, 14),
          updatedAt: DateTime.utc(2026, 9, 20, 15),
        ),
      );

      final DischargeAiSummary? loaded = await repository.aiSummaryForDischarge(
        'discharge-1',
      );
      expect(loaded!.modelId, 'clinical-summarizer-v2');
      expect(loaded.isAccepted, isTrue);
      expect(loaded.reviewedBy, 'doctor-2');
    });
  });

  group('failure mapping', () {
    test('a closed database surfaces as a persistence error', () async {
      store.closed = true;
      expect(
        () => repository.clearanceForDischarge('discharge-1'),
        throwsA(isA<PersistenceError>()),
      );
    });
  });
}
