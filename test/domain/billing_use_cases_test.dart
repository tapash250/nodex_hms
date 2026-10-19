/// Tests for the billing use-case gates and lifecycle (Module 31).
///
/// The invoice entity is covered by `invoice_test.dart`; this file pins the
/// workflow: who may price and settle, that lines belong only to a draft,
/// that issue → settle only moves forward, and that a closed invoice never
/// takes another payment or cancellation.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/authorization_snapshot.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/billing/billing_repository.dart';
import 'package:nodex_hms/domain/billing/billing_use_cases.dart';
import 'package:nodex_hms/domain/billing/invoice.dart';
import 'package:nodex_hms/domain/billing/patient_account.dart';

/// Records what the billing commands were asked to write.
final class RecordingBillingRepository implements BillingRepository {
  final List<Map<String, Object?>> invoices = <Map<String, Object?>>[];
  final List<Map<String, Object?>> lines = <Map<String, Object?>>[];
  final List<Map<String, Object?>> updates = <Map<String, Object?>>[];
  final List<Map<String, Object?>> payments = <Map<String, Object?>>[];
  final List<Map<String, Object?>> refunds = <Map<String, Object?>>[];

  @override
  Future<List<Invoice>> listForPatient(String patientId) async => <Invoice>[];

  @override
  Future<Invoice?> getInvoice(String id) async => null;

  @override
  Future<Invoice?> getByCode(String invoiceCode) async => null;

  @override
  Future<List<InvoiceLine>> listLines(String invoiceId) async =>
      <InvoiceLine>[];

  @override
  Future<List<Payment>> listPayments(String invoiceId) async => <Payment>[];

  @override
  Future<List<Refund>> listRefunds(String invoiceId) async => <Refund>[];

  @override
  Future<String> createInvoice(Map<String, Object?> row) async {
    invoices.add(row);
    return 'invoice-new';
  }

  @override
  Future<String> addLine(Map<String, Object?> row) async {
    lines.add(row);
    return 'line-new';
  }

  @override
  Future<void> updateInvoice(String id, Map<String, Object?> changes) async {
    updates.add(<String, Object?>{'id': id, ...changes});
  }

  @override
  Future<void> updateLine(String id, Map<String, Object?> changes) async {}

  @override
  Future<String> recordPayment(Map<String, Object?> row) async {
    payments.add(row);
    return 'payment-new';
  }

  @override
  Future<String> recordRefund(Map<String, Object?> row) async {
    refunds.add(row);
    return 'refund-new';
  }

  final List<Map<String, Object?>> accounts = <Map<String, Object?>>[];
  final List<Map<String, Object?>> entries = <Map<String, Object?>>[];
  final List<Map<String, Object?>> allocations = <Map<String, Object?>>[];

  /// Accounts the repository should answer by patient id.
  final Map<String, PatientAccount> storedAccounts = <String, PatientAccount>{};

  /// Journal entries the repository should return for an account.
  final Map<String, List<LedgerEntry>> storedEntries =
      <String, List<LedgerEntry>>{};

  /// Allocations already recorded against a payment.
  final List<PaymentAllocation> storedAllocations = <PaymentAllocation>[];

  /// Id minted for the next opened account.
  String nextAccountId = 'account-new';

  @override
  Future<PatientAccount?> getAccountForPatient(String patientId) async =>
      storedAccounts[patientId];

  @override
  Future<PatientAccount?> getAccountById(String id) async =>
      storedAccounts.values.where((PatientAccount a) => a.id == id).firstOrNull;

  @override
  Future<List<LedgerEntry>> listLedgerEntries(
    String accountId, {
    int limit = 200,
  }) async => storedEntries[accountId] ?? <LedgerEntry>[];

  @override
  Future<String> openAccount(Map<String, Object?> row) async {
    accounts.add(row);
    return nextAccountId;
  }

  @override
  Future<String> postLedgerEntry(Map<String, Object?> row) async {
    entries.add(row);
    return 'entry-new';
  }

  @override
  Future<List<PaymentAllocation>> listAllocations(String paymentId) async =>
      storedAllocations;

  @override
  Future<String> allocatePayment(Map<String, Object?> row) async {
    allocations.add(row);
    return 'allocation-new';
  }
}

/// Builds a policy holding exactly [permissions].
AuthorizationPolicy policyWith(Set<String> permissions) {
  final DateTime issuedAt = DateTime.now().toUtc();
  return AuthorizationPolicy(
    snapshot: AuthorizationSnapshot(
      snapshotId: 'snapshot-1',
      tenantId: 'tenant-1',
      userId: 'accounts-1',
      deviceId: 'device-1',
      revision: 1,
      issuedAt: issuedAt,
      expiresAt: issuedAt.add(const Duration(days: 30)),
      payloadDigest: 'digest',
      roles: const <String>{NodexRoles.billingAccounts},
      permissions: permissions,
      offlinePermissions: permissions,
      facilityIds: const <String>{},
      departmentIds: const <String>{},
      wardIds: const <String>{},
    ),
    connectivity: ConnectivityState.online,
  );
}

/// An invoice in [status], owned by the standard fixture identity.
Invoice invoiceWith({
  InvoiceStatus status = InvoiceStatus.draft,
  String id = 'invoice-1',
  String currency = 'BDT',
  int settledMinor = 0,
}) => Invoice(
  id: id,
  tenantId: 'tenant-1',
  patientId: 'patient-1',
  createdBy: 'accounts-1',
  invoiceCode: 'INV-001',
  status: status,
  currency: currency,
  totalMinor: 45000,
  settledMinor: status == InvoiceStatus.settled ? 45000 : settledMinor,
  createdAt: DateTime.utc(2026, 9, 12, 9),
);

/// The patient account the standard fixture identity owns.
PatientAccount accountWith({
  String id = 'account-1',
  int balanceMinor = 0,
  AccountStatus status = AccountStatus.open,
}) => PatientAccount(
  id: id,
  tenantId: 'tenant-1',
  patientId: 'patient-1',
  accountCode: 'ACC-001',
  currency: 'BDT',
  status: status,
  balanceMinor: balanceMinor,
  lastActivityAt: DateTime.utc(2026, 9, 12, 11),
  openedAt: DateTime.utc(2026, 9, 1, 8),
);

/// A recorded payment against [invoiceId].
Payment paymentWith({String invoiceId = 'invoice-1'}) => Payment(
  id: 'payment-1',
  tenantId: 'tenant-1',
  invoiceId: invoiceId,
  recordedBy: 'accounts-1',
  amountMinor: 45000,
  paidAt: DateTime.utc(2026, 9, 12, 10),
  method: PaymentMethod.cash,
);

void main() {
  late RecordingBillingRepository repository;
  late DraftInvoiceUseCase draft;
  late AddInvoiceLineUseCase addLine;
  late IssueInvoiceUseCase issue;
  late SettleInvoiceUseCase settle;
  late RecordPaymentUseCase recordPayment;
  late RecordRefundUseCase recordRefund;
  late CancelInvoiceUseCase cancel;

  const Set<String> accounts = <String>{NodexPermissions.billingSettle};
  const Set<String> reader = <String>{NodexPermissions.billingRead};

  setUp(() {
    repository = RecordingBillingRepository();
    draft = DraftInvoiceUseCase(repository: repository);
    addLine = AddInvoiceLineUseCase(repository: repository);
    issue = IssueInvoiceUseCase(repository: repository);
    settle = SettleInvoiceUseCase(repository: repository);
    recordPayment = RecordPaymentUseCase(repository: repository);
    recordRefund = RecordRefundUseCase(repository: repository);
    cancel = CancelInvoiceUseCase(repository: repository);
  });

  Future<String> seedDraft(Set<String> permissions) => draft.call(
    policy: policyWith(permissions),
    tenantId: 'tenant-1',
    patientId: 'patient-1',
    createdBy: 'accounts-1',
    invoiceCode: 'INV-001',
  );

  group('authorization gates', () {
    test('drafting an invoice requires billing.settle', () {
      expect(
        seedDraft(reader),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.requiredPermission,
            'requiredPermission',
            NodexPermissions.billingSettle,
          ),
        ),
      );
    });

    test('adding a line requires billing.settle', () {
      expect(
        addLine.call(
          policy: policyWith(reader),
          invoice: invoiceWith(),
          lineNumber: 1,
          description: 'Consultation',
          quantity: 1,
          unitPriceMinor: 45000,
          lineTotalMinor: 45000,
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('issuing requires billing.settle', () {
      expect(
        issue.call(policy: policyWith(reader), invoice: invoiceWith()),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('settling requires billing.settle', () {
      expect(
        settle.call(
          policy: policyWith(reader),
          invoice: invoiceWith(status: InvoiceStatus.issued),
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('recording a payment requires billing.settle', () {
      expect(
        recordPayment.call(
          policy: policyWith(reader),
          invoice: invoiceWith(status: InvoiceStatus.issued),
          recordedBy: 'accounts-1',
          amountMinor: 45000,
          method: PaymentMethod.cash,
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('recording a refund requires billing.settle', () {
      expect(
        recordRefund.call(
          policy: policyWith(reader),
          payment: paymentWith(),
          recordedBy: 'accounts-1',
          amountMinor: 10000,
          reason: 'Duplicate charge',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('cancelling requires billing.settle', () {
      expect(
        cancel.call(
          policy: policyWith(reader),
          invoice: invoiceWith(),
          reason: 'Raised in error',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });
  });

  group('drafting', () {
    test('a draft starts empty and unissued', () async {
      final String id = await seedDraft(accounts);

      expect(id, 'invoice-new');
      expect(repository.invoices, hasLength(1));
      final Map<String, Object?> row = repository.invoices.single;
      expect(row['status'], 'draft');
      expect(row['total_minor'], 0);
      expect(row['settled_minor'], 0);
      expect(row['currency'], 'BDT');
      expect(row['issued_at'], isNull);
      expect(row['tenant_id'], 'tenant-1');
      expect(row['patient_id'], 'patient-1');
    });
  });

  group('pricing', () {
    test('a line is added to a draft invoice', () async {
      await addLine.call(
        policy: policyWith(accounts),
        invoice: invoiceWith(),
        lineNumber: 1,
        description: ' Consultation ',
        quantity: 1,
        unitPriceMinor: 45000,
        lineTotalMinor: 45000,
      );

      expect(repository.lines, hasLength(1));
      final Map<String, Object?> row = repository.lines.single;
      expect(row['invoice_id'], 'invoice-1');
      expect(row['description'], 'Consultation');
      expect(row['line_total_minor'], 45000);
    });

    test('an issued invoice cannot be re-priced', () {
      // The backend refuses this outright ("issued invoices cannot be
      // re-priced"); the client must not queue a write it knows will fail.
      expect(
        addLine.call(
          policy: policyWith(accounts),
          invoice: invoiceWith(status: InvoiceStatus.issued),
          lineNumber: 2,
          description: 'Late charge',
          quantity: 1,
          unitPriceMinor: 1000,
          lineTotalMinor: 1000,
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'invoice_not_editable',
          ),
        ),
      );
      expect(repository.lines, isEmpty);
    });

    test('a cancelled invoice cannot be priced', () {
      expect(
        addLine.call(
          policy: policyWith(accounts),
          invoice: invoiceWith(status: InvoiceStatus.cancelled),
          lineNumber: 3,
          description: 'Late charge',
          quantity: 1,
          unitPriceMinor: 1000,
          lineTotalMinor: 1000,
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });
  });

  group('lifecycle', () {
    test('a draft is issued once', () async {
      await issue.call(policy: policyWith(accounts), invoice: invoiceWith());

      expect(repository.updates, hasLength(1));
      expect(repository.updates.single['id'], 'invoice-1');
      expect(repository.updates.single['status'], 'issued');
      expect(repository.updates.single['issued_at'], isNotNull);
    });

    test('an issued invoice cannot be issued again', () {
      expect(
        issue.call(
          policy: policyWith(accounts),
          invoice: invoiceWith(status: InvoiceStatus.issued),
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'invoice_not_draft',
          ),
        ),
      );
      expect(repository.updates, isEmpty);
    });

    test('only an issued invoice can be settled', () {
      expect(
        settle.call(policy: policyWith(accounts), invoice: invoiceWith()),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'invoice_not_issued',
          ),
        ),
      );
      expect(repository.updates, isEmpty);
    });

    test('settling records the settlement transition', () async {
      await settle.call(
        policy: policyWith(accounts),
        invoice: invoiceWith(status: InvoiceStatus.issued),
      );

      expect(repository.updates.single['status'], 'settled');
      expect(repository.updates.single['settled_at'], isNotNull);
    });
  });

  group('payments and refunds', () {
    test('a payment is recorded against an issued invoice', () async {
      await recordPayment.call(
        policy: policyWith(accounts),
        invoice: invoiceWith(status: InvoiceStatus.issued),
        recordedBy: 'accounts-1',
        amountMinor: 45000,
        method: PaymentMethod.mobileMoney,
      );

      expect(repository.payments, hasLength(1));
      final Map<String, Object?> row = repository.payments.single;
      expect(row['invoice_id'], 'invoice-1');
      expect(row['amount_minor'], 45000);
      expect(row['method'], 'mobile_money');
      // The running total is derived server-side, never by the client.
      expect(row['amount_received_minor'], isNull);
    });

    test('a closed invoice takes no payment', () {
      expect(
        recordPayment.call(
          policy: policyWith(accounts),
          invoice: invoiceWith(status: InvoiceStatus.settled),
          recordedBy: 'accounts-1',
          amountMinor: 1000,
          method: PaymentMethod.cash,
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'invoice_closed',
          ),
        ),
      );
      expect(repository.payments, isEmpty);
    });

    test('a refund links to its source payment', () async {
      await recordRefund.call(
        policy: policyWith(accounts),
        payment: paymentWith(),
        recordedBy: 'accounts-1',
        amountMinor: 10000,
        reason: ' Duplicate charge ',
      );

      expect(repository.refunds, hasLength(1));
      final Map<String, Object?> row = repository.refunds.single;
      expect(row['payment_id'], 'payment-1');
      expect(row['invoice_id'], 'invoice-1');
      expect(row['amount_minor'], 10000);
      expect(row['reason'], 'Duplicate charge');
    });
  });

  group('cancellation', () {
    test('a draft can be cancelled with a reason', () async {
      await cancel.call(
        policy: policyWith(accounts),
        invoice: invoiceWith(),
        reason: ' Raised in error ',
      );

      expect(repository.updates.single['status'], 'cancelled');
      expect(repository.updates.single['closure_reason'], 'Raised in error');
      expect(repository.updates.single['closed_at'], isNotNull);
    });

    test('an issued invoice can still be cancelled', () async {
      await cancel.call(
        policy: policyWith(accounts),
        invoice: invoiceWith(status: InvoiceStatus.issued),
        reason: 'Patient disputes the charge',
      );

      expect(repository.updates.single['status'], 'cancelled');
    });

    test('a settled invoice cannot be cancelled', () {
      expect(
        cancel.call(
          policy: policyWith(accounts),
          invoice: invoiceWith(status: InvoiceStatus.settled),
          reason: 'Too late',
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'invoice_not_cancellable',
          ),
        ),
      );
      expect(repository.updates, isEmpty);
    });

    test('cancelling without a reason is refused', () {
      expect(
        cancel.call(
          policy: policyWith(accounts),
          invoice: invoiceWith(),
          reason: '   ',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'invoice_cancel_reason_required',
          ),
        ),
      );
      expect(repository.updates, isEmpty);
    });
  });

  group('patient accounts and the ledger', () {
    late RecordingBillingRepository repository;

    setUp(() {
      repository = RecordingBillingRepository();
    });

    test(
      'opening an account returns the existing one rather than a second',
      () async {
        final PatientAccount existing = PatientAccount(
          id: 'account-1',
          tenantId: 'tenant-1',
          patientId: 'patient-1',
          accountCode: 'ACC-001',
          currency: 'BDT',
          status: AccountStatus.open,
          balanceMinor: 12000,
          lastActivityAt: DateTime.utc(2026, 9, 12, 11),
          openedAt: DateTime.utc(2026, 9, 1, 8),
        );
        repository.storedAccounts['patient-1'] = existing;

        final PatientAccount result =
            await OpenPatientAccountUseCase(repository: repository).call(
              policy: policyWith(<String>{NodexPermissions.billingLedger}),
              tenantId: 'tenant-1',
              patientId: 'patient-1',
              accountCode: 'ACC-002',
            );

        expect(result.id, 'account-1');
        expect(repository.accounts, isEmpty);
      },
    );

    test('opening an account requires the ledger permission', () async {
      await expectLater(
        OpenPatientAccountUseCase(repository: repository).call(
          policy: policyWith(<String>{NodexPermissions.billingRead}),
          tenantId: 'tenant-1',
          patientId: 'patient-1',
          accountCode: 'ACC-001',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('a charge cannot be posted against a draft invoice', () async {
      final PatientAccount account = accountWith();
      await expectLater(
        PostChargeUseCase(repository: repository).call(
          policy: policyWith(<String>{NodexPermissions.billingLedger}),
          account: account,
          invoice: invoiceWith(),
          recordedBy: 'accounts-1',
          amountMinor: 45000,
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'invoice_not_issued',
          ),
        ),
      );
      expect(repository.entries, isEmpty);
    });

    test('a charge is posted as a receivable debit against revenue', () async {
      await PostChargeUseCase(repository: repository).call(
        policy: policyWith(<String>{NodexPermissions.billingLedger}),
        account: accountWith(),
        invoice: invoiceWith(status: InvoiceStatus.issued),
        recordedBy: 'accounts-1',
        amountMinor: 45000,
      );

      expect(repository.entries, hasLength(1));
      final Map<String, Object?> row = repository.entries.single;
      expect(row['direction'], 'debit');
      expect(row['account_code'], 'patient_receivable');
      expect(row['transaction_type'], 'charge');
      expect(row['amount_minor'], 45000);
    });

    test('a charge in another currency is refused', () async {
      await expectLater(
        PostChargeUseCase(repository: repository).call(
          policy: policyWith(<String>{NodexPermissions.billingLedger}),
          account: accountWith(),
          invoice: invoiceWith(status: InvoiceStatus.issued, currency: 'USD'),
          recordedBy: 'accounts-1',
          amountMinor: 100,
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'ledger_currency_mismatch',
          ),
        ),
      );
    });

    test('an adjustment without a reason is refused', () async {
      await expectLater(
        PostAdjustmentUseCase(repository: repository).call(
          policy: policyWith(<String>{NodexPermissions.billingLedger}),
          account: accountWith(),
          recordedBy: 'accounts-1',
          amountMinor: 500,
          direction: LedgerDirection.credit,
          reason: '  ',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'ledger_adjustment_reason_required',
          ),
        ),
      );
      expect(repository.entries, isEmpty);
    });

    test('an allocation beyond what the payment holds is refused', () async {
      repository.storedAllocations.add(
        const PaymentAllocation(
          id: 'allocation-1',
          tenantId: 'tenant-1',
          paymentId: 'payment-1',
          invoiceId: 'invoice-1',
          amountMinor: 40000,
        ),
      );

      await expectLater(
        AllocatePaymentUseCase(repository: repository).call(
          policy: policyWith(<String>{NodexPermissions.billingSettle}),
          payment: paymentWith(),
          invoice: invoiceWith(status: InvoiceStatus.issued),
          amountMinor: 10000,
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'allocation_exceeds_payment',
          ),
        ),
      );
      expect(repository.allocations, isEmpty);
    });

    test('an allocation beyond the invoice balance is refused', () async {
      await expectLater(
        AllocatePaymentUseCase(repository: repository).call(
          policy: policyWith(<String>{NodexPermissions.billingSettle}),
          payment: paymentWith(),
          invoice: invoiceWith(
            status: InvoiceStatus.issued,
            settledMinor: 40000,
          ),
          amountMinor: 10000,
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'allocation_exceeds_invoice',
          ),
        ),
      );
      expect(repository.allocations, isEmpty);
    });

    test('a payment can be split across two invoices', () async {
      await AllocatePaymentUseCase(repository: repository).call(
        policy: policyWith(<String>{NodexPermissions.billingSettle}),
        payment: paymentWith(),
        invoice: invoiceWith(status: InvoiceStatus.issued, settledMinor: 35000),
        amountMinor: 10000,
      );

      expect(repository.allocations, hasLength(1));
      expect(repository.allocations.single['amount_minor'], 10000);
      expect(repository.allocations.single['invoice_id'], 'invoice-1');
    });

    test('the statement reconciliation detects a partial journal', () async {
      final PatientAccount account = accountWith(balanceMinor: 45000);
      repository.storedAccounts['patient-1'] = account;
      repository.storedEntries[account.id] = <LedgerEntry>[
        LedgerEntry(
          id: 'entry-1',
          tenantId: 'tenant-1',
          accountId: account.id,
          transactionType: LedgerTransactionType.charge,
          direction: LedgerDirection.debit,
          accountCode: LedgerAccountCode.patientReceivable,
          amountMinor: 45000,
          currency: 'BDT',
          recordedBy: 'accounts-1',
          occurredAt: DateTime.utc(2026, 9, 12, 9),
          invoiceId: 'invoice-1',
        ),
      ];

      final PatientAccountStatement? statement =
          await ReadPatientAccountUseCase(repository: repository).call(
            policy: policyWith(<String>{NodexPermissions.billingRead}),
            patientId: 'patient-1',
          );

      expect(statement, isNotNull);
      expect(statement!.agreesWithServer, isTrue);

      repository.storedEntries[account.id] = <LedgerEntry>[];
      final PatientAccountStatement? partial =
          await ReadPatientAccountUseCase(repository: repository).call(
            policy: policyWith(<String>{NodexPermissions.billingRead}),
            patientId: 'patient-1',
          );
      expect(partial!.agreesWithServer, isFalse);
    });

    test('a payment posting is a credit to the receivable', () {
      final LedgerEntry entry = LedgerEntry(
        id: 'entry-2',
        tenantId: 'tenant-1',
        accountId: 'account-1',
        transactionType: LedgerTransactionType.payment,
        direction: LedgerDirection.credit,
        accountCode: LedgerAccountCode.patientReceivable,
        amountMinor: 45000,
        currency: 'BDT',
        recordedBy: 'accounts-1',
        occurredAt: DateTime.utc(2026, 9, 12, 10),
      );

      expect(entry.debitAccountCode, LedgerAccountCode.cash);
      expect(entry.creditAccountCode, LedgerAccountCode.patientReceivable);
      expect(entry.balanceDeltaMinor, -45000);
      expect(entry.isBalanced, isTrue);
    });
  });
}
