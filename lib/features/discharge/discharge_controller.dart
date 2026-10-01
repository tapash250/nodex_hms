/// Discharge presentation providers (Module 23).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/discharge/discharge.dart';
import 'package:nodex_hms/domain/discharge/discharge_management.dart';
import 'package:nodex_hms/domain/discharge/discharge_management_repository.dart';

/// Discharges for one patient, newest first.
final dischargesForPatientProvider = FutureProvider.autoDispose
    .family<List<Discharge>, String>((Ref ref, String patientId) async {
      return ref.watch(dischargeRepositoryProvider).listForPatient(patientId);
    });

/// One discharge by id.
final dischargeDetailProvider = FutureProvider.autoDispose
    .family<Discharge, String>((Ref ref, String dischargeId) async {
      final Discharge? discharge = await ref
          .watch(dischargeRepositoryProvider)
          .getDischarge(dischargeId);
      if (discharge == null) {
        throw const PersistenceError(
          message: 'This discharge is not available on this device.',
          code: 'discharge_not_found_locally',
        );
      }
      return discharge;
    });

/// The readiness artifacts for one discharge, read together.
///
/// Bundled so the ward sees the whole picture in one read: which gate is
/// missing, and what has already been recorded against it.
final class DischargeReadinessBundle {
  /// Creates a bundle.
  const DischargeReadinessBundle({
    required this.readiness,
    this.clearance,
    this.reconciliation,
    this.items = const <DischargeMedicationReconciliationItem>[],
    this.settlement,
    this.aiSummary,
  });

  /// What still stands between the draft and its authorization.
  final DischargeReadiness readiness;

  /// Clinical clearance, when a review has been recorded.
  final DischargeClearance? clearance;

  /// Medication reconciliation, when one has been started.
  final DischargeMedicationReconciliation? reconciliation;

  /// Medication decisions recorded so far.
  final List<DischargeMedicationReconciliationItem> items;

  /// Episode settlement, when the invoice has been settled.
  final DischargeSettlement? settlement;

  /// AI-generated summary, when one has been filed.
  final DischargeAiSummary? aiSummary;
}

/// Readiness artifacts for one discharge.
final dischargeReadinessProvider = FutureProvider.autoDispose
    .family<DischargeReadinessBundle, String>((
      Ref ref,
      String dischargeId,
    ) async {
      final DischargeManagementRepository repository = ref.watch(
        dischargeManagementRepositoryProvider,
      );
      final DischargeClearance? clearance = await repository
          .clearanceForDischarge(dischargeId);
      final DischargeMedicationReconciliation? reconciliation = await repository
          .reconciliationForDischarge(dischargeId);
      final List<DischargeMedicationReconciliationItem> items =
          reconciliation == null
          ? const <DischargeMedicationReconciliationItem>[]
          : await repository.itemsForReconciliation(reconciliation.id);
      final DischargeSettlement? settlement = await repository
          .settlementForDischarge(dischargeId);
      final DischargeAiSummary? summary = await repository
          .aiSummaryForDischarge(dischargeId);
      return DischargeReadinessBundle(
        readiness: DischargeReadiness(
          cleared: clearance?.isCleared ?? false,
          reconciled: reconciliation?.isReconciled ?? false,
          settled: settlement != null,
          outstandingClearanceItems: clearance?.outstandingItems ?? 0,
          pendingMedications: reconciliation?.isReconciled ?? false
              ? 0
              : items.length,
          aiSummaryReviewed: summary?.isAccepted ?? false,
        ),
        clearance: clearance,
        reconciliation: reconciliation,
        items: items,
        settlement: settlement,
        aiSummary: summary,
      );
    });
