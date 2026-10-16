/// Nurse ward station (Module 06): observations, handover and the task board.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/domain/nursing_station/nursing_station.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// The ward station board.
class WardStationScreen extends ConsumerStatefulWidget {
  /// Creates the ward station screen.
  const WardStationScreen({super.key});

  @override
  ConsumerState<WardStationScreen> createState() => _WardStationScreenState();
}

class _WardStationScreenState extends ConsumerState<WardStationScreen> {
  List<WardTask> _tasks = const <WardTask>[];
  List<WardVital> _vitals = const <WardVital>[];
  List<WardHandover> _handovers = const <WardHandover>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _defaultWardId {
    final Set<String> wards =
        ref.read(sessionProvider).snapshot?.wardIds ?? const <String>{};
    return wards.isEmpty ? '' : wards.first;
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
      final read = ref.read(readWardStationUseCaseProvider);
      final String wardId = _defaultWardId;
      final List<WardTask> tasks = await read.openTasks(
        policy: session.authorization,
        tenantId: tenantId,
        wardId: wardId,
      );
      final List<WardVital> vitals = await read.recentVitals(
        policy: session.authorization,
        tenantId: tenantId,
        wardId: wardId,
      );
      final List<WardHandover> handovers = await read.handovers(
        policy: session.authorization,
        tenantId: tenantId,
        wardId: wardId,
      );
      if (!mounted) return;
      setState(() {
        _tasks = tasks;
        _vitals = vitals;
        _handovers = handovers;
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ward station')),
        body: Center(child: Text(_error!)),
      );
    }
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Ward station'),
          bottom: const TabBar(
            tabs: <Widget>[
              Tab(text: 'Tasks'),
              Tab(text: 'Observations'),
              Tab(text: 'Handover'),
            ],
          ),
        ),
        body: TabBarView(
          children: <Widget>[_tasksTab(), _vitalsTab(), _handoverTab()],
        ),
      ),
    );
  }

  Widget _tasksTab() => Scaffold(
    body: _tasks.isEmpty
        ? const Center(child: Text('No open tasks on this ward.'))
        : ListView.builder(
            itemCount: _tasks.length,
            itemBuilder: (BuildContext context, int index) {
              final WardTask task = _tasks[index];
              return ListTile(
                leading: Icon(
                  task.priority == WardTaskPriority.stat
                      ? Icons.priority_high
                      : Icons.check_circle_outline,
                  color: task.priority == WardTaskPriority.routine
                      ? null
                      : Theme.of(context).colorScheme.error,
                ),
                title: Text(task.title),
                subtitle: Text(
                  '${task.taskType.label} · ${task.priority.label} · '
                  '${task.assignedTo == null ? 'Unassigned' : 'Assigned'}',
                ),
                trailing: Text(task.status.label),
                onTap: () => _taskActions(task),
              );
            },
          ),
    floatingActionButton: FloatingActionButton(
      onPressed: _newTask,
      tooltip: 'New task',
      child: const Icon(Icons.add),
    ),
  );

  Widget _vitalsTab() => Scaffold(
    body: _vitals.isEmpty
        ? const Center(child: Text('No observations recorded.'))
        : ListView.builder(
            itemCount: _vitals.length,
            itemBuilder: (BuildContext context, int index) {
              final WardVital vital = _vitals[index];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: _alertColor(context, vital.alert),
                  child: Text(vital.alert.label.substring(0, 1)),
                ),
                title: Text(_summarise(vital)),
                subtitle: Text(
                  '${vital.consciousness.label}'
                  '${vital.onOxygen ? ' · on oxygen' : ''}',
                ),
                trailing: Text(
                  vital.observedAt.substring(0, 16).replaceFirst('T', ' '),
                ),
              );
            },
          ),
    floatingActionButton: FloatingActionButton(
      onPressed: _recordVitals,
      tooltip: 'Record vitals',
      child: const Icon(Icons.add),
    ),
  );

  Widget _handoverTab() => Scaffold(
    body: _handovers.isEmpty
        ? const Center(child: Text('No handovers recorded.'))
        : ListView.builder(
            itemCount: _handovers.length,
            itemBuilder: (BuildContext context, int index) {
              final WardHandover handover = _handovers[index];
              return ListTile(
                leading: const Icon(Icons.swap_horiz),
                title: Text(handover.summary, maxLines: 2),
                subtitle: Text(
                  handover.pendingItems == null
                      ? 'No pending items'
                      : 'Pending: ${handover.pendingItems}',
                ),
                trailing: Text(
                  handover.handoverAt.substring(0, 16).replaceFirst('T', ' '),
                ),
              );
            },
          ),
    floatingActionButton: FloatingActionButton(
      onPressed: _recordHandover,
      tooltip: 'Record handover',
      child: const Icon(Icons.add),
    ),
  );

  Color _alertColor(BuildContext context, VitalAlert alert) => switch (alert) {
    VitalAlert.critical => Theme.of(context).colorScheme.error,
    VitalAlert.warning => Theme.of(context).colorScheme.tertiary,
    VitalAlert.normal => Theme.of(context).colorScheme.secondaryContainer,
  };

  String _summarise(WardVital vital) {
    final List<String> parts = <String>[];
    if (vital.temperatureCelsius != null) {
      parts.add('${vital.temperatureCelsius}°C');
    }
    if (vital.pulseBpm != null) parts.add('HR ${vital.pulseBpm}');
    if (vital.respiratoryRate != null) parts.add('RR ${vital.respiratoryRate}');
    if (vital.systolicBp != null && vital.diastolicBp != null) {
      parts.add('BP ${vital.systolicBp}/${vital.diastolicBp}');
    }
    if (vital.spo2 != null) parts.add('SpO2 ${vital.spo2}%');
    if (vital.painScore != null) parts.add('Pain ${vital.painScore}/10');
    return parts.join('  ·  ');
  }

  Future<void> _taskActions(WardTask task) async {
    final session = ref.read(sessionProvider);
    final String? userId = session.user?.userId;
    if (userId == null) return;
    final String? action = await showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (task.status == WardTaskStatus.open)
              ListTile(
                leading: const Icon(Icons.play_arrow),
                title: const Text('Start'),
                onTap: () => Navigator.of(context).pop('start'),
              ),
            ListTile(
              leading: const Icon(Icons.person_add_alt),
              title: const Text('Assign to me'),
              onTap: () => Navigator.of(context).pop('assign'),
            ),
            ListTile(
              leading: const Icon(Icons.check),
              title: const Text('Mark done'),
              onTap: () => Navigator.of(context).pop('done'),
            ),
            ListTile(
              leading: const Icon(Icons.cancel_outlined),
              title: const Text('Cancel task'),
              onTap: () => Navigator.of(context).pop('cancel'),
            ),
          ],
        ),
      ),
    );
    if (action == null) return;
    try {
      switch (action) {
        case 'start':
          await ref
              .read(startWardTaskUseCaseProvider)
              .call(policy: session.authorization, task: task);
        case 'assign':
          await ref
              .read(assignWardTaskUseCaseProvider)
              .call(
                policy: session.authorization,
                task: task,
                assignedTo: userId,
              );
        case 'done':
          await ref
              .read(closeWardTaskUseCaseProvider)
              .call(
                policy: session.authorization,
                task: task,
                status: WardTaskStatus.done,
                completedBy: userId,
              );
        case 'cancel':
          await ref
              .read(closeWardTaskUseCaseProvider)
              .call(
                policy: session.authorization,
                task: task,
                status: WardTaskStatus.cancelled,
                completedBy: userId,
              );
      }
      await _load();
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _newTask() async {
    final session = ref.read(sessionProvider);
    final String? userId = session.user?.userId;
    final String? tenantId = session.tenantId;
    if (userId == null || tenantId == null) return;
    final ({String title, WardTaskPriority priority})? entry =
        await showDialog<({String title, WardTaskPriority priority})>(
          context: context,
          builder: (BuildContext context) => const _TaskDialog(),
        );
    if (entry == null) return;
    try {
      await ref
          .read(createWardTaskUseCaseProvider)
          .call(
            policy: session.authorization,
            tenantId: tenantId,
            wardId: _defaultWardId,
            createdBy: userId,
            title: entry.title,
            priority: entry.priority,
          );
      await _load();
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _recordVitals() async {
    final session = ref.read(sessionProvider);
    final String? userId = session.user?.userId;
    final String? tenantId = session.tenantId;
    if (userId == null || tenantId == null) return;
    final _VitalsEntry? entry = await showDialog<_VitalsEntry>(
      context: context,
      builder: (BuildContext context) => const _VitalsDialog(),
    );
    if (entry == null) return;
    try {
      await ref
          .read(recordWardVitalsUseCaseProvider)
          .call(
            policy: session.authorization,
            tenantId: tenantId,
            patientId: entry.patientId,
            wardId: _defaultWardId,
            recordedBy: userId,
            temperatureCelsius: entry.temperatureCelsius,
            pulseBpm: entry.pulseBpm,
            respiratoryRate: entry.respiratoryRate,
            systolicBp: entry.systolicBp,
            diastolicBp: entry.diastolicBp,
            spo2: entry.spo2,
            painScore: entry.painScore,
            consciousness: entry.consciousness,
            onOxygen: entry.onOxygen,
          );
      await _load();
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _recordHandover() async {
    final session = ref.read(sessionProvider);
    final String? userId = session.user?.userId;
    final String? tenantId = session.tenantId;
    if (userId == null || tenantId == null) return;
    final ({String summary, String? pending})? entry =
        await showDialog<({String summary, String? pending})>(
          context: context,
          builder: (BuildContext context) => const _HandoverDialog(),
        );
    if (entry == null) return;
    try {
      await ref
          .read(recordWardHandoverUseCaseProvider)
          .call(
            policy: session.authorization,
            tenantId: tenantId,
            wardId: _defaultWardId,
            fromUser: userId,
            summary: entry.summary,
            pendingItems: entry.pending,
          );
      await _load();
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}

int? _intOrNull(String value) =>
    value.trim().isEmpty ? null : int.tryParse(value.trim());

double? _doubleOrNull(String value) =>
    value.trim().isEmpty ? null : double.tryParse(value.trim());

class _VitalsEntry {
  const _VitalsEntry({
    required this.patientId,
    required this.consciousness,
    required this.onOxygen,
    this.temperatureCelsius,
    this.pulseBpm,
    this.respiratoryRate,
    this.systolicBp,
    this.diastolicBp,
    this.spo2,
    this.painScore,
  });

  final String patientId;
  final ConsciousnessLevel consciousness;
  final bool onOxygen;
  final double? temperatureCelsius;
  final int? pulseBpm;
  final int? respiratoryRate;
  final int? systolicBp;
  final int? diastolicBp;
  final int? spo2;
  final int? painScore;
}

class _VitalsDialog extends StatefulWidget {
  const _VitalsDialog();

  @override
  State<_VitalsDialog> createState() => _VitalsDialogState();
}

class _VitalsDialogState extends State<_VitalsDialog> {
  final TextEditingController _patientId = TextEditingController();
  final TextEditingController _temperature = TextEditingController();
  final TextEditingController _pulse = TextEditingController();
  final TextEditingController _respiratory = TextEditingController();
  final TextEditingController _systolic = TextEditingController();
  final TextEditingController _diastolic = TextEditingController();
  final TextEditingController _spo2 = TextEditingController();
  final TextEditingController _pain = TextEditingController();
  ConsciousnessLevel _consciousness = ConsciousnessLevel.alert;
  bool _onOxygen = false;

  @override
  void dispose() {
    for (final TextEditingController controller in <TextEditingController>[
      _patientId,
      _temperature,
      _pulse,
      _respiratory,
      _systolic,
      _diastolic,
      _spo2,
      _pain,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Record observation'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _patientId,
            decoration: const InputDecoration(labelText: 'Patient id'),
          ),
          TextField(
            controller: _temperature,
            decoration: const InputDecoration(labelText: 'Temp °C'),
            keyboardType: TextInputType.number,
          ),
          TextField(
            controller: _pulse,
            decoration: const InputDecoration(labelText: 'Pulse'),
            keyboardType: TextInputType.number,
          ),
          TextField(
            controller: _respiratory,
            decoration: const InputDecoration(labelText: 'Resp rate'),
            keyboardType: TextInputType.number,
          ),
          TextField(
            controller: _systolic,
            decoration: const InputDecoration(labelText: 'Systolic'),
            keyboardType: TextInputType.number,
          ),
          TextField(
            controller: _diastolic,
            decoration: const InputDecoration(labelText: 'Diastolic'),
            keyboardType: TextInputType.number,
          ),
          TextField(
            controller: _spo2,
            decoration: const InputDecoration(labelText: 'SpO2 %'),
            keyboardType: TextInputType.number,
          ),
          TextField(
            controller: _pain,
            decoration: const InputDecoration(labelText: 'Pain 0–10'),
            keyboardType: TextInputType.number,
          ),
          DropdownButtonFormField<ConsciousnessLevel>(
            initialValue: _consciousness,
            decoration: const InputDecoration(labelText: 'Consciousness'),
            items: <DropdownMenuItem<ConsciousnessLevel>>[
              for (final ConsciousnessLevel level in ConsciousnessLevel.values)
                DropdownMenuItem<ConsciousnessLevel>(
                  value: level,
                  child: Text(level.label),
                ),
            ],
            onChanged: (ConsciousnessLevel? value) {
              if (value != null) setState(() => _consciousness = value);
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('On oxygen'),
            value: _onOxygen,
            onChanged: (bool value) => setState(() => _onOxygen = value),
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
          _VitalsEntry(
            patientId: _patientId.text.trim(),
            consciousness: _consciousness,
            onOxygen: _onOxygen,
            temperatureCelsius: _doubleOrNull(_temperature.text),
            pulseBpm: _intOrNull(_pulse.text),
            respiratoryRate: _intOrNull(_respiratory.text),
            systolicBp: _intOrNull(_systolic.text),
            diastolicBp: _intOrNull(_diastolic.text),
            spo2: _intOrNull(_spo2.text),
            painScore: _intOrNull(_pain.text),
          ),
        ),
        child: const Text('Record'),
      ),
    ],
  );
}

class _TaskDialog extends StatefulWidget {
  const _TaskDialog();

  @override
  State<_TaskDialog> createState() => _TaskDialogState();
}

class _TaskDialogState extends State<_TaskDialog> {
  final TextEditingController _title = TextEditingController();
  WardTaskPriority _priority = WardTaskPriority.routine;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('New task'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        TextField(
          controller: _title,
          decoration: const InputDecoration(labelText: 'Task'),
        ),
        DropdownButtonFormField<WardTaskPriority>(
          initialValue: _priority,
          decoration: const InputDecoration(labelText: 'Priority'),
          items: <DropdownMenuItem<WardTaskPriority>>[
            for (final WardTaskPriority priority in WardTaskPriority.values)
              DropdownMenuItem<WardTaskPriority>(
                value: priority,
                child: Text(priority.label),
              ),
          ],
          onChanged: (WardTaskPriority? value) {
            if (value != null) setState(() => _priority = value);
          },
        ),
      ],
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () =>
            Navigator.of(context)
                .pop((title: _title.text.trim(), priority: _priority)),
        child: const Text('Create'),
      ),
    ],
  );
}

class _HandoverDialog extends StatefulWidget {
  const _HandoverDialog();

  @override
  State<_HandoverDialog> createState() => _HandoverDialogState();
}

class _HandoverDialogState extends State<_HandoverDialog> {
  final TextEditingController _summary = TextEditingController();
  final TextEditingController _pending = TextEditingController();

  @override
  void dispose() {
    _summary.dispose();
    _pending.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Record handover'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        TextField(
          controller: _summary,
          decoration: const InputDecoration(labelText: 'Summary'),
          maxLines: 3,
        ),
        TextField(
          controller: _pending,
          decoration: const InputDecoration(labelText: 'Pending items'),
          maxLines: 2,
        ),
      ],
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          final String summary = _summary.text.trim();
          final String pending = _pending.text.trim();
          Navigator.of(
            context,
          ).pop((summary: summary, pending: pending.isEmpty ? null : pending));
        },
        child: const Text('Record'),
      ),
    ],
  );
}
