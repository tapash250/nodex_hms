/// Tests for the offline authorization policy.
///
/// These cover the Tier 1 client control's contract: it can only ever deny more
/// than the server does, privileged actions are refused offline, an expired or
/// tampered snapshot authorizes nothing, and scope narrowing is respected.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/authorization_snapshot.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';

void main() {
  final DateTime issuedAt = DateTime.utc(2026, 9, 1, 8);
  final DateTime now = DateTime.utc(2026, 9, 1, 10);

  AuthorizationSnapshot buildSnapshot({
    Set<String> permissions = const <String>{},
    Set<String> offlinePermissions = const <String>{},
    Set<String> roles = const <String>{NodexRoles.medicalOfficer},
    Set<String> facilityIds = const <String>{},
    Set<String> departmentIds = const <String>{},
    Set<String> wardIds = const <String>{},
    DateTime? expiresAt,
    DateTime? revokedAt,
  }) => AuthorizationSnapshot(
    snapshotId: 'snapshot-1',
    tenantId: 'tenant-1',
    userId: 'user-1',
    deviceId: 'device-1',
    revision: 1,
    issuedAt: issuedAt,
    expiresAt: expiresAt ?? issuedAt.add(const Duration(hours: 12)),
    payloadDigest: 'digest',
    roles: roles,
    permissions: permissions,
    offlinePermissions: offlinePermissions,
    facilityIds: facilityIds,
    departmentIds: departmentIds,
    wardIds: wardIds,
    revokedAt: revokedAt,
  );

  group('AuthorizationPolicy without a session', () {
    test('denies every permission when no snapshot is present', () {
      const AuthorizationPolicy policy = AuthorizationPolicy(
        snapshot: null,
        connectivity: ConnectivityState.online,
      );

      final AuthorizationDecision decision = policy.evaluate(
        NodexPermissions.patientRead,
      );

      expect(decision.isPermitted, isFalse);
      expect(decision.reason, AuthorizationDenialReason.notGranted);
    });
  });

  group('AuthorizationPolicy online', () {
    test('permits a granted permission', () {
      final AuthorizationPolicy policy = AuthorizationPolicy(
        snapshot: buildSnapshot(
          permissions: <String>{NodexPermissions.patientRead},
          offlinePermissions: <String>{NodexPermissions.patientRead},
        ),
        connectivity: ConnectivityState.online,
      );

      expect(policy.can(NodexPermissions.patientRead, now: now), isTrue);
    });

    test('denies a permission that was never granted', () {
      final AuthorizationPolicy policy = AuthorizationPolicy(
        snapshot: buildSnapshot(
          permissions: <String>{NodexPermissions.patientRead},
        ),
        connectivity: ConnectivityState.online,
      );

      final AuthorizationDecision decision = policy.evaluate(
        NodexPermissions.prescriptionFinalize,
        now: now,
      );

      expect(decision.isPermitted, isFalse);
      expect(decision.reason, AuthorizationDenialReason.notGranted);
      expect(decision.isRecoverableOnline, isFalse);
    });

    test('permits an online-only permission while connected', () {
      final AuthorizationPolicy policy = AuthorizationPolicy(
        snapshot: buildSnapshot(
          permissions: <String>{NodexPermissions.prescriptionFinalize},
          // Deliberately absent from the offline subset, as the server computes it.
        ),
        connectivity: ConnectivityState.online,
      );

      expect(
        policy.can(NodexPermissions.prescriptionFinalize, now: now),
        isTrue,
      );
    });
  });

  group('AuthorizationPolicy offline', () {
    test('permits a permission present in the offline subset', () {
      final AuthorizationPolicy policy = AuthorizationPolicy(
        snapshot: buildSnapshot(
          permissions: <String>{NodexPermissions.vitalsRecord},
          offlinePermissions: <String>{NodexPermissions.vitalsRecord},
        ),
        connectivity: ConnectivityState.offline,
      );

      expect(policy.can(NodexPermissions.vitalsRecord, now: now), isTrue);
    });

    test('refuses a privileged action that requires online revalidation', () {
      final AuthorizationPolicy policy = AuthorizationPolicy(
        snapshot: buildSnapshot(
          permissions: <String>{NodexPermissions.prescriptionFinalize},
          offlinePermissions: <String>{},
        ),
        connectivity: ConnectivityState.offline,
      );

      final AuthorizationDecision decision = policy.evaluate(
        NodexPermissions.prescriptionFinalize,
        now: now,
      );

      expect(decision.isPermitted, isFalse);
      expect(
        decision.reason,
        AuthorizationDenialReason.requiresOnlineRevalidation,
      );
      expect(decision.isRecoverableOnline, isTrue);
    });

    test('refuses an online-only permission even if a stale snapshot lists it '
        'as offline-capable', () {
      // Guards against a snapshot issued before a permission was reclassified
      // as online-only: the local catalogue is a second gate.
      final AuthorizationPolicy policy = AuthorizationPolicy(
        snapshot: buildSnapshot(
          permissions: <String>{NodexPermissions.billingSettle},
          offlinePermissions: <String>{NodexPermissions.billingSettle},
        ),
        connectivity: ConnectivityState.offline,
      );

      final AuthorizationDecision decision = policy.evaluate(
        NodexPermissions.billingSettle,
        now: now,
      );

      expect(decision.isPermitted, isFalse);
      expect(
        decision.reason,
        AuthorizationDenialReason.requiresOnlineRevalidation,
      );
    });

    test('every catalogued online-only permission is refused offline', () {
      final AuthorizationPolicy policy = AuthorizationPolicy(
        snapshot: buildSnapshot(
          permissions: NodexPermissions.requiresOnline,
          offlinePermissions: NodexPermissions.requiresOnline,
        ),
        connectivity: ConnectivityState.offline,
      );

      for (final String permission in NodexPermissions.requiresOnline) {
        expect(
          policy.can(permission, now: now),
          isFalse,
          reason: '$permission must not be exercisable offline',
        );
      }
    });
  });

  group('AuthorizationPolicy snapshot validity', () {
    test('denies once the offline window has elapsed', () {
      final AuthorizationPolicy policy = AuthorizationPolicy(
        snapshot: buildSnapshot(
          permissions: <String>{NodexPermissions.patientRead},
          offlinePermissions: <String>{NodexPermissions.patientRead},
          expiresAt: issuedAt.add(const Duration(hours: 1)),
        ),
        connectivity: ConnectivityState.online,
      );

      final AuthorizationDecision decision = policy.evaluate(
        NodexPermissions.patientRead,
        now: now,
      );

      expect(decision.isPermitted, isFalse);
      expect(decision.reason, AuthorizationDenialReason.snapshotExpired);
      expect(decision.isRecoverableOnline, isTrue);
    });

    test('denies a revoked snapshot', () {
      final AuthorizationPolicy policy = AuthorizationPolicy(
        snapshot: buildSnapshot(
          permissions: <String>{NodexPermissions.patientRead},
          offlinePermissions: <String>{NodexPermissions.patientRead},
          revokedAt: issuedAt.add(const Duration(minutes: 30)),
        ),
        connectivity: ConnectivityState.online,
      );

      expect(
        policy.evaluate(NodexPermissions.patientRead, now: now).reason,
        AuthorizationDenialReason.snapshotRevoked,
      );
    });

    test('denies everything when the digest failed verification', () {
      final AuthorizationPolicy policy = AuthorizationPolicy(
        snapshot: buildSnapshot(
          permissions: <String>{NodexPermissions.patientRead},
          offlinePermissions: <String>{NodexPermissions.patientRead},
        ),
        connectivity: ConnectivityState.online,
        digestVerified: false,
      );

      expect(
        policy.evaluate(NodexPermissions.patientRead, now: now).reason,
        AuthorizationDenialReason.snapshotTampered,
      );
    });
  });

  group('AuthorizationPolicy scope', () {
    test('permits an action inside the assigned facility', () {
      final AuthorizationPolicy policy = AuthorizationPolicy(
        snapshot: buildSnapshot(
          permissions: <String>{NodexPermissions.bedAssign},
          offlinePermissions: <String>{NodexPermissions.bedAssign},
          facilityIds: <String>{'facility-1'},
        ),
        connectivity: ConnectivityState.online,
      );

      expect(
        policy.can(
          NodexPermissions.bedAssign,
          scope: const ActionScope(facilityId: 'facility-1'),
          now: now,
        ),
        isTrue,
      );
    });

    test('refuses an action outside the assigned facility', () {
      final AuthorizationPolicy policy = AuthorizationPolicy(
        snapshot: buildSnapshot(
          permissions: <String>{NodexPermissions.bedAssign},
          offlinePermissions: <String>{NodexPermissions.bedAssign},
          facilityIds: <String>{'facility-1'},
        ),
        connectivity: ConnectivityState.online,
      );

      final AuthorizationDecision decision = policy.evaluate(
        NodexPermissions.bedAssign,
        scope: const ActionScope(facilityId: 'facility-2'),
        now: now,
      );

      expect(decision.isPermitted, isFalse);
      expect(decision.reason, AuthorizationDenialReason.outsideScope);
    });

    test('treats an empty scope set as tenant-wide for that axis', () {
      // How a Hospital Super Admin or Auditor membership is represented.
      final AuthorizationPolicy policy = AuthorizationPolicy(
        snapshot: buildSnapshot(
          permissions: <String>{NodexPermissions.auditRead},
          offlinePermissions: <String>{NodexPermissions.auditRead},
          roles: <String>{NodexRoles.auditor},
        ),
        connectivity: ConnectivityState.online,
      );

      expect(
        policy.can(
          NodexPermissions.auditRead,
          scope: const ActionScope(
            facilityId: 'any-facility',
            wardId: 'any-ward',
          ),
          now: now,
        ),
        isTrue,
      );
    });

    test('narrows on the ward axis independently', () {
      final AuthorizationPolicy policy = AuthorizationPolicy(
        snapshot: buildSnapshot(
          permissions: <String>{NodexPermissions.medicationAdminister},
          offlinePermissions: <String>{NodexPermissions.medicationAdminister},
          roles: <String>{NodexRoles.nursingStaff},
          wardIds: <String>{'ward-a'},
        ),
        connectivity: ConnectivityState.offline,
      );

      expect(
        policy.can(
          NodexPermissions.medicationAdminister,
          scope: const ActionScope(wardId: 'ward-a'),
          now: now,
        ),
        isTrue,
      );
      expect(
        policy.can(
          NodexPermissions.medicationAdminister,
          scope: const ActionScope(wardId: 'ward-b'),
          now: now,
        ),
        isFalse,
      );
    });
  });

  group('AuthorizationPolicy.require', () {
    test('throws AuthorizationError with the offending permission', () {
      final AuthorizationPolicy policy = AuthorizationPolicy(
        snapshot: buildSnapshot(
          permissions: <String>{NodexPermissions.patientRead},
        ),
        connectivity: ConnectivityState.online,
      );

      expect(
        () => policy.require(NodexPermissions.dischargeFinalize, now: now),
        throwsA(
          isA<AuthorizationError>()
              .having(
                (AuthorizationError e) => e.requiredPermission,
                'requiredPermission',
                NodexPermissions.dischargeFinalize,
              )
              .having(
                (AuthorizationError e) => e.isRetryable,
                'isRetryable',
                isFalse,
              ),
        ),
      );
    });

    test('marks an offline denial as recoverable online', () {
      final AuthorizationPolicy policy = AuthorizationPolicy(
        snapshot: buildSnapshot(
          permissions: <String>{NodexPermissions.labResultVerify},
          offlinePermissions: <String>{},
        ),
        connectivity: ConnectivityState.offline,
      );

      expect(
        () => policy.require(NodexPermissions.labResultVerify, now: now),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError e) => e.requiresOnlineRevalidation,
            'requiresOnlineRevalidation',
            isTrue,
          ),
        ),
      );
    });

    test(
      'raises IntegrityError rather than AuthorizationError on tampering',
      () {
        final AuthorizationPolicy policy = AuthorizationPolicy(
          snapshot: buildSnapshot(
            permissions: <String>{NodexPermissions.patientRead},
            offlinePermissions: <String>{NodexPermissions.patientRead},
          ),
          connectivity: ConnectivityState.online,
          digestVerified: false,
        );

        expect(
          () => policy.require(NodexPermissions.patientRead, now: now),
          throwsA(
            isA<IntegrityError>().having(
              (IntegrityError e) => e.subject,
              'subject',
              'authorization_snapshot',
            ),
          ),
        );
      },
    );

    test('returns normally when permitted', () {
      final AuthorizationPolicy policy = AuthorizationPolicy(
        snapshot: buildSnapshot(
          permissions: <String>{NodexPermissions.vitalsRecord},
          offlinePermissions: <String>{NodexPermissions.vitalsRecord},
        ),
        connectivity: ConnectivityState.offline,
      );

      expect(
        () => policy.require(NodexPermissions.vitalsRecord, now: now),
        returnsNormally,
      );
    });
  });

  group('AuthorizationPolicy.canAny and hasRole', () {
    test('canAny is true when at least one permission is held', () {
      final AuthorizationPolicy policy = AuthorizationPolicy(
        snapshot: buildSnapshot(
          permissions: <String>{NodexPermissions.appointmentRead},
          offlinePermissions: <String>{NodexPermissions.appointmentRead},
        ),
        connectivity: ConnectivityState.online,
      );

      expect(
        policy.canAny(<String>{
          NodexPermissions.patientWrite,
          NodexPermissions.appointmentRead,
        }, now: now),
        isTrue,
      );
    });

    test('canAny is false when none are held', () {
      final AuthorizationPolicy policy = AuthorizationPolicy(
        snapshot: buildSnapshot(
          permissions: <String>{NodexPermissions.appointmentRead},
        ),
        connectivity: ConnectivityState.online,
      );

      expect(
        policy.canAny(<String>{
          NodexPermissions.patientWrite,
          NodexPermissions.billingSettle,
        }, now: now),
        isFalse,
      );
    });

    test('hasRole reflects the snapshot roles', () {
      final AuthorizationPolicy policy = AuthorizationPolicy(
        snapshot: buildSnapshot(roles: <String>{NodexRoles.pharmacist}),
        connectivity: ConnectivityState.online,
      );

      expect(policy.hasRole(NodexRoles.pharmacist), isTrue);
      expect(policy.hasRole(NodexRoles.hospitalSuperAdmin), isFalse);
    });
  });

  group('AuthorizationSnapshot', () {
    test('reports remaining validity and expiry', () {
      final AuthorizationSnapshot snapshot = buildSnapshot(
        expiresAt: issuedAt.add(const Duration(hours: 3)),
      );

      expect(snapshot.remainingValidity(now), const Duration(hours: 1));
      expect(snapshot.isValidAt(now), isTrue);
      expect(
        snapshot.isValidAt(issuedAt.add(const Duration(hours: 4))),
        isFalse,
      );
      expect(
        snapshot.remainingValidity(issuedAt.add(const Duration(hours: 4))),
        Duration.zero,
      );
    });

    test('round-trips through JSON', () {
      final AuthorizationSnapshot original = buildSnapshot(
        permissions: <String>{
          NodexPermissions.patientRead,
          NodexPermissions.vitalsRecord,
        },
        offlinePermissions: <String>{NodexPermissions.vitalsRecord},
        facilityIds: <String>{'facility-1'},
        wardIds: <String>{'ward-a'},
      );

      final AuthorizationSnapshot restored = AuthorizationSnapshot.fromJson(
        original.toJson(),
      );

      expect(restored, original);
    });

    test('preserves revocation across a JSON round trip', () {
      final AuthorizationSnapshot revoked = buildSnapshot().revoke(now);
      final AuthorizationSnapshot restored = AuthorizationSnapshot.fromJson(
        revoked.toJson(),
      );

      expect(restored.isRevoked, isTrue);
      expect(restored.revokedAt, now);
    });

    test('rejects a server payload missing a required field', () {
      expect(
        () => AuthorizationSnapshot.fromServer(const <String, Object?>{
          'snapshot_id': 'snapshot-1',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('materialises from a server row', () {
      final AuthorizationSnapshot snapshot = AuthorizationSnapshot.fromServer(
        <String, Object?>{
          'snapshot_id': 'snapshot-9',
          'tenant_id': 'tenant-1',
          'user_id': 'user-1',
          'device_id': 'device-1',
          'snapshot_revision': 4,
          'issued_at': issuedAt.toIso8601String(),
          'expires_at': issuedAt
              .add(const Duration(hours: 6))
              .toIso8601String(),
          'payload_digest': 'abc123',
          'roles': const <String>['nursing_staff'],
          'permissions': const <String>['vitals.record'],
          'offline_permissions': const <String>['vitals.record'],
          'facility_ids': const <String>['facility-1'],
          'department_ids': const <String>[],
          'ward_ids': const <String>['ward-a'],
        },
      );

      expect(snapshot.revision, 4);
      expect(snapshot.roles, <String>{'nursing_staff'});
      expect(snapshot.offlinePermissions, <String>{'vitals.record'});
      expect(snapshot.wardIds, <String>{'ward-a'});
    });
  });
}
