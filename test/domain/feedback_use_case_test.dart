/// Tests for the feedback and grievance use cases, the derived net promoter
/// score and the two deadline rules (Module 36).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/authorization_snapshot.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/domain/feedback/feedback.dart';
import 'package:nodex_hms/domain/feedback/feedback_repository.dart';
import 'package:nodex_hms/domain/feedback/feedback_use_cases.dart';

import 'feedback_repository_test.dart' show FakeFeedbackStore;

AuthorizationPolicy policyWith(
  Set<String> permissions, {
  ConnectivityState connectivity = ConnectivityState.online,
  Set<String>? offlinePermissions,
}) {
  final DateTime issuedAt = DateTime.now().toUtc();
  return AuthorizationPolicy(
    snapshot: AuthorizationSnapshot(
      snapshotId: 'snapshot-1',
      tenantId: 'tenant-1',
      userId: 'admin-1',
      deviceId: 'device-1',
      revision: 1,
      issuedAt: issuedAt,
      expiresAt: issuedAt.add(const Duration(days: 30)),
      payloadDigest: 'digest',
      roles: const <String>{NodexRoles.hospitalSuperAdmin},
      permissions: permissions,
      offlinePermissions: connectivity.isOnline
          ? permissions
          : (offlinePermissions ?? const <String>{}),
      facilityIds: const <String>{'facility-1'},
      departmentIds: const <String>{'department-1', 'department-2'},
      wardIds: const <String>{},
    ),
    connectivity: connectivity,
  );
}

void main() {
  late FakeFeedbackStore store;
  late DefaultFeedbackRepository repository;
  late RecordSurveyUseCase recordSurvey;
  late ActionSurveyUseCase actionSurvey;
  late VoidSurveyUseCase voidSurvey;
  late LogComplaintUseCase logComplaint;
  late AcknowledgeComplaintUseCase acknowledgeComplaint;
  late RouteComplaintUseCase routeComplaint;
  late EscalateComplaintUseCase escalateComplaint;
  late InvestigateComplaintUseCase investigateComplaint;
  late ResolveComplaintUseCase resolveComplaint;
  late CloseComplaintUseCase closeComplaint;
  late DismissComplaintUseCase dismissComplaint;
  late VoidComplaintUseCase voidComplaint;
  late ReadFeedbackHubUseCase readHub;

  const Set<String> canRead = <String>{NodexPermissions.feedbackRead};
  const Set<String> canRecord = <String>{NodexPermissions.feedbackRecord};
  const Set<String> canResolve = <String>{NodexPermissions.feedbackResolve};

  final AuthorizationPolicy reader = policyWith(canRead);
  final AuthorizationPolicy desk = policyWith(canRecord);
  final AuthorizationPolicy manager = policyWith(canResolve);
  final DateTime now = DateTime.utc(2026, 6, 14, 12);

  setUp(() {
    store = FakeFeedbackStore();
    repository = DefaultFeedbackRepository(
      store: store,
      logger: NodexLogger(
        sinks: <NodexLogSink>[InMemoryLogSink()],
        minimumLevel: NodexLogLevel.trace,
      ),
    );
    recordSurvey = RecordSurveyUseCase(repository: repository);
    actionSurvey = ActionSurveyUseCase(repository: repository);
    voidSurvey = VoidSurveyUseCase(repository: repository);
    logComplaint = LogComplaintUseCase(repository: repository);
    acknowledgeComplaint = AcknowledgeComplaintUseCase(repository: repository);
    routeComplaint = RouteComplaintUseCase(repository: repository);
    escalateComplaint = EscalateComplaintUseCase(repository: repository);
    investigateComplaint = InvestigateComplaintUseCase(repository: repository);
    resolveComplaint = ResolveComplaintUseCase(repository: repository);
    closeComplaint = CloseComplaintUseCase(repository: repository);
    dismissComplaint = DismissComplaintUseCase(repository: repository);
    voidComplaint = VoidComplaintUseCase(repository: repository);
    readHub = ReadFeedbackHubUseCase(repository: repository);
  });

  Future<String> seedSurvey({
    String id = '',
    int score = 9,
    String number = 'SV-1',
    DateTime? recordedAt,
  }) => recordSurvey(
    policy: desk,
    tenantId: 'tenant-1',
    facilityId: 'facility-1',
    surveyNumber: number,
    npsScore: score,
    recordedBy: 'admin-1',
    createdBy: 'admin-1',
    recordedAt: recordedAt ?? DateTime.utc(2026, 6, 12, 9),
    surveyId: id,
  );

  Future<String> seedComplaint({
    String id = '',
    String number = 'CMP-1',
    ComplaintSeverity severity = ComplaintSeverity.high,
    String? departmentId,
    DateTime? receivedAt,
    String status = 'logged',
  }) async {
    final String created = await logComplaint(
      policy: desk,
      tenantId: 'tenant-1',
      facilityId: 'facility-1',
      complaintNumber: number,
      complainantName: 'Rahima Begum',
      description: 'Waited three hours in the OPD queue.',
      loggedBy: 'admin-1',
      createdBy: 'admin-1',
      category: ComplaintCategory.waitingTime,
      severity: severity,
      routedDepartmentId: departmentId,
      receivedAt: receivedAt ?? DateTime.utc(2026, 6, 11, 8),
      complaintId: id,
    );
    if (status != 'logged') {
      await repository.updateComplaint(
        created,
        complaintAcknowledgeChanges(at: DateTime.utc(2026, 6, 11, 9)),
      );
    }
    if (status == 'investigating' ||
        status == 'resolved' ||
        status == 'closed' ||
        status == 'dismissed') {
      await repository.updateComplaint(
        created,
        complaintInvestigateChanges(at: DateTime.utc(2026, 6, 11, 10)),
      );
    }
    if (status == 'resolved' || status == 'closed') {
      await repository.updateComplaint(
        created,
        complaintResolveChanges(
          summary: 'Queue re-opened and triage staffed',
          resolvedBy: 'admin-1',
          at: DateTime.utc(2026, 6, 12, 10),
        ),
      );
    }
    if (status == 'closed') {
      await repository.updateComplaint(
        created,
        complaintCloseChanges(
          note: 'Complainant informed by phone',
          at: DateTime.utc(2026, 6, 13, 10),
        ),
      );
    }
    if (status == 'dismissed') {
      await repository.updateComplaint(
        created,
        complaintDismissChanges(
          reason: 'Attended elsewhere',
          at: DateTime.utc(2026, 6, 12, 10),
        ),
      );
    }
    return created;
  }

  group('survey state machine', () {
    test('a recorded response is followed up or withdrawn', () {
      expect(
        surveyCanTransition(SurveyStatus.recorded, SurveyStatus.actioned),
        isTrue,
      );
      expect(
        surveyCanTransition(SurveyStatus.recorded, SurveyStatus.voided),
        isTrue,
      );
      expect(SurveyStatus.recorded.isTerminal, isFalse);
    });

    test('a settled response goes nowhere', () {
      expect(
        surveyCanTransition(SurveyStatus.actioned, SurveyStatus.voided),
        isFalse,
      );
      expect(
        surveyCanTransition(SurveyStatus.voided, SurveyStatus.actioned),
        isFalse,
      );
      expect(SurveyStatus.actioned.isTerminal, isTrue);
      expect(SurveyStatus.voided.isTerminal, isTrue);
    });
  });

  group('grievance state machine', () {
    test('a grievance runs logged to closed one stage at a time', () {
      expect(
        complaintCanTransition(
          ComplaintStatus.logged,
          ComplaintStatus.acknowledged,
        ),
        isTrue,
      );
      expect(
        complaintCanTransition(
          ComplaintStatus.acknowledged,
          ComplaintStatus.investigating,
        ),
        isTrue,
      );
      expect(
        complaintCanTransition(
          ComplaintStatus.investigating,
          ComplaintStatus.resolved,
        ),
        isTrue,
      );
      expect(
        complaintCanTransition(
          ComplaintStatus.resolved,
          ComplaintStatus.closed,
        ),
        isTrue,
      );
      expect(
        complaintCanTransition(
          ComplaintStatus.logged,
          ComplaintStatus.resolved,
        ),
        isFalse,
      );
      expect(
        complaintCanTransition(
          ComplaintStatus.acknowledged,
          ComplaintStatus.closed,
        ),
        isFalse,
      );
    });

    test('anything live can be dismissed, only a fresh one withdrawn', () {
      expect(
        complaintCanTransition(
          ComplaintStatus.logged,
          ComplaintStatus.dismissed,
        ),
        isTrue,
      );
      expect(
        complaintCanTransition(
          ComplaintStatus.acknowledged,
          ComplaintStatus.dismissed,
        ),
        isTrue,
      );
      expect(
        complaintCanTransition(
          ComplaintStatus.investigating,
          ComplaintStatus.dismissed,
        ),
        isTrue,
      );
      expect(
        complaintCanTransition(
          ComplaintStatus.acknowledged,
          ComplaintStatus.voided,
        ),
        isFalse,
      );
      expect(
        complaintCanTransition(
          ComplaintStatus.resolved,
          ComplaintStatus.dismissed,
        ),
        isFalse,
      );
    });

    test('a settled grievance goes nowhere', () {
      expect(ComplaintStatus.closed.isTerminal, isTrue);
      expect(ComplaintStatus.dismissed.isTerminal, isTrue);
      expect(ComplaintStatus.voided.isTerminal, isTrue);
      expect(ComplaintStatus.logged.isLive, isTrue);
      expect(ComplaintStatus.logged.awaitsAcknowledgement, isTrue);
      expect(ComplaintStatus.acknowledged.awaitsAcknowledgement, isFalse);
      expect(ComplaintStatus.acknowledged.awaitsResolution, isTrue);
      expect(ComplaintStatus.resolved.awaitsResolution, isFalse);
    });
  });

  group('derived net promoter score', () {
    test('the band is the definition, not a setting', () {
      expect(npsBand(10), NpsBand.promoter);
      expect(npsBand(9), NpsBand.promoter);
      expect(npsBand(8), NpsBand.passive);
      expect(npsBand(7), NpsBand.passive);
      expect(npsBand(6), NpsBand.detractor);
      expect(npsBand(0), NpsBand.detractor);
    });

    test('promoters minus detractors over the total', () {
      expect(netPromoterScore(<int>[10, 9, 8, 6]), closeTo(25, 0.001));
    });

    test('all promoters is a hundred', () {
      expect(netPromoterScore(<int>[10, 9, 9]), closeTo(100, 0.001));
    });

    test('all detractors is minus a hundred', () {
      expect(netPromoterScore(<int>[0, 3, 6]), closeTo(-100, 0.001));
    });

    test('no responses has no score', () {
      expect(netPromoterScore(const <int>[]), isNull);
    });

    test('a detractor unfollowed past the window is overdue', () async {
      final String id = await seedSurvey(
        score: 4,
        recordedAt: DateTime.utc(2026, 6, 1, 9),
      );
      final FeedbackSurvey survey = (await repository.surveyById(id))!;
      expect(survey.isDetractor, isTrue);
      expect(isSurveyFollowUpOverdue(survey: survey, now: now), isTrue);
    });

    test('a detractor within the window is not overdue', () async {
      final String id = await seedSurvey(
        score: 4,
        recordedAt: DateTime.utc(2026, 6, 13, 9),
      );
      expect(
        isSurveyFollowUpOverdue(
          survey: (await repository.surveyById(id))!,
          now: now,
        ),
        isFalse,
      );
    });

    test('a promoter is never overdue for a follow-up', () async {
      final String id = await seedSurvey(
        score: 10,
        recordedAt: DateTime.utc(2026, 6, 1, 9),
      );
      expect(
        isSurveyFollowUpOverdue(
          survey: (await repository.surveyById(id))!,
          now: now,
        ),
        isFalse,
      );
    });

    test('a followed-up detractor is no longer overdue', () async {
      final String id = await seedSurvey(
        score: 4,
        recordedAt: DateTime.utc(2026, 6, 1, 9),
      );
      await actionSurvey(
        policy: manager,
        survey: (await repository.surveyById(id))!,
        note: 'Called the patient back',
        actionedBy: 'admin-1',
      );
      expect(
        isSurveyFollowUpOverdue(
          survey: (await repository.surveyById(id))!,
          now: now,
        ),
        isFalse,
      );
    });
  });

  group('derived grievance deadlines', () {
    test('acknowledgement is a day and resolution is set by severity', () {
      expect(complaintAcknowledgementWindow, const Duration(hours: 24));
      expect(
        complaintResolutionWindow(ComplaintSeverity.high),
        const Duration(days: 3),
      );
      expect(
        complaintResolutionWindow(ComplaintSeverity.medium),
        const Duration(days: 7),
      );
      expect(
        complaintResolutionWindow(ComplaintSeverity.low),
        const Duration(days: 14),
      );
    });

    test('a grievance unreceived-acknowledged for a day is overdue', () async {
      final String id = await seedComplaint(
        receivedAt: DateTime.utc(2026, 6, 10, 8),
      );
      final FeedbackComplaint complaint = (await repository.complaintById(id))!;
      expect(complaint.isUnacknowledged, isTrue);
      expect(
        isComplaintAcknowledgementOverdue(complaint: complaint, now: now),
        isTrue,
      );
      expect(
        isComplaintResolutionOverdue(complaint: complaint, now: now),
        isTrue,
      );
      expect(isComplaintSlaBreached(complaint: complaint, now: now), isTrue);
    });

    test('a fresh grievance is not overdue', () async {
      final String id = await seedComplaint(
        receivedAt: DateTime.utc(2026, 6, 14, 9),
      );
      final FeedbackComplaint complaint = (await repository.complaintById(id))!;
      expect(
        isComplaintAcknowledgementOverdue(complaint: complaint, now: now),
        isFalse,
      );
      expect(isComplaintSlaBreached(complaint: complaint, now: now), isFalse);
    });

    test('an acknowledged grievance is past acknowledgement only', () async {
      final String id = await seedComplaint(
        status: 'acknowledged',
        receivedAt: DateTime.utc(2026, 6, 11, 8),
      );
      final FeedbackComplaint complaint = (await repository.complaintById(id))!;
      expect(
        isComplaintAcknowledgementOverdue(complaint: complaint, now: now),
        isFalse,
      );
      expect(
        isComplaintResolutionOverdue(complaint: complaint, now: now),
        isTrue,
      );
    });

    test(
      'a high-severity grievance past three days is past resolution',
      () async {
        final String id = await seedComplaint(
          severity: ComplaintSeverity.high,
          receivedAt: DateTime.utc(2026, 6, 10, 8),
        );
        expect(
          isComplaintResolutionOverdue(
            complaint: (await repository.complaintById(id))!,
            now: now,
          ),
          isTrue,
        );
      },
    );

    test('a low-severity grievance within its fortnight is not', () async {
      final String id = await seedComplaint(
        severity: ComplaintSeverity.low,
        receivedAt: DateTime.utc(2026, 6, 10, 8),
      );
      expect(
        isComplaintResolutionOverdue(
          complaint: (await repository.complaintById(id))!,
          now: now,
        ),
        isFalse,
      );
    });

    test('a resolved grievance is not overdue however slow it was', () async {
      final String id = await seedComplaint(
        status: 'resolved',
        receivedAt: DateTime.utc(2026, 6, 1, 8),
      );
      final FeedbackComplaint complaint = (await repository.complaintById(id))!;
      expect(complaint.isResolved, isTrue);
      expect(isComplaintSlaBreached(complaint: complaint, now: now), isFalse);
    });
  });

  group('recording a response', () {
    test('records a response with its touchpoint and score', () async {
      final String id = await seedSurvey(score: 8);
      final FeedbackSurvey survey = (await repository.surveyById(id))!;
      expect(survey.status, SurveyStatus.recorded);
      expect(survey.npsScore, 8);
      expect(survey.band, NpsBand.passive);
      expect(survey.touchpoint, FeedbackTouchpoint.opd);
      expect(survey.actionNote, isNull);
    });

    test(
      'refuses a number, a score outside the range and no recorder',
      () async {
        await expectLater(
          recordSurvey(
            policy: desk,
            tenantId: 'tenant-1',
            facilityId: 'facility-1',
            surveyNumber: '  ',
            npsScore: 11,
            recordedBy: '',
            createdBy: 'admin-1',
          ),
          throwsA(
            isA<ValidationError>().having(
              (ValidationError error) => error.fieldErrors.keys.toSet(),
              'fields',
              containsAll(<String>[
                'survey_number',
                'nps_score',
                'recorded_by',
              ]),
            ),
          ),
        );
      },
    );

    test('refuses a second response with the same number', () async {
      await seedSurvey(number: 'SV-7');
      await expectLater(
        recordSurvey(
          policy: desk,
          tenantId: 'tenant-1',
          facilityId: 'facility-1',
          surveyNumber: 'SV-7',
          npsScore: 10,
          recordedBy: 'admin-1',
          createdBy: 'admin-1',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'feedback_survey_number_duplicate',
          ),
        ),
      );
    });

    test(
      'a caller without the record permission cannot capture a response',
      () async {
        await expectLater(
          recordSurvey(
            policy: reader,
            tenantId: 'tenant-1',
            facilityId: 'facility-1',
            surveyNumber: 'SV-8',
            npsScore: 10,
            recordedBy: 'admin-1',
            createdBy: 'admin-1',
          ),
          throwsA(isA<AuthorizationError>()),
        );
      },
    );
  });

  group('acting on a response', () {
    test('following up records the note and who did it', () async {
      final String id = await seedSurvey(score: 3);
      await actionSurvey(
        policy: manager,
        survey: (await repository.surveyById(id))!,
        note: 'Consultant called the family',
        actionedBy: 'admin-1',
        at: now,
      );
      final FeedbackSurvey survey = (await repository.surveyById(id))!;
      expect(survey.status, SurveyStatus.actioned);
      expect(survey.actionNote, 'Consultant called the family');
      expect(survey.actionedBy, 'admin-1');
      expect(survey.actionedAt, now);
    });

    test('following up without a note is refused', () async {
      final String id = await seedSurvey(score: 3);
      await expectLater(
        actionSurvey(
          policy: manager,
          survey: (await repository.surveyById(id))!,
          note: '   ',
          actionedBy: 'admin-1',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'feedback_action_note_missing',
          ),
        ),
      );
    });

    test('a settled response cannot be followed up twice', () async {
      final String id = await seedSurvey(score: 3);
      await actionSurvey(
        policy: manager,
        survey: (await repository.surveyById(id))!,
        note: 'Called back',
        actionedBy: 'admin-1',
      );
      await expectLater(
        actionSurvey(
          policy: manager,
          survey: (await repository.surveyById(id))!,
          note: 'Called again',
          actionedBy: 'admin-1',
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'feedback_survey_transition_invalid',
          ),
        ),
      );
    });

    test('withdrawing records the reason', () async {
      final String id = await seedSurvey();
      await voidSurvey(
        policy: manager,
        survey: (await repository.surveyById(id))!,
        reason: 'Filed against the wrong patient',
        at: now,
      );
      final FeedbackSurvey survey = (await repository.surveyById(id))!;
      expect(survey.status, SurveyStatus.voided);
      expect(survey.voidReason, 'Filed against the wrong patient');
      expect(survey.voidedAt, now);
    });

    test('withdrawing without a reason is refused', () async {
      final String id = await seedSurvey();
      await expectLater(
        voidSurvey(
          policy: manager,
          survey: (await repository.surveyById(id))!,
          reason: ' ',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'feedback_void_reason_missing',
          ),
        ),
      );
    });

    test('a reader cannot act on a response', () async {
      final String id = await seedSurvey(score: 3);
      await expectLater(
        actionSurvey(
          policy: reader,
          survey: (await repository.surveyById(id))!,
          note: 'Called back',
          actionedBy: 'admin-1',
        ),
        throwsA(isA<AuthorizationError>()),
      );
      await expectLater(
        voidSurvey(
          policy: reader,
          survey: (await repository.surveyById(id))!,
          reason: 'Duplicate',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });
  });

  group('logging a grievance', () {
    test(
      'records a grievance with its channel, category and severity',
      () async {
        final String id = await seedComplaint();
        final FeedbackComplaint complaint = (await repository.complaintById(
          id,
        ))!;
        expect(complaint.status, ComplaintStatus.logged);
        expect(complaint.channel, ComplaintChannel.counter);
        expect(complaint.category, ComplaintCategory.waitingTime);
        expect(complaint.severity, ComplaintSeverity.high);
        expect(complaint.loggedBy, 'admin-1');
        expect(complaint.acknowledgedAt, isNull);
        expect(complaint.resolutionWindow, const Duration(days: 3));
      },
    );

    test('the intake event opens the routing history', () async {
      final String id = await logComplaint(
        policy: desk,
        tenantId: 'tenant-1',
        facilityId: 'facility-1',
        complaintNumber: 'CMP-9',
        complainantName: 'Rahima Begum',
        description: 'No seats in the waiting area.',
        loggedBy: 'admin-1',
        createdBy: 'admin-1',
        routedDepartmentId: 'department-1',
        receivedAt: DateTime.utc(2026, 6, 11, 8),
      );
      final List<ComplaintRoutingEvent> events = await readHub.routingHistory(
        policy: reader,
        tenantId: 'tenant-1',
        complaintId: id,
      );
      expect(events, hasLength(1));
      expect(events.single.eventType, RoutingEventType.logged);
      expect(events.single.note, 'Grievance taken at intake.');
      expect(events.single.recordedBy, 'admin-1');
      expect(events.single.occurredAt, DateTime.utc(2026, 6, 11, 8));
      expect(events.single.isMovement, isFalse);
    });

    test('refuses a grievance with no number, name or description', () async {
      await expectLater(
        logComplaint(
          policy: desk,
          tenantId: 'tenant-1',
          facilityId: 'facility-1',
          complaintNumber: ' ',
          complainantName: '',
          description: '   ',
          loggedBy: 'admin-1',
          createdBy: 'admin-1',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.fieldErrors.keys.toSet(),
            'fields',
            containsAll(<String>[
              'complaint_number',
              'complainant_name',
              'description',
            ]),
          ),
        ),
      );
    });

    test('refuses a second grievance with the same number', () async {
      await seedComplaint(number: 'CMP-7');
      await expectLater(
        logComplaint(
          policy: desk,
          tenantId: 'tenant-1',
          facilityId: 'facility-1',
          complaintNumber: 'CMP-7',
          complainantName: 'Karim Mia',
          description: 'The same grievance filed twice.',
          loggedBy: 'admin-1',
          createdBy: 'admin-1',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'feedback_complaint_number_duplicate',
          ),
        ),
      );
    });

    test('a caller without the record permission cannot log', () async {
      await expectLater(
        logComplaint(
          policy: reader,
          tenantId: 'tenant-1',
          facilityId: 'facility-1',
          complaintNumber: 'CMP-8',
          complainantName: 'Karim Mia',
          description: 'No seats in the waiting area.',
          loggedBy: 'admin-1',
          createdBy: 'admin-1',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });
  });

  group('working a grievance', () {
    test('acknowledging records the moment', () async {
      final String id = await seedComplaint();
      await acknowledgeComplaint(
        policy: manager,
        complaint: (await repository.complaintById(id))!,
        at: now,
      );
      final FeedbackComplaint complaint = (await repository.complaintById(id))!;
      expect(complaint.status, ComplaintStatus.acknowledged);
      expect(complaint.acknowledgedAt, now);
    });

    test('an acknowledged grievance cannot be acknowledged again', () async {
      final String id = await seedComplaint(status: 'acknowledged');
      await expectLater(
        acknowledgeComplaint(
          policy: manager,
          complaint: (await repository.complaintById(id))!,
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'feedback_complaint_transition_invalid',
          ),
        ),
      );
    });

    test('routing sends the case to a department and logs the move', () async {
      final String id = await seedComplaint();
      await routeComplaint(
        policy: manager,
        complaint: (await repository.complaintById(id))!,
        note: 'Sent to the OPD manager.',
        recordedBy: 'admin-1',
        departmentId: 'department-1',
        at: now,
      );
      final FeedbackComplaint complaint = (await repository.complaintById(id))!;
      expect(complaint.routedDepartmentId, 'department-1');
      expect(complaint.routedAt, now);
      expect(complaint.status, ComplaintStatus.logged);
      final List<ComplaintRoutingEvent> events = await readHub.routingHistory(
        policy: reader,
        tenantId: 'tenant-1',
        complaintId: id,
      );
      final ComplaintRoutingEvent last = events.last;
      expect(last.eventType, RoutingEventType.routed);
      expect(last.toDepartmentId, 'department-1');
      expect(last.fromDepartmentId, isNull);
      expect(last.isMovement, isTrue);
    });

    test('routing a case that already has an owner re-routes it', () async {
      final String id = await seedComplaint(departmentId: 'department-1');
      await routeComplaint(
        policy: manager,
        complaint: (await repository.complaintById(id))!,
        note: 'Moved to housekeeping.',
        recordedBy: 'admin-1',
        departmentId: 'department-2',
        routedTo: 'user-3',
        at: now,
      );
      final FeedbackComplaint complaint = (await repository.complaintById(id))!;
      expect(complaint.routedDepartmentId, 'department-2');
      expect(complaint.routedTo, 'user-3');
      final List<ComplaintRoutingEvent> events = await readHub.routingHistory(
        policy: reader,
        tenantId: 'tenant-1',
        complaintId: id,
      );
      final ComplaintRoutingEvent last = events.last;
      expect(last.eventType, RoutingEventType.rerouted);
      expect(last.fromDepartmentId, 'department-1');
      expect(last.toDepartmentId, 'department-2');
    });

    test('routing with no destination is refused', () async {
      final String id = await seedComplaint();
      await expectLater(
        routeComplaint(
          policy: manager,
          complaint: (await repository.complaintById(id))!,
          note: 'Nowhere in particular.',
          recordedBy: 'admin-1',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'feedback_routing_target_missing',
          ),
        ),
      );
    });

    test('a settled grievance cannot be re-routed', () async {
      final String id = await seedComplaint(status: 'closed');
      await expectLater(
        routeComplaint(
          policy: manager,
          complaint: (await repository.complaintById(id))!,
          note: 'Too late.',
          recordedBy: 'admin-1',
          departmentId: 'department-2',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test(
      'escalating leaves the case where it is and logs the escalation',
      () async {
        final String id = await seedComplaint(departmentId: 'department-1');
        await escalateComplaint(
          policy: manager,
          complaint: (await repository.complaintById(id))!,
          note: 'Third day without an answer.',
          recordedBy: 'admin-1',
          toDepartmentId: 'department-2',
          at: now,
        );
        final FeedbackComplaint complaint = (await repository.complaintById(
          id,
        ))!;
        expect(complaint.routedDepartmentId, 'department-1');
        final List<ComplaintRoutingEvent> events = await readHub.routingHistory(
          policy: reader,
          tenantId: 'tenant-1',
          complaintId: id,
        );
        expect(events.last.eventType, RoutingEventType.escalated);
        expect(events.last.note, 'Third day without an answer.');
        expect(events.last.toDepartmentId, 'department-2');
      },
    );

    test('escalating needs a reason', () async {
      final String id = await seedComplaint();
      await expectLater(
        escalateComplaint(
          policy: manager,
          complaint: (await repository.complaintById(id))!,
          note: '  ',
          recordedBy: 'admin-1',
        ),
        throwsA(isA<ValidationError>()),
      );
    });

    test('investigating records the moment', () async {
      final String id = await seedComplaint(status: 'acknowledged');
      await investigateComplaint(
        policy: manager,
        complaint: (await repository.complaintById(id))!,
        at: now,
      );
      final FeedbackComplaint complaint = (await repository.complaintById(id))!;
      expect(complaint.status, ComplaintStatus.investigating);
      expect(complaint.investigationStartedAt, now);
    });

    test('an investigation follows the acknowledgement', () async {
      final String id = await seedComplaint();
      await expectLater(
        investigateComplaint(
          policy: manager,
          complaint: (await repository.complaintById(id))!,
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('answering records the answer and who gave it', () async {
      final String id = await seedComplaint(status: 'investigating');
      await resolveComplaint(
        policy: manager,
        complaint: (await repository.complaintById(id))!,
        summary: 'Second triage nurse rostered at peak.',
        resolvedBy: 'admin-1',
        at: now,
      );
      final FeedbackComplaint complaint = (await repository.complaintById(id))!;
      expect(complaint.status, ComplaintStatus.resolved);
      expect(
        complaint.resolutionSummary,
        'Second triage nurse rostered at peak.',
      );
      expect(complaint.resolvedBy, 'admin-1');
      expect(complaint.resolvedAt, now);
    });

    test('answering without a summary or an author is refused', () async {
      final String id = await seedComplaint(status: 'investigating');
      await expectLater(
        resolveComplaint(
          policy: manager,
          complaint: (await repository.complaintById(id))!,
          summary: '  ',
          resolvedBy: '',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'feedback_resolution_invalid',
          ),
        ),
      );
    });

    test('a grievance cannot be answered before the investigation', () async {
      final String id = await seedComplaint(status: 'acknowledged');
      await expectLater(
        resolveComplaint(
          policy: manager,
          complaint: (await repository.complaintById(id))!,
          summary: 'Nothing was looked into.',
          resolvedBy: 'admin-1',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('closing records how the complainant was told', () async {
      final String id = await seedComplaint(status: 'resolved');
      await closeComplaint(
        policy: manager,
        complaint: (await repository.complaintById(id))!,
        note: 'Complainant informed by phone',
        at: now,
      );
      final FeedbackComplaint complaint = (await repository.complaintById(id))!;
      expect(complaint.status, ComplaintStatus.closed);
      expect(complaint.closureNote, 'Complainant informed by phone');
      expect(complaint.closedAt, now);
    });

    test('closing without a note is refused', () async {
      final String id = await seedComplaint(status: 'resolved');
      await expectLater(
        closeComplaint(
          policy: manager,
          complaint: (await repository.complaintById(id))!,
          note: '',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'feedback_closure_note_missing',
          ),
        ),
      );
    });

    test('a grievance cannot be closed before it is answered', () async {
      final String id = await seedComplaint(status: 'investigating');
      await expectLater(
        closeComplaint(
          policy: manager,
          complaint: (await repository.complaintById(id))!,
          note: 'Closed without an answer',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('dismissing records why it had no substance', () async {
      final String id = await seedComplaint(status: 'investigating');
      await dismissComplaint(
        policy: manager,
        complaint: (await repository.complaintById(id))!,
        reason: 'Patient was seen at another facility',
        at: now,
      );
      final FeedbackComplaint complaint = (await repository.complaintById(id))!;
      expect(complaint.status, ComplaintStatus.dismissed);
      expect(complaint.dismissReason, 'Patient was seen at another facility');
      expect(complaint.dismissedAt, now);
    });

    test('dismissing without a reason is refused', () async {
      final String id = await seedComplaint();
      await expectLater(
        dismissComplaint(
          policy: manager,
          complaint: (await repository.complaintById(id))!,
          reason: ' ',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'feedback_dismiss_reason_missing',
          ),
        ),
      );
    });

    test('withdrawing records the reason on a fresh grievance', () async {
      final String id = await seedComplaint();
      await voidComplaint(
        policy: manager,
        complaint: (await repository.complaintById(id))!,
        reason: 'Filed under the wrong patient',
        at: now,
      );
      final FeedbackComplaint complaint = (await repository.complaintById(id))!;
      expect(complaint.status, ComplaintStatus.voided);
      expect(complaint.voidReason, 'Filed under the wrong patient');
      expect(complaint.voidedAt, now);
    });

    test('an old grievance is dismissed rather than withdrawn', () async {
      final String id = await seedComplaint(status: 'acknowledged');
      await expectLater(
        voidComplaint(
          policy: manager,
          complaint: (await repository.complaintById(id))!,
          reason: 'Changed my mind',
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.message,
            'message',
            contains('dismissed'),
          ),
        ),
      );
    });

    test('a reader cannot work a grievance', () async {
      final String id = await seedComplaint();
      await expectLater(
        acknowledgeComplaint(
          policy: reader,
          complaint: (await repository.complaintById(id))!,
        ),
        throwsA(isA<AuthorizationError>()),
      );
      await expectLater(
        dismissComplaint(
          policy: reader,
          complaint: (await repository.complaintById(id))!,
          reason: 'No substance',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });
  });

  group('reading the board', () {
    test('lists the responses and the grievances', () async {
      await seedSurvey();
      await seedComplaint();
      final FeedbackBoard board = await readHub.board(
        policy: reader,
        tenantId: 'tenant-1',
        now: now,
      );
      expect(board.surveys, hasLength(1));
      expect(board.complaints, hasLength(1));
      expect(board.asOf, now);
    });

    test(
      'the board derives the net promoter score from the responses',
      () async {
        await seedSurvey(score: 10);
        await seedSurvey(score: 9, number: 'SV-2');
        await seedSurvey(score: 8, number: 'SV-3');
        await seedSurvey(score: 4, number: 'SV-4');
        final FeedbackBoard board = await readHub.board(
          policy: reader,
          tenantId: 'tenant-1',
          now: now,
        );
        expect(board.nps, closeTo(25, 0.001));
        expect(board.bandCounts[NpsBand.promoter], 2);
        expect(board.bandCounts[NpsBand.passive], 1);
        expect(board.bandCounts[NpsBand.detractor], 1);
      },
    );

    test('a withdrawn response does not count towards the score', () async {
      final String id = await seedSurvey(score: 0, number: 'SV-1');
      await seedSurvey(score: 10, number: 'SV-2');
      await voidSurvey(
        policy: manager,
        survey: (await repository.surveyById(id))!,
        reason: 'Duplicate',
      );
      final FeedbackBoard board = await readHub.board(
        policy: reader,
        tenantId: 'tenant-1',
        now: now,
      );
      expect(board.countedSurveys, hasLength(1));
      expect(board.nps, closeTo(100, 0.001));
    });

    test('the board lists live grievances before settled ones', () async {
      await seedComplaint(
        id: 'c-settled',
        number: 'CMP-1',
        status: 'closed',
        receivedAt: DateTime.utc(2026, 6, 1, 8),
      );
      await seedComplaint(
        id: 'c-live',
        number: 'CMP-2',
        receivedAt: DateTime.utc(2026, 6, 2, 8),
      );
      final FeedbackBoard board = await readHub.board(
        policy: reader,
        tenantId: 'tenant-1',
        now: now,
      );
      expect(board.complaints.first.id, 'c-live');
      expect(board.complaints.last.id, 'c-settled');
      expect(board.openComplaints.single.id, 'c-live');
    });

    test('the board lists the newest responses first', () async {
      await seedSurvey(
        id: 's-old',
        number: 'SV-1',
        recordedAt: DateTime.utc(2026, 6, 1, 8),
      );
      await seedSurvey(
        id: 's-new',
        number: 'SV-2',
        recordedAt: DateTime.utc(2026, 6, 13, 8),
      );
      final FeedbackBoard board = await readHub.board(
        policy: reader,
        tenantId: 'tenant-1',
        now: now,
      );
      expect(board.surveys.first.id, 's-new');
      expect(board.surveys.last.id, 's-old');
    });

    test('the board marks the detractors and the missed deadlines', () async {
      await seedSurvey(score: 2, recordedAt: DateTime.utc(2026, 6, 1, 8));
      await seedComplaint(receivedAt: DateTime.utc(2026, 6, 1, 8));
      final FeedbackBoard board = await readHub.board(
        policy: reader,
        tenantId: 'tenant-1',
        now: now,
      );
      expect(board.detractorsAwaitingFollowUp, hasLength(1));
      expect(board.followUpOverdue(board.surveys.single), isTrue);
      expect(board.unacknowledgedComplaints, hasLength(1));
      expect(board.slaBreached(board.complaints.single), isTrue);
      expect(board.hasOverdue, isTrue);
    });

    test(
      'hiding the settled records leaves only what still has to be worked',
      () async {
        await seedSurvey();
        await seedComplaint(id: 'c-1', number: 'CMP-1');
        await seedComplaint(id: 'c-2', number: 'CMP-2', status: 'closed');
        final List<FeedbackSurvey> liveSurveys = await readHub.surveys(
          policy: reader,
          tenantId: 'tenant-1',
          includeSettled: false,
        );
        expect(liveSurveys, hasLength(1));
        final List<FeedbackComplaint> liveComplaints = await readHub.complaints(
          policy: reader,
          tenantId: 'tenant-1',
          includeSettled: false,
        );
        expect(liveComplaints.single.id, 'c-1');
      },
    );

    test('filtering reaches the register', () async {
      await seedComplaint(
        id: 'c-1',
        number: 'CMP-1',
        departmentId: 'department-1',
      );
      await seedComplaint(
        id: 'c-2',
        number: 'CMP-2',
        departmentId: 'department-2',
      );
      final List<FeedbackComplaint> routed = await readHub.complaints(
        policy: reader,
        tenantId: 'tenant-1',
        departmentId: 'department-2',
      );
      expect(routed.single.id, 'c-2');
    });

    test('reading the board needs the read permission', () async {
      await expectLater(
        readHub.board(policy: desk, tenantId: 'tenant-1', now: now),
        throwsA(isA<AuthorizationError>()),
      );
      await expectLater(
        readHub.routingHistory(
          policy: manager,
          tenantId: 'tenant-1',
          complaintId: 'c-1',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('an offline reader sees the board they hold', () async {
      await seedSurvey();
      final FeedbackBoard board = await readHub.board(
        policy: policyWith(
          canRead,
          connectivity: ConnectivityState.offline,
          offlinePermissions: canRead,
        ),
        tenantId: 'tenant-1',
        now: now,
      );
      expect(board.surveys, hasLength(1));
    });
  });
}
