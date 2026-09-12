/// Clinical encounter domain entities (Module 16, Longitudinal EMR/EHR).
///
/// The defining invariant is the signature gate. An encounter is editable while
/// in progress and frozen the moment it is signed. Corrections are recorded as
/// [EncounterAmendment] rows; the signed encounter itself is never rewritten.
///
/// This file mirrors the server rules rather than inventing its own: the same
/// transition set, the same separation of signature and status, and the same
/// requirement that an amendment carry a reason.
library;

import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';

/// Kind of encounter, matching `clinical_encounters.encounter_type`.
enum EncounterType {
  /// Outpatient clinic visit.
  outpatient('outpatient'),

  /// Inpatient admission encounter.
  inpatient('inpatient'),

  /// Emergency department encounter.
  emergency('emergency'),

  /// Telemedicine encounter.
  telehealth('telehealth');

  const EncounterType(this.wireValue);

  /// Value persisted in `clinical_encounters.encounter_type`.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    EncounterType.outpatient => 'Outpatient',
    EncounterType.inpatient => 'Inpatient',
    EncounterType.emergency => 'Emergency',
    EncounterType.telehealth => 'Telehealth',
  };

  /// Parses a stored value, or null when unrecognised.
  static EncounterType? fromWire(String value) {
    for (final EncounterType type in EncounterType.values) {
      if (type.wireValue == value) {
        return type;
      }
    }
    return null;
  }
}

/// Lifecycle status of an encounter.
///
/// The set is closed and the transitions are one-way. `signed_and_locked` is
/// terminal except for the move to `amended`, which accompanies an amendment.
enum EncounterStatus {
  /// Booked or expected, not yet documented.
  planned('planned'),

  /// Being documented.
  inProgress('in_progress'),

  /// Signed by the attending clinician and frozen.
  signedAndLocked('signed_and_locked'),

  /// A signed encounter that carries at least one amendment.
  amended('amended');

  const EncounterStatus(this.wireValue);

  /// Value persisted in `clinical_encounters.status`.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    EncounterStatus.planned => 'Planned',
    EncounterStatus.inProgress => 'In progress',
    EncounterStatus.signedAndLocked => 'Signed and locked',
    EncounterStatus.amended => 'Amended',
  };

  /// Whether content may still be edited.
  bool get isEditable =>
      this == EncounterStatus.planned || this == EncounterStatus.inProgress;

  /// Whether the encounter is signed (and therefore frozen).
  bool get isSigned =>
      this == EncounterStatus.signedAndLocked ||
      this == EncounterStatus.amended;

  /// Parses a stored value, defaulting to [inProgress].
  static EncounterStatus fromWire(String value) {
    for (final EncounterStatus status in EncounterStatus.values) {
      if (status.wireValue == value) {
        return status;
      }
    }
    return EncounterStatus.inProgress;
  }
}

/// A coded diagnosis attached to an encounter.
@immutable
final class EncounterDiagnosis {
  /// Creates a coded diagnosis.
  const EncounterDiagnosis({required this.code, required this.description});

  /// Code system value, for example an ICD-10 code.
  final String code;

  /// Human-readable description.
  final String description;

  /// Serialises for the `diagnoses` JSON column.
  Map<String, Object?> toJson() => <String, Object?>{
    'code': code,
    'description': description,
  };

  /// Parses one entry from the `diagnoses` JSON column.
  static EncounterDiagnosis fromJson(Map<String, Object?> json) =>
      EncounterDiagnosis(
        code: json['code']! as String,
        description: json['description']! as String,
      );
}

/// A clinical encounter.
@immutable
final class ClinicalEncounter {
  /// Creates an encounter. Prefer [ClinicalEncounter.draftRow] for new records.
  const ClinicalEncounter({
    required this.id,
    required this.tenantId,
    required this.patientId,
    required this.attendingPhysicianId,
    required this.encounterType,
    required this.status,
    required this.diagnoses,
    this.subjectiveNote,
    this.objectiveFindings,
    this.assessment,
    this.planDescription,
    this.signedAt,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
  });

  /// Materialises an encounter from a local database row.
  factory ClinicalEncounter.fromRow(Map<String, Object?> row) {
    final Object? rawDiagnoses = row['diagnoses'];
    final List<EncounterDiagnosis> diagnoses;
    if (rawDiagnoses is List<Object?>) {
      diagnoses = rawDiagnoses
          .whereType<Map<Object?, Object?>>()
          .map(
            (Map<Object?, Object?> d) =>
                EncounterDiagnosis.fromJson(d.cast<String, Object?>()),
          )
          .toList(growable: false);
    } else if (rawDiagnoses is String && rawDiagnoses.trim().isNotEmpty) {
      diagnoses = _decodeDiagnosesString(rawDiagnoses);
    } else {
      diagnoses = const <EncounterDiagnosis>[];
    }

    return ClinicalEncounter(
      id: row['id']! as String,
      tenantId: row['tenant_id']! as String,
      patientId: row['patient_id']! as String,
      attendingPhysicianId: row['attending_physician_id']! as String,
      encounterType:
          EncounterType.fromWire(row['encounter_type']! as String) ??
          EncounterType.outpatient,
      status: EncounterStatus.fromWire(row['status']! as String),
      diagnoses: diagnoses,
      subjectiveNote: row['subjective_note'] as String?,
      objectiveFindings: row['objective_findings'] as String?,
      assessment: row['assessment'] as String?,
      planDescription: row['plan_description'] as String?,
      signedAt: row['signed_at'] == null
          ? null
          : DateTime.parse(row['signed_at']! as String),
      createdBy: row['created_by'] as String?,
      createdAt: row['created_at'] == null
          ? null
          : DateTime.parse(row['created_at']! as String),
      updatedAt: row['updated_at'] == null
          ? null
          : DateTime.parse(row['updated_at']! as String),
    );
  }

  /// Validates draft input and builds the local row for insertion.
  ///
  /// An encounter starts in [EncounterStatus.inProgress] with no signature: a
  /// record cannot be created already signed, because signing is a deliberate
  /// act by an identified clinician at a recorded time.
  static Map<String, Object?> draftRow({
    required String tenantId,
    required String patientId,
    required String attendingPhysicianId,
    required EncounterType encounterType,
    required String createdBy,
    String? subjectiveNote,
    String? objectiveFindings,
    String? assessment,
    String? planDescription,
    List<EncounterDiagnosis> diagnoses = const <EncounterDiagnosis>[],
  }) {
    final Map<String, String> fieldErrors = <String, String>{};

    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'A tenant is required.';
    }
    if (patientId.isEmpty) {
      fieldErrors['patient_id'] = 'A patient is required.';
    }
    if (attendingPhysicianId.isEmpty) {
      fieldErrors['attending_physician_id'] =
          'An attending clinician is required.';
    }

    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'The encounter could not be created.',
        fieldErrors: fieldErrors,
        code: 'encounter_draft_invalid',
      );
    }

    final DateTime now = DateTime.now().toUtc();
    return <String, Object?>{
      'tenant_id': tenantId,
      'patient_id': patientId,
      'attending_physician_id': attendingPhysicianId,
      'encounter_type': encounterType.wireValue,
      'status': EncounterStatus.inProgress.wireValue,
      'subjective_note': _clean(subjectiveNote),
      'objective_findings': _clean(objectiveFindings),
      'assessment': _clean(assessment),
      'plan_description': _clean(planDescription),
      'diagnoses': _encodeDiagnoses(diagnoses),
      'signed_at': null,
      'created_by': createdBy,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    };
  }

  /// Builds the update map for an edit to an unsigned encounter.
  ///
  /// Signing is a separate operation ([signChanges]) because it is a different
  /// clinical act: documenting an assessment and taking responsibility for it
  /// are not the same decision.
  static Map<String, Object?> editChanges({
    String? subjectiveNote,
    String? objectiveFindings,
    String? assessment,
    String? planDescription,
    List<EncounterDiagnosis>? diagnoses,
  }) {
    final Map<String, Object?> changes = <String, Object?>{};
    if (subjectiveNote != null) {
      changes['subjective_note'] = _clean(subjectiveNote);
    }
    if (objectiveFindings != null) {
      changes['objective_findings'] = _clean(objectiveFindings);
    }
    if (assessment != null) {
      changes['assessment'] = _clean(assessment);
    }
    if (planDescription != null) {
      changes['plan_description'] = _clean(planDescription);
    }
    if (diagnoses != null) {
      changes['diagnoses'] = _encodeDiagnoses(diagnoses);
    }
    changes['updated_at'] = DateTime.now().toUtc().toIso8601String();
    return changes;
  }

  /// Builds the update map that signs and freezes an encounter.
  static Map<String, Object?> signChanges() {
    final DateTime now = DateTime.now().toUtc();
    return <String, Object?>{
      'status': EncounterStatus.signedAndLocked.wireValue,
      'signed_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    };
  }

  /// Database identifier.
  final String id;

  /// Tenant this encounter belongs to.
  final String tenantId;

  /// Patient the encounter concerns.
  final String patientId;

  /// Attending clinician responsible for the encounter.
  final String attendingPhysicianId;

  /// Kind of encounter.
  final EncounterType encounterType;

  /// Lifecycle status.
  final EncounterStatus status;

  /// Coded diagnoses.
  final List<EncounterDiagnosis> diagnoses;

  /// Subjective SOAP field.
  final String? subjectiveNote;

  /// Objective SOAP field.
  final String? objectiveFindings;

  /// Assessment SOAP field.
  final String? assessment;

  /// Plan SOAP field.
  final String? planDescription;

  /// When the encounter was signed, if it has been.
  final DateTime? signedAt;

  /// Principal that created the encounter.
  final String? createdBy;

  /// When the encounter was created.
  final DateTime? createdAt;

  /// When the encounter was last modified.
  final DateTime? updatedAt;

  /// Whether content may still be edited.
  bool get isEditable => status.isEditable;

  /// Whether the encounter is signed and frozen.
  bool get isSigned => status.isSigned;

  static String? _clean(String? value) {
    if (value == null) {
      return null;
    }
    final String trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static String _encodeDiagnoses(List<EncounterDiagnosis> diagnoses) =>
      jsonEncode(<Object?>[
        for (final EncounterDiagnosis d in diagnoses) d.toJson(),
      ]);

  static List<EncounterDiagnosis> _decodeDiagnosesString(String raw) {
    // A malformed value yields no diagnoses rather than throwing: a display
    // screen must not crash on stored data.
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List<Object?>) {
        return const <EncounterDiagnosis>[];
      }
      return decoded
          .whereType<Map<String, Object?>>()
          .map(EncounterDiagnosis.fromJson)
          .toList(growable: false);
    } on FormatException {
      return const <EncounterDiagnosis>[];
    }
  }
}

/// An append-only correction to a signed encounter.
@immutable
final class EncounterAmendment {
  /// Creates an amendment.
  const EncounterAmendment({
    required this.id,
    required this.tenantId,
    required this.encounterId,
    required this.amendmentType,
    required this.reason,
    required this.amendedBy,
    required this.createdAt,
    this.fieldChanges = const <String, Object?>{},
  });

  /// Materialises an amendment from a local database row.
  ///
  /// `field_changes` travels as encoded text through the local projection; a
  /// malformed value yields an empty map rather than throwing.
  factory EncounterAmendment.fromRow(Map<String, Object?> row) =>
      EncounterAmendment(
        id: row['id']! as String,
        tenantId: row['tenant_id']! as String,
        encounterId: row['encounter_id']! as String,
        amendmentType: row['amendment_type']! as String,
        reason: row['reason']! as String,
        amendedBy: row['amended_by']! as String,
        createdAt: DateTime.parse(row['created_at']! as String),
        fieldChanges: _decodeFieldChanges(row['field_changes']),
      );

  /// Decodes the encoded `field_changes` value from a local row.
  static Map<String, Object?> _decodeFieldChanges(Object? rawChanges) {
    if (rawChanges is Map<Object?, Object?>) {
      return rawChanges.cast<String, Object?>();
    }
    if (rawChanges is String && rawChanges.trim().isNotEmpty) {
      try {
        final Object? decoded = jsonDecode(rawChanges);
        if (decoded is Map<String, Object?>) {
          return decoded;
        }
      } on FormatException {
        // Fall through to the empty map below.
      }
    }
    return const <String, Object?>{};
  }

  /// Validates an amendment and builds the local row for insertion.
  ///
  /// `field_changes` is encoded here so the returned map is insert-ready: the
  /// local column is TEXT and the server column is jsonb, and the encoded form
  /// satisfies both. [EncounterAmendment.fromRow] decodes it back.
  static Map<String, Object?> amendmentRow({
    required String tenantId,
    required String encounterId,
    required String reason,
    required String amendedBy,
    required Map<String, Object?> fieldChanges,
    String amendmentType = 'correction',
  }) {
    if (reason.trim().isEmpty) {
      throw const ValidationError(
        message: 'An amendment requires a reason.',
        fieldErrors: <String, String>{
          'reason': 'Enter why the signed record is being amended.',
        },
        code: 'amendment_reason_required',
      );
    }
    if (fieldChanges.isEmpty) {
      throw const ValidationError(
        message: 'An amendment must change at least one field.',
        fieldErrors: <String, String>{'field_changes': 'Nothing was changed.'},
        code: 'amendment_empty',
      );
    }

    return <String, Object?>{
      'tenant_id': tenantId,
      'encounter_id': encounterId,
      'amendment_type': amendmentType,
      'reason': reason.trim(),
      'field_changes': jsonEncode(fieldChanges),
      'amended_by': amendedBy,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  /// Database identifier.
  final String id;

  /// Tenant this amendment belongs to.
  final String tenantId;

  /// The signed encounter being amended.
  final String encounterId;

  /// `correction` or `addendum`.
  final String amendmentType;

  /// Why the amendment was made. Required.
  final String reason;

  /// Principal that made the amendment.
  final String amendedBy;

  /// When the amendment was recorded.
  final DateTime createdAt;

  /// Fields changed, for display and audit.
  final Map<String, Object?> fieldChanges;
}
