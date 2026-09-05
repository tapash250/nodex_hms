/// Placeholder for a module whose implementation lands in a later phase.
///
/// The route, permission gate and navigation entry are real and enforced; only
/// the clinical surface is pending. Being explicit about that is better than
/// shipping a screen that looks functional but has no domain behind it.
library;

import 'package:flutter/material.dart';
import 'package:nodex_hms/app/router/navigation_destinations.dart';

/// Screen shown for a declared but not yet implemented module.
class ModulePlaceholderScreen extends StatelessWidget {
  /// Creates a placeholder for [destination].
  const ModulePlaceholderScreen({
    required this.destination,
    required this.plannedPhase,
    super.key,
  });

  /// The destination this placeholder stands in for.
  final NavigationDestinationSpec destination;

  /// The roadmap phase that delivers this module.
  final String plannedPhase;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(destination.label)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  destination.icon,
                  size: 56,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  destination.label,
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Module ${destination.moduleCode}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: <Widget>[
                        Text(
                          'This module is scheduled for $plannedPhase.',
                          style: theme.textTheme.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Its route, permission gate and navigation entry are '
                          'already enforced: you can reach this screen because '
                          'your role grants access to it.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
