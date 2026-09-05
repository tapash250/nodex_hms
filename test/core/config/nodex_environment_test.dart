/// Tests for build-time environment validation.
///
/// Two of these rules are security controls rather than conveniences: a client
/// build must never carry a privileged Supabase key, and a production build must
/// never use cleartext transport. Both fail the build at startup instead of
/// shipping a misconfigured clinical application.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/config/nodex_environment.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';

/// Builds a JWT-shaped key whose payload claims [role].
String jwtWithRole(String role) {
  String segment(Map<String, Object?> json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');

  final String header = segment(<String, Object?>{
    'alg': 'HS256',
    'typ': 'JWT',
  });
  final String payload = segment(<String, Object?>{
    'iss': 'supabase',
    'role': role,
  });
  return '$header.$payload.signature';
}

void main() {
  const String validUrl = 'https://project.supabase.co';
  final String anonKey = jwtWithRole('anon');

  NodexEnvironment build({
    String environmentName = 'development',
    String supabaseUrl = validUrl,
    String? supabaseKey,
    String powerSyncUrl = '',
    String profileRevision = 'profile-2026.09.01',
    int offlineWindowMinutes = 720,
    int sessionIdleMinutes = 15,
  }) => NodexEnvironment.validated(
    environmentName: environmentName,
    supabaseUrl: supabaseUrl,
    supabasePublishableKey: supabaseKey ?? anonKey,
    powerSyncUrl: powerSyncUrl,
    aiDeploymentProfileRevision: profileRevision,
    offlineWindowMinutes: offlineWindowMinutes,
    sessionIdleMinutes: sessionIdleMinutes,
  );

  group('required configuration', () {
    test('accepts a complete development configuration', () {
      final NodexEnvironment environment = build();

      expect(environment.environment, DeploymentEnvironment.development);
      expect(environment.supabaseUrl, validUrl);
      expect(environment.isSyncConfigured, isFalse);
      expect(environment.offlineWindow, const Duration(minutes: 720));
      expect(environment.sessionIdleTimeout, const Duration(minutes: 15));
    });

    test('rejects a missing Supabase URL', () {
      expect(
        () => build(supabaseUrl: ''),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError e) => e.code,
            'code',
            'missing_dart_define',
          ),
        ),
      );
    });

    test('rejects a missing publishable key', () {
      expect(() => build(supabaseKey: ''), throwsA(isA<ValidationError>()));
    });

    test('rejects a malformed URL', () {
      expect(
        () => build(supabaseUrl: 'not a url'),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError e) => e.code,
            'code',
            'malformed_url',
          ),
        ),
      );
    });
  });

  group('privileged key rejection', () {
    test('rejects a service_role JWT in a client build', () {
      // A service-role key bypasses row level security entirely.
      expect(
        () => build(supabaseKey: jwtWithRole('service_role')),
        throwsA(
          isA<IntegrityError>()
              .having(
                (IntegrityError e) => e.code,
                'code',
                'privileged_key_in_client_build',
              )
              .having(
                (IntegrityError e) => e.subject,
                'subject',
                'supabase_key',
              ),
        ),
      );
    });

    test('rejects a modern secret key in a client build', () {
      expect(
        () => build(supabaseKey: 'sb_secret_abc123'),
        throwsA(
          isA<IntegrityError>().having(
            (IntegrityError e) => e.code,
            'code',
            'privileged_key_in_client_build',
          ),
        ),
      );
    });

    test('accepts a legacy anon JWT', () {
      expect(() => build(supabaseKey: jwtWithRole('anon')), returnsNormally);
    });

    test('accepts a modern publishable key', () {
      expect(
        () => build(supabaseKey: 'sb_publishable_abc123'),
        returnsNormally,
      );
    });

    test('treats an undecodable key as opaque rather than failing the build', () {
      // The server rejects an invalid key; the client cannot second-guess every
      // future key format.
      expect(() => build(supabaseKey: 'not.a.jwt'), returnsNormally);
    });
  });

  group('transport security', () {
    test('permits http in development for a local emulator', () {
      expect(
        () => build(supabaseUrl: 'http://10.0.2.2:54321'),
        returnsNormally,
      );
    });

    test('refuses http in a production build', () {
      expect(
        () => build(
          environmentName: 'production',
          supabaseUrl: 'http://project.supabase.co',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError e) => e.code,
            'code',
            'insecure_transport',
          ),
        ),
      );
    });

    test('validates the PowerSync URL when supplied', () {
      expect(
        () => build(
          environmentName: 'production',
          powerSyncUrl: 'http://instance.powersync.journeyapps.com',
        ),
        throwsA(isA<ValidationError>()),
      );
    });

    test('accepts an https PowerSync URL and reports sync configured', () {
      final NodexEnvironment environment = build(
        powerSyncUrl: 'https://instance.powersync.journeyapps.com',
      );

      expect(environment.isSyncConfigured, isTrue);
      expect(
        environment.powerSyncUrl,
        'https://instance.powersync.journeyapps.com',
      );
    });
  });

  group('production requirements', () {
    test('requires a versioned AI deployment profile revision', () {
      // Routing must be reproducible from a stored profile revision.
      expect(
        () => build(environmentName: 'production', profileRevision: 'unset'),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError e) => e.code,
            'code',
            'missing_ai_profile_revision',
          ),
        ),
      );
    });

    test('accepts production with a declared profile revision', () {
      final NodexEnvironment environment = build(
        environmentName: 'production',
        profileRevision: '20260901.01',
      );

      expect(environment.environment.isProduction, isTrue);
      expect(environment.aiDeploymentProfileRevision, '20260901.01');
    });

    test('development does not require a profile revision', () {
      expect(() => build(profileRevision: 'unset'), returnsNormally);
    });
  });

  group('DeploymentEnvironment', () {
    test('parses known names', () {
      expect(
        DeploymentEnvironment.fromName('production'),
        DeploymentEnvironment.production,
      );
      expect(
        DeploymentEnvironment.fromName('staging'),
        DeploymentEnvironment.staging,
      );
      expect(
        DeploymentEnvironment.fromName('development'),
        DeploymentEnvironment.development,
      );
    });

    test('falls back to development for an unknown name', () {
      // Defaulting to the least privileged environment avoids accidentally
      // treating an unrecognised value as production.
      expect(
        DeploymentEnvironment.fromName('prd'),
        DeploymentEnvironment.development,
      );
    });

    test('only production reports isProduction', () {
      for (final DeploymentEnvironment env in DeploymentEnvironment.values) {
        expect(env.isProduction, env == DeploymentEnvironment.production);
      }
    });
  });

  group('window configuration', () {
    test('honours a custom offline window', () {
      final NodexEnvironment environment = build(offlineWindowMinutes: 180);
      expect(environment.offlineWindow, const Duration(minutes: 180));
    });

    test('honours a custom idle timeout', () {
      final NodexEnvironment environment = build(sessionIdleMinutes: 5);
      expect(environment.sessionIdleTimeout, const Duration(minutes: 5));
    });
  });
}
