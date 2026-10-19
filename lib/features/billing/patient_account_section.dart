/// Patient account and ledger section for the patient detail screen (Module 31).
///
/// The screen never computes a balance of its own to show: it shows the balance
/// the server maintains, the journal the device holds, and whether the two
/// agree. A device with a partial journal says so instead of quietly rendering
/// a number nobody can reconcile.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/billing/billing_use_cases.dart';
import 'package:nodex_hms/domain/billing/patient_account.dart';
import 'package:nodex_hms/domain/session/session_state.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// The statement a patient's account currently shows, or null when no account
/// has been opened.
final patientAccountStatementProvider = FutureProvider.autoDispose
    .family<PatientAccountStatement?, String>((
      Ref ref,
      String patientId,
    ) async {
      final SessionState session = ref.watch(sessionProvider);
      return ref
          .watch(readPatientAccountUseCaseProvider)
          .call(policy: session.authorization, patientId: patientId);
    });

/// Shows the running account, its journal and the actions that move it.
class PatientAccountSection extends ConsumerWidget {
  /// Creates the section.
  const PatientAccountSection({required this.patientId, super.key});

  /// Patient identifier.
  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<PatientAccountStatement?> statement = ref.watch(
      patientAccountStatementProvider(patientId),
    );
    final SessionState session = ref.watch(sessionProvider);
    final bool canPost = session.authorization.can(
      NodexPermissions.billingLedger,
    );
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text('Account', style: theme.textTheme.titleMedium),
            ),
            if (canPost)
              TextButton.icon(
                icon: const Icon(Icons.tune),
                label: const Text('Adjust'),
                onPressed: () => _showAdjustSheet(context, ref),
              ),
          ],
        ),
        statement.when(
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
                error is NodexError
                    ? error.message
                    : 'Account unavailable on this device.',
              ),
            ),
          ),
          data: (PatientAccountStatement? value) => value == null
              ? _NoAccountCard(
                  onOpen: canPost ? () => _openAccount(context, ref) : null,
                )
              : _StatementBody(statement: value),
        ),
      ],
    );
  }

  Future<void> _openAccount(BuildContext context, WidgetRef ref) async {
    await ensurePatientAccount(
      context: context,
      ref: ref,
      patientId: patientId,
    );
  }

  Future<void> _showAdjustSheet(BuildContext context, WidgetRef ref) async {
    final PatientAccountStatement? current = ref
        .read(patientAccountStatementProvider(patientId))
        .value;
    if (current == null) {
      if (context.mounted) {
        _snack(context, 'Open the account before adjusting it.');
      }
      return;
    }
    final _AdjustDraft? draft = await showModalBottomSheet<_AdjustDraft>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) => const _AdjustSheet(),
    );
    if (draft == null) return;
    final SessionState session = ref.read(sessionProvider);
    final String? userId = session.user?.userId;
    if (userId == null) return;
    try {
      await ref
          .read(postAdjustmentUseCaseProvider)
          .call(
            policy: session.authorization,
            account: current.account,
            recordedBy: userId,
            amountMinor: draft.amountMinor,
            direction: draft.direction,
            reason: draft.reason,
          );
      ref.invalidate(patientAccountStatementProvider(patientId));
    } on NodexError catch (error) {
      if (context.mounted) _snack(context, error.message);
    }
  }
}

class _NoAccountCard extends StatelessWidget {
  const _NoAccountCard({this.onOpen});

  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('This patient has no running account yet.'),
          const SizedBox(height: 8),
          if (onOpen != null)
            FilledButton.tonal(
              onPressed: onOpen,
              child: const Text('Open account'),
            ),
        ],
      ),
    ),
  );
}

class _StatementBody extends StatelessWidget {
  const _StatementBody({required this.statement});

  final PatientAccountStatement statement;

  @override
  Widget build(BuildContext context) {
    final PatientAccount account = statement.account;
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(account.accountCode, style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  '${account.currency} '
                  '${account.formatMinor(account.balanceMinor.abs())}'
                  '${account.isInCredit ? ' in credit' : ' outstanding'}',
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Text(switch (account.status) {
                  AccountStatus.settled => 'Settled',
                  AccountStatus.credit => 'In credit',
                  AccountStatus.closed => 'Closed',
                  AccountStatus.open => 'Open',
                }, style: theme.textTheme.bodySmall),
                if (!statement.agreesWithServer) ...<Widget>[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          Icons.sync_problem_outlined,
                          color: colors.onErrorContainer,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'This device holds ${statement.entries.length} '
                            'journal entries reconciling to '
                            '${account.formatMinor(statement.journalledBalanceMinor)}; '
                            'the account balance is '
                            '${account.formatMinor(account.balanceMinor)}. '
                            'The journal shown here is incomplete.',
                            style: TextStyle(color: colors.onErrorContainer),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        Text('Journal', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        if (statement.entries.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No ledger entries recorded.'),
            ),
          )
        else
          Column(
            children: statement.entries
                .map((LedgerEntry entry) => _LedgerTile(entry: entry))
                .toList(growable: false),
          ),
      ],
    );
  }
}

class _LedgerTile extends StatelessWidget {
  const _LedgerTile({required this.entry});

  final LedgerEntry entry;

  @override
  Widget build(BuildContext context) {
    final bool isDebit = entry.direction == LedgerDirection.debit;
    final String when = entry.occurredAt.toLocal().toIso8601String();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          isDebit ? Icons.trending_up : Icons.trending_down,
          color: isDebit
              ? Theme.of(context).colorScheme.error
              : Theme.of(context).colorScheme.primary,
        ),
        title: Text(
          '${entry.transactionType.wireValue} · ${entry.accountCode.wireValue}',
        ),
        subtitle: Text(
          <String>[
            when,
            if (entry.memo != null) entry.memo!,
            if (entry.invoiceId != null) 'invoice ${entry.invoiceId}',
            if (entry.paymentId != null) 'payment ${entry.paymentId}',
            if (entry.refundId != null) 'refund ${entry.refundId}',
          ].join('\n'),
        ),
        trailing: Text(
          '${isDebit ? '+' : '-'}${entry.formatMinor(entry.amountMinor)}',
        ),
      ),
    );
  }
}

class _AdjustDraft {
  const _AdjustDraft({
    required this.amountMinor,
    required this.direction,
    required this.reason,
  });

  final int amountMinor;
  final LedgerDirection direction;
  final String reason;
}

class _AdjustSheet extends StatefulWidget {
  const _AdjustSheet();

  @override
  State<_AdjustSheet> createState() => _AdjustSheetState();
}

class _AdjustSheetState extends State<_AdjustSheet> {
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _reason = TextEditingController();
  LedgerDirection _direction = LedgerDirection.debit;

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
            'Adjust the account',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          SegmentedButton<LedgerDirection>(
            segments: const <ButtonSegment<LedgerDirection>>[
              ButtonSegment<LedgerDirection>(
                value: LedgerDirection.debit,
                label: Text('Increase'),
              ),
              ButtonSegment<LedgerDirection>(
                value: LedgerDirection.credit,
                label: Text('Reduce'),
              ),
            ],
            selected: <LedgerDirection>{_direction},
            onSelectionChanged: (Set<LedgerDirection> selection) =>
                setState(() => _direction = selection.first),
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
            maxLines: 2,
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              final int? amount = int.tryParse(_amount.text.trim());
              if (amount == null || amount <= 0) return;
              if (_reason.text.trim().isEmpty) return;
              Navigator.pop(
                context,
                _AdjustDraft(
                  amountMinor: amount,
                  direction: _direction,
                  reason: _reason.text.trim(),
                ),
              );
            },
            child: const Text('Post adjustment'),
          ),
        ],
      ),
    );
  }
}

/// Prompts for the account code a new account should carry.
Future<String?> askAccountCode(BuildContext context) async {
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
                'Open a running account',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                decoration: const InputDecoration(labelText: 'Account code *'),
                autofocus: true,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () {
                  final String value = controller.text.trim();
                  if (value.isEmpty) return;
                  Navigator.pop(context, value);
                },
                child: const Text('Open account'),
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

/// Returns the patient's account, opening one first when the patient has none.
///
/// Both the account section and the invoice charge action need the same
/// sequence: read what the device already holds, ask for a code only when
/// nothing exists, open, then refresh the statement. Keeping it in one place is
/// what stops the two screens from disagreeing about when an account appears.
Future<PatientAccount?> ensurePatientAccount({
  required BuildContext context,
  required WidgetRef ref,
  required String patientId,
}) async {
  final PatientAccountStatement? existing = ref
      .read(patientAccountStatementProvider(patientId))
      .value;
  if (existing != null) return existing.account;

  final SessionState session = ref.read(sessionProvider);
  final String? tenantId = session.tenantId;
  if (tenantId == null) return null;

  final String? code = await askAccountCode(context);
  if (code == null || !context.mounted) return null;
  try {
    final PatientAccount account = await ref
        .read(openPatientAccountUseCaseProvider)
        .call(
          policy: session.authorization,
          tenantId: tenantId,
          patientId: patientId,
          accountCode: code,
        );
    ref.invalidate(patientAccountStatementProvider(patientId));
    return account;
  } on NodexError catch (error) {
    if (context.mounted) _snack(context, error.message);
    return null;
  }
}

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
