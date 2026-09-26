/// Physiotherapy workflow use cases (Module 20).
///
/// Each write gates on the authorization policy before touching the
/// repository. Session transitions require `physio_session.write`, exercise
/// regimens require `physio_exercise.write`, and recovery notes require
/// `physio_note.write`.
library;

import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/physio/physio.dart';
import 'package:nodex_hms/domain/physio/physio_repository.dart';
import 'package:uuid/uuid.dart';

/// Schedules a physiotherapy session. Requires `physio_session.write`.
final class SchedulePhysioSessionUseCase {
  SchedulePhysioSessionUseCase({required this._repository});

  final PhysioRepository _repository;

  Future<PhysioSession> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String patientId,
    required String physiotherapistId,
    required String sessionCode,
    required PhysioSessionType sessionType,
    required String bodyArea,
    required DateTime scheduledAt,
    String? encounterId,
    String? equipmentUsed,
  }) async {
    policy.require(NodexPermissions.physioSessionWrite);
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (patientId.isEmpty) {
      fieldErrors['patient_id'] = 'Patient is required.';
    }
    if (physiotherapistId.isEmpty) {
      fieldErrors['physiotherapist_id'] = 'Physiotherapist is required.';
    }
    if (sessionCode.trim().isEmpty) {
      fieldErrors['session_code'] = 'Session code is required.';
    }
    if (bodyArea.trim().isEmpty) {
      fieldErrors['body_area'] = 'Body area is required.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Physiotherapy session failed validation.',
        fieldErrors: fieldErrors,
        code: 'physio_session_invalid',
      );
    }
    final DateTime now = DateTime.now().toUtc();
    final String? equipment = equipmentUsed?.trim();
    final PhysioSession session = PhysioSession(
      id: const Uuid().v4(),
      tenantId: tenantId,
      patientId: patientId,
      encounterId: encounterId,
      physiotherapistId: physiotherapistId,
      sessionCode: sessionCode.trim(),
      sessionType: sessionType,
      bodyArea: bodyArea.trim(),
      status: PhysioSessionStatus.scheduled,
      scheduledAt: scheduledAt.toUtc(),
      equipmentUsed: equipment == null || equipment.isEmpty ? null : equipment,
      createdAt: now,
      updatedAt: now,
    );
    return _repository.upsertSession(session);
  }
}

/// Starts a scheduled session. Requires `physio_session.write`.
final class StartPhysioSessionUseCase {
  StartPhysioSessionUseCase({required this._repository});

  final PhysioRepository _repository;

  Future<PhysioSession> call({
    required AuthorizationPolicy policy,
    required PhysioSession session,
  }) async {
    policy.require(NodexPermissions.physioSessionWrite);
    if (!session.isScheduled) {
      throw const AuthorizationError(
        message: 'Only scheduled physiotherapy sessions can be started.',
        code: 'physio_session_not_scheduled',
      );
    }
    final DateTime now = DateTime.now().toUtc();
    return _repository.upsertSession(
      PhysioSession(
        id: session.id,
        tenantId: session.tenantId,
        patientId: session.patientId,
        encounterId: session.encounterId,
        physiotherapistId: session.physiotherapistId,
        sessionCode: session.sessionCode,
        sessionType: session.sessionType,
        bodyArea: session.bodyArea,
        status: PhysioSessionStatus.inProgress,
        scheduledAt: session.scheduledAt,
        startedAt: now,
        equipmentUsed: session.equipmentUsed,
        createdAt: session.createdAt,
        updatedAt: now,
      ),
    );
  }
}

/// Completes an in-progress session. Requires `physio_session.write`.
final class CompletePhysioSessionUseCase {
  CompletePhysioSessionUseCase({required this._repository});

  final PhysioRepository _repository;

  Future<PhysioSession> call({
    required AuthorizationPolicy policy,
    required PhysioSession session,
  }) async {
    policy.require(NodexPermissions.physioSessionWrite);
    if (!session.isRunning) {
      throw const AuthorizationError(
        message: 'Only in-progress physiotherapy sessions can be completed.',
        code: 'physio_session_not_started',
      );
    }
    final DateTime now = DateTime.now().toUtc();
    return _repository.upsertSession(
      PhysioSession(
        id: session.id,
        tenantId: session.tenantId,
        patientId: session.patientId,
        encounterId: session.encounterId,
        physiotherapistId: session.physiotherapistId,
        sessionCode: session.sessionCode,
        sessionType: session.sessionType,
        bodyArea: session.bodyArea,
        status: PhysioSessionStatus.completed,
        scheduledAt: session.scheduledAt,
        startedAt: session.startedAt,
        completedAt: now,
        equipmentUsed: session.equipmentUsed,
        createdAt: session.createdAt,
        updatedAt: now,
      ),
    );
  }
}

/// Cancels a session with a reason. Requires `physio_session.write`.
final class CancelPhysioSessionUseCase {
  CancelPhysioSessionUseCase({required this._repository});

  final PhysioRepository _repository;

  Future<PhysioSession> call({
    required AuthorizationPolicy policy,
    required PhysioSession original,
    required String reason,
  }) async {
    policy.require(NodexPermissions.physioSessionWrite);
    if (original.isTerminal) {
      throw const AuthorizationError(
        message: 'Closed physiotherapy sessions cannot be cancelled.',
        code: 'physio_session_closed',
      );
    }
    if (reason.trim().isEmpty) {
      throw const ValidationError(
        message: 'Cancelling a physiotherapy session requires a reason.',
        code: 'physio_cancellation_reason_required',
      );
    }
    final DateTime now = DateTime.now().toUtc();
    return _repository.upsertSession(
      PhysioSession(
        id: original.id,
        tenantId: original.tenantId,
        patientId: original.patientId,
        encounterId: original.encounterId,
        physiotherapistId: original.physiotherapistId,
        sessionCode: original.sessionCode,
        sessionType: original.sessionType,
        bodyArea: original.bodyArea,
        status: PhysioSessionStatus.cancelled,
        scheduledAt: original.scheduledAt,
        startedAt: original.startedAt,
        cancelledAt: now,
        cancellationReason: reason.trim(),
        equipmentUsed: original.equipmentUsed,
        createdAt: original.createdAt,
        updatedAt: now,
      ),
    );
  }
}

/// Prescribes an exercise regimen. Requires `physio_exercise.write`.
final class PrescribePhysioExerciseUseCase {
  PrescribePhysioExerciseUseCase({required this._repository});

  final PhysioRepository _repository;

  Future<PhysioExercisePlan> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String patientId,
    required String prescribedBy,
    required String exerciseName,
    required int setsCount,
    required int repsCount,
    required int frequencyPerWeek,
    required int durationWeeks,
    String? sessionId,
    String? instructions,
  }) async {
    policy.require(NodexPermissions.physioExerciseWrite);
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (patientId.isEmpty) {
      fieldErrors['patient_id'] = 'Patient is required.';
    }
    if (prescribedBy.isEmpty) {
      fieldErrors['prescribed_by'] = 'Prescribing clinician is required.';
    }
    if (exerciseName.trim().isEmpty) {
      fieldErrors['exercise_name'] = 'Exercise name is required.';
    }
    if (setsCount < 1 || setsCount > 100) {
      fieldErrors['sets_count'] = 'Sets must be between 1 and 100.';
    }
    if (repsCount < 1 || repsCount > 1000) {
      fieldErrors['reps_count'] = 'Repetitions must be between 1 and 1000.';
    }
    if (frequencyPerWeek < 1 || frequencyPerWeek > 7) {
      fieldErrors['frequency_per_week'] = 'Frequency must be 1 to 7 days.';
    }
    if (durationWeeks < 1 || durationWeeks > 52) {
      fieldErrors['duration_weeks'] = 'Duration must be 1 to 52 weeks.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Exercise regimen failed validation.',
        fieldErrors: fieldErrors,
        code: 'physio_exercise_invalid',
      );
    }
    final DateTime now = DateTime.now().toUtc();
    final String? cleanInstructions = instructions?.trim();
    final PhysioExercisePlan plan = PhysioExercisePlan(
      id: const Uuid().v4(),
      tenantId: tenantId,
      patientId: patientId,
      sessionId: sessionId,
      prescribedBy: prescribedBy,
      exerciseName: exerciseName.trim(),
      setsCount: setsCount,
      repsCount: repsCount,
      frequencyPerWeek: frequencyPerWeek,
      durationWeeks: durationWeeks,
      instructions: cleanInstructions == null || cleanInstructions.isEmpty
          ? null
          : cleanInstructions,
      status: PhysioPlanStatus.active,
      createdAt: now,
      updatedAt: now,
    );
    return _repository.upsertPlan(plan);
  }
}

/// Finishes a regimen as completed or stopped. Requires
/// `physio_exercise.write`.
final class FinishPhysioExercisePlanUseCase {
  FinishPhysioExercisePlanUseCase({required this._repository});

  final PhysioRepository _repository;

  Future<PhysioExercisePlan> call({
    required AuthorizationPolicy policy,
    required PhysioExercisePlan plan,
    required bool completed,
  }) async {
    policy.require(NodexPermissions.physioExerciseWrite);
    if (plan.isFinished) {
      throw const AuthorizationError(
        message: 'Finished exercise plans cannot transition.',
        code: 'physio_plan_closed',
      );
    }
    final DateTime now = DateTime.now().toUtc();
    return _repository.upsertPlan(
      PhysioExercisePlan(
        id: plan.id,
        tenantId: plan.tenantId,
        patientId: plan.patientId,
        sessionId: plan.sessionId,
        prescribedBy: plan.prescribedBy,
        exerciseName: plan.exerciseName,
        setsCount: plan.setsCount,
        repsCount: plan.repsCount,
        frequencyPerWeek: plan.frequencyPerWeek,
        durationWeeks: plan.durationWeeks,
        instructions: plan.instructions,
        status: completed
            ? PhysioPlanStatus.completed
            : PhysioPlanStatus.stopped,
        createdAt: plan.createdAt,
        updatedAt: now,
      ),
    );
  }
}

/// Records a recovery note against a session. Requires `physio_note.write`.
final class RecordPhysioRecoveryNoteUseCase {
  RecordPhysioRecoveryNoteUseCase({required this._repository});

  final PhysioRepository _repository;

  Future<PhysioRecoveryNote> call({
    required AuthorizationPolicy policy,
    required PhysioSession session,
    required String recordedBy,
    required String content,
    int? painScore,
  }) async {
    policy.require(NodexPermissions.physioNoteWrite);
    if (session.isScheduled ||
        session.status == PhysioSessionStatus.cancelled) {
      throw const AuthorizationError(
        message:
            'Recovery notes require a session that has started and not been '
            'cancelled.',
        code: 'physio_session_not_active',
      );
    }
    final String cleanContent = content.trim();
    if (cleanContent.isEmpty) {
      throw const ValidationError(
        message: 'A recovery note needs content.',
        code: 'physio_note_text_required',
      );
    }
    if (painScore != null && (painScore < 0 || painScore > 10)) {
      throw const ValidationError(
        message: 'Pain score must be between 0 and 10.',
        fieldErrors: <String, String>{'pain_score': 'Expected 0 to 10.'},
        code: 'physio_pain_score_out_of_range',
      );
    }
    final DateTime now = DateTime.now().toUtc();
    final PhysioRecoveryNote note = PhysioRecoveryNote(
      id: const Uuid().v4(),
      tenantId: session.tenantId,
      sessionId: session.id,
      recordedBy: recordedBy,
      content: cleanContent,
      painScore: painScore,
      recordedAt: now,
      createdAt: now,
      updatedAt: now,
    );
    return _repository.upsertNote(note);
  }
}
