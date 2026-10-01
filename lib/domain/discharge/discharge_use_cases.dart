/// Discharge finalization use cases (Module 23).
library;

import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/discharge/discharge.dart';
import 'package:nodex_hms/domain/discharge/discharge_management.dart';
import 'package:nodex_hms/domain/discharge/discharge_management_repository.dart';
import 'package:nodex_hms/domain/discharge/discharge_repository.dart';

/// Drafts a discharge for an encounter. Drafting rides on encounter.write;
/// finalizing is a separate high-risk authorization.
final class DraftDischargeUseCase {
  /// Creates the use case.
  DraftDischargeUseCase({required this._repository});

  final DischargeRepository _repository;

  /// Drafts the record, refusing an encounter that already has one.
  Future<String> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String patientId,
    required String encounterId,
    required String createdBy,
    required String dischargeCode,
    required DischargeType dischargeType,
    String? summary,
    String? followUpPlan,
  }) async {
    policy.require(NodexPermissions.encounterWrite);
    final Discharge? existing = await _repository.getByEncounter(encounterId);
    if (existing != null) {
      throw const AuthorizationError(
        message: 'This encounter already has a discharge record.',
        code: 'discharge_exists',
      );
    }
    return _repository.createDischarge(
      Discharge.draftRow(
        tenantId: tenantId,
        patientId: patientId,
        encounterId: encounterId,
        createdBy: createdBy,
        dischargeCode: dischargeCode,
        dischargeType: dischargeType,
        summary: summary,
        followUpPlan: followUpPlan,
      ),
    );
  }
}

/// Finalizes a draft, authorizing the episode record.
///
/// Finalizing is the point at which the patient actually leaves, so the
/// discharge-management artifacts must be in place first: clinical clearance
/// granted, medication reconciliation complete, and the episode invoice
/// settled. An AI summary is deliberately not required — it is documentation,
/// whereas those three are what make going home safe.
final class FinalizeDischargeUseCase {
  /// Creates the use case.
  FinalizeDischargeUseCase({
    required this._repository,
    required this._managementRepository,
  });

  final DischargeRepository _repository;
  final DischargeManagementRepository? _managementRepository;

  /// Finalizes [discharge], refusing anything but a cleared, reconciled and
  /// settled draft.
  Future<void> call({
    required AuthorizationPolicy policy,
    required Discharge discharge,
    required String finalizerId,
  }) async {
    policy.require(NodexPermissions.dischargeFinalize);
    if (!discharge.status.isEditable) {
      throw const AuthorizationError(
        message: 'Only a draft discharge can be finalized.',
        code: 'discharge_not_draft',
      );
    }
    final DischargeManagementRepository? management = _managementRepository;
    if (management != null) {
      final DischargeClearance? clearance = await management
          .clearanceForDischarge(discharge.id);
      if (clearance == null || !clearance.isCleared) {
        throw const AuthorizationError(
          message: 'Grant clinical clearance before finalizing the discharge.',
          code: 'discharge_clearance_required',
        );
      }
      final DischargeMedicationReconciliation? reconciliation = await management
          .reconciliationForDischarge(discharge.id);
      if (reconciliation == null || !reconciliation.isReconciled) {
        throw const AuthorizationError(
          message:
              'Complete medication reconciliation before finalizing the '
              'discharge.',
          code: 'discharge_reconciliation_required',
        );
      }
      final DischargeSettlement? settlement = await management
          .settlementForDischarge(discharge.id);
      if (settlement == null) {
        throw const AuthorizationError(
          message: 'Settle the episode invoice before finalizing.',
          code: 'discharge_settlement_required',
        );
      }
    }
    await _repository.updateDischarge(
      discharge.id,
      Discharge.finalizeChanges(finalizerId: finalizerId),
    );
  }
}

/// Cancels a mistaken draft.
final class CancelDischargeUseCase {
  /// Creates the use case.
  CancelDischargeUseCase({required this._repository});

  final DischargeRepository _repository;

  /// Cancels [discharge] with [reason], refusing closed records.
  Future<void> call({
    required AuthorizationPolicy policy,
    required Discharge discharge,
    required String reason,
  }) async {
    policy.require(NodexPermissions.encounterWrite);
    if (!discharge.status.isEditable) {
      throw const AuthorizationError(
        message: 'Only a draft discharge can be cancelled.',
        code: 'discharge_not_draft',
      );
    }
    await _repository.updateDischarge(
      discharge.id,
      Discharge.cancelChanges(reason: reason),
    );
  }
}
