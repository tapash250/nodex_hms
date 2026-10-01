/// Discharge detail and finalization actions (Module 23).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/beds/bed.dart';
import 'package:nodex_hms/domain/discharge/discharge.dart';
import 'package:nodex_hms/domain/session/session_state.dart';
import 'package:nodex_hms/features/beds/bed_controller.dart';
import 'package:nodex_hms/features/discharge/discharge_controller.dart';
import 'package:nodex_hms/features/discharge/discharge_readiness_section.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// Detail screen for one discharge record.
class DischargeDetailScreen extends ConsumerWidget {
  /// Creates the screen.
  const DischargeDetailScreen({required this.dischargeId, super.key});

  /// Local discharge id.
  final String dischargeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Discharge> detail = ref.watch(
      dischargeDetailProvider(dischargeId),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Discharge')),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace _) => _DischargeError(
          error: error,
          onRetry: () => ref.invalidate(dischargeDetailProvider(dischargeId)),
        ),
        data: (Discharge value) => _DischargeBody(value: value),
      ),
    );
  }
}

class _DischargeBody extends ConsumerWidget {
  const _DischargeBody({required this.value});

  final Discharge value;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final SessionState session = ref.watch(sessionProvider);
    final bool canFinalize = session.authorization.can(
      NodexPermissions.dischargeFinalize,
    );
    final bool canDraft = session.authorization.can(
      NodexPermissions.encounterWrite,
    );
    final bool canReleaseBed = session.authorization.can(
      NodexPermissions.bedAssign,
    );
    final AsyncValue<BedAssignment?> stay = ref.watch(
      patientStayProvider(value.patientId),
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
                Text(value.dischargeCode, style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                _DischargeFact(
                  label: 'Disposition',
                  value: value.dischargeType.label,
                ),
                _DischargeFact(label: 'Status', value: value.status.wireValue),
                if (value.summary != null)
                  _DischargeFact(label: 'Summary', value: value.summary!),
                if (value.followUpPlan != null)
                  _DischargeFact(
                    label: 'Follow-up',
                    value: value.followUpPlan!,
                  ),
                if (value.closureReason != null)
                  _DischargeFact(
                    label: 'Cancel reason',
                    value: value.closureReason!,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const SizedBox(height: 16),
        DischargeReadinessSection(discharge: value),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            if (value.status.isEditable && canFinalize)
              FilledButton.icon(
                icon: const Icon(Icons.verified_outlined),
                label: const Text('Finalize'),
                onPressed: () => _finalize(context, ref),
              ),
            if (value.status.isEditable && canDraft)
              OutlinedButton.icon(
                icon: const Icon(Icons.close),
                label: const Text('Cancel draft'),
                onPressed: () => _cancel(context, ref),
              ),
            OutlinedButton.icon(
              icon: const Icon(Icons.chevron_right),
              label: const Text('Open encounter'),
              onPressed: () => context.go(
                '/patients/${value.patientId}/encounters/${value.encounterId}',
              ),
            ),
          ],
        ),
        stay.maybeWhen(
          data: (BedAssignment? active) => active != null && canReleaseBed
              ? Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.logout_outlined),
                    label: const Text('Release bed (discharge)'),
                    onPressed: () => _releaseBed(context, ref, active),
                  ),
                )
              : const SizedBox.shrink(),
          orElse: () => const SizedBox.shrink(),
        ),
      ],
    );
  }

  Future<void> _finalize(BuildContext context, WidgetRef ref) async {
    final SessionState session = ref.read(sessionProvider);
    final String? userId = session.user?.userId;
    if (userId == null) return;
    try {
      await ref
          .read(finalizeDischargeUseCaseProvider)
          .call(
            policy: session.authorization,
            discharge: value,
            finalizerId: userId,
          );
      ref.invalidate(dischargeDetailProvider(value.id));
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
          .read(cancelDischargeUseCaseProvider)
          .call(
            policy: session.authorization,
            discharge: value,
            reason: reason,
          );
      ref.invalidate(dischargeDetailProvider(value.id));
    } on NodexError catch (error) {
      if (context.mounted) _snack(context, error.message);
    }
  }

  Future<void> _releaseBed(
    BuildContext context,
    WidgetRef ref,
    BedAssignment active,
  ) async {
    final String? reason = await _askReason(context);
    if (reason == null) return;
    final SessionState session = ref.read(sessionProvider);
    try {
      await ref
          .read(releaseBedUseCaseProvider)
          .call(
            policy: session.authorization,
            assignment: active,
            reason: reason,
          );
      ref.invalidate(patientStayProvider(value.patientId));
      if (context.mounted) _snack(context, 'Bed released.');
    } on NodexError catch (error) {
      if (context.mounted) _snack(context, error.message);
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
                  'Reason required',
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
                  child: const Text('Confirm'),
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

  static void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _DischargeFact extends StatelessWidget {
  const _DischargeFact({required this.label, required this.value});
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

class _DischargeError extends StatelessWidget {
  const _DischargeError({required this.error, required this.onRetry});
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
              : 'Discharge unavailable',
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    ),
  );
}
