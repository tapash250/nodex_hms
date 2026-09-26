/// Blood bank use cases (Module 26).
///
/// Each write gates on the authorization policy before touching the
/// repository.
library;

import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/blood_bank/blood_bank.dart';
import 'package:nodex_hms/domain/blood_bank/blood_bank_repository.dart';
import 'package:uuid/uuid.dart';

/// Registers a collected blood unit. Requires `blood_unit.write`.
final class CreateBloodUnitUseCase {
  CreateBloodUnitUseCase({required this._repository});

  final BloodBankRepository _repository;

  Future<BloodUnit> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String unitNumber,
    required BloodGroup bloodGroup,
    required BloodComponent component,
    required String createdBy,
    required DateTime expiresAt,
    DateTime? collectedAt,
    int? volumeMl,
    String? locationId,
  }) async {
    policy.require(NodexPermissions.bloodUnitWrite);
    if (unitNumber.trim().isEmpty) {
      throw const ValidationError(
        message: 'A blood unit needs a unit number.',
        code: 'blood_unit_number_required',
      );
    }
    final DateTime now = DateTime.now().toUtc();
    final DateTime collected = collectedAt ?? now;
    if (!expiresAt.isAfter(collected)) {
      throw const ValidationError(
        message: 'A blood unit must expire after collection.',
        code: 'blood_unit_expiry_invalid',
      );
    }
    if (volumeMl != null && volumeMl < 1) {
      throw const ValidationError(
        message: 'Collected volume must be positive.',
        code: 'blood_unit_volume_invalid',
      );
    }
    final BloodUnit unit = BloodUnit(
      id: const Uuid().v4(),
      tenantId: tenantId,
      unitNumber: unitNumber.trim(),
      bloodGroup: bloodGroup,
      component: component,
      volumeMl: volumeMl,
      collectedAt: collected,
      expiresAt: expiresAt,
      status: BloodUnitStatus.available,
      locationId: locationId,
      createdBy: createdBy,
      createdAt: now,
      updatedAt: now,
    );
    return _repository.upsertBloodUnit(unit);
  }
}

/// Raises a transfusion request. Requires `transfusion.request`.
final class RequestTransfusionUseCase {
  RequestTransfusionUseCase({required this._repository});

  final BloodBankRepository _repository;

  Future<TransfusionRequest> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String patientId,
    required String requestedBy,
    required BloodGroup requestedBloodGroup,
    required BloodComponent component,
    required int unitsRequested,
    String? encounterId,
    String? indication,
    TransfusionUrgency urgency = TransfusionUrgency.routine,
  }) async {
    policy.require(NodexPermissions.transfusionRequest);
    if (unitsRequested < 1) {
      throw const ValidationError(
        message: 'A transfusion request needs at least one unit.',
        code: 'transfusion_request_units_invalid',
      );
    }
    if (indication != null && indication.trim().isEmpty) {
      throw const ValidationError(
        message: 'Indication must be descriptive when supplied.',
        code: 'transfusion_request_indication_invalid',
      );
    }
    final DateTime now = DateTime.now().toUtc();
    final TransfusionRequest request = TransfusionRequest(
      id: const Uuid().v4(),
      tenantId: tenantId,
      patientId: patientId,
      encounterId: encounterId,
      requestedBy: requestedBy,
      requestedBloodGroup: requestedBloodGroup,
      component: component,
      unitsRequested: unitsRequested,
      indication: indication?.trim(),
      urgency: urgency,
      status: TransfusionRequestStatus.pending,
      crossmatchResult: CrossmatchResult.pending,
      requestedAt: now,
      createdAt: now,
      updatedAt: now,
    );
    return _repository.upsertRequest(request);
  }
}

/// Records a crossmatch result. Requires `blood_unit.write`.
final class RecordCrossmatchUseCase {
  RecordCrossmatchUseCase({required this._repository});

  final BloodBankRepository _repository;

  Future<TransfusionRequest> call({
    required AuthorizationPolicy policy,
    required TransfusionRequest original,
    required CrossmatchResult crossmatchResult,
  }) async {
    policy.require(NodexPermissions.bloodUnitWrite);
    if (original.isTerminal) {
      throw const AuthorizationError(
        message: 'Closed transfusion requests cannot receive a crossmatch.',
        code: 'transfusion_request_closed',
      );
    }
    final DateTime now = DateTime.now().toUtc();
    final bool advance =
        crossmatchResult.isCompatible &&
        original.status == TransfusionRequestStatus.pending;
    final TransfusionRequest updated = TransfusionRequest(
      id: original.id,
      tenantId: original.tenantId,
      patientId: original.patientId,
      encounterId: original.encounterId,
      requestedBy: original.requestedBy,
      requestedBloodGroup: original.requestedBloodGroup,
      component: original.component,
      unitsRequested: original.unitsRequested,
      indication: original.indication,
      urgency: original.urgency,
      status: advance ? TransfusionRequestStatus.crossmatched : original.status,
      crossmatchResult: crossmatchResult,
      requestedAt: original.requestedAt,
      approvedBy: original.approvedBy,
      approvedAt: original.approvedAt,
      createdAt: original.createdAt,
      updatedAt: now,
    );
    return _repository.upsertRequest(updated);
  }
}

/// Approves a transfusion request. Requires `transfusion.request` and
/// `transfusion.finalize`.
final class ApproveTransfusionRequestUseCase {
  ApproveTransfusionRequestUseCase({required this._repository});

  final BloodBankRepository _repository;

  Future<TransfusionRequest> call({
    required AuthorizationPolicy policy,
    required TransfusionRequest original,
    required String approvedBy,
  }) async {
    policy.require(NodexPermissions.transfusionRequest);
    policy.require(NodexPermissions.transfusionFinalize);
    if (original.isTerminal) {
      throw const AuthorizationError(
        message: 'Closed transfusion requests cannot be approved.',
        code: 'transfusion_request_closed',
      );
    }
    final DateTime now = DateTime.now().toUtc();
    final TransfusionRequest updated = TransfusionRequest(
      id: original.id,
      tenantId: original.tenantId,
      patientId: original.patientId,
      encounterId: original.encounterId,
      requestedBy: original.requestedBy,
      requestedBloodGroup: original.requestedBloodGroup,
      component: original.component,
      unitsRequested: original.unitsRequested,
      indication: original.indication,
      urgency: original.urgency,
      status: TransfusionRequestStatus.approved,
      crossmatchResult: original.crossmatchResult,
      requestedAt: original.requestedAt,
      approvedBy: approvedBy,
      approvedAt: now,
      createdAt: original.createdAt,
      updatedAt: now,
    );
    return _repository.upsertRequest(updated);
  }
}

/// Reserves an available unit for a patient. Requires `blood_unit.write`.
final class ReserveBloodUnitUseCase {
  ReserveBloodUnitUseCase({required this._repository});

  final BloodBankRepository _repository;

  Future<BloodUnit> call({
    required AuthorizationPolicy policy,
    required BloodUnit original,
    required String patientId,
    String? transfusionRequestId,
  }) async {
    policy.require(NodexPermissions.bloodUnitWrite);
    if (original.status != BloodUnitStatus.available) {
      throw const AuthorizationError(
        message: 'Only available blood units accept reservations.',
        code: 'blood_unit_not_available',
      );
    }
    final DateTime now = DateTime.now().toUtc();
    final BloodUnit updated = BloodUnit(
      id: original.id,
      tenantId: original.tenantId,
      unitNumber: original.unitNumber,
      bloodGroup: original.bloodGroup,
      component: original.component,
      volumeMl: original.volumeMl,
      collectedAt: original.collectedAt,
      expiresAt: original.expiresAt,
      status: BloodUnitStatus.reserved,
      locationId: original.locationId,
      patientId: patientId,
      transfusionRequestId:
          transfusionRequestId ?? original.transfusionRequestId,
      createdBy: original.createdBy,
      createdAt: original.createdAt,
      updatedAt: now,
    );
    return _repository.upsertBloodUnit(updated);
  }
}

/// Issues a reserved unit against an approved request. Requires
/// `blood_unit.write`.
final class IssueBloodUnitUseCase {
  IssueBloodUnitUseCase({required this._repository});

  final BloodBankRepository _repository;

  Future<BloodUnit> call({
    required AuthorizationPolicy policy,
    required BloodUnit original,
  }) async {
    policy.require(NodexPermissions.bloodUnitWrite);
    if (original.status != BloodUnitStatus.reserved) {
      throw const AuthorizationError(
        message: 'Only reserved blood units can be issued.',
        code: 'blood_unit_not_reserved',
      );
    }
    final String? requestId = original.transfusionRequestId;
    if (requestId == null) {
      throw const AuthorizationError(
        message: 'Issue requires a transfusion request.',
        code: 'blood_unit_issue_requires_request',
      );
    }
    final TransfusionRequest? request = await _repository.requestById(
      requestId,
    );
    if (request == null) {
      throw const PersistenceError(
        message: 'The transfusion request is not on this device.',
        code: 'transfusion_request_not_found_locally',
      );
    }
    if (request.status != TransfusionRequestStatus.approved) {
      throw const AuthorizationError(
        message: 'The transfusion request must be approved before issue.',
        code: 'transfusion_request_not_approved',
      );
    }
    final DateTime now = DateTime.now().toUtc();
    final BloodUnit updated = BloodUnit(
      id: original.id,
      tenantId: original.tenantId,
      unitNumber: original.unitNumber,
      bloodGroup: original.bloodGroup,
      component: original.component,
      volumeMl: original.volumeMl,
      collectedAt: original.collectedAt,
      expiresAt: original.expiresAt,
      status: BloodUnitStatus.issued,
      locationId: original.locationId,
      patientId: original.patientId,
      transfusionRequestId: original.transfusionRequestId,
      createdBy: original.createdBy,
      createdAt: original.createdAt,
      updatedAt: now,
    );
    return _repository.upsertBloodUnit(updated);
  }
}

/// Starts a transfusion against an issued unit. Requires
/// `transfusion.administer`.
final class RecordTransfusionUseCase {
  RecordTransfusionUseCase({required this._repository});

  final BloodBankRepository _repository;

  Future<Transfusion> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String transfusionRequestId,
    required String bloodUnitId,
    required String patientId,
    required String recordedBy,
    DateTime? startedAt,
  }) async {
    policy.require(NodexPermissions.transfusionAdminister);
    final DateTime now = DateTime.now().toUtc();
    final Transfusion transfusion = Transfusion(
      id: const Uuid().v4(),
      tenantId: tenantId,
      transfusionRequestId: transfusionRequestId,
      bloodUnitId: bloodUnitId,
      patientId: patientId,
      recordedBy: recordedBy,
      startedAt: startedAt ?? now,
      status: TransfusionStatus.started,
      createdAt: now,
      updatedAt: now,
    );
    return _repository.upsertTransfusion(transfusion);
  }
}

/// Records the outcome of a started transfusion. Requires
/// `transfusion.administer`.
final class RecordTransfusionOutcomeUseCase {
  RecordTransfusionOutcomeUseCase({required this._repository});

  final BloodBankRepository _repository;

  Future<Transfusion> call({
    required AuthorizationPolicy policy,
    required Transfusion original,
    required TransfusionStatus status,
    int? volumeMl,
    String? reactionNotes,
    DateTime? finishedAt,
  }) async {
    policy.require(NodexPermissions.transfusionAdminister);
    if (original.isComplete) {
      throw const AuthorizationError(
        message: 'This transfusion has already been closed.',
        code: 'transfusion_already_closed',
      );
    }
    if (status == TransfusionStatus.started) {
      throw const ValidationError(
        message: 'Choose a completion outcome for the transfusion.',
        code: 'transfusion_outcome_required',
      );
    }
    if (volumeMl != null && volumeMl < 1) {
      throw const ValidationError(
        message: 'Transfused volume must be positive.',
        code: 'transfusion_volume_invalid',
      );
    }
    if (reactionNotes != null && reactionNotes.trim().isEmpty) {
      throw const ValidationError(
        message: 'Reaction notes cannot be blank.',
        code: 'transfusion_reaction_notes_invalid',
      );
    }
    final String? notes = reactionNotes ?? original.reactionNotes;
    if (status == TransfusionStatus.reaction &&
        (notes == null || notes.trim().isEmpty)) {
      throw const ValidationError(
        message: 'A transfusion reaction requires notes.',
        code: 'transfusion_reaction_notes_required',
      );
    }
    final DateTime now = DateTime.now().toUtc();
    final Transfusion updated = Transfusion(
      id: original.id,
      tenantId: original.tenantId,
      transfusionRequestId: original.transfusionRequestId,
      bloodUnitId: original.bloodUnitId,
      patientId: original.patientId,
      recordedBy: original.recordedBy,
      startedAt: original.startedAt,
      finishedAt: finishedAt ?? now,
      status: status,
      volumeMl: volumeMl ?? original.volumeMl,
      reactionNotes: notes,
      createdAt: original.createdAt,
      updatedAt: now,
    );
    return _repository.upsertTransfusion(updated);
  }
}

/// Discards a collected unit. Requires `blood_unit.write`.
final class DiscardBloodUnitUseCase {
  DiscardBloodUnitUseCase({required this._repository});

  final BloodBankRepository _repository;

  Future<BloodUnit> call({
    required AuthorizationPolicy policy,
    required BloodUnit original,
  }) async {
    policy.require(NodexPermissions.bloodUnitWrite);
    if (original.isTerminal) {
      throw const AuthorizationError(
        message: 'Discarded or expired units cannot change.',
        code: 'blood_unit_terminal',
      );
    }
    final DateTime now = DateTime.now().toUtc();
    final BloodUnit updated = BloodUnit(
      id: original.id,
      tenantId: original.tenantId,
      unitNumber: original.unitNumber,
      bloodGroup: original.bloodGroup,
      component: original.component,
      volumeMl: original.volumeMl,
      collectedAt: original.collectedAt,
      expiresAt: original.expiresAt,
      status: BloodUnitStatus.discarded,
      locationId: original.locationId,
      patientId: original.patientId,
      transfusionRequestId: original.transfusionRequestId,
      createdBy: original.createdBy,
      createdAt: original.createdAt,
      updatedAt: now,
    );
    return _repository.upsertBloodUnit(updated);
  }
}

/// Completes an approved transfusion request. Requires
/// `transfusion.request`.
final class CompleteTransfusionRequestUseCase {
  CompleteTransfusionRequestUseCase({required this._repository});

  final BloodBankRepository _repository;

  Future<TransfusionRequest> call({
    required AuthorizationPolicy policy,
    required TransfusionRequest original,
  }) async {
    policy.require(NodexPermissions.transfusionRequest);
    if (original.status != TransfusionRequestStatus.approved) {
      throw const AuthorizationError(
        message: 'The transfusion request must be approved first.',
        code: 'transfusion_request_not_approved',
      );
    }
    final DateTime now = DateTime.now().toUtc();
    final TransfusionRequest updated = TransfusionRequest(
      id: original.id,
      tenantId: original.tenantId,
      patientId: original.patientId,
      encounterId: original.encounterId,
      requestedBy: original.requestedBy,
      requestedBloodGroup: original.requestedBloodGroup,
      component: original.component,
      unitsRequested: original.unitsRequested,
      indication: original.indication,
      urgency: original.urgency,
      status: TransfusionRequestStatus.completed,
      crossmatchResult: original.crossmatchResult,
      requestedAt: original.requestedAt,
      approvedBy: original.approvedBy,
      approvedAt: original.approvedAt,
      createdAt: original.createdAt,
      updatedAt: now,
    );
    return _repository.upsertRequest(updated);
  }
}
