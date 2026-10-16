/// Institutional calendar and shift overlay (Module 40).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/domain/calendar/calendar.dart';
import 'package:nodex_hms/domain/session/session_state.dart';
import 'package:nodex_hms/domain/workforce/workforce.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// Days of calendar shown from today.
const int _windowDays = 30;

/// The institutional calendar surface, overlaying roster shifts.
class InstitutionalCalendarScreen extends ConsumerStatefulWidget {
  /// Creates the calendar screen.
  const InstitutionalCalendarScreen({super.key});

  @override
  ConsumerState<InstitutionalCalendarScreen> createState() =>
      _InstitutionalCalendarScreenState();
}

class _InstitutionalCalendarScreenState
    extends ConsumerState<InstitutionalCalendarScreen> {
  List<CalendarDayOverlay> _days = const <CalendarDayOverlay>[];
  bool _loading = true;
  String? _error;

  static DateTime get _from {
    final DateTime now = DateTime.now().toUtc();
    return DateTime.utc(now.year, now.month, now.day);
  }

  static DateTime get _to => _from.add(const Duration(days: _windowDays));

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = ref.read(sessionProvider);
    final String? tenantId = session.tenantId;
    if (tenantId == null) {
      setState(() {
        _error = 'Session is not ready.';
        _loading = false;
      });
      return;
    }
    try {
      final List<ShiftSlice> shifts = await _loadShifts(session, tenantId);
      final List<CalendarDayOverlay> days = await ref
          .read(readCalendarUseCaseProvider)
          .overlay(
            policy: session.authorization,
            tenantId: tenantId,
            from: _from,
            to: _to,
            shifts: shifts,
          );
      if (!mounted) return;
      setState(() {
        _days = days;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  /// The overlay only includes the roster when the session may read it. A user
  /// who can see the calendar but not the roster still gets the events.
  Future<List<ShiftSlice>> _loadShifts(
    SessionState session,
    String tenantId,
  ) async {
    if (!session.authorization.can(NodexPermissions.workforceRead)) {
      return const <ShiftSlice>[];
    }
    final List<StaffShift> roster = await ref
        .read(readWorkforceUseCaseProvider)
        .shifts(policy: session.authorization, tenantId: tenantId, limit: 500);
    return roster
        .where(
          (StaffShift shift) =>
              shift.startsAt.isBefore(_to) && _from.isBefore(shift.endsAt),
        )
        .map(
          (StaffShift shift) => ShiftSlice(
            id: shift.id,
            label: shift.displayName,
            startsAt: shift.startsAt,
            endsAt: shift.endsAt,
            detail: shift.shiftCode,
          ),
        )
        .toList(growable: false);
  }

  Future<void> _createEvent() async {
    final session = ref.read(sessionProvider);
    final String? tenantId = session.tenantId;
    final String? userId = session.user?.userId;
    if (tenantId == null || userId == null) return;
    final _EventFormResult? result = await showDialog<_EventFormResult>(
      context: context,
      builder: (BuildContext context) => const _EventFormDialog(),
    );
    if (result == null) return;
    try {
      await ref
          .read(createCalendarEventUseCaseProvider)
          .call(
            policy: session.authorization,
            tenantId: tenantId,
            createdBy: userId,
            title: result.title,
            eventType: result.eventType,
            startsAt: result.startsAt,
            endsAt: result.endsAt,
            allDay: true,
          );
      await _load();
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _cancelEvent(CalendarEvent event) async {
    final session = ref.read(sessionProvider);
    try {
      await ref
          .read(cancelCalendarEventUseCaseProvider)
          .call(policy: session.authorization, event: event);
      await _load();
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  void _showEvent(CalendarEvent event) {
    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.event),
              title: Text(event.title),
              subtitle: Text(
                <String>[
                  event.eventType.label,
                  if (event.location case final String location) location,
                ].join(' · '),
              ),
            ),
            if (event.description case final String description)
              ListTile(
                leading: const Icon(Icons.notes),
                title: Text(description),
              ),
            if (event.isEditable)
              ListTile(
                leading: const Icon(Icons.cancel_outlined),
                title: const Text('Cancel event'),
                onTap: () {
                  Navigator.of(context).pop();
                  _cancelEvent(event);
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Calendar')),
        body: Center(child: Text(_error!)),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Calendar')),
      floatingActionButton: FloatingActionButton(
        onPressed: _createEvent,
        tooltip: 'Add event',
        child: const Icon(Icons.add),
      ),
      body: _days.isEmpty
          ? const Center(child: Text('Nothing scheduled in the next 30 days.'))
          : ListView.builder(
              itemCount: _days.length,
              itemBuilder: (BuildContext context, int index) =>
                  _day(context, _days[index]),
            ),
    );
  }

  Widget _day(BuildContext context, CalendarDayOverlay day) {
    final String label =
        '${day.date.year}-'
        '${day.date.month.toString().padLeft(2, '0')}-'
        '${day.date.day.toString().padLeft(2, '0')}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(label, style: Theme.of(context).textTheme.titleSmall),
        ),
        for (final CalendarEvent event in day.events)
          ListTile(
            leading: Icon(
              event.typeIcon,
              color: event.isScheduled ? null : Theme.of(context).disabledColor,
            ),
            title: Text(event.title),
            subtitle: Text(event.eventType.label),
            onTap: () => _showEvent(event),
          ),
        for (final ShiftSlice shift in day.shifts)
          ListTile(
            dense: true,
            leading: const Icon(Icons.groups_outlined),
            title: Text(shift.label),
            subtitle: Text(
              <String>[
                if (shift.detail case final String detail) detail,
                'Roster',
              ].join(' · '),
            ),
          ),
        const Divider(height: 1),
      ],
    );
  }
}

extension on CalendarEvent {
  /// An icon that reflects the event type.
  IconData get typeIcon => switch (eventType) {
    CalendarEventType.holiday => Icons.beach_access_outlined,
    CalendarEventType.training => Icons.school_outlined,
    CalendarEventType.audit => Icons.fact_check_outlined,
    CalendarEventType.maintenance => Icons.build_outlined,
    CalendarEventType.academic => Icons.menu_book_outlined,
    CalendarEventType.meeting => Icons.groups_2_outlined,
    CalendarEventType.other => Icons.event_note_outlined,
  };
}

/// The editable fields of an event form.
class _EventFormResult {
  const _EventFormResult({
    required this.title,
    required this.eventType,
    required this.startsAt,
    required this.endsAt,
  });

  final String title;
  final CalendarEventType eventType;
  final DateTime startsAt;
  final DateTime endsAt;
}

class _EventFormDialog extends StatefulWidget {
  const _EventFormDialog();

  @override
  State<_EventFormDialog> createState() => _EventFormDialogState();
}

class _EventFormDialogState extends State<_EventFormDialog> {
  final TextEditingController _title = TextEditingController();
  CalendarEventType _eventType = CalendarEventType.training;
  late DateTime _start = DateTime.now().toUtc();
  late DateTime _end = _start;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _pick({required bool isStart}) async {
    final DateTime initial = isStart ? _start : _end;
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.utc(2020),
      lastDate: DateTime.utc(2100),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _start = DateTime.utc(picked.year, picked.month, picked.day);
        if (_end.isBefore(_start)) _end = _start;
      } else {
        _end = DateTime.utc(picked.year, picked.month, picked.day);
        if (_end.isBefore(_start)) _start = _end;
      }
    });
  }

  String _format(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add event'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          DropdownButtonFormField<CalendarEventType>(
            initialValue: _eventType,
            decoration: const InputDecoration(labelText: 'Type'),
            items: <DropdownMenuItem<CalendarEventType>>[
              for (final CalendarEventType type in CalendarEventType.values)
                DropdownMenuItem<CalendarEventType>(
                  value: type,
                  child: Text(type.label),
                ),
            ],
            onChanged: (CalendarEventType? value) {
              if (value != null) setState(() => _eventType = value);
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Starts'),
            subtitle: Text(_format(_start)),
            onTap: () => _pick(isStart: true),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Ends'),
            subtitle: Text(_format(_end)),
            onTap: () => _pick(isStart: false),
          ),
        ],
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(
          _EventFormResult(
            title: _title.text.trim(),
            eventType: _eventType,
            startsAt: _start,
            endsAt: _end.add(
              const Duration(hours: 23, minutes: 59, seconds: 59),
            ),
          ),
        ),
        child: const Text('Save'),
      ),
    ],
  );
}
