/// ICU bed census (Module 06).
///
/// Lists every ICU bed for the active tenant with status, occupancy, and
/// ventilator linkage. Selection opens the bed detail screen; this screen only
/// renders state and routes — assignment and vitals stay in the use cases.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/icu/icu.dart';
import 'package:nodex_hms/features/icu/icu_controller.dart';

/// ICU bed census list.
class IcuListScreen extends ConsumerWidget {
  /// Creates the ICU list screen.
  const IcuListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<IcuBed>> beds = ref.watch(icuBedsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('ICU'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(icuBedsProvider),
          ),
        ],
      ),
      body: beds.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace _) => _IcuListError(
          error: error,
          onRetry: () => ref.invalidate(icuBedsProvider),
        ),
        data: (List<IcuBed> value) => value.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No ICU beds on this device yet.'),
                ),
              )
            : ListView.separated(
                itemCount: value.length,
                separatorBuilder: (BuildContext context, int _) =>
                    const Divider(height: 1),
                itemBuilder: (BuildContext context, int index) {
                  final IcuBed bed = value[index];
                  return ListTile(
                    leading: Icon(
                      bed.isOccupied
                          ? Icons.bed_outlined
                          : Icons.meeting_room_outlined,
                      color: bed.isOccupied
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    title: Text(bed.bedId),
                    subtitle: Text(
                      <String>[
                        'Status: ${_statusLabel(bed.status)}',
                        if (bed.currentPatientId != null)
                          'Patient: ${bed.currentPatientId}',
                        if (bed.ventilatorId != null) 'Ventilator linked',
                      ].join('\n'),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/icu/beds/${bed.id}'),
                  );
                },
              ),
      ),
    );
  }

  static String _statusLabel(IcuBedStatus status) => switch (status) {
    IcuBedStatus.available => 'Available',
    IcuBedStatus.occupied => 'Occupied',
    IcuBedStatus.maintenance => 'Maintenance',
    IcuBedStatus.isolation => 'Isolation',
  };
}

class _IcuListError extends StatelessWidget {
  const _IcuListError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String message = error is NodexError
        ? (error as NodexError).message
        : 'ICU beds could not be loaded.';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.error_outline, size: 56, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(
              message,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}
