/// Physiotherapy repository contract and PowerSync-backed implementation
/// (Module 20).
library;

import 'package:nodex_hms/core/errors/error_mapper.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';
import 'package:nodex_hms/domain/physio/physio.dart';

/// Read and write access to physiotherapy sessions, exercise plans and
/// recovery notes.
abstract interface class PhysioRepository {
  /// One session by id, or null.
  Future<PhysioSession?> sessionById(String id);

  /// Sessions for one patient, newest first.
  Future<List<PhysioSession>> sessionsForPatient(String patientId);

  /// Every session on the device, newest first.
  Future<List<PhysioSession>> allSessions();

  /// Inserts or updates a session row.
  Future<PhysioSession> upsertSession(PhysioSession session);

  /// One exercise plan by id, or null.
  Future<PhysioExercisePlan?> planById(String id);

  /// Exercise plans for one patient, newest first.
  Future<List<PhysioExercisePlan>> plansForPatient(String patientId);

  /// Inserts or updates an exercise plan row.
  Future<PhysioExercisePlan> upsertPlan(PhysioExercisePlan plan);

  /// Recovery notes recorded against a session, oldest first.
  Future<List<PhysioRecoveryNote>> notesForSession(String sessionId);

  /// Inserts or updates a recovery note row.
  Future<PhysioRecoveryNote> upsertNote(PhysioRecoveryNote note);
}

/// Default repository over the encrypted local projection.
final class DefaultPhysioRepository implements PhysioRepository {
  const DefaultPhysioRepository({required this._store, required this._logger});

  static const String _module = 'domain.physio';

  final PatientLocalStore _store;
  final NodexLogger _logger;

  @override
  Future<PhysioSession?> sessionById(String id) async {
    try {
      final Map<String, Object?>? row = await _store.getById(
        LocalTables.physioSessions,
        id,
      );
      return row == null ? null : PhysioSession.fromRow(row);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'physio.sessionById');
    }
  }

  @override
  Future<List<PhysioSession>> sessionsForPatient(String patientId) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select * from ${LocalTables.physioSessions} where patient_id = ? '
        'order by scheduled_at desc',
        <Object?>[patientId],
      );
      return rows.map(PhysioSession.fromRow).toList();
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'physio.sessionsForPatient');
    }
  }

  @override
  Future<List<PhysioSession>> allSessions() async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select * from ${LocalTables.physioSessions} '
        'order by scheduled_at desc',
        const <Object?>[],
      );
      return rows.map(PhysioSession.fromRow).toList();
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'physio.allSessions');
    }
  }

  @override
  Future<PhysioSession> upsertSession(PhysioSession session) async {
    try {
      final Map<String, Object?>? existing = await _store.getById(
        LocalTables.physioSessions,
        session.id,
      );
      final Map<String, Object?> changes = <String, Object?>{
        'patient_id': session.patientId,
        'encounter_id': session.encounterId,
        'physiotherapist_id': session.physiotherapistId,
        'session_code': session.sessionCode,
        'session_type': session.sessionType.wireValue,
        'body_area': session.bodyArea,
        'status': session.status.wireValue,
        'scheduled_at': session.scheduledAt,
        'started_at': session.startedAt,
        'completed_at': session.completedAt,
        'cancelled_at': session.cancelledAt,
        'cancellation_reason': session.cancellationReason,
        'equipment_used': session.equipmentUsed,
        'updated_at': session.updatedAt,
      };
      if (existing == null) {
        await _store.insert(LocalTables.physioSessions, <String, Object?>{
          ...changes,
          'id': session.id,
          'tenant_id': session.tenantId,
          'created_at': session.createdAt,
        });
      } else {
        await _store.update(LocalTables.physioSessions, session.id, changes);
      }
      return session;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'physio.upsertSession');
    }
  }

  @override
  Future<PhysioExercisePlan?> planById(String id) async {
    try {
      final Map<String, Object?>? row = await _store.getById(
        LocalTables.physioExercisePlans,
        id,
      );
      return row == null ? null : PhysioExercisePlan.fromRow(row);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'physio.planById');
    }
  }

  @override
  Future<List<PhysioExercisePlan>> plansForPatient(String patientId) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select * from ${LocalTables.physioExercisePlans} '
        'where patient_id = ? order by created_at desc',
        <Object?>[patientId],
      );
      return rows.map(PhysioExercisePlan.fromRow).toList();
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'physio.plansForPatient');
    }
  }

  @override
  Future<PhysioExercisePlan> upsertPlan(PhysioExercisePlan plan) async {
    try {
      final Map<String, Object?>? existing = await _store.getById(
        LocalTables.physioExercisePlans,
        plan.id,
      );
      final Map<String, Object?> changes = <String, Object?>{
        'patient_id': plan.patientId,
        'session_id': plan.sessionId,
        'prescribed_by': plan.prescribedBy,
        'exercise_name': plan.exerciseName,
        'sets_count': plan.setsCount,
        'reps_count': plan.repsCount,
        'frequency_per_week': plan.frequencyPerWeek,
        'duration_weeks': plan.durationWeeks,
        'instructions': plan.instructions,
        'status': plan.status.wireValue,
        'updated_at': plan.updatedAt,
      };
      if (existing == null) {
        await _store.insert(LocalTables.physioExercisePlans, <String, Object?>{
          ...changes,
          'id': plan.id,
          'tenant_id': plan.tenantId,
          'created_at': plan.createdAt,
        });
      } else {
        await _store.update(LocalTables.physioExercisePlans, plan.id, changes);
      }
      return plan;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'physio.upsertPlan');
    }
  }

  @override
  Future<List<PhysioRecoveryNote>> notesForSession(String sessionId) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select * from ${LocalTables.physioRecoveryNotes} '
        'where session_id = ? order by recorded_at asc',
        <Object?>[sessionId],
      );
      return rows.map(PhysioRecoveryNote.fromRow).toList();
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'physio.notesForSession');
    }
  }

  @override
  Future<PhysioRecoveryNote> upsertNote(PhysioRecoveryNote note) async {
    try {
      final Map<String, Object?>? existing = await _store.getById(
        LocalTables.physioRecoveryNotes,
        note.id,
      );
      final Map<String, Object?> changes = <String, Object?>{
        'session_id': note.sessionId,
        'recorded_by': note.recordedBy,
        'content': note.content,
        'pain_score': note.painScore,
        'recorded_at': note.recordedAt,
        'updated_at': note.updatedAt,
      };
      if (existing == null) {
        await _store.insert(LocalTables.physioRecoveryNotes, <String, Object?>{
          ...changes,
          'id': note.id,
          'tenant_id': note.tenantId,
          'created_at': note.createdAt,
        });
      } else {
        await _store.update(LocalTables.physioRecoveryNotes, note.id, changes);
      }
      return note;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'physio.upsertNote');
    }
  }

  Never _mapped(Object error, StackTrace stackTrace, String operation) {
    if (error is NodexError) throw error;
    final NodexError mapped = NodexErrorMapper.map(error, operation: operation);
    _logger.error(
      _module,
      'Physiotherapy repository failure.',
      operation: operation,
      outcome: 'failed',
      errorCode: mapped.code,
      stackTrace: stackTrace,
    );
    throw mapped;
  }
}
