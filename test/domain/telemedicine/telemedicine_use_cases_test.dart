/// Tests for the telemedicine use-case gates (Module 22).
///
/// The consultation lifecycle needs `tele_consultation.write`, live vitals
/// overlays need `tele_vitals.record`, and archiving needs
/// `tele_archive.write`. A call starts only from the waiting room and
/// completes only from an in-call state; vitals are observed only during a
/// call; archiving requires a completed visit and recorded consent.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/authorization_snapshot.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/domain/telemedicine/telemedicine.dart';
import 'package:nodex_hms/domain/telemedicine/telemedicine_repository.dart';
import 'package:nodex_hms/domain/telemedicine/telemedicine_use_cases.dart';

import 'telemedicine_repository_test.dart' show FakeTelemedicineStore;

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
  late FakeTelemedicineStore store;
  late DefaultTelemedicineRepository repository;
  late ScheduleTeleConsultationUseCase schedule;
  late AdmitToWaitingRoomUseCase admit;
  late StartTeleConsultationUseCase start;
  late CompleteTeleConsultationUseCase complete;
  late MarkTeleNoShowUseCase noShow;
  late CancelTeleConsultationUseCase cancel;
  late RecordTeleVitalsOverlayUseCase recordVitals;
  late ArchiveTeleConsultationUseCase archive;

  const Set<String> runner = <String>{NodexPermissions.teleConsultationWrite};
  const Set<String> vitalsReader = <String>{NodexPermissions.teleVitalsRecord};
  const Set<String> archivist = <String>{NodexPermissions.teleArchiveWrite};

  setUp(() {
    store = FakeTelemedicineStore();
    repository = DefaultTelemedicineRepository(
      store: store,
      logger: NodexLogger(
        sinks: <NodexLogSink>[InMemoryLogSink()],
        minimumLevel: NodexLogLevel.trace,
      ),
    );
    schedule = ScheduleTeleConsultationUseCase(repository: repository);
    admit = AdmitToWaitingRoomUseCase(repository: repository);
    start = StartTeleConsultationUseCase(repository: repository);
    complete = CompleteTeleConsultationUseCase(repository: repository);
    noShow = MarkTeleNoShowUseCase(repository: repository);
    cancel = CancelTeleConsultationUseCase(repository: repository);
    recordVitals = RecordTeleVitalsOverlayUseCase(repository: repository);
    archive = ArchiveTeleConsultationUseCase(repository: repository);
  });

  // Seeded rows predate "now" so a use case re-stamping `updatedAt` moves the
  // clock forward rather than backwards.
  DateTime at(int hour) => DateTime.utc(2026, 9, 1, hour);

  Future<TeleConsultation> seedConsultation({
    TeleConsultationStatus status = TeleConsultationStatus.scheduled,
    String id = 'consultation-1',
  }) async {
    final TeleConsultation visit = TeleConsultation(
      id: id,
      tenantId: 'tenant-1',
      patientId: 'patient-1',
      clinicianId: 'doctor-1',
      bookedBy: 'reception-1',
      visitCode: 'TEL-00$id',
      channel: TeleChannel.video,
      status: status,
      reason: 'Post-op review',
      scheduledAt: at(9),
      waitingAt: status == TeleConsultationStatus.scheduled ? null : at(10),
      startedAt:
          status == TeleConsultationStatus.inCall ||
              status == TeleConsultationStatus.completed
          ? at(11)
          : null,
      completedAt: status == TeleConsultationStatus.completed ? at(12) : null,
      noShowAt: status == TeleConsultationStatus.noShow ? at(11) : null,
      createdAt: at(8),
      updatedAt: at(8),
    );
    await repository.upsertConsultation(visit);
    return visit;
  }

  group('scheduling', () {
    test('scheduling requires tele_consultation.write', () {
      expect(
        schedule.call(
          policy: policyWith(vitalsReader),
          tenantId: 'tenant-1',
          patientId: 'patient-1',
          clinicianId: 'doctor-1',
          bookedBy: 'reception-1',
          visitCode: 'TEL-100',
          channel: TeleChannel.video,
          scheduledAt: DateTime.now(),
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('an incomplete consultation is rejected', () {
      expect(
        schedule.call(
          policy: policyWith(runner),
          tenantId: 'tenant-1',
          patientId: 'patient-1',
          clinicianId: '',
          bookedBy: 'reception-1',
          visitCode: '  ',
          channel: TeleChannel.audio,
          scheduledAt: DateTime.now(),
        ),
        throwsA(
          isA<ValidationError>()
              .having(
                (ValidationError error) => error.code,
                'code',
                'tele_consultation_invalid',
              )
              .having(
                (ValidationError error) => error.fieldErrors.keys,
                'fields',
                containsAll(<String>{'clinician_id', 'visit_code'}),
              ),
        ),
      );
    });

    test('a consultation is created scheduled and trims its text', () async {
      final TeleConsultation visit = await schedule.call(
        policy: policyWith(runner),
        tenantId: 'tenant-1',
        patientId: 'patient-1',
        clinicianId: 'doctor-1',
        bookedBy: 'reception-1',
        visitCode: ' TEL-100 ',
        channel: TeleChannel.audio,
        scheduledAt: DateTime.utc(2026, 9, 25, 10),
        reason: '  Post-op review  ',
      );

      expect(visit.status, TeleConsultationStatus.scheduled);
      expect(visit.visitCode, 'TEL-100');
      expect(visit.channel, TeleChannel.audio);
      expect(visit.reason, 'Post-op review');
      expect(visit.scheduledAt, DateTime.utc(2026, 9, 25, 10));
      expect((await repository.consultationById(visit.id))!.id, visit.id);
    });
  });

  group('waiting room and call lifecycle', () {
    test('admission requires tele_consultation.write', () async {
      final TeleConsultation visit = await seedConsultation();
      expect(
        admit.call(policy: policyWith(vitalsReader), original: visit),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('only a scheduled consultation enters the waiting room', () async {
      final TeleConsultation visit = await seedConsultation(
        status: TeleConsultationStatus.waiting,
      );
      expect(
        admit.call(policy: policyWith(runner), original: visit),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'tele_consultation_not_scheduled',
          ),
        ),
      );
    });

    test('admission stamps the waiting room', () async {
      final TeleConsultation visit = await seedConsultation();
      final TeleConsultation waiting = await admit.call(
        policy: policyWith(runner),
        original: visit,
      );

      expect(waiting.status, TeleConsultationStatus.waiting);
      expect(waiting.waitingAt, isNotNull);
      expect((await repository.consultationById(visit.id))!.isWaiting, isTrue);
    });

    test('a call starts only from the waiting room', () async {
      final TeleConsultation visit = await seedConsultation();
      expect(
        start.call(policy: policyWith(runner), original: visit),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'tele_consultation_not_waiting',
          ),
        ),
      );
    });

    test(
      'starting stamps the in-call state and keeps the queue timestamps',
      () async {
        final TeleConsultation waiting = await seedConsultation(
          status: TeleConsultationStatus.waiting,
        );
        final TeleConsultation inCall = await start.call(
          policy: policyWith(runner),
          original: waiting,
        );

        expect(inCall.status, TeleConsultationStatus.inCall);
        expect(inCall.startedAt, isNotNull);
        expect(inCall.waitingAt, waiting.waitingAt);
        expect(inCall.reason, waiting.reason);
      },
    );

    test('a consultation completes only from an in-call state', () async {
      final TeleConsultation waiting = await seedConsultation(
        status: TeleConsultationStatus.waiting,
      );
      expect(
        complete.call(policy: policyWith(runner), original: waiting),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'tele_consultation_not_in_call',
          ),
        ),
      );
    });

    test('completing stamps the completed state', () async {
      final TeleConsultation inCall = await seedConsultation(
        status: TeleConsultationStatus.inCall,
      );
      final TeleConsultation done = await complete.call(
        policy: policyWith(runner),
        original: inCall,
      );

      expect(done.status, TeleConsultationStatus.completed);
      expect(done.completedAt, isNotNull);
      expect(done.isTerminal, isTrue);
    });

    test('a no-show is recorded before the call starts', () async {
      final TeleConsultation inCall = await seedConsultation(
        status: TeleConsultationStatus.inCall,
      );
      expect(
        noShow.call(policy: policyWith(runner), original: inCall),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'tele_consultation_in_call',
          ),
        ),
      );
    });

    test('a closed consultation cannot become a no-show', () async {
      final TeleConsultation done = await seedConsultation(
        status: TeleConsultationStatus.completed,
      );
      expect(
        noShow.call(policy: policyWith(runner), original: done),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'tele_consultation_closed',
          ),
        ),
      );
    });

    test('a no-show stamps the waiting room exit', () async {
      final TeleConsultation waiting = await seedConsultation(
        status: TeleConsultationStatus.waiting,
      );
      final TeleConsultation missed = await noShow.call(
        policy: policyWith(runner),
        original: waiting,
      );

      expect(missed.status, TeleConsultationStatus.noShow);
      expect(missed.noShowAt, isNotNull);
      expect(missed.isTerminal, isTrue);
    });

    test('cancelling requires a reason and freezes the visit', () async {
      final TeleConsultation visit = await seedConsultation();
      expect(
        cancel.call(policy: policyWith(runner), original: visit, reason: ' '),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'tele_cancellation_reason_required',
          ),
        ),
      );

      final TeleConsultation cancelled = await cancel.call(
        policy: policyWith(runner),
        original: visit,
        reason: ' Patient unwell. ',
      );
      expect(cancelled.status, TeleConsultationStatus.cancelled);
      expect(cancelled.cancellationReason, 'Patient unwell.');
      expect(cancelled.cancelledAt, isNotNull);
      expect(cancelled.isTerminal, isTrue);
    });

    test('a closed visit cannot be cancelled', () async {
      final TeleConsultation done = await seedConsultation(
        status: TeleConsultationStatus.completed,
      );
      expect(
        cancel.call(
          policy: policyWith(runner),
          original: done,
          reason: 'Too late.',
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'tele_consultation_closed',
          ),
        ),
      );
    });
  });

  group('live vitals', () {
    test('recording vitals requires tele_vitals.record', () async {
      final TeleConsultation inCall = await seedConsultation(
        status: TeleConsultationStatus.inCall,
      );
      expect(
        recordVitals.call(
          policy: policyWith(runner),
          consultation: inCall,
          observedBy: 'nurse-1',
          heartRateBpm: 88,
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('vitals are observed only during a call', () async {
      final TeleConsultation waiting = await seedConsultation(
        status: TeleConsultationStatus.waiting,
      );
      expect(
        recordVitals.call(
          policy: policyWith(vitalsReader),
          consultation: waiting,
          observedBy: 'nurse-1',
          heartRateBpm: 88,
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'tele_consultation_not_in_call',
          ),
        ),
      );
    });

    test('implausible readings are rejected', () async {
      final TeleConsultation inCall = await seedConsultation(
        status: TeleConsultationStatus.inCall,
      );
      expect(
        recordVitals.call(
          policy: policyWith(vitalsReader),
          consultation: inCall,
          observedBy: 'nurse-1',
          heartRateBpm: 400,
          spo2Pct: 40,
          temperatureC: 50,
        ),
        throwsA(
          isA<ValidationError>()
              .having(
                (ValidationError error) => error.code,
                'code',
                'tele_vitals_invalid',
              )
              .having(
                (ValidationError error) => error.fieldErrors.keys,
                'fields',
                containsAll(<String>{
                  'heart_rate_bpm',
                  'spo2_pct',
                  'temperature_c',
                }),
              ),
        ),
      );
    });

    test('an empty reading is rejected', () async {
      final TeleConsultation inCall = await seedConsultation(
        status: TeleConsultationStatus.inCall,
      );
      expect(
        recordVitals.call(
          policy: policyWith(vitalsReader),
          consultation: inCall,
          observedBy: 'nurse-1',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'tele_vitals_invalid',
          ),
        ),
      );
    });

    test('a reading is recorded against the in-call consultation', () async {
      final TeleConsultation inCall = await seedConsultation(
        status: TeleConsultationStatus.inCall,
      );
      final TeleVitalsOverlay overlay = await recordVitals.call(
        policy: policyWith(vitalsReader),
        consultation: inCall,
        observedBy: 'nurse-1',
        heartRateBpm: 88,
        spo2Pct: 96,
        notes: '  Comfortable.  ',
      );

      expect(overlay.heartRateBpm, 88);
      expect(overlay.spo2Pct, 96);
      expect(overlay.notes, 'Comfortable.');
      expect(overlay.consultationId, inCall.id);
      expect(
        (await repository.overlaysForConsultation(inCall.id)).single.id,
        overlay.id,
      );
    });
  });

  group('archiving', () {
    test('archiving requires tele_archive.write', () async {
      final TeleConsultation done = await seedConsultation(
        status: TeleConsultationStatus.completed,
      );
      expect(
        archive.call(
          policy: policyWith(runner),
          consultation: done,
          archivedBy: 'doctor-1',
          durationSeconds: 1200,
          consentRecorded: true,
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('only a completed consultation can be archived', () async {
      final TeleConsultation inCall = await seedConsultation(
        status: TeleConsultationStatus.inCall,
      );
      expect(
        archive.call(
          policy: policyWith(archivist),
          consultation: inCall,
          archivedBy: 'doctor-1',
          durationSeconds: 1200,
          consentRecorded: true,
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'tele_consultation_not_completed',
          ),
        ),
      );
    });

    test('archiving without recorded consent is refused', () async {
      final TeleConsultation done = await seedConsultation(
        status: TeleConsultationStatus.completed,
      );
      expect(
        archive.call(
          policy: policyWith(archivist),
          consultation: done,
          archivedBy: 'doctor-1',
          durationSeconds: 1200,
          consentRecorded: false,
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'tele_consent_required',
          ),
        ),
      );
    });

    test('a nonsensical duration is rejected', () async {
      final TeleConsultation done = await seedConsultation(
        status: TeleConsultationStatus.completed,
      );
      expect(
        archive.call(
          policy: policyWith(archivist),
          consultation: done,
          archivedBy: 'doctor-1',
          durationSeconds: 0,
          consentRecorded: true,
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'tele_archive_invalid',
          ),
        ),
      );
    });

    test('a completed visit is archived once, with consent', () async {
      final TeleConsultation done = await seedConsultation(
        status: TeleConsultationStatus.completed,
      );
      final TeleConsultationArchive archived = await archive.call(
        policy: policyWith(archivist),
        consultation: done,
        archivedBy: 'doctor-1',
        durationSeconds: 1200,
        consentRecorded: true,
        recordingReference: '  object://tele/consultation-1.m4a  ',
      );

      expect(archived.consentRecorded, isTrue);
      expect(archived.durationSeconds, 1200);
      expect(archived.recordingReference, 'object://tele/consultation-1.m4a');
      expect(
        (await repository.archiveForConsultation(done.id))!.id,
        archived.id,
      );
      expect(
        archive.call(
          policy: policyWith(archivist),
          consultation: done,
          archivedBy: 'doctor-2',
          durationSeconds: 900,
          consentRecorded: true,
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'tele_archive_exists',
          ),
        ),
      );
    });
  });
}
