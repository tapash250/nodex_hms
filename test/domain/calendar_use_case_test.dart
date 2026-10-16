/// Tests for the institutional calendar use-case gates and overlay
/// (Module 40).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/authorization_snapshot.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/domain/calendar/calendar.dart';
import 'package:nodex_hms/domain/calendar/calendar_repository.dart';
import 'package:nodex_hms/domain/calendar/calendar_use_cases.dart';

import 'calendar_repository_test.dart' show FakeCalendarStore;

AuthorizationPolicy policyWith(Set<String> permissions) {
  final DateTime issuedAt = DateTime.now().toUtc();
  return AuthorizationPolicy(
    snapshot: AuthorizationSnapshot(
      snapshotId: 'snapshot-1',
      tenantId: 'tenant-1',
      userId: 'admin-1',
      deviceId: 'device-1',
      revision: 1,
      issuedAt: issuedAt,
      expiresAt: issuedAt.add(const Duration(days: 30)),
      payloadDigest: 'digest',
      roles: const <String>{NodexRoles.hospitalSuperAdmin},
      permissions: permissions,
      offlinePermissions: permissions,
      facilityIds: const <String>{'f-1'},
      departmentIds: const <String>{},
      wardIds: const <String>{},
    ),
    connectivity: ConnectivityState.online,
  );
}

CalendarEvent event({
  required String id,
  required DateTime startsAt,
  required DateTime endsAt,
  CalendarEventType type = CalendarEventType.training,
}) => CalendarEvent.fromRow(
  CalendarEvent.registerRow(
    tenantId: 'tenant-1',
    createdBy: 'user-1',
    title: id,
    startsAt: startsAt,
    endsAt: endsAt,
    eventType: type,
    eventId: id,
  ),
);

void main() {
  late FakeCalendarStore store;
  late DefaultCalendarRepository repository;
  late CreateCalendarEventUseCase create;
  late UpdateCalendarEventUseCase update;
  late CancelCalendarEventUseCase cancel;
  late ReadCalendarUseCase read;

  const Set<String> manage = <String>{NodexPermissions.calendarManage};
  const Set<String> reader = <String>{NodexPermissions.calendarRead};

  setUp(() {
    store = FakeCalendarStore();
    repository = DefaultCalendarRepository(
      store: store,
      logger: NodexLogger(
        sinks: <NodexLogSink>[InMemoryLogSink()],
        minimumLevel: NodexLogLevel.trace,
      ),
    );
    create = CreateCalendarEventUseCase(repository: repository);
    update = UpdateCalendarEventUseCase(repository: repository);
    cancel = CancelCalendarEventUseCase(repository: repository);
    read = ReadCalendarUseCase(repository: repository);
  });

  test('create requires management permission', () async {
    final DateTime start = DateTime.utc(2026, 10, 20, 9);
    expect(
      () => create(
        policy: policyWith(<String>{}),
        tenantId: 'tenant-1',
        createdBy: 'user-1',
        title: 'Fire drill',
        startsAt: start,
        endsAt: start.add(const Duration(hours: 1)),
      ),
      throwsA(isA<NodexError>()),
    );
    final String id = await create(
      policy: policyWith(manage),
      tenantId: 'tenant-1',
      createdBy: 'user-1',
      title: 'Fire drill',
      startsAt: start,
      endsAt: start.add(const Duration(hours: 1)),
    );
    expect(id, isNotEmpty);
  });

  test('create rejects an end before the start', () async {
    final DateTime start = DateTime.utc(2026, 10, 20, 9);
    expect(
      () => create(
        policy: policyWith(manage),
        tenantId: 'tenant-1',
        createdBy: 'user-1',
        title: 'Backwards',
        startsAt: start,
        endsAt: start.subtract(const Duration(hours: 1)),
      ),
      throwsA(isA<NodexError>()),
    );
  });

  test('update after cancel is refused', () async {
    final DateTime start = DateTime.utc(2026, 10, 20, 9);
    final String id = await create(
      policy: policyWith(manage),
      tenantId: 'tenant-1',
      createdBy: 'user-1',
      title: 'Audit',
      startsAt: start,
      endsAt: start.add(const Duration(hours: 2)),
    );
    final CalendarEvent created = (await repository.eventById(id))!;
    await cancel(policy: policyWith(manage), event: created);
    final CalendarEvent cancelled = (await repository.eventById(id))!;
    expect(cancelled.status, CalendarEventStatus.cancelled);
    expect(
      () => update(
        policy: policyWith(manage),
        event: cancelled,
        title: 'Renamed audit',
      ),
      throwsA(isA<NodexError>()),
    );
  });

  test('cancel is idempotent-guarded and requires management', () async {
    final DateTime start = DateTime.utc(2026, 10, 20, 9);
    final String id = await create(
      policy: policyWith(manage),
      tenantId: 'tenant-1',
      createdBy: 'user-1',
      title: 'Audit',
      startsAt: start,
      endsAt: start.add(const Duration(hours: 2)),
    );
    final CalendarEvent created = (await repository.eventById(id))!;
    expect(
      () => cancel(policy: policyWith(<String>{}), event: created),
      throwsA(isA<NodexError>()),
    );
    await cancel(policy: policyWith(manage), event: created);
    final CalendarEvent cancelled = (await repository.eventById(id))!;
    expect(
      () => cancel(policy: policyWith(manage), event: cancelled),
      throwsA(isA<NodexError>()),
    );
  });

  test('eventsInWindow requires read and filters by overlap', () async {
    final DateTime from = DateTime.utc(2026, 10, 20);
    final DateTime to = DateTime.utc(2026, 10, 27);
    expect(
      () => read.eventsInWindow(
        policy: policyWith(<String>{}),
        tenantId: 'tenant-1',
        from: from,
        to: to,
      ),
      throwsA(isA<NodexError>()),
    );

    await create(
      policy: policyWith(manage),
      tenantId: 'tenant-1',
      createdBy: 'user-1',
      title: 'Inside',
      startsAt: DateTime.utc(2026, 10, 21, 9),
      endsAt: DateTime.utc(2026, 10, 21, 10),
    );
    await create(
      policy: policyWith(manage),
      tenantId: 'tenant-1',
      createdBy: 'user-1',
      title: 'Outside',
      startsAt: DateTime.utc(2026, 11, 5, 9),
      endsAt: DateTime.utc(2026, 11, 5, 10),
    );

    final List<CalendarEvent> window = await read.eventsInWindow(
      policy: policyWith(reader),
      tenantId: 'tenant-1',
      from: from,
      to: to,
    );
    expect(window, hasLength(1));
    expect(window.first.title, 'Inside');
  });

  test('overlay merges events and shifts, one entry per non-empty day', () {
    final DateTime from = DateTime.utc(2026, 10, 20);
    final DateTime to = DateTime.utc(2026, 10, 23);
    final List<CalendarDayOverlay> overlay = buildCalendarOverlay(
      events: <CalendarEvent>[
        event(
          id: 'e-1',
          startsAt: DateTime.utc(2026, 10, 20, 9),
          endsAt: DateTime.utc(2026, 10, 20, 10),
        ),
      ],
      shifts: <ShiftSlice>[
        ShiftSlice(
          id: 's-1',
          label: 'Morning',
          startsAt: DateTime.utc(2026, 10, 21, 6),
          endsAt: DateTime.utc(2026, 10, 21, 14),
        ),
      ],
      from: from,
      to: to,
    );
    expect(overlay, hasLength(2));
    expect(overlay.first.date, DateTime.utc(2026, 10, 20));
    expect(overlay.first.events, hasLength(1));
    expect(overlay.first.shifts, isEmpty);
    expect(overlay.last.date, DateTime.utc(2026, 10, 21));
    expect(overlay.last.shifts.single.label, 'Morning');
  });

  test('overlay helpers and enum parsing behave as documented', () {
    expect(
      CalendarEventType.fromWire('maintenance'),
      CalendarEventType.maintenance,
    );
    expect(CalendarEventType.fromWire('nonsense'), CalendarEventType.other);
    expect(
      CalendarEventStatus.fromWire('cancelled'),
      CalendarEventStatus.cancelled,
    );

    final CalendarEvent e = event(
      id: 'e-1',
      startsAt: DateTime.utc(2026, 10, 20, 9),
      endsAt: DateTime.utc(2026, 10, 20, 10),
    );
    expect(
      calendarEventOverlapsWindow(
        e,
        DateTime.utc(2026, 10, 20, 9, 30),
        DateTime.utc(2026, 10, 20, 11),
      ),
      isTrue,
    );
    expect(
      calendarEventOverlapsWindow(
        e,
        DateTime.utc(2026, 10, 21),
        DateTime.utc(2026, 10, 22),
      ),
      isFalse,
    );

    final ShiftSlice shift = ShiftSlice(
      id: 's',
      label: 'Night',
      startsAt: DateTime.utc(2026, 10, 20, 22),
      endsAt: DateTime.utc(2026, 10, 21, 6),
    );
    expect(
      shift.overlapsWindow(
        DateTime.utc(2026, 10, 20, 23),
        DateTime.utc(2026, 10, 21, 1),
      ),
      isTrue,
    );

    expect(
      buildCalendarOverlay(
        events: const <CalendarEvent>[],
        shifts: const <ShiftSlice>[],
        from: DateTime.utc(2026, 10, 20),
        to: DateTime.utc(2026, 10, 20),
      ),
      isEmpty,
    );
  });
}
