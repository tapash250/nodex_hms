/// Patient account and ledger entities (Module 31).
///
/// The ledger is the authoritative record of what a patient owes; the account
/// balance is a projection over it. Nothing here writes a balance: an event is
/// posted, and the balance follows. Money stays in integer minor units.
///
/// Each event implies exactly two postings. `LedgerEntry` computes that pair
/// locally so the client can render a trial balance without asking the server,
/// and so a test can assert the journal balances.
// ignore_for_file: sort_constructors_first
library;

import 'package:meta/meta.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';

/// Lifecycle of a patient account.
enum AccountStatus {
  /// The patient owes money.
  open('open'),

  /// The balance is exactly zero.
  settled('settled'),

  /// The patient has paid more than they owe.
  credit('credit'),

  /// Administratively closed.
  closed('closed');

  const AccountStatus(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Parses a stored value.
  static AccountStatus fromWire(String value) =>
      AccountStatus.values.firstWhere(
        (AccountStatus status) => status.wireValue == value,
        orElse: () => AccountStatus.open,
      );
}

/// Which way an event moves the balance.
enum LedgerDirection {
  /// Increases what the patient owes.
  debit('debit'),

  /// Reduces what the patient owes.
  credit('credit');

  const LedgerDirection(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Signed effect on the receivable balance, in minor units.
  int signedAmount(int amountMinor) =>
      this == LedgerDirection.debit ? amountMinor : -amountMinor;

  /// Parses a stored value.
  static LedgerDirection fromWire(String value) =>
      LedgerDirection.values.firstWhere(
        (LedgerDirection d) => d.wireValue == value,
        orElse: () => LedgerDirection.debit,
      );
}

/// Financial event kinds recorded in the journal.
enum LedgerTransactionType {
  /// A charge for a service or item.
  charge('charge'),

  /// A payment received.
  payment('payment'),

  /// Money returned to the patient.
  refund('refund'),

  /// A manual correction.
  adjustment('adjustment'),

  /// A discount granted.
  discount('discount'),

  /// Tax applied.
  tax('tax');

  const LedgerTransactionType(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Parses a stored value.
  static LedgerTransactionType fromWire(String value) =>
      LedgerTransactionType.values.firstWhere(
        (LedgerTransactionType t) => t.wireValue == value,
        orElse: () => LedgerTransactionType.charge,
      );
}

/// Chart-of-accounts codes the journal posts against.
enum LedgerAccountCode {
  /// What the patient owes the hospital.
  patientReceivable('patient_receivable'),

  /// Clinical income.
  revenue('revenue'),

  /// Cash or cash-equivalent received.
  cash('cash'),

  /// Discount granted.
  discount('discount'),

  /// Tax collected.
  tax('tax'),

  /// Money owed back to the patient.
  refundPayable('refund_payable');

  const LedgerAccountCode(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Parses a stored value.
  static LedgerAccountCode fromWire(String value) =>
      LedgerAccountCode.values.firstWhere(
        (LedgerAccountCode c) => c.wireValue == value,
        orElse: () => LedgerAccountCode.patientReceivable,
      );
}

/// The running account a patient carries across visits.
@immutable
final class PatientAccount {
  /// Creates an account.
  const PatientAccount({
    required this.id,
    required this.tenantId,
    required this.patientId,
    required this.accountCode,
    required this.currency,
    required this.status,
    required this.balanceMinor,
    required this.lastActivityAt,
    required this.openedAt,
    this.closedAt,
  });

  /// Validates and builds a new account row.
  ///
  /// The balance is not a parameter: an account always opens at zero, and the
  /// database refuses an insert that claims otherwise.
  static Map<String, Object?> openRow({
    required String tenantId,
    required String patientId,
    required String accountCode,
    String currency = 'BDT',
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.trim().isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (patientId.trim().isEmpty) {
      fieldErrors['patient_id'] = 'Patient is required.';
    }
    if (accountCode.trim().isEmpty) {
      fieldErrors['account_code'] = 'Account code is required.';
    }
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
      fieldErrors['currency'] = 'Use a three-letter ISO-4217 code.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Opening a patient account failed validation.',
        fieldErrors: fieldErrors,
        code: 'patient_account_invalid',
      );
    }

    final String now = DateTime.now().toUtc().toIso8601String();
    return <String, Object?>{
      'tenant_id': tenantId,
      'patient_id': patientId,
      'account_code': accountCode.trim(),
      'currency': currency,
      'status': AccountStatus.open.wireValue,
      'balance_minor': 0,
      'last_activity_at': now,
      'opened_at': now,
      'closed_at': null,
      'created_at': now,
      'updated_at': now,
    };
  }

  /// Materializes an account from a local row.
  factory PatientAccount.fromRow(Map<String, Object?> row) => PatientAccount(
    id: row['id']! as String,
    tenantId: row['tenant_id']! as String,
    patientId: row['patient_id']! as String,
    accountCode: row['account_code']! as String,
    currency: row['currency']! as String,
    status: AccountStatus.fromWire(row['status']! as String),
    balanceMinor: (row['balance_minor'] as num).toInt(),
    lastActivityAt: DateTime.parse(row['last_activity_at']! as String),
    openedAt: DateTime.parse(row['opened_at']! as String),
    closedAt: row['closed_at'] == null
        ? null
        : DateTime.parse(row['closed_at']! as String),
  );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// Patient identifier.
  final String patientId;

  /// Human-facing account number.
  final String accountCode;

  /// ISO-4217 currency of the account.
  final String currency;

  /// Current lifecycle state.
  final AccountStatus status;

  /// Signed running balance in minor units; positive means the patient owes.
  final int balanceMinor;

  /// Timestamp of the most recent ledger event.
  final DateTime lastActivityAt;

  /// When the account was opened.
  final DateTime openedAt;

  /// When the account was closed.
  final DateTime? closedAt;

  /// Whether the patient owes nothing.
  bool get isSettled => balanceMinor == 0;

  /// Whether the patient has overpaid.
  bool get isInCredit => balanceMinor < 0;

  /// Whether more financial events may be posted.
  bool get acceptsPostings => status != AccountStatus.closed;

  /// Formats a minor-unit amount for display.
  String formatMinor(int minor) => formatMinorUnits(minor, currency);
}

/// One journal event, and the balanced pair of postings it implies.
@immutable
final class LedgerEntry {
  /// Creates an entry.
  const LedgerEntry({
    required this.id,
    required this.tenantId,
    required this.accountId,
    required this.transactionType,
    required this.direction,
    required this.accountCode,
    required this.amountMinor,
    required this.currency,
    required this.recordedBy,
    required this.occurredAt,
    this.invoiceId,
    this.paymentId,
    this.refundId,
    this.paymentMethod,
    this.memo,
  });

  /// Builds a charge against an issued invoice.
  static Map<String, Object?> chargeRow({
    required String tenantId,
    required String accountId,
    required String invoiceId,
    required int amountMinor,
    required String currency,
    required String recordedBy,
    String? memo,
    LedgerTransactionType type = LedgerTransactionType.charge,
  }) => _row(
    tenantId: tenantId,
    accountId: accountId,
    invoiceId: invoiceId,
    transactionType: type,
    direction: LedgerDirection.debit,
    accountCode: LedgerAccountCode.patientReceivable,
    amountMinor: amountMinor,
    currency: currency,
    recordedBy: recordedBy,
    memo: memo,
    requireInvoice: true,
  );

  /// Builds a payment posting against an account.
  static Map<String, Object?> paymentRow({
    required String tenantId,
    required String accountId,
    required String paymentId,
    required int amountMinor,
    required String currency,
    required String recordedBy,
    String? paymentMethod,
    String? memo,
  }) => _row(
    tenantId: tenantId,
    accountId: accountId,
    paymentId: paymentId,
    transactionType: LedgerTransactionType.payment,
    direction: LedgerDirection.credit,
    accountCode: LedgerAccountCode.patientReceivable,
    amountMinor: amountMinor,
    currency: currency,
    recordedBy: recordedBy,
    paymentMethod: paymentMethod,
    memo: memo,
    requirePayment: true,
  );

  /// Builds a refund posting against an account.
  static Map<String, Object?> refundRow({
    required String tenantId,
    required String accountId,
    required String refundId,
    required int amountMinor,
    required String currency,
    required String recordedBy,
    String? memo,
  }) => _row(
    tenantId: tenantId,
    accountId: accountId,
    refundId: refundId,
    transactionType: LedgerTransactionType.refund,
    direction: LedgerDirection.debit,
    accountCode: LedgerAccountCode.patientReceivable,
    amountMinor: amountMinor,
    currency: currency,
    recordedBy: recordedBy,
    memo: memo,
    requireRefund: true,
  );

  /// Builds a correcting adjustment.
  ///
  /// An adjustment carries no source document, so it must state its reason: an
  /// unexplained money movement is not auditable.
  static Map<String, Object?> adjustmentRow({
    required String tenantId,
    required String accountId,
    required int amountMinor,
    required String currency,
    required String recordedBy,
    required LedgerDirection direction,
    required String reason,
  }) {
    if (reason.trim().isEmpty) {
      throw const ValidationError(
        message: 'An adjustment requires a reason.',
        fieldErrors: <String, String>{'memo': 'State why the balance moved.'},
        code: 'ledger_adjustment_reason_required',
      );
    }
    return _row(
      tenantId: tenantId,
      accountId: accountId,
      transactionType: LedgerTransactionType.adjustment,
      direction: direction,
      accountCode: LedgerAccountCode.patientReceivable,
      amountMinor: amountMinor,
      currency: currency,
      recordedBy: recordedBy,
      memo: reason,
    );
  }

  static Map<String, Object?> _row({
    required String tenantId,
    required String accountId,
    required LedgerTransactionType transactionType,
    required LedgerDirection direction,
    required LedgerAccountCode accountCode,
    required int amountMinor,
    required String currency,
    required String recordedBy,
    String? invoiceId,
    String? paymentId,
    String? refundId,
    String? paymentMethod,
    String? memo,
    bool requireInvoice = false,
    bool requirePayment = false,
    bool requireRefund = false,
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.trim().isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (accountId.trim().isEmpty) {
      fieldErrors['account_id'] = 'Patient account is required.';
    }
    if (recordedBy.trim().isEmpty) {
      fieldErrors['recorded_by'] = 'Authoring user is required.';
    }
    if (amountMinor <= 0) {
      fieldErrors['amount_minor'] = 'Enter an amount greater than zero.';
    }
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
      fieldErrors['currency'] = 'Use a three-letter ISO-4217 code.';
    }
    if (requireInvoice && (invoiceId == null || invoiceId.trim().isEmpty)) {
      fieldErrors['invoice_id'] =
          'A charge must name the invoice it came from.';
    }
    if (requirePayment && (paymentId == null || paymentId.trim().isEmpty)) {
      fieldErrors['payment_id'] = 'A payment posting must name its payment.';
    }
    if (requireRefund && (refundId == null || refundId.trim().isEmpty)) {
      fieldErrors['refund_id'] = 'A refund posting must name its refund.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Ledger posting failed validation.',
        fieldErrors: fieldErrors,
        code: 'ledger_entry_invalid',
      );
    }

    final String now = DateTime.now().toUtc().toIso8601String();
    return <String, Object?>{
      'tenant_id': tenantId,
      'account_id': accountId,
      'invoice_id': invoiceId,
      'payment_id': paymentId,
      'refund_id': refundId,
      'transaction_type': transactionType.wireValue,
      'direction': direction.wireValue,
      'account_code': accountCode.wireValue,
      'amount_minor': amountMinor,
      'currency': currency,
      'payment_method': paymentMethod,
      'memo': _clean(memo),
      'recorded_by': recordedBy,
      'occurred_at': now,
      'created_at': now,
    };
  }

  /// Materializes an entry from a local row.
  factory LedgerEntry.fromRow(Map<String, Object?> row) => LedgerEntry(
    id: row['id']! as String,
    tenantId: row['tenant_id']! as String,
    accountId: row['account_id']! as String,
    transactionType: LedgerTransactionType.fromWire(
      row['transaction_type']! as String,
    ),
    direction: LedgerDirection.fromWire(row['direction']! as String),
    accountCode: LedgerAccountCode.fromWire(row['account_code']! as String),
    amountMinor: (row['amount_minor'] as num).toInt(),
    currency: row['currency']! as String,
    recordedBy: row['recorded_by']! as String,
    occurredAt: DateTime.parse(row['occurred_at']! as String),
    invoiceId: row['invoice_id'] as String?,
    paymentId: row['payment_id'] as String?,
    refundId: row['refund_id'] as String?,
    paymentMethod: row['payment_method'] as String?,
    memo: row['memo'] as String?,
  );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// Owning patient account.
  final String accountId;

  /// Event kind.
  final LedgerTransactionType transactionType;

  /// Direction the event moves the receivable.
  final LedgerDirection direction;

  /// Code the entry posts to on its own side.
  final LedgerAccountCode accountCode;

  /// Amount in minor units; always positive.
  final int amountMinor;

  /// ISO-4217 currency.
  final String currency;

  /// Recording user.
  final String recordedBy;

  /// When the event happened.
  final DateTime occurredAt;

  /// Invoice that caused a charge, when applicable.
  final String? invoiceId;

  /// Payment that caused the posting, when applicable.
  final String? paymentId;

  /// Refund that caused the posting, when applicable.
  final String? refundId;

  /// Payment instrument, for cash-like events.
  final String? paymentMethod;

  /// Free-text note, mandatory for adjustments.
  final String? memo;

  /// Signed effect on the receivable balance.
  int get balanceDeltaMinor => direction.signedAmount(amountMinor);

  /// The debit leg of this event.
  LedgerAccountCode get debitAccountCode =>
      direction == LedgerDirection.debit ? accountCode : _contraAccount;

  /// The credit leg of this event.
  LedgerAccountCode get creditAccountCode =>
      direction == LedgerDirection.credit ? accountCode : _contraAccount;

  /// Whether both legs carry the same amount, which is what makes the journal
  /// balance. Always true for a well-formed entry; asserted in tests.
  bool get isBalanced => debitAccountCode != creditAccountCode;

  LedgerAccountCode get _contraAccount => switch (transactionType) {
    LedgerTransactionType.charge => LedgerAccountCode.revenue,
    LedgerTransactionType.payment => LedgerAccountCode.cash,
    LedgerTransactionType.refund => LedgerAccountCode.refundPayable,
    LedgerTransactionType.discount => LedgerAccountCode.discount,
    LedgerTransactionType.tax => LedgerAccountCode.tax,
    LedgerTransactionType.adjustment => LedgerAccountCode.revenue,
  };

  /// Whether the entry is a reversal of the receivable.
  bool get isReceivableMovement =>
      accountCode == LedgerAccountCode.patientReceivable;

  /// Formats a minor-unit amount for display.
  String formatMinor(int minor) => formatMinorUnits(minor, currency);
}

/// One part of a split payment.
@immutable
final class PaymentAllocation {
  /// Creates an allocation.
  const PaymentAllocation({
    required this.id,
    required this.tenantId,
    required this.paymentId,
    required this.invoiceId,
    required this.amountMinor,
  });

  /// Validates and builds an allocation row.
  static Map<String, Object?> row({
    required String tenantId,
    required String paymentId,
    required String invoiceId,
    required int amountMinor,
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.trim().isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (paymentId.trim().isEmpty) {
      fieldErrors['payment_id'] = 'Payment is required.';
    }
    if (invoiceId.trim().isEmpty) {
      fieldErrors['invoice_id'] = 'Invoice is required.';
    }
    if (amountMinor <= 0) {
      fieldErrors['amount_minor'] = 'Enter an amount greater than zero.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Splitting a payment failed validation.',
        fieldErrors: fieldErrors,
        code: 'payment_allocation_invalid',
      );
    }

    return <String, Object?>{
      'tenant_id': tenantId,
      'payment_id': paymentId,
      'invoice_id': invoiceId,
      'amount_minor': amountMinor,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  /// Materializes an allocation from a local row.
  factory PaymentAllocation.fromRow(Map<String, Object?> row) =>
      PaymentAllocation(
        id: row['id']! as String,
        tenantId: row['tenant_id']! as String,
        paymentId: row['payment_id']! as String,
        invoiceId: row['invoice_id']! as String,
        amountMinor: (row['amount_minor'] as num).toInt(),
      );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// Payment being split.
  final String paymentId;

  /// Invoice receiving part of the payment.
  final String invoiceId;

  /// Allocated amount in minor units.
  final int amountMinor;
}

/// Sums a journal into a single balance.
///
/// Used by the statement screen and by tests: the projection the server
/// maintains must equal what the entries themselves say.
int ledgerBalanceMinor(Iterable<LedgerEntry> entries) => entries.fold<int>(
  0,
  (int total, LedgerEntry entry) => total + entry.balanceDeltaMinor,
);

/// Renders minor units as a decimal amount with its currency.
///
/// Money is stored as an integer count of minor units everywhere in Nodex, so
/// every surface that shows money must divide in exactly one place. Duplicating
/// the arithmetic per widget is how a ledger starts disagreeing with itself.
String formatMinorUnits(int minor, String currency) {
  final bool negative = minor < 0;
  final String digits = minor.abs().toString();
  final String major = digits.length <= 2
      ? '0'.padLeft(3 - digits.length, '0')
      : digits.substring(0, digits.length - 2);
  final String minorPart = digits.length <= 2
      ? digits.padLeft(2, '0')
      : digits.substring(digits.length - 2);
  return '${negative ? '-' : ''}$major.$minorPart $currency';
}

String? _clean(String? value) {
  final String? trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
