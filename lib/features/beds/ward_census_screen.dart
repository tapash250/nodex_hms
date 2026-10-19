/// Ward census board: beds with live occupancy (Module 11).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodex_hms/app/adaptive/adaptive_components.dart';
import 'package:nodex_hms/app/charts/clinical_bar_chart.dart';
import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/app/widgets/clinical_widgets.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/beds/bed.dart';
import 'package:nodex_hms/domain/beds/bed_repository.dart';
import 'package:nodex_hms/domain/session/session_state.dart';
import 'package:nodex_hms/features/beds/bed_controller.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// Census board across the device scope.
class WardCensusScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const WardCensusScreen({super.key});

  @override
  ConsumerState<WardCensusScreen> createState() => _WardCensusScreenState();
}

class _WardCensusScreenState extends ConsumerState<WardCensusScreen> {
  String? _wardId;
  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<WardInfo>> wards = ref.watch(censusWardsProvider);
    final SessionState session = ref.watch(sessionProvider);
    final bool canAssign = session.authorization.can(
      NodexPermissions.bedAssign,
    );
    final bool canAdminister = session.authorization.can(
      NodexPermissions.wardAdminister,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ward census'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh census',
            onPressed: () {
              ref.invalidate(censusWardsProvider);
              final String? wardId = _wardId;
              if (wardId != null) ref.invalidate(wardCensusProvider(wardId));
            },
          ),
        ],
      ),
      floatingActionButton: canAdminister && _wardId != null
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('Bed'),
              onPressed: () => _registerBed(context, ref, _wardId!),
            )
          : null,
      body: wards.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace _) => Center(
          child: Text(
            error is NodexError ? error.message : 'Wards unavailable.',
          ),
        ),
        data: (List<WardInfo> values) {
          if (values.isEmpty) {
            return const Center(child: Text('No wards in scope.'));
          }
          if (_wardId == null ||
              values.every((WardInfo ward) => ward.id != _wardId)) {
            _wardId = values.first.id;
          }
          final AsyncValue<List<BedCensusEntry>> census = ref.watch(
            wardCensusProvider(_wardId!),
          );
          return Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(16),
                child: DropdownButtonFormField<String>(
                  initialValue: _wardId,
                  decoration: const InputDecoration(labelText: 'Ward'),
                  items: values
                      .map(
                        (WardInfo ward) => DropdownMenuItem<String>(
                          value: ward.id,
                          child: Text(ward.displayName),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (String? value) {
                    if (value != null) setState(() => _wardId = value);
                  },
                ),
              ),
              // A clinical tablet has room for the occupancy graph beside the
              // bed list; a phone stacks them, with the graph first because it
              // is the summary of the list beneath it.
              Expanded(
                child: AdaptiveSplitView(
                  secondaryFirst: true,
                  secondary: const _OccupancyGraph(),
                  primary: census.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (Object error, StackTrace _) => Center(
                      child: Text(
                        error is NodexError
                            ? error.message
                            : 'Census unavailable.',
                      ),
                    ),
                    data: (List<BedCensusEntry> entries) => entries.isEmpty
                        ? const Center(child: Text('No beds registered.'))
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            itemCount: entries.length,
                            itemBuilder: (BuildContext context, int index) {
                              final BedCensusEntry entry = entries[index];
                              return _BedCard(
                                entry: entry,
                                canAssign: canAssign,
                                canAdminister: canAdminister,
                                onAssign: () =>
                                    _assign(context, ref, entry.bed),
                                onRelease: () =>
                                    _release(context, ref, entry.assignment!),
                                onToggleMaintenance: () =>
                                    _toggleMaintenance(context, ref, entry),
                              );
                            },
                          ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _registerBed(
    BuildContext context,
    WidgetRef ref,
    String wardId,
  ) async {
    final _BedDraft? draft = await showModalBottomSheet<_BedDraft>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) => const _BedSheet(),
    );
    if (draft == null) return;
    final SessionState session = ref.read(sessionProvider);
    final String? tenantId = session.tenantId;
    if (tenantId == null) return;
    try {
      await ref
          .read(registerBedUseCaseProvider)
          .call(
            policy: session.authorization,
            tenantId: tenantId,
            wardId: wardId,
            bedCode: draft.bedCode,
            bedType: draft.bedType,
          );
      ref.invalidate(wardCensusProvider(wardId));
    } on NodexError catch (error) {
      if (context.mounted) _snack(context, error.message);
    }
  }

  Future<void> _assign(BuildContext context, WidgetRef ref, Bed bed) async {
    final String? patientId = await _askPatient(context);
    if (patientId == null) return;
    final SessionState session = ref.read(sessionProvider);
    final String? userId = session.user?.userId;
    if (userId == null) return;
    try {
      await ref
          .read(assignBedUseCaseProvider)
          .call(
            policy: session.authorization,
            bed: bed,
            patientId: patientId,
            assignedBy: userId,
          );
      ref.invalidate(wardCensusProvider(bed.wardId));
    } on NodexError catch (error) {
      if (context.mounted) _snack(context, error.message);
    }
  }

  Future<void> _release(
    BuildContext context,
    WidgetRef ref,
    BedAssignment assignment,
  ) async {
    final String? reason = await _askReason(context, title: 'Release reason');
    if (reason == null) return;
    final SessionState session = ref.read(sessionProvider);
    try {
      await ref
          .read(releaseBedUseCaseProvider)
          .call(
            policy: session.authorization,
            assignment: assignment,
            reason: reason,
          );
      final Bed? bed = await ref
          .read(bedRepositoryProvider)
          .getBed(assignment.bedId);
      if (bed != null) ref.invalidate(wardCensusProvider(bed.wardId));
    } on NodexError catch (error) {
      if (context.mounted) _snack(context, error.message);
    }
  }

  Future<void> _toggleMaintenance(
    BuildContext context,
    WidgetRef ref,
    BedCensusEntry entry,
  ) async {
    final SessionState session = ref.read(sessionProvider);
    try {
      await ref
          .read(setBedStatusUseCaseProvider)
          .call(
            policy: session.authorization,
            bed: entry.bed,
            status: entry.bed.status == BedStatus.available
                ? BedStatus.maintenance
                : BedStatus.available,
          );
      ref.invalidate(wardCensusProvider(entry.bed.wardId));
    } on NodexError catch (error) {
      if (context.mounted) _snack(context, error.message);
    }
  }

  Future<String?> _askPatient(BuildContext context) {
    final TextEditingController controller = TextEditingController();
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) {
        final double keyboard = MediaQuery.viewInsetsOf(context).bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + keyboard),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text(
                'Assign patient',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                decoration: const InputDecoration(labelText: 'Patient ID *'),
                autofocus: true,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () {
                  if (controller.text.trim().isEmpty) return;
                  Navigator.pop(context, controller.text.trim());
                },
                child: const Text('Assign bed'),
              ),
            ],
          ),
        );
      },
    ).whenComplete(controller.dispose);
  }

  Future<String?> _askReason(BuildContext context, {required String title}) {
    final TextEditingController controller = TextEditingController();
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) {
        final double keyboard = MediaQuery.viewInsetsOf(context).bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + keyboard),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                decoration: const InputDecoration(labelText: 'Reason *'),
                autofocus: true,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () {
                  if (controller.text.trim().isEmpty) return;
                  Navigator.pop(context, controller.text.trim());
                },
                child: const Text('Confirm'),
              ),
            ],
          ),
        );
      },
    ).whenComplete(controller.dispose);
  }

  static void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

/// How full each ward is, as a bar per ward.
///
/// The graph counts live assignments, so it cannot drift from the census list
/// below it, and a ward that is over its staffed capacity is marked rather
/// than left for the reader to compare.
class _OccupancyGraph extends ConsumerWidget {
  const _OccupancyGraph();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<WardOccupancy>> occupancies = ref.watch(
      wardOccupancyProvider,
    );
    final ThemeData theme = Theme.of(context);
    return occupancies.when(
      loading: () => const SizedBox.shrink(),
      error: (Object error, StackTrace _) => const SizedBox.shrink(),
      data: (List<WardOccupancy> values) {
        if (values.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('Occupancy', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  ClinicalBarChart(
                    bars: <ChartBar>[
                      for (final WardOccupancy occupancy in values)
                        ChartBar(
                          label: occupancy.name,
                          value: occupancy.occupied.toDouble(),
                          caption: '${occupancy.occupied}/${occupancy.total}',
                          tone: occupancy.ratio >= 0.9
                              ? ClinicalTone.critical
                              : ClinicalTone.info,
                        ),
                    ],
                    height: 168,
                    showValues: true,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BedCard extends ConsumerWidget {
  const _BedCard({
    required this.entry,
    required this.canAssign,
    required this.canAdminister,
    required this.onAssign,
    required this.onRelease,
    required this.onToggleMaintenance,
  });

  final BedCensusEntry entry;
  final bool canAssign;
  final bool canAdminister;
  final VoidCallback onAssign;
  final VoidCallback onRelease;
  final VoidCallback onToggleMaintenance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final Bed bed = entry.bed;
    final BedAssignment? stay = entry.assignment;
    final AsyncValue<String> occupantName = stay == null
        ? const AsyncValue.data('')
        : ref.watch(bedOccupantNameProvider(stay.patientId));

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          bed.status == BedStatus.maintenance
              ? Icons.build_outlined
              : stay != null
              ? Icons.single_bed
              : Icons.single_bed_outlined,
        ),
        title: Text('${bed.bedCode} · ${bed.bedType.label}'),
        subtitle: Text(
          bed.status == BedStatus.maintenance
              ? 'Maintenance'
              : stay == null
              ? 'Vacant'
              : 'Occupied · ${occupantName.maybeWhen(data: (String name) => name, orElse: () => '…')}',
          style: theme.textTheme.bodySmall,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (stay == null && bed.status == BedStatus.available && canAssign)
              IconButton(
                icon: const Icon(Icons.person_add_outlined),
                tooltip: 'Assign patient',
                onPressed: onAssign,
              ),
            if (stay != null && canAssign)
              IconButton(
                icon: const Icon(Icons.logout_outlined),
                tooltip: 'Release bed',
                onPressed: onRelease,
              ),
            if (canAdminister)
              IconButton(
                icon: Icon(
                  bed.status == BedStatus.available
                      ? Icons.build_outlined
                      : Icons.check_circle_outline,
                ),
                tooltip: bed.status == BedStatus.available
                    ? 'Take to maintenance'
                    : 'Return to service',
                onPressed: onToggleMaintenance,
              ),
          ],
        ),
      ),
    );
  }
}

class _BedDraft {
  const _BedDraft({required this.bedCode, required this.bedType});
  final String bedCode;
  final BedType bedType;
}

class _BedSheet extends StatefulWidget {
  const _BedSheet();
  @override
  State<_BedSheet> createState() => _BedSheetState();
}

class _BedSheetState extends State<_BedSheet> {
  final TextEditingController _code = TextEditingController();
  BedType _type = BedType.general;
  @override
  void dispose() {
    _code.dispose();
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
            'Register bed',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _code,
            decoration: const InputDecoration(labelText: 'Bed code *'),
            autofocus: true,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<BedType>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Bed type'),
            items: BedType.values
                .map(
                  (BedType t) =>
                      DropdownMenuItem<BedType>(value: t, child: Text(t.label)),
                )
                .toList(growable: false),
            onChanged: (BedType? value) {
              if (value != null) setState(() => _type = value);
            },
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              if (_code.text.trim().isEmpty) return;
              Navigator.pop(
                context,
                _BedDraft(bedCode: _code.text.trim(), bedType: _type),
              );
            },
            child: const Text('Register'),
          ),
        ],
      ),
    );
  }
}
