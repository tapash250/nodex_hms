/// Client-side authorization policy evaluated against an offline snapshot.
///
/// This is the Tier 1 client control from the specification's three-tier
/// security architecture. It exists to keep the interface honest (hiding
/// controls the user cannot use, and explaining why) and to stop a device from
/// attempting a privileged action while offline. It is explicitly *not* the
/// authorization boundary: PostgreSQL RLS and the backend mutation path remain
/// authoritative, and this policy can only ever deny more than the server does.
library;

import 'package:meta/meta.dart';
import 'package:nodex_hms/core/authorization/authorization_snapshot.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';

/// Connectivity state relevant to authorization.
enum ConnectivityState {
  /// A WAN path to the backend is available.
  online,

  /// No WAN path is available; only offline-permitted actions may proceed.
  offline;

  /// Whether this state represents an available WAN path.
  bool get isOnline => this == ConnectivityState.online;
}

/// The clinical scope an action targets.
///
/// A null component means the action is not scoped along that axis. Scope is
/// checked as a client-side pre-flight; the server enforces the same scope via
/// RLS helper functions and PowerSync sync streams.
@immutable
final class ActionScope {
  /// Creates an action scope.
  const ActionScope({this.facilityId, this.departmentId, this.wardId});

  /// An unscoped action, such as reading the signed-in user's own profile.
  static const ActionScope unscoped = ActionScope();

  /// Target facility, if any.
  final String? facilityId;

  /// Target department, if any.
  final String? departmentId;

  /// Target ward, if any.
  final String? wardId;

  /// Whether every component is absent.
  bool get isUnscoped =>
      facilityId == null && departmentId == null && wardId == null;
}

/// Evaluates whether an action may be attempted from the current device state.
@immutable
final class AuthorizationPolicy {
  /// Creates a policy over [snapshot] at [connectivity].
  const AuthorizationPolicy({
    required this.snapshot,
    required this.connectivity,
    this.digestVerified = true,
  });

  /// The active authorization snapshot, or null when no session is established.
  final AuthorizationSnapshot? snapshot;

  /// Current connectivity state.
  final ConnectivityState connectivity;

  /// Whether the cached snapshot's digest matched its contents on load.
  ///
  /// False indicates local tampering; the policy then denies everything and the
  /// bootstrap sequence raises an [IntegrityError].
  final bool digestVerified;

  /// Evaluates [permissionKey] against the current state.
  AuthorizationDecision evaluate(
    String permissionKey, {
    ActionScope scope = ActionScope.unscoped,
    DateTime? now,
  }) {
    final AuthorizationSnapshot? active = snapshot;
    if (active == null) {
      return AuthorizationDecision.denied(
        AuthorizationDenialReason.notGranted,
        permissionKey: permissionKey,
      );
    }

    if (!digestVerified) {
      return AuthorizationDecision.denied(
        AuthorizationDenialReason.snapshotTampered,
        permissionKey: permissionKey,
      );
    }

    if (active.isRevoked) {
      return AuthorizationDecision.denied(
        AuthorizationDenialReason.snapshotRevoked,
        permissionKey: permissionKey,
      );
    }

    final DateTime evaluatedAt = (now ?? DateTime.now()).toUtc();

    // An expired snapshot cannot authorize offline work. While online, the
    // caller is expected to refresh; until it does, deny rather than assume.
    if (!active.isValidAt(evaluatedAt)) {
      return AuthorizationDecision.denied(
        AuthorizationDenialReason.snapshotExpired,
        permissionKey: permissionKey,
      );
    }

    if (!active.permissions.contains(permissionKey)) {
      return AuthorizationDecision.denied(
        AuthorizationDenialReason.notGranted,
        permissionKey: permissionKey,
      );
    }

    if (!_isWithinScope(active, scope)) {
      return AuthorizationDecision.denied(
        AuthorizationDenialReason.outsideScope,
        permissionKey: permissionKey,
      );
    }

    // Offline: only the server-computed offline subset may be exercised. The
    // catalogue check is a defensive second gate in case a stale snapshot was
    // issued before a permission was reclassified as online-only.
    if (!connectivity.isOnline) {
      final bool offlinePermitted =
          active.offlinePermissions.contains(permissionKey) &&
          !NodexPermissions.requiresOnline.contains(permissionKey);
      if (!offlinePermitted) {
        return AuthorizationDecision.denied(
          AuthorizationDenialReason.requiresOnlineRevalidation,
          permissionKey: permissionKey,
        );
      }
    }

    return AuthorizationDecision.permitted(permissionKey: permissionKey);
  }

  /// Whether [permissionKey] may be attempted now.
  bool can(
    String permissionKey, {
    ActionScope scope = ActionScope.unscoped,
    DateTime? now,
  }) => evaluate(permissionKey, scope: scope, now: now).isPermitted;

  /// Whether any of [permissionKeys] may be attempted now.
  ///
  /// Used by navigation to decide whether a destination has at least one
  /// reachable action.
  bool canAny(
    Iterable<String> permissionKeys, {
    ActionScope scope = ActionScope.unscoped,
    DateTime? now,
  }) => permissionKeys.any((String key) => can(key, scope: scope, now: now));

  /// Whether the principal holds [roleKey] in the active tenant.
  bool hasRole(String roleKey) => snapshot?.roles.contains(roleKey) ?? false;

  /// Throws an [AuthorizationError] unless [permissionKey] is permitted.
  ///
  /// Domain use cases call this before mutating local state, so an unauthorized
  /// action never reaches the upload queue and never appears to have succeeded.
  void require(
    String permissionKey, {
    ActionScope scope = ActionScope.unscoped,
    DateTime? now,
  }) {
    final AuthorizationDecision decision = evaluate(
      permissionKey,
      scope: scope,
      now: now,
    );
    if (decision.isPermitted) {
      return;
    }

    if (decision.reason == AuthorizationDenialReason.snapshotTampered) {
      throw const IntegrityError(
        message:
            'The cached authorization snapshot failed verification; '
            'the local session has been quarantined.',
        subject: 'authorization_snapshot',
        code: 'snapshot_digest_mismatch',
      );
    }

    throw AuthorizationError(
      message: _denialMessage(decision.reason!, permissionKey),
      requiredPermission: permissionKey,
      requiresOnlineRevalidation: decision.isRecoverableOnline,
      code: decision.reason!.name,
      context: <String, Object?>{
        'permission_key': permissionKey,
        'connectivity': connectivity.name,
      },
    );
  }

  bool _isWithinScope(AuthorizationSnapshot active, ActionScope scope) {
    if (scope.isUnscoped) {
      return true;
    }

    // An empty scope set in the snapshot means the membership is not narrowed
    // along that axis, which is how tenant-wide roles are represented.
    bool axisPermitted(Set<String> permitted, String? target) =>
        target == null || permitted.isEmpty || permitted.contains(target);

    return axisPermitted(active.facilityIds, scope.facilityId) &&
        axisPermitted(active.departmentIds, scope.departmentId) &&
        axisPermitted(active.wardIds, scope.wardId);
  }

  static String _denialMessage(
    AuthorizationDenialReason reason,
    String permissionKey,
  ) => switch (reason) {
    AuthorizationDenialReason.notGranted =>
      'This account does not hold the permission required for this action.',
    AuthorizationDenialReason.requiresOnlineRevalidation =>
      'This action requires an online connection to revalidate authorization.',
    AuthorizationDenialReason.snapshotExpired =>
      'The offline authorization window has expired; reconnect to continue.',
    AuthorizationDenialReason.snapshotRevoked =>
      'Authorization for this device has been revoked.',
    AuthorizationDenialReason.snapshotTampered =>
      'The local authorization record failed verification.',
    AuthorizationDenialReason.outsideScope =>
      'This action targets a location outside the assigned scope.',
  };
}
