/// Session repository contract and its implementation.
///
/// Repositories expose domain-oriented methods, not transport details. Nothing
/// above this layer knows whether a value came from the encrypted local
/// projection, from replicated cloud state, or from the authorization RPC.
library;

import 'dart:convert';

import 'package:nodex_hms/core/authorization/authorization_snapshot.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/security/database_key_manager.dart';
import 'package:nodex_hms/core/security/secure_key_store.dart';
import 'package:nodex_hms/data/remote/supabase_gateway.dart';
import 'package:nodex_hms/domain/session/session_state.dart';

/// Domain contract for session and authorization operations.
abstract interface class SessionRepository {
  /// Signs in and returns the authenticated principal identifier.
  Future<String> signIn({required String email, required String password});

  /// Signs out, clearing the cached snapshot.
  Future<void> signOut();

  /// Requests a password recovery email.
  Future<void> requestPasswordReset(String email);

  /// Whether an authenticated session exists.
  bool hasSession();

  /// Obtains a fresh authorization snapshot from the server.
  Future<AuthorizationSnapshot> refreshAuthorization({
    required String tenantId,
    required SessionDevice device,
  });

  /// Reads the cached snapshot, or null when none is stored.
  ///
  /// Returns null rather than throwing when the cached payload fails digest
  /// verification, after discarding it: a tampered snapshot must not become an
  /// authorization decision.
  Future<AuthorizationSnapshot?> cachedAuthorization();

  /// Discards the cached snapshot.
  Future<void> clearCachedAuthorization();
}

/// Default [SessionRepository] over Supabase and Keystore-backed storage.
final class DefaultSessionRepository implements SessionRepository {
  /// Creates a repository.
  DefaultSessionRepository({
    required this._gateway,
    required this._keyStore,
    required this._logger,
  });

  static const String _module = 'domain.session';

  /// Storage slot holding the cached authorization snapshot.
  static const String _snapshotSlot = 'nodex.authorization.snapshot.v1';

  final SupabaseGateway _gateway;
  final SecureKeyStore _keyStore;
  final NodexLogger _logger;

  @override
  Future<String> signIn({
    required String email,
    required String password,
  }) async {
    final SupabaseSessionSnapshot session = await _gateway.signInWithPassword(
      email: email,
      password: password,
    );
    _logger.info(
      _module,
      'Principal authenticated.',
      operation: 'session.sign_in',
      outcome: 'succeeded',
    );
    return session.userId;
  }

  @override
  Future<void> signOut() async {
    await clearCachedAuthorization();
    await _gateway.signOut();
    _logger.info(
      _module,
      'Principal signed out.',
      operation: 'session.sign_out',
      outcome: 'succeeded',
    );
  }

  @override
  Future<void> requestPasswordReset(String email) =>
      _gateway.requestPasswordReset(email);

  @override
  bool hasSession() => _gateway.currentSession() != null;

  @override
  Future<AuthorizationSnapshot> refreshAuthorization({
    required String tenantId,
    required SessionDevice device,
  }) async {
    final SupabaseSessionSnapshot? session = _gateway.currentSession();
    if (session == null) {
      throw const AuthorizationError(
        message:
            'An authenticated session is required to refresh authorization.',
        code: 'no_session',
      );
    }

    final Map<String, Object?> row = await _gateway.issueAuthorizationSnapshot(
      tenantId: tenantId,
      deviceFingerprint: device.fingerprint,
      sessionId: session.accessToken.hashCode.toRadixString(16),
      appVersion: device.appVersion,
      osVersion: device.osVersion,
    );

    final AuthorizationSnapshot snapshot;
    try {
      snapshot = AuthorizationSnapshot.fromServer(<String, Object?>{
        ...row,
        'user_id': row['user_id'] ?? session.userId,
      });
    } on FormatException catch (error) {
      throw ValidationError(
        message: 'The server returned a malformed authorization snapshot.',
        code: 'malformed_snapshot',
        cause: error,
      );
    }

    await _cacheSnapshot(snapshot);

    _logger.info(
      _module,
      'Authorization snapshot refreshed.',
      operation: 'session.refresh_authorization',
      outcome: 'succeeded',
      dimensions: <String, Object?>{
        'snapshot_revision': snapshot.revision,
        'role_count': snapshot.roles.length,
        'permission_count': snapshot.permissions.length,
        'offline_permission_count': snapshot.offlinePermissions.length,
        'valid_for_minutes': snapshot
            .remainingValidity(DateTime.now())
            .inMinutes,
      },
    );

    return snapshot;
  }

  @override
  Future<AuthorizationSnapshot?> cachedAuthorization() async {
    final String? raw = await _keyStore.read(_snapshotSlot);
    if (raw == null || raw.isEmpty) {
      return null;
    }

    final AuthorizationSnapshot snapshot;
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('cached snapshot is not an object');
      }
      snapshot = AuthorizationSnapshot.fromJson(decoded);
    } on Object catch (error) {
      await clearCachedAuthorization();
      _logger.critical(
        _module,
        'Discarded an unreadable cached authorization snapshot.',
        operation: 'session.load_cached_authorization',
        outcome: 'quarantined',
        dimensions: <String, Object?>{'error': '$error'},
      );
      return null;
    }

    // Recompute the digest over the canonical payload. A mismatch means the
    // cached snapshot was altered on the device, so it is discarded rather than
    // trusted: an attacker-widened permission set must never take effect.
    final String recomputed = PayloadDigest.forSnapshot(
      userId: snapshot.userId,
      tenantId: snapshot.tenantId,
      deviceId: snapshot.deviceId,
      revision: snapshot.revision,
      roles: snapshot.roles,
      permissions: snapshot.permissions,
      offlinePermissions: snapshot.offlinePermissions,
      facilityIds: snapshot.facilityIds,
      departmentIds: snapshot.departmentIds,
      wardIds: snapshot.wardIds,
      issuedAt: snapshot.issuedAt,
      expiresAt: snapshot.expiresAt,
    );

    if (!PayloadDigest.matches(snapshot.payloadDigest, recomputed)) {
      await clearCachedAuthorization();
      _logger.critical(
        _module,
        'Cached authorization snapshot failed digest verification.',
        operation: 'session.load_cached_authorization',
        outcome: 'quarantined',
        errorCode: 'snapshot_digest_mismatch',
      );
      return null;
    }

    return snapshot;
  }

  @override
  Future<void> clearCachedAuthorization() => _keyStore.delete(_snapshotSlot);

  /// Caches [snapshot] with a locally recomputed digest.
  ///
  /// The server's digest covers the same fields but is computed over its own
  /// timestamp rendering. Storing a locally computed digest keeps verification
  /// self-consistent across serialisation round trips, while still detecting any
  /// edit to the cached payload.
  Future<void> _cacheSnapshot(AuthorizationSnapshot snapshot) async {
    final String digest = PayloadDigest.forSnapshot(
      userId: snapshot.userId,
      tenantId: snapshot.tenantId,
      deviceId: snapshot.deviceId,
      revision: snapshot.revision,
      roles: snapshot.roles,
      permissions: snapshot.permissions,
      offlinePermissions: snapshot.offlinePermissions,
      facilityIds: snapshot.facilityIds,
      departmentIds: snapshot.departmentIds,
      wardIds: snapshot.wardIds,
      issuedAt: snapshot.issuedAt,
      expiresAt: snapshot.expiresAt,
    );

    final Map<String, Object?> payload = <String, Object?>{
      ...snapshot.toJson(),
      'payload_digest': digest,
      'server_payload_digest': snapshot.payloadDigest,
    };

    await _keyStore.write(_snapshotSlot, jsonEncode(payload));
  }
}
