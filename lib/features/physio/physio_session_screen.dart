/// Physiotherapy session detail and workflow actions (Module 20).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/physio/physio.dart';
import 'package:nodex_hms/domain/session/session_state.dart';
import 'package:nodex_hms/features/physio/physio_controller.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// Detail screen for one physiotherapy session.
class PhysioSessionScreen extends ConsumerWidget {
  /// Creates the screen.
  const PhysioSessionScreen({required this.sessionId, super.key});

  /// Local session id.
  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<PhysioSessionDetail> detail = ref.watch(
      physioSessionDetailProvider(sessionId),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Physiotherapy session')),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace _) => _PhysioError(
          error: error,
          onRetry: () => ref.invalidate(physioSessionDetailProvider(sessionId)),
        ),
        data: (PhysioSessionDetail value) => _SessionBody(value: value),
      ),
    );
  }
}

class _SessionBody extends ConsumerWidget {
  const _SessionBody({required this.value});

  final PhysioSessionDetail value;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final SessionState session = ref.watch(sessionProvider);
    final PhysioSession physio = value.session;
    final bool canSession = session.authorization.can(
      NodexPermissions.physioSessionWrite,
    );
    final bool canNote = session.authorization.can(
      NodexPermissions.physioNoteWrite,
    );
    final bool canExercise = session.authorization.can(
      NodexPermissions.physioExerciseWrite,
    );
    final bool mayNote = physio.isRunning || physio.status.isCompleted;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(physio.sessionCode, style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                _Fact(label: 'Type', value: physio.sessionType.label),
                _Fact(label: 'Body area', value: physio.bodyArea),
                _Fact(label: 'Status', value: physio.status.label),
                _Fact(
                  label: 'Scheduled',
                  value: _formatWhen(physio.scheduledAt),
                ),
                if (physio.startedAt != null)
                  _Fact(
                    label: 'Started',
                    value: _formatWhen(physio.startedAt!),
                  ),
                if (physio.completedAt != null)
                  _Fact(
                    label: 'Completed',
                    value: _formatWhen(physio.completedAt!),
                  ),
                if (physio.equipmentUsed != null)
                  _Fact(label: 'Equipment', value: physio.equipmentUsed!),
                if (physio.cancellationReason != null)
                  _Fact(label: 'Cancelled', value: physio.cancellationReason!),
              ],
            ),
          ),
        ),
        if (canSession && physio.isScheduled)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start session'),
              onPressed: () => _transition(context, ref, start: true),
            ),
          ),
        if (canSession && physio.isRunning)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Complete session'),
              onPressed: () => _transition(context, ref, start: false),
            ),
          ),
        if (canSession && !physio.isTerminal)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('Cancel session'),
              onPressed: () => _cancel(context, ref),
            ),
          ),
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            Expanded(
              child: Text('Recovery notes', style: theme.textTheme.titleMedium),
            ),
            if (canNote && mayNote)
              TextButton.icon(
                icon: const Icon(Icons.note_add_outlined),
                label: const Text('Add'),
                onPressed: () => _showNoteSheet(context, ref),
              ),
          ],
        ),
        if (value.notes.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No recovery notes yet.'),
            ),
          )
        else
          ...value.notes.map(
            (PhysioRecoveryNote note) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.healing_outlined),
                title: Text(note.content),
                subtitle: Text(
                  note.painScore == null
                      ? _formatWhen(note.recordedAt)
                      : 'Pain ${note.painScore}/10 · '
                            '${_formatWhen(note.recordedAt)}',
                ),
              ),
            ),
          ),
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'Exercise regimens',
                style: theme.textTheme.titleMedium,
              ),
            ),
            if (canExercise)
              TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Prescribe'),
                onPressed: () => _showPlanSheet(context, ref),
              ),
          ],
        ),
        if (value.plans.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No exercise regimens prescribed yet.'),
            ),
          )
        else
          ...value.plans.map(
            (PhysioExercisePlan plan) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon(
                  plan.isActive
                      ? Icons.fitness_center
                      : Icons.checkroom_outlined,
                ),
                title: Text(plan.exerciseName),
                subtitle: Text(
                  '${plan.setsCount}×${plan.repsCount} · '
                  '${plan.frequencyPerWeek}/week · '
                  '${plan.durationWeeks} weeks · ${plan.status.label}',
                ),
                trailing: canExercise && plan.isActive
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          IconButton(
                            icon: const Icon(Icons.check_circle),
                            tooltip: 'Mark completed',
                            onPressed: () => _finish(context, ref, plan, true),
                          ),
                          IconButton(
                            icon: const Icon(Icons.stop_circle_outlined),
                            tooltip: 'Stop regimen',
                            onPressed: () => _finish(context, ref, plan, false),
                          ),
                        ],
                      )
                    : null,
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _transition(
    BuildContext context,
    WidgetRef ref, {
    required bool start,
  }) async {
    final SessionState session = ref.read(sessionProvider);
    try {
      if (start) {
        await ref
            .read(startPhysioSessionUseCaseProvider)
            .call(policy: session.authorization, session: value.session);
      } else {
        await ref
            .read(completePhysioSessionUseCaseProvider)
            .call(policy: session.authorization, session: value.session);
      }
      _invalidate(ref);
    } on NodexError catch (error) {
      if (context.mounted) _snack(context, error.message);
    }
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final String? reason = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) => const _CancelSheet(),
    );
    if (reason == null) return;
    final SessionState session = ref.read(sessionProvider);
    try {
      await ref
          .read(cancelPhysioSessionUseCaseProvider)
          .call(
            policy: session.authorization,
            original: value.session,
            reason: reason,
          );
      _invalidate(ref);
    } on NodexError catch (error) {
      if (context.mounted) _snack(context, error.message);
    }
  }

  Future<void> _showNoteSheet(BuildContext context, WidgetRef ref) async {
    final _NoteDraft? draft = await showModalBottomSheet<_NoteDraft>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) => const _NoteSheet(),
    );
    if (draft == null) return;
    final SessionState session = ref.read(sessionProvider);
    final String? userId = session.user?.userId;
    if (userId == null) return;
    try {
      await ref
          .read(recordPhysioRecoveryNoteUseCaseProvider)
          .call(
            policy: session.authorization,
            session: value.session,
            recordedBy: userId,
            content: draft.content,
            painScore: draft.painScore,
          );
      _invalidate(ref);
    } on NodexError catch (error) {
      if (context.mounted) _snack(context, error.message);
    }
  }

  Future<void> _showPlanSheet(BuildContext context, WidgetRef ref) async {
    final _PlanDraft? draft = await showModalBottomSheet<_PlanDraft>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) => const _PlanSheet(),
    );
    if (draft == null) return;
    final SessionState session = ref.read(sessionProvider);
    final String? userId = session.user?.userId;
    final String? tenantId = session.tenantId;
    if (userId == null || tenantId == null) return;
    try {
      await ref
          .read(prescribePhysioExerciseUseCaseProvider)
          .call(
            policy: session.authorization,
            tenantId: tenantId,
            patientId: value.session.patientId,
            prescribedBy: userId,
            exerciseName: draft.exerciseName,
            setsCount: draft.setsCount,
            repsCount: draft.repsCount,
            frequencyPerWeek: draft.frequencyPerWeek,
            durationWeeks: draft.durationWeeks,
            sessionId: value.session.id,
            instructions: draft.instructions,
          );
      _invalidate(ref);
    } on NodexError catch (error) {
      if (context.mounted) _snack(context, error.message);
    }
  }

  Future<void> _finish(
    BuildContext context,
    WidgetRef ref,
    PhysioExercisePlan plan,
    bool completed,
  ) async {
    final SessionState session = ref.read(sessionProvider);
    try {
      await ref
          .read(finishPhysioExercisePlanUseCaseProvider)
          .call(
            policy: session.authorization,
            plan: plan,
            completed: completed,
          );
      _invalidate(ref);
    } on NodexError catch (error) {
      if (context.mounted) _snack(context, error.message);
    }
  }

  void _invalidate(WidgetRef ref) {
    final String sessionId = value.session.id;
    ref.invalidate(physioSessionDetailProvider(sessionId));
    ref.invalidate(physioSessionsForPatientProvider(value.session.patientId));
  }

  static void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  static String _formatWhen(DateTime when) {
    final DateTime local = when.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(child: Text(label)),
        Flexible(child: Text(value, textAlign: TextAlign.end)),
      ],
    ),
  );
}

class _CancelSheet extends StatefulWidget {
  const _CancelSheet();
  @override
  State<_CancelSheet> createState() => _CancelSheetState();
}

class _CancelSheetState extends State<_CancelSheet> {
  final TextEditingController _reason = TextEditingController();
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + keyboard),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text(
            'Cancel physiotherapy session',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _reason,
            decoration: const InputDecoration(
              labelText: 'Cancellation reason *',
            ),
            autofocus: true,
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              if (_reason.text.trim().isEmpty) return;
              Navigator.pop(context, _reason.text.trim());
            },
            child: const Text('Cancel session'),
          ),
        ],
      ),
    );
  }
}

class _NoteDraft {
  const _NoteDraft({required this.content, this.painScore});
  final String content;
  final int? painScore;
}

class _NoteSheet extends StatefulWidget {
  const _NoteSheet();
  @override
  State<_NoteSheet> createState() => _NoteSheetState();
}

class _NoteSheetState extends State<_NoteSheet> {
  final TextEditingController _content = TextEditingController();
  final TextEditingController _pain = TextEditingController();

  @override
  void dispose() {
    _content.dispose();
    _pain.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + keyboard),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text(
            'Record recovery note',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _content,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Note *'),
            autofocus: true,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pain,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Pain score 0-10 (optional)',
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              final String content = _content.text.trim();
              if (content.isEmpty) return;
              final String painText = _pain.text.trim();
              final int? painScore = painText.isEmpty
                  ? null
                  : int.tryParse(painText);
              if (painText.isNotEmpty && painScore == null) return;
              Navigator.pop(
                context,
                _NoteDraft(content: content, painScore: painScore),
              );
            },
            child: const Text('Save note'),
          ),
        ],
      ),
    );
  }
}

class _PlanDraft {
  const _PlanDraft({
    required this.exerciseName,
    required this.setsCount,
    required this.repsCount,
    required this.frequencyPerWeek,
    required this.durationWeeks,
    this.instructions,
  });
  final String exerciseName;
  final int setsCount;
  final int repsCount;
  final int frequencyPerWeek;
  final int durationWeeks;
  final String? instructions;
}

class _PlanSheet extends StatefulWidget {
  const _PlanSheet();
  @override
  State<_PlanSheet> createState() => _PlanSheetState();
}

class _PlanSheetState extends State<_PlanSheet> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _sets = TextEditingController(text: '3');
  final TextEditingController _reps = TextEditingController(text: '10');
  final TextEditingController _frequency = TextEditingController(text: '3');
  final TextEditingController _duration = TextEditingController(text: '6');
  final TextEditingController _instructions = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _sets.dispose();
    _reps.dispose();
    _frequency.dispose();
    _duration.dispose();
    _instructions.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + keyboard),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text(
            'Prescribe exercise regimen',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Exercise name *'),
            autofocus: true,
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _sets,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Sets *'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _reps,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Reps *'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _frequency,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Days/week *'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _duration,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Weeks *'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _instructions,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Instructions (optional)',
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              final int? sets = int.tryParse(_sets.text.trim());
              final int? reps = int.tryParse(_reps.text.trim());
              final int? frequency = int.tryParse(_frequency.text.trim());
              final int? duration = int.tryParse(_duration.text.trim());
              if (_name.text.trim().isEmpty ||
                  sets == null ||
                  reps == null ||
                  frequency == null ||
                  duration == null) {
                return;
              }
              Navigator.pop(
                context,
                _PlanDraft(
                  exerciseName: _name.text.trim(),
                  setsCount: sets,
                  repsCount: reps,
                  frequencyPerWeek: frequency,
                  durationWeeks: duration,
                  instructions: _instructions.text.trim().isEmpty
                      ? null
                      : _instructions.text.trim(),
                ),
              );
            },
            child: const Text('Prescribe regimen'),
          ),
        ],
      ),
    );
  }
}

class _PhysioError extends StatelessWidget {
  const _PhysioError({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Text(
          error is NodexError
              ? (error as NodexError).message
              : 'Physiotherapy session unavailable',
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    ),
  );
}
