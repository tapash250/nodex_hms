/// Tests for the provider circuit breaker.
///
/// Two properties matter and are asserted here: only *eligible* provider failures
/// count toward tripping the breaker, and the state machine follows the
/// specification's transitions including half-open recovery.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/ai/contracts/ai_contracts.dart';
import 'package:nodex_hms/ai/orchestrator/circuit_breaker.dart';

void main() {
  group('CircuitBreaker state machine', () {
    test('starts healthy and admits traffic', () {
      final CircuitBreaker breaker = CircuitBreaker(
        threshold: 3,
        cooldown: const Duration(minutes: 5),
      );

      expect(breaker.stateOf('model_a'), CircuitState.healthy);
      expect(breaker.allowsRequest('model_a'), isTrue);
    });

    test('degrades on the first eligible failure', () {
      final CircuitBreaker breaker = CircuitBreaker(
        threshold: 3,
        cooldown: const Duration(minutes: 5),
      );

      breaker.recordFailure('model_a', AiFailureClass.timeout);

      expect(breaker.stateOf('model_a'), CircuitState.degraded);
      // Degraded still admits traffic: one timeout is not an outage.
      expect(breaker.allowsRequest('model_a'), isTrue);
      expect(breaker.consecutiveFailures('model_a'), 1);
    });

    test('opens once the threshold is reached', () {
      final CircuitBreaker breaker = CircuitBreaker(
        threshold: 3,
        cooldown: const Duration(minutes: 5),
      );

      for (int i = 0; i < 3; i++) {
        breaker.recordFailure('model_a', AiFailureClass.providerServer);
      }

      expect(breaker.stateOf('model_a'), CircuitState.open);
      expect(breaker.allowsRequest('model_a'), isFalse);
    });

    test('success resets the counter and returns to healthy', () {
      final CircuitBreaker breaker = CircuitBreaker(
        threshold: 3,
        cooldown: const Duration(minutes: 5),
      );

      breaker.recordFailure('model_a', AiFailureClass.timeout);
      breaker.recordFailure('model_a', AiFailureClass.timeout);
      breaker.recordSuccess('model_a');

      expect(breaker.stateOf('model_a'), CircuitState.healthy);
      expect(breaker.consecutiveFailures('model_a'), 0);
    });

    test('moves to half-open after the cool-down elapses', () {
      DateTime now = DateTime.utc(2026, 9, 1, 12);
      final CircuitBreaker breaker = CircuitBreaker(
        threshold: 2,
        cooldown: const Duration(minutes: 5),
        clock: () => now,
      );

      breaker.recordFailure('model_a', AiFailureClass.connectivity);
      breaker.recordFailure('model_a', AiFailureClass.connectivity);
      expect(breaker.stateOf('model_a'), CircuitState.open);

      now = now.add(const Duration(minutes: 4));
      expect(breaker.stateOf('model_a'), CircuitState.open);

      now = now.add(const Duration(minutes: 2));
      expect(breaker.stateOf('model_a'), CircuitState.halfOpen);
      expect(breaker.allowsRequest('model_a'), isTrue);
    });

    test('a successful probe closes the circuit', () {
      DateTime now = DateTime.utc(2026, 9, 1, 12);
      final CircuitBreaker breaker = CircuitBreaker(
        threshold: 2,
        cooldown: const Duration(minutes: 5),
        clock: () => now,
      );

      breaker.recordFailure('model_a', AiFailureClass.timeout);
      breaker.recordFailure('model_a', AiFailureClass.timeout);
      now = now.add(const Duration(minutes: 6));
      expect(breaker.stateOf('model_a'), CircuitState.halfOpen);

      breaker.recordSuccess('model_a');
      expect(breaker.stateOf('model_a'), CircuitState.healthy);
    });

    test('a failed probe re-opens the circuit and restarts the cool-down', () {
      DateTime now = DateTime.utc(2026, 9, 1, 12);
      final CircuitBreaker breaker = CircuitBreaker(
        threshold: 2,
        cooldown: const Duration(minutes: 5),
        clock: () => now,
      );

      breaker.recordFailure('model_a', AiFailureClass.timeout);
      breaker.recordFailure('model_a', AiFailureClass.timeout);
      now = now.add(const Duration(minutes: 6));
      expect(breaker.stateOf('model_a'), CircuitState.halfOpen);

      breaker.recordFailure('model_a', AiFailureClass.timeout);
      expect(breaker.stateOf('model_a'), CircuitState.open);

      // Cool-down restarted from the failed probe, not from the original trip.
      now = now.add(const Duration(minutes: 4));
      expect(breaker.stateOf('model_a'), CircuitState.open);
      now = now.add(const Duration(minutes: 2));
      expect(breaker.stateOf('model_a'), CircuitState.halfOpen);
    });

    test('tracks circuits independently per key', () {
      final CircuitBreaker breaker = CircuitBreaker(
        threshold: 1,
        cooldown: const Duration(minutes: 5),
      );

      breaker.recordFailure('model_a', AiFailureClass.timeout);

      expect(breaker.stateOf('model_a'), CircuitState.open);
      expect(breaker.stateOf('model_b'), CircuitState.healthy);
    });

    test('reset clears all state', () {
      final CircuitBreaker breaker = CircuitBreaker(
        threshold: 1,
        cooldown: const Duration(minutes: 5),
      );

      breaker.recordFailure('model_a', AiFailureClass.timeout);
      breaker.reset();

      expect(breaker.stateOf('model_a'), CircuitState.healthy);
    });
  });

  group('CircuitBreaker failure eligibility', () {
    test('ignores failure classes that are not provider health signals', () {
      // A safety block or authorization fault says nothing about the provider,
      // and tripping the breaker on it would take a healthy provider offline.
      const List<AiFailureClass> ineligible = <AiFailureClass>[
        AiFailureClass.authorization,
        AiFailureClass.invalidInput,
        AiFailureClass.schemaValidation,
        AiFailureClass.safetyBlocked,
        AiFailureClass.unsupportedModality,
        AiFailureClass.modelNotApproved,
      ];

      for (final AiFailureClass failureClass in ineligible) {
        final CircuitBreaker breaker = CircuitBreaker(
          threshold: 1,
          cooldown: const Duration(minutes: 5),
        );
        breaker.recordFailure('model_a', failureClass);

        expect(
          breaker.stateOf('model_a'),
          CircuitState.healthy,
          reason: '${failureClass.wireValue} must not trip the breaker',
        );
        expect(breaker.consecutiveFailures('model_a'), 0);
      }
    });

    test('counts failure classes that indicate provider trouble', () {
      const List<AiFailureClass> eligible = <AiFailureClass>[
        AiFailureClass.connectivity,
        AiFailureClass.timeout,
        AiFailureClass.rateLimit,
        AiFailureClass.providerServer,
      ];

      for (final AiFailureClass failureClass in eligible) {
        final CircuitBreaker breaker = CircuitBreaker(
          threshold: 1,
          cooldown: const Duration(minutes: 5),
        );
        breaker.recordFailure('model_a', failureClass);

        expect(
          breaker.stateOf('model_a'),
          CircuitState.open,
          reason: '${failureClass.wireValue} should trip at threshold 1',
        );
      }
    });
  });

  group('CircuitBreaker transition reporting', () {
    test('reports every transition for the audit trail', () {
      DateTime now = DateTime.utc(2026, 9, 1, 12);
      final List<CircuitTransition> transitions = <CircuitTransition>[];

      final CircuitBreaker breaker = CircuitBreaker(
        threshold: 2,
        cooldown: const Duration(minutes: 5),
        clock: () => now,
        onTransition: transitions.add,
      );

      breaker.recordFailure('model_a', AiFailureClass.timeout);
      breaker.recordFailure('model_a', AiFailureClass.timeout);
      now = now.add(const Duration(minutes: 6));
      breaker.stateOf('model_a');
      breaker.recordSuccess('model_a');

      expect(transitions.map((CircuitTransition t) => t.to), <CircuitState>[
        CircuitState.degraded,
        CircuitState.open,
        CircuitState.halfOpen,
        CircuitState.healthy,
      ]);
      expect(transitions.first.key, 'model_a');
      expect(transitions.first.from, CircuitState.healthy);
      expect(transitions.first.failureClass, AiFailureClass.timeout);
    });

    test('does not report a transition when the state is unchanged', () {
      final List<CircuitTransition> transitions = <CircuitTransition>[];
      final CircuitBreaker breaker = CircuitBreaker(
        threshold: 5,
        cooldown: const Duration(minutes: 5),
        onTransition: transitions.add,
      );

      breaker.recordFailure('model_a', AiFailureClass.timeout);
      breaker.recordFailure('model_a', AiFailureClass.timeout);
      breaker.recordFailure('model_a', AiFailureClass.timeout);

      // healthy -> degraded once; subsequent failures stay degraded.
      expect(transitions, hasLength(1));
      expect(breaker.consecutiveFailures('model_a'), 3);
    });
  });

  group('AiFailureClass contract', () {
    test('wire values are unique', () {
      final Set<String> wireValues = AiFailureClass.values
          .map((AiFailureClass f) => f.wireValue)
          .toSet();
      expect(wireValues.length, AiFailureClass.values.length);
    });

    test('rate limiting advances routing without an immediate retry', () {
      expect(AiFailureClass.rateLimit.retryable, isFalse);
      expect(AiFailureClass.rateLimit.failoverEligible, isTrue);
    });

    test('safety blocks neither retry nor fail over', () {
      expect(AiFailureClass.safetyBlocked.retryable, isFalse);
      expect(AiFailureClass.safetyBlocked.failoverEligible, isFalse);
    });

    test('fromWire falls back to unknown', () {
      expect(AiFailureClass.fromWire('nonexistent'), AiFailureClass.unknown);
    });
  });
}
