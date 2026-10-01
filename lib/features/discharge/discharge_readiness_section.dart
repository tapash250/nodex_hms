/// Discharge readiness section for the discharge detail screen (Module 23).
///
/// Shows the three gates that stand between a draft discharge and its
/// authorization — clinical clearance, medication reconciliation and billing
/// settlement — and offers the actions that advance each one.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/discharge/discharge.dart';
import 'package:nodex_hms/domain/discharge/discharge_management.dart';
import 'package:nodex_hms/domain/session/session_state.dart';
import 'package:nodex_hms/features/discharge/discharge_controller.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// Renders the discharge readiness gates and their actions.
class DischargeReadinessSection extends ConsumerWidget {
  /// Creates the section.
  const DischargeReadinessSection({required this.discharge, super.key});

  /// The discharge whose readiness is shown.
  final Discharge discharge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<DischargeReadinessBundle> bundle = ref.watch(
      dischargeReadinessProvider(discharge.id),
    );
    final ThemeData theme = Theme.of(context);
    final SessionState session = ref.watch(sessionProvider);
    final bool canClear = session.authorization.can(
      NodexPermissions.dischargeClearanceWrite,
    );
    final bool canReconcile = session.authorization.can(
      NodexPermissions.dischargeReconciliationWrite,
    );
    final bool canSettle = session.authorization.can(
      NodexPermissions.billingSettle,
    );
    final bool editable = discharge.status.isEditable;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Discharge readiness', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        bundle.when(
          loading: () => const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
          error: (Object error, StackTrace _) => Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                error is NodexError ? error.message : 'Readiness unavailable.',
              ),
            ),
          ),
          data: (DischargeReadinessBundle value) {
            final DischargeReadiness readiness = value.readiness;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _GateRow(
                          label: 'Clinical clearance',
                          done: readiness.cleared,
                          detail: readiness.cleared
                              ? 'Cleared'
                              : readiness.outstandingClearanceItems > 0
                              ? '${readiness.outstandingClearanceItems} '
                                    'outstanding'
                              : value.clearance == null
                              ? 'Not started'
                              : 'Pending',
                        ),
                        _GateRow(
                          label: 'Medication reconciliation',
                          done: readiness.reconciled,
                          detail: readiness.reconciled
                              ? '${value.reconciliation!.medicationsReviewed} '
                                    'reviewed, '
                                    '${value.reconciliation!.discrepanciesFound} '
                                    'discrepancies'
                              : readiness.pendingMedications > 0
                              ? '${readiness.pendingMedications} recorded'
                              : value.reconciliation == null
                              ? 'Not started'
                              : 'Pending',
                        ),
                        _GateRow(
                          label: 'Billing settlement',
                          done: readiness.settled,
                          detail: readiness.settled
                              ? 'Invoice ${value.settlement!.invoiceId} settled'
                              : 'Outstanding',
                        ),
                        const Divider(height: 24),
                        Text(
                          readiness.canFinalize
                              ? 'Ready to authorize discharge.'
                              : 'Clearance, reconciliation and settlement are '
                                    'all required before this discharge can be '
                                    'authorized.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                if (editable && canClear) ...<Widget>[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      OutlinedButton.icon(
                        icon: const Icon(Icons.fact_check_outlined),
                        label: Text(
                          value.clearance == null
                              ? 'Record review'
                              : 'Update review',
                        ),
                        onPressed: () => _recordClearance(context, ref),
                      ),
                      if (value.clearance != null &&
                          !value.clearance!.isCleared)
                        OutlinedButton.icon(
                          icon: const Icon(Icons.verified_outlined),
                          label: const Text('Grant clearance'),
                          onPressed: () => _grantClearance(context, ref),
                        ),
                    ],
                  ),
                ],
                if (editable && canReconcile) ...<Widget>[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      if (value.reconciliation == null)
                        OutlinedButton.icon(
                          icon: const Icon(Icons.playlist_add),
                          label: const Text('Start reconciliation'),
                          onPressed: () => _startReconciliation(context, ref),
                        ),
                      if (value.reconciliation != null &&
                          !value.reconciliation!.isReconciled) ...<Widget>[
                        OutlinedButton.icon(
                          icon: const Icon(Icons.medication_outlined),
                          label: const Text('Add medication'),
                          onPressed: () => _addMedication(context, ref),
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.task_alt),
                          label: const Text('Complete review'),
                          onPressed: () =>
                              _completeReconciliation(context, ref),
                        ),
                      ],
                    ],
                  ),
                  if (value.reconciliation != null &&
                      !value.reconciliation!.isReconciled &&
                      value.items.isNotEmpty)
                    Card(
                      margin: const EdgeInsets.only(top: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: value.items
                              .map(
                                (DischargeMedicationReconciliationItem item) =>
                                    _MedicationRow(item: item),
                              )
                              .toList(growable: false),
                        ),
                      ),
                    ),
                ],
                if (editable && canSettle && !readiness.settled) ...<Widget>[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.receipt_long_outlined),
                    label: const Text('Record settlement'),
                    onPressed: () => _settle(context, ref),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _recordClearance(BuildContext context, WidgetRef ref) async {
    final _ClearanceDraft? draft = await showModalBottomSheet<_ClearanceDraft>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) => const _ClearanceSheet(),
    );
    if (draft == null) return;
    final SessionState session = ref.read(sessionProvider);
    final String? userId = session.user?.userId;
    if (userId == null) return;
    try {
      await ref
          .read(recordDischargeClearanceUseCaseProvider)
          .call(
            policy: session.authorization,
            discharge: discharge,
            reviewedBy: userId,
            outstandingItems: draft.outstandingItems,
            notes: draft.notes,
          );
      _invalidate(ref);
    } on NodexError catch (error) {
      if (context.mounted) _snack(context, error.message);
    }
  }

  Future<void> _grantClearance(BuildContext context, WidgetRef ref) async {
    final SessionState session = ref.read(sessionProvider);
    final String? userId = session.user?.userId;
    if (userId == null) return;
    try {
      await ref
          .read(grantDischargeClearanceUseCaseProvider)
          .call(
            policy: session.authorization,
            discharge: discharge,
            clearedBy: userId,
          );
      _invalidate(ref);
    } on NodexError catch (error) {
      if (context.mounted) _snack(context, error.message);
    }
  }

  Future<void> _startReconciliation(BuildContext context, WidgetRef ref) async {
    final SessionState session = ref.read(sessionProvider);
    try {
      await ref
          .read(startDischargeReconciliationUseCaseProvider)
          .call(policy: session.authorization, discharge: discharge);
      _invalidate(ref);
    } on NodexError catch (error) {
      if (context.mounted) _snack(context, error.message);
    }
  }

  Future<void> _addMedication(BuildContext context, WidgetRef ref) async {
    final _MedicationDraft? draft =
        await showModalBottomSheet<_MedicationDraft>(
          context: context,
          isScrollControlled: true,
          builder: (BuildContext context) => const _MedicationSheet(),
        );
    if (draft == null) return;
    final SessionState session = ref.read(sessionProvider);
    final String? userId = session.user?.userId;
    if (userId == null) return;
    try {
      await ref
          .read(recordDischargeMedicationUseCaseProvider)
          .call(
            policy: session.authorization,
            discharge: discharge,
            medicationName: draft.medicationName,
            action: draft.action,
            recordedBy: userId,
            detail: draft.detail,
          );
      _invalidate(ref);
    } on NodexError catch (error) {
      if (context.mounted) _snack(context, error.message);
    }
  }

  Future<void> _completeReconciliation(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final SessionState session = ref.read(sessionProvider);
    final String? userId = session.user?.userId;
    if (userId == null) return;
    try {
      await ref
          .read(completeDischargeReconciliationUseCaseProvider)
          .call(
            policy: session.authorization,
            discharge: discharge,
            reviewedBy: userId,
          );
      _invalidate(ref);
    } on NodexError catch (error) {
      if (context.mounted) _snack(context, error.message);
    }
  }

  Future<void> _settle(BuildContext context, WidgetRef ref) async {
    final _SettlementDraft? draft =
        await showModalBottomSheet<_SettlementDraft>(
          context: context,
          isScrollControlled: true,
          builder: (BuildContext context) => const _SettlementSheet(),
        );
    if (draft == null) return;
    final SessionState session = ref.read(sessionProvider);
    final String? userId = session.user?.userId;
    if (userId == null) return;
    try {
      await ref
          .read(settleDischargeBillingUseCaseProvider)
          .call(
            policy: session.authorization,
            discharge: discharge,
            invoiceId: draft.invoiceId,
            amountMinor: draft.amountMinor,
            settledBy: userId,
          );
      _invalidate(ref);
    } on NodexError catch (error) {
      if (context.mounted) _snack(context, error.message);
    }
  }

  void _invalidate(WidgetRef ref) {
    ref.invalidate(dischargeReadinessProvider(discharge.id));
    ref.invalidate(dischargeDetailProvider(discharge.id));
  }

  static void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _GateRow extends StatelessWidget {
  const _GateRow({
    required this.label,
    required this.done,
    required this.detail,
  });
  final String label;
  final bool done;
  final String detail;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: <Widget>[
        Icon(
          done ? Icons.check_circle : Icons.radio_button_unchecked,
          color: done ? Colors.green : Colors.grey,
          size: 20,
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(label)),
        Text(detail, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}

class _MedicationRow extends StatelessWidget {
  const _MedicationRow({required this.item});
  final DischargeMedicationReconciliationItem item;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: <Widget>[
        Icon(
          item.discrepancy ? Icons.warning_amber_outlined : Icons.check,
          size: 18,
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(item.medicationName)),
        Text(item.action.label),
      ],
    ),
  );
}

class _ClearanceDraft {
  const _ClearanceDraft({required this.outstandingItems, this.notes});
  final int outstandingItems;
  final String? notes;
}

class _ClearanceSheet extends StatefulWidget {
  const _ClearanceSheet();
  @override
  State<_ClearanceSheet> createState() => _ClearanceSheetState();
}

class _ClearanceSheetState extends State<_ClearanceSheet> {
  final TextEditingController _outstanding = TextEditingController(text: '0');
  final TextEditingController _notes = TextEditingController();

  @override
  void dispose() {
    _outstanding.dispose();
    _notes.dispose();
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
            'Clinical review',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _outstanding,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Outstanding items'),
            autofocus: true,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            decoration: const InputDecoration(labelText: 'Notes (optional)'),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              final int? outstanding = int.tryParse(_outstanding.text.trim());
              if (outstanding == null || outstanding < 0) return;
              Navigator.pop(
                context,
                _ClearanceDraft(
                  outstandingItems: outstanding,
                  notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
                ),
              );
            },
            child: const Text('Save review'),
          ),
        ],
      ),
    );
  }
}

class _MedicationDraft {
  const _MedicationDraft({
    required this.medicationName,
    required this.action,
    this.detail,
  });
  final String medicationName;
  final DischargeMedicationAction action;
  final String? detail;
}

class _MedicationSheet extends StatefulWidget {
  const _MedicationSheet();
  @override
  State<_MedicationSheet> createState() => _MedicationSheetState();
}

class _MedicationSheetState extends State<_MedicationSheet> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _detail = TextEditingController();
  DischargeMedicationAction _action =
      DischargeMedicationAction.continueMedication;

  @override
  void dispose() {
    _name.dispose();
    _detail.dispose();
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
            'Medication decision',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Medication *'),
            autofocus: true,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<DischargeMedicationAction>(
            initialValue: _action,
            decoration: const InputDecoration(labelText: 'Decision *'),
            items: DischargeMedicationAction.values
                .map(
                  (DischargeMedicationAction action) =>
                      DropdownMenuItem<DischargeMedicationAction>(
                        value: action,
                        child: Text(action.label),
                      ),
                )
                .toList(growable: false),
            onChanged: (DischargeMedicationAction? value) {
              if (value != null) setState(() => _action = value);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _detail,
            decoration: const InputDecoration(labelText: 'Detail (optional)'),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              if (_name.text.trim().isEmpty) return;
              Navigator.pop(
                context,
                _MedicationDraft(
                  medicationName: _name.text.trim(),
                  action: _action,
                  detail: _detail.text.trim().isEmpty
                      ? null
                      : _detail.text.trim(),
                ),
              );
            },
            child: const Text('Record decision'),
          ),
        ],
      ),
    );
  }
}

class _SettlementDraft {
  const _SettlementDraft({required this.invoiceId, required this.amountMinor});
  final String invoiceId;
  final int amountMinor;
}

class _SettlementSheet extends StatefulWidget {
  const _SettlementSheet();
  @override
  State<_SettlementSheet> createState() => _SettlementSheetState();
}

class _SettlementSheetState extends State<_SettlementSheet> {
  final TextEditingController _invoice = TextEditingController();
  final TextEditingController _amount = TextEditingController();

  @override
  void dispose() {
    _invoice.dispose();
    _amount.dispose();
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
            'Record settlement',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _invoice,
            decoration: const InputDecoration(labelText: 'Invoice id *'),
            autofocus: true,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Amount in minor units *',
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              final int? amount = int.tryParse(_amount.text.trim());
              if (_invoice.text.trim().isEmpty ||
                  amount == null ||
                  amount < 0) {
                return;
              }
              Navigator.pop(
                context,
                _SettlementDraft(
                  invoiceId: _invoice.text.trim(),
                  amountMinor: amount,
                ),
              );
            },
            child: const Text('Record settlement'),
          ),
        ],
      ),
    );
  }
}
