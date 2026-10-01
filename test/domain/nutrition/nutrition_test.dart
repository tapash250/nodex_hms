/// Clinical nutrition entity decoding and enum wire tests (Module 21).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/domain/nutrition/nutrition.dart';

void main() {
  group('diet cycle', () {
    test('a plan cycle is a full week', () {
      expect(dietCycleDays, 7);
    });
  });

  group('DietAssessmentType wire decoding', () {
    test('round-trips every wire value', () {
      for (final DietAssessmentType type in DietAssessmentType.values) {
        expect(DietAssessmentType.fromWire(type.wireValue), type);
      }
    });

    test('falls back to initial for unknown values', () {
      expect(
        DietAssessmentType.fromWire('follow_up'),
        DietAssessmentType.initial,
      );
    });
  });

  group('DietAssessmentStatus wire decoding', () {
    test('round-trips every wire value', () {
      for (final DietAssessmentStatus status in DietAssessmentStatus.values) {
        expect(DietAssessmentStatus.fromWire(status.wireValue), status);
      }
    });

    test('classifies draft and finalized', () {
      expect(DietAssessmentStatus.draft.isDraft, isTrue);
      expect(DietAssessmentStatus.draft.isTerminal, isFalse);
      expect(DietAssessmentStatus.finalized.isFinalized, isTrue);
      expect(DietAssessmentStatus.finalized.isTerminal, isTrue);
    });

    test('falls back to draft for unknown values', () {
      expect(
        DietAssessmentStatus.fromWire('superseded'),
        DietAssessmentStatus.draft,
      );
    });
  });

  group('DietPlanSource wire decoding', () {
    test('round-trips every wire value', () {
      for (final DietPlanSource source in DietPlanSource.values) {
        expect(DietPlanSource.fromWire(source.wireValue), source);
      }
    });

    test('flags generated plans as needing approval', () {
      expect(DietPlanSource.aiGenerated.isAiGenerated, isTrue);
      expect(DietPlanSource.clinicianAuthored.isAiGenerated, isFalse);
    });
  });

  group('DietMealPlanStatus wire decoding', () {
    test('round-trips every wire value', () {
      for (final DietMealPlanStatus status in DietMealPlanStatus.values) {
        expect(DietMealPlanStatus.fromWire(status.wireValue), status);
      }
    });

    test('decisions are terminal', () {
      expect(DietMealPlanStatus.draft.isTerminal, isFalse);
      expect(DietMealPlanStatus.approved.isApproved, isTrue);
      expect(DietMealPlanStatus.approved.isTerminal, isTrue);
      expect(DietMealPlanStatus.rejected.isTerminal, isTrue);
    });
  });

  group('DietMealSlot wire decoding', () {
    test('round-trips every wire value', () {
      for (final DietMealSlot slot in DietMealSlot.values) {
        expect(DietMealSlot.fromWire(slot.wireValue), slot);
      }
    });

    test('falls back to breakfast for unknown values', () {
      expect(DietMealSlot.fromWire('supper'), DietMealSlot.breakfast);
    });
  });

  group('DietAssessment.fromRow', () {
    test('decodes a finalized assessment with anthropometrics', () {
      final DietAssessment assessment = DietAssessment.fromRow(
        <String, Object?>{
          'id': 'assessment-1',
          'tenant_id': 'tenant-1',
          'patient_id': 'patient-1',
          'encounter_id': 'encounter-1',
          'assessed_by': 'doctor-1',
          'assessment_type': 'reassessment',
          'weight_kg': 72.5,
          'height_cm': 168.0,
          'nutrition_diagnosis': 'Protein-energy malnutrition.',
          'restrictions': 'Renal diet',
          'status': 'finalized',
          'assessed_at': DateTime.utc(2026, 9, 20, 9),
          'finalized_at': DateTime.utc(2026, 9, 20, 10),
          'finalized_by': 'doctor-1',
          'created_at': DateTime.utc(2026, 9, 20, 9),
          'updated_at': DateTime.utc(2026, 9, 20, 10),
        },
      );

      expect(assessment.assessmentType, DietAssessmentType.reassessment);
      expect(assessment.weightKg, 72.5);
      expect(assessment.heightCm, 168.0);
      expect(assessment.restrictions, 'Renal diet');
      expect(assessment.isFinalized, isTrue);
      expect(assessment.finalizedBy, 'doctor-1');
    });

    test('decodes a draft assessment without optional values', () {
      final DietAssessment assessment = DietAssessment.fromRow(
        <String, Object?>{
          'id': 'assessment-2',
          'tenant_id': 'tenant-1',
          'patient_id': 'patient-1',
          'encounter_id': null,
          'assessed_by': 'doctor-2',
          'assessment_type': 'initial',
          'weight_kg': null,
          'height_cm': null,
          'nutrition_diagnosis': 'Well nourished.',
          'restrictions': null,
          'status': 'draft',
          'assessed_at': DateTime.utc(2026, 9, 21, 9),
          'finalized_at': null,
          'finalized_by': null,
          'created_at': DateTime.utc(2026, 9, 21, 9),
          'updated_at': DateTime.utc(2026, 9, 21, 9),
        },
      );

      expect(assessment.encounterId, isNull);
      expect(assessment.weightKg, isNull);
      expect(assessment.heightCm, isNull);
      expect(assessment.restrictions, isNull);
      expect(assessment.finalizedAt, isNull);
      expect(assessment.isDraft, isTrue);
    });
  });

  group('DietMealPlan.fromRow', () {
    test('decodes an approved generated plan', () {
      final DietMealPlan plan = DietMealPlan.fromRow(<String, Object?>{
        'id': 'plan-1',
        'tenant_id': 'tenant-1',
        'patient_id': 'patient-1',
        'assessment_id': 'assessment-1',
        'name': 'Renal recovery week',
        'plan_source': 'ai_generated',
        'cycle_days': 7,
        'status': 'approved',
        'generated_by': 'doctor-1',
        'generated_at': DateTime.utc(2026, 9, 20, 11),
        'approved_by': 'doctor-2',
        'approved_at': DateTime.utc(2026, 9, 20, 12),
        'rejected_by': null,
        'rejected_at': null,
        'rejection_reason': null,
        'created_at': DateTime.utc(2026, 9, 20, 11),
        'updated_at': DateTime.utc(2026, 9, 20, 12),
      });

      expect(plan.planSource.isAiGenerated, isTrue);
      expect(plan.cycleDays, 7);
      expect(plan.isApproved, isTrue);
      expect(plan.approvedBy, 'doctor-2');
      expect(plan.rejectionReason, isNull);
    });

    test('decodes a rejected authored plan', () {
      final DietMealPlan plan = DietMealPlan.fromRow(<String, Object?>{
        'id': 'plan-2',
        'tenant_id': 'tenant-1',
        'patient_id': 'patient-1',
        'assessment_id': 'assessment-1',
        'name': 'Low sodium week',
        'plan_source': 'clinician_authored',
        'cycle_days': 7,
        'status': 'rejected',
        'generated_by': null,
        'generated_at': null,
        'approved_by': null,
        'approved_at': null,
        'rejected_by': 'doctor-2',
        'rejected_at': DateTime.utc(2026, 9, 20, 13),
        'rejection_reason': 'Exceeds the prescribed potassium limit.',
        'created_at': DateTime.utc(2026, 9, 20, 11),
        'updated_at': DateTime.utc(2026, 9, 20, 13),
      });

      expect(plan.isApproved, isFalse);
      expect(plan.isTerminal, isTrue);
      expect(plan.rejectionReason, 'Exceeds the prescribed potassium limit.');
      expect(plan.generatedBy, isNull);
    });
  });

  group('DietMealPlanDay.fromRow', () {
    test('decodes a day menu', () {
      final DietMealPlanDay day = DietMealPlanDay.fromRow(<String, Object?>{
        'id': 'day-1',
        'tenant_id': 'tenant-1',
        'meal_plan_id': 'plan-1',
        'day_number': 3,
        'breakfast': 'Oat porridge with milk',
        'lunch': 'Grilled chicken and rice',
        'dinner': 'Lentil soup with bread',
        'snacks': 'Apple',
        'calories_kcal': 2100,
        'created_at': DateTime.utc(2026, 9, 20, 11),
        'updated_at': DateTime.utc(2026, 9, 20, 11),
      });

      expect(day.dayNumber, 3);
      expect(day.caloriesKcal, 2100);
      expect(day.snacks, 'Apple');
    });

    test('tolerates a null snack column', () {
      final DietMealPlanDay day = DietMealPlanDay.fromRow(<String, Object?>{
        'id': 'day-2',
        'tenant_id': 'tenant-1',
        'meal_plan_id': 'plan-1',
        'day_number': 4,
        'breakfast': 'Eggs',
        'lunch': 'Fish and vegetables',
        'dinner': 'Khichdi',
        'snacks': null,
        'calories_kcal': 1900.0,
        'created_at': DateTime.utc(2026, 9, 20, 11),
        'updated_at': DateTime.utc(2026, 9, 20, 11),
      });

      expect(day.snacks, isNull);
      expect(day.caloriesKcal, 1900);
    });
  });

  group('DietIntakeLog.fromRow', () {
    test('decodes a portion record', () {
      final DietIntakeLog log = DietIntakeLog.fromRow(<String, Object?>{
        'id': 'intake-1',
        'tenant_id': 'tenant-1',
        'patient_id': 'patient-1',
        'meal_plan_day_id': 'day-1',
        'meal_slot': 'lunch',
        'portion_consumed_pct': 75,
        'recorded_by': 'nurse-1',
        'recorded_at': DateTime.utc(2026, 9, 21, 13),
        'created_at': DateTime.utc(2026, 9, 21, 13),
        'updated_at': DateTime.utc(2026, 9, 21, 13),
      });

      expect(log.mealSlot, DietMealSlot.lunch);
      expect(log.portionConsumedPct, 75);
      expect(log.mealPlanDayId, 'day-1');
    });
  });
}
