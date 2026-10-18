/// Patient Feedback & Grievance Redressal (Module 36).
///
/// Two tabs: the Net Promoter Score responses and the grievances registry. The
/// headline number on the survey tab is derived from the responses on the same
/// screen, so it cannot disagree with them, and the deadline markers on the
/// grievance tab come from the moment the grievance was received and its
/// severity rather than from a stored flag.
///
/// The routing history is read where it matters: the detail sheet for a
/// grievance shows where the case went and who held it, from the append-only
/// event log rather than from a column that overwrote its own past.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/domain/feedback/feedback.dart';
import 'package:nodex_hms/domain/feedback/feedback_use_cases.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// The patient feedback and grievance board.
class FeedbackGrievanceScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const FeedbackGrievanceScreen({super.key});

  @override
  ConsumerState<FeedbackGrievanceScreen> createState() =>
      _FeedbackGrievanceScreenState();
}

class _FeedbackGrievanceScreenState
    extends ConsumerState<FeedbackGrievanceScreen> {
  FeedbackBoard? _board;
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
      final FeedbackBoard board = await ref
          .read(readFeedbackHubUseCaseProvider)
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

  Future<void> _recordSurvey() async {
    final scope = _actingScope;
    if (scope == null) return;
    final _SurveyFormResult? result = await showDialog<_SurveyFormResult>(
      context: context,
      builder: (BuildContext context) => const _SurveyFormDialog(),
    );
    if (result == null) return;
    await _run(() async {
      await ref
          .read(recordSurveyUseCaseProvider)
          .call(
            policy: ref.read(sessionProvider).authorization,
            tenantId: scope.tenantId,
            facilityId: scope.facilityId,
            surveyNumber: result.surveyNumber,
            npsScore: result.npsScore,
            recordedBy: scope.userId,
            createdBy: scope.userId,
            touchpoint: result.touchpoint,
            patientId: result.patientId,
            comment: result.comment,
          );
    });
  }

  Future<void> _followUpSurvey(FeedbackSurvey survey) async {
    final scope = _actingScope;
    if (scope == null) return;
    final String? note = await _askValue(
      title: 'Follow the detractor up',
      label: 'What was done',
      confirm: 'Record',
    );
    if (note == null) return;
    await _run(() async {
      await ref
          .read(actionSurveyUseCaseProvider)
          .call(
            policy: ref.read(sessionProvider).authorization,
            survey: survey,
            note: note,
            actionedBy: scope.userId,
          );
    });
  }

  Future<void> _voidSurvey(FeedbackSurvey survey) async {
    final String? reason = await _askValue(
      title: 'Withdraw the response',
      label: 'Reason',
      confirm: 'Withdraw',
    );
    if (reason == null) return;
    await _run(() async {
      await ref
          .read(voidSurveyUseCaseProvider)
          .call(
            policy: ref.read(sessionProvider).authorization,
            survey: survey,
            reason: reason,
          );
    });
  }

  Future<void> _logComplaint() async {
    final scope = _actingScope;
    if (scope == null) return;
    final _ComplaintFormResult? result = await showDialog<_ComplaintFormResult>(
      context: context,
      builder: (BuildContext context) => const _ComplaintFormDialog(),
    );
    if (result == null) return;
    await _run(() async {
      await ref
          .read(logComplaintUseCaseProvider)
          .call(
            policy: ref.read(sessionProvider).authorization,
            tenantId: scope.tenantId,
            facilityId: scope.facilityId,
            complaintNumber: result.complaintNumber,
            complainantName: result.complainantName,
            description: result.description,
            loggedBy: scope.userId,
            createdBy: scope.userId,
            channel: result.channel,
            category: result.category,
            severity: result.severity,
            patientId: result.patientId,
            complainantContact: result.complainantContact,
          );
    });
  }

  Future<void> _acknowledge(FeedbackComplaint complaint) async {
    await _run(() async {
      await ref
          .read(acknowledgeComplaintUseCaseProvider)
          .call(
            policy: ref.read(sessionProvider).authorization,
            complaint: complaint,
          );
    });
  }

  Future<void> _route(FeedbackComplaint complaint) async {
    final scope = _actingScope;
    if (scope == null) return;
    final Set<String> departments =
        ref.read(sessionProvider).snapshot?.departmentIds ?? const <String>{};
    final _RouteResult? result = await showDialog<_RouteResult>(
      context: context,
      builder: (BuildContext context) => _RouteDialog(departments: departments),
    );
    if (result == null) return;
    await _run(() async {
      await ref
          .read(routeComplaintUseCaseProvider)
          .call(
            policy: ref.read(sessionProvider).authorization,
            complaint: complaint,
            note: result.note,
            recordedBy: scope.userId,
            departmentId: result.departmentId,
            routedTo: result.routedTo,
          );
    });
  }

  Future<void> _escalate(FeedbackComplaint complaint) async {
    final scope = _actingScope;
    if (scope == null) return;
    final String? note = await _askValue(
      title: 'Escalate the grievance',
      label: 'Why it is being escalated',
      confirm: 'Escalate',
    );
    if (note == null) return;
    await _run(() async {
      await ref
          .read(escalateComplaintUseCaseProvider)
          .call(
            policy: ref.read(sessionProvider).authorization,
            complaint: complaint,
            note: note,
            recordedBy: scope.userId,
          );
    });
  }

  Future<void> _investigate(FeedbackComplaint complaint) async {
    await _run(() async {
      await ref
          .read(investigateComplaintUseCaseProvider)
          .call(
            policy: ref.read(sessionProvider).authorization,
            complaint: complaint,
          );
    });
  }

  Future<void> _resolve(FeedbackComplaint complaint) async {
    final scope = _actingScope;
    if (scope == null) return;
    final String? summary = await _askValue(
      title: 'Answer the grievance',
      label: 'The answer',
      confirm: 'Resolve',
    );
    if (summary == null) return;
    await _run(() async {
      await ref
          .read(resolveComplaintUseCaseProvider)
          .call(
            policy: ref.read(sessionProvider).authorization,
            complaint: complaint,
            summary: summary,
            resolvedBy: scope.userId,
          );
    });
  }

  Future<void> _close(FeedbackComplaint complaint) async {
    final String? note = await _askValue(
      title: 'Close the grievance',
      label: 'How the complainant was told',
      confirm: 'Close',
    );
    if (note == null) return;
    await _run(() async {
      await ref
          .read(closeComplaintUseCaseProvider)
          .call(
            policy: ref.read(sessionProvider).authorization,
            complaint: complaint,
            note: note,
          );
    });
  }

  Future<void> _dismiss(FeedbackComplaint complaint) async {
    final String? reason = await _askValue(
      title: 'Dismiss the grievance',
      label: 'Why it has no substance',
      confirm: 'Dismiss',
    );
    if (reason == null) return;
    await _run(() async {
      await ref
          .read(dismissComplaintUseCaseProvider)
          .call(
            policy: ref.read(sessionProvider).authorization,
            complaint: complaint,
            reason: reason,
          );
    });
  }

  Future<void> _voidComplaint(FeedbackComplaint complaint) async {
    final String? reason = await _askValue(
      title: 'Withdraw the grievance',
      label: 'Reason',
      confirm: 'Withdraw',
    );
    if (reason == null) return;
    await _run(() async {
      await ref
          .read(voidComplaintUseCaseProvider)
          .call(
            policy: ref.read(sessionProvider).authorization,
            complaint: complaint,
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

  Future<void> _showSurvey(FeedbackSurvey survey) async {
    final FeedbackBoard? board = _board;
    await showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.forum_outlined),
              title: Text('${survey.surveyNumber} · ${survey.npsScore}/10'),
              subtitle: Text(
                <String>[
                  '${survey.band.label} · ${survey.touchpoint.label}',
                  survey.status.label,
                  'Recorded ${_formatMoment(survey.recordedAt)}',
                  if (survey.isAnonymous) 'Anonymous' else survey.patientId!,
                  if (survey.comment case final String comment) comment,
                  if (board != null && board.followUpOverdue(survey))
                    'Follow-up overdue for a detractor',
                  if (survey.actionNote case final String note)
                    'Followed up: $note',
                  if (survey.voidReason case final String why)
                    'Withdrawn: $why',
                ].join('\n'),
              ),
            ),
            if (survey.status == SurveyStatus.recorded && survey.isDetractor)
              ListTile(
                leading: const Icon(Icons.support_agent_outlined),
                title: const Text('Follow the detractor up'),
                onTap: () {
                  Navigator.of(context).pop();
                  _followUpSurvey(survey);
                },
              ),
            if (!survey.isTerminal)
              ListTile(
                leading: const Icon(Icons.block_outlined),
                title: const Text('Withdraw the response'),
                onTap: () {
                  Navigator.of(context).pop();
                  _voidSurvey(survey);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showComplaint(FeedbackComplaint complaint) async {
    final session = ref.read(sessionProvider);
    final String? tenantId = session.tenantId;
    List<ComplaintRoutingEvent> events = const <ComplaintRoutingEvent>[];
    if (tenantId != null) {
      try {
        events = await ref
            .read(readFeedbackHubUseCaseProvider)
            .routingHistory(
              policy: session.authorization,
              tenantId: tenantId,
              complaintId: complaint.id,
            );
      } on Object catch (error) {
        if (!mounted) return;
        _snack(error.toString());
        return;
      }
    }
    final FeedbackBoard? board = _board;
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.report_problem_outlined),
              title: Text(
                '${complaint.complaintNumber} · ${complaint.complainantName}',
              ),
              subtitle: Text(
                <String>[
                  '${complaint.category.label} · ${complaint.severity.label} via ${complaint.channel.label}',
                  complaint.status.label,
                  'Received ${_formatMoment(complaint.receivedAt)}',
                  'Resolution window ${complaint.resolutionWindow.inDays} days',
                  if (complaint.isRouted)
                    'Routed to ${complaint.routedDepartmentId ?? 'a named owner'}',
                  if (board != null && board.acknowledgementOverdue(complaint))
                    'Acknowledgement overdue',
                  if (board != null && board.resolutionOverdue(complaint))
                    'Resolution overdue',
                  complaint.description,
                  if (complaint.resolutionSummary case final String summary)
                    'Answer: $summary',
                  if (complaint.closureNote case final String note)
                    'Closed: $note',
                  if (complaint.dismissReason case final String why)
                    'Dismissed: $why',
                  if (complaint.voidReason case final String why)
                    'Withdrawn: $why',
                ].join('\n'),
              ),
            ),
            if (complaint.status == ComplaintStatus.logged)
              ListTile(
                leading: const Icon(Icons.mark_email_read_outlined),
                title: const Text('Acknowledge the grievance'),
                onTap: () {
                  Navigator.of(context).pop();
                  _acknowledge(complaint);
                },
              ),
            if (complaint.isLive)
              ListTile(
                leading: const Icon(Icons.alt_route_outlined),
                title: const Text('Route or re-route'),
                onTap: () {
                  Navigator.of(context).pop();
                  _route(complaint);
                },
              ),
            if (complaint.isLive)
              ListTile(
                leading: const Icon(Icons.priority_high_outlined),
                title: const Text('Escalate on the record'),
                onTap: () {
                  Navigator.of(context).pop();
                  _escalate(complaint);
                },
              ),
            if (complaint.status == ComplaintStatus.acknowledged)
              ListTile(
                leading: const Icon(Icons.search_outlined),
                title: const Text('Open the investigation'),
                onTap: () {
                  Navigator.of(context).pop();
                  _investigate(complaint);
                },
              ),
            if (complaint.status == ComplaintStatus.investigating)
              ListTile(
                leading: const Icon(Icons.task_alt_outlined),
                title: const Text('Answer the grievance'),
                onTap: () {
                  Navigator.of(context).pop();
                  _resolve(complaint);
                },
              ),
            if (complaint.status == ComplaintStatus.resolved)
              ListTile(
                leading: const Icon(Icons.done_all_outlined),
                title: const Text('Close the grievance'),
                onTap: () {
                  Navigator.of(context).pop();
                  _close(complaint);
                },
              ),
            if (complaint.isLive)
              ListTile(
                leading: const Icon(Icons.block_outlined),
                title: Text(
                  complaint.status == ComplaintStatus.logged
                      ? 'Withdraw the grievance'
                      : 'Dismiss the grievance',
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  if (complaint.status == ComplaintStatus.logged) {
                    _voidComplaint(complaint);
                  } else {
                    _dismiss(complaint);
                  }
                },
              ),
            for (final ComplaintRoutingEvent event in events)
              ListTile(
                dense: true,
                leading: const Icon(Icons.history_outlined),
                title: Text('${event.eventType.label} · ${event.note}'),
                subtitle: Text(_formatMoment(event.occurredAt)),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final FeedbackBoard? board = _board;
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null || board == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Feedback')),
        body: Center(
          child: Text(_error ?? 'The feedback board is unavailable.'),
        ),
      );
    }
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Feedback & grievances'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: <Widget>[
              Tab(text: 'Surveys'),
              Tab(text: 'Grievances'),
            ],
          ),
        ),
        body: TabBarView(
          children: <Widget>[_surveyTab(board), _complaintTab(board)],
        ),
      ),
    );
  }

  Widget _surveyTab(FeedbackBoard board) {
    final Map<NpsBand, int> counts = board.bandCounts;
    final double? nps = board.nps;
    return Stack(
      children: <Widget>[
        Column(
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.insights_outlined),
              title: Text(
                nps == null
                    ? 'No responses yet'
                    : 'NPS ${nps.toStringAsFixed(0)}',
              ),
              subtitle: Text(
                '${counts[NpsBand.promoter]} promoters · '
                '${counts[NpsBand.passive]} passive · '
                '${counts[NpsBand.detractor]} detractors',
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: board.surveys.isEmpty
                  ? const Center(
                      child: Text('No survey responses on this device.'),
                    )
                  : ListView.builder(
                      itemCount: board.surveys.length,
                      itemBuilder: (BuildContext context, int index) {
                        final FeedbackSurvey survey = board.surveys[index];
                        final bool overdue = board.followUpOverdue(survey);
                        return ListTile(
                          leading: Icon(
                            overdue
                                ? Icons.error_outline
                                : survey.band == NpsBand.detractor
                                ? Icons.sentiment_dissatisfied_outlined
                                : Icons.sentiment_satisfied_outlined,
                            color: overdue
                                ? Theme.of(context).colorScheme.error
                                : null,
                          ),
                          title: Text(
                            '${survey.npsScore}/10 · ${survey.touchpoint.label}',
                          ),
                          subtitle: Text(
                            <String>[
                              survey.surveyNumber,
                              survey.band.label,
                              survey.status.label,
                              if (overdue) 'Follow-up overdue',
                            ].join(' · '),
                          ),
                          onTap: () => _showSurvey(survey),
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
            onPressed: _recordSurvey,
            icon: const Icon(Icons.add),
            label: const Text('Record response'),
          ),
        ),
      ],
    );
  }

  Widget _complaintTab(FeedbackBoard board) {
    return Stack(
      children: <Widget>[
        if (board.complaints.isEmpty)
          const Center(child: Text('No grievances on this device.'))
        else
          ListView.builder(
            itemCount: board.complaints.length,
            itemBuilder: (BuildContext context, int index) {
              final FeedbackComplaint complaint = board.complaints[index];
              final bool breached = board.slaBreached(complaint);
              return ListTile(
                leading: Icon(
                  breached
                      ? Icons.error_outline
                      : Icons.report_problem_outlined,
                  color: breached ? Theme.of(context).colorScheme.error : null,
                ),
                title: Text(
                  '${complaint.complaintNumber} · ${complaint.complainantName}',
                ),
                subtitle: Text(
                  <String>[
                    complaint.category.label,
                    complaint.severity.label,
                    complaint.status.label,
                    if (board.acknowledgementOverdue(complaint))
                      'Acknowledgement overdue'
                    else if (board.resolutionOverdue(complaint))
                      'Resolution overdue',
                  ].join(' · '),
                ),
                onTap: () => _showComplaint(complaint),
              );
            },
          ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            onPressed: _logComplaint,
            icon: const Icon(Icons.add),
            label: const Text('Log grievance'),
          ),
        ),
      ],
    );
  }
}

class _SurveyFormResult {
  const _SurveyFormResult({
    required this.surveyNumber,
    required this.touchpoint,
    required this.npsScore,
    this.comment,
    this.patientId,
  });

  final String surveyNumber;
  final FeedbackTouchpoint touchpoint;
  final int npsScore;
  final String? comment;
  final String? patientId;
}

class _SurveyFormDialog extends StatefulWidget {
  const _SurveyFormDialog();

  @override
  State<_SurveyFormDialog> createState() => _SurveyFormDialogState();
}

class _SurveyFormDialogState extends State<_SurveyFormDialog> {
  final TextEditingController _number = TextEditingController();
  final TextEditingController _patient = TextEditingController();
  final TextEditingController _comment = TextEditingController();
  FeedbackTouchpoint _touchpoint = FeedbackTouchpoint.opd;
  int _score = 9;

  @override
  void dispose() {
    _number.dispose();
    _patient.dispose();
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Record response'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _number,
            decoration: const InputDecoration(labelText: 'Survey number'),
          ),
          DropdownButtonFormField<FeedbackTouchpoint>(
            initialValue: _touchpoint,
            decoration: const InputDecoration(labelText: 'Touchpoint'),
            items: <DropdownMenuItem<FeedbackTouchpoint>>[
              for (final FeedbackTouchpoint value in FeedbackTouchpoint.values)
                DropdownMenuItem<FeedbackTouchpoint>(
                  value: value,
                  child: Text(value.label),
                ),
            ],
            onChanged: (FeedbackTouchpoint? value) {
              if (value != null) setState(() => _touchpoint = value);
            },
          ),
          DropdownButtonFormField<int>(
            initialValue: _score,
            decoration: const InputDecoration(
              labelText: 'How likely to recommend (0-10)',
            ),
            items: <DropdownMenuItem<int>>[
              for (int value = 0; value <= 10; value++)
                DropdownMenuItem<int>(
                  value: value,
                  child: Text('$value · ${npsBand(value).label}'),
                ),
            ],
            onChanged: (int? value) {
              if (value != null) setState(() => _score = value);
            },
          ),
          TextField(
            controller: _patient,
            decoration: const InputDecoration(
              labelText: 'Patient id (leave blank to stay anonymous)',
            ),
          ),
          TextField(
            controller: _comment,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'What the patient said (optional)',
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
          _SurveyFormResult(
            surveyNumber: _number.text.trim(),
            touchpoint: _touchpoint,
            npsScore: _score,
            comment: _nullIfEmpty(_comment),
            patientId: _nullIfEmpty(_patient),
          ),
        ),
        child: const Text('Record'),
      ),
    ],
  );

  String? _nullIfEmpty(TextEditingController controller) {
    final String value = controller.text.trim();
    return value.isEmpty ? null : value;
  }
}

class _ComplaintFormResult {
  const _ComplaintFormResult({
    required this.complaintNumber,
    required this.complainantName,
    required this.description,
    required this.channel,
    required this.category,
    required this.severity,
    this.patientId,
    this.complainantContact,
  });

  final String complaintNumber;
  final String complainantName;
  final String description;
  final ComplaintChannel channel;
  final ComplaintCategory category;
  final ComplaintSeverity severity;
  final String? patientId;
  final String? complainantContact;
}

class _ComplaintFormDialog extends StatefulWidget {
  const _ComplaintFormDialog();

  @override
  State<_ComplaintFormDialog> createState() => _ComplaintFormDialogState();
}

class _ComplaintFormDialogState extends State<_ComplaintFormDialog> {
  final TextEditingController _number = TextEditingController();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _contact = TextEditingController();
  final TextEditingController _patient = TextEditingController();
  final TextEditingController _description = TextEditingController();
  ComplaintChannel _channel = ComplaintChannel.counter;
  ComplaintCategory _category = ComplaintCategory.other;
  ComplaintSeverity _severity = ComplaintSeverity.medium;

  @override
  void dispose() {
    _number.dispose();
    _name.dispose();
    _contact.dispose();
    _patient.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Log grievance'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _number,
            decoration: const InputDecoration(labelText: 'Complaint number'),
          ),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Who complained'),
          ),
          TextField(
            controller: _contact,
            decoration: const InputDecoration(
              labelText: 'How to reach them (optional)',
            ),
          ),
          TextField(
            controller: _patient,
            decoration: const InputDecoration(
              labelText: 'Patient id (optional)',
            ),
          ),
          DropdownButtonFormField<ComplaintChannel>(
            initialValue: _channel,
            decoration: const InputDecoration(labelText: 'How it arrived'),
            items: <DropdownMenuItem<ComplaintChannel>>[
              for (final ComplaintChannel value in ComplaintChannel.values)
                DropdownMenuItem<ComplaintChannel>(
                  value: value,
                  child: Text(value.label),
                ),
            ],
            onChanged: (ComplaintChannel? value) {
              if (value != null) setState(() => _channel = value);
            },
          ),
          DropdownButtonFormField<ComplaintCategory>(
            initialValue: _category,
            decoration: const InputDecoration(labelText: 'What it is about'),
            items: <DropdownMenuItem<ComplaintCategory>>[
              for (final ComplaintCategory value in ComplaintCategory.values)
                DropdownMenuItem<ComplaintCategory>(
                  value: value,
                  child: Text(value.label),
                ),
            ],
            onChanged: (ComplaintCategory? value) {
              if (value != null) setState(() => _category = value);
            },
          ),
          DropdownButtonFormField<ComplaintSeverity>(
            initialValue: _severity,
            decoration: const InputDecoration(
              labelText: 'Severity (which sets the deadline)',
            ),
            items: <DropdownMenuItem<ComplaintSeverity>>[
              for (final ComplaintSeverity value in ComplaintSeverity.values)
                DropdownMenuItem<ComplaintSeverity>(
                  value: value,
                  child: Text(
                    '${value.label} · ${complaintResolutionWindow(value).inDays} days',
                  ),
                ),
            ],
            onChanged: (ComplaintSeverity? value) {
              if (value != null) setState(() => _severity = value);
            },
          ),
          TextField(
            controller: _description,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'The grievance'),
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
          _ComplaintFormResult(
            complaintNumber: _number.text.trim(),
            complainantName: _name.text.trim(),
            description: _description.text.trim(),
            channel: _channel,
            category: _category,
            severity: _severity,
            patientId: _nullIfEmpty(_patient),
            complainantContact: _nullIfEmpty(_contact),
          ),
        ),
        child: const Text('Log'),
      ),
    ],
  );

  String? _nullIfEmpty(TextEditingController controller) {
    final String value = controller.text.trim();
    return value.isEmpty ? null : value;
  }
}

class _RouteResult {
  const _RouteResult({required this.note, this.departmentId, this.routedTo});

  final String note;
  final String? departmentId;
  final String? routedTo;
}

class _RouteDialog extends StatefulWidget {
  const _RouteDialog({required this.departments});

  /// The departments the acting user may route into.
  final Set<String> departments;

  @override
  State<_RouteDialog> createState() => _RouteDialogState();
}

class _RouteDialogState extends State<_RouteDialog> {
  final TextEditingController _owner = TextEditingController();
  final TextEditingController _note = TextEditingController();
  String? _department;

  @override
  void initState() {
    super.initState();
    _department = widget.departments.isEmpty ? null : widget.departments.first;
  }

  @override
  void dispose() {
    _owner.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Route the grievance'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (widget.departments.isNotEmpty)
            DropdownButtonFormField<String>(
              initialValue: _department,
              decoration: const InputDecoration(labelText: 'Department'),
              items: <DropdownMenuItem<String>>[
                for (final String department in widget.departments)
                  DropdownMenuItem<String>(
                    value: department,
                    child: Text(department),
                  ),
              ],
              onChanged: (String? value) {
                if (value != null) setState(() => _department = value);
              },
            ),
          TextField(
            controller: _owner,
            decoration: const InputDecoration(
              labelText: 'Owner user id (optional)',
            ),
          ),
          TextField(
            controller: _note,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Why it is going there',
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
          _RouteResult(
            note: _note.text.trim(),
            departmentId: _department,
            routedTo: _owner.text.trim().isEmpty ? null : _owner.text.trim(),
          ),
        ),
        child: const Text('Route'),
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
