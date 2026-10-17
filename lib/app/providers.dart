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
import 'package:nodex_hms/core/security/secure_key_store.dart';
import 'package:nodex_hms/core/storage/storage_service.dart';
import 'package:nodex_hms/data/local/local_database.dart';
import 'package:nodex_hms/data/remote/supabase_gateway.dart';
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
import 'package:nodex_hms/domain/encounters/encounter_repository.dart';
import 'package:nodex_hms/domain/encounters/encounter_use_cases.dart';
import 'package:nodex_hms/domain/encounters/problem_list_repository.dart';
import 'package:nodex_hms/domain/encounters/problem_list_use_cases.dart';
import 'package:nodex_hms/domain/er/er_repository.dart';
import 'package:nodex_hms/domain/er/er_use_cases.dart';
import 'package:nodex_hms/domain/fleet/fleet_repository.dart';
import 'package:nodex_hms/domain/fleet/fleet_use_cases.dart';
import 'package:nodex_hms/domain/floormap/floormap_repository.dart';
import 'package:nodex_hms/domain/floormap/floormap_use_cases.dart';
import 'package:nodex_hms/domain/hr/hr_repository.dart';
import 'package:nodex_hms/domain/hr/hr_use_cases.dart';
import 'package:nodex_hms/domain/icu/icu_repository.dart';
import 'package:nodex_hms/domain/icu/icu_use_cases.dart';
import 'package:nodex_hms/domain/inventory/inventory_repository.dart';
import 'package:nodex_hms/domain/inventory/inventory_use_cases.dart';
import 'package:nodex_hms/domain/laboratory/lab_repository.dart';
import 'package:nodex_hms/domain/laboratory/lab_use_cases.dart';
import 'package:nodex_hms/domain/nursing_station/nursing_station_repository.dart';
import 'package:nodex_hms/domain/nursing_station/nursing_station_use_cases.dart';
import 'package:nodex_hms/domain/nutrition/nutrition_repository.dart';
import 'package:nodex_hms/domain/nutrition/nutrition_use_cases.dart';
import 'package:nodex_hms/domain/ot/ot_repository.dart';
import 'package:nodex_hms/domain/ot/ot_use_cases.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';
import 'package:nodex_hms/domain/patients/patient_use_cases.dart';
import 'package:nodex_hms/domain/physio/physio_repository.dart';
import 'package:nodex_hms/domain/physio/physio_use_cases.dart';
import 'package:nodex_hms/domain/prescriptions/prescription_repository.dart';
import 'package:nodex_hms/domain/prescriptions/prescription_use_cases.dart';
import 'package:nodex_hms/domain/radiology/radiology_repository.dart';
import 'package:nodex_hms/domain/radiology/radiology_use_cases.dart';
import 'package:nodex_hms/domain/roster/practitioner_repository.dart';
import 'package:nodex_hms/domain/roster/practitioner_use_cases.dart';
import 'package:nodex_hms/domain/session/session_repository.dart';
import 'package:nodex_hms/domain/telemedicine/telemedicine_repository.dart';
import 'package:nodex_hms/domain/telemedicine/telemedicine_use_cases.dart';
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
