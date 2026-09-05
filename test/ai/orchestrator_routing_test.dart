/// Deterministic routing acceptance tests.
///
/// These implement the specification's routing acceptance table directly:
///
/// | Test                        | Expected result                                    |
/// |-----------------------------|----------------------------------------------------|
/// | Primary healthy             | Primary model executes                             |
/// | Primary timeout             | Secondary executes if policy allows                 |
/// | Primary 429                 | Secondary executes; same provider not retried       |
/// | Primary 5xx threshold       | Circuit opens and routing advances                  |
/// | Secondary failure           | Tertiary executes when configured and eligible      |
/// | WAN unavailable             | Offline policy activates                            |
/// | All candidates unavailable  | System refuses silent degradation, enters manual     |
/// | Unauthorized provider/model | Execution blocked; configuration error logged       |
/// | Unsupported modality        | Task blocked or routed only to a compatible candidate|
/// | Safety block                | Safety decision authoritative, not bypassed         |
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/ai/contracts/ai_contracts.dart';
import 'package:nodex_hms/ai/gateway/adapters/stub_adapters.dart';
import 'package:nodex_hms/ai/gateway/ai_gateway.dart';
import 'package:nodex_hms/ai/model_registry/model_registry.dart';
import 'package:nodex_hms/ai/orchestrator/ai_engines.dart';
import 'package:nodex_hms/ai/orchestrator/ai_orchestrator.dart';
import 'package:nodex_hms/ai/orchestrator/circuit_breaker.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';

const String _engineKey = AiEngines.triageAdvisory;
const String _primary = 'reasoning_cloud_primary';
const String _secondary = 'reasoning_cloud_secondary';
const String _tertiary = 'reasoning_cloud_tertiary';
const String _offline = 'reasoning_local_offline';

/// An approved, active, evaluated model record.
ModelRecord approvedModel({
  required String modelKey,
  required String provider,
  Set<Modality> modalities = const <Modality>{Modality.text},
  ClinicalRiskLevel risk = ClinicalRiskLevel.high,
  DataPrivacyClass privacy = DataPrivacyClass.phiPermitted,
  bool structuredJson = true,
  ModelLifecycleStatus lifecycle = ModelLifecycleStatus.active,
  ModelEvaluationStatus evaluation = ModelEvaluationStatus.passed,
  bool enabled = true,
  String? evaluationSetRevision = 'acceptance-2026.09',
}) => ModelRecord(
  modelKey: modelKey,
  provider: provider,
  displayName: modelKey,
  modelRevision: '$modelKey-rev1',
  modalities: modalities,
  clinicalRiskTier: risk,
  privacyClass: privacy,
  lifecycleStatus: lifecycle,
  evaluationStatus: evaluation,
  enabled: enabled,
  evaluationSetRevision: evaluationSetRevision,
  supportsStructuredJson: structuredJson,
);

RoutingPolicy buildPolicy({
  String? secondary = _secondary,
  String? tertiary = _tertiary,
  String? offline = _offline,
  bool requireHumanReview = true,
  bool allowManualFallback = true,
  bool enabled = true,
  int circuitThreshold = 3,
}) => RoutingPolicy(
  engineKey: _engineKey,
  primaryModelKey: _primary,
  secondaryModelKey: secondary,
  tertiaryModelKey: tertiary,
  offlineFallbackModelKey: offline,
  policyRevision: 'policy-2026.09.01',
  minimumRiskCapability: ClinicalRiskLevel.high,
  requireHumanReview: requireHumanReview,
  allowManualFallback: allowManualFallback,
  enabled: enabled,
  circuitBreakerThreshold: circuitThreshold,
  timeout: const Duration(seconds: 12),
);

AiExecutionRequest buildRequest({
  Modality modality = Modality.text,
  ClinicalRiskLevel risk = ClinicalRiskLevel.high,
  DataPrivacyClass privacy = DataPrivacyClass.phiPermitted,
  bool requireStructuredOutput = true,
}) => AiExecutionRequest(
  requestId: 'request-1',
  engineKey: _engineKey,
  modelKey: _primary,
  riskLevel: risk,
  privacyClass: privacy,
  modality: modality,
  sanitizedContext: const <String, Object?>{'presentation': 'chest pain'},
  timeout: const Duration(seconds: 12),
  requireStructuredOutput: requireStructuredOutput,
  contextDigest: 'digest-1',
);

AiProviderResponse success(String modelKey, {String provider = 'cloud_a'}) =>
    AiProviderResponse.success(
      modelKey: modelKey,
      modelRevision: '$modelKey-rev1',
      provider: provider,
      output: const <String, Object?>{
        'recommendation_type': 'urgent_review',
        'requires_human_review': true,
      },
      latency: const Duration(milliseconds: 420),
      confidence: 0.82,
    );

AiProviderResponse failure(
  String modelKey,
  AiFailureClass failureClass, {
  String provider = 'cloud_a',
}) => AiProviderResponse.failure(
  modelKey: modelKey,
  modelRevision: '$modelKey-rev1',
  provider: provider,
  failureClass: failureClass,
  latency: const Duration(milliseconds: 120),
  failureDetail: 'scripted ${failureClass.wireValue}',
);

void main() {
  late InMemoryLogSink sink;
  late NodexLogger logger;

  setUp(() {
    sink = InMemoryLogSink();
    logger = NodexLogger(
      sinks: <NodexLogSink>[sink],
      minimumLevel: NodexLogLevel.trace,
    );
  });

  AiOrchestrator buildOrchestrator({
    required List<ModelRecord> models,
    required List<RoutingPolicy> policies,
    required Map<String, AiProviderAdapter> adapters,
    CircuitBreaker? breaker,
  }) {
    final AiModelRegistry registry = InMemoryAiModelRegistry(
      models: models,
      policies: policies,
    );
    return AiOrchestrator(
      gateway: AiGateway(
        adapters: adapters,
        registry: registry,
        logger: logger,
      ),
      registry: registry,
      logger: logger,
      deploymentProfileRevision: 'profile-2026.09.01',
      circuitBreaker: breaker,
    );
  }

  group('deterministic routing acceptance', () {
    test('primary healthy: the primary model executes', () async {
      final ScriptedProviderAdapter adapter = ScriptedProviderAdapter(
        provider: 'cloud_a',
        script: <String, AiProviderResponse>{_primary: success(_primary)},
      );

      final AiOrchestrator orchestrator = buildOrchestrator(
        models: <ModelRecord>[
          approvedModel(modelKey: _primary, provider: 'cloud_a'),
        ],
        policies: <RoutingPolicy>[buildPolicy()],
        adapters: <String, AiProviderAdapter>{'cloud_a': adapter},
      );

      final AiTaskResult result = await orchestrator.run(
        buildRequest(),
        connectivity: ConnectivityState.online,
      );

      expect(result.outcome, AiTaskOutcome.completed);
      expect(result.modelKey, _primary);
      expect(result.attempts, hasLength(1));
      expect(result.attempts.single.attemptNumber, 1);
      expect(result.routingPolicyRevision, 'policy-2026.09.01');
      expect(result.deploymentProfileRevision, 'profile-2026.09.01');
    });

    test('primary timeout: the secondary executes', () async {
      final ScriptedProviderAdapter adapter = ScriptedProviderAdapter(
        provider: 'cloud_a',
        script: <String, AiProviderResponse>{
          _primary: failure(_primary, AiFailureClass.timeout),
          _secondary: success(_secondary),
        },
      );

      final AiOrchestrator orchestrator = buildOrchestrator(
        models: <ModelRecord>[
          approvedModel(modelKey: _primary, provider: 'cloud_a'),
          approvedModel(modelKey: _secondary, provider: 'cloud_a'),
        ],
        policies: <RoutingPolicy>[buildPolicy()],
        adapters: <String, AiProviderAdapter>{'cloud_a': adapter},
      );

      final AiTaskResult result = await orchestrator.run(
        buildRequest(),
        connectivity: ConnectivityState.online,
      );

      expect(result.outcome, AiTaskOutcome.completed);
      expect(result.modelKey, _secondary);
      expect(result.attempts, hasLength(2));
      expect(result.attempts.first.failureClass, AiFailureClass.timeout);
      expect(result.attempts.last.succeeded, isTrue);
    });

    test(
      'primary 429: routing advances without retrying the same model',
      () async {
        final ScriptedProviderAdapter adapter = ScriptedProviderAdapter(
          provider: 'cloud_a',
          script: <String, AiProviderResponse>{
            _primary: failure(_primary, AiFailureClass.rateLimit),
            _secondary: success(_secondary),
          },
        );

        final AiOrchestrator orchestrator = buildOrchestrator(
          models: <ModelRecord>[
            approvedModel(modelKey: _primary, provider: 'cloud_a'),
            approvedModel(modelKey: _secondary, provider: 'cloud_a'),
          ],
          policies: <RoutingPolicy>[buildPolicy()],
          adapters: <String, AiProviderAdapter>{'cloud_a': adapter},
        );

        final AiTaskResult result = await orchestrator.run(
          buildRequest(),
          connectivity: ConnectivityState.online,
        );

        expect(result.outcome, AiTaskOutcome.completed);
        expect(result.modelKey, _secondary);
        // The rate-limited model was attempted exactly once.
        expect(
          adapter.receivedRequests
              .where((AiExecutionRequest r) => r.modelKey == _primary)
              .length,
          1,
        );
      },
    );

    test('secondary failure: the tertiary executes', () async {
      final ScriptedProviderAdapter adapter = ScriptedProviderAdapter(
        provider: 'cloud_a',
        script: <String, AiProviderResponse>{
          _primary: failure(_primary, AiFailureClass.providerServer),
          _secondary: failure(_secondary, AiFailureClass.connectivity),
          _tertiary: success(_tertiary),
        },
      );

      final AiOrchestrator orchestrator = buildOrchestrator(
        models: <ModelRecord>[
          approvedModel(modelKey: _primary, provider: 'cloud_a'),
          approvedModel(modelKey: _secondary, provider: 'cloud_a'),
          approvedModel(modelKey: _tertiary, provider: 'cloud_a'),
        ],
        policies: <RoutingPolicy>[buildPolicy()],
        adapters: <String, AiProviderAdapter>{'cloud_a': adapter},
      );

      final AiTaskResult result = await orchestrator.run(
        buildRequest(),
        connectivity: ConnectivityState.online,
      );

      expect(result.outcome, AiTaskOutcome.completed);
      expect(result.modelKey, _tertiary);
      expect(result.attempts, hasLength(3));
    });

    test(
      'primary 5xx threshold: the circuit opens and routing advances',
      () async {
        final CircuitBreaker breaker = CircuitBreaker(
          threshold: 1,
          cooldown: const Duration(minutes: 5),
        );

        final ScriptedProviderAdapter adapter = ScriptedProviderAdapter(
          provider: 'cloud_a',
          script: <String, AiProviderResponse>{
            _primary: failure(_primary, AiFailureClass.providerServer),
            _secondary: success(_secondary),
          },
        );

        final AiOrchestrator orchestrator = buildOrchestrator(
          models: <ModelRecord>[
            approvedModel(modelKey: _primary, provider: 'cloud_a'),
            approvedModel(modelKey: _secondary, provider: 'cloud_a'),
          ],
          policies: <RoutingPolicy>[buildPolicy()],
          adapters: <String, AiProviderAdapter>{'cloud_a': adapter},
          breaker: breaker,
        );

        final AiTaskResult first = await orchestrator.run(
          buildRequest(),
          connectivity: ConnectivityState.online,
        );
        expect(first.modelKey, _secondary);
        expect(orchestrator.circuitStateOf(_primary), CircuitState.open);

        // A second task skips the open circuit entirely rather than attempting it.
        final AiTaskResult second = await orchestrator.run(
          buildRequest(),
          connectivity: ConnectivityState.online,
        );
        expect(second.modelKey, _secondary);
        expect(second.attempts.first.circuitState, CircuitState.open);
        expect(second.attempts.first.provider, 'skipped');
        expect(
          adapter.receivedRequests
              .where((AiExecutionRequest r) => r.modelKey == _primary)
              .length,
          1,
        );
      },
    );

    test('WAN unavailable: the offline fallback executes', () async {
      final ScriptedProviderAdapter cloud = ScriptedProviderAdapter(
        provider: 'cloud_a',
        script: <String, AiProviderResponse>{_primary: success(_primary)},
      );
      final ScriptedProviderAdapter local = ScriptedProviderAdapter(
        provider: 'llama_cpp',
        script: <String, AiProviderResponse>{
          _offline: success(_offline, provider: 'llama_cpp'),
        },
      );

      final AiOrchestrator orchestrator = buildOrchestrator(
        models: <ModelRecord>[
          approvedModel(modelKey: _primary, provider: 'cloud_a'),
          approvedModel(
            modelKey: _offline,
            provider: 'llama_cpp',
            privacy: DataPrivacyClass.onDeviceOnly,
          ),
        ],
        policies: <RoutingPolicy>[buildPolicy()],
        adapters: <String, AiProviderAdapter>{
          'cloud_a': cloud,
          'llama_cpp': local,
        },
      );

      final AiTaskResult result = await orchestrator.run(
        buildRequest(),
        connectivity: ConnectivityState.offline,
      );

      expect(result.outcome, AiTaskOutcome.completed);
      expect(result.modelKey, _offline);
      // No cloud candidate was attempted: doing so would burn the timeout.
      expect(cloud.receivedRequests, isEmpty);
    });

    test(
      'offline with no local fallback: enters the manual workflow',
      () async {
        final AiOrchestrator orchestrator = buildOrchestrator(
          models: <ModelRecord>[
            approvedModel(modelKey: _primary, provider: 'cloud_a'),
          ],
          policies: <RoutingPolicy>[buildPolicy(offline: null)],
          adapters: <String, AiProviderAdapter>{
            'cloud_a': ScriptedProviderAdapter(
              provider: 'cloud_a',
              script: <String, AiProviderResponse>{_primary: success(_primary)},
            ),
          },
        );

        final AiTaskResult result = await orchestrator.run(
          buildRequest(),
          connectivity: ConnectivityState.offline,
        );

        expect(result.outcome, AiTaskOutcome.manualWorkflow);
        expect(result.requiresManualWorkflow, isTrue);
        expect(result.hasOutput, isFalse);
        expect(result.manualWorkflowReason, contains('offline'));
      },
    );

    test('all candidates unavailable: refuses silent degradation', () async {
      final ScriptedProviderAdapter adapter = ScriptedProviderAdapter(
        provider: 'cloud_a',
        script: <String, AiProviderResponse>{
          _primary: failure(_primary, AiFailureClass.connectivity),
          _secondary: failure(_secondary, AiFailureClass.connectivity),
          _tertiary: failure(_tertiary, AiFailureClass.connectivity),
        },
      );

      final AiOrchestrator orchestrator = buildOrchestrator(
        models: <ModelRecord>[
          approvedModel(modelKey: _primary, provider: 'cloud_a'),
          approvedModel(modelKey: _secondary, provider: 'cloud_a'),
          approvedModel(modelKey: _tertiary, provider: 'cloud_a'),
        ],
        policies: <RoutingPolicy>[buildPolicy()],
        adapters: <String, AiProviderAdapter>{'cloud_a': adapter},
      );

      final AiTaskResult result = await orchestrator.run(
        buildRequest(),
        connectivity: ConnectivityState.online,
      );

      expect(result.outcome, AiTaskOutcome.manualWorkflow);
      expect(result.attempts, hasLength(3));
      expect(result.output, isEmpty);
    });

    test(
      'manual fallback disabled: the task fails rather than degrading',
      () async {
        final ScriptedProviderAdapter adapter = ScriptedProviderAdapter(
          provider: 'cloud_a',
          script: <String, AiProviderResponse>{
            _primary: failure(_primary, AiFailureClass.connectivity),
          },
        );

        final AiOrchestrator orchestrator = buildOrchestrator(
          models: <ModelRecord>[
            approvedModel(modelKey: _primary, provider: 'cloud_a'),
          ],
          policies: <RoutingPolicy>[
            buildPolicy(
              secondary: null,
              tertiary: null,
              allowManualFallback: false,
            ),
          ],
          adapters: <String, AiProviderAdapter>{'cloud_a': adapter},
        );

        final AiTaskResult result = await orchestrator.run(
          buildRequest(),
          connectivity: ConnectivityState.online,
        );

        expect(result.outcome, AiTaskOutcome.failed);
        expect(result.requiresManualWorkflow, isTrue);
      },
    );

    test(
      'unapproved model: execution is blocked as a governance fault',
      () async {
        final ScriptedProviderAdapter adapter = ScriptedProviderAdapter(
          provider: 'cloud_a',
          script: <String, AiProviderResponse>{_primary: success(_primary)},
        );

        final AiOrchestrator orchestrator = buildOrchestrator(
          models: <ModelRecord>[
            // Discovered in a provider catalog but never evaluated or approved.
            approvedModel(
              modelKey: _primary,
              provider: 'cloud_a',
              lifecycle: ModelLifecycleStatus.discovered,
              evaluation: ModelEvaluationStatus.notEvaluated,
              enabled: false,
              evaluationSetRevision: null,
            ),
          ],
          policies: <RoutingPolicy>[
            buildPolicy(secondary: null, tertiary: null, offline: null),
          ],
          adapters: <String, AiProviderAdapter>{'cloud_a': adapter},
        );

        final AiTaskResult result = await orchestrator.run(
          buildRequest(),
          connectivity: ConnectivityState.online,
        );

        expect(result.outcome, AiTaskOutcome.rejected);
        expect(
          result.attempts.single.failureClass,
          AiFailureClass.modelNotApproved,
        );
        // The provider was never contacted.
        expect(adapter.receivedRequests, isEmpty);
      },
    );

    test('unregistered provider adapter blocks execution', () async {
      final AiOrchestrator orchestrator = buildOrchestrator(
        models: <ModelRecord>[
          approvedModel(
            modelKey: _primary,
            provider: 'provider_without_adapter',
          ),
        ],
        policies: <RoutingPolicy>[
          buildPolicy(secondary: null, tertiary: null, offline: null),
        ],
        adapters: const <String, AiProviderAdapter>{},
      );

      final AiTaskResult result = await orchestrator.run(
        buildRequest(),
        connectivity: ConnectivityState.online,
      );

      expect(result.outcome, AiTaskOutcome.rejected);
      expect(
        result.attempts.single.failureClass,
        AiFailureClass.modelNotApproved,
      );
    });

    test(
      'unsupported modality: the task is not silently reinterpreted',
      () async {
        final ScriptedProviderAdapter adapter = ScriptedProviderAdapter(
          provider: 'cloud_a',
          script: <String, AiProviderResponse>{_primary: success(_primary)},
        );

        final AiOrchestrator orchestrator = buildOrchestrator(
          models: <ModelRecord>[
            // Text-only model asked to process an image.
            approvedModel(
              modelKey: _primary,
              provider: 'cloud_a',
              modalities: <Modality>{Modality.text},
            ),
          ],
          policies: <RoutingPolicy>[
            buildPolicy(secondary: null, tertiary: null, offline: null),
          ],
          adapters: <String, AiProviderAdapter>{'cloud_a': adapter},
        );

        final AiTaskResult result = await orchestrator.run(
          buildRequest(modality: Modality.image),
          connectivity: ConnectivityState.online,
        );

        expect(result.outcome, AiTaskOutcome.rejected);
        expect(
          result.attempts.single.failureClass,
          AiFailureClass.unsupportedModality,
        );
        expect(adapter.receivedRequests, isEmpty);
      },
    );

    test(
      'safety block: the decision is authoritative and not failed over',
      () async {
        final ScriptedProviderAdapter adapter = ScriptedProviderAdapter(
          provider: 'cloud_a',
          script: <String, AiProviderResponse>{
            _primary: failure(_primary, AiFailureClass.safetyBlocked),
            _secondary: success(_secondary),
          },
        );

        final AiOrchestrator orchestrator = buildOrchestrator(
          models: <ModelRecord>[
            approvedModel(modelKey: _primary, provider: 'cloud_a'),
            approvedModel(modelKey: _secondary, provider: 'cloud_a'),
          ],
          policies: <RoutingPolicy>[buildPolicy()],
          adapters: <String, AiProviderAdapter>{'cloud_a': adapter},
        );

        final AiTaskResult result = await orchestrator.run(
          buildRequest(),
          connectivity: ConnectivityState.online,
        );

        expect(result.outcome, AiTaskOutcome.rejected);
        expect(result.attempts, hasLength(1));
        // The secondary was never tried: a safety block is not a provider failure.
        expect(
          adapter.receivedRequests.where(
            (AiExecutionRequest r) => r.modelKey == _secondary,
          ),
          isEmpty,
        );
      },
    );

    test('authorization faults terminate rather than failing over', () async {
      final ScriptedProviderAdapter adapter = ScriptedProviderAdapter(
        provider: 'cloud_a',
        script: <String, AiProviderResponse>{
          _primary: failure(_primary, AiFailureClass.authorization),
          _secondary: success(_secondary),
        },
      );

      final AiOrchestrator orchestrator = buildOrchestrator(
        models: <ModelRecord>[
          approvedModel(modelKey: _primary, provider: 'cloud_a'),
          approvedModel(modelKey: _secondary, provider: 'cloud_a'),
        ],
        policies: <RoutingPolicy>[buildPolicy()],
        adapters: <String, AiProviderAdapter>{'cloud_a': adapter},
      );

      final AiTaskResult result = await orchestrator.run(
        buildRequest(),
        connectivity: ConnectivityState.online,
      );

      expect(result.outcome, AiTaskOutcome.rejected);
      expect(result.attempts, hasLength(1));
    });

    test('no routing policy: enters the manual workflow', () async {
      final AiOrchestrator orchestrator = buildOrchestrator(
        models: <ModelRecord>[
          approvedModel(modelKey: _primary, provider: 'cloud_a'),
        ],
        policies: const <RoutingPolicy>[],
        adapters: const <String, AiProviderAdapter>{},
      );

      final AiTaskResult result = await orchestrator.run(
        buildRequest(),
        connectivity: ConnectivityState.online,
      );

      expect(result.outcome, AiTaskOutcome.manualWorkflow);
      expect(result.requiresHumanReview, isTrue);
      expect(result.routingPolicyRevision, 'unconfigured');
    });

    test('disabled routing policy: enters the manual workflow', () async {
      final AiOrchestrator orchestrator = buildOrchestrator(
        models: <ModelRecord>[
          approvedModel(modelKey: _primary, provider: 'cloud_a'),
        ],
        policies: <RoutingPolicy>[buildPolicy(enabled: false)],
        adapters: const <String, AiProviderAdapter>{},
      );

      final AiTaskResult result = await orchestrator.run(
        buildRequest(),
        connectivity: ConnectivityState.online,
      );

      expect(result.outcome, AiTaskOutcome.manualWorkflow);
    });
  });

  group('clinical safety invariant', () {
    test('failover does not clear the human-review requirement', () async {
      final ScriptedProviderAdapter adapter = ScriptedProviderAdapter(
        provider: 'cloud_a',
        script: <String, AiProviderResponse>{
          _primary: failure(_primary, AiFailureClass.timeout),
          _secondary: success(_secondary),
        },
      );

      final AiOrchestrator orchestrator = buildOrchestrator(
        models: <ModelRecord>[
          approvedModel(modelKey: _primary, provider: 'cloud_a'),
          approvedModel(modelKey: _secondary, provider: 'cloud_a'),
        ],
        policies: <RoutingPolicy>[buildPolicy()],
        adapters: <String, AiProviderAdapter>{'cloud_a': adapter},
      );

      final AiTaskResult result = await orchestrator.run(
        buildRequest(),
        connectivity: ConnectivityState.online,
      );

      expect(result.outcome, AiTaskOutcome.completed);
      expect(result.modelKey, _secondary);
      // The requirement comes from the policy, never from the responding model.
      expect(result.requiresHumanReview, isTrue);
    });

    test('a candidate below the engine risk tier is refused', () async {
      final ScriptedProviderAdapter adapter = ScriptedProviderAdapter(
        provider: 'cloud_a',
        script: <String, AiProviderResponse>{_primary: success(_primary)},
      );

      final AiOrchestrator orchestrator = buildOrchestrator(
        models: <ModelRecord>[
          approvedModel(
            modelKey: _primary,
            provider: 'cloud_a',
            risk: ClinicalRiskLevel.standard,
          ),
        ],
        policies: <RoutingPolicy>[
          buildPolicy(secondary: null, tertiary: null, offline: null),
        ],
        adapters: <String, AiProviderAdapter>{'cloud_a': adapter},
      );

      final AiTaskResult result = await orchestrator.run(
        // A high-risk triage task.
        buildRequest(),
        connectivity: ConnectivityState.online,
      );

      expect(result.outcome, AiTaskOutcome.rejected);
      expect(
        result.attempts.single.failureClass,
        AiFailureClass.unsupportedModality,
      );
    });

    test('an on-device-only task is refused a cloud candidate', () async {
      final ScriptedProviderAdapter adapter = ScriptedProviderAdapter(
        provider: 'cloud_a',
        script: <String, AiProviderResponse>{_primary: success(_primary)},
      );

      final AiOrchestrator orchestrator = buildOrchestrator(
        models: <ModelRecord>[
          approvedModel(
            modelKey: _primary,
            provider: 'cloud_a',
            privacy: DataPrivacyClass.phiPermitted,
          ),
        ],
        policies: <RoutingPolicy>[
          buildPolicy(secondary: null, tertiary: null, offline: null),
        ],
        adapters: <String, AiProviderAdapter>{'cloud_a': adapter},
      );

      final AiTaskResult result = await orchestrator.run(
        buildRequest(privacy: DataPrivacyClass.onDeviceOnly),
        connectivity: ConnectivityState.online,
      );

      expect(result.outcome, AiTaskOutcome.rejected);
      expect(adapter.receivedRequests, isEmpty);
    });

    test(
      'a structured-output engine refuses a model without JSON support',
      () async {
        final ScriptedProviderAdapter adapter = ScriptedProviderAdapter(
          provider: 'cloud_a',
          script: <String, AiProviderResponse>{_primary: success(_primary)},
        );

        final AiOrchestrator orchestrator = buildOrchestrator(
          models: <ModelRecord>[
            approvedModel(
              modelKey: _primary,
              provider: 'cloud_a',
              structuredJson: false,
            ),
          ],
          policies: <RoutingPolicy>[
            buildPolicy(secondary: null, tertiary: null, offline: null),
          ],
          adapters: <String, AiProviderAdapter>{'cloud_a': adapter},
        );

        final AiTaskResult result = await orchestrator.run(
          buildRequest(),
          connectivity: ConnectivityState.online,
        );

        expect(result.outcome, AiTaskOutcome.rejected);
      },
    );

    test(
      'routing decisions are reconstructable from the attempt trail',
      () async {
        final ScriptedProviderAdapter adapter = ScriptedProviderAdapter(
          provider: 'cloud_a',
          script: <String, AiProviderResponse>{
            _primary: failure(_primary, AiFailureClass.timeout),
            _secondary: failure(_secondary, AiFailureClass.rateLimit),
            _tertiary: success(_tertiary),
          },
        );

        final AiOrchestrator orchestrator = buildOrchestrator(
          models: <ModelRecord>[
            approvedModel(modelKey: _primary, provider: 'cloud_a'),
            approvedModel(modelKey: _secondary, provider: 'cloud_a'),
            approvedModel(modelKey: _tertiary, provider: 'cloud_a'),
          ],
          policies: <RoutingPolicy>[buildPolicy()],
          adapters: <String, AiProviderAdapter>{'cloud_a': adapter},
        );

        final AiTaskResult result = await orchestrator.run(
          buildRequest(),
          connectivity: ConnectivityState.online,
        );

        expect(
          result.attempts.map((AiAttemptRecord a) => a.attemptNumber),
          <int>[1, 2, 3],
        );
        expect(result.attempts.map((AiAttemptRecord a) => a.modelKey), <String>[
          _primary,
          _secondary,
          _tertiary,
        ]);
        expect(
          result.attempts.map((AiAttemptRecord a) => a.failureClass),
          <AiFailureClass?>[
            AiFailureClass.timeout,
            AiFailureClass.rateLimit,
            null,
          ],
        );
        for (final AiAttemptRecord attempt in result.attempts) {
          expect(attempt.modelRevision, isNotEmpty);
        }
      },
    );

    test('no PHI reaches the diagnostic log', () async {
      final ScriptedProviderAdapter adapter = ScriptedProviderAdapter(
        provider: 'cloud_a',
        script: <String, AiProviderResponse>{_primary: success(_primary)},
      );

      final AiOrchestrator orchestrator = buildOrchestrator(
        models: <ModelRecord>[
          approvedModel(modelKey: _primary, provider: 'cloud_a'),
        ],
        policies: <RoutingPolicy>[buildPolicy()],
        adapters: <String, AiProviderAdapter>{'cloud_a': adapter},
      );

      await orchestrator.run(
        buildRequest(),
        connectivity: ConnectivityState.online,
      );

      for (final NodexLogRecord record in sink.records) {
        expect(record.message, isNot(contains('chest pain')));
      }
    });
  });

  group('model registry governance', () {
    test('an ACTIVE model without a passed evaluation is ineligible', () {
      final ModelRecord model = approvedModel(
        modelKey: 'm',
        provider: 'p',
        evaluation: ModelEvaluationStatus.inProgress,
      );
      expect(model.isEligibleForClinicalExecution, isFalse);
    });

    test(
      'an ACTIVE model without an acceptance-set revision is ineligible',
      () {
        final ModelRecord model = approvedModel(
          modelKey: 'm',
          provider: 'p',
          evaluationSetRevision: null,
        );
        expect(model.isEligibleForClinicalExecution, isFalse);
      },
    );

    test('a disabled model is ineligible even when approved', () {
      final ModelRecord model = approvedModel(
        modelKey: 'm',
        provider: 'p',
        enabled: false,
      );
      expect(model.isEligibleForClinicalExecution, isFalse);
    });

    test('a deprecated model is ineligible for new production traffic', () {
      final ModelRecord model = approvedModel(
        modelKey: 'm',
        provider: 'p',
        lifecycle: ModelLifecycleStatus.deprecated,
      );
      expect(model.isEligibleForClinicalExecution, isFalse);
    });

    test(
      'an unknown lifecycle value falls back to the least privileged state',
      () {
        expect(
          ModelLifecycleStatus.fromWire('promoted_by_catalog_scan'),
          ModelLifecycleStatus.discovered,
        );
      },
    );

    test('routing policy candidate chains preserve declared order', () {
      final RoutingPolicy policy = buildPolicy();
      expect(policy.onlineCandidates, <String>[
        _primary,
        _secondary,
        _tertiary,
      ]);
      expect(policy.offlineCandidates, <String>[_offline]);
    });

    test(
      'an absent candidate is omitted rather than nulled into the chain',
      () {
        final RoutingPolicy policy = buildPolicy(tertiary: null);
        expect(policy.onlineCandidates, <String>[_primary, _secondary]);
      },
    );
  });

  group('privacy and risk compatibility', () {
    test('on-device-only data requires an on-device-only model', () {
      expect(
        DataPrivacyClass.onDeviceOnly.isCompatibleWith(
          DataPrivacyClass.onDeviceOnly,
        ),
        isTrue,
      );
      expect(
        DataPrivacyClass.onDeviceOnly.isCompatibleWith(
          DataPrivacyClass.phiPermitted,
        ),
        isFalse,
      );
    });

    test('de-identified data may run on a PHI-permitted model', () {
      expect(
        DataPrivacyClass.deIdentified.isCompatibleWith(
          DataPrivacyClass.phiPermitted,
        ),
        isTrue,
      );
    });

    test('PHI may not run on a public-only model', () {
      expect(
        DataPrivacyClass.phiPermitted.isCompatibleWith(DataPrivacyClass.public),
        isFalse,
      );
    });

    test('risk tiers compare by rank', () {
      expect(
        ClinicalRiskLevel.high.isSatisfiedBy(ClinicalRiskLevel.high),
        isTrue,
      );
      expect(
        ClinicalRiskLevel.high.isSatisfiedBy(ClinicalRiskLevel.elevated),
        isFalse,
      );
      expect(
        ClinicalRiskLevel.standard.isSatisfiedBy(ClinicalRiskLevel.high),
        isTrue,
      );
    });
  });

  group('AI engine catalogue', () {
    test('every engine key follows the ai_ naming contract', () {
      for (final String key in AiEngines.engineKeys) {
        expect(
          RegExp(r'^ai_[a-z][a-z0-9_]{2,63}$').hasMatch(key),
          isTrue,
          reason: '$key must match the engine key pattern',
        );
      }
    });

    test('clinically material engines require human review', () {
      const List<String> mustReview = <String>[
        AiEngines.clinicalNotesScribe,
        AiEngines.triageAdvisory,
        AiEngines.labReportInterpreter,
        AiEngines.clinicalDocumentExtraction,
        AiEngines.dischargeSummary,
        AiEngines.medicationInteraction,
      ];

      for (final String key in mustReview) {
        expect(
          AiEngines.definitionOf(key)!.requiresHumanReview,
          isTrue,
          reason: '$key output must not become a clinical decision unreviewed',
        );
      }
    });

    test('clinical document extraction is on-device and may abstain', () {
      final AiEngineDefinition engine = AiEngines.definitionOf(
        AiEngines.clinicalDocumentExtraction,
      )!;

      expect(engine.privacyClass, DataPrivacyClass.onDeviceOnly);
      expect(engine.modality, Modality.image);
      expect(engine.riskLevel, ClinicalRiskLevel.high);
      // Abstention is mandatory: a critical field that cannot be read
      // confidently must not be guessed.
      expect(engine.mayAbstain, isTrue);
    });

    test('every engine declares a response schema', () {
      for (final AiEngineDefinition engine in AiEngines.definitions.values) {
        expect(engine.requiresStructuredOutput, isTrue);
        expect(engine.responseSchemaKey, isNotEmpty);
      }
    });
  });
}
