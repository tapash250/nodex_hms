/// Second-factor step-up assertions (Module 39).
///
/// The master settings hub is the one part of NODEX that changes what every
/// other module means: the currency a bill is written in, the timezone a shift
/// starts in, the tariff an invoice is priced from, the model that reads a note.
/// The specification asks for Multi-Factor Authentication on those changes, and
/// this file is how the domain states that demand: a mutating use case takes a
/// [SecondFactorAssertion] and refuses to run without a fresh one.
///
/// The assertion is evidence, not a permission. Permissions say who may act;
/// the assertion says that the person at the keyboard proved a second factor a
/// moment ago, and it expires. Keeping it a separate object rather than a flag
/// on the session is what makes "fresh" testable: an assertion produced for one
/// purpose by one user in one tenant is refused for another.
///
/// The verifier is a port because the factor belongs to the identity provider,
/// not to this app. A code this app generated and this app checked would be a
/// code an attacker on this device could generate too. [StubSecondFactorVerifier]
/// is a placeholder for the development build only and is documented as a gap.
library;

import 'package:meta/meta.dart';

/// The kind of second factor that was presented.
enum SecondFactorMethod {
  /// A device-bound passkey or platform authenticator.
  passkey('passkey'),

  /// A time-based one-time code from an authenticator app.
  totp('totp'),

  /// A one-time code sent to a registered phone.
  sms('sms');

  const SecondFactorMethod(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    SecondFactorMethod.passkey => 'Passkey',
    SecondFactorMethod.totp => 'Authenticator app',
    SecondFactorMethod.sms => 'Texted code',
  };

  /// Parses a stored value.
  static SecondFactorMethod fromWire(String value) =>
      SecondFactorMethod.values.firstWhere(
        (SecondFactorMethod value_) => value_.wireValue == value,
        orElse: () => SecondFactorMethod.totp,
      );
}

/// A second factor that was verified at a moment, for one purpose, by one user.
@immutable
final class SecondFactorAssertion {
  /// Creates an assertion.
  const SecondFactorAssertion({
    required this.assertionId,
    required this.tenantId,
    required this.userId,
    required this.purpose,
    required this.verifiedAt,
    this.method = SecondFactorMethod.totp,
    this.validFor = const Duration(minutes: 5),
  });

  /// Identifier of the challenge that produced this assertion.
  final String assertionId;

  /// Tenant the person was acting in.
  final String tenantId;

  /// The person who proved the factor.
  final String userId;

  /// What the factor was proved for, so an assertion cannot be replayed at
  /// another door.
  final String purpose;

  /// The moment the factor was verified, UTC.
  final DateTime verifiedAt;

  /// How the factor was presented.
  final SecondFactorMethod method;

  /// How long the assertion stays usable.
  final Duration validFor;

  /// The moment the assertion stops being usable, UTC.
  DateTime get expiresAt => verifiedAt.toUtc().add(validFor);

  /// Whether the assertion is still usable at [now].
  ///
  /// An assertion from the future is refused as well as an expired one: a device
  /// whose clock jumped forward would otherwise hold a step-up indefinitely.
  bool isFreshAt(DateTime now) {
    final DateTime moment = now.toUtc();
    final DateTime verified = verifiedAt.toUtc();
    if (moment.isBefore(verified)) {
      return false;
    }
    return !moment.isAfter(verified.add(validFor));
  }

  /// Whether the assertion was produced for [userId] in [tenantId].
  bool belongsTo({required String tenantId, required String userId}) =>
      this.tenantId == tenantId && this.userId == userId;
}

/// Verifies a second factor presented by the person at the keyboard.
///
/// Implementations live at the edge: the domain never sees a code, only the
/// assertion that came back.
abstract interface class SecondFactorVerifier {
  /// Challenges [code] and returns the assertion, or null when it is refused.
  Future<SecondFactorAssertion?> verify({
    required String tenantId,
    required String userId,
    required String purpose,
    required String code,
    SecondFactorMethod method = SecondFactorMethod.totp,
    DateTime? at,
  });
}

/// A placeholder verifier for the development build.
///
/// It accepts a six-digit code and refuses the obviously fake ones. It is not a
/// TOTP implementation on purpose: a code this app generates is a code an
/// attacker on this device can generate, so the real factor has to come from the
/// identity provider. Until Supabase Auth MFA is wired, this class is what the
/// development build uses, and the release build should be given a verifier that
/// asks the provider instead of replacing this one.
final class StubSecondFactorVerifier implements SecondFactorVerifier {
  /// Creates the stub.
  const StubSecondFactorVerifier();

  static final RegExp _codePattern = RegExp(r'^\d{6}$');

  @override
  Future<SecondFactorAssertion?> verify({
    required String tenantId,
    required String userId,
    required String purpose,
    required String code,
    SecondFactorMethod method = SecondFactorMethod.totp,
    DateTime? at,
  }) async {
    final String trimmed = code.trim();
    if (!_codePattern.hasMatch(trimmed) || trimmed == '000000') {
      return null;
    }
    final DateTime moment = (at ?? DateTime.now()).toUtc();
    return SecondFactorAssertion(
      assertionId: 'stub-$userId-${moment.millisecondsSinceEpoch}',
      tenantId: tenantId,
      userId: userId,
      purpose: purpose,
      verifiedAt: moment,
      method: method,
    );
  }
}
