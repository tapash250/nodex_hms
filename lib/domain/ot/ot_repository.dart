/// Operation theatre repository contract and PowerSync-backed implementation
/// (Module 19).
library;

import 'package:nodex_hms/core/errors/error_mapper.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/ot/ot.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';

/// Read and write access to theatre bookings and their per-case records.
abstract interface class OtRepository {
  Future<OtBooking?> bookingById(String id);

  Future<List<OtBooking>> bookingsForPatient(String patientId);

  Future<List<OtBooking>> bookingsForRoom(String theatreRoom);

  Future<List<OtBooking>> allBookings();

  Future<OtBooking> upsertBooking(OtBooking booking);

  Future<OtPreOpAssessment?> preOpForBooking(String bookingId);

  Future<OtPreOpAssessment> upsertPreOpAssessment(OtPreOpAssessment assessment);

  Future<OtAnesthesiaRecord?> anesthesiaForBooking(String bookingId);

  Future<OtAnesthesiaRecord> upsertAnesthesiaRecord(OtAnesthesiaRecord record);

  Future<OtProcedureLog?> procedureLogForBooking(String bookingId);

  Future<OtProcedureLog> upsertProcedureLog(OtProcedureLog log);

  Future<OtPostOpRecord?> postOpForBooking(String bookingId);

  Future<OtPostOpRecord> upsertPostOpRecord(OtPostOpRecord record);
}

/// Default repository over the encrypted local projection.
final class DefaultOtRepository implements OtRepository {
  const DefaultOtRepository({required this._store, required this._logger});

  static const String _module = 'domain.ot';

  final PatientLocalStore _store;
  final NodexLogger _logger;

  @override
  Future<OtBooking?> bookingById(String id) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select * from ${LocalTables.otBookings} where id = ?',
        <Object?>[id],
      );
      if (rows.isEmpty) return null;
      return OtBooking.fromRow(rows.first);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'ot.bookingById');
    }
  }

  @override
  Future<List<OtBooking>> bookingsForPatient(String patientId) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select * from ${LocalTables.otBookings} where patient_id = ? '
        'order by scheduled_start desc',
        <Object?>[patientId],
      );
      return rows.map(OtBooking.fromRow).toList();
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'ot.bookingsForPatient');
    }
  }

  @override
  Future<List<OtBooking>> bookingsForRoom(String theatreRoom) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select * from ${LocalTables.otBookings} where theatre_room = ? '
        'order by scheduled_start',
        <Object?>[theatreRoom],
      );
      return rows.map(OtBooking.fromRow).toList();
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'ot.bookingsForRoom');
    }
  }

  @override
  Future<List<OtBooking>> allBookings() async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select * from ${LocalTables.otBookings} order by scheduled_start',
        const <Object?>[],
      );
      return rows.map(OtBooking.fromRow).toList();
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'ot.allBookings');
    }
  }

  @override
  Future<OtBooking> upsertBooking(OtBooking booking) async {
    try {
      final Map<String, Object?>? existing = await _store.getById(
        LocalTables.otBookings,
        booking.id,
      );
      final Map<String, Object?> changes = <String, Object?>{
        'patient_id': booking.patientId,
        'encounter_id': booking.encounterId,
        'theatre_room': booking.theatreRoom,
        'procedure_name': booking.procedureName,
        'scheduled_start': booking.scheduledStart,
        'scheduled_end': booking.scheduledEnd,
        'surgeon_id': booking.surgeonId,
        'anesthesiologist_id': booking.anesthesiologistId,
        'status': booking.status.wireValue,
        'priority': booking.priority.wireValue,
        'cancellation_reason': booking.cancellationReason,
        'updated_at': booking.updatedAt,
      };
      if (existing == null) {
        await _store.insert(LocalTables.otBookings, <String, Object?>{
          ...changes,
          'id': booking.id,
          'tenant_id': booking.tenantId,
          'created_by': booking.createdBy,
          'created_at': booking.createdAt,
        });
      } else {
        await _store.update(LocalTables.otBookings, booking.id, changes);
      }
      return booking;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'ot.upsertBooking');
    }
  }

  @override
  Future<OtPreOpAssessment?> preOpForBooking(String bookingId) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select * from ${LocalTables.otPreOpAssessments} where booking_id = ?',
        <Object?>[bookingId],
      );
      if (rows.isEmpty) return null;
      return OtPreOpAssessment.fromRow(rows.first);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'ot.preOpForBooking');
    }
  }

  @override
  Future<OtPreOpAssessment> upsertPreOpAssessment(
    OtPreOpAssessment assessment,
  ) async {
    try {
      final Map<String, Object?>? existing = await _store.getById(
        LocalTables.otPreOpAssessments,
        assessment.id,
      );
      final Map<String, Object?> changes = <String, Object?>{
        'booking_id': assessment.bookingId,
        'patient_id': assessment.patientId,
        'assessed_by': assessment.assessedBy,
        'assessed_at': assessment.assessedAt,
        'fitness': assessment.fitness.wireValue,
        'asa_class': assessment.asaClass,
        'notes': assessment.notes,
        'updated_at': assessment.updatedAt,
      };
      if (existing == null) {
        await _store.insert(LocalTables.otPreOpAssessments, <String, Object?>{
          ...changes,
          'id': assessment.id,
          'tenant_id': assessment.tenantId,
          'created_at': assessment.createdAt,
        });
      } else {
        await _store.update(
          LocalTables.otPreOpAssessments,
          assessment.id,
          changes,
        );
      }
      return assessment;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'ot.upsertPreOpAssessment');
    }
  }

  @override
  Future<OtAnesthesiaRecord?> anesthesiaForBooking(String bookingId) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select * from ${LocalTables.otAnesthesiaRecords} where booking_id = ?',
        <Object?>[bookingId],
      );
      if (rows.isEmpty) return null;
      return OtAnesthesiaRecord.fromRow(rows.first);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'ot.anesthesiaForBooking');
    }
  }

  @override
  Future<OtAnesthesiaRecord> upsertAnesthesiaRecord(
    OtAnesthesiaRecord record,
  ) async {
    try {
      final Map<String, Object?>? existing = await _store.getById(
        LocalTables.otAnesthesiaRecords,
        record.id,
      );
      final Map<String, Object?> changes = <String, Object?>{
        'booking_id': record.bookingId,
        'patient_id': record.patientId,
        'anesthesia_type': record.anesthesiaType.wireValue,
        'recorded_by': record.recordedBy,
        'started_at': record.startedAt,
        'ended_at': record.endedAt,
        'notes': record.notes,
        'updated_at': record.updatedAt,
      };
      if (existing == null) {
        await _store.insert(LocalTables.otAnesthesiaRecords, <String, Object?>{
          ...changes,
          'id': record.id,
          'tenant_id': record.tenantId,
          'created_at': record.createdAt,
        });
      } else {
        await _store.update(
          LocalTables.otAnesthesiaRecords,
          record.id,
          changes,
        );
      }
      return record;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'ot.upsertAnesthesiaRecord');
    }
  }

  @override
  Future<OtProcedureLog?> procedureLogForBooking(String bookingId) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select * from ${LocalTables.otProcedureLogs} where booking_id = ?',
        <Object?>[bookingId],
      );
      if (rows.isEmpty) return null;
      return OtProcedureLog.fromRow(rows.first);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'ot.procedureLogForBooking');
    }
  }

  @override
  Future<OtProcedureLog> upsertProcedureLog(OtProcedureLog log) async {
    try {
      final Map<String, Object?>? existing = await _store.getById(
        LocalTables.otProcedureLogs,
        log.id,
      );
      final Map<String, Object?> changes = <String, Object?>{
        'booking_id': log.bookingId,
        'patient_id': log.patientId,
        'procedure_name': log.procedureName,
        'performed_by': log.performedBy,
        'started_at': log.startedAt,
        'completed_at': log.completedAt,
        'findings': log.findings,
        'updated_at': log.updatedAt,
      };
      if (existing == null) {
        await _store.insert(LocalTables.otProcedureLogs, <String, Object?>{
          ...changes,
          'id': log.id,
          'tenant_id': log.tenantId,
          'created_at': log.createdAt,
        });
      } else {
        await _store.update(LocalTables.otProcedureLogs, log.id, changes);
      }
      return log;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'ot.upsertProcedureLog');
    }
  }

  @override
  Future<OtPostOpRecord?> postOpForBooking(String bookingId) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select * from ${LocalTables.otPostOpRecords} where booking_id = ?',
        <Object?>[bookingId],
      );
      if (rows.isEmpty) return null;
      return OtPostOpRecord.fromRow(rows.first);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'ot.postOpForBooking');
    }
  }

  @override
  Future<OtPostOpRecord> upsertPostOpRecord(OtPostOpRecord record) async {
    try {
      final Map<String, Object?>? existing = await _store.getById(
        LocalTables.otPostOpRecords,
        record.id,
      );
      final Map<String, Object?> changes = <String, Object?>{
        'booking_id': record.bookingId,
        'patient_id': record.patientId,
        'recorded_by': record.recordedBy,
        'recorded_at': record.recordedAt,
        'condition': record.condition.wireValue,
        'pain_score': record.painScore,
        'complications': record.complications,
        'notes': record.notes,
        'updated_at': record.updatedAt,
      };
      if (existing == null) {
        await _store.insert(LocalTables.otPostOpRecords, <String, Object?>{
          ...changes,
          'id': record.id,
          'tenant_id': record.tenantId,
          'created_at': record.createdAt,
        });
      } else {
        await _store.update(LocalTables.otPostOpRecords, record.id, changes);
      }
      return record;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'ot.upsertPostOpRecord');
    }
  }

  Never _mapped(Object error, StackTrace stackTrace, String operation) {
    if (error is NodexError) throw error;
    final NodexError mapped = NodexErrorMapper.map(error, operation: operation);
    _logger.error(
      _module,
      'Operation theatre repository failure.',
      operation: operation,
      outcome: 'failed',
      errorCode: mapped.code,
      stackTrace: stackTrace,
    );
    throw mapped;
  }
}
