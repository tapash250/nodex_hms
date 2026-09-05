/// Tests for session state derivation.
///
/// The session couples an authenticated principal to a device-bound authorization
/// snapshot and a connectivity state. Screens derive everything from it, so these
/// tests pin the derivations that gate clinical surfaces.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/authorization_snapshot.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/domain/session/session_state.dart';

void main() {
  final DateTime issuedAt = DateTime.utc(2026, 9, 1, 8);

  AuthorizationSnapshot snapshotExpiringAt(DateTime expiresAt) =>
      AuthorizationSnapshot(
        snapshotId: 'snapshot-1',
        tenantId: 'tenant-1',
        userId: 'user-1',
        deviceId: 'device-1',
        revision: 1,
        issuedAt: issuedAt,
        expiresAt: expiresAt,
        payloadDigest: 'digest',
        roles: const <String>{'nursing_staff'},
        permissions: const <String>{NodexPermissions.vitalsRecord},
        offlinePermissions: const <String>{NodexPermissions.vitalsRecord},
        facilityIds: const <String>{},
        departmentIds: const <String>{},
        wardIds: const <String>{},
      );

  group('SessionState phases', () {
    test('initial state is initialising and offline', () {
      expect(SessionState.initial.phase, SessionPhase.initialising);
      expect(SessionState.initial.connectivity, ConnectivityState.offline);
      expect(SessionState.initial.isAuthenticated, isFalse);
      expect(SessionState.initial.isClinicallyActive, isFalse);
    });

    test('only the active phase opens clinical surfaces', () {
      for (final SessionPhase phase in SessionPhase.values) {
        final SessionState state = SessionState(
          phase: phase,
          connectivity: ConnectivityState.online,
        );
        expect(
          state.isClinicallyActive,
          phase == SessionPhase.active,
          reason: '$phase must not open clinical surfaces unless active',
        );
      }
    });

    test('authenticated covers active, locked and awaiting authorization', () {
      const Map<SessionPhase, bool> expected = <SessionPhase, bool>{
        SessionPhase.initialising: false,
        SessionPhase.unauthenticated: false,
        SessionPhase.awaitingAuthorization: true,
        SessionPhase.active: true,
        SessionPhase.locked: true,
        SessionPhase.quarantined: false,
      };

      expected.forEach((SessionPhase phase, bool isAuthenticated) {
        final SessionState state = SessionState(
          phase: phase,
          connectivity: ConnectivityState.online,
        );
        expect(state.isAuthenticated, isAuthenticated, reason: '$phase');
      });
    });
  });

  group('SessionState authorization derivation', () {
    test('derives a policy carrying the snapshot and connectivity', () {
      final SessionState state = SessionState(
        phase: SessionPhase.active,
        connectivity: ConnectivityState.offline,
        snapshot: snapshotExpiringAt(issuedAt.add(const Duration(hours: 12))),
      );

      final AuthorizationPolicy policy = state.authorization;
      expect(policy.connectivity, ConnectivityState.offline);
      expect(policy.snapshot, isNotNull);
      expect(
        policy.can(
          NodexPermissions.vitalsRecord,
          now: issuedAt.add(const Duration(hours: 1)),
        ),
        isTrue,
      );
    });

    test('propagates an integrity failure into the policy', () {
      final SessionState state = SessionState(
        phase: SessionPhase.quarantined,
        connectivity: ConnectivityState.online,
        snapshot: snapshotExpiringAt(issuedAt.add(const Duration(hours: 12))),
        snapshotIntegrityVerified: false,
      );

      expect(state.authorization.digestVerified, isFalse);
      expect(
        state.authorization
            .evaluate(
              NodexPermissions.vitalsRecord,
              now: issuedAt.add(const Duration(hours: 1)),
            )
            .reason,
        AuthorizationDenialReason.snapshotTampered,
      );
    });

    test('reports zero remaining authorization without a snapshot', () {
      const SessionState state = SessionState(
        phase: SessionPhase.awaitingAuthorization,
        connectivity: ConnectivityState.online,
      );

      expect(state.remainingAuthorization(DateTime.now()), Duration.zero);
      expect(state.isAuthorizationExpiringSoon(DateTime.now()), isFalse);
    });
  });

  group('offline window expiry warning', () {
    test('warns inside the threshold', () {
      final SessionState state = SessionState(
        phase: SessionPhase.active,
        connectivity: ConnectivityState.offline,
        snapshot: snapshotExpiringAt(issuedAt.add(const Duration(hours: 12))),
      );

      // 20 minutes remaining against a 30-minute threshold.
      final DateTime now = issuedAt.add(const Duration(hours: 11, minutes: 40));
      expect(state.isAuthorizationExpiringSoon(now), isTrue);
      expect(state.remainingAuthorization(now), const Duration(minutes: 20));
    });

    test('does not warn well before expiry', () {
      final SessionState state = SessionState(
        phase: SessionPhase.active,
        connectivity: ConnectivityState.offline,
        snapshot: snapshotExpiringAt(issuedAt.add(const Duration(hours: 12))),
      );

      expect(
        state.isAuthorizationExpiringSoon(
          issuedAt.add(const Duration(hours: 2)),
        ),
        isFalse,
      );
    });

    test('does not warn once already expired', () {
      // Expiry is a different state with its own handling; warning about it here
      // would duplicate the awaiting-authorization message.
      final SessionState state = SessionState(
        phase: SessionPhase.active,
        connectivity: ConnectivityState.offline,
        snapshot: snapshotExpiringAt(issuedAt.add(const Duration(hours: 1))),
      );

      expect(
        state.isAuthorizationExpiringSoon(
          issuedAt.add(const Duration(hours: 2)),
        ),
        isFalse,
      );
    });

    test('honours a custom threshold', () {
      final SessionState state = SessionState(
        phase: SessionPhase.active,
        connectivity: ConnectivityState.offline,
        snapshot: snapshotExpiringAt(issuedAt.add(const Duration(hours: 12))),
      );

      final DateTime now = issuedAt.add(const Duration(hours: 10));
      expect(
        state.isAuthorizationExpiringSoon(
          now,
          threshold: const Duration(hours: 3),
        ),
        isTrue,
      );
      expect(
        state.isAuthorizationExpiringSoon(
          now,
          threshold: const Duration(minutes: 10),
        ),
        isFalse,
      );
    });
  });

  group('SessionState.copyWith', () {
    test('replaces only the supplied fields', () {
      final SessionState original = SessionState(
        phase: SessionPhase.active,
        connectivity: ConnectivityState.online,
        tenantId: 'tenant-1',
        snapshot: snapshotExpiringAt(issuedAt.add(const Duration(hours: 12))),
        pendingUploadCount: 3,
      );

      final SessionState updated = original.copyWith(
        connectivity: ConnectivityState.offline,
      );

      expect(updated.connectivity, ConnectivityState.offline);
      expect(updated.phase, SessionPhase.active);
      expect(updated.tenantId, 'tenant-1');
      expect(updated.pendingUploadCount, 3);
      expect(updated.snapshot, original.snapshot);
    });

    test('clearSnapshot drops the snapshot', () {
      final SessionState original = SessionState(
        phase: SessionPhase.active,
        connectivity: ConnectivityState.online,
        snapshot: snapshotExpiringAt(issuedAt.add(const Duration(hours: 12))),
      );

      final SessionState cleared = original.copyWith(
        phase: SessionPhase.awaitingAuthorization,
        clearSnapshot: true,
      );

      expect(cleared.snapshot, isNull);
      expect(cleared.authorization.snapshot, isNull);
    });

    test('clearUser drops the user and the tenant binding together', () {
      // Retaining a tenant id without a principal would let a subsequent refresh
      // request authorization for a tenant nobody is signed into.
      final SessionState original = SessionState(
        phase: SessionPhase.active,
        connectivity: ConnectivityState.online,
        user: const SessionUser(userId: 'user-1', fullName: 'A Clinician'),
        tenantId: 'tenant-1',
        snapshot: snapshotExpiringAt(issuedAt.add(const Duration(hours: 12))),
      );

      final SessionState cleared = original.copyWith(
        phase: SessionPhase.unauthenticated,
        clearUser: true,
      );

      expect(cleared.user, isNull);
      expect(cleared.tenantId, isNull);
    });

    test('clearMessage removes a stale message', () {
      const SessionState original = SessionState(
        phase: SessionPhase.awaitingAuthorization,
        connectivity: ConnectivityState.online,
        message: 'Refreshing authorization.',
      );

      expect(original.copyWith(clearMessage: true).message, isNull);
    });

    test('device survives a user clear so the fingerprint is retained', () {
      const SessionState original = SessionState(
        phase: SessionPhase.active,
        connectivity: ConnectivityState.online,
        device: SessionDevice(
          fingerprint: 'fp-1',
          formFactor: DeviceFormFactor.tabletCompact,
        ),
        user: SessionUser(userId: 'user-1', fullName: 'A Clinician'),
      );

      final SessionState cleared = original.copyWith(clearUser: true);
      expect(cleared.device?.fingerprint, 'fp-1');
    });
  });

  group('SessionUser', () {
    test('prefers the display name when present', () {
      const SessionUser user = SessionUser(
        userId: 'u',
        fullName: 'Abdul Karim Rahman',
        displayName: 'Dr Karim',
      );
      expect(user.preferredName, 'Dr Karim');
    });

    test('falls back to the full name', () {
      const SessionUser user = SessionUser(
        userId: 'u',
        fullName: 'Abdul Karim Rahman',
      );
      expect(user.preferredName, 'Abdul Karim Rahman');
    });

    test('falls back when the display name is empty', () {
      const SessionUser user = SessionUser(
        userId: 'u',
        fullName: 'Abdul Karim Rahman',
        displayName: '',
      );
      expect(user.preferredName, 'Abdul Karim Rahman');
    });
  });

  group('DeviceFormFactor', () {
    test('tablets use a navigation rail and phones do not', () {
      expect(DeviceFormFactor.phone.usesNavigationRail, isFalse);
      expect(DeviceFormFactor.tabletCompact.usesNavigationRail, isTrue);
      expect(DeviceFormFactor.tabletLarge.usesNavigationRail, isTrue);
    });

    test('only large tablets support a master/detail workspace', () {
      expect(DeviceFormFactor.phone.supportsMasterDetail, isFalse);
      expect(DeviceFormFactor.tabletCompact.supportsMasterDetail, isFalse);
      expect(DeviceFormFactor.tabletLarge.supportsMasterDetail, isTrue);
    });

    test('wire values are unique', () {
      final Set<String> values = DeviceFormFactor.values
          .map((DeviceFormFactor f) => f.wireValue)
          .toSet();
      expect(values.length, DeviceFormFactor.values.length);
    });
  });

  group('ConnectivityState', () {
    test('isOnline reflects the state', () {
      expect(ConnectivityState.online.isOnline, isTrue);
      expect(ConnectivityState.offline.isOnline, isFalse);
    });
  });
}
