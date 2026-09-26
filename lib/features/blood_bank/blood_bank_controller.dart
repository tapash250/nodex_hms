/// Blood bank inventory and transfusion presentation providers (Module 26).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/blood_bank/blood_bank.dart';

/// All blood units visible to the signed-in user.
final bloodUnitsProvider = FutureProvider.autoDispose<List<BloodUnit>>((
  Ref ref,
) async {
  return ref.watch(bloodBankRepositoryProvider).allBloodUnits();
});

/// A single blood unit, or a not-found error when the row is missing locally.
final bloodUnitDetailProvider = FutureProvider.autoDispose
    .family<BloodUnit, String>((Ref ref, String unitId) async {
      final BloodUnit? unit = await ref
          .watch(bloodBankRepositoryProvider)
          .bloodUnitById(unitId);
      if (unit == null) {
        throw const PersistenceError(
          message: 'This blood unit is not available on this device.',
          code: 'blood_unit_not_found_locally',
        );
      }
      return unit;
    });

/// All transfusion requests visible to the signed-in user.
final transfusionRequestsProvider =
    FutureProvider.autoDispose<List<TransfusionRequest>>((Ref ref) async {
      return ref.watch(bloodBankRepositoryProvider).allRequests();
    });

/// A single transfusion request, or a not-found error when missing locally.
final transfusionRequestDetailProvider = FutureProvider.autoDispose
    .family<TransfusionRequest, String>((Ref ref, String requestId) async {
      final TransfusionRequest? request = await ref
          .watch(bloodBankRepositoryProvider)
          .requestById(requestId);
      if (request == null) {
        throw const PersistenceError(
          message: 'This transfusion request is not available on this device.',
          code: 'transfusion_request_not_found_locally',
        );
      }
      return request;
    });

/// Blood units reserved or issued against a request, soonest expiry first.
final bloodUnitsForRequestProvider = FutureProvider.autoDispose
    .family<List<BloodUnit>, String>((Ref ref, String requestId) async {
      return ref
          .watch(bloodBankRepositoryProvider)
          .bloodUnitsForRequest(requestId);
    });

/// Transfusion requests raised for a patient, most recent first.
final transfusionRequestsForPatientProvider = FutureProvider.autoDispose
    .family<List<TransfusionRequest>, String>((
      Ref ref,
      String patientId,
    ) async {
      return ref
          .watch(bloodBankRepositoryProvider)
          .requestsForPatient(patientId);
    });

/// Transfusions recorded for a patient, most recent first.
final transfusionsForPatientProvider = FutureProvider.autoDispose
    .family<List<Transfusion>, String>((Ref ref, String patientId) async {
      return ref
          .watch(bloodBankRepositoryProvider)
          .transfusionsForPatient(patientId);
    });

/// Blood units held for a patient, soonest expiry first.
final bloodUnitsForPatientProvider = FutureProvider.autoDispose
    .family<List<BloodUnit>, String>((Ref ref, String patientId) async {
      return ref
          .watch(bloodBankRepositoryProvider)
          .bloodUnitsForPatient(patientId);
    });
