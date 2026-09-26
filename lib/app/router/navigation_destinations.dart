/// Role-aware navigation destinations.
///
/// A destination is visible only when the session holds at least one of its
/// permissions. This is presentation filtering, not authorization: the server
/// remains the boundary. Hiding a destination the user cannot use prevents a
/// clinician discovering a permission gap by tapping into a dead end mid-shift.
library;

import 'package:flutter/material.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';

/// A navigable area of the application.
@immutable
final class NavigationDestinationSpec {
  /// Declares a destination.
  const NavigationDestinationSpec({
    required this.routePath,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.requiredPermissions,
    required this.moduleCode,
    this.availableOffline = true,
    this.isPrimary = true,
  });

  /// GoRouter path.
  final String routePath;

  /// Label shown in navigation surfaces.
  final String label;

  /// Unselected icon.
  final IconData icon;

  /// Selected icon.
  final IconData selectedIcon;

  /// Any one of these permissions makes the destination visible.
  final Set<String> requiredPermissions;

  /// Specification module code, for traceability.
  final String moduleCode;

  /// Whether the destination functions without connectivity.
  final bool availableOffline;

  /// Whether the destination appears in the primary navigation surface.
  ///
  /// Non-primary destinations are reachable from within other screens; showing
  /// every module in a bottom bar would be unusable on a phone.
  final bool isPrimary;

  /// Whether [policy] permits at least one of [requiredPermissions].
  ///
  /// An empty permission set means universally visible, which applies to the
  /// signed-in user's own profile and to operational utility pages.
  bool isVisibleTo(AuthorizationPolicy policy) {
    if (requiredPermissions.isEmpty) {
      return true;
    }
    return policy.canAny(requiredPermissions);
  }
}

/// The Phase 1 destination catalogue.
///
/// Phase 1 ships the shell plus the surfaces the foundation itself requires:
/// a role-aware home, sync diagnostics, AI governance and settings. Clinical
/// modules register their destinations as they land in later phases.
abstract final class NodexDestinations {
  /// Role-aware landing surface.
  static const NavigationDestinationSpec home = NavigationDestinationSpec(
    routePath: '/home',
    label: 'Home',
    icon: Icons.dashboard_outlined,
    selectedIcon: Icons.dashboard,
    requiredPermissions: <String>{},
    moduleCode: 'M01',
  );

  /// Patient index. Phase 2 supplies the implementation.
  static const NavigationDestinationSpec patients = NavigationDestinationSpec(
    routePath: '/patients',
    label: 'Patients',
    icon: Icons.people_outline,
    selectedIcon: Icons.people,
    requiredPermissions: <String>{NodexPermissions.patientRead},
    moduleCode: 'M10',
  );

  /// Appointment calendar. Phase 2 supplies the implementation.
  static const NavigationDestinationSpec appointments =
      NavigationDestinationSpec(
        routePath: '/appointments',
        label: 'Appointments',
        icon: Icons.event_outlined,
        selectedIcon: Icons.event,
        requiredPermissions: <String>{NodexPermissions.appointmentRead},
        moduleCode: 'M07',
      );

  /// Ward census board. Phase 2 supplies the implementation.
  static const NavigationDestinationSpec wards = NavigationDestinationSpec(
    routePath: '/wards',
    label: 'Wards',
    icon: Icons.single_bed_outlined,
    selectedIcon: Icons.single_bed,
    requiredPermissions: <String>{NodexPermissions.bedAssign},
    moduleCode: 'M11',
  );

  /// Emergency Department triage and open visits.
  static const NavigationDestinationSpec er = NavigationDestinationSpec(
    routePath: '/er',
    label: 'Emergency',
    icon: Icons.emergency_outlined,
    selectedIcon: Icons.emergency,
    requiredPermissions: <String>{
      NodexPermissions.triageRead,
      NodexPermissions.erVisitWrite,
    },
    moduleCode: 'M05',
  );

  /// ICU bed census and critical-care documentation.
  static const NavigationDestinationSpec icu = NavigationDestinationSpec(
    routePath: '/icu',
    label: 'ICU',
    icon: Icons.monitor_heart_outlined,
    selectedIcon: Icons.monitor_heart,
    requiredPermissions: <String>{
      NodexPermissions.icuBedAssign,
      NodexPermissions.icuVitalsRecord,
    },
    moduleCode: 'M06',
    isPrimary: false,
  );

  /// Blood bank inventory and transfusion workflow.
  static const NavigationDestinationSpec bloodBank = NavigationDestinationSpec(
    routePath: '/blood-bank',
    label: 'Blood bank',
    icon: Icons.bloodtype_outlined,
    selectedIcon: Icons.bloodtype,
    requiredPermissions: <String>{
      NodexPermissions.transfusionRequest,
      NodexPermissions.bloodUnitWrite,
      NodexPermissions.transfusionAdminister,
    },
    moduleCode: 'M26',
    isPrimary: false,
  );

  /// Operation theatre scheduling and case documentation.
  static const NavigationDestinationSpec ot = NavigationDestinationSpec(
    routePath: '/ot',
    label: 'Theatre',
    icon: Icons.content_cut_outlined,
    selectedIcon: Icons.content_cut,
    requiredPermissions: <String>{
      NodexPermissions.otSchedule,
      NodexPermissions.otRecord,
      NodexPermissions.otFinalize,
    },
    moduleCode: 'M19',
    isPrimary: false,
  );

  /// Inventory management. Phase 2 supplies the implementation.
  static const NavigationDestinationSpec inventory = NavigationDestinationSpec(
    routePath: '/inventory',
    label: 'Inventory',
    icon: Icons.inventory_2_outlined,
    selectedIcon: Icons.inventory_2,
    requiredPermissions: <String>{NodexPermissions.inventoryMovement},
    moduleCode: 'M13',
  );

  /// Synchronization diagnostics: queue depth, retries, conflicts, failures.
  static const NavigationDestinationSpec syncDiagnostics =
      NavigationDestinationSpec(
        routePath: '/diagnostics',
        label: 'Sync',
        icon: Icons.sync_outlined,
        selectedIcon: Icons.sync,
        requiredPermissions: <String>{},
        moduleCode: 'M53',
      );

  /// AI governance: model lifecycle, routing, safety decisions, reviews.
  static const NavigationDestinationSpec aiGovernance =
      NavigationDestinationSpec(
        routePath: '/ai-governance',
        label: 'AI',
        icon: Icons.psychology_outlined,
        selectedIcon: Icons.psychology,
        requiredPermissions: <String>{NodexPermissions.aiGovernanceRead},
        moduleCode: 'M39',
      );

  /// Audit trail inspection.
  static const NavigationDestinationSpec audit = NavigationDestinationSpec(
    routePath: '/audit',
    label: 'Audit',
    icon: Icons.fact_check_outlined,
    selectedIcon: Icons.fact_check,
    requiredPermissions: <String>{NodexPermissions.auditRead},
    moduleCode: 'M35',
    isPrimary: false,
  );

  /// Settings and configuration.
  static const NavigationDestinationSpec settings = NavigationDestinationSpec(
    routePath: '/settings',
    label: 'Settings',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
    requiredPermissions: <String>{},
    moduleCode: 'M39',
    isPrimary: false,
  );

  /// Every declared destination in navigation order.
  static const List<NavigationDestinationSpec> all =
      <NavigationDestinationSpec>[
        home,
        patients,
        appointments,
        wards,
        er,
        icu,
        bloodBank,
        ot,
        inventory,
        syncDiagnostics,
        aiGovernance,
        audit,
        settings,
      ];

  /// Destinations visible to [policy], in navigation order.
  static List<NavigationDestinationSpec> visibleTo(
    AuthorizationPolicy policy, {
    bool primaryOnly = false,
  }) => all
      .where(
        (NavigationDestinationSpec spec) =>
            spec.isVisibleTo(policy) && (!primaryOnly || spec.isPrimary),
      )
      .toList(growable: false);
}
