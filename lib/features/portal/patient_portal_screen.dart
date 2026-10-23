/// The patient portal screen (Module 05).
///
/// The patient's own view of their record: their appointments, the results
/// that are final, and the medicines they are taking. Nothing preliminary is
/// shown, and nothing belonging to another patient is reachable from here.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/appointments/appointment.dart';
import 'package:nodex_hms/domain/laboratory/lab.dart';
import 'package:nodex_hms/domain/portal/patient_portal.dart';
import 'package:nodex_hms/domain/prescriptions/prescription.dart';
import 'package:nodex_hms/domain/prescriptions/prescription_repository.dart';
import 'package:nodex_hms/domain/session/session_state.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// The patient the portal account reads.
final portalPatientProvider = FutureProvider.autoDispose
    .family<String?, String>((Ref ref, String portalUserId) async {
      return ref.watch(portalRepositoryProvider).resolvePatientId(portalUserId);
    });

/// The patient's appointments.
final portalAppointmentsProvider = FutureProvider.autoDispose
    .family<List<Appointment>, String>((Ref ref, String patientId) async {
      return ref.watch(appointmentRepositoryProvider).listForPatient(patientId);
    });

/// The patient's finalized results.
final portalResultsProvider = FutureProvider.autoDispose
    .family<List<PortalResult>, String>((Ref ref, String patientId) async {
      final List<LabOrder> orders = await ref
          .watch(labRepositoryProvider)
          .listOrdersForPatient(patientId);
      final List<PortalResult> results = <PortalResult>[];
      for (final LabOrder order in orders) {
        final List<LabResult> rows = await ref
            .watch(labRepositoryProvider)
            .listResults(order.id);
        for (final LabResult row in rows) {
          final PortalResult? visible = PortalResult.fromLabResult(row);
          if (visible != null) results.add(visible);
        }
      }
      return results;
    });

/// The patient's active medicines.
final portalMedicationsProvider = FutureProvider.autoDispose
    .family<List<PortalMedication>, String>((Ref ref, String patientId) async {
      final PrescriptionRepository repository = ref.watch(
        prescriptionRepositoryProvider,
      );
      final List<Prescription> prescriptions = await repository
          .listPrescriptionsForPatient(patientId);
      final List<PortalMedication> medications = <PortalMedication>[];
      for (final Prescription prescription in prescriptions) {
        if (prescription.status != PrescriptionStatus.finalized) continue;
        final List<PrescriptionItem> items = await repository.listItems(
          prescription.id,
        );
        for (final PrescriptionItem item in items) {
          final PortalMedication? medication = PortalMedication.fromItem(item);
          if (medication != null) medications.add(medication);
        }
      }
      return medications;
    });

/// The patient portal.
class PatientPortalScreen extends ConsumerWidget {
  /// Creates the screen.
  const PatientPortalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SessionState session = ref.watch(sessionProvider);
    final String? userId = session.user?.userId;
    final ThemeData theme = Theme.of(context);

    if (userId == null) {
      return const Scaffold(body: Center(child: Text('Session is not ready.')));
    }
    if (!session.authorization.can(NodexPermissions.portalAccess)) {
      return Scaffold(
        appBar: AppBar(title: const Text('My health')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'This account is not linked to a patient record yet. Ask the '
              'hospital to link it.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final AsyncValue<String?> patientId = ref.watch(
      portalPatientProvider(userId),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('My health')),
      body: patientId.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace _) => Center(
          child: Text(
            error is NodexError ? error.message : 'The portal is unavailable.',
          ),
        ),
        data: (String? id) {
          if (id == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'This account is not linked to a patient record yet.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              _PortalSection(
                title: 'Appointments',
                child: _AppointmentsList(patientId: id),
              ),
              _PortalSection(
                title: 'Results',
                child: _ResultsList(patientId: id),
              ),
              _PortalSection(
                title: 'Medicines',
                child: _MedicationsList(patientId: id),
              ),
              const SizedBox(height: 16),
              Text(
                'Only results that are final are shown here. A result that is '
                'still being checked will appear once it is signed off.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PortalSection extends StatelessWidget {
  const _PortalSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        child,
      ],
    ),
  );
}

class _AppointmentsList extends ConsumerWidget {
  const _AppointmentsList({required this.patientId});

  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Appointment>> appointments = ref.watch(
      portalAppointmentsProvider(patientId),
    );
    return appointments.when(
      loading: () => const LinearProgressIndicator(),
      error: (Object error, StackTrace _) => const Text('Unavailable.'),
      data: (List<Appointment> values) => values.isEmpty
          ? const Text('No appointments booked.')
          : Column(
              children: values
                  .map(
                    (Appointment appointment) => ListTile(
                      dense: true,
                      leading: const Icon(Icons.event_outlined),
                      title: Text(
                        appointment.scheduledStart
                            .toLocal()
                            .toIso8601String()
                            .substring(0, 16),
                      ),
                      subtitle: Text(appointment.reason ?? 'Visit'),
                    ),
                  )
                  .toList(growable: false),
            ),
    );
  }
}

class _ResultsList extends ConsumerWidget {
  const _ResultsList({required this.patientId});

  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<PortalResult>> results = ref.watch(
      portalResultsProvider(patientId),
    );
    return results.when(
      loading: () => const LinearProgressIndicator(),
      error: (Object error, StackTrace _) => const Text('Unavailable.'),
      data: (List<PortalResult> values) => values.isEmpty
          ? const Text('No final results yet.')
          : Column(
              children: values
                  .map(
                    (PortalResult result) => ListTile(
                      dense: true,
                      leading: const Icon(Icons.science_outlined),
                      title: Text(result.display),
                      subtitle: result.referenceRange == null
                          ? null
                          : Text('Reference ${result.referenceRange}'),
                    ),
                  )
                  .toList(growable: false),
            ),
    );
  }
}

class _MedicationsList extends ConsumerWidget {
  const _MedicationsList({required this.patientId});

  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<PortalMedication>> medications = ref.watch(
      portalMedicationsProvider(patientId),
    );
    return medications.when(
      loading: () => const LinearProgressIndicator(),
      error: (Object error, StackTrace _) => const Text('Unavailable.'),
      data: (List<PortalMedication> values) => values.isEmpty
          ? const Text('No active medicines.')
          : Column(
              children: values
                  .map(
                    (PortalMedication medication) => ListTile(
                      dense: true,
                      leading: const Icon(Icons.medication_outlined),
                      title: Text(medication.display),
                    ),
                  )
                  .toList(growable: false),
            ),
    );
  }
}
