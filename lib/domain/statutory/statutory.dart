/// Statutory Records & Birth/Death Registry entities (Module 34).
///
/// Specification scope: "Birth and death certificate registries, cause-of-death
/// coding, and Medico-Legal Case (MLC) police intimations."
/// Audit invariant: "Append-only records. Modifications generate linked
/// amendment events; hard deletions are blocked by PostgreSQL RLS."
///
/// This is the register a hospital is legally obliged to keep: the birth and
/// death entries and the medico-legal intimation the law requires when a death
/// or injury is not natural. It is distinct from the clinical record (an
/// encounter holds the care; a birth registration is the fact the civil registry
/// is told) and from the document vault (a vault holds the artefacts a register
/// entry is issued against).
///
/// Four records, mirroring the scope: the [BirthRecord], the [DeathRecord] with
/// its cause-of-death coding, the [MlcIntimation], and the
/// [StatutoryAmendment] log that is the only way a registered fact changes.
/// Because a register row freezes the moment it is registered, an amendment is
/// a fact in its own right, never an edit.
///
/// Two facts are *derived* rather than stored, so they cannot drift: the
/// corrected value of a registered fact ([effectiveStatutoryValues], replayed
/// from the amendments) and whether a registration or an intimation is overdue
/// against its statutory window ([isStatutoryRegistrationOverdue],
/// [isMlcIntimationOverdue]).
// ignore_for_file: sort_constructors_first
library;

import 'package:meta/meta.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';

/// The sex recorded by a statutory register.
///
/// A register records what was observed and what the informant attested; it is
/// deliberately not the patient demographic model, because a birth has no
/// patient record yet and a death may be of a person never registered.
enum StatutorySex {
  /// Male.
  male('male'),

  /// Female.
  female('female'),

  /// Ambiguous, as recorded.
  ambiguous('ambiguous'),

  /// Not recorded.
  unknown('unknown');

  const StatutorySex(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    StatutorySex.male => 'Male',
    StatutorySex.female => 'Female',
    StatutorySex.ambiguous => 'Ambiguous',
    StatutorySex.unknown => 'Unknown',
  };

  /// Parses a stored value.
  static StatutorySex fromWire(String value) => StatutorySex.values.firstWhere(
    (StatutorySex value_) => value_.wireValue == value,
    orElse: () => StatutorySex.unknown,
  );
}

/// How a birth was delivered.
enum DeliveryType {
  /// Unassisted vertex delivery.
  normal('normal'),

  /// Instrumental delivery.
  assisted('assisted'),

  /// Caesarean section.
  cesarean('cesarean'),

  /// Breech presentation.
  breech('breech'),

  /// Anything else, recorded on the row.
  other('other');

  const DeliveryType(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    DeliveryType.normal => 'Normal',
    DeliveryType.assisted => 'Assisted',
    DeliveryType.cesarean => 'Caesarean',
    DeliveryType.breech => 'Breech',
    DeliveryType.other => 'Other',
  };

  /// Parses a stored value.
  static DeliveryType fromWire(String value) => DeliveryType.values.firstWhere(
    (DeliveryType value_) => value_.wireValue == value,
    orElse: () => DeliveryType.other,
  );
}

/// How many children a birth produced.
enum BirthPlurality {
  /// One child.
  singleton('singleton'),

  /// Two children.
  twin('twin'),

  /// Three children.
  triplet('triplet'),

  /// Four or more.
  higher('higher');

  const BirthPlurality(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    BirthPlurality.singleton => 'Singleton',
    BirthPlurality.twin => 'Twin',
    BirthPlurality.triplet => 'Triplet',
    BirthPlurality.higher => 'Higher order',
  };

  /// Parses a stored value.
  static BirthPlurality fromWire(String value) =>
      BirthPlurality.values.firstWhere(
        (BirthPlurality value_) => value_.wireValue == value,
        orElse: () => BirthPlurality.singleton,
      );
}

/// Lifecycle status of a birth registration.
enum BirthStatus {
  /// Being entered; editable.
  drafted('drafted'),

  /// Entered in the register; frozen, certificate pending.
  registered('registered'),

  /// Certificate issued; terminal.
  certified('certified'),

  /// Withdrawn before certification.
  voided('voided');

  const BirthStatus(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    BirthStatus.drafted => 'Drafted',
    BirthStatus.registered => 'Registered',
    BirthStatus.certified => 'Certified',
    BirthStatus.voided => 'Voided',
  };

  /// Parses a stored value.
  static BirthStatus fromWire(String value) => BirthStatus.values.firstWhere(
    (BirthStatus value_) => value_.wireValue == value,
    orElse: () => BirthStatus.drafted,
  );

  /// Whether the entry is still being entered.
  bool get isDraft => this == BirthStatus.drafted;

  /// Whether the entry is closed.
  bool get isTerminal =>
      this == BirthStatus.certified || this == BirthStatus.voided;
}

/// Whether a birth registration may move from [from] to [to].
///
/// One stage at a time, and only a live entry may be withdrawn. This is the same
/// rule the database enforces.
bool birthCanTransition(BirthStatus from, BirthStatus to) {
  if (from.isTerminal) {
    return false;
  }
  return switch (from) {
    BirthStatus.drafted =>
      to == BirthStatus.registered || to == BirthStatus.voided,
    BirthStatus.registered =>
      to == BirthStatus.certified || to == BirthStatus.voided,
    BirthStatus.certified || BirthStatus.voided => false,
  };
}

/// How a death is classified.
enum MannerOfDeath {
  /// Disease or natural process.
  natural('natural'),

  /// Unintentional injury.
  accident('accident'),

  /// Self-inflicted.
  suicide('suicide'),

  /// Inflicted by another.
  homicide('homicide'),

  /// The evidence does not settle it.
  undetermined('undetermined'),

  /// Awaits the inquest.
  pending('pending');

  const MannerOfDeath(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    MannerOfDeath.natural => 'Natural',
    MannerOfDeath.accident => 'Accident',
    MannerOfDeath.suicide => 'Suicide',
    MannerOfDeath.homicide => 'Homicide',
    MannerOfDeath.undetermined => 'Undetermined',
    MannerOfDeath.pending => 'Pending inquest',
  };

  /// Parses a stored value.
  static MannerOfDeath fromWire(String value) =>
      MannerOfDeath.values.firstWhere(
        (MannerOfDeath value_) => value_.wireValue == value,
        orElse: () => MannerOfDeath.undetermined,
      );
}

/// Lifecycle status of a death registration.
enum DeathStatus {
  /// Being entered; editable.
  drafted('drafted'),

  /// Entered in the register with its cause coded; frozen.
  registered('registered'),

  /// Certificate issued; terminal.
  certified('certified'),

  /// Withdrawn before certification.
  voided('voided');

  const DeathStatus(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    DeathStatus.drafted => 'Drafted',
    DeathStatus.registered => 'Registered',
    DeathStatus.certified => 'Certified',
    DeathStatus.voided => 'Voided',
  };

  /// Parses a stored value.
  static DeathStatus fromWire(String value) => DeathStatus.values.firstWhere(
    (DeathStatus value_) => value_.wireValue == value,
    orElse: () => DeathStatus.drafted,
  );

  /// Whether the entry is still being entered.
  bool get isDraft => this == DeathStatus.drafted;

  /// Whether the entry is closed.
  bool get isTerminal =>
      this == DeathStatus.certified || this == DeathStatus.voided;
}

/// Whether a death registration may move from [from] to [to].
bool deathCanTransition(DeathStatus from, DeathStatus to) {
  if (from.isTerminal) {
    return false;
  }
  return switch (from) {
    DeathStatus.drafted =>
      to == DeathStatus.registered || to == DeathStatus.voided,
    DeathStatus.registered =>
      to == DeathStatus.certified || to == DeathStatus.voided,
    DeathStatus.certified || DeathStatus.voided => false,
  };
}

/// The kind of police case a medico-legal intimation reports.
enum MlcCaseType {
  /// A road traffic accident.
  roadTrafficAccident('road_traffic_accident'),

  /// An assault.
  assault('assault'),

  /// A poisoning.
  poisoning('poisoning'),

  /// A burn.
  burn('burn'),

  /// A sexual assault.
  sexualAssault('sexual_assault'),

  /// A drowning.
  drowning('drowning'),

  /// A firearm injury.
  firearm('firearm'),

  /// A fall.
  fall('fall'),

  /// Anything else, recorded on the row.
  other('other');

  const MlcCaseType(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    MlcCaseType.roadTrafficAccident => 'Road traffic accident',
    MlcCaseType.assault => 'Assault',
    MlcCaseType.poisoning => 'Poisoning',
    MlcCaseType.burn => 'Burn',
    MlcCaseType.sexualAssault => 'Sexual assault',
    MlcCaseType.drowning => 'Drowning',
    MlcCaseType.firearm => 'Firearm',
    MlcCaseType.fall => 'Fall',
    MlcCaseType.other => 'Other',
  };

  /// Parses a stored value.
  static MlcCaseType fromWire(String value) => MlcCaseType.values.firstWhere(
    (MlcCaseType value_) => value_.wireValue == value,
    orElse: () => MlcCaseType.other,
  );
}

/// Lifecycle status of a medico-legal case.
enum MlcStatus {
  /// Logged by the hospital; editable.
  reported('reported'),

  /// The police have been told; frozen.
  intimated('intimated'),

  /// The police acknowledged, with their reference.
  acknowledged('acknowledged'),

  /// Closed with a reason; terminal.
  closed('closed'),

  /// Withdrawn while live.
  voided('voided');

  const MlcStatus(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    MlcStatus.reported => 'Reported',
    MlcStatus.intimated => 'Police intimated',
    MlcStatus.acknowledged => 'Acknowledged',
    MlcStatus.closed => 'Closed',
    MlcStatus.voided => 'Voided',
  };

  /// Parses a stored value.
  static MlcStatus fromWire(String value) => MlcStatus.values.firstWhere(
    (MlcStatus value_) => value_.wireValue == value,
    orElse: () => MlcStatus.reported,
  );

  /// Whether the case has still to be worked.
  bool get isLive =>
      this == MlcStatus.reported ||
      this == MlcStatus.intimated ||
      this == MlcStatus.acknowledged;

  /// Whether the case is closed.
  bool get isTerminal => !isLive;

  /// Whether the case is waiting on the police.
  bool get awaitsPolice =>
      this == MlcStatus.reported || this == MlcStatus.intimated;
}

/// Whether a medico-legal case may move from [from] to [to].
bool mlcCanTransition(MlcStatus from, MlcStatus to) {
  if (from.isTerminal) {
    return false;
  }
  return switch (from) {
    MlcStatus.reported => to == MlcStatus.intimated || to == MlcStatus.voided,
    MlcStatus.intimated =>
      to == MlcStatus.acknowledged || to == MlcStatus.voided,
    MlcStatus.acknowledged => to == MlcStatus.closed,
    MlcStatus.closed || MlcStatus.voided => false,
  };
}

/// Which register a statutory row belongs to.
enum StatutoryRegistryKind {
  /// The birth register.
  birth('birth'),

  /// The death register.
  death('death'),

  /// The medico-legal case log.
  mlc('mlc');

  const StatutoryRegistryKind(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    StatutoryRegistryKind.birth => 'Birth',
    StatutoryRegistryKind.death => 'Death',
    StatutoryRegistryKind.mlc => 'Medico-legal',
  };
}

/// A register row by identity, whichever register it belongs to.
///
/// A correction is appended against a row the caller has already loaded, so the
/// amendment path needs the kind, the id and the current status and nothing
/// else. This keeps one amendment use case honest instead of three near-copies.
@immutable
final class StatutoryRecordRef {
  /// Creates a reference.
  const StatutoryRecordRef({
    required this.kind,
    required this.id,
    required this.status,
  });

  /// Which register the row belongs to.
  final StatutoryRegistryKind kind;

  /// The row identifier.
  final String id;

  /// The row's current status, as stored.
  final String status;

  /// Whether the row may still be voided.
  bool get canVoid => switch (kind) {
    StatutoryRegistryKind.birth => birthCanTransition(
      BirthStatus.fromWire(status),
      BirthStatus.voided,
    ),
    StatutoryRegistryKind.death => deathCanTransition(
      DeathStatus.fromWire(status),
      DeathStatus.voided,
    ),
    StatutoryRegistryKind.mlc => mlcCanTransition(
      MlcStatus.fromWire(status),
      MlcStatus.voided,
    ),
  };
}

/// The statutory window within which a birth is registered.
///
/// Real jurisdictions differ; twenty-one days is the common civil-registration
/// window and is stated here as a default the board derives against rather than
/// a fact stored on every row, so changing it re-derives every overdue marker.
const Duration birthRegistrationWindow = Duration(days: 21);

/// The statutory window within which a death is registered.
const Duration deathRegistrationWindow = Duration(days: 7);

/// The window within which a medico-legal case must reach the police.
const Duration mlcIntimationWindow = Duration(hours: 24);

/// Whether [value] looks like an ICD-10 code (`A00` or `A00.0`).
bool isIcd10Code(String value) =>
    RegExp(r'^[A-Z][0-9]{2}(\.[0-9A-Z]{1,4})?$').hasMatch(value.trim());

/// Whether a statutory registration is overdue.
///
/// A registration is overdue when the event happened longer ago than [limit] and
/// the row has not been registered. A registered row is never overdue, however
/// late it was entered: the fact of registration settles it.
bool isStatutoryRegistrationOverdue({
  required DateTime occurredAt,
  required DateTime? registeredAt,
  required DateTime now,
  required Duration limit,
}) {
  if (registeredAt != null) {
    return false;
  }
  return now.toUtc().difference(occurredAt.toUtc()) > limit;
}

/// Whether a medico-legal case is overdue for police intimation.
///
/// A case already intimated is not overdue, whatever the delay was; the rule
/// marks what still has to happen, not what was slow.
bool isMlcIntimationOverdue({
  required MlcIntimation record,
  required DateTime now,
  Duration limit = mlcIntimationWindow,
}) {
  if (!record.status.awaitsPolice) {
    return false;
  }
  if (record.status == MlcStatus.intimated) {
    return false;
  }
  return now.toUtc().difference(record.reportedAt.toUtc()) > limit;
}

/// The corrected value of each amended field, replayed from [amendments].
///
/// The register row is never rewritten, so the value a reader should act on is
/// the latest amendment for a field. Later amendments win; ties break on the
/// row id so the result is deterministic across devices.
Map<String, String> effectiveStatutoryValues(
  List<StatutoryAmendment> amendments,
) {
  final List<StatutoryAmendment> ordered = <StatutoryAmendment>[...amendments]
    ..sort((StatutoryAmendment a, StatutoryAmendment b) {
      final int order = a.amendedAt.compareTo(b.amendedAt);
      return order != 0 ? order : a.id.compareTo(b.id);
    });
  final Map<String, String> values = <String, String>{};
  for (final StatutoryAmendment amendment in ordered) {
    values[amendment.subjectField] = amendment.newValue;
  }
  return values;
}

/// A birth entered in the statutory register.
@immutable
final class BirthRecord {
  /// Creates a birth registration.
  const BirthRecord({
    required this.id,
    required this.tenantId,
    required this.facilityId,
    required this.childName,
    required this.sex,
    required this.birthAt,
    required this.placeOfBirth,
    required this.deliveryType,
    required this.plurality,
    required this.motherName,
    required this.status,
    required this.createdBy,
    required this.updatedAt,
    this.registrationNumber,
    this.weightGrams,
    this.motherPatientId,
    this.fatherName,
    this.informantName,
    this.attendedBy,
    this.registrationAt,
    this.certificateNumber,
    this.certifiedBy,
    this.certifiedAt,
    this.voidedAt,
    this.voidReason,
    this.createdAt,
  });

  /// Validates and builds a new draft birth row.
  ///
  /// The registration number and the certificate are deliberately absent: a
  /// draft is not in the register yet.
  static Map<String, Object?> registerRow({
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
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (facilityId.isEmpty) {
      fieldErrors['facility_id'] = 'A facility is required.';
    }
    if (childName.trim().isEmpty) {
      fieldErrors['child_name'] = "The child's name is required.";
    }
    if (placeOfBirth.trim().isEmpty) {
      fieldErrors['place_of_birth'] = 'A place of birth is required.';
    }
    if (motherName.trim().isEmpty) {
      fieldErrors['mother_name'] = "The mother's name is required.";
    }
    if (createdBy.isEmpty) {
      fieldErrors['created_by'] = 'Creator is required.';
    }
    if (weightGrams != null && (weightGrams <= 0 || weightGrams > 20000)) {
      fieldErrors['weight_grams'] = 'Expected a weight in grams, above zero.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Birth registration failed validation.',
        fieldErrors: fieldErrors,
        code: 'birth_record_invalid',
      );
    }
    final String now = DateTime.now().toUtc().toIso8601String();
    return <String, Object?>{
      if (birthId.isNotEmpty) 'id': birthId,
      'tenant_id': tenantId,
      'facility_id': facilityId,
      'registration_number': null,
      'child_name': childName.trim(),
      'sex': sex.wireValue,
      'birth_at': birthAt.toUtc().toIso8601String(),
      'place_of_birth': placeOfBirth.trim(),
      'delivery_type': deliveryType.wireValue,
      'plurality': plurality.wireValue,
      'weight_grams': weightGrams,
      'mother_patient_id': _trimmed(motherPatientId),
      'mother_name': motherName.trim(),
      'father_name': _trimmed(fatherName),
      'informant_name': _trimmed(informantName),
      'attended_by': _trimmed(attendedBy),
      'status': BirthStatus.drafted.wireValue,
      'registration_at': null,
      'certificate_number': null,
      'certified_by': null,
      'certified_at': null,
      'voided_at': null,
      'void_reason': null,
      'created_by': createdBy,
      'created_at': now,
      'updated_at': now,
    };
  }

  /// Materializes a birth registration from a local row.
  factory BirthRecord.fromRow(Map<String, Object?> row) => BirthRecord(
    id: row['id']! as String,
    tenantId: row['tenant_id']! as String,
    facilityId: row['facility_id']! as String,
    childName: row['child_name']! as String,
    sex: StatutorySex.fromWire((row['sex'] as String?) ?? 'unknown'),
    birthAt: _parse(row['birth_at']),
    placeOfBirth: row['place_of_birth']! as String,
    deliveryType: DeliveryType.fromWire(
      (row['delivery_type'] as String?) ?? DeliveryType.normal.wireValue,
    ),
    plurality: BirthPlurality.fromWire(
      (row['plurality'] as String?) ?? BirthPlurality.singleton.wireValue,
    ),
    motherName: row['mother_name']! as String,
    status: BirthStatus.fromWire(
      (row['status'] as String?) ?? BirthStatus.drafted.wireValue,
    ),
    createdBy: row['created_by']! as String,
    updatedAt: _parse(row['updated_at']),
    registrationNumber: row['registration_number'] as String?,
    weightGrams: row['weight_grams'] == null
        ? null
        : _asInt(row['weight_grams']),
    motherPatientId: row['mother_patient_id'] as String?,
    fatherName: row['father_name'] as String?,
    informantName: row['informant_name'] as String?,
    attendedBy: row['attended_by'] as String?,
    registrationAt: _parseNullable(row['registration_at']),
    certificateNumber: row['certificate_number'] as String?,
    certifiedBy: row['certified_by'] as String?,
    certifiedAt: _parseNullable(row['certified_at']),
    voidedAt: _parseNullable(row['voided_at']),
    voidReason: row['void_reason'] as String?,
    createdAt: _parseNullable(row['created_at']),
  );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// The facility where the birth occurred.
  final String facilityId;

  /// The child's name as registered.
  final String childName;

  /// The sex recorded.
  final StatutorySex sex;

  /// When the birth occurred, UTC.
  final DateTime birthAt;

  /// Where the birth occurred.
  final String placeOfBirth;

  /// How the birth was delivered.
  final DeliveryType deliveryType;

  /// How many children the birth produced.
  final BirthPlurality plurality;

  /// The mother's name as recorded.
  final String motherName;

  /// Lifecycle status.
  final BirthStatus status;

  /// Who raised the entry.
  final String createdBy;

  /// Last change, UTC.
  final DateTime updatedAt;

  /// The register number, assigned on registration.
  final String? registrationNumber;

  /// Birth weight in grams.
  final int? weightGrams;

  /// The mother's patient record, when she is a patient here.
  final String? motherPatientId;

  /// The father's name as recorded.
  final String? fatherName;

  /// Who reported the birth.
  final String? informantName;

  /// The clinician or midwife who attended.
  final String? attendedBy;

  /// When the entry was registered, UTC.
  final DateTime? registrationAt;

  /// The certificate number, issued on certification.
  final String? certificateNumber;

  /// Who certified the entry.
  final String? certifiedBy;

  /// When the certificate was issued, UTC.
  final DateTime? certifiedAt;

  /// When the entry was withdrawn, UTC.
  final DateTime? voidedAt;

  /// Why the entry was withdrawn.
  final String? voidReason;

  /// When the entry was raised, UTC.
  final DateTime? createdAt;

  /// Whether the entry is still being entered.
  bool get isDraft => status.isDraft;

  /// Whether the entry is closed.
  bool get isTerminal => status.isTerminal;

  /// Whether a certificate has been issued.
  bool get isCertified => status == BirthStatus.certified;

  /// A reference for the amendment log.
  StatutoryRecordRef get ref => StatutoryRecordRef(
    kind: StatutoryRegistryKind.birth,
    id: id,
    status: status.wireValue,
  );
}

/// The change set that enters a birth in the register.
Map<String, Object?> birthRegisterChanges({
  required String registrationNumber,
  DateTime? at,
}) {
  if (registrationNumber.trim().isEmpty) {
    throw const ValidationError(
      message: 'Birth registration failed validation.',
      fieldErrors: <String, String>{
        'registration_number': 'A register number is required.',
      },
      code: 'birth_registration_number_missing',
    );
  }
  final String now = (at ?? DateTime.now()).toUtc().toIso8601String();
  return <String, Object?>{
    'status': BirthStatus.registered.wireValue,
    'registration_number': registrationNumber.trim(),
    'registration_at': now,
    'updated_at': now,
  };
}

/// The change set that issues a birth certificate.
Map<String, Object?> birthCertifyChanges({
  required String certificateNumber,
  required String certifiedBy,
  DateTime? at,
}) {
  final Map<String, String> fieldErrors = <String, String>{};
  if (certificateNumber.trim().isEmpty) {
    fieldErrors['certificate_number'] = 'A certificate number is required.';
  }
  if (certifiedBy.isEmpty) {
    fieldErrors['certified_by'] = 'Who issued it is required.';
  }
  if (fieldErrors.isNotEmpty) {
    throw ValidationError(
      message: 'Birth registration failed validation.',
      fieldErrors: fieldErrors,
      code: 'birth_certificate_invalid',
    );
  }
  final String now = (at ?? DateTime.now()).toUtc().toIso8601String();
  return <String, Object?>{
    'status': BirthStatus.certified.wireValue,
    'certificate_number': certificateNumber.trim(),
    'certified_by': certifiedBy,
    'certified_at': now,
    'updated_at': now,
  };
}

/// The change set that withdraws a birth entry.
Map<String, Object?> birthVoidChanges({required String reason, DateTime? at}) =>
    _voidChanges(
      status: BirthStatus.voided.wireValue,
      reason: reason,
      at: at,
      message: 'Birth registration failed validation.',
      code: 'birth_void_reason_missing',
    );

/// A death entered in the statutory register, with its cause coded.
@immutable
final class DeathRecord {
  /// Creates a death registration.
  const DeathRecord({
    required this.id,
    required this.tenantId,
    required this.facilityId,
    required this.deceasedName,
    required this.sex,
    required this.deathAt,
    required this.placeOfDeath,
    required this.isMedicoLegal,
    required this.status,
    required this.createdBy,
    required this.updatedAt,
    this.registrationNumber,
    this.patientId,
    this.ageYears,
    this.causeOfDeathText,
    this.icd10Code,
    this.mannerOfDeath,
    this.certifyingClinician,
    this.informantName,
    this.informantRelationship,
    this.registrationAt,
    this.certificateNumber,
    this.certifiedBy,
    this.certifiedAt,
    this.voidedAt,
    this.voidReason,
    this.createdAt,
  });

  /// Validates and builds a new draft death row.
  ///
  /// The cause of death is deliberately not required here: a death is entered as
  /// soon as it happens and coded once the clinician has completed it, and the
  /// register refuses the entry until it is coded.
  static Map<String, Object?> registerRow({
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
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (facilityId.isEmpty) {
      fieldErrors['facility_id'] = 'A facility is required.';
    }
    if (deceasedName.trim().isEmpty) {
      fieldErrors['deceased_name'] = "The deceased's name is required.";
    }
    if (placeOfDeath.trim().isEmpty) {
      fieldErrors['place_of_death'] = 'A place of death is required.';
    }
    if (createdBy.isEmpty) {
      fieldErrors['created_by'] = 'Creator is required.';
    }
    if (ageYears != null && (ageYears < 0 || ageYears > 130)) {
      fieldErrors['age_years'] = 'Expected an age from 0 to 130.';
    }
    if (icd10Code != null &&
        icd10Code.trim().isNotEmpty &&
        !isIcd10Code(icd10Code)) {
      fieldErrors['icd10_code'] = 'Expected an ICD-10 code, such as I21.9.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Death registration failed validation.',
        fieldErrors: fieldErrors,
        code: 'death_record_invalid',
      );
    }
    final String now = DateTime.now().toUtc().toIso8601String();
    return <String, Object?>{
      if (deathId.isNotEmpty) 'id': deathId,
      'tenant_id': tenantId,
      'facility_id': facilityId,
      'registration_number': null,
      'patient_id': _trimmed(patientId),
      'deceased_name': deceasedName.trim(),
      'sex': sex.wireValue,
      'age_years': ageYears,
      'death_at': deathAt.toUtc().toIso8601String(),
      'place_of_death': placeOfDeath.trim(),
      'cause_of_death_text': _trimmed(causeOfDeathText),
      'icd10_code': _code(icd10Code),
      'manner_of_death': mannerOfDeath?.wireValue,
      'is_medico_legal': isMedicoLegal ? 1 : 0,
      'certifying_clinician': _trimmed(certifyingClinician),
      'informant_name': _trimmed(informantName),
      'informant_relationship': _trimmed(informantRelationship),
      'status': DeathStatus.drafted.wireValue,
      'registration_at': null,
      'certificate_number': null,
      'certified_by': null,
      'certified_at': null,
      'voided_at': null,
      'void_reason': null,
      'created_by': createdBy,
      'created_at': now,
      'updated_at': now,
    };
  }

  /// Materializes a death registration from a local row.
  factory DeathRecord.fromRow(Map<String, Object?> row) => DeathRecord(
    id: row['id']! as String,
    tenantId: row['tenant_id']! as String,
    facilityId: row['facility_id']! as String,
    deceasedName: row['deceased_name']! as String,
    sex: StatutorySex.fromWire((row['sex'] as String?) ?? 'unknown'),
    deathAt: _parse(row['death_at']),
    placeOfDeath: row['place_of_death']! as String,
    isMedicoLegal: _asBool(row['is_medico_legal']),
    status: DeathStatus.fromWire(
      (row['status'] as String?) ?? DeathStatus.drafted.wireValue,
    ),
    createdBy: row['created_by']! as String,
    updatedAt: _parse(row['updated_at']),
    registrationNumber: row['registration_number'] as String?,
    patientId: row['patient_id'] as String?,
    ageYears: row['age_years'] == null ? null : _asInt(row['age_years']),
    causeOfDeathText: row['cause_of_death_text'] as String?,
    icd10Code: row['icd10_code'] as String?,
    mannerOfDeath: row['manner_of_death'] == null
        ? null
        : MannerOfDeath.fromWire(row['manner_of_death']! as String),
    certifyingClinician: row['certifying_clinician'] as String?,
    informantName: row['informant_name'] as String?,
    informantRelationship: row['informant_relationship'] as String?,
    registrationAt: _parseNullable(row['registration_at']),
    certificateNumber: row['certificate_number'] as String?,
    certifiedBy: row['certified_by'] as String?,
    certifiedAt: _parseNullable(row['certified_at']),
    voidedAt: _parseNullable(row['voided_at']),
    voidReason: row['void_reason'] as String?,
    createdAt: _parseNullable(row['created_at']),
  );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// The facility where the death occurred.
  final String facilityId;

  /// The deceased's name as registered.
  final String deceasedName;

  /// The sex recorded.
  final StatutorySex sex;

  /// When the death occurred, UTC.
  final DateTime deathAt;

  /// Where the death occurred.
  final String placeOfDeath;

  /// Whether the death is a medico-legal case.
  final bool isMedicoLegal;

  /// Lifecycle status.
  final DeathStatus status;

  /// Who raised the entry.
  final String createdBy;

  /// Last change, UTC.
  final DateTime updatedAt;

  /// The register number, assigned on registration.
  final String? registrationNumber;

  /// The deceased's patient record, when they are a patient here.
  final String? patientId;

  /// Age at death in years, when known.
  final int? ageYears;

  /// The cause of death in words, as certified.
  final String? causeOfDeathText;

  /// The ICD-10 code for the underlying cause.
  final String? icd10Code;

  /// How the death is classified.
  final MannerOfDeath? mannerOfDeath;

  /// The clinician who certified the cause.
  final String? certifyingClinician;

  /// Who reported the death.
  final String? informantName;

  /// How the informant is related.
  final String? informantRelationship;

  /// When the entry was registered, UTC.
  final DateTime? registrationAt;

  /// The certificate number, issued on certification.
  final String? certificateNumber;

  /// Who certified the entry.
  final String? certifiedBy;

  /// When the certificate was issued, UTC.
  final DateTime? certifiedAt;

  /// When the entry was withdrawn, UTC.
  final DateTime? voidedAt;

  /// Why the entry was withdrawn.
  final String? voidReason;

  /// When the entry was raised, UTC.
  final DateTime? createdAt;

  /// Whether the entry is still being entered.
  bool get isDraft => status.isDraft;

  /// Whether the entry is closed.
  bool get isTerminal => status.isTerminal;

  /// Whether a certificate has been issued.
  bool get isCertified => status == DeathStatus.certified;

  /// Whether the cause of death is coded, which registration requires.
  bool get isCoded =>
      causeOfDeathText != null && icd10Code != null && mannerOfDeath != null;

  /// A reference for the amendment log.
  StatutoryRecordRef get ref => StatutoryRecordRef(
    kind: StatutoryRegistryKind.death,
    id: id,
    status: status.wireValue,
  );
}

/// The change set that records the cause-of-death coding.
Map<String, Object?> deathCodingChanges({
  required String causeOfDeathText,
  required String icd10Code,
  required MannerOfDeath mannerOfDeath,
  bool? isMedicoLegal,
  String? certifyingClinician,
}) {
  final Map<String, String> fieldErrors = <String, String>{};
  if (causeOfDeathText.trim().isEmpty) {
    fieldErrors['cause_of_death_text'] = 'The cause of death is required.';
  }
  if (!isIcd10Code(icd10Code)) {
    fieldErrors['icd10_code'] = 'Expected an ICD-10 code, such as I21.9.';
  }
  if (fieldErrors.isNotEmpty) {
    throw ValidationError(
      message: 'Death registration failed validation.',
      fieldErrors: fieldErrors,
      code: 'death_coding_invalid',
    );
  }
  return <String, Object?>{
    'cause_of_death_text': causeOfDeathText.trim(),
    'icd10_code': icd10Code.trim(),
    'manner_of_death': mannerOfDeath.wireValue,
    if (isMedicoLegal != null) 'is_medico_legal': isMedicoLegal ? 1 : 0,
    'certifying_clinician': ?_trimmed(certifyingClinician),
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  };
}

/// The change set that enters a death in the register.
Map<String, Object?> deathRegisterChanges({
  required String registrationNumber,
  DateTime? at,
}) {
  if (registrationNumber.trim().isEmpty) {
    throw const ValidationError(
      message: 'Death registration failed validation.',
      fieldErrors: <String, String>{
        'registration_number': 'A register number is required.',
      },
      code: 'death_registration_number_missing',
    );
  }
  final String now = (at ?? DateTime.now()).toUtc().toIso8601String();
  return <String, Object?>{
    'status': DeathStatus.registered.wireValue,
    'registration_number': registrationNumber.trim(),
    'registration_at': now,
    'updated_at': now,
  };
}

/// The change set that issues a death certificate.
Map<String, Object?> deathCertifyChanges({
  required String certificateNumber,
  required String certifiedBy,
  DateTime? at,
}) {
  final Map<String, String> fieldErrors = <String, String>{};
  if (certificateNumber.trim().isEmpty) {
    fieldErrors['certificate_number'] = 'A certificate number is required.';
  }
  if (certifiedBy.isEmpty) {
    fieldErrors['certified_by'] = 'Who issued it is required.';
  }
  if (fieldErrors.isNotEmpty) {
    throw ValidationError(
      message: 'Death registration failed validation.',
      fieldErrors: fieldErrors,
      code: 'death_certificate_invalid',
    );
  }
  final String now = (at ?? DateTime.now()).toUtc().toIso8601String();
  return <String, Object?>{
    'status': DeathStatus.certified.wireValue,
    'certificate_number': certificateNumber.trim(),
    'certified_by': certifiedBy,
    'certified_at': now,
    'updated_at': now,
  };
}

/// The change set that withdraws a death entry.
Map<String, Object?> deathVoidChanges({required String reason, DateTime? at}) =>
    _voidChanges(
      status: DeathStatus.voided.wireValue,
      reason: reason,
      at: at,
      message: 'Death registration failed validation.',
      code: 'death_void_reason_missing',
    );

/// A medico-legal case and its police intimation.
@immutable
final class MlcIntimation {
  /// Creates a medico-legal case.
  const MlcIntimation({
    required this.id,
    required this.tenantId,
    required this.facilityId,
    required this.caseNumber,
    required this.subjectName,
    required this.caseType,
    required this.reportedAt,
    required this.status,
    required this.createdBy,
    required this.updatedAt,
    this.patientId,
    this.incidentAt,
    this.reportingClinician,
    this.policeStation,
    this.policeOfficerName,
    this.policeContact,
    this.policeReference,
    this.intimatedAt,
    this.acknowledgedAt,
    this.closedAt,
    this.closureReason,
    this.voidedAt,
    this.voidReason,
    this.createdAt,
  });

  /// Validates and builds a new reported case row.
  static Map<String, Object?> registerRow({
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
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (facilityId.isEmpty) {
      fieldErrors['facility_id'] = 'A facility is required.';
    }
    if (caseNumber.trim().isEmpty) {
      fieldErrors['case_number'] = 'A case number is required.';
    }
    if (subjectName.trim().isEmpty) {
      fieldErrors['subject_name'] = 'The subject is required.';
    }
    if (createdBy.isEmpty) {
      fieldErrors['created_by'] = 'Creator is required.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Medico-legal case failed validation.',
        fieldErrors: fieldErrors,
        code: 'mlc_intimation_invalid',
      );
    }
    final DateTime at = (reportedAt ?? DateTime.now()).toUtc();
    final String stamp = at.toIso8601String();
    return <String, Object?>{
      if (mlcId.isNotEmpty) 'id': mlcId,
      'tenant_id': tenantId,
      'facility_id': facilityId,
      'case_number': caseNumber.trim(),
      'patient_id': _trimmed(patientId),
      'subject_name': subjectName.trim(),
      'case_type': caseType.wireValue,
      'incident_at': ?incidentAt?.toUtc().toIso8601String(),
      'reported_at': stamp,
      'reporting_clinician': _trimmed(reportingClinician),
      'police_station': null,
      'police_officer_name': null,
      'police_contact': null,
      'police_reference': null,
      'status': MlcStatus.reported.wireValue,
      'intimated_at': null,
      'acknowledged_at': null,
      'closed_at': null,
      'closure_reason': null,
      'voided_at': null,
      'void_reason': null,
      'created_by': createdBy,
      'created_at': stamp,
      'updated_at': stamp,
    };
  }

  /// Materializes a case from a local row.
  factory MlcIntimation.fromRow(Map<String, Object?> row) => MlcIntimation(
    id: row['id']! as String,
    tenantId: row['tenant_id']! as String,
    facilityId: row['facility_id']! as String,
    caseNumber: row['case_number']! as String,
    subjectName: row['subject_name']! as String,
    caseType: MlcCaseType.fromWire(
      (row['case_type'] as String?) ?? MlcCaseType.other.wireValue,
    ),
    reportedAt: _parse(row['reported_at']),
    status: MlcStatus.fromWire(
      (row['status'] as String?) ?? MlcStatus.reported.wireValue,
    ),
    createdBy: row['created_by']! as String,
    updatedAt: _parse(row['updated_at']),
    patientId: row['patient_id'] as String?,
    incidentAt: _parseNullable(row['incident_at']),
    reportingClinician: row['reporting_clinician'] as String?,
    policeStation: row['police_station'] as String?,
    policeOfficerName: row['police_officer_name'] as String?,
    policeContact: row['police_contact'] as String?,
    policeReference: row['police_reference'] as String?,
    intimatedAt: _parseNullable(row['intimated_at']),
    acknowledgedAt: _parseNullable(row['acknowledged_at']),
    closedAt: _parseNullable(row['closed_at']),
    closureReason: row['closure_reason'] as String?,
    voidedAt: _parseNullable(row['voided_at']),
    voidReason: row['void_reason'] as String?,
    createdAt: _parseNullable(row['created_at']),
  );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// The facility that logged the case.
  final String facilityId;

  /// The hospital's case number.
  final String caseNumber;

  /// The person the case concerns.
  final String subjectName;

  /// What kind of case it is.
  final MlcCaseType caseType;

  /// When the hospital logged the case, UTC.
  final DateTime reportedAt;

  /// Lifecycle status.
  final MlcStatus status;

  /// Who raised the case.
  final String createdBy;

  /// Last change, UTC.
  final DateTime updatedAt;

  /// The subject's patient record, when they are a patient here.
  final String? patientId;

  /// When the incident occurred, UTC.
  final DateTime? incidentAt;

  /// The clinician who reported the case.
  final String? reportingClinician;

  /// The police station told.
  final String? policeStation;

  /// The officer spoken to.
  final String? policeOfficerName;

  /// A contact number for the station.
  final String? policeContact;

  /// The police reference, recorded on acknowledgement.
  final String? policeReference;

  /// When the police were told, UTC.
  final DateTime? intimatedAt;

  /// When the police acknowledged, UTC.
  final DateTime? acknowledgedAt;

  /// When the case was closed, UTC.
  final DateTime? closedAt;

  /// Why the case was closed.
  final String? closureReason;

  /// When the case was withdrawn, UTC.
  final DateTime? voidedAt;

  /// Why the case was withdrawn.
  final String? voidReason;

  /// When the case was raised, UTC.
  final DateTime? createdAt;

  /// Whether the case has still to be worked.
  bool get isLive => status.isLive;

  /// Whether the case is closed.
  bool get isTerminal => status.isTerminal;

  /// A reference for the amendment log.
  StatutoryRecordRef get ref => StatutoryRecordRef(
    kind: StatutoryRegistryKind.mlc,
    id: id,
    status: status.wireValue,
  );
}

/// The change set that tells the police about a case.
Map<String, Object?> mlcIntimateChanges({
  required String policeStation,
  String? policeOfficerName,
  String? policeContact,
  DateTime? at,
}) {
  if (policeStation.trim().isEmpty) {
    throw const ValidationError(
      message: 'Medico-legal case failed validation.',
      fieldErrors: <String, String>{
        'police_station': 'The station told is required.',
      },
      code: 'mlc_police_station_missing',
    );
  }
  final String now = (at ?? DateTime.now()).toUtc().toIso8601String();
  return <String, Object?>{
    'status': MlcStatus.intimated.wireValue,
    'police_station': policeStation.trim(),
    'police_officer_name': ?_trimmed(policeOfficerName),
    'police_contact': ?_trimmed(policeContact),
    'intimated_at': now,
    'updated_at': now,
  };
}

/// The change set that records police acknowledgement.
Map<String, Object?> mlcAcknowledgeChanges({
  required String policeReference,
  DateTime? at,
}) {
  if (policeReference.trim().isEmpty) {
    throw const ValidationError(
      message: 'Medico-legal case failed validation.',
      fieldErrors: <String, String>{
        'police_reference': 'The police reference is required.',
      },
      code: 'mlc_police_reference_missing',
    );
  }
  final String now = (at ?? DateTime.now()).toUtc().toIso8601String();
  return <String, Object?>{
    'status': MlcStatus.acknowledged.wireValue,
    'police_reference': policeReference.trim(),
    'acknowledged_at': now,
    'updated_at': now,
  };
}

/// The change set that closes a case.
Map<String, Object?> mlcCloseChanges({required String reason, DateTime? at}) {
  if (reason.trim().isEmpty) {
    throw const ValidationError(
      message: 'Medico-legal case failed validation.',
      fieldErrors: <String, String>{'closure_reason': 'A reason is required.'},
      code: 'mlc_closure_reason_missing',
    );
  }
  final String now = (at ?? DateTime.now()).toUtc().toIso8601String();
  return <String, Object?>{
    'status': MlcStatus.closed.wireValue,
    'closed_at': now,
    'closure_reason': reason.trim(),
    'updated_at': now,
  };
}

/// The change set that withdraws a case.
Map<String, Object?> mlcVoidChanges({required String reason, DateTime? at}) =>
    _voidChanges(
      status: MlcStatus.voided.wireValue,
      reason: reason,
      at: at,
      message: 'Medico-legal case failed validation.',
      code: 'mlc_void_reason_missing',
    );

/// An append-only correction to a registered statutory fact.
@immutable
final class StatutoryAmendment {
  /// Creates an amendment.
  const StatutoryAmendment({
    required this.id,
    required this.tenantId,
    required this.kind,
    required this.recordId,
    required this.subjectField,
    required this.newValue,
    required this.reason,
    required this.amendedBy,
    required this.amendedAt,
    this.previousValue,
  });

  /// Validates and builds an amendment row for [record].
  static Map<String, Object?> registerRow({
    required String tenantId,
    required StatutoryRecordRef record,
    required String subjectField,
    required String newValue,
    required String reason,
    required String amendedBy,
    String? previousValue,
    DateTime? at,
    String amendmentId = '',
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (record.id.isEmpty) {
      fieldErrors['record'] = 'An amendment names what it corrects.';
    }
    if (subjectField.trim().isEmpty) {
      fieldErrors['subject_field'] = 'Which field changed is required.';
    }
    if (newValue.trim().isEmpty) {
      fieldErrors['new_value'] = 'The corrected value is required.';
    }
    if (reason.trim().isEmpty) {
      fieldErrors['reason'] = 'A reason is required.';
    }
    if (amendedBy.isEmpty) {
      fieldErrors['amended_by'] = 'Who attested it is required.';
    }
    if (previousValue != null && previousValue.trim() == newValue.trim()) {
      fieldErrors['new_value'] = 'The corrected value is unchanged.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Statutory amendment failed validation.',
        fieldErrors: fieldErrors,
        code: 'statutory_amendment_invalid',
      );
    }
    final String now = (at ?? DateTime.now()).toUtc().toIso8601String();
    return <String, Object?>{
      if (amendmentId.isNotEmpty) 'id': amendmentId,
      'tenant_id': tenantId,
      'birth_record_id': record.kind == StatutoryRegistryKind.birth
          ? record.id
          : null,
      'death_record_id': record.kind == StatutoryRegistryKind.death
          ? record.id
          : null,
      'mlc_intimation_id': record.kind == StatutoryRegistryKind.mlc
          ? record.id
          : null,
      'subject_field': subjectField.trim(),
      'previous_value': _trimmed(previousValue),
      'new_value': newValue.trim(),
      'reason': reason.trim(),
      'amended_by': amendedBy,
      'created_at': now,
    };
  }

  /// Materializes an amendment from a local row.
  factory StatutoryAmendment.fromRow(Map<String, Object?> row) {
    final String? birthId = row['birth_record_id'] as String?;
    final String? deathId = row['death_record_id'] as String?;
    final String? mlcId = row['mlc_intimation_id'] as String?;
    return StatutoryAmendment(
      id: row['id']! as String,
      tenantId: row['tenant_id']! as String,
      kind: birthId != null
          ? StatutoryRegistryKind.birth
          : deathId != null
          ? StatutoryRegistryKind.death
          : StatutoryRegistryKind.mlc,
      recordId: birthId ?? deathId ?? mlcId ?? '',
      subjectField: row['subject_field']! as String,
      newValue: row['new_value']! as String,
      reason: row['reason']! as String,
      amendedBy: row['amended_by']! as String,
      amendedAt: _parse(row['created_at']),
      previousValue: row['previous_value'] as String?,
    );
  }

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// Which register the corrected row belongs to.
  final StatutoryRegistryKind kind;

  /// The corrected row.
  final String recordId;

  /// Which field was corrected.
  final String subjectField;

  /// The value now asserted.
  final String newValue;

  /// Why the correction was made.
  final String reason;

  /// Who attested the correction.
  final String amendedBy;

  /// When the correction was appended, UTC.
  final DateTime amendedAt;

  /// The value the register held before, when it held one.
  final String? previousValue;
}

Map<String, Object?> _voidChanges({
  required String status,
  required String reason,
  required DateTime? at,
  required String message,
  required String code,
}) {
  if (reason.trim().isEmpty) {
    throw ValidationError(
      message: message,
      fieldErrors: const <String, String>{
        'void_reason': 'A reason is required.',
      },
      code: code,
    );
  }
  final String now = (at ?? DateTime.now()).toUtc().toIso8601String();
  return <String, Object?>{
    'status': status,
    'voided_at': now,
    'void_reason': reason.trim(),
    'updated_at': now,
  };
}

String? _code(String? value) {
  final String? trimmed = _trimmed(value);
  return trimmed?.toUpperCase();
}

String? _trimmed(String? value) {
  if (value == null) {
    return null;
  }
  final String trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

DateTime _parse(Object? value) => value is String
    ? DateTime.parse(value).toUtc()
    : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

DateTime? _parseNullable(Object? value) =>
    value is String ? DateTime.parse(value).toUtc() : null;

int _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.parse(value);
  }
  return 0;
}

bool _asBool(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  if (value is String) {
    return value == '1' || value.toLowerCase() == 'true';
  }
  return false;
}
