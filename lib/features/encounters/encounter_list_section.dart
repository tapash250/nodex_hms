/// Encounter list section embedded in the patient detail screen (Module 16).
///
/// Shows the longitudinal encounter history for one patient with a start action.
/// Tapping an encounter opens the editor. Signed encounters display their
/// frozen state with amendment counts; in-progress ones invite documentation.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/encounters/encounter.dart';
import 'package:nodex_hms/domain/patients/patient.dart';
import 'package:nodex_hms/domain/session/session_state.dart';
import 'package:nodex_hms/features/encounters/encounters_controller.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// Encounter history section for [patient].
class EncounterListSection extends ConsumerWidget {
  /// Creates the section.
  const EncounterListSection({required this.patient, super.key});

  /// The patient whose encounters are shown.
  final Patient patient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final SessionState session = ref.watch(sessionProvider);
    final bool canWrite = session.authorization.can(
      NodexPermissions.encounterWrite,
    );
    final AsyncValue<List<ClinicalEncounter>> encounters = ref.watch(
      encountersForPatientProvider(patient.id),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text('Encounters', style: theme.textTheme.titleMedium),
            ),
            if (canWrite)
              TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Start'),
                onPressed: () => _startEncounter(context, ref),
              ),
          ],
        ),
        const SizedBox(height: 8),
        encounters.when(
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
                    : 'Encounter history is unavailable.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ),
          data: (List<ClinicalEncounter> list) {
            if (list.isEmpty) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'No encounters recorded. The first encounter starts the '
                    'longitudinal record this module — and every downstream '
                    'module — builds on.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              );
            }
            return Column(
              children: <Widget>[
                for (final ClinicalEncounter encounter in list)
                  _EncounterCard(encounter: encounter),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _startEncounter(BuildContext context, WidgetRef ref) async {
    final SessionState session = ref.read(sessionProvider);
    final String? tenantId = session.tenantId;
    final String? userId = session.user?.userId;
    if (tenantId == null || userId == null) {
      return;
    }

    final EncounterType? type = await showDialog<EncounterType>(
      context: context,
      builder: (BuildContext context) => SimpleDialog(
        title: const Text('Encounter type'),
        children: <Widget>[
          for (final EncounterType t in EncounterType.values)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(t),
              child: Text(t.label),
            ),
        ],
      ),
    );
    if (type == null) {
      return;
    }

    try {
      final String encounterId = await ref
          .read(startEncounterUseCaseProvider)
          .call(
            policy: session.authorization,
            tenantId: tenantId,
            patientId: patient.id,
            attendingPhysicianId: userId,
            encounterType: type,
            createdBy: userId,
          );
      ref.invalidate(encountersForPatientProvider(patient.id));
      if (context.mounted) {
        context.go('/patients/${patient.id}/encounters/$encounterId');
      }
    } on NodexError catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }
}

class _EncounterCard extends StatelessWidget {
  const _EncounterCard({required this.encounter});

  final ClinicalEncounter encounter;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final (IconData icon, Color color) = switch (encounter.status) {
      EncounterStatus.planned => (
        Icons.event_outlined,
        theme.colorScheme.onSurfaceVariant,
      ),
      EncounterStatus.inProgress => (
        Icons.edit_note_outlined,
        theme.colorScheme.primary,
      ),
      EncounterStatus.signedAndLocked => (
        Icons.lock_outline,
        theme.colorScheme.tertiary,
      ),
      EncounterStatus.amended => (
        Icons.history_outlined,
        theme.colorScheme.tertiary,
      ),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(
          '${encounter.encounterType.label} · ${encounter.status.label}',
        ),
        subtitle: Text(
          encounter.assessment?.trim().isNotEmpty ?? false
              ? encounter.assessment!.trim().split('\n').first
              : 'No assessment documented yet',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.go(
          '/patients/${encounter.patientId}/encounters/${encounter.id}',
        ),
      ),
    );
  }
}
