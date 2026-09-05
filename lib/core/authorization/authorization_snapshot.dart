/// Device-bound, time-bounded offline authorization snapshot.
///
/// The snapshot is issued by the server (`public.issue_authorization_snapshot`)
/// at online authorization refresh. It contains the minimum information needed
/// to continue approved offline workflows and nothing more.
///
/// Three properties matter and are enforced here rather than at call sites:
///
/// 1. The snapshot never widens access. It is a client-side gate that can only
///    deny; PostgreSQL row level security remains the authoritative boundary.
/// 2. Offline permissions are a server-computed subset. The client does not
///    derive them, because deriving them locally would make the offline
///    boundary a client-side decision.
/// 3. Validity is bounded in time and bound to one device and one user.
library;

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

/// Why an authorization decision was refused.
enum AuthorizationDenialReason {
  /// The principal does not hold the permission at all.
  notGranted,

  /// The permission is held but requires online revalidation.
  requiresOnlineRevalidation,

  /// The snapshot's validity window has elapsed.
  snapshotExpired,

  /// The snapshot was revoked, for example by a role change or device wipe.
  snapshotRevoked,

  /// The snapshot digest did not match its contents.
  snapshotTampered,

  /// The action targets a facility, department or ward outside the device scope.
  outsideScope,
}

/// Result of an authorization check.
@immutable
final class AuthorizationDecision {
  /// Creates a decision.
  const AuthorizationDecision._({
    required this.isPermitted,
    this.reason,
    this.permissionKey,
  });

  /// The action is permitted within the current authorization state.
  const AuthorizationDecision.permitted({String? permissionKey})
    : this._(isPermitted: true, permissionKey: permissionKey);

  /// The action is refused for [reason].
  const AuthorizationDecision.denied(
    AuthorizationDenialReason reason, {
    String? permissionKey,
  }) : this._(isPermitted: false, reason: reason, permissionKey: permissionKey);

  /// Whether the action may proceed.
  final bool isPermitted;

  /// Why the action was refused, when it was.
  final AuthorizationDenialReason? reason;

  /// The permission that was evaluated.
  final String? permissionKey;

  /// Whether an online authorization refresh could change this outcome.
  bool get isRecoverableOnline =>
      reason == AuthorizationDenialReason.requiresOnlineRevalidation ||
      reason == AuthorizationDenialReason.snapshotExpired;
}

/// An issued authorization snapshot.
@immutable
final class AuthorizationSnapshot {
  /// Creates a snapshot. Prefer [AuthorizationSnapshot.fromServer] when
  /// materialising the result of the issuance RPC.
  AuthorizationSnapshot({
    required this.snapshotId,
    required this.tenantId,
    required this.userId,
    required this.deviceId,
    required this.revision,
    required this.issuedAt,
    required this.expiresAt,
    required this.payloadDigest,
    required Set<String> roles,
    required Set<String> permissions,
    required Set<String> offlinePermissions,
    required Set<String> facilityIds,
    required Set<String> departmentIds,
    required Set<String> wardIds,
    this.revokedAt,
  }) : roles = Set<String>.unmodifiable(roles),
       permissions = Set<String>.unmodifiable(permissions),
       offlinePermissions = Set<String>.unmodifiable(offlinePermissions),
       facilityIds = Set<String>.unmodifiable(facilityIds),
       departmentIds = Set<String>.unmodifiable(departmentIds),
       wardIds = Set<String>.unmodifiable(wardIds),
       assert(
         expiresAt.isAfter(issuedAt),
         'snapshot validity window must be positive',
       );

  /// Materialises a snapshot from the issuance RPC result.
  ///
  /// Throws [FormatException] when a required field is absent or malformed.
  /// The caller maps that onto a validation failure.
  factory AuthorizationSnapshot.fromServer(Map<String, Object?> row) {
    String requireString(String key) {
      final Object? value = row[key];
      if (value is String && value.isNotEmpty) {
        return value;
      }
      throw FormatException('authorization snapshot field "$key" is missing');
    }

    DateTime requireTimestamp(String key) {
      final Object? value = row[key];
      if (value is DateTime) {
        return value.toUtc();
      }
      if (value is String) {
        return DateTime.parse(value).toUtc();
      }
      throw FormatException('authorization snapshot field "$key" is missing');
    }

    Set<String> stringSet(String key) {
      final Object? value = row[key];
      if (value == null) {
        return const <String>{};
      }
      if (value is Iterable<Object?>) {
        return value.whereType<String>().toSet();
      }
      throw FormatException('authorization snapshot field "$key" is malformed');
    }

    final Object? revision = row['snapshot_revision'];
    return AuthorizationSnapshot(
      snapshotId: requireString('snapshot_id'),
      tenantId: requireString('tenant_id'),
      userId: requireString('user_id'),
      deviceId: requireString('device_id'),
      revision: revision is int
          ? revision
          : int.parse(revision?.toString() ?? '1'),
      issuedAt: requireTimestamp('issued_at'),
      expiresAt: requireTimestamp('expires_at'),
      payloadDigest: requireString('payload_digest'),
      roles: stringSet('roles'),
      permissions: stringSet('permissions'),
      offlinePermissions: stringSet('offline_permissions'),
      facilityIds: stringSet('facility_ids'),
      departmentIds: stringSet('department_ids'),
      wardIds: stringSet('ward_ids'),
    );
  }

  /// Server-side snapshot identifier.
  final String snapshotId;

  /// Tenant this snapshot authorizes within.
  final String tenantId;

  /// The principal the snapshot was issued to.
  final String userId;

  /// The device the snapshot is bound to.
  final String deviceId;

  /// Monotonic revision for this device/user pair.
  final int revision;

  /// When the snapshot was issued, in UTC.
  final DateTime issuedAt;

  /// When the snapshot ceases to authorize offline work, in UTC.
  final DateTime expiresAt;

  /// Server-computed digest of the issued payload.
  final String payloadDigest;

  /// Roles held in this tenant.
  final Set<String> roles;

  /// All permissions held in this tenant, online or offline.
  final Set<String> permissions;

  /// The server-computed subset exercisable without connectivity.
  final Set<String> offlinePermissions;

  /// Facilities in scope. Empty means tenant-wide for the held roles.
  final Set<String> facilityIds;

  /// Departments in scope. Empty means department-agnostic.
  final Set<String> departmentIds;

  /// Wards in scope. Empty means ward-agnostic.
  final Set<String> wardIds;

  /// When the snapshot was revoked, if it was.
  final DateTime? revokedAt;

  /// Whether the snapshot has been revoked.
  bool get isRevoked => revokedAt != null;

  /// Whether the snapshot is still within its validity window at [now].
  bool isValidAt(DateTime now) => !isRevoked && now.toUtc().isBefore(expiresAt);

  /// Remaining validity at [now]; [Duration.zero] once expired.
  Duration remainingValidity(DateTime now) {
    final Duration remaining = expiresAt.difference(now.toUtc());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Returns a copy marked revoked at [at].
  AuthorizationSnapshot revoke(DateTime at) => AuthorizationSnapshot(
    snapshotId: snapshotId,
    tenantId: tenantId,
    userId: userId,
    deviceId: deviceId,
    revision: revision,
    issuedAt: issuedAt,
    expiresAt: expiresAt,
    payloadDigest: payloadDigest,
    roles: roles,
    permissions: permissions,
    offlinePermissions: offlinePermissions,
    facilityIds: facilityIds,
    departmentIds: departmentIds,
    wardIds: wardIds,
    revokedAt: at.toUtc(),
  );

  /// Serialises the snapshot for encrypted local persistence.
  Map<String, Object?> toJson() => <String, Object?>{
    'snapshot_id': snapshotId,
    'tenant_id': tenantId,
    'user_id': userId,
    'device_id': deviceId,
    'snapshot_revision': revision,
    'issued_at': issuedAt.toIso8601String(),
    'expires_at': expiresAt.toIso8601String(),
    'payload_digest': payloadDigest,
    'roles': roles.toList(growable: false),
    'permissions': permissions.toList(growable: false),
    'offline_permissions': offlinePermissions.toList(growable: false),
    'facility_ids': facilityIds.toList(growable: false),
    'department_ids': departmentIds.toList(growable: false),
    'ward_ids': wardIds.toList(growable: false),
    'revoked_at': revokedAt?.toIso8601String(),
  };

  /// Restores a snapshot previously written by [toJson].
  static AuthorizationSnapshot fromJson(Map<String, Object?> json) {
    final AuthorizationSnapshot base = AuthorizationSnapshot.fromServer(json);
    final Object? revokedAt = json['revoked_at'];
    if (revokedAt is String) {
      return base.revoke(DateTime.parse(revokedAt));
    }
    return base;
  }

  @override
  bool operator ==(Object other) {
    if (other is! AuthorizationSnapshot) {
      return false;
    }
    const SetEquality<String> sets = SetEquality<String>();
    return other.snapshotId == snapshotId &&
        other.revision == revision &&
        other.tenantId == tenantId &&
        other.userId == userId &&
        other.deviceId == deviceId &&
        other.issuedAt == issuedAt &&
        other.expiresAt == expiresAt &&
        other.payloadDigest == payloadDigest &&
        other.revokedAt == revokedAt &&
        sets.equals(other.roles, roles) &&
        sets.equals(other.permissions, permissions) &&
        sets.equals(other.offlinePermissions, offlinePermissions) &&
        sets.equals(other.facilityIds, facilityIds) &&
        sets.equals(other.departmentIds, departmentIds) &&
        sets.equals(other.wardIds, wardIds);
  }

  @override
  int get hashCode => Object.hash(
    snapshotId,
    revision,
    tenantId,
    userId,
    deviceId,
    issuedAt,
    expiresAt,
    payloadDigest,
    revokedAt,
  );
}
