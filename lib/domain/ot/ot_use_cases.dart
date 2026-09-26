/// Operation theatre use cases (Module 19).
///
/// Each write gates on the authorization policy before touching the
/// repository. Scheduling enforces the room conflict check, a case cannot
/// start without a fit pre-op assessment, and completion requires
/// `ot.finalize` plus a post-op record.
library;

import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/ot/ot.dart';
import 'package:nodex_hms/domain/ot/ot_repository.dart';
import 'package:uuid/uuid.dart';

/// Books a theatre slot. Requires `ot.schedule`.
final class ScheduleOtBookingUseCase {
  ScheduleOtBookingUseCase({required this._repository});

  final OtRepository _repository;

  Future<OtBooking> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String patientId,
    required String theatreRoom,
    required String procedureName,
    required DateTime scheduledStart,
    required DateTime scheduledEnd,
    required String surgeonId,
    required String createdBy,
    String? encounterId,
    String? anesthesiologistId,
    OtPriority priority = OtPriority.routine,
  }) async {
    policy.require(NodexPermissions.otSchedule);
    if (theatreRoom.trim().isEmpty) {
      throw const ValidationError(
        message: 'A booking needs a theatre room.',
        code: 'ot_room_required',
      );
    }
    if (procedureName.trim().isEmpty) {
      throw const ValidationError(
        message: 'A booking needs a procedure.',
        code: 'ot_procedure_required',
      );
    }
    if (!scheduledEnd.isAfter(scheduledStart)) {
      throw const ValidationError(
        message: 'A booking must end after it starts.',
        code: 'ot_time_range_invalid',
      );
    }
    final List<OtBooking> room = await _repository.bookingsForRoom(
      theatreRoom.trim(),
    );
    final bool clash = room.any(
      (OtBooking booking) =>
          !booking.isTerminal && booking.overlaps(scheduledStart, scheduledEnd),
    );
    if (clash) {
      throw const ValidationError(
        message: 'The theatre room is already booked for that time.',
        code: 'ot_room_double_booked',
      );
    }
    final DateTime now = DateTime.now().toUtc();
    final OtBooking booking = OtBooking(
      id: const Uuid().v4(),
      tenantId: tenantId,
      patientId: patientId,
      encounterId: encounterId,
      theatreRoom: theatreRoom.trim(),
      procedureName: procedureName.trim(),
      scheduledStart: scheduledStart,
      scheduledEnd: scheduledEnd,
      surgeonId: surgeonId,
      anesthesiologistId: anesthesiologistId,
      status: OtBookingStatus.scheduled,
      priority: priority,
      createdBy: createdBy,
      createdAt: now,
      updatedAt: now,
    );
    return _repository.upsertBooking(booking);
  }
}

/// Records the pre-operative fitness assessment for a booking. Requires
/// `ot.record`. Revising an existing assessment replaces it in place.
final class RecordPreOpAssessmentUseCase {
  RecordPreOpAssessmentUseCase({required this._repository});

  final OtRepository _repository;

  Future<OtPreOpAssessment> call({
    required AuthorizationPolicy policy,
    required OtBooking booking,
    required String assessedBy,
    required OtFitness fitness,
    int? asaClass,
    String? notes,
    DateTime? assessedAt,
  }) async {
    policy.require(NodexPermissions.otRecord);
    if (booking.isTerminal) {
      throw const AuthorizationError(
        message: 'Closed theatre bookings cannot receive an assessment.',
        code: 'ot_booking_closed',
      );
    }
    if (asaClass != null && (asaClass < 1 || asaClass > 6)) {
      throw const ValidationError(
        message: 'ASA class must be between 1 and 6.',
        code: 'ot_asa_class_invalid',
      );
    }
    if (notes != null && notes.trim().isEmpty) {
      throw const ValidationError(
        message: 'Assessment notes cannot be blank.',
        code: 'ot_assessment_notes_invalid',
      );
    }
    final OtPreOpAssessment? existing = await _repository.preOpForBooking(
      booking.id,
    );
    final DateTime now = DateTime.now().toUtc();
    final OtPreOpAssessment assessment = OtPreOpAssessment(
      id: existing?.id ?? const Uuid().v4(),
      tenantId: booking.tenantId,
      bookingId: booking.id,
      patientId: booking.patientId,
      assessedBy: assessedBy,
      assessedAt: assessedAt ?? now,
      fitness: fitness,
      asaClass: asaClass,
      notes: notes?.trim(),
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    return _repository.upsertPreOpAssessment(assessment);
  }
}

/// Starts a scheduled case. Requires `ot.record`. The case must have a
/// recorded pre-op assessment and the patient must be fit for surgery.
final class StartOtBookingUseCase {
  StartOtBookingUseCase({required this._repository});

  final OtRepository _repository;

  Future<OtBooking> call({
    required AuthorizationPolicy policy,
    required OtBooking original,
  }) async {
    policy.require(NodexPermissions.otRecord);
    if (original.isTerminal) {
      throw const AuthorizationError(
        message: 'Closed theatre bookings cannot be started.',
        code: 'ot_booking_closed',
      );
    }
    if (original.status != OtBookingStatus.scheduled) {
      throw const AuthorizationError(
        message: 'This case has already been started.',
        code: 'ot_booking_already_started',
      );
    }
    final OtPreOpAssessment? assessment = await _repository.preOpForBooking(
      original.id,
    );
    if (assessment == null) {
      throw const AuthorizationError(
        message: 'A pre-op assessment is required before starting a case.',
        code: 'ot_preop_required',
      );
    }
    if (!assessment.fitForSurgery) {
      throw const AuthorizationError(
        message: 'The patient is not fit for surgery.',
        code: 'ot_patient_not_fit',
      );
    }
    final DateTime now = DateTime.now().toUtc();
    return _repository.upsertBooking(
      OtBooking(
        id: original.id,
        tenantId: original.tenantId,
        patientId: original.patientId,
        encounterId: original.encounterId,
        theatreRoom: original.theatreRoom,
        procedureName: original.procedureName,
        scheduledStart: original.scheduledStart,
        scheduledEnd: original.scheduledEnd,
        surgeonId: original.surgeonId,
        anesthesiologistId: original.anesthesiologistId,
        status: OtBookingStatus.inProgress,
        priority: original.priority,
        cancellationReason: original.cancellationReason,
        createdBy: original.createdBy,
        createdAt: original.createdAt,
        updatedAt: now,
      ),
    );
  }
}

/// Records or updates the anesthesia record for a started case. Requires
/// `ot.record`.
final class RecordAnesthesiaUseCase {
  RecordAnesthesiaUseCase({required this._repository});

  final OtRepository _repository;

  Future<OtAnesthesiaRecord> call({
    required AuthorizationPolicy policy,
    required OtBooking booking,
    required String recordedBy,
    required OtAnesthesiaType anesthesiaType,
    String? notes,
    DateTime? startedAt,
    DateTime? endedAt,
  }) async {
    policy.require(NodexPermissions.otRecord);
    _requireStarted(booking);
    final OtAnesthesiaRecord? existing = await _repository.anesthesiaForBooking(
      booking.id,
    );
    final DateTime now = DateTime.now().toUtc();
    final DateTime start = startedAt ?? existing?.startedAt ?? now;
    if (endedAt != null && !endedAt.isAfter(start)) {
      throw const ValidationError(
        message: 'Anesthesia must end after it starts.',
        code: 'ot_anesthesia_time_invalid',
      );
    }
    if (notes != null && notes.trim().isEmpty) {
      throw const ValidationError(
        message: 'Anesthesia notes cannot be blank.',
        code: 'ot_anesthesia_notes_invalid',
      );
    }
    final OtAnesthesiaRecord record = OtAnesthesiaRecord(
      id: existing?.id ?? const Uuid().v4(),
      tenantId: booking.tenantId,
      bookingId: booking.id,
      patientId: booking.patientId,
      anesthesiaType: anesthesiaType,
      recordedBy: recordedBy,
      startedAt: start,
      endedAt: endedAt,
      notes: notes?.trim() ?? existing?.notes,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    return _repository.upsertAnesthesiaRecord(record);
  }

  static void _requireStarted(OtBooking booking) {
    if (booking.isTerminal) {
      throw const AuthorizationError(
        message: 'Closed theatre bookings cannot be documented.',
        code: 'ot_booking_closed',
      );
    }
    if (booking.status != OtBookingStatus.inProgress) {
      throw const AuthorizationError(
        message: 'The case must be started before intra-op records.',
        code: 'ot_booking_not_started',
      );
    }
  }
}

/// Records or updates the procedure log for a started case. Requires
/// `ot.record`.
final class RecordProcedureLogUseCase {
  RecordProcedureLogUseCase({required this._repository});

  final OtRepository _repository;

  Future<OtProcedureLog> call({
    required AuthorizationPolicy policy,
    required OtBooking booking,
    required String performedBy,
    required String procedureName,
    String? findings,
    DateTime? startedAt,
    DateTime? completedAt,
  }) async {
    policy.require(NodexPermissions.otRecord);
    if (booking.isTerminal) {
      throw const AuthorizationError(
        message: 'Closed theatre bookings cannot be documented.',
        code: 'ot_booking_closed',
      );
    }
    if (booking.status != OtBookingStatus.inProgress) {
      throw const AuthorizationError(
        message: 'The case must be started before intra-op records.',
        code: 'ot_booking_not_started',
      );
    }
    if (procedureName.trim().isEmpty) {
      throw const ValidationError(
        message: 'A procedure log needs a procedure.',
        code: 'ot_procedure_required',
      );
    }
    final OtProcedureLog? existing = await _repository.procedureLogForBooking(
      booking.id,
    );
    final DateTime now = DateTime.now().toUtc();
    final DateTime start = startedAt ?? existing?.startedAt ?? now;
    if (completedAt != null && completedAt.isBefore(start)) {
      throw const ValidationError(
        message: 'A procedure cannot complete before it starts.',
        code: 'ot_procedure_time_invalid',
      );
    }
    if (findings != null && findings.trim().isEmpty) {
      throw const ValidationError(
        message: 'Findings cannot be blank.',
        code: 'ot_procedure_findings_invalid',
      );
    }
    final OtProcedureLog log = OtProcedureLog(
      id: existing?.id ?? const Uuid().v4(),
      tenantId: booking.tenantId,
      bookingId: booking.id,
      patientId: booking.patientId,
      procedureName: procedureName.trim(),
      performedBy: performedBy,
      startedAt: start,
      completedAt: completedAt,
      findings: findings?.trim() ?? existing?.findings,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    return _repository.upsertProcedureLog(log);
  }
}

/// Records or updates the post-op recovery record for a started case.
/// Requires `ot.record`.
final class RecordPostOpUseCase {
  RecordPostOpUseCase({required this._repository});

  final OtRepository _repository;

  Future<OtPostOpRecord> call({
    required AuthorizationPolicy policy,
    required OtBooking booking,
    required String recordedBy,
    required OtPostOpCondition condition,
    int? painScore,
    String? complications,
    String? notes,
    DateTime? recordedAt,
  }) async {
    policy.require(NodexPermissions.otRecord);
    if (booking.isTerminal) {
      throw const AuthorizationError(
        message: 'Closed theatre bookings cannot be documented.',
        code: 'ot_booking_closed',
      );
    }
    if (booking.status != OtBookingStatus.inProgress) {
      throw const AuthorizationError(
        message: 'The case must be started before post-op records.',
        code: 'ot_booking_not_started',
      );
    }
    if (painScore != null && (painScore < 0 || painScore > 10)) {
      throw const ValidationError(
        message: 'Pain score must be between 0 and 10.',
        code: 'ot_pain_score_invalid',
      );
    }
    if (complications != null && complications.trim().isEmpty) {
      throw const ValidationError(
        message: 'Complications cannot be blank.',
        code: 'ot_complications_invalid',
      );
    }
    if (notes != null && notes.trim().isEmpty) {
      throw const ValidationError(
        message: 'Post-op notes cannot be blank.',
        code: 'ot_postop_notes_invalid',
      );
    }
    final OtPostOpRecord? existing = await _repository.postOpForBooking(
      booking.id,
    );
    final DateTime now = DateTime.now().toUtc();
    final OtPostOpRecord record = OtPostOpRecord(
      id: existing?.id ?? const Uuid().v4(),
      tenantId: booking.tenantId,
      bookingId: booking.id,
      patientId: booking.patientId,
      recordedBy: recordedBy,
      recordedAt: recordedAt ?? now,
      condition: condition,
      painScore: painScore,
      complications: complications?.trim(),
      notes: notes?.trim(),
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    return _repository.upsertPostOpRecord(record);
  }
}

/// Completes a started case. Requires `ot.finalize` and a post-op record.
final class CompleteOtBookingUseCase {
  CompleteOtBookingUseCase({required this._repository});

  final OtRepository _repository;

  Future<OtBooking> call({
    required AuthorizationPolicy policy,
    required OtBooking original,
  }) async {
    policy.require(NodexPermissions.otFinalize);
    if (original.isTerminal) {
      throw const AuthorizationError(
        message: 'Closed theatre bookings cannot be completed.',
        code: 'ot_booking_closed',
      );
    }
    if (original.status != OtBookingStatus.inProgress) {
      throw const AuthorizationError(
        message: 'The case must be started before completion.',
        code: 'ot_booking_not_started',
      );
    }
    final OtPostOpRecord? postOp = await _repository.postOpForBooking(
      original.id,
    );
    if (postOp == null) {
      throw const AuthorizationError(
        message: 'A post-op record is required before completing a case.',
        code: 'ot_postop_required',
      );
    }
    final DateTime now = DateTime.now().toUtc();
    return _repository.upsertBooking(
      OtBooking(
        id: original.id,
        tenantId: original.tenantId,
        patientId: original.patientId,
        encounterId: original.encounterId,
        theatreRoom: original.theatreRoom,
        procedureName: original.procedureName,
        scheduledStart: original.scheduledStart,
        scheduledEnd: original.scheduledEnd,
        surgeonId: original.surgeonId,
        anesthesiologistId: original.anesthesiologistId,
        status: OtBookingStatus.completed,
        priority: original.priority,
        cancellationReason: original.cancellationReason,
        createdBy: original.createdBy,
        createdAt: original.createdAt,
        updatedAt: now,
      ),
    );
  }
}

/// Cancels a booking with a reason. Requires `ot.schedule`.
final class CancelOtBookingUseCase {
  CancelOtBookingUseCase({required this._repository});

  final OtRepository _repository;

  Future<OtBooking> call({
    required AuthorizationPolicy policy,
    required OtBooking original,
    required String reason,
  }) async {
    policy.require(NodexPermissions.otSchedule);
    if (original.isTerminal) {
      throw const AuthorizationError(
        message: 'Closed theatre bookings cannot be cancelled.',
        code: 'ot_booking_closed',
      );
    }
    if (reason.trim().isEmpty) {
      throw const ValidationError(
        message: 'Cancelling a booking requires a reason.',
        code: 'ot_cancellation_reason_required',
      );
    }
    final DateTime now = DateTime.now().toUtc();
    return _repository.upsertBooking(
      OtBooking(
        id: original.id,
        tenantId: original.tenantId,
        patientId: original.patientId,
        encounterId: original.encounterId,
        theatreRoom: original.theatreRoom,
        procedureName: original.procedureName,
        scheduledStart: original.scheduledStart,
        scheduledEnd: original.scheduledEnd,
        surgeonId: original.surgeonId,
        anesthesiologistId: original.anesthesiologistId,
        status: OtBookingStatus.cancelled,
        priority: original.priority,
        cancellationReason: reason.trim(),
        createdBy: original.createdBy,
        createdAt: original.createdAt,
        updatedAt: now,
      ),
    );
  }
}
