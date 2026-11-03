/// Session lifecycle tests: cached-snapshot binding, lock persistence and
/// fail-closed sign-out.
///
/// These exercise the controller against a fake repository and a fake local
/// database, so no platform channel, PowerSync instance or Supabase project is
/// required. The point is the decision, not the transport.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/authorization/authorization_snapshot.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/security/database_key_manager.dart';
import 'package:nodex_hms/core/security/secure_key_store.dart';
import 'package:nodex_hms/data/local/local_database.dart';
import 'package:nodex_hms/domain/session/session_repository.dart';
import 'package:nodex_hms/domain/session/session_state.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

final NodexLogger _logger = NodexLogger(sinks: <NodexLogSink>[]);

const SessionDevice _device = SessionDevice(
  fingerprint: 'manufacturer:model:serial',
  formFactor: DeviceFormFactor.phone,
  deviceId: 'device-1',
  appVersion: '0.1.0+1',
  osVersion: 'Android 14',
);

AuthorizationSnapshot _snapshot({
  String userId = 'user-1',
  String deviceId = 'device-1',
}) {
  final DateTime now = DateTime.now().toUtc();
  return AuthorizationSnapshot(
    snapshotId: 'snapshot-1',
    tenantId: 'tenant-1',
    userId: userId,
    deviceId: deviceId,
    revision: 1,
    issuedAt: now.subtract(const Duration(minutes: 1)),
    expiresAt: now.add(const Duration(days: 1)),
    payloadDigest: 'digest',
    roles: const <String>{'medical_officer'},
    permissions: const <String>{'patient.read'},
    offlinePermissions: const <String>{'patient.read'},
    facilityIds: const <String>{},
    departmentIds: const <String>{},
    wardIds: const <String>{},
  );
}

final class _FakeSessionRepository implements SessionRepository {
  _FakeSessionRepository({this.cached, this.locked = false});

  AuthorizationSnapshot? cached;
  bool locked;
  bool has = true;
  int clearCalls = 0;
  int signOutCalls = 0;
  String? seenUserId;
  String? seenDeviceFingerprint;
  bool? lockedWrite;

  @override
  Future<String> signIn({
    required String email,
    required String password,
  }) async => 'user-1';

  @override
  Future<void> signOut() async {
    signOutCalls++;
    locked = false;
  }

  @override
  Future<void> requestPasswordReset(String email) async {}

  @override
  bool hasSession() => has;

  @override
  String? currentUserId() => has ? 'user-1' : null;

  @override
  Future<bool> isLocked() async => locked;

  @override
  Future<void> setLocked({required bool locked}) async {
    this.locked = locked;
    lockedWrite = locked;
  }

  @override
  Future<AuthorizationSnapshot> refreshAuthorization({
    required String tenantId,
    required SessionDevice device,
  }) async => cached ?? _snapshot();

  @override
  Future<AuthorizationSnapshot?> cachedAuthorization({
    String? userId,
    String? deviceFingerprint,
  }) async {
    seenUserId = userId;
    seenDeviceFingerprint = deviceFingerprint;
    final AuthorizationSnapshot? value = cached;
    if (value == null) {
      return null;
    }
    if (userId != null && value.userId != userId) {
      return null;
    }
    if (deviceFingerprint != null && deviceFingerprint != _device.fingerprint) {
      return null;
    }
    return value;
  }

  @override
  Future<void> clearCachedAuthorization() async {
    clearCalls++;
    cached = null;
  }
}

final class _FakeLocalDatabase extends LocalDatabase {
  _FakeLocalDatabase({this.pending = 0, this.clearFailure})
    : super(
        keyManager: DatabaseKeyManager(
          keyStore: InMemorySecureKeyStore(),
          logger: _logger,
        ),
        logger: _logger,
      );

  int pending;
  PersistenceError? clearFailure;
  bool? forced;
  int clearCalls = 0;

  @override
  bool get isOpen => true;

  @override
  Future<int> pendingMutationCount() async => pending;

  @override
  Future<void> signOutAndClear({bool force = false}) async {
    clearCalls++;
    forced = force;
    final PersistenceError? failure = clearFailure;
    if (failure != null) {
      throw failure;
    }
  }
}

ProviderContainer _container({
  required _FakeSessionRepository repository,
  required _FakeLocalDatabase database,
}) {
  final ProviderContainer container = ProviderContainer(
    overrides: [
      sessionRepositoryProvider.overrideWithValue(repository),
      localDatabaseProvider.overrideWithValue(database),
      loggerProvider.overrideWithValue(_logger),
      sessionDeviceProvider.overrideWithValue(_device),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('cached authorization binding', () {
    test('hydrates a snapshot bound to the current user and device', () async {
      final _FakeSessionRepository repository = _FakeSessionRepository(
        cached: _snapshot(),
      );
      final _FakeLocalDatabase database = _FakeLocalDatabase();
      final ProviderContainer container = _container(
        repository: repository,
        database: database,
      );

      await container.read(sessionProvider.notifier).restoreSession();

      final SessionState state = container.read(sessionProvider);
      expect(state.phase, SessionPhase.active);
      expect(state.snapshot?.userId, 'user-1');
      expect(repository.seenUserId, 'user-1');
      expect(repository.seenDeviceFingerprint, _device.fingerprint);
    });

    test('a snapshot for another principal is not hydrated', () async {
      final _FakeSessionRepository repository = _FakeSessionRepository(
        cached: _snapshot(userId: 'user-2'),
      );
      final _FakeLocalDatabase database = _FakeLocalDatabase();
      final ProviderContainer container = _container(
        repository: repository,
        database: database,
      );

      await container.read(sessionProvider.notifier).restoreSession();

      expect(
        container.read(sessionProvider).phase,
        SessionPhase.awaitingAuthorization,
      );
      expect(container.read(sessionProvider).snapshot, isNull);
    });

    test('a snapshot bound to another device is rejected', () {
      final AuthorizationSnapshot snapshot = _snapshot();
      expect(
        cachedSnapshotIsBound(
          snapshot: snapshot,
          userId: 'user-1',
          deviceFingerprint: _device.fingerprint,
          boundDeviceId: snapshot.deviceId,
          boundFingerprint: 'another-device',
        ),
        isFalse,
      );
      expect(
        cachedSnapshotIsBound(
          snapshot: snapshot,
          userId: 'user-1',
          deviceFingerprint: _device.fingerprint,
          boundDeviceId: snapshot.deviceId,
          boundFingerprint: _device.fingerprint,
        ),
        isTrue,
      );
      // No binding at all fails closed.
      expect(
        cachedSnapshotIsBound(
          snapshot: snapshot,
          userId: 'user-1',
          deviceFingerprint: _device.fingerprint,
          boundDeviceId: null,
          boundFingerprint: null,
        ),
        isFalse,
      );
    });

    test(
      'sign-in clears the previous snapshot before authenticating',
      () async {
        final _FakeSessionRepository repository = _FakeSessionRepository(
          cached: _snapshot(userId: 'user-2'),
        );
        final _FakeLocalDatabase database = _FakeLocalDatabase();
        final ProviderContainer container = _container(
          repository: repository,
          database: database,
        );

        await container
            .read(sessionProvider.notifier)
            .signIn(
              email: 'clinician@example.test',
              password: 'secret',
              tenantId: 'tenant-1',
            );

        expect(repository.clearCalls, greaterThanOrEqualTo(1));
        expect(repository.cached, isNull);
      },
    );
  });

  group('lock persistence', () {
    test('a session locked before a restart stays locked', () async {
      final _FakeSessionRepository repository = _FakeSessionRepository(
        cached: _snapshot(),
        locked: true,
      );
      final ProviderContainer container = _container(
        repository: repository,
        database: _FakeLocalDatabase(),
      );

      await container.read(sessionProvider.notifier).restoreSession();

      final SessionState state = container.read(sessionProvider);
      expect(state.phase, SessionPhase.locked);
      expect(state.snapshot, isNotNull);
    });

    test('locking persists and unlocking clears the flag', () async {
      final _FakeSessionRepository repository = _FakeSessionRepository(
        cached: _snapshot(),
      );
      final ProviderContainer container = _container(
        repository: repository,
        database: _FakeLocalDatabase(),
      );

      final SessionController controller = container.read(
        sessionProvider.notifier,
      );
      await controller.restoreSession();
      await controller.lock();

      expect(container.read(sessionProvider).phase, SessionPhase.locked);
      expect(repository.locked, isTrue);
      expect(repository.lockedWrite, isTrue);

      await controller.unlock();

      expect(container.read(sessionProvider).phase, SessionPhase.active);
      expect(repository.locked, isFalse);
    });
  });

  group('fail-closed sign-out', () {
    test('queued mutations block the standard sign-out', () async {
      final _FakeSessionRepository repository = _FakeSessionRepository(
        cached: _snapshot(),
      );
      final _FakeLocalDatabase database = _FakeLocalDatabase(pending: 3);
      final ProviderContainer container = _container(
        repository: repository,
        database: database,
      );
      final SessionController controller = container.read(
        sessionProvider.notifier,
      );
      await controller.restoreSession();

      await controller.signOut();

      final SessionState state = container.read(sessionProvider);
      expect(state.phase, SessionPhase.active);
      expect(state.message, contains('3 unsynchronized'));
      expect(database.clearCalls, 0);
      expect(repository.signOutCalls, 0);
    });

    test('a forced sign-out discards the queue and signs out', () async {
      final _FakeSessionRepository repository = _FakeSessionRepository(
        cached: _snapshot(),
      );
      final _FakeLocalDatabase database = _FakeLocalDatabase(pending: 3);
      final ProviderContainer container = _container(
        repository: repository,
        database: database,
      );
      final SessionController controller = container.read(
        sessionProvider.notifier,
      );
      await controller.restoreSession();

      await controller.signOut(force: true);

      expect(database.forced, isTrue);
      expect(repository.signOutCalls, 1);
      expect(
        container.read(sessionProvider).phase,
        SessionPhase.unauthenticated,
      );
    });

    test('a local clear failure leaves the session signed in', () async {
      final _FakeSessionRepository repository = _FakeSessionRepository(
        cached: _snapshot(),
      );
      final _FakeLocalDatabase database = _FakeLocalDatabase(
        clearFailure: const PersistenceError(
          message: 'disk unavailable',
          code: 'database_clear_failed',
        ),
      );
      final ProviderContainer container = _container(
        repository: repository,
        database: database,
      );
      final SessionController controller = container.read(
        sessionProvider.notifier,
      );
      await controller.restoreSession();

      await controller.signOut();

      final SessionState state = container.read(sessionProvider);
      expect(state.phase, SessionPhase.active);
      expect(state.message, contains('could not be cleared'));
      expect(repository.signOutCalls, 0);
    });
  });
}
