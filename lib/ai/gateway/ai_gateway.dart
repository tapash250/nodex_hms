/// NODEX AI Gateway: provider transport and adapter selection.
///
/// The architecture boundary is mandatory and enforced by this file's narrow
/// surface:
///
/// * The Gateway MUST NOT decide clinical task routing or override Orchestrator
///   policy. It receives a fully-resolved [AiExecutionRequest] naming exactly one
///   model, and executes it.
/// * The Orchestrator MUST NOT contain provider-specific API formatting,
///   authentication, transport logic or error parsing. All of that lives inside
///   [AiProviderAdapter] implementations reached only through here.
///
/// Adding a provider means registering an adapter. No clinical workflow, domain
/// use case, safety rule, repository or presentation file changes.
library;

import 'dart:async';

import 'package:nodex_hms/ai/contracts/ai_contracts.dart';
import 'package:nodex_hms/ai/model_registry/model_registry.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';

/// Routes a resolved execution request to the adapter for its provider.
final class AiGateway {
  /// Creates a gateway over [adapters], keyed by provider identifier.
  AiGateway({
    required Map<String, AiProviderAdapter> adapters,
    required this._registry,
    required this._logger,
  }) : _adapters = Map<String, AiProviderAdapter>.unmodifiable(adapters);

  static const String _module = 'ai.gateway';

  final Map<String, AiProviderAdapter> _adapters;
  final AiModelRegistry _registry;
  final NodexLogger _logger;

  /// Provider identifiers with a registered adapter.
  Iterable<String> get registeredProviders => _adapters.keys;

  /// Whether an adapter exists for [provider].
  bool hasAdapter(String provider) => _adapters.containsKey(provider);

  /// Executes [request] against the adapter for its model's provider.
  ///
  /// Never throws for provider-side conditions: transport failures, timeouts and
  /// provider rejections are returned as [AiProviderResponse.failure] with a
  /// normalized [AiFailureClass], so the Orchestrator's failover decision stays
  /// deterministic.
  ///
  /// Two conditions are refused before any transport occurs, because both are
  /// governance faults rather than provider failures:
  /// [AiFailureClass.modelNotApproved] when the model is not eligible for
  /// clinical execution, and [AiFailureClass.unsupportedModality] when the model
  /// cannot serve the request's modality.
  Future<AiProviderResponse> execute(AiExecutionRequest request) async {
    final ModelRecord? model = await _registry.model(request.modelKey);

    if (model == null) {
      _logger.error(
        _module,
        'Execution refused: the requested model is not registered.',
        operation: 'gateway.execute',
        outcome: 'rejected',
        errorCode: AiFailureClass.modelNotApproved.wireValue,
        dimensions: <String, Object?>{
          'engine_key': request.engineKey,
          'model_key': request.modelKey,
        },
      );
      return AiProviderResponse.failure(
        modelKey: request.modelKey,
        modelRevision: 'unknown',
        provider: 'unresolved',
        failureClass: AiFailureClass.modelNotApproved,
        latency: Duration.zero,
        failureDetail: 'Model is not present in the registry.',
      );
    }

    if (!model.isEligibleForClinicalExecution) {
      _logger.error(
        _module,
        'Execution refused: the model is not approved and active for clinical use.',
        operation: 'gateway.execute',
        outcome: 'rejected',
        errorCode: AiFailureClass.modelNotApproved.wireValue,
        dimensions: <String, Object?>{
          'engine_key': request.engineKey,
          'model_key': request.modelKey,
          'lifecycle_status': model.lifecycleStatus.wireValue,
          'evaluation_status': model.evaluationStatus.wireValue,
        },
      );
      return AiProviderResponse.failure(
        modelKey: model.modelKey,
        modelRevision: model.modelRevision,
        provider: model.provider,
        failureClass: AiFailureClass.modelNotApproved,
        latency: Duration.zero,
        failureDetail:
            'Model lifecycle is ${model.lifecycleStatus.wireValue} with '
            'evaluation ${model.evaluationStatus.wireValue}.',
      );
    }

    final AiProviderAdapter? adapter = _adapters[model.provider];
    if (adapter == null) {
      _logger.error(
        _module,
        'Execution refused: no adapter is registered for the model provider.',
        operation: 'gateway.execute',
        outcome: 'rejected',
        errorCode: AiFailureClass.modelNotApproved.wireValue,
        dimensions: <String, Object?>{
          'engine_key': request.engineKey,
          'model_key': request.modelKey,
          'provider': model.provider,
        },
      );
      return AiProviderResponse.failure(
        modelKey: model.modelKey,
        modelRevision: model.modelRevision,
        provider: model.provider,
        failureClass: AiFailureClass.modelNotApproved,
        latency: Duration.zero,
        failureDetail: 'No adapter registered for provider.',
      );
    }

    if (!model.satisfies(
      modality: request.modality,
      riskLevel: request.riskLevel,
      privacyClass: request.privacyClass,
      requiresStructuredOutput: request.requireStructuredOutput,
    )) {
      _logger.warning(
        _module,
        'Execution refused: the model does not meet the task requirements.',
        operation: 'gateway.execute',
        outcome: 'rejected',
        errorCode: AiFailureClass.unsupportedModality.wireValue,
        dimensions: <String, Object?>{
          'engine_key': request.engineKey,
          'model_key': request.modelKey,
          'modality': request.modality.wireValue,
          'risk_level': request.riskLevel.wireValue,
        },
      );
      return AiProviderResponse.failure(
        modelKey: model.modelKey,
        modelRevision: model.modelRevision,
        provider: model.provider,
        failureClass: AiFailureClass.unsupportedModality,
        latency: Duration.zero,
        failureDetail:
            'Model does not satisfy the engine modality, structured-output, '
            'risk or privacy requirements.',
      );
    }

    final Stopwatch stopwatch = Stopwatch()..start();
    try {
      final AiProviderResponse response = await adapter
          .execute(request)
          .timeout(request.timeout);
      stopwatch.stop();
      return response;
    } on TimeoutException {
      stopwatch.stop();
      return AiProviderResponse.failure(
        modelKey: model.modelKey,
        modelRevision: model.modelRevision,
        provider: adapter.provider,
        providerRevision: adapter.providerRevision,
        failureClass: AiFailureClass.timeout,
        latency: stopwatch.elapsed,
        failureDetail: 'Provider did not respond within the policy timeout.',
      );
    } on Object catch (error) {
      stopwatch.stop();
      // Provider-specific error interpretation stays inside the adapter.
      final AiFailureClass failureClass = adapter.mapError(error);
      return AiProviderResponse.failure(
        modelKey: model.modelKey,
        modelRevision: model.modelRevision,
        provider: adapter.provider,
        providerRevision: adapter.providerRevision,
        failureClass: failureClass,
        latency: stopwatch.elapsed,
        failureDetail: 'Adapter reported ${failureClass.wireValue}.',
      );
    }
  }

  /// Probes the health of the adapter serving [provider].
  ///
  /// Returns an unavailable report when no adapter is registered, so a missing
  /// adapter behaves like an unreachable provider rather than throwing into
  /// routing logic.
  Future<ProviderHealth> healthOf(String provider) async {
    final AiProviderAdapter? adapter = _adapters[provider];
    if (adapter == null) {
      return const ProviderHealth.unavailable(
        detail: 'No adapter registered for provider.',
      );
    }
    try {
      return await adapter.healthCheck();
    } on Object catch (error) {
      return ProviderHealth.unavailable(
        detail: 'Health probe failed: ${adapter.mapError(error).wireValue}.',
      );
    }
  }

  /// Reports the capabilities of the adapter serving [provider].
  Future<AiProviderCapabilities?> capabilitiesOf(String provider) async {
    final AiProviderAdapter? adapter = _adapters[provider];
    if (adapter == null) {
      return null;
    }
    try {
      return await adapter.capabilities();
    } on Object {
      return null;
    }
  }
}
