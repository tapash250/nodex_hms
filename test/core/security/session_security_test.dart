/// Tests for the enterprise security suite (Module 52).
///
/// Two things are tested here: the PIN that lets a device be handed over, and
/// the inactivity lock that protects a device left on a trolley. Both are
/// about the same rule — a screen that shows a clinician's patients must not
/// be open to the next passer-by.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/security/inactivity_lock.dart';
import 'package:nodex_hms/core/security/pin_service.dart';

void main() {
  group('the PIN', () {
    test('a PIN is hashed with a salt and never stored in the clear', () {
      final PinDigest digest = PinHasher.hash('2468');
      expect(digest.hash, isNot(contains('2468')));
      expect(digest.salt, isNotEmpty);
    });

    test('the same PIN hashed twice gives two digests', () {
      final PinDigest first = PinHasher.hash('2468');
      final PinDigest second = PinHasher.hash('2468');
      expect(first.hash, isNot(second.hash));
      expect(first.salt, isNot(second.salt));
    });

    test('a matching PIN verifies', () {
      final PinDigest digest = PinHasher.hash('2468');
      expect(PinHasher.verify('2468', digest), isTrue);
    });

    test('a different PIN does not verify', () {
      final PinDigest digest = PinHasher.hash('2468');
      expect(PinHasher.verify('1357', digest), isFalse);
    });

    test('a PIN that is one repeated digit is refused', () {
      expect(PinHasher.isAcceptable('1111'), isFalse);
      expect(PinHasher.isAcceptable('0000'), isFalse);
    });

    test('a PIN that is too short or too long is refused', () {
      expect(PinHasher.isAcceptable('123'), isFalse);
      expect(PinHasher.isAcceptable('123456789'), isFalse);
    });

    test('a PIN that is not digits is refused', () {
      expect(PinHasher.isAcceptable('abcd'), isFalse);
    });

    test('an ordinary PIN is accepted', () {
      expect(PinHasher.isAcceptable('2468'), isTrue);
    });

    test('a digest survives being stored and read back', () {
      final PinDigest digest = PinHasher.hash('2468');
      final PinDigest? parsed = PinDigest.parse(digest.encode());
      expect(parsed, isNotNull);
      expect(parsed!.salt, digest.salt);
      expect(parsed.hash, digest.hash);
      expect(PinHasher.verify('2468', parsed), isTrue);
    });

    test('a stored value that is not a digest is refused', () {
      expect(PinDigest.parse('not-a-digest'), isNull);
      expect(PinDigest.parse(null), isNull);
    });
  });

  group('the inactivity lock', () {
    test('a device that was just touched is not locked', () {
      final InactivityTracker tracker = InactivityTracker();
      final DateTime now = DateTime.utc(2026, 9, 12, 9);
      tracker.registerInteraction(now);
      expect(tracker.shouldLock(now.add(const Duration(minutes: 5))), isFalse);
    });

    test('a device left for fifteen minutes is locked', () {
      final InactivityTracker tracker = InactivityTracker();
      final DateTime now = DateTime.utc(2026, 9, 12, 9);
      tracker.registerInteraction(now);
      expect(tracker.shouldLock(now.add(const Duration(minutes: 15))), isTrue);
    });

    test('a device left for longer is still locked', () {
      final InactivityTracker tracker = InactivityTracker();
      final DateTime now = DateTime.utc(2026, 9, 12, 9);
      tracker.registerInteraction(now);
      expect(tracker.shouldLock(now.add(const Duration(hours: 2))), isTrue);
    });

    test('a touch puts the clock back', () {
      final InactivityTracker tracker = InactivityTracker();
      final DateTime now = DateTime.utc(2026, 9, 12, 9);
      tracker.registerInteraction(now);
      tracker.registerInteraction(now.add(const Duration(minutes: 14)));
      expect(tracker.shouldLock(now.add(const Duration(minutes: 16))), isFalse);
    });

    test('the remaining time counts down and never goes negative', () {
      final InactivityTracker tracker = InactivityTracker();
      final DateTime now = DateTime.utc(2026, 9, 12, 9);
      tracker.registerInteraction(now);
      expect(
        tracker.remainingUntilLock(now.add(const Duration(minutes: 5))),
        const Duration(minutes: 10),
      );
      expect(
        tracker.remainingUntilLock(now.add(const Duration(minutes: 30))),
        Duration.zero,
      );
    });

    test('the timeout is fifteen minutes', () {
      expect(nodexInactivityTimeout, const Duration(minutes: 15));
    });

    test('a tracker that was never touched is not locked', () {
      final InactivityTracker tracker = InactivityTracker();
      expect(tracker.shouldLock(DateTime.utc(2026, 9, 12, 9)), isFalse);
    });
  });
}
