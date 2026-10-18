/// Tests for the analytics warehouse use cases, the period arithmetic and the
/// derived figures (Module 38).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/authorization_snapshot.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/domain/analytics/analytics.dart';
import 'package:nodex_hms/domain/analytics/analytics_repository.dart';
import 'package:nodex_hms/domain/analytics/analytics_use_cases.dart';

import 'analytics_repository_test.dart' show FakeAnalyticsStore;

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
      departmentIds: const <String>{'department-1'},
      wardIds: const <String>{'ward-1'},
    ),
    connectivity: connectivity,
  );
}

void main() {
  late FakeAnalyticsStore store;
  late DefaultAnalyticsRepository repository;
  late DefineReportUseCase defineReport;
  late PublishReportUseCase publishReport;
  late RetireReportUseCase retireReport;
  late MaterialiseRollupUseCase materialiseRollup;
  late VoidRollupUseCase voidRollup;
  late QueueReportRunUseCase queueRun;
  late StartReportRunUseCase startRun;
  late CompleteReportRunUseCase completeRun;
  late FailReportRunUseCase failRun;
  late CancelReportRunUseCase cancelRun;
  late ExportReportRunUseCase exportRun;
  late ReadAnalyticsWarehouseUseCase readWarehouse;

  const Set<String> canRead = <String>{NodexPermissions.analyticsRead};
  const Set<String> canDefine = <String>{NodexPermissions.analyticsDefine};
  const Set<String> canMaterialise = <String>{
    NodexPermissions.analyticsMaterialise,
  };
  const Set<String> canExport = <String>{NodexPermissions.analyticsExport};

  final AuthorizationPolicy reader = policyWith(canRead);
  final AuthorizationPolicy definer = policyWith(canDefine);
  final AuthorizationPolicy warehouse = policyWith(canMaterialise);
  final AuthorizationPolicy exporter = policyWith(canExport);
  final DateTime now = DateTime.utc(2026, 6, 11, 12);

  setUp(() {
    store = FakeAnalyticsStore();
    repository = DefaultAnalyticsRepository(
      store: store,
      logger: NodexLogger(
        sinks: <NodexLogSink>[InMemoryLogSink()],
        minimumLevel: NodexLogLevel.trace,
      ),
    );
    defineReport = DefineReportUseCase(repository: repository);
    publishReport = PublishReportUseCase(repository: repository);
    retireReport = RetireReportUseCase(repository: repository);
    materialiseRollup = MaterialiseRollupUseCase(repository: repository);
    voidRollup = VoidRollupUseCase(repository: repository);
    queueRun = QueueReportRunUseCase(repository: repository);
    startRun = StartReportRunUseCase(repository: repository);
    completeRun = CompleteReportRunUseCase(repository: repository);
    failRun = FailReportRunUseCase(repository: repository);
    cancelRun = CancelReportRunUseCase(repository: repository);
    exportRun = ExportReportRunUseCase(repository: repository);
    readWarehouse = ReadAnalyticsWarehouseUseCase(repository: repository);
  });

  Future<String> seedDefinition({
    String id = '',
    String code = 'MORB-1',
    String name = 'Monthly morbidity',
    ReportCategory category = ReportCategory.morbidity,
    AnalyticsSource source = AnalyticsSource.encounters,
    AnalyticsGrain grain = AnalyticsGrain.month,
    bool published = true,
  }) async {
    final String created = await defineReport(
      policy: definer,
      tenantId: 'tenant-1',
      code: code,
      displayName: name,
      createdBy: 'admin-1',
      category: category,
      primarySource: source,
      grain: grain,
      definitionId: id,
    );
    if (published) {
      await publishReport(
        policy: definer,
        definition: (await repository.definitionById(created))!,
        publishedBy: 'admin-1',
      );
    }
    return created;
  }

  Future<String> seedRollup({
    String id = '',
    required String definitionId,
    DateTime? periodStart,
    AnalyticsGrain? grain,
    int rowCount = 12,
    int numerator = 3,
    int denominator = 8,
    int incomeMinor = 100000,
    int expenditureMinor = 60000,
  }) async => materialiseRollup(
    policy: warehouse,
    definition: (await repository.definitionById(definitionId))!,
    createdBy: 'admin-1',
    materialisedBy: 'admin-1',
    periodStart: periodStart ?? DateTime.utc(2026, 5, 1),
    grain: grain,
    rowCount: rowCount,
    numerator: numerator,
    denominator: denominator,
    incomeMinor: incomeMinor,
    expenditureMinor: expenditureMinor,
    at: now,
  );

  Future<String> seedRun({
    String id = '',
    required String definitionId,
    String runNumber = 'RUN-1',
    DateTime? periodStart,
    String status = 'queued',
    DateTime? startedAt,
  }) async {
    final String created = await queueRun(
      policy: reader,
      definition: (await repository.definitionById(definitionId))!,
      runNumber: runNumber,
      requestedBy: 'admin-1',
      createdBy: 'admin-1',
      periodStart: periodStart ?? DateTime.utc(2026, 5, 1),
      runId: id,
    );
    if (status != 'queued') {
      await startRun(
        policy: warehouse,
        run: (await repository.runById(created))!,
        at: startedAt ?? DateTime.utc(2026, 6, 11, 11, 50),
      );
    }
    if (status == 'succeeded') {
      await completeRun(
        policy: warehouse,
        run: (await repository.runById(created))!,
        servedFrom: RollupServedFrom.rollup,
        rowCount: 42,
        at: now,
      );
    } else if (status == 'failed') {
      await failRun(
        policy: warehouse,
        run: (await repository.runById(created))!,
        reason: 'The replica is not reachable.',
        at: now,
      );
    } else if (status == 'cancelled') {
      await cancelRun(
        policy: reader,
        run: (await repository.runById(created))!,
        reason: 'Asked for the wrong period',
        at: now,
      );
    }
    return created;
  }

  group('definition state machine', () {
    test('a draft is published, and a published report is retired', () {
      expect(
        definitionCanTransition(
          ReportDefinitionStatus.draft,
          ReportDefinitionStatus.published,
        ),
        isTrue,
      );
      expect(
        definitionCanTransition(
          ReportDefinitionStatus.published,
          ReportDefinitionStatus.retired,
        ),
        isTrue,
      );
    });

    test('a draft is not retired before it is published', () {
      expect(
        definitionCanTransition(
          ReportDefinitionStatus.draft,
          ReportDefinitionStatus.retired,
        ),
        isFalse,
      );
      expect(
        definitionCanTransition(
          ReportDefinitionStatus.published,
          ReportDefinitionStatus.draft,
        ),
        isFalse,
      );
    });

    test('a retired report goes nowhere', () {
      expect(ReportDefinitionStatus.retired.isTerminal, isTrue);
      expect(
        definitionCanTransition(
          ReportDefinitionStatus.retired,
          ReportDefinitionStatus.published,
        ),
        isFalse,
      );
    });
  });

  group('run state machine', () {
    test('a queued run starts, then finishes or is abandoned', () {
      expect(
        reportRunCanTransition(ReportRunStatus.queued, ReportRunStatus.running),
        isTrue,
      );
      expect(
        reportRunCanTransition(
          ReportRunStatus.queued,
          ReportRunStatus.cancelled,
        ),
        isTrue,
      );
      expect(
        reportRunCanTransition(
          ReportRunStatus.running,
          ReportRunStatus.succeeded,
        ),
        isTrue,
      );
      expect(
        reportRunCanTransition(ReportRunStatus.running, ReportRunStatus.failed),
        isTrue,
      );
      expect(
        reportRunCanTransition(
          ReportRunStatus.running,
          ReportRunStatus.cancelled,
        ),
        isTrue,
      );
    });

    test('a queued run does not succeed without running', () {
      expect(
        reportRunCanTransition(
          ReportRunStatus.queued,
          ReportRunStatus.succeeded,
        ),
        isFalse,
      );
      expect(
        reportRunCanTransition(ReportRunStatus.queued, ReportRunStatus.failed),
        isFalse,
      );
    });

    test('a settled run goes nowhere', () {
      for (final ReportRunStatus status in <ReportRunStatus>[
        ReportRunStatus.succeeded,
        ReportRunStatus.failed,
        ReportRunStatus.cancelled,
      ]) {
        expect(status.isTerminal, isTrue, reason: status.wireValue);
        expect(status.isLive, isFalse, reason: status.wireValue);
        expect(
          reportRunCanTransition(status, ReportRunStatus.running),
          isFalse,
        );
      }
    });
  });

  group('period arithmetic', () {
    test('a day covers one day', () {
      expect(
        analyticsPeriodEnd(
          grain: AnalyticsGrain.day,
          periodStart: DateTime.utc(2026, 6, 11),
        ),
        DateTime.utc(2026, 6, 11),
      );
    });

    test('a week runs Monday to Sunday', () {
      // 2026-06-08 is a Monday.
      expect(
        analyticsPeriodEnd(
          grain: AnalyticsGrain.week,
          periodStart: DateTime.utc(2026, 6, 8),
        ),
        DateTime.utc(2026, 6, 14),
      );
      expect(
        analyticsPeriodStartFor(
          grain: AnalyticsGrain.week,
          at: DateTime.utc(2026, 6, 11),
        ),
        DateTime.utc(2026, 6, 8),
      );
    });

    test('a month covers the calendar month', () {
      expect(
        analyticsPeriodEnd(
          grain: AnalyticsGrain.month,
          periodStart: DateTime.utc(2026, 6, 1),
        ),
        DateTime.utc(2026, 6, 30),
      );
      expect(
        analyticsPeriodEnd(
          grain: AnalyticsGrain.month,
          periodStart: DateTime.utc(2026, 2, 1),
        ),
        DateTime.utc(2026, 2, 28),
      );
      expect(
        analyticsPeriodStartFor(
          grain: AnalyticsGrain.month,
          at: DateTime.utc(2026, 6, 11),
        ),
        DateTime.utc(2026, 6, 1),
      );
    });

    test('a quarter covers the calendar quarter', () {
      expect(
        analyticsPeriodEnd(
          grain: AnalyticsGrain.quarter,
          periodStart: DateTime.utc(2026, 5, 1),
        ),
        DateTime.utc(2026, 6, 30),
      );
      expect(
        analyticsPeriodEnd(
          grain: AnalyticsGrain.quarter,
          periodStart: DateTime.utc(2026, 10, 1),
        ),
        DateTime.utc(2026, 12, 31),
      );
      expect(
        analyticsPeriodStartFor(
          grain: AnalyticsGrain.quarter,
          at: DateTime.utc(2026, 5, 20),
        ),
        DateTime.utc(2026, 4, 1),
      );
    });

    test('a year covers the calendar year', () {
      expect(
        analyticsPeriodEnd(
          grain: AnalyticsGrain.year,
          periodStart: DateTime.utc(2026, 3, 15),
        ),
        DateTime.utc(2026, 12, 31),
      );
      expect(
        analyticsPeriodStartFor(
          grain: AnalyticsGrain.year,
          at: DateTime.utc(2026, 6, 11),
        ),
        DateTime.utc(2026, 1, 1),
      );
    });

    test('a period start is idempotent', () {
      for (final AnalyticsGrain grain in AnalyticsGrain.values) {
        final DateTime start = analyticsPeriodStartFor(
          grain: grain,
          at: DateTime.utc(2026, 6, 11),
        );
        expect(
          analyticsPeriodStartFor(grain: grain, at: start),
          start,
          reason: grain.wireValue,
        );
      }
    });
  });

  group('derived figures', () {
    AnalyticsRollup rollupWith({
      int numerator = 3,
      int denominator = 8,
      int incomeMinor = 100000,
      int expenditureMinor = 60000,
      String status = 'materialised',
      DateTime? periodStart,
      String definitionId = 'd-1',
      AnalyticsGrain grain = AnalyticsGrain.month,
    }) => AnalyticsRollup.fromRow(<String, Object?>{
      ...AnalyticsRollup.registerRow(
        tenantId: 'tenant-1',
        definitionId: definitionId,
        periodStart: periodStart ?? DateTime.utc(2026, 5, 1),
        createdBy: 'admin-1',
        grain: grain,
        numerator: numerator,
        denominator: denominator,
        incomeMinor: incomeMinor,
        expenditureMinor: expenditureMinor,
        rollupId: 'g-$definitionId-${periodStart ?? 'may'}',
      ),
      'status': status,
    });

    test('a ratio is a percentage of the two terms', () {
      expect(rollupRatio(rollupWith(numerator: 9, denominator: 30)), 30);
    });

    test('a ratio over an empty denominator is unknown, not zero', () {
      expect(rollupRatio(rollupWith(numerator: 9, denominator: 0)), isNull);
    });

    test('a bottom line is money in less money out', () {
      expect(
        rollupNetPosition(
          rollupWith(incomeMinor: 250000, expenditureMinor: 175000),
        ),
        75000,
      );
      expect(
        rollupNetPosition(
          rollupWith(incomeMinor: 40000, expenditureMinor: 90000),
        ),
        -50000,
      );
    });

    test('growth against nothing has no percentage', () {
      expect(growthRate(current: 140000, previous: 40000), 250);
      expect(
        growthRate(current: 40000, previous: 140000),
        closeTo(-71.43, 0.01),
      );
      expect(growthRate(current: 10, previous: 0), isNull);
    });

    test('a figure goes out of date once its period has closed', () {
      final AnalyticsRollup may = rollupWith(
        periodStart: DateTime.utc(2026, 5, 1),
      );
      final AnalyticsRollup june = rollupWith(
        periodStart: DateTime.utc(2026, 6, 1),
      );
      // The May period closed on 31 May; read in June it is out of date.
      expect(isRollupStale(rollup: may, now: now), isTrue);
      // The June period has not closed yet.
      expect(isRollupStale(rollup: june, now: now), isFalse);
      // The day after the period closes, it is still fresh enough.
      expect(
        isRollupStale(rollup: may, now: DateTime.utc(2026, 6, 1, 12)),
        isFalse,
      );
    });

    test('a figure covers the range it spans', () {
      final AnalyticsRollup may = rollupWith(
        periodStart: DateTime.utc(2026, 5, 1),
      );
      expect(
        isRollupCovering(
          rollup: may,
          from: DateTime.utc(2026, 5, 10),
          to: DateTime.utc(2026, 5, 20),
        ),
        isTrue,
      );
      expect(
        isRollupCovering(
          rollup: may,
          from: DateTime.utc(2026, 4, 1),
          to: DateTime.utc(2026, 6, 30),
        ),
        isFalse,
      );
    });

    test('the newest current figure is read, skipping settled ones', () {
      final AnalyticsRollup april = rollupWith(
        periodStart: DateTime.utc(2026, 4, 1),
      );
      final AnalyticsRollup may = rollupWith(
        periodStart: DateTime.utc(2026, 5, 1),
      );
      final AnalyticsRollup supersededMay = rollupWith(
        periodStart: DateTime.utc(2026, 5, 1),
        status: 'superseded',
      );
      final AnalyticsRollup? newest = latestRollupFor(
        definitionId: 'd-1',
        grain: AnalyticsGrain.month,
        rollups: <AnalyticsRollup>[april, supersededMay, may],
      );
      expect(newest, same(may));
    });

    test('a definition with no current figure has nothing to read', () {
      expect(
        latestRollupFor(
          definitionId: 'd-1',
          grain: AnalyticsGrain.month,
          rollups: <AnalyticsRollup>[rollupWith(status: 'voided')],
        ),
        isNull,
      );
      expect(
        latestRollupFor(
          definitionId: 'd-2',
          grain: AnalyticsGrain.month,
          rollups: <AnalyticsRollup>[rollupWith()],
        ),
        isNull,
      );
    });

    test('a run is stalled only while it is running', () {
      final ReportRun running = ReportRun.fromRow(<String, Object?>{
        ...ReportRun.registerRow(
          tenantId: 'tenant-1',
          definitionId: 'd-1',
          runNumber: 'RUN-1',
          requestedBy: 'admin-1',
          createdBy: 'admin-1',
          periodStart: DateTime.utc(2026, 5, 1),
          runId: 'r-1',
        ),
        'status': 'running',
        'started_at': DateTime.utc(2026, 6, 11, 11).toIso8601String(),
      });
      expect(isRunStalled(run: running, now: now), isTrue);
      expect(
        isRunStalled(run: running, now: DateTime.utc(2026, 6, 11, 11, 10)),
        isFalse,
      );
      final ReportRun queued = ReportRun.fromRow(<String, Object?>{
        ...ReportRun.registerRow(
          tenantId: 'tenant-1',
          definitionId: 'd-1',
          runNumber: 'RUN-2',
          requestedBy: 'admin-1',
          createdBy: 'admin-1',
          periodStart: DateTime.utc(2026, 5, 1),
          runId: 'r-2',
        ),
      });
      expect(isRunStalled(run: queued, now: now), isFalse);
    });

    test('a run reports how long it took once it has finished', () {
      final ReportRun run = ReportRun.fromRow(<String, Object?>{
        ...ReportRun.registerRow(
          tenantId: 'tenant-1',
          definitionId: 'd-1',
          runNumber: 'RUN-1',
          requestedBy: 'admin-1',
          createdBy: 'admin-1',
          periodStart: DateTime.utc(2026, 5, 1),
          runId: 'r-1',
        ),
        'status': 'succeeded',
        'served_from': 'replica',
        'row_count': 7,
        'started_at': DateTime.utc(2026, 6, 11, 11, 59).toIso8601String(),
        'finished_at': DateTime.utc(2026, 6, 11, 12, 2).toIso8601String(),
      });
      expect(runDurationSeconds(run), 180);
      expect(run.servedFromRollup, isFalse);
      expect(run.succeeded, isTrue);
    });
  });

  group('catalogue validation', () {
    test('refuses a definition with no code, name or retention', () {
      expect(
        () => ReportDefinition.registerRow(
          tenantId: 'tenant-1',
          code: ' ',
          displayName: '',
          createdBy: '',
          retentionDays: 1,
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.fieldErrors.keys.toSet(),
            'fields',
            containsAll(<String>[
              'code',
              'display_name',
              'retention_days',
              'created_by',
            ]),
          ),
        ),
      );
    });

    test('a definition starts as a draft', () {
      final Map<String, Object?> row = ReportDefinition.registerRow(
        tenantId: 'tenant-1',
        code: ' MORB-1 ',
        displayName: ' Monthly morbidity ',
        createdBy: 'admin-1',
        category: ReportCategory.morbidity,
        primarySource: AnalyticsSource.encounters,
      );
      expect(row['code'], 'MORB-1');
      expect(row['display_name'], 'Monthly morbidity');
      expect(row['status'], 'draft');
      expect(row['grain'], 'month');
      expect(row['published_at'], isNull);
      expect(row['retired_at'], isNull);
    });

    test('publishing needs a publisher', () {
      expect(
        () => definitionPublishChanges(publishedBy: '  '),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'report_definition_publisher_missing',
          ),
        ),
      );
    });
  });

  group('figure validation', () {
    test('refuses a figure with no definition, or a negative count', () {
      expect(
        () => AnalyticsRollup.registerRow(
          tenantId: 'tenant-1',
          definitionId: '',
          periodStart: DateTime.utc(2026, 5, 1),
          createdBy: 'admin-1',
          rowCount: -1,
          denominator: -1,
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.fieldErrors.keys.toSet(),
            'fields',
            containsAll(<String>['definition_id', 'row_count', 'denominator']),
          ),
        ),
      );
    });

    test('refuses a period that ends before it starts', () {
      expect(
        () => AnalyticsRollup.registerRow(
          tenantId: 'tenant-1',
          definitionId: 'd-1',
          periodStart: DateTime.utc(2026, 5, 1),
          periodEnd: DateTime.utc(2026, 4, 1),
          createdBy: 'admin-1',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.fieldErrors.keys.toSet(),
            'fields',
            contains('period_end'),
          ),
        ),
      );
    });

    test('a figure derives its own period end from the grain', () {
      final Map<String, Object?> row = AnalyticsRollup.registerRow(
        tenantId: 'tenant-1',
        definitionId: 'd-1',
        periodStart: DateTime.utc(2026, 5, 1),
        createdBy: 'admin-1',
        grain: AnalyticsGrain.quarter,
      );
      expect(row['period_start'], '2026-05-01');
      expect(row['period_end'], '2026-06-30');
      expect(row['status'], 'materialised');
    });

    test('withdrawing a figure needs a reason', () {
      expect(
        () => rollupVoidChanges(reason: '  '),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'analytics_rollup_void_reason_missing',
          ),
        ),
      );
    });
  });

  group('run validation', () {
    test('refuses a run with no number, definition or requester', () {
      expect(
        () => ReportRun.registerRow(
          tenantId: 'tenant-1',
          definitionId: '',
          runNumber: ' ',
          requestedBy: '',
          createdBy: '',
          periodStart: DateTime.utc(2026, 5, 1),
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.fieldErrors.keys.toSet(),
            'fields',
            containsAll(<String>[
              'definition_id',
              'run_number',
              'requested_by',
              'created_by',
            ]),
          ),
        ),
      );
    });

    test('a run starts queued', () {
      final Map<String, Object?> row = ReportRun.registerRow(
        tenantId: 'tenant-1',
        definitionId: 'd-1',
        runNumber: ' RUN-1 ',
        requestedBy: 'admin-1',
        createdBy: 'admin-1',
        periodStart: DateTime.utc(2026, 5, 1),
      );
      expect(row['run_number'], 'RUN-1');
      expect(row['status'], 'queued');
      expect(row['served_from'], isNull);
      expect(row['row_count'], isNull);
    });

    test('a failure and an abandonment need a reason', () {
      expect(
        () => runFailChanges(reason: ' '),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'report_run_failure_reason_missing',
          ),
        ),
      );
      expect(
        () => runCancelChanges(reason: ' '),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'report_run_cancel_reason_missing',
          ),
        ),
      );
    });

    test('finishing a run with a negative count is refused', () {
      expect(
        () => runSucceedChanges(
          servedFrom: RollupServedFrom.rollup,
          rowCount: -1,
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'report_run_row_count_invalid',
          ),
        ),
      );
    });
  });

  group('export validation', () {
    test('refuses an artefact with no run, name or taker', () {
      expect(
        () => AnalyticsExport.registerRow(
          tenantId: 'tenant-1',
          runId: '',
          artifactLabel: ' ',
          exportedBy: '',
          byteSize: -1,
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.fieldErrors.keys.toSet(),
            'fields',
            containsAll(<String>[
              'run_id',
              'artifact_label',
              'exported_by',
              'byte_size',
            ]),
          ),
        ),
      );
    });

    test('an artefact defaults to a download', () {
      final Map<String, Object?> row = AnalyticsExport.registerRow(
        tenantId: 'tenant-1',
        runId: 'r-1',
        artifactLabel: ' morbidity.csv ',
        exportedBy: 'admin-1',
      );
      expect(row['artifact_label'], 'morbidity.csv');
      expect(row['format'], 'csv');
      expect(row['destination'], 'download');
    });
  });

  group('running the catalogue', () {
    test('adds a report to the catalogue', () async {
      final String id = await defineReport(
        policy: definer,
        tenantId: 'tenant-1',
        code: 'BURN-1',
        displayName: 'Pharmacy burn rate',
        createdBy: 'admin-1',
        category: ReportCategory.pharmacy,
        primarySource: AnalyticsSource.pharmacy,
        grain: AnalyticsGrain.month,
        retentionDays: 730,
      );
      final ReportDefinition definition = (await repository.definitionById(
        id,
      ))!;
      expect(definition.code, 'BURN-1');
      expect(definition.category, ReportCategory.pharmacy);
      expect(definition.isRunnable, isFalse);
    });

    test('refuses a second report sharing a code', () async {
      await seedDefinition(code: 'MORB-1', published: false);
      await expectLater(
        seedDefinition(code: 'MORB-1', name: 'Another', published: false),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'report_definition_code_duplicate',
          ),
        ),
      );
    });

    test(
      'a caller without the define permission cannot add a report',
      () async {
        await expectLater(
          defineReport(
            policy: reader,
            tenantId: 'tenant-1',
            code: 'MORB-1',
            displayName: 'Monthly morbidity',
            createdBy: 'admin-1',
          ),
          throwsA(isA<AuthorizationError>()),
        );
      },
    );

    test('publishing a draft makes it runnable', () async {
      final String id = await seedDefinition(published: false);
      await publishReport(
        policy: definer,
        definition: (await repository.definitionById(id))!,
        publishedBy: 'admin-1',
        at: now,
      );
      final ReportDefinition definition = (await repository.definitionById(
        id,
      ))!;
      expect(definition.status, ReportDefinitionStatus.published);
      expect(definition.publishedAt, now);
      expect(definition.publishedBy, 'admin-1');
      expect(definition.isRunnable, isTrue);
    });

    test('a published report is not published twice', () async {
      final String id = await seedDefinition();
      await expectLater(
        publishReport(
          policy: definer,
          definition: (await repository.definitionById(id))!,
          publishedBy: 'admin-1',
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'report_definition_transition_invalid',
          ),
        ),
      );
    });

    test('retires a published report and keeps it', () async {
      final String id = await seedDefinition();
      await retireReport(
        policy: definer,
        definition: (await repository.definitionById(id))!,
        at: now,
      );
      final ReportDefinition definition = (await repository.definitionById(
        id,
      ))!;
      expect(definition.status, ReportDefinitionStatus.retired);
      expect(definition.retiredAt, now);
      expect(definition.isTerminal, isTrue);
    });

    test('a draft is not retired before it is published', () async {
      final String id = await seedDefinition(published: false);
      await expectLater(
        retireReport(
          policy: definer,
          definition: (await repository.definitionById(id))!,
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'report_definition_transition_invalid',
          ),
        ),
      );
    });

    test('a reader cannot publish or retire a report', () async {
      final String id = await seedDefinition(published: false);
      final ReportDefinition definition = (await repository.definitionById(
        id,
      ))!;
      await expectLater(
        publishReport(
          policy: reader,
          definition: definition,
          publishedBy: 'admin-1',
        ),
        throwsA(isA<AuthorizationError>()),
      );
      await expectLater(
        retireReport(policy: reader, definition: definition),
        throwsA(isA<AuthorizationError>()),
      );
    });
  });

  group('materialising figures', () {
    test('writes the figure for a period', () async {
      final String definition = await seedDefinition();
      final String id = await seedRollup(
        definitionId: definition,
        rowCount: 120,
        numerator: 9,
        denominator: 30,
        incomeMinor: 250000,
        expenditureMinor: 175000,
      );
      final AnalyticsRollup rollup = (await repository.rollupById(id))!;
      expect(rollup.definitionId, definition);
      expect(rollup.grain, AnalyticsGrain.month);
      expect(rollup.periodStart, DateTime.utc(2026, 5, 1));
      expect(rollup.periodEnd, DateTime.utc(2026, 5, 31));
      expect(rollup.rowCount, 120);
      expect(rollup.ratio, 30);
      expect(rollup.netPosition, 75000);
      expect(rollup.isCurrent, isTrue);
      expect(rollup.materialisedBy, 'admin-1');
    });

    test(
      're-materialising a period supersedes the figure it replaces',
      () async {
        final String definition = await seedDefinition();
        final String first = await seedRollup(
          definitionId: definition,
          incomeMinor: 100000,
          expenditureMinor: 60000,
        );
        final String second = await seedRollup(
          definitionId: definition,
          incomeMinor: 120000,
          expenditureMinor: 60000,
        );
        expect(
          (await repository.rollupById(first))!.status,
          RollupStatus.superseded,
        );
        expect((await repository.rollupById(first))!.supersededAt, now);
        final AnalyticsRollup current = (await repository.rollupById(second))!;
        expect(current.isCurrent, isTrue);
        expect(
          await readWarehouse
              .rollupsOf(policy: reader, tenantId: 'tenant-1')
              .then(
                (List<AnalyticsRollup> all) =>
                    all.where((AnalyticsRollup r) => r.isCurrent).length,
              ),
          1,
        );
      },
    );

    test('a later period leaves the earlier one current', () async {
      final String definition = await seedDefinition();
      final String may = await seedRollup(definitionId: definition);
      await seedRollup(
        definitionId: definition,
        periodStart: DateTime.utc(2026, 6, 1),
      );
      expect((await repository.rollupById(may))!.isCurrent, isTrue);
    });

    test('a draft report is not materialised', () async {
      final String id = await seedDefinition(published: false);
      await expectLater(
        materialiseRollup(
          policy: warehouse,
          definition: (await repository.definitionById(id))!,
          createdBy: 'admin-1',
          periodStart: DateTime.utc(2026, 5, 1),
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'analytics_definition_not_runnable',
          ),
        ),
      );
    });

    test('a retired report is no longer materialised', () async {
      final String id = await seedDefinition();
      await retireReport(
        policy: definer,
        definition: (await repository.definitionById(id))!,
      );
      await expectLater(
        materialiseRollup(
          policy: warehouse,
          definition: (await repository.definitionById(id))!,
          createdBy: 'admin-1',
          periodStart: DateTime.utc(2026, 5, 1),
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test(
      'materialising needs the warehouse permission, and a network',
      () async {
        final String definition = await seedDefinition();
        final ReportDefinition report = (await repository.definitionById(
          definition,
        ))!;
        await expectLater(
          materialiseRollup(
            policy: reader,
            definition: report,
            createdBy: 'admin-1',
            periodStart: DateTime.utc(2026, 5, 1),
          ),
          throwsA(isA<AuthorizationError>()),
        );
        await expectLater(
          materialiseRollup(
            policy: policyWith(
              canMaterialise,
              connectivity: ConnectivityState.offline,
              offlinePermissions: canRead,
            ),
            definition: report,
            createdBy: 'admin-1',
            periodStart: DateTime.utc(2026, 5, 1),
          ),
          throwsA(isA<AuthorizationError>()),
        );
      },
    );

    test('withdraws a figure that should not stand', () async {
      final String definition = await seedDefinition();
      final String id = await seedRollup(definitionId: definition);
      await voidRollup(
        policy: warehouse,
        rollup: (await repository.rollupById(id))!,
        reason: 'Wrong period selected',
        at: now,
      );
      final AnalyticsRollup rollup = (await repository.rollupById(id))!;
      expect(rollup.status, RollupStatus.voided);
      expect(rollup.voidReason, 'Wrong period selected');
      expect(rollup.voidedAt, now);
      expect(rollup.isCurrent, isFalse);
    });

    test('withdrawing without a reason is refused', () async {
      final String definition = await seedDefinition();
      final String id = await seedRollup(definitionId: definition);
      await expectLater(
        voidRollup(
          policy: warehouse,
          rollup: (await repository.rollupById(id))!,
          reason: '  ',
        ),
        throwsA(isA<ValidationError>()),
      );
    });

    test('a settled figure is not settled twice', () async {
      final String definition = await seedDefinition();
      final String id = await seedRollup(definitionId: definition);
      await voidRollup(
        policy: warehouse,
        rollup: (await repository.rollupById(id))!,
        reason: 'Wrong period selected',
      );
      await expectLater(
        voidRollup(
          policy: warehouse,
          rollup: (await repository.rollupById(id))!,
          reason: 'Changed our mind',
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'analytics_rollup_transition_invalid',
          ),
        ),
      );
    });
  });

  group('running reports', () {
    test('queues a run of a published report', () async {
      final String definition = await seedDefinition();
      final String id = await seedRun(
        definitionId: definition,
        runNumber: 'RUN-7',
      );
      final ReportRun run = (await repository.runById(id))!;
      expect(run.definitionId, definition);
      expect(run.runNumber, 'RUN-7');
      expect(run.status, ReportRunStatus.queued);
      expect(run.requestedBy, 'admin-1');
      expect(run.periodStart, DateTime.utc(2026, 5, 1));
      expect(run.periodEnd, DateTime.utc(2026, 5, 31));
      expect(run.isLive, isTrue);
    });

    test('a draft report is not run', () async {
      final String id = await seedDefinition(published: false);
      await expectLater(
        queueRun(
          policy: reader,
          definition: (await repository.definitionById(id))!,
          runNumber: 'RUN-1',
          requestedBy: 'admin-1',
          createdBy: 'admin-1',
          periodStart: DateTime.utc(2026, 5, 1),
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'analytics_definition_not_runnable',
          ),
        ),
      );
    });

    test('refuses a second run sharing a run number', () async {
      final String definition = await seedDefinition();
      await seedRun(definitionId: definition, runNumber: 'RUN-1');
      await expectLater(
        seedRun(definitionId: definition, runNumber: 'RUN-1'),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'report_run_number_duplicate',
          ),
        ),
      );
    });

    test('starts a queued run', () async {
      final String definition = await seedDefinition();
      final String id = await seedRun(definitionId: definition);
      await startRun(
        policy: warehouse,
        run: (await repository.runById(id))!,
        at: now,
      );
      final ReportRun run = (await repository.runById(id))!;
      expect(run.status, ReportRunStatus.running);
      expect(run.startedAt, now);
    });

    test('a run is not started twice', () async {
      final String definition = await seedDefinition();
      final String id = await seedRun(
        definitionId: definition,
        status: 'running',
      );
      await expectLater(
        startRun(policy: warehouse, run: (await repository.runById(id))!),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'report_run_transition_invalid',
          ),
        ),
      );
    });

    test('finishes a run with what answered it', () async {
      final String definition = await seedDefinition();
      final String id = await seedRun(
        definitionId: definition,
        status: 'running',
      );
      await completeRun(
        policy: warehouse,
        run: (await repository.runById(id))!,
        servedFrom: RollupServedFrom.replica,
        rowCount: 42,
        at: now,
      );
      final ReportRun run = (await repository.runById(id))!;
      expect(run.status, ReportRunStatus.succeeded);
      expect(run.servedFrom, RollupServedFrom.replica);
      expect(run.servedFromRollup, isFalse);
      expect(run.rowCount, 42);
      expect(run.finishedAt, now);
    });

    test('a queued run does not finish before it starts', () async {
      final String definition = await seedDefinition();
      final String id = await seedRun(definitionId: definition);
      await expectLater(
        completeRun(
          policy: warehouse,
          run: (await repository.runById(id))!,
          servedFrom: RollupServedFrom.rollup,
          rowCount: 1,
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('records a failure with the reason kept', () async {
      final String definition = await seedDefinition();
      final String id = await seedRun(
        definitionId: definition,
        status: 'running',
      );
      await failRun(
        policy: warehouse,
        run: (await repository.runById(id))!,
        reason: 'The replica is not reachable.',
        at: now,
      );
      final ReportRun run = (await repository.runById(id))!;
      expect(run.status, ReportRunStatus.failed);
      expect(run.failureReason, 'The replica is not reachable.');
      expect(run.finishedAt, now);
    });

    test('abandons a queued run with the reason kept', () async {
      final String definition = await seedDefinition();
      final String id = await seedRun(definitionId: definition);
      await cancelRun(
        policy: reader,
        run: (await repository.runById(id))!,
        reason: 'Asked for the wrong period',
        at: now,
      );
      final ReportRun run = (await repository.runById(id))!;
      expect(run.status, ReportRunStatus.cancelled);
      expect(run.cancelReason, 'Asked for the wrong period');
      expect(run.cancelledAt, now);
    });

    test('a settled run is not abandoned', () async {
      final String definition = await seedDefinition();
      final String id = await seedRun(
        definitionId: definition,
        status: 'succeeded',
      );
      await expectLater(
        cancelRun(
          policy: reader,
          run: (await repository.runById(id))!,
          reason: 'Too late',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('a reader cannot start or finish a run', () async {
      final String definition = await seedDefinition();
      final String id = await seedRun(definitionId: definition);
      final ReportRun run = (await repository.runById(id))!;
      await expectLater(
        startRun(policy: reader, run: run),
        throwsA(isA<AuthorizationError>()),
      );
      await expectLater(
        failRun(policy: reader, run: run, reason: 'No'),
        throwsA(isA<AuthorizationError>()),
      );
    });
  });

  group('taking artefacts out', () {
    test('records an artefact from a finished run', () async {
      final String definition = await seedDefinition();
      final String run = await seedRun(
        definitionId: definition,
        status: 'succeeded',
      );
      await exportRun(
        policy: exporter,
        run: (await repository.runById(run))!,
        artifactLabel: 'morbidity-2026-05.csv',
        exportedBy: 'admin-1',
        format: ExportFormat.xlsx,
        destination: ExportDestination.email,
        byteSize: 2048,
        note: 'For the board pack',
        at: now,
      );
      final AnalyticsExport export = (await repository.listExports(
        'tenant-1',
        runId: run,
      )).single;
      expect(export.artifactLabel, 'morbidity-2026-05.csv');
      expect(export.format, ExportFormat.xlsx);
      expect(export.destination, ExportDestination.email);
      expect(export.byteSize, 2048);
      expect(export.note, 'For the board pack');
      expect(export.exportedAt, now);
    });

    test('a report that has not finished is not taken out', () async {
      final String definition = await seedDefinition();
      final String run = await seedRun(definitionId: definition);
      await expectLater(
        exportRun(
          policy: exporter,
          run: (await repository.runById(run))!,
          artifactLabel: 'morbidity.csv',
          exportedBy: 'admin-1',
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'analytics_export_run_not_finished',
          ),
        ),
      );
    });

    test('refuses a second artefact sharing a name', () async {
      final String definition = await seedDefinition();
      final String run = await seedRun(
        definitionId: definition,
        status: 'succeeded',
      );
      await exportRun(
        policy: exporter,
        run: (await repository.runById(run))!,
        artifactLabel: 'morbidity.csv',
        exportedBy: 'admin-1',
      );
      await expectLater(
        exportRun(
          policy: exporter,
          run: (await repository.runById(run))!,
          artifactLabel: 'morbidity.csv',
          exportedBy: 'admin-1',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'analytics_export_label_duplicate',
          ),
        ),
      );
    });

    test('a reader cannot take a report out', () async {
      final String definition = await seedDefinition();
      final String run = await seedRun(
        definitionId: definition,
        status: 'succeeded',
      );
      await expectLater(
        exportRun(
          policy: reader,
          run: (await repository.runById(run))!,
          artifactLabel: 'morbidity.csv',
          exportedBy: 'admin-1',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('exporting needs a network', () async {
      final String definition = await seedDefinition();
      final String run = await seedRun(
        definitionId: definition,
        status: 'succeeded',
      );
      await expectLater(
        exportRun(
          policy: policyWith(
            canExport,
            connectivity: ConnectivityState.offline,
            offlinePermissions: canRead,
          ),
          run: (await repository.runById(run))!,
          artifactLabel: 'morbidity.csv',
          exportedBy: 'admin-1',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });
  });

  group('reading the warehouse', () {
    test('reads the catalogue, the figures, the runs and the log', () async {
      final String definition = await seedDefinition();
      await seedRollup(definitionId: definition);
      await seedRun(definitionId: definition, status: 'succeeded');
      final AnalyticsWarehouseBoard board = await readWarehouse.board(
        policy: reader,
        tenantId: 'tenant-1',
        now: now,
      );
      expect(board.definitions, hasLength(1));
      expect(board.rollups, hasLength(1));
      expect(board.runs, hasLength(1));
      expect(board.exports, isEmpty);
      expect(board.asOf, now);
    });

    test('the catalogue is read by code', () async {
      await seedDefinition(code: 'ZZZ-9', name: 'Last');
      await seedDefinition(code: 'AAA-1', name: 'First');
      final AnalyticsWarehouseBoard board = await readWarehouse.board(
        policy: reader,
        tenantId: 'tenant-1',
        now: now,
      );
      expect(board.definitions.first.code, 'AAA-1');
      expect(board.definitions.last.code, 'ZZZ-9');
    });

    test('the figures are read newest period first', () async {
      final String definition = await seedDefinition();
      await seedRollup(
        definitionId: definition,
        periodStart: DateTime.utc(2026, 3, 1),
      );
      await seedRollup(
        definitionId: definition,
        periodStart: DateTime.utc(2026, 5, 1),
      );
      final AnalyticsWarehouseBoard board = await readWarehouse.board(
        policy: reader,
        tenantId: 'tenant-1',
        now: now,
      );
      expect(board.rollups.first.periodStart, DateTime.utc(2026, 5, 1));
      expect(board.rollups.last.periodStart, DateTime.utc(2026, 3, 1));
    });

    test('the latest figure of a report is the newest current one', () async {
      final String definition = await seedDefinition();
      await seedRollup(
        definitionId: definition,
        periodStart: DateTime.utc(2026, 4, 1),
        incomeMinor: 40000,
        expenditureMinor: 0,
      );
      await seedRollup(
        definitionId: definition,
        periodStart: DateTime.utc(2026, 5, 1),
        incomeMinor: 140000,
        expenditureMinor: 0,
      );
      final AnalyticsWarehouseBoard board = await readWarehouse.board(
        policy: reader,
        tenantId: 'tenant-1',
        now: now,
      );
      final AnalyticsRollup latest = board.latestRollup(
        definitionId: definition,
      )!;
      expect(latest.periodStart, DateTime.utc(2026, 5, 1));
      expect(board.growthFor(definitionId: definition), 250);
    });

    test('growth against a single figure is unknown', () async {
      final String definition = await seedDefinition();
      await seedRollup(definitionId: definition);
      final AnalyticsWarehouseBoard board = await readWarehouse.board(
        policy: reader,
        tenantId: 'tenant-1',
        now: now,
      );
      expect(board.growthFor(definitionId: definition), isNull);
    });

    test('the board knows which periods it can answer for', () async {
      final String definition = await seedDefinition();
      await seedRollup(definitionId: definition);
      final AnalyticsWarehouseBoard board = await readWarehouse.board(
        policy: reader,
        tenantId: 'tenant-1',
        now: now,
      );
      expect(
        board.isCoveredByRollup(
          definitionId: definition,
          from: DateTime.utc(2026, 5, 10),
          to: DateTime.utc(2026, 5, 20),
        ),
        isTrue,
      );
      expect(
        board.isCoveredByRollup(
          definitionId: definition,
          from: DateTime.utc(2026, 4, 1),
          to: DateTime.utc(2026, 6, 30),
        ),
        isFalse,
      );
    });

    test('a figure whose period has closed is flagged out of date', () async {
      final String definition = await seedDefinition();
      await seedRollup(definitionId: definition);
      await seedRollup(
        definitionId: definition,
        periodStart: DateTime.utc(2026, 6, 1),
      );
      final AnalyticsWarehouseBoard board = await readWarehouse.board(
        policy: reader,
        tenantId: 'tenant-1',
        now: now,
      );
      expect(board.staleRollups, hasLength(1));
      expect(board.staleRollups.single.periodStart, DateTime.utc(2026, 5, 1));
      expect(board.needsAttention, isTrue);
    });

    test('a settled figure is not read as current', () async {
      final String definition = await seedDefinition();
      final String id = await seedRollup(definitionId: definition);
      await voidRollup(
        policy: warehouse,
        rollup: (await repository.rollupById(id))!,
        reason: 'Wrong period selected',
      );
      final AnalyticsWarehouseBoard board = await readWarehouse.board(
        policy: reader,
        tenantId: 'tenant-1',
        now: now,
      );
      expect(board.rollups.single.isCurrent, isFalse);
      expect(board.latestRollup(definitionId: definition), isNull);
      expect(board.needsAttention, isFalse);
    });

    test(
      'the board lists the runs in flight and the ones that stalled',
      () async {
        final String definition = await seedDefinition();
        await seedRun(
          definitionId: definition,
          runNumber: 'RUN-1',
          status: 'running',
          startedAt: DateTime.utc(2026, 6, 11, 11),
        );
        await seedRun(definitionId: definition, runNumber: 'RUN-2');
        await seedRun(
          definitionId: definition,
          runNumber: 'RUN-3',
          status: 'succeeded',
        );
        final AnalyticsWarehouseBoard board = await readWarehouse.board(
          policy: reader,
          tenantId: 'tenant-1',
          now: now,
        );
        expect(board.liveRuns, hasLength(2));
        expect(board.stalledRuns.single.runNumber, 'RUN-1');
        expect(board.succeededRuns.single.runNumber, 'RUN-3');
        expect(board.runsFor(definition), hasLength(3));
      },
    );

    test('a failed run wants attention', () async {
      final String definition = await seedDefinition();
      await seedRun(definitionId: definition, status: 'failed');
      final AnalyticsWarehouseBoard board = await readWarehouse.board(
        policy: reader,
        tenantId: 'tenant-1',
        now: now,
      );
      expect(board.failedRuns, hasLength(1));
      expect(board.needsAttention, isTrue);
    });

    test('a clean board wants nothing', () async {
      final String definition = await seedDefinition();
      await seedRun(definitionId: definition, status: 'succeeded');
      final AnalyticsWarehouseBoard board = await readWarehouse.board(
        policy: reader,
        tenantId: 'tenant-1',
        now: now,
      );
      expect(board.needsAttention, isFalse);
    });

    test('the artefacts taken today are counted', () async {
      final String definition = await seedDefinition();
      final String run = await seedRun(
        definitionId: definition,
        status: 'succeeded',
      );
      await exportRun(
        policy: exporter,
        run: (await repository.runById(run))!,
        artifactLabel: 'morbidity.csv',
        exportedBy: 'admin-1',
        at: DateTime.utc(2026, 6, 11, 9),
      );
      final AnalyticsWarehouseBoard board = await readWarehouse.board(
        policy: reader,
        tenantId: 'tenant-1',
        now: now,
      );
      expect(board.exportsToday, hasLength(1));
      expect(board.exportsFor(run), hasLength(1));
      expect(board.definitionFor(definition)!.code, 'MORB-1');
      expect(board.definitionFor('missing'), isNull);
    });

    test('reading the warehouse needs the read permission', () async {
      await expectLater(
        readWarehouse.board(policy: definer, tenantId: 'tenant-1', now: now),
        throwsA(isA<AuthorizationError>()),
      );
      await expectLater(
        readWarehouse.definitionsOf(policy: warehouse, tenantId: 'tenant-1'),
        throwsA(isA<AuthorizationError>()),
      );
      await expectLater(
        readWarehouse.rollupsOf(policy: warehouse, tenantId: 'tenant-1'),
        throwsA(isA<AuthorizationError>()),
      );
      await expectLater(
        readWarehouse.runsOf(policy: warehouse, tenantId: 'tenant-1'),
        throwsA(isA<AuthorizationError>()),
      );
      await expectLater(
        readWarehouse.exportsOf(policy: warehouse, tenantId: 'tenant-1'),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('an offline reader still reads the warehouse they hold', () async {
      final String definition = await seedDefinition();
      await seedRollup(definitionId: definition);
      final AnalyticsWarehouseBoard board = await readWarehouse.board(
        policy: policyWith(
          canRead,
          connectivity: ConnectivityState.offline,
          offlinePermissions: canRead,
        ),
        tenantId: 'tenant-1',
        now: now,
      );
      expect(board.rollups, hasLength(1));
    });
  });
}
