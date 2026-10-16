/// Allied staff & workforce rosters (Module 09).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/domain/workforce/workforce.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// A shift pattern a ward can schedule without free-text time entry.
typedef _ShiftPattern = ({String name, StaffCategory category, int hours});

const Map<String, _ShiftPattern> _shiftPatterns = <String, _ShiftPattern>{
  'DAY': (name: 'Day shift', category: StaffCategory.nursing, hours: 8),
  'EVE': (name: 'Evening shift', category: StaffCategory.nursing, hours: 8),
  'NIGHT': (name: 'Night shift', category: StaffCategory.nursing, hours: 8),
  'SUPPORT': (name: 'Support cover', category: StaffCategory.orderly, hours: 8),
  'TECH': (
    name: 'Technician cover',
    category: StaffCategory.technician,
    hours: 8,
  ),
};

/// Workforce roster surface.
class WorkforceScreen extends ConsumerStatefulWidget {
  /// Creates the roster.
  const WorkforceScreen({super.key});

  @override
  ConsumerState<WorkforceScreen> createState() => _WorkforceScreenState();
}

class _WorkforceScreenState extends ConsumerState<WorkforceScreen> {
  List<StaffShift> _shifts = const <StaffShift>[];
  bool _loading = true;
  String? _error;

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
      final Set<String> facilities =
          session.snapshot?.facilityIds ?? const <String>{};
      final List<StaffShift> shifts = await ref
          .read(readWorkforceUseCaseProvider)
          .shifts(
            policy: session.authorization,
            tenantId: tenantId,
            facilityId: facilities.isEmpty ? null : facilities.first,
          );
      if (!mounted) return;
      setState(() {
        _shifts = shifts;
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

  Future<void> _schedule() async {
    final session = ref.read(sessionProvider);
    final String? tenantId = session.tenantId;
    final Set<String> facilities =
        session.snapshot?.facilityIds ?? const <String>{};
    if (tenantId == null || facilities.isEmpty) {
      return;
    }
    final ({String code, String date, int headcount})? entry =
        await showDialog<({String code, String date, int headcount})>(
          context: context,
          builder: (BuildContext context) => const _ShiftFormDialog(),
        );
    if (entry == null) {
      return;
    }
    final _ShiftPattern? pattern = _shiftPatterns[entry.code];
    if (pattern == null) {
      return;
    }
    final DateTime start = DateTime.utc(
      int.parse(entry.date.substring(0, 4)),
      int.parse(entry.date.substring(5, 7)),
      int.parse(entry.date.substring(8, 10)),
      8,
    );
    try {
      await ref
          .read(scheduleStaffShiftUseCaseProvider)
          .call(
            policy: session.authorization,
            tenantId: tenantId,
            facilityId: facilities.first,
            shiftDate: entry.date,
            shiftCode: entry.code,
            displayName: pattern.name,
            staffCategory: pattern.category,
            startsAt: start,
            endsAt: start.add(Duration(hours: pattern.hours)),
            requiredHeadcount: entry.headcount,
          );
      await _load();
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Workforce')),
        body: Center(child: Text(_error!)),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Workforce')),
      floatingActionButton: FloatingActionButton(
        onPressed: _schedule,
        tooltip: 'Schedule shift',
        child: const Icon(Icons.add),
      ),
      body: _shifts.isEmpty
          ? const Center(child: Text('No shifts scheduled yet.'))
          : ListView.builder(
              itemCount: _shifts.length,
              itemBuilder: (BuildContext context, int index) {
                final StaffShift shift = _shifts[index];
                return ListTile(
                  leading: const Icon(Icons.schedule_outlined),
                  title: Text('${shift.displayName} · ${shift.shiftDate}'),
                  subtitle: Text(
                    '${shift.shiftCode} · ${shift.staffCategory.label} · '
                    'needs ${shift.requiredHeadcount}',
                  ),
                  trailing: Text(shift.status.name),
                );
              },
            ),
    );
  }
}

class _ShiftFormDialog extends StatefulWidget {
  const _ShiftFormDialog();

  @override
  State<_ShiftFormDialog> createState() => _ShiftFormDialogState();
}

class _ShiftFormDialogState extends State<_ShiftFormDialog> {
  String _code = _shiftPatterns.keys.first;
  final TextEditingController _date = TextEditingController(
    text: DateTime.now().toUtc().toIso8601String().substring(0, 10),
  );
  final TextEditingController _headcount = TextEditingController(text: '1');

  @override
  void dispose() {
    _date.dispose();
    _headcount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Schedule shift'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        DropdownButtonFormField<String>(
          initialValue: _code,
          decoration: const InputDecoration(labelText: 'Shift'),
          items: <DropdownMenuItem<String>>[
            for (final MapEntry<String, _ShiftPattern> entry
                in _shiftPatterns.entries)
              DropdownMenuItem<String>(
                value: entry.key,
                child: Text('${entry.value.name} (${entry.key})'),
              ),
          ],
          onChanged: (String? value) {
            if (value != null) {
              setState(() => _code = value);
            }
          },
        ),
        TextField(
          controller: _date,
          decoration: const InputDecoration(labelText: 'Date (YYYY-MM-DD)'),
        ),
        TextField(
          controller: _headcount,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Required headcount'),
        ),
      ],
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop((
          code: _code,
          date: _date.text.trim(),
          headcount: int.tryParse(_headcount.text.trim()) ?? 1,
        )),
        child: const Text('Schedule'),
      ),
    ],
  );
}
