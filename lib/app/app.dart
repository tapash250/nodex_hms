/// Application widget and bootstrap sequence.
///
/// Bootstrap order is deliberate and load-bearing:
///
/// 1. Resolve build configuration. A privileged Supabase key or a missing
///    required define fails here, before any clinical surface exists.
/// 2. Initialise Supabase, so a session can be restored.
/// 3. Open the encrypted local database, so clinical reads have a source.
/// 4. Connect replication if configured. Failure is non-fatal: the app is
///    local-first and continues against the local projection.
/// 5. Establish the session, which verifies the cached authorization snapshot.
///
/// A failure in steps 1-3 produces a diagnostic screen rather than a partially
/// functional clinical application.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/app/router/app_router.dart';
import 'package:nodex_hms/app/theme/nodex_theme.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// The NODEX application root.
class NodexApp extends ConsumerStatefulWidget {
  /// Creates the application root.
  const NodexApp({super.key});

  @override
  ConsumerState<NodexApp> createState() => _NodexAppState();
}

class _NodexAppState extends ConsumerState<NodexApp>
    with WidgetsBindingObserver {
  DateTime? _backgroundedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(sessionProvider.notifier).bootstrap();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _backgroundedAt = DateTime.now();
      case AppLifecycleState.resumed:
        _lockIfIdleTooLong();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  /// Locks the session when the app was backgrounded beyond the idle timeout.
  ///
  /// A ward tablet left on a trolley must not expose a live clinical session, but
  /// locking on every brief switch away would make the device unusable during a
  /// round. The configured idle timeout is the balance point.
  void _lockIfIdleTooLong() {
    final DateTime? backgroundedAt = _backgroundedAt;
    _backgroundedAt = null;
    if (backgroundedAt == null) {
      return;
    }

    final Duration idle = DateTime.now().difference(backgroundedAt);
    final Duration timeout = ref.read(environmentProvider).sessionIdleTimeout;
    if (idle >= timeout) {
      ref.read(sessionProvider.notifier).lock();
    }
  }

  @override
  Widget build(BuildContext context) {
    final GoRouter router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'NODEX Enterprise HMS',
      debugShowCheckedModeBanner: false,
      theme: NodexTheme.light(),
      darkTheme: NodexTheme.dark(),
      routerConfig: router,
    );
  }
}

/// Shown when bootstrap fails before the application can start safely.
///
/// Deliberately not a clinical surface: a build with an invalid configuration or
/// an unopenable encrypted database must not present itself as usable.
class BootstrapFailureApp extends StatelessWidget {
  /// Creates the failure screen.
  const BootstrapFailureApp({
    required this.title,
    required this.message,
    this.detail,
    super.key,
  });

  /// Short failure summary.
  final String title;

  /// Operator-facing explanation.
  final String message;

  /// Non-PHI diagnostic detail.
  final String? detail;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'NODEX Enterprise HMS',
    debugShowCheckedModeBanner: false,
    theme: NodexTheme.light(),
    darkTheme: NodexTheme.dark(),
    home: Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Builder(
                builder: (BuildContext context) {
                  final ThemeData theme = Theme.of(context);
                  return Column(
                    children: <Widget>[
                      Icon(
                        Icons.report_gmailerrorred_outlined,
                        size: 56,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        title,
                        style: theme.textTheme.headlineSmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        message,
                        style: theme.textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                      if (detail != null) ...<Widget>[
                        const SizedBox(height: 24),
                        Card(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              detail!,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
