/// Billing presentation providers (Module 31).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/billing/invoice.dart';

/// Invoices for one patient, newest first.
final invoicesForPatientProvider = FutureProvider.autoDispose
    .family<List<Invoice>, String>((Ref ref, String patientId) async {
      return ref.watch(billingRepositoryProvider).listForPatient(patientId);
    });

/// One invoice by id.
final invoiceDetailProvider = FutureProvider.autoDispose
    .family<Invoice, String>((Ref ref, String invoiceId) async {
      final Invoice? invoice = await ref
          .watch(billingRepositoryProvider)
          .getInvoice(invoiceId);
      if (invoice == null) {
        throw const PersistenceError(
          message: 'This invoice is not available on this device.',
          code: 'invoice_not_found_locally',
        );
      }
      return invoice;
    });

/// Invoice lines for one invoice.
final invoiceLinesProvider = FutureProvider.autoDispose
    .family<List<InvoiceLine>, String>((Ref ref, String invoiceId) async {
      return ref.watch(billingRepositoryProvider).listLines(invoiceId);
    });

/// Payments for one invoice.
final invoicePaymentsProvider = FutureProvider.autoDispose
    .family<List<Payment>, String>((Ref ref, String invoiceId) async {
      return ref.watch(billingRepositoryProvider).listPayments(invoiceId);
    });

/// Refunds for one invoice.
final invoiceRefundsProvider = FutureProvider.autoDispose
    .family<List<Refund>, String>((Ref ref, String invoiceId) async {
      return ref.watch(billingRepositoryProvider).listRefunds(invoiceId);
    });
