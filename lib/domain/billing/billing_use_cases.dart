/// Billing use cases (Module 31).
library;

import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/billing/billing_repository.dart';
import 'package:nodex_hms/domain/billing/invoice.dart';

/// Drafts a new invoice.
final class DraftInvoiceUseCase {
  /// Creates the use case.
  DraftInvoiceUseCase({required this._repository});

  final BillingRepository _repository;

  /// Drafts an invoice locally.
  Future<String> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String patientId,
    required String createdBy,
    required String invoiceCode,
    String? encounterId,
    String? notes,
    String currency = 'BDT',
  }) async {
    policy.require(NodexPermissions.billingSettle);
    return _repository.createInvoice(
      Invoice.draftRow(
        tenantId: tenantId,
        patientId: patientId,
        createdBy: createdBy,
        invoiceCode: invoiceCode,
        encounterId: encounterId,
        notes: notes,
        currency: currency,
      ),
    );
  }
}

/// Adds a line to a draft invoice.
final class AddInvoiceLineUseCase {
  /// Creates the use case.
  AddInvoiceLineUseCase({required this._repository});

  final BillingRepository _repository;

  /// Adds the line, refusing a parent that is no longer a draft.
  Future<String> call({
    required AuthorizationPolicy policy,
    required Invoice invoice,
    required int lineNumber,
    required String description,
    required double quantity,
    required int unitPriceMinor,
    required int lineTotalMinor,
  }) async {
    policy.require(NodexPermissions.billingSettle);
    if (invoice.status != InvoiceStatus.draft) {
      throw const AuthorizationError(
        message: 'Lines can only be added to a draft invoice.',
        code: 'invoice_not_editable',
      );
    }
    return _repository.addLine(
      InvoiceLine.draftRow(
        tenantId: invoice.tenantId,
        invoiceId: invoice.id,
        lineNumber: lineNumber,
        description: description,
        quantity: quantity,
        unitPriceMinor: unitPriceMinor,
        lineTotalMinor: lineTotalMinor,
      ),
    );
  }
}

/// Issues a draft invoice.
final class IssueInvoiceUseCase {
  /// Creates the use case.
  IssueInvoiceUseCase({required this._repository});

  final BillingRepository _repository;

  /// Issues [invoice], refusing anything but a draft.
  Future<void> call({
    required AuthorizationPolicy policy,
    required Invoice invoice,
  }) async {
    policy.require(NodexPermissions.billingSettle);
    if (invoice.status != InvoiceStatus.draft) {
      throw const AuthorizationError(
        message: 'Only a draft invoice can be issued.',
        code: 'invoice_not_draft',
      );
    }
    await _repository.updateInvoice(invoice.id, Invoice.issueChanges());
  }
}

/// Settles an issued invoice (full payment required).
final class SettleInvoiceUseCase {
  /// Creates the use case.
  SettleInvoiceUseCase({required this._repository});

  final BillingRepository _repository;

  /// Settles [invoice], refusing anything but an issued invoice.
  Future<void> call({
    required AuthorizationPolicy policy,
    required Invoice invoice,
  }) async {
    policy.require(NodexPermissions.billingSettle);
    if (invoice.status != InvoiceStatus.issued) {
      throw const AuthorizationError(
        message: 'Only an issued invoice can be settled.',
        code: 'invoice_not_issued',
      );
    }
    await _repository.updateInvoice(invoice.id, Invoice.settleChanges());
  }
}

/// Records a payment against an invoice.
final class RecordPaymentUseCase {
  /// Creates the use case.
  RecordPaymentUseCase({required this._repository});

  final BillingRepository _repository;

  /// Records the payment, refusing closed invoices. The running total is
  /// derived server-side; a concurrent over-payment is rejected on upload.
  Future<String> call({
    required AuthorizationPolicy policy,
    required Invoice invoice,
    required String recordedBy,
    required int amountMinor,
    required PaymentMethod method,
    String? reference,
    String? note,
  }) async {
    policy.require(NodexPermissions.billingSettle);
    if (invoice.status.isTerminal) {
      throw const AuthorizationError(
        message: 'A closed invoice cannot receive payments.',
        code: 'invoice_closed',
      );
    }
    return _repository.recordPayment(
      Payment.eventRow(
        tenantId: invoice.tenantId,
        invoiceId: invoice.id,
        recordedBy: recordedBy,
        amountMinor: amountMinor,
        method: method,
        reference: reference,
        note: note,
      ),
    );
  }
}

/// Records a refund against a payment.
final class RecordRefundUseCase {
  /// Creates the use case.
  RecordRefundUseCase({required this._repository});

  final BillingRepository _repository;

  /// Records the refund, refusing amounts that exceed what was received.
  Future<String> call({
    required AuthorizationPolicy policy,
    required Payment payment,
    required String recordedBy,
    required int amountMinor,
    required String reason,
  }) async {
    policy.require(NodexPermissions.billingSettle);
    return _repository.recordRefund(
      Refund.eventRow(
        tenantId: payment.tenantId,
        invoiceId: payment.invoiceId,
        paymentId: payment.id,
        recordedBy: recordedBy,
        amountMinor: amountMinor,
        reason: reason,
      ),
    );
  }
}

/// Cancels a draft or issued invoice.
final class CancelInvoiceUseCase {
  /// Creates the use case.
  CancelInvoiceUseCase({required this._repository});

  final BillingRepository _repository;

  /// Cancels [invoice] with [reason].
  Future<void> call({
    required AuthorizationPolicy policy,
    required Invoice invoice,
    required String reason,
  }) async {
    if (!invoice.status.isEditable) {
      throw const AuthorizationError(
        message: 'Only a draft or issued invoice can be cancelled.',
        code: 'invoice_not_cancellable',
      );
    }
    policy.require(
      invoice.status == InvoiceStatus.draft
          ? NodexPermissions.billingSettle
          : NodexPermissions.billingSettle,
    );
    await _repository.updateInvoice(
      invoice.id,
      Invoice.cancelChanges(reason: reason),
    );
  }
}
