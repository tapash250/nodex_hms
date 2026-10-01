/// Telemedicine entity decoding and enum wire tests (Module 22).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/domain/telemedicine/telemedicine.dart';

void main() {
  group('TeleChannel wire decoding', () {
    test('round-trips every wire value', () {
      for (final TeleChannel channel in TeleChannel.values) {
        expect(TeleChannel.fromWire(channel.wireValue), channel);
      }
    });

    test('falls back to video for unknown values', () {
      expect(TeleChannel.fromWire('holographic'), TeleChannel.video);
    });

    test('labels read for the UI', () {
      expect(TeleChannel.audio.label, 'Audio only');
      expect(TeleChannel.video.label, 'Video');
    });
  });

  group('TeleConsultationStatus wire decoding', () {
    test('round-trips every wire value', () {
      for (final TeleConsultationStatus status
          in TeleConsultationStatus.values) {
        expect(TeleConsultationStatus.fromWire(status.wireValue), status);
      }
    });

    test('decodes the multi-word wire values', () {
      expect(
        TeleConsultationStatus.fromWire('in_call'),
        TeleConsultationStatus.inCall,
      );
      expect(
        TeleConsultationStatus.fromWire('no_show'),
        TeleConsultationStatus.noShow,
      );
    });

    test('falls back to scheduled for unknown values', () {
      expect(
        TeleConsultationStatus.fromWire('ringing'),
        TeleConsultationStatus.scheduled,
      );
    });

    test('classifies the waiting room and call states', () {
      expect(TeleConsultationStatus.scheduled.isScheduled, isTrue);
      expect(TeleConsultationStatus.waiting.isWaiting, isTrue);
      expect(TeleConsultationStatus.inCall.isInCall, isTrue);
      expect(TeleConsultationStatus.waiting.isPreCall, isTrue);
      expect(TeleConsultationStatus.scheduled.isPreCall, isTrue);
      expect(TeleConsultationStatus.inCall.isPreCall, isFalse);
    });

    test('completed, cancelled and no-show are terminal', () {
      expect(TeleConsultationStatus.completed.isTerminal, isTrue);
      expect(TeleConsultationStatus.cancelled.isTerminal, isTrue);
      expect(TeleConsultationStatus.noShow.isTerminal, isTrue);
      expect(TeleConsultationStatus.inCall.isTerminal, isFalse);
      expect(TeleConsultationStatus.waiting.isTerminal, isFalse);
    });
  });

  group('TeleConsultation.fromRow', () {
    test('decodes a completed consultation with its timestamps', () {
      final TeleConsultation visit = TeleConsultation.fromRow(<String, Object?>{
        'id': 'consultation-1',
        'tenant_id': 'tenant-1',
        'patient_id': 'patient-1',
        'encounter_id': 'encounter-1',
        'clinician_id': 'doctor-1',
        'booked_by': 'reception-1',
        'visit_code': 'TEL-001',
        'channel': 'video',
        'status': 'completed',
        'reason': 'Post-op review',
        'scheduled_at': DateTime.utc(2026, 9, 20, 9),
        'waiting_at': DateTime.utc(2026, 9, 20, 9, 2),
        'started_at': DateTime.utc(2026, 9, 20, 9, 5),
        'completed_at': DateTime.utc(2026, 9, 20, 9, 25),
        'cancelled_at': null,
        'cancellation_reason': null,
        'no_show_at': null,
        'created_at': DateTime.utc(2026, 9, 19),
        'updated_at': DateTime.utc(2026, 9, 20, 9, 25),
      });

      expect(visit.channel, TeleChannel.video);
      expect(visit.status, TeleConsultationStatus.completed);
      expect(visit.waitingAt, DateTime.utc(2026, 9, 20, 9, 2));
      expect(visit.startedAt, DateTime.utc(2026, 9, 20, 9, 5));
      expect(visit.completedAt, DateTime.utc(2026, 9, 20, 9, 25));
      expect(visit.isTerminal, isTrue);
      expect(visit.reason, 'Post-op review');
    });

    test('decodes a scheduled consultation with null optionals', () {
      final TeleConsultation visit = TeleConsultation.fromRow(<String, Object?>{
        'id': 'consultation-2',
        'tenant_id': 'tenant-1',
        'patient_id': 'patient-1',
        'encounter_id': null,
        'clinician_id': 'doctor-2',
        'booked_by': 'doctor-2',
        'visit_code': 'TEL-002',
        'channel': 'audio',
        'status': 'scheduled',
        'reason': null,
        'scheduled_at': DateTime.utc(2026, 9, 21, 14),
        'waiting_at': null,
        'started_at': null,
        'completed_at': null,
        'cancelled_at': null,
        'cancellation_reason': null,
        'no_show_at': null,
        'created_at': DateTime.utc(2026, 9, 20),
        'updated_at': DateTime.utc(2026, 9, 20),
      });

      expect(visit.channel, TeleChannel.audio);
      expect(visit.encounterId, isNull);
      expect(visit.reason, isNull);
      expect(visit.waitingAt, isNull);
      expect(visit.isScheduled, isTrue);
      expect(visit.isPreCall, isTrue);
      expect(visit.isTerminal, isFalse);
    });
  });

  group('TeleVitalsOverlay.fromRow', () {
    test('decodes a full reading', () {
      final TeleVitalsOverlay overlay = TeleVitalsOverlay.fromRow(
        <String, Object?>{
          'id': 'overlay-1',
          'tenant_id': 'tenant-1',
          'consultation_id': 'consultation-1',
          'observed_by': 'nurse-1',
          'heart_rate_bpm': 88,
          'spo2_pct': 97.0,
          'temperature_c': 37.2,
          'respiratory_rate': 18,
          'notes': 'Patient comfortable.',
          'observed_at': DateTime.utc(2026, 9, 20, 9, 10),
          'created_at': DateTime.utc(2026, 9, 20, 9, 10),
          'updated_at': DateTime.utc(2026, 9, 20, 9, 10),
        },
      );

      expect(overlay.heartRateBpm, 88);
      expect(overlay.spo2Pct, 97.0);
      expect(overlay.temperatureC, 37.2);
      expect(overlay.respiratoryRate, 18);
      expect(overlay.notes, 'Patient comfortable.');
    });

    test('decodes a partial reading', () {
      final TeleVitalsOverlay overlay = TeleVitalsOverlay.fromRow(
        <String, Object?>{
          'id': 'overlay-2',
          'tenant_id': 'tenant-1',
          'consultation_id': 'consultation-1',
          'observed_by': 'nurse-1',
          'heart_rate_bpm': null,
          'spo2_pct': 94.0,
          'temperature_c': null,
          'respiratory_rate': null,
          'notes': null,
          'observed_at': DateTime.utc(2026, 9, 20, 9, 15),
          'created_at': DateTime.utc(2026, 9, 20, 9, 15),
          'updated_at': DateTime.utc(2026, 9, 20, 9, 15),
        },
      );

      expect(overlay.heartRateBpm, isNull);
      expect(overlay.spo2Pct, 94.0);
      expect(overlay.temperatureC, isNull);
      expect(overlay.notes, isNull);
    });
  });

  group('TeleConsultationArchive.fromRow', () {
    test('decodes an archive with a recording reference', () {
      final TeleConsultationArchive archive = TeleConsultationArchive.fromRow(
        <String, Object?>{
          'id': 'archive-1',
          'tenant_id': 'tenant-1',
          'consultation_id': 'consultation-1',
          'archived_by': 'doctor-1',
          'duration_seconds': 1200,
          'recording_reference': 'object://tele/consultation-1.m4a',
          'transcript_reference': null,
          'consent_recorded': 1,
          'archived_at': DateTime.utc(2026, 9, 20, 10),
          'created_at': DateTime.utc(2026, 9, 20, 10),
          'updated_at': DateTime.utc(2026, 9, 20, 10),
        },
      );

      expect(archive.durationSeconds, 1200);
      expect(archive.consentRecorded, isTrue);
      expect(archive.recordingReference, 'object://tele/consultation-1.m4a');
      expect(archive.transcriptReference, isNull);
    });

    test('decodes a boolean consent flag and a null recording', () {
      final TeleConsultationArchive archive = TeleConsultationArchive.fromRow(
        <String, Object?>{
          'id': 'archive-2',
          'tenant_id': 'tenant-1',
          'consultation_id': 'consultation-2',
          'archived_by': 'doctor-2',
          'duration_seconds': 600,
          'recording_reference': null,
          'transcript_reference': null,
          'consent_recorded': true,
          'archived_at': DateTime.utc(2026, 9, 21, 10),
          'created_at': DateTime.utc(2026, 9, 21, 10),
          'updated_at': DateTime.utc(2026, 9, 21, 10),
        },
      );

      expect(archive.consentRecorded, isTrue);
      expect(archive.recordingReference, isNull);
      expect(archive.durationSeconds, 600);
    });
  });
}
