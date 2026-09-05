/// Tests for local database key lifecycle and snapshot digest verification.
///
/// The specification requires the local database encryption key to be
/// Keystore-protected with a defined lifecycle covering generation, rotation,
/// logout and wipe. These tests exercise that lifecycle against an in-memory
/// store, and verify that the snapshot digest detects local tampering.
library;

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/security/database_key_manager.dart';
import 'package:nodex_hms/core/security/secure_key_store.dart';

/// A key store whose writes always fail, standing in for a keystore that cannot
/// persist material after a system restore or keystore reset.
final class _FailingKeyStore implements SecureKeyStore {
  @override
  Future<String?> read(String slot) async => null;

  @override
  Future<void> write(String slot, String value) async =>
      throw StateError('keystore unavailable');

  @override
  Future<void> delete(String slot) async {}

  @override
  Future<void> deleteAll() async {}
}

void main() {
  late InMemorySecureKeyStore store;
  late InMemoryLogSink sink;
  late NodexLogger logger;
  late DatabaseKeyManager manager;

  setUp(() {
    store = InMemorySecureKeyStore();
    sink = InMemoryLogSink();
    logger = NodexLogger(
      sinks: <NodexLogSink>[sink],
      minimumLevel: NodexLogLevel.trace,
    );
    manager = DatabaseKeyManager(
      keyStore: store,
      logger: logger,
      // Seeded for determinism; production uses Random.secure().
      random: Random(20260901),
    );
  });

  group('DatabaseKeyManager lifecycle', () {
    test('generates a 256-bit key on first use', () async {
      expect(await manager.hasKey(), isFalse);

      final String key = await manager.obtainKey();

      // 32 bytes rendered as hex.
      expect(key.length, DatabaseKeyManager.keyLengthBytes * 2);
      expect(RegExp(r'^[0-9a-f]+$').hasMatch(key), isTrue);
      expect(await manager.hasKey(), isTrue);
      expect(await manager.currentGeneration(), 1);
    });

    test('returns the same key on subsequent calls', () async {
      final String first = await manager.obtainKey();
      final String second = await manager.obtainKey();

      expect(second, first);
      expect(await manager.currentGeneration(), 1);
    });

    test('rotation produces a new key and increments the generation', () async {
      final String original = await manager.obtainKey();
      final String rotated = await manager.rotateKey();

      expect(rotated, isNot(original));
      expect(rotated.length, original.length);
      expect(await manager.currentGeneration(), 2);
      expect(await manager.obtainKey(), rotated);
    });

    test(
      'rotation is recorded as a warning: the projection must be rebuilt',
      () async {
        await manager.obtainKey();
        await manager.rotateKey();

        expect(
          sink.records.any(
            (NodexLogRecord r) =>
                r.level == NodexLogLevel.warning &&
                r.operation == 'database_key.rotate',
          ),
          isTrue,
        );
      },
    );

    test('destroying the key makes the database unreadable', () async {
      await manager.obtainKey();
      await manager.destroyKey(reason: 'device_revoked');

      expect(await manager.hasKey(), isFalse);
      expect(
        sink.records.any(
          (NodexLogRecord r) =>
              r.level == NodexLogLevel.critical &&
              r.operation == 'database_key.destroy',
        ),
        isTrue,
      );
    });

    test('a new key is generated after destruction', () async {
      final String original = await manager.obtainKey();
      await manager.destroyKey(reason: 'wipe');
      final String replacement = await manager.obtainKey();

      expect(replacement, isNot(original));
    });

    test('successive generations differ', () async {
      final Set<String> keys = <String>{};
      keys.add(await manager.obtainKey());
      for (int i = 0; i < 5; i++) {
        keys.add(await manager.rotateKey());
      }
      expect(keys, hasLength(6));
    });

    test(
      'a keystore write failure raises IntegrityError, not a silent pass',
      () async {
        final DatabaseKeyManager failing = DatabaseKeyManager(
          keyStore: _FailingKeyStore(),
          logger: logger,
          random: Random(1),
        );

        await expectLater(
          failing.obtainKey(),
          throwsA(
            isA<IntegrityError>()
                .having(
                  (IntegrityError e) => e.subject,
                  'subject',
                  'database_encryption_key',
                )
                .having(
                  (IntegrityError e) => e.code,
                  'code',
                  'keystore_write_failed',
                ),
          ),
        );

        expect(
          sink.records.any(
            (NodexLogRecord r) => r.level == NodexLogLevel.critical,
          ),
          isTrue,
        );
      },
    );

    test('the key never appears in a diagnostic record', () async {
      final String key = await manager.obtainKey();
      await manager.rotateKey();

      for (final NodexLogRecord record in sink.records) {
        expect(record.message, isNot(contains(key)));
        for (final Object? value in record.dimensions.values) {
          expect(value?.toString(), isNot(contains(key)));
        }
      }
    });
  });

  group('PayloadDigest', () {
    final DateTime issuedAt = DateTime.utc(2026, 9, 1, 8);
    final DateTime expiresAt = DateTime.utc(2026, 9, 1, 20);

    String digestFor({
      Iterable<String> permissions = const <String>['patient.read'],
      Iterable<String> offlinePermissions = const <String>['patient.read'],
      int revision = 1,
    }) => PayloadDigest.forSnapshot(
      userId: 'user-1',
      tenantId: 'tenant-1',
      deviceId: 'device-1',
      revision: revision,
      roles: const <String>['nursing_staff'],
      permissions: permissions,
      offlinePermissions: offlinePermissions,
      facilityIds: const <String>['facility-1'],
      departmentIds: const <String>[],
      wardIds: const <String>['ward-a'],
      issuedAt: issuedAt,
      expiresAt: expiresAt,
    );

    test('is deterministic for identical input', () {
      expect(digestFor(), digestFor());
    });

    test('produces a hex sha-256 digest', () {
      final String digest = digestFor();
      expect(digest.length, 64);
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(digest), isTrue);
    });

    test('changes when a permission is added', () {
      // The tampering case that matters: widening the local permission set.
      expect(
        digestFor(
          permissions: const <String>['patient.read', 'prescription.finalize'],
        ),
        isNot(digestFor()),
      );
    });

    test('changes when a permission is moved into the offline subset', () {
      expect(
        digestFor(
          permissions: const <String>['patient.read', 'billing.settle'],
          offlinePermissions: const <String>['patient.read', 'billing.settle'],
        ),
        isNot(digestFor()),
      );
    });

    test('changes when the revision changes', () {
      expect(digestFor(revision: 2), isNot(digestFor()));
    });

    test('matches performs a constant-time comparison of equal digests', () {
      final String digest = digestFor();
      expect(PayloadDigest.matches(digest, digest), isTrue);
    });

    test('matches rejects a different digest', () {
      expect(
        PayloadDigest.matches(digestFor(), digestFor(revision: 9)),
        isFalse,
      );
    });

    test('matches rejects digests of differing length', () {
      expect(PayloadDigest.matches(digestFor(), 'short'), isFalse);
    });

    test('matches rejects a single-character alteration', () {
      final String digest = digestFor();
      final String altered =
          '${digest.substring(0, 63)}${digest[63] == 'a' ? 'b' : 'a'}';
      expect(PayloadDigest.matches(digest, altered), isFalse);
    });
  });

  group('InMemorySecureKeyStore', () {
    test('reads back what it wrote', () async {
      final InMemorySecureKeyStore store = InMemorySecureKeyStore();
      await store.write('slot', 'value');
      expect(await store.read('slot'), 'value');
    });

    test('returns null for an absent slot', () async {
      expect(await InMemorySecureKeyStore().read('missing'), isNull);
    });

    test('delete removes a single slot', () async {
      final InMemorySecureKeyStore store = InMemorySecureKeyStore();
      await store.write('a', '1');
      await store.write('b', '2');
      await store.delete('a');

      expect(await store.read('a'), isNull);
      expect(await store.read('b'), '2');
    });

    test('deleteAll clears every slot', () async {
      final InMemorySecureKeyStore store = InMemorySecureKeyStore();
      await store.write('a', '1');
      await store.write('b', '2');
      await store.deleteAll();

      expect(store.slots, isEmpty);
    });
  });
}
