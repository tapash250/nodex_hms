/// GoRouter configuration with session-phase and permission guards.
///
/// Route guards are the Tier 1 client control: they shape navigation so a user is
/// never dropped into a surface they cannot use. They are not the authorization
/// boundary — PostgreSQL RLS and the backend mutation path are — and this file
/// never assumes otherwise.
///
/// Redirects are driven by [SessionPhase], which keeps the reachable surface and
/// the session lifecycle in one correspondence rather than scattering `if (signed
/// in)` checks across screens.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nodex_hms/app/router/navigation_destinations.dart';
import 'package:nodex_hms/app/shell/adaptive_shell.dart';
import 'package:nodex_hms/domain/session/session_state.dart';
import 'package:nodex_hms/features/ai_governance/ai_governance_screen.dart';
import 'package:nodex_hms/features/appointments/appointment_detail_screen.dart';
import 'package:nodex_hms/features/appointments/appointment_schedule_screen.dart';
import 'package:nodex_hms/features/audit/audit_screen.dart';
import 'package:nodex_hms/features/auth/sign_in_screen.dart';
import 'package:nodex_hms/features/beds/ward_census_screen.dart';
import 'package:nodex_hms/features/billing/invoice_detail_screen.dart';
import 'package:nodex_hms/features/blood_bank/blood_bank_list_screen.dart';
import 'package:nodex_hms/features/blood_bank/blood_unit_detail_screen.dart';
import 'package:nodex_hms/features/blood_bank/transfusion_request_detail_screen.dart';
import 'package:nodex_hms/features/diagnostics/sync_diagnostics_screen.dart';
import 'package:nodex_hms/features/discharge/discharge_detail_screen.dart';
import 'package:nodex_hms/features/encounters/encounter_editor_screen.dart';
import 'package:nodex_hms/features/er/er_list_screen.dart';
import 'package:nodex_hms/features/er/er_visit_detail_screen.dart';
import 'package:nodex_hms/features/er/triage_detail_screen.dart';
import 'package:nodex_hms/features/er/triage_intake_screen.dart';
import 'package:nodex_hms/features/home/home_screen.dart';
import 'package:nodex_hms/features/icu/icu_bed_detail_screen.dart';
import 'package:nodex_hms/features/icu/icu_list_screen.dart';
import 'package:nodex_hms/features/inventory/inventory_screen.dart';
import 'package:nodex_hms/features/laboratory/lab_order_screen.dart';
import 'package:nodex_hms/features/nutrition/nutrition_meal_plan_screen.dart';
import 'package:nodex_hms/features/ot/ot_booking_detail_screen.dart';
import 'package:nodex_hms/features/ot/ot_list_screen.dart';
import 'package:nodex_hms/features/patients/patient_detail_screen.dart';
import 'package:nodex_hms/features/patients/patient_search_screen.dart';
import 'package:nodex_hms/features/physio/physio_session_screen.dart';
import 'package:nodex_hms/features/prescriptions/prescription_detail_screen.dart';
import 'package:nodex_hms/features/radiology/radiology_order_screen.dart';
import 'package:nodex_hms/features/session/session_controller.dart';
import 'package:nodex_hms/features/session/session_lock_screen.dart';
import 'package:nodex_hms/features/settings/settings_screen.dart';
import 'package:nodex_hms/features/telemedicine/telemedicine_consultation_screen.dart';

/// Route paths that do not require an authorized session.
abstract final class NodexRoutes {
  /// Bootstrap splash.
  static const String splash = '/';

  /// Credential entry.
  static const String signIn = '/sign-in';

  /// Shown while authenticated but not yet authorized.
  static const String awaitingAuthorization = '/awaiting-authorization';

  /// Biometric or credential re-entry.
  static const String locked = '/locked';

  /// Shown after an integrity fault.
  static const String quarantined = '/quarantined';
}

/// Builds the application router.
final Provider<GoRouter> routerProvider = Provider<GoRouter>((Ref ref) {
  // A listenable bridge from Riverpod to GoRouter: the router re-evaluates its
  // redirect whenever the session phase changes.
  final _SessionRouterNotifier notifier = _SessionRouterNotifier(ref);
  ref.onDispose(notifier.dispose);

  return GoRouter(
    initialLocation: NodexRoutes.splash,
    refreshListenable: notifier,
    redirect: (BuildContext context, GoRouterState state) {
      final SessionState session = ref.read(sessionProvider);
      final String location = state.matchedLocation;

      switch (session.phase) {
        case SessionPhase.initialising:
          return location == NodexRoutes.splash ? null : NodexRoutes.splash;

        case SessionPhase.unauthenticated:
          return location == NodexRoutes.signIn ? null : NodexRoutes.signIn;

        case SessionPhase.awaitingAuthorization:
          return location == NodexRoutes.awaitingAuthorization
              ? null
              : NodexRoutes.awaitingAuthorization;

        case SessionPhase.locked:
          return location == NodexRoutes.locked ? null : NodexRoutes.locked;

        case SessionPhase.quarantined:
          return location == NodexRoutes.quarantined
              ? null
              : NodexRoutes.quarantined;

        case SessionPhase.active:
          // Bounce away from the pre-session routes once authorized.
          const Set<String> preSessionRoutes = <String>{
            NodexRoutes.splash,
            NodexRoutes.signIn,
            NodexRoutes.awaitingAuthorization,
            NodexRoutes.locked,
            NodexRoutes.quarantined,
          };
          if (preSessionRoutes.contains(location)) {
            return NodexDestinations.home.routePath;
          }

          // Refuse a destination whose permissions the session does not hold.
          // Redirecting to home rather than showing an error avoids teaching the
          // user which permissions exist.
          final NavigationDestinationSpec? destination = NodexDestinations.all
              .where(
                (NavigationDestinationSpec spec) =>
                    location == spec.routePath ||
                    location.startsWith('${spec.routePath}/'),
              )
              .firstOrNull;

          if (destination != null &&
              !destination.isVisibleTo(session.authorization)) {
            return NodexDestinations.home.routePath;
          }
          return null;
      }
    },
    routes: <RouteBase>[
      GoRoute(
        path: NodexRoutes.splash,
        builder: (BuildContext context, GoRouterState state) =>
            const _SplashScreen(),
      ),
      GoRoute(
        path: NodexRoutes.signIn,
        builder: (BuildContext context, GoRouterState state) =>
            const SignInScreen(),
      ),
      GoRoute(
        path: NodexRoutes.awaitingAuthorization,
        builder: (BuildContext context, GoRouterState state) =>
            const AwaitingAuthorizationScreen(),
      ),
      GoRoute(
        path: NodexRoutes.locked,
        builder: (BuildContext context, GoRouterState state) =>
            const SessionLockScreen(),
      ),
      GoRoute(
        path: NodexRoutes.quarantined,
        builder: (BuildContext context, GoRouterState state) =>
            const QuarantinedScreen(),
      ),
      ShellRoute(
        builder: (BuildContext context, GoRouterState state, Widget child) =>
            AdaptiveShell(child: child),
        routes: <RouteBase>[
          GoRoute(
            path: NodexDestinations.home.routePath,
            builder: (BuildContext context, GoRouterState state) =>
                const HomeScreen(),
          ),
          GoRoute(
            path: NodexDestinations.patients.routePath,
            builder: (BuildContext context, GoRouterState state) =>
                const PatientSearchScreen(),
            routes: <RouteBase>[
              GoRoute(
                path: ':id',
                builder: (BuildContext context, GoRouterState state) =>
                    PatientDetailScreen(patientId: state.pathParameters['id']!),
                routes: <RouteBase>[
                  GoRoute(
                    path: 'encounters/:encounterId',
                    builder: (BuildContext context, GoRouterState state) =>
                        EncounterEditorScreen(
                          encounterId: state.pathParameters['encounterId']!,
                        ),
                  ),
                  GoRoute(
                    path: 'lab/:orderId',
                    builder: (BuildContext context, GoRouterState state) =>
                        LabOrderScreen(
                          orderId: state.pathParameters['orderId']!,
                        ),
                  ),
                  GoRoute(
                    path: 'imaging/:orderId',
                    builder: (BuildContext context, GoRouterState state) =>
                        ImagingOrderScreen(
                          orderId: state.pathParameters['orderId']!,
                        ),
                  ),
                  GoRoute(
                    path: 'physio/:sessionId',
                    builder: (BuildContext context, GoRouterState state) =>
                        PhysioSessionScreen(
                          sessionId: state.pathParameters['sessionId']!,
                        ),
                  ),
                  GoRoute(
                    path: 'nutrition/:planId',
                    builder: (BuildContext context, GoRouterState state) =>
                        MealPlanScreen(planId: state.pathParameters['planId']!),
                  ),
                  GoRoute(
                    path: 'telemedicine/:consultationId',
                    builder: (BuildContext context, GoRouterState state) =>
                        TeleConsultationScreen(
                          consultationId:
                              state.pathParameters['consultationId']!,
                        ),
                  ),
                  GoRoute(
                    path: 'rx/:prescriptionId',
                    builder: (BuildContext context, GoRouterState state) =>
                        PrescriptionDetailScreen(
                          prescriptionId:
                              state.pathParameters['prescriptionId']!,
                        ),
                  ),
                  GoRoute(
                    path: 'discharge/:dischargeId',
                    builder: (BuildContext context, GoRouterState state) =>
                        DischargeDetailScreen(
                          dischargeId: state.pathParameters['dischargeId']!,
                        ),
                  ),
                  GoRoute(
                    path: 'billing/:invoiceId',
                    builder: (BuildContext context, GoRouterState state) =>
                        InvoiceDetailScreen(
                          invoiceId: state.pathParameters['invoiceId']!,
                        ),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: NodexDestinations.appointments.routePath,
            builder: (BuildContext context, GoRouterState state) =>
                const AppointmentScheduleScreen(),
            routes: <RouteBase>[
              GoRoute(
                path: ':id',
                builder: (BuildContext context, GoRouterState state) =>
                    AppointmentDetailScreen(
                      appointmentId: state.pathParameters['id']!,
                    ),
              ),
            ],
          ),
          GoRoute(
            path: NodexDestinations.wards.routePath,
            builder: (BuildContext context, GoRouterState state) =>
                const WardCensusScreen(),
          ),
          GoRoute(
            path: NodexDestinations.er.routePath,
            builder: (BuildContext context, GoRouterState state) =>
                const ErListScreen(),
            routes: <RouteBase>[
              GoRoute(
                path: 'visits/:visitId',
                builder: (BuildContext context, GoRouterState state) =>
                    ErVisitDetailScreen(
                      visitId: state.pathParameters['visitId']!,
                    ),
              ),
              // triage/new must precede triage/:triageId for declaration-order
              // matching on the static 'new' segment.
              GoRoute(
                path: 'triage/new',
                builder: (BuildContext context, GoRouterState state) {
                  final String? patientId =
                      state.uri.queryParameters['patientId'];
                  if (patientId == null || patientId.isEmpty) {
                    return const _MissingPatientScreen();
                  }
                  return TriageIntakeScreen(patientId: patientId);
                },
              ),
              GoRoute(
                path: 'triage/:triageId',
                builder: (BuildContext context, GoRouterState state) =>
                    TriageDetailScreen(
                      triageId: state.pathParameters['triageId']!,
                    ),
              ),
            ],
          ),
          GoRoute(
            path: NodexDestinations.icu.routePath,
            builder: (BuildContext context, GoRouterState state) =>
                const IcuListScreen(),
            routes: <RouteBase>[
              GoRoute(
                path: 'beds/:icuBedId',
                builder: (BuildContext context, GoRouterState state) =>
                    IcuBedDetailScreen(
                      icuBedId: state.pathParameters['icuBedId']!,
                    ),
              ),
            ],
          ),
          GoRoute(
            path: NodexDestinations.bloodBank.routePath,
            builder: (BuildContext context, GoRouterState state) =>
                const BloodBankListScreen(),
            routes: <RouteBase>[
              GoRoute(
                path: 'units/:unitId',
                builder: (BuildContext context, GoRouterState state) =>
                    BloodUnitDetailScreen(
                      unitId: state.pathParameters['unitId']!,
                    ),
              ),
              GoRoute(
                path: 'requests/:transfusionRequestId',
                builder: (BuildContext context, GoRouterState state) =>
                    TransfusionRequestDetailScreen(
                      transfusionRequestId:
                          state.pathParameters['transfusionRequestId']!,
                    ),
              ),
            ],
          ),
          GoRoute(
            path: NodexDestinations.ot.routePath,
            builder: (BuildContext context, GoRouterState state) =>
                const OtListScreen(),
            routes: <RouteBase>[
              GoRoute(
                path: 'bookings/:bookingId',
                builder: (BuildContext context, GoRouterState state) =>
                    OtBookingDetailScreen(
                      bookingId: state.pathParameters['bookingId']!,
                    ),
              ),
            ],
          ),
          GoRoute(
            path: NodexDestinations.inventory.routePath,
            builder: (BuildContext context, GoRouterState state) =>
                const InventoryScreen(),
          ),
          GoRoute(
            path: NodexDestinations.syncDiagnostics.routePath,
            builder: (BuildContext context, GoRouterState state) =>
                const SyncDiagnosticsScreen(),
          ),
          GoRoute(
            path: NodexDestinations.aiGovernance.routePath,
            builder: (BuildContext context, GoRouterState state) =>
                const AiGovernanceScreen(),
          ),
          GoRoute(
            path: NodexDestinations.audit.routePath,
            builder: (BuildContext context, GoRouterState state) =>
                const AuditScreen(),
          ),
          GoRoute(
            path: NodexDestinations.settings.routePath,
            builder: (BuildContext context, GoRouterState state) =>
                const SettingsScreen(),
          ),
        ],
      ),
    ],
  );
});

/// Bridges session-phase changes to GoRouter's refresh mechanism.
final class _SessionRouterNotifier extends ChangeNotifier {
  _SessionRouterNotifier(Ref ref) {
    _subscription = ref.listen<SessionState>(sessionProvider, (
      SessionState? previous,
      SessionState next,
    ) {
      // Only a phase change alters the reachable route set. Ignoring the rest
      // avoids re-running the redirect on every sync-status tick.
      if (previous?.phase != next.phase) {
        notifyListeners();
      }
    });
  }

  late final ProviderSubscription<SessionState> _subscription;

  @override
  void dispose() {
    _subscription.close();
    super.dispose();
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          CircularProgressIndicator(),
          SizedBox(height: 24),
          Text('Preparing secure clinical workspace'),
        ],
      ),
    ),
  );
}

/// Shown when the triage intake route is opened without a patientId query.
class _MissingPatientScreen extends StatelessWidget {
  const _MissingPatientScreen();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Record triage')),
    body: const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text('Select a patient first.', textAlign: TextAlign.center),
      ),
    ),
  );
}
