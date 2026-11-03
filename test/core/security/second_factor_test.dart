/// Second-factor verifier tests.
///
/// The security-relevant property is the build gate: a release build must never
/// accept the development stub, because the stub accepts any well-formed
/// six-digit code.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/security/second_factor.dart';

void main() {
  group('development stub', () {
    test('accepts a well-formed code', () async {
      const StubSecondFactorVerifier verifier = StubSecondFactorVerifier();
      final SecondFactorAssertion? assertion = await verifier.verify(
        tenantId: 'tenant-1',
        userId: 'user-1',
        purpose: 'master_settings',
        code: '123456',
      );
      expect(assertion, isNotNull);
      expect(
        assertion!.belongsTo(tenantId: 'tenant-1', userId: 'user-1'),
        isTrue,
      );
    });

    test('refuses the obvious placeholder', () async {
      const StubSecondFactorVerifier verifier = StubSecondFactorVerifier();
      expect(
        await verifier.verify(
          tenantId: 'tenant-1',
          userId: 'user-1',
          purpose: 'master_settings',
          code: '000000',
        ),
        isNull,
      );
    });
  });

  group('release build', () {
    test('selects the closed verifier', () {
      expect(
        secondFactorVerifierFor(isReleaseBuild: true),
        isA<UnavailableSecondFactorVerifier>(),
      );
    });

    test('the closed verifier refuses every code', () async {
      const UnavailableSecondFactorVerifier verifier =
          UnavailableSecondFactorVerifier();
      for (final String code in const <String>[
        '123456',
        '654321',
        '111111',
        '000000',
      ]) {
        expect(
          await verifier.verify(
            tenantId: 'tenant-1',
            userId: 'user-1',
            purpose: 'master_settings',
            code: code,
          ),
          isNull,
          reason: 'release builds must fail closed for $code',
        );
      }
    });

    test('development builds keep the stub', () {
      expect(
        secondFactorVerifierFor(isReleaseBuild: false),
        isA<StubSecondFactorVerifier>(),
      );
    });
  });
}
