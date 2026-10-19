/// Laboratory order section embedded in the patient detail screen (Module 17).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nodex_hms/app/charts/chart_geometry.dart';
import 'package:nodex_hms/app/charts/clinical_line_chart.dart';
import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/app/widgets/clinical_widgets.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/laboratory/lab.dart';
import 'package:nodex_hms/domain/session/session_state.dart';
import 'package:nodex_hms/features/laboratory/lab_trend.dart';
import 'package:nodex_hms/features/laboratory/laboratory_controller.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// Shows laboratory orders and the order creation entry point for a patient.
class LabPatientSection extends ConsumerWidget {
  /// Creates the section.
  const LabPatientSection({required this.patientId, super.key});

  /// Patient identifier.
  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<LabOrder>> orders = ref.watch(
      labOrdersForPatientProvider(patientId),
    );
    final SessionState session = ref.watch(sessionProvider);
    final bool canOrder = session.authorization.can(
      NodexPermissions.labOrderWrite,
    );
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text('Laboratory', style: theme.textTheme.titleMedium),
            ),
            if (canOrder)
              TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Order'),
                onPressed: () => _showOrderSheet(context, ref),
              ),
          ],
        ),
        orders.when(
          loading: () => const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
          error: (Object error, StackTrace _) => Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                error is NodexError
                    ? error.message
                    : 'Laboratory history unavailable.',
              ),
            ),
          ),
          data: (List<LabOrder> values) => values.isEmpty
              ? const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No laboratory orders recorded.'),
                  ),
                )
              : Column(
                  children: values
                      .map(
                        (LabOrder order) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: Icon(
                              order.priority == LabPriority.stat
                                  ? Icons.priority_high
                                  : Icons.science_outlined,
                            ),
                            title: Text(order.orderCode),
                            subtitle: Text(
                              '${order.priority.label} · ${order.status.wireValue} · ${order.tests.length} test(s)',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.go(
                              '/patients/$patientId/lab/${order.id}',
                            ),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
        ),
        const SizedBox(height: 16),
        _LabTrends(patientId: patientId),
      ],
    );
  }

  Future<void> _showOrderSheet(BuildContext context, WidgetRef ref) async {
    final _LabOrderDraft? draft = await showModalBottomSheet<_LabOrderDraft>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) => const _LabOrderSheet(),
    );
    if (draft == null) return;
    final SessionState session = ref.read(sessionProvider);
    final String? userId = session.user?.userId;
    final String? tenantId = session.tenantId;
    if (userId == null || tenantId == null) return;
    try {
      final String id = await ref
          .read(createLabOrderUseCaseProvider)
          .call(
            policy: session.authorization,
            tenantId: tenantId,
            patientId: patientId,
            orderedBy: userId,
            orderCode: draft.orderCode,
            priority: draft.priority,
            tests: <LabTestRequest>[
              LabTestRequest(code: draft.testCode, name: draft.testName),
            ],
            clinicalIndication: draft.indication,
          );
      ref.invalidate(labOrdersForPatientProvider(patientId));
      if (context.mounted) context.go('/patients/$patientId/lab/$id');
    } on NodexError catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }
}

/// The patient's numeric trends, drawn as curves.
///
/// A trend is drawn only when there is something to draw: an analyte with a
/// single reading is a measurement, not a direction, so it is not shown here.
class _LabTrends extends ConsumerWidget {
  const _LabTrends({required this.patientId});

  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<LabTrend>> trends = ref.watch(
      labTrendsProvider(patientId),
    );
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Trends', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        trends.when(
          loading: () => const LinearProgressIndicator(),
          error: (Object error, StackTrace _) => Text(
            error is NodexError
                ? error.message
                : 'Trends unavailable on this device.',
            style: theme.textTheme.bodySmall,
          ),
          data: (List<LabTrend> values) => values.isEmpty
              ? Text(
                  'No analyte has been measured twice yet.',
                  style: theme.textTheme.bodySmall,
                )
              : Column(
                  children: values
                      .map((LabTrend trend) => _TrendCard(trend: trend))
                      .toList(growable: false),
                ),
        ),
      ],
    );
  }
}

/// One analyte's curve.
class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.trend});

  final LabTrend trend;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String unit = trend.unit ?? '';
    final List<ChartPoint> points = <ChartPoint>[
      for (int i = 0; i < trend.points.length; i++)
        ChartPoint(
          i.toDouble(),
          trend.points[i].value,
          label: _day(trend.points[i].at),
        ),
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '${trend.analyteName}${unit.isEmpty ? '' : ' ($unit)'}',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                ClinicalStatusBadge(
                  label: trend.latestIsAbnormal ? 'Outside range' : 'In range',
                  tone: trend.latestIsAbnormal
                      ? ClinicalTone.critical
                      : ClinicalTone.success,
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClinicalLineChart(
              series: <ChartSeries>[
                ChartSeries(
                  label: trend.analyteName,
                  points: points,
                  tone: trend.latestIsAbnormal
                      ? ClinicalTone.critical
                      : ClinicalTone.info,
                ),
              ],
              bands: <ChartBand>[
                if (trend.referenceLow != null && trend.referenceHigh != null)
                  ChartBand(
                    from: trend.referenceLow!,
                    to: trend.referenceHigh!,
                    label: 'Reference',
                  ),
              ],
              unit: unit.isEmpty ? null : unit,
              xLabelBuilder: (ChartPoint point) => point.label ?? '',
            ),
            const SizedBox(height: 4),
            Text(
              'Latest ${_number(trend.latest.value)} $unit · '
              '${trend.points.length} readings'
              '${trend.referenceLow != null ? ' · reference ${_number(trend.referenceLow!)}–${_number(trend.referenceHigh!)}' : ''}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  static String _number(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(1);

  static String _day(DateTime at) {
    final DateTime local = at.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}';
  }
}

class _LabOrderDraft {
  const _LabOrderDraft({
    required this.orderCode,
    required this.testCode,
    required this.testName,
    required this.priority,
    this.indication,
  });
  final String orderCode;
  final String testCode;
  final String testName;
  final LabPriority priority;
  final String? indication;
}

class _LabOrderSheet extends StatefulWidget {
  const _LabOrderSheet();
  @override
  State<_LabOrderSheet> createState() => _LabOrderSheetState();
}

class _LabOrderSheetState extends State<_LabOrderSheet> {
  final TextEditingController _orderCode = TextEditingController();
  final TextEditingController _testCode = TextEditingController(text: 'CBC');
  final TextEditingController _testName = TextEditingController(
    text: 'Complete blood count',
  );
  final TextEditingController _indication = TextEditingController();
  LabPriority _priority = LabPriority.routine;

  @override
  void dispose() {
    _orderCode.dispose();
    _testCode.dispose();
    _testName.dispose();
    _indication.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + keyboard),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text(
            'Create laboratory order',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _orderCode,
            decoration: const InputDecoration(labelText: 'Order code *'),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _testCode,
                  decoration: const InputDecoration(labelText: 'Test code *'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _testName,
                  decoration: const InputDecoration(labelText: 'Test name *'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<LabPriority>(
            initialValue: _priority,
            decoration: const InputDecoration(labelText: 'Priority'),
            items: LabPriority.values
                .map(
                  (LabPriority p) => DropdownMenuItem<LabPriority>(
                    value: p,
                    child: Text(p.label),
                  ),
                )
                .toList(growable: false),
            onChanged: (LabPriority? value) {
              if (value != null) setState(() => _priority = value);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _indication,
            decoration: const InputDecoration(
              labelText: 'Clinical indication (optional)',
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              if (_orderCode.text.trim().isEmpty ||
                  _testCode.text.trim().isEmpty ||
                  _testName.text.trim().isEmpty) {
                return;
              }
              Navigator.pop(
                context,
                _LabOrderDraft(
                  orderCode: _orderCode.text.trim(),
                  testCode: _testCode.text.trim(),
                  testName: _testName.text.trim(),
                  priority: _priority,
                  indication: _indication.text.trim().isEmpty
                      ? null
                      : _indication.text.trim(),
                ),
              );
            },
            child: const Text('Create order'),
          ),
        ],
      ),
    );
  }
}
