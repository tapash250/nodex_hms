/// The clinical dashboard (Module 04).
///
/// The three lists a clinician opens at the start of a shift, read from the
/// assignments and the records the device already holds.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/app/widgets/clinical_widgets.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/appointments/appointment.dart';
import 'package:nodex_hms/domain/clinical_dashboard/doctor_assignment.dart';
import 'package:nodex_hms/domain/patients/patient.dart';
import 'package:nodex_hms/domain/session/session_state.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// The patients the signed-in clinician is responsible for.
final myAssignmentsProvider = FutureProvider.autoDispose
    .family<List<DoctorAssignment>, String>((Ref ref, String doctorId) async {
      return ref
          .watch(listDoctorAssignmentsUseCaseProvider)
          .call(
            policy: ref.watch(sessionProvider).authorization,
            doctorId: doctorId,
          );
    });

/// The clinic list for the signed-in clinician.
final myClinicProvider = FutureProvider.autoDispose<List<Appointment>>((
  Ref ref,
) async {
  final String? userId = ref.watch(sessionProvider).user?.userId;
  if (userId == null) return const <Appointment>[];
  return ref
      .watch(appointmentRepositoryProvider)
      .listForProvider(providerId: userId, from: DateTime.now());
});

/// One patient's name, read from the local projection.
final assignedPatientProvider = FutureProvider.autoDispose
    .family<Patient?, String>((Ref ref, String patientId) async {
      return ref.watch(patientRepositoryProvider).getPatient(patientId);
    });

/// The attending's cockpit.
class ClinicalDashboardScreen extends ConsumerWidget {
  /// Creates the screen.
  const ClinicalDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SessionState session = ref.watch(sessionProvider);
    final String? userId = session.user?.userId;
    final ThemeData theme = Theme.of(context);

    if (userId == null) {
      return const Scaffold(body: Center(child: Text('Session is not ready.')));
    }

    final AsyncValue<List<DoctorAssignment>> assignments = ref.watch(
      myAssignmentsProvider(userId),
    );
    final AsyncValue<List<Appointment>> clinic = ref.watch(myClinicProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My patients')),
      body: assignments.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace _) => Center(
          child: Text(
            error is NodexError
                ? error.message
                : 'The clinical dashboard is unavailable.',
          ),
        ),
        data: (List<DoctorAssignment> values) {
          final List<DoctorAssignment> active = values
              .where((DoctorAssignment a) => a.isActive)
              .toList(growable: false);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('Under my care', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text('${active.length} active assignment(s)'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              for (final DoctorAssignment assignment in active)
                _AssignmentCard(assignment: assignment),
              const SizedBox(height: 12),
              Text('Today in clinic', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              clinic.when(
                loading: () => const LinearProgressIndicator(),
                error: (Object error, StackTrace _) => Text(
                  error is NodexError
                      ? error.message
                      : 'The clinic list is unavailable.',
                  style: theme.textTheme.bodySmall,
                ),
                data: (List<Appointment> appointments) => appointments.isEmpty
                    ? Text(
                        'No clinic booked.',
                        style: theme.textTheme.bodySmall,
                      )
                    : Column(
                        children: appointments
                            .map(
                              (Appointment appointment) => Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  leading: const Icon(Icons.event_outlined),
                                  title: Text(appointment.appointmentCode),
                                  subtitle: Text(
                                    '${appointment.visitType.wireValue} · '
                                    '${appointment.scheduledStart.toLocal().toIso8601String().substring(11, 16)}'
                                    '${appointment.reason != null ? ' · ${appointment.reason}' : ''}',
                                  ),
                                ),
                              ),
                            )
                            .toList(growable: false),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AssignmentCard extends ConsumerWidget {
  const _AssignmentCard({required this.assignment});

  final DoctorAssignment assignment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Patient?> patient = ref.watch(
      assignedPatientProvider(assignment.patientId),
    );
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.person_outline),
        title: Text(
          patient.value?.displayName ?? 'Patient ${assignment.patientId}',
        ),
        subtitle: Text(
          assignment.assignedAt == null
              ? assignment.assignmentType.label
              : '${assignment.assignmentType.label} · since '
                    '${assignment.assignedAt!.toLocal().toIso8601String().substring(0, 10)}',
        ),
        trailing: ClinicalStatusBadge(
          label: assignment.assignmentType.label,
          tone: assignment.assignmentType == AssignmentType.primaryAttending
              ? ClinicalTone.info
              : ClinicalTone.neutral,
        ),
        onTap: () => context.go('/patients/${assignment.patientId}'),
      ),
    );
  }
}
