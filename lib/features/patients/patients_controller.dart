/// Master Patient Index presentation controllers (Module 10).
///
/// Search state lives in an [AsyncNotifier] so loading, empty, error and
/// sync-failure states are explicit values rather than scattered flags. Detail
/// screens load through families keyed by patient id. Controllers never touch
/// PowerSync or Supabase: they call use cases and repositories only.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/patients/patient.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';
import 'package:nodex_hms/domain/session/session_state.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// Patient detail bundle for the detail screen.
final class PatientDetail {
  /// Creates a detail bundle.
  const PatientDetail({required this.patient, required this.allergies});

  /// The patient record.
  final Patient patient;

  /// Allergies, active first by repository ordering.
  final List<PatientAllergy> allergies;

  /// Allergies currently in force.
  List<PatientAllergy> get activeAllergies =>
      allergies.where((PatientAllergy a) => a.isActive).toList(growable: false);
}

/// Searches patients in the active tenant.
///
/// The query is explicit state (not a watched text field) so every search is a
/// deliberate read against a known tenant scope — important when a principal
/// holds memberships in several tenants.
final class PatientSearchController extends AsyncNotifier<List<Patient>> {
  /// Current query. Empty lists recently updated records.
  String _query = '';

  @override
  Future<List<Patient>> build() => _search('');

  /// Runs a search for [query].
  Future<void> search(String query) async {
    _query = query;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _search(query));
  }

  /// Re-runs the current query, e.g. after returning from registration.
  Future<void> refresh() => search(_query);

  Future<List<Patient>> _search(String query) {
    final SessionState session = ref.read(sessionProvider);
    final String? tenantId = session.tenantId;
    if (tenantId == null) {
      throw const AuthorizationError(
        message: 'No active tenant. Sign in again to restore access.',
        code: 'no_active_tenant',
      );
    }
    return ref
        .read(patientRepositoryProvider)
        .searchPatients(tenantId: tenantId, query: query);
  }
}

/// Search results for the patient list screen.
final AsyncNotifierProvider<PatientSearchController, List<Patient>>
patientSearchProvider =
    AsyncNotifierProvider<PatientSearchController, List<Patient>>(
      PatientSearchController.new,
    );

/// Detail bundle for one patient, including allergies.
final patientDetailProvider = FutureProvider.autoDispose
    .family<PatientDetail, String>((Ref ref, String patientId) async {
      final PatientRepository repository = ref.watch(patientRepositoryProvider);
      final Patient? patient = await repository.getPatient(patientId);
      if (patient == null) {
        throw const PersistenceError(
          message:
              'This patient record is not in the local projection. It may not '
              'have replicated to this device yet.',
          code: 'patient_not_found_locally',
        );
      }
      final List<PatientAllergy> allergies = await repository.getAllergies(
        patientId,
        activeOnly: false,
      );
      return PatientDetail(patient: patient, allergies: allergies);
    });
