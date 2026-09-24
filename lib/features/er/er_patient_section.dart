/// ER section embedded in the patient detail screen (Module 05).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/er/er.dart';
import 'package:nodex_hms/features/er/er_controller.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// Shows a patient's ER visits and lets authorized staff open a new one.
class ErPatientSection extends ConsumerWidget {
  const ErPatientSection({super.key, required this.patientId});

  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final records = ref.watch(erVisitsForPatientProvider(patientId));
    final triages = ref.watch(triageForPatientProvider(patientId));
    final session = ref.watch(sessionProvider);
    final canOpen = session.authorization.can(NodexPermissions.erVisitWrite);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Emergency', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        records.when(
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
                    : 'Could not load ER visits.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ),
          data: (List<ErVisit> visits) {
            if (visits.isEmpty) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'No ER visits recorded.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              );
            }

            return Card(
              child: Column(
                children: [
                  for (final visit in visits.take(5))
                    ListTile(
                      leading: const Icon(Icons.emergency),
                      title: Text(visit.status.label),
                      subtitle: Text(visit.arrivalMode?.label ?? '—'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/er/visits/${visit.id}'),
                    ),
                ],
              ),
            );
          },
        ),
        if (canOpen) ...[
          const SizedBox(height: 8),
          triages.when(
            loading: () => const SizedBox.shrink(),
            error: (Object _, StackTrace _) => const SizedBox.shrink(),
            data: (List<TriageAssessment> list) {
              final latest = list.isEmpty ? null : list.last;
              return Row(
                children: [
                  Expanded(
                    child: Text(
                      latest == null
                          ? 'Record triage before opening an ER visit.'
                          : 'Open a new ER visit for this patient.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  if (latest == null)
                    TextButton.icon(
                      onPressed: () =>
                          context.push('/er/triage/new?patientId=$patientId'),
                      icon: const Icon(Icons.assignment),
                      label: const Text('Record triage'),
                    )
                  else
                    TextButton.icon(
                      onPressed: () async {
                        final useCase = ref.read(openErVisitUseCaseProvider);
                        final session = ref.read(sessionProvider);
                        final tenantId = session.tenantId;
                        final userId = session.user?.userId;
                        if (tenantId == null || userId == null) {
                          return;
                        }
                        await useCase(
                          policy: session.authorization,
                          tenantId: tenantId,
                          patientId: patientId,
                          triageId: latest.id,
                          providerId: userId,
                          arrivalMode: ArrivalMode.walkIn,
                        );
                        ref.invalidate(erVisitsForPatientProvider(patientId));
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Open'),
                    ),
                ],
              );
            },
          ),
        ],
      ],
    );
  }
}
