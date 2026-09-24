/// ER visit detail and disposition actions (Module 05).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/er/er.dart';
import 'package:nodex_hms/features/er/er_controller.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// Detail screen for a single ER visit.
class ErVisitDetailScreen extends ConsumerWidget {
  const ErVisitDetailScreen({super.key, required this.visitId});

  final String visitId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(erVisitDetailProvider(visitId));
    final session = ref.watch(sessionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('ER Visit')),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace _) => _ErVisitError(
          error: error,
          onRetry: () => ref.invalidate(erVisitDetailProvider(visitId)),
        ),
        data: (ErVisit value) => _ErVisitBody(
          visit: value,
          canDischarge: session.authorization.can(
            NodexPermissions.erVisitWrite,
          ),
          onTransition: (ErVisitStatus status) async {
            final useCase = ref.read(transitionErVisitUseCaseProvider);
            await useCase(
              policy: session.authorization,
              visit: value,
              nextStatus: status,
            );
            ref.invalidate(erVisitDetailProvider(visitId));
          },
        ),
      ),
    );
  }
}

class _ErVisitBody extends StatelessWidget {
  const _ErVisitBody({
    required this.visit,
    required this.canDischarge,
    required this.onTransition,
  });

  final ErVisit visit;
  final bool canDischarge;
  final Future<void> Function(ErVisitStatus status) onTransition;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canTransition = canDischarge && !visit.status.isTerminal;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(visit.status.label, style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  visit.arrivalMode?.label ?? 'Unknown arrival mode',
                  style: theme.textTheme.bodyMedium,
                ),
                if (visit.disposition != null) ...[
                  const SizedBox(height: 8),
                  Text(visit.disposition!, style: theme.textTheme.bodyMedium),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (canTransition) ...[
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => onTransition(ErVisitStatus.discharged),
              icon: const Icon(Icons.exit_to_app),
              label: const Text('Discharge'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => onTransition(ErVisitStatus.admitted),
              icon: const Icon(Icons.login),
              label: const Text('Admit'),
            ),
          ),
        ],
      ],
    );
  }
}

class _ErVisitError extends StatelessWidget {
  const _ErVisitError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final message = switch (error) {
      final NodexError e => e.message,
      _ => 'Something went wrong while loading this ER visit.',
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
