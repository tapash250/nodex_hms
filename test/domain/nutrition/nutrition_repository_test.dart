/// Clinical nutrition repository tests over the local projection (Module 21).
///
/// The repository is the only path the presentation layer has to the nutrition
/// tables, so round trips must preserve every column the entities decode and
/// the read scopes (by patient, by assessment, and by plan day) must filter
/// correctly.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/nutrition/nutrition.dart';
import 'package:nodex_hms/domain/nutrition/nutrition_repository.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';

/// In-memory stand-in for the PowerSync-backed patient store.
final class FakeNutritionStore implements PatientLocalStore {
  /// Tables keyed by name, then row id.
  final Map<String, Map<String, Map<String, Object?>>> tables =
      <String, Map<String, Map<String, Object?>>>{};

  /// When true, every operation throws to simulate a closed database.
  bool closed = false;

  Map<String, Map<String, Object?>> _table(String name) =>
      tables.putIfAbsent(name, () => <String, Map<String, Object?>>{});

  void _guard() {
    if (closed) {
      throw const PersistenceError(
        message: 'The local clinical database has not been opened.',
        code: 'database_not_open',
      );
    }
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String sql,
    List<Object?> parameters,
  ) async {
    _guard();
    if (sql.contains(LocalTables.dietAssessments)) {
      final Iterable<Map<String, Object?>> rows = _table(
        LocalTables.dietAssessments,
      ).values;
      if (sql.contains('where patient_id = ?')) {
        return _by(rows, 'patient_id', parameters[0]! as String);
      }
      throw UnimplementedError('FakeNutritionStore cannot run: $sql');
    }
    if (sql.contains(LocalTables.dietMealPlans)) {
      final Iterable<Map<String, Object?>> rows = _table(
        LocalTables.dietMealPlans,
      ).values;
      if (sql.contains('where patient_id = ?')) {
        return _by(rows, 'patient_id', parameters[0]! as String);
      }
      if (sql.contains('where assessment_id = ?')) {
        return _by(rows, 'assessment_id', parameters[0]! as String);
      }
      throw UnimplementedError('FakeNutritionStore cannot run: $sql');
    }
    if (sql.contains(LocalTables.dietMealPlanDays)) {
      final Iterable<Map<String, Object?>> rows = _table(
        LocalTables.dietMealPlanDays,
      ).values;
      if (sql.contains('where meal_plan_id = ? and day_number = ?')) {
        return rows
            .where(
              (Map<String, Object?> row) =>
                  row['meal_plan_id'] == parameters[0] &&
                  row['day_number'] == parameters[1],
            )
            .toList(growable: false);
      }
      if (sql.contains('where meal_plan_id = ?')) {
        return _by(rows, 'meal_plan_id', parameters[0]! as String);
      }
      throw UnimplementedError('FakeNutritionStore cannot run: $sql');
    }
    if (sql.contains(LocalTables.dietIntakeLogs)) {
      final Iterable<Map<String, Object?>> rows = _table(
        LocalTables.dietIntakeLogs,
      ).values;
      if (sql.contains('where meal_plan_day_id = ?')) {
        return _by(rows, 'meal_plan_day_id', parameters[0]! as String);
      }
      throw UnimplementedError('FakeNutritionStore cannot run: $sql');
    }
    throw UnimplementedError('FakeNutritionStore cannot run: $sql');
  }

  List<Map<String, Object?>> _by(
    Iterable<Map<String, Object?>> rows,
    String column,
    String value,
  ) => rows
      .where((Map<String, Object?> row) => row[column] == value)
      .toList(growable: false);

  @override
  Future<Map<String, Object?>?> getById(String table, String id) async {
    _guard();
    return _table(table)[id];
  }

  @override
  Future<void> insert(String table, Map<String, Object?> row) async {
    _guard();
    _table(table)[row['id']! as String] = Map<String, Object?>.from(row);
  }

  @override
  Future<void> update(
    String table,
    String id,
    Map<String, Object?> changes,
  ) async {
    _guard();
    final Map<String, Object?>? existing = _table(table)[id];
    if (existing == null) {
      throw StateError('row $id not found in $table');
    }
    existing.addAll(changes);
  }
}

void main() {
  late FakeNutritionStore store;
  late DefaultNutritionRepository repository;

  setUp(() {
    store = FakeNutritionStore();
    repository = DefaultNutritionRepository(
      store: store,
      logger: NodexLogger(
        sinks: <NodexLogSink>[InMemoryLogSink()],
        minimumLevel: NodexLogLevel.trace,
      ),
    );
  });

  DietAssessment assessment({
    String id = 'assessment-1',
    String patientId = 'patient-1',
    DietAssessmentStatus status = DietAssessmentStatus.draft,
  }) => DietAssessment(
    id: id,
    tenantId: 'tenant-1',
    patientId: patientId,
    assessedBy: 'doctor-1',
    assessmentType: DietAssessmentType.initial,
    weightKg: 70,
    heightCm: 170,
    nutritionDiagnosis: 'Protein-energy malnutrition.',
    status: status,
    assessedAt: DateTime.utc(2026, 9, 20, 9),
    createdAt: DateTime.utc(2026, 9, 19),
    updatedAt: DateTime.utc(2026, 9, 19),
  );

  DietMealPlan plan({
    String id = 'plan-1',
    String patientId = 'patient-1',
    DietMealPlanStatus status = DietMealPlanStatus.draft,
  }) => DietMealPlan(
    id: id,
    tenantId: 'tenant-1',
    patientId: patientId,
    assessmentId: 'assessment-1',
    name: 'Recovery week',
    planSource: DietPlanSource.aiGenerated,
    cycleDays: dietCycleDays,
    status: status,
    generatedBy: 'doctor-1',
    generatedAt: DateTime.utc(2026, 9, 20, 10),
    createdAt: DateTime.utc(2026, 9, 20, 10),
    updatedAt: DateTime.utc(2026, 9, 20, 10),
  );

  DietMealPlanDay day({int dayNumber = 1, String planId = 'plan-1'}) =>
      DietMealPlanDay(
        id: 'day-$dayNumber',
        tenantId: 'tenant-1',
        mealPlanId: planId,
        dayNumber: dayNumber,
        breakfast: 'Oat porridge',
        lunch: 'Grilled chicken and rice',
        dinner: 'Lentil soup',
        caloriesKcal: 2000,
        createdAt: DateTime.utc(2026, 9, 20, 10),
        updatedAt: DateTime.utc(2026, 9, 20, 10),
      );

  DietIntakeLog log({String id = 'intake-1', String dayId = 'day-1'}) =>
      DietIntakeLog(
        id: id,
        tenantId: 'tenant-1',
        patientId: 'patient-1',
        mealPlanDayId: dayId,
        mealSlot: DietMealSlot.lunch,
        portionConsumedPct: 75,
        recordedBy: 'nurse-1',
        recordedAt: DateTime.utc(2026, 9, 21, 13),
        createdAt: DateTime.utc(2026, 9, 21, 13),
        updatedAt: DateTime.utc(2026, 9, 21, 13),
      );

  group('assessments', () {
    test('missing assessments read as null', () async {
      expect(await repository.assessmentById('absent'), isNull);
    });

    test('upsert inserts then updates in place', () async {
      await repository.upsertAssessment(assessment());
      expect(
        (await repository.assessmentById('assessment-1'))!.status,
        DietAssessmentStatus.draft,
      );

      await repository.upsertAssessment(
        assessment(status: DietAssessmentStatus.finalized),
      );
      expect(
        (await repository.assessmentById('assessment-1'))!.isFinalized,
        isTrue,
      );
      expect(store.tables[LocalTables.dietAssessments]!.length, 1);
    });

    test('patient scope filters and the draft scope narrows', () async {
      await repository.upsertAssessment(assessment());
      await repository.upsertAssessment(
        assessment(
          id: 'assessment-2',
          patientId: 'patient-2',
          status: DietAssessmentStatus.finalized,
        ),
      );

      expect((await repository.assessmentsForPatient('patient-1')).length, 1);
      expect((await repository.assessmentsForPatient('patient-2')).length, 1);
      expect(
        (await repository.draftAssessmentForPatient('patient-1'))!.id,
        'assessment-1',
      );
      expect(
        await repository.draftAssessmentForPatient('patient-2'),
        isNull,
        reason: 'a finalized assessment is not an open draft',
      );
    });
  });

  group('meal plans', () {
    test('missing plans read as null', () async {
      expect(await repository.planById('absent'), isNull);
      expect(await repository.planForAssessment('absent'), isNull);
    });

    test('plan round-trips through patient and assessment scopes', () async {
      await repository.upsertPlan(plan());

      expect(
        (await repository.plansForPatient('patient-1')).single.id,
        'plan-1',
      );
      expect(
        (await repository.planForAssessment('assessment-1'))!.planSource,
        DietPlanSource.aiGenerated,
      );
      expect(await repository.plansForPatient('patient-2'), isEmpty);
    });
  });

  group('plan days', () {
    test('day lookup by number and listing by plan', () async {
      await repository.upsertPlan(plan());
      await repository.upsertPlanDay(day(dayNumber: 1));
      await repository.upsertPlanDay(day(dayNumber: 2));

      expect((await repository.planDay('plan-1', 2))!.dayNumber, 2);
      expect(await repository.planDay('plan-1', 3), isNull);
      expect((await repository.planDays('plan-1')).length, 2);
      expect(await repository.planDays('plan-2'), isEmpty);
    });
  });

  group('intake logs', () {
    test('intake round-trips portion against a plan day', () async {
      await repository.upsertIntakeLog(log());
      await repository.upsertIntakeLog(log(id: 'intake-2', dayId: 'day-2'));

      final List<DietIntakeLog> loaded = await repository.intakeLogsForDay(
        'day-1',
      );
      expect(loaded.single.portionConsumedPct, 75);
      expect(loaded.single.mealSlot, DietMealSlot.lunch);
      expect(
        (await repository.intakeLogsForDay('day-2')).single.id,
        'intake-2',
      );
      expect(await repository.intakeLogsForDay('day-9'), isEmpty);
    });
  });

  group('failure mapping', () {
    test('a closed database surfaces as a persistence error', () async {
      store.closed = true;
      expect(
        () => repository.plansForPatient('patient-1'),
        throwsA(isA<PersistenceError>()),
      );
    });
  });
}
