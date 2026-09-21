import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart' show NodexError;
import 'package:nodex_hms/domain/billing/invoice.dart';
import 'package:nodex_hms/domain/session/session_state.dart' show SessionState;
import 'package:nodex_hms/features/billing/billing_controller.dart';
import 'package:nodex_hms/features/session/session_controller.dart'
    show sessionProvider;

/// Detail screen for one invoice.
class InvoiceDetailScreen extends ConsumerWidget {
  /// Creates the screen.
  const InvoiceDetailScreen({required this.invoiceId, super.key});

  /// Local invoice id.
  final String invoiceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Invoice> detail = ref.watch(
      invoiceDetailProvider(invoiceId),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Invoice')),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace _) => _BillingError(
          error: error,
          onRetry: () => ref.invalidate(invoiceDetailProvider(invoiceId)),
        ),
        data: (Invoice value) => _InvoiceBody(value: value),
      ),
    );
  }
}

class _InvoiceBody extends ConsumerWidget {
  const _InvoiceBody({required this.value});

  final Invoice value;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final SessionState session = ref.watch(sessionProvider);
    final bool canSettle = session.authorization.can(
      NodexPermissions.billingSettle,
    );
    final bool canDraft = session.authorization.can(
      NodexPermissions.billingSettle,
    );
    final AsyncValue<List<InvoiceLine>> lines = ref.watch(
      invoiceLinesProvider(value.id),
    );
    final AsyncValue<List<Payment>> payments = ref.watch(
      invoicePaymentsProvider(value.id),
    );
    final AsyncValue<List<Refund>> refunds = ref.watch(
      invoiceRefundsProvider(value.id),
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(value.invoiceCode, style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                _BillFact(label: 'Currency', value: value.currency),
                _BillFact(
                  label: 'Total',
                  value: value.formatMinor(value.totalMinor),
                ),
                _BillFact(
                  label: 'Settled',
                  value: value.formatMinor(value.settledMinor),
                ),
                _BillFact(label: 'Status', value: value.status.wireValue),
                if (value.notes != null)
                  _BillFact(label: 'Notes', value: value.notes!),
                if (value.closureReason != null)
                  _BillFact(
                    label: 'Cancel reason',
                    value: value.closureReason!,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            if (value.status == InvoiceStatus.draft && canDraft)
              FilledButton.icon(
                icon: const Icon(Icons.send),
                label: const Text('Issue'),
                onPressed: () => _issue(context, ref),
              ),
            if (value.status == InvoiceStatus.issued && canSettle)
              FilledButton.icon(
                icon: const Icon(Icons.verified_outlined),
                label: const Text('Settle'),
                onPressed: () => _settle(context, ref),
              ),
            if (value.status == InvoiceStatus.issued && canDraft)
              FilledButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Add line'),
                onPressed: () => _showLineSheet(context, ref),
              ),
            if (value.status.isEditable && canDraft)
              OutlinedButton.icon(
                icon: const Icon(Icons.close),
                label: const Text('Cancel'),
                onPressed: () => _cancel(context, ref),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(child: Text('Lines', style: theme.textTheme.titleMedium)),
            if (value.status.isEditable && canDraft)
              TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Add line'),
                onPressed: () => _showLineSheet(context, ref),
              ),
          ],
        ),
        lines.when(
          loading: () => const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
          error: (Object error, StackTrace _) => const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Lines unavailable.'),
            ),
          ),
          data: (List<InvoiceLine> values) => values.isEmpty
              ? const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No lines yet.'),
                  ),
                )
              : Column(
                  children: values
                      .map(
                        (InvoiceLine line) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: const Icon(Icons.receipt_long_outlined),
                            title: Text(line.description),
                            subtitle: Text(
                              '${line.quantity} × ${value.formatMinor(line.unitPriceMinor)} = ${value.formatMinor(line.lineTotalMinor)}',
                            ),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: Text('Payments', style: theme.textTheme.titleMedium),
            ),
            if (value.status == InvoiceStatus.issued && canSettle)
              TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Record'),
                onPressed: () => _showPaymentSheet(context, ref),
              ),
          ],
        ),
        payments.when(
          loading: () => const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
          error: (Object error, StackTrace _) => const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Payments unavailable.'),
            ),
          ),
          data: (List<Payment> values) => values.isEmpty
              ? const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No payments recorded.'),
                  ),
                )
              : Column(
                  children: values
                      .map(
                        (Payment payment) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: Icon(_paymentMethodIcon(payment.method)),
                            title: Text(value.formatMinor(payment.amountMinor)),
                            subtitle: Text(
                              '${payment.method.label} · ${_formatWhen(payment.paidAt)}',
                            ),
                            trailing: payment.amountReceivedMinor != null
                                ? Text(
                                    'Running: ${value.formatMinor(payment.amountReceivedMinor!)}',
                                  )
                                : null,
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: Text('Refunds', style: theme.textTheme.titleMedium),
            ),
            if (value.status != InvoiceStatus.cancelled && canDraft)
              TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Record'),
                onPressed: () => _showRefundSheet(context, ref),
              ),
          ],
        ),
        refunds.when(
          loading: () => const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
          error: (Object error, StackTrace _) => const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Refunds unavailable.'),
            ),
          ),
          data: (List<Refund> values) => values.isEmpty
              ? const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No refunds recorded.'),
                  ),
                )
              : Column(
                  children: values
                      .map(
                        (Refund refund) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: const Icon(Icons.money_off_outlined),
                            title: Text(value.formatMinor(refund.amountMinor)),
                            subtitle: Text(refund.reason),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
        ),
      ],
    );
  }

  Future<void> _issue(BuildContext context, WidgetRef ref) async {
    final SessionState session = ref.read(sessionProvider);
    final String? userId = session.user?.userId;
    if (userId == null) return;
    try {
      await ref
          .read(issueInvoiceUseCaseProvider)
          .call(policy: session.authorization, invoice: value);
      ref.invalidate(invoiceDetailProvider(value.id));
    } on NodexError catch (error) {
      if (context.mounted) _snack(context, error.message);
    }
  }

  Future<void> _settle(BuildContext context, WidgetRef ref) async {
    final SessionState session = ref.read(sessionProvider);
    try {
      await ref
          .read(settleInvoiceUseCaseProvider)
          .call(policy: session.authorization, invoice: value);
      ref.invalidate(invoiceDetailProvider(value.id));
    } on NodexError catch (error) {
      if (context.mounted) _snack(context, error.message);
    }
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final String? reason = await _askReason(context);
    if (reason == null) return;
    final SessionState session = ref.read(sessionProvider);
    try {
      await ref
          .read(cancelInvoiceUseCaseProvider)
          .call(policy: session.authorization, invoice: value, reason: reason);
      ref.invalidate(invoiceDetailProvider(value.id));
    } on NodexError catch (error) {
      if (context.mounted) _snack(context, error.message);
    }
  }

  Future<void> _showLineSheet(BuildContext context, WidgetRef ref) async {
    final _LineDraft? draft = await showModalBottomSheet<_LineDraft>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) => const _LineSheet(),
    );
    if (draft == null) return;
    final SessionState session = ref.read(sessionProvider);
    try {
      await ref
          .read(addInvoiceLineUseCaseProvider)
          .call(
            policy: session.authorization,
            invoice: value,
            lineNumber: draft.lineNumber,
            description: draft.description,
            quantity: draft.quantity,
            unitPriceMinor: draft.unitPrice,
            lineTotalMinor: draft.lineTotal,
          );
      ref.invalidate(invoiceLinesProvider(value.id));
      ref.invalidate(invoiceDetailProvider(value.id));
    } on NodexError catch (error) {
      if (context.mounted) _snack(context, error.message);
    }
  }

  Future<void> _showPaymentSheet(BuildContext context, WidgetRef ref) async {
    final _PaymentDraft? draft = await showModalBottomSheet<_PaymentDraft>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) => const _PaymentSheet(),
    );
    if (draft == null) return;
    final SessionState session = ref.read(sessionProvider);
    final String? userId = session.user?.userId;
    if (userId == null) return;
    try {
      await ref
          .read(recordPaymentUseCaseProvider)
          .call(
            policy: session.authorization,
            invoice: value,
            recordedBy: userId,
            amountMinor: draft.amount,
            method: draft.method,
            reference: draft.reference,
            note: draft.note,
          );
      ref.invalidate(invoicePaymentsProvider(value.id));
      ref.invalidate(invoiceDetailProvider(value.id));
    } on NodexError catch (error) {
      if (context.mounted) _snack(context, error.message);
    }
  }

  Future<void> _showRefundSheet(BuildContext context, WidgetRef ref) async {
    final List<Payment> payments = await ref.read(
      invoicePaymentsProvider(value.id).future,
    );
    if (!context.mounted) return;
    final _RefundDraft? draft = await showModalBottomSheet<_RefundDraft>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) => _RefundSheet(payments: payments),
    );
    if (draft == null) return;
    final SessionState session = ref.read(sessionProvider);
    final String? userId = session.user?.userId;
    if (userId == null) return;
    try {
      await ref
          .read(recordRefundUseCaseProvider)
          .call(
            policy: session.authorization,
            payment: draft.payment,
            recordedBy: userId,
            amountMinor: draft.amount,
            reason: draft.reason,
          );
      ref.invalidate(invoiceRefundsProvider(value.id));
      ref.invalidate(invoiceDetailProvider(value.id));
    } on NodexError catch (error) {
      if (context.mounted) _snack(context, error.message);
    }
  }
}

Future<String?> _askReason(BuildContext context) async {
  final TextEditingController controller = TextEditingController();
  try {
    return await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) {
        final double keyboard = MediaQuery.viewInsetsOf(context).bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + keyboard),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text(
                'Cancel reason required',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                decoration: const InputDecoration(labelText: 'Reason *'),
                autofocus: true,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () {
                  if (controller.text.trim().isEmpty) return;
                  Navigator.pop(context, controller.text.trim());
                },
                child: const Text('Cancel'),
              ),
            ],
          ),
        );
      },
    );
  } finally {
    controller.dispose();
  }
}

IconData _paymentMethodIcon(PaymentMethod method) {
  return switch (method) {
    PaymentMethod.cash => Icons.money_outlined,
    PaymentMethod.card => Icons.credit_card_outlined,
    PaymentMethod.mobileMoney => Icons.phone_android_outlined,
    PaymentMethod.bankTransfer => Icons.account_balance_outlined,
    PaymentMethod.insurance => Icons.health_and_safety_outlined,
    PaymentMethod.waiver => Icons.block_outlined,
  };
}

String _formatWhen(DateTime when) {
  final DateTime local = when.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

class _LineDraft {
  const _LineDraft({
    required this.lineNumber,
    required this.description,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
  });
  final int lineNumber;
  final String description;
  final double quantity;
  final int unitPrice;
  final int lineTotal;
}

class _LineSheet extends StatefulWidget {
  const _LineSheet();
  @override
  State<_LineSheet> createState() => _LineSheetState();
}

class _LineSheetState extends State<_LineSheet> {
  final TextEditingController _description = TextEditingController();
  final TextEditingController _quantity = TextEditingController(text: '1');
  final TextEditingController _unitPrice = TextEditingController();
  final TextEditingController _lineTotal = TextEditingController();
  final int _lineNumber = 1;

  @override
  void dispose() {
    _description.dispose();
    _quantity.dispose();
    _unitPrice.dispose();
    _lineTotal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + keyboard),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text(
            'Add invoice line',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _description,
            decoration: const InputDecoration(labelText: 'Description *'),
            autofocus: true,
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _quantity,
                  decoration: const InputDecoration(labelText: 'Quantity *'),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _unitPrice,
                  decoration: const InputDecoration(
                    labelText: 'Unit price (minor) *',
                  ),
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _lineTotal,
            decoration: const InputDecoration(
              labelText: 'Line total (minor) *',
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              final double? qty = double.tryParse(_quantity.text.trim());
              final int? unit = int.tryParse(_unitPrice.text.trim());
              final int? total = int.tryParse(_lineTotal.text.trim());
              if (_description.text.trim().isEmpty ||
                  qty == null ||
                  unit == null ||
                  total == null) {
                return;
              }
              Navigator.pop(
                context,
                _LineDraft(
                  lineNumber: _lineNumber,
                  description: _description.text.trim(),
                  quantity: qty,
                  unitPrice: unit,
                  lineTotal: total,
                ),
              );
            },
            child: const Text('Add line'),
          ),
        ],
      ),
    );
  }
}

class _PaymentDraft {
  const _PaymentDraft({
    required this.amount,
    required this.method,
    this.reference,
    this.note,
  });
  final int amount;
  final PaymentMethod method;
  final String? reference;
  final String? note;
}

class _PaymentSheet extends StatefulWidget {
  const _PaymentSheet();
  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<_PaymentSheet> {
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _reference = TextEditingController();
  final TextEditingController _note = TextEditingController();
  PaymentMethod _method = PaymentMethod.cash;

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + keyboard),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text(
            'Record payment',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _amount,
            decoration: const InputDecoration(
              labelText: 'Amount (minor units) *',
            ),
            keyboardType: TextInputType.number,
            autofocus: true,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<PaymentMethod>(
            initialValue: _method,
            decoration: const InputDecoration(labelText: 'Method'),
            items: PaymentMethod.values
                .map(
                  (PaymentMethod m) => DropdownMenuItem<PaymentMethod>(
                    value: m,
                    child: Text(m.label),
                  ),
                )
                .toList(growable: false),
            onChanged: (PaymentMethod? value) {
              if (value != null) setState(() => _method = value);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reference,
            decoration: const InputDecoration(labelText: 'Reference'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            decoration: const InputDecoration(labelText: 'Note'),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              final int? amount = int.tryParse(_amount.text.trim());
              if (amount == null) return;
              Navigator.pop(
                context,
                _PaymentDraft(
                  amount: amount,
                  method: _method,
                  reference: _reference.text.trim().isEmpty
                      ? null
                      : _reference.text.trim(),
                  note: _note.text.trim().isEmpty ? null : _note.text.trim(),
                ),
              );
            },
            child: const Text('Record payment'),
          ),
        ],
      ),
    );
  }
}

class _RefundDraft {
  const _RefundDraft({
    required this.payment,
    required this.amount,
    required this.reason,
  });
  final Payment payment;
  final int amount;
  final String reason;
}

class _RefundSheet extends StatefulWidget {
  const _RefundSheet({required this.payments});
  final List<Payment> payments;
  @override
  State<_RefundSheet> createState() => _RefundSheetState();
}

class _RefundSheetState extends State<_RefundSheet> {
  late Payment _payment = widget.payments.first;
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _reason = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + keyboard),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text(
            'Record refund',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<Payment>(
            initialValue: _payment,
            decoration: const InputDecoration(labelText: 'Source payment *'),
            items: widget.payments
                .map(
                  (Payment p) => DropdownMenuItem<Payment>(
                    value: p,
                    child: Text(
                      '${p.amountMinor} minor units · ${p.paidAt.toLocal()}',
                    ),
                  ),
                )
                .toList(growable: false),
            onChanged: (Payment? value) {
              if (value != null) setState(() => _payment = value);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            decoration: const InputDecoration(
              labelText: 'Amount (minor units) *',
            ),
            keyboardType: TextInputType.number,
            autofocus: true,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reason,
            decoration: const InputDecoration(labelText: 'Reason *'),
            autofocus: true,
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              final int? amount = int.tryParse(_amount.text.trim());
              if (amount == null || _reason.text.trim().isEmpty) return;
              Navigator.pop(
                context,
                _RefundDraft(
                  payment: _payment,
                  amount: amount,
                  reason: _reason.text.trim(),
                ),
              );
            },
            child: const Text('Record refund'),
          ),
        ],
      ),
    );
  }
}

class _BillFact extends StatelessWidget {
  const _BillFact({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: <Widget>[
        Expanded(child: Text(label)),
        Text(value),
      ],
    ),
  );
}

class _BillingError extends StatelessWidget {
  const _BillingError({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Text(
          error is NodexError
              ? (error as NodexError).message
              : 'Invoice unavailable',
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    ),
  );
}
