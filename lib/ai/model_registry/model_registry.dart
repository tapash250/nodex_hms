/// AI model registry and per-engine routing policy.
///
/// Registry data is configuration, not business logic. It makes provider
/// configuration, capability metadata, evaluation status and lifecycle state
/// explicit so that routing is reproducible from stored revisions.
///
/// The governance invariant enforced here: an available model is not an approved
/// model. [ModelRecord.isEligibleForClinicalExecution] requires ACTIVE lifecycle,
/// a passed evaluation and a recorded evaluation-set revision. No discovery
/// process can promote a model into clinical production.
library;

import 'package:meta/meta.dart';
import 'package:nodex_hms/ai/contracts/ai_contracts.dart';

/// Lifecycle state of a registered model.
///
/// `DISCOVERED -> EVALUATING -> APPROVED -> ACTIVE -> DEPRECATED -> RETIRED`.
enum ModelLifecycleStatus {
  /// Catalog metadata known; not eligible for clinical execution.
  discovered('discovered'),

  /// Capability, performance, safety and intended-use evaluation in progress.
  evaluating('evaluating'),

  /// Required evaluation gates passed for a defined engine/task scope.
  approved('approved'),

  /// Enabled in a deployment profile; may receive production traffic.
  active('active'),

  /// Available only for controlled migration, rollback or audit replay.
  deprecated('deprecated'),

  /// May not receive new production clinical requests.
  retired('retired');

  const ModelLifecycleStatus(this.wireValue);

  /// Value persisted in `ai_model_registry.lifecycle_status`.
  final String wireValue;

  /// Whether a model in this state may serve production clinical traffic.
  bool get permitsProductionTraffic => this == ModelLifecycleStatus.active;

  /// Parses a wire value, defaulting to [discovered] for unknown input.
  ///
  /// Defaulting to the least privileged state is deliberate: an unrecognised
  /// lifecycle value must never be treated as approved.
  static ModelLifecycleStatus fromWire(String value) {
    for (final ModelLifecycleStatus status in ModelLifecycleStatus.values) {
      if (status.wireValue == value) {
        return status;
      }
    }
    return ModelLifecycleStatus.discovered;
  }
}

/// Evaluation state of a registered model.
enum ModelEvaluationStatus {
  /// No evaluation has been performed.
  notEvaluated('not_evaluated'),

  /// Evaluation is under way.
  inProgress('in_progress'),

  /// Evaluation gates passed.
  passed('passed'),

  /// Evaluation gates failed.
  failed('failed');

  const ModelEvaluationStatus(this.wireValue);

  /// Value persisted in `ai_model_registry.evaluation_status`.
  final String wireValue;

  /// Parses a wire value, defaulting to [notEvaluated].
  static ModelEvaluationStatus fromWire(String value) {
    for (final ModelEvaluationStatus status in ModelEvaluationStatus.values) {
      if (status.wireValue == value) {
        return status;
      }
    }
    return ModelEvaluationStatus.notEvaluated;
  }
}

/// A registered model and its governance state.
@immutable
final class ModelRecord {
  /// Creates a registry record.
  const ModelRecord({
    required this.modelKey,
    required this.provider,
    required this.displayName,
    required this.modelRevision,
    required this.modalities,
    required this.clinicalRiskTier,
    required this.privacyClass,
    required this.lifecycleStatus,
    required this.evaluationStatus,
    required this.enabled,
    this.evaluationSetRevision,
    this.supportsStructuredJson = false,
    this.supportsToolCalling = false,
    this.supportsVision = false,
    this.contextWindow,
    this.maxOutputTokens,
    this.latencyTargetMs,
    this.memoryRequirementMb,
    this.priority = 100,
    this.intendedUse,
  });

  /// Deployment-neutral identifier used by routing policy and clinical code.
  final String modelKey;

  /// Provider identifier, resolved to an adapter by the Gateway.
  final String provider;

  /// Human-readable name for governance surfaces.
  final String displayName;

  /// Exact model revision, recorded with every execution.
  final String modelRevision;

  /// Modalities this model accepts.
  final Set<Modality> modalities;

  /// Highest clinical risk tier this model is approved for.
  final ClinicalRiskLevel clinicalRiskTier;

  /// Most sensitive data class this model may process.
  final DataPrivacyClass privacyClass;

  /// Governance lifecycle state.
  final ModelLifecycleStatus lifecycleStatus;

  /// Evaluation state.
  final ModelEvaluationStatus evaluationStatus;

  /// Whether the model is enabled in the active deployment profile.
  final bool enabled;

  /// Revision of the locked acceptance set the evaluation was run against.
  final String? evaluationSetRevision;

  /// Whether the model can be constrained to schema-valid JSON.
  final bool supportsStructuredJson;

  /// Whether the model supports tool/function calling.
  final bool supportsToolCalling;

  /// Whether the model accepts image input.
  final bool supportsVision;

  /// Maximum input context length in tokens.
  final int? contextWindow;

  /// Maximum output length in tokens.
  final int? maxOutputTokens;

  /// Target latency used for candidate comparison.
  final int? latencyTargetMs;

  /// Device memory required, relevant for on-device models.
  final int? memoryRequirementMb;

  /// Ordering hint among otherwise equivalent candidates.
  final int priority;

  /// Declared intended use, recorded for governance review.
  final String? intendedUse;

  /// Whether this model may execute clinical traffic.
  ///
  /// Requires ACTIVE lifecycle, enablement in the profile, a passed evaluation
  /// and a recorded acceptance-set revision. Any missing element blocks
  /// execution: provider availability alone is not evidence of clinical fitness.
  bool get isEligibleForClinicalExecution =>
      lifecycleStatus.permitsProductionTraffic &&
      enabled &&
      evaluationStatus == ModelEvaluationStatus.passed &&
      (evaluationSetRevision?.isNotEmpty ?? false);

  /// Whether this model can serve a task with the given requirements.
  ///
  /// Checks modality, structured-output capability, risk tier and privacy class.
  /// Failover may not place a task on a model failing any of these.
  bool satisfies({
    required Modality modality,
    required ClinicalRiskLevel riskLevel,
    required DataPrivacyClass privacyClass,
    required bool requiresStructuredOutput,
  }) {
    final bool modalityOk =
        modalities.contains(modality) ||
        modalities.contains(Modality.multimodal);
    if (!modalityOk) {
      return false;
    }
    if (requiresStructuredOutput && !supportsStructuredJson) {
      return false;
    }
    if (!riskLevel.isSatisfiedBy(clinicalRiskTier)) {
      return false;
    }
    return privacyClass.isCompatibleWith(this.privacyClass);
  }

  /// Whether this model runs on-device and can serve as an offline fallback.
  bool get isOnDevice => privacyClass == DataPrivacyClass.onDeviceOnly;

  /// Materialises a record from a database row.
  static ModelRecord fromRow(Map<String, Object?> row) {
    Set<Modality> parseModalities(Object? raw) {
      if (raw is Iterable<Object?>) {
        return raw
            .whereType<String>()
            .map(Modality.fromWire)
            .whereType<Modality>()
            .toSet();
      }
      if (raw is String && raw.isNotEmpty) {
        // PowerSync stores text[] as a JSON-ish string; accept both shapes.
        return raw
            .replaceAll(RegExp(r'[\[\]{}"]'), '')
            .split(',')
            .map((String part) => part.trim())
            .where((String part) => part.isNotEmpty)
            .map(Modality.fromWire)
            .whereType<Modality>()
            .toSet();
      }
      return const <Modality>{};
    }

    bool parseBool(Object? raw) => raw == true || raw == 1 || raw == '1';

    return ModelRecord(
      modelKey: row['model_key']! as String,
      provider: row['provider']! as String,
      displayName:
          row['display_name'] as String? ?? row['model_key']! as String,
      modelRevision: row['model_revision'] as String? ?? 'unspecified',
      modalities: parseModalities(row['modality']),
      clinicalRiskTier:
          ClinicalRiskLevel.fromWire(
            row['clinical_risk_tier'] as String? ?? '',
          ) ??
          ClinicalRiskLevel.low,
      privacyClass:
          DataPrivacyClass.fromWire(row['privacy_class'] as String? ?? '') ??
          DataPrivacyClass.public,
      lifecycleStatus: ModelLifecycleStatus.fromWire(
        row['lifecycle_status'] as String? ?? '',
      ),
      evaluationStatus: ModelEvaluationStatus.fromWire(
        row['evaluation_status'] as String? ?? '',
      ),
      enabled: parseBool(row['enabled']),
      evaluationSetRevision: row['evaluation_set_revision'] as String?,
      supportsStructuredJson: parseBool(row['supports_structured_json']),
      supportsToolCalling: parseBool(row['supports_tool_calling']),
      supportsVision: parseBool(row['supports_vision']),
      contextWindow: row['context_window'] as int?,
      maxOutputTokens: row['max_output_tokens'] as int?,
      latencyTargetMs: row['latency_target_ms'] as int?,
      memoryRequirementMb: row['memory_requirement_mb'] as int?,
      priority: row['priority'] as int? ?? 100,
      intendedUse: row['intended_use'] as String?,
    );
  }
}

/// Deterministic candidate chain and execution policy for one AI engine.
@immutable
final class RoutingPolicy {
  /// Creates a routing policy.
  const RoutingPolicy({
    required this.engineKey,
    required this.primaryModelKey,
    required this.policyRevision,
    required this.minimumRiskCapability,
    this.secondaryModelKey,
    this.tertiaryModelKey,
    this.offlineFallbackModelKey,
    this.timeout = const Duration(milliseconds: 12000),
    this.maxAttempts = 1,
    this.circuitBreakerThreshold = 3,
    this.circuitBreakerCooldown = const Duration(seconds: 300),
    this.requireStructuredOutput = true,
    this.requireHumanReview = true,
    this.allowManualFallback = true,
    this.enabled = true,
  });

  /// The engine this policy governs.
  final String engineKey;

  /// First candidate.
  final String primaryModelKey;

  /// Second candidate, attempted after an eligible primary failure.
  final String? secondaryModelKey;

  /// Third candidate, attempted after an eligible secondary failure.
  final String? tertiaryModelKey;

  /// Candidate used when WAN access is unavailable or policy requires local
  /// execution.
  final String? offlineFallbackModelKey;

  /// Per-attempt timeout.
  final Duration timeout;

  /// Maximum attempts against a single candidate.
  final int maxAttempts;

  /// Consecutive eligible failures before the circuit opens.
  final int circuitBreakerThreshold;

  /// How long the circuit stays open before a half-open probe.
  final Duration circuitBreakerCooldown;

  /// Whether responses must validate against the engine schema.
  final bool requireStructuredOutput;

  /// Whether clinically material output requires human review.
  ///
  /// Failover must never clear this: the safety boundary is independent of the
  /// execution source.
  final bool requireHumanReview;

  /// Whether a manual workflow is an acceptable terminal outcome.
  final bool allowManualFallback;

  /// Minimum clinical risk capability a candidate must hold.
  final ClinicalRiskLevel minimumRiskCapability;

  /// Whether this policy is active.
  final bool enabled;

  /// Policy revision recorded with every routing decision.
  final String policyRevision;

  /// The ordered online candidate chain, excluding the offline fallback.
  List<String> get onlineCandidates => <String>[
    primaryModelKey,
    ?secondaryModelKey,
    ?tertiaryModelKey,
  ];

  /// The full ordered chain used when WAN access is unavailable.
  ///
  /// Only the offline fallback is eligible: attempting a cloud candidate without
  /// connectivity would burn the policy timeout for a guaranteed failure.
  List<String> get offlineCandidates => <String>[?offlineFallbackModelKey];

  /// Materialises a policy from a database row.
  static RoutingPolicy fromRow(Map<String, Object?> row) {
    bool parseBool(Object? raw) => raw == true || raw == 1 || raw == '1';

    return RoutingPolicy(
      engineKey: row['engine_key']! as String,
      primaryModelKey: row['primary_model_key']! as String,
      secondaryModelKey: row['secondary_model_key'] as String?,
      tertiaryModelKey: row['tertiary_model_key'] as String?,
      offlineFallbackModelKey: row['offline_fallback_model_key'] as String?,
      timeout: Duration(milliseconds: row['timeout_ms'] as int? ?? 12000),
      maxAttempts: row['max_attempts'] as int? ?? 1,
      circuitBreakerThreshold: row['circuit_breaker_threshold'] as int? ?? 3,
      circuitBreakerCooldown: Duration(
        seconds: row['circuit_breaker_seconds'] as int? ?? 300,
      ),
      requireStructuredOutput: parseBool(row['require_structured_output']),
      requireHumanReview: parseBool(row['require_human_review']),
      allowManualFallback: parseBool(row['allow_manual_fallback']),
      minimumRiskCapability:
          ClinicalRiskLevel.fromWire(
            row['minimum_risk_capability'] as String? ?? '',
          ) ??
          ClinicalRiskLevel.standard,
      enabled: parseBool(row['enabled']),
      policyRevision: row['policy_revision'] as String? ?? 'unspecified',
    );
  }
}

/// Read access to model and routing configuration.
///
/// Implemented over the replicated local tables so that routing decisions remain
/// available offline, and so the Orchestrator never issues a network call to
/// decide what to run.
abstract interface class AiModelRegistry {
  /// Returns the record for [modelKey], or null when unregistered.
  Future<ModelRecord?> model(String modelKey);

  /// Returns the routing policy for [engineKey], or null when unconfigured.
  Future<RoutingPolicy?> policy(String engineKey);

  /// Returns every registered model, for governance surfaces.
  Future<List<ModelRecord>> allModels();
}

/// In-memory registry used by tests and by the stub deployment profile.
final class InMemoryAiModelRegistry implements AiModelRegistry {
  /// Creates a registry over fixed configuration.
  InMemoryAiModelRegistry({
    required List<ModelRecord> models,
    required List<RoutingPolicy> policies,
  }) : _models = <String, ModelRecord>{
         for (final ModelRecord model in models) model.modelKey: model,
       },
       _policies = <String, RoutingPolicy>{
         for (final RoutingPolicy policy in policies) policy.engineKey: policy,
       };

  final Map<String, ModelRecord> _models;
  final Map<String, RoutingPolicy> _policies;

  @override
  Future<ModelRecord?> model(String modelKey) async => _models[modelKey];

  @override
  Future<RoutingPolicy?> policy(String engineKey) async => _policies[engineKey];

  @override
  Future<List<ModelRecord>> allModels() async =>
      _models.values.toList(growable: false);
}
