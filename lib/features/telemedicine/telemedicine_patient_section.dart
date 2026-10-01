/// Telemedicine section embedded in the patient detail screen (Module 22).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/session/session_state.dart';
import 'package:nodex_hms/domain/telemedicine/telemedicine.dart';
import 'package:nodex_hms/features/session/session_controller.dart';
import 'package:nodex_hms/features/telemedicine/telemedicine_controller.dart';

/// Shows virtual consultations and the scheduling entry point for a patient.
class TelemedicinePatientSection extends ConsumerWidget {
  /// Creates the section.
  const TelemedicinePatientSection({required this.patientId, super.key});

  /// Patient identifier.
  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<TeleConsultation>> consultations = ref.watch(
      teleConsultationsForPatientProvider(patientId),
    );
    final SessionState session = ref.watch(sessionProvider);
    final bool canSchedule = session.authorization.can(
      NodexPermissions.teleConsultationWrite,
    );
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text('Telemedicine', style: theme.textTheme.titleMedium),
            ),
            if (canSchedule)
              TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Schedule'),
                onPressed: () => _showScheduleSheet(context, ref),
              ),
          ],
        ),
        consultations.when(
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
                    : 'Consultation history unavailable.',
              ),
            ),
          ),
          data: (List<TeleConsultation> values) => values.isEmpty
              ? const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No virtual consultations scheduled.'),
                  ),
                )
              : Column(
                  children: values
                      .map(
                        (TeleConsultation value) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: Icon(
                              value.channel == TeleChannel.video
                                  ? Icons.videocam_outlined
                                  : Icons.call_outlined,
                            ),
                            title: Text(value.visitCode),
                            subtitle: Text(
                              '${value.channel.label} · '
                              '${value.status.label}'
                              '${value.reason == null ? '' : ' · ${value.reason}'}',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.go(
                              '/patients/$patientId/telemedicine/${value.id}',
                            ),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
        ),
      ],
    );
  }

  Future<void> _showScheduleSheet(BuildContext context, WidgetRef ref) async {
    final _VisitDraft? draft = await showModalBottomSheet<_VisitDraft>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) => const _ScheduleSheet(),
    );
    if (draft == null) return;
    final SessionState session = ref.read(sessionProvider);
    final String? userId = session.user?.userId;
    final String? tenantId = session.tenantId;
    if (userId == null || tenantId == null) return;
    try {
      final TeleConsultation consultation = await ref
          .read(scheduleTeleConsultationUseCaseProvider)
          .call(
            policy: session.authorization,
            tenantId: tenantId,
            patientId: patientId,
            clinicianId: userId,
            bookedBy: userId,
            visitCode: draft.visitCode,
            channel: draft.channel,
            scheduledAt: draft.scheduledAt,
            reason: draft.reason,
          );
      ref.invalidate(teleConsultationsForPatientProvider(patientId));
      if (context.mounted) {
        context.go('/patients/$patientId/telemedicine/${consultation.id}');
      }
    } on NodexError catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }
}

class _VisitDraft {
  const _VisitDraft({
    required this.visitCode,
    required this.channel,
    required this.scheduledAt,
    this.reason,
  });
  final String visitCode;
  final TeleChannel channel;
  final DateTime scheduledAt;
  final String? reason;
}

class _ScheduleSheet extends StatefulWidget {
  const _ScheduleSheet();
  @override
  State<_ScheduleSheet> createState() => _ScheduleSheetState();
}

class _ScheduleSheetState extends State<_ScheduleSheet> {
  final TextEditingController _visitCode = TextEditingController();
  final TextEditingController _reason = TextEditingController();
  TeleChannel _channel = TeleChannel.video;
  DateTime _scheduledAt = DateTime.now().add(const Duration(hours: 1));

  @override
  void dispose() {
    _visitCode.dispose();
    _reason.dispose();
    super.dispose();
  }

  String get _scheduledLabel {
    final DateTime local = _scheduledAt.toLocal();
    final String date =
        '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
    final String time =
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
    return '$date $time';
  }

  Future<void> _pickScheduled() async {
    final DateTime now = DateTime.now();
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: _scheduledAt,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1),
    );
    if (date == null || !mounted) return;
    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_scheduledAt),
    );
    if (time == null || !mounted) return;
    setState(() {
      _scheduledAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
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
            'Schedule virtual consultation',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _visitCode,
            decoration: const InputDecoration(labelText: 'Visit code *'),
            autofocus: true,
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: DropdownButtonFormField<TeleChannel>(
                  initialValue: _channel,
                  decoration: const InputDecoration(labelText: 'Channel *'),
                  items: TeleChannel.values
                      .map(
                        (TeleChannel channel) => DropdownMenuItem<TeleChannel>(
                          value: channel,
                          child: Text(channel.label),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (TeleChannel? value) {
                    if (value != null) setState(() => _channel = value);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.event),
                  label: Text(_scheduledLabel),
                  onPressed: _pickScheduled,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reason,
            decoration: const InputDecoration(
              labelText: 'Reason for visit (optional)',
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              if (_visitCode.text.trim().isEmpty) return;
              Navigator.pop(
                context,
                _VisitDraft(
                  visitCode: _visitCode.text.trim(),
                  channel: _channel,
                  scheduledAt: _scheduledAt,
                  reason: _reason.text.trim().isEmpty
                      ? null
                      : _reason.text.trim(),
                ),
              );
            },
            child: const Text('Schedule visit'),
          ),
        ],
      ),
    );
  }
}
