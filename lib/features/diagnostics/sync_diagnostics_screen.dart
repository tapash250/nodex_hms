/// Synchronization diagnostics.
///
/// The specification requires that failed synchronization is visible, recoverable
/// and never silently discarded. This screen is where that visibility lives: sync
/// health, queue depth, the oldest pending mutation, and the redacted diagnostic
/// log.
///
/// Every value shown here is non-PHI by construction; the logging layer redacts
/// records before they reach the buffer this screen reads.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/sync/conflict_policy.dart';
import 'package:nodex_hms/domain/session/session_state.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// Sync diagnostics screen.
class SyncDiagnosticsScreen extends ConsumerWidget {
  /// Creates the diagnostics screen.
  const SyncDiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SessionState session = ref.watch(sessionProvider);
    final InMemoryLogSink sink = ref.watch(diagnosticsSinkProvider);
    final ThemeData theme = Theme.of(context);

    // Newest first: an operator investigating a failure wants the most recent
    // events without scrolling.
    final List<NodexLogRecord> records = sink.records.reversed
        .take(100)
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(title: const Text('Synchronization')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('Replication', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  _DiagnosticRow(
                    label: 'Connectivity',
                    value: session.connectivity.isOnline ? 'Online' : 'Offline',
                  ),
                  _DiagnosticRow(
                    label: 'Pending uploads',
                    value: '${session.pendingUploadCount}',
                  ),
                  _DiagnosticRow(
                    label: 'Last successful sync',
                    value: session.lastSyncAt == null
                        ? 'Not yet synchronized'
                        : _formatTimestamp(session.lastSyncAt!),
                  ),
                  _DiagnosticRow(
                    label: 'Offline authorization',
                    value: session.snapshot == null
                        ? 'Not established'
                        : _formatRemaining(
                            session.remainingAuthorization(DateTime.now()),
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
                  Text('Conflict policies', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Each clinical entity resolves conflicts by a declared, '
                    'deterministic strategy. There is no global last-write-wins.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...ConflictPolicyRegistry.entries.values.map(
                    (ConflictPolicyEntry entry) => _DiagnosticRow(
                      label: _humanise(entry.resourceType),
                      value: _humanise(entry.policy.wireValue),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Recent activity', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Diagnostic records are redacted and contain no patient information.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          if (records.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No diagnostic activity recorded yet.'),
              ),
            )
          else
            ...records.map(
              (NodexLogRecord record) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(
                    _iconFor(record.level),
                    color: _colorFor(record.level, theme),
                  ),
                  title: Text(record.message),
                  subtitle: Text(
                    <String>[
                      record.module,
                      ?record.operation,
                      ?record.outcome,
                      _formatTimestamp(record.timestamp),
                    ].join(' • '),
                  ),
                  isThreeLine: false,
                ),
              ),
            ),
        ],
      ),
    );
  }

  static IconData _iconFor(NodexLogLevel level) => switch (level) {
    NodexLogLevel.trace => Icons.bug_report_outlined,
    NodexLogLevel.info => Icons.info_outline,
    NodexLogLevel.warning => Icons.warning_amber_outlined,
    NodexLogLevel.error => Icons.error_outline,
    NodexLogLevel.critical => Icons.dangerous_outlined,
  };

  static Color _colorFor(NodexLogLevel level, ThemeData theme) =>
      switch (level) {
        NodexLogLevel.trace => theme.colorScheme.onSurfaceVariant,
        NodexLogLevel.info => theme.colorScheme.primary,
        NodexLogLevel.warning => theme.colorScheme.tertiary,
        NodexLogLevel.error => theme.colorScheme.error,
        NodexLogLevel.critical => theme.colorScheme.error,
      };

  static String _formatTimestamp(DateTime timestamp) {
    final DateTime local = timestamp.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }

  static String _formatRemaining(Duration remaining) {
    if (remaining == Duration.zero) {
      return 'Expired';
    }
    if (remaining.inHours >= 1) {
      return '${remaining.inHours} h ${remaining.inMinutes % 60} min remaining';
    }
    return '${remaining.inMinutes} min remaining';
  }

  static String _humanise(String key) => key
      .split('_')
      .map(
        (String part) => part.isEmpty
            ? part
            : '${part[0].toUpperCase()}${part.substring(1)}',
      )
      .join(' ');
}

class _DiagnosticRow extends StatelessWidget {
  const _DiagnosticRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
