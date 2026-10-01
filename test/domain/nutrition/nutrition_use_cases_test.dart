/// Tests for the clinical nutrition use-case gates (Module 21).
///
/// Assessments need `diet_assessment.write`, authoring a plan and its day
/// menus needs `diet_plan.write`, approving or rejecting needs
/// `diet_plan.approve`, and intake needs `diet_intake.record`. A finalized
/// assessment is frozen, a plan can only be approved once all seven days are
/// planned, and intake is recorded only against an approved plan.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/authorization_snapshot.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/domain/nutrition/nutrition.dart';
import 'package:nodex_hms/domain/nutrition/nutrition_repository.dart';
import 'package:nodex_hms/domain/nutrition/nutrition_use_cases.dart';

import 'nutrition_repository_test.dart' show FakeNutritionStore;

/// Builds a policy holding exactly [permissions].
AuthorizationPolicy policyWith(Set<String> permissions) {
  final DateTime issuedAt = DateTime.now().toUtc();
  return AuthorizationPolicy(
    snapshot: AuthorizationSnapshot(
      snapshotId: 'snapshot-1',
      tenantId: 'tenant-1',
      userId: 'clinician-1',
      deviceId: 'device-1',
      revision: 1,
      issuedAt: issuedAt,
      expiresAt: issuedAt.add(const Duration(days: 30)),
      payloadDigest: 'digest',
      roles: const <String>{NodexRoles.medicalOfficer},
      permissions: permissions,
      offlinePermissions: permissions,
      facilityIds: const <String>{},
      departmentIds: const <String>{},
      wardIds: const <String>{},
    ),
    connectivity: ConnectivityState.online,
  );
}

void main() {
  late FakeNutritionStore store;
  late DefaultNutritionRepository repository;
  late RecordDietAssessmentUseCase recordAssessment;
  late FinalizeDietAssessmentUseCase finalizeAssessment;
  late DraftDietMealPlanUseCase draftPlan;
  late AddDietMealPlanDayUseCase addDay;
  late ApproveDietMealPlanUseCase approvePlan;
  late RejectDietMealPlanUseCase rejectPlan;
  late RecordDietIntakeLogUseCase recordIntake;

  const Set<String> assessor = <String>{NodexPermissions.dietAssessmentWrite};
  const Set<String> author = <String>{NodexPermissions.dietPlanWrite};
  const Set<String> approver = <String>{NodexPermissions.dietPlanApprove};
  const Set<String> recorder = <String>{NodexPermissions.dietIntakeRecord};

  setUp(() {
    store = FakeNutritionStore();
    repository = DefaultNutritionRepository(
      store: store,
      logger: NodexLogger(
        sinks: <NodexLogSink>[InMemoryLogSink()],
        minimumLevel: NodexLogLevel.trace,
      ),
    );
    recordAssessment = RecordDietAssessmentUseCase(repository: repository);
    finalizeAssessment = FinalizeDietAssessmentUseCase(repository: repository);
    draftPlan = DraftDietMealPlanUseCase(repository: repository);
    addDay = AddDietMealPlanDayUseCase(repository: repository);
    approvePlan = ApproveDietMealPlanUseCase(repository: repository);
    rejectPlan = RejectDietMealPlanUseCase(repository: repository);
    recordIntake = RecordDietIntakeLogUseCase(repository: repository);
  });

  // Seeded rows predate "now" so a use case re-stamping `updatedAt` moves the
  // clock forward rather than backwards.
  DateTime at(int hour) => DateTime.utc(2026, 9, 1, hour);

  Future<DietAssessment> seedAssessment({
    DietAssessmentStatus status = DietAssessmentStatus.draft,
    String id = 'assessment-1',
  }) async {
    final DietAssessment assessment = DietAssessment(
      id: id,
      tenantId: 'tenant-1',
      patientId: 'patient-1',
      assessedBy: 'doctor-1',
      assessmentType: DietAssessmentType.initial,
      weightKg: 70,
      heightCm: 170,
      nutritionDiagnosis: 'Protein-energy malnutrition.',
      status: status,
      assessedAt: at(8),
      finalizedAt: status == DietAssessmentStatus.finalized ? at(9) : null,
      finalizedBy: status == DietAssessmentStatus.finalized ? 'doctor-1' : null,
      createdAt: at(8),
      updatedAt: at(8),
    );
    await repository.upsertAssessment(assessment);
    return assessment;
  }

  Future<DietMealPlan> seedPlan({
    DietMealPlanStatus status = DietMealPlanStatus.draft,
    String id = 'plan-1',
  }) async {
    final DietMealPlan plan = DietMealPlan(
      id: id,
      tenantId: 'tenant-1',
      patientId: 'patient-1',
      assessmentId: 'assessment-1',
      name: 'Recovery week',
      planSource: DietPlanSource.aiGenerated,
      cycleDays: dietCycleDays,
      status: status,
      generatedBy: 'doctor-1',
      generatedAt: at(10),
      approvedBy: status == DietMealPlanStatus.approved ? 'doctor-2' : null,
      approvedAt: status == DietMealPlanStatus.approved ? at(11) : null,
      createdAt: at(10),
      updatedAt: at(10),
    );
    await repository.upsertPlan(plan);
    return plan;
  }

  Future<void> seedDays(String planId, {int count = dietCycleDays}) async {
    for (int dayNumber = 1; dayNumber <= count; dayNumber++) {
      await repository.upsertPlanDay(
        DietMealPlanDay(
          id: 'day-$planId-$dayNumber',
          tenantId: 'tenant-1',
          mealPlanId: planId,
          dayNumber: dayNumber,
          breakfast: 'Oat porridge',
          lunch: 'Grilled chicken and rice',
          dinner: 'Lentil soup',
          caloriesKcal: 2000,
          createdAt: at(10),
          updatedAt: at(10),
        ),
      );
    }
  }

  group('assessments', () {
    test('recording an assessment requires diet_assessment.write', () {
      expect(
        recordAssessment.call(
          policy: policyWith(author),
          tenantId: 'tenant-1',
          patientId: 'patient-1',
          assessedBy: 'doctor-1',
          assessmentType: DietAssessmentType.initial,
          nutritionDiagnosis: 'Well nourished.',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test(
      'out-of-range anthropometrics and a missing diagnosis are rejected',
      () {
        expect(
          recordAssessment.call(
            policy: policyWith(assessor),
            tenantId: 'tenant-1',
            patientId: 'patient-1',
            assessedBy: 'doctor-1',
            assessmentType: DietAssessmentType.initial,
            nutritionDiagnosis: '  ',
            weightKg: 900,
            heightCm: 400,
          ),
          throwsA(
            isA<ValidationError>()
                .having(
                  (ValidationError error) => error.code,
                  'code',
                  'diet_assessment_invalid',
                )
                .having(
                  (ValidationError error) => error.fieldErrors.keys,
                  'fields',
                  containsAll(<String>{
                    'nutrition_diagnosis',
                    'weight_kg',
                    'height_cm',
                  }),
                ),
          ),
        );
      },
    );

    test('an open draft blocks a second assessment', () async {
      await seedAssessment();
      expect(
        recordAssessment.call(
          policy: policyWith(assessor),
          tenantId: 'tenant-1',
          patientId: 'patient-1',
          assessedBy: 'doctor-2',
          assessmentType: DietAssessmentType.reassessment,
          nutritionDiagnosis: 'Improving.',
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'diet_assessment_exists',
          ),
        ),
      );
    });

    test('a draft assessment is recorded and trims its text', () async {
      final DietAssessment assessment = await recordAssessment.call(
        policy: policyWith(assessor),
        tenantId: 'tenant-1',
        patientId: 'patient-1',
        assessedBy: 'doctor-1',
        assessmentType: DietAssessmentType.initial,
        nutritionDiagnosis: ' Protein-energy malnutrition. ',
        weightKg: 72.5,
        heightCm: 168,
        restrictions: '  ',
      );

      expect(assessment.status, DietAssessmentStatus.draft);
      expect(assessment.nutritionDiagnosis, 'Protein-energy malnutrition.');
      expect(assessment.restrictions, isNull);
      expect(assessment.weightKg, 72.5);
      expect(
        (await repository.assessmentById(assessment.id))!.id,
        assessment.id,
      );
    });

    test('a finalized assessment is frozen', () async {
      final DietAssessment draft = await seedAssessment();
      final DietAssessment finalized = await finalizeAssessment.call(
        policy: policyWith(assessor),
        original: draft,
        finalizedBy: 'doctor-2',
      );

      expect(finalized.isFinalized, isTrue);
      expect(finalized.finalizedBy, 'doctor-2');
      expect(finalized.finalizedAt, isNotNull);
      expect(
        finalizeAssessment.call(
          policy: policyWith(assessor),
          original: finalized,
          finalizedBy: 'doctor-3',
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'diet_assessment_not_draft',
          ),
        ),
      );
    });
  });

  group('plan authoring', () {
    test('planning requires a finalized assessment', () async {
      final DietAssessment draft = await seedAssessment();
      expect(
        draftPlan.call(
          policy: policyWith(author),
          assessment: draft,
          name: 'Recovery week',
          planSource: DietPlanSource.clinicianAuthored,
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'diet_assessment_required',
          ),
        ),
      );
    });

    test('authoring requires diet_plan.write', () async {
      final DietAssessment finalized = await seedAssessment(
        status: DietAssessmentStatus.finalized,
      );
      expect(
        draftPlan.call(
          policy: policyWith(assessor),
          assessment: finalized,
          name: 'Recovery week',
          planSource: DietPlanSource.clinicianAuthored,
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('a generated plan must record its generator', () async {
      final DietAssessment finalized = await seedAssessment(
        status: DietAssessmentStatus.finalized,
      );
      expect(
        draftPlan.call(
          policy: policyWith(author),
          assessment: finalized,
          name: 'Recovery week',
          planSource: DietPlanSource.aiGenerated,
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'diet_plan_generation_required',
          ),
        ),
      );
    });

    test('one plan per assessment', () async {
      final DietAssessment finalized = await seedAssessment(
        status: DietAssessmentStatus.finalized,
      );
      await draftPlan.call(
        policy: policyWith(author),
        assessment: finalized,
        name: 'Recovery week',
        planSource: DietPlanSource.aiGenerated,
        generatedBy: 'doctor-1',
      );
      expect(
        draftPlan.call(
          policy: policyWith(author),
          assessment: finalized,
          name: 'Second attempt',
          planSource: DietPlanSource.clinicianAuthored,
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'diet_plan_exists',
          ),
        ),
      );
    });

    test('a generated plan is drafted with its generator stamped', () async {
      final DietAssessment finalized = await seedAssessment(
        status: DietAssessmentStatus.finalized,
      );
      final DietMealPlan plan = await draftPlan.call(
        policy: policyWith(author),
        assessment: finalized,
        name: ' Renal recovery week ',
        planSource: DietPlanSource.aiGenerated,
        generatedBy: ' doctor-1 ',
      );

      expect(plan.name, 'Renal recovery week');
      expect(plan.planSource.isAiGenerated, isTrue);
      expect(plan.generatedBy, 'doctor-1');
      expect(plan.generatedAt, isNotNull);
      expect(plan.cycleDays, dietCycleDays);
      expect(plan.isDraft, isTrue);
    });

    test('an authored plan carries no generator', () async {
      final DietAssessment finalized = await seedAssessment(
        status: DietAssessmentStatus.finalized,
      );
      final DietMealPlan plan = await draftPlan.call(
        policy: policyWith(author),
        assessment: finalized,
        name: 'Low sodium week',
        planSource: DietPlanSource.clinicianAuthored,
      );

      expect(plan.generatedBy, isNull);
      expect(plan.generatedAt, isNull);
    });

    test('day menus validate range, meals and calories', () async {
      final DietMealPlan plan = await seedPlan();
      expect(
        addDay.call(
          policy: policyWith(author),
          plan: plan,
          dayNumber: 8,
          breakfast: 'Oats',
          lunch: 'Rice',
          dinner: 'Soup',
          caloriesKcal: 2000,
        ),
        throwsA(
          isA<ValidationError>()
              .having(
                (ValidationError error) => error.code,
                'code',
                'diet_plan_day_invalid',
              )
              .having(
                (ValidationError error) => error.fieldErrors.keys,
                'fields',
                contains('day_number'),
              ),
        ),
      );
      expect(
        addDay.call(
          policy: policyWith(author),
          plan: plan,
          dayNumber: 1,
          breakfast: ' ',
          lunch: 'Rice',
          dinner: 'Soup',
          caloriesKcal: 0,
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.fieldErrors.keys,
            'fields',
            containsAll(<String>{'breakfast', 'calories_kcal'}),
          ),
        ),
      );
    });

    test('a decided plan cannot gain new days', () async {
      final DietMealPlan approved = await seedPlan(
        status: DietMealPlanStatus.approved,
      );
      expect(
        addDay.call(
          policy: policyWith(author),
          plan: approved,
          dayNumber: 1,
          breakfast: 'Oats',
          lunch: 'Rice',
          dinner: 'Soup',
          caloriesKcal: 2000,
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'diet_plan_closed',
          ),
        ),
      );
    });

    test('a day cannot be planned twice', () async {
      final DietMealPlan plan = await seedPlan();
      await seedDays(plan.id, count: 1);
      expect(
        addDay.call(
          policy: policyWith(author),
          plan: plan,
          dayNumber: 1,
          breakfast: 'Oats',
          lunch: 'Rice',
          dinner: 'Soup',
          caloriesKcal: 2000,
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'diet_plan_day_exists',
          ),
        ),
      );
    });

    test('a day is appended to the cycle', () async {
      final DietMealPlan plan = await seedPlan();
      final DietMealPlanDay day = await addDay.call(
        policy: policyWith(author),
        plan: plan,
        dayNumber: 2,
        breakfast: ' Eggs ',
        lunch: ' Fish ',
        dinner: ' Khichdi ',
        caloriesKcal: 1900,
        snacks: ' Fruit ',
      );

      expect(day.dayNumber, 2);
      expect(day.breakfast, 'Eggs');
      expect(day.snacks, 'Fruit');
      expect((await repository.planDays(plan.id)).single.id, day.id);
    });
  });

  group('plan decisions', () {
    test('approval requires diet_plan.approve', () async {
      final DietMealPlan plan = await seedPlan();
      await seedDays(plan.id);
      expect(
        approvePlan.call(
          policy: policyWith(author),
          plan: plan,
          approvedBy: 'doctor-2',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('an incomplete cycle cannot be approved', () async {
      final DietMealPlan plan = await seedPlan();
      await seedDays(plan.id, count: 5);
      expect(
        approvePlan.call(
          policy: policyWith(approver),
          plan: plan,
          approvedBy: 'doctor-2',
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'diet_plan_incomplete',
          ),
        ),
      );
    });

    test('a complete cycle is approved and frozen', () async {
      final DietMealPlan plan = await seedPlan();
      await seedDays(plan.id);
      final DietMealPlan approved = await approvePlan.call(
        policy: policyWith(approver),
        plan: plan,
        approvedBy: 'doctor-2',
      );

      expect(approved.isApproved, isTrue);
      expect(approved.approvedBy, 'doctor-2');
      expect(approved.approvedAt, isNotNull);
      expect(approved.isTerminal, isTrue);
      expect(
        approvePlan.call(
          policy: policyWith(approver),
          plan: approved,
          approvedBy: 'doctor-3',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('rejection requires a reason and freezes the plan', () async {
      final DietMealPlan plan = await seedPlan();
      expect(
        rejectPlan.call(
          policy: policyWith(approver),
          plan: plan,
          rejectedBy: 'doctor-2',
          reason: '  ',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'diet_rejection_reason_required',
          ),
        ),
      );

      final DietMealPlan rejected = await rejectPlan.call(
        policy: policyWith(approver),
        plan: plan,
        rejectedBy: 'doctor-2',
        reason: ' Exceeds the potassium limit. ',
      );
      expect(rejected.status, DietMealPlanStatus.rejected);
      expect(rejected.rejectionReason, 'Exceeds the potassium limit.');
      expect(rejected.isTerminal, isTrue);
    });
  });

  group('intake', () {
    test('intake requires diet_intake.record', () async {
      final DietMealPlan plan = await seedPlan(
        status: DietMealPlanStatus.approved,
      );
      await seedDays(plan.id);
      final DietMealPlanDay day = (await repository.planDays(plan.id)).first;
      expect(
        recordIntake.call(
          policy: policyWith(approver),
          plan: plan,
          day: day,
          mealSlot: DietMealSlot.lunch,
          portionConsumedPct: 75,
          recordedBy: 'nurse-1',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('intake is recorded only against an approved plan', () async {
      final DietMealPlan plan = await seedPlan();
      await seedDays(plan.id);
      final DietMealPlanDay day = (await repository.planDays(plan.id)).first;
      expect(
        recordIntake.call(
          policy: policyWith(recorder),
          plan: plan,
          day: day,
          mealSlot: DietMealSlot.lunch,
          portionConsumedPct: 75,
          recordedBy: 'nurse-1',
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'diet_plan_not_approved',
          ),
        ),
      );
    });

    test('a day from another plan is rejected', () async {
      final DietMealPlan plan = await seedPlan(
        status: DietMealPlanStatus.approved,
      );
      await seedDays(plan.id);
      final DietMealPlanDay other = (await repository.planDays(plan.id)).first;
      expect(
        recordIntake.call(
          policy: policyWith(recorder),
          plan: plan,
          day: DietMealPlanDay(
            id: 'foreign-day',
            tenantId: 'tenant-1',
            mealPlanId: 'other-plan',
            dayNumber: 1,
            breakfast: 'Oats',
            lunch: 'Rice',
            dinner: 'Soup',
            caloriesKcal: 2000,
            createdAt: at(10),
            updatedAt: at(10),
          ),
          mealSlot: DietMealSlot.lunch,
          portionConsumedPct: 50,
          recordedBy: 'nurse-1',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'diet_plan_day_mismatch',
          ),
        ),
      );
      expect(other.mealPlanId, plan.id);
    });

    test('a portion outside 0-100 is rejected', () async {
      final DietMealPlan plan = await seedPlan(
        status: DietMealPlanStatus.approved,
      );
      await seedDays(plan.id);
      final DietMealPlanDay day = (await repository.planDays(plan.id)).first;
      expect(
        recordIntake.call(
          policy: policyWith(recorder),
          plan: plan,
          day: day,
          mealSlot: DietMealSlot.dinner,
          portionConsumedPct: 140,
          recordedBy: 'nurse-1',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'diet_intake_invalid',
          ),
        ),
      );
    });

    test('a portion is recorded against the plan day', () async {
      final DietMealPlan plan = await seedPlan(
        status: DietMealPlanStatus.approved,
      );
      await seedDays(plan.id);
      final DietMealPlanDay day = (await repository.planDays(plan.id)).first;

      final DietIntakeLog log = await recordIntake.call(
        policy: policyWith(recorder),
        plan: plan,
        day: day,
        mealSlot: DietMealSlot.lunch,
        portionConsumedPct: 75,
        recordedBy: 'nurse-1',
      );

      expect(log.portionConsumedPct, 75);
      expect(log.patientId, plan.patientId);
      expect(log.mealPlanDayId, day.id);
      expect((await repository.intakeLogsForDay(day.id)).single.id, log.id);
    });
  });
}
