/// Session domain model.
///
/// A session couples an authenticated principal to a device-bound authorization
/// snapshot and a connectivity state. Everything the UI needs in order to decide
/// what a user may attempt is derived from this one object, which keeps
/// authorization decisions in one place instead of scattered across screens.
library;

import 'package:meta/meta.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/authorization_snapshot.dart';

/// Lifecycle phase of the application session.
enum SessionPhase {
  /// Bootstrap has not completed.
  initialising,

  /// No authenticated principal.
  unauthenticated,

  /// Authenticated, but the device holds no valid authorization snapshot.
  ///
  /// Reached when a first sign-in has not yet obtained a snapshot, or when the
  /// offline window lapsed while the device was disconnected. Clinical surfaces
  /// stay closed in this phase.
  awaitingAuthorization,

  /// Authenticated and authorized; clinical workflows are available.
  active,

  /// Authenticated but locked pending biometric or credential re-entry.
  locked,

  /// Quarantined after an integrity fault. Requires re-authentication.
  quarantined,
}

/// The signed-in principal's profile, limited to what the UI renders.
@immutable
final class SessionUser {
  /// Creates a session user.
  const SessionUser({
    required this.userId,
    required this.fullName,
    this.displayName,
    this.designation,
    this.email,
    this.avatarPath,
  });

  /// Authenticated principal identifier.
  final String userId;

  /// Legal name.
  final String fullName;

  /// Preferred short name.
  final String? displayName;

  /// Professional designation shown alongside the name.
  final String? designation;

  /// Contact email.
  final String? email;

  /// Storage path of the avatar image.
  final String? avatarPath;

  /// The name to render in navigation surfaces.
  String get preferredName => (displayName != null && displayName!.isNotEmpty)
      ? displayName!
      : fullName;
}

/// Identity of the device this session runs on.
@immutable
final class SessionDevice {
  /// Creates a device identity.
  const SessionDevice({
    required this.fingerprint,
    required this.formFactor,
    this.deviceId,
    this.displayName,
    this.osVersion,
    this.appVersion,
  });

  /// Stable device fingerprint used for enrolment and snapshot binding.
  final String fingerprint;

  /// Form factor, driving adaptive layout selection.
  final DeviceFormFactor formFactor;

  /// Server-side device identifier, once enrolled.
  final String? deviceId;

  /// Administrator-assigned label.
  final String? displayName;

  /// Android version string.
  final String? osVersion;

  /// Application version string.
  final String? appVersion;
}

/// Device form factor as defined by the specification's target devices.
enum DeviceFormFactor {
  /// 6" Android phone: bottom navigation.
  phone('phone'),

  /// 8" compact ward tablet: navigation rail.
  tabletCompact('tablet_compact'),

  /// 11-13" clinical tablet: navigation rail plus master/detail workspace.
  tabletLarge('tablet_large'),

  /// Unclassified device.
  other('other');

  const DeviceFormFactor(this.wireValue);

  /// Value persisted in `devices.form_factor`.
  final String wireValue;

  /// Whether this form factor uses a navigation rail rather than a bottom bar.
  bool get usesNavigationRail =>
      this == DeviceFormFactor.tabletCompact ||
      this == DeviceFormFactor.tabletLarge;

  /// Whether this form factor supports a master/detail workspace.
  bool get supportsMasterDetail => this == DeviceFormFactor.tabletLarge;
}

/// Immutable snapshot of the application session.
@immutable
final class SessionState {
  /// Creates a session state.
  const SessionState({
    required this.phase,
    required this.connectivity,
    this.user,
    this.device,
    this.snapshot,
    this.tenantId,
    this.snapshotIntegrityVerified = true,
    this.lastSyncAt,
    this.pendingUploadCount = 0,
    this.message,
  });

  /// The pre-bootstrap state.
  static const SessionState initial = SessionState(
    phase: SessionPhase.initialising,
    connectivity: ConnectivityState.offline,
  );

  /// Current lifecycle phase.
  final SessionPhase phase;

  /// Current connectivity state.
  final ConnectivityState connectivity;

  /// The signed-in principal, when authenticated.
  final SessionUser? user;

  /// The device this session runs on.
  final SessionDevice? device;

  /// The active authorization snapshot.
  final AuthorizationSnapshot? snapshot;

  /// Active tenant identifier.
  final String? tenantId;

  /// Whether the cached snapshot's digest verified on load.
  final bool snapshotIntegrityVerified;

  /// When replication last completed successfully.
  final DateTime? lastSyncAt;

  /// Mutations awaiting upload, surfaced in the sync status indicator.
  final int pendingUploadCount;

  /// Non-PHI user-facing message, for example why authorization is pending.
  final String? message;

  /// The authorization policy for this session.
  AuthorizationPolicy get authorization => AuthorizationPolicy(
    snapshot: snapshot,
    connectivity: connectivity,
    digestVerified: snapshotIntegrityVerified,
  );

  /// Whether clinical surfaces may be shown.
  bool get isClinicallyActive => phase == SessionPhase.active;

  /// Whether an authenticated principal exists.
  bool get isAuthenticated =>
      phase == SessionPhase.active ||
      phase == SessionPhase.locked ||
      phase == SessionPhase.awaitingAuthorization;

  /// Remaining offline authorization validity at [now].
  Duration remainingAuthorization(DateTime now) =>
      snapshot?.remainingValidity(now) ?? Duration.zero;

  /// Whether the offline window is close enough to expiry to warn the user.
  ///
  /// Warning before expiry matters clinically: a nurse mid-round should learn
  /// that authorization is lapsing while there is still time to reconnect.
  bool isAuthorizationExpiringSoon(
    DateTime now, {
    Duration threshold = const Duration(minutes: 30),
  }) {
    final AuthorizationSnapshot? active = snapshot;
    if (active == null) {
      return false;
    }
    final Duration remaining = active.remainingValidity(now);
    return remaining > Duration.zero && remaining <= threshold;
  }

  /// Returns a copy with the supplied fields replaced.
  SessionState copyWith({
    SessionPhase? phase,
    ConnectivityState? connectivity,
    SessionUser? user,
    SessionDevice? device,
    AuthorizationSnapshot? snapshot,
    String? tenantId,
    bool? snapshotIntegrityVerified,
    DateTime? lastSyncAt,
    int? pendingUploadCount,
    String? message,
    bool clearUser = false,
    bool clearSnapshot = false,
    bool clearMessage = false,
  }) => SessionState(
    phase: phase ?? this.phase,
    connectivity: connectivity ?? this.connectivity,
    user: clearUser ? null : (user ?? this.user),
    device: device ?? this.device,
    snapshot: clearSnapshot ? null : (snapshot ?? this.snapshot),
    tenantId: clearUser ? null : (tenantId ?? this.tenantId),
    snapshotIntegrityVerified:
        snapshotIntegrityVerified ?? this.snapshotIntegrityVerified,
    lastSyncAt: lastSyncAt ?? this.lastSyncAt,
    pendingUploadCount: pendingUploadCount ?? this.pendingUploadCount,
    message: clearMessage ? null : (message ?? this.message),
  );
}
