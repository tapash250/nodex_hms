/// NODEX AI Orchestrator: deterministic routing, controlled failover and the
/// clinical safety boundary.
///
/// For every engine the Orchestrator resolves exactly one ordered candidate
/// chain from the active deployment profile and evaluates it in order:
/// primary, secondary, tertiary, offline fallback, manual workflow.
///
/// Three invariants are enforced here and covered by tests:
///
/// 1. Failover changes the execution source, never the safety boundary. The
///    required human-review flag and the engine's risk, modality, privacy and
///    structured-output requirements are properties of the policy, not of the
///    candidate that happened to answer.
/// 2. Only eligible failure classes advance the chain. Authorization errors,
///    invalid input, schema violations and safety blocks terminate the attempt.
/// 3. When no approved candidate is available the system refuses silent
///    degradation and returns a manual-workflow outcome.
library;

import 'package:meta/meta.dart';
import 'package:nodex_hms/ai/contracts/ai_contracts.dart';
import 'package:nodex_hms/ai/gateway/ai_gateway.dart';
import 'package:nodex_hms/ai/model_registry/model_registry.dart';
import 'package:nodex_hms/ai/orchestrator/circuit_breaker.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';

/// Terminal outcome of an orchestrated AI task.
enum AiTaskOutcome {
  /// A candidate produced output that passed validation.
  completed('completed'),

  /// Execution was refused, for example by a governance or safety gate.
  rejected('rejected'),

  /// The model declined to answer because it could not do so safely.
  abstained('abstained'),

  /// Every eligible candidate failed.
  failed('failed'),

  /// The task was handed to a human process instead of being degraded silently.
  manualWorkflow('manual_workflow');

  const AiTaskOutcome(this.wireValue);

  /// Value persisted in `ai_requests.final_outcome`.
  final String wireValue;
}

/// One attempt within a candidate chain, recorded for audit reconstruction.
@immutable
final class AiAttemptRecord {
  /// Creates an attempt record.
  const AiAttemptRecord({
    required this.attemptNumber,
    required this.modelKey,
    required this.provider,
    required this.modelRevision,
    required this.circuitState,
    required this.latency,
    required this.succeeded,
    this.failureClass,
    this.failureDetail,
  });

  /// 1-based position in the chain.
  final int attemptNumber;

  /// Candidate that was attempted.
  final String modelKey;

  /// Provider that served the attempt.
  final String provider;

  /// Model revision that executed.
  final String modelRevision;

  /// Circuit state at dispatch.
  final CircuitState circuitState;

  /// Measured latency.
  final Duration latency;

  /// Whether the attempt produced output.
  final bool succeeded;

  /// Normalized failure class, when the attempt failed.
  final AiFailureClass? failureClass;

  /// Non-PHI failure detail.
  final String? failureDetail;
}

/// The result of orchestrating one AI task.
@immutable
final class AiTaskResult {
  /// Creates a task result.
  const AiTaskResult({
    required this.requestId,
    required this.engineKey,
    required this.outcome,
    required this.attempts,
    required this.routingPolicyRevision,
    required this.deploymentProfileRevision,
    required this.requiresHumanReview,
    this.output = const <String, Object?>{},
    this.modelKey,
    this.modelRevision,
    this.provider,
    this.confidence,
    this.manualWorkflowReason,
  });

  /// Correlates this result with its audit records.
  final String requestId;

  /// The engine that was orchestrated.
  final String engineKey;

  /// Terminal outcome.
  final AiTaskOutcome outcome;

  /// Every attempt in order, including failures.
  final List<AiAttemptRecord> attempts;

  /// Routing policy revision that produced the chain.
  final String routingPolicyRevision;

  /// Deployment profile revision in force.
  final String deploymentProfileRevision;

  /// Whether the output requires human review before any clinical use.
  ///
  /// Carried through unchanged from the routing policy. A successful failover
  /// never clears it.
  final bool requiresHumanReview;

  /// Structured output, empty unless [outcome] is [AiTaskOutcome.completed].
  final Map<String, Object?> output;

  /// Model that produced the output.
  final String? modelKey;

  /// Revision of the model that produced the output.
  final String? modelRevision;

  /// Provider that served the output.
  final String? provider;

  /// Model-reported confidence, when available.
  final double? confidence;

  /// Why the task fell through to a manual workflow.
  final String? manualWorkflowReason;

  /// Whether output is available for review.
  bool get hasOutput => outcome == AiTaskOutcome.completed && output.isNotEmpty;

  /// Whether the caller must fall back to a deterministic or manual process.
  bool get requiresManualWorkflow =>
      outcome == AiTaskOutcome.manualWorkflow ||
      outcome == AiTaskOutcome.failed ||
      outcome == AiTaskOutcome.rejected;
}

/// Orchestrates AI tasks under deployment policy.
final class AiOrchestrator {
  /// Creates an orchestrator.
  AiOrchestrator({
    required this._gateway,
    required this._registry,
    required this._logger,
    required this._deploymentProfileRevision,
    CircuitBreaker? circuitBreaker,
    void Function(CircuitTransition transition)? onCircuitTransition,
  }) : _circuitBreaker =
           circuitBreaker ??
           CircuitBreaker(
             threshold: 3,
             cooldown: const Duration(minutes: 5),
             onTransition: onCircuitTransition,
           );

  static const String _module = 'ai.orchestrator';

  final AiGateway _gateway;
  final AiModelRegistry _registry;
  final NodexLogger _logger;
  final String _deploymentProfileRevision;
  final CircuitBreaker _circuitBreaker;

  /// Circuit state for [modelKey], exposed for diagnostics surfaces.
  CircuitState circuitStateOf(String modelKey) =>
      _circuitBreaker.stateOf(modelKey);

  /// Executes the task described by [request] under the policy for its engine.
  ///
  /// [connectivity] selects the candidate chain: offline tasks are routed only to
  /// an approved on-device fallback, because attempting a cloud candidate without
  /// a WAN path would burn the policy timeout for a guaranteed failure.
  Future<AiTaskResult> run(
    AiExecutionRequest request, {
    required ConnectivityState connectivity,
  }) async {
    final RoutingPolicy? policy = await _registry.policy(request.engineKey);

    if (policy == null || !policy.enabled) {
      return _manualWorkflow(
        request: request,
        policyRevision: policy?.policyRevision ?? 'unconfigured',
        requiresHumanReview: true,
        reason: policy == null
            ? 'No routing policy is configured for this engine.'
            : 'The routing policy for this engine is disabled.',
        attempts: const <AiAttemptRecord>[],
      );
    }

    final List<String> chain = connectivity.isOnline
        ? policy.onlineCandidates
        : policy.offlineCandidates;

    if (chain.isEmpty) {
      return _manualWorkflow(
        request: request,
        policyRevision: policy.policyRevision,
        requiresHumanReview: policy.requireHumanReview,
        reason: connectivity.isOnline
            ? 'The routing policy declares no online candidates.'
            : 'No approved offline fallback is configured for this engine.',
        attempts: const <AiAttemptRecord>[],
      );
    }

    final List<AiAttemptRecord> attempts = <AiAttemptRecord>[];
    int attemptNumber = 0;

    for (final String candidateKey in chain) {
      attemptNumber += 1;

      // An open circuit is skipped rather than attempted: the cool-down exists
      // precisely to stop hammering an unhealthy provider.
      final CircuitState circuitState = _circuitBreaker.stateOf(candidateKey);
      if (!circuitState.admitsTraffic) {
        attempts.add(
          AiAttemptRecord(
            attemptNumber: attemptNumber,
            modelKey: candidateKey,
            provider: 'skipped',
            modelRevision: 'skipped',
            circuitState: circuitState,
            latency: Duration.zero,
            succeeded: false,
            failureClass: AiFailureClass.providerServer,
            failureDetail: 'Circuit is open; candidate skipped by policy.',
          ),
        );
        continue;
      }

      final AiExecutionRequest attempt = request.forCandidate(
        modelKey: candidateKey,
        attemptNumber: attemptNumber,
        timeout: policy.timeout,
      );

      final AiProviderResponse response = await _gateway.execute(attempt);

      if (response.isSuccess) {
        _circuitBreaker.recordSuccess(candidateKey);
        attempts.add(
          AiAttemptRecord(
            attemptNumber: attemptNumber,
            modelKey: response.modelKey,
            provider: response.provider,
            modelRevision: response.modelRevision,
            circuitState: circuitState,
            latency: response.latency,
            succeeded: true,
          ),
        );

        _logger.info(
          _module,
          'AI task completed.',
          operation: 'orchestrator.run',
          outcome: AiTaskOutcome.completed.wireValue,
          dimensions: <String, Object?>{
            'engine_key': request.engineKey,
            'model_key': response.modelKey,
            'provider': response.provider,
            'attempt_number': attemptNumber,
            'latency_ms': response.latency.inMilliseconds,
            'policy_revision': policy.policyRevision,
          },
        );

        return AiTaskResult(
          requestId: request.requestId,
          engineKey: request.engineKey,
          outcome: AiTaskOutcome.completed,
          attempts: List<AiAttemptRecord>.unmodifiable(attempts),
          routingPolicyRevision: policy.policyRevision,
          deploymentProfileRevision: _deploymentProfileRevision,
          // Never weakened by which candidate answered.
          requiresHumanReview: policy.requireHumanReview,
          output: response.output,
          modelKey: response.modelKey,
          modelRevision: response.modelRevision,
          provider: response.provider,
          confidence: response.confidence,
        );
      }

      final AiFailureClass failureClass =
          response.failureClass ?? AiFailureClass.unknown;
      _circuitBreaker.recordFailure(candidateKey, failureClass);

      attempts.add(
        AiAttemptRecord(
          attemptNumber: attemptNumber,
          modelKey: response.modelKey,
          provider: response.provider,
          modelRevision: response.modelRevision,
          circuitState: circuitState,
          latency: response.latency,
          succeeded: false,
          failureClass: failureClass,
          failureDetail: response.failureDetail,
        ),
      );

      _logger.warning(
        _module,
        'AI attempt failed.',
        operation: 'orchestrator.run',
        outcome: 'failed',
        errorCode: failureClass.wireValue,
        dimensions: <String, Object?>{
          'engine_key': request.engineKey,
          'model_key': response.modelKey,
          'provider': response.provider,
          'attempt_number': attemptNumber,
          'circuit_state': circuitState.wireValue,
        },
      );

      // Ineligible classes terminate the chain. A safety block or an
      // authorization fault is not something a different provider can fix, and
      // retrying elsewhere would obscure the real cause.
      if (!failureClass.failoverEligible) {
        return _terminal(
          request: request,
          policy: policy,
          attempts: attempts,
          failureClass: failureClass,
        );
      }
    }

    // Chain exhausted.
    return _manualWorkflow(
      request: request,
      policyRevision: policy.policyRevision,
      requiresHumanReview: policy.requireHumanReview,
      reason: policy.allowManualFallback
          ? 'All approved candidates were unavailable.'
          : 'All approved candidates failed and manual fallback is disabled.',
      attempts: attempts,
      outcome: policy.allowManualFallback
          ? AiTaskOutcome.manualWorkflow
          : AiTaskOutcome.failed,
    );
  }

  AiTaskResult _terminal({
    required AiExecutionRequest request,
    required RoutingPolicy policy,
    required List<AiAttemptRecord> attempts,
    required AiFailureClass failureClass,
  }) {
    final AiTaskOutcome outcome = switch (failureClass) {
      AiFailureClass.safetyBlocked => AiTaskOutcome.rejected,
      AiFailureClass.modelNotApproved => AiTaskOutcome.rejected,
      AiFailureClass.authorization => AiTaskOutcome.rejected,
      AiFailureClass.invalidInput => AiTaskOutcome.rejected,
      AiFailureClass.unsupportedModality => AiTaskOutcome.rejected,
      AiFailureClass.schemaValidation => AiTaskOutcome.failed,
      _ => AiTaskOutcome.failed,
    };

    return AiTaskResult(
      requestId: request.requestId,
      engineKey: request.engineKey,
      outcome: outcome,
      attempts: List<AiAttemptRecord>.unmodifiable(attempts),
      routingPolicyRevision: policy.policyRevision,
      deploymentProfileRevision: _deploymentProfileRevision,
      requiresHumanReview: policy.requireHumanReview,
      manualWorkflowReason:
          'Terminal failure class ${failureClass.wireValue}; '
          'failover is not permitted for this class.',
    );
  }

  AiTaskResult _manualWorkflow({
    required AiExecutionRequest request,
    required String policyRevision,
    required bool requiresHumanReview,
    required String reason,
    required List<AiAttemptRecord> attempts,
    AiTaskOutcome outcome = AiTaskOutcome.manualWorkflow,
  }) {
    _logger.warning(
      _module,
      'AI task routed to a manual workflow.',
      operation: 'orchestrator.run',
      outcome: outcome.wireValue,
      dimensions: <String, Object?>{
        'engine_key': request.engineKey,
        'attempt_count': attempts.length,
        'policy_revision': policyRevision,
      },
    );

    return AiTaskResult(
      requestId: request.requestId,
      engineKey: request.engineKey,
      outcome: outcome,
      attempts: List<AiAttemptRecord>.unmodifiable(attempts),
      routingPolicyRevision: policyRevision,
      deploymentProfileRevision: _deploymentProfileRevision,
      requiresHumanReview: requiresHumanReview,
      manualWorkflowReason: reason,
    );
  }
}
