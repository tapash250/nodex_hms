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
import 'package:nodex_hms/domain/encounters/encounter_repository.dart';
import 'package:nodex_hms/domain/encounters/encounter_use_cases.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';
import 'package:nodex_hms/domain/patients/patient_use_cases.dart';
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
