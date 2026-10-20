/// The patient's journey on the patient screen (Module 50).
///
/// The journey is read from the records the device already holds, so it is
/// available offline and in the same place as the rest of the chart. Events
/// are grouped by month, newest first, and each one names the module that
/// holds it so a reader can tell a test from a treatment at a glance.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/timeline/patient_timeline.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// The journey for one patient.
final patientTimelineProvider = FutureProvider.autoDispose
    .family<PatientTimeline, String>((Ref ref, String patientId) async {
      return ref
          .watch(readPatientTimelineUseCaseProvider)
          .call(
            policy: ref.watch(sessionProvider).authorization,
            patientId: patientId,
          );
    });

/// Shows the patient's journey.
class PatientTimelineSection extends ConsumerWidget {
  /// Creates the section.
  const PatientTimelineSection({required this.patientId, super.key});

  /// Patient identifier.
  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<PatientTimeline> timeline = ref.watch(
      patientTimelineProvider(patientId),
    );
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Journey', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        timeline.when(
          loading: () => const LinearProgressIndicator(),
          error: (Object error, StackTrace _) => Text(
            error is NodexError
                ? error.message
                : 'The journey is not available on this device.',
            style: theme.textTheme.bodySmall,
          ),
          data: (PatientTimeline value) {
            if (value.count == 0) {
              return Text(
                'No visits, tests or treatments recorded yet.',
                style: theme.textTheme.bodySmall,
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (final TimelineGroup group in value.groupedByMonth())
                  _MonthGroup(group: group, patientId: patientId),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _MonthGroup extends StatelessWidget {
  const _MonthGroup({required this.group, required this.patientId});

  final TimelineGroup group;
  final String patientId;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Text(group.label, style: theme.textTheme.labelLarge),
        ),
        for (final TimelineEvent event in group.events)
          _TimelineTile(event: event, patientId: patientId, isLast: false),
      ],
    );
  }
}

class _TimelineTile extends StatelessWidget {
  const _TimelineTile({
    required this.event,
    required this.patientId,
    required this.isLast,
  });

  final TimelineEvent event;
  final String patientId;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DateTime local = event.at.toLocal();
    final String when =
        '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/${local.year} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
    final String? route = _routeFor(event);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Column(
            children: <Widget>[
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _iconFor(event.kind),
                  size: 16,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: theme.colorScheme.outlineVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: InkWell(
                onTap: route == null ? null : () => context.go(route),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(event.title, style: theme.textTheme.bodyLarge),
                    Text(when, style: theme.textTheme.bodySmall),
                    if (event.detail != null)
                      Text(
                        event.detail!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The route to the record behind the event, when the module has one.
  String? _routeFor(TimelineEvent event) {
    final String? sourceId = event.sourceId;
    if (sourceId == null) return null;
    return switch (event.kind) {
      TimelineEventKind.outpatientVisit ||
      TimelineEventKind.admission ||
      TimelineEventKind.emergency ||
      TimelineEventKind.telehealth =>
        '/patients/$patientId/encounters/$sourceId',
      TimelineEventKind.labOrder => '/patients/$patientId/lab/$sourceId',
      TimelineEventKind.prescription => '/patients/$patientId/rx/$sourceId',
      TimelineEventKind.discharge => '/patients/$patientId/discharge/$sourceId',
      TimelineEventKind.surgery => null,
    };
  }

  static IconData _iconFor(TimelineEventKind kind) => switch (kind) {
    TimelineEventKind.outpatientVisit => Icons.medical_services_outlined,
    TimelineEventKind.admission => Icons.bed_outlined,
    TimelineEventKind.emergency => Icons.emergency_outlined,
    TimelineEventKind.telehealth => Icons.videocam_outlined,
    TimelineEventKind.surgery => Icons.healing_outlined,
    TimelineEventKind.labOrder => Icons.science_outlined,
    TimelineEventKind.prescription => Icons.medication_outlined,
    TimelineEventKind.discharge => Icons.logout_outlined,
  };
}
