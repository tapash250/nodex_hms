/// Operation theatre section embedded in the patient detail screen
/// (Module 19).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/ot/ot.dart';
import 'package:nodex_hms/features/ot/ot_controller.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// Shows a patient's theatre bookings and lets authorized staff book a case.
class OtPatientSection extends ConsumerWidget {
  /// Creates the operation theatre patient section.
  const OtPatientSection({super.key, required this.patientId});

  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<List<OtBooking>> bookings = ref.watch(
      otBookingsForPatientProvider(patientId),
    );
    final session = ref.watch(sessionProvider);
    final bool canSchedule = session.authorization.can(
      NodexPermissions.otSchedule,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Operation theatre', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        bookings.when(
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
                    : 'Could not load theatre bookings.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ),
          data: (List<OtBooking> list) {
            if (list.isEmpty) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'No theatre bookings recorded.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              );
            }

            return Card(
              child: Column(
                children: <Widget>[
                  for (final OtBooking booking in list.take(5))
                    ListTile(
                      leading: const Icon(Icons.content_cut_outlined),
                      title: Text(booking.procedureName),
                      subtitle: Text(
                        '${booking.theatreRoom} · ${booking.status.label} · '
                        '${booking.priority.label}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/ot/bookings/${booking.id}'),
                    ),
                ],
              ),
            );
          },
        ),
        if (canSchedule) ...<Widget>[
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Book an operation theatre case for this patient.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              TextButton.icon(
                onPressed: () => _showBookSheet(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('Book case'),
              ),
            ],
          ),
        ],
      ],
    );
  }

  void _showBookSheet(BuildContext context, WidgetRef ref) {
    final TextEditingController roomController = TextEditingController(
      text: 'OT 1',
    );
    final TextEditingController procedureController = TextEditingController();
    OtPriority priority = OtPriority.routine;
    DateTime day = DateTime.now();
    TimeOfDay start = const TimeOfDay(hour: 9, minute: 0);
    int durationMinutes = 60;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder:
              (BuildContext context, void Function(void Function()) setState) {
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
                    children: <Widget>[
                      Text(
                        'Book theatre case',
                        style: Theme.of(sheetContext).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: roomController,
                        decoration: const InputDecoration(
                          labelText: 'Theatre room',
                        ),
                      ),
                      TextField(
                        controller: procedureController,
                        decoration: const InputDecoration(
                          labelText: 'Procedure',
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<OtPriority>(
                        initialValue: priority,
                        decoration: const InputDecoration(
                          labelText: 'Priority',
                        ),
                        items: <DropdownMenuItem<OtPriority>>[
                          for (final OtPriority value in OtPriority.values)
                            DropdownMenuItem<OtPriority>(
                              value: value,
                              child: Text(value.label),
                            ),
                        ],
                        onChanged: (OtPriority? value) {
                          if (value != null) {
                            setState(() => priority = value);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () async {
                                final DateTime? picked = await showDatePicker(
                                  context: context,
                                  initialDate: day,
                                  firstDate: DateTime.now().subtract(
                                    const Duration(days: 1),
                                  ),
                                  lastDate: DateTime.now().add(
                                    const Duration(days: 365),
                                  ),
                                );
                                if (picked != null) {
                                  setState(() => day = picked);
                                }
                              },
                              child: Text(
                                '${day.year}-'
                                '${day.month.toString().padLeft(2, '0')}-'
                                '${day.day.toString().padLeft(2, '0')}',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () async {
                                final TimeOfDay? picked = await showTimePicker(
                                  context: context,
                                  initialTime: start,
                                );
                                if (picked != null) {
                                  setState(() => start = picked);
                                }
                              },
                              child: Text(start.format(context)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              initialValue: durationMinutes,
                              decoration: const InputDecoration(
                                labelText: 'Minutes',
                              ),
                              items: const <int>[30, 60, 90, 120, 180, 240]
                                  .map(
                                    (int minutes) => DropdownMenuItem<int>(
                                      value: minutes,
                                      child: Text('$minutes'),
                                    ),
                                  )
                                  .toList(growable: false),
                              onChanged: (int? value) {
                                if (value != null) {
                                  setState(() => durationMinutes = value);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () async {
                            await _submit(
                              context: sheetContext,
                              ref: ref,
                              theatreRoom: roomController.text,
                              procedureName: procedureController.text,
                              priority: priority,
                              scheduledStart: DateTime(
                                day.year,
                                day.month,
                                day.day,
                                start.hour,
                                start.minute,
                              ),
                              durationMinutes: durationMinutes,
                            );
                          },
                          child: const Text('Book case'),
                        ),
                      ),
                    ],
                  ),
                );
              },
        );
      },
    );
  }

  Future<void> _submit({
    required BuildContext context,
    required WidgetRef ref,
    required String theatreRoom,
    required String procedureName,
    required OtPriority priority,
    required DateTime scheduledStart,
    required int durationMinutes,
  }) async {
    final session = ref.read(sessionProvider);
    final String? tenantId = session.tenantId;
    final String? userId = session.user?.userId;
    if (tenantId == null || userId == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Session is not ready.')));
      }
      return;
    }
    try {
      final useCase = ref.read(scheduleOtBookingUseCaseProvider);
      await useCase(
        policy: session.authorization,
        tenantId: tenantId,
        patientId: patientId,
        theatreRoom: theatreRoom,
        procedureName: procedureName,
        scheduledStart: scheduledStart.toUtc(),
        scheduledEnd: scheduledStart
            .add(Duration(minutes: durationMinutes))
            .toUtc(),
        surgeonId: userId,
        createdBy: userId,
        priority: priority,
      );
      ref.invalidate(otBookingsForPatientProvider(patientId));
      ref.invalidate(otBookingsProvider);
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Case booked.')));
      }
    } on NodexError catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('The case could not be booked.')),
        );
      }
    }
  }
}
