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

  /// The authenticated principal identifier, or null when there is no session.
  ///
  /// Used to bind a cached authorization snapshot to the principal who is
  /// actually signed in, so a second clinician on a shared device cannot
  /// inherit the previous user's permissions.
  String? currentUserId();

  /// Whether the session was locked when the application last stopped.
  Future<bool> isLocked();

  /// Persists the locked state across application restarts.
  Future<void> setLocked({required bool locked});

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
  ///
  /// When [userId] is supplied, a snapshot cached for another principal is
  /// discarded. When [deviceFingerprint] is supplied, a snapshot cached for
  /// another physical device is discarded as well. Both bindings are required
  /// for an offline restart: without them a shared tablet could resume the
  /// previous clinician's permissions.
  Future<AuthorizationSnapshot?> cachedAuthorization({
    String? userId,
    String? deviceFingerprint,
  });

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

  /// Storage slot binding the cached snapshot to the device that obtained it.
  static const String _bindingSlot = 'nodex.authorization.binding.v1';

  /// Storage slot recording that the session is locked.
  static const String _lockSlot = 'nodex.session.locked.v1';

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
    await setLocked(locked: false);
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
  String? currentUserId() => _gateway.currentSession()?.userId;

  @override
  Future<bool> isLocked() async => (await _keyStore.read(_lockSlot)) == 'true';

  @override
  Future<void> setLocked({required bool locked}) async {
    if (locked) {
      await _keyStore.write(_lockSlot, 'true');
    } else {
      await _keyStore.delete(_lockSlot);
    }
  }

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

    await _cacheSnapshot(snapshot, deviceFingerprint: device.fingerprint);

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
  Future<AuthorizationSnapshot?> cachedAuthorization({
    String? userId,
    String? deviceFingerprint,
  }) async {
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

    if (userId != null && snapshot.userId != userId) {
      await clearCachedAuthorization();
      _logger.critical(
        _module,
        'Discarded a cached snapshot issued to another principal.',
        operation: 'session.load_cached_authorization',
        outcome: 'quarantined',
        errorCode: 'snapshot_user_mismatch',
      );
      return null;
    }

    if (deviceFingerprint != null) {
      final _SnapshotBinding? binding = await _readBinding();
      if (!cachedSnapshotIsBound(
        snapshot: snapshot,
        userId: userId,
        deviceFingerprint: deviceFingerprint,
        boundDeviceId: binding?.deviceId,
        boundFingerprint: binding?.deviceFingerprint,
      )) {
        await clearCachedAuthorization();
        _logger.critical(
          _module,
          'Discarded a cached snapshot that is not bound to this device.',
          operation: 'session.load_cached_authorization',
          outcome: 'quarantined',
          errorCode: 'snapshot_device_mismatch',
        );
        return null;
      }
    }

    return snapshot;
  }

  @override
  Future<void> clearCachedAuthorization() async {
    await _keyStore.delete(_snapshotSlot);
    await _keyStore.delete(_bindingSlot);
  }

  Future<_SnapshotBinding?> _readBinding() async {
    final String? raw = await _keyStore.read(_bindingSlot);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) {
        return null;
      }
      final Object? deviceId = decoded['device_id'];
      final Object? fingerprint = decoded['device_fingerprint'];
      if (deviceId is! String || fingerprint is! String) {
        return null;
      }
      return _SnapshotBinding(
        deviceId: deviceId,
        deviceFingerprint: fingerprint,
      );
    } on Object {
      return null;
    }
  }

  /// Caches [snapshot] with a locally recomputed digest.
  ///
  /// The server's digest covers the same fields but is computed over its own
  /// timestamp rendering. Storing a locally computed digest keeps verification
  /// self-consistent across serialisation round trips, while still detecting any
  /// edit to the cached payload.
  Future<void> _cacheSnapshot(
    AuthorizationSnapshot snapshot, {
    required String deviceFingerprint,
  }) async {
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
    await _keyStore.write(
      _bindingSlot,
      jsonEncode(<String, Object?>{
        'device_id': snapshot.deviceId,
        'device_fingerprint': deviceFingerprint,
      }),
    );
  }
}

/// The device a cached authorization snapshot belongs to.
final class _SnapshotBinding {
  const _SnapshotBinding({
    required this.deviceId,
    required this.deviceFingerprint,
  });

  final String deviceId;
  final String deviceFingerprint;
}

/// Whether a cached snapshot belongs to [userId] on [deviceFingerprint].
///
/// Pure so the binding rule is testable without a gateway or a platform
/// keystore. A missing binding is a mismatch: a snapshot cached before binding
/// was introduced must be reissued rather than trusted.
bool cachedSnapshotIsBound({
  required AuthorizationSnapshot snapshot,
  required String? userId,
  required String deviceFingerprint,
  required String? boundDeviceId,
  required String? boundFingerprint,
}) {
  if (userId != null && snapshot.userId != userId) {
    return false;
  }
  if (boundDeviceId == null || boundFingerprint == null) {
    return false;
  }
  return snapshot.deviceId == boundDeviceId &&
      boundFingerprint == deviceFingerprint;
}
