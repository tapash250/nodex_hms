/// Quality & NABH Compliance Hub (Module 35).
///
/// Three tabs: the accreditation audits, the patient safety incident log and
/// the measured clinical indicators. Each is a guarded state machine, and the
/// screen says so: an audit is scheduled, started and scored; an incident is
/// reported, investigated, given an action plan and closed; an indicator is
/// drafted, published and, if needed, retracted.
///
/// The facts that would otherwise be stored twice are shown as the derivations
/// they are: the compliance score and its verdict come from the two criterion
/// counts, an indicator's value and target comparison come from its counts, its
/// unit and its direction, and the overdue markers come from the row and the
/// clock. An audit past its scheduled moment and an incident past its severity
/// response window are marked in red, not held in a column.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/domain/quality/quality.dart';
import 'package:nodex_hms/domain/quality/quality_use_cases.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// The quality and accreditation board.
class QualityHubScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const QualityHubScreen({super.key});

  @override
  ConsumerState<QualityHubScreen> createState() => _QualityHubScreenState();
}

class _QualityHubScreenState extends ConsumerState<QualityHubScreen> {
  QualityBoard? _board;
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
      final QualityBoard board = await ref
          .read(readQualityHubUseCaseProvider)
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

  /// The tenant, acting user and facility the screen is working under.
  ({String tenantId, String userId, String facilityId})? get _actingScope {
    final session = ref.read(sessionProvider);
    final String? tenantId = session.tenantId;
    final String? userId = session.user?.userId;
    final Set<String> facilities =
        session.snapshot?.facilityIds ?? const <String>{};
    if (tenantId == null || userId == null || facilities.isEmpty) {
      return null;
    }
    return (tenantId: tenantId, userId: userId, facilityId: facilities.first);
  }

  Future<void> _scheduleAudit() async {
    final scope = _actingScope;
    if (scope == null) return;
    final _AuditFormResult? result = await showDialog<_AuditFormResult>(
      context: context,
      builder: (BuildContext context) => const _AuditFormDialog(),
    );
    if (result == null) return;
    await _run(() async {
      await ref
          .read(scheduleComplianceAuditUseCaseProvider)
          .call(
            policy: ref.read(sessionProvider).authorization,
            tenantId: scope.tenantId,
            facilityId: scope.facilityId,
            chapter: result.chapter,
            title: result.title,
            scheduledFor: result.scheduledFor,
            createdBy: scope.userId,
            framework: result.framework,
            standardReference: result.standardReference,
          );
    });
  }

  Future<void> _startAudit(ComplianceAudit audit) async {
    await _run(() async {
      await ref
          .read(startComplianceAuditUseCaseProvider)
          .call(policy: ref.read(sessionProvider).authorization, audit: audit);
    });
  }

  Future<void> _completeAudit(ComplianceAudit audit) async {
    final scope = _actingScope;
    if (scope == null) return;
    final _ScoreResult? result = await showDialog<_ScoreResult>(
      context: context,
      builder: (BuildContext context) => const _ScoreDialog(),
    );
    if (result == null) return;
    await _run(() async {
      await ref
          .read(completeComplianceAuditUseCaseProvider)
          .call(
            policy: ref.read(sessionProvider).authorization,
            audit: audit,
            totalCriteria: result.totalCriteria,
            compliantCriteria: result.compliantCriteria,
            completedBy: scope.userId,
            findings: result.findings,
          );
    });
  }

  Future<void> _cancelAudit(ComplianceAudit audit) async {
    final String? reason = await _askValue(
      title: 'Call the audit off',
      label: 'Reason',
      confirm: 'Cancel audit',
    );
    if (reason == null) return;
    await _run(() async {
      await ref
          .read(cancelComplianceAuditUseCaseProvider)
          .call(
            policy: ref.read(sessionProvider).authorization,
            audit: audit,
            reason: reason,
          );
    });
  }

  Future<void> _reportIncident() async {
    final scope = _actingScope;
    if (scope == null) return;
    final _IncidentFormResult? result = await showDialog<_IncidentFormResult>(
      context: context,
      builder: (BuildContext context) => const _IncidentFormDialog(),
    );
    if (result == null) return;
    await _run(() async {
      await ref
          .read(reportIncidentUseCaseProvider)
          .call(
            policy: ref.read(sessionProvider).authorization,
            tenantId: scope.tenantId,
            facilityId: scope.facilityId,
            reportNumber: result.reportNumber,
            title: result.title,
            description: result.description,
            occurredAt: result.occurredAt,
            reportedBy: scope.userId,
            createdBy: scope.userId,
            category: result.category,
            severity: result.severity,
            location: result.location,
            immediateAction: result.immediateAction,
            followUpDueAt: result.followUpDueAt,
          );
    });
  }

  Future<void> _investigate(IncidentReport incident) async {
    final scope = _actingScope;
    if (scope == null) return;
    await _run(() async {
      await ref
          .read(investigateIncidentUseCaseProvider)
          .call(
            policy: ref.read(sessionProvider).authorization,
            incident: incident,
            assignedTo: scope.userId,
          );
    });
  }

  Future<void> _planAction(IncidentReport incident) async {
    final _ActionPlanResult? result = await showDialog<_ActionPlanResult>(
      context: context,
      builder: (BuildContext context) => const _ActionPlanDialog(),
    );
    if (result == null) return;
    await _run(() async {
      await ref
          .read(planIncidentActionUseCaseProvider)
          .call(
            policy: ref.read(sessionProvider).authorization,
            incident: incident,
            actionPlan: result.actionPlan,
            dueAt: result.dueAt,
          );
    });
  }

  Future<void> _closeIncident(IncidentReport incident) async {
    final String? note = await _askValue(
      title: 'Close the incident',
      label: 'Closure note',
      confirm: 'Close',
    );
    if (note == null) return;
    await _run(() async {
      await ref
          .read(closeIncidentUseCaseProvider)
          .call(
            policy: ref.read(sessionProvider).authorization,
            incident: incident,
            note: note,
          );
    });
  }

  Future<void> _voidIncident(IncidentReport incident) async {
    final String? reason = await _askValue(
      title: 'Withdraw the incident report',
      label: 'Reason',
      confirm: 'Withdraw',
    );
    if (reason == null) return;
    await _run(() async {
      await ref
          .read(voidIncidentUseCaseProvider)
          .call(
            policy: ref.read(sessionProvider).authorization,
            incident: incident,
            reason: reason,
          );
    });
  }

  Future<void> _recordIndicator() async {
    final scope = _actingScope;
    if (scope == null) return;
    final _IndicatorFormResult? result = await showDialog<_IndicatorFormResult>(
      context: context,
      builder: (BuildContext context) => const _IndicatorFormDialog(),
    );
    if (result == null) return;
    await _run(() async {
      await ref
          .read(recordClinicalIndicatorUseCaseProvider)
          .call(
            policy: ref.read(sessionProvider).authorization,
            tenantId: scope.tenantId,
            facilityId: scope.facilityId,
            code: result.code,
            name: result.name,
            periodStart: result.periodStart,
            periodEnd: result.periodEnd,
            createdBy: scope.userId,
            category: result.category,
            unit: result.unit,
            direction: result.direction,
            numerator: result.numerator,
            denominator: result.denominator,
            targetValue: result.targetValue,
            sourceNote: result.sourceNote,
          );
    });
  }

  Future<void> _publishIndicator(ClinicalIndicator indicator) async {
    final scope = _actingScope;
    if (scope == null) return;
    await _run(() async {
      await ref
          .read(publishClinicalIndicatorUseCaseProvider)
          .call(
            policy: ref.read(sessionProvider).authorization,
            indicator: indicator,
            publishedBy: scope.userId,
          );
    });
  }

  Future<void> _retractIndicator(ClinicalIndicator indicator) async {
    final String? reason = await _askValue(
      title: 'Retract the reading',
      label: 'Reason',
      confirm: 'Retract',
    );
    if (reason == null) return;
    await _run(() async {
      await ref
          .read(retractClinicalIndicatorUseCaseProvider)
          .call(
            policy: ref.read(sessionProvider).authorization,
            indicator: indicator,
            reason: reason,
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

  Future<void> _showAudit(ComplianceAudit audit) async {
    final QualityBoard? board = _board;
    await showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.verified_outlined),
              title: Text(
                '${audit.framework.label} ${audit.chapter} · ${audit.title}',
              ),
              subtitle: Text(
                <String>[
                  audit.status.label,
                  'Scheduled ${_formatMoment(audit.scheduledFor)}',
                  if (audit.conductedAt case final DateTime conducted)
                    'Conducted ${_formatMoment(conducted)}',
                  if (board != null && board.auditOverdue(audit))
                    'Past its scheduled moment',
                  if (audit.score case final int score) '$score%',
                  audit.verdict.label,
                  if (audit.totalCriteria case final int total)
                    '$total criteria assessed',
                  if (audit.compliantCriteria case final int met) '$met met',
                  if (audit.standardReference case final String reference)
                    reference,
                  if (audit.findings case final String findings) findings,
                  if (audit.correctiveActionDueAt case final DateTime due)
                    'Corrective action due ${_formatMoment(due)}',
                  if (audit.cancelReason case final String why)
                    'Cancelled: $why',
                ].join('\n'),
              ),
            ),
            if (audit.status == AuditStatus.planned)
              ListTile(
                leading: const Icon(Icons.play_arrow_outlined),
                title: const Text('Start the audit'),
                onTap: () {
                  Navigator.of(context).pop();
                  _startAudit(audit);
                },
              ),
            if (audit.status == AuditStatus.inProgress)
              ListTile(
                leading: const Icon(Icons.checklist_outlined),
                title: const Text('Score and complete'),
                onTap: () {
                  Navigator.of(context).pop();
                  _completeAudit(audit);
                },
              ),
            if (!audit.isTerminal)
              ListTile(
                leading: const Icon(Icons.block_outlined),
                title: const Text('Call the audit off'),
                onTap: () {
                  Navigator.of(context).pop();
                  _cancelAudit(audit);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showIncident(IncidentReport incident) async {
    final QualityBoard? board = _board;
    await showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.report_gmailerrorred_outlined),
              title: Text('${incident.reportNumber} · ${incident.title}'),
              subtitle: Text(
                <String>[
                  '${incident.category.label} · ${incident.severity.label}',
                  incident.status.label,
                  'Occurred ${_formatMoment(incident.occurredAt)}',
                  if (incident.location case final String where) where,
                  incident.description,
                  if (incident.immediateAction case final String action)
                    'At once: $action',
                  if (incident.investigationStartedAt case final DateTime since)
                    'Investigating since ${_formatMoment(since)}',
                  if (incident.actionPlan case final String plan) plan,
                  if (incident.actionPlanDueAt case final DateTime due)
                    'Action due ${_formatMoment(due)}',
                  if (incident.followUpDueAt case final DateTime due)
                    'Follow-up due ${_formatMoment(due)}',
                  if (board != null && board.incidentOverdue(incident))
                    'Past its response window (${incident.responseWindow.inHours} h)',
                  if (board != null && board.followUpOverdue(incident))
                    'Follow-up overdue',
                  if (incident.closureNote case final String note) note,
                  if (incident.voidReason case final String why)
                    'Withdrawn: $why',
                ].join('\n'),
              ),
            ),
            if (incident.status == IncidentStatus.reported)
              ListTile(
                leading: const Icon(Icons.search_outlined),
                title: const Text('Open the investigation'),
                onTap: () {
                  Navigator.of(context).pop();
                  _investigate(incident);
                },
              ),
            if (incident.status == IncidentStatus.investigating)
              ListTile(
                leading: const Icon(Icons.build_outlined),
                title: const Text('Agree the corrective action'),
                onTap: () {
                  Navigator.of(context).pop();
                  _planAction(incident);
                },
              ),
            if (incident.status == IncidentStatus.actionPlan)
              ListTile(
                leading: const Icon(Icons.task_alt_outlined),
                title: const Text('Close the incident'),
                onTap: () {
                  Navigator.of(context).pop();
                  _closeIncident(incident);
                },
              ),
            if (incident.isLive)
              ListTile(
                leading: const Icon(Icons.block_outlined),
                title: const Text('Withdraw the report'),
                onTap: () {
                  Navigator.of(context).pop();
                  _voidIncident(incident);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showIndicator(ClinicalIndicator indicator) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.insights_outlined),
              title: Text('${indicator.code} · ${indicator.name}'),
              subtitle: Text(
                <String>[
                  '${indicator.category.label} · ${indicator.status.label}',
                  '${_formatDay(indicator.periodStart)} to ${_formatDay(indicator.periodEnd)}',
                  '${indicator.numerator} of ${indicator.denominator} ${indicator.unit.label.toLowerCase()}',
                  if (indicator.value case final double value)
                    'Value ${_formatValue(value)}',
                  if (indicator.targetValue case final int target)
                    'Target $target (${indicator.direction.label.toLowerCase()})',
                  if (indicator.meetsTarget case final bool met)
                    met ? 'Meets the target' : 'Misses the target',
                  if (indicator.sourceNote case final String note) note,
                  if (indicator.retractReason case final String why)
                    'Retracted: $why',
                ].join('\n'),
              ),
            ),
            if (indicator.status.isDraft)
              ListTile(
                leading: const Icon(Icons.publish_outlined),
                title: const Text('Publish the reading'),
                onTap: () {
                  Navigator.of(context).pop();
                  _publishIndicator(indicator);
                },
              ),
            if (indicator.isPublished)
              ListTile(
                leading: const Icon(Icons.block_outlined),
                title: const Text('Retract the reading'),
                onTap: () {
                  Navigator.of(context).pop();
                  _retractIndicator(indicator);
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final QualityBoard? board = _board;
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null || board == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Quality hub')),
        body: Center(child: Text(_error ?? 'The quality hub is unavailable.')),
      );
    }
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Quality hub'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: <Widget>[
              Tab(text: 'Audits'),
              Tab(text: 'Incidents'),
              Tab(text: 'Indicators'),
            ],
          ),
        ),
        body: TabBarView(
          children: <Widget>[
            _auditTab(board),
            _incidentTab(board),
            _indicatorTab(board),
          ],
        ),
      ),
    );
  }

  Widget _auditTab(QualityBoard board) {
    return Stack(
      children: <Widget>[
        if (board.audits.isEmpty)
          const Center(child: Text('No accreditation audits on this device.'))
        else
          ListView.builder(
            itemCount: board.audits.length,
            itemBuilder: (BuildContext context, int index) {
              final ComplianceAudit audit = board.audits[index];
              final bool overdue = board.auditOverdue(audit);
              return ListTile(
                leading: Icon(
                  overdue ? Icons.error_outline : Icons.verified_outlined,
                  color: overdue ? Theme.of(context).colorScheme.error : null,
                ),
                title: Text('${audit.framework.label} ${audit.chapter}'),
                subtitle: Text(
                  <String>[
                    audit.title,
                    audit.status.label,
                    if (overdue) 'Past its scheduled moment',
                    if (audit.score case final int score)
                      '$score% · ${audit.verdict.label}',
                  ].join(' · '),
                ),
                onTap: () => _showAudit(audit),
              );
            },
          ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            onPressed: _scheduleAudit,
            icon: const Icon(Icons.add),
            label: const Text('Schedule audit'),
          ),
        ),
      ],
    );
  }

  Widget _incidentTab(QualityBoard board) {
    return Stack(
      children: <Widget>[
        if (board.incidents.isEmpty)
          const Center(child: Text('No incidents logged on this device.'))
        else
          ListView.builder(
            itemCount: board.incidents.length,
            itemBuilder: (BuildContext context, int index) {
              final IncidentReport incident = board.incidents[index];
              final bool overdue = board.incidentOverdue(incident);
              final bool followUp = board.followUpOverdue(incident);
              return ListTile(
                leading: Icon(
                  overdue || followUp
                      ? Icons.error_outline
                      : Icons.report_gmailerrorred_outlined,
                  color: overdue || followUp
                      ? Theme.of(context).colorScheme.error
                      : null,
                ),
                title: Text(incident.title),
                subtitle: Text(
                  <String>[
                    incident.reportNumber,
                    incident.category.label,
                    incident.severity.label,
                    incident.status.label,
                    if (overdue) 'Response window passed',
                    if (followUp) 'Follow-up overdue',
                  ].join(' · '),
                ),
                onTap: () => _showIncident(incident),
              );
            },
          ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            onPressed: _reportIncident,
            icon: const Icon(Icons.add),
            label: const Text('Report incident'),
          ),
        ),
      ],
    );
  }

  Widget _indicatorTab(QualityBoard board) {
    return Stack(
      children: <Widget>[
        if (board.indicators.isEmpty)
          const Center(child: Text('No clinical indicators on this device.'))
        else
          ListView.builder(
            itemCount: board.indicators.length,
            itemBuilder: (BuildContext context, int index) {
              final ClinicalIndicator indicator = board.indicators[index];
              final bool missing =
                  indicator.isPublished && indicator.meetsTarget == false;
              return ListTile(
                leading: Icon(
                  missing ? Icons.error_outline : Icons.insights_outlined,
                  color: missing ? Theme.of(context).colorScheme.error : null,
                ),
                title: Text('${indicator.code} · ${indicator.name}'),
                subtitle: Text(
                  <String>[
                    indicator.status.label,
                    '${_formatDay(indicator.periodStart)} to ${_formatDay(indicator.periodEnd)}',
                    if (indicator.value case final double value)
                      _formatValue(value),
                    if (missing) 'Below target',
                  ].join(' · '),
                ),
                onTap: () => _showIndicator(indicator),
              );
            },
          ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            onPressed: _recordIndicator,
            icon: const Icon(Icons.add),
            label: const Text('Record indicator'),
          ),
        ),
      ],
    );
  }
}

class _AuditFormResult {
  const _AuditFormResult({
    required this.framework,
    required this.chapter,
    required this.title,
    required this.scheduledFor,
    this.standardReference,
  });

  final AccreditationFramework framework;
  final String chapter;
  final String title;
  final DateTime scheduledFor;
  final String? standardReference;
}

class _AuditFormDialog extends StatefulWidget {
  const _AuditFormDialog();

  @override
  State<_AuditFormDialog> createState() => _AuditFormDialogState();
}

class _AuditFormDialogState extends State<_AuditFormDialog> {
  final TextEditingController _chapter = TextEditingController();
  final TextEditingController _title = TextEditingController();
  final TextEditingController _reference = TextEditingController();
  AccreditationFramework _framework = AccreditationFramework.nabh;
  DateTime _scheduledFor = DateTime.now().toUtc();

  @override
  void dispose() {
    _chapter.dispose();
    _title.dispose();
    _reference.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _scheduledFor.toUtc(),
      firstDate: DateTime.utc(2000),
      lastDate: DateTime.utc(2100),
    );
    if (picked != null) {
      setState(() => _scheduledFor = picked.toUtc());
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Schedule audit'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          DropdownButtonFormField<AccreditationFramework>(
            initialValue: _framework,
            decoration: const InputDecoration(labelText: 'Framework'),
            items: <DropdownMenuItem<AccreditationFramework>>[
              for (final AccreditationFramework value
                  in AccreditationFramework.values)
                DropdownMenuItem<AccreditationFramework>(
                  value: value,
                  child: Text(value.label),
                ),
            ],
            onChanged: (AccreditationFramework? value) {
              if (value != null) setState(() => _framework = value);
            },
          ),
          TextField(
            controller: _chapter,
            decoration: const InputDecoration(
              labelText: 'Chapter (for example COP)',
            ),
          ),
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          TextField(
            controller: _reference,
            decoration: const InputDecoration(
              labelText: 'Standard reference (optional)',
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_outlined),
            title: Text('Scheduled ${_formatDay(_scheduledFor)}'),
            trailing: TextButton(
              onPressed: _pickDate,
              child: const Text('Change'),
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
          _AuditFormResult(
            framework: _framework,
            chapter: _chapter.text.trim(),
            title: _title.text.trim(),
            scheduledFor: _scheduledFor,
            standardReference: _nullIfEmpty(_reference),
          ),
        ),
        child: const Text('Schedule'),
      ),
    ],
  );

  String? _nullIfEmpty(TextEditingController controller) {
    final String value = controller.text.trim();
    return value.isEmpty ? null : value;
  }
}

class _ScoreResult {
  const _ScoreResult({
    required this.totalCriteria,
    required this.compliantCriteria,
    this.findings,
  });

  final int totalCriteria;
  final int compliantCriteria;
  final String? findings;
}

class _ScoreDialog extends StatefulWidget {
  const _ScoreDialog();

  @override
  State<_ScoreDialog> createState() => _ScoreDialogState();
}

class _ScoreDialogState extends State<_ScoreDialog> {
  final TextEditingController _total = TextEditingController();
  final TextEditingController _compliant = TextEditingController();
  final TextEditingController _findings = TextEditingController();

  @override
  void dispose() {
    _total.dispose();
    _compliant.dispose();
    _findings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Score and complete'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _total,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Criteria assessed'),
          ),
          TextField(
            controller: _compliant,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Criteria met'),
          ),
          TextField(
            controller: _findings,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Findings (optional)'),
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
          _ScoreResult(
            totalCriteria: int.tryParse(_total.text.trim()) ?? 0,
            compliantCriteria: int.tryParse(_compliant.text.trim()) ?? 0,
            findings: _findings.text.trim().isEmpty
                ? null
                : _findings.text.trim(),
          ),
        ),
        child: const Text('Complete'),
      ),
    ],
  );
}

class _IncidentFormResult {
  const _IncidentFormResult({
    required this.reportNumber,
    required this.category,
    required this.severity,
    required this.title,
    required this.description,
    required this.occurredAt,
    this.location,
    this.immediateAction,
    this.followUpDueAt,
  });

  final String reportNumber;
  final IncidentCategory category;
  final IncidentSeverity severity;
  final String title;
  final String description;
  final DateTime occurredAt;
  final String? location;
  final String? immediateAction;
  final DateTime? followUpDueAt;
}

class _IncidentFormDialog extends StatefulWidget {
  const _IncidentFormDialog();

  @override
  State<_IncidentFormDialog> createState() => _IncidentFormDialogState();
}

class _IncidentFormDialogState extends State<_IncidentFormDialog> {
  final TextEditingController _number = TextEditingController();
  final TextEditingController _title = TextEditingController();
  final TextEditingController _description = TextEditingController();
  final TextEditingController _location = TextEditingController();
  final TextEditingController _immediate = TextEditingController();
  IncidentCategory _category = IncidentCategory.needleStick;
  IncidentSeverity _severity = IncidentSeverity.minor;
  bool _followUp = false;

  @override
  void dispose() {
    _number.dispose();
    _title.dispose();
    _description.dispose();
    _location.dispose();
    _immediate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Report incident'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _number,
            decoration: const InputDecoration(labelText: 'Report number'),
          ),
          DropdownButtonFormField<IncidentCategory>(
            initialValue: _category,
            decoration: const InputDecoration(labelText: 'Category'),
            items: <DropdownMenuItem<IncidentCategory>>[
              for (final IncidentCategory value in IncidentCategory.values)
                DropdownMenuItem<IncidentCategory>(
                  value: value,
                  child: Text(value.label),
                ),
            ],
            onChanged: (IncidentCategory? value) {
              if (value != null) setState(() => _category = value);
            },
          ),
          DropdownButtonFormField<IncidentSeverity>(
            initialValue: _severity,
            decoration: const InputDecoration(labelText: 'Severity'),
            items: <DropdownMenuItem<IncidentSeverity>>[
              for (final IncidentSeverity value in IncidentSeverity.values)
                DropdownMenuItem<IncidentSeverity>(
                  value: value,
                  child: Text(value.label),
                ),
            ],
            onChanged: (IncidentSeverity? value) {
              if (value != null) setState(() => _severity = value);
            },
          ),
          TextField(
            controller: _title,
            decoration: const InputDecoration(
              labelText: 'What happened, briefly',
            ),
          ),
          TextField(
            controller: _description,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'What happened, in full',
            ),
          ),
          TextField(
            controller: _location,
            decoration: const InputDecoration(labelText: 'Where (optional)'),
          ),
          TextField(
            controller: _immediate,
            decoration: const InputDecoration(
              labelText: 'What was done at once (optional)',
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _followUp,
            title: const Text('Set a serology follow-up date'),
            onChanged: (bool value) => setState(() => _followUp = value),
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
          _IncidentFormResult(
            reportNumber: _number.text.trim(),
            category: _category,
            severity: _severity,
            title: _title.text.trim(),
            description: _description.text.trim(),
            occurredAt: DateTime.now().toUtc(),
            location: _nullIfEmpty(_location),
            immediateAction: _nullIfEmpty(_immediate),
            followUpDueAt: _followUp
                ? DateTime.now().toUtc().add(const Duration(days: 180))
                : null,
          ),
        ),
        child: const Text('Report'),
      ),
    ],
  );

  String? _nullIfEmpty(TextEditingController controller) {
    final String value = controller.text.trim();
    return value.isEmpty ? null : value;
  }
}

class _ActionPlanResult {
  const _ActionPlanResult({required this.actionPlan, required this.dueAt});

  final String actionPlan;
  final DateTime dueAt;
}

class _ActionPlanDialog extends StatefulWidget {
  const _ActionPlanDialog();

  @override
  State<_ActionPlanDialog> createState() => _ActionPlanDialogState();
}

class _ActionPlanDialogState extends State<_ActionPlanDialog> {
  final TextEditingController _plan = TextEditingController();
  DateTime _dueAt = DateTime.now().toUtc().add(const Duration(days: 14));

  @override
  void dispose() {
    _plan.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _dueAt.toUtc(),
      firstDate: DateTime.utc(2000),
      lastDate: DateTime.utc(2100),
    );
    if (picked != null) {
      setState(() => _dueAt = picked.toUtc());
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Agree the corrective action'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _plan,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Action plan'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_outlined),
            title: Text('Due ${_formatDay(_dueAt)}'),
            trailing: TextButton(
              onPressed: _pickDate,
              child: const Text('Change'),
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
        onPressed: () => Navigator.of(
          context,
        ).pop(_ActionPlanResult(actionPlan: _plan.text.trim(), dueAt: _dueAt)),
        child: const Text('Record'),
      ),
    ],
  );
}

class _IndicatorFormResult {
  const _IndicatorFormResult({
    required this.code,
    required this.name,
    required this.category,
    required this.unit,
    required this.direction,
    required this.periodStart,
    required this.periodEnd,
    required this.numerator,
    required this.denominator,
    this.targetValue,
    this.sourceNote,
  });

  final String code;
  final String name;
  final IndicatorCategory category;
  final IndicatorUnit unit;
  final IndicatorDirection direction;
  final DateTime periodStart;
  final DateTime periodEnd;
  final int numerator;
  final int denominator;
  final int? targetValue;
  final String? sourceNote;
}

class _IndicatorFormDialog extends StatefulWidget {
  const _IndicatorFormDialog();

  @override
  State<_IndicatorFormDialog> createState() => _IndicatorFormDialogState();
}

class _IndicatorFormDialogState extends State<_IndicatorFormDialog> {
  final TextEditingController _code = TextEditingController();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _numerator = TextEditingController();
  final TextEditingController _denominator = TextEditingController();
  final TextEditingController _target = TextEditingController();
  final TextEditingController _note = TextEditingController();
  IndicatorCategory _category = IndicatorCategory.infectionControl;
  IndicatorUnit _unit = IndicatorUnit.perThousandDeviceDays;
  IndicatorDirection _direction = IndicatorDirection.lowerIsBetter;
  DateTime _periodStart = DateTime.now().toUtc().subtract(
    const Duration(days: 30),
  );
  DateTime _periodEnd = DateTime.now().toUtc();

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _numerator.dispose();
    _denominator.dispose();
    _target.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final DateTime initial = (isStart ? _periodStart : _periodEnd).toUtc();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.utc(2000),
      lastDate: DateTime.utc(2100),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _periodStart = picked.toUtc();
        } else {
          _periodEnd = picked.toUtc();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Record indicator'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _code,
            decoration: const InputDecoration(
              labelText: 'Code (for example HAI-CLABSI)',
            ),
          ),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          DropdownButtonFormField<IndicatorCategory>(
            initialValue: _category,
            decoration: const InputDecoration(labelText: 'Category'),
            items: <DropdownMenuItem<IndicatorCategory>>[
              for (final IndicatorCategory value in IndicatorCategory.values)
                DropdownMenuItem<IndicatorCategory>(
                  value: value,
                  child: Text(value.label),
                ),
            ],
            onChanged: (IndicatorCategory? value) {
              if (value != null) setState(() => _category = value);
            },
          ),
          DropdownButtonFormField<IndicatorUnit>(
            initialValue: _unit,
            decoration: const InputDecoration(labelText: 'Unit'),
            items: <DropdownMenuItem<IndicatorUnit>>[
              for (final IndicatorUnit value in IndicatorUnit.values)
                DropdownMenuItem<IndicatorUnit>(
                  value: value,
                  child: Text(value.label),
                ),
            ],
            onChanged: (IndicatorUnit? value) {
              if (value != null) setState(() => _unit = value);
            },
          ),
          DropdownButtonFormField<IndicatorDirection>(
            initialValue: _direction,
            decoration: const InputDecoration(labelText: 'Direction'),
            items: <DropdownMenuItem<IndicatorDirection>>[
              for (final IndicatorDirection value in IndicatorDirection.values)
                DropdownMenuItem<IndicatorDirection>(
                  value: value,
                  child: Text(value.label),
                ),
            ],
            onChanged: (IndicatorDirection? value) {
              if (value != null) setState(() => _direction = value);
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_outlined),
            title: Text('From ${_formatDay(_periodStart)}'),
            trailing: TextButton(
              onPressed: () => _pickDate(isStart: true),
              child: const Text('Change'),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_available_outlined),
            title: Text('To ${_formatDay(_periodEnd)}'),
            trailing: TextButton(
              onPressed: () => _pickDate(isStart: false),
              child: const Text('Change'),
            ),
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
            controller: _target,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Target (optional)'),
          ),
          TextField(
            controller: _note,
            decoration: const InputDecoration(
              labelText: 'Where the counts came from (optional)',
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
          _IndicatorFormResult(
            code: _code.text.trim(),
            name: _name.text.trim(),
            category: _category,
            unit: _unit,
            direction: _direction,
            periodStart: _periodStart,
            periodEnd: _periodEnd,
            numerator: int.tryParse(_numerator.text.trim()) ?? 0,
            denominator: int.tryParse(_denominator.text.trim()) ?? 0,
            targetValue: int.tryParse(_target.text.trim()),
            sourceNote: _note.text.trim().isEmpty ? null : _note.text.trim(),
          ),
        ),
        child: const Text('Record'),
      ),
    ],
  );
}

String _formatMoment(DateTime value) {
  final DateTime utc = value.toUtc();
  return '${utc.year}-${utc.month.toString().padLeft(2, '0')}-'
      '${utc.day.toString().padLeft(2, '0')} '
      '${utc.hour.toString().padLeft(2, '0')}:'
      '${utc.minute.toString().padLeft(2, '0')}';
}

String _formatDay(DateTime value) {
  final DateTime utc = value.toUtc();
  return '${utc.year}-${utc.month.toString().padLeft(2, '0')}-'
      '${utc.day.toString().padLeft(2, '0')}';
}

String _formatValue(double value) => value.toStringAsFixed(1);
