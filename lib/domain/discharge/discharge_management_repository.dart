/// Discharge management repository (Module 23).
///
/// Separate from the discharge record's own repository so the Phase 2
/// aggregate keeps its narrow contract: these are the readiness artifacts that
/// sit alongside it and gate its authorization.
library;

import 'package:nodex_hms/core/errors/error_mapper.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/discharge/discharge_management.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';

/// Read and write access to the discharge readiness artifacts.
abstract interface class DischargeManagementRepository {
  /// The clearance for a discharge, or null.
  Future<DischargeClearance?> clearanceForDischarge(String dischargeId);

  /// Inserts or updates a clearance row.
  Future<DischargeClearance> upsertClearance(DischargeClearance clearance);

  /// The reconciliation for a discharge, or null.
  Future<DischargeMedicationReconciliation?> reconciliationForDischarge(
    String dischargeId,
  );

  /// Inserts or updates a reconciliation row.
  Future<DischargeMedicationReconciliation> upsertReconciliation(
    DischargeMedicationReconciliation reconciliation,
  );

  /// Medication decisions recorded against a reconciliation, oldest first.
  Future<List<DischargeMedicationReconciliationItem>> itemsForReconciliation(
    String reconciliationId,
  );

  /// Inserts or updates a reconciliation item row.
  Future<DischargeMedicationReconciliationItem> upsertReconciliationItem(
    DischargeMedicationReconciliationItem item,
  );

  /// The settlement for a discharge, or null.
  Future<DischargeSettlement?> settlementForDischarge(String dischargeId);

  /// Inserts or updates a settlement row.
  Future<DischargeSettlement> upsertSettlement(DischargeSettlement settlement);

  /// The AI summary for a discharge, or null.
  Future<DischargeAiSummary?> aiSummaryForDischarge(String dischargeId);

  /// Inserts or updates an AI summary row.
  Future<DischargeAiSummary> upsertAiSummary(DischargeAiSummary summary);
}

/// Default repository over the encrypted local projection.
final class DefaultDischargeManagementRepository
    implements DischargeManagementRepository {
  /// Creates a repository over a local store.
  DefaultDischargeManagementRepository({
    required this._store,
    required this._logger,
  });

  static const String _module = 'domain.discharge.management';

  final PatientLocalStore _store;
  final NodexLogger _logger;

  @override
  Future<DischargeClearance?> clearanceForDischarge(String dischargeId) async {
    try {
      final List<Map<String, Object?>> rows = await _query(
        LocalTables.dischargeClearances,
        'where discharge_id = ?',
        <Object?>[dischargeId],
      );
      if (rows.isEmpty) return null;
      return DischargeClearance.fromRow(rows.first);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'discharge.clearanceForDischarge');
    }
  }

  @override
  Future<DischargeClearance> upsertClearance(
    DischargeClearance clearance,
  ) async {
    await _upsert(
      table: LocalTables.dischargeClearances,
      id: clearance.id,
      tenantId: clearance.tenantId,
      createdAt: clearance.createdAt,
      changes: <String, Object?>{
        'discharge_id': clearance.dischargeId,
        'reviewed_by': clearance.reviewedBy,
        'status': clearance.status.wireValue,
        'outstanding_items': clearance.outstandingItems,
        'notes': clearance.notes,
        'cleared_by': clearance.clearedBy,
        'cleared_at': clearance.clearedAt,
        'updated_at': clearance.updatedAt,
      },
      operation: 'discharge.upsertClearance',
    );
    return clearance;
  }

  @override
  Future<DischargeMedicationReconciliation?> reconciliationForDischarge(
    String dischargeId,
  ) async {
    try {
      final List<Map<String, Object?>> rows = await _query(
        LocalTables.dischargeReconciliations,
        'where discharge_id = ?',
        <Object?>[dischargeId],
      );
      if (rows.isEmpty) return null;
      return DischargeMedicationReconciliation.fromRow(rows.first);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'discharge.reconciliationForDischarge');
    }
  }

  @override
  Future<DischargeMedicationReconciliation> upsertReconciliation(
    DischargeMedicationReconciliation reconciliation,
  ) async {
    await _upsert(
      table: LocalTables.dischargeReconciliations,
      id: reconciliation.id,
      tenantId: reconciliation.tenantId,
      createdAt: reconciliation.createdAt,
      changes: <String, Object?>{
        'discharge_id': reconciliation.dischargeId,
        'status': reconciliation.status.wireValue,
        'medications_reviewed': reconciliation.medicationsReviewed,
        'discrepancies_found': reconciliation.discrepanciesFound,
        'reviewed_by': reconciliation.reviewedBy,
        'reviewed_at': reconciliation.reviewedAt,
        'notes': reconciliation.notes,
        'updated_at': reconciliation.updatedAt,
      },
      operation: 'discharge.upsertReconciliation',
    );
    return reconciliation;
  }

  @override
  Future<List<DischargeMedicationReconciliationItem>> itemsForReconciliation(
    String reconciliationId,
  ) async {
    try {
      final List<Map<String, Object?>> rows = await _query(
        LocalTables.dischargeReconciliationItems,
        'where reconciliation_id = ? order by recorded_at asc',
        <Object?>[reconciliationId],
      );
      return rows
          .map(DischargeMedicationReconciliationItem.fromRow)
          .toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'discharge.itemsForReconciliation');
    }
  }

  @override
  Future<DischargeMedicationReconciliationItem> upsertReconciliationItem(
    DischargeMedicationReconciliationItem item,
  ) async {
    await _upsert(
      table: LocalTables.dischargeReconciliationItems,
      id: item.id,
      tenantId: item.tenantId,
      createdAt: item.createdAt,
      changes: <String, Object?>{
        'reconciliation_id': item.reconciliationId,
        'medication_name': item.medicationName,
        'action': item.action.wireValue,
        'discrepancy': item.discrepancy ? 1 : 0,
        'detail': item.detail,
        'recorded_by': item.recordedBy,
        'recorded_at': item.recordedAt,
        'updated_at': item.updatedAt,
      },
      operation: 'discharge.upsertReconciliationItem',
    );
    return item;
  }

  @override
  Future<DischargeSettlement?> settlementForDischarge(
    String dischargeId,
  ) async {
    try {
      final List<Map<String, Object?>> rows = await _query(
        LocalTables.dischargeSettlements,
        'where discharge_id = ?',
        <Object?>[dischargeId],
      );
      if (rows.isEmpty) return null;
      return DischargeSettlement.fromRow(rows.first);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'discharge.settlementForDischarge');
    }
  }

  @override
  Future<DischargeSettlement> upsertSettlement(
    DischargeSettlement settlement,
  ) async {
    await _upsert(
      table: LocalTables.dischargeSettlements,
      id: settlement.id,
      tenantId: settlement.tenantId,
      createdAt: settlement.createdAt,
      changes: <String, Object?>{
        'discharge_id': settlement.dischargeId,
        'invoice_id': settlement.invoiceId,
        'amount_minor': settlement.amountMinor,
        'settled_by': settlement.settledBy,
        'settled_at': settlement.settledAt,
        'updated_at': settlement.updatedAt,
      },
      operation: 'discharge.upsertSettlement',
    );
    return settlement;
  }

  @override
  Future<DischargeAiSummary?> aiSummaryForDischarge(String dischargeId) async {
    try {
      final List<Map<String, Object?>> rows = await _query(
        LocalTables.dischargeAiSummaries,
        'where discharge_id = ?',
        <Object?>[dischargeId],
      );
      if (rows.isEmpty) return null;
      return DischargeAiSummary.fromRow(rows.first);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'discharge.aiSummaryForDischarge');
    }
  }

  @override
  Future<DischargeAiSummary> upsertAiSummary(DischargeAiSummary summary) async {
    await _upsert(
      table: LocalTables.dischargeAiSummaries,
      id: summary.id,
      tenantId: summary.tenantId,
      createdAt: summary.createdAt,
      changes: <String, Object?>{
        'discharge_id': summary.dischargeId,
        'model_id': summary.modelId,
        'summary_text': summary.summaryText,
        'status': summary.status.wireValue,
        'safety_decision': summary.safetyDecision,
        'requested_by': summary.requestedBy,
        'reviewed_by': summary.reviewedBy,
        'reviewed_at': summary.reviewedAt,
        'rejection_reason': summary.rejectionReason,
        'updated_at': summary.updatedAt,
      },
      operation: 'discharge.upsertAiSummary',
    );
    return summary;
  }

  Future<List<Map<String, Object?>>> _query(
    String table,
    String clause,
    List<Object?> parameters,
  ) => _store.query('select * from $table $clause', parameters);

  Future<void> _upsert({
    required String table,
    required String id,
    required String tenantId,
    required DateTime createdAt,
    required Map<String, Object?> changes,
    required String operation,
  }) async {
    try {
      final Map<String, Object?>? existing = await _store.getById(table, id);
      if (existing == null) {
        await _store.insert(table, <String, Object?>{
          ...changes,
          'id': id,
          'tenant_id': tenantId,
          'created_at': createdAt,
        });
      } else {
        await _store.update(table, id, changes);
      }
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, operation);
    }
  }

  Never _mapped(Object error, StackTrace stackTrace, String operation) {
    if (error is NodexError) throw error;
    final NodexError mapped = NodexErrorMapper.map(error, operation: operation);
    _logger.error(
      _module,
      'Discharge management repository failure.',
      operation: operation,
      outcome: 'failed',
      errorCode: mapped.code,
      stackTrace: stackTrace,
    );
    throw mapped;
  }
}
