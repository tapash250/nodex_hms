/// Tests for the physiotherapy use-case gates (Module 20).
///
/// Session transitions need `physio_session.write`, regimens need
/// `physio_exercise.write`, and recovery notes need `physio_note.write`.
/// Sessions walk scheduled -> in progress -> completed (or cancelled with a
/// reason), notes require a session that has started, and finished plans are
/// frozen.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/authorization_snapshot.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/domain/physio/physio.dart';
import 'package:nodex_hms/domain/physio/physio_repository.dart';
import 'package:nodex_hms/domain/physio/physio_use_cases.dart';

import 'physio_repository_test.dart' show FakePhysioStore;

/// Builds a policy holding exactly [permissions].
AuthorizationPolicy policyWith(Set<String> permissions) {
  final DateTime issuedAt = DateTime.now().toUtc();
  return AuthorizationPolicy(
    snapshot: AuthorizationSnapshot(
      snapshotId: 'snapshot-1',
      tenantId: 'tenant-1',
      userId: 'clinician-1',
      deviceId: 'device-1',
      revision: 1,
      issuedAt: issuedAt,
      expiresAt: issuedAt.add(const Duration(days: 30)),
      payloadDigest: 'digest',
      roles: const <String>{NodexRoles.medicalOfficer},
      permissions: permissions,
      offlinePermissions: permissions,
      facilityIds: const <String>{},
      departmentIds: const <String>{},
      wardIds: const <String>{},
    ),
    connectivity: ConnectivityState.online,
  );
}

void main() {
  late FakePhysioStore store;
  late DefaultPhysioRepository repository;
  late SchedulePhysioSessionUseCase schedule;
  late StartPhysioSessionUseCase start;
  late CompletePhysioSessionUseCase complete;
  late CancelPhysioSessionUseCase cancel;
  late PrescribePhysioExerciseUseCase prescribe;
  late FinishPhysioExercisePlanUseCase finish;
  late RecordPhysioRecoveryNoteUseCase recordNote;

  const Set<String> sessionWriter = <String>{
    NodexPermissions.physioSessionWrite,
  };
  const Set<String> exerciseWriter = <String>{
    NodexPermissions.physioExerciseWrite,
  };
  const Set<String> noteWriter = <String>{NodexPermissions.physioNoteWrite};

  setUp(() {
    store = FakePhysioStore();
    repository = DefaultPhysioRepository(
      store: store,
      logger: NodexLogger(
        sinks: <NodexLogSink>[InMemoryLogSink()],
        minimumLevel: NodexLogLevel.trace,
      ),
    );
    schedule = SchedulePhysioSessionUseCase(repository: repository);
    start = StartPhysioSessionUseCase(repository: repository);
    complete = CompletePhysioSessionUseCase(repository: repository);
    cancel = CancelPhysioSessionUseCase(repository: repository);
    prescribe = PrescribePhysioExerciseUseCase(repository: repository);
    finish = FinishPhysioExercisePlanUseCase(repository: repository);
    recordNote = RecordPhysioRecoveryNoteUseCase(repository: repository);
  });

  // Seeded rows predate "now" so a use case re-stamping `updatedAt` moves the
  // clock forward rather than backwards.
  DateTime at(int hour) => DateTime.utc(2026, 9, 1, hour);

  Future<PhysioSession> seedSession({
    PhysioSessionStatus status = PhysioSessionStatus.scheduled,
    String id = 'session-1',
  }) async {
    final PhysioSession session = PhysioSession(
      id: id,
      tenantId: 'tenant-1',
      patientId: 'patient-1',
      physiotherapistId: 'therapist-1',
      sessionCode: 'PHY-00$id',
      sessionType: PhysioSessionType.therapy,
      bodyArea: 'Left knee',
      status: status,
      scheduledAt: at(9),
      startedAt: status == PhysioSessionStatus.scheduled ? null : at(10),
      completedAt: status == PhysioSessionStatus.completed ? at(11) : null,
      createdAt: at(8),
      updatedAt: at(8),
    );
    await repository.upsertSession(session);
    return session;
  }

  Future<PhysioExercisePlan> seedPlan({
    PhysioPlanStatus status = PhysioPlanStatus.active,
    String id = 'plan-1',
  }) async {
    final PhysioExercisePlan plan = PhysioExercisePlan(
      id: id,
      tenantId: 'tenant-1',
      patientId: 'patient-1',
      sessionId: 'session-1',
      prescribedBy: 'doctor-1',
      exerciseName: 'Straight leg raise',
      setsCount: 3,
      repsCount: 12,
      frequencyPerWeek: 5,
      durationWeeks: 6,
      status: status,
      createdAt: at(8),
      updatedAt: at(8),
    );
    await repository.upsertPlan(plan);
    return plan;
  }

  group('scheduling', () {
    test('scheduling requires physio_session.write', () {
      expect(
        schedule.call(
          policy: policyWith(noteWriter),
          tenantId: 'tenant-1',
          patientId: 'patient-1',
          physiotherapistId: 'therapist-1',
          sessionCode: 'PHY-100',
          sessionType: PhysioSessionType.therapy,
          bodyArea: 'Left knee',
          scheduledAt: DateTime.now(),
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('an incomplete session is rejected', () {
      expect(
        schedule.call(
          policy: policyWith(sessionWriter),
          tenantId: 'tenant-1',
          patientId: 'patient-1',
          physiotherapistId: 'therapist-1',
          sessionCode: ' ',
          sessionType: PhysioSessionType.therapy,
          bodyArea: 'Left knee',
          scheduledAt: DateTime.now(),
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'physio_session_invalid',
          ),
        ),
      );
    });

    test('a session is created in the scheduled state', () async {
      final PhysioSession session = await schedule.call(
        policy: policyWith(sessionWriter),
        tenantId: 'tenant-1',
        patientId: 'patient-1',
        physiotherapistId: 'therapist-1',
        sessionCode: ' PHY-100 ',
        sessionType: PhysioSessionType.assessment,
        bodyArea: ' Lumbar spine ',
        scheduledAt: DateTime.utc(2026, 9, 25, 10),
        equipmentUsed: '  ',
      );

      expect(session.status, PhysioSessionStatus.scheduled);
      expect(session.sessionCode, 'PHY-100');
      expect(session.bodyArea, 'Lumbar spine');
      expect(session.sessionType, PhysioSessionType.assessment);
      expect(session.equipmentUsed, isNull);
      expect((await repository.sessionById(session.id))!.id, session.id);
    });
  });

  group('session transitions', () {
    test('starting requires physio_session.write', () async {
      final PhysioSession session = await seedSession();
      expect(
        start.call(policy: policyWith(noteWriter), session: session),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('only a scheduled session can start', () async {
      final PhysioSession session = await seedSession(
        status: PhysioSessionStatus.completed,
      );
      expect(
        start.call(policy: policyWith(sessionWriter), session: session),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'physio_session_not_scheduled',
          ),
        ),
      );
    });

    test('starting stamps the in-progress state', () async {
      final PhysioSession session = await seedSession();
      final PhysioSession started = await start.call(
        policy: policyWith(sessionWriter),
        session: session,
      );

      expect(started.status, PhysioSessionStatus.inProgress);
      expect(started.startedAt, isNotNull);
      expect((await repository.sessionById(session.id))!.isRunning, isTrue);
    });

    test('only an in-progress session can complete', () async {
      final PhysioSession session = await seedSession();
      expect(
        complete.call(policy: policyWith(sessionWriter), session: session),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'physio_session_not_started',
          ),
        ),
      );
    });

    test('completing stamps the completed state', () async {
      final PhysioSession running = await seedSession(
        status: PhysioSessionStatus.inProgress,
      );
      final PhysioSession done = await complete.call(
        policy: policyWith(sessionWriter),
        session: running,
      );

      expect(done.status, PhysioSessionStatus.completed);
      expect(done.completedAt, isNotNull);
      expect(done.isTerminal, isTrue);
    });

    test('cancelling requires physio_session.write', () async {
      final PhysioSession session = await seedSession();
      expect(
        cancel.call(
          policy: policyWith(noteWriter),
          original: session,
          reason: 'Patient unwell.',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('cancelling requires a reason', () async {
      final PhysioSession session = await seedSession();
      expect(
        cancel.call(
          policy: policyWith(sessionWriter),
          original: session,
          reason: ' ',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'physio_cancellation_reason_required',
          ),
        ),
      );
    });

    test('a closed session cannot be cancelled', () async {
      final PhysioSession session = await seedSession(
        status: PhysioSessionStatus.completed,
      );
      expect(
        cancel.call(
          policy: policyWith(sessionWriter),
          original: session,
          reason: 'Patient left.',
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'physio_session_closed',
          ),
        ),
      );
    });

    test('cancelling stamps the reason and freezes the session', () async {
      final PhysioSession session = await seedSession();
      final PhysioSession cancelled = await cancel.call(
        policy: policyWith(sessionWriter),
        original: session,
        reason: 'Patient refused.',
      );

      expect(cancelled.status, PhysioSessionStatus.cancelled);
      expect(cancelled.cancellationReason, 'Patient refused.');
      expect(cancelled.cancelledAt, isNotNull);
      expect(cancelled.isTerminal, isTrue);
    });
  });

  group('exercise regimens', () {
    test('prescribing requires physio_exercise.write', () {
      expect(
        prescribe.call(
          policy: policyWith(sessionWriter),
          tenantId: 'tenant-1',
          patientId: 'patient-1',
          prescribedBy: 'doctor-1',
          exerciseName: 'Heel slides',
          setsCount: 3,
          repsCount: 10,
          frequencyPerWeek: 3,
          durationWeeks: 4,
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('out-of-range regimen counts are rejected', () {
      expect(
        prescribe.call(
          policy: policyWith(exerciseWriter),
          tenantId: 'tenant-1',
          patientId: 'patient-1',
          prescribedBy: 'doctor-1',
          exerciseName: 'Heel slides',
          setsCount: 0,
          repsCount: 10,
          frequencyPerWeek: 9,
          durationWeeks: 4,
        ),
        throwsA(
          isA<ValidationError>()
              .having(
                (ValidationError error) => error.code,
                'code',
                'physio_exercise_invalid',
              )
              .having(
                (ValidationError error) => error.fieldErrors.keys,
                'fields',
                containsAll(<String>{'sets_count', 'frequency_per_week'}),
              ),
        ),
      );
    });

    test('a regimen is created active', () async {
      final PhysioExercisePlan plan = await prescribe.call(
        policy: policyWith(exerciseWriter),
        tenantId: 'tenant-1',
        patientId: 'patient-1',
        prescribedBy: 'doctor-1',
        exerciseName: ' Heel slides ',
        setsCount: 3,
        repsCount: 10,
        frequencyPerWeek: 3,
        durationWeeks: 4,
        instructions: ' slow down. ',
      );

      expect(plan.status, PhysioPlanStatus.active);
      expect(plan.exerciseName, 'Heel slides');
      expect(plan.instructions, 'slow down.');
      expect((await repository.planById(plan.id))!.isActive, isTrue);
    });

    test('finishing requires physio_exercise.write', () async {
      final PhysioExercisePlan plan = await seedPlan();
      expect(
        finish.call(
          policy: policyWith(sessionWriter),
          plan: plan,
          completed: true,
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('a finished plan cannot transition again', () async {
      final PhysioExercisePlan plan = await seedPlan(
        status: PhysioPlanStatus.stopped,
      );
      expect(
        finish.call(
          policy: policyWith(exerciseWriter),
          plan: plan,
          completed: true,
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'physio_plan_closed',
          ),
        ),
      );
    });

    test('a regimen can be completed or stopped', () async {
      final PhysioExercisePlan plan = await seedPlan();
      final PhysioExercisePlan completedPlan = await finish.call(
        policy: policyWith(exerciseWriter),
        plan: plan,
        completed: true,
      );
      expect(completedPlan.status, PhysioPlanStatus.completed);
      expect(completedPlan.isFinished, isTrue);

      final PhysioExercisePlan other = await seedPlan(id: 'plan-2');
      final PhysioExercisePlan stopped = await finish.call(
        policy: policyWith(exerciseWriter),
        plan: other,
        completed: false,
      );
      expect(stopped.status, PhysioPlanStatus.stopped);
    });
  });

  group('recovery notes', () {
    test('recording requires physio_note.write', () async {
      final PhysioSession session = await seedSession(
        status: PhysioSessionStatus.inProgress,
      );
      expect(
        recordNote.call(
          policy: policyWith(sessionWriter),
          session: session,
          recordedBy: 'nurse-1',
          content: 'Progressing well.',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('a session that never started cannot receive notes', () async {
      final PhysioSession session = await seedSession();
      expect(
        recordNote.call(
          policy: policyWith(noteWriter),
          session: session,
          recordedBy: 'nurse-1',
          content: 'Progressing well.',
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'physio_session_not_active',
          ),
        ),
      );
    });

    test('a cancelled session cannot receive notes', () async {
      final PhysioSession session = await seedSession(
        status: PhysioSessionStatus.cancelled,
      );
      expect(
        recordNote.call(
          policy: policyWith(noteWriter),
          session: session,
          recordedBy: 'nurse-1',
          content: 'Progressing well.',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('note content is required', () async {
      final PhysioSession session = await seedSession(
        status: PhysioSessionStatus.inProgress,
      );
      expect(
        recordNote.call(
          policy: policyWith(noteWriter),
          session: session,
          recordedBy: 'nurse-1',
          content: '  ',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'physio_note_text_required',
          ),
        ),
      );
    });

    test('a pain score outside 0-10 is rejected', () async {
      final PhysioSession session = await seedSession(
        status: PhysioSessionStatus.inProgress,
      );
      expect(
        recordNote.call(
          policy: policyWith(noteWriter),
          session: session,
          recordedBy: 'nurse-1',
          content: 'Sharp pain on extension.',
          painScore: 11,
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'physio_pain_score_out_of_range',
          ),
        ),
      );
    });

    test('a note records against a running session', () async {
      final PhysioSession session = await seedSession(
        status: PhysioSessionStatus.inProgress,
      );
      final PhysioRecoveryNote note = await recordNote.call(
        policy: policyWith(noteWriter),
        session: session,
        recordedBy: 'nurse-1',
        content: '  Tolerated the full set.  ',
        painScore: 4,
      );

      expect(note.content, 'Tolerated the full set.');
      expect(note.painScore, 4);
      expect(note.sessionId, session.id);
      expect((await repository.notesForSession(session.id)).single.id, note.id);
    });

    test('a completed session still accepts notes', () async {
      final PhysioSession session = await seedSession(
        status: PhysioSessionStatus.completed,
      );
      final PhysioRecoveryNote note = await recordNote.call(
        policy: policyWith(noteWriter),
        session: session,
        recordedBy: 'therapist-1',
        content: 'Discharged to home programme.',
      );

      expect(note.painScore, isNull);
      expect(note.content, 'Discharged to home programme.');
    });
  });
}
