/// AI governance surface.
///
/// Makes the governance position visible and checkable in the product itself:
/// which engines exist, what each requires, which models are registered and at
/// what lifecycle state, and the standing rule that an available model is not an
/// approved model.
///
/// In the Phase 1 build no model has passed evaluation, so every engine resolves
/// to a manual workflow. That is the correct and intended state, and this screen
/// says so rather than implying AI capability that has not been validated.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodex_hms/ai/model_registry/model_registry.dart';
import 'package:nodex_hms/ai/orchestrator/ai_engines.dart';
import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/config/nodex_environment.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/session/session_state.dart';
import 'package:nodex_hms/features/ai_governance/ai_governance_controller.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// AI governance screen.
class AiGovernanceScreen extends ConsumerWidget {
  /// Creates the governance screen.
  const AiGovernanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final NodexEnvironment environment = ref.watch(environmentProvider);
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('AI governance')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Card(
            color: theme.colorScheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(
                        Icons.policy_outlined,
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Clinical governance position',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.onSecondaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'NODEX AI is advisory and non-autonomous. AI output cannot '
                    'become a finalized clinical decision without human review. '
                    'An available model is not an approved model: a model must '
                    'pass evaluation against a locked acceptance set and receive '
                    'clinical governance approval before it may serve clinical '
                    'traffic.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Active deployment profile',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  _KeyValueRow(
                    label: 'Environment',
                    value: environment.environment.name,
                  ),
                  _KeyValueRow(
                    label: 'Profile revision',
                    value: environment.aiDeploymentProfileRevision,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Registered models', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const _RegisteredModels(),
          const SizedBox(height: 16),
          Text('Declared engines', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          ...AiEngines.definitions.values.map(
            (AiEngineDefinition engine) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(engine.displayName, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 4),
                    Text(
                      engine.purpose,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        _EngineChip(
                          icon: Icons.speed_outlined,
                          label: 'Risk ${engine.riskLevel.wireValue}',
                        ),
                        _EngineChip(
                          icon: Icons.shield_outlined,
                          label: engine.privacyClass.wireValue,
                        ),
                        _EngineChip(
                          icon: Icons.data_object_outlined,
                          label: engine.modality.wireValue,
                        ),
                        if (engine.requiresHumanReview)
                          const _EngineChip(
                            icon: Icons.how_to_reg_outlined,
                            label: 'Human review required',
                          ),
                        if (engine.mayAbstain)
                          const _EngineChip(
                            icon: Icons.pan_tool_outlined,
                            label: 'May abstain',
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RegisteredModels extends ConsumerWidget {
  const _RegisteredModels();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SessionState session = ref.watch(sessionProvider);
    final bool canAdminister = session.authorization.can(
      NodexPermissions.aiGovernanceAdminister,
    );
    final bool holdsAdminister =
        session.snapshot?.permissions.contains(
          NodexPermissions.aiGovernanceAdminister,
        ) ??
        false;
    final AsyncValue<List<ModelRecord>> models = ref.watch(
      aiGovernanceModelsProvider,
    );

    return models.when(
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
                : 'The model registry could not be read.',
          ),
        ),
      ),
      data: (List<ModelRecord> list) {
        if (list.isEmpty) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'No models are registered.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Every AI engine therefore routes to a manual workflow. '
                    'Clinical workflows remain fully usable without AI.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (holdsAdminister && !canAdminister)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  color: Theme.of(context).colorScheme.tertiaryContainer,
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Approval and activation require an online connection. '
                      'The registry is shown from the local projection.',
                    ),
                  ),
                ),
              ),
            for (final ModelRecord model in list)
              _ModelCard(model: model, canAdminister: canAdminister),
          ],
        );
      },
    );
  }
}

class _ModelCard extends ConsumerWidget {
  const _ModelCard({required this.model, required this.canAdminister});

  final ModelRecord model;
  final bool canAdminister;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final bool evaluated =
        model.evaluationStatus == ModelEvaluationStatus.passed &&
        (model.evaluationSetRevision?.trim().isNotEmpty ?? false);
    final bool canApprove =
        canAdminister &&
        evaluated &&
        model.lifecycleStatus == ModelLifecycleStatus.evaluating;
    final bool canActivate =
        canAdminister && model.lifecycleStatus == ModelLifecycleStatus.approved;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  model.isEligibleForClinicalExecution
                      ? Icons.verified_outlined
                      : Icons.block_outlined,
                  color: model.isEligibleForClinicalExecution
                      ? theme.colorScheme.primary
                      : theme.colorScheme.error,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        model.displayName,
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${model.provider} • ${model.modelKey} • '
                        'revision ${model.modelRevision}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                _EngineChip(
                  icon: Icons.timeline_outlined,
                  label: model.lifecycleStatus.wireValue,
                ),
                _EngineChip(
                  icon: Icons.fact_check_outlined,
                  label: 'evaluation ${model.evaluationStatus.wireValue}',
                ),
                _EngineChip(
                  icon: Icons.shield_outlined,
                  label: model.clinicalRiskTier.wireValue,
                ),
                if (model.evaluationSetRevision != null)
                  _EngineChip(
                    icon: Icons.rule_outlined,
                    label: 'set ${model.evaluationSetRevision}',
                  ),
              ],
            ),
            if (model.approvedAt != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                'Approved ${model.approvedAt!.toLocal().toIso8601String().substring(0, 16).replaceFirst('T', ' ')}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (canApprove || canActivate) ...<Widget>[
              const SizedBox(height: 12),
              if (canApprove)
                FilledButton.icon(
                  onPressed: () => _approve(context, ref),
                  icon: const Icon(Icons.verified_outlined),
                  label: const Text('Approve model'),
                ),
              if (canActivate)
                FilledButton.icon(
                  onPressed: () => _activate(context, ref),
                  icon: const Icon(Icons.play_arrow_outlined),
                  label: const Text('Activate model'),
                ),
            ] else if (canAdminister &&
                model.lifecycleStatus == ModelLifecycleStatus.evaluating &&
                !evaluated) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                'Approval waits on a passed evaluation against a recorded '
                'acceptance-set revision.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _approve(BuildContext context, WidgetRef ref) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final String? userId = ref.read(sessionProvider).snapshot?.userId;
    if (userId == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('The session has no signed-in user.')),
      );
      return;
    }
    try {
      await ref
          .read(aiGovernanceModelsProvider.notifier)
          .approve(model, approvedBy: userId);
      messenger.showSnackBar(
        SnackBar(content: Text('${model.displayName} approved.')),
      );
    } on NodexError catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _activate(BuildContext context, WidgetRef ref) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(aiGovernanceModelsProvider.notifier).activate(model);
      messenger.showSnackBar(
        SnackBar(content: Text('${model.displayName} activated.')),
      );
    } on NodexError catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}

class _EngineChip extends StatelessWidget {
  const _EngineChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Chip(
    avatar: Icon(icon, size: 16),
    label: Text(label),
    visualDensity: VisualDensity.compact,
  );
}

class _KeyValueRow extends StatelessWidget {
  const _KeyValueRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
