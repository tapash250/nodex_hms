/// Cross-department task board (Module 41).
///
/// The board is read top-down: unclaimed STAT errands first, then whatever the
/// signed-in user owns, then the rest of the live work, then the closed record.
/// Overdue work is marked from the row and the clock rather than stored as a
/// flag, because a task does not become late in a database — it becomes late
/// when somebody looks at it after its time.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodex_hms/app/adaptive/adaptive_breaks.dart';
import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/tasks/hospital_task.dart';
import 'package:nodex_hms/domain/tasks/task_use_cases.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// The hospital task board.
class TaskBoardScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const TaskBoardScreen({super.key});

  @override
  ConsumerState<TaskBoardScreen> createState() => _TaskBoardScreenState();
}

/// Which slice of the board is on screen.
enum _BoardFilter {
  /// Work nobody owns.
  unclaimed('Unclaimed'),

  /// Work the signed-in user owns.
  mine('Mine'),

  /// Every live task.
  live('All live'),

  /// The closed record.
  closed('Closed');

  const _BoardFilter(this.label);

  /// Chip label.
  final String label;
}

class _TaskBoardScreenState extends ConsumerState<TaskBoardScreen> {
  TaskBoard? _board;
  bool _loading = true;
  String? _error;
  _BoardFilter _filter = _BoardFilter.unclaimed;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final TaskBoard board = await ref
          .read(readTaskBoardUseCaseProvider)
          .call(policy: ref.read(sessionProvider).authorization);
      if (!mounted) return;
      setState(() {
        _board = board;
        _loading = false;
        _error = null;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is NodexError ? error.message : error.toString();
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
      _snack(error is NodexError ? error.message : error.toString());
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String? get _userId => ref.read(sessionProvider).user?.userId;

  bool get _canManage =>
      ref.read(sessionProvider).authorization.can(NodexPermissions.tasksManage);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TaskBoard? board = _board;
    final String? userId = _userId;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Task board'),
        actions: <Widget>[
          if (_canManage)
            IconButton(
              icon: const Icon(Icons.add_task),
              tooltip: 'Raise a task',
              onPressed: _raiseTask,
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? _BoardError(message: _error!, onRetry: _load)
            : board == null || userId == null
            ? const Center(child: Text('Session is not ready.'))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: <Widget>[
                  Wrap(
                    spacing: 8,
                    children: _BoardFilter.values
                        .map(
                          (_BoardFilter filter) => ChoiceChip(
                            label: Text(
                              filter == _BoardFilter.unclaimed
                                  ? '${filter.label} (${board.unclaimed.length})'
                                  : filter == _BoardFilter.mine
                                  ? '${filter.label} (${board.claimedBy(userId).length})'
                                  : filter.label,
                            ),
                            selected: _filter == filter,
                            onSelected: (bool _) =>
                                setState(() => _filter = filter),
                          ),
                        )
                        .toList(growable: false),
                  ),
                  const SizedBox(height: 12),
                  _summary(theme, board, userId),
                  const SizedBox(height: 12),
                  ..._visibleTasks(board, userId).map(
                    (HospitalTask task) => _TaskCard(
                      task: task,
                      canManage: _canManage,
                      isMine: task.assignedTo == userId,
                      onClaim: () => _run(
                        () => ref
                            .read(claimTaskUseCaseProvider)
                            .call(
                              policy: ref.read(sessionProvider).authorization,
                              task: task,
                              user: userId,
                            ),
                      ),
                      onStart: () => _run(
                        () => ref
                            .read(startTaskUseCaseProvider)
                            .call(
                              policy: ref.read(sessionProvider).authorization,
                              task: task,
                              user: userId,
                            ),
                      ),
                      onComplete: () => _completeTask(task),
                      onCancel: () => _cancelTask(task),
                      onEscalate: () => _reprioritise(task),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _summary(ThemeData theme, TaskBoard board, String userId) {
    final List<HospitalTask> overdue = board.overdueAt(DateTime.now());
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Live work', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '${board.live.length} live · ${board.unclaimed.length} unclaimed · '
              '${board.claimedBy(userId).length} yours · '
              '${overdue.length} overdue',
            ),
            if (overdue.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                'Most overdue: ${overdue.first.title} '
                '(${overdue.first.taskCode})',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<HospitalTask> _visibleTasks(TaskBoard board, String userId) =>
      switch (_filter) {
        _BoardFilter.unclaimed => board.unclaimed,
        _BoardFilter.mine =>
          board
              .claimedBy(userId)
              .followedBy(
                board.closed.where((HospitalTask t) => t.completedBy == userId),
              )
              .toList(growable: false),
        _BoardFilter.live => board.live,
        _BoardFilter.closed => board.closed,
      };

  Future<void> _raiseTask() async {
    final session = ref.read(sessionProvider);
    final String? tenantId = session.tenantId;
    final String? userId = session.user?.userId;
    if (tenantId == null || userId == null) return;
    final _RaiseResult? result = await showDialog<_RaiseResult>(
      context: context,
      builder: (BuildContext context) => const _RaiseDialog(),
    );
    if (result == null) return;
    await _run(() async {
      await ref
          .read(raiseTaskUseCaseProvider)
          .call(
            policy: session.authorization,
            tenantId: tenantId,
            taskCode: result.taskCode,
            title: result.title,
            requestedBy: userId,
            category: result.category,
            priority: result.priority,
            detail: result.detail,
            fromLocation: result.fromLocation,
            toLocation: result.toLocation,
          );
    });
  }

  Future<void> _completeTask(HospitalTask task) async {
    final String? userId = _userId;
    if (userId == null) return;
    final String? note = await _askValue(
      context: context,
      title: 'Complete ${task.taskCode}',
      label: 'What was done',
      confirm: 'Complete',
    );
    if (note == null) return;
    await _run(
      () => ref
          .read(completeTaskUseCaseProvider)
          .call(
            policy: ref.read(sessionProvider).authorization,
            task: task,
            user: userId,
            note: note,
          ),
    );
  }

  Future<void> _cancelTask(HospitalTask task) async {
    final String? reason = await _askValue(
      context: context,
      title: 'Cancel ${task.taskCode}',
      label: 'Reason',
      confirm: 'Cancel task',
    );
    if (reason == null) return;
    await _run(
      () => ref
          .read(cancelTaskUseCaseProvider)
          .call(
            policy: ref.read(sessionProvider).authorization,
            task: task,
            reason: reason,
          ),
    );
  }

  Future<void> _reprioritise(HospitalTask task) async {
    final TaskPriority? raised = await showDialog<TaskPriority>(
      context: context,
      builder: (BuildContext context) => SimpleDialog(
        title: const Text('Raise the priority'),
        children: TaskPriority.values
            .where((TaskPriority p) => p.weight > task.priority.weight)
            .map(
              (TaskPriority p) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, p),
                child: Text(p.label),
              ),
            )
            .toList(growable: false),
      ),
    );
    if (raised == null) return;
    await _run(
      () => ref
          .read(reprioritiseTaskUseCaseProvider)
          .call(
            policy: ref.read(sessionProvider).authorization,
            task: task,
            priority: raised,
          ),
    );
    if (mounted) {
      _snack('${task.taskCode} is now ${raised.label.toLowerCase()}.');
    }
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.task,
    required this.canManage,
    required this.isMine,
    required this.onClaim,
    required this.onStart,
    required this.onComplete,
    required this.onCancel,
    required this.onEscalate,
  });

  /// A task is closed at a bedside, often with gloves on, so every action on
  /// it is a full 48dp target rather than the 40dp a text button defaults to.
  static final ButtonStyle _gloveStyle = TextButton.styleFrom(
    minimumSize: const Size(48, nodexMinTouchTarget),
  );

  final HospitalTask task;
  final bool canManage;
  final bool isMine;
  final VoidCallback onClaim;
  final VoidCallback onStart;
  final VoidCallback onComplete;
  final VoidCallback onCancel;
  final VoidCallback onEscalate;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool overdue = task.isOverdueAt(DateTime.now());
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '${task.taskCode} · ${task.title}',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                _PriorityChip(priority: task.priority),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              <String>[
                task.category.label,
                task.status.label,
                if (task.fromLocation != null || task.toLocation != null)
                  '${task.fromLocation ?? '?'} → ${task.toLocation ?? '?'}',
                if (task.dueAt != null)
                  'due ${task.dueAt!.toLocal().toIso8601String()}${overdue ? ' (overdue)' : ''}',
              ].join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: overdue ? theme.colorScheme.error : null,
              ),
            ),
            if (task.detail != null) ...<Widget>[
              const SizedBox(height: 4),
              Text(task.detail!),
            ],
            if (task.completionNote != null) ...<Widget>[
              const SizedBox(height: 4),
              Text('Done: ${task.completionNote}'),
            ],
            if (task.cancellationReason != null) ...<Widget>[
              const SizedBox(height: 4),
              Text('Cancelled: ${task.cancellationReason}'),
            ],
            if (canManage) ...<Widget>[
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                children: <Widget>[
                  if (task.status == TaskStatus.open)
                    TextButton(
                      onPressed: onClaim,
                      style: _gloveStyle,
                      child: const Text('Claim'),
                    ),
                  if (task.status == TaskStatus.claimed && isMine)
                    TextButton(
                      onPressed: onStart,
                      style: _gloveStyle,
                      child: const Text('Start'),
                    ),
                  if ((task.status == TaskStatus.claimed ||
                          task.status == TaskStatus.inProgress) &&
                      isMine)
                    TextButton(
                      onPressed: onComplete,
                      style: _gloveStyle,
                      child: const Text('Complete'),
                    ),
                  if (task.priority != TaskPriority.stat && task.status.isLive)
                    TextButton(
                      onPressed: onEscalate,
                      style: _gloveStyle,
                      child: const Text('Escalate'),
                    ),
                  if (task.status.isLive)
                    TextButton(
                      onPressed: onCancel,
                      style: _gloveStyle,
                      child: const Text('Cancel'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PriorityChip extends StatelessWidget {
  const _PriorityChip({required this.priority});

  final TaskPriority priority;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final Color background = switch (priority) {
      TaskPriority.stat => colors.errorContainer,
      TaskPriority.urgent => colors.tertiaryContainer,
      TaskPriority.medium => colors.surfaceContainerHighest,
      TaskPriority.low => colors.surfaceContainerLow,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(priority.label),
    );
  }
}

class _RaiseResult {
  const _RaiseResult({
    required this.taskCode,
    required this.title,
    required this.category,
    required this.priority,
    this.detail,
    this.fromLocation,
    this.toLocation,
  });

  final String taskCode;
  final String title;
  final TaskCategory category;
  final TaskPriority priority;
  final String? detail;
  final String? fromLocation;
  final String? toLocation;
}

class _RaiseDialog extends StatefulWidget {
  const _RaiseDialog();

  @override
  State<_RaiseDialog> createState() => _RaiseDialogState();
}

class _RaiseDialogState extends State<_RaiseDialog> {
  final TextEditingController _code = TextEditingController();
  final TextEditingController _title = TextEditingController();
  final TextEditingController _detail = TextEditingController();
  final TextEditingController _from = TextEditingController();
  final TextEditingController _to = TextEditingController();
  TaskCategory _category = TaskCategory.specimenTransport;
  TaskPriority _priority = TaskPriority.medium;

  @override
  void dispose() {
    _code.dispose();
    _title.dispose();
    _detail.dispose();
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Raise a task'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _code,
            decoration: const InputDecoration(labelText: 'Task code *'),
          ),
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'What needs doing *'),
          ),
          DropdownButtonFormField<TaskCategory>(
            initialValue: _category,
            decoration: const InputDecoration(labelText: 'Category'),
            items: TaskCategory.values
                .map(
                  (TaskCategory category) => DropdownMenuItem<TaskCategory>(
                    value: category,
                    child: Text(category.label),
                  ),
                )
                .toList(growable: false),
            onChanged: (TaskCategory? value) =>
                setState(() => _category = value ?? _category),
          ),
          DropdownButtonFormField<TaskPriority>(
            initialValue: _priority,
            decoration: const InputDecoration(labelText: 'Priority'),
            items: TaskPriority.values
                .map(
                  (TaskPriority priority) => DropdownMenuItem<TaskPriority>(
                    value: priority,
                    child: Text(priority.label),
                  ),
                )
                .toList(growable: false),
            onChanged: (TaskPriority? value) =>
                setState(() => _priority = value ?? _priority),
          ),
          TextField(
            controller: _from,
            decoration: const InputDecoration(
              labelText: 'From (optional location)',
            ),
          ),
          TextField(
            controller: _to,
            decoration: const InputDecoration(labelText: 'To (location)'),
          ),
          TextField(
            controller: _detail,
            decoration: const InputDecoration(labelText: 'Detail (optional)'),
            maxLines: 2,
          ),
        ],
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Dismiss'),
      ),
      FilledButton(
        onPressed: () {
          if (_code.text.trim().isEmpty || _title.text.trim().isEmpty) return;
          Navigator.pop(
            context,
            _RaiseResult(
              taskCode: _code.text.trim(),
              title: _title.text.trim(),
              category: _category,
              priority: _priority,
              detail: _detail.text.trim().isEmpty ? null : _detail.text.trim(),
              fromLocation: _from.text.trim().isEmpty
                  ? null
                  : _from.text.trim(),
              toLocation: _to.text.trim().isEmpty ? null : _to.text.trim(),
            ),
          );
        },
        child: const Text('Raise'),
      ),
    ],
  );
}

class _BoardError extends StatelessWidget {
  const _BoardError({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: onRetry,
            child: const Text('Try again'),
          ),
        ],
      ),
    ),
  );
}

Future<String?> _askValue({
  required BuildContext context,
  required String title,
  required String label,
  required String confirm,
}) async {
  final TextEditingController controller = TextEditingController();
  try {
    return await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(labelText: label),
          autofocus: true,
          maxLines: 3,
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Dismiss'),
          ),
          FilledButton(
            onPressed: () {
              final String value = controller.text.trim();
              if (value.isEmpty) return;
              Navigator.pop(context, value);
            },
            child: Text(confirm),
          ),
        ],
      ),
    );
  } finally {
    controller.dispose();
  }
}
