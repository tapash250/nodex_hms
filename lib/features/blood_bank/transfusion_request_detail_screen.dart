/// Transfusion request detail with crossmatch, approval, and reservation
/// actions (Module 26).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/blood_bank/blood_bank.dart';
import 'package:nodex_hms/features/blood_bank/blood_bank_controller.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// Detail screen for a single transfusion request.
class TransfusionRequestDetailScreen extends ConsumerWidget {
  /// Creates the transfusion request detail screen.
  const TransfusionRequestDetailScreen({
    super.key,
    required this.transfusionRequestId,
  });

  final String transfusionRequestId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<TransfusionRequest> detail = ref.watch(
      transfusionRequestDetailProvider(transfusionRequestId),
    );
    final AsyncValue<List<BloodUnit>> units = ref.watch(
      bloodUnitsForRequestProvider(transfusionRequestId),
    );
    final session = ref.watch(sessionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Transfusion request')),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace _) => _RequestError(
          error: error,
          onRetry: () => ref.invalidate(
            transfusionRequestDetailProvider(transfusionRequestId),
          ),
        ),
        data: (TransfusionRequest request) {
          final bool canCrossmatch = session.authorization.can(
            NodexPermissions.bloodUnitWrite,
          );
          final bool canApprove =
              session.authorization.can(NodexPermissions.transfusionRequest) &&
              session.authorization.can(NodexPermissions.transfusionFinalize);
          final bool canComplete = session.authorization.can(
            NodexPermissions.transfusionRequest,
          );
          final bool canReserve = session.authorization.can(
            NodexPermissions.bloodUnitWrite,
          );

          return _RequestBody(
            request: request,
            units: units,
            canCrossmatch: canCrossmatch,
            canApprove: canApprove,
            canComplete: canComplete,
            canReserve: canReserve,
            onCrossmatch: (CrossmatchResult result) async {
              try {
                final useCase = ref.read(recordCrossmatchUseCaseProvider);
                await useCase(
                  policy: session.authorization,
                  original: request,
                  crossmatchResult: result,
                );
                ref.invalidate(
                  transfusionRequestDetailProvider(transfusionRequestId),
                );
                ref.invalidate(transfusionRequestsProvider);
              } on NodexError catch (error) {
                if (context.mounted) {
                  _snack(context, error.message);
                }
              } catch (_) {
                if (context.mounted) {
                  _snack(context, 'The crossmatch could not be recorded.');
                }
              }
            },
            onApprove: () async {
              final String? userId = session.user?.userId;
              if (userId == null) {
                if (context.mounted) {
                  _snack(context, 'Session is not ready.');
                }
                return;
              }
              try {
                final useCase = ref.read(
                  approveTransfusionRequestUseCaseProvider,
                );
                await useCase(
                  policy: session.authorization,
                  original: request,
                  approvedBy: userId,
                );
                ref.invalidate(
                  transfusionRequestDetailProvider(transfusionRequestId),
                );
                ref.invalidate(transfusionRequestsProvider);
              } on NodexError catch (error) {
                if (context.mounted) {
                  _snack(context, error.message);
                }
              } catch (_) {
                if (context.mounted) {
                  _snack(context, 'The request could not be approved.');
                }
              }
            },
            onComplete: () async {
              try {
                final useCase = ref.read(
                  completeTransfusionRequestUseCaseProvider,
                );
                await useCase(policy: session.authorization, original: request);
                ref.invalidate(
                  transfusionRequestDetailProvider(transfusionRequestId),
                );
                ref.invalidate(transfusionRequestsProvider);
              } on NodexError catch (error) {
                if (context.mounted) {
                  _snack(context, error.message);
                }
              } catch (_) {
                if (context.mounted) {
                  _snack(context, 'The request could not be completed.');
                }
              }
            },
            onReserve: (BloodUnit unit) async {
              try {
                final useCase = ref.read(reserveBloodUnitUseCaseProvider);
                await useCase(
                  policy: session.authorization,
                  original: unit,
                  patientId: request.patientId,
                  transfusionRequestId: request.id,
                );
                ref.invalidate(bloodUnitsProvider);
                ref.invalidate(bloodUnitsForRequestProvider(request.id));
              } on NodexError catch (error) {
                if (context.mounted) {
                  _snack(context, error.message);
                }
              } catch (_) {
                if (context.mounted) {
                  _snack(context, 'The unit could not be reserved.');
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

class _RequestBody extends StatelessWidget {
  const _RequestBody({
    required this.request,
    required this.units,
    required this.canCrossmatch,
    required this.canApprove,
    required this.canComplete,
    required this.canReserve,
    required this.onCrossmatch,
    required this.onApprove,
    required this.onComplete,
    required this.onReserve,
  });

  final TransfusionRequest request;
  final AsyncValue<List<BloodUnit>> units;
  final bool canCrossmatch;
  final bool canApprove;
  final bool canComplete;
  final bool canReserve;
  final Future<void> Function(CrossmatchResult result) onCrossmatch;
  final Future<void> Function() onApprove;
  final Future<void> Function() onComplete;
  final Future<void> Function(BloodUnit unit) onReserve;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(request.status.label, style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  '${request.component.label} ×'
                  ' ${request.unitsRequested} · '
                  '${request.requestedBloodGroup.label}',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Urgency: ${request.urgency.label} · '
                  'Crossmatch: ${request.crossmatchResult.label}',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Patient: ${request.patientId}',
                  style: theme.textTheme.bodyMedium,
                ),
                if (request.indication != null) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    'Indication: ${request.indication}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
                if (request.approvedAt != null) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    'Approved: ${request.approvedAt!.toIso8601String()}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (canCrossmatch && !request.isTerminal) ...<Widget>[
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _showCrossmatchSheet(context, onCrossmatch),
              icon: const Icon(Icons.biotech),
              label: const Text('Record crossmatch'),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (canApprove && !request.isTerminal) ...<Widget>[
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () async {
                final bool confirmed = await _confirm(
                  context,
                  title: 'Approve request',
                  message: 'Approve this transfusion request?',
                );
                if (confirmed) {
                  await onApprove();
                }
              },
              icon: const Icon(Icons.how_to_reg),
              label: const Text('Approve request'),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (canReserve && !request.isTerminal) ...<Widget>[
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _showReserveSheet(context, onReserve),
              icon: const Icon(Icons.inventory_2_outlined),
              label: const Text('Reserve a unit'),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (canComplete &&
            request.status == TransfusionRequestStatus.approved) ...<Widget>[
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                final bool confirmed = await _confirm(
                  context,
                  title: 'Complete request',
                  message: 'Mark this transfusion request completed?',
                );
                if (confirmed) {
                  await onComplete();
                }
              },
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Mark completed'),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Text('Units', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        units.when(
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
                    : 'Could not load blood units.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ),
          data: (List<BloodUnit> list) {
            if (list.isEmpty) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'No units reserved for this request.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              );
            }
            return Card(
              child: Column(
                children: <Widget>[
                  for (final BloodUnit unit in list)
                    ListTile(
                      leading: const Icon(Icons.bloodtype_outlined),
                      title: Text(unit.unitNumber),
                      subtitle: Text(
                        '${unit.bloodGroup.label} · '
                        '${unit.status.label}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/blood-bank/units/${unit.id}'),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  void _showCrossmatchSheet(
    BuildContext context,
    Future<void> Function(CrossmatchResult result) onCrossmatch,
  ) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Record crossmatch',
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () async {
                    await onCrossmatch(CrossmatchResult.compatible);
                    if (sheetContext.mounted) {
                      Navigator.of(sheetContext).pop();
                    }
                  },
                  icon: const Icon(Icons.check),
                  label: const Text('Compatible'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await onCrossmatch(CrossmatchResult.incompatible);
                    if (sheetContext.mounted) {
                      Navigator.of(sheetContext).pop();
                    }
                  },
                  icon: const Icon(Icons.close),
                  label: const Text('Incompatible'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showReserveSheet(
    BuildContext context,
    Future<void> Function(BloodUnit unit) onReserve,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Consumer(
            builder: (BuildContext context, WidgetRef ref, Widget? _) {
              final AsyncValue<List<BloodUnit>> all = ref.watch(
                bloodUnitsProvider,
              );
              return all.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (Object error, StackTrace _) => Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    error is NodexError
                        ? error.message
                        : 'Could not load blood units.',
                  ),
                ),
                data: (List<BloodUnit> list) {
                  final List<BloodUnit> available = list
                      .where(
                        (BloodUnit unit) =>
                            unit.status == BloodUnitStatus.available,
                      )
                      .toList(growable: false);
                  if (available.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No available blood units.'),
                    );
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: available.length,
                    itemBuilder: (BuildContext context, int index) {
                      final BloodUnit unit = available[index];
                      return ListTile(
                        leading: const Icon(Icons.bloodtype_outlined),
                        title: Text(unit.unitNumber),
                        subtitle: Text(
                          '${unit.bloodGroup.label} · '
                          '${unit.component.label}',
                        ),
                        onTap: () async {
                          await onReserve(unit);
                          if (sheetContext.mounted) {
                            Navigator.of(sheetContext).pop();
                          }
                        },
                      );
                    },
                  );
                },
              );
            },
          ),
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

class _RequestError extends StatelessWidget {
  const _RequestError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String message = error is NodexError
        ? (error as NodexError).message
        : 'The transfusion request could not be loaded.';
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
