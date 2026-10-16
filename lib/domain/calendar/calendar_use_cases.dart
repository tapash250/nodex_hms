/// Institutional calendar use cases (Module 40).
library;

import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/calendar/calendar.dart';
import 'package:nodex_hms/domain/calendar/calendar_repository.dart';

/// Creates an institutional calendar event.
final class CreateCalendarEventUseCase {
  /// Creates the use case.
  CreateCalendarEventUseCase({required this._repository});

  final CalendarRepository _repository;

  Future<String> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String createdBy,
    required String title,
    required DateTime startsAt,
    required DateTime endsAt,
    CalendarEventType eventType = CalendarEventType.other,
    String? facilityId,
    String? departmentId,
    String? description,
    bool allDay = false,
    String? location,
    String eventId = '',
  }) async {
    policy.require(NodexPermissions.calendarManage);
    return _repository.createEvent(
      CalendarEvent.registerRow(
        tenantId: tenantId,
        createdBy: createdBy,
        title: title,
        startsAt: startsAt,
        endsAt: endsAt,
        eventType: eventType,
        facilityId: facilityId,
        departmentId: departmentId,
        description: description,
        allDay: allDay,
        location: location,
        eventId: eventId,
      ),
    );
  }
}

/// Updates a scheduled event. A cancelled event is a retained, frozen record.
final class UpdateCalendarEventUseCase {
  /// Creates the use case.
  UpdateCalendarEventUseCase({required this._repository});

  final CalendarRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required CalendarEvent event,
    String? title,
    CalendarEventType? eventType,
    DateTime? startsAt,
    DateTime? endsAt,
    String? facilityId,
    String? departmentId,
    String? description,
    String? location,
  }) async {
    policy.require(NodexPermissions.calendarManage);
    if (!event.isEditable) {
      throw const AuthorizationError(
        message:
            'A cancelled event is retained as a historical record and cannot '
            'be edited.',
        code: 'calendar_event_cancelled_immutable',
      );
    }
    await _repository.updateEvent(
      event.id,
      calendarEventChanges(
        facilityId: facilityId ?? event.facilityId,
        departmentId: departmentId ?? event.departmentId,
        title: title ?? event.title,
        eventType: eventType ?? event.eventType,
        startsAt: startsAt ?? event.startsAt,
        endsAt: endsAt ?? event.endsAt,
        description: description ?? event.description,
        location: location ?? event.location,
      ),
    );
  }
}

/// Cancels an event. The row is retained because a record that names the event
/// stays answerable.
final class CancelCalendarEventUseCase {
  /// Creates the use case.
  CancelCalendarEventUseCase({required this._repository});

  final CalendarRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required CalendarEvent event,
  }) async {
    policy.require(NodexPermissions.calendarManage);
    if (event.status == CalendarEventStatus.cancelled) {
      throw const AuthorizationError(
        message: 'This event is already cancelled.',
        code: 'calendar_event_already_cancelled',
      );
    }
    await _repository.updateEvent(event.id, calendarEventCancelChanges());
  }
}

/// Reads the institutional calendar and builds the shift overlay.
final class ReadCalendarUseCase {
  /// Creates the use case.
  ReadCalendarUseCase({required this._repository});

  final CalendarRepository _repository;

  /// Events overlapping the half-open window `[from, to)`, in start order.
  Future<List<CalendarEvent>> eventsInWindow({
    required AuthorizationPolicy policy,
    required String tenantId,
    required DateTime from,
    required DateTime to,
    CalendarEventType? eventType,
    bool includeCancelled = false,
  }) async {
    policy.require(NodexPermissions.calendarRead);
    final List<CalendarEvent> events = await _repository.listEvents(
      tenantId,
      eventType: eventType,
      includeCancelled: includeCancelled,
    );
    return events
        .where(
          (CalendarEvent event) => calendarEventOverlapsWindow(event, from, to),
        )
        .toList(growable: false);
  }

  /// The day-by-day overlay of institutional events and roster shifts.
  Future<List<CalendarDayOverlay>> overlay({
    required AuthorizationPolicy policy,
    required String tenantId,
    required DateTime from,
    required DateTime to,
    List<ShiftSlice> shifts = const <ShiftSlice>[],
    bool includeCancelled = false,
  }) async {
    final List<CalendarEvent> events = await eventsInWindow(
      policy: policy,
      tenantId: tenantId,
      from: from,
      to: to,
      includeCancelled: includeCancelled,
    );
    return buildCalendarOverlay(
      events: events,
      shifts: shifts,
      from: from,
      to: to,
    );
  }
}
