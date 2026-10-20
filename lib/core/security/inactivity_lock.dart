/// The inactivity lock (Module 52).
///
/// A device left on a trolley is a device that shows one clinician's patient
/// list to whoever walks past. The lock is the answer: after fifteen minutes
/// without a touch, the session locks and needs the clinician's own
/// credentials to come back.
///
/// The rule is deliberately plain — a lock that surprises a clinician in the
/// middle of a ward round is a lock that gets switched off.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// How long the device may be left alone before it locks.
const Duration nodexInactivityTimeout = Duration(minutes: 15);

/// Counts the silence since the last touch.
final class InactivityTracker {
  /// Creates a tracker.
  InactivityTracker({
    this.lastInteraction,
    this.timeout = nodexInactivityTimeout,
  });

  /// When the device was last touched.
  DateTime? lastInteraction;

  /// How long the silence may run before the device locks.
  final Duration timeout;

  /// Records a touch.
  void registerInteraction(DateTime now) {
    lastInteraction = now;
  }

  /// How long the device has been quiet.
  Duration quietFor(DateTime now) {
    final DateTime? last = lastInteraction;
    if (last == null) return Duration.zero;
    final Duration quiet = now.difference(last);
    return quiet.isNegative ? Duration.zero : quiet;
  }

  /// Whether the device should lock at [now].
  bool shouldLock(DateTime now) => quietFor(now) >= timeout;

  /// How long is left before the lock, at [now].
  ///
  /// Zero once the lock is due, so a screen can show a countdown without
  /// handling the negative case itself.
  Duration remainingUntilLock(DateTime now) {
    final Duration quiet = quietFor(now);
    final Duration left = timeout - quiet;
    return left.isNegative ? Duration.zero : left;
  }
}

/// Watches for touches and locks the session when the device is left alone.
///
/// The watcher is placed above the session in the tree, so it sees the
/// interactions that the screens themselves do not: a scroll, a keyboard
/// shortcut, a tap on a dialog.
class InactivityGuard extends StatefulWidget {
  /// Creates the guard.
  const InactivityGuard({
    required this.child,
    required this.onTimeout,
    this.tracker,
    this.timeout = nodexInactivityTimeout,
    super.key,
  });

  /// The guarded surface.
  final Widget child;

  /// Called when the device has been left alone long enough.
  final VoidCallback onTimeout;

  /// The tracker to use, when the caller keeps one.
  final InactivityTracker? tracker;

  /// How long the silence may run.
  final Duration timeout;

  @override
  State<InactivityGuard> createState() => _InactivityGuardState();
}

class _InactivityGuardState extends State<InactivityGuard> {
  late final InactivityTracker _tracker =
      widget.tracker ?? InactivityTracker(timeout: widget.timeout);
  bool _locked = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _tracker.registerInteraction(DateTime.now());
    // The device is checked on a timer rather than on every frame: a screen
    // that rebuilds sixty times a second to notice it is idle is a screen
    // that spends its battery being idle.
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      checkTimeout(DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _onPointer(PointerEvent event) {
    _tracker.registerInteraction(DateTime.now());
    if (_locked) {
      setState(() => _locked = false);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      _tracker.registerInteraction(DateTime.now());
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: _onPointer,
    onPointerMove: _onPointer,
    onPointerSignal: _onPointer,
    child: Focus(onKeyEvent: _onKey, child: widget.child),
  );

  /// Whether the guard has fired.
  bool get hasLocked => _locked;

  /// Fires the timeout if the silence is long enough.
  ///
  /// The guard calls this on a timer so the screen is not rebuilt every
  /// frame; the decision itself is the tracker's.
  void checkTimeout(DateTime now) {
    if (_locked || !_tracker.shouldLock(now)) return;
    _locked = true;
    widget.onTimeout();
  }
}
