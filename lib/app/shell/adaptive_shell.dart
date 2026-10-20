/// Material 3 adaptive navigation shell.
///
/// Implements the specification's navigation behaviour by form factor:
///
/// * Phone: bottom navigation.
/// * Compact tablet: navigation rail.
/// * Large tablet: extended navigation rail, leaving room for a master/detail
///   workspace inside the destination itself.
///
/// The shell also carries the two pieces of status a clinician needs visible at
/// all times: connectivity/sync state, and how much offline authorization remains.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nodex_hms/app/adaptive/adaptive_breaks.dart';
import 'package:nodex_hms/app/router/navigation_destinations.dart';
import 'package:nodex_hms/app/shell/session_status_bar.dart';
import 'package:nodex_hms/core/security/inactivity_lock.dart';
import 'package:nodex_hms/domain/session/session_state.dart';
import 'package:nodex_hms/features/search/global_search_screen.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// Adaptive navigation scaffold wrapping every authorized destination.
class AdaptiveShell extends ConsumerWidget {
  /// Creates the shell around [child].
  const AdaptiveShell({required this.child, super.key});

  /// The active destination's content.
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SessionState session = ref.watch(sessionProvider);
    final List<NavigationDestinationSpec> destinations =
        NodexDestinations.visibleTo(session.authorization, primaryOnly: true);

    if (destinations.isEmpty) {
      // A session with no visible destination is a misconfiguration rather than a
      // normal state; say so plainly instead of rendering an empty rail.
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'This account has no accessible modules in the current tenant. '
              'Contact your administrator to review role assignments.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ),
      );
    }

    // The device locks itself when it is left alone: a trolley with a patient
    // list on it is a privacy incident waiting for a passer-by.
    final Widget guarded = _SearchShortcuts(
      child: InactivityGuard(
        onTimeout: () => ref.read(sessionProvider.notifier).lock(),
        child: child,
      ),
    );

    final String location = GoRouterState.of(context).matchedLocation;
    final int selectedIndex = _selectedIndex(destinations, location);
    final double width = MediaQuery.sizeOf(context).width;

    if (width < NodexBreakpoints.compact) {
      return _PhoneLayout(
        destinations: destinations,
        selectedIndex: selectedIndex,
        child: guarded,
      );
    }

    return _TabletLayout(
      destinations: destinations,
      selectedIndex: selectedIndex,
      extended: width >= NodexBreakpoints.expanded,
      child: guarded,
    );
  }

  static int _selectedIndex(
    List<NavigationDestinationSpec> destinations,
    String location,
  ) {
    for (int i = 0; i < destinations.length; i++) {
      final String path = destinations[i].routePath;
      if (location == path || location.startsWith('$path/')) {
        return i;
      }
    }
    return 0;
  }
}

class _PhoneLayout extends StatelessWidget {
  const _PhoneLayout({
    required this.destinations,
    required this.selectedIndex,
    required this.child,
  });

  final List<NavigationDestinationSpec> destinations;
  final int selectedIndex;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: <Widget>[
        const SessionStatusBar(),
        Expanded(child: child),
      ],
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: (int index) =>
          context.go(destinations[index].routePath),
      destinations: destinations
          .map(
            (NavigationDestinationSpec spec) => NavigationDestination(
              icon: Icon(spec.icon),
              selectedIcon: Icon(spec.selectedIcon),
              label: spec.label,
              tooltip: spec.label,
            ),
          )
          .toList(growable: false),
    ),
  );
}

class _TabletLayout extends StatelessWidget {
  const _TabletLayout({
    required this.destinations,
    required this.selectedIndex,
    required this.extended,
    required this.child,
  });

  final List<NavigationDestinationSpec> destinations;
  final int selectedIndex;
  final bool extended;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Row(
      children: <Widget>[
        NavigationRail(
          extended: extended,
          selectedIndex: selectedIndex,
          labelType: extended
              ? NavigationRailLabelType.none
              : NavigationRailLabelType.all,
          onDestinationSelected: (int index) =>
              context.go(destinations[index].routePath),
          destinations: destinations
              .map(
                (NavigationDestinationSpec spec) => NavigationRailDestination(
                  icon: Icon(spec.icon),
                  selectedIcon: Icon(spec.selectedIcon),
                  label: Text(spec.label),
                ),
              )
              .toList(growable: false),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: Column(
            children: <Widget>[
              const SessionStatusBar(),
              Expanded(child: child),
            ],
          ),
        ),
      ],
    ),
  );
}

/// The global search, on a hotkey.
///
/// Control-K, Command-K and "/" all open the same search. The shortcut sits
/// above the screens, so it works from anywhere in the application, and a
/// text field that holds the focus keeps its own keys: a clinician typing a
/// slash into a note does not leave the note.
class _SearchShortcuts extends StatelessWidget {
  const _SearchShortcuts({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Focus(
    autofocus: true,
    child: CallbackShortcuts(
      bindings: GlobalSearchShortcuts.bindings(
        onOpen: () => context.go('/search'),
      ),
      child: child,
    ),
  );
}
