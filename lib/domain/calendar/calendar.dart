/// Institutional calendar entities and the shift overlay (Module 40).
///
/// Specification scope: an institutional calendar that overlays the
/// operational roster, so an event and the cover for the same day can be read
/// together.
///
/// The calendar owns only the institutional event. It does not own the roster:
/// shifts are Module 09, and the "overlay" is reading them on the same time
/// axis rather than storing a second copy. [buildCalendarOverlay] takes plain
/// [ShiftSlice] values — a minimal projection of a shift — so the calendar
/// domain does not depend on the workforce domain and the overlay stays a pure,
/// testable function.
// ignore_for_file: sort_constructors_first
library;

import 'package:meta/meta.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';

/// What kind of institutional event this is.
enum CalendarEventType {
  /// An institution-wide holiday.
  holiday('holiday'),

  /// Staff or clinical training.
  training('training'),

  /// An internal or external audit.
  audit('audit'),

  /// A planned outage or service window.
  maintenance('maintenance'),

  /// An academic or teaching session.
  academic('academic'),

  /// A meeting.
  meeting('meeting'),

  /// Anything else.
  other('other');

  const CalendarEventType(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    CalendarEventType.holiday => 'Holiday',
    CalendarEventType.training => 'Training',
    CalendarEventType.audit => 'Audit',
    CalendarEventType.maintenance => 'Maintenance',
    CalendarEventType.academic => 'Academic',
    CalendarEventType.meeting => 'Meeting',
    CalendarEventType.other => 'Other',
  };

  /// Parses a stored value.
  static CalendarEventType fromWire(String value) =>
      CalendarEventType.values.firstWhere(
        (CalendarEventType type) => type.wireValue == value,
        orElse: () => CalendarEventType.other,
      );
}

/// Lifecycle status of a calendar event.
enum CalendarEventStatus {
  /// Planned and current.
  scheduled('scheduled'),

  /// Called off; retained as a historical record and frozen.
  cancelled('cancelled');

  const CalendarEventStatus(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Parses a stored value.
  static CalendarEventStatus fromWire(String value) =>
      CalendarEventStatus.values.firstWhere(
        (CalendarEventStatus status) => status.wireValue == value,
        orElse: () => CalendarEventStatus.scheduled,
      );

  /// Whether the event may still be edited.
  bool get isEditable => this == CalendarEventStatus.scheduled;
}

/// An institutional calendar event.
@immutable
final class CalendarEvent {
  /// Creates a calendar event.
  const CalendarEvent({
    required this.id,
    required this.tenantId,
    required this.title,
    required this.eventType,
    required this.startsAt,
    required this.endsAt,
    required this.allDay,
    required this.status,
    required this.createdBy,
    required this.updatedAt,
    this.facilityId,
    this.departmentId,
    this.description,
    this.location,
    this.createdAt,
  });

  /// Validates and builds a new calendar-event row.
  static Map<String, Object?> registerRow({
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
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (createdBy.isEmpty) {
      fieldErrors['created_by'] = 'Creator is required.';
    }
    if (title.trim().isEmpty) {
      fieldErrors['title'] = 'An event title is required.';
    }
    if (endsAt.isBefore(startsAt)) {
      fieldErrors['ends_at'] = 'Must end on or after it starts.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Calendar event failed validation.',
        fieldErrors: fieldErrors,
        code: 'calendar_event_invalid',
      );
    }

    final String now = DateTime.now().toUtc().toIso8601String();
    return <String, Object?>{
      if (eventId.isNotEmpty) 'id': eventId,
      'tenant_id': tenantId,
      'facility_id': _trimmed(facilityId),
      'department_id': _trimmed(departmentId),
      'title': title.trim(),
      'description': _trimmed(description),
      'event_type': eventType.wireValue,
      'starts_at': startsAt.toUtc().toIso8601String(),
      'ends_at': endsAt.toUtc().toIso8601String(),
      'all_day': allDay,
      'location': _trimmed(location),
      'status': CalendarEventStatus.scheduled.wireValue,
      'created_by': createdBy,
      'created_at': now,
      'updated_at': now,
    };
  }

  /// Materializes a calendar event from a local row.
  factory CalendarEvent.fromRow(Map<String, Object?> row) => CalendarEvent(
    id: row['id']! as String,
    tenantId: row['tenant_id']! as String,
    title: row['title']! as String,
    eventType: CalendarEventType.fromWire(
      (row['event_type'] as String?) ?? CalendarEventType.other.wireValue,
    ),
    startsAt: DateTime.parse(row['starts_at']! as String).toUtc(),
    endsAt: DateTime.parse(row['ends_at']! as String).toUtc(),
    allDay: _asBool(row['all_day']),
    status: CalendarEventStatus.fromWire(
      (row['status'] as String?) ?? CalendarEventStatus.scheduled.wireValue,
    ),
    createdBy: row['created_by']! as String,
    updatedAt: _parse(row['updated_at']),
    facilityId: row['facility_id'] as String?,
    departmentId: row['department_id'] as String?,
    description: row['description'] as String?,
    location: row['location'] as String?,
    createdAt: _parseNullable(row['created_at']),
  );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// Facility the event belongs to, or null when institution-wide.
  final String? facilityId;

  /// Related department, when any.
  final String? departmentId;

  /// Event title.
  final String title;

  /// Free-text description.
  final String? description;

  /// What kind of event this is.
  final CalendarEventType eventType;

  /// Start, UTC.
  final DateTime startsAt;

  /// End, UTC.
  final DateTime endsAt;

  /// Whether the event is displayed as whole days.
  final bool allDay;

  /// Where the event is held.
  final String? location;

  /// Lifecycle status.
  final CalendarEventStatus status;

  /// Who created the event.
  final String createdBy;

  /// Last change, UTC.
  final DateTime updatedAt;

  /// When the event was created, UTC.
  final DateTime? createdAt;

  /// Whether the event may be edited or cancelled.
  bool get isEditable => status.isEditable;

  /// Whether the event is still current (not cancelled).
  bool get isScheduled => status == CalendarEventStatus.scheduled;
}

/// The full editable change set for a calendar event.
Map<String, Object?> calendarEventChanges({
  String? facilityId,
  String? departmentId,
  required String title,
  CalendarEventType? eventType,
  required DateTime startsAt,
  required DateTime endsAt,
  String? description,
  bool? allDay,
  String? location,
}) {
  if (endsAt.isBefore(startsAt)) {
    throw const ValidationError(
      message: 'Calendar event failed validation.',
      fieldErrors: <String, String>{
        'ends_at': 'Must end on or after it starts.',
      },
      code: 'calendar_event_invalid',
    );
  }
  return <String, Object?>{
    'facility_id': _trimmed(facilityId),
    'department_id': _trimmed(departmentId),
    'title': title.trim(),
    if (eventType != null) 'event_type': eventType.wireValue,
    'starts_at': startsAt.toUtc().toIso8601String(),
    'ends_at': endsAt.toUtc().toIso8601String(),
    'all_day': ?allDay,
    'location': _trimmed(location),
    'description': _trimmed(description),
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  };
}

/// The change set for cancelling a calendar event. The row is retained and
/// frozen.
Map<String, Object?> calendarEventCancelChanges() => <String, Object?>{
  'status': CalendarEventStatus.cancelled.wireValue,
  'updated_at': DateTime.now().toUtc().toIso8601String(),
};

/// Whether [event] overlaps the half-open window `[from, to)`.
bool calendarEventOverlapsWindow(
  CalendarEvent event,
  DateTime from,
  DateTime to,
) => event.startsAt.isBefore(to) && from.isBefore(event.endsAt);

/// A minimal projection of a roster shift for the overlay.
///
/// The calendar does not depend on the workforce domain; callers adapt a
/// Module 09 shift into this shape.
@immutable
final class ShiftSlice {
  /// Creates a shift slice.
  const ShiftSlice({
    required this.id,
    required this.label,
    required this.startsAt,
    required this.endsAt,
    this.detail,
  });

  /// Shift identifier.
  final String id;

  /// Human-readable label.
  final String label;

  /// Cover start, UTC.
  final DateTime startsAt;

  /// Cover end, UTC.
  final DateTime endsAt;

  /// Optional detail (ward, category, headcount).
  final String? detail;

  /// Whether the shift overlaps the half-open window `[from, to)`.
  bool overlapsWindow(DateTime from, DateTime to) =>
      startsAt.isBefore(to) && from.isBefore(endsAt);
}

/// One day's schedule: institutional events and the roster cover that falls on
/// it.
@immutable
final class CalendarDayOverlay {
  /// Creates a day overlay.
  const CalendarDayOverlay({
    required this.date,
    required this.events,
    required this.shifts,
  });

  /// The day, as UTC midnight.
  final DateTime date;

  /// Institutional events touching the day, in start order.
  final List<CalendarEvent> events;

  /// Roster shifts touching the day, in start order.
  final List<ShiftSlice> shifts;

  /// Whether the day has neither events nor shifts.
  bool get isEmpty => events.isEmpty && shifts.isEmpty;
}

/// Builds the calendar overlay for `[from, to)`: one entry per day that has at
/// least one event or shift, in ascending date order.
List<CalendarDayOverlay> buildCalendarOverlay({
  required List<CalendarEvent> events,
  required List<ShiftSlice> shifts,
  required DateTime from,
  required DateTime to,
}) {
  if (!to.isAfter(from)) {
    return const <CalendarDayOverlay>[];
  }
  final List<CalendarDayOverlay> days = <CalendarDayOverlay>[];
  DateTime day = _dayStart(from);
  while (day.isBefore(to)) {
    final DateTime next = day.add(const Duration(days: 1));
    final List<CalendarEvent> dayEvents =
        events
            .where(
              (CalendarEvent event) =>
                  event.startsAt.isBefore(next) && day.isBefore(event.endsAt),
            )
            .toList(growable: false)
          ..sort(
            (CalendarEvent a, CalendarEvent b) =>
                a.startsAt.compareTo(b.startsAt),
          );
    final List<ShiftSlice> dayShifts =
        shifts
            .where((ShiftSlice shift) => shift.overlapsWindow(day, next))
            .toList(growable: false)
          ..sort(
            (ShiftSlice a, ShiftSlice b) => a.startsAt.compareTo(b.startsAt),
          );
    if (dayEvents.isNotEmpty || dayShifts.isNotEmpty) {
      days.add(
        CalendarDayOverlay(date: day, events: dayEvents, shifts: dayShifts),
      );
    }
    day = next;
  }
  return days;
}

DateTime _dayStart(DateTime value) =>
    DateTime.utc(value.toUtc().year, value.toUtc().month, value.toUtc().day);

String? _trimmed(String? value) {
  final String? trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

DateTime _parse(Object? value) => value is String
    ? DateTime.parse(value).toUtc()
    : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

DateTime? _parseNullable(Object? value) =>
    value is String ? DateTime.parse(value).toUtc() : null;

bool _asBool(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  if (value is String) {
    return value == '1' || value.toLowerCase() == 'true';
  }
  return false;
}
