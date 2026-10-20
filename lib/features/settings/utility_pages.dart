/// Operational utilities (Module 53).
///
/// The screens a support engineer opens when a device misbehaves: how big
/// the local database is, how far the network is away, and what can safely be
/// cleared. The last one is the important one — clearing the upload queue
/// would throw away clinical work that has not reached the server, so the
/// utility refuses to do it and says why.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:path_provider/path_provider.dart';

/// Renders a byte count the way a support engineer reads it.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const List<String> units = <String>['KB', 'MB', 'GB', 'TB'];
  double value = bytes / 1024;
  int unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(value >= 10 ? 0 : 1)} ${units[unit]}';
}

/// What a measured round trip means.
enum LatencyVerdict {
  /// Fast enough for the work at hand.
  good('Good'),

  /// Usable, but a clinician will notice.
  fair('Fair'),

  /// Slow enough to change how the device is used.
  poor('Poor');

  const LatencyVerdict(this.label);

  /// Human-readable label.
  final String label;
}

/// Reads a round trip as a verdict.
LatencyVerdict verdictFor(Duration roundTrip) {
  if (roundTrip <= const Duration(milliseconds: 300)) {
    return LatencyVerdict.good;
  }
  if (roundTrip <= const Duration(milliseconds: 1000)) {
    return LatencyVerdict.fair;
  }
  return LatencyVerdict.poor;
}

/// What a cache clear would remove.
@immutable
final class CacheClearPlan {
  /// Creates a plan.
  const CacheClearPlan({
    required this.removable,
    required this.withheld,
    required this.withheldReason,
  });

  /// The tables a clear would empty.
  final List<String> removable;

  /// The tables a clear would leave alone.
  final List<String> withheld;

  /// Why they are left alone.
  final String withheldReason;

  /// The plan this module always uses.
  ///
  /// The upload queue is withheld: it holds clinical work that has not
  /// reached the server, and a support engineer clearing a cache is not
  /// authorised to throw away a result.
  static const CacheClearPlan standard = CacheClearPlan(
    removable: <String>[LocalTables.localDiagnostics, LocalTables.scratchpads],
    withheld: <String>[LocalTables.localMutationLog],
    withheldReason:
        'The upload queue holds clinical work that has not reached the '
        'server yet. It is cleared by the sync engine when the work is '
        'accepted, not by a support engineer.',
  );
}

/// The operational utilities.
class UtilitiesScreen extends ConsumerWidget {
  /// Creates the screen.
  const UtilitiesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Utilities')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text('Device', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const _LocalDatabaseCard(),
          const SizedBox(height: 16),
          Text('Network', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const _NetworkLatencyCard(),
          const SizedBox(height: 16),
          Text('Cache', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const _CacheClearCard(),
        ],
      ),
    );
  }
}

/// Reports how big the local database is.
class _LocalDatabaseCard extends ConsumerStatefulWidget {
  const _LocalDatabaseCard();

  @override
  ConsumerState<_LocalDatabaseCard> createState() => _LocalDatabaseCardState();
}

class _LocalDatabaseCardState extends ConsumerState<_LocalDatabaseCard> {
  int? _bytes;
  int? _diagnosticRows;
  int? _queuedMutations;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _measure();
  }

  Future<void> _measure() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final Directory directory = await getApplicationSupportDirectory();
      int total = 0;
      for (final FileSystemEntity entity in directory.listSync()) {
        if (entity is File) total += entity.lengthSync();
      }
      final List<Map<String, Object?>> diagnostics = await ref
          .watch(localDatabaseProvider)
          .database
          .getAll('SELECT count(*) AS c FROM ${LocalTables.localDiagnostics}');
      final List<Map<String, Object?>> queued = await ref
          .watch(localDatabaseProvider)
          .database
          .getAll('SELECT count(*) AS c FROM ${LocalTables.localMutationLog}');
      if (!mounted) return;
      setState(() {
        _bytes = total;
        _diagnosticRows = (diagnostics.first['c'] as int?) ?? 0;
        _queuedMutations = (queued.first['c'] as int?) ?? 0;
        _busy = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Local database',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Measure again',
                  onPressed: _busy ? null : _measure,
                ),
              ],
            ),
            if (_error != null)
              Text(_error!, style: TextStyle(color: theme.colorScheme.error))
            else if (_busy)
              const LinearProgressIndicator()
            else ...<Widget>[
              Text('On disk: ${_bytes == null ? '—' : formatBytes(_bytes!)}'),
              Text('Diagnostic rows: ${_diagnosticRows ?? '—'}'),
              Text('Queued mutations: ${_queuedMutations ?? '—'}'),
            ],
          ],
        ),
      ),
    );
  }
}

/// Measures how far the server is.
class _NetworkLatencyCard extends ConsumerStatefulWidget {
  const _NetworkLatencyCard();

  @override
  ConsumerState<_NetworkLatencyCard> createState() =>
      _NetworkLatencyCardState();
}

class _NetworkLatencyCardState extends ConsumerState<_NetworkLatencyCard> {
  Duration? _roundTrip;
  String? _error;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text('Round trip', style: theme.textTheme.titleSmall),
                ),
                FilledButton.tonal(
                  onPressed: _busy ? null : _measure,
                  child: const Text('Test'),
                ),
              ],
            ),
            if (_error != null)
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            if (_roundTrip != null) ...<Widget>[
              const SizedBox(height: 4),
              Text('${_roundTrip!.inMilliseconds} ms'),
              Text(
                verdictFor(_roundTrip!).label,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _measure() async {
    setState(() {
      _busy = true;
      _error = null;
      _roundTrip = null;
    });
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5);
    try {
      final DateTime start = DateTime.now();
      final HttpClientRequest request = await client
          .getUrl(Uri.parse(ref.watch(environmentProvider).supabaseUrl))
          .timeout(const Duration(seconds: 8));
      request.headers.set('Accept', 'application/json');
      final HttpClientResponse response = await request.close();
      await response.drain<void>();
      final Duration roundTrip = DateTime.now().difference(start);
      if (!mounted) return;
      setState(() {
        _roundTrip = roundTrip;
        _busy = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'The server did not answer: $error';
        _busy = false;
      });
    } finally {
      client.close();
    }
  }
}

/// Clears what can safely be cleared.
class _CacheClearCard extends ConsumerStatefulWidget {
  const _CacheClearCard();

  @override
  ConsumerState<_CacheClearCard> createState() => _CacheClearCardState();
}

class _CacheClearCardState extends ConsumerState<_CacheClearCard> {
  String? _result;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    const CacheClearPlan plan = CacheClearPlan.standard;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Clear the local cache', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'Removes: ${plan.removable.join(', ')}',
              style: theme.textTheme.bodySmall,
            ),
            Text(
              'Keeps: ${plan.withheld.join(', ')}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(plan.withheldReason, style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: _clear,
              child: const Text('Clear what is safe'),
            ),
            if (_result != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(_result!, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _clear() async {
    try {
      await ref
          .read(localDatabaseProvider)
          .database
          .execute('DELETE FROM ${LocalTables.localDiagnostics}');
      await ref
          .read(localDatabaseProvider)
          .database
          .execute('DELETE FROM ${LocalTables.scratchpads}');
      if (!mounted) return;
      setState(
        () => _result = 'The diagnostic buffer and the scratchpad are empty.',
      );
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _result = 'Could not clear the cache: $error');
    }
  }
}
