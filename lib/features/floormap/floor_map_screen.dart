/// Hospital floor map visualizer (Module 24).
///
/// Draws the rooms registered for a floor and overlays live occupancy derived
/// from the bed assignments the ward is actually running, so the map is a view
/// of the census rather than a second copy of it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/floormap/floormap.dart';
import 'package:nodex_hms/domain/session/session_state.dart';
import 'package:nodex_hms/features/floormap/floormap_controller.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// Floor map surface.
class FloorMapScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const FloorMapScreen({super.key});

  @override
  ConsumerState<FloorMapScreen> createState() => _FloorMapScreenState();
}

class _FloorMapScreenState extends ConsumerState<FloorMapScreen> {
  String? _floor;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<String>> floors = ref.watch(floorLabelsProvider);
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Floor map')),
      body: floors.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace _) => _FloorMapError(
          error: error,
          onRetry: () => ref.invalidate(floorLabelsProvider),
        ),
        data: (List<String> labels) {
          if (labels.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No rooms have been registered on the floor plan yet.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final String selected = _floor != null && labels.contains(_floor)
              ? _floor!
              : labels.first;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(16),
                child: DropdownButtonFormField<String>(
                  initialValue: selected,
                  decoration: const InputDecoration(labelText: 'Floor'),
                  items: labels
                      .map(
                        (String label) => DropdownMenuItem<String>(
                          value: label,
                          child: Text(label),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (String? value) {
                    if (value != null) setState(() => _floor = value);
                  },
                ),
              ),
              Expanded(
                child: _FloorBody(floorLabel: selected, theme: theme),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FloorBody extends ConsumerWidget {
  const _FloorBody({required this.floorLabel, required this.theme});

  final String floorLabel;
  final ThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<FloorOccupancy> occupancy = ref.watch(
      floorOccupancyProvider(floorLabel),
    );
    return occupancy.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object error, StackTrace _) => _FloorMapError(
        error: error,
        onRetry: () => ref.invalidate(floorOccupancyProvider(floorLabel)),
      ),
      data: (FloorOccupancy value) => RefreshIndicator(
        onRefresh: () async {
          ref
            ..invalidate(floorOccupancyProvider(floorLabel))
            ..invalidate(floorLabelsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: <Widget>[
            _OccupancySummary(occupancy: value),
            const SizedBox(height: 16),
            if (value.rooms.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No rooms are drawn on this floor yet.'),
                ),
              )
            else
              ...value.rooms.map(
                (RoomOccupancy room) => _RoomCard(occupancy: room),
              ),
            if (value.spaces.isNotEmpty) ...<Widget>[
              const SizedBox(height: 16),
              Text('Wards on this floor', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: value.spaces
                        .map(
                          (FloorSpace space) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              children: <Widget>[
                                Expanded(child: Text(space.displayName)),
                                Text(
                                  space.code,
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(growable: false),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OccupancySummary extends StatelessWidget {
  const _OccupancySummary({required this.occupancy});
  final FloorOccupancy occupancy;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color tone = occupancy.isFull
        ? Colors.red
        : occupancy.occupancyRate >= 0.85
        ? Colors.orange
        : Colors.green;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(occupancy.floorLabel, style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              '${occupancy.availableBeds} of ${occupancy.totalBeds} beds '
              'available',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: occupancy.occupancyRate,
                color: tone,
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${(occupancy.occupancyRate * 100).round()}% occupied · '
              '${occupancy.roomsAtCapacity} at capacity',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomCard extends StatelessWidget {
  const _RoomCard({required this.occupancy});
  final RoomOccupancy occupancy;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final WardRoom room = occupancy.room;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(_iconFor(room.roomType), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(room.roomName, style: theme.textTheme.titleSmall),
                ),
                Text(room.roomCode, style: theme.textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${room.roomType.label} · capacity ${room.capacity} · '
              'grid ${room.gridX},${room.gridY}',
              style: theme.textTheme.bodySmall,
            ),
            if (room.isRetired) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                room.retirementReason == null
                    ? 'Retired'
                    : 'Retired: ${room.retirementReason}',
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
              ),
            ] else if (room.isOccupiable) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                '${occupancy.availableBeds} of ${occupancy.mappedBeds} beds '
                'free'
                '${occupancy.isAtCapacity ? ' · at capacity' : ''}',
                style: theme.textTheme.bodyMedium,
              ),
              if (occupancy.beds.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: occupancy.beds
                      .map(
                        (BedOccupancy bed) => Chip(
                          visualDensity: VisualDensity.compact,
                          avatar: Icon(
                            bed.isOccupied ? Icons.person : Icons.bed_outlined,
                            size: 16,
                          ),
                          label: Text(bed.bedCode),
                        ),
                      )
                      .toList(growable: false),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  static IconData _iconFor(WardRoomType type) => switch (type) {
    WardRoomType.ward => Icons.single_bed_outlined,
    WardRoomType.icu => Icons.monitor_heart_outlined,
    WardRoomType.theatre => Icons.content_cut_outlined,
    WardRoomType.emergency => Icons.emergency_outlined,
    WardRoomType.diagnostics => Icons.science_outlined,
    WardRoomType.pharmacy => Icons.medication_outlined,
    WardRoomType.utility => Icons.cleaning_services_outlined,
    WardRoomType.office => Icons.badge_outlined,
  };
}

/// Admin entry point for registering a room on the current floor.
class WardRoomAdminScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const WardRoomAdminScreen({required this.floorLabel, super.key});

  /// The floor the room belongs to.
  final String floorLabel;

  @override
  ConsumerState<WardRoomAdminScreen> createState() =>
      _WardRoomAdminScreenState();
}

class _WardRoomAdminScreenState extends ConsumerState<WardRoomAdminScreen> {
  final TextEditingController _code = TextEditingController();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _capacity = TextEditingController(text: '1');
  WardRoomType _type = WardRoomType.ward;
  String? _wardId;
  String? _facilityId;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _capacity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final SessionState session = ref.watch(sessionProvider);
    final bool canWrite = session.authorization.can(
      NodexPermissions.wardRoomWrite,
    );
    // The plan is drawn per facility, so a room is only ever written against a
    // facility the signed-in principal is actually assigned to.
    final List<String> facilities = _facilities(session);
    final List<FloorSpace> spaces =
        ref.watch(floorSpacesProvider(widget.floorLabel)).asData?.value ??
        const <FloorSpace>[];
    if (facilities.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Register room')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'No facility is assigned to this account, so there is no plan to '
              'draw a room on.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Register room')),
      body: !canWrite
          ? const Center(
              child: Text('Room layout requires ward administration.'),
            )
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  TextField(
                    controller: _code,
                    decoration: const InputDecoration(labelText: 'Room code *'),
                    autofocus: true,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Room name *'),
                  ),
                  const SizedBox(height: 12),
                  if (facilities.length > 1)
                    DropdownButtonFormField<String>(
                      initialValue: _facilityId ?? facilities.first,
                      decoration: const InputDecoration(
                        labelText: 'Facility *',
                      ),
                      items: facilities
                          .map(
                            (String id) => DropdownMenuItem<String>(
                              value: id,
                              child: Text(id),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (String? value) {
                        if (value != null) {
                          setState(() => _facilityId = value);
                        }
                      },
                    ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    initialValue: _wardId,
                    decoration: const InputDecoration(
                      labelText: 'Linked ward',
                      helperText:
                          'Links this room to the patients of one ward.',
                    ),
                    items: <DropdownMenuItem<String?>>[
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Not linked'),
                      ),
                      ...spaces.map(
                        (FloorSpace space) => DropdownMenuItem<String?>(
                          value: space.wardId,
                          child: Text(space.displayName),
                        ),
                      ),
                    ],
                    onChanged: (String? value) =>
                        setState(() => _wardId = value),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<WardRoomType>(
                    initialValue: _type,
                    decoration: const InputDecoration(labelText: 'Room type *'),
                    items: WardRoomType.values
                        .map(
                          (WardRoomType type) => DropdownMenuItem<WardRoomType>(
                            value: type,
                            child: Text(type.label),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (WardRoomType? value) {
                      if (value != null) setState(() => _type = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _capacity,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Capacity *'),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _submit,
                    child: const Text('Register room'),
                  ),
                ],
              ),
            ),
    );
  }

  /// Facilities the signed-in principal may draw a plan on.
  List<String> _facilities(SessionState session) {
    final List<String> ids =
        session.snapshot?.facilityIds.toList(growable: true) ?? <String>[];
    ids.sort();
    return ids;
  }

  Future<void> _submit() async {
    final SessionState session = ref.read(sessionProvider);
    final List<String> facilities = _facilities(session);
    if (facilities.isEmpty) return;
    final String? tenantId = session.tenantId;
    if (tenantId == null) return;
    final String facilityId = _facilityId ?? facilities.first;
    final int? capacity = int.tryParse(_capacity.text.trim());
    if (_code.text.trim().isEmpty ||
        _name.text.trim().isEmpty ||
        capacity == null) {
      return;
    }
    try {
      await ref
          .read(registerWardRoomUseCaseProvider)
          .call(
            policy: session.authorization,
            tenantId: tenantId,
            facilityId: facilityId,
            roomCode: _code.text.trim(),
            roomName: _name.text.trim(),
            roomType: _type,
            floorLabel: widget.floorLabel,
            capacity: capacity,
            wardId: _wardId,
          );
      ref.invalidate(floorLabelsProvider);
      if (mounted) Navigator.pop(context);
    } on NodexError catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }
}

class _FloorMapError extends StatelessWidget {
  const _FloorMapError({required this.error, required this.onRetry});
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
              : 'Floor map unavailable',
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    ),
  );
}
