/// Tests for the operation theatre use-case gates (Module 19).
///
/// Scheduling enforces the room conflict check, a case cannot start without a
/// fit pre-op assessment, intra-op records require a started case, completion
/// needs `ot.finalize` plus a post-op record, and cancellation carries a
/// reason.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/authorization_snapshot.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/domain/ot/ot.dart';
import 'package:nodex_hms/domain/ot/ot_repository.dart';
import 'package:nodex_hms/domain/ot/ot_use_cases.dart';

import 'ot_repository_test.dart' show FakeOtStore;

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
  late FakeOtStore store;
  late DefaultOtRepository repository;
  late ScheduleOtBookingUseCase schedule;
  late RecordPreOpAssessmentUseCase assess;
  late StartOtBookingUseCase startCase;
  late RecordAnesthesiaUseCase anesthesia;
  late RecordProcedureLogUseCase procedure;
  late RecordPostOpUseCase postOp;
  late CompleteOtBookingUseCase complete;
  late CancelOtBookingUseCase cancel;

  const Set<String> scheduler = <String>{NodexPermissions.otSchedule};
  const Set<String> recorder = <String>{NodexPermissions.otRecord};
  const Set<String> finalizer = <String>{NodexPermissions.otFinalize};

  setUp(() {
    store = FakeOtStore();
    repository = DefaultOtRepository(
      store: store,
      logger: NodexLogger(
        sinks: <NodexLogSink>[InMemoryLogSink()],
        minimumLevel: NodexLogLevel.trace,
      ),
    );
    schedule = ScheduleOtBookingUseCase(repository: repository);
    assess = RecordPreOpAssessmentUseCase(repository: repository);
    startCase = StartOtBookingUseCase(repository: repository);
    anesthesia = RecordAnesthesiaUseCase(repository: repository);
    procedure = RecordProcedureLogUseCase(repository: repository);
    postOp = RecordPostOpUseCase(repository: repository);
    complete = CompleteOtBookingUseCase(repository: repository);
    cancel = CancelOtBookingUseCase(repository: repository);
  });

  // Seeded rows predate "now" so a use case re-stamping `updatedAt` moves the
  // clock forward rather than backwards.
  DateTime at(int hour) => DateTime.utc(2026, 9, 1, hour);

  Future<OtBooking> seedBooking({
    OtBookingStatus status = OtBookingStatus.scheduled,
    String room = 'OT 1',
    String id = 'booking-1',
  }) async {
    final OtBooking booking = OtBooking(
      id: id,
      tenantId: 'tenant-1',
      patientId: 'patient-1',
      theatreRoom: room,
      procedureName: 'Appendectomy',
      scheduledStart: at(9),
      scheduledEnd: at(11),
      surgeonId: 'doctor-1',
      status: status,
      priority: OtPriority.routine,
      createdBy: 'doctor-1',
      createdAt: at(8),
      updatedAt: at(8),
    );
    await repository.upsertBooking(booking);
    return booking;
  }

  Future<void> seedFitPreOp(String bookingId) async {
    await repository.upsertPreOpAssessment(
      OtPreOpAssessment(
        id: 'preop-1',
        tenantId: 'tenant-1',
        bookingId: bookingId,
        patientId: 'patient-1',
        assessedBy: 'doctor-1',
        assessedAt: at(8),
        fitness: OtFitness.fit,
        createdAt: at(8),
        updatedAt: at(8),
      ),
    );
  }

  Future<void> seedPostOp(String bookingId) async {
    await repository.upsertPostOpRecord(
      OtPostOpRecord(
        id: 'postop-1',
        tenantId: 'tenant-1',
        bookingId: bookingId,
        patientId: 'patient-1',
        recordedBy: 'nurse-1',
        recordedAt: at(12),
        condition: OtPostOpCondition.stable,
        createdAt: at(12),
        updatedAt: at(12),
      ),
    );
  }

  group('scheduling', () {
    test('booking a case requires ot.schedule', () {
      expect(
        schedule.call(
          policy: policyWith(recorder),
          tenantId: 'tenant-1',
          patientId: 'patient-1',
          theatreRoom: 'OT 1',
          procedureName: 'Appendectomy',
          scheduledStart: at(9),
          scheduledEnd: at(11),
          surgeonId: 'doctor-1',
          createdBy: 'doctor-1',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('booking creates a scheduled case', () async {
      final OtBooking booking = await schedule.call(
        policy: policyWith(scheduler),
        tenantId: 'tenant-1',
        patientId: 'patient-1',
        theatreRoom: 'OT 1',
        procedureName: 'Appendectomy',
        scheduledStart: at(9),
        scheduledEnd: at(11),
        surgeonId: 'doctor-1',
        createdBy: 'doctor-1',
        priority: OtPriority.urgent,
      );

      expect(booking.status, OtBookingStatus.scheduled);
      expect(booking.priority, OtPriority.urgent);
      expect(booking.isScheduled, isTrue);
      expect((await repository.bookingById(booking.id))!.id, booking.id);
    });

    test('an end before the start is rejected', () {
      expect(
        schedule.call(
          policy: policyWith(scheduler),
          tenantId: 'tenant-1',
          patientId: 'patient-1',
          theatreRoom: 'OT 1',
          procedureName: 'Appendectomy',
          scheduledStart: at(11),
          scheduledEnd: at(9),
          surgeonId: 'doctor-1',
          createdBy: 'doctor-1',
        ),
        throwsA(isA<ValidationError>()),
      );
    });

    test('an overlapping booking in the same room is rejected', () async {
      await seedBooking();

      expect(
        schedule.call(
          policy: policyWith(scheduler),
          tenantId: 'tenant-1',
          patientId: 'patient-2',
          theatreRoom: 'OT 1',
          procedureName: 'Hernia repair',
          scheduledStart: at(10),
          scheduledEnd: at(12),
          surgeonId: 'doctor-1',
          createdBy: 'doctor-1',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'ot_room_double_booked',
          ),
        ),
      );
    });

    test('another room at the same hour books normally', () async {
      await seedBooking();

      final OtBooking booking = await schedule.call(
        policy: policyWith(scheduler),
        tenantId: 'tenant-1',
        patientId: 'patient-2',
        theatreRoom: 'OT 2',
        procedureName: 'Hernia repair',
        scheduledStart: at(10),
        scheduledEnd: at(12),
        surgeonId: 'doctor-1',
        createdBy: 'doctor-1',
      );
      expect(booking.theatreRoom, 'OT 2');
    });

    test('a cancelled case does not hold the room', () async {
      await seedBooking(status: OtBookingStatus.cancelled);

      final OtBooking booking = await schedule.call(
        policy: policyWith(scheduler),
        tenantId: 'tenant-1',
        patientId: 'patient-2',
        theatreRoom: 'OT 1',
        procedureName: 'Hernia repair',
        scheduledStart: at(9),
        scheduledEnd: at(11),
        surgeonId: 'doctor-1',
        createdBy: 'doctor-1',
      );
      expect(booking.isScheduled, isTrue);
    });
  });

  group('pre-op and case start', () {
    test('recording an assessment requires ot.record', () async {
      final OtBooking booking = await seedBooking();
      expect(
        assess.call(
          policy: policyWith(scheduler),
          booking: booking,
          assessedBy: 'doctor-1',
          fitness: OtFitness.fit,
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('a second assessment replaces the first in place', () async {
      final OtBooking booking = await seedBooking();
      final OtPreOpAssessment first = await assess.call(
        policy: policyWith(recorder),
        booking: booking,
        assessedBy: 'doctor-1',
        fitness: OtFitness.unfit,
      );
      final OtPreOpAssessment second = await assess.call(
        policy: policyWith(recorder),
        booking: booking,
        assessedBy: 'doctor-1',
        fitness: OtFitness.fit,
      );

      expect(second.id, first.id);
      expect(
        store.tables['ot_preop_assessments']!.length,
        1,
        reason: 'one booking holds exactly one assessment row',
      );
      expect(
        (await repository.preOpForBooking(booking.id))!.fitness,
        OtFitness.fit,
      );
    });

    test('an out-of-range ASA class is rejected', () async {
      final OtBooking booking = await seedBooking();
      expect(
        assess.call(
          policy: policyWith(recorder),
          booking: booking,
          assessedBy: 'doctor-1',
          fitness: OtFitness.fit,
          asaClass: 9,
        ),
        throwsA(isA<ValidationError>()),
      );
    });

    test('starting requires ot.record', () async {
      final OtBooking booking = await seedBooking();
      expect(
        startCase.call(policy: policyWith(scheduler), original: booking),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('a case cannot start without an assessment', () async {
      final OtBooking booking = await seedBooking();
      expect(
        startCase.call(policy: policyWith(recorder), original: booking),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'ot_preop_required',
          ),
        ),
      );
    });

    test('an unfit patient cannot start', () async {
      final OtBooking booking = await seedBooking();
      await repository.upsertPreOpAssessment(
        OtPreOpAssessment(
          id: 'preop-1',
          tenantId: 'tenant-1',
          bookingId: booking.id,
          patientId: booking.patientId,
          assessedBy: 'doctor-1',
          assessedAt: at(8),
          fitness: OtFitness.unfit,
          createdAt: at(8),
          updatedAt: at(8),
        ),
      );
      expect(
        startCase.call(policy: policyWith(recorder), original: booking),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'ot_patient_not_fit',
          ),
        ),
      );
    });

    test('a fit assessment starts the case', () async {
      final OtBooking booking = await seedBooking();
      await seedFitPreOp(booking.id);

      final OtBooking started = await startCase.call(
        policy: policyWith(recorder),
        original: booking,
      );
      expect(started.status, OtBookingStatus.inProgress);
      expect(started.isInProgress, isTrue);

      expect(
        startCase.call(policy: policyWith(recorder), original: started),
        throwsA(isA<AuthorizationError>()),
      );
    });
  });

  group('intra-op records', () {
    late OtBooking inProgress;

    setUp(() async {
      inProgress = await seedBooking(status: OtBookingStatus.inProgress);
    });

    test('intra-op records require ot.record', () async {
      expect(
        anesthesia.call(
          policy: policyWith(scheduler),
          booking: inProgress,
          recordedBy: 'doctor-2',
          anesthesiaType: OtAnesthesiaType.general,
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('intra-op records refuse a case that has not started', () async {
      final OtBooking scheduled = await seedBooking(
        id: 'booking-2',
        status: OtBookingStatus.scheduled,
      );
      expect(
        anesthesia.call(
          policy: policyWith(recorder),
          booking: scheduled,
          recordedBy: 'doctor-2',
          anesthesiaType: OtAnesthesiaType.general,
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'ot_booking_not_started',
          ),
        ),
      );
    });

    test('anesthesia records and closes against the case', () async {
      final OtAnesthesiaRecord record = await anesthesia.call(
        policy: policyWith(recorder),
        booking: inProgress,
        recordedBy: 'doctor-2',
        anesthesiaType: OtAnesthesiaType.general,
      );
      expect(record.isComplete, isFalse);

      final OtAnesthesiaRecord closed = await anesthesia.call(
        policy: policyWith(recorder),
        booking: inProgress,
        recordedBy: record.recordedBy,
        anesthesiaType: record.anesthesiaType,
        startedAt: record.startedAt,
        endedAt: record.startedAt.add(const Duration(hours: 2)),
      );
      expect(closed.isComplete, isTrue);
      expect(closed.id, record.id);
      expect(
        store.tables['ot_anesthesia_records']!.length,
        1,
        reason: 'one booking holds exactly one anesthesia record',
      );
    });

    test('an anesthesia end before its start is rejected', () async {
      expect(
        anesthesia.call(
          policy: policyWith(recorder),
          booking: inProgress,
          recordedBy: 'doctor-2',
          anesthesiaType: OtAnesthesiaType.general,
          endedAt: at(8),
        ),
        throwsA(isA<ValidationError>()),
      );
    });

    test('a procedure log completes against the case', () async {
      final OtProcedureLog log = await procedure.call(
        policy: policyWith(recorder),
        booking: inProgress,
        performedBy: 'doctor-1',
        procedureName: 'Appendectomy',
      );
      expect(log.isComplete, isFalse);

      final OtProcedureLog done = await procedure.call(
        policy: policyWith(recorder),
        booking: inProgress,
        performedBy: log.performedBy,
        procedureName: log.procedureName,
        startedAt: log.startedAt,
        completedAt: log.startedAt.add(const Duration(hours: 1)),
      );
      expect(done.isComplete, isTrue);
      expect(done.id, log.id);
    });

    test('an out-of-range pain score is rejected', () async {
      expect(
        postOp.call(
          policy: policyWith(recorder),
          booking: inProgress,
          recordedBy: 'nurse-1',
          condition: OtPostOpCondition.stable,
          painScore: 11,
        ),
        throwsA(isA<ValidationError>()),
      );
    });

    test('post-op records the recovery state', () async {
      final OtPostOpRecord record = await postOp.call(
        policy: policyWith(recorder),
        booking: inProgress,
        recordedBy: 'nurse-1',
        condition: OtPostOpCondition.watch,
        painScore: 4,
      );
      expect(record.condition, OtPostOpCondition.watch);
      expect(record.painScore, 4);
      expect((await repository.postOpForBooking(inProgress.id))!.id, record.id);
    });

    test('records refuse a closed case', () async {
      final OtBooking completed = await seedBooking(
        id: 'booking-3',
        status: OtBookingStatus.completed,
      );
      expect(
        postOp.call(
          policy: policyWith(recorder),
          booking: completed,
          recordedBy: 'nurse-1',
          condition: OtPostOpCondition.stable,
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });
  });

  group('completion and cancellation', () {
    test('completion requires ot.finalize', () async {
      final OtBooking inProgress = await seedBooking(
        status: OtBookingStatus.inProgress,
      );
      await seedPostOp(inProgress.id);
      expect(
        complete.call(policy: policyWith(recorder), original: inProgress),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('completion requires a post-op record', () async {
      final OtBooking inProgress = await seedBooking(
        status: OtBookingStatus.inProgress,
      );
      expect(
        complete.call(policy: policyWith(finalizer), original: inProgress),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'ot_postop_required',
          ),
        ),
      );
    });

    test('completion requires a started case', () async {
      final OtBooking scheduled = await seedBooking();
      expect(
        complete.call(policy: policyWith(finalizer), original: scheduled),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('post-op documentation completes the case', () async {
      final OtBooking inProgress = await seedBooking(
        status: OtBookingStatus.inProgress,
      );
      await seedPostOp(inProgress.id);

      final OtBooking done = await complete.call(
        policy: policyWith(finalizer),
        original: inProgress,
      );
      expect(done.status, OtBookingStatus.completed);
      expect(done.isTerminal, isTrue);

      expect(
        complete.call(policy: policyWith(finalizer), original: done),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('cancellation requires ot.schedule', () async {
      final OtBooking scheduled = await seedBooking();
      expect(
        cancel.call(
          policy: policyWith(recorder),
          original: scheduled,
          reason: 'Patient unwell.',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('cancellation requires a reason', () async {
      final OtBooking scheduled = await seedBooking();
      expect(
        cancel.call(
          policy: policyWith(scheduler),
          original: scheduled,
          reason: '   ',
        ),
        throwsA(isA<ValidationError>()),
      );
    });

    test('cancellation stamps the reason and freezes the case', () async {
      final OtBooking scheduled = await seedBooking();
      final OtBooking cancelled = await cancel.call(
        policy: policyWith(scheduler),
        original: scheduled,
        reason: 'Patient unwell.',
      );

      expect(cancelled.status, OtBookingStatus.cancelled);
      expect(cancelled.cancellationReason, 'Patient unwell.');
      expect(cancelled.isTerminal, isTrue);
      expect(
        cancel.call(
          policy: policyWith(scheduler),
          original: cancelled,
          reason: 'Another reason.',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });
  });
}
