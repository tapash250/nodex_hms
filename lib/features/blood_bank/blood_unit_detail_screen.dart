/// Blood unit detail with issue, transfusion, and discard actions (Module 26).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/blood_bank/blood_bank.dart';
import 'package:nodex_hms/features/blood_bank/blood_bank_controller.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// Detail screen for a single blood unit.
class BloodUnitDetailScreen extends ConsumerWidget {
  /// Creates the blood unit detail screen.
  const BloodUnitDetailScreen({super.key, required this.unitId});

  final String unitId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<BloodUnit> detail = ref.watch(
      bloodUnitDetailProvider(unitId),
    );
    final session = ref.watch(sessionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Blood unit')),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace _) => _UnitError(
          error: error,
          onRetry: () => ref.invalidate(bloodUnitDetailProvider(unitId)),
        ),
        data: (BloodUnit unit) {
          final AsyncValue<List<Transfusion>> transfusions =
              unit.patientId == null
              ? const AsyncValue.data(<Transfusion>[])
              : ref.watch(transfusionsForPatientProvider(unit.patientId!));

          return _UnitBody(
            unit: unit,
            transfusions: transfusions,
            canWrite: session.authorization.can(
              NodexPermissions.bloodUnitWrite,
            ),
            canAdminister: session.authorization.can(
              NodexPermissions.transfusionAdminister,
            ),
            onIssue: () async {
              try {
                final useCase = ref.read(issueBloodUnitUseCaseProvider);
                await useCase(policy: session.authorization, original: unit);
                ref.invalidate(bloodUnitDetailProvider(unitId));
                ref.invalidate(bloodUnitsProvider);
              } on NodexError catch (error) {
                if (context.mounted) {
                  _snack(context, error.message);
                }
              } catch (_) {
                if (context.mounted) {
                  _snack(context, 'The unit could not be issued.');
                }
              }
            },
            onDiscard: () async {
              try {
                final useCase = ref.read(discardBloodUnitUseCaseProvider);
                await useCase(policy: session.authorization, original: unit);
                ref.invalidate(bloodUnitDetailProvider(unitId));
                ref.invalidate(bloodUnitsProvider);
              } on NodexError catch (error) {
                if (context.mounted) {
                  _snack(context, error.message);
                }
              } catch (_) {
                if (context.mounted) {
                  _snack(context, 'The unit could not be discarded.');
                }
              }
            },
            onStartTransfusion: () async {
              final String? patientId = unit.patientId;
              final String? requestId = unit.transfusionRequestId;
              final String? userId = session.user?.userId;
              if (patientId == null || requestId == null || userId == null) {
                if (context.mounted) {
                  _snack(context, 'Session is not ready.');
                }
                return;
              }
              try {
                final useCase = ref.read(recordTransfusionUseCaseProvider);
                await useCase(
                  policy: session.authorization,
                  tenantId: unit.tenantId,
                  transfusionRequestId: requestId,
                  bloodUnitId: unit.id,
                  patientId: patientId,
                  recordedBy: userId,
                );
                ref.invalidate(bloodUnitDetailProvider(unitId));
                ref.invalidate(transfusionsForPatientProvider(patientId));
              } on NodexError catch (error) {
                if (context.mounted) {
                  _snack(context, error.message);
                }
              } catch (_) {
                if (context.mounted) {
                  _snack(context, 'The transfusion could not be started.');
                }
              }
            },
            onRecordOutcome:
                (
                  Transfusion transfusion,
                  TransfusionStatus status,
                  int? volumeMl,
                  String? reactionNotes,
                ) async {
                  try {
                    final useCase = ref.read(
                      recordTransfusionOutcomeUseCaseProvider,
                    );
                    await useCase(
                      policy: session.authorization,
                      original: transfusion,
                      status: status,
                      volumeMl: volumeMl,
                      reactionNotes: reactionNotes,
                    );
                    ref.invalidate(bloodUnitDetailProvider(unitId));
                    ref.invalidate(
                      transfusionsForPatientProvider(transfusion.patientId),
                    );
                  } on NodexError catch (error) {
                    if (context.mounted) {
                      _snack(context, error.message);
                    }
                  } catch (_) {
                    if (context.mounted) {
                      _snack(context, 'The outcome could not be recorded.');
                    }
                  }
                },
          );
        },
      ),
    );
  }

  static void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _UnitBody extends StatelessWidget {
  const _UnitBody({
    required this.unit,
    required this.transfusions,
    required this.canWrite,
    required this.canAdminister,
    required this.onIssue,
    required this.onDiscard,
    required this.onStartTransfusion,
    required this.onRecordOutcome,
  });

  final BloodUnit unit;
  final AsyncValue<List<Transfusion>> transfusions;
  final bool canWrite;
  final bool canAdminister;
  final Future<void> Function() onIssue;
  final Future<void> Function() onDiscard;
  final Future<void> Function() onStartTransfusion;
  final Future<void> Function(
    Transfusion transfusion,
    TransfusionStatus status,
    int? volumeMl,
    String? reactionNotes,
  )
  onRecordOutcome;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool canIssue =
        canWrite &&
        unit.status == BloodUnitStatus.reserved &&
        unit.transfusionRequestId != null;
    final bool canStart =
        canAdminister &&
        unit.status == BloodUnitStatus.issued &&
        unit.patientId != null;
    final bool canDiscard = canWrite && !unit.isTerminal;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(unit.status.label, style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  '${unit.unitNumber} · ${unit.bloodGroup.label} · '
                  '${unit.component.label}',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Expires: ${unit.expiresAt.toIso8601String()}',
                  style: theme.textTheme.bodyMedium,
                ),
                if (unit.volumeMl != null) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    'Volume: ${unit.volumeMl} ml',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
                if (unit.patientId != null) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    'Patient: ${unit.patientId}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (canIssue) ...<Widget>[
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () async {
                final bool confirmed = await _confirm(
                  context,
                  title: 'Issue unit',
                  message:
                      'Issue this blood unit against its approved '
                      'transfusion request?',
                );
                if (confirmed) {
                  await onIssue();
                }
              },
              icon: const Icon(Icons.outbox_outlined),
              label: const Text('Issue unit'),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (canStart) ...<Widget>[
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () async {
                final bool confirmed = await _confirm(
                  context,
                  title: 'Start transfusion',
                  message: 'Start transfusing this blood unit?',
                );
                if (confirmed) {
                  await onStartTransfusion();
                }
              },
              icon: const Icon(Icons.favorite_outline),
              label: const Text('Start transfusion'),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (canDiscard) ...<Widget>[
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                final bool confirmed = await _confirm(
                  context,
                  title: 'Discard unit',
                  message: 'Discard this blood unit? This cannot be undone.',
                );
                if (confirmed) {
                  await onDiscard();
                }
              },
              icon: const Icon(Icons.delete_outline),
              label: const Text('Discard unit'),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Text('Transfusions', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        transfusions.when(
          loading: () => const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
          error: (Object error, StackTrace _) => Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                error is NodexError
                    ? error.message
                    : 'Could not load transfusions.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ),
          data: (List<Transfusion> list) {
            final List<Transfusion> forUnit = list
                .where(
                  (Transfusion transfusion) =>
                      transfusion.bloodUnitId == unit.id,
                )
                .toList(growable: false);
            Transfusion? activeCandidate;
            for (final Transfusion transfusion in forUnit) {
              if (transfusion.status == TransfusionStatus.started) {
                activeCandidate = transfusion;
                break;
              }
            }
            final Transfusion? active = activeCandidate;
            if (forUnit.isEmpty) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'No transfusions recorded for this unit.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              );
            }
            return Card(
              child: Column(
                children: <Widget>[
                  for (final Transfusion transfusion in forUnit)
                    ListTile(
                      leading: const Icon(Icons.favorite_outline),
                      title: Text(transfusion.status.label),
                      subtitle: Text(transfusion.startedAt.toIso8601String()),
                    ),
                  if (active != null && canAdminister)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => _showOutcomeSheet(
                            context,
                            active,
                            onRecordOutcome,
                          ),
                          icon: const Icon(Icons.assignment_turned_in),
                          label: const Text('Record outcome'),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  void _showOutcomeSheet(
    BuildContext context,
    Transfusion transfusion,
    Future<void> Function(
      Transfusion transfusion,
      TransfusionStatus status,
      int? volumeMl,
      String? reactionNotes,
    )
    onRecordOutcome,
  ) {
    final TextEditingController volumeController = TextEditingController();
    final TextEditingController notesController = TextEditingController();
    TransfusionStatus status = TransfusionStatus.transfused;

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
                        'Record outcome',
                        style: Theme.of(sheetContext).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<TransfusionStatus>(
                        initialValue: status,
                        decoration: const InputDecoration(labelText: 'Outcome'),
                        items: <DropdownMenuItem<TransfusionStatus>>[
                          for (final TransfusionStatus value
                              in TransfusionStatus.values)
                            DropdownMenuItem<TransfusionStatus>(
                              value: value,
                              child: Text(value.label),
                            ),
                        ],
                        onChanged: (TransfusionStatus? value) {
                          if (value != null) {
                            setState(() => status = value);
                          }
                        },
                      ),
                      TextField(
                        controller: volumeController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Volume infused (ml)',
                        ),
                      ),
                      TextField(
                        controller: notesController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Reaction notes',
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () async {
                            await onRecordOutcome(
                              transfusion,
                              status,
                              int.tryParse(volumeController.text),
                              notesController.text.trim().isEmpty
                                  ? null
                                  : notesController.text.trim(),
                            );
                            if (sheetContext.mounted) {
                              Navigator.of(sheetContext).pop();
                            }
                          },
                          child: const Text('Save'),
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

  static Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String message,
  }) async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }
}

class _UnitError extends StatelessWidget {
  const _UnitError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String message = error is NodexError
        ? (error as NodexError).message
        : 'The blood unit could not be loaded.';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.error_outline, size: 56, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(
              message,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
