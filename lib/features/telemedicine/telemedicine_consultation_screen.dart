/// Telemedicine consultation detail and workflow actions (Module 22).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/session/session_state.dart';
import 'package:nodex_hms/domain/telemedicine/telemedicine.dart';
import 'package:nodex_hms/features/session/session_controller.dart';
import 'package:nodex_hms/features/telemedicine/telemedicine_controller.dart';

/// Detail screen for one virtual consultation.
class TeleConsultationScreen extends ConsumerWidget {
  /// Creates the screen.
  const TeleConsultationScreen({required this.consultationId, super.key});

  /// Local consultation id.
  final String consultationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<TeleConsultationDetail> detail = ref.watch(
      teleConsultationDetailProvider(consultationId),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Virtual consultation')),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace _) => _TeleError(
          error: error,
          onRetry: () =>
              ref.invalidate(teleConsultationDetailProvider(consultationId)),
        ),
        data: (TeleConsultationDetail value) => _ConsultationBody(value: value),
      ),
    );
  }
}

class _ConsultationBody extends ConsumerWidget {
  const _ConsultationBody({required this.value});

  final TeleConsultationDetail value;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final SessionState session = ref.watch(sessionProvider);
    final TeleConsultation visit = value.consultation;
    final bool canRun = session.authorization.can(
      NodexPermissions.teleConsultationWrite,
    );
    final bool canVitals = session.authorization.can(
      NodexPermissions.teleVitalsRecord,
    );
    final bool canArchive = session.authorization.can(
      NodexPermissions.teleArchiveWrite,
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(visit.visitCode, style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                _Fact(label: 'Channel', value: visit.channel.label),
                _Fact(label: 'Status', value: visit.status.label),
                _Fact(
                  label: 'Scheduled',
                  value: _formatWhen(visit.scheduledAt),
                ),
                if (visit.reason != null)
                  _Fact(label: 'Reason', value: visit.reason!),
                if (visit.startedAt != null)
                  _Fact(label: 'Started', value: _formatWhen(visit.startedAt!)),
                if (visit.completedAt != null)
                  _Fact(
                    label: 'Completed',
                    value: _formatWhen(visit.completedAt!),
                  ),
                if (visit.cancellationReason != null)
                  _Fact(label: 'Cancelled', value: visit.cancellationReason!),
              ],
            ),
          ),
        ),
        if (canRun && !visit.isTerminal) ...<Widget>[
          const SizedBox(height: 8),
          if (visit.isScheduled)
            OutlinedButton.icon(
              icon: const Icon(Icons.meeting_room_outlined),
              label: const Text('Admit to waiting room'),
              onPressed: () => _transition(context, ref, _admit),
            ),
          if (visit.isWaiting)
            OutlinedButton.icon(
              icon: const Icon(Icons.videocam),
              label: const Text('Start call'),
              onPressed: () => _transition(context, ref, _start),
            ),
          if (visit.isInCall)
            OutlinedButton.icon(
              icon: const Icon(Icons.call_end),
              label: const Text('End call'),
              onPressed: () => _transition(context, ref, _complete),
            ),
          if (visit.isPreCall)
            OutlinedButton.icon(
              icon: const Icon(Icons.person_off_outlined),
              label: const Text('Record no-show'),
              onPressed: () => _transition(context, ref, _noShow),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.cancel_outlined),
            label: const Text('Cancel visit'),
            onPressed: () => _cancel(context, ref),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            Expanded(
              child: Text('Live vitals', style: theme.textTheme.titleMedium),
            ),
            if (canVitals && visit.isInCall)
              TextButton.icon(
                icon: const Icon(Icons.monitor_heart_outlined),
                label: const Text('Record'),
                onPressed: () => _showVitalsSheet(context, ref),
              ),
          ],
        ),
        if (value.overlays.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No vitals observed during this call.'),
            ),
          )
        else
          ...value.overlays.map(
            (TeleVitalsOverlay overlay) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.favorite_outline),
                title: Text(_readingSummary(overlay)),
                subtitle: Text(
                  overlay.notes == null
                      ? _formatWhen(overlay.observedAt)
                      : '${overlay.notes} · ${_formatWhen(overlay.observedAt)}',
                ),
              ),
            ),
          ),
        const SizedBox(height: 16),
        Text('Archive', style: theme.textTheme.titleMedium),
        if (value.archive != null)
          Card(
            child: ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: Text('Archived · ${value.archive!.durationSeconds}s'),
              subtitle: Text(
                value.archive!.recordingReference == null
                    ? 'No recording retained · consent recorded'
                    : 'Recording ${value.archive!.recordingReference} · '
                          'consent recorded',
              ),
            ),
          )
        else if (canArchive && visit.status == TeleConsultationStatus.completed)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.archive_outlined),
              label: const Text('Archive consultation'),
              onPressed: () => _showArchiveSheet(context, ref),
            ),
          )
        else
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No archive for this consultation.'),
            ),
          ),
      ],
    );
  }

  Future<void> _admit(
    WidgetRef ref,
    AuthorizationPolicy policy,
    TeleConsultation visit,
  ) => ref
      .read(admitToWaitingRoomUseCaseProvider)
      .call(policy: policy, original: visit);

  Future<TeleConsultation> _start(
    WidgetRef ref,
    AuthorizationPolicy policy,
    TeleConsultation visit,
  ) => ref
      .read(startTeleConsultationUseCaseProvider)
      .call(policy: policy, original: visit);

  Future<TeleConsultation> _complete(
    WidgetRef ref,
    AuthorizationPolicy policy,
    TeleConsultation visit,
  ) => ref
      .read(completeTeleConsultationUseCaseProvider)
      .call(policy: policy, original: visit);

  Future<TeleConsultation> _noShow(
    WidgetRef ref,
    AuthorizationPolicy policy,
    TeleConsultation visit,
  ) => ref
      .read(markTeleNoShowUseCaseProvider)
      .call(policy: policy, original: visit);

  Future<void> _transition(
    BuildContext context,
    WidgetRef ref,
    Future<Object?> Function(WidgetRef, AuthorizationPolicy, TeleConsultation)
    action,
  ) async {
    final SessionState session = ref.read(sessionProvider);
    try {
      await action(ref, session.authorization, value.consultation);
      _invalidate(ref);
    } on NodexError catch (error) {
      if (context.mounted) _snack(context, error.message);
    }
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final String? reason = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) => const _ReasonSheet(),
    );
    if (reason == null) return;
    final SessionState session = ref.read(sessionProvider);
    try {
      await ref
          .read(cancelTeleConsultationUseCaseProvider)
          .call(
            policy: session.authorization,
            original: value.consultation,
            reason: reason,
          );
      _invalidate(ref);
    } on NodexError catch (error) {
      if (context.mounted) _snack(context, error.message);
    }
  }

  Future<void> _showVitalsSheet(BuildContext context, WidgetRef ref) async {
    final _VitalsDraft? draft = await showModalBottomSheet<_VitalsDraft>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) => const _VitalsSheet(),
    );
    if (draft == null) return;
    final SessionState session = ref.read(sessionProvider);
    final String? userId = session.user?.userId;
    if (userId == null) return;
    try {
      await ref
          .read(recordTeleVitalsOverlayUseCaseProvider)
          .call(
            policy: session.authorization,
            consultation: value.consultation,
            observedBy: userId,
            heartRateBpm: draft.heartRateBpm,
            spo2Pct: draft.spo2Pct,
            temperatureC: draft.temperatureC,
            respiratoryRate: draft.respiratoryRate,
            notes: draft.notes,
          );
      _invalidate(ref);
    } on NodexError catch (error) {
      if (context.mounted) _snack(context, error.message);
    }
  }

  Future<void> _showArchiveSheet(BuildContext context, WidgetRef ref) async {
    final _ArchiveDraft? draft = await showModalBottomSheet<_ArchiveDraft>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) => const _ArchiveSheet(),
    );
    if (draft == null) return;
    final SessionState session = ref.read(sessionProvider);
    final String? userId = session.user?.userId;
    if (userId == null) return;
    try {
      await ref
          .read(archiveTeleConsultationUseCaseProvider)
          .call(
            policy: session.authorization,
            consultation: value.consultation,
            archivedBy: userId,
            durationSeconds: draft.durationSeconds,
            consentRecorded: draft.consentRecorded,
            recordingReference: draft.recordingReference,
          );
      _invalidate(ref);
    } on NodexError catch (error) {
      if (context.mounted) _snack(context, error.message);
    }
  }

  void _invalidate(WidgetRef ref) {
    ref.invalidate(teleConsultationDetailProvider(value.consultation.id));
    ref.invalidate(
      teleConsultationsForPatientProvider(value.consultation.patientId),
    );
  }

  static String _readingSummary(TeleVitalsOverlay overlay) {
    final List<String> parts = <String>[];
    if (overlay.heartRateBpm != null) {
      parts.add('HR ${overlay.heartRateBpm}');
    }
    if (overlay.spo2Pct != null) {
      parts.add('SpO2 ${overlay.spo2Pct!.toStringAsFixed(0)}%');
    }
    if (overlay.temperatureC != null) {
      parts.add('${overlay.temperatureC!.toStringAsFixed(1)}°C');
    }
    if (overlay.respiratoryRate != null) {
      parts.add('RR ${overlay.respiratoryRate}');
    }
    return parts.isEmpty ? 'No readings' : parts.join(' · ');
  }

  static void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  static String _formatWhen(DateTime when) {
    final DateTime local = when.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(child: Text(label)),
        Flexible(child: Text(value, textAlign: TextAlign.end)),
      ],
    ),
  );
}

class _ReasonSheet extends StatefulWidget {
  const _ReasonSheet();
  @override
  State<_ReasonSheet> createState() => _ReasonSheetState();
}

class _ReasonSheetState extends State<_ReasonSheet> {
  final TextEditingController _reason = TextEditingController();
  @override
  void dispose() {
    _reason.dispose();
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
            'Cancel virtual consultation',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _reason,
            decoration: const InputDecoration(
              labelText: 'Cancellation reason *',
            ),
            autofocus: true,
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              if (_reason.text.trim().isEmpty) return;
              Navigator.pop(context, _reason.text.trim());
            },
            child: const Text('Cancel visit'),
          ),
        ],
      ),
    );
  }
}

class _VitalsDraft {
  const _VitalsDraft({
    this.heartRateBpm,
    this.spo2Pct,
    this.temperatureC,
    this.respiratoryRate,
    this.notes,
  });
  final int? heartRateBpm;
  final double? spo2Pct;
  final double? temperatureC;
  final int? respiratoryRate;
  final String? notes;
}

class _VitalsSheet extends StatefulWidget {
  const _VitalsSheet();
  @override
  State<_VitalsSheet> createState() => _VitalsSheetState();
}

class _VitalsSheetState extends State<_VitalsSheet> {
  final TextEditingController _heartRate = TextEditingController();
  final TextEditingController _spo2 = TextEditingController();
  final TextEditingController _temperature = TextEditingController();
  final TextEditingController _respiratory = TextEditingController();
  final TextEditingController _notes = TextEditingController();

  @override
  void dispose() {
    _heartRate.dispose();
    _spo2.dispose();
    _temperature.dispose();
    _respiratory.dispose();
    _notes.dispose();
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
            'Record live vitals',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _heartRate,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'HR bpm'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _spo2,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'SpO2 %'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _temperature,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Temp °C'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _respiratory,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'RR /min'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            decoration: const InputDecoration(labelText: 'Notes (optional)'),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              final _VitalsDraft? draft = _buildDraft();
              if (draft == null) return;
              Navigator.pop(context, draft);
            },
            child: const Text('Save reading'),
          ),
        ],
      ),
    );
  }

  _VitalsDraft? _buildDraft() {
    final int? heartRate = int.tryParse(_heartRate.text.trim());
    final double? spo2 = double.tryParse(_spo2.text.trim());
    final double? temperature = double.tryParse(_temperature.text.trim());
    final int? respiratory = int.tryParse(_respiratory.text.trim());
    if (heartRate == null &&
        spo2 == null &&
        temperature == null &&
        respiratory == null) {
      return null;
    }
    return _VitalsDraft(
      heartRateBpm: heartRate,
      spo2Pct: spo2,
      temperatureC: temperature,
      respiratoryRate: respiratory,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    );
  }
}

class _ArchiveDraft {
  const _ArchiveDraft({
    required this.durationSeconds,
    required this.consentRecorded,
    this.recordingReference,
  });
  final int durationSeconds;
  final bool consentRecorded;
  final String? recordingReference;
}

class _ArchiveSheet extends StatefulWidget {
  const _ArchiveSheet();
  @override
  State<_ArchiveSheet> createState() => _ArchiveSheetState();
}

class _ArchiveSheetState extends State<_ArchiveSheet> {
  final TextEditingController _duration = TextEditingController();
  final TextEditingController _recording = TextEditingController();
  bool _consent = false;

  @override
  void dispose() {
    _duration.dispose();
    _recording.dispose();
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
            'Archive consultation',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _duration,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Call duration in seconds *',
            ),
            autofocus: true,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _recording,
            decoration: const InputDecoration(
              labelText: 'Recording reference (optional)',
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Patient consent recorded'),
            value: _consent,
            onChanged: (bool value) => setState(() => _consent = value),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () {
              final int? duration = int.tryParse(_duration.text.trim());
              if (duration == null || duration <= 0) return;
              Navigator.pop(
                context,
                _ArchiveDraft(
                  durationSeconds: duration,
                  consentRecorded: _consent,
                  recordingReference: _recording.text.trim().isEmpty
                      ? null
                      : _recording.text.trim(),
                ),
              );
            },
            child: const Text('Archive'),
          ),
        ],
      ),
    );
  }
}

class _TeleError extends StatelessWidget {
  const _TeleError({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Text(
          error is NodexError
              ? (error as NodexError).message
              : 'Consultation unavailable',
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    ),
  );
}
