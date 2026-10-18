/// Reports & Operational Analytics Warehouse (Module 38).
///
/// Three tabs: the report catalogue, the runs, and the figures the warehouse has
/// materialised. The catalogue is what the hospital says it measures; a run is
/// somebody asking for it; a figure is the answer, kept per period.
///
/// The screen never computes a total. What a period covers is [analyticsPeriodEnd],
/// a rate is the rollup's own ratio, a balance sheet's bottom line is its net
/// position, and whether a figure has gone out of date is derived from the clock
/// against the period it claims. Nothing on this screen is a stored flag that
/// somebody has to remember to clear, and nothing is a second opinion about the
/// number the warehouse materialised.
///
/// The export log is read where it matters, in the run sheet, because the question
/// a balance sheet raises is not "what does it say" but "who has one".
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/domain/analytics/analytics.dart';
import 'package:nodex_hms/domain/analytics/analytics_use_cases.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// The analytics warehouse screen.
class AnalyticsWarehouseScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const AnalyticsWarehouseScreen({super.key});

  @override
  ConsumerState<AnalyticsWarehouseScreen> createState() =>
      _AnalyticsWarehouseScreenState();
}

class _AnalyticsWarehouseScreenState
    extends ConsumerState<AnalyticsWarehouseScreen> {
  AnalyticsWarehouseBoard? _board;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = ref.read(sessionProvider);
    final String? tenantId = session.tenantId;
    if (tenantId == null) {
      setState(() {
        _error = 'Session is not ready.';
        _loading = false;
      });
      return;
    }
    try {
      final AnalyticsWarehouseBoard board = await ref
          .read(readAnalyticsWarehouseUseCaseProvider)
          .board(tenantId: tenantId, policy: session.authorization);
      if (!mounted) return;
      setState(() {
        _board = board;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      await _load();
    } on Object catch (error) {
      if (!mounted) return;
      _snack(error.toString());
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String? get _userId => ref.read(sessionProvider).user?.userId;

  String? get _facilityId {
    final Set<String> facilities =
        ref.read(sessionProvider).snapshot?.facilityIds ?? const <String>{};
    return facilities.isEmpty ? null : facilities.first;
  }

  Future<void> _defineReport() async {
    final String? userId = _userId;
    final String? tenantId = ref.read(sessionProvider).tenantId;
    if (userId == null || tenantId == null) return;
    final _DefinitionFormResult? result =
        await showDialog<_DefinitionFormResult>(
          context: context,
          builder: (BuildContext context) => const _DefinitionFormDialog(),
        );
    if (result == null) return;
    await _run(() async {
      await ref
          .read(defineReportUseCaseProvider)
          .call(
            policy: ref.read(sessionProvider).authorization,
            tenantId: tenantId,
            code: result.code,
            displayName: result.displayName,
            createdBy: userId,
            category: result.category,
            primarySource: result.primarySource,
            grain: result.grain,
            retentionDays: result.retentionDays,
            facilityId: result.hospitalWide ? null : _facilityId,
            description: result.description,
          );
    });
  }

  Future<void> _publish(ReportDefinition definition) async {
    final String? userId = _userId;
    if (userId == null) return;
    await _run(() async {
      await ref
          .read(publishReportUseCaseProvider)
          .call(
            policy: ref.read(sessionProvider).authorization,
            definition: definition,
            publishedBy: userId,
          );
    });
  }

  Future<void> _retire(ReportDefinition definition) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Retire the report'),
        content: const Text(
          'The report stops being run and becomes immutable. Its figures are '
          'kept so a past board pack still resolves to the definition it was '
          'built against.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Retire'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() async {
      await ref
          .read(retireReportUseCaseProvider)
          .call(
            policy: ref.read(sessionProvider).authorization,
            definition: definition,
          );
    });
  }

  Future<void> _materialise(ReportDefinition definition) async {
    final String? userId = _userId;
    if (userId == null) return;
    final _MaterialiseFormResult? result =
        await showDialog<_MaterialiseFormResult>(
          context: context,
          builder: (BuildContext context) =>
              _MaterialiseFormDialog(grain: definition.grain),
        );
    if (result == null) return;
    await _run(() async {
      await ref
          .read(materialiseRollupUseCaseProvider)
          .call(
            policy: ref.read(sessionProvider).authorization,
            definition: definition,
            createdBy: userId,
            materialisedBy: userId,
            periodStart: result.periodStart,
            rowCount: result.rowCount,
            numerator: result.numerator,
            denominator: result.denominator,
            incomeMinor: result.incomeMinor,
            expenditureMinor: result.expenditureMinor,
          );
    });
  }

  Future<void> _voidRollup(AnalyticsRollup rollup) async {
    final String? reason = await _askValue(
      title: 'Withdraw the figure',
      label: 'Why',
      confirm: 'Withdraw',
    );
    if (reason == null) return;
    await _run(() async {
      await ref
          .read(voidRollupUseCaseProvider)
          .call(
            policy: ref.read(sessionProvider).authorization,
            rollup: rollup,
            reason: reason,
          );
    });
  }

  Future<void> _queueRun() async {
    final AnalyticsWarehouseBoard? board = _board;
    final String? userId = _userId;
    if (board == null || userId == null) return;
    final List<ReportDefinition> runnable = board.runnableDefinitions;
    if (runnable.isEmpty) {
      _snack('No published report is available to run.');
      return;
    }
    final _RunFormResult? result = await showDialog<_RunFormResult>(
      context: context,
      builder: (BuildContext context) => _RunFormDialog(definitions: runnable),
    );
    if (result == null) return;
    final ReportDefinition? definition = board.definitionFor(
      result.definitionId,
    );
    if (definition == null) return;
    await _run(() async {
      await ref
          .read(queueReportRunUseCaseProvider)
          .call(
            policy: ref.read(sessionProvider).authorization,
            definition: definition,
            runNumber: result.runNumber,
            requestedBy: userId,
            createdBy: userId,
            periodStart: result.periodStart,
            filterNote: result.filterNote,
          );
    });
  }

  Future<void> _startRun(ReportRun run) async {
    await _run(() async {
      await ref
          .read(startReportRunUseCaseProvider)
          .call(policy: ref.read(sessionProvider).authorization, run: run);
    });
  }

  Future<void> _completeRun(ReportRun run) async {
    final _SettleFormResult? result = await showDialog<_SettleFormResult>(
      context: context,
      builder: (BuildContext context) => const _CompleteRunDialog(),
    );
    if (result == null) return;
    await _run(() async {
      await ref
          .read(completeReportRunUseCaseProvider)
          .call(
            policy: ref.read(sessionProvider).authorization,
            run: run,
            servedFrom: result.servedFrom,
            rowCount: result.rowCount,
          );
    });
  }

  Future<void> _failRun(ReportRun run) async {
    final String? reason = await _askValue(
      title: 'Fail the run',
      label: 'What went wrong',
      confirm: 'Fail',
    );
    if (reason == null) return;
    await _run(() async {
      await ref
          .read(failReportRunUseCaseProvider)
          .call(
            policy: ref.read(sessionProvider).authorization,
            run: run,
            reason: reason,
          );
    });
  }

  Future<void> _cancelRun(ReportRun run) async {
    final String? reason = await _askValue(
      title: 'Abandon the run',
      label: 'Why',
      confirm: 'Abandon',
    );
    if (reason == null) return;
    await _run(() async {
      await ref
          .read(cancelReportRunUseCaseProvider)
          .call(
            policy: ref.read(sessionProvider).authorization,
            run: run,
            reason: reason,
          );
    });
  }

  Future<void> _exportRun(ReportRun run) async {
    final String? userId = _userId;
    if (userId == null) return;
    final _ExportFormResult? result = await showDialog<_ExportFormResult>(
      context: context,
      builder: (BuildContext context) => _ExportFormDialog(run: run),
    );
    if (result == null) return;
    await _run(() async {
      await ref
          .read(exportReportRunUseCaseProvider)
          .call(
            policy: ref.read(sessionProvider).authorization,
            run: run,
            artifactLabel: result.artifactLabel,
            exportedBy: userId,
            format: result.format,
            destination: result.destination,
            note: result.note,
          );
    });
  }

  Future<String?> _askValue({
    required String title,
    required String label,
    required String confirm,
  }) async {
    final TextEditingController controller = TextEditingController();
    final bool? accepted = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: InputDecoration(labelText: label),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirm),
          ),
        ],
      ),
    );
    final String value = controller.text.trim();
    controller.dispose();
    if (accepted != true || value.isEmpty) {
      return null;
    }
    return value;
  }

  Future<void> _showDefinition(ReportDefinition definition) async {
    final AnalyticsWarehouseBoard? board = _board;
    final AnalyticsRollup? figure = board?.latestRollup(
      definitionId: definition.id,
    );
    final double? growth = board?.growthFor(definitionId: definition.id);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.assessment_outlined),
              title: Text('${definition.code} · ${definition.displayName}'),
              subtitle: Text(
                <String>[
                  '${definition.category.label} · ${definition.primarySource.label}',
                  definition.grain.label,
                  definition.status.label,
                  if (definition.isHospitalWide)
                    'Hospital-wide'
                  else
                    'One facility',
                  'Kept ${definition.retentionDays} days',
                  if (figure != null)
                    'Latest ${_periodLabel(figure)}: '
                        '${_formatMoney(figure.netPosition)}'
                  else
                    'No figure materialised yet',
                  if (growth case final double rate)
                    'Against the period before: ${_formatPercent(rate)}',
                  if (figure?.ratio case final double ratio)
                    'Rate ${_formatPercent(ratio)}',
                  if (definition.description case final String text) text,
                  if (definition.publishedAt case final DateTime at)
                    'Published ${_formatMoment(at)}',
                ].join('\n'),
              ),
            ),
            if (definition.status == ReportDefinitionStatus.draft)
              ListTile(
                leading: const Icon(Icons.publish_outlined),
                title: const Text('Publish the report'),
                onTap: () {
                  Navigator.of(context).pop();
                  _publish(definition);
                },
              ),
            if (definition.isRunnable)
              ListTile(
                leading: const Icon(Icons.play_circle_outline),
                title: const Text('Run it now'),
                onTap: () {
                  Navigator.of(context).pop();
                  _queueRunFor(definition);
                },
              ),
            if (definition.isRunnable)
              ListTile(
                leading: const Icon(Icons.functions_outlined),
                title: const Text('Materialise a figure'),
                onTap: () {
                  Navigator.of(context).pop();
                  _materialise(definition);
                },
              ),
            if (definition.status == ReportDefinitionStatus.published)
              ListTile(
                leading: const Icon(Icons.block_outlined),
                title: const Text('Retire the report'),
                onTap: () {
                  Navigator.of(context).pop();
                  _retire(definition);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _queueRunFor(ReportDefinition definition) async {
    final String? userId = _userId;
    if (userId == null) return;
    final _RunFormResult? result = await showDialog<_RunFormResult>(
      context: context,
      builder: (BuildContext context) =>
          _RunFormDialog(definitions: <ReportDefinition>[definition]),
    );
    if (result == null) return;
    await _run(() async {
      await ref
          .read(queueReportRunUseCaseProvider)
          .call(
            policy: ref.read(sessionProvider).authorization,
            definition: definition,
            runNumber: result.runNumber,
            requestedBy: userId,
            createdBy: userId,
            periodStart: result.periodStart,
            filterNote: result.filterNote,
          );
    });
  }

  Future<void> _showRun(ReportRun run) async {
    final AnalyticsWarehouseBoard? board = _board;
    final ReportDefinition? definition = board?.definitionFor(run.definitionId);
    List<AnalyticsExport> exports = const <AnalyticsExport>[];
    final String? tenantId = ref.read(sessionProvider).tenantId;
    if (tenantId != null) {
      try {
        exports = await ref
            .read(readAnalyticsWarehouseUseCaseProvider)
            .exportsOf(
              policy: ref.read(sessionProvider).authorization,
              tenantId: tenantId,
              runId: run.id,
            );
      } on Object catch (error) {
        if (!mounted) return;
        _snack(error.toString());
        return;
      }
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.query_stats_outlined),
              title: Text('${run.runNumber} · ${run.status.label}'),
              subtitle: Text(
                <String>[
                  definition?.displayName ?? run.definitionId,
                  '${_formatDate(run.periodStart)} to ${_formatDate(run.periodEnd)}',
                  if (run.servedFrom case final RollupServedFrom from)
                    'Answered from the ${from.label.toLowerCase()}',
                  if (run.rowCount case final int rows) '$rows rows',
                  if (run.durationSeconds case final int seconds)
                    'Took $seconds s',
                  if (run.filterNote case final String note) note,
                  if (run.failureReason case final String why) 'Failed: $why',
                  if (run.cancelReason case final String why) 'Abandoned: $why',
                  if (run.requestedBy case final String who) 'Asked by $who',
                ].join('\n'),
              ),
            ),
            if (run.status == ReportRunStatus.queued)
              ListTile(
                leading: const Icon(Icons.play_arrow_outlined),
                title: const Text('Start the run'),
                onTap: () {
                  Navigator.of(context).pop();
                  _startRun(run);
                },
              ),
            if (run.status == ReportRunStatus.running)
              ListTile(
                leading: const Icon(Icons.check_circle_outline),
                title: const Text('Finish with rows'),
                onTap: () {
                  Navigator.of(context).pop();
                  _completeRun(run);
                },
              ),
            if (run.status == ReportRunStatus.running)
              ListTile(
                leading: const Icon(Icons.error_outline),
                title: const Text('Record a failure'),
                onTap: () {
                  Navigator.of(context).pop();
                  _failRun(run);
                },
              ),
            if (run.isLive)
              ListTile(
                leading: const Icon(Icons.cancel_outlined),
                title: const Text('Abandon the run'),
                onTap: () {
                  Navigator.of(context).pop();
                  _cancelRun(run);
                },
              ),
            if (run.succeeded)
              ListTile(
                leading: const Icon(Icons.ios_share_outlined),
                title: const Text('Take the report out'),
                onTap: () {
                  Navigator.of(context).pop();
                  _exportRun(run);
                },
              ),
            for (final AnalyticsExport export in exports)
              ListTile(
                dense: true,
                leading: const Icon(Icons.receipt_long_outlined),
                title: Text('${export.artifactLabel} · ${export.format.label}'),
                subtitle: Text(
                  <String>[
                    _formatMoment(export.exportedAt),
                    export.destination.label,
                    if (export.byteSize case final int size)
                      '${(size / 1024).toStringAsFixed(0)} KB',
                    if (export.note case final String note) note,
                  ].join(' · '),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showRollup(AnalyticsRollup rollup) async {
    final AnalyticsWarehouseBoard? board = _board;
    final ReportDefinition? definition = board?.definitionFor(
      rollup.definitionId,
    );
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.stacked_line_chart_outlined),
              title: Text(
                '${definition?.displayName ?? rollup.definitionId} · '
                '${_periodLabel(rollup)}',
              ),
              subtitle: Text(
                <String>[
                  rollup.status.label,
                  '${rollup.rowCount} rows',
                  'Money in ${_formatMoney(rollup.incomeMinor)}',
                  'Money out ${_formatMoney(rollup.expenditureMinor)}',
                  'Bottom line ${_formatMoney(rollup.netPosition)}',
                  if (rollup.ratio case final double ratio)
                    'Rate ${_formatPercent(ratio)}',
                  'Materialised ${_formatMoment(rollup.materialisedAt)}',
                  if (rollup.voidReason case final String why)
                    'Withdrawn: $why',
                  if (rollup.supersedeNote case final String note) note,
                ].join('\n'),
              ),
            ),
            if (rollup.isCurrent)
              ListTile(
                leading: const Icon(Icons.block_outlined),
                title: const Text('Withdraw the figure'),
                onTap: () {
                  Navigator.of(context).pop();
                  _voidRollup(rollup);
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AnalyticsWarehouseBoard? board = _board;
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null || board == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Analytics')),
        body: Center(
          child: Text(_error ?? 'The analytics warehouse is unavailable.'),
        ),
      );
    }
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Reports & analytics'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: <Widget>[
              Tab(text: 'Reports'),
              Tab(text: 'Runs'),
              Tab(text: 'Figures'),
            ],
          ),
        ),
        body: TabBarView(
          children: <Widget>[
            _definitionTab(board),
            _runTab(board),
            _rollupTab(board),
          ],
        ),
      ),
    );
  }

  Widget _definitionTab(AnalyticsWarehouseBoard board) {
    return Stack(
      children: <Widget>[
        Column(
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.assessment_outlined),
              title: Text('${board.definitions.length} reports catalogued'),
              subtitle: Text(
                '${board.runnableDefinitions.length} published · '
                '${board.staleRollups.length} figures out of date',
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: board.definitions.isEmpty
                  ? const Center(child: Text('No reports catalogued yet.'))
                  : ListView.builder(
                      itemCount: board.definitions.length,
                      itemBuilder: (BuildContext context, int index) {
                        final ReportDefinition definition =
                            board.definitions[index];
                        final AnalyticsRollup? figure = board.latestRollup(
                          definitionId: definition.id,
                        );
                        final bool stale =
                            figure != null &&
                            isRollupStale(rollup: figure, now: board.asOf);
                        return ListTile(
                          leading: Icon(
                            definition.isRunnable
                                ? Icons.assessment_outlined
                                : Icons.assessment,
                            color: stale
                                ? Theme.of(context).colorScheme.error
                                : null,
                          ),
                          title: Text(definition.displayName),
                          subtitle: Text(
                            <String>[
                              definition.code,
                              definition.category.label,
                              definition.grain.label,
                              definition.status.label,
                              if (stale) 'Figure out of date',
                            ].join(' · '),
                          ),
                          onTap: () => _showDefinition(definition),
                        );
                      },
                    ),
            ),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            onPressed: _defineReport,
            icon: const Icon(Icons.add),
            label: const Text('Add report'),
          ),
        ),
      ],
    );
  }

  Widget _runTab(AnalyticsWarehouseBoard board) {
    return Stack(
      children: <Widget>[
        Column(
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.query_stats_outlined),
              title: Text('${board.runs.length} runs on this device'),
              subtitle: Text(
                '${board.liveRuns.length} in flight · '
                '${board.stalledRuns.length} stalled · '
                '${board.failedRuns.length} failed',
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: board.runs.isEmpty
                  ? const Center(child: Text('No report has been run yet.'))
                  : ListView.builder(
                      itemCount: board.runs.length,
                      itemBuilder: (BuildContext context, int index) {
                        final ReportRun run = board.runs[index];
                        final bool stalled = isRunStalled(
                          run: run,
                          now: board.asOf,
                        );
                        return ListTile(
                          leading: Icon(
                            switch (run.status) {
                              ReportRunStatus.queued => Icons.schedule_outlined,
                              ReportRunStatus.running => Icons.hourglass_top,
                              ReportRunStatus.succeeded =>
                                Icons.check_circle_outline,
                              ReportRunStatus.failed => Icons.error_outline,
                              ReportRunStatus.cancelled =>
                                Icons.cancel_outlined,
                            },
                            color: stalled
                                ? Theme.of(context).colorScheme.error
                                : null,
                          ),
                          title: Text(run.runNumber),
                          subtitle: Text(
                            <String>[
                              board
                                      .definitionFor(run.definitionId)
                                      ?.displayName ??
                                  run.definitionId,
                              run.status.label,
                              _formatDate(run.periodStart),
                              if (run.servedFrom
                                  case final RollupServedFrom from)
                                from.label,
                              if (stalled) 'Running too long',
                            ].join(' · '),
                          ),
                          onTap: () => _showRun(run),
                        );
                      },
                    ),
            ),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            onPressed: _queueRun,
            icon: const Icon(Icons.add),
            label: const Text('Run a report'),
          ),
        ),
      ],
    );
  }

  Widget _rollupTab(AnalyticsWarehouseBoard board) {
    return Column(
      children: <Widget>[
        ListTile(
          leading: const Icon(Icons.stacked_line_chart_outlined),
          title: Text('${board.rollups.length} figures held'),
          subtitle: Text(
            '${board.staleRollups.length} out of date · '
            '${board.exportsToday.length} artefacts taken today',
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: board.rollups.isEmpty
              ? const Center(child: Text('No figure materialised yet.'))
              : ListView.builder(
                  itemCount: board.rollups.length,
                  itemBuilder: (BuildContext context, int index) {
                    final AnalyticsRollup rollup = board.rollups[index];
                    final bool stale = isRollupStale(
                      rollup: rollup,
                      now: board.asOf,
                    );
                    return ListTile(
                      leading: Icon(
                        rollup.isCurrent
                            ? Icons.insights_outlined
                            : Icons.insights,
                        color: stale && rollup.isCurrent
                            ? Theme.of(context).colorScheme.error
                            : null,
                      ),
                      title: Text(
                        '${board.definitionFor(rollup.definitionId)?.displayName ?? rollup.definitionId} · ${_periodLabel(rollup)}',
                      ),
                      subtitle: Text(
                        <String>[
                          rollup.grain.label,
                          rollup.status.label,
                          _formatMoney(rollup.netPosition),
                          if (rollup.isSurplus) 'Surplus',
                          if (rollup.isDeficit) 'Deficit',
                          if (rollup.ratio case final double ratio)
                            'Rate ${_formatPercent(ratio)}',
                          if (stale && rollup.isCurrent) 'Out of date',
                        ].join(' · '),
                      ),
                      onTap: () => _showRollup(rollup),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _DefinitionFormResult {
  const _DefinitionFormResult({
    required this.code,
    required this.displayName,
    required this.category,
    required this.primarySource,
    required this.grain,
    required this.retentionDays,
    required this.hospitalWide,
    this.description,
  });

  final String code;
  final String displayName;
  final ReportCategory category;
  final AnalyticsSource primarySource;
  final AnalyticsGrain grain;
  final int retentionDays;
  final bool hospitalWide;
  final String? description;
}

class _DefinitionFormDialog extends StatefulWidget {
  const _DefinitionFormDialog();

  @override
  State<_DefinitionFormDialog> createState() => _DefinitionFormDialogState();
}

class _DefinitionFormDialogState extends State<_DefinitionFormDialog> {
  final TextEditingController _code = TextEditingController();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _description = TextEditingController();
  final TextEditingController _retention = TextEditingController(text: '3650');
  ReportCategory _category = ReportCategory.morbidity;
  AnalyticsSource _source = AnalyticsSource.encounters;
  AnalyticsGrain _grain = AnalyticsGrain.month;
  bool _hospitalWide = true;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _description.dispose();
    _retention.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add a report'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _code,
            decoration: const InputDecoration(labelText: 'Report code'),
          ),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Display name'),
          ),
          DropdownButtonFormField<ReportCategory>(
            initialValue: _category,
            decoration: const InputDecoration(labelText: 'Category'),
            items: <DropdownMenuItem<ReportCategory>>[
              for (final ReportCategory value in ReportCategory.values)
                DropdownMenuItem<ReportCategory>(
                  value: value,
                  child: Text(value.label),
                ),
            ],
            onChanged: (ReportCategory? value) {
              if (value != null) setState(() => _category = value);
            },
          ),
          DropdownButtonFormField<AnalyticsSource>(
            initialValue: _source,
            decoration: const InputDecoration(labelText: 'Drawn from'),
            items: <DropdownMenuItem<AnalyticsSource>>[
              for (final AnalyticsSource value in AnalyticsSource.values)
                DropdownMenuItem<AnalyticsSource>(
                  value: value,
                  child: Text(value.label),
                ),
            ],
            onChanged: (AnalyticsSource? value) {
              if (value != null) setState(() => _source = value);
            },
          ),
          DropdownButtonFormField<AnalyticsGrain>(
            initialValue: _grain,
            decoration: const InputDecoration(labelText: 'Period grain'),
            items: <DropdownMenuItem<AnalyticsGrain>>[
              for (final AnalyticsGrain value in AnalyticsGrain.values)
                DropdownMenuItem<AnalyticsGrain>(
                  value: value,
                  child: Text(value.label),
                ),
            ],
            onChanged: (AnalyticsGrain? value) {
              if (value != null) setState(() => _grain = value);
            },
          ),
          TextField(
            controller: _retention,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Kept for (days)'),
          ),
          TextField(
            controller: _description,
            decoration: const InputDecoration(labelText: 'What it is for'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _hospitalWide,
            title: const Text('Hospital-wide'),
            subtitle: const Text('Off for a single facility'),
            onChanged: (bool value) => setState(() => _hospitalWide = value),
          ),
        ],
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(
          _DefinitionFormResult(
            code: _code.text.trim(),
            displayName: _name.text.trim(),
            category: _category,
            primarySource: _source,
            grain: _grain,
            retentionDays: int.tryParse(_retention.text.trim()) ?? 3650,
            hospitalWide: _hospitalWide,
            description: _description.text.trim().isEmpty
                ? null
                : _description.text.trim(),
          ),
        ),
        child: const Text('Add'),
      ),
    ],
  );
}

class _MaterialiseFormResult {
  const _MaterialiseFormResult({
    required this.periodStart,
    required this.rowCount,
    required this.numerator,
    required this.denominator,
    required this.incomeMinor,
    required this.expenditureMinor,
  });

  final DateTime periodStart;
  final int rowCount;
  final int numerator;
  final int denominator;
  final int incomeMinor;
  final int expenditureMinor;
}

class _MaterialiseFormDialog extends StatefulWidget {
  const _MaterialiseFormDialog({required this.grain});

  /// The grain the definition is defined at, so the period can be shown.
  final AnalyticsGrain grain;

  @override
  State<_MaterialiseFormDialog> createState() => _MaterialiseFormDialogState();
}

class _MaterialiseFormDialogState extends State<_MaterialiseFormDialog> {
  final TextEditingController _rows = TextEditingController(text: '0');
  final TextEditingController _numerator = TextEditingController(text: '0');
  final TextEditingController _denominator = TextEditingController(text: '0');
  final TextEditingController _income = TextEditingController(text: '0');
  final TextEditingController _expenditure = TextEditingController(text: '0');
  late DateTime _periodStart = analyticsPeriodStartFor(
    grain: widget.grain,
    at: DateTime.now(),
  );

  @override
  void dispose() {
    _rows.dispose();
    _numerator.dispose();
    _denominator.dispose();
    _income.dispose();
    _expenditure.dispose();
    super.dispose();
  }

  Future<void> _pickPeriod() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _periodStart,
      firstDate: DateTime.utc(2015),
      lastDate: DateTime.utc(2100),
    );
    if (picked == null || !mounted) return;
    setState(() => _periodStart = DateTime.utc(picked.year, picked.month, 1));
  }

  int _minor(TextEditingController controller) {
    final double? value = double.tryParse(controller.text.trim());
    return value == null ? 0 : (value * 100).round();
  }

  @override
  Widget build(BuildContext context) {
    final DateTime periodEnd = analyticsPeriodEnd(
      grain: widget.grain,
      periodStart: _periodStart,
    );
    return AlertDialog(
      title: const Text('Materialise a figure'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                '${widget.grain.label} · ${_formatDate(_periodStart)} to '
                '${_formatDate(periodEnd)}',
              ),
              trailing: TextButton(
                onPressed: _pickPeriod,
                child: const Text('Change'),
              ),
            ),
            TextField(
              controller: _rows,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Rows added up'),
            ),
            TextField(
              controller: _numerator,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Numerator'),
            ),
            TextField(
              controller: _denominator,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Denominator'),
            ),
            TextField(
              controller: _income,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Money in (major units)',
              ),
            ),
            TextField(
              controller: _expenditure,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Money out (major units)',
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            _MaterialiseFormResult(
              periodStart: _periodStart,
              rowCount: int.tryParse(_rows.text.trim()) ?? 0,
              numerator: int.tryParse(_numerator.text.trim()) ?? 0,
              denominator: int.tryParse(_denominator.text.trim()) ?? 0,
              incomeMinor: _minor(_income),
              expenditureMinor: _minor(_expenditure),
            ),
          ),
          child: const Text('Materialise'),
        ),
      ],
    );
  }
}

class _RunFormResult {
  const _RunFormResult({
    required this.definitionId,
    required this.runNumber,
    required this.periodStart,
    this.filterNote,
  });

  final String definitionId;
  final String runNumber;
  final DateTime periodStart;
  final String? filterNote;
}

class _RunFormDialog extends StatefulWidget {
  const _RunFormDialog({required this.definitions});

  /// The reports that may be run.
  final List<ReportDefinition> definitions;

  @override
  State<_RunFormDialog> createState() => _RunFormDialogState();
}

class _RunFormDialogState extends State<_RunFormDialog> {
  final TextEditingController _runNumber = TextEditingController();
  final TextEditingController _filter = TextEditingController();
  late String _definitionId = widget.definitions.first.id;
  late DateTime _periodStart = analyticsPeriodStartFor(
    grain: widget.definitions.first.grain,
    at: DateTime.now(),
  );

  @override
  void dispose() {
    _runNumber.dispose();
    _filter.dispose();
    super.dispose();
  }

  Future<void> _pickPeriod() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _periodStart,
      firstDate: DateTime.utc(2015),
      lastDate: DateTime.utc(2100),
    );
    if (picked == null || !mounted) return;
    setState(() => _periodStart = DateTime.utc(picked.year, picked.month, 1));
  }

  @override
  Widget build(BuildContext context) {
    final ReportDefinition selected = widget.definitions.firstWhere(
      (ReportDefinition definition) => definition.id == _definitionId,
      orElse: () => widget.definitions.first,
    );
    return AlertDialog(
      title: const Text('Run a report'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            DropdownButtonFormField<String>(
              initialValue: _definitionId,
              decoration: const InputDecoration(labelText: 'Report'),
              items: <DropdownMenuItem<String>>[
                for (final ReportDefinition definition in widget.definitions)
                  DropdownMenuItem<String>(
                    value: definition.id,
                    child: Text(definition.displayName),
                  ),
              ],
              onChanged: (String? value) {
                if (value == null) return;
                setState(() {
                  _definitionId = value;
                  _periodStart = analyticsPeriodStartFor(
                    grain: widget.definitions
                        .firstWhere(
                          (ReportDefinition definition) =>
                              definition.id == value,
                        )
                        .grain,
                    at: DateTime.now(),
                  );
                });
              },
            ),
            TextField(
              controller: _runNumber,
              decoration: const InputDecoration(labelText: 'Run number'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                '${selected.grain.label} · ${_formatDate(_periodStart)}',
              ),
              trailing: TextButton(
                onPressed: _pickPeriod,
                child: const Text('Change'),
              ),
            ),
            TextField(
              controller: _filter,
              decoration: const InputDecoration(
                labelText: 'Filter applied (optional)',
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            _RunFormResult(
              definitionId: _definitionId,
              runNumber: _runNumber.text.trim(),
              periodStart: _periodStart,
              filterNote: _filter.text.trim().isEmpty
                  ? null
                  : _filter.text.trim(),
            ),
          ),
          child: const Text('Queue'),
        ),
      ],
    );
  }
}

class _SettleFormResult {
  const _SettleFormResult({required this.servedFrom, required this.rowCount});

  final RollupServedFrom servedFrom;
  final int rowCount;
}

class _CompleteRunDialog extends StatefulWidget {
  const _CompleteRunDialog();

  @override
  State<_CompleteRunDialog> createState() => _CompleteRunDialogState();
}

class _CompleteRunDialogState extends State<_CompleteRunDialog> {
  final TextEditingController _rows = TextEditingController(text: '0');
  RollupServedFrom _servedFrom = RollupServedFrom.rollup;

  @override
  void dispose() {
    _rows.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Finish the run'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          DropdownButtonFormField<RollupServedFrom>(
            initialValue: _servedFrom,
            decoration: const InputDecoration(labelText: 'Answered from'),
            items: <DropdownMenuItem<RollupServedFrom>>[
              for (final RollupServedFrom value in RollupServedFrom.values)
                DropdownMenuItem<RollupServedFrom>(
                  value: value,
                  child: Text(value.label),
                ),
            ],
            onChanged: (RollupServedFrom? value) {
              if (value != null) setState(() => _servedFrom = value);
            },
          ),
          TextField(
            controller: _rows,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Rows returned'),
          ),
        ],
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(
          _SettleFormResult(
            servedFrom: _servedFrom,
            rowCount: int.tryParse(_rows.text.trim()) ?? 0,
          ),
        ),
        child: const Text('Finish'),
      ),
    ],
  );
}

class _ExportFormResult {
  const _ExportFormResult({
    required this.artifactLabel,
    required this.format,
    required this.destination,
    this.note,
  });

  final String artifactLabel;
  final ExportFormat format;
  final ExportDestination destination;
  final String? note;
}

class _ExportFormDialog extends StatefulWidget {
  const _ExportFormDialog({required this.run});

  /// The run the artefact comes from.
  final ReportRun run;

  @override
  State<_ExportFormDialog> createState() => _ExportFormDialogState();
}

class _ExportFormDialogState extends State<_ExportFormDialog> {
  late final TextEditingController _label = TextEditingController(
    text: '${widget.run.runNumber}.csv',
  );
  final TextEditingController _note = TextEditingController();
  ExportFormat _format = ExportFormat.csv;
  ExportDestination _destination = ExportDestination.download;

  @override
  void dispose() {
    _label.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Take the report out'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _label,
            decoration: const InputDecoration(labelText: 'File name'),
          ),
          DropdownButtonFormField<ExportFormat>(
            initialValue: _format,
            decoration: const InputDecoration(labelText: 'Format'),
            items: <DropdownMenuItem<ExportFormat>>[
              for (final ExportFormat value in ExportFormat.values)
                DropdownMenuItem<ExportFormat>(
                  value: value,
                  child: Text(value.label),
                ),
            ],
            onChanged: (ExportFormat? value) {
              if (value != null) setState(() => _format = value);
            },
          ),
          DropdownButtonFormField<ExportDestination>(
            initialValue: _destination,
            decoration: const InputDecoration(labelText: 'Where it goes'),
            items: <DropdownMenuItem<ExportDestination>>[
              for (final ExportDestination value in ExportDestination.values)
                DropdownMenuItem<ExportDestination>(
                  value: value,
                  child: Text(value.label),
                ),
            ],
            onChanged: (ExportDestination? value) {
              if (value != null) setState(() => _destination = value);
            },
          ),
          TextField(
            controller: _note,
            decoration: const InputDecoration(labelText: 'Why (optional)'),
          ),
        ],
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(
          _ExportFormResult(
            artifactLabel: _label.text.trim(),
            format: _format,
            destination: _destination,
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          ),
        ),
        child: const Text('Take it'),
      ),
    ],
  );
}

String _periodLabel(AnalyticsRollup rollup) =>
    '${_formatDate(rollup.periodStart)} to ${_formatDate(rollup.periodEnd)}';

String _formatDate(DateTime value) {
  final DateTime utc = value.toUtc();
  return '${utc.year.toString().padLeft(4, '0')}-'
      '${utc.month.toString().padLeft(2, '0')}-'
      '${utc.day.toString().padLeft(2, '0')}';
}

String _formatMoment(DateTime value) {
  final DateTime utc = value.toUtc();
  return '${_formatDate(utc)} '
      '${utc.hour.toString().padLeft(2, '0')}:'
      '${utc.minute.toString().padLeft(2, '0')}';
}

/// Money is held in minor units, so it is shown in minor units until the last
/// step, where it is only ever displayed.
String _formatMoney(int minorUnits) {
  final bool negative = minorUnits < 0;
  final int absolute = minorUnits.abs();
  final String units = (absolute ~/ 100).toString();
  final String minor = (absolute % 100).toString().padLeft(2, '0');
  return '${negative ? '-' : ''}$units.$minor';
}

String _formatPercent(double value) => '${value.toStringAsFixed(1)}%';
