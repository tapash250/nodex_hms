/// Billing repository contract and local implementation (Module 31).
library;

import 'package:nodex_hms/core/errors/error_mapper.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/billing/invoice.dart';
import 'package:nodex_hms/domain/billing/patient_account.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';
import 'package:uuid/uuid.dart';

/// Repository operations for billing.
abstract interface class BillingRepository {
  /// Invoices for one patient, newest first.
  Future<List<Invoice>> listForPatient(String patientId);

  /// One invoice by id, or null.
  Future<Invoice?> getInvoice(String id);

  /// Invoice by code, or null.
  Future<Invoice?> getByCode(String invoiceCode);

  /// Lines for one invoice, in line order.
  Future<List<InvoiceLine>> listLines(String invoiceId);

  /// Payments for one invoice, oldest first.
  Future<List<Payment>> listPayments(String invoiceId);

  /// Refunds for one invoice, oldest first.
  Future<List<Refund>> listRefunds(String invoiceId);

  /// Creates a local draft invoice.
  Future<String> createInvoice(Map<String, Object?> row);

  /// Adds a draft line.
  Future<String> addLine(Map<String, Object?> row);

  /// Applies an invoice transition.
  Future<void> updateInvoice(String id, Map<String, Object?> changes);

  /// Applies a line transition.
  Future<void> updateLine(String id, Map<String, Object?> changes);

  /// Records a payment.
  Future<String> recordPayment(Map<String, Object?> row);

  /// Records a refund.
  Future<String> recordRefund(Map<String, Object?> row);

  /// The patient's account, or null when none is open.
  Future<PatientAccount?> getAccountForPatient(String patientId);

  /// One account by id, or null.
  Future<PatientAccount?> getAccountById(String id);

  /// Journal entries for an account, newest first.
  Future<List<LedgerEntry>> listLedgerEntries(String accountId, {int limit});

  /// Opens a patient account.
  Future<String> openAccount(Map<String, Object?> row);

  /// Posts a journal entry.
  Future<String> postLedgerEntry(Map<String, Object?> row);

  /// Allocations recorded against a payment.
  Future<List<PaymentAllocation>> listAllocations(String paymentId);

  /// Splits part of a payment onto an invoice.
  Future<String> allocatePayment(Map<String, Object?> row);
}

/// PowerSync-backed billing repository.
final class DefaultBillingRepository implements BillingRepository {
  /// Creates a repository over a local store.
  DefaultBillingRepository({required this._store, required this._logger});

  static const String _module = 'domain.billing';

  final PatientLocalStore _store;
  final NodexLogger _logger;

  @override
  Future<List<Invoice>> listForPatient(String patientId) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'SELECT * FROM ${LocalTables.invoices} WHERE patient_id = ? ORDER BY created_at DESC',
        <Object?>[patientId],
      );
      return rows.map(Invoice.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'billing.invoices');
    }
  }

  @override
  Future<Invoice?> getInvoice(String id) async {
    final Map<String, Object?>? row = await _store.getById(
      LocalTables.invoices,
      id,
    );
    return row == null ? null : Invoice.fromRow(row);
  }

  @override
  Future<Invoice?> getByCode(String invoiceCode) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'SELECT * FROM ${LocalTables.invoices} WHERE invoice_code = ?',
        <Object?>[invoiceCode],
      );
      if (rows.isEmpty) return null;
      return Invoice.fromRow(rows.first);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'billing.invoice_by_code');
    }
  }

  @override
  Future<List<InvoiceLine>> listLines(String invoiceId) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'SELECT * FROM ${LocalTables.invoiceLines} WHERE invoice_id = ? ORDER BY line_number',
        <Object?>[invoiceId],
      );
      return rows.map(InvoiceLine.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'billing.lines');
    }
  }

  @override
  Future<List<Payment>> listPayments(String invoiceId) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'SELECT * FROM ${LocalTables.payments} WHERE invoice_id = ? ORDER BY paid_at',
        <Object?>[invoiceId],
      );
      return rows.map(Payment.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'billing.payments');
    }
  }

  @override
  Future<List<Refund>> listRefunds(String invoiceId) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'SELECT * FROM ${LocalTables.refunds} WHERE invoice_id = ? ORDER BY refunded_at',
        <Object?>[invoiceId],
      );
      return rows.map(Refund.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'billing.refunds');
    }
  }

  @override
  Future<String> createInvoice(Map<String, Object?> row) async {
    final String id = const Uuid().v4();
    try {
      await _store.insert(LocalTables.invoices, <String, Object?>{
        ...row,
        'id': id,
      });
      _logger.info(
        _module,
        'Invoice draft committed locally.',
        operation: 'billing.invoice.draft',
        outcome: 'queued',
      );
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'billing.invoice.draft');
    }
  }

  @override
  Future<String> addLine(Map<String, Object?> row) async {
    final String id = const Uuid().v4();
    try {
      await _store.insert(LocalTables.invoiceLines, <String, Object?>{
        ...row,
        'id': id,
      });
      _logger.info(
        _module,
        'Invoice line committed locally.',
        operation: 'billing.line',
        outcome: 'queued',
      );
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'billing.line');
    }
  }

  @override
  Future<void> updateInvoice(String id, Map<String, Object?> changes) async {
    try {
      await _store.update(LocalTables.invoices, id, changes);
      _logger.info(
        _module,
        'Invoice transition committed locally.',
        operation: 'billing.invoice.update',
        outcome: 'queued',
      );
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'billing.invoice.update');
    }
  }

  @override
  Future<void> updateLine(String id, Map<String, Object?> changes) async {
    try {
      await _store.update(LocalTables.invoiceLines, id, changes);
      _logger.info(
        _module,
        'Invoice line transition committed locally.',
        operation: 'billing.line.update',
        outcome: 'queued',
      );
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'billing.line.update');
    }
  }

  @override
  Future<String> recordPayment(Map<String, Object?> row) async {
    final String id = const Uuid().v4();
    try {
      await _store.insert(LocalTables.payments, <String, Object?>{
        ...row,
        'id': id,
      });
      _logger.info(
        _module,
        'Payment recorded locally.',
        operation: 'billing.payment',
        outcome: 'queued',
      );
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'billing.payment');
    }
  }

  @override
  Future<String> recordRefund(Map<String, Object?> row) async {
    final String id = const Uuid().v4();
    try {
      await _store.insert(LocalTables.refunds, <String, Object?>{
        ...row,
        'id': id,
      });
      _logger.info(
        _module,
        'Refund recorded locally.',
        operation: 'billing.refund',
        outcome: 'queued',
      );
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'billing.refund');
    }
  }

  @override
  Future<PatientAccount?> getAccountForPatient(String patientId) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'SELECT * FROM ${LocalTables.patientAccounts} WHERE patient_id = ?',
        <Object?>[patientId],
      );
      if (rows.isEmpty) {
        return null;
      }
      return PatientAccount.fromRow(rows.first);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'billing.account');
    }
  }

  @override
  Future<PatientAccount?> getAccountById(String id) async {
    final Map<String, Object?>? row = await _store.getById(
      LocalTables.patientAccounts,
      id,
    );
    return row == null ? null : PatientAccount.fromRow(row);
  }

  @override
  Future<List<LedgerEntry>> listLedgerEntries(
    String accountId, {
    int limit = 200,
  }) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'SELECT * FROM ${LocalTables.ledgerEntries} WHERE account_id = ? '
        'ORDER BY occurred_at DESC',
        <Object?>[accountId],
      );
      return rows.take(limit).map(LedgerEntry.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'billing.ledger');
    }
  }

  @override
  Future<String> openAccount(Map<String, Object?> row) async {
    final String id = const Uuid().v4();
    try {
      await _store.insert(LocalTables.patientAccounts, <String, Object?>{
        ...row,
        'id': id,
      });
      _logger.info(
        _module,
        'Patient account opened locally.',
        operation: 'billing.account.open',
        outcome: 'queued',
      );
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'billing.account.open');
    }
  }

  @override
  Future<String> postLedgerEntry(Map<String, Object?> row) async {
    final String id = const Uuid().v4();
    try {
      await _store.insert(LocalTables.ledgerEntries, <String, Object?>{
        ...row,
        'id': id,
      });
      _logger.info(
        _module,
        'Ledger entry posted locally.',
        operation: 'billing.ledger.post',
        outcome: 'queued',
      );
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'billing.ledger.post');
    }
  }

  @override
  Future<List<PaymentAllocation>> listAllocations(String paymentId) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'SELECT * FROM ${LocalTables.paymentAllocations} WHERE payment_id = ?',
        <Object?>[paymentId],
      );
      return rows.map(PaymentAllocation.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'billing.allocations');
    }
  }

  @override
  Future<String> allocatePayment(Map<String, Object?> row) async {
    final String id = const Uuid().v4();
    try {
      await _store.insert(LocalTables.paymentAllocations, <String, Object?>{
        ...row,
        'id': id,
      });
      _logger.info(
        _module,
        'Payment allocation committed locally.',
        operation: 'billing.allocation',
        outcome: 'queued',
      );
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'billing.allocation');
    }
  }

  Never _mapped(Object error, StackTrace stackTrace, String operation) {
    if (error is NodexError) throw error;
    final NodexError mapped = NodexErrorMapper.map(error, operation: operation);
    _logger.error(
      _module,
      'Billing repository failure.',
      operation: operation,
      outcome: 'failed',
      errorCode: mapped.code,
      stackTrace: stackTrace,
    );
    throw mapped;
  }
}
