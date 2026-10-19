/// Laboratory presentation providers (Module 17).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/laboratory/lab.dart';
import 'package:nodex_hms/domain/laboratory/lab_repository.dart';
import 'package:nodex_hms/features/laboratory/lab_trend.dart';

/// Order detail bundle for the laboratory screen.
final class LabOrderDetail {
  /// Creates a bundle.
  const LabOrderDetail({
    required this.order,
    required this.specimens,
    required this.results,
  });

  /// Parent order.
  final LabOrder order;

  /// Barcode specimens belonging to the order.
  final List<LabSpecimen> specimens;

  /// Results, newest correction first.
  final List<LabResult> results;
}

/// Laboratory orders for one patient.
final labOrdersForPatientProvider = FutureProvider.autoDispose
    .family<List<LabOrder>, String>((Ref ref, String patientId) async {
      return ref.watch(labRepositoryProvider).listOrdersForPatient(patientId);
    });

/// The numeric trends held for one patient (Module 49).
///
/// The curve follows the analyte across orders, so it is built from the
/// patient's results rather than from any single order.
final labTrendsProvider = FutureProvider.autoDispose
    .family<List<LabTrend>, String>((Ref ref, String patientId) async {
      final List<LabResult> results = await ref
          .watch(labRepositoryProvider)
          .listResultsForPatient(patientId);
      return buildLabTrends(results);
    });

/// One order with specimens and results.
final labOrderDetailProvider = FutureProvider.autoDispose
    .family<LabOrderDetail, String>((Ref ref, String orderId) async {
      final LabRepository repository = ref.watch(labRepositoryProvider);
      final LabOrder? order = await repository.getOrder(orderId);
      if (order == null) {
        throw const PersistenceError(
          message: 'This laboratory order is not available on this device.',
          code: 'lab_order_not_found_locally',
        );
      }
      return LabOrderDetail(
        order: order,
        specimens: await repository.listSpecimens(orderId),
        results: await repository.listResults(orderId),
      );
    });
