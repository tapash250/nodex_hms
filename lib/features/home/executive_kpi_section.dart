/// Executive KPI surface on the home landing page (Module 01).
///
/// The home screen is the global executive dashboard. It shows the latest
/// facility reading, the four risk points derived from that reading and the
/// trailing baseline each point was compared with. When no approved narrative
/// is attached, the screen says so rather than presenting a generated sentence
/// as if a model had been cleared to write one.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodex_hms/app/widgets/clinical_widgets.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/executive/executive_kpi.dart';
import 'package:nodex_hms/domain/session/session_state.dart';
import 'package:nodex_hms/features/home/executive_kpi_controller.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// The executive section shown to a principal with `executive.read`.
class ExecutiveKpiSection extends ConsumerWidget {
  /// Creates the section.
  const ExecutiveKpiSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SessionState session = ref.watch(sessionProvider);
    if (!session.authorization.can(NodexPermissions.executiveRead)) {
      return const SizedBox.shrink();
    }
    final AsyncValue<ExecutiveKpiState> reading = ref.watch(
      executiveKpiProvider,
    );
    return reading.when(
      loading: () => const _MessageCard(
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('Reading the latest executive snapshot...'),
          ],
        ),
      ),
      error: (Object error, StackTrace _) => _MessageCard(
        child: Text(
          error is NodexError
              ? error.message
              : 'The executive reading is unavailable.',
        ),
      ),
      data: (ExecutiveKpiState state) => ExecutiveKpiView(state: state),
    );
  }
}

/// The rendered executive reading, separated from the provider for tests.
class ExecutiveKpiView extends StatelessWidget {
  /// Creates the view.
  const ExecutiveKpiView({required this.state, super.key});

  /// The reading to render.
  final ExecutiveKpiState state;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    if (state.facilityId.isEmpty) {
      return const _MessageCard(
        child: Text(
          'No facility is in this session scope, so there is no executive '
          'reading to show.',
        ),
      );
    }
    final ExecutiveKpiSnapshot? latest = state.latest;
    if (latest == null) {
      return const _MessageCard(
        child: Text(
          'No executive snapshot has replicated to this device yet. The '
          'capture job writes snapshots on the server; this surface reads '
          'what it wrote.',
        ),
      );
    }

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
                    'Executive reading',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Text(
                  _timestamp(latest.at),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Facility ${latest.facilityId}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                _KpiTile(
                  icon: Icons.hotel_outlined,
                  label: 'Occupancy',
                  value: '${latest.occupancyRate.toStringAsFixed(2)}%',
                ),
                _KpiTile(
                  icon: Icons.people_outline,
                  label: 'Inpatients',
                  value: '${latest.activeInpatients}',
                ),
                _KpiTile(
                  icon: Icons.emergency_outlined,
                  label: 'Emergency queue',
                  value: '${latest.erWaitingCount}',
                ),
                _KpiTile(
                  icon: Icons.payments_outlined,
                  label: 'Net revenue today',
                  value: latest.dailyNetRevenue.toStringAsFixed(2),
                ),
                _KpiTile(
                  icon: Icons.swap_horiz_outlined,
                  label: 'Bed turnover',
                  value: '${latest.bedTurnoverRate.toStringAsFixed(2)}%',
                ),
                _KpiTile(
                  icon: Icons.schedule_outlined,
                  label: 'Length of stay',
                  value:
                      '${latest.averageLengthOfStayDays.toStringAsFixed(2)} d',
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text('Four-point risk summary', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            for (final ExecutiveRisk risk in state.risks) _RiskRow(risk: risk),
            const SizedBox(height: 16),
            _Narrative(state: state),
          ],
        ),
      ),
    );
  }

  static String _timestamp(DateTime at) {
    final DateTime local = at.toLocal();
    return local.toIso8601String().substring(0, 16).replaceFirst('T', ' ');
  }
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({
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
    return SizedBox(
      width: 150,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 8),
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RiskRow extends StatelessWidget {
  const _RiskRow({required this.risk});

  final ExecutiveRisk risk;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ClinicalTone tone = switch (risk.level) {
      ExecutiveRiskLevel.normal => ClinicalTone.success,
      ExecutiveRiskLevel.watch => ClinicalTone.warning,
      ExecutiveRiskLevel.critical => ClinicalTone.critical,
    };
    final IconData icon = switch (risk.level) {
      ExecutiveRiskLevel.normal => Icons.check_circle_outline,
      ExecutiveRiskLevel.watch => Icons.visibility_outlined,
      ExecutiveRiskLevel.critical => Icons.warning_amber_outlined,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 20, color: tone.foreground(theme.colorScheme)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(risk.title, style: theme.textTheme.bodyMedium),
                Text(
                  risk.detail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ClinicalStatusBadge(label: risk.level.label, tone: tone),
        ],
      ),
    );
  }
}

class _Narrative extends StatelessWidget {
  const _Narrative({required this.state});

  final ExecutiveKpiState state;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? summary = state.aiSummary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            summary == null ? 'No AI narrative attached' : 'Approved narrative',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            summary ??
                'The four points above are derived from the stored figures. '
                    'No model has been approved for an executive summary, so '
                    'none is shown.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }
}
