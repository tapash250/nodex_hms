/// The PIN store (Module 52).
///
/// The PIN lives in the platform keystore, never in the local database and
/// never in a log line. The store holds the salted digest; the plain code is
/// only ever in the clinician's hands.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:nodex_hms/core/security/pin_service.dart';

/// Reads and writes the PIN digest.
class PinStore {
  /// Creates a store over the platform keystore.
  const PinStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const String _key = 'nodex.session.pin_digest';

  final FlutterSecureStorage _storage;

  /// The stored digest, or null when no PIN has been set.
  Future<PinDigest?> read() async {
    final String? stored = await _storage.read(key: _key);
    return PinDigest.parse(stored);
  }

  /// Sets the PIN.
  ///
  /// The code is hashed here and the plain text is dropped: it is not stored,
  /// not logged and not returned.
  Future<void> set(String pin) async {
    if (!PinHasher.isAcceptable(pin)) {
      throw ArgumentError.value(
        pin.length,
        'pin',
        'A PIN must be 4 to 8 digits and not a single repeated digit.',
      );
    }
    final PinDigest digest = PinHasher.hash(pin);
    await _storage.write(key: _key, value: digest.encode());
  }

  /// Removes the PIN.
  Future<void> clear() async {
    await _storage.delete(key: _key);
  }

  /// Whether [pin] matches the stored one.
  ///
  /// A device with no PIN set has nothing to check against, so a missing PIN
  /// is a failed check rather than a passed one: the quick switch stays
  /// closed until somebody sets a PIN.
  Future<bool> verify(String pin) async {
    final PinDigest? digest = await read();
    if (digest == null) return false;
    return PinHasher.verify(pin, digest);
  }

  /// Whether a PIN has been set.
  Future<bool> get hasPin async => (await read()) != null;
}
