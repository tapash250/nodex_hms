/// Radiology presentation providers (Module 18).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/radiology/radiology.dart';
import 'package:nodex_hms/domain/radiology/radiology_repository.dart';

/// Order detail bundle for the radiology screen.
final class ImagingOrderDetail {
  /// Creates a bundle.
  const ImagingOrderDetail({required this.order, this.study, this.report});

  /// Parent order.
  final ImagingOrder order;

  /// Acquired study, when one has been recorded.
  final ImagingStudy? study;

  /// Report filed for the order, when one exists.
  final ImagingReport? report;
}

/// Imaging orders for one patient.
final imagingOrdersForPatientProvider = FutureProvider.autoDispose
    .family<List<ImagingOrder>, String>((Ref ref, String patientId) async {
      return ref.watch(radiologyRepositoryProvider).ordersForPatient(patientId);
    });

/// One order with its study and report.
final imagingOrderDetailProvider = FutureProvider.autoDispose
    .family<ImagingOrderDetail, String>((Ref ref, String orderId) async {
      final RadiologyRepository repository = ref.watch(
        radiologyRepositoryProvider,
      );
      final ImagingOrder? order = await repository.orderById(orderId);
      if (order == null) {
        throw const PersistenceError(
          message: 'This imaging order is not available on this device.',
          code: 'imaging_order_not_found_locally',
        );
      }
      return ImagingOrderDetail(
        order: order,
        study: await repository.studyForOrder(orderId),
        report: await repository.reportForOrder(orderId),
      );
    });
