/// Clinical nutrition presentation providers (Module 21).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/nutrition/nutrition.dart';
import 'package:nodex_hms/domain/nutrition/nutrition_repository.dart';

/// Meal plan detail bundle for the nutrition screen.
final class MealPlanDetail {
  /// Creates a bundle.
  const MealPlanDetail({
    required this.plan,
    required this.days,
    required this.assessment,
  });

  /// The plan itself.
  final DietMealPlan plan;

  /// Day menus of the cycle, ordered by day.
  final List<DietMealPlanDay> days;

  /// The assessment the plan was authored against.
  final DietAssessment? assessment;
}

/// Nutrition assessments for one patient.
final dietAssessmentsForPatientProvider = FutureProvider.autoDispose
    .family<List<DietAssessment>, String>((Ref ref, String patientId) async {
      return ref
          .watch(nutritionRepositoryProvider)
          .assessmentsForPatient(patientId);
    });

/// Meal plans for one patient.
final dietPlansForPatientProvider = FutureProvider.autoDispose
    .family<List<DietMealPlan>, String>((Ref ref, String patientId) async {
      return ref.watch(nutritionRepositoryProvider).plansForPatient(patientId);
    });

/// One meal plan with its day menus and originating assessment.
final mealPlanDetailProvider = FutureProvider.autoDispose
    .family<MealPlanDetail, String>((Ref ref, String planId) async {
      final NutritionRepository repository = ref.watch(
        nutritionRepositoryProvider,
      );
      final DietMealPlan? plan = await repository.planById(planId);
      if (plan == null) {
        throw const PersistenceError(
          message: 'This meal plan is not available on this device.',
          code: 'diet_plan_not_found_locally',
        );
      }
      return MealPlanDetail(
        plan: plan,
        days: await repository.planDays(planId),
        assessment: await repository.assessmentById(plan.assessmentId),
      );
    });
