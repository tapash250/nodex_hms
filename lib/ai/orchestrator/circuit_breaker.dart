/// Provider circuit breaker.
///
/// Implements the state machine from the specification:
///
/// ```text
/// HEALTHY -> (eligible failure) -> DEGRADED -> (threshold) -> OPEN
///   OPEN -> (cool-down + probe) -> HALF_OPEN -> success -> HEALTHY
///                                            -> failure -> OPEN
/// ```
///
/// Two properties matter. Only *eligible* provider failures count: an
/// authorization error or a safety block is a configuration or clinical decision,
/// not a provider health signal, and must not trip the breaker. And every state
/// transition is observable so it can be written to the AI audit trail.
library;

import 'package:meta/meta.dart';
import 'package:nodex_hms/ai/contracts/ai_contracts.dart';

/// Circuit state for one provider or model.
enum CircuitState {
  /// Accepting traffic; no recent eligible failures.
  healthy('healthy'),

  /// Accepting traffic, but eligible failures have been observed.
  degraded('degraded'),

  /// Refusing traffic until the cool-down elapses.
  open('open'),

  /// Allowing a single probe request to test recovery.
  halfOpen('half_open');

  const CircuitState(this.wireValue);

  /// Value persisted in `ai_responses.circuit_state`.
  final String wireValue;

  /// Whether a request may be dispatched in this state.
  bool get admitsTraffic => this != CircuitState.open;
}

/// A recorded circuit state transition.
@immutable
final class CircuitTransition {
  /// Creates a transition record.
  const CircuitTransition({
    required this.key,
    required this.from,
    required this.to,
    required this.at,
    required this.consecutiveFailures,
    this.failureClass,
  });

  /// The circuit identity, typically a model key.
  final String key;

  /// Prior state.
  final CircuitState from;

  /// New state.
  final CircuitState to;

  /// When the transition occurred.
  final DateTime at;

  /// Consecutive eligible failures at the time of transition.
  final int consecutiveFailures;

  /// The failure class that triggered the transition, when applicable.
  final AiFailureClass? failureClass;
}

/// Tracks circuit state across providers and models.
final class CircuitBreaker {
  /// Creates a breaker that opens after [threshold] consecutive eligible
  /// failures and stays open for [cooldown].
  CircuitBreaker({
    required this.threshold,
    required this.cooldown,
    DateTime Function()? clock,
    this.onTransition,
  }) : assert(threshold > 0, 'threshold must be positive'),
       _clock = clock ?? DateTime.now;

  /// Consecutive eligible failures required to open the circuit.
  final int threshold;

  /// How long the circuit remains open before permitting a probe.
  final Duration cooldown;

  /// Invoked on every state transition so it can be written to the audit trail.
  final void Function(CircuitTransition transition)? onTransition;

  final DateTime Function() _clock;

  final Map<String, _CircuitEntry> _entries = <String, _CircuitEntry>{};

  /// Current state of the circuit identified by [key].
  ///
  /// Reading the state also performs the time-based `OPEN -> HALF_OPEN`
  /// transition, so callers never see a stale open circuit after the cool-down.
  CircuitState stateOf(String key) {
    final _CircuitEntry? entry = _entries[key];
    if (entry == null) {
      return CircuitState.healthy;
    }

    if (entry.state == CircuitState.open) {
      final DateTime? openedAt = entry.openedAt;
      if (openedAt != null && !_clock().isBefore(openedAt.add(cooldown))) {
        _transition(key, entry, CircuitState.halfOpen);
      }
    }
    return entry.state;
  }

  /// Whether a request to [key] may be dispatched now.
  bool allowsRequest(String key) => stateOf(key).admitsTraffic;

  /// Records a successful execution against [key].
  void recordSuccess(String key) {
    final _CircuitEntry entry = _entries.putIfAbsent(key, _CircuitEntry.new);
    entry.consecutiveFailures = 0;
    if (entry.state != CircuitState.healthy) {
      _transition(key, entry, CircuitState.healthy);
    }
  }

  /// Records a failure against [key].
  ///
  /// Ineligible failure classes are ignored entirely: they neither increment the
  /// counter nor change state, because they say nothing about provider health.
  void recordFailure(String key, AiFailureClass failureClass) {
    if (!failureClass.failoverEligible) {
      return;
    }

    final _CircuitEntry entry = _entries.putIfAbsent(key, _CircuitEntry.new);

    // A failed probe re-opens the circuit immediately and restarts the cool-down.
    if (entry.state == CircuitState.halfOpen) {
      entry.consecutiveFailures += 1;
      _transition(key, entry, CircuitState.open, failureClass: failureClass);
      return;
    }

    entry.consecutiveFailures += 1;
    if (entry.consecutiveFailures >= threshold) {
      _transition(key, entry, CircuitState.open, failureClass: failureClass);
    } else if (entry.state == CircuitState.healthy) {
      _transition(
        key,
        entry,
        CircuitState.degraded,
        failureClass: failureClass,
      );
    }
  }

  /// Consecutive eligible failures currently recorded for [key].
  int consecutiveFailures(String key) =>
      _entries[key]?.consecutiveFailures ?? 0;

  /// Clears all circuit state. Used when a deployment profile is activated.
  void reset() => _entries.clear();

  void _transition(
    String key,
    _CircuitEntry entry,
    CircuitState next, {
    AiFailureClass? failureClass,
  }) {
    final CircuitState previous = entry.state;
    if (previous == next) {
      return;
    }

    final DateTime now = _clock();
    entry.state = next;
    entry.openedAt = next == CircuitState.open ? now : null;
    if (next == CircuitState.healthy) {
      entry.consecutiveFailures = 0;
    }

    onTransition?.call(
      CircuitTransition(
        key: key,
        from: previous,
        to: next,
        at: now,
        consecutiveFailures: entry.consecutiveFailures,
        failureClass: failureClass,
      ),
    );
  }
}

final class _CircuitEntry {
  CircuitState state = CircuitState.healthy;
  int consecutiveFailures = 0;
  DateTime? openedAt;
}
