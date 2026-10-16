/// Institutional calendar repository contract and local implementation
/// (Module 40).
library;

import 'package:nodex_hms/core/errors/error_mapper.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/calendar/calendar.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';
import 'package:uuid/uuid.dart';

abstract interface class CalendarRepository {
  /// Lists events by tenant, ordered by start time. The date window is applied
  /// by the caller via [calendarEventOverlapsWindow]; this returns the
  /// candidate set the tenant holds.
  Future<List<CalendarEvent>> listEvents(
    String tenantId, {
    CalendarEventType? eventType,
    String? facilityId,
    bool includeCancelled = false,
    int limit = 500,
  });
  Future<CalendarEvent?> eventById(String id);
  Future<String> createEvent(Map<String, Object?> row);
  Future<void> updateEvent(String id, Map<String, Object?> changes);
}

final class DefaultCalendarRepository implements CalendarRepository {
  DefaultCalendarRepository({required this._store, required this._logger});

  static const String _module = 'domain.calendar';
  final PatientLocalStore _store;
  final NodexLogger _logger;

  @override
  Future<List<CalendarEvent>> listEvents(
    String tenantId, {
    CalendarEventType? eventType,
    String? facilityId,
    bool includeCancelled = false,
    int limit = 500,
  }) async {
    try {
      final List<String> conditions = <String>['tenant_id = ?'];
      final List<Object?> params = <Object?>[tenantId];
      if (eventType != null) {
        conditions.add('event_type = ?');
        params.add(eventType.wireValue);
      }
      if (facilityId != null) {
        conditions.add('facility_id = ?');
        params.add(facilityId);
      }
      if (!includeCancelled) {
        conditions.add('status = ?');
        params.add(CalendarEventStatus.scheduled.wireValue);
      }
      final String sql =
          'select * from ${LocalTables.calendarEvents} '
          'where ${conditions.join(' and ')} '
          'order by starts_at asc limit ?';
      params.add(limit);
      final List<Map<String, Object?>> rows = await _store.query(sql, params);
      return rows.map(CalendarEvent.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'calendar.listEvents');
    }
  }

  @override
  Future<CalendarEvent?> eventById(String id) async {
    try {
      final Map<String, Object?>? row = await _store.getById(
        LocalTables.calendarEvents,
        id,
      );
      return row == null ? null : CalendarEvent.fromRow(row);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'calendar.eventById');
    }
  }

  @override
  Future<String> createEvent(Map<String, Object?> row) async {
    final String id = (row['id'] as String?) ?? const Uuid().v4();
    try {
      await _store.insert(LocalTables.calendarEvents, <String, Object?>{
        ...row,
        'id': id,
      });
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'calendar.createEvent');
    }
  }

  @override
  Future<void> updateEvent(String id, Map<String, Object?> changes) async {
    try {
      await _store.update(LocalTables.calendarEvents, id, changes);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'calendar.updateEvent');
    }
  }

  NodexError _mapped(Object error, StackTrace stackTrace, String operation) {
    if (error is NodexError) {
      return error;
    }
    final NodexError mapped = NodexErrorMapper.map(error, operation: operation);
    _logger.error(
      _module,
      'Local store operation failed.',
      operation: operation,
      errorCode: mapped.code,
      stackTrace: stackTrace,
    );
    return mapped;
  }
}
