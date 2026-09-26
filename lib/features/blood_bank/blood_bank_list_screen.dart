/// Blood bank inventory and transfusion queue (Module 26).
///
/// Lists every blood unit and transfusion request for the active tenant with
/// status and linkage. Selection opens the detail screens; this screen only
/// renders state and routes — registration, reservations, approvals and issue
/// stay in the use cases.
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

/// Blood bank list with blood unit and transfusion request tabs.
class BloodBankListScreen extends ConsumerWidget {
  /// Creates the blood bank list screen.
  const BloodBankListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Blood bank'),
          actions: <Widget>[
            if (session.authorization.can(NodexPermissions.bloodUnitWrite))
              IconButton(
                tooltip: 'Register unit',
                icon: const Icon(Icons.add),
                onPressed: () => _showRegisterSheet(context, ref),
              ),
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh),
              onPressed: () {
                ref.invalidate(bloodUnitsProvider);
                ref.invalidate(transfusionRequestsProvider);
              },
            ),
          ],
          bottom: const TabBar(
            tabs: <Widget>[
              Tab(text: 'Units'),
              Tab(text: 'Requests'),
            ],
          ),
        ),
        body: const TabBarView(children: <Widget>[_UnitsTab(), _RequestsTab()]),
      ),
    );
  }

  void _showRegisterSheet(BuildContext context, WidgetRef ref) {
    final TextEditingController numberController = TextEditingController();
    final TextEditingController volumeController = TextEditingController();
    final TextEditingController expiryController = TextEditingController();
    BloodGroup bloodGroup = BloodGroup.oPositive;
    BloodComponent component = BloodComponent.redCells;

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
                        'Register blood unit',
                        style: Theme.of(sheetContext).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: numberController,
                        decoration: const InputDecoration(
                          labelText: 'Unit number',
                        ),
                      ),
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
                      TextField(
                        controller: volumeController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Volume (ml)',
                        ),
                      ),
                      TextField(
                        controller: expiryController,
                        keyboardType: TextInputType.datetime,
                        decoration: const InputDecoration(
                          labelText: 'Expires (yyyy-mm-dd)',
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () async {
                            await _register(
                              context: sheetContext,
                              ref: ref,
                              unitNumber: numberController.text,
                              bloodGroup: bloodGroup,
                              component: component,
                              volumeMl: int.tryParse(volumeController.text),
                              expiresAt: DateTime.tryParse(
                                expiryController.text.trim(),
                              ),
                            );
                          },
                          child: const Text('Register'),
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

  Future<void> _register({
    required BuildContext context,
    required WidgetRef ref,
    required String unitNumber,
    required BloodGroup bloodGroup,
    required BloodComponent component,
    required int? volumeMl,
    required DateTime? expiresAt,
  }) async {
    final session = ref.read(sessionProvider);
    final String? tenantId = session.tenantId;
    final String? userId = session.user?.userId;
    if (tenantId == null || userId == null) {
      _snack(context, 'Session is not ready.');
      return;
    }
    if (expiresAt == null) {
      _snack(context, 'Enter a valid expiry date.');
      return;
    }
    try {
      final useCase = ref.read(createBloodUnitUseCaseProvider);
      await useCase(
        policy: session.authorization,
        tenantId: tenantId,
        unitNumber: unitNumber,
        bloodGroup: bloodGroup,
        component: component,
        createdBy: userId,
        expiresAt: expiresAt,
        volumeMl: volumeMl,
      );
      ref.invalidate(bloodUnitsProvider);
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    } on NodexError catch (error) {
      if (context.mounted) {
        _snack(context, error.message);
      }
    } catch (_) {
      if (context.mounted) {
        _snack(context, 'The blood unit could not be registered.');
      }
    }
  }

  static void _snack(BuildContext context, String message) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }
}

class _UnitsTab extends ConsumerWidget {
  const _UnitsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<BloodUnit>> units = ref.watch(bloodUnitsProvider);

    return units.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object error, StackTrace _) => _BloodBankListError(
        error: error,
        fallback: 'Blood units could not be loaded.',
        onRetry: () => ref.invalidate(bloodUnitsProvider),
      ),
      data: (List<BloodUnit> value) => value.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No blood units on this device yet.'),
              ),
            )
          : ListView.separated(
              itemCount: value.length,
              separatorBuilder: (BuildContext context, int _) =>
                  const Divider(height: 1),
              itemBuilder: (BuildContext context, int index) {
                final BloodUnit unit = value[index];
                final bool available = unit.status == BloodUnitStatus.available;
                return ListTile(
                  leading: Icon(
                    Icons.bloodtype_outlined,
                    color: available
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  title: Text(unit.unitNumber),
                  subtitle: Text(
                    '${unit.bloodGroup.label} · ${unit.component.label}',
                  ),
                  trailing: Text(unit.status.label),
                  onTap: () => context.push('/blood-bank/units/${unit.id}'),
                );
              },
            ),
    );
  }
}

class _RequestsTab extends ConsumerWidget {
  const _RequestsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<TransfusionRequest>> requests = ref.watch(
      transfusionRequestsProvider,
    );

    return requests.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object error, StackTrace _) => _BloodBankListError(
        error: error,
        fallback: 'Transfusion requests could not be loaded.',
        onRetry: () => ref.invalidate(transfusionRequestsProvider),
      ),
      data: (List<TransfusionRequest> value) => value.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No transfusion requests on this device yet.'),
              ),
            )
          : ListView.separated(
              itemCount: value.length,
              separatorBuilder: (BuildContext context, int _) =>
                  const Divider(height: 1),
              itemBuilder: (BuildContext context, int index) {
                final TransfusionRequest request = value[index];
                return ListTile(
                  leading: Icon(
                    Icons.volunteer_activism_outlined,
                    color: request.isApproved
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  title: Text(
                    '${request.component.label} ×'
                    '${request.unitsRequested}',
                  ),
                  subtitle: Text(
                    '${request.requestedBloodGroup.label} · '
                    '${request.urgency.label}',
                  ),
                  trailing: Text(request.status.label),
                  onTap: () =>
                      context.push('/blood-bank/requests/${request.id}'),
                );
              },
            ),
    );
  }
}

class _BloodBankListError extends StatelessWidget {
  const _BloodBankListError({
    required this.error,
    required this.fallback,
    required this.onRetry,
  });

  final Object error;
  final String fallback;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String message = error is NodexError
        ? (error as NodexError).message
        : fallback;
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
            FilledButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}
