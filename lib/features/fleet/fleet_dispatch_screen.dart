/// Fleet & ambulance dispatch (Module 27).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/domain/fleet/fleet.dart';
import 'package:nodex_hms/domain/fleet/fleet_use_cases.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// The fleet and dispatch board.
class FleetDispatchScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const FleetDispatchScreen({super.key});

  @override
  ConsumerState<FleetDispatchScreen> createState() =>
      _FleetDispatchScreenState();
}

class _FleetDispatchScreenState extends ConsumerState<FleetDispatchScreen> {
  List<AmbulanceDispatch> _dispatches = const <AmbulanceDispatch>[];
  List<Ambulance> _vehicles = const <Ambulance>[];
  Map<String, List<AmbulanceDuty>> _dutiesByVehicle =
      const <String, List<AmbulanceDuty>>{};
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
      final ReadFleetUseCase read = ref.read(readFleetUseCaseProvider);
      final List<AmbulanceDispatch> dispatches = await read.dispatches(
        policy: session.authorization,
        tenantId: tenantId,
        activeFirst: true,
      );
      final List<Ambulance> vehicles = await read.ambulances(
        policy: session.authorization,
        tenantId: tenantId,
      );
      final Map<String, List<AmbulanceDuty>> duties =
          <String, List<AmbulanceDuty>>{};
      for (final Ambulance vehicle in vehicles) {
        duties[vehicle.id] = await read.duties(
          policy: session.authorization,
          tenantId: tenantId,
          ambulanceId: vehicle.id,
          liveOnly: true,
        );
      }
      if (!mounted) return;
      setState(() {
        _dispatches = dispatches;
        _vehicles = vehicles;
        _dutiesByVehicle = duties;
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

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      await _load();
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  String _vehicleLabel(String? id) {
    if (id == null) {
      return 'Unassigned';
    }
    for (final Ambulance vehicle in _vehicles) {
      if (vehicle.id == id) {
        return vehicle.callSign;
      }
    }
    return 'Vehicle';
  }

  Future<void> _raiseDispatch() async {
    final session = ref.read(sessionProvider);
    final String? tenantId = session.tenantId;
    final Set<String> facilities =
        session.snapshot?.facilityIds ?? const <String>{};
    final String? facilityId = facilities.isEmpty ? null : facilities.first;
    final String? userId = session.user?.userId;
    if (tenantId == null || facilityId == null || userId == null) return;
    final _DispatchFormResult? result = await showDialog<_DispatchFormResult>(
      context: context,
      builder: (BuildContext context) => const _DispatchFormDialog(),
    );
    if (result == null) return;
    await _run(() async {
      await ref
          .read(raiseDispatchUseCaseProvider)
          .call(
            policy: session.authorization,
            tenantId: tenantId,
            createdBy: userId,
            facilityId: facilityId,
            pickupAddress: result.pickupAddress,
            patientNameText: result.patientName,
            priority: result.priority,
            destinationAddress: result.destinationAddress,
            requestingReference: result.requestingReference,
          );
    });
  }

  Future<void> _advance(
    AmbulanceDispatch job,
    DispatchStatus to, {
    String? ambulanceId,
  }) async {
    final session = ref.read(sessionProvider);
    await _run(() async {
      await ref
          .read(advanceDispatchUseCaseProvider)
          .call(
            policy: session.authorization,
            dispatch: job,
            to: to,
            ambulanceId: ambulanceId,
          );
    });
  }

  Future<void> _cancel(AmbulanceDispatch job) async {
    final session = ref.read(sessionProvider);
    await _run(() async {
      await ref
          .read(cancelDispatchUseCaseProvider)
          .call(policy: session.authorization, dispatch: job);
    });
  }

  Future<void> _showDispatch(AmbulanceDispatch job) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            ListTile(
              leading: Icon(
                job.priority == DispatchPriority.emergency
                    ? Icons.emergency
                    : Icons.local_taxi_outlined,
              ),
              title: Text(job.displayName),
              subtitle: Text(
                <String>[
                  job.priority.label,
                  job.status.label,
                  _vehicleLabel(job.ambulanceId),
                ].join(' · '),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.place_outlined),
              title: Text(job.pickupAddress),
              subtitle: job.destinationAddress == null
                  ? null
                  : Text('to ${job.destinationAddress}'),
            ),
            ..._dispatchActions(job),
          ],
        ),
      ),
    );
  }

  List<Widget> _dispatchActions(AmbulanceDispatch job) {
    if (!job.isLive) {
      return <Widget>[];
    }
    if (job.status == DispatchStatus.requested) {
      final List<Ambulance> available = _vehicles
          .where(
            (Ambulance v) =>
                v.serviceStatus == AmbulanceServiceStatus.inService,
          )
          .toList(growable: false);
      if (available.isEmpty) {
        return <Widget>[
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('No vehicle is in service to assign.'),
          ),
          _cancelTile(job),
        ];
      }
      return <Widget>[
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text('Assign a vehicle'),
        ),
        for (final Ambulance vehicle in available)
          ListTile(
            leading: const Icon(Icons.airport_shuttle_outlined),
            title: Text(vehicle.callSign),
            subtitle: Text(vehicle.vehicleType.label),
            onTap: () {
              Navigator.of(context).pop();
              _advance(job, DispatchStatus.assigned, ambulanceId: vehicle.id);
            },
          ),
        _cancelTile(job),
      ];
    }
    final DispatchStatus? next = switch (job.status) {
      DispatchStatus.assigned => DispatchStatus.enRoute,
      DispatchStatus.enRoute => DispatchStatus.onScene,
      DispatchStatus.onScene => DispatchStatus.completed,
      _ => null,
    };
    return <Widget>[
      if (next != null)
        ListTile(
          leading: const Icon(Icons.arrow_forward),
          title: Text('Advance to ${next.label.toLowerCase()}'),
          onTap: () {
            Navigator.of(context).pop();
            _advance(job, next);
          },
        ),
      _cancelTile(job),
    ];
  }

  Widget _cancelTile(AmbulanceDispatch job) => ListTile(
    leading: const Icon(Icons.cancel_outlined),
    title: const Text('Cancel dispatch'),
    onTap: () {
      Navigator.of(context).pop();
      _cancel(job);
    },
  );

  Future<void> _registerVehicle() async {
    final session = ref.read(sessionProvider);
    final String? tenantId = session.tenantId;
    final Set<String> facilities =
        session.snapshot?.facilityIds ?? const <String>{};
    final String? facilityId = facilities.isEmpty ? null : facilities.first;
    final String? userId = session.user?.userId;
    if (tenantId == null || facilityId == null || userId == null) return;
    final _VehicleFormResult? result = await showDialog<_VehicleFormResult>(
      context: context,
      builder: (BuildContext context) => const _VehicleFormDialog(),
    );
    if (result == null) return;
    await _run(() async {
      await ref
          .read(registerAmbulanceUseCaseProvider)
          .call(
            policy: session.authorization,
            tenantId: tenantId,
            createdBy: userId,
            facilityId: facilityId,
            callSign: result.callSign,
            vehicleType: result.vehicleType,
            capacity: result.capacity,
            registrationNo: result.registrationNo,
            capabilityNotes: result.capabilityNotes,
          );
    });
  }

  Future<void> _showVehicle(Ambulance vehicle) async {
    final List<AmbulanceDuty> duties =
        _dutiesByVehicle[vehicle.id] ?? const <AmbulanceDuty>[];
    await showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.airport_shuttle_outlined),
              title: Text(vehicle.callSign),
              subtitle: Text(
                <String>[
                  vehicle.vehicleType.label,
                  vehicle.serviceStatus.label,
                  if (vehicle.registrationNo case final String reg) reg,
                ].join(' · '),
              ),
            ),
            if (vehicle.capabilityNotes case final String notes)
              ListTile(leading: const Icon(Icons.notes), title: Text(notes)),
            const Divider(height: 1),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text('Live duty roster'),
            ),
            if (duties.isEmpty)
              const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('No live duty assigned.'),
              ),
            for (final AmbulanceDuty duty in duties)
              ListTile(
                dense: true,
                leading: const Icon(Icons.badge_outlined),
                title: Text(duty.status.name),
                subtitle: Text(
                  '${_format(duty.startsAt)} → ${_format(duty.endsAt)}',
                ),
              ),
            ListTile(
              leading: const Icon(Icons.schedule),
              title: const Text('Schedule a duty'),
              onTap: () {
                Navigator.of(context).pop();
                _scheduleDuty(vehicle);
              },
            ),
            if (vehicle.isEditable)
              ListTile(
                leading: const Icon(Icons.archive_outlined),
                title: const Text('Archive vehicle'),
                onTap: () {
                  Navigator.of(context).pop();
                  _archive(vehicle);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _archive(Ambulance vehicle) async {
    final session = ref.read(sessionProvider);
    await _run(() async {
      await ref
          .read(archiveAmbulanceUseCaseProvider)
          .call(policy: session.authorization, ambulance: vehicle);
    });
  }

  Future<void> _scheduleDuty(Ambulance vehicle) async {
    final session = ref.read(sessionProvider);
    final String? tenantId = session.tenantId;
    final String? userId = session.user?.userId;
    if (tenantId == null || userId == null) return;
    final _DutyFormResult? result = await showDialog<_DutyFormResult>(
      context: context,
      builder: (BuildContext context) => const _DutyFormDialog(),
    );
    if (result == null) return;
    await _run(() async {
      await ref
          .read(scheduleDutyUseCaseProvider)
          .call(
            policy: session.authorization,
            tenantId: tenantId,
            createdBy: userId,
            ambulanceId: vehicle.id,
            driverUserId: result.driverUserId,
            attendantUserId: result.attendantUserId,
            startsAt: result.startsAt,
            endsAt: result.endsAt,
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Fleet')),
        body: Center(child: Text(_error!)),
      );
    }
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Fleet'),
          bottom: const TabBar(
            tabs: <Widget>[
              Tab(text: 'Dispatch'),
              Tab(text: 'Vehicles'),
            ],
          ),
        ),
        body: TabBarView(children: <Widget>[_dispatchTab(), _vehicleTab()]),
      ),
    );
  }

  Widget _dispatchTab() {
    return Stack(
      children: <Widget>[
        if (_dispatches.isEmpty)
          const Center(child: Text('No dispatches.'))
        else
          ListView.builder(
            itemCount: _dispatches.length,
            itemBuilder: (BuildContext context, int index) {
              final AmbulanceDispatch job = _dispatches[index];
              return ListTile(
                leading: Icon(
                  job.status.isLive
                      ? Icons.wifi_tethering
                      : Icons.check_circle_outline,
                  color: job.status.isLive
                      ? Theme.of(context).colorScheme.error
                      : null,
                ),
                title: Text(job.displayName),
                subtitle: Text(
                  <String>[
                    job.priority.label,
                    job.status.label,
                    _vehicleLabel(job.ambulanceId),
                  ].join(' · '),
                ),
                onTap: () => _showDispatch(job),
              );
            },
          ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            onPressed: _raiseDispatch,
            tooltip: 'Raise dispatch',
            child: const Icon(Icons.emergency_share_outlined),
          ),
        ),
      ],
    );
  }

  Widget _vehicleTab() {
    if (_vehicles.isEmpty) {
      return const Center(child: Text('No vehicles registered.'));
    }
    return Stack(
      children: <Widget>[
        ListView.builder(
          itemCount: _vehicles.length,
          itemBuilder: (BuildContext context, int index) {
            final Ambulance vehicle = _vehicles[index];
            return ListTile(
              leading: const Icon(Icons.airport_shuttle_outlined),
              title: Text(vehicle.callSign),
              subtitle: Text(
                <String>[
                  vehicle.vehicleType.label,
                  vehicle.serviceStatus.label,
                ].join(' · '),
              ),
              onTap: () => _showVehicle(vehicle),
            );
          },
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            onPressed: _registerVehicle,
            tooltip: 'Add vehicle',
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }
}

String _format(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')} '
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}';

class _DispatchFormResult {
  const _DispatchFormResult({
    required this.pickupAddress,
    required this.patientName,
    required this.priority,
    this.destinationAddress,
    this.requestingReference,
  });

  final String pickupAddress;
  final String patientName;
  final DispatchPriority priority;
  final String? destinationAddress;
  final String? requestingReference;
}

class _DispatchFormDialog extends StatefulWidget {
  const _DispatchFormDialog();

  @override
  State<_DispatchFormDialog> createState() => _DispatchFormDialogState();
}

class _DispatchFormDialogState extends State<_DispatchFormDialog> {
  final TextEditingController _pickup = TextEditingController();
  final TextEditingController _patient = TextEditingController();
  final TextEditingController _destination = TextEditingController();
  final TextEditingController _reference = TextEditingController();
  DispatchPriority _priority = DispatchPriority.emergency;

  @override
  void dispose() {
    for (final TextEditingController controller in <TextEditingController>[
      _pickup,
      _patient,
      _destination,
      _reference,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _nullIfEmpty(TextEditingController controller) {
    final String value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Raise dispatch'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _patient,
            decoration: const InputDecoration(labelText: 'Patient name'),
          ),
          TextField(
            controller: _pickup,
            decoration: const InputDecoration(labelText: 'Pickup address'),
          ),
          DropdownButtonFormField<DispatchPriority>(
            initialValue: _priority,
            decoration: const InputDecoration(labelText: 'Priority'),
            items: <DropdownMenuItem<DispatchPriority>>[
              for (final DispatchPriority priority in DispatchPriority.values)
                DropdownMenuItem<DispatchPriority>(
                  value: priority,
                  child: Text(priority.label),
                ),
            ],
            onChanged: (DispatchPriority? value) {
              if (value != null) setState(() => _priority = value);
            },
          ),
          TextField(
            controller: _destination,
            decoration: const InputDecoration(labelText: 'Destination'),
          ),
          TextField(
            controller: _reference,
            decoration: const InputDecoration(labelText: 'Requested by'),
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
          _DispatchFormResult(
            pickupAddress: _pickup.text.trim(),
            patientName: _patient.text.trim(),
            priority: _priority,
            destinationAddress: _nullIfEmpty(_destination),
            requestingReference: _nullIfEmpty(_reference),
          ),
        ),
        child: const Text('Raise'),
      ),
    ],
  );
}

class _VehicleFormResult {
  const _VehicleFormResult({
    required this.callSign,
    required this.vehicleType,
    required this.capacity,
    this.registrationNo,
    this.capabilityNotes,
  });

  final String callSign;
  final VehicleType vehicleType;
  final int capacity;
  final String? registrationNo;
  final String? capabilityNotes;
}

class _VehicleFormDialog extends StatefulWidget {
  const _VehicleFormDialog();

  @override
  State<_VehicleFormDialog> createState() => _VehicleFormDialogState();
}

class _VehicleFormDialogState extends State<_VehicleFormDialog> {
  final TextEditingController _callSign = TextEditingController();
  final TextEditingController _registration = TextEditingController();
  final TextEditingController _capacity = TextEditingController(text: '1');
  final TextEditingController _notes = TextEditingController();
  VehicleType _type = VehicleType.bls;

  @override
  void dispose() {
    for (final TextEditingController controller in <TextEditingController>[
      _callSign,
      _registration,
      _capacity,
      _notes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _nullIfEmpty(TextEditingController controller) {
    final String value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add vehicle'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _callSign,
            decoration: const InputDecoration(labelText: 'Call sign'),
          ),
          TextField(
            controller: _registration,
            decoration: const InputDecoration(labelText: 'Registration'),
          ),
          DropdownButtonFormField<VehicleType>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Type'),
            items: <DropdownMenuItem<VehicleType>>[
              for (final VehicleType type in VehicleType.values)
                DropdownMenuItem<VehicleType>(
                  value: type,
                  child: Text(type.label),
                ),
            ],
            onChanged: (VehicleType? value) {
              if (value != null) setState(() => _type = value);
            },
          ),
          TextField(
            controller: _capacity,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Capacity'),
          ),
          TextField(
            controller: _notes,
            decoration: const InputDecoration(labelText: 'Capability notes'),
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
          _VehicleFormResult(
            callSign: _callSign.text.trim(),
            vehicleType: _type,
            capacity: int.tryParse(_capacity.text.trim()) ?? 1,
            registrationNo: _nullIfEmpty(_registration),
            capabilityNotes: _nullIfEmpty(_notes),
          ),
        ),
        child: const Text('Save'),
      ),
    ],
  );
}

class _DutyFormResult {
  const _DutyFormResult({
    required this.driverUserId,
    required this.startsAt,
    required this.endsAt,
    this.attendantUserId,
  });

  final String driverUserId;
  final DateTime startsAt;
  final DateTime endsAt;
  final String? attendantUserId;
}

class _DutyFormDialog extends StatefulWidget {
  const _DutyFormDialog();

  @override
  State<_DutyFormDialog> createState() => _DutyFormDialogState();
}

class _DutyFormDialogState extends State<_DutyFormDialog> {
  final TextEditingController _driver = TextEditingController();
  final TextEditingController _attendant = TextEditingController();
  late DateTime _start = DateTime.now().toUtc();
  late DateTime _end = _start.add(const Duration(hours: 8));

  @override
  void dispose() {
    _driver.dispose();
    _attendant.dispose();
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
      final DateTime day = DateTime.utc(picked.year, picked.month, picked.day);
      if (isStart) {
        _start = day;
        if (_end.isBefore(_start)) {
          _end = _start.add(const Duration(hours: 8));
        }
      } else {
        _end = day.add(const Duration(hours: 23, minutes: 59));
        if (_end.isBefore(_start)) _start = day;
      }
    });
  }

  String _format(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Schedule duty'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _driver,
            decoration: const InputDecoration(labelText: 'Driver user id'),
          ),
          TextField(
            controller: _attendant,
            decoration: const InputDecoration(labelText: 'Attendant user id'),
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
          _DutyFormResult(
            driverUserId: _driver.text.trim(),
            startsAt: _start,
            endsAt: _end,
            attendantUserId: _attendant.text.trim().isEmpty
                ? null
                : _attendant.text.trim(),
          ),
        ),
        child: const Text('Book'),
      ),
    ],
  );
}
