/// Keystore-backed secret storage abstraction.
///
/// The database encryption key, session material and device-bound cryptographic
/// values are protected by the Android Keystore. This interface keeps that
/// dependency behind a seam so that key lifecycle logic is unit-testable without
/// a device, and so a future platform change does not reach into
/// security-critical code.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A namespaced store for small secrets held under platform key protection.
abstract interface class SecureKeyStore {
  /// Reads the value at [slot], or null when absent.
  Future<String?> read(String slot);

  /// Writes [value] to [slot], replacing any existing value.
  Future<void> write(String slot, String value);

  /// Removes the value at [slot]. Absent slots are not an error.
  Future<void> delete(String slot);

  /// Removes every value owned by this store.
  ///
  /// Used by device de-registration and wipe handling.
  Future<void> deleteAll();
}

/// [SecureKeyStore] backed by `flutter_secure_storage`.
///
/// On Android this resolves to `EncryptedSharedPreferences`, whose master key is
/// held in the hardware-backed Keystore. `resetOnError` is enabled: a keystore
/// that can no longer decrypt its own store (after a system restore or a
/// keystore reset) must fail closed by discarding the unreadable material rather
/// than leaving the app unable to start.
final class PlatformSecureKeyStore implements SecureKeyStore {
  /// Creates a store using the platform secure storage implementation.
  PlatformSecureKeyStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(resetOnError: true),
          );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String slot) => _storage.read(key: slot);

  @override
  Future<void> write(String slot, String value) =>
      _storage.write(key: slot, value: value);

  @override
  Future<void> delete(String slot) => _storage.delete(key: slot);

  @override
  Future<void> deleteAll() => _storage.deleteAll();
}

/// In-memory [SecureKeyStore] for tests.
///
/// Never used in a shipped build: it provides no protection at rest.
final class InMemorySecureKeyStore implements SecureKeyStore {
  final Map<String, String> _values = <String, String>{};

  /// Slots currently held, for test assertions.
  Iterable<String> get slots => _values.keys;

  @override
  Future<String?> read(String slot) async => _values[slot];

  @override
  Future<void> write(String slot, String value) async {
    _values[slot] = value;
  }

  @override
  Future<void> delete(String slot) async {
    _values.remove(slot);
  }

  @override
  Future<void> deleteAll() async {
    _values.clear();
  }
}
