/// Clinical encounter use cases (Module 16).
///
/// Commands go through use cases; reads go straight from controller to
/// repository. Every command gates on the session authorization policy *before*
/// touching local state. Signing additionally requires the signer to be the
/// attending physician or a holder of explicit sign authority — accountability
/// for a signed note is personal and non-transferable.
library;

import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/encounters/encounter.dart';
import 'package:nodex_hms/domain/encounters/encounter_repository.dart';

/// Opens a new encounter draft for a patient.
final class StartEncounterUseCase {
  /// Creates the use case.
  StartEncounterUseCase({required this._repository});

  final EncounterRepository _repository;

  /// Executes, returning the new encounter id.
  Future<String> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String patientId,
    required String attendingPhysicianId,
    required EncounterType encounterType,
    required String createdBy,
  }) async {
    policy.require(NodexPermissions.encounterWrite);

    return _repository.createEncounter(
      ClinicalEncounter.draftRow(
        tenantId: tenantId,
        patientId: patientId,
        attendingPhysicianId: attendingPhysicianId,
        encounterType: encounterType,
        createdBy: createdBy,
      ),
    );
  }
}

/// Saves SOAP content to an unsigned encounter.
///
/// Refuses signed encounters before reaching the repository: the server trigger
/// would reject the write, but failing fast keeps the rejection legible and
/// avoids a doomed upload rotting in the queue.
final class SaveEncounterDraftUseCase {
  /// Creates the use case.
  SaveEncounterDraftUseCase({required this._repository});

  final EncounterRepository _repository;

  /// Executes the save.
  Future<void> call({
    required AuthorizationPolicy policy,
    required ClinicalEncounter encounter,
    String? subjectiveNote,
    String? objectiveFindings,
    String? assessment,
    String? planDescription,
    List<EncounterDiagnosis>? diagnoses,
  }) async {
    policy.require(NodexPermissions.encounterWrite);

    if (!encounter.isEditable) {
      throw const AuthorizationError(
        message: 'This encounter is signed and frozen. Record an amendment instead of editing it.',
        code: 'encounter_signed_frozen',
      );
    }

    await _repository.updateEncounter(
      encounter.id,
      ClinicalEncounter.editChanges(
        subjectiveNote: subjectiveNote,
        objectiveFindings: objectiveFindings,
        assessment: assessment,
        planDescription: planDescription,
        diagnoses: diagnoses,
      ),
    );
  }
}

/// Signs and freezes an encounter.
///
/// The signer must be the attending physician recorded on the encounter. This
/// is the one place in the module where identity is checked against content,
/// not just against a role: a signature is a personal attestation.
///
/// The encounter is re-read before signing so the checks run against current
/// state, not a stale screen copy: a signature over stale text would freeze
/// the wrong words, and a double-tap must not sign twice.
final class SignEncounterUseCase {
  /// Creates the use case.
  SignEncounterUseCase({required this._repository});

  final EncounterRepository _repository;

  /// Executes the signature.
  Future<void> call({
    required AuthorizationPolicy policy,
    required String encounterId,
    required String signerUserId,
  }) async {
    policy.require(NodexPermissions.encounterWrite);

    final ClinicalEncounter? fresh = await _repository.getEncounter(
      encounterId,
    );
    if (fresh == null) {
      throw const PersistenceError(
        message:
            'This encounter is not in the local projection. It may not have '
            'replicated to this device yet.',
        code: 'encounter_not_found_locally',
      );
    }
    if (!fresh.isEditable) {
      throw const AuthorizationError(
        message: 'This encounter is already signed.',
        code: 'encounter_already_signed',
      );
    }
    if (fresh.attendingPhysicianId != signerUserId) {
      throw const AuthorizationError(
        message: 'Only the attending clinician recorded on this encounter may sign it.',
        code: 'encounter_signer_mismatch',
      );
    }

    await _repository.signEncounter(fresh.id);
  }
}

/// Records an amendment against a signed encounter.
///
/// Requires the encounter to be signed: amending an unsigned encounter is a
/// plain edit, and routing it through amendments would hide draft content in
/// the correction history.
final class AmendEncounterUseCase {
  /// Creates the use case.
  AmendEncounterUseCase({required this._repository});

  final EncounterRepository _repository;

  /// Executes the amendment, returning the amendment id.
  Future<String> call({
    required AuthorizationPolicy policy,
    required ClinicalEncounter encounter,
    required String reason,
    required Map<String, Object?> fieldChanges,
    required String amendedBy,
    String amendmentType = 'correction',
  }) async {
    policy.require(NodexPermissions.encounterWrite);

    if (!encounter.isSigned) {
      throw const AuthorizationError(
        message: 'This encounter is not signed yet. Edit it directly instead of amending it.',
        code: 'encounter_not_signed',
      );
    }

    return _repository.amendEncounter(
      encounterId: encounter.id,
      amendmentRow: EncounterAmendment.amendmentRow(
        tenantId: encounter.tenantId,
        encounterId: encounter.id,
        reason: reason,
        amendedBy: amendedBy,
        fieldChanges: fieldChanges,
        amendmentType: amendmentType,
      ),
    );
  }
}
