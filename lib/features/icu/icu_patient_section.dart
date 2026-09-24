/// ICU section embedded in the patient detail screen (Module 06).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/icu/icu.dart';
import 'package:nodex_hms/features/icu/icu_controller.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// Shows a patient's ICU beds and recent vitals/handovers.
class IcuPatientSection extends ConsumerWidget {
  const IcuPatientSection({super.key, required this.patientId});

  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final beds = ref.watch(icuBedsForPatientProvider(patientId));
    final vitals = ref.watch(icuVitalsForPatientProvider(patientId));
    final handovers = ref.watch(icuHandoversForPatientProvider(patientId));
    final session = ref.watch(sessionProvider);
    final canAssign = session.authorization.can(NodexPermissions.icuBedAssign);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Critical Care', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        beds.when(
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
                    : 'Could not load ICU beds.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ),
          data: (List<IcuBed> list) {
            if (list.isEmpty) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'No ICU beds assigned.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              );
            }
            return Card(
              child: Column(
                children: [
                  for (final bed in list)
                    ListTile(
                      leading: const Icon(Icons.local_hospital),
                      title: Text(bed.status.label),
                      subtitle: Text(
                        bed.ventilatorId != null
                            ? 'Ventilator ${bed.ventilatorId}'
                            : 'Bed ${bed.bedId}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/icu/beds/${bed.id}'),
                    ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        Text('Recent vitals', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        vitals.when(
          loading: () => const LinearProgressIndicator(),
          error: (Object error, StackTrace _) => Text(
            error is NodexError ? error.message : 'Could not load vitals.',
            style: theme.textTheme.bodySmall,
          ),
          data: (List<IcuVitals> list) {
            if (list.isEmpty) {
              return Text(
                'No vitals recorded.',
                style: theme.textTheme.bodySmall,
              );
            }
            final latest = list.first;
            return Text(
              [
                if (latest.heartRate != null) 'HR ${latest.heartRate}',
                if (latest.spo2 != null) 'SpO₂ ${latest.spo2}%',
                if (latest.respiratoryRate != null)
                  'RR ${latest.respiratoryRate}',
                if (latest.temperatureCelsius != null)
                  '${latest.temperatureCelsius}°C',
              ].join(' · '),
              style: theme.textTheme.bodySmall,
            );
          },
        ),
        const SizedBox(height: 12),
        Text('Latest handover', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        handovers.when(
          loading: () => const LinearProgressIndicator(),
          error: (Object error, StackTrace _) => Text(
            error is NodexError ? error.message : 'Could not load handovers.',
            style: theme.textTheme.bodySmall,
          ),
          data: (List<IcuNursingHandover> list) {
            if (list.isEmpty) {
              return Text(
                'No handovers recorded.',
                style: theme.textTheme.bodySmall,
              );
            }
            final latest = list.first;
            return Text(
              latest.summary,
              style: theme.textTheme.bodySmall,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            );
          },
        ),
        if (canAssign) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Assign an ICU bed for this patient.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              TextButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.add),
                label: const Text('Assign'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
