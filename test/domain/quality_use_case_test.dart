/// Tests for the quality hub use cases, the derived compliance score, the
/// indicator value in its own unit and the three state machines (Module 35).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/authorization_snapshot.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/domain/quality/quality.dart';
import 'package:nodex_hms/domain/quality/quality_repository.dart';
import 'package:nodex_hms/domain/quality/quality_use_cases.dart';

import 'quality_repository_test.dart' show FakeQualityStore;

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
      departmentIds: const <String>{},
      wardIds: const <String>{},
    ),
    connectivity: connectivity,
  );
}

void main() {
  late FakeQualityStore store;
  late DefaultQualityRepository repository;
  late ScheduleComplianceAuditUseCase scheduleAudit;
  late StartComplianceAuditUseCase startAudit;
  late CompleteComplianceAuditUseCase completeAudit;
  late CancelComplianceAuditUseCase cancelAudit;
  late ReportIncidentUseCase reportIncident;
  late InvestigateIncidentUseCase investigateIncident;
  late PlanIncidentActionUseCase planAction;
  late CloseIncidentUseCase closeIncident;
  late VoidIncidentUseCase voidIncident;
  late RecordClinicalIndicatorUseCase recordIndicator;
  late PublishClinicalIndicatorUseCase publishIndicator;
  late RetractClinicalIndicatorUseCase retractIndicator;
  late ReadQualityHubUseCase readHub;

  const Set<String> canAudit = <String>{NodexPermissions.qualityAudit};
  const Set<String> canReport = <String>{NodexPermissions.qualityIncident};
  const Set<String> canIndicate = <String>{NodexPermissions.qualityIndicator};
  const Set<String> canRead = <String>{NodexPermissions.qualityRead};

  final AuthorizationPolicy auditor = policyWith(canAudit);
  final AuthorizationPolicy reporter = policyWith(canReport);
  final AuthorizationPolicy analyst = policyWith(canIndicate);
  final AuthorizationPolicy reader = policyWith(canRead);
  final DateTime now = DateTime.utc(2026, 6, 10, 12);

  setUp(() {
    store = FakeQualityStore();
    repository = DefaultQualityRepository(
      store: store,
      logger: NodexLogger(
        sinks: <NodexLogSink>[InMemoryLogSink()],
        minimumLevel: NodexLogLevel.trace,
      ),
    );
    scheduleAudit = ScheduleComplianceAuditUseCase(repository: repository);
    startAudit = StartComplianceAuditUseCase(repository: repository);
    completeAudit = CompleteComplianceAuditUseCase(repository: repository);
    cancelAudit = CancelComplianceAuditUseCase(repository: repository);
    reportIncident = ReportIncidentUseCase(repository: repository);
    investigateIncident = InvestigateIncidentUseCase(repository: repository);
    planAction = PlanIncidentActionUseCase(repository: repository);
    closeIncident = CloseIncidentUseCase(repository: repository);
    voidIncident = VoidIncidentUseCase(repository: repository);
    recordIndicator = RecordClinicalIndicatorUseCase(repository: repository);
    publishIndicator = PublishClinicalIndicatorUseCase(repository: repository);
    retractIndicator = RetractClinicalIndicatorUseCase(repository: repository);
    readHub = ReadQualityHubUseCase(repository: repository);
  });

  Future<String> seedAudit({
    String id = '',
    DateTime? scheduledFor,
    AccreditationFramework framework = AccreditationFramework.nabh,
    int? total,
    int? compliant,
    String status = 'planned',
  }) async {
    final String created = await scheduleAudit(
      policy: auditor,
      tenantId: 'tenant-1',
      facilityId: 'facility-1',
      chapter: 'COP',
      title: 'Care of patients',
      scheduledFor: scheduledFor ?? DateTime.utc(2026, 6, 20, 9),
      createdBy: 'admin-1',
      framework: framework,
      auditId: id,
    );
    if (status == 'in_progress' || status == 'completed') {
      await repository.updateAudit(created, auditStartChanges(at: now));
    }
    if (status == 'completed') {
      await repository.updateAudit(
        created,
        auditCompleteChanges(
          totalCriteria: total ?? 20,
          compliantCriteria: compliant ?? 18,
          completedBy: 'admin-1',
          at: now,
        ),
      );
    }
    return created;
  }

  Future<String> seedIncident({
    String id = '',
    IncidentCategory category = IncidentCategory.needleStick,
    IncidentSeverity severity = IncidentSeverity.major,
    DateTime? occurredAt,
    DateTime? followUpDueAt,
    String reportNumber = 'INC-1',
    String status = 'reported',
  }) async {
    final String created = await reportIncident(
      policy: reporter,
      tenantId: 'tenant-1',
      facilityId: 'facility-1',
      reportNumber: reportNumber,
      title: 'Sharps injury in theatre',
      description: 'Suture needle injury while clearing the trolley.',
      occurredAt: occurredAt ?? DateTime.utc(2026, 6, 10, 9),
      reportedBy: 'admin-1',
      createdBy: 'admin-1',
      category: category,
      severity: severity,
      followUpDueAt: followUpDueAt,
      incidentId: id,
    );
    if (status == 'investigating' ||
        status == 'action_plan' ||
        status == 'closed') {
      await repository.updateIncident(
        created,
        incidentInvestigateChanges(assignedTo: 'admin-1', at: now),
      );
    }
    if (status == 'action_plan' || status == 'closed') {
      await repository.updateIncident(
        created,
        incidentActionPlanChanges(
          actionPlan: 'Sharps bins replaced',
          dueAt: DateTime.utc(2026, 6, 24),
        ),
      );
    }
    if (status == 'closed') {
      await repository.updateIncident(
        created,
        incidentCloseChanges(note: 'Bins replaced', at: now),
      );
    }
    return created;
  }

  Future<String> seedIndicator({
    String id = '',
    String code = 'HAI-CLABSI',
    int numerator = 3,
    int denominator = 450,
    int? target = 1,
    IndicatorUnit unit = IndicatorUnit.perThousandDeviceDays,
    IndicatorDirection direction = IndicatorDirection.lowerIsBetter,
    DateTime? periodStart,
    String status = 'draft',
  }) async {
    final String created = await recordIndicator(
      policy: analyst,
      tenantId: 'tenant-1',
      facilityId: 'facility-1',
      code: code,
      name: 'CLABSI rate',
      periodStart: periodStart ?? DateTime.utc(2026, 5, 1),
      periodEnd: DateTime.utc(2026, 5, 31),
      createdBy: 'admin-1',
      numerator: numerator,
      denominator: denominator,
      targetValue: target,
      unit: unit,
      direction: direction,
      indicatorId: id,
    );
    if (status == 'published') {
      await repository.updateIndicator(
        created,
        indicatorPublishChanges(publishedBy: 'admin-1', at: now),
      );
    }
    return created;
  }

  group('audit state machine', () {
    test('a planned audit starts, is scored and stops there', () {
      expect(
        auditCanTransition(AuditStatus.planned, AuditStatus.inProgress),
        isTrue,
      );
      expect(
        auditCanTransition(AuditStatus.inProgress, AuditStatus.completed),
        isTrue,
      );
      expect(
        auditCanTransition(AuditStatus.planned, AuditStatus.completed),
        isFalse,
      );
    });

    test('either live stage can be called off', () {
      expect(
        auditCanTransition(AuditStatus.planned, AuditStatus.cancelled),
        isTrue,
      );
      expect(
        auditCanTransition(AuditStatus.inProgress, AuditStatus.cancelled),
        isTrue,
      );
    });

    test('a settled audit goes nowhere', () {
      expect(
        auditCanTransition(AuditStatus.completed, AuditStatus.inProgress),
        isFalse,
      );
      expect(
        auditCanTransition(AuditStatus.cancelled, AuditStatus.planned),
        isFalse,
      );
      expect(AuditStatus.completed.isTerminal, isTrue);
      expect(AuditStatus.inProgress.isStarted, isTrue);
    });
  });

  group('incident state machine', () {
    test('an incident runs reported to closed one stage at a time', () {
      expect(
        incidentCanTransition(
          IncidentStatus.reported,
          IncidentStatus.investigating,
        ),
        isTrue,
      );
      expect(
        incidentCanTransition(
          IncidentStatus.investigating,
          IncidentStatus.actionPlan,
        ),
        isTrue,
      );
      expect(
        incidentCanTransition(IncidentStatus.actionPlan, IncidentStatus.closed),
        isTrue,
      );
      expect(
        incidentCanTransition(IncidentStatus.reported, IncidentStatus.closed),
        isFalse,
      );
    });

    test('a report cannot be withdrawn once the action plan is agreed', () {
      expect(
        incidentCanTransition(IncidentStatus.reported, IncidentStatus.voided),
        isTrue,
      );
      expect(
        incidentCanTransition(
          IncidentStatus.investigating,
          IncidentStatus.voided,
        ),
        isTrue,
      );
      expect(
        incidentCanTransition(IncidentStatus.actionPlan, IncidentStatus.voided),
        isFalse,
      );
    });

    test('a settled incident goes nowhere', () {
      expect(
        incidentCanTransition(
          IncidentStatus.closed,
          IncidentStatus.investigating,
        ),
        isFalse,
      );
      expect(IncidentStatus.closed.isTerminal, isTrue);
      expect(IncidentStatus.reported.awaitsInvestigation, isTrue);
      expect(IncidentStatus.investigating.awaitsInvestigation, isFalse);
      expect(IncidentStatus.voided.isLive, isFalse);
    });
  });

  group('indicator state machine', () {
    test('a draft publishes and a published reading retracts', () {
      expect(
        indicatorCanTransition(
          IndicatorStatus.draft,
          IndicatorStatus.published,
        ),
        isTrue,
      );
      expect(
        indicatorCanTransition(
          IndicatorStatus.published,
          IndicatorStatus.retracted,
        ),
        isTrue,
      );
      expect(
        indicatorCanTransition(
          IndicatorStatus.draft,
          IndicatorStatus.retracted,
        ),
        isFalse,
      );
      expect(IndicatorStatus.retracted.isTerminal, isTrue);
    });
  });

  group('derived compliance score', () {
    test('reads the met criteria as a percentage', () async {
      final String id = await seedAudit(
        status: 'completed',
        total: 20,
        compliant: 17,
      );
      final ComplianceAudit audit = (await repository.auditById(id))!;
      expect(complianceScore(audit), 85);
      expect(auditVerdict(audit), AuditVerdict.partiallyConformant);
    });

    test('rounds to the nearest whole percentage', () async {
      final String id = await seedAudit(
        status: 'completed',
        total: 3,
        compliant: 2,
      );
      final ComplianceAudit audit = (await repository.auditById(id))!;
      expect(complianceScore(audit), 67);
      expect(auditVerdict(audit), AuditVerdict.nonConformant);
    });

    test('an unscored audit has no score and no verdict', () async {
      final String id = await seedAudit();
      final ComplianceAudit audit = (await repository.auditById(id))!;
      expect(complianceScore(audit), isNull);
      expect(auditVerdict(audit), AuditVerdict.notScored);
      expect(audit.isScored, isFalse);
    });

    test('a perfect score is conformant', () async {
      final String id = await seedAudit(
        status: 'completed',
        total: 10,
        compliant: 10,
      );
      final ComplianceAudit audit = (await repository.auditById(id))!;
      expect(complianceScore(audit), 100);
      expect(auditVerdict(audit), AuditVerdict.conformant);
    });

    test('a score below the partial threshold is non-conformant', () async {
      final String id = await seedAudit(
        status: 'completed',
        total: 40,
        compliant: 24,
      );
      expect(
        (await repository.auditById(id))!.verdict,
        AuditVerdict.nonConformant,
      );
    });

    test(
      'an audit past its scheduled moment is overdue until conducted',
      () async {
        final String id = await seedAudit(
          scheduledFor: DateTime.utc(2026, 6, 1, 9),
        );
        final ComplianceAudit planned = (await repository.auditById(id))!;
        expect(isAuditOverdue(audit: planned, now: now), isTrue);
        await repository.updateAudit(id, auditStartChanges(at: now));
        final ComplianceAudit started = (await repository.auditById(id))!;
        expect(isAuditOverdue(audit: started, now: now), isFalse);
      },
    );

    test('a scheduled audit in the future is not overdue', () async {
      final String id = await seedAudit(
        scheduledFor: DateTime.utc(2026, 7, 1, 9),
      );
      expect(
        isAuditOverdue(audit: (await repository.auditById(id))!, now: now),
        isFalse,
      );
    });

    test('a cancelled audit is never overdue', () async {
      final String id = await seedAudit(
        scheduledFor: DateTime.utc(2026, 6, 1, 9),
      );
      await repository.updateAudit(
        id,
        auditCancelChanges(reason: 'Rescheduled', at: now),
      );
      expect(
        isAuditOverdue(audit: (await repository.auditById(id))!, now: now),
        isFalse,
      );
    });
  });

  group('derived incident windows', () {
    test('a sentinel or major harm gets a day and a moderate one three', () {
      expect(
        incidentResponseWindow(IncidentSeverity.sentinel),
        const Duration(days: 1),
      );
      expect(
        incidentResponseWindow(IncidentSeverity.major),
        const Duration(days: 1),
      );
      expect(
        incidentResponseWindow(IncidentSeverity.moderate),
        const Duration(days: 3),
      );
      expect(
        incidentResponseWindow(IncidentSeverity.minor),
        const Duration(days: 7),
      );
      expect(
        incidentResponseWindow(IncidentSeverity.nearMiss),
        const Duration(days: 7),
      );
    });

    test('a major incident unreported for two days is overdue', () async {
      final String id = await seedIncident(
        occurredAt: DateTime.utc(2026, 6, 8, 9),
      );
      final IncidentReport incident = (await repository.incidentById(id))!;
      expect(incident.responseWindow, const Duration(days: 1));
      expect(isIncidentResponseOverdue(incident: incident, now: now), isTrue);
    });

    test('a minor incident within its week is not overdue', () async {
      final String id = await seedIncident(
        severity: IncidentSeverity.minor,
        occurredAt: DateTime.utc(2026, 6, 8, 9),
      );
      expect(
        isIncidentResponseOverdue(
          incident: (await repository.incidentById(id))!,
          now: now,
        ),
        isFalse,
      );
    });

    test('an investigated incident is not overdue however late', () async {
      final String id = await seedIncident(
        occurredAt: DateTime.utc(2026, 6, 1, 9),
        status: 'investigating',
      );
      expect(
        isIncidentResponseOverdue(
          incident: (await repository.incidentById(id))!,
          now: now,
        ),
        isFalse,
      );
    });

    test('a needle-stick follow-up date is derived from the clock', () async {
      final String id = await seedIncident(
        occurredAt: DateTime.utc(2026, 6, 9, 9),
        followUpDueAt: DateTime.utc(2026, 6, 10, 9),
      );
      final IncidentReport incident = (await repository.incidentById(id))!;
      expect(incident.isNeedleStick, isTrue);
      expect(isIncidentFollowUpOverdue(incident: incident, now: now), isTrue);
    });

    test('a follow-up date in the future is not overdue', () async {
      final String id = await seedIncident(
        followUpDueAt: DateTime.utc(2026, 12, 1),
      );
      expect(
        isIncidentFollowUpOverdue(
          incident: (await repository.incidentById(id))!,
          now: now,
        ),
        isFalse,
      );
    });

    test('a closed incident is not overdue on either marker', () async {
      final String id = await seedIncident(
        occurredAt: DateTime.utc(2026, 6, 1, 9),
        followUpDueAt: DateTime.utc(2026, 6, 2),
        status: 'closed',
      );
      final IncidentReport incident = (await repository.incidentById(id))!;
      expect(isIncidentResponseOverdue(incident: incident, now: now), isFalse);
      expect(isIncidentFollowUpOverdue(incident: incident, now: now), isFalse);
    });
  });

  group('derived indicator value', () {
    test('a rate per thousand device days multiplies the ratio', () async {
      final String id = await seedIndicator(numerator: 3, denominator: 450);
      final ClinicalIndicator indicator = (await repository.indicatorById(id))!;
      expect(indicatorValue(indicator), closeTo(6.667, 0.001));
      expect(indicatorMeetsTarget(indicator), isFalse);
    });

    test('a percentage multiplies by one hundred', () async {
      final String id = await seedIndicator(
        code: 'HH-COMPLIANCE',
        numerator: 92,
        denominator: 100,
        target: 90,
        unit: IndicatorUnit.percent,
        direction: IndicatorDirection.higherIsBetter,
      );
      final ClinicalIndicator indicator = (await repository.indicatorById(id))!;
      expect(indicatorValue(indicator), closeTo(92, 0.001));
      expect(indicatorMeetsTarget(indicator), isTrue);
    });

    test('a count is the numerator itself', () async {
      final String id = await seedIndicator(
        code: 'FALLS',
        numerator: 4,
        denominator: 0,
        target: 5,
        unit: IndicatorUnit.count,
      );
      final ClinicalIndicator indicator = (await repository.indicatorById(id))!;
      expect(indicatorValue(indicator), 4);
      expect(indicatorMeetsTarget(indicator), isTrue);
    });

    test('a rate with no denominator has no value and no verdict', () async {
      final String id = await seedIndicator(numerator: 2, denominator: 0);
      final ClinicalIndicator indicator = (await repository.indicatorById(id))!;
      expect(indicatorValue(indicator), isNull);
      expect(indicatorMeetsTarget(indicator), isNull);
      expect(indicator.hasDenominator, isFalse);
    });

    test('an indicator with no target has no verdict', () async {
      final String id = await seedIndicator(target: null);
      final ClinicalIndicator indicator = (await repository.indicatorById(id))!;
      expect(indicatorValue(indicator), isNotNull);
      expect(indicatorMeetsTarget(indicator), isNull);
    });

    test('a lower-is-better indicator misses a target it exceeds', () async {
      final String id = await seedIndicator(numerator: 9, denominator: 1000);
      final ClinicalIndicator indicator = (await repository.indicatorById(id))!;
      expect(indicatorValue(indicator), closeTo(9, 0.001));
      expect(indicator.meetsTarget, isFalse);
    });
  });

  group('scheduling an audit', () {
    test('records a planned audit with the framework chapter', () async {
      final String id = await scheduleAudit(
        policy: auditor,
        tenantId: 'tenant-1',
        facilityId: 'facility-1',
        chapter: 'COP',
        title: 'Care of patients',
        scheduledFor: DateTime.utc(2026, 6, 20, 9),
        createdBy: 'admin-1',
        framework: AccreditationFramework.jci,
      );
      final ComplianceAudit audit = (await repository.auditById(id))!;
      expect(audit.framework, AccreditationFramework.jci);
      expect(audit.chapter, 'COP');
      expect(audit.status, AuditStatus.planned);
      expect(audit.conductedAt, isNull);
      expect(audit.score, isNull);
    });

    test('refuses an audit with no chapter or title', () async {
      await expectLater(
        scheduleAudit(
          policy: auditor,
          tenantId: 'tenant-1',
          facilityId: 'facility-1',
          chapter: '  ',
          title: '',
          scheduledFor: DateTime.utc(2026, 6, 20),
          createdBy: 'admin-1',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.fieldErrors.keys.toSet(),
            'fields',
            containsAll(<String>['chapter', 'title']),
          ),
        ),
      );
    });

    test('refuses a caller without the audit permission', () async {
      await expectLater(
        scheduleAudit(
          policy: reader,
          tenantId: 'tenant-1',
          facilityId: 'facility-1',
          chapter: 'COP',
          title: 'Care of patients',
          scheduledFor: DateTime.utc(2026, 6, 20),
          createdBy: 'admin-1',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });
  });

  group('running an audit', () {
    test('starting an audit records when it started', () async {
      final String id = await seedAudit();
      await startAudit(
        policy: auditor,
        audit: (await repository.auditById(id))!,
        at: now,
      );
      final ComplianceAudit audit = (await repository.auditById(id))!;
      expect(audit.status, AuditStatus.inProgress);
      expect(audit.conductedAt, now);
    });

    test('a started audit cannot be started again', () async {
      final String id = await seedAudit(status: 'in_progress');
      await expectLater(
        startAudit(policy: auditor, audit: (await repository.auditById(id))!),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'compliance_audit_transition_invalid',
          ),
        ),
      );
    });

    test('scoring an audit completes it and derives the verdict', () async {
      final String id = await seedAudit(status: 'in_progress');
      await completeAudit(
        policy: auditor,
        audit: (await repository.auditById(id))!,
        totalCriteria: 20,
        compliantCriteria: 19,
        completedBy: 'admin-1',
        findings: 'Two records incomplete',
        at: now,
      );
      final ComplianceAudit audit = (await repository.auditById(id))!;
      expect(audit.status, AuditStatus.completed);
      expect(audit.score, 95);
      expect(audit.verdict, AuditVerdict.conformant);
      expect(audit.completedBy, 'admin-1');
      expect(audit.findings, 'Two records incomplete');
    });

    test('a planned audit cannot be scored without starting', () async {
      final String id = await seedAudit();
      await expectLater(
        completeAudit(
          policy: auditor,
          audit: (await repository.auditById(id))!,
          totalCriteria: 10,
          compliantCriteria: 10,
          completedBy: 'admin-1',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('a completed audit cannot be rescored', () async {
      final String id = await seedAudit(
        status: 'completed',
        total: 10,
        compliant: 9,
      );
      await expectLater(
        completeAudit(
          policy: auditor,
          audit: (await repository.auditById(id))!,
          totalCriteria: 10,
          compliantCriteria: 10,
          completedBy: 'admin-1',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('refuses a score where more was met than assessed', () async {
      final String id = await seedAudit(status: 'in_progress');
      await expectLater(
        completeAudit(
          policy: auditor,
          audit: (await repository.auditById(id))!,
          totalCriteria: 10,
          compliantCriteria: 11,
          completedBy: 'admin-1',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'compliance_audit_score_invalid',
          ),
        ),
      );
    });

    test('refuses a score with no criteria assessed', () async {
      final String id = await seedAudit(status: 'in_progress');
      await expectLater(
        completeAudit(
          policy: auditor,
          audit: (await repository.auditById(id))!,
          totalCriteria: 0,
          compliantCriteria: 0,
          completedBy: 'admin-1',
        ),
        throwsA(isA<ValidationError>()),
      );
    });

    test('cancelling records the reason and the moment', () async {
      final String id = await seedAudit();
      await cancelAudit(
        policy: auditor,
        audit: (await repository.auditById(id))!,
        reason: 'Surveyor unavailable',
        at: now,
      );
      final ComplianceAudit audit = (await repository.auditById(id))!;
      expect(audit.status, AuditStatus.cancelled);
      expect(audit.cancelReason, 'Surveyor unavailable');
      expect(audit.cancelledAt, now);
    });

    test('cancelling without a reason is refused', () async {
      final String id = await seedAudit();
      await expectLater(
        cancelAudit(
          policy: auditor,
          audit: (await repository.auditById(id))!,
          reason: '   ',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'compliance_audit_cancel_reason_missing',
          ),
        ),
      );
    });

    test('a completed audit cannot be cancelled', () async {
      final String id = await seedAudit(
        status: 'completed',
        total: 5,
        compliant: 5,
      );
      await expectLater(
        cancelAudit(
          policy: auditor,
          audit: (await repository.auditById(id))!,
          reason: 'Too late',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('a reader cannot score an audit', () async {
      final String id = await seedAudit(status: 'in_progress');
      await expectLater(
        completeAudit(
          policy: reader,
          audit: (await repository.auditById(id))!,
          totalCriteria: 10,
          compliantCriteria: 10,
          completedBy: 'admin-1',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });
  });

  group('reporting an incident', () {
    test(
      'records a reported incident with its category and severity',
      () async {
        final String id = await seedIncident();
        final IncidentReport incident = (await repository.incidentById(id))!;
        expect(incident.status, IncidentStatus.reported);
        expect(incident.category, IncidentCategory.needleStick);
        expect(incident.severity, IncidentSeverity.major);
        expect(incident.reportedBy, 'admin-1');
        expect(incident.investigationStartedAt, isNull);
      },
    );

    test('refuses a report without a number, title or description', () async {
      await expectLater(
        reportIncident(
          policy: reporter,
          tenantId: 'tenant-1',
          facilityId: 'facility-1',
          reportNumber: ' ',
          title: '',
          description: '',
          occurredAt: DateTime.utc(2026, 6, 10),
          reportedBy: 'admin-1',
          createdBy: 'admin-1',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.fieldErrors.keys.toSet(),
            'fields',
            containsAll(<String>['report_number', 'title', 'description']),
          ),
        ),
      );
    });

    test('refuses a second report with the same number', () async {
      await seedIncident(reportNumber: 'INC-7');
      await expectLater(
        reportIncident(
          policy: reporter,
          tenantId: 'tenant-1',
          facilityId: 'facility-1',
          reportNumber: 'INC-7',
          title: 'Another injury',
          description: 'The same incident filed twice.',
          occurredAt: DateTime.utc(2026, 6, 10),
          reportedBy: 'admin-1',
          createdBy: 'admin-1',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'incident_report_number_duplicate',
          ),
        ),
      );
    });

    test('a caller without the incident permission cannot report', () async {
      await expectLater(
        reportIncident(
          policy: reader,
          tenantId: 'tenant-1',
          facilityId: 'facility-1',
          reportNumber: 'INC-8',
          title: 'Injury',
          description: 'Sharps injury.',
          occurredAt: DateTime.utc(2026, 6, 10),
          reportedBy: 'admin-1',
          createdBy: 'admin-1',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });
  });

  group('working an incident', () {
    test('investigating records who took it on and when', () async {
      final String id = await seedIncident();
      await investigateIncident(
        policy: reporter,
        incident: (await repository.incidentById(id))!,
        assignedTo: 'admin-1',
        at: now,
      );
      final IncidentReport incident = (await repository.incidentById(id))!;
      expect(incident.status, IncidentStatus.investigating);
      expect(incident.assignedTo, 'admin-1');
      expect(incident.investigationStartedAt, now);
    });

    test('an investigated incident cannot be reopened', () async {
      final String id = await seedIncident(status: 'investigating');
      await expectLater(
        investigateIncident(
          policy: reporter,
          incident: (await repository.incidentById(id))!,
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('an action plan needs a plan and a date', () async {
      final String id = await seedIncident(status: 'investigating');
      await expectLater(
        planAction(
          policy: reporter,
          incident: (await repository.incidentById(id))!,
          actionPlan: '  ',
          dueAt: DateTime.utc(2026, 6, 24),
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'incident_action_plan_missing',
          ),
        ),
      );
    });

    test('recording the action plan moves the incident on', () async {
      final String id = await seedIncident(status: 'investigating');
      await planAction(
        policy: reporter,
        incident: (await repository.incidentById(id))!,
        actionPlan: 'Re-train on sharps handling',
        dueAt: DateTime.utc(2026, 6, 24),
      );
      final IncidentReport incident = (await repository.incidentById(id))!;
      expect(incident.status, IncidentStatus.actionPlan);
      expect(incident.actionPlan, 'Re-train on sharps handling');
      expect(incident.actionPlanDueAt, DateTime.utc(2026, 6, 24));
    });

    test(
      'an incident with no investigation cannot get an action plan',
      () async {
        final String id = await seedIncident();
        await expectLater(
          planAction(
            policy: reporter,
            incident: (await repository.incidentById(id))!,
            actionPlan: 'Something',
            dueAt: DateTime.utc(2026, 6, 24),
          ),
          throwsA(isA<AuthorizationError>()),
        );
      },
    );

    test('closing records the note and the moment', () async {
      final String id = await seedIncident(status: 'action_plan');
      await closeIncident(
        policy: reporter,
        incident: (await repository.incidentById(id))!,
        note: 'Sharps bins replaced and staff re-trained',
        at: now,
      );
      final IncidentReport incident = (await repository.incidentById(id))!;
      expect(incident.status, IncidentStatus.closed);
      expect(incident.closureNote, 'Sharps bins replaced and staff re-trained');
      expect(incident.closedAt, now);
    });

    test('closing without a note is refused', () async {
      final String id = await seedIncident(status: 'action_plan');
      await expectLater(
        closeIncident(
          policy: reporter,
          incident: (await repository.incidentById(id))!,
          note: '',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'incident_closure_note_missing',
          ),
        ),
      );
    });

    test('an incident cannot be closed before the action plan', () async {
      final String id = await seedIncident(status: 'investigating');
      await expectLater(
        closeIncident(
          policy: reporter,
          incident: (await repository.incidentById(id))!,
          note: 'Nothing was done',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('withdrawing records the reason', () async {
      final String id = await seedIncident();
      await voidIncident(
        policy: reporter,
        incident: (await repository.incidentById(id))!,
        reason: 'Filed against the wrong patient',
        at: now,
      );
      final IncidentReport incident = (await repository.incidentById(id))!;
      expect(incident.status, IncidentStatus.voided);
      expect(incident.voidReason, 'Filed against the wrong patient');
      expect(incident.voidedAt, now);
    });

    test('withdrawing without a reason is refused', () async {
      final String id = await seedIncident();
      await expectLater(
        voidIncident(
          policy: reporter,
          incident: (await repository.incidentById(id))!,
          reason: ' ',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'incident_void_reason_missing',
          ),
        ),
      );
    });

    test('a closed incident cannot be withdrawn', () async {
      final String id = await seedIncident(status: 'closed');
      await expectLater(
        voidIncident(
          policy: reporter,
          incident: (await repository.incidentById(id))!,
          reason: 'Changed my mind',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('a reader cannot investigate an incident', () async {
      final String id = await seedIncident();
      await expectLater(
        investigateIncident(
          policy: reader,
          incident: (await repository.incidentById(id))!,
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });
  });

  group('recording an indicator', () {
    test('records a draft reading with its counts and unit', () async {
      final String id = await seedIndicator();
      final ClinicalIndicator indicator = (await repository.indicatorById(id))!;
      expect(indicator.status, IndicatorStatus.draft);
      expect(indicator.numerator, 3);
      expect(indicator.denominator, 450);
      expect(indicator.targetValue, 1);
      expect(indicator.publishedAt, isNull);
    });

    test('refuses a reading with no code or name', () async {
      await expectLater(
        recordIndicator(
          policy: analyst,
          tenantId: 'tenant-1',
          facilityId: 'facility-1',
          code: ' ',
          name: '',
          periodStart: DateTime.utc(2026, 5, 1),
          periodEnd: DateTime.utc(2026, 5, 31),
          createdBy: 'admin-1',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.fieldErrors.keys.toSet(),
            'fields',
            containsAll(<String>['code', 'name']),
          ),
        ),
      );
    });

    test('refuses a period that ends before it starts', () async {
      await expectLater(
        recordIndicator(
          policy: analyst,
          tenantId: 'tenant-1',
          facilityId: 'facility-1',
          code: 'HAI-CLABSI',
          name: 'CLABSI rate',
          periodStart: DateTime.utc(2026, 5, 31),
          periodEnd: DateTime.utc(2026, 5, 1),
          createdBy: 'admin-1',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.fieldErrors.keys,
            'fields',
            contains('period_end'),
          ),
        ),
      );
    });

    test('refuses a second reading of the same indicator and period', () async {
      await seedIndicator(
        code: 'HAI-CLABSI',
        periodStart: DateTime.utc(2026, 5, 1),
      );
      await expectLater(
        recordIndicator(
          policy: analyst,
          tenantId: 'tenant-1',
          facilityId: 'facility-1',
          code: 'HAI-CLABSI',
          name: 'CLABSI rate',
          periodStart: DateTime.utc(2026, 5, 1),
          periodEnd: DateTime.utc(2026, 5, 31),
          createdBy: 'admin-1',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'clinical_indicator_period_duplicate',
          ),
        ),
      );
    });

    test('an indicator reading needs the indicator permission', () async {
      await expectLater(
        recordIndicator(
          policy: reader,
          tenantId: 'tenant-1',
          facilityId: 'facility-1',
          code: 'HAI-CLABSI',
          name: 'CLABSI rate',
          periodStart: DateTime.utc(2026, 5, 1),
          periodEnd: DateTime.utc(2026, 5, 31),
          createdBy: 'admin-1',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('publishing records who published and when', () async {
      final String id = await seedIndicator();
      await publishIndicator(
        policy: analyst,
        indicator: (await repository.indicatorById(id))!,
        publishedBy: 'admin-1',
        at: now,
      );
      final ClinicalIndicator indicator = (await repository.indicatorById(id))!;
      expect(indicator.status, IndicatorStatus.published);
      expect(indicator.publishedBy, 'admin-1');
      expect(indicator.publishedAt, now);
    });

    test('a published reading cannot be published again', () async {
      final String id = await seedIndicator(status: 'published');
      await expectLater(
        publishIndicator(
          policy: analyst,
          indicator: (await repository.indicatorById(id))!,
          publishedBy: 'admin-1',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('retracting a reading records the reason', () async {
      final String id = await seedIndicator(status: 'published');
      await retractIndicator(
        policy: analyst,
        indicator: (await repository.indicatorById(id))!,
        reason: 'Device days were miscounted',
        at: now,
      );
      final ClinicalIndicator indicator = (await repository.indicatorById(id))!;
      expect(indicator.status, IndicatorStatus.retracted);
      expect(indicator.retractReason, 'Device days were miscounted');
      expect(indicator.retractedAt, now);
    });

    test('a draft reading is discarded, not retracted', () async {
      final String id = await seedIndicator();
      await expectLater(
        retractIndicator(
          policy: analyst,
          indicator: (await repository.indicatorById(id))!,
          reason: 'Never mind',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('retracting without a reason is refused', () async {
      final String id = await seedIndicator(status: 'published');
      await expectLater(
        retractIndicator(
          policy: analyst,
          indicator: (await repository.indicatorById(id))!,
          reason: '  ',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'clinical_indicator_retract_reason_missing',
          ),
        ),
      );
    });

    test('publishing without a publisher is refused', () async {
      final String id = await seedIndicator();
      await expectLater(
        publishIndicator(
          policy: analyst,
          indicator: (await repository.indicatorById(id))!,
          publishedBy: '',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'clinical_indicator_publisher_missing',
          ),
        ),
      );
    });
  });

  group('reading the hub', () {
    test('lists audit, incident and indicator registers', () async {
      await seedAudit();
      await seedIncident();
      await seedIndicator();
      final QualityBoard board = await readHub.board(
        policy: reader,
        tenantId: 'tenant-1',
        now: now,
      );
      expect(board.audits, hasLength(1));
      expect(board.incidents, hasLength(1));
      expect(board.indicators, hasLength(1));
    });

    test('the board lists live records before settled ones', () async {
      await seedAudit(
        id: 'a-settled',
        scheduledFor: DateTime.utc(2026, 7, 1),
        status: 'completed',
      );
      await seedAudit(id: 'a-live', scheduledFor: DateTime.utc(2026, 6, 1));
      await seedIncident(
        id: 'i-settled',
        reportNumber: 'INC-2',
        status: 'closed',
      );
      await seedIncident(id: 'i-live', reportNumber: 'INC-3');
      final QualityBoard board = await readHub.board(
        policy: reader,
        tenantId: 'tenant-1',
        now: now,
      );
      expect(board.audits.first.id, 'a-live');
      expect(board.audits.last.id, 'a-settled');
      expect(board.incidents.first.id, 'i-live');
      expect(board.incidents.last.id, 'i-settled');
    });

    test(
      'the board marks an audit and an incident that need attention',
      () async {
        await seedAudit(id: 'a-1', scheduledFor: DateTime.utc(2026, 6, 1));
        await seedIncident(id: 'i-1', occurredAt: DateTime.utc(2026, 6, 1));
        final QualityBoard board = await readHub.board(
          policy: reader,
          tenantId: 'tenant-1',
          now: now,
        );
        expect(board.auditOverdue(board.audits.single), isTrue);
        expect(board.incidentOverdue(board.incidents.single), isTrue);
        expect(board.hasOverdue, isTrue);
        expect(board.incidentsAwaitingInvestigation, hasLength(1));
      },
    );

    test('the board derives the non-conformant audits', () async {
      await seedAudit(
        id: 'a-1',
        scheduledFor: DateTime.utc(2026, 7, 1),
        status: 'completed',
        total: 20,
        compliant: 10,
      );
      await seedAudit(
        id: 'a-2',
        scheduledFor: DateTime.utc(2026, 7, 2),
        status: 'completed',
        total: 20,
        compliant: 20,
      );
      final QualityBoard board = await readHub.board(
        policy: reader,
        tenantId: 'tenant-1',
        now: now,
      );
      expect(board.nonConformantAudits.single.id, 'a-1');
    });

    test('the board derives the published indicators missing target', () async {
      await seedIndicator(id: 'n-1', status: 'published', numerator: 9);
      await seedIndicator(
        id: 'n-2',
        code: 'HH-COMPLIANCE',
        status: 'published',
        numerator: 95,
        denominator: 100,
        target: 90,
        unit: IndicatorUnit.percent,
        direction: IndicatorDirection.higherIsBetter,
      );
      final QualityBoard board = await readHub.board(
        policy: reader,
        tenantId: 'tenant-1',
        now: now,
      );
      expect(
        board.indicatorsMissingTarget.map((ClinicalIndicator i) => i.id),
        <String>['n-1'],
      );
    });

    test('a hidden register is filtered out of the listing', () async {
      await seedAudit();
      await seedIncident();
      final List<ComplianceAudit> live = await readHub.audits(
        policy: reader,
        tenantId: 'tenant-1',
        includeSettled: false,
      );
      expect(live, hasLength(1));
      final List<IncidentReport> openIncidents = await readHub.incidents(
        policy: reader,
        tenantId: 'tenant-1',
        status: IncidentStatus.reported,
      );
      expect(openIncidents.single.status, IncidentStatus.reported);
    });

    test('filtering by status reaches the register', () async {
      await seedIndicator(id: 'n-1');
      await seedIndicator(
        id: 'n-2',
        code: 'HH-COMPLIANCE',
        status: 'published',
      );
      final List<ClinicalIndicator> drafts = await readHub.indicators(
        policy: reader,
        tenantId: 'tenant-1',
        status: IndicatorStatus.draft,
      );
      expect(drafts.single.id, 'n-1');
    });

    test('reading the hub needs the read permission', () async {
      await expectLater(
        readHub.board(policy: auditor, tenantId: 'tenant-1', now: now),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('an offline reader sees the hub they hold', () async {
      await seedAudit();
      final QualityBoard board = await readHub.board(
        policy: policyWith(
          canRead,
          connectivity: ConnectivityState.offline,
          offlinePermissions: canRead,
        ),
        tenantId: 'tenant-1',
        now: now,
      );
      expect(board.audits, hasLength(1));
    });
  });
}
