/// Problem-list and ambient-scribe use cases (Module 16).
///
/// Two rules run through this file. A problem is never deleted or reopened, only
/// resolved by an attributed note. And a scribe draft never becomes clinical
/// content on its own: it must be accepted section by section by a clinician
/// holding the AI review permission, and only while the encounter it targets is
/// still editable.
library;

import 'package:meta/meta.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/encounters/encounter.dart';
import 'package:nodex_hms/domain/encounters/encounter_repository.dart';
import 'package:nodex_hms/domain/encounters/problem_list.dart';
import 'package:nodex_hms/domain/encounters/problem_list_repository.dart';

/// Records a problem on a patient's longitudinal list.
///
/// Requires `encounter.write`: the problem list is part of the clinical
/// record, and an unwitnessed problem is a clinical claim.
final class RecordProblemUseCase {
  const RecordProblemUseCase({required this._repository});

  final ProblemListRepository _repository;

  /// Records the problem and returns its id.
  Future<String> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String patientId,
    required String problemCode,
    required String description,
    required String recordedBy,
    String? encounterId,
    DateTime? onsetDate,
  }) async {
    policy.require(NodexPermissions.encounterWrite);
    return _repository.recordProblem(
      ClinicalProblem.recordRow(
        tenantId: tenantId,
        patientId: patientId,
        problemCode: problemCode,
        description: description,
        recordedBy: recordedBy,
        encounterId: encounterId,
        onsetDate: onsetDate,
      ),
    );
  }
}

/// Closes an active problem by recording how it resolved.
///
/// Resolution is additive and irreversible: the row keeps its code, description
/// and recording clinician, because the value of a problem list is that it can
/// answer when a condition started and stopped.
final class ResolveProblemUseCase {
  const ResolveProblemUseCase({required this._repository});

  final ProblemListRepository _repository;

  /// Resolves [problem].
  Future<void> call({
    required AuthorizationPolicy policy,
    required ClinicalProblem problem,
    required String resolvedBy,
    required String resolutionNote,
  }) async {
    policy.require(NodexPermissions.encounterWrite);
    if (!problem.isActive) {
      throw const AuthorizationError(
        message: 'A resolved problem cannot be resolved again.',
        code: 'problem_already_resolved',
      );
    }
    await _repository.resolveProblem(
      problem.id,
      ClinicalProblem.resolutionChanges(
        resolvedBy: resolvedBy,
        resolutionNote: resolutionNote,
      ),
    );
  }
}

/// Records a dictation as a draft awaiting review.
///
/// Requires `encounter.write`. Recording the draft is part of authoring the
/// encounter; deciding whether to trust it is a separate decision gated on
/// `ai_output.review`.
final class RequestScribeDraftUseCase {
  const RequestScribeDraftUseCase({required this._repository});

  final ProblemListRepository _repository;

  /// Stores the draft and returns its id.
  Future<String> call({
    required AuthorizationPolicy policy,
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
  }) async {
    policy.require(NodexPermissions.encounterWrite);
    return _repository.recordDraft(
      ScribeDraft.draftRow(
        tenantId: tenantId,
        encounterId: encounterId,
        modelId: modelId,
        transcriptText: transcriptText,
        safetyDecision: safetyDecision,
        requestedBy: requestedBy,
        subjectiveNote: subjectiveNote,
        objectiveFindings: objectiveFindings,
        assessment: assessment,
        planDescription: planDescription,
        confidence: confidence,
      ),
    );
  }
}

/// The outcome of reviewing a scribe draft.
@immutable
final class ScribeReviewOutcome {
  const ScribeReviewOutcome.accepted({
    required this.draftId,
    required this.encounterId,
    required this.encounterChanges,
  }) : rejected = false,
       rejectionReason = null;

  const ScribeReviewOutcome.rejected({
    required this.draftId,
    required this.encounterId,
    required this.rejectionReason,
  }) : rejected = true,
       encounterChanges = const <String, Object?>{};

  /// The reviewed draft.
  final String draftId;

  /// The encounter the dictation targeted.
  final String encounterId;

  /// Whether the draft was rejected outright.
  final bool rejected;

  /// Why it was rejected.
  final String? rejectionReason;

  /// Sections to write into the encounter, empty on rejection.
  final Map<String, Object?> encounterChanges;
}

/// Reviews an ambient scribe draft.
///
/// Requires `ai_output.review`, not `encounter.write`: accepting machine
/// output is an AI-governance decision, and a clinician who may author an
/// encounter must not thereby be able to launder unreviewed dictation into the
/// record. The reviewed text of every accepted section is written through, so
/// the encounter stores what the clinician signed off rather than what the
/// model first produced.
final class ReviewScribeDraftUseCase {
  const ReviewScribeDraftUseCase({
    required this._repository,
    required this._encounters,
  });

  final ProblemListRepository _repository;
  final EncounterRepository _encounters;

  /// Reviews [draft] and, on acceptance, writes the accepted sections into the
  /// encounter.
  Future<ScribeReviewOutcome> call({
    required AuthorizationPolicy policy,
    required ScribeDraft draft,
    required String reviewedBy,
    Map<ScribeSection, String> acceptedText = const <ScribeSection, String>{},
    String? rejectionReason,
  }) async {
    policy.require(NodexPermissions.aiOutputReview);
    if (!draft.isPendingReview) {
      throw const AuthorizationError(
        message: 'This dictation has already been reviewed.',
        code: 'scribe_already_reviewed',
      );
    }

    // Review is a one-shot decision, so the stored state is re-read rather than
    // trusted from the caller: a stale copy claiming the draft is still pending
    // would otherwise let a second review through, and the server would then
    // have to be the thing that stopped it.
    final ScribeDraft? current = await _repository.draftById(draft.id);
    if (current == null) {
      throw const PersistenceError(
        message: 'The dictation is not held locally.',
        code: 'scribe_draft_not_found_locally',
      );
    }
    if (!current.isPendingReview) {
      throw const AuthorizationError(
        message: 'This dictation has already been reviewed.',
        code: 'scribe_already_reviewed',
      );
    }
    draft = current;
    final ScribeDraftStatus status = rejectionReason == null
        ? ScribeDraftStatus.accepted
        : ScribeDraftStatus.rejected;

    final Map<String, Object?> changes = ScribeDraft.reviewChanges(
      status: status,
      reviewedBy: reviewedBy,
      acceptedText: acceptedText,
      rejectionReason: rejectionReason,
    );
    await _repository.reviewDraft(draft.id, changes);

    if (status == ScribeDraftStatus.rejected) {
      return ScribeReviewOutcome.rejected(
        draftId: draft.id,
        encounterId: draft.encounterId,
        rejectionReason: rejectionReason!.trim(),
      );
    }

    // Acceptance touches the encounter, so it must be re-read: the draft may
    // have been recorded while the encounter was open and reviewed after it was
    // signed, and machine text must never reach a frozen record.
    final ClinicalEncounter? encounter = await _encounters.getEncounter(
      draft.encounterId,
    );
    if (encounter == null) {
      throw const PersistenceError(
        message: 'The encounter for this dictation is not held locally.',
        code: 'encounter_not_found_locally',
      );
    }
    if (!encounter.isEditable) {
      throw const AuthorizationError(
        message:
            'This encounter is already signed. Dictation text cannot be added '
            'to a signed record; record an amendment instead.',
        code: 'encounter_signed_frozen',
      );
    }
    final Map<String, Object?> encounterChanges = ClinicalEncounter.editChanges(
      subjectiveNote: _acceptedOrNull(acceptedText, ScribeSection.subjective),
      objectiveFindings: _acceptedOrNull(acceptedText, ScribeSection.objective),
      assessment: _acceptedOrNull(acceptedText, ScribeSection.assessment),
      planDescription: _acceptedOrNull(acceptedText, ScribeSection.plan),
    );
    await _encounters.updateEncounter(draft.encounterId, encounterChanges);
    return ScribeReviewOutcome.accepted(
      draftId: draft.id,
      encounterId: draft.encounterId,
      encounterChanges: encounterChanges,
    );
  }
}

String? _acceptedOrNull(Map<ScribeSection, String> accepted, ScribeSection s) {
  if (!accepted.containsKey(s)) return null;
  return accepted[s]!.trim();
}
