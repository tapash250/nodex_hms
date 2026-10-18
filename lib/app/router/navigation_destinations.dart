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
    moduleCode: 'M14',
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
    moduleCode: 'M15',
    isPrimary: false,
  );

  /// Nurse ward station: observations, handover and the task board.
  static const NavigationDestinationSpec wardStation =
      NavigationDestinationSpec(
        routePath: '/ward-station',
        label: 'Ward station',
        icon: Icons.assignment_outlined,
        selectedIcon: Icons.assignment,
        requiredPermissions: <String>{NodexPermissions.nursingStationRead},
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

  /// Doctor & specialist directory (Module 08).
  static const NavigationDestinationSpec staffDirectory =
      NavigationDestinationSpec(
        routePath: '/staff-directory',
        label: 'Staff directory',
        icon: Icons.medical_services_outlined,
        selectedIcon: Icons.medical_services,
        requiredPermissions: <String>{NodexPermissions.staffDirectoryRead},
        moduleCode: 'M08',
        isPrimary: false,
      );

  /// Clinical departments registry (Module 12).
  static const NavigationDestinationSpec departments =
      NavigationDestinationSpec(
        routePath: '/departments',
        label: 'Departments',
        icon: Icons.account_tree_outlined,
        selectedIcon: Icons.account_tree,
        requiredPermissions: <String>{NodexPermissions.departmentAdminister},
        moduleCode: 'M12',
        isPrimary: false,
      );

  /// Allied staff & workforce rosters (Module 09).
  static const NavigationDestinationSpec workforce = NavigationDestinationSpec(
    routePath: '/workforce',
    label: 'Workforce',
    icon: Icons.groups_outlined,
    selectedIcon: Icons.groups,
    requiredPermissions: <String>{NodexPermissions.workforceRead},
    moduleCode: 'M09',
    isPrimary: false,
  );

  /// Hospital contacts directory (Module 42).
  static const NavigationDestinationSpec contacts = NavigationDestinationSpec(
    routePath: '/contacts',
    label: 'Contacts',
    icon: Icons.contact_phone_outlined,
    selectedIcon: Icons.contact_phone,
    requiredPermissions: <String>{NodexPermissions.contactsRead},
    moduleCode: 'M42',
    isPrimary: false,
  );

  /// Institutional calendar and shift overlay (Module 40).
  static const NavigationDestinationSpec calendar = NavigationDestinationSpec(
    routePath: '/calendar',
    label: 'Calendar',
    icon: Icons.calendar_month_outlined,
    selectedIcon: Icons.calendar_month,
    requiredPermissions: <String>{NodexPermissions.calendarRead},
    moduleCode: 'M40',
    isPrimary: false,
  );

  /// Fleet & ambulance dispatch (Module 27).
  static const NavigationDestinationSpec fleet = NavigationDestinationSpec(
    routePath: '/fleet',
    label: 'Fleet',
    icon: Icons.airport_shuttle_outlined,
    selectedIcon: Icons.airport_shuttle,
    requiredPermissions: <String>{NodexPermissions.fleetRead},
    moduleCode: 'M27',
    isPrimary: false,
  );

  /// Biomedical assets & calibration (Module 29).
  static const NavigationDestinationSpec biomedical = NavigationDestinationSpec(
    routePath: '/biomedical',
    label: 'Biomedical',
    icon: Icons.precision_manufacturing_outlined,
    selectedIcon: Icons.precision_manufacturing,
    requiredPermissions: <String>{NodexPermissions.biomedicalRead},
    moduleCode: 'M29',
    isPrimary: false,
  );

  /// Bio-medical waste management (Module 30).
  static const NavigationDestinationSpec waste = NavigationDestinationSpec(
    routePath: '/waste',
    label: 'Waste',
    icon: Icons.delete_sweep_outlined,
    selectedIcon: Icons.delete_sweep,
    requiredPermissions: <String>{NodexPermissions.wasteRead},
    moduleCode: 'M30',
    isPrimary: false,
  );

  /// Health insurance & TPA (Module 32).
  static const NavigationDestinationSpec insurance = NavigationDestinationSpec(
    routePath: '/insurance',
    label: 'Insurance',
    icon: Icons.health_and_safety_outlined,
    selectedIcon: Icons.health_and_safety,
    requiredPermissions: <String>{NodexPermissions.insuranceRead},
    moduleCode: 'M32',
    isPrimary: false,
  );

  /// Documents & biometric e-consent vault (Module 33).
  static const NavigationDestinationSpec consents = NavigationDestinationSpec(
    routePath: '/consents',
    label: 'Consents',
    icon: Icons.draw_outlined,
    selectedIcon: Icons.draw,
    requiredPermissions: <String>{NodexPermissions.documentsRead},
    moduleCode: 'M33',
    isPrimary: false,
  );

  /// Human resources & payroll suite (Module 13).
  static const NavigationDestinationSpec humanResources =
      NavigationDestinationSpec(
        routePath: '/hr',
        label: 'HR & payroll',
        icon: Icons.badge_outlined,
        selectedIcon: Icons.badge,
        requiredPermissions: <String>{
          NodexPermissions.hrRead,
          NodexPermissions.payrollRead,
        },
        moduleCode: 'M13',
        isPrimary: false,
      );

  /// Hospital floor map: rooms, capacity and live patient locations.
  static const NavigationDestinationSpec floorMap = NavigationDestinationSpec(
    routePath: '/floor-map',
    label: 'Floor map',
    icon: Icons.grid_view_outlined,
    selectedIcon: Icons.grid_view,
    requiredPermissions: <String>{NodexPermissions.wardFloorRead},
    moduleCode: 'M24',
    isPrimary: false,
  );

  /// Inventory management. Phase 2 supplies the implementation.
  static const NavigationDestinationSpec inventory = NavigationDestinationSpec(
    routePath: '/inventory',
    label: 'Inventory',
    icon: Icons.inventory_2_outlined,
    selectedIcon: Icons.inventory_2,
    requiredPermissions: <String>{NodexPermissions.inventoryMovement},
    moduleCode: 'M28',
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
        wardStation,
        bloodBank,
        ot,
        floorMap,
        staffDirectory,
        departments,
        workforce,
        humanResources,
        contacts,
        calendar,
        fleet,
        biomedical,
        waste,
        insurance,
        consents,
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
