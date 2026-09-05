/// Supabase transport boundary.
///
/// This is the only file permitted to import the Supabase SDK. Presentation code
/// and domain use cases never touch it: the specification's first engineering
/// prohibition is direct Supabase calls from UI or presentation code, and keeping
/// the SDK confined to one file makes that prohibition mechanically checkable.
///
/// Every failure leaving this class is a normalized [NodexError]. No
/// `PostgrestException`, `AuthException` or `StorageException` escapes.
library;

import 'package:nodex_hms/core/errors/error_mapper.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A non-PHI view of the current authentication session.
final class SupabaseSessionSnapshot {
  /// Creates a session snapshot.
  const SupabaseSessionSnapshot({
    required this.userId,
    required this.accessToken,
    required this.expiresAt,
  });

  /// Authenticated principal identifier.
  final String userId;

  /// Short-lived access token, passed to PowerSync and never persisted.
  final String accessToken;

  /// Token expiry, used to decide when to refresh.
  final DateTime? expiresAt;
}

/// Result of issuing an offline authorization snapshot.
typedef SnapshotIssuanceResult = Map<String, Object?>;

/// Wraps the Supabase client behind a normalized, domain-oriented surface.
final class SupabaseGateway {
  /// Creates a gateway over a configured Supabase client.
  SupabaseGateway({required this._client, required this._logger});

  static const String _module = 'data.supabase';

  final SupabaseClient _client;
  final NodexLogger _logger;

  /// The current session, or null when signed out.
  SupabaseSessionSnapshot? currentSession() {
    final Session? session = _client.auth.currentSession;
    if (session == null) {
      return null;
    }
    final int? expiresAt = session.expiresAt;
    return SupabaseSessionSnapshot(
      userId: session.user.id,
      accessToken: session.accessToken,
      expiresAt: expiresAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000, isUtc: true),
    );
  }

  /// Emits on every authentication state change.
  Stream<AuthChangeEvent> get authEvents =>
      _client.auth.onAuthStateChange.map((AuthState state) => state.event);

  /// Signs in with email and password.
  ///
  /// Throws [AuthorizationError] on rejected credentials and
  /// [ConnectivityError] when the identity provider is unreachable.
  Future<SupabaseSessionSnapshot> signInWithPassword({
    required String email,
    required String password,
  }) async {
    try {
      final AuthResponse response = await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      final Session? session = response.session;
      if (session == null) {
        throw const AuthorizationError(
          message: 'Sign-in did not establish a session.',
          code: 'no_session',
        );
      }
      final int? expiresAt = session.expiresAt;
      return SupabaseSessionSnapshot(
        userId: session.user.id,
        accessToken: session.accessToken,
        expiresAt: expiresAt == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                expiresAt * 1000,
                isUtc: true,
              ),
      );
    } on AuthException catch (error) {
      throw _mapAuthException(error, operation: 'auth.sign_in');
    } on Object catch (error) {
      throw NodexErrorMapper.map(error, operation: 'auth.sign_in');
    }
  }

  /// Signs out and clears the local session.
  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } on AuthException catch (error) {
      throw _mapAuthException(error, operation: 'auth.sign_out');
    } on Object catch (error) {
      throw NodexErrorMapper.map(error, operation: 'auth.sign_out');
    }
  }

  /// Requests a password recovery email.
  Future<void> requestPasswordReset(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(email);
    } on AuthException catch (error) {
      throw _mapAuthException(error, operation: 'auth.reset_password');
    } on Object catch (error) {
      throw NodexErrorMapper.map(error, operation: 'auth.reset_password');
    }
  }

  /// Issues a device-bound offline authorization snapshot.
  ///
  /// Calls `public.issue_authorization_snapshot`, which derives roles,
  /// permissions and scopes server-side. The client supplies only its device
  /// fingerprint and build metadata; it cannot influence what it is granted.
  Future<SnapshotIssuanceResult> issueAuthorizationSnapshot({
    required String tenantId,
    required String deviceFingerprint,
    String? sessionId,
    String? appVersion,
    String? osVersion,
  }) async {
    try {
      final Object? result = await _client.rpc<Object?>(
        'issue_authorization_snapshot',
        params: <String, Object?>{
          'p_tenant_id': tenantId,
          'p_device_fingerprint': deviceFingerprint,
          'p_session_id': sessionId,
          'p_app_version': appVersion,
          'p_os_version': osVersion,
        },
      );

      // The function returns a single-row table, which PostgREST renders as a
      // one-element array.
      final Map<String, Object?> row = switch (result) {
        final List<Object?> rows when rows.isNotEmpty =>
          (rows.first as Map<Object?, Object?>).cast<String, Object?>(),
        final Map<Object?, Object?> single => single.cast<String, Object?>(),
        _ => throw const RemoteError(
          message: 'Authorization snapshot issuance returned no row.',
          code: 'empty_snapshot_result',
        ),
      };
      return row;
    } on PostgrestException catch (error) {
      throw _mapPostgrestException(
        error,
        operation: 'authorization.issue_snapshot',
        resourceType: 'authorization_snapshot',
      );
    } on Object catch (error) {
      throw NodexErrorMapper.map(
        error,
        operation: 'authorization.issue_snapshot',
      );
    }
  }

  /// Reads rows from [table] filtered by [equals].
  Future<List<Map<String, Object?>>> select({
    required String table,
    Map<String, Object?> equals = const <String, Object?>{},
    String? orderBy,
    bool ascending = true,
    int? limit,
  }) async {
    try {
      PostgrestFilterBuilder<List<Map<String, dynamic>>> filter = _client
          .from(table)
          .select();
      for (final MapEntry<String, Object?> entry in equals.entries) {
        filter = filter.eq(entry.key, entry.value as Object);
      }

      final List<Map<String, dynamic>> rows;
      if (orderBy != null && limit != null) {
        rows = await filter.order(orderBy, ascending: ascending).limit(limit);
      } else if (orderBy != null) {
        rows = await filter.order(orderBy, ascending: ascending);
      } else if (limit != null) {
        rows = await filter.limit(limit);
      } else {
        rows = await filter;
      }

      return rows
          .map((Map<String, dynamic> row) => row.cast<String, Object?>())
          .toList(growable: false);
    } on PostgrestException catch (error) {
      throw _mapPostgrestException(
        error,
        operation: 'data.select',
        resourceType: table,
      );
    } on Object catch (error) {
      throw NodexErrorMapper.map(error, operation: 'data.select');
    }
  }

  /// Inserts or replaces a row in [table].
  Future<void> upsert({
    required String table,
    required String id,
    required Map<String, Object?> values,
  }) async {
    try {
      await _client.from(table).upsert(<String, Object?>{'id': id, ...values});
    } on PostgrestException catch (error) {
      throw _mapPostgrestException(
        error,
        operation: 'data.upsert',
        resourceType: table,
      );
    } on Object catch (error) {
      throw NodexErrorMapper.map(error, operation: 'data.upsert');
    }
  }

  /// Applies a partial update to a row in [table].
  Future<void> patch({
    required String table,
    required String id,
    required Map<String, Object?> values,
  }) async {
    if (values.isEmpty) {
      return;
    }
    try {
      await _client.from(table).update(values).eq('id', id);
    } on PostgrestException catch (error) {
      throw _mapPostgrestException(
        error,
        operation: 'data.patch',
        resourceType: table,
      );
    } on Object catch (error) {
      throw NodexErrorMapper.map(error, operation: 'data.patch');
    }
  }

  NodexError _mapAuthException(
    AuthException error, {
    required String operation,
  }) {
    final int? status = int.tryParse(error.statusCode ?? '');
    _logger.warning(
      _module,
      'Authentication request failed.',
      operation: operation,
      outcome: 'rejected',
      errorCode: error.code ?? 'auth_error',
      dimensions: <String, Object?>{'status': status},
    );

    if (status == null || status == 400 || status == 401 || status == 403) {
      return AuthorizationError(
        message: 'The credentials were rejected.',
        code: error.code ?? 'invalid_credentials',
        cause: error,
      );
    }
    if (status == 429) {
      return RemoteError(
        message: 'Too many attempts; try again shortly.',
        statusCode: status,
        isTransient: true,
        code: error.code ?? 'rate_limited',
        cause: error,
      );
    }
    return RemoteError(
      message: 'The identity provider could not process the request.',
      statusCode: status,
      isTransient: status >= 500,
      code: error.code,
      cause: error,
    );
  }

  NodexError _mapPostgrestException(
    PostgrestException error, {
    required String operation,
    required String resourceType,
  }) {
    final NodexError mapped = NodexErrorMapper.mapPostgres(
      sqlState: error.code,
      message: error.message,
      httpStatusCode: int.tryParse(error.code ?? ''),
      operation: operation,
      resourceType: resourceType,
      cause: error,
    );

    // An RLS denial is a security-relevant event: the client attempted something
    // its tier-1 controls should already have prevented.
    if (mapped is AuthorizationError) {
      _logger.warning(
        _module,
        'Server-side authorization denied a request.',
        operation: operation,
        outcome: 'denied',
        errorCode: mapped.code,
        dimensions: <String, Object?>{'resource_type': resourceType},
      );
    }
    return mapped;
  }
}
