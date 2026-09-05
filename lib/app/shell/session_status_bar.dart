/// Persistent session status bar.
///
/// Surfaces the two facts a clinician must be able to see without navigating:
/// whether the device is replicating to the cloud, and how much offline
/// authorization remains. Both are load-bearing in an offline-first system —
/// a nurse needs to know that a recorded observation has not yet reached the
/// server, and that authorization is lapsing while there is still time to
/// reconnect.
///
/// The bar hides itself when everything is nominal, so it does not consume
/// clinical screen space or become background noise that gets ignored.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodex_hms/app/theme/nodex_theme.dart';
import 'package:nodex_hms/domain/session/session_state.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// Compact status strip shown above the active destination.
class SessionStatusBar extends ConsumerWidget {
  /// Creates the status bar.
  const SessionStatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SessionState session = ref.watch(sessionProvider);
    final DateTime now = DateTime.now();

    final bool isOffline = !session.connectivity.isOnline;
    final bool hasPendingUploads = session.pendingUploadCount > 0;
    final bool authorizationExpiringSoon = session.isAuthorizationExpiringSoon(
      now,
    );

    if (!isOffline && !hasPendingUploads && !authorizationExpiringSoon) {
      return const SizedBox.shrink();
    }

    final ClinicalSeverityColors severity = Theme.of(context)
        .extension<ClinicalSeverityColors>()!;

    // Authorization expiry outranks connectivity: losing authorization stops
    // clinical work entirely, while working offline is a supported mode.
    final (Color background, IconData icon, String message) = switch ((
      authorizationExpiringSoon,
      isOffline,
      hasPendingUploads,
    )) {
      (true, _, _) => (
        severity.high,
        Icons.timer_outlined,
        'Offline access expires in '
            '${_formatDuration(session.remainingAuthorization(now))}. '
            'Reconnect to extend.',
      ),
      (false, true, true) => (
        severity.moderate,
        Icons.cloud_off_outlined,
        'Working offline. ${session.pendingUploadCount} '
            '${session.pendingUploadCount == 1 ? 'change' : 'changes'} '
            'waiting to sync.',
      ),
      (false, true, false) => (
        severity.info,
        Icons.cloud_off_outlined,
        'Working offline. Clinical records are saved on this device.',
      ),
      (false, false, true) => (
        severity.info,
        Icons.sync_outlined,
        'Syncing ${session.pendingUploadCount} '
            '${session.pendingUploadCount == 1 ? 'change' : 'changes'}.',
      ),
      _ => (severity.info, Icons.info_outline, 'Session status'),
    };

    return Semantics(
      liveRegion: true,
      container: true,
      child: Material(
        color: background,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: <Widget>[
                Icon(icon, size: 18, color: severity.onSeverity),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    message,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: severity.onSeverity),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _formatDuration(Duration duration) {
    if (duration.inMinutes < 1) {
      return 'under a minute';
    }
    if (duration.inMinutes < 60) {
      return '${duration.inMinutes} min';
    }
    final int hours = duration.inHours;
    final int minutes = duration.inMinutes % 60;
    return minutes == 0 ? '$hours h' : '$hours h $minutes min';
  }
}
