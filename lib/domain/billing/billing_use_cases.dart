/// Billing use cases (Module 31).
library;

import 'package:meta/meta.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/billing/billing_repository.dart';
import 'package:nodex_hms/domain/billing/invoice.dart';
import 'package:nodex_hms/domain/billing/patient_account.dart';

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

/// Opens the running account a patient carries across visits.
final class OpenPatientAccountUseCase {
  /// Creates the use case.
  OpenPatientAccountUseCase({required this._repository});

  final BillingRepository _repository;

  /// Opens an account, returning the existing one when the patient already has
  /// one. Two accounts for one patient would make the balance ambiguous, so the
  /// unique (tenant, patient) constraint is respected rather than raced.
  Future<PatientAccount> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String patientId,
    required String accountCode,
    String currency = 'BDT',
  }) async {
    policy.require(NodexPermissions.billingLedger);
    final PatientAccount? existing = await _repository.getAccountForPatient(
      patientId,
    );
    if (existing != null) {
      return existing;
    }
    final String id = await _repository.openAccount(
      PatientAccount.openRow(
        tenantId: tenantId,
        patientId: patientId,
        accountCode: accountCode,
        currency: currency,
      ),
    );
    final PatientAccount? opened = await _repository.getAccountById(id);
    if (opened == null) {
      throw const PersistenceError(
        message: 'The patient account could not be read back after opening.',
        code: 'patient_account_unreadable',
      );
    }
    return opened;
  }
}

/// Posts a charge for an issued invoice onto the patient's account.
final class PostChargeUseCase {
  /// Creates the use case.
  PostChargeUseCase({required this._repository});

  final BillingRepository _repository;

  /// Posts the charge, refusing an unissued invoice: billing a draft would
  /// charge a patient for a decision nobody has made yet.
  Future<String> call({
    required AuthorizationPolicy policy,
    required PatientAccount account,
    required Invoice invoice,
    required String recordedBy,
    required int amountMinor,
    String? memo,
  }) async {
    policy.require(NodexPermissions.billingLedger);
    if (!account.acceptsPostings) {
      throw const AuthorizationError(
        message: 'A closed account cannot receive charges.',
        code: 'patient_account_closed',
      );
    }
    if (invoice.status == InvoiceStatus.draft) {
      throw const AuthorizationError(
        message: 'Issue the invoice before charging the patient for it.',
        code: 'invoice_not_issued',
      );
    }
    if (invoice.status == InvoiceStatus.cancelled) {
      throw const AuthorizationError(
        message: 'A cancelled invoice cannot be charged.',
        code: 'invoice_cancelled',
      );
    }
    if (invoice.currency != account.currency) {
      throw ValidationError(
        message: 'The invoice currency does not match the patient account.',
        fieldErrors: <String, String>{
          'currency':
              'Invoice is ${invoice.currency}, account is '
              '${account.currency}.',
        },
        code: 'ledger_currency_mismatch',
      );
    }
    return _repository.postLedgerEntry(
      LedgerEntry.chargeRow(
        tenantId: account.tenantId,
        accountId: account.id,
        invoiceId: invoice.id,
        amountMinor: amountMinor,
        currency: account.currency,
        recordedBy: recordedBy,
        memo: memo,
      ),
    );
  }
}

/// Posts a correcting adjustment. Requires a reason.
final class PostAdjustmentUseCase {
  /// Creates the use case.
  PostAdjustmentUseCase({required this._repository});

  final BillingRepository _repository;

  /// Posts the adjustment.
  ///
  /// Adjustments move money without a source document, so they are the one
  /// posting kind that demands a stated reason and is audited by name.
  Future<String> call({
    required AuthorizationPolicy policy,
    required PatientAccount account,
    required String recordedBy,
    required int amountMinor,
    required LedgerDirection direction,
    required String reason,
  }) async {
    policy.require(NodexPermissions.billingLedger);
    if (!account.acceptsPostings) {
      throw const AuthorizationError(
        message: 'A closed account cannot be adjusted.',
        code: 'patient_account_closed',
      );
    }
    return _repository.postLedgerEntry(
      LedgerEntry.adjustmentRow(
        tenantId: account.tenantId,
        accountId: account.id,
        amountMinor: amountMinor,
        currency: account.currency,
        recordedBy: recordedBy,
        direction: direction,
        reason: reason,
      ),
    );
  }
}

/// Splits part of a payment onto one invoice.
final class AllocatePaymentUseCase {
  /// Creates the use case.
  AllocatePaymentUseCase({required this._repository});

  final BillingRepository _repository;

  /// Allocates [amountMinor] of [payment] to [invoice].
  ///
  /// The client checks the two sums it can see, so an obviously impossible
  /// split is refused offline; the server revalidates both under a row lock,
  /// which is what actually prevents double allocation.
  Future<String> call({
    required AuthorizationPolicy policy,
    required Payment payment,
    required Invoice invoice,
    required int amountMinor,
  }) async {
    policy.require(NodexPermissions.billingSettle);
    if (payment.tenantId != invoice.tenantId) {
      throw const ValidationError(
        message: 'A payment can only settle an invoice in the same tenant.',
        fieldErrors: <String, String>{'invoice_id': 'Tenant mismatch.'},
        code: 'allocation_tenant_mismatch',
      );
    }

    final List<PaymentAllocation> existing = await _repository.listAllocations(
      payment.id,
    );
    final int allocated = existing.fold<int>(
      0,
      (int total, PaymentAllocation a) => total + a.amountMinor,
    );
    if (allocated + amountMinor > payment.amountMinor) {
      throw ValidationError(
        message: 'The allocation exceeds what remains of the payment.',
        fieldErrors: <String, String>{
          'amount_minor':
              'Only ${payment.amountMinor - allocated} left on '
              'this payment.',
        },
        code: 'allocation_exceeds_payment',
      );
    }

    final int outstanding = invoice.totalMinor - invoice.settledMinor;
    if (amountMinor > outstanding) {
      throw ValidationError(
        message: 'The allocation exceeds what the invoice still owes.',
        fieldErrors: <String, String>{
          'amount_minor': 'Invoice outstanding is $outstanding.',
        },
        code: 'allocation_exceeds_invoice',
      );
    }

    return _repository.allocatePayment(
      PaymentAllocation.row(
        tenantId: payment.tenantId,
        paymentId: payment.id,
        invoiceId: invoice.id,
        amountMinor: amountMinor,
      ),
    );
  }
}

/// A patient's statement: the account, its journal, and the balance the journal
/// itself implies.
@immutable
final class PatientAccountStatement {
  /// Creates a statement.
  const PatientAccountStatement({required this.account, required this.entries});

  /// The account.
  final PatientAccount account;

  /// Journal entries, newest first.
  final List<LedgerEntry> entries;

  /// Balance implied by the entries the device holds.
  int get journalledBalanceMinor => ledgerBalanceMinor(entries);

  /// Whether the device's journal agrees with the server projection.
  ///
  /// A disagreement means the device is missing entries (a partial replication
  /// window, or a bucket not yet materialized), which the screen must say out
  /// loud rather than render a balance nobody can explain.
  bool get agreesWithServer => journalledBalanceMinor == account.balanceMinor;
}

/// Reads a patient account and its journal.
final class ReadPatientAccountUseCase {
  /// Creates the use case.
  ReadPatientAccountUseCase({required this._repository});

  final BillingRepository _repository;

  /// Returns the statement, or null when the patient has no account yet.
  Future<PatientAccountStatement?> call({
    required AuthorizationPolicy policy,
    required String patientId,
    int entryLimit = 200,
  }) async {
    policy.require(NodexPermissions.billingRead);
    final PatientAccount? account = await _repository.getAccountForPatient(
      patientId,
    );
    if (account == null) {
      return null;
    }
    final List<LedgerEntry> entries = await _repository.listLedgerEntries(
      account.id,
      limit: entryLimit,
    );
    return PatientAccountStatement(account: account, entries: entries);
  }
}
