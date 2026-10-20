/// The operations dashboard (Module 02).
///
/// The dashboard answers one question — where is the queue building — and it
/// answers it with the readings the operational systems wrote. A department
/// is flagged when the numbers say it is long, and the screen shows which
/// numbers, because a red box nobody can check is a rumour.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodex_hms/app/charts/clinical_bar_chart.dart';
import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/app/widgets/clinical_widgets.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/operations/department_metric.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// The latest flow reading for each department.
final operationsDashboardProvider = FutureProvider.autoDispose
    .family<List<DepartmentMetric>, String>((Ref ref, String facilityId) async {
      return ref
          .watch(readOperationsDashboardUseCaseProvider)
          .call(policy: ref.watch(sessionProvider).authorization);
    });

/// The operations dashboard.
class OperationsDashboardScreen extends ConsumerWidget {
  /// Creates the screen.
  const OperationsDashboardScreen({required this.facilityId, super.key});

  /// The facility whose flow is shown.
  final String facilityId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<DepartmentMetric>> metrics = ref.watch(
      operationsDashboardProvider(facilityId),
    );
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Operations')),
      body: metrics.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace _) => Center(
          child: Text(
            error is NodexError
                ? error.message
                : 'Operational flow is unavailable.',
          ),
        ),
        data: (List<DepartmentMetric> values) {
          if (values.isEmpty) {
            return const Center(
              child: Text('No operational readings have arrived yet.'),
            );
          }
          final int backlogged = values
              .where((DepartmentMetric metric) => metric.isBacklogged())
              .length;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Waiting by department',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$backlogged of ${values.length} department(s) '
                        'have a queue that needs attention',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      ClinicalBarChart(
                        bars: <ChartBar>[
                          for (final DepartmentMetric metric in values)
                            ChartBar(
                              label: _shortLabel(metric.departmentId),
                              value: metric.waitingCount.toDouble(),
                              tone: metric.isBacklogged()
                                  ? ClinicalTone.critical
                                  : ClinicalTone.info,
                            ),
                        ],
                        height: 180,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              for (final DepartmentMetric metric in values)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(
                      metric.isBacklogged()
                          ? Icons.warning_amber_outlined
                          : Icons.check_circle_outline,
                      color: metric.isBacklogged()
                          ? theme.colorScheme.error
                          : null,
                    ),
                    title: Text(_shortLabel(metric.departmentId)),
                    subtitle: Text(
                      <String>[
                        metric.summary,
                        if (metric.bottleneck != null)
                          'Bottleneck: ${metric.bottleneck}',
                      ].join(' · '),
                    ),
                    trailing: Text(
                      '${(metric.waitingShare * 100).toStringAsFixed(0)}%',
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// The last part of a department identifier, which is its code in the data.
  static String _shortLabel(String departmentId) {
    final int underscore = departmentId.lastIndexOf('-');
    if (underscore < 0 || underscore == departmentId.length - 1) {
      return departmentId;
    }
    return departmentId.substring(underscore + 1);
  }
}
