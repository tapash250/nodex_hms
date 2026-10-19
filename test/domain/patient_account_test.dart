/// Tests for the patient account and ledger entities (Module 31).
///
/// The journal's promise is that every event moves money once, in one
/// direction, and that the movement can be explained afterwards. These tests
/// pin the rules that make that true before anything reaches PostgreSQL: an
/// account opens at zero, a charge names its invoice, an adjustment states its
/// reason, and the two legs of an event always differ.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/billing/patient_account.dart';

LedgerEntry entryWith({
  required LedgerTransactionType type,
  required LedgerDirection direction,
  int amountMinor = 10000,
}) => LedgerEntry(
  id: 'entry-1',
  tenantId: 'tenant-1',
  accountId: 'account-1',
  transactionType: type,
  direction: direction,
  accountCode: LedgerAccountCode.patientReceivable,
  amountMinor: amountMinor,
  currency: 'BDT',
  recordedBy: 'accounts-1',
  occurredAt: DateTime.utc(2026, 9, 12, 9),
);

void main() {
  group('opening an account', () {
    test('always opens at zero balance', () {
      final Map<String, Object?> row = PatientAccount.openRow(
        tenantId: 'tenant-1',
        patientId: 'patient-1',
        accountCode: 'ACC-001',
      );
      expect(row['balance_minor'], 0);
      expect(row['status'], 'open');
      expect(row['closed_at'], isNull);
    });

    test('refuses a currency that is not an ISO code', () {
      expect(
        () => PatientAccount.openRow(
          tenantId: 'tenant-1',
          patientId: 'patient-1',
          accountCode: 'ACC-001',
          currency: 'taka',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'patient_account_invalid',
          ),
        ),
      );
    });

    test('reads a balance projection back from a row', () {
      final PatientAccount account = PatientAccount.fromRow(
        const <String, Object?>{
          'id': 'account-1',
          'tenant_id': 'tenant-1',
          'patient_id': 'patient-1',
          'account_code': 'ACC-001',
          'currency': 'BDT',
          'status': 'credit',
          'balance_minor': -2500,
          'last_activity_at': '2026-09-12T09:00:00.000Z',
          'opened_at': '2026-09-01T08:00:00.000Z',
          'closed_at': null,
        },
      );
      expect(account.balanceMinor, -2500);
      expect(account.isInCredit, isTrue);
      expect(account.isSettled, isFalse);
      expect(account.formatMinor(250000), '2500.00 BDT');
      expect(account.formatMinor(-125), '-1.25 BDT');
    });
  });

  group('posting rules', () {
    test('a charge must name the invoice it came from', () {
      expect(
        () => LedgerEntry.chargeRow(
          tenantId: 'tenant-1',
          accountId: 'account-1',
          invoiceId: 'invoice-1',
          amountMinor: 0,
          currency: 'BDT',
          recordedBy: 'accounts-1',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'ledger_entry_invalid',
          ),
        ),
      );
    });

    test('an adjustment demands a stated reason', () {
      expect(
        () => LedgerEntry.adjustmentRow(
          tenantId: 'tenant-1',
          accountId: 'account-1',
          amountMinor: 5000,
          currency: 'BDT',
          recordedBy: 'accounts-1',
          direction: LedgerDirection.credit,
          reason: '   ',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'ledger_adjustment_reason_required',
          ),
        ),
      );
    });

    test('a zero-amount event is not an event', () {
      expect(
        () => LedgerEntry.paymentRow(
          tenantId: 'tenant-1',
          accountId: 'account-1',
          paymentId: 'payment-1',
          amountMinor: -1,
          currency: 'BDT',
          recordedBy: 'accounts-1',
        ),
        throwsA(isA<ValidationError>()),
      );
    });

    test('a payment posting must name its payment', () {
      final Map<String, Object?> row = LedgerEntry.paymentRow(
        tenantId: 'tenant-1',
        accountId: 'account-1',
        paymentId: 'payment-1',
        amountMinor: 25000,
        currency: 'BDT',
        recordedBy: 'accounts-1',
      );
      expect(row['payment_id'], 'payment-1');
      expect(row['direction'], 'credit');
      expect(row['transaction_type'], 'payment');
    });
  });

  group('double entry', () {
    test('a charge debits the receivable and credits revenue', () {
      final LedgerEntry entry = entryWith(
        type: LedgerTransactionType.charge,
        direction: LedgerDirection.debit,
      );
      expect(entry.debitAccountCode, LedgerAccountCode.patientReceivable);
      expect(entry.creditAccountCode, LedgerAccountCode.revenue);
      expect(entry.isBalanced, isTrue);
      expect(entry.balanceDeltaMinor, 10000);
    });

    test('a refund debits the receivable and credits refunds payable', () {
      final LedgerEntry entry = entryWith(
        type: LedgerTransactionType.refund,
        direction: LedgerDirection.credit,
      );
      expect(entry.debitAccountCode, LedgerAccountCode.refundPayable);
      expect(entry.creditAccountCode, LedgerAccountCode.patientReceivable);
      expect(entry.balanceDeltaMinor, -10000);
    });

    test(
      'a discount reduces the receivable and lands in the discount code',
      () {
        final LedgerEntry entry = LedgerEntry(
          id: 'entry-2',
          tenantId: 'tenant-1',
          accountId: 'account-1',
          transactionType: LedgerTransactionType.discount,
          direction: LedgerDirection.credit,
          accountCode: LedgerAccountCode.patientReceivable,
          amountMinor: 3000,
          currency: 'BDT',
          recordedBy: 'accounts-1',
          occurredAt: DateTime.utc(2026, 9, 12, 10),
        );
        expect(entry.debitAccountCode, LedgerAccountCode.discount);
        expect(entry.creditAccountCode, LedgerAccountCode.patientReceivable);
      },
    );

    test('the journal balance is the sum of its events', () {
      final List<LedgerEntry> entries = <LedgerEntry>[
        entryWith(
          type: LedgerTransactionType.charge,
          direction: LedgerDirection.debit,
        ),
        entryWith(
          type: LedgerTransactionType.payment,
          direction: LedgerDirection.credit,
          amountMinor: 4000,
        ),
      ];
      expect(ledgerBalanceMinor(entries), 6000);
    });
  });

  group('allocations', () {
    test('an allocation carries the payment, the invoice and an amount', () {
      final Map<String, Object?> row = PaymentAllocation.row(
        tenantId: 'tenant-1',
        paymentId: 'payment-1',
        invoiceId: 'invoice-1',
        amountMinor: 4000,
      );
      expect(row['payment_id'], 'payment-1');
      expect(row['invoice_id'], 'invoice-1');
      expect(row['amount_minor'], 4000);
    });

    test('a split with no amount is refused', () {
      expect(
        () => PaymentAllocation.row(
          tenantId: 'tenant-1',
          paymentId: 'payment-1',
          invoiceId: 'invoice-1',
          amountMinor: 0,
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'payment_allocation_invalid',
          ),
        ),
      );
    });
  });
}
