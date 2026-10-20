/// Timeline repository (Module 50).
///
/// The journey is read from the modules that hold the care, not from a table
/// of its own: there is no second record to fall out of step with the first.
library;

import 'package:nodex_hms/core/errors/error_mapper.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/domain/appointments/appointment_repository.dart';
import 'package:nodex_hms/domain/discharge/discharge_repository.dart';
import 'package:nodex_hms/domain/encounters/encounter_repository.dart';
import 'package:nodex_hms/domain/laboratory/lab_repository.dart';
import 'package:nodex_hms/domain/ot/ot_repository.dart';
import 'package:nodex_hms/domain/prescriptions/prescription_repository.dart';
import 'package:nodex_hms/domain/timeline/patient_timeline.dart';

/// Reads a patient's journey.
abstract interface class TimelineRepository {
  /// The journey for one patient, newest event first.
  Future<PatientTimeline> readTimeline(String patientId);
}

/// Reads the journey from the clinical modules.
final class DefaultTimelineRepository implements TimelineRepository {
  /// Creates a repository over the clinical modules.
  const DefaultTimelineRepository({
    required this.encounters,
    required this.lab,
    required this.prescriptions,
    required this.appointments,
    required this.discharge,
    required this.theatre,
    required this.logger,
  });

  static const String _module = 'domain.timeline';

  final EncounterRepository encounters;
  final LabRepository lab;
  final PrescriptionRepository prescriptions;
  final AppointmentRepository appointments;
  final DischargeRepository discharge;
  final OtRepository theatre;
  final NodexLogger logger;

  @override
  Future<PatientTimeline> readTimeline(String patientId) async {
    try {
      // The parts are read together: a journey that showed the visit but not
      // the prescription written at it would be a misleading picture.
      final PatientTimeline timeline = buildPatientTimeline(
        encounters: await encounters.listForPatient(patientId),
        appointments: await appointments.listForPatient(patientId),
        labOrders: await lab.listOrdersForPatient(patientId),
        prescriptions: await prescriptions.listPrescriptionsForPatient(
          patientId,
        ),
        discharges: await discharge.listForPatient(patientId),
        surgeries: await theatre.bookingsForPatient(patientId),
      );
      logger.info(
        _module,
        'Patient journey read from the local projection.',
        operation: 'timeline.read',
        outcome: 'ok',
      );
      return timeline;
    } on Object catch (error, stackTrace) {
      if (error is NodexError) rethrow;
      final NodexError mapped = NodexErrorMapper.map(
        error,
        operation: 'timeline.read',
      );
      logger.error(
        _module,
        'Timeline repository failure.',
        operation: 'timeline.read',
        outcome: 'failed',
        errorCode: mapped.code,
        stackTrace: stackTrace,
      );
      throw mapped;
    }
  }
}
