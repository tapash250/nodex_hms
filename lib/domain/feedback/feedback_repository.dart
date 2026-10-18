/// Patient feedback and grievance repository contract and local implementation
/// (Module 36).
library;

import 'package:nodex_hms/core/errors/error_mapper.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/feedback/feedback.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';
import 'package:uuid/uuid.dart';

abstract interface class FeedbackRepository {
  /// Lists survey responses, newest first, optionally for one status.
  Future<List<FeedbackSurvey>> listSurveys(
    String tenantId, {
    String? status,
    int limit = 500,
  });
  Future<FeedbackSurvey?> surveyById(String id);
  Future<String> registerSurvey(Map<String, Object?> row);
  Future<void> updateSurvey(String id, Map<String, Object?> changes);

  /// Lists grievances, newest received first, optionally for one status or
  /// department.
  Future<List<FeedbackComplaint>> listComplaints(
    String tenantId, {
    String? status,
    String? departmentId,
    int limit = 500,
  });
  Future<FeedbackComplaint?> complaintById(String id);
  Future<String> registerComplaint(Map<String, Object?> row);
  Future<void> updateComplaint(String id, Map<String, Object?> changes);

  /// Lists the routing history of one grievance, oldest first.
  Future<List<ComplaintRoutingEvent>> listRoutingEvents(
    String tenantId, {
    String? complaintId,
    int limit = 500,
  });
  Future<String> appendRoutingEvent(Map<String, Object?> row);
}

final class DefaultFeedbackRepository implements FeedbackRepository {
  DefaultFeedbackRepository({required this._store, required this._logger});

  static const String _module = 'domain.feedback';
  final PatientLocalStore _store;
  final NodexLogger _logger;

  @override
  Future<List<FeedbackSurvey>> listSurveys(
    String tenantId, {
    String? status,
    int limit = 500,
  }) async {
    try {
      final List<String> conditions = <String>['tenant_id = ?'];
      final List<Object?> params = <Object?>[tenantId];
      if (status != null) {
        conditions.add('status = ?');
        params.add(status);
      }
      final String sql =
          'select * from ${LocalTables.feedbackSurveys} '
          'where ${conditions.join(' and ')} '
          'order by recorded_at desc limit ?';
      params.add(limit);
      final List<Map<String, Object?>> rows = await _store.query(sql, params);
      return rows.map(FeedbackSurvey.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'feedback.listSurveys');
    }
  }

  @override
  Future<FeedbackSurvey?> surveyById(String id) async {
    try {
      final Map<String, Object?>? row = await _store.getById(
        LocalTables.feedbackSurveys,
        id,
      );
      return row == null ? null : FeedbackSurvey.fromRow(row);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'feedback.surveyById');
    }
  }

  @override
  Future<String> registerSurvey(Map<String, Object?> row) async {
    final String id = (row['id'] as String?) ?? const Uuid().v4();
    try {
      await _store.insert(LocalTables.feedbackSurveys, <String, Object?>{
        ...row,
        'id': id,
      });
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'feedback.registerSurvey');
    }
  }

  @override
  Future<void> updateSurvey(String id, Map<String, Object?> changes) async {
    try {
      await _store.update(LocalTables.feedbackSurveys, id, changes);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'feedback.updateSurvey');
    }
  }

  @override
  Future<List<FeedbackComplaint>> listComplaints(
    String tenantId, {
    String? status,
    String? departmentId,
    int limit = 500,
  }) async {
    try {
      final List<String> conditions = <String>['tenant_id = ?'];
      final List<Object?> params = <Object?>[tenantId];
      if (status != null) {
        conditions.add('status = ?');
        params.add(status);
      }
      if (departmentId != null) {
        conditions.add('routed_department_id = ?');
        params.add(departmentId);
      }
      final String sql =
          'select * from ${LocalTables.feedbackComplaints} '
          'where ${conditions.join(' and ')} '
          'order by received_at desc limit ?';
      params.add(limit);
      final List<Map<String, Object?>> rows = await _store.query(sql, params);
      return rows.map(FeedbackComplaint.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'feedback.listComplaints');
    }
  }

  @override
  Future<FeedbackComplaint?> complaintById(String id) async {
    try {
      final Map<String, Object?>? row = await _store.getById(
        LocalTables.feedbackComplaints,
        id,
      );
      return row == null ? null : FeedbackComplaint.fromRow(row);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'feedback.complaintById');
    }
  }

  @override
  Future<String> registerComplaint(Map<String, Object?> row) async {
    final String id = (row['id'] as String?) ?? const Uuid().v4();
    try {
      await _store.insert(LocalTables.feedbackComplaints, <String, Object?>{
        ...row,
        'id': id,
      });
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'feedback.registerComplaint');
    }
  }

  @override
  Future<void> updateComplaint(String id, Map<String, Object?> changes) async {
    try {
      await _store.update(LocalTables.feedbackComplaints, id, changes);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'feedback.updateComplaint');
    }
  }

  @override
  Future<List<ComplaintRoutingEvent>> listRoutingEvents(
    String tenantId, {
    String? complaintId,
    int limit = 500,
  }) async {
    try {
      final List<String> conditions = <String>['tenant_id = ?'];
      final List<Object?> params = <Object?>[tenantId];
      if (complaintId != null) {
        conditions.add('complaint_id = ?');
        params.add(complaintId);
      }
      final String sql =
          'select * from ${LocalTables.complaintRoutingEvents} '
          'where ${conditions.join(' and ')} '
          'order by occurred_at asc limit ?';
      params.add(limit);
      final List<Map<String, Object?>> rows = await _store.query(sql, params);
      return rows.map(ComplaintRoutingEvent.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'feedback.listRoutingEvents');
    }
  }

  @override
  Future<String> appendRoutingEvent(Map<String, Object?> row) async {
    final String id = (row['id'] as String?) ?? const Uuid().v4();
    try {
      await _store.insert(LocalTables.complaintRoutingEvents, <String, Object?>{
        ...row,
        'id': id,
      });
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'feedback.appendRoutingEvent');
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
