/// Doctor & specialist directory entities (Module 08).
///
/// Specification scope: an enterprise registry of doctors, sub-specialties,
/// credentials, consultation rooms and on-call rotations, read-only for its
/// consumers. A profile hangs off an existing app user rather than duplicating
/// identity: name and employment status live with the user record, while this
/// owns the clinical directory facts a specialist search filters on.
///
/// A retired profile is a credential record: it freezes on retirement so a
/// historical referral still names the specialist who saw it, matching the
/// append-only stance taken across the clinical schema.
///
/// On-call rotations are never overwritten. An expiring rotation stays on the
/// row it describes, so "who was on call last Tuesday" is answerable from the
/// local projection.
// ignore_for_file: sort_constructors_first
library;

import 'package:meta/meta.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';

/// Registry status of a practitioner.
enum PractitionerStatus {
  /// Listed and accepting referrals.
  active('active'),

  /// Temporarily not listed; profile retained.
  suspended('suspended'),

  /// Retired; the profile is frozen as the credential record.
  retired('retired');

  const PractitionerStatus(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Parses a stored value.
  static PractitionerStatus fromWire(String value) =>
      PractitionerStatus.values.firstWhere(
        (PractitionerStatus status) => status.wireValue == value,
        orElse: () => PractitionerStatus.active,
      );

  /// Whether the profile may still be edited.
  bool get isEditable => this != PractitionerStatus.retired;
}

/// Kind of on-call cover a rotation carries.
enum OnCallType {
  /// First response for the service.
  primary('primary'),

  /// Backup while primary is engaged.
  secondary('secondary'),

  /// Ward-level cover.
  ward('ward'),

  /// Theatre cover.
  theatre('theatre'),

  /// Outpatient consult cover.
  consult('consult'),

  /// Relief cover during a break.
  respite('respite');

  const OnCallType(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    OnCallType.primary => 'Primary',
    OnCallType.secondary => 'Secondary',
    OnCallType.ward => 'Ward',
    OnCallType.theatre => 'Theatre',
    OnCallType.consult => 'Consult',
    OnCallType.respite => 'Relief',
  };

  /// Parses a stored value.
  static OnCallType fromWire(String value) => OnCallType.values.firstWhere(
    (OnCallType type) => type.wireValue == value,
    orElse: () => OnCallType.consult,
  );
}

/// A practitioner as the directory lists them.
///
/// Identity (name, contact) is read from the linked user record by the screen;
/// this entity owns the clinical facts and their lifecycle.
@immutable
final class PractitionerProfile {
  /// Creates a profile.
  const PractitionerProfile({
    required this.id,
    required this.tenantId,
    required this.userId,
    required this.facilityId,
    required this.specialty,
    required this.yearsExperience,
    required this.acceptingReferrals,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.departmentId,
    this.subSpecialty,
    this.credentials,
    this.registrationNo,
    this.consultationRoomId,
    this.retiredBy,
    this.retiredAt,
    this.retirementReason,
  });

  /// Validates and builds a new profile row.
  ///
  /// Directory administration is the only writer, so the local projection
  /// receives a complete row the first time and transitions thereafter.
  static Map<String, Object?> registerRow({
    required String tenantId,
    required String userId,
    required String facilityId,
    required String specialty,
    int yearsExperience = 0,
    bool acceptingReferrals = true,
    String? departmentId,
    String? subSpecialty,
    String? credentials,
    String? registrationNo,
    String? consultationRoomId,
    String profileId = '',
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (userId.isEmpty) {
      fieldErrors['user_id'] = 'Practitioner is required.';
    }
    if (facilityId.isEmpty) {
      fieldErrors['facility_id'] = 'Facility is required.';
    }
    if (specialty.trim().isEmpty) {
      fieldErrors['specialty'] = 'Specialty is required.';
    }
    if (yearsExperience < 0 || yearsExperience > 80) {
      fieldErrors['years_experience'] = 'Expected 0 to 80 years.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Directory entry failed validation.',
        fieldErrors: fieldErrors,
        code: 'practitioner_invalid',
      );
    }

    final String now = DateTime.now().toUtc().toIso8601String();
    final String? sub = subSpecialty?.trim();
    final String? creds = credentials?.trim();
    final String? reg = registrationNo?.trim();

    return <String, Object?>{
      if (profileId.isNotEmpty) 'id': profileId,
      'tenant_id': tenantId,
      'user_id': userId,
      'facility_id': facilityId,
      'department_id': departmentId,
      'specialty': specialty.trim(),
      'sub_specialty': sub == null || sub.isEmpty ? null : sub,
      'credentials': creds == null || creds.isEmpty ? null : creds,
      'registration_no': reg == null || reg.isEmpty ? null : reg,
      'years_experience': yearsExperience,
      'consultation_room_id': consultationRoomId,
      'accepting_referrals': acceptingReferrals ? 1 : 0,
      'status': PractitionerStatus.active.wireValue,
      'created_at': now,
      'updated_at': now,
    };
  }

  /// Materializes a profile from a local row.
  factory PractitionerProfile.fromRow(Map<String, Object?> row) {
    final Object? accepting = row['accepting_referrals'];
    return PractitionerProfile(
      id: row['id']! as String,
      tenantId: row['tenant_id']! as String,
      userId: row['user_id']! as String,
      facilityId: row['facility_id']! as String,
      specialty: row['specialty']! as String,
      yearsExperience: (row['years_experience'] as num?)?.toInt() ?? 0,
      acceptingReferrals: accepting is int ? accepting != 0 : accepting == true,
      status: PractitionerStatus.fromWire(row['status']! as String),
      createdAt: DateTime.parse(row['created_at']! as String).toUtc(),
      updatedAt: DateTime.parse(row['updated_at']! as String).toUtc(),
      departmentId: row['department_id'] as String?,
      subSpecialty: row['sub_specialty'] as String?,
      credentials: row['credentials'] as String?,
      registrationNo: row['registration_no'] as String?,
      consultationRoomId: row['consultation_room_id'] as String?,
      retiredBy: row['retired_by'] as String?,
      retiredAt: row['retired_at'] is String
          ? DateTime.parse(row['retired_at']! as String).toUtc()
          : null,
      retirementReason: row['retirement_reason'] as String?,
    );
  }

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// The linked app user.
  final String userId;

  /// Facility the practitioner practises from.
  final String facilityId;

  /// Owning department, when the facility organizes specialties that way.
  final String? departmentId;

  /// Primary specialty.
  final String specialty;

  /// Named sub-specialty, when declared.
  final String? subSpecialty;

  /// Qualifications summary, as the credentialing record describes it.
  final String? credentials;

  /// Professional registration number.
  final String? registrationNo;

  /// Years in practice since full registration.
  final int yearsExperience;

  /// Room they consult from, when it is a mapped floor-map room.
  final String? consultationRoomId;

  /// Whether new referrals are being accepted.
  final bool acceptingReferrals;

  /// Registry status.
  final PractitionerStatus status;

  /// Who retired the profile.
  final String? retiredBy;

  /// When it was retired.
  final DateTime? retiredAt;

  /// Why it was retired.
  final String? retirementReason;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// Whether the profile may be edited or retired.
  bool get isEditable => status.isEditable;
}

/// Column changes for a profile edit.
Map<String, Object?> practitionerChanges({
  required bool acceptingReferrals,
  String? subSpecialty,
  String? credentials,
  String? consultationRoomId,
  required String updatedBy,
}) => <String, Object?>{
  'accepting_referrals': acceptingReferrals ? 1 : 0,
  'sub_specialty': subSpecialty?.trim(),
  'credentials': credentials?.trim(),
  'consultation_room_id': consultationRoomId,
  'updated_at': DateTime.now().toUtc().toIso8601String(),
};

/// The full change set for retiring a practitioner, including who and why.
Map<String, Object?> practitionerRetirementChanges({
  required String retiredBy,
  required String reason,
}) {
  final String trimmed = reason.trim();
  if (trimmed.isEmpty) {
    throw const ValidationError(
      message: 'Retiring a practitioner requires a reason.',
      code: 'practitioner_retirement_reason_required',
    );
  }
  return <String, Object?>{
    'status': PractitionerStatus.retired.wireValue,
    'retired_by': retiredBy,
    'retired_at': DateTime.now().toUtc().toIso8601String(),
    'retirement_reason': trimmed,
    'accepting_referrals': 0,
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  };
}

/// One on-call rotation.
///
/// Rotations are append-only: an expiring rotation stays on the row it
/// describes rather than being overwritten, so historical cover is always
/// answerable.
@immutable
final class OnCallRotation {
  /// Creates a rotation.
  const OnCallRotation({
    required this.id,
    required this.tenantId,
    required this.practitionerId,
    required this.rotationType,
    required this.startsAt,
    required this.endsAt,
    required this.createdAt,
    required this.updatedAt,
    this.location,
    this.contactNote,
    this.recordedBy,
  });

  /// Validates and builds a rotation row.
  static Map<String, Object?> eventRow({
    required String tenantId,
    required String practitionerId,
    required OnCallType rotationType,
    required DateTime startsAt,
    required DateTime endsAt,
    required String recordedBy,
    String? location,
    String? contactNote,
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (practitionerId.isEmpty) {
      fieldErrors['practitioner_id'] = 'Practitioner is required.';
    }
    if (recordedBy.isEmpty) {
      fieldErrors['recorded_by'] = 'Recorder is required.';
    }
    if (!endsAt.isAfter(startsAt)) {
      fieldErrors['ends_at'] = 'Must end after it starts.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'On-call rotation failed validation.',
        fieldErrors: fieldErrors,
        code: 'practitioner_on_call_invalid',
      );
    }

    final String now = DateTime.now().toUtc().toIso8601String();
    final String? place = location?.trim();
    final String? note = contactNote?.trim();

    return <String, Object?>{
      'tenant_id': tenantId,
      'practitioner_id': practitionerId,
      'rotation_type': rotationType.wireValue,
      'starts_at': startsAt.toUtc().toIso8601String(),
      'ends_at': endsAt.toUtc().toIso8601String(),
      'location': place == null || place.isEmpty ? null : place,
      'contact_note': note == null || note.isEmpty ? null : note,
      'recorded_by': recordedBy,
      'created_at': now,
      'updated_at': now,
    };
  }

  /// Materializes a rotation from a local row.
  factory OnCallRotation.fromRow(Map<String, Object?> row) => OnCallRotation(
    id: row['id']! as String,
    tenantId: row['tenant_id']! as String,
    practitionerId: row['practitioner_id']! as String,
    rotationType: OnCallType.fromWire(row['rotation_type']! as String),
    startsAt: DateTime.parse(row['starts_at']! as String).toUtc(),
    endsAt: DateTime.parse(row['ends_at']! as String).toUtc(),
    createdAt: DateTime.parse(row['created_at']! as String).toUtc(),
    updatedAt: DateTime.parse(row['updated_at']! as String).toUtc(),
    location: row['location'] as String?,
    contactNote: row['contact_note'] as String?,
    recordedBy: row['recorded_by'] as String?,
  );

  /// Whether this rotation covers [moment].
  bool covers(DateTime moment) =>
      !moment.isBefore(startsAt) && moment.isBefore(endsAt);

  /// Whether this rotation overlaps [other].
  bool overlaps(OnCallRotation other) =>
      startsAt.isBefore(other.endsAt) && other.startsAt.isBefore(endsAt);

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// The covered profile.
  final String practitionerId;

  /// Kind of cover.
  final OnCallType rotationType;

  /// Cover start, UTC.
  final DateTime startsAt;

  /// Cover end, UTC.
  final DateTime endsAt;

  /// Where cover operates from, when relevant.
  final String? location;

  /// Reach note recorded with the rota.
  final String? contactNote;

  /// Who recorded the rotation.
  final String? recordedBy;

  final DateTime createdAt;
  final DateTime updatedAt;
}

/// Column changes for an on-call rotation edit-note update.
Map<String, Object?> onCallNoteChanges({required String contactNote}) =>
    <String, Object?>{
      'contact_note': contactNote.trim(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
