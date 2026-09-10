/// Session controller.
///
/// Owns the session lifecycle: bootstrap, sign-in, authorization refresh,
/// connectivity tracking, offline-window expiry, lock and wipe. Screens read
/// [SessionState] and dispatch intents here; they never call a repository, a
/// gateway or the Supabase SDK.
library;

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/authorization_snapshot.dart';
import 'package:nodex_hms/core/errors/error_mapper.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/data/local/local_database.dart';
import 'package:nodex_hms/domain/session/session_repository.dart';
import 'package:nodex_hms/domain/session/session_state.dart';

/// The current session state.
final NotifierProvider<SessionController, SessionState> sessionProvider =
    NotifierProvider<SessionController, SessionState>(SessionController.new);

/// Device identity, resolved once during bootstrap.
///
/// Overridden in `main` with values read from the platform, and in tests with a
/// fixture, so the controller never touches a platform channel directly.
final Provider<SessionDevice> sessionDeviceProvider = Provider<SessionDevice>((
  Ref ref,
) {
  throw UnimplementedError(
    'sessionDeviceProvider must be overridden during bootstrap.',
  );
});

/// Manages session lifecycle and authorization state.
final class SessionController extends Notifier<SessionState> {
  static const String _module = 'session.controller';

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _authorizationExpiryTimer;

  SessionRepository get _repository => ref.read(sessionRepositoryProvider);
  NodexLogger get _logger => ref.read(loggerProvider);
  LocalDatabase get _localDatabase => ref.read(localDatabaseProvider);

  @override
  SessionState build() {
    ref.onDispose(() {
      _connectivitySubscription?.cancel();
      _authorizationExpiryTimer?.cancel();
    });
    return SessionState.initial;
  }

  /// Establishes the session from cached state.
  ///
  /// Order matters. Connectivity is determined first, because the authorization
  /// policy differs online and offline. The cached snapshot is then verified: a
  /// digest mismatch quarantines the session rather than trusting the cached
  /// permission set.
  Future<void> bootstrap() async {
    await _startConnectivityWatch();

    final SessionDevice device = ref.read(sessionDeviceProvider);
    state = state.copyWith(device: device);

    if (!_repository.hasSession()) {
      state = state.copyWith(phase: SessionPhase.unauthenticated);
      return;
    }

    final AuthorizationSnapshot? cached = await _repository
        .cachedAuthorization();

    if (cached == null) {
      // Authenticated with no usable snapshot. Online, a refresh can recover;
      // offline, the device must reconnect before clinical work resumes.
      state = state.copyWith(
        phase: SessionPhase.awaitingAuthorization,
        message: state.connectivity.isOnline
            ? 'Refreshing authorization.'
            : 'Reconnect to restore clinical access.',
      );
      if (state.connectivity.isOnline) {
        await refreshAuthorization();
      }
      return;
    }

    final DateTime now = DateTime.now().toUtc();
    if (!cached.isValidAt(now)) {
      _logger.warning(
        _module,
        'Cached authorization has expired.',
        operation: 'session.bootstrap',
        outcome: 'expired',
      );
      state = state.copyWith(
        phase: SessionPhase.awaitingAuthorization,
        tenantId: cached.tenantId,
        clearSnapshot: true,
        message: 'The offline authorization window has expired.',
      );
      if (state.connectivity.isOnline) {
        await refreshAuthorization(tenantId: cached.tenantId);
      }
      return;
    }

    state = state.copyWith(
      phase: SessionPhase.active,
      snapshot: cached,
      tenantId: cached.tenantId,
      clearMessage: true,
    );
    _scheduleAuthorizationExpiry(cached);

    // Refresh opportunistically while online so role changes take effect without
    // waiting for the window to lapse.
    if (state.connectivity.isOnline) {
      await refreshAuthorization(tenantId: cached.tenantId);
    }
  }

  /// Signs in and establishes authorization.
  ///
  /// [tenantId] identifies the tenant to authorize within. A principal with
  /// memberships in several tenants selects one; the server rejects a tenant the
  /// principal has no active membership in.
  Future<void> signIn({
    required String email,
    required String password,
    required String tenantId,
  }) async {
    try {
      await _repository.signIn(email: email, password: password);
      state = state.copyWith(
        phase: SessionPhase.awaitingAuthorization,
        tenantId: tenantId,
        clearMessage: true,
      );
      await refreshAuthorization(tenantId: tenantId);
    } on NodexError catch (error) {
      state = state.copyWith(
        phase: SessionPhase.unauthenticated,
        clearUser: true,
        clearSnapshot: true,
        message: error.message,
      );
      rethrow;
    }
  }

  /// Obtains a fresh authorization snapshot.
  Future<void> refreshAuthorization({String? tenantId}) async {
    final String? resolvedTenant = tenantId ?? state.tenantId;
    final SessionDevice? device = state.device;

    if (resolvedTenant == null || device == null) {
      state = state.copyWith(
        phase: SessionPhase.awaitingAuthorization,
        message:
            'A tenant must be selected before authorization can be issued.',
      );
      return;
    }

    if (!state.connectivity.isOnline) {
      // Not an error: the device continues within its existing window if it has
      // one, and the caller already knows connectivity is absent.
      return;
    }

    try {
      final AuthorizationSnapshot snapshot = await _repository
          .refreshAuthorization(tenantId: resolvedTenant, device: device);

      state = state.copyWith(
        phase: SessionPhase.active,
        snapshot: snapshot,
        tenantId: snapshot.tenantId,
        snapshotIntegrityVerified: true,
        clearMessage: true,
      );
      _scheduleAuthorizationExpiry(snapshot);
    } on AuthorizationError catch (error) {
      // The principal is authenticated but not authorized in this tenant, or the
      // device has been revoked. Either way clinical surfaces stay closed.
      _logger.warning(
        _module,
        'Authorization refresh was denied.',
        operation: 'session.refresh_authorization',
        outcome: 'denied',
        errorCode: error.code,
      );
      state = state.copyWith(
        phase: SessionPhase.awaitingAuthorization,
        clearSnapshot: true,
        message: _authorizationDenialMessage(error),
      );
    } on ConnectivityError {
      // Keep the existing window; local-first operation continues.
      _logger.info(
        _module,
        'Authorization refresh deferred; the network was unavailable.',
        operation: 'session.refresh_authorization',
        outcome: 'deferred',
      );
    } on IntegrityError catch (error) {
      await _quarantine(error);
    } on Object catch (error, stackTrace) {
      final NodexError mapped = NodexErrorMapper.map(
        error,
        operation: 'session.refresh_authorization',
      );
      _logger.error(
        _module,
        'Authorization refresh failed.',
        operation: 'session.refresh_authorization',
        outcome: 'failed',
        errorCode: mapped.code,
        stackTrace: stackTrace,
      );
      state = state.copyWith(message: mapped.message);
    }
  }

  /// Requests a password recovery email for [email].
  ///
  /// Succeeds regardless of whether the account exists: the caller shows a
  /// neutral confirmation so the screen cannot be used to enumerate accounts.
  Future<void> requestPasswordReset(String email) =>
      _repository.requestPasswordReset(email);

  /// Locks the session, requiring biometric or credential re-entry.
  ///
  /// The snapshot is retained: locking protects the screen, it does not revoke
  /// authorization, so an interrupted ward round resumes without a round trip.
  void lock() {
    if (state.phase != SessionPhase.active) {
      return;
    }
    state = state.copyWith(phase: SessionPhase.locked);
  }

  /// Unlocks a locked session.
  ///
  /// Re-validates the window on unlock: the device may have sat locked past its
  /// offline expiry.
  Future<void> unlock() async {
    if (state.phase != SessionPhase.locked) {
      return;
    }

    final AuthorizationSnapshot? snapshot = state.snapshot;
    final DateTime now = DateTime.now().toUtc();

    if (snapshot == null || !snapshot.isValidAt(now)) {
      state = state.copyWith(
        phase: SessionPhase.awaitingAuthorization,
        clearSnapshot: true,
        message: 'The offline authorization window expired while locked.',
      );
      if (state.connectivity.isOnline) {
        await refreshAuthorization();
      }
      return;
    }

    state = state.copyWith(phase: SessionPhase.active, clearMessage: true);
  }

  /// Signs out, clearing local clinical data.
  Future<void> signOut() async {
    _authorizationExpiryTimer?.cancel();
    try {
      if (_localDatabase.isOpen) {
        await _localDatabase.signOutAndClear();
      }
    } on Object catch (error, stackTrace) {
      _logger.error(
        _module,
        'Failed to clear local data during sign-out.',
        operation: 'session.sign_out',
        outcome: 'partial',
        stackTrace: stackTrace,
        dimensions: <String, Object?>{'error': '$error'},
      );
    }

    await _repository.signOut();
    state = SessionState(
      phase: SessionPhase.unauthenticated,
      connectivity: state.connectivity,
      device: state.device,
    );
  }

  /// Records the observed connectivity state.
  void setConnectivity(ConnectivityState connectivity) {
    if (state.connectivity == connectivity) {
      return;
    }
    state = state.copyWith(connectivity: connectivity);
  }

  /// Updates sync telemetry shown by the status indicator.
  void updateSyncStatus({DateTime? lastSyncAt, int? pendingUploadCount}) {
    state = state.copyWith(
      lastSyncAt: lastSyncAt,
      pendingUploadCount: pendingUploadCount,
    );
  }

  Future<void> _startConnectivityWatch() async {
    final Connectivity connectivity = Connectivity();
    try {
      final List<ConnectivityResult> current = await connectivity
          .checkConnectivity();
      setConnectivity(_classify(current));
    } on Object {
      // Unknown connectivity is treated as offline: assuming a network that is
      // not there would let a privileged action be attempted and fail late.
      setConnectivity(ConnectivityState.offline);
    }

    await _connectivitySubscription?.cancel();
    _connectivitySubscription = connectivity.onConnectivityChanged.listen((
      List<ConnectivityResult> results,
    ) {
      final ConnectivityState next = _classify(results);
      final bool regained =
          state.connectivity == ConnectivityState.offline && next.isOnline;
      setConnectivity(next);

      // Reconnection is the moment to re-establish authorization, both to pick
      // up role changes and to extend the offline window before it lapses.
      if (regained && _repository.hasSession()) {
        unawaited(refreshAuthorization());
      }
    });
  }

  static ConnectivityState _classify(List<ConnectivityResult> results) {
    final bool hasTransport = results.any(
      (ConnectivityResult result) => result != ConnectivityResult.none,
    );
    return hasTransport ? ConnectivityState.online : ConnectivityState.offline;
  }

  void _scheduleAuthorizationExpiry(AuthorizationSnapshot snapshot) {
    _authorizationExpiryTimer?.cancel();
    final Duration remaining = snapshot.remainingValidity(DateTime.now());
    if (remaining == Duration.zero) {
      return;
    }

    _authorizationExpiryTimer = Timer(remaining, () async {
      _logger.warning(
        _module,
        'Offline authorization window elapsed.',
        operation: 'session.authorization_expiry',
        outcome: 'expired',
      );

      // Stop pulling new data the moment authorization lapses; local data is
      // retained under the retention policy rather than wiped.
      if (_localDatabase.isConnected) {
        await _localDatabase.disconnect();
      }

      state = state.copyWith(
        phase: SessionPhase.awaitingAuthorization,
        clearSnapshot: true,
        message: 'The offline authorization window has expired.',
      );

      if (state.connectivity.isOnline) {
        await refreshAuthorization();
      }
    });
  }

  /// Maps an authorization denial to the message shown on the
  /// awaiting-authorization screen.
  ///
  /// An unprovisioned account (authenticated but holding no membership, or a
  /// device the tenant has revoked) gets a first-run explanation that points
  /// at the administrator, not a raw database error string. Every other denial
  /// keeps the mapped message, which carries no PHI by construction.
  String _authorizationDenialMessage(AuthorizationError error) {
    if (error.code == 'account_not_provisioned' ||
        error.code == 'no_active_membership') {
      return 'This account has not been set up for clinical access yet. '
          'Ask your hospital administrator for an invitation, then sign in again.';
    }
    return error.message;
  }

  Future<void> _quarantine(IntegrityError error) async {
    _authorizationExpiryTimer?.cancel();
    _logger.critical(
      _module,
      'Session quarantined after an integrity fault.',
      operation: 'session.quarantine',
      outcome: 'quarantined',
      errorCode: error.code,
      dimensions: <String, Object?>{'subject': error.subject},
    );

    await _repository.clearCachedAuthorization();
    try {
      await _localDatabase.wipe(reason: 'integrity_fault:${error.subject}');
    } on Object catch (wipeError, stackTrace) {
      _logger.critical(
        _module,
        'Failed to wipe local data after an integrity fault.',
        operation: 'session.quarantine',
        outcome: 'failed',
        stackTrace: stackTrace,
        dimensions: <String, Object?>{'error': '$wipeError'},
      );
    }

    state = state.copyWith(
      phase: SessionPhase.quarantined,
      clearSnapshot: true,
      snapshotIntegrityVerified: false,
      message:
          'The local security state failed verification. Sign in again to '
          'restore access.',
    );
  }
}
