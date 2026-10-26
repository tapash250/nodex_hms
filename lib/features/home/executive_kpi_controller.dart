/// Executive KPI controller (Module 01).
///
/// The controller reads one facility's replicated snapshots through the use
/// case. It never calls the server: the capture job writes snapshots, PowerSync
/// brings the trailing window, and the home surface renders what the device
/// already holds.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/domain/executive/executive_kpi.dart';
import 'package:nodex_hms/domain/session/session_state.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// The executive reading for the session's first facility in scope.
final AsyncNotifierProvider<ExecutiveKpiNotifier, ExecutiveKpiState>
executiveKpiProvider =
    AsyncNotifierProvider.autoDispose<ExecutiveKpiNotifier, ExecutiveKpiState>(
      ExecutiveKpiNotifier.new,
    );

/// Loads the executive dashboard from the local projection.
final class ExecutiveKpiNotifier extends AsyncNotifier<ExecutiveKpiState> {
  @override
  Future<ExecutiveKpiState> build() async {
    return _load(ref.watch(sessionProvider));
  }

  /// Re-reads the local projection, for example after a sync completes.
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _load(ref.read(sessionProvider)));
  }

  Future<ExecutiveKpiState> _load(SessionState session) {
    final String? facilityId = _firstFacility(session);
    if (facilityId == null) {
      return Future<ExecutiveKpiState>.value(const ExecutiveKpiState.empty());
    }
    return ref
        .read(readExecutiveKpiUseCaseProvider)
        .call(policy: session.authorization, facilityId: facilityId);
  }

  static String? _firstFacility(SessionState session) {
    final Set<String> facilities =
        session.snapshot?.facilityIds ?? const <String>{};
    if (facilities.isEmpty) return null;
    return facilities.first;
  }
}
