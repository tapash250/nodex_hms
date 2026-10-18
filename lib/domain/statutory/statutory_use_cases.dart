/// Statutory Records & Birth/Death Registry use cases (Module 34).
library;

import 'package:meta/meta.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/statutory/statutory.dart';
import 'package:nodex_hms/domain/statutory/statutory_repository.dart';

/// Raises a draft birth registration.
final class RaiseBirthUseCase {
  /// Creates the use case.
  RaiseBirthUseCase({required this._repository});

  final StatutoryRepository _repository;

  Future<String> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String facilityId,
    required String childName,
    required StatutorySex sex,
    required DateTime birthAt,
    required String placeOfBirth,
    required String motherName,
    required String createdBy,
    DeliveryType deliveryType = DeliveryType.normal,
    BirthPlurality plurality = BirthPlurality.singleton,
    int? weightGrams,
    String? motherPatientId,
    String? fatherName,
    String? informantName,
    String? attendedBy,
    String birthId = '',
  }) async {
    policy.require(NodexPermissions.statutoryRegister);
    return _repository.registerBirth(
      BirthRecord.registerRow(
        tenantId: tenantId,
        facilityId: facilityId,
        childName: childName,
        sex: sex,
        birthAt: birthAt,
        placeOfBirth: placeOfBirth,
        motherName: motherName,
        createdBy: createdBy,
        deliveryType: deliveryType,
        plurality: plurality,
        weightGrams: weightGrams,
        motherPatientId: motherPatientId,
        fatherName: fatherName,
        informantName: informantName,
        attendedBy: attendedBy,
        birthId: birthId,
      ),
    );
  }
}

/// Enters a draft birth in the register.
final class RegisterBirthUseCase {
  /// Creates the use case.
  RegisterBirthUseCase({required this._repository});

  final StatutoryRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required BirthRecord record,
    required String registrationNumber,
    DateTime? at,
  }) async {
    policy.require(NodexPermissions.statutoryRegister);
    if (!birthCanTransition(record.status, BirthStatus.registered)) {
      throw AuthorizationError(
        message: record.status.isTerminal
            ? 'This birth registration is closed.'
            : 'That birth is already registered.',
        code: 'birth_record_transition_invalid',
      );
    }
    await _requireFreeNumber(
      record.tenantId,
      registrationNumber,
      exceptId: record.id,
    );
    await _repository.updateBirth(
      record.id,
      birthRegisterChanges(registrationNumber: registrationNumber, at: at),
    );
  }

  /// A register number identifies one entry: two entries sharing one is one
  /// entry with two claims on it.
  Future<void> _requireFreeNumber(
    String tenantId,
    String registrationNumber, {
    required String exceptId,
  }) async {
    final List<BirthRecord> births = await _repository.listBirths(tenantId);
    for (final BirthRecord other in births) {
      if (other.registrationNumber == registrationNumber.trim() &&
          other.id != exceptId) {
        throw const ValidationError(
          message: 'Birth registration failed validation.',
          fieldErrors: <String, String>{
            'registration_number': 'That register number is already used.',
          },
          code: 'birth_registration_number_duplicate',
        );
      }
    }
  }
}

/// Issues a birth certificate against a registered entry.
final class CertifyBirthUseCase {
  /// Creates the use case.
  CertifyBirthUseCase({required this._repository});

  final StatutoryRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required BirthRecord record,
    required String certificateNumber,
    required String certifiedBy,
    DateTime? at,
  }) async {
    policy.require(NodexPermissions.statutoryCertify);
    if (!birthCanTransition(record.status, BirthStatus.certified)) {
      throw AuthorizationError(
        message: record.status.isTerminal
            ? 'This birth registration is closed.'
            : 'A birth is certified once it is registered.',
        code: 'birth_record_transition_invalid',
      );
    }
    await _repository.updateBirth(
      record.id,
      birthCertifyChanges(
        certificateNumber: certificateNumber,
        certifiedBy: certifiedBy,
        at: at,
      ),
    );
  }
}

/// Raises a draft death registration.
final class RaiseDeathUseCase {
  /// Creates the use case.
  RaiseDeathUseCase({required this._repository});

  final StatutoryRepository _repository;

  Future<String> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String facilityId,
    required String deceasedName,
    required StatutorySex sex,
    required DateTime deathAt,
    required String placeOfDeath,
    required String createdBy,
    String? patientId,
    int? ageYears,
    String? causeOfDeathText,
    String? icd10Code,
    MannerOfDeath? mannerOfDeath,
    bool isMedicoLegal = false,
    String? certifyingClinician,
    String? informantName,
    String? informantRelationship,
    String deathId = '',
  }) async {
    policy.require(NodexPermissions.statutoryRegister);
    return _repository.registerDeath(
      DeathRecord.registerRow(
        tenantId: tenantId,
        facilityId: facilityId,
        deceasedName: deceasedName,
        sex: sex,
        deathAt: deathAt,
        placeOfDeath: placeOfDeath,
        createdBy: createdBy,
        patientId: patientId,
        ageYears: ageYears,
        causeOfDeathText: causeOfDeathText,
        icd10Code: icd10Code,
        mannerOfDeath: mannerOfDeath,
        isMedicoLegal: isMedicoLegal,
        certifyingClinician: certifyingClinician,
        informantName: informantName,
        informantRelationship: informantRelationship,
        deathId: deathId,
      ),
    );
  }
}

/// Records or corrects the cause-of-death coding on a draft death registration.
///
/// The cause of death is coded while the entry is a draft, and registration then
/// freezes it: after that a correction is an amendment, because the coded cause
/// is what an inquest and a mortality review turn on.
final class RecordDeathCodingUseCase {
  /// Creates the use case.
  RecordDeathCodingUseCase({required this._repository});

  final StatutoryRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required DeathRecord record,
    required String causeOfDeathText,
    required String icd10Code,
    required MannerOfDeath mannerOfDeath,
    bool? isMedicoLegal,
    String? certifyingClinician,
  }) async {
    policy.require(NodexPermissions.statutoryRegister);
    if (!record.isDraft) {
      throw AuthorizationError(
        message: record.status.isTerminal
            ? 'This death registration is closed.'
            : 'A registered death is coded by amendment, not by edit.',
        code: 'death_record_coding_immutable',
      );
    }
    await _repository.updateDeath(
      record.id,
      deathCodingChanges(
        causeOfDeathText: causeOfDeathText,
        icd10Code: icd10Code,
        mannerOfDeath: mannerOfDeath,
        isMedicoLegal: isMedicoLegal,
        certifyingClinician: certifyingClinician,
      ),
    );
  }
}

/// Enters a draft death in the register.
final class RegisterDeathUseCase {
  /// Creates the use case.
  RegisterDeathUseCase({required this._repository});

  final StatutoryRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required DeathRecord record,
    required String registrationNumber,
    DateTime? at,
  }) async {
    policy.require(NodexPermissions.statutoryRegister);
    if (!deathCanTransition(record.status, DeathStatus.registered)) {
      throw AuthorizationError(
        message: record.status.isTerminal
            ? 'This death registration is closed.'
            : 'That death is already registered.',
        code: 'death_record_transition_invalid',
      );
    }
    if (!record.isCoded) {
      throw const ValidationError(
        message: 'Death registration failed validation.',
        fieldErrors: <String, String>{
          'icd10_code':
              'A death is registered with its cause coded: record the cause, '
              'the ICD-10 code and the manner of death first.',
        },
        code: 'death_coding_missing',
      );
    }
    await _requireFreeNumber(
      record.tenantId,
      registrationNumber,
      exceptId: record.id,
    );
    await _repository.updateDeath(
      record.id,
      deathRegisterChanges(registrationNumber: registrationNumber, at: at),
    );
  }

  Future<void> _requireFreeNumber(
    String tenantId,
    String registrationNumber, {
    required String exceptId,
  }) async {
    final List<DeathRecord> deaths = await _repository.listDeaths(tenantId);
    for (final DeathRecord other in deaths) {
      if (other.registrationNumber == registrationNumber.trim() &&
          other.id != exceptId) {
        throw const ValidationError(
          message: 'Death registration failed validation.',
          fieldErrors: <String, String>{
            'registration_number': 'That register number is already used.',
          },
          code: 'death_registration_number_duplicate',
        );
      }
    }
  }
}

/// Issues a death certificate against a registered entry.
final class CertifyDeathUseCase {
  /// Creates the use case.
  CertifyDeathUseCase({required this._repository});

  final StatutoryRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required DeathRecord record,
    required String certificateNumber,
    required String certifiedBy,
    DateTime? at,
  }) async {
    policy.require(NodexPermissions.statutoryCertify);
    if (!deathCanTransition(record.status, DeathStatus.certified)) {
      throw AuthorizationError(
        message: record.status.isTerminal
            ? 'This death registration is closed.'
            : 'A death is certified once it is registered.',
        code: 'death_record_transition_invalid',
      );
    }
    await _repository.updateDeath(
      record.id,
      deathCertifyChanges(
        certificateNumber: certificateNumber,
        certifiedBy: certifiedBy,
        at: at,
      ),
    );
  }
}

/// Logs a medico-legal case.
final class RaiseMlcIntimationUseCase {
  /// Creates the use case.
  RaiseMlcIntimationUseCase({required this._repository});

  final StatutoryRepository _repository;

  Future<String> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String facilityId,
    required String caseNumber,
    required String subjectName,
    required MlcCaseType caseType,
    required String createdBy,
    String? patientId,
    DateTime? incidentAt,
    DateTime? reportedAt,
    String? reportingClinician,
    String mlcId = '',
  }) async {
    policy.require(NodexPermissions.statutoryRegister);
    await _requireFreeNumber(tenantId, caseNumber, exceptId: mlcId);
    return _repository.registerMlcIntimation(
      MlcIntimation.registerRow(
        tenantId: tenantId,
        facilityId: facilityId,
        caseNumber: caseNumber,
        subjectName: subjectName,
        caseType: caseType,
        createdBy: createdBy,
        patientId: patientId,
        incidentAt: incidentAt,
        reportedAt: reportedAt,
        reportingClinician: reportingClinician,
        mlcId: mlcId,
      ),
    );
  }

  /// One case number per incident: two hospital files for one incident split the
  /// record the police rely on.
  Future<void> _requireFreeNumber(
    String tenantId,
    String caseNumber, {
    required String exceptId,
  }) async {
    final List<MlcIntimation> cases = await _repository.listMlcIntimations(
      tenantId,
    );
    for (final MlcIntimation other in cases) {
      if (other.caseNumber == caseNumber.trim() && other.id != exceptId) {
        throw const ValidationError(
          message: 'Medico-legal case failed validation.',
          fieldErrors: <String, String>{
            'case_number': 'That case number is already logged.',
          },
          code: 'mlc_case_number_duplicate',
        );
      }
    }
  }
}

/// Records that the police have been told about a case.
final class IntimatePoliceUseCase {
  /// Creates the use case.
  IntimatePoliceUseCase({required this._repository});

  final StatutoryRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required MlcIntimation record,
    required String policeStation,
    String? policeOfficerName,
    String? policeContact,
    DateTime? at,
  }) async {
    policy.require(NodexPermissions.statutoryRegister);
    if (!mlcCanTransition(record.status, MlcStatus.intimated)) {
      throw AuthorizationError(
        message: record.status.isTerminal
            ? 'This case is closed.'
            : 'The police have already been told about this case.',
        code: 'mlc_transition_invalid',
      );
    }
    await _repository.updateMlcIntimation(
      record.id,
      mlcIntimateChanges(
        policeStation: policeStation,
        policeOfficerName: policeOfficerName,
        policeContact: policeContact,
        at: at,
      ),
    );
  }
}

/// Records the police acknowledgement and their reference.
final class AcknowledgeMlcUseCase {
  /// Creates the use case.
  AcknowledgeMlcUseCase({required this._repository});

  final StatutoryRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required MlcIntimation record,
    required String policeReference,
    DateTime? at,
  }) async {
    policy.require(NodexPermissions.statutoryRegister);
    if (!mlcCanTransition(record.status, MlcStatus.acknowledged)) {
      throw AuthorizationError(
        message: record.status.isTerminal
            ? 'This case is closed.'
            : 'The police acknowledge a case they have been told about.',
        code: 'mlc_transition_invalid',
      );
    }
    await _repository.updateMlcIntimation(
      record.id,
      mlcAcknowledgeChanges(policeReference: policeReference, at: at),
    );
  }
}

/// Closes an acknowledged case.
final class CloseMlcUseCase {
  /// Creates the use case.
  CloseMlcUseCase({required this._repository});

  final StatutoryRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required MlcIntimation record,
    required String reason,
    DateTime? at,
  }) async {
    policy.require(NodexPermissions.statutoryRegister);
    if (!mlcCanTransition(record.status, MlcStatus.closed)) {
      throw AuthorizationError(
        message: record.status.isTerminal
            ? 'This case is closed.'
            : 'A case is closed once the police have acknowledged it.',
        code: 'mlc_transition_invalid',
      );
    }
    await _repository.updateMlcIntimation(
      record.id,
      mlcCloseChanges(reason: reason, at: at),
    );
  }
}

/// Withdraws a live statutory record.
///
/// One use case for the three registers, because the rule is the same and the
/// caller has already loaded the row: a register entry that should never have
/// been made is withdrawn with a reason, never deleted.
final class VoidStatutoryRecordUseCase {
  /// Creates the use case.
  VoidStatutoryRecordUseCase({required this._repository});

  final StatutoryRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required StatutoryRecordRef record,
    required String reason,
  }) async {
    policy.require(NodexPermissions.statutoryAmend);
    if (!record.canVoid) {
      throw AuthorizationError(
        message:
            'A ${record.kind.label.toLowerCase()} record that is '
            '${record.status.replaceAll('_', ' ')} is closed, not withdrawn.',
        code: 'statutory_record_transition_invalid',
      );
    }
    switch (record.kind) {
      case StatutoryRegistryKind.birth:
        await _repository.updateBirth(
          record.id,
          birthVoidChanges(reason: reason),
        );
      case StatutoryRegistryKind.death:
        await _repository.updateDeath(
          record.id,
          deathVoidChanges(reason: reason),
        );
      case StatutoryRegistryKind.mlc:
        await _repository.updateMlcIntimation(
          record.id,
          mlcVoidChanges(reason: reason),
        );
    }
  }
}

/// Appends a correction to a registered statutory fact.
///
/// This is the only mechanism by which a registered fact changes: the register
/// row itself is frozen, and the amendment names the field, the previous value,
/// the new value and why. Nothing is overwritten, so the history stays legible.
final class AppendStatutoryAmendmentUseCase {
  /// Creates the use case.
  AppendStatutoryAmendmentUseCase({required this._repository});

  final StatutoryRepository _repository;

  Future<String> call({
    required AuthorizationPolicy policy,
    required StatutoryRecordRef record,
    required String subjectField,
    required String newValue,
    required String reason,
    required String amendedBy,
    String? previousValue,
    String? tenantId,
    DateTime? at,
    String amendmentId = '',
  }) async {
    policy.require(NodexPermissions.statutoryAmend);
    final String tenant = tenantId ?? '';
    if (tenant.isEmpty) {
      throw const ValidationError(
        message: 'Statutory amendment failed validation.',
        fieldErrors: <String, String>{'tenant_id': 'Tenant is required.'},
        code: 'statutory_amendment_invalid',
      );
    }
    return _repository.registerAmendment(
      StatutoryAmendment.registerRow(
        tenantId: tenant,
        record: record,
        subjectField: subjectField,
        newValue: newValue,
        reason: reason,
        amendedBy: amendedBy,
        previousValue: previousValue,
        at: at,
        amendmentId: amendmentId,
      ),
    );
  }
}

/// The statutory register as the board shows it.
@immutable
final class StatutoryBoard {
  /// Creates a board snapshot.
  const StatutoryBoard({
    required this.births,
    required this.deaths,
    required this.intimations,
    required this.asOf,
  });

  /// Birth registrations, live entries first.
  final List<BirthRecord> births;

  /// Death registrations, live entries first.
  final List<DeathRecord> deaths;

  /// Medico-legal cases, live cases first.
  final List<MlcIntimation> intimations;

  /// The instant the derived flags were computed at.
  final DateTime asOf;

  /// Whether a birth registration is past its statutory window.
  bool birthOverdue(BirthRecord record) => isStatutoryRegistrationOverdue(
    occurredAt: record.birthAt,
    registeredAt: record.registrationAt,
    now: asOf,
    limit: birthRegistrationWindow,
  );

  /// Whether a death registration is past its statutory window.
  bool deathOverdue(DeathRecord record) => isStatutoryRegistrationOverdue(
    occurredAt: record.deathAt,
    registeredAt: record.registrationAt,
    now: asOf,
    limit: deathRegistrationWindow,
  );

  /// Whether a medico-legal case is past its intimation window.
  bool caseOverdue(MlcIntimation record) =>
      isMlcIntimationOverdue(record: record, now: asOf);

  /// Whether anything on the board needs attention.
  bool get hasOverdue =>
      births.any(birthOverdue) ||
      deaths.any(deathOverdue) ||
      intimations.any(caseOverdue);
}

/// Reads the statutory registers and the amendment log.
final class ReadStatutoryRegistryUseCase {
  /// Creates the use case.
  ReadStatutoryRegistryUseCase({required this._repository});

  final StatutoryRepository _repository;

  /// The birth register, newest event first.
  Future<List<BirthRecord>> births({
    required AuthorizationPolicy policy,
    required String tenantId,
    BirthStatus? status,
    bool includeClosed = true,
  }) async {
    policy.require(NodexPermissions.statutoryRead);
    final List<BirthRecord> births = await _repository.listBirths(
      tenantId,
      status: status?.wireValue,
    );
    return births
        .where((BirthRecord record) => includeClosed || !record.isTerminal)
        .toList(growable: false);
  }

  /// The death register, newest event first.
  Future<List<DeathRecord>> deaths({
    required AuthorizationPolicy policy,
    required String tenantId,
    DeathStatus? status,
    bool includeClosed = true,
  }) async {
    policy.require(NodexPermissions.statutoryRead);
    final List<DeathRecord> deaths = await _repository.listDeaths(
      tenantId,
      status: status?.wireValue,
    );
    return deaths
        .where((DeathRecord record) => includeClosed || !record.isTerminal)
        .toList(growable: false);
  }

  /// The medico-legal case log, newest report first.
  Future<List<MlcIntimation>> intimations({
    required AuthorizationPolicy policy,
    required String tenantId,
    MlcStatus? status,
    bool includeClosed = true,
  }) async {
    policy.require(NodexPermissions.statutoryRead);
    final List<MlcIntimation> cases = await _repository.listMlcIntimations(
      tenantId,
      status: status?.wireValue,
    );
    return cases
        .where((MlcIntimation record) => includeClosed || record.isLive)
        .toList(growable: false);
  }

  /// The amendment log for one register row, or the whole tenant.
  Future<List<StatutoryAmendment>> amendments({
    required AuthorizationPolicy policy,
    required String tenantId,
    StatutoryRegistryKind? kind,
    String? recordId,
  }) async {
    policy.require(NodexPermissions.statutoryRead);
    return _repository.listAmendments(tenantId, kind: kind, recordId: recordId);
  }

  /// The statutory board: the three registers with their derived overdue flags,
  /// most needing attention first.
  Future<StatutoryBoard> board({
    required AuthorizationPolicy policy,
    required String tenantId,
    DateTime? now,
  }) async {
    policy.require(NodexPermissions.statutoryRead);
    final DateTime asOf = (now ?? DateTime.now().toUtc()).toUtc();
    final List<BirthRecord> births = await _repository.listBirths(tenantId);
    final List<DeathRecord> deaths = await _repository.listDeaths(tenantId);
    final List<MlcIntimation> cases = await _repository.listMlcIntimations(
      tenantId,
    );
    births.sort((BirthRecord a, BirthRecord b) {
      final int rank = _rank(a.isTerminal) - _rank(b.isTerminal);
      return rank != 0 ? rank : b.birthAt.compareTo(a.birthAt);
    });
    deaths.sort((DeathRecord a, DeathRecord b) {
      final int rank = _rank(a.isTerminal) - _rank(b.isTerminal);
      return rank != 0 ? rank : b.deathAt.compareTo(a.deathAt);
    });
    cases.sort((MlcIntimation a, MlcIntimation b) {
      final int rank = _rank(a.isTerminal) - _rank(b.isTerminal);
      return rank != 0 ? rank : b.reportedAt.compareTo(a.reportedAt);
    });
    return StatutoryBoard(
      births: births,
      deaths: deaths,
      intimations: cases,
      asOf: asOf,
    );
  }

  static int _rank(bool isTerminal) => isTerminal ? 1 : 0;
}
