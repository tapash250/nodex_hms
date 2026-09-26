/// Blood bank section embedded in the patient detail screen (Module 26).
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

/// Shows a patient's transfusion requests and lets authorized staff raise one.
class BloodBankPatientSection extends ConsumerWidget {
  /// Creates the blood bank patient section.
  const BloodBankPatientSection({super.key, required this.patientId});

  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<List<TransfusionRequest>> requests = ref.watch(
      transfusionRequestsForPatientProvider(patientId),
    );
    final session = ref.watch(sessionProvider);
    final bool canRequest = session.authorization.can(
      NodexPermissions.transfusionRequest,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Transfusion', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        requests.when(
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
                    : 'Could not load transfusion requests.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ),
          data: (List<TransfusionRequest> list) {
            if (list.isEmpty) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'No transfusion requests recorded.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              );
            }

            return Card(
              child: Column(
                children: <Widget>[
                  for (final TransfusionRequest request in list.take(5))
                    ListTile(
                      leading: const Icon(Icons.volunteer_activism_outlined),
                      title: Text(
                        '${request.component.label} ×'
                        ' ${request.unitsRequested}',
                      ),
                      subtitle: Text(
                        '${request.status.label} · '
                        '${request.urgency.label}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () =>
                          context.push('/blood-bank/requests/${request.id}'),
                    ),
                ],
              ),
            );
          },
        ),
        if (canRequest) ...<Widget>[
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Raise a transfusion request for this patient.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              TextButton.icon(
                onPressed: () => _showRequestSheet(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('New request'),
              ),
            ],
          ),
        ],
      ],
    );
  }

  void _showRequestSheet(BuildContext context, WidgetRef ref) {
    final TextEditingController unitsController = TextEditingController(
      text: '1',
    );
    final TextEditingController indicationController = TextEditingController();
    BloodGroup bloodGroup = BloodGroup.oPositive;
    BloodComponent component = BloodComponent.redCells;
    TransfusionUrgency urgency = TransfusionUrgency.routine;

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
                        'New transfusion request',
                        style: Theme.of(sheetContext).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<BloodGroup>(
                        initialValue: bloodGroup,
                        decoration: const InputDecoration(
                          labelText: 'Blood group',
                        ),
                        items: <DropdownMenuItem<BloodGroup>>[
                          for (final BloodGroup group in BloodGroup.values)
                            DropdownMenuItem<BloodGroup>(
                              value: group,
                              child: Text(group.label),
                            ),
                        ],
                        onChanged: (BloodGroup? value) {
                          if (value != null) {
                            setState(() => bloodGroup = value);
                          }
                        },
                      ),
                      DropdownButtonFormField<BloodComponent>(
                        initialValue: component,
                        decoration: const InputDecoration(
                          labelText: 'Component',
                        ),
                        items: <DropdownMenuItem<BloodComponent>>[
                          for (final BloodComponent value
                              in BloodComponent.values)
                            DropdownMenuItem<BloodComponent>(
                              value: value,
                              child: Text(value.label),
                            ),
                        ],
                        onChanged: (BloodComponent? value) {
                          if (value != null) {
                            setState(() => component = value);
                          }
                        },
                      ),
                      DropdownButtonFormField<TransfusionUrgency>(
                        initialValue: urgency,
                        decoration: const InputDecoration(labelText: 'Urgency'),
                        items: <DropdownMenuItem<TransfusionUrgency>>[
                          for (final TransfusionUrgency value
                              in TransfusionUrgency.values)
                            DropdownMenuItem<TransfusionUrgency>(
                              value: value,
                              child: Text(value.label),
                            ),
                        ],
                        onChanged: (TransfusionUrgency? value) {
                          if (value != null) {
                            setState(() => urgency = value);
                          }
                        },
                      ),
                      TextField(
                        controller: unitsController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Units requested',
                        ),
                      ),
                      TextField(
                        controller: indicationController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Indication (optional)',
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () async {
                            await _submit(
                              context: sheetContext,
                              ref: ref,
                              bloodGroup: bloodGroup,
                              component: component,
                              urgency: urgency,
                              unitsRequested:
                                  int.tryParse(unitsController.text) ?? 0,
                              indication: indicationController.text,
                            );
                          },
                          child: const Text('Raise request'),
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

  Future<void> _submit({
    required BuildContext context,
    required WidgetRef ref,
    required BloodGroup bloodGroup,
    required BloodComponent component,
    required TransfusionUrgency urgency,
    required int unitsRequested,
    required String indication,
  }) async {
    final session = ref.read(sessionProvider);
    final String? tenantId = session.tenantId;
    final String? userId = session.user?.userId;
    if (tenantId == null || userId == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Session is not ready.')));
      }
      return;
    }
    try {
      final useCase = ref.read(requestTransfusionUseCaseProvider);
      await useCase(
        policy: session.authorization,
        tenantId: tenantId,
        patientId: patientId,
        requestedBy: userId,
        requestedBloodGroup: bloodGroup,
        component: component,
        unitsRequested: unitsRequested,
        indication: indication.trim().isEmpty ? null : indication.trim(),
        urgency: urgency,
      );
      ref.invalidate(transfusionRequestsForPatientProvider(patientId));
      ref.invalidate(transfusionRequestsProvider);
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    } on NodexError catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The transfusion request could not be raised.'),
          ),
        );
      }
    }
  }
}
