/// Operation theatre entity decoding tests (Module 19).
///
/// Booking state, fitness judgements, and per-case records all decode from
/// snake_case projection rows; a wrong wire value silently reclassifies a
/// clinical state, so every enum and nullable column round trips through the
/// row form.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/domain/ot/ot.dart';

void main() {
  group('enum wire decoding', () {
    test('booking status decodes and flags terminal cases', () {
      expect(
        OtBookingStatus.fromWire('in_progress'),
        OtBookingStatus.inProgress,
      );
      expect(OtBookingStatus.fromWire('completed'), OtBookingStatus.completed);
      expect(OtBookingStatus.fromWire('nope'), OtBookingStatus.scheduled);
      expect(OtBookingStatus.completed.isTerminal, isTrue);
      expect(OtBookingStatus.cancelled.isTerminal, isTrue);
      expect(OtBookingStatus.scheduled.isTerminal, isFalse);
      expect(OtBookingStatus.inProgress.isTerminal, isFalse);
    });

    test('priority decodes and flags emergencies', () {
      expect(OtPriority.fromWire('urgent'), OtPriority.urgent);
      expect(OtPriority.fromWire('emergency'), OtPriority.emergency);
      expect(OtPriority.fromWire('nope'), OtPriority.routine);
      expect(OtPriority.emergency.isEmergency, isTrue);
      expect(OtPriority.routine.isEmergency, isFalse);
    });

    test('fitness decodes and only unfit blocks surgery', () {
      expect(
        OtFitness.fromWire('fit_with_conditions'),
        OtFitness.fitWithConditions,
      );
      expect(OtFitness.fromWire('unfit'), OtFitness.unfit);
      expect(OtFitness.fromWire('nope'), OtFitness.fit);
      expect(OtFitness.fit.allowsSurgery, isTrue);
      expect(OtFitness.fitWithConditions.allowsSurgery, isTrue);
      expect(OtFitness.unfit.allowsSurgery, isFalse);
    });

    test('anesthesia technique decodes every stored value', () {
      expect(OtAnesthesiaType.fromWire('regional'), OtAnesthesiaType.regional);
      expect(OtAnesthesiaType.fromWire('sedation'), OtAnesthesiaType.sedation);
      expect(OtAnesthesiaType.fromWire(''), OtAnesthesiaType.general);
    });

    test('post-op condition decodes and flags critical recovery', () {
      expect(OtPostOpCondition.fromWire('watch'), OtPostOpCondition.watch);
      expect(
        OtPostOpCondition.fromWire('critical'),
        OtPostOpCondition.critical,
      );
      expect(OtPostOpCondition.fromWire(''), OtPostOpCondition.stable);
      expect(OtPostOpCondition.critical.isCritical, isTrue);
      expect(OtPostOpCondition.stable.isCritical, isFalse);
    });
  });

  group('OtBooking.fromRow', () {
    test('decodes a fully-populated booking row', () {
      final DateTime start = DateTime.utc(2026, 9, 20, 9);
      final DateTime end = start.add(const Duration(hours: 2));
      final OtBooking booking = OtBooking.fromRow(<String, Object?>{
        'id': 'booking-1',
        'tenant_id': 'tenant-1',
        'patient_id': 'patient-1',
        'encounter_id': 'enc-1',
        'theatre_room': 'OT 1',
        'procedure_name': 'Appendectomy',
        'scheduled_start': start,
        'scheduled_end': end,
        'surgeon_id': 'doctor-1',
        'anesthesiologist_id': 'doctor-2',
        'status': 'in_progress',
        'priority': 'urgent',
        'cancellation_reason': null,
        'created_by': 'doctor-1',
        'created_at': start,
        'updated_at': start,
      });

      expect(booking.theatreRoom, 'OT 1');
      expect(booking.status, OtBookingStatus.inProgress);
      expect(booking.priority, OtPriority.urgent);
      expect(booking.anesthesiologistId, 'doctor-2');
      expect(booking.isInProgress, isTrue);
      expect(booking.isTerminal, isFalse);
      expect(booking.overlaps(end, end.add(const Duration(hours: 1))), isFalse);
      expect(
        booking.overlaps(
          end.subtract(const Duration(minutes: 1)),
          end.add(const Duration(hours: 1)),
        ),
        isTrue,
      );
    });

    test('clears absent links and carries cancellation reasons', () {
      final DateTime start = DateTime.utc(2026, 9, 20, 9);
      final OtBooking booking = OtBooking.fromRow(<String, Object?>{
        'id': 'booking-2',
        'tenant_id': 'tenant-1',
        'patient_id': 'patient-1',
        'encounter_id': null,
        'theatre_room': 'OT 2',
        'procedure_name': 'Hernia repair',
        'scheduled_start': start,
        'scheduled_end': start.add(const Duration(hours: 1)),
        'surgeon_id': 'doctor-1',
        'anesthesiologist_id': null,
        'status': 'cancelled',
        'priority': 'routine',
        'cancellation_reason': 'Patient unwell.',
        'created_by': 'doctor-1',
        'created_at': start,
        'updated_at': start,
      });

      expect(booking.encounterId, isNull);
      expect(booking.anesthesiologistId, isNull);
      expect(booking.cancellationReason, 'Patient unwell.');
      expect(booking.isTerminal, isTrue);
    });
  });

  group('per-case record decoding', () {
    test('pre-op assessment decodes fitness and ASA class', () {
      final DateTime at = DateTime.utc(2026, 9, 20, 8);
      final OtPreOpAssessment preOp = OtPreOpAssessment.fromRow(
        <String, Object?>{
          'id': 'preop-1',
          'tenant_id': 'tenant-1',
          'booking_id': 'booking-1',
          'patient_id': 'patient-1',
          'assessed_by': 'doctor-1',
          'assessed_at': at,
          'fitness': 'fit_with_conditions',
          'asa_class': 3,
          'notes': 'Controlled hypertension.',
          'created_at': at,
          'updated_at': at,
        },
      );

      expect(preOp.fitness, OtFitness.fitWithConditions);
      expect(preOp.asaClass, 3);
      expect(preOp.fitForSurgery, isTrue);
      expect(
        OtPreOpAssessment.fromRow(<String, Object?>{
          'id': 'preop-2',
          'tenant_id': 'tenant-1',
          'booking_id': 'booking-1',
          'patient_id': 'patient-1',
          'assessed_by': 'doctor-1',
          'assessed_at': at,
          'fitness': 'unfit',
          'asa_class': null,
          'notes': null,
          'created_at': at,
          'updated_at': at,
        }).fitForSurgery,
        isFalse,
      );
    });

    test('anesthesia record flags completion', () {
      final DateTime start = DateTime.utc(2026, 9, 20, 9);
      final OtAnesthesiaRecord open = OtAnesthesiaRecord.fromRow(
        <String, Object?>{
          'id': 'anesthesia-1',
          'tenant_id': 'tenant-1',
          'booking_id': 'booking-1',
          'patient_id': 'patient-1',
          'anesthesia_type': 'general',
          'recorded_by': 'doctor-2',
          'started_at': start,
          'ended_at': null,
          'notes': null,
          'created_at': start,
          'updated_at': start,
        },
      );
      expect(open.isComplete, isFalse);

      final OtAnesthesiaRecord closed = OtAnesthesiaRecord.fromRow(
        <String, Object?>{
          'id': 'anesthesia-1',
          'tenant_id': 'tenant-1',
          'booking_id': 'booking-1',
          'patient_id': 'patient-1',
          'anesthesia_type': 'regional',
          'recorded_by': 'doctor-2',
          'started_at': start,
          'ended_at': start.add(const Duration(hours: 2)),
          'notes': null,
          'created_at': start,
          'updated_at': start,
        },
      );
      expect(closed.isComplete, isTrue);
      expect(closed.endedAt, isNotNull);
    });

    test('procedure log decodes findings and completion', () {
      final DateTime start = DateTime.utc(2026, 9, 20, 9);
      final OtProcedureLog log = OtProcedureLog.fromRow(<String, Object?>{
        'id': 'procedure-1',
        'tenant_id': 'tenant-1',
        'booking_id': 'booking-1',
        'patient_id': 'patient-1',
        'procedure_name': 'Appendectomy',
        'performed_by': 'doctor-1',
        'started_at': start,
        'completed_at': start.add(const Duration(hours: 1)),
        'findings': 'Non-perforated appendix.',
        'created_at': start,
        'updated_at': start,
      });

      expect(log.isComplete, isTrue);
      expect(log.findings, 'Non-perforated appendix.');
    });

    test('post-op record decodes condition, pain score and complications', () {
      final DateTime at = DateTime.utc(2026, 9, 20, 12);
      final OtPostOpRecord postOp = OtPostOpRecord.fromRow(<String, Object?>{
        'id': 'postop-1',
        'tenant_id': 'tenant-1',
        'booking_id': 'booking-1',
        'patient_id': 'patient-1',
        'recorded_by': 'nurse-1',
        'recorded_at': at,
        'condition': 'watch',
        'pain_score': 6,
        'complications': null,
        'notes': 'Recovery ward.',
        'created_at': at,
        'updated_at': at,
      });

      expect(postOp.condition, OtPostOpCondition.watch);
      expect(postOp.painScore, 6);
      expect(postOp.isCritical, isFalse);
      expect(
        OtPostOpRecord.fromRow(<String, Object?>{
          'id': 'postop-2',
          'tenant_id': 'tenant-1',
          'booking_id': 'booking-1',
          'patient_id': 'patient-1',
          'recorded_by': 'nurse-1',
          'recorded_at': at,
          'condition': 'critical',
          'pain_score': null,
          'complications': null,
          'notes': null,
          'created_at': at,
          'updated_at': at,
        }).isCritical,
        isTrue,
      );
    });
  });
}
