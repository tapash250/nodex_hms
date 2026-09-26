/// One theatre booking with its pre-op, anesthesia, procedure and post-op
/// records plus the case state transitions (Module 19).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/ot/ot.dart';
import 'package:nodex_hms/features/ot/ot_controller.dart';
import 'package:nodex_hms/features/ot/ot_list_screen.dart' show otStamp;
import 'package:nodex_hms/features/session/session_controller.dart';

/// Loads one booking and renders its full case record.
class OtBookingDetailScreen extends ConsumerWidget {
  /// Creates the operation theatre booking detail screen.
  const OtBookingDetailScreen({super.key, required this.bookingId});

  /// Identifier of the booking to load.
  final String bookingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<OtBooking> async = ref.watch(
      otBookingDetailProvider(bookingId),
    );
    return async.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (Object error, StackTrace _) => Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              error is NodexError
                  ? error.message
                  : 'Could not load this theatre booking.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
      data: (OtBooking booking) => _OtBookingDetail(booking: booking),
    );
  }
}

class _OtBookingDetail extends ConsumerWidget {
  const _OtBookingDetail({required this.booking});

  final OtBooking booking;

  void _invalidate(WidgetRef ref) {
    ref.invalidate(otBookingDetailProvider(booking.id));
    ref.invalidate(otBookingsProvider);
    ref.invalidate(otBookingsForPatientProvider(booking.patientId));
    ref.invalidate(otPreOpForBookingProvider(booking.id));
    ref.invalidate(otAnesthesiaForBookingProvider(booking.id));
    ref.invalidate(otProcedureLogForBookingProvider(booking.id));
    ref.invalidate(otPostOpForBookingProvider(booking.id));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final session = ref.watch(sessionProvider);
    final bool canRecord = session.authorization.can(NodexPermissions.otRecord);
    final bool canSchedule = session.authorization.can(
      NodexPermissions.otSchedule,
    );
    final bool canFinalize = session.authorization.can(
      NodexPermissions.otFinalize,
    );
    final OtPreOpAssessment? preOp = ref
        .watch(otPreOpForBookingProvider(booking.id))
        .value;
    final OtAnesthesiaRecord? anesthesia = ref
        .watch(otAnesthesiaForBookingProvider(booking.id))
        .value;
    final OtProcedureLog? procedure = ref
        .watch(otProcedureLogForBookingProvider(booking.id))
        .value;
    final OtPostOpRecord? postOp = ref
        .watch(otPostOpForBookingProvider(booking.id))
        .value;

    return Scaffold(
      appBar: AppBar(title: Text(booking.procedureName)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Chip(label: Text(booking.status.label)),
                      const SizedBox(width: 8),
                      Chip(label: Text(booking.priority.label)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${booking.theatreRoom} · '
                    '${otStamp(booking.scheduledStart)} → '
                    '${otStamp(booking.scheduledEnd)}',
                    style: theme.textTheme.bodyMedium,
                  ),
                  if (booking.cancellationReason != null) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      'Cancelled: ${booking.cancellationReason}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Pre-op assessment', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (preOp == null)
            Card(
              child: ListTile(
                title: const Text('Not recorded'),
                subtitle: canRecord && !booking.isTerminal
                    ? const Text('Required before the case can start.')
                    : null,
                trailing: canRecord && !booking.isTerminal
                    ? const Icon(Icons.add)
                    : null,
                onTap: canRecord && !booking.isTerminal
                    ? () => _preOpSheet(context, ref)
                    : null,
              ),
            )
          else
            Card(
              child: ListTile(
                leading: Icon(
                  preOp.fitForSurgery
                      ? Icons.check_circle_outline
                      : Icons.warning_amber_outlined,
                ),
                title: Text(preOp.fitness.label),
                subtitle: Text(
                  [
                    if (preOp.asaClass != null) 'ASA ${preOp.asaClass}',
                    if (preOp.notes != null) preOp.notes!,
                  ].join(' · '),
                ),
                trailing: canRecord && !booking.isTerminal
                    ? const Icon(Icons.edit_outlined)
                    : null,
                onTap: canRecord && !booking.isTerminal
                    ? () => _preOpSheet(context, ref)
                    : null,
              ),
            ),
          const SizedBox(height: 16),
          Text('Anesthesia', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (anesthesia == null)
            Card(
              child: ListTile(
                title: const Text('Not recorded'),
                trailing: canRecord && booking.isInProgress
                    ? const Icon(Icons.add)
                    : null,
                onTap: canRecord && booking.isInProgress
                    ? () => _anesthesiaSheet(context, ref)
                    : null,
              ),
            )
          else
            Card(
              child: ListTile(
                title: Text(anesthesia.anesthesiaType.label),
                subtitle: Text(
                  anesthesia.isComplete
                      ? 'Ended ${otStamp(anesthesia.endedAt!)}'
                      : 'In progress since '
                            '${otStamp(anesthesia.startedAt)}',
                ),
                trailing:
                    canRecord && booking.isInProgress && !anesthesia.isComplete
                    ? const Icon(Icons.stop_circle_outlined)
                    : null,
                onTap:
                    canRecord && booking.isInProgress && !anesthesia.isComplete
                    ? () => _endAnesthesia(context, ref)
                    : null,
              ),
            ),
          const SizedBox(height: 16),
          Text('Procedure', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (procedure == null)
            Card(
              child: ListTile(
                title: const Text('Not recorded'),
                trailing: canRecord && booking.isInProgress
                    ? const Icon(Icons.add)
                    : null,
                onTap: canRecord && booking.isInProgress
                    ? () => _procedureSheet(context, ref)
                    : null,
              ),
            )
          else
            Card(
              child: ListTile(
                title: Text(procedure.procedureName),
                subtitle: Text(
                  procedure.isComplete
                      ? 'Completed ${otStamp(procedure.completedAt!)}'
                      : 'In progress since ${otStamp(procedure.startedAt)}',
                ),
                trailing:
                    canRecord && booking.isInProgress && !procedure.isComplete
                    ? const Icon(Icons.check_circle_outline)
                    : null,
                onTap:
                    canRecord && booking.isInProgress && !procedure.isComplete
                    ? () => _completeProcedure(context, ref)
                    : null,
              ),
            ),
          const SizedBox(height: 16),
          Text('Post-op recovery', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (postOp == null)
            Card(
              child: ListTile(
                title: const Text('Not recorded'),
                subtitle: canRecord && booking.isInProgress
                    ? const Text('Required before the case can complete.')
                    : null,
                trailing: canRecord && booking.isInProgress
                    ? const Icon(Icons.add)
                    : null,
                onTap: canRecord && booking.isInProgress
                    ? () => _postOpSheet(context, ref)
                    : null,
              ),
            )
          else
            Card(
              child: ListTile(
                leading: Icon(
                  postOp.isCritical
                      ? Icons.warning_amber_outlined
                      : Icons.favorite_outline,
                ),
                title: Text(postOp.condition.label),
                subtitle: Text(
                  [
                    if (postOp.painScore != null) 'Pain ${postOp.painScore}/10',
                    if (postOp.complications != null) postOp.complications!,
                    if (postOp.notes != null) postOp.notes!,
                  ].join(' · '),
                ),
                trailing: canRecord && booking.isInProgress
                    ? const Icon(Icons.edit_outlined)
                    : null,
                onTap: canRecord && booking.isInProgress
                    ? () => _postOpSheet(context, ref)
                    : null,
              ),
            ),
          const SizedBox(height: 24),
          if (booking.isScheduled && canRecord)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _start(context, ref),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start case'),
              ),
            ),
          if (booking.isInProgress && canFinalize) ...<Widget>[
            if (postOp == null)
              Text(
                'Record the post-op recovery state to complete this case.',
                style: theme.textTheme.bodySmall,
              ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: postOp == null
                    ? null
                    : () => _complete(context, ref),
                icon: const Icon(Icons.check),
                label: const Text('Complete case'),
              ),
            ),
          ],
          if (!booking.isTerminal && canSchedule) ...<Widget>[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _cancel(context, ref),
                icon: const Icon(Icons.close),
                label: const Text('Cancel case'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _run(
    BuildContext context,
    WidgetRef ref, {
    required Future<Object?> Function() run,
    bool popSheet = false,
    String fallback = 'The update could not be saved.',
  }) async {
    try {
      await run();
      _invalidate(ref);
      if (popSheet && context.mounted) {
        Navigator.of(context).pop();
      }
    } on NodexError catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(fallback)));
      }
    }
  }

  Future<void> _start(BuildContext context, WidgetRef ref) async {
    final session = ref.read(sessionProvider);
    await _run(
      context,
      ref,
      run: () => ref.read(startOtBookingUseCaseProvider)(
        policy: session.authorization,
        original: booking,
      ),
      fallback: 'The case could not be started.',
    );
  }

  Future<void> _complete(BuildContext context, WidgetRef ref) async {
    final session = ref.read(sessionProvider);
    await _run(
      context,
      ref,
      run: () => ref.read(completeOtBookingUseCaseProvider)(
        policy: session.authorization,
        original: booking,
      ),
      fallback: 'The case could not be completed.',
    );
  }

  Future<void> _endAnesthesia(BuildContext context, WidgetRef ref) async {
    final session = ref.read(sessionProvider);
    final String? userId = session.user?.userId;
    final OtAnesthesiaRecord? record = ref
        .read(otAnesthesiaForBookingProvider(booking.id))
        .value;
    if (userId == null || record == null) return;
    await _run(
      context,
      ref,
      run: () => ref.read(recordAnesthesiaUseCaseProvider)(
        policy: session.authorization,
        booking: booking,
        recordedBy: record.recordedBy,
        anesthesiaType: record.anesthesiaType,
        startedAt: record.startedAt,
        endedAt: DateTime.now().toUtc(),
      ),
      fallback: 'The anesthesia record could not be closed.',
    );
  }

  Future<void> _completeProcedure(BuildContext context, WidgetRef ref) async {
    final session = ref.read(sessionProvider);
    final OtProcedureLog? log = ref
        .read(otProcedureLogForBookingProvider(booking.id))
        .value;
    if (log == null) return;
    await _run(
      context,
      ref,
      run: () => ref.read(recordProcedureLogUseCaseProvider)(
        policy: session.authorization,
        booking: booking,
        performedBy: log.performedBy,
        procedureName: log.procedureName,
        findings: log.findings,
        startedAt: log.startedAt,
        completedAt: DateTime.now().toUtc(),
      ),
      fallback: 'The procedure log could not be completed.',
    );
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final TextEditingController reason = TextEditingController();
    final String? value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel case'),
        content: TextField(
          controller: reason,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Reason'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Keep booking'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(reason.text),
            child: const Text('Cancel case'),
          ),
        ],
      ),
    );
    if (value == null || !context.mounted) return;
    final session = ref.read(sessionProvider);
    await _run(
      context,
      ref,
      run: () => ref.read(cancelOtBookingUseCaseProvider)(
        policy: session.authorization,
        original: booking,
        reason: value,
      ),
      fallback: 'The case could not be cancelled.',
    );
  }

  void _preOpSheet(BuildContext context, WidgetRef ref) {
    OtFitness fitness = OtFitness.fit;
    final TextEditingController asaController = TextEditingController();
    final TextEditingController notesController = TextEditingController();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder:
              (BuildContext context, void Function(void Function()) setState) {
                return Padding(
                  padding: EdgeInsets.only(
                    left: 16,
                    right: 16,
                    top: 16,
                    bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Pre-op assessment',
                        style: Theme.of(sheetContext).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<OtFitness>(
                        initialValue: fitness,
                        decoration: const InputDecoration(labelText: 'Fitness'),
                        items: <DropdownMenuItem<OtFitness>>[
                          for (final OtFitness value in OtFitness.values)
                            DropdownMenuItem<OtFitness>(
                              value: value,
                              child: Text(value.label),
                            ),
                        ],
                        onChanged: (OtFitness? value) {
                          if (value != null) {
                            setState(() => fitness = value);
                          }
                        },
                      ),
                      TextField(
                        controller: asaController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'ASA class 1–6 (optional)',
                        ),
                      ),
                      TextField(
                        controller: notesController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Notes (optional)',
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () async {
                            final session = ref.read(sessionProvider);
                            await _run(
                              sheetContext,
                              ref,
                              popSheet: true,
                              run: () =>
                                  ref.read(
                                    recordPreOpAssessmentUseCaseProvider,
                                  )(
                                    policy: session.authorization,
                                    booking: booking,
                                    assessedBy: session.user?.userId ?? '',
                                    fitness: fitness,
                                    asaClass: int.tryParse(asaController.text),
                                    notes: notesController.text.trim().isEmpty
                                        ? null
                                        : notesController.text.trim(),
                                  ),
                              fallback: 'The assessment could not be recorded.',
                            );
                          },
                          child: const Text('Record assessment'),
                        ),
                      ),
                    ],
                  ),
                );
              },
        );
      },
    );
  }

  void _anesthesiaSheet(BuildContext context, WidgetRef ref) {
    OtAnesthesiaType type = OtAnesthesiaType.general;
    final TextEditingController notesController = TextEditingController();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder:
              (BuildContext context, void Function(void Function()) setState) {
                return Padding(
                  padding: EdgeInsets.only(
                    left: 16,
                    right: 16,
                    top: 16,
                    bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Record anesthesia',
                        style: Theme.of(sheetContext).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<OtAnesthesiaType>(
                        initialValue: type,
                        decoration: const InputDecoration(
                          labelText: 'Technique',
                        ),
                        items: <DropdownMenuItem<OtAnesthesiaType>>[
                          for (final OtAnesthesiaType value
                              in OtAnesthesiaType.values)
                            DropdownMenuItem<OtAnesthesiaType>(
                              value: value,
                              child: Text(value.label),
                            ),
                        ],
                        onChanged: (OtAnesthesiaType? value) {
                          if (value != null) {
                            setState(() => type = value);
                          }
                        },
                      ),
                      TextField(
                        controller: notesController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Notes (optional)',
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () async {
                            final session = ref.read(sessionProvider);
                            await _run(
                              sheetContext,
                              ref,
                              popSheet: true,
                              run: () =>
                                  ref.read(recordAnesthesiaUseCaseProvider)(
                                    policy: session.authorization,
                                    booking: booking,
                                    recordedBy: session.user?.userId ?? '',
                                    anesthesiaType: type,
                                    notes: notesController.text.trim().isEmpty
                                        ? null
                                        : notesController.text.trim(),
                                  ),
                              fallback:
                                  'The anesthesia record could not be saved.',
                            );
                          },
                          child: const Text('Start anesthesia'),
                        ),
                      ),
                    ],
                  ),
                );
              },
        );
      },
    );
  }

  void _procedureSheet(BuildContext context, WidgetRef ref) {
    final TextEditingController nameController = TextEditingController(
      text: booking.procedureName,
    );
    final TextEditingController findingsController = TextEditingController();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Record procedure',
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Procedure'),
              ),
              TextField(
                controller: findingsController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Findings (optional)',
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    final session = ref.read(sessionProvider);
                    await _run(
                      sheetContext,
                      ref,
                      popSheet: true,
                      run: () => ref.read(recordProcedureLogUseCaseProvider)(
                        policy: session.authorization,
                        booking: booking,
                        performedBy: session.user?.userId ?? '',
                        procedureName: nameController.text,
                        findings: findingsController.text.trim().isEmpty
                            ? null
                            : findingsController.text.trim(),
                      ),
                      fallback: 'The procedure log could not be saved.',
                    );
                  },
                  child: const Text('Start procedure'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _postOpSheet(BuildContext context, WidgetRef ref) {
    OtPostOpCondition condition = OtPostOpCondition.stable;
    final TextEditingController painController = TextEditingController();
    final TextEditingController complicationsController =
        TextEditingController();
    final TextEditingController notesController = TextEditingController();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder:
              (BuildContext context, void Function(void Function()) setState) {
                return Padding(
                  padding: EdgeInsets.only(
                    left: 16,
                    right: 16,
                    top: 16,
                    bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Post-op recovery',
                        style: Theme.of(sheetContext).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<OtPostOpCondition>(
                        initialValue: condition,
                        decoration: const InputDecoration(
                          labelText: 'Condition',
                        ),
                        items: <DropdownMenuItem<OtPostOpCondition>>[
                          for (final OtPostOpCondition value
                              in OtPostOpCondition.values)
                            DropdownMenuItem<OtPostOpCondition>(
                              value: value,
                              child: Text(value.label),
                            ),
                        ],
                        onChanged: (OtPostOpCondition? value) {
                          if (value != null) {
                            setState(() => condition = value);
                          }
                        },
                      ),
                      TextField(
                        controller: painController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Pain score 0–10 (optional)',
                        ),
                      ),
                      TextField(
                        controller: complicationsController,
                        decoration: const InputDecoration(
                          labelText: 'Complications (optional)',
                        ),
                      ),
                      TextField(
                        controller: notesController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Notes (optional)',
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () async {
                            final session = ref.read(sessionProvider);
                            await _run(
                              sheetContext,
                              ref,
                              popSheet: true,
                              run: () => ref.read(recordPostOpUseCaseProvider)(
                                policy: session.authorization,
                                booking: booking,
                                recordedBy: session.user?.userId ?? '',
                                condition: condition,
                                painScore: int.tryParse(painController.text),
                                complications:
                                    complicationsController.text.trim().isEmpty
                                    ? null
                                    : complicationsController.text.trim(),
                                notes: notesController.text.trim().isEmpty
                                    ? null
                                    : notesController.text.trim(),
                              ),
                              fallback:
                                  'The post-op record could not be saved.',
                            );
                          },
                          child: const Text('Record post-op'),
                        ),
                      ),
                    ],
                  ),
                );
              },
        );
      },
    );
  }
}
