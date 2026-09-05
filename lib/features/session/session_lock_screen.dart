/// Session lock and recovery screens.
///
/// Three related surfaces:
///
/// * [SessionLockScreen] gates a live session behind biometric or credential
///   re-entry after idle timeout. Authorization is retained, so an interrupted
///   ward round resumes without a server round trip.
/// * [AwaitingAuthorizationScreen] is shown when a principal is authenticated but
///   the device holds no valid authorization snapshot.
/// * [QuarantinedScreen] is shown after an integrity fault, when local data has
///   been wiped and re-authentication is required.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:nodex_hms/domain/session/session_state.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// Biometric or credential unlock surface.
class SessionLockScreen extends ConsumerStatefulWidget {
  /// Creates the lock screen.
  const SessionLockScreen({super.key});

  @override
  ConsumerState<SessionLockScreen> createState() => _SessionLockScreenState();
}

class _SessionLockScreenState extends ConsumerState<SessionLockScreen> {
  bool _isAuthenticating = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    // Prompt immediately: the user locked the screen, they expect the biometric
    // sheet rather than another button to press.
    WidgetsBinding.instance.addPostFrameCallback((_) => _authenticate());
  }

  Future<void> _authenticate() async {
    if (_isAuthenticating) {
      return;
    }
    setState(() {
      _isAuthenticating = true;
      _message = null;
    });

    try {
      final LocalAuthentication auth = LocalAuthentication();
      final bool isSupported = await auth.isDeviceSupported();
      final bool canCheck = await auth.canCheckBiometrics;

      if (!isSupported && !canCheck) {
        // No device credential configured. Unlocking here would leave the
        // session unguarded, so require a full sign-out and sign-in instead.
        if (mounted) {
          setState(
            () => _message =
                'This device has no screen lock configured. Sign out and sign '
                'in again to continue.',
          );
        }
        return;
      }

      final bool didAuthenticate = await auth.authenticate(
        localizedReason: 'Unlock your NODEX clinical session',
        // Device credential is accepted as a fallback so a clinician with a wet
        // or gloved hand is not locked out mid-shift.
        biometricOnly: false,
        // Survive the prompt being backgrounded rather than failing the unlock.
        persistAcrossBackgrounding: true,
      );

      if (!didAuthenticate) {
        if (mounted) {
          setState(() => _message = 'Unlock was cancelled.');
        }
        return;
      }

      await ref.read(sessionProvider.notifier).unlock();
    } on Object {
      if (mounted) {
        setState(
          () => _message =
              'Unlock could not be completed on this device. Sign out and sign '
              'in again to continue.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isAuthenticating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final SessionState session = ref.watch(sessionProvider);
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(
                    Icons.lock_outline,
                    size: 56,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Session locked',
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    session.user?.preferredName ??
                        'Unlock to return to your workspace',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (_message != null) ...<Widget>[
                    const SizedBox(height: 24),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _message!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    onPressed: _isAuthenticating ? null : _authenticate,
                    icon: const Icon(Icons.fingerprint),
                    label: const Text('Unlock'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _isAuthenticating
                        ? null
                        : () => ref.read(sessionProvider.notifier).signOut(),
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown while authenticated but not yet authorized in a tenant.
class AwaitingAuthorizationScreen extends ConsumerWidget {
  /// Creates the awaiting-authorization screen.
  const AwaitingAuthorizationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SessionState session = ref.watch(sessionProvider);
    final ThemeData theme = Theme.of(context);
    final bool isOffline = !session.connectivity.isOnline;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(
                    isOffline
                        ? Icons.cloud_off_outlined
                        : Icons.verified_user_outlined,
                    size: 56,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    isOffline
                        ? 'Reconnect to restore access'
                        : 'Establishing authorization',
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    session.message ??
                        'Your clinical permissions are being confirmed with '
                            'the server.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  if (!isOffline)
                    const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () => ref
                        .read(sessionProvider.notifier)
                        .refreshAuthorization(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry now'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () =>
                        ref.read(sessionProvider.notifier).signOut(),
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown after an integrity fault has quarantined the session.
class QuarantinedScreen extends ConsumerWidget {
  /// Creates the quarantine screen.
  const QuarantinedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SessionState session = ref.watch(sessionProvider);
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(
                    Icons.gpp_maybe_outlined,
                    size: 56,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Security verification failed',
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    session.message ??
                        'The local security state could not be verified. Local '
                            'clinical data on this device has been cleared. '
                            'Sign in again to restore access.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No clinical record has been lost: the cloud system of '
                    'record is authoritative and unaffected.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  FilledButton(
                    onPressed: () =>
                        ref.read(sessionProvider.notifier).signOut(),
                    child: const Text('Sign in again'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
