/// Problem-list and scribe-draft panels for the encounter editor (Module 16).
///
/// Two surfaces, both deliberately cautious. A dictation is shown section by
/// section so a clinician accepts exactly what they want, and the transcript is
/// always visible next to the machine text it produced. Acceptance requires the
/// AI review permission, which is a different decision from writing the note,
/// and nothing here can push text into a signed encounter.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/encounters/encounter.dart';
import 'package:nodex_hms/domain/encounters/problem_list.dart';
import 'package:nodex_hms/domain/session/session_state.dart';
import 'package:nodex_hms/features/encounters/encounters_controller.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// The patient's problem list, with recording and resolution.
class ProblemListPanel extends ConsumerWidget {
  const ProblemListPanel({
    required this.patientId,
    required this.encounterId,
    required this.editable,
    super.key,
  });

  /// Patient whose list is shown.
  final String patientId;

  /// Encounter a newly recorded problem is attributed to.
  final String encounterId;

  /// Whether the encounter still accepts new clinical content.
  final bool editable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final SessionState session = ref.watch(sessionProvider);
    final bool canWrite = session.authorization.can(
      NodexPermissions.encounterWrite,
    );
    final AsyncValue<List<ClinicalProblem>> problems = ref.watch(
      problemsForPatientProvider(patientId),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text('Problem list', style: theme.textTheme.titleMedium),
            ),
            if (canWrite && editable)
              TextButton.icon(
                icon: const Icon(Icons.add_outlined),
                label: const Text('Add'),
                onPressed: () => _recordProblem(context, ref, session),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Problems outlive this encounter. Closing one records when it '
          'resolved and by whom; it is never deleted.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        problems.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object error, StackTrace _) => Text(
            'Problem list unavailable: $error',
            style: theme.textTheme.bodySmall,
          ),
          data: (List<ClinicalProblem> items) => items.isEmpty
              ? Text('No problems recorded.', style: theme.textTheme.bodySmall)
              : Column(
                  children: items
                      .map(
                        (ClinicalProblem problem) => _ProblemTile(
                          problem: problem,
                          canResolve: canWrite && editable,
                          onResolve: () =>
                              _resolveProblem(context, ref, session, problem),
                        ),
                      )
                      .toList(growable: false),
                ),
        ),
      ],
    );
  }

  Future<void> _recordProblem(
    BuildContext context,
    WidgetRef ref,
    SessionState session,
  ) async {
    final _ProblemDraft? draft = await showModalBottomSheet<_ProblemDraft>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) => const _ProblemSheet(),
    );
    if (draft == null) return;
    final String? userId = session.user?.userId;
    final String? tenantId = session.tenantId;
    if (userId == null || tenantId == null) return;

    try {
      await ref
          .read(recordProblemUseCaseProvider)
          .call(
            policy: session.authorization,
            tenantId: tenantId,
            patientId: patientId,
            encounterId: encounterId,
            problemCode: draft.code,
            description: draft.description,
            recordedBy: userId,
          );
      ref.invalidate(problemsForPatientProvider(patientId));
      ref.invalidate(activeProblemsProvider(patientId));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Problem added to the list.')),
        );
      }
    } on NodexError catch (error) {
      if (context.mounted) _showError(context, error.message);
    }
  }

  Future<void> _resolveProblem(
    BuildContext context,
    WidgetRef ref,
    SessionState session,
    ClinicalProblem problem,
  ) async {
    final String? note = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => const _ResolutionDialog(),
    );
    if (note == null || note.trim().isEmpty) return;
    final String? userId = session.user?.userId;
    if (userId == null) return;

    try {
      await ref
          .read(resolveProblemUseCaseProvider)
          .call(
            policy: session.authorization,
            problem: problem,
            resolvedBy: userId,
            resolutionNote: note,
          );
      ref.invalidate(problemsForPatientProvider(patientId));
      ref.invalidate(activeProblemsProvider(patientId));
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Problem resolved.')));
      }
    } on NodexError catch (error) {
      if (context.mounted) _showError(context, error.message);
    }
  }
}

class _ProblemTile extends StatelessWidget {
  const _ProblemTile({
    required this.problem,
    required this.canResolve,
    required this.onResolve,
  });

  final ClinicalProblem problem;
  final bool canResolve;
  final VoidCallback onResolve;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool active = problem.isActive;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          active ? Icons.monitor_heart_outlined : Icons.check_circle_outline,
          color: active ? null : theme.disabledColor,
        ),
        title: Text(
          '${problem.problemCode} · ${problem.description}',
          style: active
              ? null
              : const TextStyle(decoration: TextDecoration.lineThrough),
        ),
        subtitle: Text(
          active
              ? 'Active'
              : 'Resolved${problem.resolutionNote == null ? '' : ' · ${problem.resolutionNote}'}',
        ),
        trailing: active && canResolve
            ? TextButton(onPressed: onResolve, child: const Text('Resolve'))
            : null,
      ),
    );
  }
}

class _ProblemDraft {
  const _ProblemDraft({required this.code, required this.description});

  final String code;
  final String description;
}

class _ProblemSheet extends StatefulWidget {
  const _ProblemSheet();

  @override
  State<_ProblemSheet> createState() => _ProblemSheetState();
}

class _ProblemSheetState extends State<_ProblemSheet> {
  final TextEditingController _code = TextEditingController();
  final TextEditingController _description = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        // Lift the sheet above the keyboard so the action stays reachable.
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text('Add problem', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(
            controller: _code,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Problem code *',
              helperText: 'Coded term, e.g. E11.9 or I10',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _description,
            decoration: const InputDecoration(labelText: 'Description *'),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              final String code = _code.text.trim();
              final String description = _description.text.trim();
              if (code.isEmpty || description.isEmpty) return;
              Navigator.pop(
                context,
                _ProblemDraft(code: code, description: description),
              );
            },
            child: const Text('Add to problem list'),
          ),
        ],
      ),
    );
  }
}

class _ResolutionDialog extends StatefulWidget {
  const _ResolutionDialog();

  @override
  State<_ResolutionDialog> createState() => _ResolutionDialogState();
}

class _ResolutionDialogState extends State<_ResolutionDialog> {
  final TextEditingController _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Resolve problem'),
      content: TextField(
        controller: _note,
        autofocus: true,
        maxLines: 3,
        decoration: const InputDecoration(
          labelText: 'How did it resolve? *',
          helperText: 'Recorded permanently against this problem.',
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _note.text),
          child: const Text('Resolve'),
        ),
      ],
    );
  }
}

/// Pending dictations for one encounter, each reviewable section by section.
class ScribeDraftPanel extends ConsumerWidget {
  const ScribeDraftPanel({required this.encounter, super.key});

  /// The encounter the dictations target.
  final ClinicalEncounter encounter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final SessionState session = ref.watch(sessionProvider);
    final bool canReview = session.authorization.can(
      NodexPermissions.aiOutputReview,
    );
    final AsyncValue<List<ScribeDraft>> drafts = ref.watch(
      scribeDraftsForEncounterProvider(encounter.id),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Dictations', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          canReview
              ? 'Machine output, never the record. Accept only the sections '
                    'you agree with; the rest is discarded.'
              : 'Machine output awaiting review. Accepting it is an AI review '
                    'decision, which your role does not hold.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        drafts.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object error, StackTrace _) => Text(
            'Dictations unavailable: $error',
            style: theme.textTheme.bodySmall,
          ),
          data: (List<ScribeDraft> items) => items.isEmpty
              ? Text('No dictations.', style: theme.textTheme.bodySmall)
              : Column(
                  children: items
                      .map(
                        (ScribeDraft draft) => _DraftCard(
                          draft: draft,
                          canReview:
                              canReview &&
                              draft.isPendingReview &&
                              encounter.isEditable,
                          encounter: encounter,
                        ),
                      )
                      .toList(growable: false),
                ),
        ),
      ],
    );
  }
}

class _DraftCard extends ConsumerWidget {
  const _DraftCard({
    required this.draft,
    required this.canReview,
    required this.encounter,
  });

  final ScribeDraft draft;
  final bool canReview;
  final ClinicalEncounter encounter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: Icon(
          draft.status == ScribeDraftStatus.pendingReview
              ? Icons.mic_none_outlined
              : draft.status == ScribeDraftStatus.accepted
              ? Icons.task_alt_outlined
              : Icons.block_outlined,
        ),
        title: Text(draft.modelId),
        subtitle: Text(
          '${draft.safetyDecision} · ${draft.status.label}'
          '${draft.confidence == null ? '' : ' · ${(draft.confidence! * 100).round()}%'}',
          style: theme.textTheme.bodySmall,
        ),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Transcript', style: theme.textTheme.labelLarge),
                const SizedBox(height: 4),
                Text(draft.transcriptText),
                const Divider(height: 24),
                for (final ScribeSection section in ScribeSection.values)
                  _DraftSection(
                    section: section,
                    text: draft.sectionText(section),
                    accepted: draft.acceptedSections.contains(section),
                  ),
                if (draft.rejectionReason != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Rejected: ${draft.rejectionReason}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                if (canReview)
                  Row(
                    children: <Widget>[
                      TextButton(
                        onPressed: () => _reject(context, ref),
                        child: const Text('Reject all'),
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        icon: const Icon(Icons.check_outlined),
                        label: const Text('Review and accept'),
                        onPressed: () => _review(context, ref),
                      ),
                    ],
                  )
                else if (draft.isPendingReview && encounter.isSigned)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'This encounter is signed, so dictation text can no '
                      'longer be added to it.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _review(BuildContext context, WidgetRef ref) async {
    final Map<ScribeSection, String>? accepted =
        await showModalBottomSheet<Map<ScribeSection, String>>(
          context: context,
          isScrollControlled: true,
          builder: (BuildContext context) => _ReviewSheet(draft: draft),
        );
    if (accepted == null || accepted.isEmpty || !context.mounted) return;

    final SessionState session = ref.read(sessionProvider);
    final String? reviewerId = session.user?.userId;
    if (reviewerId == null) return;
    try {
      await ref
          .read(reviewScribeDraftUseCaseProvider)
          .call(
            policy: session.authorization,
            draft: draft,
            reviewedBy: reviewerId,
            acceptedText: accepted,
          );
      ref.invalidate(scribeDraftsForEncounterProvider(encounter.id));
      ref.invalidate(encounterDetailProvider(encounter.id));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Accepted ${accepted.length} section(s) into the note.',
            ),
          ),
        );
      }
    } on NodexError catch (error) {
      if (context.mounted) _showError(context, error.message);
    }
  }

  Future<void> _reject(BuildContext context, WidgetRef ref) async {
    final String? reason = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => const _RejectionDialog(),
    );
    if (reason == null || reason.trim().isEmpty || !context.mounted) return;

    final SessionState session = ref.read(sessionProvider);
    final String? reviewerId = session.user?.userId;
    if (reviewerId == null) return;
    try {
      await ref
          .read(reviewScribeDraftUseCaseProvider)
          .call(
            policy: session.authorization,
            draft: draft,
            reviewedBy: reviewerId,
            rejectionReason: reason,
          );
      ref.invalidate(scribeDraftsForEncounterProvider(encounter.id));
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Dictation rejected.')));
      }
    } on NodexError catch (error) {
      if (context.mounted) _showError(context, error.message);
    }
  }
}

class _DraftSection extends StatelessWidget {
  const _DraftSection({
    required this.section,
    required this.text,
    required this.accepted,
  });

  final ScribeSection section;
  final String? text;
  final bool accepted;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    if (text == null || text!.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(section.label, style: theme.textTheme.labelLarge),
              if (accepted)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Icon(
                    Icons.verified_outlined,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                ),
            ],
          ),
          Text(text!),
        ],
      ),
    );
  }
}

class _ReviewSheet extends StatefulWidget {
  const _ReviewSheet({required this.draft});

  final ScribeDraft draft;

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  late final Map<ScribeSection, TextEditingController> _controllers =
      <ScribeSection, TextEditingController>{
        for (final ScribeSection section in ScribeSection.values)
          if (widget.draft.sectionText(section) != null)
            section: TextEditingController(
              text: widget.draft.sectionText(section),
            ),
      };
  final Set<ScribeSection> _accepted = <ScribeSection>{};

  @override
  void dispose() {
    for (final TextEditingController controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      builder: (BuildContext context, ScrollController controller) => ListView(
        controller: controller,
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        children: <Widget>[
          Text('Review dictation', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Edit anything you disagree with, then accept the sections that '
            'are ready. Unaccepted sections are discarded.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Text('Transcript', style: theme.textTheme.labelLarge),
          Text(widget.draft.transcriptText),
          const Divider(height: 24),
          for (final ScribeSection section in _controllers.keys)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(section.label, style: theme.textTheme.labelLarge),
                subtitle: TextField(
                  controller: _controllers[section],
                  maxLines: 3,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                value: _accepted.contains(section),
                onChanged: (bool? checked) => setState(() {
                  if (checked ?? false) {
                    _accepted.add(section);
                  } else {
                    _accepted.remove(section);
                  }
                }),
              ),
            ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _accepted.isEmpty
                ? null
                : () {
                    final Map<ScribeSection, String> accepted =
                        <ScribeSection, String>{
                          for (final ScribeSection section in _accepted)
                            section: _controllers[section]!.text.trim(),
                        };
                    if (accepted.values.any((String text) => text.isEmpty)) {
                      return;
                    }
                    Navigator.pop(context, accepted);
                  },
            child: Text('Accept ${_accepted.length} section(s)'),
          ),
        ],
      ),
    );
  }
}

class _RejectionDialog extends StatefulWidget {
  const _RejectionDialog();

  @override
  State<_RejectionDialog> createState() => _RejectionDialogState();
}

class _RejectionDialogState extends State<_RejectionDialog> {
  final TextEditingController _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reject dictation'),
      content: TextField(
        controller: _reason,
        autofocus: true,
        maxLines: 3,
        decoration: const InputDecoration(
          labelText: 'Reason *',
          helperText: 'Recorded permanently against this dictation.',
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _reason.text),
          child: const Text('Reject'),
        ),
      ],
    );
  }
}

void _showError(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
