/// Physiotherapy entity decoding and enum wire tests (Module 20).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/domain/physio/physio.dart';

void main() {
  group('PhysioSessionType wire decoding', () {
    test('round-trips every wire value', () {
      for (final PhysioSessionType type in PhysioSessionType.values) {
        expect(PhysioSessionType.fromWire(type.wireValue), type);
      }
    });

    test('falls back to therapy for unknown values', () {
      expect(
        PhysioSessionType.fromWire('hydrotherapy'),
        PhysioSessionType.therapy,
      );
    });

    test('labels read for the UI', () {
      expect(PhysioSessionType.assessment.label, 'Assessment');
      expect(PhysioSessionType.therapy.label, 'Therapy');
      expect(PhysioSessionType.reassessment.label, 'Reassessment');
    });
  });

  group('PhysioSessionStatus wire decoding', () {
    test('round-trips every wire value', () {
      for (final PhysioSessionStatus status in PhysioSessionStatus.values) {
        expect(PhysioSessionStatus.fromWire(status.wireValue), status);
      }
    });

    test('decodes the in-progress wire value', () {
      expect(
        PhysioSessionStatus.fromWire('in_progress'),
        PhysioSessionStatus.inProgress,
      );
    });

    test('falls back to scheduled for unknown values', () {
      expect(
        PhysioSessionStatus.fromWire('paused'),
        PhysioSessionStatus.scheduled,
      );
    });

    test('classifies lifecycle states', () {
      expect(PhysioSessionStatus.scheduled.isScheduled, isTrue);
      expect(PhysioSessionStatus.inProgress.isRunning, isTrue);
      expect(PhysioSessionStatus.completed.isCompleted, isTrue);
      expect(PhysioSessionStatus.completed.isTerminal, isTrue);
      expect(PhysioSessionStatus.cancelled.isTerminal, isTrue);
      expect(PhysioSessionStatus.scheduled.isTerminal, isFalse);
      expect(PhysioSessionStatus.inProgress.isTerminal, isFalse);
    });
  });

  group('PhysioPlanStatus wire decoding', () {
    test('round-trips every wire value', () {
      for (final PhysioPlanStatus status in PhysioPlanStatus.values) {
        expect(PhysioPlanStatus.fromWire(status.wireValue), status);
      }
    });

    test('falls back to active for unknown values', () {
      expect(PhysioPlanStatus.fromWire('paused'), PhysioPlanStatus.active);
    });

    test('only active plans are editable', () {
      expect(PhysioPlanStatus.active.isActive, isTrue);
      expect(PhysioPlanStatus.active.isTerminal, isFalse);
      expect(PhysioPlanStatus.completed.isTerminal, isTrue);
      expect(PhysioPlanStatus.stopped.isTerminal, isTrue);
    });
  });

  group('PhysioSession.fromRow', () {
    test('decodes a fully populated row', () {
      final PhysioSession session = PhysioSession.fromRow(<String, Object?>{
        'id': 'session-1',
        'tenant_id': 'tenant-1',
        'patient_id': 'patient-1',
        'encounter_id': 'encounter-1',
        'physiotherapist_id': 'user-1',
        'session_code': 'PHY-001',
        'session_type': 'therapy',
        'body_area': 'Left knee',
        'status': 'in_progress',
        'scheduled_at': DateTime.utc(2026, 9, 20, 9),
        'started_at': DateTime.utc(2026, 9, 20, 9, 5),
        'completed_at': null,
        'cancelled_at': null,
        'cancellation_reason': null,
        'equipment_used': 'Resistance bands',
        'created_at': DateTime.utc(2026, 9, 19),
        'updated_at': DateTime.utc(2026, 9, 20, 9, 5),
      });

      expect(session.id, 'session-1');
      expect(session.encounterId, 'encounter-1');
      expect(session.sessionType, PhysioSessionType.therapy);
      expect(session.status, PhysioSessionStatus.inProgress);
      expect(session.isRunning, isTrue);
      expect(session.startedAt, DateTime.utc(2026, 9, 20, 9, 5));
      expect(session.completedAt, isNull);
      expect(session.equipmentUsed, 'Resistance bands');
    });

    test('decodes null optional columns', () {
      final PhysioSession session = PhysioSession.fromRow(<String, Object?>{
        'id': 'session-2',
        'tenant_id': 'tenant-1',
        'patient_id': 'patient-1',
        'encounter_id': null,
        'physiotherapist_id': 'user-2',
        'session_code': 'PHY-002',
        'session_type': 'assessment',
        'body_area': 'Lumbar spine',
        'status': 'scheduled',
        'scheduled_at': DateTime.utc(2026, 9, 21, 14),
        'started_at': null,
        'completed_at': null,
        'cancelled_at': null,
        'cancellation_reason': null,
        'equipment_used': null,
        'created_at': DateTime.utc(2026, 9, 19),
        'updated_at': DateTime.utc(2026, 9, 19),
      });

      expect(session.encounterId, isNull);
      expect(session.startedAt, isNull);
      expect(session.equipmentUsed, isNull);
      expect(session.isScheduled, isTrue);
      expect(session.isTerminal, isFalse);
    });
  });

  group('PhysioExercisePlan.fromRow', () {
    test('decodes regimen counts and status', () {
      final PhysioExercisePlan plan = PhysioExercisePlan.fromRow(
        <String, Object?>{
          'id': 'plan-1',
          'tenant_id': 'tenant-1',
          'patient_id': 'patient-1',
          'session_id': 'session-1',
          'prescribed_by': 'doctor-1',
          'exercise_name': 'Straight leg raise',
          'sets_count': 3,
          'reps_count': 12,
          'frequency_per_week': 5,
          'duration_weeks': 6,
          'instructions': 'Slow and controlled.',
          'status': 'active',
          'created_at': DateTime.utc(2026, 9, 20),
          'updated_at': DateTime.utc(2026, 9, 20),
        },
      );

      expect(plan.setsCount, 3);
      expect(plan.repsCount, 12);
      expect(plan.frequencyPerWeek, 5);
      expect(plan.durationWeeks, 6);
      expect(plan.status, PhysioPlanStatus.active);
      expect(plan.isActive, isTrue);
      expect(plan.sessionId, 'session-1');
    });

    test('tolerates numeric counts and null optionals', () {
      final PhysioExercisePlan plan = PhysioExercisePlan.fromRow(
        <String, Object?>{
          'id': 'plan-2',
          'tenant_id': 'tenant-1',
          'patient_id': 'patient-1',
          'session_id': null,
          'prescribed_by': 'doctor-1',
          'exercise_name': 'Heel slides',
          'sets_count': 2.0,
          'reps_count': 10.0,
          'frequency_per_week': 3,
          'duration_weeks': 4,
          'instructions': null,
          'status': 'stopped',
          'created_at': DateTime.utc(2026, 9, 20),
          'updated_at': DateTime.utc(2026, 9, 21),
        },
      );

      expect(plan.setsCount, 2);
      expect(plan.sessionId, isNull);
      expect(plan.instructions, isNull);
      expect(plan.isFinished, isTrue);
      expect(plan.isActive, isFalse);
    });
  });

  group('PhysioRecoveryNote.fromRow', () {
    test('decodes content and pain score', () {
      final PhysioRecoveryNote note = PhysioRecoveryNote.fromRow(
        <String, Object?>{
          'id': 'note-1',
          'tenant_id': 'tenant-1',
          'session_id': 'session-1',
          'recorded_by': 'nurse-1',
          'content': 'Tolerated the full set without guarding.',
          'pain_score': 4,
          'recorded_at': DateTime.utc(2026, 9, 20, 10),
          'created_at': DateTime.utc(2026, 9, 20, 10),
          'updated_at': DateTime.utc(2026, 9, 20, 10),
        },
      );

      expect(note.painScore, 4);
      expect(note.sessionId, 'session-1');
      expect(note.recordedBy, 'nurse-1');
    });

    test('tolerates a null pain score', () {
      final PhysioRecoveryNote note = PhysioRecoveryNote.fromRow(
        <String, Object?>{
          'id': 'note-2',
          'tenant_id': 'tenant-1',
          'session_id': 'session-1',
          'recorded_by': 'nurse-1',
          'content': 'Home exercise plan reviewed.',
          'pain_score': null,
          'recorded_at': DateTime.utc(2026, 9, 21),
          'created_at': DateTime.utc(2026, 9, 21),
          'updated_at': DateTime.utc(2026, 9, 21),
        },
      );

      expect(note.painScore, isNull);
    });
  });
}
