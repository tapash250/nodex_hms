/// Settings and security posture surface.
///
/// Shows the device's security state and the controls a user can exercise
/// themselves: session lock, sign-out with local data clearing, and a full local
/// wipe. Administrative controls (device revocation, role changes, tenant
/// configuration) require online revalidation and live on the server.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/config/nodex_environment.dart';
import 'package:nodex_hms/domain/session/session_state.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// Settings screen.
class SettingsScreen extends ConsumerWidget {
  /// Creates the settings screen.
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SessionState session = ref.watch(sessionProvider);
    final NodexEnvironment environment = ref.watch(environmentProvider);
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('This device', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  _SettingRow(
                    label: 'Form factor',
                    value: session.device?.formFactor.wireValue ?? 'unknown',
                  ),
                  _SettingRow(
                    label: 'Application version',
                    value: session.device?.appVersion ?? 'unknown',
                  ),
                  _SettingRow(
                    label: 'Android version',
                    value: session.device?.osVersion ?? 'unknown',
                  ),
                  _SettingRow(
                    label: 'Environment',
                    value: environment.environment.name,
                  ),
                  _SettingRow(
                    label: 'Replication',
                    value: environment.isSyncConfigured
                        ? 'Configured'
                        : 'Local only (no PowerSync instance configured)',
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
                  Text('Local data', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    'Clinical data on this device is stored in an encrypted '
                    'database whose key is held in the Android Keystore. The '
                    'cloud system of record remains authoritative, so clearing '
                    'local data never loses a committed clinical record.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.lock_outline),
                    title: const Text('Lock session now'),
                    subtitle: const Text(
                      'Requires biometric or device credential to resume',
                    ),
                    onTap: () => ref.read(sessionProvider.notifier).lock(),
                  ),
                  const Divider(),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.logout),
                    title: const Text('Sign out'),
                    subtitle: const Text(
                      'Clears local clinical data on this device',
                    ),
                    onTap: () => _confirmSignOut(context, ref),
                  ),
                  const Divider(),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.delete_forever_outlined,
                      color: theme.colorScheme.error,
                    ),
                    title: Text(
                      'Wipe local data and keys',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                    subtitle: const Text(
                      'Destroys the local database encryption key',
                    ),
                    onTap: () => _confirmWipe(context, ref),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Administrative controls',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Role assignment, device revocation and tenant configuration '
                    'require online revalidation and are performed by a hospital '
                    'administrator. They are enforced server-side regardless of '
                    'what this client requests.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
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

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Sign out'),
        content: const Text(
          'Local clinical data on this device will be cleared. Any change that '
          'has not yet reached the server will be reported before it is '
          'discarded.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      await ref.read(sessionProvider.notifier).signOut();
    }
  }

  Future<void> _confirmWipe(BuildContext context, WidgetRef ref) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Wipe local data'),
        content: const Text(
          'This destroys the local database encryption key, making local '
          'clinical data unreadable. The cloud system of record is unaffected. '
          'You will need to sign in again and re-download your authorized data.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Wipe'),
          ),
        ],
      ),
    );

    if (!(confirmed ?? false)) {
      return;
    }

    await ref
        .read(localDatabaseProvider)
        .wipe(reason: 'user_initiated_local_wipe');
    await ref.read(sessionProvider.notifier).signOut();
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({required this.label, required this.value});

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
