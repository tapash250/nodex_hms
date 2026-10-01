/// Dietetics & clinical nutrition workflow use cases (Module 21).
///
/// Each write gates on the authorization policy before touching the
/// repository. Assessments need `diet_assessment.write`, authoring a plan and
/// its day menus needs `diet_plan.write`, deciding a plan needs
/// `diet_plan.approve`, and recording what the patient actually ate needs
/// `diet_intake.record`.
library;

import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/nutrition/nutrition.dart';
import 'package:nodex_hms/domain/nutrition/nutrition_repository.dart';
import 'package:uuid/uuid.dart';

/// Records a draft nutrition assessment. Requires `diet_assessment.write`.
final class RecordDietAssessmentUseCase {
  RecordDietAssessmentUseCase({required this._repository});

  final NutritionRepository _repository;

  Future<DietAssessment> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String patientId,
    required String assessedBy,
    required DietAssessmentType assessmentType,
    required String nutritionDiagnosis,
    double? weightKg,
    double? heightCm,
    String? encounterId,
    String? restrictions,
  }) async {
    policy.require(NodexPermissions.dietAssessmentWrite);
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (patientId.isEmpty) {
      fieldErrors['patient_id'] = 'Patient is required.';
    }
    if (assessedBy.isEmpty) {
      fieldErrors['assessed_by'] = 'Assessing clinician is required.';
    }
    if (nutritionDiagnosis.trim().isEmpty) {
      fieldErrors['nutrition_diagnosis'] = 'Nutrition diagnosis is required.';
    }
    if (weightKg != null && (weightKg <= 0 || weightKg > 500)) {
      fieldErrors['weight_kg'] = 'Weight must be between 0 and 500 kg.';
    }
    if (heightCm != null && (heightCm <= 0 || heightCm > 260)) {
      fieldErrors['height_cm'] = 'Height must be between 0 and 260 cm.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Nutrition assessment failed validation.',
        fieldErrors: fieldErrors,
        code: 'diet_assessment_invalid',
      );
    }
    final DietAssessment? open = await _repository.draftAssessmentForPatient(
      patientId,
    );
    if (open != null) {
      throw const AuthorizationError(
        message: 'Finalize or discard the open nutrition assessment first.',
        code: 'diet_assessment_exists',
      );
    }
    final DateTime now = DateTime.now().toUtc();
    final String? cleanRestrictions = restrictions?.trim();
    final DietAssessment assessment = DietAssessment(
      id: const Uuid().v4(),
      tenantId: tenantId,
      patientId: patientId,
      encounterId: encounterId,
      assessedBy: assessedBy,
      assessmentType: assessmentType,
      weightKg: weightKg,
      heightCm: heightCm,
      nutritionDiagnosis: nutritionDiagnosis.trim(),
      restrictions: cleanRestrictions == null || cleanRestrictions.isEmpty
          ? null
          : cleanRestrictions,
      status: DietAssessmentStatus.draft,
      assessedAt: now,
      createdAt: now,
      updatedAt: now,
    );
    return _repository.upsertAssessment(assessment);
  }
}

/// Finalizes a draft assessment. Requires `diet_assessment.write`.
final class FinalizeDietAssessmentUseCase {
  FinalizeDietAssessmentUseCase({required this._repository});

  final NutritionRepository _repository;

  Future<DietAssessment> call({
    required AuthorizationPolicy policy,
    required DietAssessment original,
    required String finalizedBy,
  }) async {
    policy.require(NodexPermissions.dietAssessmentWrite);
    if (!original.isDraft) {
      throw const AuthorizationError(
        message: 'Finalized nutrition assessments are immutable.',
        code: 'diet_assessment_not_draft',
      );
    }
    final DateTime now = DateTime.now().toUtc();
    return _repository.upsertAssessment(
      DietAssessment(
        id: original.id,
        tenantId: original.tenantId,
        patientId: original.patientId,
        encounterId: original.encounterId,
        assessedBy: original.assessedBy,
        assessmentType: original.assessmentType,
        weightKg: original.weightKg,
        heightCm: original.heightCm,
        nutritionDiagnosis: original.nutritionDiagnosis,
        restrictions: original.restrictions,
        status: DietAssessmentStatus.finalized,
        assessedAt: original.assessedAt,
        finalizedAt: now,
        finalizedBy: finalizedBy,
        createdAt: original.createdAt,
        updatedAt: now,
      ),
    );
  }
}

/// Authors a draft seven-day meal plan for a finalized assessment. Requires
/// `diet_plan.write`.
final class DraftDietMealPlanUseCase {
  DraftDietMealPlanUseCase({required this._repository});

  final NutritionRepository _repository;

  Future<DietMealPlan> call({
    required AuthorizationPolicy policy,
    required DietAssessment assessment,
    required String name,
    required DietPlanSource planSource,
    String? generatedBy,
  }) async {
    policy.require(NodexPermissions.dietPlanWrite);
    if (!assessment.isFinalized) {
      throw const AuthorizationError(
        message: 'Finalize the nutrition assessment before planning meals.',
        code: 'diet_assessment_required',
      );
    }
    if (name.trim().isEmpty) {
      throw const ValidationError(
        message: 'A meal plan needs a name.',
        code: 'diet_plan_invalid',
      );
    }
    if (planSource.isAiGenerated &&
        (generatedBy == null || generatedBy.trim().isEmpty)) {
      throw const ValidationError(
        message: 'A generated plan must record the generating clinician.',
        code: 'diet_plan_generation_required',
      );
    }
    final DietMealPlan? existing = await _repository.planForAssessment(
      assessment.id,
    );
    if (existing != null) {
      throw const AuthorizationError(
        message: 'This assessment already carries a meal plan.',
        code: 'diet_plan_exists',
      );
    }
    final DateTime now = DateTime.now().toUtc();
    final String? generator = generatedBy?.trim();
    final DietMealPlan plan = DietMealPlan(
      id: const Uuid().v4(),
      tenantId: assessment.tenantId,
      patientId: assessment.patientId,
      assessmentId: assessment.id,
      name: name.trim(),
      planSource: planSource,
      cycleDays: dietCycleDays,
      status: DietMealPlanStatus.draft,
      generatedBy: generator == null || generator.isEmpty ? null : generator,
      generatedAt: planSource.isAiGenerated ? now : null,
      createdAt: now,
      updatedAt: now,
    );
    return _repository.upsertPlan(plan);
  }
}

/// Adds one day's menu to a draft plan. Requires `diet_plan.write`.
final class AddDietMealPlanDayUseCase {
  AddDietMealPlanDayUseCase({required this._repository});

  final NutritionRepository _repository;

  Future<DietMealPlanDay> call({
    required AuthorizationPolicy policy,
    required DietMealPlan plan,
    required int dayNumber,
    required String breakfast,
    required String lunch,
    required String dinner,
    required int caloriesKcal,
    String? snacks,
  }) async {
    policy.require(NodexPermissions.dietPlanWrite);
    if (!plan.isDraft) {
      throw const AuthorizationError(
        message: 'Decided meal plans are frozen.',
        code: 'diet_plan_closed',
      );
    }
    final Map<String, String> fieldErrors = <String, String>{};
    if (dayNumber < 1 || dayNumber > dietCycleDays) {
      fieldErrors['day_number'] = 'Day must be 1 to $dietCycleDays.';
    }
    if (breakfast.trim().isEmpty) {
      fieldErrors['breakfast'] = 'Breakfast is required.';
    }
    if (lunch.trim().isEmpty) {
      fieldErrors['lunch'] = 'Lunch is required.';
    }
    if (dinner.trim().isEmpty) {
      fieldErrors['dinner'] = 'Dinner is required.';
    }
    if (caloriesKcal <= 0 || caloriesKcal > 5000) {
      fieldErrors['calories_kcal'] = 'Daily calories must be 1 to 5000 kcal.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Meal plan day failed validation.',
        fieldErrors: fieldErrors,
        code: 'diet_plan_day_invalid',
      );
    }
    final DietMealPlanDay? taken = await _repository.planDay(
      plan.id,
      dayNumber,
    );
    if (taken != null) {
      throw const AuthorizationError(
        message: 'That day is already planned.',
        code: 'diet_plan_day_exists',
      );
    }
    final DateTime now = DateTime.now().toUtc();
    final String? cleanSnacks = snacks?.trim();
    final DietMealPlanDay day = DietMealPlanDay(
      id: const Uuid().v4(),
      tenantId: plan.tenantId,
      mealPlanId: plan.id,
      dayNumber: dayNumber,
      breakfast: breakfast.trim(),
      lunch: lunch.trim(),
      dinner: dinner.trim(),
      snacks: cleanSnacks == null || cleanSnacks.isEmpty ? null : cleanSnacks,
      caloriesKcal: caloriesKcal,
      createdAt: now,
      updatedAt: now,
    );
    return _repository.upsertPlanDay(day);
  }
}

/// Approves a complete seven-day plan. Requires `diet_plan.approve`.
final class ApproveDietMealPlanUseCase {
  ApproveDietMealPlanUseCase({required this._repository});

  final NutritionRepository _repository;

  Future<DietMealPlan> call({
    required AuthorizationPolicy policy,
    required DietMealPlan plan,
    required String approvedBy,
  }) async {
    policy.require(NodexPermissions.dietPlanApprove);
    if (!plan.isDraft) {
      throw const AuthorizationError(
        message: 'Decided meal plans cannot transition.',
        code: 'diet_plan_closed',
      );
    }
    final List<DietMealPlanDay> days = await _repository.planDays(plan.id);
    if (days.length != dietCycleDays) {
      throw const AuthorizationError(
        message: 'Approve a plan only once all seven days are planned.',
        code: 'diet_plan_incomplete',
      );
    }
    final DateTime now = DateTime.now().toUtc();
    return _repository.upsertPlan(
      DietMealPlan(
        id: plan.id,
        tenantId: plan.tenantId,
        patientId: plan.patientId,
        assessmentId: plan.assessmentId,
        name: plan.name,
        planSource: plan.planSource,
        cycleDays: plan.cycleDays,
        status: DietMealPlanStatus.approved,
        generatedBy: plan.generatedBy,
        generatedAt: plan.generatedAt,
        approvedBy: approvedBy,
        approvedAt: now,
        createdAt: plan.createdAt,
        updatedAt: now,
      ),
    );
  }
}

/// Rejects a draft plan with a reason. Requires `diet_plan.approve`.
final class RejectDietMealPlanUseCase {
  RejectDietMealPlanUseCase({required this._repository});

  final NutritionRepository _repository;

  Future<DietMealPlan> call({
    required AuthorizationPolicy policy,
    required DietMealPlan plan,
    required String rejectedBy,
    required String reason,
  }) async {
    policy.require(NodexPermissions.dietPlanApprove);
    if (!plan.isDraft) {
      throw const AuthorizationError(
        message: 'Decided meal plans cannot transition.',
        code: 'diet_plan_closed',
      );
    }
    if (reason.trim().isEmpty) {
      throw const ValidationError(
        message: 'Rejecting a meal plan requires a reason.',
        code: 'diet_rejection_reason_required',
      );
    }
    final DateTime now = DateTime.now().toUtc();
    return _repository.upsertPlan(
      DietMealPlan(
        id: plan.id,
        tenantId: plan.tenantId,
        patientId: plan.patientId,
        assessmentId: plan.assessmentId,
        name: plan.name,
        planSource: plan.planSource,
        cycleDays: plan.cycleDays,
        status: DietMealPlanStatus.rejected,
        generatedBy: plan.generatedBy,
        generatedAt: plan.generatedAt,
        rejectedBy: rejectedBy,
        rejectedAt: now,
        rejectionReason: reason.trim(),
        createdAt: plan.createdAt,
        updatedAt: now,
      ),
    );
  }
}

/// Records the portion of a planned meal the patient took. Requires
/// `diet_intake.record`.
final class RecordDietIntakeLogUseCase {
  RecordDietIntakeLogUseCase({required this._repository});

  final NutritionRepository _repository;

  Future<DietIntakeLog> call({
    required AuthorizationPolicy policy,
    required DietMealPlan plan,
    required DietMealPlanDay day,
    required DietMealSlot mealSlot,
    required int portionConsumedPct,
    required String recordedBy,
  }) async {
    policy.require(NodexPermissions.dietIntakeRecord);
    if (!plan.isApproved) {
      throw const AuthorizationError(
        message: 'Intake is recorded against an approved meal plan.',
        code: 'diet_plan_not_approved',
      );
    }
    if (day.mealPlanId != plan.id) {
      throw const ValidationError(
        message: 'That day belongs to a different meal plan.',
        code: 'diet_plan_day_mismatch',
      );
    }
    if (portionConsumedPct < 0 || portionConsumedPct > 100) {
      throw const ValidationError(
        message: 'Portion consumed must be 0 to 100 percent.',
        fieldErrors: <String, String>{
          'portion_consumed_pct': 'Expected 0 to 100.',
        },
        code: 'diet_intake_invalid',
      );
    }
    final DateTime now = DateTime.now().toUtc();
    final DietIntakeLog log = DietIntakeLog(
      id: const Uuid().v4(),
      tenantId: plan.tenantId,
      patientId: plan.patientId,
      mealPlanDayId: day.id,
      mealSlot: mealSlot,
      portionConsumedPct: portionConsumedPct,
      recordedBy: recordedBy,
      recordedAt: now,
      createdAt: now,
      updatedAt: now,
    );
    return _repository.upsertIntakeLog(log);
  }
}
