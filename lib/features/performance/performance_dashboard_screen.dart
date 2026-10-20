/// The performance dashboard (Module 03).
///
/// Each indicator is shown with its own baseline, because an indicator
/// without its baseline is a number and not a judgement. The reading that
/// has drifted comes first, and the screen says how far it has drifted.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/app/widgets/clinical_widgets.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/performance/performance_index.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// The latest reading for each performance indicator.
final performanceDashboardProvider = FutureProvider.autoDispose
    .family<List<PerformanceIndex>, String>((Ref ref, String tenantKey) async {
      return ref
          .watch(readPerformanceDashboardUseCaseProvider)
          .call(policy: ref.watch(sessionProvider).authorization);
    });

/// The clinical performance dashboard.
class PerformanceDashboardScreen extends ConsumerWidget {
  /// Creates the screen.
  const PerformanceDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<PerformanceIndex>> readings = ref.watch(
      performanceDashboardProvider('current'),
    );
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Performance')),
      body: readings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace _) => Center(
          child: Text(
            error is NodexError
                ? error.message
                : 'Performance indicators are unavailable.',
          ),
        ),
        data: (List<PerformanceIndex> values) => values.isEmpty
            ? const Center(
                child: Text('No performance indicators have been recorded.'),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: values.length,
                itemBuilder: (BuildContext context, int index) {
                  final PerformanceIndex reading = values[index];
                  final bool worse = reading.isWorseThanBaseline;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Icon(
                        worse ? Icons.trending_up : Icons.check_circle_outline,
                        color: worse ? theme.colorScheme.error : null,
                      ),
                      title: Text(reading.indicatorName),
                      subtitle: Text(
                        <String>[
                          reading.summary,
                          'baseline ${_number(reading.baselineMean)} ± ${_number(reading.baselineStddev)}',
                          if (reading.sampleSize > 0)
                            '${reading.sampleSize} case(s)',
                        ].join(' · '),
                      ),
                      trailing: ClinicalStatusBadge(
                        label: reading.standing.label,
                        tone: worse
                            ? ClinicalTone.critical
                            : ClinicalTone.success,
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  static String _number(double? value) =>
      value == null ? '—' : value.toStringAsFixed(1);
}
