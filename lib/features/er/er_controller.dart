/// ER triage and visit presentation providers (Module 05).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/er/er.dart';

/// Triage assessments recorded for a patient, oldest first.
final triageForPatientProvider = FutureProvider.autoDispose
    .family<List<TriageAssessment>, String>((Ref ref, String patientId) async {
      return ref.watch(erRepositoryProvider).triageForPatient(patientId);
    });

/// ER visits recorded for a patient, most recent first.
final erVisitsForPatientProvider = FutureProvider.autoDispose
    .family<List<ErVisit>, String>((Ref ref, String patientId) async {
      return ref.watch(erRepositoryProvider).visitsForPatient(patientId);
    });

/// Currently open ER visits across the signed-in user's scope.
final openErVisitsProvider = FutureProvider.autoDispose<List<ErVisit>>((
  Ref ref,
) async {
  return ref.watch(erRepositoryProvider).openVisits();
});

/// A single ER visit, or a not-found error when the row is missing locally.
final erVisitDetailProvider = FutureProvider.autoDispose
    .family<ErVisit, String>((Ref ref, String visitId) async {
      final visit = await ref.watch(erRepositoryProvider).visitById(visitId);
      if (visit == null) {
        throw const PersistenceError(
          message: 'This ER visit is not available on this device.',
          code: 'er_visit_not_found_locally',
        );
      }
      return visit;
    });

/// A single triage assessment, or a not-found error when the row is missing locally.
final triageDetailProvider = FutureProvider.autoDispose
    .family<TriageAssessment, String>((Ref ref, String triageId) async {
      final assessment = await ref
          .watch(erRepositoryProvider)
          .triageById(triageId);
      if (assessment == null) {
        throw const PersistenceError(
          message: 'This triage assessment is not available on this device.',
          code: 'triage_not_found_locally',
        );
      }
      return assessment;
    });
