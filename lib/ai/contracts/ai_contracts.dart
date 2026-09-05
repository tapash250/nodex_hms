/// Provider-neutral AI contracts.
///
/// The specification draws a hard boundary: the Orchestrator decides *what* runs
/// and under which policy; the Gateway decides *how* to reach a provider. These
/// types are the vocabulary they share, and they contain no provider-specific
/// fields — no HTTP paths, no API-key fields, no provider-native message objects.
///
/// Clinical workflow code depends only on this file and never on an adapter.
library;

import 'package:meta/meta.dart';

/// Clinical risk tier of an AI task.
///
/// Matches `ai_model_registry.clinical_risk_tier`. A candidate model must meet
/// or exceed the engine's declared minimum; failover may never quietly downgrade
/// it.
enum ClinicalRiskLevel {
  /// No clinical bearing, for example formatting assistance.
  low('low', 0),

  /// Routine clinical support with human review.
  standard('standard', 1),

  /// Materially influences a clinical decision.
  elevated('elevated', 2),

  /// Directly informs a high-risk action such as triage acuity.
  high('high', 3);

  const ClinicalRiskLevel(this.wireValue, this.rank);

  /// Value persisted in the database.
  final String wireValue;

  /// Ordering used for capability comparison.
  final int rank;

  /// Whether a model rated [other] is adequate for a task rated `this`.
  bool isSatisfiedBy(ClinicalRiskLevel other) => other.rank >= rank;

  /// Parses a wire value, or null when unrecognised.
  static ClinicalRiskLevel? fromWire(String value) {
    for (final ClinicalRiskLevel level in ClinicalRiskLevel.values) {
      if (level.wireValue == value) {
        return level;
      }
    }
    return null;
  }
}

/// Privacy classification of the data an AI task processes.
///
/// Matches `ai_model_registry.privacy_class`. A task carrying identifiable
/// clinical content may not execute on a model classified for public data only.
enum DataPrivacyClass {
  /// No clinical or personal content.
  public('public', 0),

  /// Clinical content with identifiers removed.
  deIdentified('de_identified', 1),

  /// Identifiable clinical content permitted on this model.
  phiPermitted('phi_permitted', 2),

  /// Must not leave the device under any circumstances.
  onDeviceOnly('on_device_only', 3);

  const DataPrivacyClass(this.wireValue, this.sensitivity);

  /// Value persisted in the database.
  final String wireValue;

  /// Relative sensitivity, used for compatibility checks.
  final int sensitivity;

  /// Whether data classified `this` may execute on a model classified [model].
  ///
  /// On-device-only data requires an on-device-only model. Otherwise the model's
  /// classification must be at least as permissive as the data requires.
  bool isCompatibleWith(DataPrivacyClass model) {
    if (this == DataPrivacyClass.onDeviceOnly) {
      return model == DataPrivacyClass.onDeviceOnly;
    }
    if (model == DataPrivacyClass.onDeviceOnly) {
      return true;
    }
    return model.sensitivity >= sensitivity;
  }

  /// Parses a wire value, or null when unrecognised.
  static DataPrivacyClass? fromWire(String value) {
    for (final DataPrivacyClass value0 in DataPrivacyClass.values) {
      if (value0.wireValue == value) {
        return value0;
      }
    }
    return null;
  }
}

/// Input modality of an AI task.
enum Modality {
  /// Text-only input.
  text('text'),

  /// Audio input, for example clinical dictation.
  audio('audio'),

  /// Image input, for example a photographed prescription.
  image('image'),

  /// Combined modalities.
  multimodal('multimodal');

  const Modality(this.wireValue);

  /// Value persisted in the database.
  final String wireValue;

  /// Parses a wire value, or null when unrecognised.
  static Modality? fromWire(String value) {
    for (final Modality modality in Modality.values) {
      if (modality.wireValue == value) {
        return modality;
      }
    }
    return null;
  }
}

/// Normalized provider failure classes.
///
/// Mirrors the specification's failure table. Retry and failover eligibility are
/// properties of the class, not decisions made at the call site, so that routing
/// stays deterministic and auditable.
enum AiFailureClass {
  /// Network unreachable.
  connectivity('connectivity', retryable: true, failoverEligible: true),

  /// Provider did not respond within the policy timeout.
  timeout('timeout', retryable: true, failoverEligible: true),

  /// Provider rate limit reached. Not retried immediately against the same
  /// provider; routing advances instead.
  rateLimit('rate_limit', retryable: false, failoverEligible: true),

  /// Provider returned a 5xx error.
  providerServer('provider_server', retryable: true, failoverEligible: true),

  /// Provider rejected the credentials. A configuration fault, never retried.
  authorization('authorization', retryable: false, failoverEligible: false),

  /// The caller supplied invalid input.
  invalidInput('invalid_input', retryable: false, failoverEligible: false),

  /// Response failed schema validation. Failover is policy-controlled.
  schemaValidation(
    'schema_validation',
    retryable: false,
    failoverEligible: false,
  ),

  /// The deterministic safety engine blocked the output. Authoritative.
  safetyBlocked('safety_blocked', retryable: false, failoverEligible: false),

  /// The candidate cannot handle the task's modality.
  unsupportedModality(
    'unsupported_modality',
    retryable: false,
    failoverEligible: false,
  ),

  /// The candidate is not approved for clinical execution.
  modelNotApproved(
    'model_not_approved',
    retryable: false,
    failoverEligible: false,
  ),

  /// Unclassified provider failure.
  unknown('unknown', retryable: false, failoverEligible: false);

  const AiFailureClass(
    this.wireValue, {
    required this.retryable,
    required this.failoverEligible,
  });

  /// Value persisted in `ai_responses.failure_class`.
  final String wireValue;

  /// Whether the same candidate may be retried.
  final bool retryable;

  /// Whether routing may advance to the next approved candidate.
  final bool failoverEligible;

  /// Parses a wire value, defaulting to [unknown].
  static AiFailureClass fromWire(String value) {
    for (final AiFailureClass failure in AiFailureClass.values) {
      if (failure.wireValue == value) {
        return failure;
      }
    }
    return AiFailureClass.unknown;
  }
}

/// Provider health as reported by an adapter.
enum ProviderHealthState {
  /// Provider is reachable and accepting requests.
  healthy,

  /// Provider is reachable but degraded.
  degraded,

  /// Provider is unreachable or refusing requests.
  unavailable,
}

/// Result of a provider health probe.
@immutable
final class ProviderHealth {
  /// Creates a health report.
  const ProviderHealth({required this.state, this.latency, this.detail});

  /// A healthy report with optional measured latency.
  const ProviderHealth.healthy({Duration? latency})
    : this(state: ProviderHealthState.healthy, latency: latency);

  /// An unavailable report with a non-PHI explanation.
  const ProviderHealth.unavailable({String? detail})
    : this(state: ProviderHealthState.unavailable, detail: detail);

  /// Reported state.
  final ProviderHealthState state;

  /// Probe latency, when measured.
  final Duration? latency;

  /// Non-PHI diagnostic detail.
  final String? detail;

  /// Whether the provider may receive traffic.
  bool get isUsable => state != ProviderHealthState.unavailable;
}

/// Capabilities an adapter reports for a provider/model pair.
@immutable
final class AiProviderCapabilities {
  /// Creates a capability report.
  const AiProviderCapabilities({
    required this.modalities,
    required this.supportsStructuredOutput,
    required this.supportsToolCalling,
    required this.maxContextTokens,
    required this.maxOutputTokens,
    this.requiresNetwork = true,
  });

  /// Modalities the provider accepts.
  final Set<Modality> modalities;

  /// Whether the provider can be constrained to emit schema-valid JSON.
  final bool supportsStructuredOutput;

  /// Whether the provider supports tool/function calling.
  final bool supportsToolCalling;

  /// Maximum input context length in tokens, when known.
  final int? maxContextTokens;

  /// Maximum output length in tokens, when known.
  final int? maxOutputTokens;

  /// Whether execution requires WAN connectivity.
  ///
  /// False for on-device runtimes, which is how the Orchestrator identifies a
  /// valid offline fallback.
  final bool requiresNetwork;

  /// Whether [modality] is supported.
  bool supports(Modality modality) =>
      modalities.contains(modality) || modalities.contains(Modality.multimodal);
}

/// A provider-neutral execution request issued by the Orchestrator.
///
/// Contains no provider-specific formatting. [sanitizedContext] has already been
/// through data minimisation: only fields the engine declares necessary are
/// present, and the request carries a digest rather than raw PHI into the audit
/// trail.
@immutable
final class AiExecutionRequest {
  /// Creates an execution request.
  const AiExecutionRequest({
    required this.requestId,
    required this.engineKey,
    required this.modelKey,
    required this.riskLevel,
    required this.privacyClass,
    required this.modality,
    required this.sanitizedContext,
    required this.timeout,
    required this.requireStructuredOutput,
    required this.contextDigest,
    this.attemptNumber = 1,
    this.maxOutputTokens,
    this.responseSchemaKey,
  });

  /// Correlates every attempt, safety decision and review for one task.
  final String requestId;

  /// The NODEX AI engine, for example `ai_triage_advisory`.
  final String engineKey;

  /// The approved model to execute, as a deployment-neutral key.
  final String modelKey;

  /// Clinical risk tier of the task.
  final ClinicalRiskLevel riskLevel;

  /// Privacy classification of the payload.
  final DataPrivacyClass privacyClass;

  /// Input modality.
  final Modality modality;

  /// Minimised, provider-neutral context.
  final Map<String, Object?> sanitizedContext;

  /// Policy timeout for this attempt.
  final Duration timeout;

  /// Whether the response must validate against the engine's JSON schema.
  final bool requireStructuredOutput;

  /// Digest of the sanitized context, recorded instead of the context itself.
  final String contextDigest;

  /// 1-based attempt number within the deterministic candidate chain.
  final int attemptNumber;

  /// Output token ceiling, when the engine imposes one.
  final int? maxOutputTokens;

  /// Identifier of the response schema the engine expects.
  final String? responseSchemaKey;

  /// Returns a copy targeting [modelKey] as attempt [attemptNumber].
  AiExecutionRequest forCandidate({
    required String modelKey,
    required int attemptNumber,
    Duration? timeout,
  }) => AiExecutionRequest(
    requestId: requestId,
    engineKey: engineKey,
    modelKey: modelKey,
    riskLevel: riskLevel,
    privacyClass: privacyClass,
    modality: modality,
    sanitizedContext: sanitizedContext,
    timeout: timeout ?? this.timeout,
    requireStructuredOutput: requireStructuredOutput,
    contextDigest: contextDigest,
    attemptNumber: attemptNumber,
    maxOutputTokens: maxOutputTokens,
    responseSchemaKey: responseSchemaKey,
  );
}

/// A normalized provider response.
///
/// Adapters translate provider-native payloads into this shape. No provider
/// error text, header or status code escapes the adapter unmapped.
@immutable
final class AiProviderResponse {
  /// Creates a successful response.
  const AiProviderResponse.success({
    required this.modelKey,
    required this.modelRevision,
    required this.provider,
    required this.output,
    required this.latency,
    this.inputTokens,
    this.outputTokens,
    this.confidence,
    this.providerRevision,
  }) : failureClass = null,
       failureDetail = null;

  /// Creates a failed response carrying a normalized failure class.
  const AiProviderResponse.failure({
    required this.modelKey,
    required this.modelRevision,
    required this.provider,
    required AiFailureClass this.failureClass,
    required this.latency,
    this.failureDetail,
    this.providerRevision,
  }) : output = const <String, Object?>{},
       inputTokens = null,
       outputTokens = null,
       confidence = null;

  /// The model key that executed.
  final String modelKey;

  /// Exact model revision, recorded in the AI audit trail.
  final String modelRevision;

  /// Provider identifier, for example `openrouter` or `llama_cpp`.
  final String provider;

  /// Adapter or provider implementation revision.
  final String? providerRevision;

  /// Structured output. Empty on failure.
  final Map<String, Object?> output;

  /// Measured execution latency.
  final Duration latency;

  /// Input token count, when reported.
  final int? inputTokens;

  /// Output token count, when reported.
  final int? outputTokens;

  /// Model-reported confidence in `[0, 1]`, when available.
  final double? confidence;

  /// Normalized failure class, null on success.
  final AiFailureClass? failureClass;

  /// Non-PHI failure detail.
  final String? failureDetail;

  /// Whether the attempt succeeded.
  bool get isSuccess => failureClass == null;
}

/// The contract every provider adapter implements.
///
/// The Gateway is the only component permitted to invoke provider-specific APIs.
/// Provider request shapes, authentication headers, naming conventions, response
/// parsing, rate-limit behavior and transport errors stay inside implementations
/// of this interface.
abstract interface class AiProviderAdapter {
  /// Provider identifier recorded in the audit trail.
  String get provider;

  /// Adapter implementation revision.
  String get providerRevision;

  /// Performs inference and returns a normalized response.
  ///
  /// Implementations must not throw for provider-side failures: they return a
  /// [AiProviderResponse.failure] carrying a mapped [AiFailureClass], so the
  /// Orchestrator's routing decision stays deterministic.
  Future<AiProviderResponse> execute(AiExecutionRequest request);

  /// Reports provider health without performing a clinical action.
  Future<ProviderHealth> healthCheck();

  /// Reports supported modalities and structured-output capabilities.
  Future<AiProviderCapabilities> capabilities();

  /// Maps a provider-specific error onto a normalized failure class.
  AiFailureClass mapError(Object error);
}
