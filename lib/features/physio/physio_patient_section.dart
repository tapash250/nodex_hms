/// Physiotherapy session section embedded in the patient detail screen
/// (Module 20).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/physio/physio.dart';
import 'package:nodex_hms/domain/session/session_state.dart';
import 'package:nodex_hms/features/physio/physio_controller.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// Shows physiotherapy sessions and the scheduling entry point for a patient.
class PhysioPatientSection extends ConsumerWidget {
  /// Creates the section.
  const PhysioPatientSection({required this.patientId, super.key});

  /// Patient identifier.
  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<PhysioSession>> sessions = ref.watch(
      physioSessionsForPatientProvider(patientId),
    );
    final SessionState session = ref.watch(sessionProvider);
    final bool canSchedule = session.authorization.can(
      NodexPermissions.physioSessionWrite,
    );
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text('Physiotherapy', style: theme.textTheme.titleMedium),
            ),
            if (canSchedule)
              TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Schedule'),
                onPressed: () => _showSessionSheet(context, ref),
              ),
          ],
        ),
        sessions.when(
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
                    : 'Physiotherapy history unavailable.',
              ),
            ),
          ),
          data: (List<PhysioSession> values) => values.isEmpty
              ? const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No physiotherapy sessions scheduled.'),
                  ),
                )
              : Column(
                  children: values
                      .map(
                        (PhysioSession value) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: Icon(
                              value.status == PhysioSessionStatus.inProgress
                                  ? Icons.directions_run
                                  : Icons.event_note_outlined,
                            ),
                            title: Text(value.sessionCode),
                            subtitle: Text(
                              '${value.sessionType.label} · '
                              '${value.bodyArea} · '
                              '${value.status.label}',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.go(
                              '/patients/$patientId/physio/${value.id}',
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

  Future<void> _showSessionSheet(BuildContext context, WidgetRef ref) async {
    final _SessionDraft? draft = await showModalBottomSheet<_SessionDraft>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) => const _SessionSheet(),
    );
    if (draft == null) return;
    final SessionState session = ref.read(sessionProvider);
    final String? userId = session.user?.userId;
    final String? tenantId = session.tenantId;
    if (userId == null || tenantId == null) return;
    try {
      final PhysioSession created = await ref
          .read(schedulePhysioSessionUseCaseProvider)
          .call(
            policy: session.authorization,
            tenantId: tenantId,
            patientId: patientId,
            physiotherapistId: userId,
            sessionCode: draft.sessionCode,
            sessionType: draft.sessionType,
            bodyArea: draft.bodyArea,
            scheduledAt: draft.scheduledAt,
            equipmentUsed: draft.equipment,
          );
      ref.invalidate(physioSessionsForPatientProvider(patientId));
      if (context.mounted) {
        context.go('/patients/$patientId/physio/${created.id}');
      }
    } on NodexError catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }
}

class _SessionDraft {
  const _SessionDraft({
    required this.sessionCode,
    required this.sessionType,
    required this.bodyArea,
    required this.scheduledAt,
    this.equipment,
  });
  final String sessionCode;
  final PhysioSessionType sessionType;
  final String bodyArea;
  final DateTime scheduledAt;
  final String? equipment;
}

class _SessionSheet extends StatefulWidget {
  const _SessionSheet();
  @override
  State<_SessionSheet> createState() => _SessionSheetState();
}

class _SessionSheetState extends State<_SessionSheet> {
  final TextEditingController _sessionCode = TextEditingController();
  final TextEditingController _bodyArea = TextEditingController();
  final TextEditingController _equipment = TextEditingController();
  PhysioSessionType _sessionType = PhysioSessionType.therapy;
  DateTime _scheduledAt = DateTime.now().add(const Duration(hours: 1));

  @override
  void dispose() {
    _sessionCode.dispose();
    _bodyArea.dispose();
    _equipment.dispose();
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
            'Schedule physiotherapy session',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _sessionCode,
            decoration: const InputDecoration(labelText: 'Session code *'),
            autofocus: true,
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: DropdownButtonFormField<PhysioSessionType>(
                  initialValue: _sessionType,
                  decoration: const InputDecoration(labelText: 'Type *'),
                  items: PhysioSessionType.values
                      .map(
                        (PhysioSessionType type) =>
                            DropdownMenuItem<PhysioSessionType>(
                              value: type,
                              child: Text(type.label),
                            ),
                      )
                      .toList(growable: false),
                  onChanged: (PhysioSessionType? value) {
                    if (value != null) setState(() => _sessionType = value);
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
            controller: _bodyArea,
            decoration: const InputDecoration(labelText: 'Body area *'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _equipment,
            decoration: const InputDecoration(
              labelText: 'Equipment (optional)',
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              if (_sessionCode.text.trim().isEmpty ||
                  _bodyArea.text.trim().isEmpty) {
                return;
              }
              Navigator.pop(
                context,
                _SessionDraft(
                  sessionCode: _sessionCode.text.trim(),
                  sessionType: _sessionType,
                  bodyArea: _bodyArea.text.trim(),
                  scheduledAt: _scheduledAt,
                  equipment: _equipment.text.trim().isEmpty
                      ? null
                      : _equipment.text.trim(),
                ),
              );
            },
            child: const Text('Schedule session'),
          ),
        ],
      ),
    );
  }
}
