/// ICU bed census, vitals, handover, and ventilator presentation providers (Module 06).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/icu/icu.dart';

/// All ICU beds visible to the signed-in user.
final icuBedsProvider = FutureProvider.autoDispose<List<IcuBed>>((
  Ref ref,
) async {
  return ref.watch(icuRepositoryProvider).allBeds();
});

/// A single ICU bed, or a not-found error when the row is missing locally.
final icuBedDetailProvider = FutureProvider.autoDispose.family<IcuBed, String>((
  Ref ref,
  String bedId,
) async {
  final bed = await ref.watch(icuRepositoryProvider).bedById(bedId);
  if (bed == null) {
    throw const PersistenceError(
      message: 'This ICU bed is not available on this device.',
      code: 'icu_bed_not_found_locally',
    );
  }
  return bed;
});

/// ICU beds currently assigned to a patient.
final icuBedsForPatientProvider = FutureProvider.autoDispose
    .family<List<IcuBed>, String>((Ref ref, String patientId) async {
      return ref.watch(icuRepositoryProvider).bedsForPatient(patientId);
    });

/// ICU vitals recorded for a patient, most recent first.
final icuVitalsForPatientProvider = FutureProvider.autoDispose
    .family<List<IcuVitals>, String>((Ref ref, String patientId) async {
      return ref.watch(icuRepositoryProvider).vitalsForPatient(patientId);
    });

/// ICU nursing handovers recorded for a patient, most recent first.
final icuHandoversForPatientProvider = FutureProvider.autoDispose
    .family<List<IcuNursingHandover>, String>((
      Ref ref,
      String patientId,
    ) async {
      return ref.watch(icuRepositoryProvider).handoversForPatient(patientId);
    });

/// Ventilator events recorded for a bed, most recent first.
final ventilatorEventsForBedProvider = FutureProvider.autoDispose
    .family<List<VentilatorEvent>, String>((Ref ref, String icuBedId) async {
      return ref.watch(icuRepositoryProvider).ventilatorEventsForBed(icuBedId);
    });
