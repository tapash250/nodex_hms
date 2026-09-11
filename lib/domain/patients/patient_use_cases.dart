/// Master Patient Index use cases (Module 10).
///
/// Commands go through use cases; reads go straight from controller to
/// repository. Every command gates on the session authorization policy *before*
/// touching local state, so an unauthorized action never reaches the upload
/// queue and never appears to have succeeded.
library;

import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/domain/patients/patient.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';

/// Registers a new patient from validated form input.
///
/// Fast-fails on a locally known duplicate MRN. The server enforces
/// (tenant_id, mrn) uniqueness finally: another device may hold an
/// unreplicated registration for the same MRN, in which case the upload is
/// rejected and the rejection surfaces in sync diagnostics.
final class RegisterPatientUseCase {
  /// Creates the use case.
  RegisterPatientUseCase({required this._repository, required this._logger});

  static const String _module = 'mpi.register';

  final PatientRepository _repository;
  final NodexLogger _logger;

  /// Executes registration, returning the new patient id.
  Future<String> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String userId,
    required String mrn,
    required String firstName,
    required String lastName,
    required DateTime dateOfBirth,
    required PatientGender gender,
    String? nationalIdHash,
    BloodGroup? bloodGroup,
    String? phoneNumber,
  }) async {
    policy.require(NodexPermissions.patientWrite);

    final Map<String, Object?> row = Patient.registrationRow(
      tenantId: tenantId,
      mrn: mrn,
      firstName: firstName,
      lastName: lastName,
      dateOfBirth: dateOfBirth,
      gender: gender,
      nationalIdHash: nationalIdHash,
      bloodGroup: bloodGroup,
      phoneNumber: phoneNumber,
      createdBy: userId,
    );

    if (await _repository.mrnExists(
      tenantId: tenantId,
      mrn: row['mrn']! as String,
    )) {
      _logger.warning(
        _module,
        'Registration blocked: MRN already registered locally.',
        operation: 'patient.register',
        outcome: 'rejected',
        errorCode: 'duplicate_mrn_local',
      );
      throw const ValidationError(
        message: 'This medical record number is already registered.',
        fieldErrors: <String, String>{
          'mrn': 'Enter a different MRN or search for the existing record.',
        },
        code: 'duplicate_mrn',
      );
    }

    return _repository.insertPatient(row);
  }
}

/// Updates mergeable contact details on an existing patient.
///
/// Identity fields are rejected here by [Patient.contactUpdateRow]: names, MRN,
/// date of birth and gender change through the merge workflow, never through a
/// direct edit.
final class UpdatePatientContactUseCase {
  /// Creates the use case.
  UpdatePatientContactUseCase({required this._repository});

  final PatientRepository _repository;

  /// Executes the contact update.
  Future<void> call({
    required AuthorizationPolicy policy,
    required String patientId,
    required Map<String, Object?> changes,
  }) async {
    policy.require(NodexPermissions.patientWrite);

    if (changes.isEmpty) {
      return;
    }
    final Map<String, Object?> row = Patient.contactUpdateRow(changes);
    await _repository.updatePatientContact(patientId, row);
  }
}

/// Records a new allergy report on a patient.
final class RecordAllergyUseCase {
  /// Creates the use case.
  RecordAllergyUseCase({required this._repository});

  final PatientRepository _repository;

  /// Executes the allergy report, returning the new allergy id.
  Future<String> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String patientId,
    required String substance,
    required AllergySeverity severity,
    String? reaction,
    String? recordedBy,
  }) async {
    policy.require(NodexPermissions.patientWrite);

    final Map<String, Object?> row = PatientAllergy.reportRow(
      tenantId: tenantId,
      patientId: patientId,
      substance: substance,
      severity: severity,
      reaction: reaction,
      recordedBy: recordedBy,
    );
    return _repository.insertAllergy(row);
  }
}

/// Retires an allergy record with a reason.
///
/// Retirement is the only mutation permitted on an allergy row, enforced again
/// server-side by `nodex.tg_allergy_retire_only`. A wrong substance is never
/// edited: retire with a reason and record a replacement.
final class RetireAllergyUseCase {
  /// Creates the use case.
  RetireAllergyUseCase({required this._repository});

  final PatientRepository _repository;

  /// Executes the retirement.
  Future<void> call({
    required AuthorizationPolicy policy,
    required String allergyId,
    required String reason,
  }) async {
    policy.require(NodexPermissions.patientWrite);
    await _repository.retireAllergy(allergyId: allergyId, reason: reason);
  }
}

/// Records a master-merge decision between two duplicate patient records.
///
/// The surviving record stays active; the absorbed record is deactivated (never
/// deleted) and the decision lands in the append-only merge history with
/// per-field winners. Field-level content merging of the surviving record is a
/// follow-up edit through [UpdatePatientContactUseCase], keeping the merge
/// decision itself a single auditable act.
final class MergePatientsUseCase {
  /// Creates the use case.
  MergePatientsUseCase({required this._repository});

  final PatientRepository _repository;

  /// Executes the merge, returning nothing on success.
  Future<void> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String survivingPatientId,
    required String mergedPatientId,
    required String reason,
    required Map<String, Object?> fieldChoices,
    required String mergedBy,
  }) async {
    policy.require(NodexPermissions.patientWrite);

    if (survivingPatientId == mergedPatientId) {
      throw const ValidationError(
        message: 'A patient record cannot be merged with itself.',
        code: 'merge_same_patient',
      );
    }

    await _repository.recordMerge(
      tenantId: tenantId,
      survivingPatientId: survivingPatientId,
      mergedPatientId: mergedPatientId,
      reason: reason,
      fieldChoices: fieldChoices,
      mergedBy: mergedBy,
    );
    await _repository.deactivatePatient(mergedPatientId);
  }
}
