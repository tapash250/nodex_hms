/// Audit trail surface.
///
/// Phase 1 establishes the append-only audit envelope in the database and the
/// permission that gates reading it. Query surfaces over that history land with
/// the modules that generate the events, so this screen states what exists rather
/// than rendering an empty table that implies a missing feature.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/domain/session/session_state.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// Audit screen.
class AuditScreen extends ConsumerWidget {
  /// Creates the audit screen.
  const AuditScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SessionState session = ref.watch(sessionProvider);
    final ThemeData theme = Theme.of(context);
    final AuthorizationPolicy policy = session.authorization;

    return Scaffold(
      appBar: AppBar(title: const Text('Audit')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Append-only clinical audit',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Safety-critical clinical actions are recorded as immutable '
                    'events. Administrative tools may query and export that '
                    'history but cannot rewrite it: update and delete are '
                    'blocked at the database level.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _AuditCapability(
                    label: 'Read audit trail',
                    granted: policy.can(NodexPermissions.auditRead),
                  ),
                  _AuditCapability(
                    label: 'Read clinical event stream',
                    granted: policy.can(NodexPermissions.clinicalEventRead),
                  ),
                  _AuditCapability(
                    label: 'Review AI governance records',
                    granted: policy.can(NodexPermissions.aiGovernanceRead),
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
                    'Recorded per high-risk action',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  ...const <String>[
                    'Actor, role and tenant',
                    'Facility and clinical context',
                    'Device and session reference',
                    'Correlation and mutation identifiers',
                    'Whether the action originated offline or online',
                    'Before and after state, or an event reference',
                    'AI involvement, model, provider and revision',
                    'Rule engine revision',
                    'Human reviewer and decision',
                    'Outcome',
                  ].map(
                    (String field) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: <Widget>[
                          Icon(
                            Icons.chevron_right,
                            size: 18,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              field,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuditCapability extends StatelessWidget {
  const _AuditCapability({required this.label, required this.granted});

  final String label;
  final bool granted;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Icon(
            granted ? Icons.check_circle_outline : Icons.remove_circle_outline,
            size: 20,
            color: granted
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          Text(
            granted ? 'Granted' : 'Not granted',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
