/// Billing entities (Module 31).
///
/// Money is stored in integer minor units with an ISO-4217 currency code, never
/// as a floating-point amount: a half-paisa rounding error in a financial
/// settlement is a defect, and binary floating point cannot represent decimal
/// currency exactly.
// ignore_for_file: sort_constructors_first
library;

import 'package:meta/meta.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';

/// Invoice lifecycle.
enum InvoiceStatus {
  /// Editable draft, not yet issued.
  draft('draft'),

  /// Issued to the patient/payer.
  issued('issued'),

  /// Fully paid.
  settled('settled'),

  /// Cancelled with a reason.
  cancelled('cancelled');

  const InvoiceStatus(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Whether the invoice can still be edited.
  bool get isEditable =>
      this == InvoiceStatus.draft || this == InvoiceStatus.issued;

  /// Whether the record reached a terminal state.
  bool get isTerminal =>
      this == InvoiceStatus.settled || this == InvoiceStatus.cancelled;

  /// Parses a stored value.
  static InvoiceStatus fromWire(String value) =>
      InvoiceStatus.values.firstWhere(
        (InvoiceStatus status) => status.wireValue == value,
        orElse: () => InvoiceStatus.draft,
      );
}

/// Payment method.
enum PaymentMethod {
  /// Cash payment.
  cash('cash'),

  /// Card payment.
  card('card'),

  /// Mobile money transfer.
  mobileMoney('mobile_money'),

  /// Bank transfer.
  bankTransfer('bank_transfer'),

  /// Insurance claim.
  insurance('insurance'),

  /// Waiver/write-off.
  waiver('waiver');

  const PaymentMethod(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    PaymentMethod.cash => 'Cash',
    PaymentMethod.card => 'Card',
    PaymentMethod.mobileMoney => 'Mobile money',
    PaymentMethod.bankTransfer => 'Bank transfer',
    PaymentMethod.insurance => 'Insurance',
    PaymentMethod.waiver => 'Waiver',
  };

  /// Parses a stored value.
  static PaymentMethod fromWire(String value) =>
      PaymentMethod.values.firstWhere(
        (PaymentMethod method) => method.wireValue == value,
        orElse: () => PaymentMethod.cash,
      );
}

/// Invoice header.
@immutable
final class Invoice {
  /// Creates an invoice.
  const Invoice({
    required this.id,
    required this.tenantId,
    required this.patientId,
    required this.createdBy,
    required this.invoiceCode,
    required this.status,
    required this.currency,
    required this.totalMinor,
    required this.settledMinor,
    required this.createdAt,
    this.encounterId,
    this.notes,
    this.issuedAt,
    this.settledAt,
    this.closedAt,
    this.closureReason,
  });

  /// Validates and builds a new draft row.
  static Map<String, Object?> draftRow({
    required String tenantId,
    required String patientId,
    required String createdBy,
    required String invoiceCode,
    String? encounterId,
    String? notes,
    String currency = 'BDT',
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (patientId.isEmpty) {
      fieldErrors['patient_id'] = 'Patient is required.';
    }
    if (createdBy.isEmpty) {
      fieldErrors['created_by'] = 'Authoring user is required.';
    }
    if (invoiceCode.trim().isEmpty) {
      fieldErrors['invoice_code'] = 'Invoice code is required.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Invoice draft failed validation.',
        fieldErrors: fieldErrors,
        code: 'invoice_invalid',
      );
    }

    final String now = DateTime.now().toUtc().toIso8601String();
    return <String, Object?>{
      'tenant_id': tenantId,
      'patient_id': patientId,
      'encounter_id': encounterId,
      'created_by': createdBy,
      'invoice_code': invoiceCode.trim(),
      'status': InvoiceStatus.draft.wireValue,
      'currency': currency,
      'total_minor': 0,
      'settled_minor': 0,
      'notes': _clean(notes),
      'issued_at': null,
      'settled_at': null,
      'closed_at': null,
      'closure_reason': null,
      'created_at': now,
      'updated_at': now,
    };
  }

  /// Builds the issue transition.
  static Map<String, Object?> issueChanges() {
    final String now = DateTime.now().toUtc().toIso8601String();
    return <String, Object?>{
      'status': InvoiceStatus.issued.wireValue,
      'issued_at': now,
      'updated_at': now,
    };
  }

  /// Builds the settlement transition.
  static Map<String, Object?> settleChanges() {
    final String now = DateTime.now().toUtc().toIso8601String();
    return <String, Object?>{
      'status': InvoiceStatus.settled.wireValue,
      'settled_at': now,
      'updated_at': now,
    };
  }

  /// Builds the cancellation transition.
  static Map<String, Object?> cancelChanges({required String reason}) {
    if (reason.trim().isEmpty) {
      throw const ValidationError(
        message: 'Cancelling an invoice requires a reason.',
        fieldErrors: <String, String>{'reason': 'Enter the cancel reason.'},
        code: 'invoice_cancel_reason_required',
      );
    }
    final String now = DateTime.now().toUtc().toIso8601String();
    return <String, Object?>{
      'status': InvoiceStatus.cancelled.wireValue,
      'closed_at': now,
      'closure_reason': reason.trim(),
      'updated_at': now,
    };
  }

  /// Materializes an invoice from a local row.
  factory Invoice.fromRow(Map<String, Object?> row) => Invoice(
    id: row['id']! as String,
    tenantId: row['tenant_id']! as String,
    patientId: row['patient_id']! as String,
    createdBy: row['created_by']! as String,
    invoiceCode: row['invoice_code']! as String,
    status: InvoiceStatus.fromWire(row['status']! as String),
    currency: row['currency']! as String,
    totalMinor: (row['total_minor'] as num).toInt(),
    settledMinor: (row['settled_minor'] as num).toInt(),
    createdAt: DateTime.parse(row['created_at']! as String),
    encounterId: row['encounter_id'] as String?,
    notes: row['notes'] as String?,
    issuedAt: row['issued_at'] == null
        ? null
        : DateTime.parse(row['issued_at']! as String),
    settledAt: row['settled_at'] == null
        ? null
        : DateTime.parse(row['settled_at']! as String),
    closedAt: row['closed_at'] == null
        ? null
        : DateTime.parse(row['closed_at']! as String),
    closureReason: row['closure_reason'] as String?,
  );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// Patient identifier.
  final String patientId;

  /// Authoring user.
  final String createdBy;

  /// Tenant-scoped invoice code.
  final String invoiceCode;

  /// Current invoice state.
  final InvoiceStatus status;

  /// ISO-4217 currency code.
  final String currency;

  /// Line total, in minor units.
  final int totalMinor;

  /// Settled amount, in minor units.
  final int settledMinor;

  /// When created.
  final DateTime createdAt;

  /// Optional encounter identifier.
  final String? encounterId;

  /// Free-text notes.
  final String? notes;

  /// Issue timestamp.
  final DateTime? issuedAt;

  /// Settlement timestamp.
  final DateTime? settledAt;

  /// Cancellation timestamp.
  final DateTime? closedAt;

  /// Cancellation reason.
  final String? closureReason;

  static String? _clean(String? value) {
    final String? trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  /// Formats a minor-unit amount for display.
  String formatMinor(int minor) {
    final bool neg = minor < 0;
    final String s = minor.abs().toString();
    final String major = s.length <= 2
        ? '0'.padLeft(3 - s.length, '0')
        : s.substring(0, s.length - 2);
    final String minorStr = s.length <= 2
        ? s.padLeft(2, '0')
        : s.substring(s.length - 2);
    return '${neg ? '-' : ''}$major.$minorStr $currency';
  }
}

/// One line on an invoice.
@immutable
final class InvoiceLine {
  /// Creates a line.
  const InvoiceLine({
    required this.id,
    required this.tenantId,
    required this.invoiceId,
    required this.lineNumber,
    required this.description,
    required this.quantity,
    required this.unitPriceMinor,
    required this.lineTotalMinor,
  });

  /// Builds a draft line row.
  static Map<String, Object?> draftRow({
    required String tenantId,
    required String invoiceId,
    required int lineNumber,
    required String description,
    required double quantity,
    required int unitPriceMinor,
    required int lineTotalMinor,
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (invoiceId.isEmpty) {
      fieldErrors['invoice_id'] = 'Invoice is required.';
    }
    if (lineNumber <= 0) {
      fieldErrors['line_number'] = 'Line number must be positive.';
    }
    if (description.trim().isEmpty) {
      fieldErrors['description'] = 'Description is required.';
    }
    if (quantity <= 0) {
      fieldErrors['quantity'] = 'Quantity must be positive.';
    }
    if (unitPriceMinor < 0) {
      fieldErrors['unit_price_minor'] = 'Unit price cannot be negative.';
    }
    if (lineTotalMinor < 0) {
      fieldErrors['line_total_minor'] = 'Line total cannot be negative.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Invoice line failed validation.',
        fieldErrors: fieldErrors,
        code: 'invoice_line_invalid',
      );
    }
    final String now = DateTime.now().toUtc().toIso8601String();
    return <String, Object?>{
      'tenant_id': tenantId,
      'invoice_id': invoiceId,
      'line_number': lineNumber,
      'description': description.trim(),
      'quantity': quantity,
      'unit_price_minor': unitPriceMinor,
      'line_total_minor': lineTotalMinor,
      'created_at': now,
      'updated_at': now,
    };
  }

  /// Materializes a line from a local row.
  factory InvoiceLine.fromRow(Map<String, Object?> row) => InvoiceLine(
    id: row['id']! as String,
    tenantId: row['tenant_id']! as String,
    invoiceId: row['invoice_id']! as String,
    lineNumber: (row['line_number'] as num).toInt(),
    description: row['description']! as String,
    quantity: (row['quantity'] as num).toDouble(),
    unitPriceMinor: (row['unit_price_minor'] as num).toInt(),
    lineTotalMinor: (row['line_total_minor'] as num).toInt(),
  );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// Parent invoice identifier.
  final String invoiceId;

  /// Stable line position within the invoice.
  final int lineNumber;

  /// Description.
  final String description;

  /// Quantity.
  final double quantity;

  /// Unit price in minor units.
  final int unitPriceMinor;

  /// Line total in minor units.
  final int lineTotalMinor;
}

/// Payment event.
@immutable
final class Payment {
  /// Creates a payment.
  const Payment({
    required this.id,
    required this.tenantId,
    required this.invoiceId,
    required this.recordedBy,
    required this.amountMinor,
    required this.paidAt,
    required this.method,
    this.amountReceivedMinor,
    this.reference,
    this.note,
  });

  /// Builds a payment event row.
  static Map<String, Object?> eventRow({
    required String tenantId,
    required String invoiceId,
    required String recordedBy,
    required int amountMinor,
    required PaymentMethod method,
    String? reference,
    String? note,
  }) {
    if (tenantId.isEmpty || invoiceId.isEmpty || recordedBy.isEmpty) {
      throw const ValidationError(
        message: 'Payment is missing a required identity field.',
        code: 'payment_invalid',
      );
    }
    if (amountMinor == 0) {
      throw const ValidationError(
        message: 'Payment amount cannot be zero.',
        fieldErrors: <String, String>{
          'amount_minor': 'Enter a non-zero amount.',
        },
        code: 'payment_amount_required',
      );
    }
    final String now = DateTime.now().toUtc().toIso8601String();
    return <String, Object?>{
      'tenant_id': tenantId,
      'invoice_id': invoiceId,
      'recorded_by': recordedBy,
      'amount_minor': amountMinor,
      'amount_received_minor': null, // always derived server-side
      'method': method.wireValue,
      'reference': reference?.trim(),
      'note': note?.trim(),
      'paid_at': now,
      'created_at': now,
    };
  }

  /// Materializes a payment from a local row.
  factory Payment.fromRow(Map<String, Object?> row) => Payment(
    id: row['id']! as String,
    tenantId: row['tenant_id']! as String,
    invoiceId: row['invoice_id']! as String,
    recordedBy: row['recorded_by']! as String,
    amountMinor: (row['amount_minor'] as num).toInt(),
    paidAt: DateTime.parse(row['paid_at']! as String),
    method: PaymentMethod.fromWire(row['method']! as String),
    amountReceivedMinor: row['amount_received_minor'] == null
        ? null
        : (row['amount_received_minor'] as num).toInt(),
    reference: row['reference'] as String?,
    note: row['note'] as String?,
  );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// Parent invoice identifier.
  final String invoiceId;

  /// Recording user.
  final String recordedBy;

  /// Amount paid, in minor units.
  final int amountMinor;

  /// Running total including this payment, derived server-side.
  final int? amountReceivedMinor;

  /// Payment method.
  final PaymentMethod method;

  /// External reference.
  final String? reference;

  /// Note.
  final String? note;

  /// When paid.
  final DateTime paidAt;
}

/// Refund event.
@immutable
final class Refund {
  /// Creates a refund.
  const Refund({
    required this.id,
    required this.tenantId,
    required this.invoiceId,
    required this.paymentId,
    required this.recordedBy,
    required this.amountMinor,
    required this.reason,
    required this.refundedAt,
  });

  /// Builds a refund event row.
  static Map<String, Object?> eventRow({
    required String tenantId,
    required String invoiceId,
    required String paymentId,
    required String recordedBy,
    required int amountMinor,
    required String reason,
  }) {
    if (tenantId.isEmpty ||
        invoiceId.isEmpty ||
        paymentId.isEmpty ||
        recordedBy.isEmpty) {
      throw const ValidationError(
        message: 'Refund is missing a required identity field.',
        code: 'refund_invalid',
      );
    }
    if (amountMinor <= 0) {
      throw const ValidationError(
        message: 'Refund amount must be positive.',
        fieldErrors: <String, String>{
          'amount_minor': 'Enter a positive amount.',
        },
        code: 'refund_amount_required',
      );
    }
    final String now = DateTime.now().toUtc().toIso8601String();
    return <String, Object?>{
      'tenant_id': tenantId,
      'invoice_id': invoiceId,
      'payment_id': paymentId,
      'recorded_by': recordedBy,
      'amount_minor': amountMinor,
      'reason': reason.trim(),
      'refunded_at': now,
      'created_at': now,
    };
  }

  /// Materializes a refund from a local row.
  factory Refund.fromRow(Map<String, Object?> row) => Refund(
    id: row['id']! as String,
    tenantId: row['tenant_id']! as String,
    invoiceId: row['invoice_id']! as String,
    paymentId: row['payment_id']! as String,
    recordedBy: row['recorded_by']! as String,
    amountMinor: (row['amount_minor'] as num).toInt(),
    reason: row['reason']! as String,
    refundedAt: DateTime.parse(row['refunded_at']! as String),
  );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// Parent invoice identifier.
  final String invoiceId;

  /// Source payment identifier.
  final String paymentId;

  /// Recording user.
  final String recordedBy;

  /// Refund amount in minor units.
  final int amountMinor;

  /// Reason.
  final String reason;

  /// When refunded.
  final DateTime refundedAt;
}
