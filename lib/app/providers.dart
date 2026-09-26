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
import 'package:nodex_hms/data/local/local_database.dart';
import 'package:nodex_hms/data/remote/supabase_gateway.dart';
import 'package:nodex_hms/domain/appointments/appointment_repository.dart';
import 'package:nodex_hms/domain/appointments/appointment_use_cases.dart';
import 'package:nodex_hms/domain/beds/bed_repository.dart';
import 'package:nodex_hms/domain/beds/bed_use_cases.dart';
import 'package:nodex_hms/domain/billing/billing_repository.dart';
import 'package:nodex_hms/domain/billing/billing_use_cases.dart';
import 'package:nodex_hms/domain/blood_bank/blood_bank_repository.dart';
import 'package:nodex_hms/domain/blood_bank/blood_bank_use_cases.dart';
import 'package:nodex_hms/domain/discharge/discharge_repository.dart';
import 'package:nodex_hms/domain/discharge/discharge_use_cases.dart';
import 'package:nodex_hms/domain/encounters/encounter_repository.dart';
import 'package:nodex_hms/domain/encounters/encounter_use_cases.dart';
import 'package:nodex_hms/domain/er/er_repository.dart';
import 'package:nodex_hms/domain/er/er_use_cases.dart';
import 'package:nodex_hms/domain/icu/icu_repository.dart';
import 'package:nodex_hms/domain/icu/icu_use_cases.dart';
import 'package:nodex_hms/domain/inventory/inventory_repository.dart';
import 'package:nodex_hms/domain/inventory/inventory_use_cases.dart';
import 'package:nodex_hms/domain/laboratory/lab_repository.dart';
import 'package:nodex_hms/domain/laboratory/lab_use_cases.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';
import 'package:nodex_hms/domain/patients/patient_use_cases.dart';
import 'package:nodex_hms/domain/prescriptions/prescription_repository.dart';
import 'package:nodex_hms/domain/prescriptions/prescription_use_cases.dart';
import 'package:nodex_hms/domain/session/session_repository.dart';
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
