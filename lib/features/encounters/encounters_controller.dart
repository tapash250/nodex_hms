/// Clinical encounter presentation controllers (Module 16).
///
/// The encounter list for a patient and the encounter detail bundle (record
/// plus amendments) load through families. Controllers call use cases and
/// repositories only — never PowerSync or Supabase directly.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/encounters/encounter.dart';
import 'package:nodex_hms/domain/encounters/encounter_repository.dart';

/// Encounter detail bundle for the editor screen.
final class EncounterDetail {
  /// Creates a detail bundle.
  const EncounterDetail({required this.encounter, required this.amendments});

  /// The encounter record.
  final ClinicalEncounter encounter;

  /// Amendments, newest first.
  final List<EncounterAmendment> amendments;
}

/// Encounters for one patient, newest first.
final encountersForPatientProvider = FutureProvider.autoDispose
    .family<List<ClinicalEncounter>, String>((Ref ref, String patientId) async {
      final EncounterRepository repository = ref.watch(
        encounterRepositoryProvider,
      );
      return repository.listForPatient(patientId);
    });

/// Detail bundle for one encounter, including its amendments.
final encounterDetailProvider = FutureProvider.autoDispose
    .family<EncounterDetail, String>((Ref ref, String encounterId) async {
      final EncounterRepository repository = ref.watch(
        encounterRepositoryProvider,
      );
      final ClinicalEncounter? encounter = await repository.getEncounter(
        encounterId,
      );
      if (encounter == null) {
        throw const PersistenceError(
          message:
              'This encounter is not in the local projection. It may not '
              'have replicated to this device yet.',
          code: 'encounter_not_found_locally',
        );
      }
      final List<EncounterAmendment> amendments = await repository
          .listAmendments(encounterId);
      return EncounterDetail(encounter: encounter, amendments: amendments);
    });
