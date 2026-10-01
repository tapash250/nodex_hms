/// Problem-list and ambient-scribe entities (Module 16).
///
/// A problem is longitudinal: it outlives the encounter that first recorded it
/// and is closed by recording when it resolved, never by being deleted. A
/// scribe draft is machine output awaiting a human: it becomes clinical content
/// only when a clinician accepts it, field by field.
library;

import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';

/// Lifecycle of a problem on the patient's list.
enum ClinicalProblemStatus {
  /// The patient currently has the problem.
  active('active'),

  /// The problem has ended; the row stays as history.
  resolved('resolved');

  const ClinicalProblemStatus(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Display name.
  String get label => switch (this) {
    ClinicalProblemStatus.active => 'Active',
    ClinicalProblemStatus.resolved => 'Resolved',
  };

  /// Whether the problem is still on the active list.
  bool get isActive => this == ClinicalProblemStatus.active;

  /// Whether the problem has been closed.
  bool get isResolved => this == ClinicalProblemStatus.resolved;

  /// Parses a stored value, falling back to active.
  static ClinicalProblemStatus fromWire(String value) =>
      ClinicalProblemStatus.values.firstWhere(
        (ClinicalProblemStatus status) => status.wireValue == value,
        orElse: () => ClinicalProblemStatus.active,
      );
}

/// A problem on a patient's longitudinal list.
@immutable
final class ClinicalProblem {
  const ClinicalProblem({
    required this.id,
    required this.tenantId,
    required this.patientId,
    required this.problemCode,
    required this.description,
    required this.clinicalStatus,
    required this.recordedBy,
    this.encounterId,
    this.onsetDate,
    this.resolvedAt,
    this.resolutionNote,
    this.resolvedBy,
    this.createdAt,
    this.updatedAt,
  });

  factory ClinicalProblem.fromRow(Map<String, Object?> row) => ClinicalProblem(
    id: row['id']! as String,
    tenantId: row['tenant_id']! as String,
    patientId: row['patient_id']! as String,
    problemCode: row['problem_code']! as String,
    description: row['description']! as String,
    clinicalStatus: ClinicalProblemStatus.fromWire(
      row['clinical_status'] as String? ?? 'active',
    ),
    recordedBy: row['recorded_by']! as String,
    encounterId: row['encounter_id'] is String
        ? row['encounter_id']! as String
        : null,
    onsetDate: _date(row['onset_date']),
    resolvedAt: DateTime.tryParse(
      row['resolved_at'] is String ? row['resolved_at']! as String : '',
    ),
    resolutionNote: row['resolution_note'] is String
        ? row['resolution_note']! as String
        : null,
    resolvedBy: row['resolved_by'] is String
        ? row['resolved_by']! as String
        : null,
    createdAt: DateTime.tryParse(
      row['created_at'] is String ? row['created_at']! as String : '',
    ),
    updatedAt: DateTime.tryParse(
      row['updated_at'] is String ? row['updated_at']! as String : '',
    ),
  );

  /// Validated insert row for a newly recorded problem.
  static Map<String, Object?> recordRow({
    required String tenantId,
    required String patientId,
    required String problemCode,
    required String description,
    required String recordedBy,
    String? encounterId,
    DateTime? onsetDate,
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) fieldErrors['tenant_id'] = 'Tenant is required.';
    if (patientId.isEmpty) fieldErrors['patient_id'] = 'Patient is required.';
    if (problemCode.trim().isEmpty) {
      fieldErrors['problem_code'] = 'Problem code is required.';
    }
    if (description.trim().isEmpty) {
      fieldErrors['description'] = 'Description is required.';
    }
    if (recordedBy.isEmpty) {
      fieldErrors['recorded_by'] = 'The recording clinician is required.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'The problem could not be recorded.',
        fieldErrors: fieldErrors,
        code: 'problem_invalid',
      );
    }
    final DateTime now = DateTime.now().toUtc();
    return <String, Object?>{
      'tenant_id': tenantId,
      'patient_id': patientId,
      'encounter_id': encounterId,
      'problem_code': problemCode.trim(),
      'description': description.trim(),
      'clinical_status': ClinicalProblemStatus.active.wireValue,
      'onset_date': onsetDate == null
          ? null
          : '${onsetDate.toUtc().year.toString().padLeft(4, '0')}-'
                '${onsetDate.toUtc().month.toString().padLeft(2, '0')}-'
                '${onsetDate.toUtc().day.toString().padLeft(2, '0')}',
      'recorded_by': recordedBy,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    };
  }

  /// Row identifier.
  final String id;

  /// Owning tenant.
  final String tenantId;

  /// Patient the problem belongs to.
  final String patientId;

  /// Coded term, for example an ICD or SNOMED code.
  final String problemCode;

  /// Clinician-readable description.
  final String description;

  /// Whether the problem is still active.
  final ClinicalProblemStatus clinicalStatus;

  /// Encounter the problem was first recorded against, if any.
  final String? encounterId;

  /// When the problem began, when known.
  final DateTime? onsetDate;

  /// When the problem resolved.
  final DateTime? resolvedAt;

  /// Why or how it resolved.
  final String? resolutionNote;

  /// Who recorded the problem.
  final String recordedBy;

  /// Who closed it.
  final String? resolvedBy;

  /// Creation time.
  final DateTime? createdAt;

  /// Last update time.
  final DateTime? updatedAt;

  /// Whether the problem is still on the active list.
  bool get isActive => clinicalStatus == ClinicalProblemStatus.active;

  /// Decodes a local or replicated row.

  /// Validated resolution changes.
  ///
  /// Resolution is additive: the problem keeps its code, description and
  /// recording clinician, and gains an end date and an attributed note.
  static Map<String, Object?> resolutionChanges({
    required String resolvedBy,
    required String resolutionNote,
  }) {
    if (resolvedBy.isEmpty) {
      throw const ValidationError(
        message: 'A problem must be resolved by a clinician.',
        fieldErrors: <String, String>{'resolved_by': 'Resolver is required.'},
        code: 'problem_resolver_required',
      );
    }
    if (resolutionNote.trim().isEmpty) {
      throw const ValidationError(
        message: 'A problem must say how it resolved.',
        fieldErrors: <String, String>{
          'resolution_note': 'A resolution note is required.',
        },
        code: 'problem_resolution_note_required',
      );
    }
    final DateTime now = DateTime.now().toUtc();
    return <String, Object?>{
      'clinical_status': ClinicalProblemStatus.resolved.wireValue,
      'resolved_at': now.toIso8601String(),
      'resolved_by': resolvedBy,
      'resolution_note': resolutionNote.trim(),
      'updated_at': now.toIso8601String(),
    };
  }
}

/// Review state of an ambient scribe draft.
enum ScribeDraftStatus {
  /// Dictated and structured, awaiting a clinician.
  pendingReview('pending_review'),

  /// A clinician accepted at least one section into the encounter.
  accepted('accepted'),

  /// A clinician rejected the whole draft.
  rejected('rejected');

  const ScribeDraftStatus(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Display name.
  String get label => switch (this) {
    ScribeDraftStatus.pendingReview => 'Awaiting review',
    ScribeDraftStatus.accepted => 'Accepted',
    ScribeDraftStatus.rejected => 'Rejected',
  };

  /// Whether the draft has already been decided.
  bool get isReviewed => this != ScribeDraftStatus.pendingReview;

  /// Parses a stored value, falling back to pending review.
  static ScribeDraftStatus fromWire(String value) =>
      ScribeDraftStatus.values.firstWhere(
        (ScribeDraftStatus status) => status.wireValue == value,
        orElse: () => ScribeDraftStatus.pendingReview,
      );
}

/// The SOAP sections a scribe produced, each of which a clinician accepts or
/// edits independently.
enum ScribeSection {
  subjective('subjective_note', 'Subjective'),
  objective('objective_findings', 'Objective'),
  assessment('assessment', 'Assessment'),
  plan('plan_description', 'Plan');

  const ScribeSection(this.column, this.label);

  /// Column on `encounter_scribe_drafts` holding this section.
  final String column;

  /// Display name.
  final String label;
}

/// Machine-produced note content waiting for a clinician.
@immutable
final class ScribeDraft {
  const ScribeDraft({
    required this.id,
    required this.tenantId,
    required this.encounterId,
    required this.modelId,
    required this.transcriptText,
    required this.safetyDecision,
    required this.status,
    required this.requestedBy,
    this.subjectiveNote,
    this.objectiveFindings,
    this.assessment,
    this.planDescription,
    this.confidence,
    this.reviewedBy,
    this.reviewedAt,
    this.rejectionReason,
    this.acceptedSections = const <ScribeSection>{},
    this.createdAt,
    this.updatedAt,
  });

  factory ScribeDraft.fromRow(Map<String, Object?> row) => ScribeDraft(
    id: row['id']! as String,
    tenantId: row['tenant_id']! as String,
    encounterId: row['encounter_id']! as String,
    modelId: row['model_id']! as String,
    transcriptText: row['transcript_text']! as String,
    safetyDecision: row['safety_decision']! as String,
    status: ScribeDraftStatus.fromWire(
      row['status'] as String? ?? 'pending_review',
    ),
    requestedBy: row['requested_by']! as String,
    subjectiveNote: row['subjective_note'] is String
        ? row['subjective_note']! as String
        : null,
    objectiveFindings: row['objective_findings'] is String
        ? row['objective_findings']! as String
        : null,
    assessment: row['assessment'] is String
        ? row['assessment']! as String
        : null,
    planDescription: row['plan_description'] is String
        ? row['plan_description']! as String
        : null,
    confidence: (row['confidence'] as num?)?.toDouble(),
    reviewedBy: row['reviewed_by'] is String
        ? row['reviewed_by']! as String
        : null,
    reviewedAt: DateTime.tryParse(
      row['reviewed_at'] is String ? row['reviewed_at']! as String : '',
    ),
    rejectionReason: row['rejection_reason'] is String
        ? row['rejection_reason']! as String
        : null,
    acceptedSections: _decodeSections(row['accepted_fields']),
    createdAt: DateTime.tryParse(
      row['created_at'] is String ? row['created_at']! as String : '',
    ),
    updatedAt: DateTime.tryParse(
      row['updated_at'] is String ? row['updated_at']! as String : '',
    ),
  );

  /// Validated insert row for a fresh dictation.
  static Map<String, Object?> draftRow({
    required String tenantId,
    required String encounterId,
    required String modelId,
    required String transcriptText,
    required String safetyDecision,
    required String requestedBy,
    String? subjectiveNote,
    String? objectiveFindings,
    String? assessment,
    String? planDescription,
    double? confidence,
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) fieldErrors['tenant_id'] = 'Tenant is required.';
    if (encounterId.isEmpty) {
      fieldErrors['encounter_id'] = 'Encounter is required.';
    }
    if (modelId.trim().isEmpty) {
      fieldErrors['model_id'] = 'The model identifier is required.';
    }
    if (transcriptText.trim().isEmpty) {
      fieldErrors['transcript_text'] = 'The transcript is required.';
    }
    if (safetyDecision.trim().isEmpty) {
      fieldErrors['safety_decision'] = 'A safety decision is required.';
    }
    if (requestedBy.isEmpty) {
      fieldErrors['requested_by'] = 'The requesting clinician is required.';
    }
    if (confidence != null && (confidence < 0 || confidence > 1)) {
      fieldErrors['confidence'] = 'Confidence must be between 0 and 1.';
    }
    final bool nothingStructured =
        (subjectiveNote == null || subjectiveNote.trim().isEmpty) &&
        (objectiveFindings == null || objectiveFindings.trim().isEmpty) &&
        (assessment == null || assessment.trim().isEmpty) &&
        (planDescription == null || planDescription.trim().isEmpty);
    if (nothingStructured) {
      fieldErrors['structured_output'] =
          'The model produced no note content to review.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'The dictation could not be recorded.',
        fieldErrors: fieldErrors,
        code: 'scribe_draft_invalid',
      );
    }
    final DateTime now = DateTime.now().toUtc();
    return <String, Object?>{
      'tenant_id': tenantId,
      'encounter_id': encounterId,
      'model_id': modelId.trim(),
      'transcript_text': transcriptText.trim(),
      'subjective_note': _nullIfBlank(subjectiveNote),
      'objective_findings': _nullIfBlank(objectiveFindings),
      'assessment': _nullIfBlank(assessment),
      'plan_description': _nullIfBlank(planDescription),
      'confidence': confidence,
      'safety_decision': safetyDecision.trim(),
      'status': ScribeDraftStatus.pendingReview.wireValue,
      'requested_by': requestedBy,
      'accepted_fields': const <String>[],
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    };
  }

  /// Row identifier.
  final String id;

  /// Owning tenant.
  final String tenantId;

  /// Encounter the dictation targets.
  final String encounterId;

  /// Model that produced the draft.
  final String modelId;

  /// Raw transcription of the clinician's dictation.
  final String transcriptText;

  /// Safety verdict returned alongside the draft.
  final String safetyDecision;

  /// Review state.
  final ScribeDraftStatus status;

  /// Who requested the dictation.
  final String requestedBy;

  /// Subjective section.
  final String? subjectiveNote;

  /// Objective section.
  final String? objectiveFindings;

  /// Assessment section.
  final String? assessment;

  /// Plan section.
  final String? planDescription;

  /// Model confidence, when reported.
  final double? confidence;

  /// Who reviewed the draft.
  final String? reviewedBy;

  /// When the draft was reviewed.
  final DateTime? reviewedAt;

  /// Why the draft was rejected.
  final String? rejectionReason;

  /// Sections the clinician accepted.
  final Set<ScribeSection> acceptedSections;

  /// Creation time.
  final DateTime? createdAt;

  /// Last update time.
  final DateTime? updatedAt;

  /// Whether the draft is still awaiting a decision.
  bool get isPendingReview => status == ScribeDraftStatus.pendingReview;

  /// The text of one section, or null when the model produced nothing.
  String? sectionText(ScribeSection section) => switch (section) {
    ScribeSection.subjective => subjectiveNote,
    ScribeSection.objective => objectiveFindings,
    ScribeSection.assessment => assessment,
    ScribeSection.plan => planDescription,
  };

  /// Decodes a local or replicated row.

  /// Validated review changes.
  ///
  /// Acceptance records which sections the clinician kept and carries the
  /// reviewed text of each, so the record shows what was signed off rather than
  /// what the model first produced. Rejection requires a reason.
  static Map<String, Object?> reviewChanges({
    required ScribeDraftStatus status,
    required String reviewedBy,
    required Map<ScribeSection, String> acceptedText,
    String? rejectionReason,
  }) {
    if (status == ScribeDraftStatus.pendingReview) {
      throw const ValidationError(
        message: 'A draft is reviewed as accepted or rejected.',
        fieldErrors: <String, String>{'status': 'Choose accept or reject.'},
        code: 'scribe_review_invalid',
      );
    }
    if (reviewedBy.isEmpty) {
      throw const ValidationError(
        message: 'A scribe draft must be reviewed by a clinician.',
        fieldErrors: <String, String>{'reviewed_by': 'Reviewer is required.'},
        code: 'scribe_reviewer_required',
      );
    }
    final Map<String, String> fieldErrors = <String, String>{};
    if (status == ScribeDraftStatus.accepted) {
      if (acceptedText.isEmpty) {
        fieldErrors['accepted_sections'] =
            'Accept at least one section, or reject the draft.';
      }
      if (acceptedText.values.any((String text) => text.trim().isEmpty)) {
        fieldErrors['accepted_sections'] =
            'An accepted section cannot be empty.';
      }
    } else if (rejectionReason == null || rejectionReason.trim().isEmpty) {
      fieldErrors['rejection_reason'] = 'A rejection needs a reason.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'The scribe review could not be recorded.',
        fieldErrors: fieldErrors,
        code: 'scribe_review_invalid',
      );
    }
    final DateTime now = DateTime.now().toUtc();
    return <String, Object?>{
      'status': status.wireValue,
      'reviewed_by': reviewedBy,
      'reviewed_at': now.toIso8601String(),
      'accepted_fields': status == ScribeDraftStatus.accepted
          ? (acceptedText.keys
                .map((ScribeSection s) => s.column)
                .toList(growable: false)
              ..sort())
          : const <String>[],
      'rejection_reason': status == ScribeDraftStatus.rejected
          ? rejectionReason!.trim()
          : null,
      // The reviewed text replaces the machine text for every accepted
      // section, so the stored draft is exactly what the clinician signed off.
      for (final MapEntry<ScribeSection, String> entry in acceptedText.entries)
        entry.key.column: entry.value.trim(),
      'updated_at': now.toIso8601String(),
    };
  }
}

String? _nullIfBlank(String? value) =>
    value == null || value.trim().isEmpty ? null : value.trim();

DateTime? _date(Object? value) {
  if (value is! String || value.isEmpty) return null;
  // A calendar date carries no timezone, so it is read as UTC. Left to
  // DateTime.tryParse it would be read as device-local time, and the same
  // problem would land on a different instant depending on where the clinician
  // happened to be when the device parsed it.
  final DateTime? parsed = DateTime.tryParse(value);
  if (parsed == null) return null;
  return parsed.isUtc
      ? parsed
      : DateTime.utc(parsed.year, parsed.month, parsed.day);
}

Set<ScribeSection> _decodeSections(Object? value) {
  final List<String> names;
  if (value is List) {
    names = value.map((Object? item) => '$item').toList(growable: false);
  } else if (value is String && value.isNotEmpty) {
    try {
      final Object? decoded = jsonDecode(value);
      names = decoded is List
          ? decoded.map((Object? item) => '$item').toList(growable: false)
          : const <String>[];
    } on FormatException {
      return const <ScribeSection>{};
    }
  } else {
    return const <ScribeSection>{};
  }
  final Set<ScribeSection> sections = <ScribeSection>{};
  for (final ScribeSection section in ScribeSection.values) {
    if (names.contains(section.column)) sections.add(section);
  }
  return sections;
}
