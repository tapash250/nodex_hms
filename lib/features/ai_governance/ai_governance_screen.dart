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
import 'package:nodex_hms/core/config/nodex_environment.dart';

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
          FutureBuilder<List<ModelRecord>>(
            future: ref.watch(aiModelRegistryProvider).allModels(),
            builder:
                (
                  BuildContext context,
                  AsyncSnapshot<List<ModelRecord>> snapshot,
                ) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    );
                  }

                  final List<ModelRecord> models =
                      snapshot.data ?? const <ModelRecord>[];
                  if (models.isEmpty) {
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'No models are registered.',
                              style: theme.textTheme.bodyLarge,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Every AI engine therefore routes to a manual '
                              'workflow. Clinical workflows remain fully usable '
                              'without AI.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return Column(
                    children: models
                        .map(
                          (ModelRecord model) => Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: Icon(
                                model.isEligibleForClinicalExecution
                                    ? Icons.verified_outlined
                                    : Icons.block_outlined,
                                color: model.isEligibleForClinicalExecution
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.error,
                              ),
                              title: Text(model.displayName),
                              subtitle: Text(
                                '${model.provider} • '
                                '${model.lifecycleStatus.wireValue} • '
                                'evaluation ${model.evaluationStatus.wireValue}',
                              ),
                            ),
                          ),
                        )
                        .toList(growable: false),
                  );
                },
          ),
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
