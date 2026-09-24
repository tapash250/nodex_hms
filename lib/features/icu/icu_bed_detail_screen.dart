/// ICU bed detail, vitals intake, handover, and ventilator actions (Module 06).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/icu/icu.dart';
import 'package:nodex_hms/features/icu/icu_controller.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// Detail screen for a single ICU bed.
class IcuBedDetailScreen extends ConsumerWidget {
  const IcuBedDetailScreen({super.key, required this.icuBedId});

  final String icuBedId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(icuBedDetailProvider(icuBedId));
    final vitals = ref.watch(ventilatorEventsForBedProvider(icuBedId));
    final session = ref.watch(sessionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('ICU Bed')),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace _) => _IcuBedError(
          error: error,
          onRetry: () => ref.invalidate(icuBedDetailProvider(icuBedId)),
        ),
        data: (IcuBed value) => _IcuBedBody(
          bed: value,
          events: vitals,
          canAssign: session.authorization.can(NodexPermissions.icuBedAssign),
          canRecordVitals: session.authorization.can(
            NodexPermissions.icuVitalsRecord,
          ),
          canRecordHandover: session.authorization.can(
            NodexPermissions.icuHandoverRecord,
          ),
          canRecordVentilator: session.authorization.can(
            NodexPermissions.ventilatorEventRecord,
          ),
          onRelease: () async {
            final useCase = ref.read(assignIcuBedUseCaseProvider);
            await useCase(
              policy: session.authorization,
              tenantId: value.tenantId,
              bedId: value.bedId,
              patientId: null,
              status: IcuBedStatus.available,
              existingBedId: value.id,
            );
            ref.invalidate(icuBedDetailProvider(icuBedId));
            ref.invalidate(icuBedsProvider);
          },
          onRecordVitals: (Map<String, Object?> data) async {
            final useCase = ref.read(recordIcuVitalsUseCaseProvider);
            await useCase(
              policy: session.authorization,
              tenantId: value.tenantId,
              patientId: value.currentPatientId!,
              icuBedId: value.id,
              recordedBy: session.user?.userId ?? '',
              heartRate: data['heart_rate'] as int?,
              spo2: data['spo2'] as int?,
              respiratoryRate: data['respiratory_rate'] as int?,
              temperatureCelsius: data['temperature_celsius'] as double?,
              systolicBp: data['systolic_bp'] as int?,
              diastolicBp: data['diastolic_bp'] as int?,
            );
            ref.invalidate(icuBedDetailProvider(icuBedId));
          },
        ),
      ),
    );
  }
}

class _IcuBedBody extends StatelessWidget {
  const _IcuBedBody({
    required this.bed,
    required this.events,
    required this.canAssign,
    required this.canRecordVitals,
    required this.canRecordHandover,
    required this.canRecordVentilator,
    required this.onRelease,
    required this.onRecordVitals,
  });

  final IcuBed bed;
  final AsyncValue<List<VentilatorEvent>> events;
  final bool canAssign;
  final bool canRecordVitals;
  final bool canRecordHandover;
  final bool canRecordVentilator;
  final Future<void> Function() onRelease;
  final Future<void> Function(Map<String, Object?> data) onRecordVitals;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canManage = canAssign && bed.isOccupied;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(bed.status.label, style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                if (bed.currentPatientId != null)
                  Text(
                    'Patient: ${bed.currentPatientId}',
                    style: theme.textTheme.bodyMedium,
                  ),
                if (bed.ventilatorId != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Ventilator: ${bed.ventilatorId}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (canRecordVitals && bed.isOccupied) ...[
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _showVitalsSheet(context, onRecordVitals),
              icon: const Icon(Icons.favorite),
              label: const Text('Record vitals'),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (canRecordHandover && bed.isOccupied) ...[
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.swap_horiz),
              label: const Text('Record handover'),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (canRecordVentilator && bed.isOccupied) ...[
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.air),
              label: const Text('Record ventilator event'),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (canManage) ...[
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onRelease,
              icon: const Icon(Icons.meeting_room),
              label: const Text('Release bed'),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Text('Ventilator events', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        events.when(
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
                    : 'Could not load ventilator events.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ),
          data: (List<VentilatorEvent> list) {
            if (list.isEmpty) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'No ventilator events.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              );
            }
            return Card(
              child: Column(
                children: [
                  for (final event in list.take(10))
                    ListTile(
                      leading: const Icon(Icons.air),
                      title: Text(event.eventType),
                      subtitle: Text(event.mode ?? '—'),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  void _showVitalsSheet(
    BuildContext context,
    Future<void> Function(Map<String, Object?> data) onSave,
  ) {
    final heartRateController = TextEditingController();
    final spo2Controller = TextEditingController();
    final respiratoryRateController = TextEditingController();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Record vitals',
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: heartRateController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Heart rate'),
              ),
              TextField(
                controller: spo2Controller,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'SpO₂ (%)'),
              ),
              TextField(
                controller: respiratoryRateController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Respiratory rate',
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    await onSave({
                      if (heartRateController.text.isNotEmpty)
                        'heart_rate': int.tryParse(heartRateController.text),
                      if (spo2Controller.text.isNotEmpty)
                        'spo2': int.tryParse(spo2Controller.text),
                      if (respiratoryRateController.text.isNotEmpty)
                        'respiratory_rate': int.tryParse(
                          respiratoryRateController.text,
                        ),
                    });
                    if (sheetContext.mounted) {
                      Navigator.of(sheetContext).pop();
                    }
                  },
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _IcuBedError extends StatelessWidget {
  const _IcuBedError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final message = switch (error) {
      final NodexError e => e.message,
      _ => 'Something went wrong while loading this ICU bed.',
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
