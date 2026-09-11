/// Master Patient Index search and registration screens (Module 10).
///
/// Search resolves against the encrypted local projection, so the registration
/// desk keeps working with no connectivity. Registration writes locally first;
/// the upload queue carries the row to the server, where (tenant_id, mrn)
/// uniqueness is enforced finally. A locally unknown duplicate MRN therefore
/// surfaces as a rejected upload in sync diagnostics, never as silent success.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/patients/patient.dart';
import 'package:nodex_hms/domain/session/session_state.dart';
import 'package:nodex_hms/features/patients/patients_controller.dart';
import 'package:nodex_hms/features/patients/register_patient_sheet.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// Patient search screen: the MPI landing surface.
class PatientSearchScreen extends ConsumerStatefulWidget {
  /// Creates the search screen.
  const PatientSearchScreen({super.key});

  @override
  ConsumerState<PatientSearchScreen> createState() =>
      _PatientSearchScreenState();
}

class _PatientSearchScreenState extends ConsumerState<PatientSearchScreen> {
  final TextEditingController _queryController = TextEditingController();

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<List<Patient>> patients = ref.watch(patientSearchProvider);
    final SessionState session = ref.watch(sessionProvider);
    final bool canRegister = session.authorization.can(
      NodexPermissions.patientWrite,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Patients'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => ref.read(patientSearchProvider.notifier).refresh(),
          ),
        ],
      ),
      floatingActionButton: canRegister
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.person_add),
              label: const Text('Register'),
              onPressed: () => _openRegistration(context),
            )
          : null,
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SearchBar(
              controller: _queryController,
              hintText: 'Search by MRN, name or phone',
              leading: const Icon(Icons.search),
              trailing: <Widget>[
                if (_queryController.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    tooltip: 'Clear search',
                    onPressed: () {
                      _queryController.clear();
                      ref.read(patientSearchProvider.notifier).search('');
                      setState(() {});
                    },
                  ),
              ],
              onChanged: (_) => setState(() {}),
              onSubmitted: (String value) =>
                  ref.read(patientSearchProvider.notifier).search(value),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                session.connectivity.isOnline
                    ? 'Searching this device\u2019s authorized records'
                    : 'Offline — searching records held on this device',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          Expanded(
            child: patients.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (Object error, StackTrace _) => _SearchError(
                error: error,
                onRetry: () =>
                    ref.read(patientSearchProvider.notifier).refresh(),
              ),
              data: (List<Patient> results) {
                if (results.isEmpty) {
                  return _EmptySearch(
                    hasQuery: _queryController.text.trim().isNotEmpty,
                    canRegister: canRegister,
                    onRegister: () => _openRegistration(context),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: results.length,
                  separatorBuilder: (BuildContext context, int index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (BuildContext context, int index) {
                    final Patient patient = results[index];
                    return _PatientCard(patient: patient);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openRegistration(BuildContext context) async {
    final bool? registered = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) => const RegisterPatientSheet(),
    );
    if (registered ?? false) {
      await ref.read(patientSearchProvider.notifier).refresh();
    }
  }
}

class _PatientCard extends StatelessWidget {
  const _PatientCard({required this.patient});

  final Patient patient;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: CircleAvatar(
          child: Text(_initials(patient), style: theme.textTheme.titleMedium),
        ),
        title: Text(patient.displayName),
        subtitle: Text(
          'MRN ${patient.mrn} · ${patient.ageAt()}y · ${patient.gender.wireValue}',
        ),
        trailing: patient.isActive
            ? const Icon(Icons.chevron_right)
            : const Chip(
                label: Text('Merged'),
                visualDensity: VisualDensity.compact,
              ),
        onTap: () => context.go('/patients/${patient.id}'),
      ),
    );
  }

  static String _initials(Patient patient) {
    final String first = patient.firstName.trim();
    final String last = patient.lastName.trim();
    final String a = first.isEmpty ? '?' : first[0].toUpperCase();
    final String b = last.isEmpty ? '' : last[0].toUpperCase();
    return '$a$b';
  }
}

class _EmptySearch extends StatelessWidget {
  const _EmptySearch({
    required this.hasQuery,
    required this.canRegister,
    required this.onRegister,
  });

  final bool hasQuery;
  final bool canRegister;
  final VoidCallback onRegister;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              Icons.person_search_outlined,
              size: 56,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              hasQuery ? 'No matching patients' : 'No patients yet',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              hasQuery
                  ? 'Check the spelling, or register the patient if this is a new record. Another device may hold a record not yet replicated here.'
                  : 'Registered patients in this tenant will appear here once replicated.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (canRegister) ...<Widget>[
              const SizedBox(height: 24),
              FilledButton.icon(
                icon: const Icon(Icons.person_add),
                label: const Text('Register patient'),
                onPressed: onRegister,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SearchError extends StatelessWidget {
  const _SearchError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String message = error is NodexError
        ? (error as NodexError).message
        : 'Patient search is unavailable. The local clinical database may not be ready.';
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
