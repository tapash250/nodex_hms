/// ER list of open visits with triage intake actions (Module 05).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/er/er.dart';
import 'package:nodex_hms/domain/patients/patient.dart';
import 'package:nodex_hms/features/er/er_controller.dart';
import 'package:nodex_hms/features/patients/patients_controller.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// List screen for open ER visits.
class ErListScreen extends ConsumerStatefulWidget {
  const ErListScreen({super.key});

  @override
  ConsumerState<ErListScreen> createState() => _ErListScreenState();
}

class _ErListScreenState extends ConsumerState<ErListScreen> {
  Future<void> _refresh() async {
    ref.invalidate(openErVisitsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visits = ref.watch(openErVisitsProvider);
    final session = ref.watch(sessionProvider);
    final canRecordTriage = session.authorization.can(
      NodexPermissions.triageWrite,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency'),
        actions: [
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: visits.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace _) =>
            _ErListError(error: error, onRetry: _refresh),
        data: (List<ErVisit> openVisits) {
          if (openVisits.isEmpty) {
            return Center(
              child: Text(
                'No open ER visits.',
                style: theme.textTheme.bodyLarge,
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.builder(
              itemCount: openVisits.length,
              itemBuilder: (context, index) {
                final visit = openVisits[index];
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  child: ListTile(
                    leading: const Icon(Icons.emergency),
                    title: Text('Visit ${visit.id.substring(0, 8)}'),
                    subtitle: Text(
                      [
                        visit.status.label,
                        visit.arrivalMode?.label,
                      ].whereType<String>().join(' · '),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/er/visits/${visit.id}'),
                  ),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: canRecordTriage
          ? FloatingActionButton.extended(
              onPressed: _pickPatient,
              icon: const Icon(Icons.health_and_safety),
              label: const Text('Record triage'),
            )
          : null,
    );
  }

  /// Opens a bottom sheet to pick the patient for a new triage assessment.
  Future<void> _pickPatient() async {
    final TextEditingController search = TextEditingController();
    String query = '';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheet) {
            final AsyncValue<List<Patient>> results = ref.watch(
              patientSearchProvider,
            );

            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.7,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: TextField(
                        controller: search,
                        decoration: const InputDecoration(
                          labelText: 'Search patients',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (String value) {
                          setSheet(() => query = value);
                          ref
                              .read(patientSearchProvider.notifier)
                              .search(value);
                        },
                      ),
                    ),
                    Expanded(
                      child: results.when(
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (Object error, StackTrace _) => Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              error is NodexError
                                  ? error.message
                                  : 'Patients could not be loaded.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                        data: (List<Patient> patients) {
                          if (patients.isEmpty) {
                            return Center(
                              child: Text(
                                query.isEmpty
                                    ? 'Search for a patient to begin triage.'
                                    : 'No patients match "$query".',
                              ),
                            );
                          }
                          return ListView.builder(
                            itemCount: patients.length,
                            itemBuilder: (BuildContext context, int index) {
                              final Patient patient = patients[index];
                              return ListTile(
                                leading: const Icon(Icons.person_outline),
                                title: Text(patient.displayName),
                                subtitle: Text(patient.id),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () {
                                  Navigator.of(context).pop();
                                  context.push(
                                    '/er/triage/new?patientId=${patient.id}',
                                  );
                                },
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _ErListError extends StatelessWidget {
  const _ErListError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final message = switch (error) {
      final NodexError e => e.message,
      _ => 'Could not load open ER visits.',
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
