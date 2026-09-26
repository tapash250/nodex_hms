/// Physiotherapy presentation providers (Module 20).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/physio/physio.dart';
import 'package:nodex_hms/domain/physio/physio_repository.dart';

/// Session detail bundle for the physiotherapy screen.
final class PhysioSessionDetail {
  /// Creates a bundle.
  const PhysioSessionDetail({
    required this.session,
    required this.notes,
    required this.plans,
  });

  /// The session itself.
  final PhysioSession session;

  /// Recovery notes recorded against the session, oldest first.
  final List<PhysioRecoveryNote> notes;

  /// Exercise plans prescribed for the patient, newest first.
  final List<PhysioExercisePlan> plans;
}

/// Physiotherapy sessions for one patient.
final physioSessionsForPatientProvider = FutureProvider.autoDispose
    .family<List<PhysioSession>, String>((Ref ref, String patientId) async {
      return ref.watch(physioRepositoryProvider).sessionsForPatient(patientId);
    });

/// One session with its recovery notes and the patient's exercise plans.
final physioSessionDetailProvider = FutureProvider.autoDispose
    .family<PhysioSessionDetail, String>((Ref ref, String sessionId) async {
      final PhysioRepository repository = ref.watch(physioRepositoryProvider);
      final PhysioSession? session = await repository.sessionById(sessionId);
      if (session == null) {
        throw const PersistenceError(
          message:
              'This physiotherapy session is not available on this '
              'device.',
          code: 'physio_session_not_found_locally',
        );
      }
      return PhysioSessionDetail(
        session: session,
        notes: await repository.notesForSession(sessionId),
        plans: await repository.plansForPatient(session.patientId),
      );
    });
