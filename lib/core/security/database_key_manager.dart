/// Local database encryption key management.
///
/// The specification requires the PowerSync SQLite database to be encrypted and
/// its key protected by the Android Keystore, with a defined lifecycle covering
/// generation, secure storage, rotation, logout handling and wipe.
///
/// `flutter_secure_storage` is the Keystore-backed store: on Android it wraps
/// `EncryptedSharedPreferences`, whose master key lives in the hardware-backed
/// Keystore and never enters the Dart heap. This class holds only the derived
/// database passphrase, and only for as long as the database is open.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/security/secure_key_store.dart';

/// Manages the lifecycle of the local database encryption key.
final class DatabaseKeyManager {
  /// Creates a key manager writing key material to the given secure store.
  DatabaseKeyManager({
    required this._keyStore,
    required this._logger,
    Random? random,
  }) : _random = random ?? Random.secure();

  static const String _module = 'security.database_key';

  /// Storage slot holding the raw database passphrase.
  static const String _keySlot = 'nodex.db.encryption_key.v1';

  /// Storage slot holding the key generation counter, used for rotation audit.
  static const String _generationSlot = 'nodex.db.encryption_key.generation';

  /// Length of the generated key material before encoding.
  ///
  /// 32 bytes yields a 256-bit key, matching the AES-256-class protection the
  /// specification calls for.
  static const int keyLengthBytes = 32;

  final SecureKeyStore _keyStore;
  final NodexLogger _logger;
  final Random _random;

  /// Returns the existing database key, generating one on first run.
  ///
  /// The returned value is the passphrase handed to SQLCipher. It is never
  /// logged, never transmitted and never written to unencrypted storage.
  Future<String> obtainKey() async {
    final String? existing = await _keyStore.read(_keySlot);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    return _generateAndStore(generation: 1);
  }

  /// Rotates the database key and returns the new value.
  ///
  /// Rotation invalidates the existing encrypted database: the caller must
  /// re-key or delete and re-replicate the local projection. Because the local
  /// database is a replica and never the authoritative record, deletion followed
  /// by re-replication is the safe default.
  Future<String> rotateKey() async {
    final int nextGeneration = await currentGeneration() + 1;
    final String key = await _generateAndStore(generation: nextGeneration);
    _logger.warning(
      _module,
      'Local database encryption key rotated; local projection must be rebuilt.',
      operation: 'database_key.rotate',
      outcome: 'succeeded',
      dimensions: <String, Object?>{'generation': nextGeneration},
    );
    return key;
  }

  /// The current key generation, or 0 when no key has been generated.
  Future<int> currentGeneration() async {
    final String? raw = await _keyStore.read(_generationSlot);
    if (raw == null) {
      return 0;
    }
    return int.tryParse(raw) ?? 0;
  }

  /// Whether a database key already exists on this device.
  Future<bool> hasKey() async {
    final String? existing = await _keyStore.read(_keySlot);
    return existing != null && existing.isNotEmpty;
  }

  /// Destroys the key material.
  ///
  /// Called on sign-out with local-data clearing, on device de-registration and
  /// on security-policy failure. Once destroyed the encrypted database is
  /// unreadable, which is the intended outcome of a selective wipe.
  Future<void> destroyKey({required String reason}) async {
    await _keyStore.delete(_keySlot);
    _logger.critical(
      _module,
      'Local database encryption key destroyed.',
      operation: 'database_key.destroy',
      outcome: 'succeeded',
      dimensions: <String, Object?>{'reason': reason},
    );
  }

  Future<String> _generateAndStore({required int generation}) async {
    final Uint8List bytes = Uint8List(keyLengthBytes);
    for (int i = 0; i < keyLengthBytes; i++) {
      bytes[i] = _random.nextInt(256);
    }

    // Hex, not base64: SQLCipher passphrases are quoted into a PRAGMA, and hex
    // avoids any escaping ambiguity in that statement.
    final String key = bytes
        .map((int b) => b.toRadixString(16).padLeft(2, '0'))
        .join();

    try {
      await _keyStore.write(_keySlot, key);
      await _keyStore.write(_generationSlot, generation.toString());
    } on Object catch (error, stackTrace) {
      _logger.critical(
        _module,
        'Failed to persist the database encryption key to the platform keystore.',
        operation: 'database_key.generate',
        outcome: 'failed',
        stackTrace: stackTrace,
        dimensions: <String, Object?>{'generation': generation},
      );
      throw IntegrityError(
        message:
            'The device keystore rejected the database encryption key. '
            'Local clinical data cannot be stored securely.',
        subject: 'database_encryption_key',
        code: 'keystore_write_failed',
        cause: error,
      );
    }

    _logger.info(
      _module,
      'Local database encryption key generated.',
      operation: 'database_key.generate',
      outcome: 'succeeded',
      dimensions: <String, Object?>{'generation': generation},
    );
    return key;
  }
}

/// Computes and verifies digests over locally cached authorization material.
///
/// The server issues a digest with every authorization snapshot. Recomputing it
/// on load detects local tampering with the cached snapshot, which the
/// authorization policy treats as an integrity fault rather than as a
/// permission set to be trusted.
abstract final class PayloadDigest {
  /// Computes the digest over the canonical snapshot payload.
  ///
  /// The field order mirrors the server-side `concat_ws` in
  /// `public.issue_authorization_snapshot`, so a snapshot mutated on the device
  /// no longer matches the digest the server issued.
  static String forSnapshot({
    required String userId,
    required String tenantId,
    required String deviceId,
    required int revision,
    required Iterable<String> roles,
    required Iterable<String> permissions,
    required Iterable<String> offlinePermissions,
    required Iterable<String> facilityIds,
    required Iterable<String> departmentIds,
    required Iterable<String> wardIds,
    required DateTime issuedAt,
    required DateTime expiresAt,
  }) {
    final String canonical = <String>[
      userId,
      tenantId,
      deviceId,
      revision.toString(),
      roles.join(','),
      permissions.join(','),
      offlinePermissions.join(','),
      facilityIds.join(','),
      departmentIds.join(','),
      wardIds.join(','),
      issuedAt.toUtc().toIso8601String(),
      expiresAt.toUtc().toIso8601String(),
    ].join('|');

    return sha256.convert(utf8.encode(canonical)).toString();
  }

  /// Constant-time comparison of two hex digests.
  ///
  /// Avoids leaking digest content through timing, which matters because the
  /// comparison runs against attacker-writable local storage.
  static bool matches(String expected, String actual) {
    if (expected.length != actual.length) {
      return false;
    }
    int difference = 0;
    for (int i = 0; i < expected.length; i++) {
      difference |= expected.codeUnitAt(i) ^ actual.codeUnitAt(i);
    }
    return difference == 0;
  }
}
