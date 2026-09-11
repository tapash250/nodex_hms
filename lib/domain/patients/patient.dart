/// Master Patient Index domain entities (Module 10).
///
/// A [Patient] is the identity root every other clinical module references. Two
/// rules shape this file:
///
/// 1. Raw national IDs never appear here. Only [PatientIdentity.hashNationalId]
///    output (SHA-256 hex) is stored or transmitted; the raw value lives in the
///    registration form's memory for the duration of one hash computation.
/// 2. Validation failures carry field names, never values, so a
///    [ValidationError] can be logged and displayed without leaking PHI.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';

/// Administrative gender classification recorded at registration.
enum PatientGender {
  /// Recorded as male.
  male('male'),

  /// Recorded as female.
  female('female'),

  /// Recorded as other.
  other('other'),

  /// Declined to state or not recorded.
  unknown('unknown');

  const PatientGender(this.wireValue);

  /// Value persisted in `patients.gender`.
  final String wireValue;

  /// Parses a stored value, defaulting to [unknown] for unrecognised input.
  ///
  /// Defaulting to the least informative value is deliberate: an unrecognised
  /// gender code must never be silently upgraded to a specific classification.
  static PatientGender fromWire(String value) {
    for (final PatientGender gender in PatientGender.values) {
      if (gender.wireValue == value) {
        return gender;
      }
    }
    return PatientGender.unknown;
  }
}

/// ABO/Rh blood group, recorded when known.
enum BloodGroup {
  /// A positive.
  aPositive('A+'),

  /// A negative.
  aNegative('A-'),

  /// B positive.
  bPositive('B+'),

  /// B negative.
  bNegative('B-'),

  /// AB positive.
  abPositive('AB+'),

  /// AB negative.
  abNegative('AB-'),

  /// O positive.
  oPositive('O+'),

  /// O negative.
  oNegative('O-');

  const BloodGroup(this.wireValue);

  /// Value persisted in `patients.blood_group`.
  final String wireValue;

  /// Parses a stored value, or null when absent or unrecognised.
  static BloodGroup? fromWire(String? value) {
    if (value == null) {
      return null;
    }
    for (final BloodGroup group in BloodGroup.values) {
      if (group.wireValue == value) {
        return group;
      }
    }
    return null;
  }
}

/// Allergy severity as recorded by the clinician.
enum AllergySeverity {
  /// Mild reaction.
  mild('mild'),

  /// Moderate reaction.
  moderate('moderate'),

  /// Severe reaction.
  severe('severe'),

  /// Severity not assessed.
  unknown('unknown');

  const AllergySeverity(this.wireValue);

  /// Value persisted in `patient_allergies.severity`.
  final String wireValue;

  /// Parses a stored value, defaulting to [unknown].
  static AllergySeverity fromWire(String value) {
    for (final AllergySeverity severity in AllergySeverity.values) {
      if (severity.wireValue == value) {
        return severity;
      }
    }
    return AllergySeverity.unknown;
  }
}

/// Identity helpers for patient matching without storing raw identifiers.
abstract final class PatientIdentity {
  /// Computes the SHA-256 hex digest of a national ID number.
  ///
  /// The raw number is normalized (whitespace and separators removed,
  /// upper-cased) before hashing so that formatting differences do not produce
  /// different hashes for the same person.
  static String hashNationalId(String rawNationalId) {
    final String normalized = rawNationalId
        .replaceAll(RegExp(r'[\s\-–—]'), '')
        .toUpperCase();
    return sha256.convert(utf8.encode('nodex-nid-v1:$normalized')).toString();
  }
}

/// A patient demographic record.
@immutable
final class Patient {
  /// Creates a patient. Prefer [Patient.registrationRow] for new registrations,
  /// which validates invariants before construction.
  const Patient({
    required this.id,
    required this.tenantId,
    required this.mrn,
    required this.firstName,
    required this.lastName,
    required this.dateOfBirth,
    required this.gender,
    required this.isActive,
    this.nationalIdHash,
    this.bloodGroup,
    this.phoneNumber,
    this.email,
    this.address,
    this.nextOfKin,
    this.occupation,
    this.maritalStatus,
    this.preferredLanguage,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
  });

  /// Materialises a patient from a local database row.
  ///
  /// PowerSync returns dates as ISO-8601 text and booleans as integers; the
  /// mapping is explicit here rather than scattered across queries.
  factory Patient.fromRow(Map<String, Object?> row) {
    DateTime parseDate(String key) {
      final Object? value = row[key];
      if (value is String) {
        return DateTime.parse(value);
      }
      throw FormatException('patient row field "$key" is not a date string');
    }

    int parseBool(String key) {
      final Object? value = row[key];
      if (value is int) {
        return value;
      }
      if (value is bool) {
        return value ? 1 : 0;
      }
      throw FormatException('patient row field "$key" is not a boolean');
    }

    return Patient(
      id: row['id']! as String,
      tenantId: row['tenant_id']! as String,
      mrn: row['mrn']! as String,
      firstName: row['first_name']! as String,
      lastName: row['last_name']! as String,
      dateOfBirth: parseDate('date_of_birth'),
      gender: PatientGender.fromWire(row['gender']! as String),
      isActive: parseBool('is_active') == 1,
      nationalIdHash: row['national_id_hash'] as String?,
      bloodGroup: BloodGroup.fromWire(row['blood_group'] as String?),
      phoneNumber: row['phone_number'] as String?,
      email: row['email'] as String?,
      address: row['address'] as String?,
      nextOfKin: row['next_of_kin'] as String?,
      occupation: row['occupation'] as String?,
      maritalStatus: row['marital_status'] as String?,
      preferredLanguage: row['preferred_language'] as String?,
      createdBy: row['created_by'] as String?,
      createdAt: row['created_at'] == null
          ? null
          : DateTime.parse(row['created_at']! as String),
      updatedAt: row['updated_at'] == null
          ? null
          : DateTime.parse(row['updated_at']! as String),
    );
  }

  /// Validates registration input and builds the local row for insertion.
  ///
  /// Returns the row map (without `id`: the repository assigns a UUIDv4 so the
  /// same row keeps its identity from the local projection through the upload
  /// queue to the cloud record) or throws [ValidationError] naming the
  /// offending fields. Values never appear in the error — only field names —
  /// so the error is safe to log and display.
  static Map<String, Object?> registrationRow({
    required String tenantId,
    required String mrn,
    required String firstName,
    required String lastName,
    required DateTime dateOfBirth,
    required PatientGender gender,
    String? nationalIdHash,
    BloodGroup? bloodGroup,
    String? phoneNumber,
    String? createdBy,
  }) {
    final Map<String, String> fieldErrors = <String, String>{};

    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'A tenant is required.';
    }
    if (mrn.trim().isEmpty) {
      fieldErrors['mrn'] = 'A medical record number is required.';
    }
    if (firstName.trim().isEmpty) {
      fieldErrors['first_name'] = 'A first name is required.';
    }
    if (lastName.trim().isEmpty) {
      fieldErrors['last_name'] = 'A last name is required.';
    }
    if (dateOfBirth.isAfter(DateTime.now())) {
      fieldErrors['date_of_birth'] = 'Date of birth cannot be in the future.';
    }
    if (phoneNumber != null &&
        phoneNumber.trim().isNotEmpty &&
        phoneNumber.trim().length < 7) {
      fieldErrors['phone_number'] = 'Enter a complete phone number.';
    }

    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Patient registration failed validation.',
        fieldErrors: fieldErrors,
        code: 'patient_registration_invalid',
      );
    }

    final DateTime now = DateTime.now().toUtc();
    String? normalizedPhone = phoneNumber?.trim();
    if (normalizedPhone != null && normalizedPhone.isEmpty) {
      normalizedPhone = null;
    }

    return <String, Object?>{
      'tenant_id': tenantId,
      'mrn': mrn.trim(),
      'national_id_hash': nationalIdHash,
      'first_name': firstName.trim(),
      'last_name': lastName.trim(),
      'date_of_birth': _formatDate(dateOfBirth),
      'gender': gender.wireValue,
      'blood_group': bloodGroup?.wireValue,
      'phone_number': normalizedPhone,
      'is_active': 1,
      'created_by': createdBy,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    };
  }

  /// Database identifier.
  final String id;

  /// Tenant this record belongs to.
  final String tenantId;

  /// Medical record number, unique within the tenant.
  final String mrn;

  /// First (given) name.
  final String firstName;

  /// Last (family) name.
  final String lastName;

  /// Date of birth.
  final DateTime dateOfBirth;

  /// Recorded gender.
  final PatientGender gender;

  /// Whether this record is the active identity (false after a merge absorbs it).
  final bool isActive;

  /// SHA-256 hash of the national ID, or null when not provided.
  final String? nationalIdHash;

  /// Blood group, when known.
  final BloodGroup? bloodGroup;

  /// Contact phone number.
  final String? phoneNumber;

  /// Contact email. Mergeable when edits are disjoint.
  final String? email;

  /// Postal address. Mergeable when edits are disjoint.
  final String? address;

  /// Next of kin contact. Mergeable when edits are disjoint.
  final String? nextOfKin;

  /// Occupation. Mergeable when edits are disjoint.
  final String? occupation;

  /// Marital status, closed vocabulary server-side. Mergeable when disjoint.
  final String? maritalStatus;

  /// Preferred language for communication. Mergeable when edits are disjoint.
  final String? preferredLanguage;

  /// Principal that registered the patient.
  final String? createdBy;

  /// When the record was created.
  final DateTime? createdAt;

  /// When the record was last modified.
  final DateTime? updatedAt;

  /// Display name in "Last, First" clinical convention.
  String get displayName => '$lastName, $firstName';

  /// Age in completed years at [at], defaulting to now.
  int ageAt([DateTime? at]) {
    final DateTime now = (at ?? DateTime.now()).toUtc();
    int age = now.year - dateOfBirth.year;
    if (now.month < dateOfBirth.month ||
        (now.month == dateOfBirth.month && now.day < dateOfBirth.day)) {
      age -= 1;
    }
    return age;
  }

  /// Returns a copy with the supplied fields replaced.
  Patient copyWith({
    String? mrn,
    String? firstName,
    String? lastName,
    DateTime? dateOfBirth,
    PatientGender? gender,
    bool? isActive,
    String? nationalIdHash,
    BloodGroup? bloodGroup,
    String? phoneNumber,
    String? email,
    String? address,
    String? nextOfKin,
    String? occupation,
    String? maritalStatus,
    String? preferredLanguage,
    DateTime? updatedAt,
  }) => Patient(
    id: id,
    tenantId: tenantId,
    mrn: mrn ?? this.mrn,
    firstName: firstName ?? this.firstName,
    lastName: lastName ?? this.lastName,
    dateOfBirth: dateOfBirth ?? this.dateOfBirth,
    gender: gender ?? this.gender,
    isActive: isActive ?? this.isActive,
    nationalIdHash: nationalIdHash ?? this.nationalIdHash,
    bloodGroup: bloodGroup ?? this.bloodGroup,
    phoneNumber: phoneNumber ?? this.phoneNumber,
    email: email ?? this.email,
    address: address ?? this.address,
    nextOfKin: nextOfKin ?? this.nextOfKin,
    occupation: occupation ?? this.occupation,
    maritalStatus: maritalStatus ?? this.maritalStatus,
    preferredLanguage: preferredLanguage ?? this.preferredLanguage,
    createdBy: createdBy,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  /// Builds the row map for a contact-detail update.
  ///
  /// Only mergeable columns are accepted here: identity fields change through
  /// the merge workflow, never through a direct edit. Unknown keys throw
  /// [ValidationError] rather than being silently dropped.
  static Map<String, Object?> contactUpdateRow(Map<String, Object?> changes) {
    const Set<String> allowed = <String>{
      'phone_number',
      'email',
      'address',
      'next_of_kin',
      'occupation',
      'marital_status',
      'preferred_language',
    };

    final List<String> rejected = changes.keys
        .where((String key) => !allowed.contains(key))
        .toList(growable: false);
    if (rejected.isNotEmpty) {
      throw ValidationError(
        message: 'Identity fields cannot be edited directly; use the merge workflow.',
        code: 'patient_identity_edit_blocked',
        context: <String, Object?>{'fields': rejected},
      );
    }

    if (changes.containsKey('marital_status')) {
      const Set<String> vocabulary = <String>{
        'single',
        'married',
        'divorced',
        'widowed',
        'other',
        'unknown',
      };
      final Object? value = changes['marital_status'];
      if (value != null &&
          (value is! String || !vocabulary.contains(value.trim()))) {
        throw const ValidationError(
          message: 'Marital status is outside the closed vocabulary.',
          fieldErrors: <String, String>{
            'marital_status': 'Choose a listed value.',
          },
          code: 'patient_marital_status_invalid',
        );
      }
    }

    return <String, Object?>{
      ...changes,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  static String _formatDate(DateTime date) {
    final String y = date.year.toString().padLeft(4, '0');
    final String m = date.month.toString().padLeft(2, '0');
    final String d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}

/// An allergy record.
///
/// Immutable after insert: corrections retire the row with a reason and insert
/// a replacement. The repository enforces this; the database trigger enforces
/// it again server-side.
@immutable
final class PatientAllergy {
  /// Creates an allergy record.
  const PatientAllergy({
    required this.id,
    required this.tenantId,
    required this.patientId,
    required this.substance,
    required this.severity,
    required this.status,
    required this.recordedAt,
    this.reaction,
    this.retiredReason,
    this.recordedBy,
    this.retiredAt,
    this.createdAt,
  });

  /// Materialises an allergy from a local database row.
  factory PatientAllergy.fromRow(Map<String, Object?> row) => PatientAllergy(
    id: row['id']! as String,
    tenantId: row['tenant_id']! as String,
    patientId: row['patient_id']! as String,
    substance: row['substance']! as String,
    severity: AllergySeverity.fromWire(row['severity']! as String),
    status: row['status']! as String,
    recordedAt: DateTime.parse(row['recorded_at']! as String),
    reaction: row['reaction'] as String?,
    retiredReason: row['retired_reason'] as String?,
    recordedBy: row['recorded_by'] as String?,
    retiredAt: row['retired_at'] == null
        ? null
        : DateTime.parse(row['retired_at']! as String),
    createdAt: row['created_at'] == null
        ? null
        : DateTime.parse(row['created_at']! as String),
  );

  /// Validates a new allergy report and builds the local row for insertion.
  static Map<String, Object?> reportRow({
    required String tenantId,
    required String patientId,
    required String substance,
    required AllergySeverity severity,
    String? reaction,
    String? recordedBy,
  }) {
    final Map<String, String> fieldErrors = <String, String>{};

    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'A tenant is required.';
    }
    if (patientId.isEmpty) {
      fieldErrors['patient_id'] = 'A patient is required.';
    }
    if (substance.trim().isEmpty) {
      fieldErrors['substance'] = 'The substance is required.';
    }

    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Allergy report failed validation.',
        fieldErrors: fieldErrors,
        code: 'allergy_report_invalid',
      );
    }

    final DateTime now = DateTime.now().toUtc();
    String? normalizedReaction = reaction?.trim();
    if (normalizedReaction != null && normalizedReaction.isEmpty) {
      normalizedReaction = null;
    }

    return <String, Object?>{
      'tenant_id': tenantId,
      'patient_id': patientId,
      'substance': substance.trim(),
      'reaction': normalizedReaction,
      'severity': severity.wireValue,
      'status': 'active',
      'retired_reason': null,
      'recorded_by': recordedBy,
      'recorded_at': now.toIso8601String(),
      'retired_at': null,
      'created_at': now.toIso8601String(),
    };
  }

  /// Database identifier.
  final String id;

  /// Tenant this record belongs to.
  final String tenantId;

  /// Patient this allergy belongs to.
  final String patientId;

  /// The substance (drug, food, environmental).
  final String substance;

  /// Recorded severity.
  final AllergySeverity severity;

  /// `active` or `retired`.
  final String status;

  /// When the allergy was recorded.
  final DateTime recordedAt;

  /// Described reaction.
  final String? reaction;

  /// Why the row was retired, when it was.
  final String? retiredReason;

  /// Principal that recorded the allergy.
  final String? recordedBy;

  /// When the row was retired.
  final DateTime? retiredAt;

  /// When the row was created.
  final DateTime? createdAt;

  /// Whether this allergy is currently in force.
  bool get isActive => status == 'active';
}
