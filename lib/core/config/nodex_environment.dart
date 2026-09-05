/// Build-time environment configuration.
///
/// Provider credentials, endpoints and deployment identifiers are supplied at
/// build time via `--dart-define`, never committed to source control and never
/// embedded as literals in the repository.
///
/// Two rules from the specification are enforced structurally here:
///
/// 1. No service-role key in client builds. [NodexEnvironment.resolve] rejects a
///    Supabase key that carries the `service_role` claim, so a misconfigured CI
///    pipeline fails at startup instead of shipping a privileged key.
/// 2. AI provider credentials never appear in the client. There is no field for
///    them: the AI Gateway reaches providers through a server-side edge function,
///    so the device holds no provider secret.
library;

import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';

/// Deployment environment, matching `ai_deployment_profiles.environment`.
enum DeploymentEnvironment {
  /// Local development against a development Supabase project.
  development,

  /// Pre-production verification.
  staging,

  /// Production clinical deployment.
  production;

  /// Parses a wire value, defaulting to [development] for unrecognised input.
  static DeploymentEnvironment fromName(String value) {
    for (final DeploymentEnvironment env in DeploymentEnvironment.values) {
      if (env.name == value) {
        return env;
      }
    }
    return DeploymentEnvironment.development;
  }

  /// Whether this environment holds real patient data.
  bool get isProduction => this == DeploymentEnvironment.production;
}

/// Resolved configuration for one build.
@immutable
final class NodexEnvironment {
  /// Creates a configuration. Prefer [NodexEnvironment.resolve].
  const NodexEnvironment({
    required this.environment,
    required this.supabaseUrl,
    required this.supabasePublishableKey,
    required this.powerSyncUrl,
    required this.aiDeploymentProfileRevision,
    required this.offlineWindow,
    required this.sessionIdleTimeout,
  });

  /// Reads configuration from `--dart-define` values.
  ///
  /// Throws [ValidationError] when a required value is absent or malformed, and
  /// [IntegrityError] when a privileged key is detected in a client build.
  factory NodexEnvironment.resolve() {
    const String environmentName = String.fromEnvironment(
      'NODEX_ENVIRONMENT',
      defaultValue: 'development',
    );
    const String supabaseUrl = String.fromEnvironment('NODEX_SUPABASE_URL');
    const String supabaseKey = String.fromEnvironment(
      'NODEX_SUPABASE_PUBLISHABLE_KEY',
    );
    const String powerSyncUrl = String.fromEnvironment('NODEX_POWERSYNC_URL');
    const String profileRevision = String.fromEnvironment(
      'NODEX_AI_PROFILE_REVISION',
      defaultValue: 'unset',
    );
    const int offlineWindowMinutes = int.fromEnvironment(
      'NODEX_OFFLINE_WINDOW_MINUTES',
      defaultValue: 720,
    );
    const int sessionIdleMinutes = int.fromEnvironment(
      'NODEX_SESSION_IDLE_MINUTES',
      defaultValue: 15,
    );

    return NodexEnvironment.validated(
      environmentName: environmentName,
      supabaseUrl: supabaseUrl,
      supabasePublishableKey: supabaseKey,
      powerSyncUrl: powerSyncUrl,
      aiDeploymentProfileRevision: profileRevision,
      offlineWindowMinutes: offlineWindowMinutes,
      sessionIdleMinutes: sessionIdleMinutes,
    );
  }

  /// Validates explicit configuration values and builds an environment.
  ///
  /// Separated from [NodexEnvironment.resolve] so the validation rules — which
  /// are security controls, not conveniences — are unit-testable without
  /// rebuilding with different `--dart-define` values.
  factory NodexEnvironment.validated({
    required String environmentName,
    required String supabaseUrl,
    required String supabasePublishableKey,
    required String powerSyncUrl,
    required String aiDeploymentProfileRevision,
    int offlineWindowMinutes = 720,
    int sessionIdleMinutes = 15,
  }) {
    final DeploymentEnvironment resolved = DeploymentEnvironment.fromName(
      environmentName,
    );

    _requireNonEmpty(supabaseUrl, 'NODEX_SUPABASE_URL');
    _requireNonEmpty(supabasePublishableKey, 'NODEX_SUPABASE_PUBLISHABLE_KEY');
    _requireHttps(supabaseUrl, 'NODEX_SUPABASE_URL', resolved);
    _rejectPrivilegedKey(supabasePublishableKey);

    if (powerSyncUrl.isNotEmpty) {
      _requireHttps(powerSyncUrl, 'NODEX_POWERSYNC_URL', resolved);
    }

    if (resolved.isProduction && aiDeploymentProfileRevision == 'unset') {
      throw const ValidationError(
        message:
            'A production build must declare NODEX_AI_PROFILE_REVISION so that '
            'AI routing decisions are reproducible from a versioned profile.',
        code: 'missing_ai_profile_revision',
      );
    }

    return NodexEnvironment(
      environment: resolved,
      supabaseUrl: supabaseUrl,
      supabasePublishableKey: supabasePublishableKey,
      powerSyncUrl: powerSyncUrl,
      aiDeploymentProfileRevision: aiDeploymentProfileRevision,
      offlineWindow: Duration(minutes: offlineWindowMinutes),
      sessionIdleTimeout: Duration(minutes: sessionIdleMinutes),
    );
  }

  /// The environment this build targets.
  final DeploymentEnvironment environment;

  /// Supabase project URL.
  final String supabaseUrl;

  /// Supabase publishable (anon) key. Never a service-role key.
  final String supabasePublishableKey;

  /// PowerSync instance URL. Empty disables replication, leaving the app
  /// local-only, which is the state of a build made before an instance exists.
  final String powerSyncUrl;

  /// Active AI deployment profile revision, recorded in the AI audit trail.
  final String aiDeploymentProfileRevision;

  /// Maximum offline authorization window requested at snapshot issuance.
  ///
  /// The server clamps this to the device's own configured window; the client
  /// cannot extend its offline validity.
  final Duration offlineWindow;

  /// Idle period after which the session requires biometric or credential unlock.
  final Duration sessionIdleTimeout;

  /// Whether replication is configured for this build.
  bool get isSyncConfigured => powerSyncUrl.isNotEmpty;

  static void _requireNonEmpty(String value, String name) {
    if (value.isEmpty) {
      throw ValidationError(
        message:
            'Required build configuration "$name" was not supplied. Pass it '
            'with --dart-define at build time.',
        code: 'missing_dart_define',
        context: <String, Object?>{'define': name},
      );
    }
  }

  static void _requireHttps(
    String value,
    String name,
    DeploymentEnvironment environment,
  ) {
    final Uri? uri = Uri.tryParse(value);
    if (uri == null || !uri.hasAuthority) {
      throw ValidationError(
        message: 'Build configuration "$name" is not a valid URL.',
        code: 'malformed_url',
        context: <String, Object?>{'define': name},
      );
    }
    // Cleartext transport is refused outright in production. Development builds
    // may target a local emulator over http.
    if (uri.scheme != 'https' && environment.isProduction) {
      throw ValidationError(
        message:
            'Build configuration "$name" must use https in a production build.',
        code: 'insecure_transport',
        context: <String, Object?>{'define': name, 'scheme': uri.scheme},
      );
    }
  }

  /// Rejects a Supabase key whose JWT payload claims a privileged role.
  ///
  /// A service-role key bypasses row level security entirely. Shipping one in an
  /// Android build would defeat the Tier 3 boundary, so this check fails the
  /// build at startup rather than allowing a silent privilege escalation.
  static void _rejectPrivilegedKey(String key) {
    // Modern publishable keys (sb_publishable_...) are not JWTs and carry no
    // role claim; only legacy JWT-format keys need inspecting.
    final List<String> segments = key.split('.');
    if (segments.length != 3) {
      if (key.startsWith('sb_secret_')) {
        throw const IntegrityError(
          message:
              'A Supabase secret key was supplied to a client build. Client '
              'builds must use a publishable key; secret keys bypass row level '
              'security.',
          subject: 'supabase_key',
          code: 'privileged_key_in_client_build',
        );
      }
      return;
    }

    try {
      final String payload = utf8.decode(
        base64Url.decode(base64Url.normalize(segments[1])),
      );
      final Object? decoded = jsonDecode(payload);
      if (decoded is Map<String, Object?> &&
          decoded['role'] == 'service_role') {
        throw const IntegrityError(
          message:
              'A Supabase service-role key was supplied to a client build. '
              'Service-role keys bypass row level security and must never be '
              'embedded in an Android build.',
          subject: 'supabase_key',
          code: 'privileged_key_in_client_build',
        );
      }
    } on FormatException {
      // A key that is not decodable as a JWT is treated as opaque; the server
      // rejects it if invalid.
      return;
    }
  }
}
