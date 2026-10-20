/// Riverpod providers wiring the Phase 1 foundation together.
///
/// This is the composition root. It is the only place where concrete
/// implementations are chosen, which keeps the dependency direction in the
/// specification's required order: presentation depends on domain, domain depends
/// on repository contracts, and only this file knows which infrastructure
/// satisfies them.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodex_hms/ai/contracts/ai_contracts.dart';
import 'package:nodex_hms/ai/gateway/adapters/stub_adapters.dart';
import 'package:nodex_hms/ai/gateway/ai_gateway.dart';
import 'package:nodex_hms/ai/model_registry/model_registry.dart';
import 'package:nodex_hms/ai/orchestrator/ai_orchestrator.dart';
import 'package:nodex_hms/core/config/nodex_environment.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/security/database_key_manager.dart';
import 'package:nodex_hms/core/security/second_factor.dart';
import 'package:nodex_hms/core/security/secure_key_store.dart';
import 'package:nodex_hms/core/storage/storage_service.dart';
import 'package:nodex_hms/data/local/local_database.dart';
import 'package:nodex_hms/data/remote/supabase_gateway.dart';
import 'package:nodex_hms/domain/analytics/analytics_repository.dart';
import 'package:nodex_hms/domain/analytics/analytics_use_cases.dart';
import 'package:nodex_hms/domain/appointments/appointment_repository.dart';
import 'package:nodex_hms/domain/appointments/appointment_use_cases.dart';
import 'package:nodex_hms/domain/beds/bed_repository.dart';
import 'package:nodex_hms/domain/beds/bed_use_cases.dart';
import 'package:nodex_hms/domain/billing/billing_repository.dart';
import 'package:nodex_hms/domain/billing/billing_use_cases.dart';
import 'package:nodex_hms/domain/biomedical/biomedical_repository.dart';
import 'package:nodex_hms/domain/biomedical/biomedical_use_cases.dart';
import 'package:nodex_hms/domain/blood_bank/blood_bank_repository.dart';
import 'package:nodex_hms/domain/blood_bank/blood_bank_use_cases.dart';
import 'package:nodex_hms/domain/calendar/calendar_repository.dart';
import 'package:nodex_hms/domain/calendar/calendar_use_cases.dart';
import 'package:nodex_hms/domain/contacts/contact_repository.dart';
import 'package:nodex_hms/domain/contacts/contact_use_cases.dart';
import 'package:nodex_hms/domain/departments/department_repository.dart';
import 'package:nodex_hms/domain/departments/department_use_cases.dart';
import 'package:nodex_hms/domain/discharge/discharge_management_repository.dart';
import 'package:nodex_hms/domain/discharge/discharge_management_use_cases.dart';
import 'package:nodex_hms/domain/discharge/discharge_repository.dart';
import 'package:nodex_hms/domain/discharge/discharge_use_cases.dart';
import 'package:nodex_hms/domain/documents/documents_repository.dart';
import 'package:nodex_hms/domain/documents/documents_use_cases.dart';
import 'package:nodex_hms/domain/encounters/encounter_repository.dart';
import 'package:nodex_hms/domain/encounters/encounter_use_cases.dart';
import 'package:nodex_hms/domain/encounters/problem_list_repository.dart';
import 'package:nodex_hms/domain/encounters/problem_list_use_cases.dart';
import 'package:nodex_hms/domain/er/er_repository.dart';
import 'package:nodex_hms/domain/er/er_use_cases.dart';
import 'package:nodex_hms/domain/feedback/feedback_repository.dart';
import 'package:nodex_hms/domain/feedback/feedback_use_cases.dart';
import 'package:nodex_hms/domain/fleet/fleet_repository.dart';
import 'package:nodex_hms/domain/fleet/fleet_use_cases.dart';
import 'package:nodex_hms/domain/floormap/floormap_repository.dart';
import 'package:nodex_hms/domain/floormap/floormap_use_cases.dart';
import 'package:nodex_hms/domain/forms/form_repository.dart';
import 'package:nodex_hms/domain/forms/form_use_cases.dart';
import 'package:nodex_hms/domain/hr/hr_repository.dart';
import 'package:nodex_hms/domain/hr/hr_use_cases.dart';
import 'package:nodex_hms/domain/icu/icu_repository.dart';
import 'package:nodex_hms/domain/icu/icu_use_cases.dart';
import 'package:nodex_hms/domain/insurance/insurance_repository.dart';
import 'package:nodex_hms/domain/insurance/insurance_use_cases.dart';
import 'package:nodex_hms/domain/inventory/inventory_repository.dart';
import 'package:nodex_hms/domain/inventory/inventory_use_cases.dart';
import 'package:nodex_hms/domain/laboratory/lab_repository.dart';
import 'package:nodex_hms/domain/laboratory/lab_use_cases.dart';

import 'package:nodex_hms/domain/messaging/messaging_repository.dart';
import 'package:nodex_hms/domain/nursing_station/nursing_station_repository.dart';
import 'package:nodex_hms/domain/nursing_station/nursing_station_use_cases.dart';
import 'package:nodex_hms/domain/nutrition/nutrition_repository.dart';
import 'package:nodex_hms/domain/nutrition/nutrition_use_cases.dart';
import 'package:nodex_hms/domain/operations/operations_repository.dart';
import 'package:nodex_hms/domain/ot/ot_repository.dart';
import 'package:nodex_hms/domain/ot/ot_use_cases.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';
import 'package:nodex_hms/domain/patients/patient_use_cases.dart';
import 'package:nodex_hms/domain/physio/physio_repository.dart';
import 'package:nodex_hms/domain/physio/physio_use_cases.dart';
import 'package:nodex_hms/domain/prescriptions/prescription_repository.dart';
import 'package:nodex_hms/domain/prescriptions/prescription_use_cases.dart';
import 'package:nodex_hms/domain/productivity/productivity_repository.dart';
import 'package:nodex_hms/domain/productivity/productivity_use_cases.dart';
import 'package:nodex_hms/domain/quality/quality_repository.dart';
import 'package:nodex_hms/domain/quality/quality_use_cases.dart';
import 'package:nodex_hms/domain/radiology/radiology_repository.dart';
import 'package:nodex_hms/domain/radiology/radiology_use_cases.dart';
import 'package:nodex_hms/domain/roster/practitioner_repository.dart';
import 'package:nodex_hms/domain/roster/practitioner_use_cases.dart';
import 'package:nodex_hms/domain/session/session_repository.dart';
import 'package:nodex_hms/domain/settings/settings_repository.dart';
import 'package:nodex_hms/domain/settings/settings_use_cases.dart';
import 'package:nodex_hms/domain/statutory/statutory_repository.dart';
import 'package:nodex_hms/domain/statutory/statutory_use_cases.dart';
import 'package:nodex_hms/domain/tasks/task_repository.dart';
import 'package:nodex_hms/domain/tasks/task_use_cases.dart';
import 'package:nodex_hms/domain/telemedicine/telemedicine_repository.dart';
import 'package:nodex_hms/domain/telemedicine/telemedicine_use_cases.dart';
import 'package:nodex_hms/domain/timeline/timeline_repository.dart';
import 'package:nodex_hms/domain/timeline/timeline_use_cases.dart';
import 'package:nodex_hms/domain/visitor/visitor_repository.dart';
import 'package:nodex_hms/domain/visitor/visitor_use_cases.dart';
import 'package:nodex_hms/domain/waste/waste_repository.dart';
import 'package:nodex_hms/domain/waste/waste_use_cases.dart';
import 'package:nodex_hms/domain/workforce/workforce_repository.dart';
import 'package:nodex_hms/domain/workforce/workforce_use_cases.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The resolved build environment.
///
/// Overridden in `main` after [NodexEnvironment.resolve] succeeds, and in tests
/// with a fixture, so no provider reads `--dart-define` values directly.
final Provider<NodexEnvironment> environmentProvider =
    Provider<NodexEnvironment>((Ref ref) {
      throw UnimplementedError(
        'environmentProvider must be overridden during bootstrap.',
      );
    });

/// The application logger.
final Provider<NodexLogger> loggerProvider = Provider<NodexLogger>((Ref ref) {
  final NodexEnvironment environment = ref.watch(environmentProvider);
  return NodexLogger(
    sinks: <NodexLogSink>[
      LoggingPackageSink(),
      // Retained in memory so the diagnostics screen can show recent activity
      // without a network round trip.
      ref.watch(diagnosticsSinkProvider),
    ],
    minimumLevel: environment.environment.isProduction
        ? NodexLogLevel.info
        : NodexLogLevel.trace,
  );
});

/// In-memory diagnostics buffer surfaced by the sync diagnostics screen.
final Provider<InMemoryLogSink> diagnosticsSinkProvider =
    Provider<InMemoryLogSink>((Ref ref) => InMemoryLogSink());

/// Keystore-backed secret storage.
final Provider<SecureKeyStore> secureKeyStoreProvider =
    Provider<SecureKeyStore>((Ref ref) => PlatformSecureKeyStore());

/// Local database encryption key lifecycle.
final Provider<DatabaseKeyManager> databaseKeyManagerProvider =
    Provider<DatabaseKeyManager>(
      (Ref ref) => DatabaseKeyManager(
        keyStore: ref.watch(secureKeyStoreProvider),
        logger: ref.watch(loggerProvider),
      ),
    );

/// The configured Supabase client.
///
/// Overridden during bootstrap once `Supabase.initialize` has completed.
final Provider<SupabaseClient> supabaseClientProvider =
    Provider<SupabaseClient>((Ref ref) {
      throw UnimplementedError(
        'supabaseClientProvider must be overridden during bootstrap.',
      );
    });

/// The Supabase transport boundary.
final Provider<SupabaseGateway> supabaseGatewayProvider =
    Provider<SupabaseGateway>(
      (Ref ref) => SupabaseGateway(
        client: ref.watch(supabaseClientProvider),
        logger: ref.watch(loggerProvider),
      ),
    );

/// Clinical object storage: tenant-scoped uploads, checksums, short-lived URLs.
final Provider<StorageService> storageServiceProvider =
    Provider<StorageService>(
      (Ref ref) => GatewayStorageService(ref.watch(supabaseGatewayProvider)),
    );

/// The encrypted local operational projection.
final Provider<LocalDatabase> localDatabaseProvider = Provider<LocalDatabase>(
  (Ref ref) => LocalDatabase(
    keyManager: ref.watch(databaseKeyManagerProvider),
    logger: ref.watch(loggerProvider),
  ),
);

/// Session and authorization repository.
final Provider<SessionRepository> sessionRepositoryProvider =
    Provider<SessionRepository>(
      (Ref ref) => DefaultSessionRepository(
        gateway: ref.watch(supabaseGatewayProvider),
        keyStore: ref.watch(secureKeyStoreProvider),
        logger: ref.watch(loggerProvider),
      ),
    );

/// Master Patient Index repository over the encrypted local projection.
final Provider<PatientRepository> patientRepositoryProvider =
    Provider<PatientRepository>(
      (Ref ref) => DefaultPatientRepository(
        store: PowerSyncPatientStore(
          database: ref.watch(localDatabaseProvider),
        ),
        logger: ref.watch(loggerProvider),
      ),
    );

/// MPI use cases. Thin wrappers over the repository carrying the authorization
/// gate; constructed per read so tests can substitute fakes at this boundary.
final Provider<RegisterPatientUseCase> registerPatientUseCaseProvider =
    Provider<RegisterPatientUseCase>(
      (Ref ref) => RegisterPatientUseCase(
        repository: ref.watch(patientRepositoryProvider),
        logger: ref.watch(loggerProvider),
      ),
    );

/// Contact update use case.
final Provider<UpdatePatientContactUseCase>
updatePatientContactUseCaseProvider = Provider<UpdatePatientContactUseCase>(
  (Ref ref) => UpdatePatientContactUseCase(
    repository: ref.watch(patientRepositoryProvider),
  ),
);

/// Allergy report use case.
final Provider<RecordAllergyUseCase> recordAllergyUseCaseProvider =
    Provider<RecordAllergyUseCase>(
      (Ref ref) => RecordAllergyUseCase(
        repository: ref.watch(patientRepositoryProvider),
      ),
    );

/// Allergy retirement use case.
final Provider<RetireAllergyUseCase> retireAllergyUseCaseProvider =
    Provider<RetireAllergyUseCase>(
      (Ref ref) => RetireAllergyUseCase(
        repository: ref.watch(patientRepositoryProvider),
      ),
    );

/// Patient merge use case.
final Provider<MergePatientsUseCase> mergePatientsUseCaseProvider =
    Provider<MergePatientsUseCase>(
      (Ref ref) => MergePatientsUseCase(
        repository: ref.watch(patientRepositoryProvider),
      ),
    );

/// Clinical encounter repository over the encrypted local projection.
final Provider<EncounterRepository> encounterRepositoryProvider =
    Provider<EncounterRepository>(
      (Ref ref) => DefaultEncounterRepository(
        store: PowerSyncPatientStore(
          database: ref.watch(localDatabaseProvider),
        ),
        logger: ref.watch(loggerProvider),
      ),
    );

/// Encounter use cases, constructed per read like the MPI ones.
final Provider<StartEncounterUseCase> startEncounterUseCaseProvider =
    Provider<StartEncounterUseCase>(
      (Ref ref) => StartEncounterUseCase(
        repository: ref.watch(encounterRepositoryProvider),
      ),
    );

/// Encounter draft save use case.
final Provider<SaveEncounterDraftUseCase> saveEncounterDraftUseCaseProvider =
    Provider<SaveEncounterDraftUseCase>(
      (Ref ref) => SaveEncounterDraftUseCase(
        repository: ref.watch(encounterRepositoryProvider),
      ),
    );

/// Encounter signature use case.
final Provider<SignEncounterUseCase> signEncounterUseCaseProvider =
    Provider<SignEncounterUseCase>(
      (Ref ref) => SignEncounterUseCase(
        repository: ref.watch(encounterRepositoryProvider),
      ),
    );

/// Encounter amendment use case.
final Provider<AmendEncounterUseCase> amendEncounterUseCaseProvider =
    Provider<AmendEncounterUseCase>(
      (Ref ref) => AmendEncounterUseCase(
        repository: ref.watch(encounterRepositoryProvider),
      ),
    );

/// Problem-list and scribe-draft repository over the local projection.
final Provider<ProblemListRepository> problemListRepositoryProvider =
    Provider<ProblemListRepository>(
      (Ref ref) => DefaultProblemListRepository(
        store: PowerSyncPatientStore(
          database: ref.watch(localDatabaseProvider),
        ),
        logger: ref.watch(loggerProvider),
      ),
    );

/// Problem recording use case.
final Provider<RecordProblemUseCase> recordProblemUseCaseProvider =
    Provider<RecordProblemUseCase>(
      (Ref ref) => RecordProblemUseCase(
        repository: ref.watch(problemListRepositoryProvider),
      ),
    );

/// Problem resolution use case.
final Provider<ResolveProblemUseCase> resolveProblemUseCaseProvider =
    Provider<ResolveProblemUseCase>(
      (Ref ref) => ResolveProblemUseCase(
        repository: ref.watch(problemListRepositoryProvider),
      ),
    );

/// Ambient dictation recording use case.
final Provider<RequestScribeDraftUseCase> requestScribeDraftUseCaseProvider =
    Provider<RequestScribeDraftUseCase>(
      (Ref ref) => RequestScribeDraftUseCase(
        repository: ref.watch(problemListRepositoryProvider),
      ),
    );

/// Ambient dictation review use case.
final Provider<ReviewScribeDraftUseCase> reviewScribeDraftUseCaseProvider =
    Provider<ReviewScribeDraftUseCase>(
      (Ref ref) => ReviewScribeDraftUseCase(
        repository: ref.watch(problemListRepositoryProvider),
        encounters: ref.watch(encounterRepositoryProvider),
      ),
    );

/// Laboratory repository over the encrypted local projection.
final Provider<LabRepository> labRepositoryProvider = Provider<LabRepository>(
  (Ref ref) => DefaultLabRepository(
    store: PowerSyncPatientStore(database: ref.watch(localDatabaseProvider)),
    logger: ref.watch(loggerProvider),
  ),
);

/// Laboratory order creation.
final Provider<CreateLabOrderUseCase> createLabOrderUseCaseProvider =
    Provider<CreateLabOrderUseCase>(
      (Ref ref) =>
          CreateLabOrderUseCase(repository: ref.watch(labRepositoryProvider)),
    );

/// Specimen registration.
final Provider<RegisterSpecimenUseCase> registerSpecimenUseCaseProvider =
    Provider<RegisterSpecimenUseCase>(
      (Ref ref) =>
          RegisterSpecimenUseCase(repository: ref.watch(labRepositoryProvider)),
    );

/// Specimen collection.
final Provider<CollectSpecimenUseCase> collectSpecimenUseCaseProvider =
    Provider<CollectSpecimenUseCase>(
      (Ref ref) =>
          CollectSpecimenUseCase(repository: ref.watch(labRepositoryProvider)),
    );

/// Laboratory result entry.
final Provider<EnterLabResultUseCase> enterLabResultUseCaseProvider =
    Provider<EnterLabResultUseCase>(
      (Ref ref) =>
          EnterLabResultUseCase(repository: ref.watch(labRepositoryProvider)),
    );

/// Laboratory result verification.
final Provider<VerifyLabResultUseCase> verifyLabResultUseCaseProvider =
    Provider<VerifyLabResultUseCase>(
      (Ref ref) =>
          VerifyLabResultUseCase(repository: ref.watch(labRepositoryProvider)),
    );

/// Laboratory result correction.
final Provider<CorrectLabResultUseCase> correctLabResultUseCaseProvider =
    Provider<CorrectLabResultUseCase>(
      (Ref ref) =>
          CorrectLabResultUseCase(repository: ref.watch(labRepositoryProvider)),
    );

/// Radiology repository over the encrypted local projection.
final Provider<RadiologyRepository> radiologyRepositoryProvider =
    Provider<RadiologyRepository>(
      (Ref ref) => DefaultRadiologyRepository(
        store: PowerSyncPatientStore(
          database: ref.watch(localDatabaseProvider),
        ),
        logger: ref.watch(loggerProvider),
      ),
    );

/// Imaging order creation.
final Provider<OrderImagingUseCase> orderImagingUseCaseProvider =
    Provider<OrderImagingUseCase>(
      (Ref ref) => OrderImagingUseCase(
        repository: ref.watch(radiologyRepositoryProvider),
      ),
    );

/// Imaging order cancellation.
final Provider<CancelImagingOrderUseCase> cancelImagingOrderUseCaseProvider =
    Provider<CancelImagingOrderUseCase>(
      (Ref ref) => CancelImagingOrderUseCase(
        repository: ref.watch(radiologyRepositoryProvider),
      ),
    );

/// Imaging study acquisition recording.
final Provider<RecordImagingStudyUseCase> recordImagingStudyUseCaseProvider =
    Provider<RecordImagingStudyUseCase>(
      (Ref ref) => RecordImagingStudyUseCase(
        repository: ref.watch(radiologyRepositoryProvider),
        storage: ref.watch(storageServiceProvider),
      ),
    );

/// Imaging report drafting.
final Provider<EnterImagingReportUseCase> enterImagingReportUseCaseProvider =
    Provider<EnterImagingReportUseCase>(
      (Ref ref) => EnterImagingReportUseCase(
        repository: ref.watch(radiologyRepositoryProvider),
      ),
    );

/// Imaging report revision.
final Provider<ReviseImagingReportUseCase> reviseImagingReportUseCaseProvider =
    Provider<ReviseImagingReportUseCase>(
      (Ref ref) => ReviseImagingReportUseCase(
        repository: ref.watch(radiologyRepositoryProvider),
      ),
    );

/// Imaging report verification and release.
final Provider<VerifyImagingReportUseCase> verifyImagingReportUseCaseProvider =
    Provider<VerifyImagingReportUseCase>(
      (Ref ref) => VerifyImagingReportUseCase(
        repository: ref.watch(radiologyRepositoryProvider),
      ),
    );

/// Physiotherapy repository over the encrypted local projection.
final Provider<PhysioRepository> physioRepositoryProvider =
    Provider<PhysioRepository>(
      (Ref ref) => DefaultPhysioRepository(
        store: PowerSyncPatientStore(
          database: ref.watch(localDatabaseProvider),
        ),
        logger: ref.watch(loggerProvider),
      ),
    );

/// Physiotherapy session scheduling.
final Provider<SchedulePhysioSessionUseCase>
schedulePhysioSessionUseCaseProvider = Provider<SchedulePhysioSessionUseCase>(
  (Ref ref) => SchedulePhysioSessionUseCase(
    repository: ref.watch(physioRepositoryProvider),
  ),
);

/// Physiotherapy session start.
final Provider<StartPhysioSessionUseCase> startPhysioSessionUseCaseProvider =
    Provider<StartPhysioSessionUseCase>(
      (Ref ref) => StartPhysioSessionUseCase(
        repository: ref.watch(physioRepositoryProvider),
      ),
    );

/// Physiotherapy session completion.
final Provider<CompletePhysioSessionUseCase>
completePhysioSessionUseCaseProvider = Provider<CompletePhysioSessionUseCase>(
  (Ref ref) => CompletePhysioSessionUseCase(
    repository: ref.watch(physioRepositoryProvider),
  ),
);

/// Physiotherapy session cancellation.
final Provider<CancelPhysioSessionUseCase> cancelPhysioSessionUseCaseProvider =
    Provider<CancelPhysioSessionUseCase>(
      (Ref ref) => CancelPhysioSessionUseCase(
        repository: ref.watch(physioRepositoryProvider),
      ),
    );

/// Exercise regimen prescription.
final Provider<PrescribePhysioExerciseUseCase>
prescribePhysioExerciseUseCaseProvider =
    Provider<PrescribePhysioExerciseUseCase>(
      (Ref ref) => PrescribePhysioExerciseUseCase(
        repository: ref.watch(physioRepositoryProvider),
      ),
    );

/// Exercise regimen completion or stoppage.
final Provider<FinishPhysioExercisePlanUseCase>
finishPhysioExercisePlanUseCaseProvider =
    Provider<FinishPhysioExercisePlanUseCase>(
      (Ref ref) => FinishPhysioExercisePlanUseCase(
        repository: ref.watch(physioRepositoryProvider),
      ),
    );

/// Physiotherapy recovery note recording.
final Provider<RecordPhysioRecoveryNoteUseCase>
recordPhysioRecoveryNoteUseCaseProvider =
    Provider<RecordPhysioRecoveryNoteUseCase>(
      (Ref ref) => RecordPhysioRecoveryNoteUseCase(
        repository: ref.watch(physioRepositoryProvider),
      ),
    );

/// Clinical nutrition repository over the encrypted local projection.
final Provider<NutritionRepository> nutritionRepositoryProvider =
    Provider<NutritionRepository>(
      (Ref ref) => DefaultNutritionRepository(
        store: PowerSyncPatientStore(
          database: ref.watch(localDatabaseProvider),
        ),
        logger: ref.watch(loggerProvider),
      ),
    );

/// Nutrition assessment recording.
final Provider<RecordDietAssessmentUseCase>
recordDietAssessmentUseCaseProvider = Provider<RecordDietAssessmentUseCase>(
  (Ref ref) => RecordDietAssessmentUseCase(
    repository: ref.watch(nutritionRepositoryProvider),
  ),
);

/// Nutrition assessment finalization.
final Provider<FinalizeDietAssessmentUseCase>
finalizeDietAssessmentUseCaseProvider = Provider<FinalizeDietAssessmentUseCase>(
  (Ref ref) => FinalizeDietAssessmentUseCase(
    repository: ref.watch(nutritionRepositoryProvider),
  ),
);

/// Meal plan authoring.
final Provider<DraftDietMealPlanUseCase> draftDietMealPlanUseCaseProvider =
    Provider<DraftDietMealPlanUseCase>(
      (Ref ref) => DraftDietMealPlanUseCase(
        repository: ref.watch(nutritionRepositoryProvider),
      ),
    );

/// Meal plan day authoring.
final Provider<AddDietMealPlanDayUseCase> addDietMealPlanDayUseCaseProvider =
    Provider<AddDietMealPlanDayUseCase>(
      (Ref ref) => AddDietMealPlanDayUseCase(
        repository: ref.watch(nutritionRepositoryProvider),
      ),
    );

/// Meal plan approval.
final Provider<ApproveDietMealPlanUseCase> approveDietMealPlanUseCaseProvider =
    Provider<ApproveDietMealPlanUseCase>(
      (Ref ref) => ApproveDietMealPlanUseCase(
        repository: ref.watch(nutritionRepositoryProvider),
      ),
    );

/// Meal plan rejection.
final Provider<RejectDietMealPlanUseCase> rejectDietMealPlanUseCaseProvider =
    Provider<RejectDietMealPlanUseCase>(
      (Ref ref) => RejectDietMealPlanUseCase(
        repository: ref.watch(nutritionRepositoryProvider),
      ),
    );

/// Dietary intake recording.
final Provider<RecordDietIntakeLogUseCase> recordDietIntakeLogUseCaseProvider =
    Provider<RecordDietIntakeLogUseCase>(
      (Ref ref) => RecordDietIntakeLogUseCase(
        repository: ref.watch(nutritionRepositoryProvider),
      ),
    );

/// Telemedicine repository over the encrypted local projection.
final Provider<TelemedicineRepository> telemedicineRepositoryProvider =
    Provider<TelemedicineRepository>(
      (Ref ref) => DefaultTelemedicineRepository(
        store: PowerSyncPatientStore(
          database: ref.watch(localDatabaseProvider),
        ),
        logger: ref.watch(loggerProvider),
      ),
    );

/// Virtual consultation scheduling.
final Provider<ScheduleTeleConsultationUseCase>
scheduleTeleConsultationUseCaseProvider =
    Provider<ScheduleTeleConsultationUseCase>(
      (Ref ref) => ScheduleTeleConsultationUseCase(
        repository: ref.watch(telemedicineRepositoryProvider),
      ),
    );

/// Waiting room admission.
final Provider<AdmitToWaitingRoomUseCase> admitToWaitingRoomUseCaseProvider =
    Provider<AdmitToWaitingRoomUseCase>(
      (Ref ref) => AdmitToWaitingRoomUseCase(
        repository: ref.watch(telemedicineRepositoryProvider),
      ),
    );

/// Call start.
final Provider<StartTeleConsultationUseCase>
startTeleConsultationUseCaseProvider = Provider<StartTeleConsultationUseCase>(
  (Ref ref) => StartTeleConsultationUseCase(
    repository: ref.watch(telemedicineRepositoryProvider),
  ),
);

/// Call completion.
final Provider<CompleteTeleConsultationUseCase>
completeTeleConsultationUseCaseProvider =
    Provider<CompleteTeleConsultationUseCase>(
      (Ref ref) => CompleteTeleConsultationUseCase(
        repository: ref.watch(telemedicineRepositoryProvider),
      ),
    );

/// No-show recording.
final Provider<MarkTeleNoShowUseCase> markTeleNoShowUseCaseProvider =
    Provider<MarkTeleNoShowUseCase>(
      (Ref ref) => MarkTeleNoShowUseCase(
        repository: ref.watch(telemedicineRepositoryProvider),
      ),
    );

/// Consultation cancellation.
final Provider<CancelTeleConsultationUseCase>
cancelTeleConsultationUseCaseProvider = Provider<CancelTeleConsultationUseCase>(
  (Ref ref) => CancelTeleConsultationUseCase(
    repository: ref.watch(telemedicineRepositoryProvider),
  ),
);

/// Live vitals overlay recording.
final Provider<RecordTeleVitalsOverlayUseCase>
recordTeleVitalsOverlayUseCaseProvider =
    Provider<RecordTeleVitalsOverlayUseCase>(
      (Ref ref) => RecordTeleVitalsOverlayUseCase(
        repository: ref.watch(telemedicineRepositoryProvider),
      ),
    );

/// Consultation archiving.
final Provider<ArchiveTeleConsultationUseCase>
archiveTeleConsultationUseCaseProvider =
    Provider<ArchiveTeleConsultationUseCase>(
      (Ref ref) => ArchiveTeleConsultationUseCase(
        repository: ref.watch(telemedicineRepositoryProvider),
        storage: ref.watch(storageServiceProvider),
      ),
    );

/// Floor map repository over the encrypted local projection.
final Provider<FloorMapRepository> floorMapRepositoryProvider =
    Provider<FloorMapRepository>(
      (Ref ref) => DefaultFloorMapRepository(
        store: PowerSyncPatientStore(
          database: ref.watch(localDatabaseProvider),
        ),
        logger: ref.watch(loggerProvider),
      ),
    );

/// Ward room registration.
final Provider<RegisterWardRoomUseCase> registerWardRoomUseCaseProvider =
    Provider<RegisterWardRoomUseCase>(
      (Ref ref) => RegisterWardRoomUseCase(
        repository: ref.watch(floorMapRepositoryProvider),
      ),
    );

/// Ward room layout and capacity updates.
final Provider<UpdateWardRoomUseCase> updateWardRoomUseCaseProvider =
    Provider<UpdateWardRoomUseCase>(
      (Ref ref) => UpdateWardRoomUseCase(
        repository: ref.watch(floorMapRepositoryProvider),
      ),
    );

/// Ward room retirement.
final Provider<RetireWardRoomUseCase> retireWardRoomUseCaseProvider =
    Provider<RetireWardRoomUseCase>(
      (Ref ref) => RetireWardRoomUseCase(
        repository: ref.watch(floorMapRepositoryProvider),
      ),
    );

/// Floor occupancy composition.
final Provider<FloorOccupancyUseCase> floorOccupancyUseCaseProvider =
    Provider<FloorOccupancyUseCase>(
      (Ref ref) => FloorOccupancyUseCase(
        repository: ref.watch(floorMapRepositoryProvider),
      ),
    );

/// Biomedical assets & calibration repository over the encrypted local
/// projection.
final Provider<BiomedicalRepository> biomedicalRepositoryProvider =
    Provider<BiomedicalRepository>(
      (Ref ref) => DefaultBiomedicalRepository(
        store: PowerSyncPatientStore(
          database: ref.watch(localDatabaseProvider),
        ),
        logger: ref.watch(loggerProvider),
      ),
    );

/// Register a biomedical asset.
final Provider<RegisterAssetUseCase> registerAssetUseCaseProvider =
    Provider<RegisterAssetUseCase>(
      (Ref ref) => RegisterAssetUseCase(
        repository: ref.watch(biomedicalRepositoryProvider),
      ),
    );

/// Update a biomedical asset.
final Provider<UpdateAssetUseCase> updateAssetUseCaseProvider =
    Provider<UpdateAssetUseCase>(
      (Ref ref) => UpdateAssetUseCase(
        repository: ref.watch(biomedicalRepositoryProvider),
      ),
    );

/// Move a biomedical asset's lifecycle status.
final Provider<SetAssetStatusUseCase> setAssetStatusUseCaseProvider =
    Provider<SetAssetStatusUseCase>(
      (Ref ref) => SetAssetStatusUseCase(
        repository: ref.watch(biomedicalRepositoryProvider),
      ),
    );

/// Decommission a biomedical asset.
final Provider<DecommissionAssetUseCase> decommissionAssetUseCaseProvider =
    Provider<DecommissionAssetUseCase>(
      (Ref ref) => DecommissionAssetUseCase(
        repository: ref.watch(biomedicalRepositoryProvider),
      ),
    );

/// Raise a breakdown ticket.
final Provider<RaiseBreakdownUseCase> raiseBreakdownUseCaseProvider =
    Provider<RaiseBreakdownUseCase>(
      (Ref ref) => RaiseBreakdownUseCase(
        repository: ref.watch(biomedicalRepositoryProvider),
      ),
    );

/// Advance a breakdown ticket.
final Provider<AdvanceBreakdownUseCase> advanceBreakdownUseCaseProvider =
    Provider<AdvanceBreakdownUseCase>(
      (Ref ref) => AdvanceBreakdownUseCase(
        repository: ref.watch(biomedicalRepositoryProvider),
      ),
    );

/// Record a maintenance or calibration event.
final Provider<RecordMaintenanceUseCase> recordMaintenanceUseCaseProvider =
    Provider<RecordMaintenanceUseCase>(
      (Ref ref) => RecordMaintenanceUseCase(
        repository: ref.watch(biomedicalRepositoryProvider),
      ),
    );

/// Read the biomedical board.
final Provider<ReadBiomedicalUseCase> readBiomedicalUseCaseProvider =
    Provider<ReadBiomedicalUseCase>(
      (Ref ref) => ReadBiomedicalUseCase(
        repository: ref.watch(biomedicalRepositoryProvider),
      ),
    );

/// Fleet & ambulance dispatch repository over the encrypted local projection.
final Provider<FleetRepository> fleetRepositoryProvider =
    Provider<FleetRepository>(
      (Ref ref) => DefaultFleetRepository(
        store: PowerSyncPatientStore(
          database: ref.watch(localDatabaseProvider),
        ),
        logger: ref.watch(loggerProvider),
      ),
    );

/// Register a fleet vehicle.
final Provider<RegisterAmbulanceUseCase> registerAmbulanceUseCaseProvider =
    Provider<RegisterAmbulanceUseCase>(
      (Ref ref) => RegisterAmbulanceUseCase(
        repository: ref.watch(fleetRepositoryProvider),
      ),
    );

/// Update a fleet vehicle.
final Provider<UpdateAmbulanceUseCase> updateAmbulanceUseCaseProvider =
    Provider<UpdateAmbulanceUseCase>(
      (Ref ref) => UpdateAmbulanceUseCase(
        repository: ref.watch(fleetRepositoryProvider),
      ),
    );

/// Archive a fleet vehicle.
final Provider<ArchiveAmbulanceUseCase> archiveAmbulanceUseCaseProvider =
    Provider<ArchiveAmbulanceUseCase>(
      (Ref ref) => ArchiveAmbulanceUseCase(
        repository: ref.watch(fleetRepositoryProvider),
      ),
    );

/// Book a driver onto a vehicle.
final Provider<ScheduleDutyUseCase> scheduleDutyUseCaseProvider =
    Provider<ScheduleDutyUseCase>(
      (Ref ref) =>
          ScheduleDutyUseCase(repository: ref.watch(fleetRepositoryProvider)),
    );

/// Close an open duty assignment.
final Provider<CloseDutyUseCase> closeDutyUseCaseProvider =
    Provider<CloseDutyUseCase>(
      (Ref ref) =>
          CloseDutyUseCase(repository: ref.watch(fleetRepositoryProvider)),
    );

/// Raise an emergency dispatch.
final Provider<RaiseDispatchUseCase> raiseDispatchUseCaseProvider =
    Provider<RaiseDispatchUseCase>(
      (Ref ref) =>
          RaiseDispatchUseCase(repository: ref.watch(fleetRepositoryProvider)),
    );

/// Advance a dispatch.
final Provider<AdvanceDispatchUseCase> advanceDispatchUseCaseProvider =
    Provider<AdvanceDispatchUseCase>(
      (Ref ref) => AdvanceDispatchUseCase(
        repository: ref.watch(fleetRepositoryProvider),
      ),
    );

/// Cancel a dispatch.
final Provider<CancelDispatchUseCase> cancelDispatchUseCaseProvider =
    Provider<CancelDispatchUseCase>(
      (Ref ref) =>
          CancelDispatchUseCase(repository: ref.watch(fleetRepositoryProvider)),
    );

/// Record a last-known-position ping.
final Provider<RecordPingUseCase> recordPingUseCaseProvider =
    Provider<RecordPingUseCase>(
      (Ref ref) =>
          RecordPingUseCase(repository: ref.watch(fleetRepositoryProvider)),
    );

/// Read the fleet board.
final Provider<ReadFleetUseCase> readFleetUseCaseProvider =
    Provider<ReadFleetUseCase>(
      (Ref ref) =>
          ReadFleetUseCase(repository: ref.watch(fleetRepositoryProvider)),
    );

/// Biomedical waste management repository over the encrypted local projection.
final Provider<WasteRepository> wasteRepositoryProvider =
    Provider<WasteRepository>(
      (Ref ref) => DefaultWasteRepository(
        store: PowerSyncPatientStore(
          database: ref.watch(localDatabaseProvider),
        ),
        logger: ref.watch(loggerProvider),
      ),
    );

/// Register a waste category.
final Provider<RegisterCategoryUseCase> registerWasteCategoryUseCaseProvider =
    Provider<RegisterCategoryUseCase>(
      (Ref ref) => RegisterCategoryUseCase(
        repository: ref.watch(wasteRepositoryProvider),
      ),
    );

/// Update a waste category.
final Provider<UpdateCategoryUseCase> updateWasteCategoryUseCaseProvider =
    Provider<UpdateCategoryUseCase>(
      (Ref ref) =>
          UpdateCategoryUseCase(repository: ref.watch(wasteRepositoryProvider)),
    );

/// Log waste generation.
final Provider<LogGenerationUseCase> logWasteGenerationUseCaseProvider =
    Provider<LogGenerationUseCase>(
      (Ref ref) =>
          LogGenerationUseCase(repository: ref.watch(wasteRepositoryProvider)),
    );

/// Issue a disposal certificate.
final Provider<IssueCertificateUseCase> issueWasteCertificateUseCaseProvider =
    Provider<IssueCertificateUseCase>(
      (Ref ref) => IssueCertificateUseCase(
        repository: ref.watch(wasteRepositoryProvider),
      ),
    );

/// Void a disposal certificate.
final Provider<VoidCertificateUseCase> voidWasteCertificateUseCaseProvider =
    Provider<VoidCertificateUseCase>(
      (Ref ref) => VoidCertificateUseCase(
        repository: ref.watch(wasteRepositoryProvider),
      ),
    );

/// Read the waste board, logs, certificates and compliance.
final Provider<ReadWasteUseCase> readWasteUseCaseProvider =
    Provider<ReadWasteUseCase>(
      (Ref ref) =>
          ReadWasteUseCase(repository: ref.watch(wasteRepositoryProvider)),
    );

/// Health Insurance & TPA repository over the encrypted local projection.
final Provider<InsuranceRepository> insuranceRepositoryProvider =
    Provider<InsuranceRepository>(
      (Ref ref) => DefaultInsuranceRepository(
        store: PowerSyncPatientStore(
          database: ref.watch(localDatabaseProvider),
        ),
        logger: ref.watch(loggerProvider),
      ),
    );

/// Register a payer.
final Provider<RegisterPayerUseCase> registerPayerUseCaseProvider =
    Provider<RegisterPayerUseCase>(
      (Ref ref) => RegisterPayerUseCase(
        repository: ref.watch(insuranceRepositoryProvider),
      ),
    );

/// Update a payer.
final Provider<UpdatePayerUseCase> updatePayerUseCaseProvider =
    Provider<UpdatePayerUseCase>(
      (Ref ref) => UpdatePayerUseCase(
        repository: ref.watch(insuranceRepositoryProvider),
      ),
    );

/// Register a patient's insurance policy.
final Provider<RegisterPolicyUseCase> registerPolicyUseCaseProvider =
    Provider<RegisterPolicyUseCase>(
      (Ref ref) => RegisterPolicyUseCase(
        repository: ref.watch(insuranceRepositoryProvider),
      ),
    );

/// Update a policy that is still in force.
final Provider<UpdatePolicyUseCase> updatePolicyUseCaseProvider =
    Provider<UpdatePolicyUseCase>(
      (Ref ref) => UpdatePolicyUseCase(
        repository: ref.watch(insuranceRepositoryProvider),
      ),
    );

/// Record policy verification.
final Provider<VerifyPolicyUseCase> verifyPolicyUseCaseProvider =
    Provider<VerifyPolicyUseCase>(
      (Ref ref) => VerifyPolicyUseCase(
        repository: ref.watch(insuranceRepositoryProvider),
      ),
    );

/// Cancel a policy.
final Provider<CancelPolicyUseCase> cancelPolicyUseCaseProvider =
    Provider<CancelPolicyUseCase>(
      (Ref ref) => CancelPolicyUseCase(
        repository: ref.watch(insuranceRepositoryProvider),
      ),
    );

/// Raise a pre-authorisation request.
final Provider<RaisePreAuthorisationUseCase>
raisePreAuthorisationUseCaseProvider = Provider<RaisePreAuthorisationUseCase>(
  (Ref ref) => RaisePreAuthorisationUseCase(
    repository: ref.watch(insuranceRepositoryProvider),
  ),
);

/// Move a pre-authorisation request, or record the payer's answer.
final Provider<AdvancePreAuthorisationUseCase>
advancePreAuthorisationUseCaseProvider =
    Provider<AdvancePreAuthorisationUseCase>(
      (Ref ref) => AdvancePreAuthorisationUseCase(
        repository: ref.watch(insuranceRepositoryProvider),
      ),
    );

/// Create an electronic claim.
final Provider<CreateClaimUseCase> createClaimUseCaseProvider =
    Provider<CreateClaimUseCase>(
      (Ref ref) => CreateClaimUseCase(
        repository: ref.watch(insuranceRepositoryProvider),
      ),
    );

/// Move a claim, record the payer's decision, or record the settlement.
final Provider<AdvanceClaimUseCase> advanceClaimUseCaseProvider =
    Provider<AdvanceClaimUseCase>(
      (Ref ref) => AdvanceClaimUseCase(
        repository: ref.watch(insuranceRepositoryProvider),
      ),
    );

/// Read the insurance board, registry, requests and claims.
final Provider<ReadInsuranceUseCase> readInsuranceUseCaseProvider =
    Provider<ReadInsuranceUseCase>(
      (Ref ref) => ReadInsuranceUseCase(
        repository: ref.watch(insuranceRepositoryProvider),
      ),
    );

/// Documents & Biometric E-Consent Vault repository over the encrypted local
/// projection.
final Provider<DocumentsRepository> documentsRepositoryProvider =
    Provider<DocumentsRepository>(
      (Ref ref) => DefaultDocumentsRepository(
        store: PowerSyncPatientStore(
          database: ref.watch(localDatabaseProvider),
        ),
        logger: ref.watch(loggerProvider),
      ),
    );

/// Publish a consent template version.
final Provider<RegisterConsentTemplateUseCase>
registerConsentTemplateUseCaseProvider =
    Provider<RegisterConsentTemplateUseCase>(
      (Ref ref) => RegisterConsentTemplateUseCase(
        repository: ref.watch(documentsRepositoryProvider),
      ),
    );

/// Activate or retire a consent template version.
final Provider<SetConsentTemplateActiveUseCase>
setConsentTemplateActiveUseCaseProvider =
    Provider<SetConsentTemplateActiveUseCase>(
      (Ref ref) => SetConsentTemplateActiveUseCase(
        repository: ref.watch(documentsRepositoryProvider),
      ),
    );

/// Raise a patient consent.
final Provider<RaiseConsentUseCase> raiseConsentUseCaseProvider =
    Provider<RaiseConsentUseCase>(
      (Ref ref) => RaiseConsentUseCase(
        repository: ref.watch(documentsRepositoryProvider),
      ),
    );

/// Capture a stylus signature, biometric or witness attestation.
final Provider<CaptureConsentAttestationUseCase>
captureConsentAttestationUseCaseProvider =
    Provider<CaptureConsentAttestationUseCase>(
      (Ref ref) => CaptureConsentAttestationUseCase(
        repository: ref.watch(documentsRepositoryProvider),
      ),
    );

/// Sign a consent against a vaulted artefact.
final Provider<SignConsentUseCase> signConsentUseCaseProvider =
    Provider<SignConsentUseCase>(
      (Ref ref) => SignConsentUseCase(
        repository: ref.watch(documentsRepositoryProvider),
      ),
    );

/// Record that the patient declined a consent.
final Provider<DeclineConsentUseCase> declineConsentUseCaseProvider =
    Provider<DeclineConsentUseCase>(
      (Ref ref) => DeclineConsentUseCase(
        repository: ref.watch(documentsRepositoryProvider),
      ),
    );

/// Revoke a signed consent.
final Provider<RevokeConsentUseCase> revokeConsentUseCaseProvider =
    Provider<RevokeConsentUseCase>(
      (Ref ref) => RevokeConsentUseCase(
        repository: ref.watch(documentsRepositoryProvider),
      ),
    );

/// Index an artefact in the document vault.
final Provider<RegisterVaultDocumentUseCase>
registerVaultDocumentUseCaseProvider = Provider<RegisterVaultDocumentUseCase>(
  (Ref ref) => RegisterVaultDocumentUseCase(
    repository: ref.watch(documentsRepositoryProvider),
  ),
);

/// Supersede or void a vault entry.
final Provider<RetireVaultDocumentUseCase> retireVaultDocumentUseCaseProvider =
    Provider<RetireVaultDocumentUseCase>(
      (Ref ref) => RetireVaultDocumentUseCase(
        repository: ref.watch(documentsRepositoryProvider),
      ),
    );

/// Read the consent board, the template catalogue and the vault index.
final Provider<ReadConsentVaultUseCase> readConsentVaultUseCaseProvider =
    Provider<ReadConsentVaultUseCase>(
      (Ref ref) => ReadConsentVaultUseCase(
        repository: ref.watch(documentsRepositoryProvider),
      ),
    );

/// Statutory Records & Birth/Death Registry repository over the encrypted local
/// projection.
final Provider<StatutoryRepository> statutoryRepositoryProvider =
    Provider<StatutoryRepository>(
      (Ref ref) => DefaultStatutoryRepository(
        store: PowerSyncPatientStore(
          database: ref.watch(localDatabaseProvider),
        ),
        logger: ref.watch(loggerProvider),
      ),
    );

/// Raise a draft birth registration.
final Provider<RaiseBirthUseCase> raiseBirthUseCaseProvider =
    Provider<RaiseBirthUseCase>(
      (Ref ref) =>
          RaiseBirthUseCase(repository: ref.watch(statutoryRepositoryProvider)),
    );

/// Enter a draft birth in the register.
final Provider<RegisterBirthUseCase> registerBirthUseCaseProvider =
    Provider<RegisterBirthUseCase>(
      (Ref ref) => RegisterBirthUseCase(
        repository: ref.watch(statutoryRepositoryProvider),
      ),
    );

/// Issue a birth certificate.
final Provider<CertifyBirthUseCase> certifyBirthUseCaseProvider =
    Provider<CertifyBirthUseCase>(
      (Ref ref) => CertifyBirthUseCase(
        repository: ref.watch(statutoryRepositoryProvider),
      ),
    );

/// Raise a draft death registration.
final Provider<RaiseDeathUseCase> raiseDeathUseCaseProvider =
    Provider<RaiseDeathUseCase>(
      (Ref ref) =>
          RaiseDeathUseCase(repository: ref.watch(statutoryRepositoryProvider)),
    );

/// Record or correct the cause-of-death coding.
final Provider<RecordDeathCodingUseCase> recordDeathCodingUseCaseProvider =
    Provider<RecordDeathCodingUseCase>(
      (Ref ref) => RecordDeathCodingUseCase(
        repository: ref.watch(statutoryRepositoryProvider),
      ),
    );

/// Enter a draft death in the register.
final Provider<RegisterDeathUseCase> registerDeathUseCaseProvider =
    Provider<RegisterDeathUseCase>(
      (Ref ref) => RegisterDeathUseCase(
        repository: ref.watch(statutoryRepositoryProvider),
      ),
    );

/// Issue a death certificate.
final Provider<CertifyDeathUseCase> certifyDeathUseCaseProvider =
    Provider<CertifyDeathUseCase>(
      (Ref ref) => CertifyDeathUseCase(
        repository: ref.watch(statutoryRepositoryProvider),
      ),
    );

/// Log a medico-legal case.
final Provider<RaiseMlcIntimationUseCase> raiseMlcIntimationUseCaseProvider =
    Provider<RaiseMlcIntimationUseCase>(
      (Ref ref) => RaiseMlcIntimationUseCase(
        repository: ref.watch(statutoryRepositoryProvider),
      ),
    );

/// Record that the police have been told about a case.
final Provider<IntimatePoliceUseCase> intimatePoliceUseCaseProvider =
    Provider<IntimatePoliceUseCase>(
      (Ref ref) => IntimatePoliceUseCase(
        repository: ref.watch(statutoryRepositoryProvider),
      ),
    );

/// Record the police acknowledgement and reference.
final Provider<AcknowledgeMlcUseCase> acknowledgeMlcUseCaseProvider =
    Provider<AcknowledgeMlcUseCase>(
      (Ref ref) => AcknowledgeMlcUseCase(
        repository: ref.watch(statutoryRepositoryProvider),
      ),
    );

/// Close an acknowledged medico-legal case.
final Provider<CloseMlcUseCase> closeMlcUseCaseProvider =
    Provider<CloseMlcUseCase>(
      (Ref ref) =>
          CloseMlcUseCase(repository: ref.watch(statutoryRepositoryProvider)),
    );

/// Withdraw a live statutory record.
final Provider<VoidStatutoryRecordUseCase> voidStatutoryRecordUseCaseProvider =
    Provider<VoidStatutoryRecordUseCase>(
      (Ref ref) => VoidStatutoryRecordUseCase(
        repository: ref.watch(statutoryRepositoryProvider),
      ),
    );

/// Append a correction to a registered statutory fact.
final Provider<AppendStatutoryAmendmentUseCase>
appendStatutoryAmendmentUseCaseProvider =
    Provider<AppendStatutoryAmendmentUseCase>(
      (Ref ref) => AppendStatutoryAmendmentUseCase(
        repository: ref.watch(statutoryRepositoryProvider),
      ),
    );

/// Read the statutory registers and the amendment log.
final Provider<ReadStatutoryRegistryUseCase>
readStatutoryRegistryUseCaseProvider = Provider<ReadStatutoryRegistryUseCase>(
  (Ref ref) => ReadStatutoryRegistryUseCase(
    repository: ref.watch(statutoryRepositoryProvider),
  ),
);

/// Quality & NABH Compliance Hub repository over the encrypted local projection.
final Provider<QualityRepository> qualityRepositoryProvider =
    Provider<QualityRepository>(
      (Ref ref) => DefaultQualityRepository(
        store: PowerSyncPatientStore(
          database: ref.watch(localDatabaseProvider),
        ),
        logger: ref.watch(loggerProvider),
      ),
    );

/// Plan an accreditation compliance audit.
final Provider<ScheduleComplianceAuditUseCase>
scheduleComplianceAuditUseCaseProvider =
    Provider<ScheduleComplianceAuditUseCase>(
      (Ref ref) => ScheduleComplianceAuditUseCase(
        repository: ref.watch(qualityRepositoryProvider),
      ),
    );

/// Start a planned audit.
final Provider<StartComplianceAuditUseCase>
startComplianceAuditUseCaseProvider = Provider<StartComplianceAuditUseCase>(
  (Ref ref) => StartComplianceAuditUseCase(
    repository: ref.watch(qualityRepositoryProvider),
  ),
);

/// Score and complete an audit.
final Provider<CompleteComplianceAuditUseCase>
completeComplianceAuditUseCaseProvider =
    Provider<CompleteComplianceAuditUseCase>(
      (Ref ref) => CompleteComplianceAuditUseCase(
        repository: ref.watch(qualityRepositoryProvider),
      ),
    );

/// Call an audit off with a reason.
final Provider<CancelComplianceAuditUseCase>
cancelComplianceAuditUseCaseProvider = Provider<CancelComplianceAuditUseCase>(
  (Ref ref) => CancelComplianceAuditUseCase(
    repository: ref.watch(qualityRepositoryProvider),
  ),
);

/// Raise a patient safety incident report.
final Provider<ReportIncidentUseCase> reportIncidentUseCaseProvider =
    Provider<ReportIncidentUseCase>(
      (Ref ref) => ReportIncidentUseCase(
        repository: ref.watch(qualityRepositoryProvider),
      ),
    );

/// Open an investigation into an incident.
final Provider<InvestigateIncidentUseCase> investigateIncidentUseCaseProvider =
    Provider<InvestigateIncidentUseCase>(
      (Ref ref) => InvestigateIncidentUseCase(
        repository: ref.watch(qualityRepositoryProvider),
      ),
    );

/// Record the corrective action agreed for an incident.
final Provider<PlanIncidentActionUseCase> planIncidentActionUseCaseProvider =
    Provider<PlanIncidentActionUseCase>(
      (Ref ref) => PlanIncidentActionUseCase(
        repository: ref.watch(qualityRepositoryProvider),
      ),
    );

/// Close an incident with a note.
final Provider<CloseIncidentUseCase> closeIncidentUseCaseProvider =
    Provider<CloseIncidentUseCase>(
      (Ref ref) => CloseIncidentUseCase(
        repository: ref.watch(qualityRepositoryProvider),
      ),
    );

/// Withdraw an incident report.
final Provider<VoidIncidentUseCase> voidIncidentUseCaseProvider =
    Provider<VoidIncidentUseCase>(
      (Ref ref) =>
          VoidIncidentUseCase(repository: ref.watch(qualityRepositoryProvider)),
    );

/// Record a measured clinical indicator.
final Provider<RecordClinicalIndicatorUseCase>
recordClinicalIndicatorUseCaseProvider =
    Provider<RecordClinicalIndicatorUseCase>(
      (Ref ref) => RecordClinicalIndicatorUseCase(
        repository: ref.watch(qualityRepositoryProvider),
      ),
    );

/// Publish a recorded indicator.
final Provider<PublishClinicalIndicatorUseCase>
publishClinicalIndicatorUseCaseProvider =
    Provider<PublishClinicalIndicatorUseCase>(
      (Ref ref) => PublishClinicalIndicatorUseCase(
        repository: ref.watch(qualityRepositoryProvider),
      ),
    );

/// Retract a published indicator.
final Provider<RetractClinicalIndicatorUseCase>
retractClinicalIndicatorUseCaseProvider =
    Provider<RetractClinicalIndicatorUseCase>(
      (Ref ref) => RetractClinicalIndicatorUseCase(
        repository: ref.watch(qualityRepositoryProvider),
      ),
    );

/// Read the quality hub and its derived markers.
final Provider<ReadQualityHubUseCase> readQualityHubUseCaseProvider =
    Provider<ReadQualityHubUseCase>(
      (Ref ref) => ReadQualityHubUseCase(
        repository: ref.watch(qualityRepositoryProvider),
      ),
    );

/// Task repository over the encrypted local projection.
final Provider<TaskRepository> taskRepositoryProvider =
    Provider<TaskRepository>(
      (Ref ref) => DefaultTaskRepository(
        store: PowerSyncPatientStore(
          database: ref.watch(localDatabaseProvider),
        ),
        logger: ref.watch(loggerProvider),
      ),
    );

/// Raising a cross-department task.
final Provider<RaiseTaskUseCase> raiseTaskUseCaseProvider =
    Provider<RaiseTaskUseCase>(
      (Ref ref) =>
          RaiseTaskUseCase(repository: ref.watch(taskRepositoryProvider)),
    );

/// Claiming a task for the signed-in user.
final Provider<ClaimTaskUseCase> claimTaskUseCaseProvider =
    Provider<ClaimTaskUseCase>(
      (Ref ref) =>
          ClaimTaskUseCase(repository: ref.watch(taskRepositoryProvider)),
    );

/// Starting a claimed task.
final Provider<StartTaskUseCase> startTaskUseCaseProvider =
    Provider<StartTaskUseCase>(
      (Ref ref) =>
          StartTaskUseCase(repository: ref.watch(taskRepositoryProvider)),
    );

/// Completing a task with a note.
final Provider<CompleteTaskUseCase> completeTaskUseCaseProvider =
    Provider<CompleteTaskUseCase>(
      (Ref ref) =>
          CompleteTaskUseCase(repository: ref.watch(taskRepositoryProvider)),
    );

/// Cancelling a task with a reason.
final Provider<CancelTaskUseCase> cancelTaskUseCaseProvider =
    Provider<CancelTaskUseCase>(
      (Ref ref) =>
          CancelTaskUseCase(repository: ref.watch(taskRepositoryProvider)),
    );

/// Raising a task's priority.
final Provider<ReprioritiseTaskUseCase> reprioritiseTaskUseCaseProvider =
    Provider<ReprioritiseTaskUseCase>(
      (Ref ref) => ReprioritiseTaskUseCase(
        repository: ref.watch(taskRepositoryProvider),
      ),
    );

/// Reading the task board.
final Provider<ReadTaskBoardUseCase> readTaskBoardUseCaseProvider =
    Provider<ReadTaskBoardUseCase>(
      (Ref ref) =>
          ReadTaskBoardUseCase(repository: ref.watch(taskRepositoryProvider)),
    );

/// The patient's journey, read from the clinical modules (Module 50).
final Provider<TimelineRepository> timelineRepositoryProvider =
    Provider<TimelineRepository>(
      (Ref ref) => DefaultTimelineRepository(
        encounters: ref.watch(encounterRepositoryProvider),
        lab: ref.watch(labRepositoryProvider),
        prescriptions: ref.watch(prescriptionRepositoryProvider),
        appointments: ref.watch(appointmentRepositoryProvider),
        discharge: ref.watch(dischargeRepositoryProvider),
        theatre: ref.watch(otRepositoryProvider),
        logger: ref.watch(loggerProvider),
      ),
    );

/// Reading the patient's journey.
final Provider<ReadPatientTimelineUseCase> readPatientTimelineUseCaseProvider =
    Provider<ReadPatientTimelineUseCase>(
      (Ref ref) => ReadPatientTimelineUseCase(
        repository: ref.watch(timelineRepositoryProvider),
      ),
    );

/// Departmental flow for the operations dashboard (Module 02).
final Provider<OperationsRepository> operationsRepositoryProvider =
    Provider<OperationsRepository>(
      (Ref ref) => DefaultOperationsRepository(
        store: PowerSyncPatientStore(
          database: ref.watch(localDatabaseProvider),
        ),
        logger: ref.watch(loggerProvider),
      ),
    );

/// Reading the operations dashboard.
final Provider<ReadOperationsDashboardUseCase>
readOperationsDashboardUseCaseProvider =
    Provider<ReadOperationsDashboardUseCase>(
      (Ref ref) => ReadOperationsDashboardUseCase(
        repository: ref.watch(operationsRepositoryProvider),
      ),
    );

/// Clinical messaging (Module 43).
final Provider<MessagingRepository> messagingRepositoryProvider =
    Provider<MessagingRepository>(
      (Ref ref) => DefaultMessagingRepository(
        store: PowerSyncPatientStore(
          database: ref.watch(localDatabaseProvider),
        ),
        logger: ref.watch(loggerProvider),
      ),
    );

/// Reading the clinical discussions.
final Provider<ListThreadsUseCase> listThreadsUseCaseProvider =
    Provider<ListThreadsUseCase>(
      (Ref ref) => ListThreadsUseCase(
        repository: ref.watch(messagingRepositoryProvider),
      ),
    );

/// Reading the messages of a discussion.
final Provider<ListMessagesUseCase> listMessagesUseCaseProvider =
    Provider<ListMessagesUseCase>(
      (Ref ref) => ListMessagesUseCase(
        repository: ref.watch(messagingRepositoryProvider),
      ),
    );

/// Starting a clinical discussion.
final Provider<StartThreadUseCase> startThreadUseCaseProvider =
    Provider<StartThreadUseCase>(
      (Ref ref) => StartThreadUseCase(
        repository: ref.watch(messagingRepositoryProvider),
      ),
    );

/// Posting a message to a discussion.
final Provider<SendMessageUseCase> sendMessageUseCaseProvider =
    Provider<SendMessageUseCase>(
      (Ref ref) => SendMessageUseCase(
        repository: ref.watch(messagingRepositoryProvider),
      ),
    );

/// Boards, service requests and the private scratchpad (Module 44).
final Provider<ProductivityRepository> productivityRepositoryProvider =
    Provider<ProductivityRepository>(
      (Ref ref) => DefaultProductivityRepository(
        store: PowerSyncPatientStore(
          database: ref.watch(localDatabaseProvider),
        ),
        logger: ref.watch(loggerProvider),
      ),
    );

/// Reading a working board.
final Provider<ReadBoardUseCase> readBoardUseCaseProvider =
    Provider<ReadBoardUseCase>(
      (Ref ref) => ReadBoardUseCase(
        repository: ref.watch(productivityRepositoryProvider),
      ),
    );

/// Adding a card to a board.
final Provider<RaiseWorkItemUseCase> raiseWorkItemUseCaseProvider =
    Provider<RaiseWorkItemUseCase>(
      (Ref ref) => RaiseWorkItemUseCase(
        repository: ref.watch(productivityRepositoryProvider),
      ),
    );

/// Moving a card between lanes.
final Provider<MoveWorkItemUseCase> moveWorkItemUseCaseProvider =
    Provider<MoveWorkItemUseCase>(
      (Ref ref) => MoveWorkItemUseCase(
        repository: ref.watch(productivityRepositoryProvider),
      ),
    );

/// Reading the service requests.
final Provider<ReadTicketsUseCase> readTicketsUseCaseProvider =
    Provider<ReadTicketsUseCase>(
      (Ref ref) => ReadTicketsUseCase(
        repository: ref.watch(productivityRepositoryProvider),
      ),
    );

/// Opening a service request.
final Provider<RaiseTicketUseCase> raiseTicketUseCaseProvider =
    Provider<RaiseTicketUseCase>(
      (Ref ref) => RaiseTicketUseCase(
        repository: ref.watch(productivityRepositoryProvider),
      ),
    );

/// Resolving a service request.
final Provider<ResolveTicketUseCase> resolveTicketUseCaseProvider =
    Provider<ResolveTicketUseCase>(
      (Ref ref) => ResolveTicketUseCase(
        repository: ref.watch(productivityRepositoryProvider),
      ),
    );

/// Reading the clinician's own notes.
final Provider<ReadScratchpadUseCase> readScratchpadUseCaseProvider =
    Provider<ReadScratchpadUseCase>(
      (Ref ref) => ReadScratchpadUseCase(
        repository: ref.watch(productivityRepositoryProvider),
      ),
    );

/// Writing the clinician's own notes.
final Provider<WriteScratchpadUseCase> writeScratchpadUseCaseProvider =
    Provider<WriteScratchpadUseCase>(
      (Ref ref) => WriteScratchpadUseCase(
        repository: ref.watch(productivityRepositoryProvider),
      ),
    );

/// Clinical form templates and responses (Module 47).
final Provider<FormRepository> formRepositoryProvider =
    Provider<FormRepository>(
      (Ref ref) => DefaultFormRepository(
        store: PowerSyncPatientStore(
          database: ref.watch(localDatabaseProvider),
        ),
        logger: ref.watch(loggerProvider),
      ),
    );

/// Listing the forms a clinician may fill in.
final Provider<ListFormTemplatesUseCase> listFormTemplatesUseCaseProvider =
    Provider<ListFormTemplatesUseCase>(
      (Ref ref) => ListFormTemplatesUseCase(
        repository: ref.watch(formRepositoryProvider),
      ),
    );

/// Searching the ICD-10 catalogue.
final Provider<SearchIcd10UseCase> searchIcd10UseCaseProvider =
    Provider<SearchIcd10UseCase>(
      (Ref ref) =>
          SearchIcd10UseCase(repository: ref.watch(formRepositoryProvider)),
    );

/// Recording a filled form.
final Provider<SubmitFormResponseUseCase> submitFormResponseUseCaseProvider =
    Provider<SubmitFormResponseUseCase>(
      (Ref ref) => SubmitFormResponseUseCase(
        repository: ref.watch(formRepositoryProvider),
      ),
    );

/// Listing the forms recorded for a patient.
final Provider<ListFormResponsesUseCase> listFormResponsesUseCaseProvider =
    Provider<ListFormResponsesUseCase>(
      (Ref ref) => ListFormResponsesUseCase(
        repository: ref.watch(formRepositoryProvider),
      ),
    );

/// Patient feedback and grievance repository over the encrypted local projection.
final Provider<FeedbackRepository> feedbackRepositoryProvider =
    Provider<FeedbackRepository>(
      (Ref ref) => DefaultFeedbackRepository(
        store: PowerSyncPatientStore(
          database: ref.watch(localDatabaseProvider),
        ),
        logger: ref.watch(loggerProvider),
      ),
    );

/// Capture a Net Promoter Score response.
final Provider<RecordSurveyUseCase> recordSurveyUseCaseProvider =
    Provider<RecordSurveyUseCase>(
      (Ref ref) => RecordSurveyUseCase(
        repository: ref.watch(feedbackRepositoryProvider),
      ),
    );

/// Record what was done about a detractor.
final Provider<ActionSurveyUseCase> actionSurveyUseCaseProvider =
    Provider<ActionSurveyUseCase>(
      (Ref ref) => ActionSurveyUseCase(
        repository: ref.watch(feedbackRepositoryProvider),
      ),
    );

/// Withdraw a survey response.
final Provider<VoidSurveyUseCase> voidSurveyUseCaseProvider =
    Provider<VoidSurveyUseCase>(
      (Ref ref) =>
          VoidSurveyUseCase(repository: ref.watch(feedbackRepositoryProvider)),
    );

/// Log a grievance at the desk that took it.
final Provider<LogComplaintUseCase> logComplaintUseCaseProvider =
    Provider<LogComplaintUseCase>(
      (Ref ref) => LogComplaintUseCase(
        repository: ref.watch(feedbackRepositoryProvider),
      ),
    );

/// Acknowledge a grievance.
final Provider<AcknowledgeComplaintUseCase>
acknowledgeComplaintUseCaseProvider = Provider<AcknowledgeComplaintUseCase>(
  (Ref ref) => AcknowledgeComplaintUseCase(
    repository: ref.watch(feedbackRepositoryProvider),
  ),
);

/// Route or re-route a grievance.
final Provider<RouteComplaintUseCase> routeComplaintUseCaseProvider =
    Provider<RouteComplaintUseCase>(
      (Ref ref) => RouteComplaintUseCase(
        repository: ref.watch(feedbackRepositoryProvider),
      ),
    );

/// Escalate a grievance on the record.
final Provider<EscalateComplaintUseCase> escalateComplaintUseCaseProvider =
    Provider<EscalateComplaintUseCase>(
      (Ref ref) => EscalateComplaintUseCase(
        repository: ref.watch(feedbackRepositoryProvider),
      ),
    );

/// Open an investigation into a grievance.
final Provider<InvestigateComplaintUseCase>
investigateComplaintUseCaseProvider = Provider<InvestigateComplaintUseCase>(
  (Ref ref) => InvestigateComplaintUseCase(
    repository: ref.watch(feedbackRepositoryProvider),
  ),
);

/// Answer a grievance.
final Provider<ResolveComplaintUseCase> resolveComplaintUseCaseProvider =
    Provider<ResolveComplaintUseCase>(
      (Ref ref) => ResolveComplaintUseCase(
        repository: ref.watch(feedbackRepositoryProvider),
      ),
    );

/// Close a resolved grievance.
final Provider<CloseComplaintUseCase> closeComplaintUseCaseProvider =
    Provider<CloseComplaintUseCase>(
      (Ref ref) => CloseComplaintUseCase(
        repository: ref.watch(feedbackRepositoryProvider),
      ),
    );

/// Dismiss a grievance that has no substance.
final Provider<DismissComplaintUseCase> dismissComplaintUseCaseProvider =
    Provider<DismissComplaintUseCase>(
      (Ref ref) => DismissComplaintUseCase(
        repository: ref.watch(feedbackRepositoryProvider),
      ),
    );

/// Withdraw a grievance filed in error.
final Provider<VoidComplaintUseCase> voidComplaintUseCaseProvider =
    Provider<VoidComplaintUseCase>(
      (Ref ref) => VoidComplaintUseCase(
        repository: ref.watch(feedbackRepositoryProvider),
      ),
    );

/// Read the feedback registers and their derived markers.
final Provider<ReadFeedbackHubUseCase> readFeedbackHubUseCaseProvider =
    Provider<ReadFeedbackHubUseCase>(
      (Ref ref) => ReadFeedbackHubUseCase(
        repository: ref.watch(feedbackRepositoryProvider),
      ),
    );

/// Visitor and pass repository over the encrypted local projection.
final Provider<VisitorRepository> visitorRepositoryProvider =
    Provider<VisitorRepository>(
      (Ref ref) => DefaultVisitorRepository(
        store: PowerSyncPatientStore(
          database: ref.watch(localDatabaseProvider),
        ),
        logger: ref.watch(loggerProvider),
      ),
    );

/// Set the visiting window a ward admits visitors under.
final Provider<SetVisitingWindowUseCase> setVisitingWindowUseCaseProvider =
    Provider<SetVisitingWindowUseCase>(
      (Ref ref) => SetVisitingWindowUseCase(
        repository: ref.watch(visitorRepositoryProvider),
      ),
    );

/// Retire a visiting window.
final Provider<ArchiveVisitingWindowUseCase>
archiveVisitingWindowUseCaseProvider = Provider<ArchiveVisitingWindowUseCase>(
  (Ref ref) => ArchiveVisitingWindowUseCase(
    repository: ref.watch(visitorRepositoryProvider),
  ),
);

/// Take a visitor at the gate.
final Provider<RegisterVisitorUseCase> registerVisitorUseCaseProvider =
    Provider<RegisterVisitorUseCase>(
      (Ref ref) => RegisterVisitorUseCase(
        repository: ref.watch(visitorRepositoryProvider),
      ),
    );

/// Admit a visitor.
final Provider<AdmitVisitorUseCase> admitVisitorUseCaseProvider =
    Provider<AdmitVisitorUseCase>(
      (Ref ref) =>
          AdmitVisitorUseCase(repository: ref.watch(visitorRepositoryProvider)),
    );

/// Record a visitor leaving.
final Provider<RecordVisitorDepartureUseCase>
recordVisitorDepartureUseCaseProvider = Provider<RecordVisitorDepartureUseCase>(
  (Ref ref) => RecordVisitorDepartureUseCase(
    repository: ref.watch(visitorRepositoryProvider),
  ),
);

/// Turn a visitor away at the gate.
final Provider<RefuseVisitorUseCase> refuseVisitorUseCaseProvider =
    Provider<RefuseVisitorUseCase>(
      (Ref ref) => RefuseVisitorUseCase(
        repository: ref.watch(visitorRepositoryProvider),
      ),
    );

/// Withdraw a registration entered in error.
final Provider<VoidVisitorRegistrationUseCase>
voidVisitorRegistrationUseCaseProvider =
    Provider<VoidVisitorRegistrationUseCase>(
      (Ref ref) => VoidVisitorRegistrationUseCase(
        repository: ref.watch(visitorRepositoryProvider),
      ),
    );

/// Issue a digital entry pass.
final Provider<IssueVisitorPassUseCase> issueVisitorPassUseCaseProvider =
    Provider<IssueVisitorPassUseCase>(
      (Ref ref) => IssueVisitorPassUseCase(
        repository: ref.watch(visitorRepositoryProvider),
      ),
    );

/// Activate a pass as its holder goes in.
final Provider<ActivateVisitorPassUseCase> activateVisitorPassUseCaseProvider =
    Provider<ActivateVisitorPassUseCase>(
      (Ref ref) => ActivateVisitorPassUseCase(
        repository: ref.watch(visitorRepositoryProvider),
      ),
    );

/// Record a badge handed back at the gate.
final Provider<ReturnVisitorPassUseCase> returnVisitorPassUseCaseProvider =
    Provider<ReturnVisitorPassUseCase>(
      (Ref ref) => ReturnVisitorPassUseCase(
        repository: ref.watch(visitorRepositoryProvider),
      ),
    );

/// Revoke a pass before its window closed.
final Provider<RevokeVisitorPassUseCase> revokeVisitorPassUseCaseProvider =
    Provider<RevokeVisitorPassUseCase>(
      (Ref ref) => RevokeVisitorPassUseCase(
        repository: ref.watch(visitorRepositoryProvider),
      ),
    );

/// Record a thermal badge print.
final Provider<RecordBadgePrintUseCase> recordBadgePrintUseCaseProvider =
    Provider<RecordBadgePrintUseCase>(
      (Ref ref) => RecordBadgePrintUseCase(
        repository: ref.watch(visitorRepositoryProvider),
      ),
    );

/// Read the visitor desk and its derived markers.
final Provider<ReadVisitorDeskUseCase> readVisitorDeskUseCaseProvider =
    Provider<ReadVisitorDeskUseCase>(
      (Ref ref) => ReadVisitorDeskUseCase(
        repository: ref.watch(visitorRepositoryProvider),
      ),
    );

/// Analytics warehouse repository over the encrypted local projection.
final Provider<AnalyticsRepository> analyticsRepositoryProvider =
    Provider<AnalyticsRepository>(
      (Ref ref) => DefaultAnalyticsRepository(
        store: PowerSyncPatientStore(
          database: ref.watch(localDatabaseProvider),
        ),
        logger: ref.watch(loggerProvider),
      ),
    );

/// Add a report to the catalogue.
final Provider<DefineReportUseCase> defineReportUseCaseProvider =
    Provider<DefineReportUseCase>(
      (Ref ref) => DefineReportUseCase(
        repository: ref.watch(analyticsRepositoryProvider),
      ),
    );

/// Publish a report, freezing its query contract.
final Provider<PublishReportUseCase> publishReportUseCaseProvider =
    Provider<PublishReportUseCase>(
      (Ref ref) => PublishReportUseCase(
        repository: ref.watch(analyticsRepositoryProvider),
      ),
    );

/// Retire a report.
final Provider<RetireReportUseCase> retireReportUseCaseProvider =
    Provider<RetireReportUseCase>(
      (Ref ref) => RetireReportUseCase(
        repository: ref.watch(analyticsRepositoryProvider),
      ),
    );

/// Write the rolling rollup for a period.
final Provider<MaterialiseRollupUseCase> materialiseRollupUseCaseProvider =
    Provider<MaterialiseRollupUseCase>(
      (Ref ref) => MaterialiseRollupUseCase(
        repository: ref.watch(analyticsRepositoryProvider),
      ),
    );

/// Withdraw a figure that should not stand.
final Provider<VoidRollupUseCase> voidRollupUseCaseProvider =
    Provider<VoidRollupUseCase>(
      (Ref ref) =>
          VoidRollupUseCase(repository: ref.watch(analyticsRepositoryProvider)),
    );

/// Queue a run of a published report.
final Provider<QueueReportRunUseCase> queueReportRunUseCaseProvider =
    Provider<QueueReportRunUseCase>(
      (Ref ref) => QueueReportRunUseCase(
        repository: ref.watch(analyticsRepositoryProvider),
      ),
    );

/// Start a queued run against the read replica.
final Provider<StartReportRunUseCase> startReportRunUseCaseProvider =
    Provider<StartReportRunUseCase>(
      (Ref ref) => StartReportRunUseCase(
        repository: ref.watch(analyticsRepositoryProvider),
      ),
    );

/// Finish a run with rows.
final Provider<CompleteReportRunUseCase> completeReportRunUseCaseProvider =
    Provider<CompleteReportRunUseCase>(
      (Ref ref) => CompleteReportRunUseCase(
        repository: ref.watch(analyticsRepositoryProvider),
      ),
    );

/// Finish a run without rows.
final Provider<FailReportRunUseCase> failReportRunUseCaseProvider =
    Provider<FailReportRunUseCase>(
      (Ref ref) => FailReportRunUseCase(
        repository: ref.watch(analyticsRepositoryProvider),
      ),
    );

/// Abandon a run.
final Provider<CancelReportRunUseCase> cancelReportRunUseCaseProvider =
    Provider<CancelReportRunUseCase>(
      (Ref ref) => CancelReportRunUseCase(
        repository: ref.watch(analyticsRepositoryProvider),
      ),
    );

/// Take a report artefact out of the hospital.
final Provider<ExportReportRunUseCase> exportReportRunUseCaseProvider =
    Provider<ExportReportRunUseCase>(
      (Ref ref) => ExportReportRunUseCase(
        repository: ref.watch(analyticsRepositoryProvider),
      ),
    );

/// Read the analytics warehouse and its derived markers.
final Provider<ReadAnalyticsWarehouseUseCase>
readAnalyticsWarehouseUseCaseProvider = Provider<ReadAnalyticsWarehouseUseCase>(
  (Ref ref) => ReadAnalyticsWarehouseUseCase(
    repository: ref.watch(analyticsRepositoryProvider),
  ),
);

/// The second-factor verifier the master settings hub steps up with.
///
/// The stub stands in for the identity provider's own multi-factor challenge,
/// which is where a real code belongs: a code this app generated and this app
/// checked would be a code an attacker on this device could generate too.
final Provider<SecondFactorVerifier> secondFactorVerifierProvider =
    Provider<SecondFactorVerifier>(
      (Ref ref) => const StubSecondFactorVerifier(),
    );

/// Master settings repository over the encrypted local projection.
final Provider<SettingsRepository> settingsRepositoryProvider =
    Provider<SettingsRepository>(
      (Ref ref) => DefaultSettingsRepository(
        store: PowerSyncPatientStore(
          database: ref.watch(localDatabaseProvider),
        ),
        logger: ref.watch(loggerProvider),
      ),
    );

/// Write a new draft hospital configuration.
final Provider<DraftSettingsProfileUseCase>
draftSettingsProfileUseCaseProvider = Provider<DraftSettingsProfileUseCase>(
  (Ref ref) => DraftSettingsProfileUseCase(
    repository: ref.watch(settingsRepositoryProvider),
  ),
);

/// Bring a hospital configuration into force.
final Provider<ActivateSettingsProfileUseCase>
activateSettingsProfileUseCaseProvider =
    Provider<ActivateSettingsProfileUseCase>(
      (Ref ref) => ActivateSettingsProfileUseCase(
        repository: ref.watch(settingsRepositoryProvider),
      ),
    );

/// Register a branding asset, awaiting publication.
final Provider<DraftBrandingAssetUseCase> draftBrandingAssetUseCaseProvider =
    Provider<DraftBrandingAssetUseCase>(
      (Ref ref) => DraftBrandingAssetUseCase(
        repository: ref.watch(settingsRepositoryProvider),
      ),
    );

/// Publish a branding asset.
final Provider<PublishBrandingAssetUseCase>
publishBrandingAssetUseCaseProvider = Provider<PublishBrandingAssetUseCase>(
  (Ref ref) => PublishBrandingAssetUseCase(
    repository: ref.watch(settingsRepositoryProvider),
  ),
);

/// Add a department to the tree.
final Provider<DefineDepartmentUseCase> defineDepartmentUseCaseProvider =
    Provider<DefineDepartmentUseCase>(
      (Ref ref) => DefineDepartmentUseCase(
        repository: ref.watch(settingsRepositoryProvider),
      ),
    );

/// Close a department.
final Provider<CloseDepartmentUseCase> closeDepartmentUseCaseProvider =
    Provider<CloseDepartmentUseCase>(
      (Ref ref) => CloseDepartmentUseCase(
        repository: ref.watch(settingsRepositoryProvider),
      ),
    );

/// Price a service into a draft tariff.
final Provider<SetTariffUseCase> setTariffUseCaseProvider =
    Provider<SetTariffUseCase>(
      (Ref ref) =>
          SetTariffUseCase(repository: ref.watch(settingsRepositoryProvider)),
    );

/// Approve a tariff into life.
final Provider<ApproveTariffUseCase> approveTariffUseCaseProvider =
    Provider<ApproveTariffUseCase>(
      (Ref ref) => ApproveTariffUseCase(
        repository: ref.watch(settingsRepositoryProvider),
      ),
    );

/// Retire a tariff.
final Provider<RetireTariffUseCase> retireTariffUseCaseProvider =
    Provider<RetireTariffUseCase>(
      (Ref ref) => RetireTariffUseCase(
        repository: ref.watch(settingsRepositoryProvider),
      ),
    );

/// Propose an AI routing profile.
final Provider<DefineRoutingProfileUseCase>
defineRoutingProfileUseCaseProvider = Provider<DefineRoutingProfileUseCase>(
  (Ref ref) => DefineRoutingProfileUseCase(
    repository: ref.watch(settingsRepositoryProvider),
  ),
);

/// Put an AI routing profile to work.
final Provider<ActivateRoutingProfileUseCase>
activateRoutingProfileUseCaseProvider = Provider<ActivateRoutingProfileUseCase>(
  (Ref ref) => ActivateRoutingProfileUseCase(
    repository: ref.watch(settingsRepositoryProvider),
  ),
);

/// Retire an AI routing profile.
final Provider<RetireRoutingProfileUseCase>
retireRoutingProfileUseCaseProvider = Provider<RetireRoutingProfileUseCase>(
  (Ref ref) => RetireRoutingProfileUseCase(
    repository: ref.watch(settingsRepositoryProvider),
  ),
);

/// Read the master settings hub and its derived markers.
final Provider<ReadMasterSettingsUseCase> readMasterSettingsUseCaseProvider =
    Provider<ReadMasterSettingsUseCase>(
      (Ref ref) => ReadMasterSettingsUseCase(
        repository: ref.watch(settingsRepositoryProvider),
      ),
    );

/// Institutional calendar repository over the encrypted local projection.
final Provider<CalendarRepository> calendarRepositoryProvider =
    Provider<CalendarRepository>(
      (Ref ref) => DefaultCalendarRepository(
        store: PowerSyncPatientStore(
          database: ref.watch(localDatabaseProvider),
        ),
        logger: ref.watch(loggerProvider),
      ),
    );

/// Create an institutional calendar event.
final Provider<CreateCalendarEventUseCase> createCalendarEventUseCaseProvider =
    Provider<CreateCalendarEventUseCase>(
      (Ref ref) => CreateCalendarEventUseCase(
        repository: ref.watch(calendarRepositoryProvider),
      ),
    );

/// Update a scheduled calendar event.
final Provider<UpdateCalendarEventUseCase> updateCalendarEventUseCaseProvider =
    Provider<UpdateCalendarEventUseCase>(
      (Ref ref) => UpdateCalendarEventUseCase(
        repository: ref.watch(calendarRepositoryProvider),
      ),
    );

/// Cancel a calendar event.
final Provider<CancelCalendarEventUseCase> cancelCalendarEventUseCaseProvider =
    Provider<CancelCalendarEventUseCase>(
      (Ref ref) => CancelCalendarEventUseCase(
        repository: ref.watch(calendarRepositoryProvider),
      ),
    );

/// Read the institutional calendar and build the shift overlay.
final Provider<ReadCalendarUseCase> readCalendarUseCaseProvider =
    Provider<ReadCalendarUseCase>(
      (Ref ref) => ReadCalendarUseCase(
        repository: ref.watch(calendarRepositoryProvider),
      ),
    );

/// Hospital contacts directory repository over the encrypted local projection.
final Provider<ContactRepository> contactRepositoryProvider =
    Provider<ContactRepository>(
      (Ref ref) => DefaultContactRepository(
        store: PowerSyncPatientStore(
          database: ref.watch(localDatabaseProvider),
        ),
        logger: ref.watch(loggerProvider),
      ),
    );

/// Register a hospital contact.
final Provider<RegisterContactUseCase> registerContactUseCaseProvider =
    Provider<RegisterContactUseCase>(
      (Ref ref) => RegisterContactUseCase(
        repository: ref.watch(contactRepositoryProvider),
      ),
    );

/// Update a hospital contact.
final Provider<UpdateContactUseCase> updateContactUseCaseProvider =
    Provider<UpdateContactUseCase>(
      (Ref ref) => UpdateContactUseCase(
        repository: ref.watch(contactRepositoryProvider),
      ),
    );

/// Archive a hospital contact.
final Provider<ArchiveContactUseCase> archiveContactUseCaseProvider =
    Provider<ArchiveContactUseCase>(
      (Ref ref) => ArchiveContactUseCase(
        repository: ref.watch(contactRepositoryProvider),
      ),
    );

/// Read the hospital contacts directory.
final Provider<ListContactsUseCase> listContactsUseCaseProvider =
    Provider<ListContactsUseCase>(
      (Ref ref) =>
          ListContactsUseCase(repository: ref.watch(contactRepositoryProvider)),
    );

/// Department registry repository over the encrypted local projection.
final Provider<DepartmentRepository> departmentRepositoryProvider =
    Provider<DepartmentRepository>(
      (Ref ref) => DefaultDepartmentRepository(
        store: PowerSyncPatientStore(
          database: ref.watch(localDatabaseProvider),
        ),
        logger: ref.watch(loggerProvider),
      ),
    );

/// Register a department into the registry.
final Provider<RegisterDepartmentUseCase> registerDepartmentUseCaseProvider =
    Provider<RegisterDepartmentUseCase>(
      (Ref ref) => RegisterDepartmentUseCase(
        repository: ref.watch(departmentRepositoryProvider),
      ),
    );

/// Update a department's registry facts.
final Provider<UpdateDepartmentUseCase> updateDepartmentUseCaseProvider =
    Provider<UpdateDepartmentUseCase>(
      (Ref ref) => UpdateDepartmentUseCase(
        repository: ref.watch(departmentRepositoryProvider),
      ),
    );

/// Archive a department.
final Provider<ArchiveDepartmentUseCase> archiveDepartmentUseCaseProvider =
    Provider<ArchiveDepartmentUseCase>(
      (Ref ref) => ArchiveDepartmentUseCase(
        repository: ref.watch(departmentRepositoryProvider),
      ),
    );

/// Read the department registry.
final Provider<ListDepartmentsUseCase> listDepartmentsUseCaseProvider =
    Provider<ListDepartmentsUseCase>(
      (Ref ref) => ListDepartmentsUseCase(
        repository: ref.watch(departmentRepositoryProvider),
      ),
    );

/// Practitioner directory repository over the encrypted local projection.
final Provider<PractitionerRepository> practitionerRepositoryProvider =
    Provider<PractitionerRepository>(
      (Ref ref) => DefaultPractitionerRepository(
        store: PowerSyncPatientStore(
          database: ref.watch(localDatabaseProvider),
        ),
        logger: ref.watch(loggerProvider),
      ),
    );

/// Register a practitioner into the directory.
final Provider<RecordPractitionerProfileUseCase>
recordPractitionerProfileUseCaseProvider =
    Provider<RecordPractitionerProfileUseCase>(
      (Ref ref) => RecordPractitionerProfileUseCase(
        repository: ref.watch(practitionerRepositoryProvider),
      ),
    );

/// Update a practitioner's directory facts.
final Provider<UpdatePractitionerProfileUseCase>
updatePractitionerProfileUseCaseProvider =
    Provider<UpdatePractitionerProfileUseCase>(
      (Ref ref) => UpdatePractitionerProfileUseCase(
        repository: ref.watch(practitionerRepositoryProvider),
      ),
    );

/// Retire a practitioner.
final Provider<RetirePractitionerProfileUseCase>
retirePractitionerProfileUseCaseProvider =
    Provider<RetirePractitionerProfileUseCase>(
      (Ref ref) => RetirePractitionerProfileUseCase(
        repository: ref.watch(practitionerRepositoryProvider),
      ),
    );

/// Schedule an on-call rotation.
final Provider<ScheduleOnCallRotationUseCase>
scheduleOnCallRotationUseCaseProvider = Provider<ScheduleOnCallRotationUseCase>(
  (Ref ref) => ScheduleOnCallRotationUseCase(
    repository: ref.watch(practitionerRepositoryProvider),
  ),
);

/// Search the directory.
final Provider<SearchPractitionersUseCase> searchPractitionersUseCaseProvider =
    Provider<SearchPractitionersUseCase>(
      (Ref ref) => SearchPractitionersUseCase(
        repository: ref.watch(practitionerRepositoryProvider),
      ),
    );

/// Workforce repository over the encrypted local projection.
final Provider<WorkforceRepository> workforceRepositoryProvider =
    Provider<WorkforceRepository>(
      (Ref ref) => DefaultWorkforceRepository(
        store: PowerSyncPatientStore(
          database: ref.watch(localDatabaseProvider),
        ),
        logger: ref.watch(loggerProvider),
      ),
    );

/// Schedule a dated staff shift.
final Provider<ScheduleStaffShiftUseCase> scheduleStaffShiftUseCaseProvider =
    Provider<ScheduleStaffShiftUseCase>(
      (Ref ref) => ScheduleStaffShiftUseCase(
        repository: ref.watch(workforceRepositoryProvider),
      ),
    );

/// Edit a scheduled shift.
final Provider<UpdateStaffShiftUseCase> updateStaffShiftUseCaseProvider =
    Provider<UpdateStaffShiftUseCase>(
      (Ref ref) => UpdateStaffShiftUseCase(
        repository: ref.watch(workforceRepositoryProvider),
      ),
    );

/// Cancel a scheduled shift.
final Provider<CancelStaffShiftUseCase> cancelStaffShiftUseCaseProvider =
    Provider<CancelStaffShiftUseCase>(
      (Ref ref) => CancelStaffShiftUseCase(
        repository: ref.watch(workforceRepositoryProvider),
      ),
    );

/// Close a finished shift.
final Provider<CloseStaffShiftUseCase> closeStaffShiftUseCaseProvider =
    Provider<CloseStaffShiftUseCase>(
      (Ref ref) => CloseStaffShiftUseCase(
        repository: ref.watch(workforceRepositoryProvider),
      ),
    );

/// Allocate a staff member to a shift.
final Provider<AllocateDutyUseCase> allocateDutyUseCaseProvider =
    Provider<AllocateDutyUseCase>(
      (Ref ref) => AllocateDutyUseCase(
        repository: ref.watch(workforceRepositoryProvider),
      ),
    );

/// Withdraw a duty allocation.
final Provider<WithdrawAllocationUseCase> withdrawAllocationUseCaseProvider =
    Provider<WithdrawAllocationUseCase>(
      (Ref ref) => WithdrawAllocationUseCase(
        repository: ref.watch(workforceRepositoryProvider),
      ),
    );

/// Record an attendance event.
final Provider<RecordAttendanceUseCase> recordAttendanceUseCaseProvider =
    Provider<RecordAttendanceUseCase>(
      (Ref ref) => RecordAttendanceUseCase(
        repository: ref.watch(workforceRepositoryProvider),
      ),
    );

/// Read the workforce rosters.
final Provider<ReadWorkforceUseCase> readWorkforceUseCaseProvider =
    Provider<ReadWorkforceUseCase>(
      (Ref ref) => ReadWorkforceUseCase(
        repository: ref.watch(workforceRepositoryProvider),
      ),
    );

/// Nurse ward station repository over the encrypted local projection.
final Provider<NursingStationRepository> nursingStationRepositoryProvider =
    Provider<NursingStationRepository>(
      (Ref ref) => DefaultNursingStationRepository(
        store: PowerSyncPatientStore(
          database: ref.watch(localDatabaseProvider),
        ),
        logger: ref.watch(loggerProvider),
      ),
    );

/// Record a routine ward observation.
final Provider<RecordWardVitalsUseCase> recordWardVitalsUseCaseProvider =
    Provider<RecordWardVitalsUseCase>(
      (Ref ref) => RecordWardVitalsUseCase(
        repository: ref.watch(nursingStationRepositoryProvider),
      ),
    );

/// Record a shift nursing handover.
final Provider<RecordWardHandoverUseCase> recordWardHandoverUseCaseProvider =
    Provider<RecordWardHandoverUseCase>(
      (Ref ref) => RecordWardHandoverUseCase(
        repository: ref.watch(nursingStationRepositoryProvider),
      ),
    );

/// Create a ward task.
final Provider<CreateWardTaskUseCase> createWardTaskUseCaseProvider =
    Provider<CreateWardTaskUseCase>(
      (Ref ref) => CreateWardTaskUseCase(
        repository: ref.watch(nursingStationRepositoryProvider),
      ),
    );

/// Delegate a ward task.
final Provider<AssignWardTaskUseCase> assignWardTaskUseCaseProvider =
    Provider<AssignWardTaskUseCase>(
      (Ref ref) => AssignWardTaskUseCase(
        repository: ref.watch(nursingStationRepositoryProvider),
      ),
    );

/// Start a ward task.
final Provider<StartWardTaskUseCase> startWardTaskUseCaseProvider =
    Provider<StartWardTaskUseCase>(
      (Ref ref) => StartWardTaskUseCase(
        repository: ref.watch(nursingStationRepositoryProvider),
      ),
    );

/// Close a ward task.
final Provider<CloseWardTaskUseCase> closeWardTaskUseCaseProvider =
    Provider<CloseWardTaskUseCase>(
      (Ref ref) => CloseWardTaskUseCase(
        repository: ref.watch(nursingStationRepositoryProvider),
      ),
    );

/// Read the ward station board.
final Provider<ReadWardStationUseCase> readWardStationUseCaseProvider =
    Provider<ReadWardStationUseCase>(
      (Ref ref) => ReadWardStationUseCase(
        repository: ref.watch(nursingStationRepositoryProvider),
      ),
    );

/// Human resources & payroll repository over the encrypted local projection.
final Provider<HrRepository> hrRepositoryProvider = Provider<HrRepository>(
  (Ref ref) => DefaultHrRepository(
    store: PowerSyncPatientStore(database: ref.watch(localDatabaseProvider)),
    logger: ref.watch(loggerProvider),
  ),
);

/// Register an employment record.
final Provider<RegisterEmployeeUseCase> registerEmployeeUseCaseProvider =
    Provider<RegisterEmployeeUseCase>(
      (Ref ref) =>
          RegisterEmployeeUseCase(repository: ref.watch(hrRepositoryProvider)),
    );

/// Edit an employment record.
final Provider<UpdateEmployeeUseCase> updateEmployeeUseCaseProvider =
    Provider<UpdateEmployeeUseCase>(
      (Ref ref) =>
          UpdateEmployeeUseCase(repository: ref.watch(hrRepositoryProvider)),
    );

/// Confirm an employee in post.
final Provider<ConfirmEmployeeUseCase> confirmEmployeeUseCaseProvider =
    Provider<ConfirmEmployeeUseCase>(
      (Ref ref) =>
          ConfirmEmployeeUseCase(repository: ref.watch(hrRepositoryProvider)),
    );

/// Separate an employee.
final Provider<SeparateEmployeeUseCase> separateEmployeeUseCaseProvider =
    Provider<SeparateEmployeeUseCase>(
      (Ref ref) =>
          SeparateEmployeeUseCase(repository: ref.watch(hrRepositoryProvider)),
    );

/// Raise a leave application.
final Provider<RequestLeaveUseCase> requestLeaveUseCaseProvider =
    Provider<RequestLeaveUseCase>(
      (Ref ref) =>
          RequestLeaveUseCase(repository: ref.watch(hrRepositoryProvider)),
    );

/// Approve or reject a leave application.
final Provider<DecideLeaveUseCase> decideLeaveUseCaseProvider =
    Provider<DecideLeaveUseCase>(
      (Ref ref) =>
          DecideLeaveUseCase(repository: ref.watch(hrRepositoryProvider)),
    );

/// Cancel a leave application.
final Provider<CancelLeaveUseCase> cancelLeaveUseCaseProvider =
    Provider<CancelLeaveUseCase>(
      (Ref ref) =>
          CancelLeaveUseCase(repository: ref.watch(hrRepositoryProvider)),
    );

/// Add a holiday to the calendar.
final Provider<SetHolidayUseCase> setHolidayUseCaseProvider =
    Provider<SetHolidayUseCase>(
      (Ref ref) =>
          SetHolidayUseCase(repository: ref.watch(hrRepositoryProvider)),
    );

/// Open a draft payroll run.
final Provider<OpenPayrollPeriodUseCase> openPayrollPeriodUseCaseProvider =
    Provider<OpenPayrollPeriodUseCase>(
      (Ref ref) =>
          OpenPayrollPeriodUseCase(repository: ref.watch(hrRepositoryProvider)),
    );

/// Add a payslip to a draft payroll run.
final Provider<CreatePayslipUseCase> createPayslipUseCaseProvider =
    Provider<CreatePayslipUseCase>(
      (Ref ref) =>
          CreatePayslipUseCase(repository: ref.watch(hrRepositoryProvider)),
    );

/// Finalize a payroll run.
final Provider<FinalizePayrollPeriodUseCase>
finalizePayrollPeriodUseCaseProvider = Provider<FinalizePayrollPeriodUseCase>(
  (Ref ref) =>
      FinalizePayrollPeriodUseCase(repository: ref.watch(hrRepositoryProvider)),
);

/// Mark a payroll run paid.
final Provider<MarkPayrollPaidUseCase> markPayrollPaidUseCaseProvider =
    Provider<MarkPayrollPaidUseCase>(
      (Ref ref) =>
          MarkPayrollPaidUseCase(repository: ref.watch(hrRepositoryProvider)),
    );

/// Read HR records.
final Provider<ReadHrUseCase> readHrUseCaseProvider = Provider<ReadHrUseCase>(
  (Ref ref) => ReadHrUseCase(repository: ref.watch(hrRepositoryProvider)),
);

/// Read payroll records.
final Provider<ReadPayrollUseCase> readPayrollUseCaseProvider =
    Provider<ReadPayrollUseCase>(
      (Ref ref) =>
          ReadPayrollUseCase(repository: ref.watch(hrRepositoryProvider)),
    );

/// Prescription repository over the encrypted local projection.
final Provider<PrescriptionRepository> prescriptionRepositoryProvider =
    Provider<PrescriptionRepository>(
      (Ref ref) => DefaultPrescriptionRepository(
        store: PowerSyncPatientStore(
          database: ref.watch(localDatabaseProvider),
        ),
        logger: ref.watch(loggerProvider),
      ),
    );

/// Prescription drafting.
final Provider<DraftPrescriptionUseCase> draftPrescriptionUseCaseProvider =
    Provider<DraftPrescriptionUseCase>(
      (Ref ref) => DraftPrescriptionUseCase(
        repository: ref.watch(prescriptionRepositoryProvider),
      ),
    );

/// Prescription line creation.
final Provider<AddPrescriptionItemUseCase> addPrescriptionItemUseCaseProvider =
    Provider<AddPrescriptionItemUseCase>(
      (Ref ref) => AddPrescriptionItemUseCase(
        repository: ref.watch(prescriptionRepositoryProvider),
      ),
    );

/// Prescription finalization.
final Provider<FinalizePrescriptionUseCase>
finalizePrescriptionUseCaseProvider = Provider<FinalizePrescriptionUseCase>(
  (Ref ref) => FinalizePrescriptionUseCase(
    repository: ref.watch(prescriptionRepositoryProvider),
  ),
);

/// Prescription versioning.
final Provider<SupersedePrescriptionUseCase>
supersedePrescriptionUseCaseProvider = Provider<SupersedePrescriptionUseCase>(
  (Ref ref) => SupersedePrescriptionUseCase(
    repository: ref.watch(prescriptionRepositoryProvider),
  ),
);

/// Prescription closure.
final Provider<ClosePrescriptionUseCase> closePrescriptionUseCaseProvider =
    Provider<ClosePrescriptionUseCase>(
      (Ref ref) => ClosePrescriptionUseCase(
        repository: ref.watch(prescriptionRepositoryProvider),
      ),
    );

/// Pharmacy dispensing.
final Provider<RecordDispenseUseCase> recordDispenseUseCaseProvider =
    Provider<RecordDispenseUseCase>(
      (Ref ref) => RecordDispenseUseCase(
        repository: ref.watch(prescriptionRepositoryProvider),
      ),
    );

/// Medication administration.
final Provider<RecordAdministrationUseCase>
recordAdministrationUseCaseProvider = Provider<RecordAdministrationUseCase>(
  (Ref ref) => RecordAdministrationUseCase(
    repository: ref.watch(prescriptionRepositoryProvider),
  ),
);

/// Appointment repository over the encrypted local projection.
final Provider<AppointmentRepository> appointmentRepositoryProvider =
    Provider<AppointmentRepository>(
      (Ref ref) => DefaultAppointmentRepository(
        store: PowerSyncPatientStore(
          database: ref.watch(localDatabaseProvider),
        ),
        logger: ref.watch(loggerProvider),
      ),
    );

/// Visit booking.
final Provider<BookAppointmentUseCase> bookAppointmentUseCaseProvider =
    Provider<BookAppointmentUseCase>(
      (Ref ref) => BookAppointmentUseCase(
        repository: ref.watch(appointmentRepositoryProvider),
      ),
    );

/// Appointment lifecycle transitions.
final Provider<TransitionAppointmentUseCase>
transitionAppointmentUseCaseProvider = Provider<TransitionAppointmentUseCase>(
  (Ref ref) => TransitionAppointmentUseCase(
    repository: ref.watch(appointmentRepositoryProvider),
  ),
);

/// Appointment rescheduling.
final Provider<RescheduleAppointmentUseCase>
rescheduleAppointmentUseCaseProvider = Provider<RescheduleAppointmentUseCase>(
  (Ref ref) => RescheduleAppointmentUseCase(
    repository: ref.watch(appointmentRepositoryProvider),
  ),
);

/// Appointment to encounter linking.
final Provider<LinkEncounterAppointmentUseCase>
linkEncounterAppointmentUseCaseProvider =
    Provider<LinkEncounterAppointmentUseCase>(
      (Ref ref) => LinkEncounterAppointmentUseCase(
        repository: ref.watch(appointmentRepositoryProvider),
      ),
    );

/// Bed repository over the encrypted local projection.
final Provider<BedRepository> bedRepositoryProvider = Provider<BedRepository>(
  (Ref ref) => DefaultBedRepository(
    store: PowerSyncPatientStore(database: ref.watch(localDatabaseProvider)),
    logger: ref.watch(loggerProvider),
  ),
);

/// Bed registration.
final Provider<RegisterBedUseCase> registerBedUseCaseProvider =
    Provider<RegisterBedUseCase>(
      (Ref ref) =>
          RegisterBedUseCase(repository: ref.watch(bedRepositoryProvider)),
    );

/// Bed availability.
final Provider<SetBedStatusUseCase> setBedStatusUseCaseProvider =
    Provider<SetBedStatusUseCase>(
      (Ref ref) =>
          SetBedStatusUseCase(repository: ref.watch(bedRepositoryProvider)),
    );

/// Bed allocation.
final Provider<AssignBedUseCase> assignBedUseCaseProvider =
    Provider<AssignBedUseCase>(
      (Ref ref) =>
          AssignBedUseCase(repository: ref.watch(bedRepositoryProvider)),
    );

/// Bed release.
final Provider<ReleaseBedUseCase> releaseBedUseCaseProvider =
    Provider<ReleaseBedUseCase>(
      (Ref ref) =>
          ReleaseBedUseCase(repository: ref.watch(bedRepositoryProvider)),
    );

/// Bed transfer.
final Provider<TransferBedUseCase> transferBedUseCaseProvider =
    Provider<TransferBedUseCase>(
      (Ref ref) =>
          TransferBedUseCase(repository: ref.watch(bedRepositoryProvider)),
    );

/// Discharge repository over the encrypted local projection.
final Provider<DischargeRepository> dischargeRepositoryProvider =
    Provider<DischargeRepository>(
      (Ref ref) => DefaultDischargeRepository(
        store: PowerSyncPatientStore(
          database: ref.watch(localDatabaseProvider),
        ),
        logger: ref.watch(loggerProvider),
      ),
    );

/// Discharge drafting.
final Provider<DraftDischargeUseCase> draftDischargeUseCaseProvider =
    Provider<DraftDischargeUseCase>(
      (Ref ref) => DraftDischargeUseCase(
        repository: ref.watch(dischargeRepositoryProvider),
      ),
    );

/// Discharge finalization.
final Provider<FinalizeDischargeUseCase> finalizeDischargeUseCaseProvider =
    Provider<FinalizeDischargeUseCase>(
      (Ref ref) => FinalizeDischargeUseCase(
        repository: ref.watch(dischargeRepositoryProvider),
        managementRepository: ref.watch(dischargeManagementRepositoryProvider),
      ),
    );

/// Discharge readiness artifacts over the encrypted local projection.
final Provider<DischargeManagementRepository>
dischargeManagementRepositoryProvider = Provider<DischargeManagementRepository>(
  (Ref ref) => DefaultDischargeManagementRepository(
    store: PowerSyncPatientStore(database: ref.watch(localDatabaseProvider)),
    logger: ref.watch(loggerProvider),
  ),
);

/// Clinical clearance recording.
final Provider<RecordDischargeClearanceUseCase>
recordDischargeClearanceUseCaseProvider =
    Provider<RecordDischargeClearanceUseCase>(
      (Ref ref) => RecordDischargeClearanceUseCase(
        repository: ref.watch(dischargeManagementRepositoryProvider),
      ),
    );

/// Clinical clearance granting.
final Provider<GrantDischargeClearanceUseCase>
grantDischargeClearanceUseCaseProvider =
    Provider<GrantDischargeClearanceUseCase>(
      (Ref ref) => GrantDischargeClearanceUseCase(
        repository: ref.watch(dischargeManagementRepositoryProvider),
      ),
    );

/// Medication reconciliation start.
final Provider<StartDischargeReconciliationUseCase>
startDischargeReconciliationUseCaseProvider =
    Provider<StartDischargeReconciliationUseCase>(
      (Ref ref) => StartDischargeReconciliationUseCase(
        repository: ref.watch(dischargeManagementRepositoryProvider),
      ),
    );

/// Medication decision recording.
final Provider<RecordDischargeMedicationUseCase>
recordDischargeMedicationUseCaseProvider =
    Provider<RecordDischargeMedicationUseCase>(
      (Ref ref) => RecordDischargeMedicationUseCase(
        repository: ref.watch(dischargeManagementRepositoryProvider),
      ),
    );

/// Medication reconciliation sign-off.
final Provider<CompleteDischargeReconciliationUseCase>
completeDischargeReconciliationUseCaseProvider =
    Provider<CompleteDischargeReconciliationUseCase>(
      (Ref ref) => CompleteDischargeReconciliationUseCase(
        repository: ref.watch(dischargeManagementRepositoryProvider),
      ),
    );

/// Episode billing settlement.
final Provider<SettleDischargeBillingUseCase>
settleDischargeBillingUseCaseProvider = Provider<SettleDischargeBillingUseCase>(
  (Ref ref) => SettleDischargeBillingUseCase(
    repository: ref.watch(dischargeManagementRepositoryProvider),
  ),
);

/// AI summary filing.
final Provider<RecordDischargeAiSummaryUseCase>
recordDischargeAiSummaryUseCaseProvider =
    Provider<RecordDischargeAiSummaryUseCase>(
      (Ref ref) => RecordDischargeAiSummaryUseCase(
        repository: ref.watch(dischargeManagementRepositoryProvider),
      ),
    );

/// AI summary acceptance.
final Provider<AcceptDischargeAiSummaryUseCase>
acceptDischargeAiSummaryUseCaseProvider =
    Provider<AcceptDischargeAiSummaryUseCase>(
      (Ref ref) => AcceptDischargeAiSummaryUseCase(
        repository: ref.watch(dischargeManagementRepositoryProvider),
      ),
    );

/// AI summary rejection.
final Provider<RejectDischargeAiSummaryUseCase>
rejectDischargeAiSummaryUseCaseProvider =
    Provider<RejectDischargeAiSummaryUseCase>(
      (Ref ref) => RejectDischargeAiSummaryUseCase(
        repository: ref.watch(dischargeManagementRepositoryProvider),
      ),
    );

/// Discharge readiness inspection.
final Provider<CheckDischargeReadinessUseCase>
checkDischargeReadinessUseCaseProvider =
    Provider<CheckDischargeReadinessUseCase>(
      (Ref ref) => CheckDischargeReadinessUseCase(
        repository: ref.watch(dischargeManagementRepositoryProvider),
      ),
    );

/// Discharge cancellation.
final Provider<CancelDischargeUseCase> cancelDischargeUseCaseProvider =
    Provider<CancelDischargeUseCase>(
      (Ref ref) => CancelDischargeUseCase(
        repository: ref.watch(dischargeRepositoryProvider),
      ),
    );

/// Billing repository over the encrypted local projection.
final Provider<BillingRepository> billingRepositoryProvider =
    Provider<BillingRepository>(
      (Ref ref) => DefaultBillingRepository(
        store: PowerSyncPatientStore(
          database: ref.watch(localDatabaseProvider),
        ),
        logger: ref.watch(loggerProvider),
      ),
    );

/// Invoice drafting.
final Provider<DraftInvoiceUseCase> draftInvoiceUseCaseProvider =
    Provider<DraftInvoiceUseCase>(
      (Ref ref) =>
          DraftInvoiceUseCase(repository: ref.watch(billingRepositoryProvider)),
    );

/// Invoice line creation.
final Provider<AddInvoiceLineUseCase> addInvoiceLineUseCaseProvider =
    Provider<AddInvoiceLineUseCase>(
      (Ref ref) => AddInvoiceLineUseCase(
        repository: ref.watch(billingRepositoryProvider),
      ),
    );

/// Invoice issuance.
final Provider<IssueInvoiceUseCase> issueInvoiceUseCaseProvider =
    Provider<IssueInvoiceUseCase>(
      (Ref ref) =>
          IssueInvoiceUseCase(repository: ref.watch(billingRepositoryProvider)),
    );

/// Invoice settlement.
final Provider<SettleInvoiceUseCase> settleInvoiceUseCaseProvider =
    Provider<SettleInvoiceUseCase>(
      (Ref ref) => SettleInvoiceUseCase(
        repository: ref.watch(billingRepositoryProvider),
      ),
    );

/// Payment recording.
final Provider<RecordPaymentUseCase> recordPaymentUseCaseProvider =
    Provider<RecordPaymentUseCase>(
      (Ref ref) => RecordPaymentUseCase(
        repository: ref.watch(billingRepositoryProvider),
      ),
    );

/// Refund recording.
final Provider<RecordRefundUseCase> recordRefundUseCaseProvider =
    Provider<RecordRefundUseCase>(
      (Ref ref) =>
          RecordRefundUseCase(repository: ref.watch(billingRepositoryProvider)),
    );

/// Invoice cancellation.
final Provider<CancelInvoiceUseCase> cancelInvoiceUseCaseProvider =
    Provider<CancelInvoiceUseCase>(
      (Ref ref) => CancelInvoiceUseCase(
        repository: ref.watch(billingRepositoryProvider),
      ),
    );

/// Patient account opening.
final Provider<OpenPatientAccountUseCase> openPatientAccountUseCaseProvider =
    Provider<OpenPatientAccountUseCase>(
      (Ref ref) => OpenPatientAccountUseCase(
        repository: ref.watch(billingRepositoryProvider),
      ),
    );

/// Patient account statement reading.
final Provider<ReadPatientAccountUseCase> readPatientAccountUseCaseProvider =
    Provider<ReadPatientAccountUseCase>(
      (Ref ref) => ReadPatientAccountUseCase(
        repository: ref.watch(billingRepositoryProvider),
      ),
    );

/// Charge posting onto a patient account.
final Provider<PostChargeUseCase> postChargeUseCaseProvider =
    Provider<PostChargeUseCase>(
      (Ref ref) =>
          PostChargeUseCase(repository: ref.watch(billingRepositoryProvider)),
    );

/// Correcting adjustment posting.
final Provider<PostAdjustmentUseCase> postAdjustmentUseCaseProvider =
    Provider<PostAdjustmentUseCase>(
      (Ref ref) => PostAdjustmentUseCase(
        repository: ref.watch(billingRepositoryProvider),
      ),
    );

/// Split payment allocation.
final Provider<AllocatePaymentUseCase> allocatePaymentUseCaseProvider =
    Provider<AllocatePaymentUseCase>(
      (Ref ref) => AllocatePaymentUseCase(
        repository: ref.watch(billingRepositoryProvider),
      ),
    );

/// Inventory repository over the encrypted local projection.
final Provider<InventoryRepository> inventoryRepositoryProvider =
    Provider<InventoryRepository>(
      (Ref ref) => DefaultInventoryRepository(
        store: PowerSyncPatientStore(
          database: ref.watch(localDatabaseProvider),
        ),
        logger: ref.watch(loggerProvider),
      ),
    );

/// Stock item registration.
final Provider<RegisterStockItemUseCase> registerStockItemUseCaseProvider =
    Provider<RegisterStockItemUseCase>(
      (Ref ref) => RegisterStockItemUseCase(
        repository: ref.watch(inventoryRepositoryProvider),
      ),
    );

/// Item status management.
final Provider<SetItemStatusUseCase> setItemStatusUseCaseProvider =
    Provider<SetItemStatusUseCase>(
      (Ref ref) => SetItemStatusUseCase(
        repository: ref.watch(inventoryRepositoryProvider),
      ),
    );

/// Location registration.
final Provider<RegisterLocationUseCase> registerLocationUseCaseProvider =
    Provider<RegisterLocationUseCase>(
      (Ref ref) => RegisterLocationUseCase(
        repository: ref.watch(inventoryRepositoryProvider),
      ),
    );

/// Batch registration.
final Provider<RegisterBatchUseCase> registerBatchUseCaseProvider =
    Provider<RegisterBatchUseCase>(
      (Ref ref) => RegisterBatchUseCase(
        repository: ref.watch(inventoryRepositoryProvider),
      ),
    );

/// Batch status updates.
final Provider<UpdateBatchStatusUseCase> updateBatchStatusUseCaseProvider =
    Provider<UpdateBatchStatusUseCase>(
      (Ref ref) => UpdateBatchStatusUseCase(
        repository: ref.watch(inventoryRepositoryProvider),
      ),
    );

/// Stock movement recording.
final Provider<RecordMovementUseCase> recordMovementUseCaseProvider =
    Provider<RecordMovementUseCase>(
      (Ref ref) => RecordMovementUseCase(
        repository: ref.watch(inventoryRepositoryProvider),
      ),
    );

/// ER repository over the encrypted local projection.
final Provider<ErRepository> erRepositoryProvider = Provider<ErRepository>(
  (Ref ref) => DefaultErRepository(
    store: PowerSyncPatientStore(database: ref.watch(localDatabaseProvider)),
    logger: ref.watch(loggerProvider),
  ),
);

/// Triage assessment recording.
final Provider<RecordTriageUseCase> recordTriageUseCaseProvider =
    Provider<RecordTriageUseCase>(
      (Ref ref) =>
          RecordTriageUseCase(repository: ref.watch(erRepositoryProvider)),
    );

/// Triage escalation.
final Provider<EscalateTriageUseCase> escalateTriageUseCaseProvider =
    Provider<EscalateTriageUseCase>(
      (Ref ref) =>
          EscalateTriageUseCase(repository: ref.watch(erRepositoryProvider)),
    );

/// ER visit opening from triage.
final Provider<OpenErVisitUseCase> openErVisitUseCaseProvider =
    Provider<OpenErVisitUseCase>(
      (Ref ref) =>
          OpenErVisitUseCase(repository: ref.watch(erRepositoryProvider)),
    );

/// ER visit lifecycle transitions.
final Provider<TransitionErVisitUseCase> transitionErVisitUseCaseProvider =
    Provider<TransitionErVisitUseCase>(
      (Ref ref) =>
          TransitionErVisitUseCase(repository: ref.watch(erRepositoryProvider)),
    );

/// ICU repository over the encrypted local projection.
final Provider<IcuRepository> icuRepositoryProvider = Provider<IcuRepository>(
  (Ref ref) => DefaultIcuRepository(
    store: PowerSyncPatientStore(database: ref.watch(localDatabaseProvider)),
    logger: ref.watch(loggerProvider),
  ),
);

/// ICU bed assignment and release.
final Provider<AssignIcuBedUseCase> assignIcuBedUseCaseProvider =
    Provider<AssignIcuBedUseCase>(
      (Ref ref) =>
          AssignIcuBedUseCase(repository: ref.watch(icuRepositoryProvider)),
    );

/// ICU vital-sign recording.
final Provider<RecordIcuVitalsUseCase> recordIcuVitalsUseCaseProvider =
    Provider<RecordIcuVitalsUseCase>(
      (Ref ref) =>
          RecordIcuVitalsUseCase(repository: ref.watch(icuRepositoryProvider)),
    );

/// ICU nursing handover.
final Provider<RecordIcuHandoverUseCase> recordIcuHandoverUseCaseProvider =
    Provider<RecordIcuHandoverUseCase>(
      (Ref ref) => RecordIcuHandoverUseCase(
        repository: ref.watch(icuRepositoryProvider),
      ),
    );

/// Ventilator event recording.
final Provider<RecordVentilatorEventUseCase>
recordVentilatorEventUseCaseProvider = Provider<RecordVentilatorEventUseCase>(
  (Ref ref) => RecordVentilatorEventUseCase(
    repository: ref.watch(icuRepositoryProvider),
  ),
);

/// Blood bank repository over the encrypted local projection.
final Provider<BloodBankRepository> bloodBankRepositoryProvider =
    Provider<BloodBankRepository>(
      (Ref ref) => DefaultBloodBankRepository(
        store: PowerSyncPatientStore(
          database: ref.watch(localDatabaseProvider),
        ),
        logger: ref.watch(loggerProvider),
      ),
    );

/// Blood unit registration.
final Provider<CreateBloodUnitUseCase> createBloodUnitUseCaseProvider =
    Provider<CreateBloodUnitUseCase>(
      (Ref ref) => CreateBloodUnitUseCase(
        repository: ref.watch(bloodBankRepositoryProvider),
      ),
    );

/// Transfusion request creation.
final Provider<RequestTransfusionUseCase> requestTransfusionUseCaseProvider =
    Provider<RequestTransfusionUseCase>(
      (Ref ref) => RequestTransfusionUseCase(
        repository: ref.watch(bloodBankRepositoryProvider),
      ),
    );

/// Crossmatch recording.
final Provider<RecordCrossmatchUseCase> recordCrossmatchUseCaseProvider =
    Provider<RecordCrossmatchUseCase>(
      (Ref ref) => RecordCrossmatchUseCase(
        repository: ref.watch(bloodBankRepositoryProvider),
      ),
    );

/// Transfusion request approval.
final Provider<ApproveTransfusionRequestUseCase>
approveTransfusionRequestUseCaseProvider =
    Provider<ApproveTransfusionRequestUseCase>(
      (Ref ref) => ApproveTransfusionRequestUseCase(
        repository: ref.watch(bloodBankRepositoryProvider),
      ),
    );

/// Blood unit reservation.
final Provider<ReserveBloodUnitUseCase> reserveBloodUnitUseCaseProvider =
    Provider<ReserveBloodUnitUseCase>(
      (Ref ref) => ReserveBloodUnitUseCase(
        repository: ref.watch(bloodBankRepositoryProvider),
      ),
    );

/// Blood unit issue against an approved request.
final Provider<IssueBloodUnitUseCase> issueBloodUnitUseCaseProvider =
    Provider<IssueBloodUnitUseCase>(
      (Ref ref) => IssueBloodUnitUseCase(
        repository: ref.watch(bloodBankRepositoryProvider),
      ),
    );

/// Transfusion start.
final Provider<RecordTransfusionUseCase> recordTransfusionUseCaseProvider =
    Provider<RecordTransfusionUseCase>(
      (Ref ref) => RecordTransfusionUseCase(
        repository: ref.watch(bloodBankRepositoryProvider),
      ),
    );

/// Transfusion outcome recording.
final Provider<RecordTransfusionOutcomeUseCase>
recordTransfusionOutcomeUseCaseProvider =
    Provider<RecordTransfusionOutcomeUseCase>(
      (Ref ref) => RecordTransfusionOutcomeUseCase(
        repository: ref.watch(bloodBankRepositoryProvider),
      ),
    );

/// Blood unit discard.
final Provider<DiscardBloodUnitUseCase> discardBloodUnitUseCaseProvider =
    Provider<DiscardBloodUnitUseCase>(
      (Ref ref) => DiscardBloodUnitUseCase(
        repository: ref.watch(bloodBankRepositoryProvider),
      ),
    );

/// Transfusion request completion.
final Provider<CompleteTransfusionRequestUseCase>
completeTransfusionRequestUseCaseProvider =
    Provider<CompleteTransfusionRequestUseCase>(
      (Ref ref) => CompleteTransfusionRequestUseCase(
        repository: ref.watch(bloodBankRepositoryProvider),
      ),
    );

/// Operation theatre repository over the encrypted local projection.
final Provider<OtRepository> otRepositoryProvider = Provider<OtRepository>(
  (Ref ref) => DefaultOtRepository(
    store: PowerSyncPatientStore(database: ref.watch(localDatabaseProvider)),
    logger: ref.watch(loggerProvider),
  ),
);

/// Theatre booking with the room conflict check.
final Provider<ScheduleOtBookingUseCase> scheduleOtBookingUseCaseProvider =
    Provider<ScheduleOtBookingUseCase>(
      (Ref ref) =>
          ScheduleOtBookingUseCase(repository: ref.watch(otRepositoryProvider)),
    );

/// Pre-op fitness assessment recording.
final Provider<RecordPreOpAssessmentUseCase>
recordPreOpAssessmentUseCaseProvider = Provider<RecordPreOpAssessmentUseCase>(
  (Ref ref) =>
      RecordPreOpAssessmentUseCase(repository: ref.watch(otRepositoryProvider)),
);

/// Case start after a fit pre-op assessment.
final Provider<StartOtBookingUseCase> startOtBookingUseCaseProvider =
    Provider<StartOtBookingUseCase>(
      (Ref ref) =>
          StartOtBookingUseCase(repository: ref.watch(otRepositoryProvider)),
    );

/// Anesthesia record recording.
final Provider<RecordAnesthesiaUseCase> recordAnesthesiaUseCaseProvider =
    Provider<RecordAnesthesiaUseCase>(
      (Ref ref) =>
          RecordAnesthesiaUseCase(repository: ref.watch(otRepositoryProvider)),
    );

/// Intra-op procedure log recording.
final Provider<RecordProcedureLogUseCase> recordProcedureLogUseCaseProvider =
    Provider<RecordProcedureLogUseCase>(
      (Ref ref) => RecordProcedureLogUseCase(
        repository: ref.watch(otRepositoryProvider),
      ),
    );

/// Post-op recovery record recording.
final Provider<RecordPostOpUseCase> recordPostOpUseCaseProvider =
    Provider<RecordPostOpUseCase>(
      (Ref ref) =>
          RecordPostOpUseCase(repository: ref.watch(otRepositoryProvider)),
    );

/// Case completion after post-op documentation.
final Provider<CompleteOtBookingUseCase> completeOtBookingUseCaseProvider =
    Provider<CompleteOtBookingUseCase>(
      (Ref ref) =>
          CompleteOtBookingUseCase(repository: ref.watch(otRepositoryProvider)),
    );

/// Case cancellation with a reason.
final Provider<CancelOtBookingUseCase> cancelOtBookingUseCaseProvider =
    Provider<CancelOtBookingUseCase>(
      (Ref ref) =>
          CancelOtBookingUseCase(repository: ref.watch(otRepositoryProvider)),
    );

/// AI model and routing configuration.
///
/// Phase 1 ships an empty registry. Every engine therefore resolves to a manual
/// workflow, which is the correct behaviour before any model has passed
/// evaluation: an unconfigured engine must not silently execute.
final Provider<AiModelRegistry> aiModelRegistryProvider =
    Provider<AiModelRegistry>(
      (Ref ref) => InMemoryAiModelRegistry(
        models: const <ModelRecord>[],
        policies: const <RoutingPolicy>[],
      ),
    );

/// Provider adapters registered with the AI Gateway.
///
/// Phase 1 registers unconfigured adapters for the three deployment-profile
/// providers. They report unavailable, so the Orchestrator exercises its real
/// failover path and terminates in a manual workflow rather than appearing to
/// succeed. Replacing one with a real adapter requires no change above this file.
final Provider<Map<String, AiProviderAdapter>> aiAdaptersProvider =
    Provider<Map<String, AiProviderAdapter>>(
      (Ref ref) => const <String, AiProviderAdapter>{
        AiProviders.openRouter: UnconfiguredProviderAdapter(
          provider: AiProviders.openRouter,
          reason:
              'Cloud AI transport is not enabled in this build. '
              'Credentials are held server-side and configured per deployment.',
        ),
        AiProviders.ollamaCloud: UnconfiguredProviderAdapter(
          provider: AiProviders.ollamaCloud,
          reason:
              'Cloud AI transport is not enabled in this build. '
              'Credentials are held server-side and configured per deployment.',
        ),
        AiProviders.llamaCpp: UnconfiguredProviderAdapter(
          provider: AiProviders.llamaCpp,
          reason:
              'The on-device inference runtime is not bundled in this build.',
        ),
      },
    );

/// The AI Gateway.
final Provider<AiGateway> aiGatewayProvider = Provider<AiGateway>(
  (Ref ref) => AiGateway(
    adapters: ref.watch(aiAdaptersProvider),
    registry: ref.watch(aiModelRegistryProvider),
    logger: ref.watch(loggerProvider),
  ),
);

/// The AI Orchestrator.
final Provider<AiOrchestrator> aiOrchestratorProvider =
    Provider<AiOrchestrator>((Ref ref) {
      final NodexEnvironment environment = ref.watch(environmentProvider);
      return AiOrchestrator(
        gateway: ref.watch(aiGatewayProvider),
        registry: ref.watch(aiModelRegistryProvider),
        logger: ref.watch(loggerProvider),
        deploymentProfileRevision: environment.aiDeploymentProfileRevision,
      );
    });
