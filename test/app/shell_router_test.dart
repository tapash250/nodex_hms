/// Widget tests for the app shell, the router's guards and the session
/// lifecycle's lock path — the three areas CONTINUE.md records as having no
/// coverage.
///
/// The router is the real [routerProvider] and the screens are the real ones,
/// with only the session overridden, so these assert on where a session actually
/// lands rather than on a reimplementation of the redirect table:
///
/// * Every session phase redirects to its canonical route, and a phase that
///   cannot reach clinical work cannot reach a clinical screen.
/// * A destination whose permissions the session lacks is neither shown in the
///   navigation nor reachable by deep link: the guard bounces to home.
/// * The shell is bottom-navigation on a phone, a rail on a tablet and an
///   extended rail on a large tablet.
/// * Locking moves the phase and the router moves with it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nodex_hms/app/router/app_router.dart';
import 'package:nodex_hms/app/router/navigation_destinations.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/authorization_snapshot.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/domain/session/session_state.dart';
import 'package:nodex_hms/features/inventory/inventory_screen.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

const Set<String> _allClinicalPermissions = <String>{
  NodexPermissions.patientRead,
  NodexPermissions.appointmentRead,
  NodexPermissions.bedAssign,
  NodexPermissions.triageRead,
  NodexPermissions.inventoryMovement,
};

AuthorizationSnapshot _snapshotFor(
  Set<String> permissions, {
  DateTime? issuedAt,
}) {
  final DateTime now = issuedAt ?? DateTime.now().toUtc();
  return AuthorizationSnapshot(
    snapshotId: 'snapshot-1',
    tenantId: 'tenant-1',
    userId: 'user-1',
    deviceId: 'device-1',
    revision: 1,
    issuedAt: now,
    expiresAt: now.add(const Duration(days: 30)),
    payloadDigest: 'digest',
    roles: const <String>{NodexRoles.medicalOfficer},
    permissions: permissions,
    offlinePermissions: permissions,
    facilityIds: const <String>{},
    departmentIds: const <String>{},
    wardIds: const <String>{},
  );
}

/// Builds a session state in [phase].
SessionState _session(
  SessionPhase phase, {
  Set<String> permissions = const <String>{},
  ConnectivityState connectivity = ConnectivityState.online,
}) {
  return SessionState(
    phase: phase,
    connectivity: connectivity,
    user: const SessionUser(userId: 'user-1', fullName: 'Dr Rivera'),
    tenantId: 'tenant-1',
    snapshot: _snapshotFor(permissions),
  );
}

/// Pumps the real router inside a scope whose session is fixed to [state].
///
/// [size] is the viewport the shell measures against, so a caller chooses the
/// form factor. When [settle] is false the pump only advances a fixed number of
/// frames, which is required for screens that animate forever: the bootstrap
/// splash and the awaiting-authorization screen both show an indeterminate
/// progress indicator, and `pumpAndSettle` would wait on it without end.
Future<(ProviderContainer, GoRouter)> pumpApp(
  WidgetTester tester,
  SessionState state, {
  Size size = const Size(1200, 2000),
  bool settle = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final ProviderContainer container = ProviderContainer(
    overrides: [
      sessionProvider.overrideWithBuild(
        (Ref ref, SessionController notifier) => state,
      ),
    ],
  );
  addTearDown(container.dispose);

  final GoRouter router = container.read(routerProvider);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(title: 'NODEX', routerConfig: router),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump();
  }
  return (container, router);
}

/// A destination label within the active navigation surface only.
///
/// The home surface also lists reachable modules by label, so an unqualified
/// text search matches twice; scoping to the rail or bar keeps the assertion
/// about navigation rather than about home's catalogue.
Finder navLabel(WidgetTester tester, String label) => find.descendant(
  of: find.byType(NavigationRail),
  matching: find.text(label),
);

void main() {
  group('the router sends each session phase to its canonical screen', () {
    testWidgets('initialising keeps the bootstrap splash', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester, _session(SessionPhase.initialising), settle: false);
      expect(find.text('Preparing secure clinical workspace'), findsOneWidget);
    });

    testWidgets('unauthenticated shows credential entry, not a workspace', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester, _session(SessionPhase.unauthenticated));
      expect(find.text('Work email'), findsOneWidget);
      // The shell belongs to the authorized surface and must not appear.
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(NavigationRail), findsNothing);
    });

    testWidgets('awaiting authorization keeps clinical surfaces closed', (
      WidgetTester tester,
    ) async {
      await pumpApp(
        tester,
        _session(SessionPhase.awaitingAuthorization),
        settle: false,
      );
      expect(find.text('Establishing authorization'), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
    });

    testWidgets('a locked session is held on the lock screen', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester, _session(SessionPhase.locked));
      expect(find.text('Session locked'), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
    });

    testWidgets('a quarantined session explains the security fault', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester, _session(SessionPhase.quarantined));
      expect(find.text('Security verification failed'), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
    });
  });

  group('the navigation surface holds only reachable destinations', () {
    testWidgets('a destination is listed only when its permission is held', (
      WidgetTester tester,
    ) async {
      await pumpApp(
        tester,
        _session(
          SessionPhase.active,
          permissions: const <String>{NodexPermissions.bedAssign},
        ),
      );

      // Home needs no permission and is always reachable.
      expect(navLabel(tester, 'Home'), findsOneWidget);
      // Wards is reachable through bed.assign; inventory is not.
      expect(navLabel(tester, 'Wards'), findsOneWidget);
      expect(navLabel(tester, 'Inventory'), findsNothing);
    });

    testWidgets('every permission a session holds adds its destination', (
      WidgetTester tester,
    ) async {
      await pumpApp(
        tester,
        _session(SessionPhase.active, permissions: _allClinicalPermissions),
      );

      expect(navLabel(tester, 'Wards'), findsOneWidget);
      expect(navLabel(tester, 'Inventory'), findsOneWidget);
    });
  });

  group('the router guards a destination the session cannot reach', () {
    testWidgets('a deep link to an unreachable destination bounces to home', (
      WidgetTester tester,
    ) async {
      final (ProviderContainer container, GoRouter router) = await pumpApp(
        tester,
        _session(
          SessionPhase.active,
          permissions: const <String>{NodexPermissions.bedAssign},
        ),
      );
      addTearDown(container.dispose);

      router.go(NodexDestinations.inventory.routePath);
      await tester.pumpAndSettle();

      // The guard refuses to show the screen and lands on home instead.
      expect(find.byType(InventoryScreen), findsNothing);
      expect(find.text('NODEX'), findsOneWidget);
    });

    testWidgets('the same destination is reachable once permitted', (
      WidgetTester tester,
    ) async {
      final (ProviderContainer container, GoRouter router) = await pumpApp(
        tester,
        _session(
          SessionPhase.active,
          permissions: const <String>{NodexPermissions.inventoryMovement},
        ),
      );
      addTearDown(container.dispose);

      router.go(NodexDestinations.inventory.routePath);
      await tester.pumpAndSettle();

      expect(find.byType(InventoryScreen), findsOneWidget);
    });
  });

  group('the shell adapts to the device form factor', () {
    testWidgets('a phone uses bottom navigation', (WidgetTester tester) async {
      await pumpApp(
        tester,
        _session(SessionPhase.active, permissions: _allClinicalPermissions),
        size: const Size(400, 800),
      );
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
    });

    testWidgets('a compact tablet uses a rail', (WidgetTester tester) async {
      await pumpApp(
        tester,
        _session(SessionPhase.active, permissions: _allClinicalPermissions),
        size: const Size(800, 1200),
      );
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(
        tester.widget<NavigationRail>(find.byType(NavigationRail)).extended,
        isFalse,
      );
    });

    testWidgets('a large tablet extends the rail', (WidgetTester tester) async {
      await pumpApp(
        tester,
        _session(SessionPhase.active, permissions: _allClinicalPermissions),
        size: const Size(1400, 1000),
      );
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(
        tester.widget<NavigationRail>(find.byType(NavigationRail)).extended,
        isTrue,
      );
    });
  });

  group('the session lifecycle and the shell stay in step', () {
    testWidgets('locking a live session moves to the lock screen', (
      WidgetTester tester,
    ) async {
      final (ProviderContainer container, GoRouter router) = await pumpApp(
        tester,
        _session(SessionPhase.active, permissions: _allClinicalPermissions),
      );

      expect(find.text('NODEX'), findsOneWidget);

      container.read(sessionProvider.notifier).lock();
      await tester.pumpAndSettle();

      expect(find.text('Session locked'), findsOneWidget);
      // The workspace content is no longer on screen.
      expect(find.text('NODEX'), findsNothing);
    });

    testWidgets('locking from the home action reaches the lock screen', (
      WidgetTester tester,
    ) async {
      await pumpApp(
        tester,
        _session(SessionPhase.active, permissions: _allClinicalPermissions),
      );

      // The lock action in the app bar drives the same controller method.
      await tester.tap(find.byIcon(Icons.lock_outline));
      await tester.pumpAndSettle();

      expect(find.text('Session locked'), findsOneWidget);
    });
  });
}
