/// The PIN that lets a clinician hand the device over (Module 52).
///
/// A PIN is not a password and it is not a second factor: it is a short code
/// that lets one of two people on the same device switch to their own
/// account without signing out and signing in again. It is therefore stored
/// as a salted hash and never in the clear, and the code that checks it is
/// deliberately slow enough to be a nuisance for someone guessing.
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// The stored form of a PIN.
final class PinDigest {
  /// Creates a digest.
  const PinDigest({
    required this.salt,
    required this.hash,
    required this.rounds,
  });

  /// The random salt, base64 encoded.
  final String salt;

  /// The hash of the PIN under the salt, base64 encoded.
  final String hash;

  /// How many times the hash was repeated.
  final int rounds;

  /// Reads a digest from its stored form.
  static PinDigest? parse(String? stored) {
    if (stored == null) return null;
    final List<String> parts = stored.split('\$');
    if (parts.length != 3) return null;
    return PinDigest(
      salt: parts[0],
      hash: parts[1],
      rounds: int.tryParse(parts[2]) ?? 1,
    );
  }

  /// The stored form of the digest.
  String encode() => '$salt\$$hash\$$rounds';
}

/// Hashes and checks PINs.
abstract final class PinHasher {
  /// How many rounds a new PIN is hashed with.
  ///
  /// A PIN is four to six digits, so the space is small. The rounds are not
  /// there to make guessing impossible — they are there to make guessing
  /// expensive enough to notice.
  static const int defaultRounds = 120000;

  /// How long a PIN must be.
  static const int minimumLength = 4;

  /// How long a PIN may be.
  static const int maximumLength = 8;

  /// Whether [pin] is an acceptable PIN.
  ///
  /// A PIN that is one repeated digit is not acceptable: it is the first
  /// thing anybody tries.
  static bool isAcceptable(String pin) {
    if (pin.length < minimumLength || pin.length > maximumLength) {
      return false;
    }
    if (!RegExp(r'^\d+$').hasMatch(pin)) return false;
    if (RegExp(r'^(\d)\1+$').hasMatch(pin)) return false;
    return true;
  }

  /// Builds the digest of [pin] with a fresh salt.
  static PinDigest hash(String pin, {Random? random}) {
    final Random source = random ?? Random.secure();
    final List<int> saltBytes = List<int>.generate(
      16,
      (_) => source.nextInt(256),
    );
    final String salt = base64Encode(saltBytes);
    return hashWithSalt(pin, salt, rounds: defaultRounds);
  }

  /// Builds the digest of [pin] under an existing salt.
  static PinDigest hashWithSalt(
    String pin,
    String salt, {
    int rounds = defaultRounds,
  }) {
    final String hash = _derive(pin, salt, rounds);
    return PinDigest(salt: salt, hash: hash, rounds: rounds);
  }

  /// Whether [pin] matches [digest].
  static bool verify(String pin, PinDigest digest) {
    final String computed = _derive(pin, digest.salt, digest.rounds);
    return _constantTimeEquals(computed, digest.hash);
  }

  static String _derive(String pin, String salt, int rounds) {
    final List<int> bytes = utf8.encode('$salt:$pin');
    late List<int> digest = sha256.convert(bytes).bytes;
    for (int i = 1; i < rounds; i++) {
      digest = sha256.convert(<int>[...digest, ...bytes]).bytes;
    }
    return base64Encode(digest);
  }

  /// Compares two strings without giving away where they differ.
  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    int difference = 0;
    for (int i = 0; i < a.length; i++) {
      difference |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return difference == 0;
  }
}
