/// ER triage assessment detail and escalation actions (Module 05).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/er/er.dart';
import 'package:nodex_hms/features/er/er_controller.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// Detail screen for a single triage assessment.
class TriageDetailScreen extends ConsumerWidget {
  const TriageDetailScreen({super.key, required this.triageId});

  final String triageId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(triageDetailProvider(triageId));
    final session = ref.watch(sessionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Triage')),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace _) => _TriageError(
          error: error,
          onRetry: () => ref.invalidate(triageDetailProvider(triageId)),
        ),
        data: (TriageAssessment value) => _TriageBody(
          assessment: value,
          canEscalate: session.authorization.can(
            NodexPermissions.triageEscalate,
          ),
          onEscalate: () async {
            final useCase = ref.read(escalateTriageUseCaseProvider);
            final userId = session.user?.userId;
            if (userId == null) {
              return;
            }
            await useCase(
              policy: session.authorization,
              assessment: value,
              escalatedBy: userId,
            );
            ref.invalidate(triageDetailProvider(triageId));
          },
        ),
      ),
    );
  }
}

class _TriageBody extends StatelessWidget {
  const _TriageBody({
    required this.assessment,
    required this.canEscalate,
    required this.onEscalate,
  });

  final TriageAssessment assessment;
  final bool canEscalate;
  final Future<void> Function() onEscalate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  assessment.acuity.label,
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  assessment.chiefComplaint,
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  assessment.disposition.label,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (canEscalate && !assessment.escalated)
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onEscalate,
              icon: const Icon(Icons.warning_amber_rounded),
              label: const Text('Escalate'),
            ),
          ),
      ],
    );
  }
}

class _TriageError extends StatelessWidget {
  const _TriageError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final message = switch (error) {
      final NodexError e => e.message,
      _ => 'Something went wrong while loading this triage assessment.',
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
