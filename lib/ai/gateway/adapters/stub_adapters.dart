/// Placeholder provider adapters for the Phase 1 foundation.
///
/// The AI abstraction is complete and testable before any real provider is
/// wired. Two adapters ship here:
///
/// * [UnconfiguredProviderAdapter] represents a provider named in the deployment
///   profile whose transport is not yet implemented. It reports unavailable and
///   fails every request with [AiFailureClass.connectivity], so the Orchestrator
///   exercises its real failover path and terminates in a manual workflow rather
///   than appearing to succeed.
/// * [ScriptedProviderAdapter] returns predetermined responses for tests.
///
/// Registering a real provider means adding an adapter alongside these. No
/// clinical workflow, domain use case, safety rule, repository or presentation
/// file changes, which is the provider-independence acceptance criterion.
library;

import 'package:nodex_hms/ai/contracts/ai_contracts.dart';

/// Provider identifiers used by the deployment profile.
abstract final class AiProviders {
  /// Cloud routing provider.
  static const String openRouter = 'openrouter';

  /// Managed cloud inference provider.
  static const String ollamaCloud = 'ollama_cloud';

  /// On-device GGUF runtime.
  static const String llamaCpp = 'llama_cpp';

  /// Terminal pseudo-provider meaning "hand this to a human".
  static const String manualWorkflow = 'manual_workflow';
}

/// An adapter for a provider whose transport is not yet implemented.
///
/// Deliberately fails rather than throwing or silently succeeding: a
/// half-configured provider must degrade into the manual workflow path, and the
/// AI audit trail must record why.
final class UnconfiguredProviderAdapter implements AiProviderAdapter {
  /// Creates an adapter for [provider].
  const UnconfiguredProviderAdapter({
    required this.provider,
    this.reason = 'Provider transport is not configured in this build.',
  });

  @override
  final String provider;

  /// Non-PHI explanation recorded with each refused request.
  final String reason;

  @override
  String get providerRevision => 'unconfigured';

  @override
  Future<AiProviderResponse> execute(AiExecutionRequest request) async =>
      AiProviderResponse.failure(
        modelKey: request.modelKey,
        modelRevision: 'unconfigured',
        provider: provider,
        providerRevision: providerRevision,
        failureClass: AiFailureClass.connectivity,
        latency: Duration.zero,
        failureDetail: reason,
      );

  @override
  Future<ProviderHealth> healthCheck() async =>
      ProviderHealth.unavailable(detail: reason);

  @override
  Future<AiProviderCapabilities> capabilities() async =>
      const AiProviderCapabilities(
        modalities: <Modality>{},
        supportsStructuredOutput: false,
        supportsToolCalling: false,
        maxContextTokens: null,
        maxOutputTokens: null,
      );

  @override
  AiFailureClass mapError(Object error) => AiFailureClass.connectivity;
}

/// A deterministic adapter driven by a script, for tests and local development.
final class ScriptedProviderAdapter implements AiProviderAdapter {
  /// Creates an adapter that replies according to [script].
  ///
  /// [script] maps a model key to the response for that model. Model keys absent
  /// from the script fail with [AiFailureClass.unknown].
  ScriptedProviderAdapter({
    required this.provider,
    required Map<String, AiProviderResponse> script,
    this._health = const ProviderHealth.healthy(),
    this._capabilities = const AiProviderCapabilities(
      modalities: <Modality>{Modality.text, Modality.multimodal},
      supportsStructuredOutput: true,
      supportsToolCalling: false,
      maxContextTokens: 8192,
      maxOutputTokens: 2048,
    ),
  }) : _script = Map<String, AiProviderResponse>.unmodifiable(script);

  @override
  final String provider;

  final Map<String, AiProviderResponse> _script;
  final ProviderHealth _health;
  final AiProviderCapabilities _capabilities;

  /// Requests received, in order, for test assertions.
  final List<AiExecutionRequest> receivedRequests = <AiExecutionRequest>[];

  @override
  String get providerRevision => 'scripted';

  @override
  Future<AiProviderResponse> execute(AiExecutionRequest request) async {
    receivedRequests.add(request);
    final AiProviderResponse? scripted = _script[request.modelKey];
    if (scripted != null) {
      return scripted;
    }
    return AiProviderResponse.failure(
      modelKey: request.modelKey,
      modelRevision: 'scripted',
      provider: provider,
      providerRevision: providerRevision,
      failureClass: AiFailureClass.unknown,
      latency: Duration.zero,
      failureDetail: 'No scripted response for this model key.',
    );
  }

  @override
  Future<ProviderHealth> healthCheck() async => _health;

  @override
  Future<AiProviderCapabilities> capabilities() async => _capabilities;

  @override
  AiFailureClass mapError(Object error) => AiFailureClass.unknown;
}
