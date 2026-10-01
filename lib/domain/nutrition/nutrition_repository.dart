/// Clinical nutrition repository contract and PowerSync-backed implementation
/// (Module 21).
library;

import 'package:nodex_hms/core/errors/error_mapper.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/nutrition/nutrition.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';

/// Read and write access to nutrition assessments, meal plans, plan days and
/// intake logs.
abstract interface class NutritionRepository {
  /// One assessment by id, or null.
  Future<DietAssessment?> assessmentById(String id);

  /// Assessments for one patient, newest first.
  Future<List<DietAssessment>> assessmentsForPatient(String patientId);

  /// The open (draft) assessment for a patient, or null.
  Future<DietAssessment?> draftAssessmentForPatient(String patientId);

  /// Inserts or updates an assessment row.
  Future<DietAssessment> upsertAssessment(DietAssessment assessment);

  /// One meal plan by id, or null.
  Future<DietMealPlan?> planById(String id);

  /// The plan authored for an assessment, or null.
  Future<DietMealPlan?> planForAssessment(String assessmentId);

  /// Meal plans for one patient, newest first.
  Future<List<DietMealPlan>> plansForPatient(String patientId);

  /// Inserts or updates a meal plan row.
  Future<DietMealPlan> upsertPlan(DietMealPlan plan);

  /// The day menu for a plan and day number, or null.
  Future<DietMealPlanDay?> planDay(String planId, int dayNumber);

  /// Day menus of a plan, ordered by day.
  Future<List<DietMealPlanDay>> planDays(String planId);

  /// Inserts or updates a plan day row.
  Future<DietMealPlanDay> upsertPlanDay(DietMealPlanDay day);

  /// Intake logs recorded against a plan day, oldest first.
  Future<List<DietIntakeLog>> intakeLogsForDay(String planDayId);

  /// Inserts or updates an intake log row.
  Future<DietIntakeLog> upsertIntakeLog(DietIntakeLog log);
}

/// Default repository over the encrypted local projection.
final class DefaultNutritionRepository implements NutritionRepository {
  const DefaultNutritionRepository({
    required this._store,
    required this._logger,
  });

  static const String _module = 'domain.nutrition';

  final PatientLocalStore _store;
  final NodexLogger _logger;

  @override
  Future<DietAssessment?> assessmentById(String id) async {
    try {
      final Map<String, Object?>? row = await _store.getById(
        LocalTables.dietAssessments,
        id,
      );
      return row == null ? null : DietAssessment.fromRow(row);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'nutrition.assessmentById');
    }
  }

  @override
  Future<List<DietAssessment>> assessmentsForPatient(String patientId) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select * from ${LocalTables.dietAssessments} where patient_id = ? '
        'order by assessed_at desc',
        <Object?>[patientId],
      );
      return rows.map(DietAssessment.fromRow).toList();
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'nutrition.assessmentsForPatient');
    }
  }

  @override
  Future<DietAssessment?> draftAssessmentForPatient(String patientId) async {
    try {
      final List<DietAssessment> assessments = await assessmentsForPatient(
        patientId,
      );
      for (final DietAssessment assessment in assessments) {
        if (assessment.isDraft) return assessment;
      }
      return null;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'nutrition.draftAssessmentForPatient');
    }
  }

  @override
  Future<DietAssessment> upsertAssessment(DietAssessment assessment) async {
    try {
      final Map<String, Object?>? existing = await _store.getById(
        LocalTables.dietAssessments,
        assessment.id,
      );
      final Map<String, Object?> changes = <String, Object?>{
        'patient_id': assessment.patientId,
        'encounter_id': assessment.encounterId,
        'assessed_by': assessment.assessedBy,
        'assessment_type': assessment.assessmentType.wireValue,
        'weight_kg': assessment.weightKg,
        'height_cm': assessment.heightCm,
        'nutrition_diagnosis': assessment.nutritionDiagnosis,
        'restrictions': assessment.restrictions,
        'status': assessment.status.wireValue,
        'assessed_at': assessment.assessedAt,
        'finalized_at': assessment.finalizedAt,
        'finalized_by': assessment.finalizedBy,
        'updated_at': assessment.updatedAt,
      };
      if (existing == null) {
        await _store.insert(LocalTables.dietAssessments, <String, Object?>{
          ...changes,
          'id': assessment.id,
          'tenant_id': assessment.tenantId,
          'created_at': assessment.createdAt,
        });
      } else {
        await _store.update(
          LocalTables.dietAssessments,
          assessment.id,
          changes,
        );
      }
      return assessment;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'nutrition.upsertAssessment');
    }
  }

  @override
  Future<DietMealPlan?> planById(String id) async {
    try {
      final Map<String, Object?>? row = await _store.getById(
        LocalTables.dietMealPlans,
        id,
      );
      return row == null ? null : DietMealPlan.fromRow(row);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'nutrition.planById');
    }
  }

  @override
  Future<DietMealPlan?> planForAssessment(String assessmentId) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select * from ${LocalTables.dietMealPlans} where assessment_id = ?',
        <Object?>[assessmentId],
      );
      if (rows.isEmpty) return null;
      return DietMealPlan.fromRow(rows.first);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'nutrition.planForAssessment');
    }
  }

  @override
  Future<List<DietMealPlan>> plansForPatient(String patientId) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select * from ${LocalTables.dietMealPlans} where patient_id = ? '
        'order by created_at desc',
        <Object?>[patientId],
      );
      return rows.map(DietMealPlan.fromRow).toList();
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'nutrition.plansForPatient');
    }
  }

  @override
  Future<DietMealPlan> upsertPlan(DietMealPlan plan) async {
    try {
      final Map<String, Object?>? existing = await _store.getById(
        LocalTables.dietMealPlans,
        plan.id,
      );
      final Map<String, Object?> changes = <String, Object?>{
        'patient_id': plan.patientId,
        'assessment_id': plan.assessmentId,
        'name': plan.name,
        'plan_source': plan.planSource.wireValue,
        'cycle_days': plan.cycleDays,
        'status': plan.status.wireValue,
        'generated_by': plan.generatedBy,
        'generated_at': plan.generatedAt,
        'approved_by': plan.approvedBy,
        'approved_at': plan.approvedAt,
        'rejected_by': plan.rejectedBy,
        'rejected_at': plan.rejectedAt,
        'rejection_reason': plan.rejectionReason,
        'updated_at': plan.updatedAt,
      };
      if (existing == null) {
        await _store.insert(LocalTables.dietMealPlans, <String, Object?>{
          ...changes,
          'id': plan.id,
          'tenant_id': plan.tenantId,
          'created_at': plan.createdAt,
        });
      } else {
        await _store.update(LocalTables.dietMealPlans, plan.id, changes);
      }
      return plan;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'nutrition.upsertPlan');
    }
  }

  @override
  Future<DietMealPlanDay?> planDay(String planId, int dayNumber) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select * from ${LocalTables.dietMealPlanDays} '
        'where meal_plan_id = ? and day_number = ?',
        <Object?>[planId, dayNumber],
      );
      if (rows.isEmpty) return null;
      return DietMealPlanDay.fromRow(rows.first);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'nutrition.planDay');
    }
  }

  @override
  Future<List<DietMealPlanDay>> planDays(String planId) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select * from ${LocalTables.dietMealPlanDays} '
        'where meal_plan_id = ? order by day_number asc',
        <Object?>[planId],
      );
      return rows.map(DietMealPlanDay.fromRow).toList();
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'nutrition.planDays');
    }
  }

  @override
  Future<DietMealPlanDay> upsertPlanDay(DietMealPlanDay day) async {
    try {
      final Map<String, Object?>? existing = await _store.getById(
        LocalTables.dietMealPlanDays,
        day.id,
      );
      final Map<String, Object?> changes = <String, Object?>{
        'meal_plan_id': day.mealPlanId,
        'day_number': day.dayNumber,
        'breakfast': day.breakfast,
        'lunch': day.lunch,
        'dinner': day.dinner,
        'snacks': day.snacks,
        'calories_kcal': day.caloriesKcal,
        'updated_at': day.updatedAt,
      };
      if (existing == null) {
        await _store.insert(LocalTables.dietMealPlanDays, <String, Object?>{
          ...changes,
          'id': day.id,
          'tenant_id': day.tenantId,
          'created_at': day.createdAt,
        });
      } else {
        await _store.update(LocalTables.dietMealPlanDays, day.id, changes);
      }
      return day;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'nutrition.upsertPlanDay');
    }
  }

  @override
  Future<List<DietIntakeLog>> intakeLogsForDay(String planDayId) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select * from ${LocalTables.dietIntakeLogs} where meal_plan_day_id = ? '
        'order by recorded_at asc',
        <Object?>[planDayId],
      );
      return rows.map(DietIntakeLog.fromRow).toList();
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'nutrition.intakeLogsForDay');
    }
  }

  @override
  Future<DietIntakeLog> upsertIntakeLog(DietIntakeLog log) async {
    try {
      final Map<String, Object?>? existing = await _store.getById(
        LocalTables.dietIntakeLogs,
        log.id,
      );
      final Map<String, Object?> changes = <String, Object?>{
        'patient_id': log.patientId,
        'meal_plan_day_id': log.mealPlanDayId,
        'meal_slot': log.mealSlot.wireValue,
        'portion_consumed_pct': log.portionConsumedPct,
        'recorded_by': log.recordedBy,
        'recorded_at': log.recordedAt,
        'updated_at': log.updatedAt,
      };
      if (existing == null) {
        await _store.insert(LocalTables.dietIntakeLogs, <String, Object?>{
          ...changes,
          'id': log.id,
          'tenant_id': log.tenantId,
          'created_at': log.createdAt,
        });
      } else {
        await _store.update(LocalTables.dietIntakeLogs, log.id, changes);
      }
      return log;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'nutrition.upsertIntakeLog');
    }
  }

  Never _mapped(Object error, StackTrace stackTrace, String operation) {
    if (error is NodexError) throw error;
    final NodexError mapped = NodexErrorMapper.map(error, operation: operation);
    _logger.error(
      _module,
      'Clinical nutrition repository failure.',
      operation: operation,
      outcome: 'failed',
      errorCode: mapped.code,
      stackTrace: stackTrace,
    );
    throw mapped;
  }
}
