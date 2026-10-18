/// Analytics warehouse use cases (Module 38).
///
/// The warehouse stores conclusions, so the use cases here are about deciding
/// which conclusion is being drawn and keeping the record of it. Materialising a
/// rollup and exporting a run both need a network, because both read the read
/// replica: a rollup computed from a stale local copy of the operational tables
/// would be a number no other device agrees with.
library;

import 'package:meta/meta.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/analytics/analytics.dart';
import 'package:nodex_hms/domain/analytics/analytics_repository.dart';

/// Adds a report to the catalogue.
final class DefineReportUseCase {
  /// Creates the use case.
  DefineReportUseCase({required this._repository});

  final AnalyticsRepository _repository;

  Future<String> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String code,
    required String displayName,
    required String createdBy,
    ReportCategory category = ReportCategory.operational,
    AnalyticsSource primarySource = AnalyticsSource.mixed,
    AnalyticsGrain grain = AnalyticsGrain.month,
    int retentionDays = 3650,
    String? facilityId,
    String? description,
    String definitionId = '',
  }) async {
    policy.require(NodexPermissions.analyticsDefine);
    await _requireFreeCode(tenantId, code, exceptId: definitionId);
    return _repository.registerDefinition(
      ReportDefinition.registerRow(
        tenantId: tenantId,
        code: code,
        displayName: displayName,
        createdBy: createdBy,
        category: category,
        primarySource: primarySource,
        grain: grain,
        retentionDays: retentionDays,
        facilityId: facilityId,
        description: description,
        definitionId: definitionId,
      ),
    );
  }

  /// One code per tenant: the code is how the rest of the hospital names the
  /// figure, so two definitions sharing one make the board unreadable.
  Future<void> _requireFreeCode(
    String tenantId,
    String code, {
    required String exceptId,
  }) async {
    final List<ReportDefinition> definitions = await _repository
        .listDefinitions(tenantId);
    for (final ReportDefinition other in definitions) {
      if (other.code == code.trim() && other.id != exceptId) {
        throw const ValidationError(
          message: 'Report definition failed validation.',
          fieldErrors: <String, String>{
            'code': 'That report code is already in use.',
          },
          code: 'report_definition_code_duplicate',
        );
      }
    }
  }
}

/// Publishes a report, freezing the contract its rollups are built against.
final class PublishReportUseCase {
  /// Creates the use case.
  PublishReportUseCase({required this._repository});

  final AnalyticsRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required ReportDefinition definition,
    required String publishedBy,
    DateTime? at,
  }) async {
    policy.require(NodexPermissions.analyticsDefine);
    if (!definitionCanTransition(
      definition.status,
      ReportDefinitionStatus.published,
    )) {
      throw AuthorizationError(
        message: definition.status.isTerminal
            ? 'This report is retired.'
            : 'That report is already published.',
        code: 'report_definition_transition_invalid',
      );
    }
    await _repository.updateDefinition(
      definition.id,
      definitionPublishChanges(publishedBy: publishedBy, at: at),
    );
  }
}

/// Retires a report.
final class RetireReportUseCase {
  /// Creates the use case.
  RetireReportUseCase({required this._repository});

  final AnalyticsRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required ReportDefinition definition,
    DateTime? at,
  }) async {
    policy.require(NodexPermissions.analyticsDefine);
    if (!definitionCanTransition(
      definition.status,
      ReportDefinitionStatus.retired,
    )) {
      throw AuthorizationError(
        message: definition.status.isTerminal
            ? 'This report is already retired.'
            : 'A draft report is not retired; it is never published.',
        code: 'report_definition_transition_invalid',
      );
    }
    await _repository.updateDefinition(
      definition.id,
      definitionRetireChanges(at: at),
    );
  }
}

/// Writes the rolling rollup for a period.
final class MaterialiseRollupUseCase {
  /// Creates the use case.
  MaterialiseRollupUseCase({required this._repository});

  final AnalyticsRepository _repository;

  /// Materialises the figure for [periodStart].
  ///
  /// Re-materialising a period supersedes the row already holding it rather than
  /// sitting beside it: two current rows for one period are two answers to one
  /// question. The superseded row is kept so a figure that was published can
  /// still be explained.
  Future<String> call({
    required AuthorizationPolicy policy,
    required ReportDefinition definition,
    required String createdBy,
    required DateTime periodStart,
    AnalyticsGrain? grain,
    DateTime? periodEnd,
    String? facilityId,
    int rowCount = 0,
    int numerator = 0,
    int denominator = 0,
    int incomeMinor = 0,
    int expenditureMinor = 0,
    String? materialisedBy,
    DateTime? at,
    String rollupId = '',
  }) async {
    policy.require(NodexPermissions.analyticsMaterialise);
    if (!definition.isRunnable) {
      throw AuthorizationError(
        message: definition.isTerminal
            ? 'This report is retired and is no longer materialised.'
            : 'This report is still a draft.',
        code: 'analytics_definition_not_runnable',
      );
    }
    final AnalyticsGrain effectiveGrain = grain ?? definition.grain;
    final DateTime start = DateTime.utc(
      periodStart.toUtc().year,
      periodStart.toUtc().month,
      periodStart.toUtc().day,
    );
    await _supersedeExisting(
      definition: definition,
      grain: effectiveGrain,
      periodStart: start,
      at: at,
    );
    return _repository.registerRollup(
      AnalyticsRollup.registerRow(
        tenantId: definition.tenantId,
        definitionId: definition.id,
        periodStart: start,
        createdBy: createdBy,
        grain: effectiveGrain,
        periodEnd: periodEnd,
        facilityId: facilityId ?? definition.facilityId,
        rowCount: rowCount,
        numerator: numerator,
        denominator: denominator,
        incomeMinor: incomeMinor,
        expenditureMinor: expenditureMinor,
        materialisedBy: materialisedBy,
        materialisedAt: at,
        rollupId: rollupId,
      ),
    );
  }

  Future<void> _supersedeExisting({
    required ReportDefinition definition,
    required AnalyticsGrain grain,
    required DateTime periodStart,
    DateTime? at,
  }) async {
    final List<AnalyticsRollup> rollups = await _repository.listRollups(
      definition.tenantId,
      definitionId: definition.id,
    );
    for (final AnalyticsRollup other in rollups) {
      if (other.grain == grain &&
          other.periodStart == periodStart &&
          other.isCurrent) {
        await _repository.updateRollup(
          other.id,
          rollupSupersedeChanges(
            note: 'Re-materialised from the read replica.',
            at: at,
          ),
        );
      }
    }
  }
}

/// Withdraws a rollup that should not stand.
final class VoidRollupUseCase {
  /// Creates the use case.
  VoidRollupUseCase({required this._repository});

  final AnalyticsRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required AnalyticsRollup rollup,
    required String reason,
    DateTime? at,
  }) async {
    policy.require(NodexPermissions.analyticsMaterialise);
    if (!rollup.isCurrent) {
      throw const AuthorizationError(
        message: 'This figure is already settled.',
        code: 'analytics_rollup_transition_invalid',
      );
    }
    await _repository.updateRollup(
      rollup.id,
      rollupVoidChanges(reason: reason, at: at),
    );
  }
}

/// Queues a run of a published report.
final class QueueReportRunUseCase {
  /// Creates the use case.
  QueueReportRunUseCase({required this._repository});

  final AnalyticsRepository _repository;

  Future<String> call({
    required AuthorizationPolicy policy,
    required ReportDefinition definition,
    required String runNumber,
    required String requestedBy,
    required String createdBy,
    required DateTime periodStart,
    AnalyticsGrain? grain,
    DateTime? periodEnd,
    String? facilityId,
    String? filterNote,
    String runId = '',
  }) async {
    policy.require(NodexPermissions.analyticsRead);
    if (!definition.isRunnable) {
      throw AuthorizationError(
        message: definition.isTerminal
            ? 'This report is retired.'
            : 'This report is still a draft.',
        code: 'analytics_definition_not_runnable',
      );
    }
    await _requireFreeNumber(definition.tenantId, runNumber, exceptId: runId);
    return _repository.registerRun(
      ReportRun.registerRow(
        tenantId: definition.tenantId,
        definitionId: definition.id,
        runNumber: runNumber,
        requestedBy: requestedBy,
        createdBy: createdBy,
        periodStart: periodStart,
        grain: grain ?? definition.grain,
        periodEnd: periodEnd,
        facilityId: facilityId ?? definition.facilityId,
        filterNote: filterNote,
        runId: runId,
      ),
    );
  }

  Future<void> _requireFreeNumber(
    String tenantId,
    String runNumber, {
    required String exceptId,
  }) async {
    final List<ReportRun> runs = await _repository.listRuns(tenantId);
    for (final ReportRun other in runs) {
      if (other.runNumber == runNumber.trim() && other.id != exceptId) {
        throw const ValidationError(
          message: 'Report run failed validation.',
          fieldErrors: <String, String>{
            'run_number': 'That run number is already used.',
          },
          code: 'report_run_number_duplicate',
        );
      }
    }
  }
}

/// Starts a queued run against the read replica.
final class StartReportRunUseCase {
  /// Creates the use case.
  StartReportRunUseCase({required this._repository});

  final AnalyticsRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required ReportRun run,
    DateTime? at,
  }) async {
    policy.require(NodexPermissions.analyticsMaterialise);
    if (!reportRunCanTransition(run.status, ReportRunStatus.running)) {
      throw AuthorizationError(
        message: run.status.isTerminal
            ? 'This run is settled.'
            : 'That run has already started.',
        code: 'report_run_transition_invalid',
      );
    }
    await _repository.updateRun(run.id, runStartChanges(at: at));
  }
}

/// Finishes a run with rows.
final class CompleteReportRunUseCase {
  /// Creates the use case.
  CompleteReportRunUseCase({required this._repository});

  final AnalyticsRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required ReportRun run,
    required RollupServedFrom servedFrom,
    required int rowCount,
    DateTime? at,
  }) async {
    policy.require(NodexPermissions.analyticsMaterialise);
    if (!reportRunCanTransition(run.status, ReportRunStatus.succeeded)) {
      throw AuthorizationError(
        message: run.status.isTerminal
            ? 'This run is settled.'
            : 'That run has not started yet.',
        code: 'report_run_transition_invalid',
      );
    }
    await _repository.updateRun(
      run.id,
      runSucceedChanges(servedFrom: servedFrom, rowCount: rowCount, at: at),
    );
  }
}

/// Finishes a run without rows.
final class FailReportRunUseCase {
  /// Creates the use case.
  FailReportRunUseCase({required this._repository});

  final AnalyticsRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required ReportRun run,
    required String reason,
    DateTime? at,
  }) async {
    policy.require(NodexPermissions.analyticsMaterialise);
    if (!reportRunCanTransition(run.status, ReportRunStatus.failed)) {
      throw AuthorizationError(
        message: run.status.isTerminal
            ? 'This run is settled.'
            : 'That run has not started yet.',
        code: 'report_run_transition_invalid',
      );
    }
    await _repository.updateRun(run.id, runFailChanges(reason: reason, at: at));
  }
}

/// Abandons a run.
final class CancelReportRunUseCase {
  /// Creates the use case.
  CancelReportRunUseCase({required this._repository});

  final AnalyticsRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required ReportRun run,
    required String reason,
    DateTime? at,
  }) async {
    policy.require(NodexPermissions.analyticsRead);
    if (!reportRunCanTransition(run.status, ReportRunStatus.cancelled)) {
      throw const AuthorizationError(
        message: 'This run is settled.',
        code: 'report_run_transition_invalid',
      );
    }
    await _repository.updateRun(
      run.id,
      runCancelChanges(reason: reason, at: at),
    );
  }
}

/// Takes an artefact out of the hospital and records that it went.
final class ExportReportRunUseCase {
  /// Creates the use case.
  ExportReportRunUseCase({required this._repository});

  final AnalyticsRepository _repository;

  Future<String> call({
    required AuthorizationPolicy policy,
    required ReportRun run,
    required String artifactLabel,
    required String exportedBy,
    ExportFormat format = ExportFormat.csv,
    ExportDestination destination = ExportDestination.download,
    int? byteSize,
    String? checksum,
    String? note,
    DateTime? at,
    String exportId = '',
  }) async {
    policy.require(NodexPermissions.analyticsExport);
    if (!run.succeeded) {
      throw const AuthorizationError(
        message: 'Only a finished report is taken out.',
        code: 'analytics_export_run_not_finished',
      );
    }
    await _requireFreeLabel(run.id, artifactLabel);
    return _repository.appendExport(
      AnalyticsExport.registerRow(
        tenantId: run.tenantId,
        runId: run.id,
        artifactLabel: artifactLabel,
        exportedBy: exportedBy,
        format: format,
        destination: destination,
        byteSize: byteSize,
        checksum: checksum,
        note: note,
        exportedAt: at,
        exportId: exportId,
      ),
    );
  }

  /// One artefact name per run, because two rows with one name are two answers
  /// to "what did they take".
  Future<void> _requireFreeLabel(String runId, String artifactLabel) async {
    final ReportRun? run = await _repository.runById(runId);
    if (run == null) {
      return;
    }
    final List<AnalyticsExport> exports = await _repository.listExports(
      run.tenantId,
      runId: runId,
    );
    for (final AnalyticsExport other in exports) {
      if (other.artifactLabel == artifactLabel.trim()) {
        throw const ValidationError(
          message: 'Analytics export failed validation.',
          fieldErrors: <String, String>{
            'artifact_label': 'That artefact is already recorded.',
          },
          code: 'analytics_export_label_duplicate',
        );
      }
    }
  }
}

/// The analytics warehouse as a gate list, a run list and a figure list.
@immutable
final class AnalyticsWarehouseBoard {
  /// Creates the board.
  const AnalyticsWarehouseBoard({
    required this.asOf,
    required this.definitions,
    required this.rollups,
    required this.runs,
    required this.exports,
  });

  /// The moment the board was read.
  final DateTime asOf;

  /// The report catalogue, by code.
  final List<ReportDefinition> definitions;

  /// Materialised rollups, newest period first.
  final List<AnalyticsRollup> rollups;

  /// Report runs, newest first.
  final List<ReportRun> runs;

  /// The export log, oldest first.
  final List<AnalyticsExport> exports;

  /// The definition with [id], or null.
  ReportDefinition? definitionFor(String id) {
    for (final ReportDefinition definition in definitions) {
      if (definition.id == id) {
        return definition;
      }
    }
    return null;
  }

  /// The rollups held for a definition, newest period first.
  List<AnalyticsRollup> rollupsFor(String definitionId) => <AnalyticsRollup>[
    for (final AnalyticsRollup rollup in rollups)
      if (rollup.definitionId == definitionId) rollup,
  ];

  /// The runs held for a definition, newest first.
  List<ReportRun> runsFor(String definitionId) => <ReportRun>[
    for (final ReportRun run in runs)
      if (run.definitionId == definitionId) run,
  ];

  /// The artefact log of a run, oldest first.
  List<AnalyticsExport> exportsFor(String runId) => <AnalyticsExport>[
    for (final AnalyticsExport export in exports)
      if (export.runId == runId) export,
  ];

  /// The reports that may be run.
  List<ReportDefinition> get runnableDefinitions => <ReportDefinition>[
    for (final ReportDefinition definition in definitions)
      if (definition.isRunnable) definition,
  ];

  /// The current figure of a definition at a grain, or null.
  AnalyticsRollup? latestRollup({
    required String definitionId,
    AnalyticsGrain? grain,
  }) {
    final ReportDefinition? definition = definitionFor(definitionId);
    return latestRollupFor(
      definitionId: definitionId,
      grain: grain ?? definition?.grain ?? AnalyticsGrain.month,
      rollups: rollups,
    );
  }

  /// The current figures whose own period closed long enough ago to be out of
  /// date.
  List<AnalyticsRollup> get staleRollups => <AnalyticsRollup>[
    for (final AnalyticsRollup rollup in rollups)
      if (rollup.isCurrent && isRollupStale(rollup: rollup, now: asOf)) rollup,
  ];

  /// The runs still to be worked.
  List<ReportRun> get liveRuns => <ReportRun>[
    for (final ReportRun run in runs)
      if (run.isLive) run,
  ];

  /// The runs that have been running longer than they should.
  List<ReportRun> get stalledRuns => <ReportRun>[
    for (final ReportRun run in runs)
      if (isRunStalled(run: run, now: asOf)) run,
  ];

  /// The runs that finished with rows.
  List<ReportRun> get succeededRuns => <ReportRun>[
    for (final ReportRun run in runs)
      if (run.succeeded) run,
  ];

  /// The runs that finished without rows.
  List<ReportRun> get failedRuns => <ReportRun>[
    for (final ReportRun run in runs)
      if (run.status == ReportRunStatus.failed) run,
  ];

  /// The artefacts that left on the reader's own day.
  List<AnalyticsExport> get exportsToday {
    final DateTime day = DateTime.utc(asOf.year, asOf.month, asOf.day);
    return <AnalyticsExport>[
      for (final AnalyticsExport export in exports)
        if (!export.exportedAt.isBefore(day) &&
            export.exportedAt.isBefore(day.add(const Duration(days: 1))))
          export,
    ];
  }

  /// The percentage change in a definition's bottom line against the figure
  /// before it, or null when there is nothing to compare or nothing to compare
  /// with.
  double? growthFor({required String definitionId, AnalyticsGrain? grain}) {
    final ReportDefinition? definition = definitionFor(definitionId);
    final AnalyticsGrain effectiveGrain =
        grain ?? definition?.grain ?? AnalyticsGrain.month;
    final List<AnalyticsRollup> figures =
        <AnalyticsRollup>[
          for (final AnalyticsRollup rollup in rollups)
            if (rollup.definitionId == definitionId &&
                rollup.grain == effectiveGrain &&
                rollup.isCurrent)
              rollup,
        ]..sort(
          (AnalyticsRollup a, AnalyticsRollup b) =>
              b.periodStart.compareTo(a.periodStart),
        );
    if (figures.length < 2) {
      return null;
    }
    return growthRate(
      current: figures[0].netPosition,
      previous: figures[1].netPosition,
    );
  }

  /// Whether a current figure of the definition covers a requested range.
  bool isCoveredByRollup({
    required String definitionId,
    required DateTime from,
    required DateTime to,
    AnalyticsGrain? grain,
  }) {
    final ReportDefinition? definition = definitionFor(definitionId);
    final AnalyticsGrain effectiveGrain =
        grain ?? definition?.grain ?? AnalyticsGrain.month;
    for (final AnalyticsRollup rollup in rollups) {
      if (rollup.definitionId == definitionId &&
          rollup.grain == effectiveGrain &&
          rollup.isCurrent &&
          isRollupCovering(rollup: rollup, from: from, to: to)) {
        return true;
      }
    }
    return false;
  }

  /// Whether anything on the board wants a decision.
  bool get needsAttention =>
      stalledRuns.isNotEmpty ||
      failedRuns.isNotEmpty ||
      staleRollups.isNotEmpty;
}

/// Reads the analytics warehouse and its derived markers.
final class ReadAnalyticsWarehouseUseCase {
  /// Creates the use case.
  ReadAnalyticsWarehouseUseCase({required this._repository});

  final AnalyticsRepository _repository;

  Future<AnalyticsWarehouseBoard> board({
    required AuthorizationPolicy policy,
    required String tenantId,
    DateTime? now,
  }) async {
    policy.require(NodexPermissions.analyticsRead);
    final List<ReportDefinition> definitions = await definitionsOf(
      policy: policy,
      tenantId: tenantId,
    );
    final List<AnalyticsRollup> rollups = await rollupsOf(
      policy: policy,
      tenantId: tenantId,
    );
    final List<ReportRun> runs = await runsOf(
      policy: policy,
      tenantId: tenantId,
    );
    final List<AnalyticsExport> exports = await exportsOf(
      policy: policy,
      tenantId: tenantId,
    );
    return AnalyticsWarehouseBoard(
      asOf: (now ?? DateTime.now()).toUtc(),
      definitions: definitions,
      rollups: rollups,
      runs: runs,
      exports: exports,
    );
  }

  /// The catalogue, by code.
  Future<List<ReportDefinition>> definitionsOf({
    required AuthorizationPolicy policy,
    required String tenantId,
    String? category,
    String? status,
  }) async {
    policy.require(NodexPermissions.analyticsRead);
    final List<ReportDefinition> definitions = await _repository
        .listDefinitions(tenantId, category: category, status: status);
    return <ReportDefinition>[...definitions]..sort(
      (ReportDefinition a, ReportDefinition b) => a.code.compareTo(b.code),
    );
  }

  /// The figures, newest period first.
  Future<List<AnalyticsRollup>> rollupsOf({
    required AuthorizationPolicy policy,
    required String tenantId,
    String? definitionId,
    String? grain,
    String? status,
  }) async {
    policy.require(NodexPermissions.analyticsRead);
    final List<AnalyticsRollup> rollups = await _repository.listRollups(
      tenantId,
      definitionId: definitionId,
      grain: grain,
      status: status,
    );
    return <AnalyticsRollup>[...rollups]
      ..sort((AnalyticsRollup a, AnalyticsRollup b) {
        final int byPeriod = b.periodStart.compareTo(a.periodStart);
        return byPeriod != 0
            ? byPeriod
            : a.definitionId.compareTo(b.definitionId);
      });
  }

  /// The runs, newest first.
  Future<List<ReportRun>> runsOf({
    required AuthorizationPolicy policy,
    required String tenantId,
    String? definitionId,
    String? status,
  }) async {
    policy.require(NodexPermissions.analyticsRead);
    final List<ReportRun> runs = await _repository.listRuns(
      tenantId,
      definitionId: definitionId,
      status: status,
    );
    return <ReportRun>[...runs]..sort((ReportRun a, ReportRun b) {
      final DateTime? left = a.createdAt;
      final DateTime? right = b.createdAt;
      if (left == null || right == null) {
        return b.updatedAt.compareTo(a.updatedAt);
      }
      return right.compareTo(left);
    });
  }

  /// The export log, oldest first.
  Future<List<AnalyticsExport>> exportsOf({
    required AuthorizationPolicy policy,
    required String tenantId,
    String? runId,
  }) async {
    policy.require(NodexPermissions.analyticsRead);
    final List<AnalyticsExport> exports = await _repository.listExports(
      tenantId,
      runId: runId,
    );
    return <AnalyticsExport>[...exports]..sort(
      (AnalyticsExport a, AnalyticsExport b) =>
          a.exportedAt.compareTo(b.exportedAt),
    );
  }
}
