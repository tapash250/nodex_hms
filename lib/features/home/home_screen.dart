/// Role-aware home surface.
///
/// Renders what the signed-in principal can actually do: the modules their
/// permissions reach, the roles they hold, and the current state of offline
/// authorization. Phase 1 has no clinical data to summarise, so the screen is
/// deliberately an honest statement of session capability rather than a mock
/// dashboard with invented numbers.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nodex_hms/app/router/navigation_destinations.dart';
import 'package:nodex_hms/core/authorization/authorization_snapshot.dart';
import 'package:nodex_hms/domain/session/session_state.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// Home screen.
class HomeScreen extends ConsumerWidget {
  /// Creates the home screen.
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SessionState session = ref.watch(sessionProvider);
    final AuthorizationSnapshot? snapshot = session.snapshot;
    final ThemeData theme = Theme.of(context);

    final List<NavigationDestinationSpec> reachable =
        NodexDestinations.visibleTo(session.authorization);

    return Scaffold(
      appBar: AppBar(
        title: const Text('NODEX'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.lock_outline),
            tooltip: 'Lock session',
            onPressed: () => ref.read(sessionProvider.notifier).lock(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _SessionSummaryCard(session: session),
          const SizedBox(height: 16),
          if (snapshot != null) ...<Widget>[
            Text('Assigned roles', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: snapshot.roles
                  .map(
                    (String role) => Chip(
                      avatar: const Icon(Icons.badge_outlined, size: 18),
                      label: Text(_humanise(role)),
                    ),
                  )
                  .toList(growable: false),
            ),
            const SizedBox(height: 24),
          ],
          Text('Available modules', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          ...reachable.map(
            (NavigationDestinationSpec spec) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon(spec.icon),
                title: Text(spec.label),
                subtitle: Text('Module ${spec.moduleCode}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go(spec.routePath),
              ),
            ),
          ),
        ],
      ),
    );
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

class _SessionSummaryCard extends StatelessWidget {
  const _SessionSummaryCard({required this.session});

  final SessionState session;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AuthorizationSnapshot? snapshot = session.snapshot;
    final DateTime now = DateTime.now();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                CircleAvatar(
                  child: Text(
                    _initials(session.user?.preferredName ?? 'NODEX'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        session.user?.preferredName ?? 'Clinical user',
                        style: theme.textTheme.titleMedium,
                      ),
                      if (session.user?.designation != null)
                        Text(
                          session.user!.designation!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            _StatusRow(
              icon: session.connectivity.isOnline
                  ? Icons.cloud_done_outlined
                  : Icons.cloud_off_outlined,
              label: 'Connectivity',
              value: session.connectivity.isOnline
                  ? 'Online, replicating'
                  : 'Offline, working locally',
            ),
            if (snapshot != null)
              _StatusRow(
                icon: Icons.timer_outlined,
                label: 'Offline access',
                value: _formatRemaining(snapshot.remainingValidity(now)),
              ),
            if (snapshot != null)
              _StatusRow(
                icon: Icons.key_outlined,
                label: 'Permissions',
                value:
                    '${snapshot.permissions.length} granted, '
                    '${snapshot.offlinePermissions.length} usable offline',
              ),
            _StatusRow(
              icon: Icons.sync_outlined,
              label: 'Pending uploads',
              value: session.pendingUploadCount == 0
                  ? 'None'
                  : '${session.pendingUploadCount} awaiting sync',
            ),
          ],
        ),
      ),
    );
  }

  static String _initials(String name) {
    final List<String> parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((String part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) {
      return '?';
    }
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  static String _formatRemaining(Duration remaining) {
    if (remaining == Duration.zero) {
      return 'Expired';
    }
    if (remaining.inHours >= 1) {
      final int minutes = remaining.inMinutes % 60;
      return minutes == 0
          ? '${remaining.inHours} h remaining'
          : '${remaining.inHours} h $minutes min remaining';
    }
    return '${remaining.inMinutes} min remaining';
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Text(label, style: theme.textTheme.bodyMedium),
          const Spacer(),
          Flexible(
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
