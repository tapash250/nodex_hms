/// Telemedicine workflow use cases (Module 22).
///
/// Each write gates on the authorization policy before touching the
/// repository. The consultation lifecycle requires `tele_consultation.write`,
/// live vitals overlays require `tele_vitals.record`, and archiving a
/// completed visit with recorded consent requires `tele_archive.write`.
library;

import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/telemedicine/telemedicine.dart';
import 'package:nodex_hms/domain/telemedicine/telemedicine_repository.dart';
import 'package:uuid/uuid.dart';

/// Schedules a virtual consultation. Requires `tele_consultation.write`.
final class ScheduleTeleConsultationUseCase {
  ScheduleTeleConsultationUseCase({required this._repository});

  final TelemedicineRepository _repository;

  Future<TeleConsultation> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String patientId,
    required String clinicianId,
    required String bookedBy,
    required String visitCode,
    required TeleChannel channel,
    required DateTime scheduledAt,
    String? encounterId,
    String? reason,
  }) async {
    policy.require(NodexPermissions.teleConsultationWrite);
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (patientId.isEmpty) {
      fieldErrors['patient_id'] = 'Patient is required.';
    }
    if (clinicianId.isEmpty) {
      fieldErrors['clinician_id'] = 'Clinician is required.';
    }
    if (bookedBy.isEmpty) {
      fieldErrors['booked_by'] = 'Booking user is required.';
    }
    if (visitCode.trim().isEmpty) {
      fieldErrors['visit_code'] = 'Visit code is required.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Telemedicine consultation failed validation.',
        fieldErrors: fieldErrors,
        code: 'tele_consultation_invalid',
      );
    }
    final DateTime now = DateTime.now().toUtc();
    final String? cleanReason = reason?.trim();
    final TeleConsultation consultation = TeleConsultation(
      id: const Uuid().v4(),
      tenantId: tenantId,
      patientId: patientId,
      encounterId: encounterId,
      clinicianId: clinicianId,
      bookedBy: bookedBy,
      visitCode: visitCode.trim(),
      channel: channel,
      status: TeleConsultationStatus.scheduled,
      reason: cleanReason == null || cleanReason.isEmpty ? null : cleanReason,
      scheduledAt: scheduledAt.toUtc(),
      createdAt: now,
      updatedAt: now,
    );
    return _repository.upsertConsultation(consultation);
  }
}

/// Admits a patient to the virtual waiting room. Requires
/// `tele_consultation.write`.
final class AdmitToWaitingRoomUseCase {
  AdmitToWaitingRoomUseCase({required this._repository});

  final TelemedicineRepository _repository;

  Future<TeleConsultation> call({
    required AuthorizationPolicy policy,
    required TeleConsultation original,
  }) async {
    policy.require(NodexPermissions.teleConsultationWrite);
    if (!original.isScheduled) {
      throw const AuthorizationError(
        message: 'Only a scheduled consultation can enter the waiting room.',
        code: 'tele_consultation_not_scheduled',
      );
    }
    final DateTime now = DateTime.now().toUtc();
    return _repository.upsertConsultation(
      _transition(
        original,
        TeleConsultationStatus.waiting,
        waitingAt: now,
        updatedAt: now,
      ),
    );
  }
}

/// Starts the call from the waiting room. Requires `tele_consultation.write`.
final class StartTeleConsultationUseCase {
  StartTeleConsultationUseCase({required this._repository});

  final TelemedicineRepository _repository;

  Future<TeleConsultation> call({
    required AuthorizationPolicy policy,
    required TeleConsultation original,
  }) async {
    policy.require(NodexPermissions.teleConsultationWrite);
    if (!original.isWaiting) {
      throw const AuthorizationError(
        message: 'A call starts only from the waiting room.',
        code: 'tele_consultation_not_waiting',
      );
    }
    final DateTime now = DateTime.now().toUtc();
    return _repository.upsertConsultation(
      _transition(
        original,
        TeleConsultationStatus.inCall,
        waitingAt: original.waitingAt,
        startedAt: now,
        updatedAt: now,
      ),
    );
  }
}

/// Completes an in-call consultation. Requires `tele_consultation.write`.
final class CompleteTeleConsultationUseCase {
  CompleteTeleConsultationUseCase({required this._repository});

  final TelemedicineRepository _repository;

  Future<TeleConsultation> call({
    required AuthorizationPolicy policy,
    required TeleConsultation original,
  }) async {
    policy.require(NodexPermissions.teleConsultationWrite);
    if (!original.isInCall) {
      throw const AuthorizationError(
        message: 'Only an in-call consultation can be completed.',
        code: 'tele_consultation_not_in_call',
      );
    }
    final DateTime now = DateTime.now().toUtc();
    return _repository.upsertConsultation(
      _transition(
        original,
        TeleConsultationStatus.completed,
        waitingAt: original.waitingAt,
        startedAt: original.startedAt,
        completedAt: now,
        updatedAt: now,
      ),
    );
  }
}

/// Records a patient no-show before the call starts. Requires
/// `tele_consultation.write`.
final class MarkTeleNoShowUseCase {
  MarkTeleNoShowUseCase({required this._repository});

  final TelemedicineRepository _repository;

  Future<TeleConsultation> call({
    required AuthorizationPolicy policy,
    required TeleConsultation original,
  }) async {
    policy.require(NodexPermissions.teleConsultationWrite);
    if (original.isTerminal) {
      throw const AuthorizationError(
        message: 'Closed consultations cannot become a no-show.',
        code: 'tele_consultation_closed',
      );
    }
    if (!original.isPreCall) {
      throw const AuthorizationError(
        message: 'A no-show is recorded only before the call starts.',
        code: 'tele_consultation_in_call',
      );
    }
    final DateTime now = DateTime.now().toUtc();
    return _repository.upsertConsultation(
      _transition(
        original,
        TeleConsultationStatus.noShow,
        waitingAt: original.waitingAt,
        noShowAt: now,
        updatedAt: now,
      ),
    );
  }
}

/// Cancels a consultation with a reason. Requires `tele_consultation.write`.
final class CancelTeleConsultationUseCase {
  CancelTeleConsultationUseCase({required this._repository});

  final TelemedicineRepository _repository;

  Future<TeleConsultation> call({
    required AuthorizationPolicy policy,
    required TeleConsultation original,
    required String reason,
  }) async {
    policy.require(NodexPermissions.teleConsultationWrite);
    if (original.isTerminal) {
      throw const AuthorizationError(
        message: 'Closed consultations cannot be cancelled.',
        code: 'tele_consultation_closed',
      );
    }
    if (reason.trim().isEmpty) {
      throw const ValidationError(
        message: 'Cancelling a telemedicine consultation requires a reason.',
        code: 'tele_cancellation_reason_required',
      );
    }
    final DateTime now = DateTime.now().toUtc();
    return _repository.upsertConsultation(
      _transition(
        original,
        TeleConsultationStatus.cancelled,
        waitingAt: original.waitingAt,
        startedAt: original.startedAt,
        cancelledAt: now,
        cancellationReason: reason.trim(),
        updatedAt: now,
      ),
    );
  }
}

/// Records a live vitals reading during a call. Requires `tele_vitals.record`.
final class RecordTeleVitalsOverlayUseCase {
  RecordTeleVitalsOverlayUseCase({required this._repository});

  final TelemedicineRepository _repository;

  Future<TeleVitalsOverlay> call({
    required AuthorizationPolicy policy,
    required TeleConsultation consultation,
    required String observedBy,
    int? heartRateBpm,
    double? spo2Pct,
    double? temperatureC,
    int? respiratoryRate,
    String? notes,
  }) async {
    policy.require(NodexPermissions.teleVitalsRecord);
    if (!consultation.isInCall) {
      throw const AuthorizationError(
        message: 'Live vitals are observed only while the call is in progress.',
        code: 'tele_consultation_not_in_call',
      );
    }
    final Map<String, String> fieldErrors = <String, String>{};
    if (heartRateBpm != null && (heartRateBpm < 20 || heartRateBpm > 250)) {
      fieldErrors['heart_rate_bpm'] = 'Heart rate must be 20 to 250 bpm.';
    }
    if (spo2Pct != null && (spo2Pct < 50 || spo2Pct > 100)) {
      fieldErrors['spo2_pct'] = 'SpO2 must be 50 to 100 percent.';
    }
    if (temperatureC != null && (temperatureC < 30 || temperatureC > 45)) {
      fieldErrors['temperature_c'] = 'Temperature must be 30 to 45 degrees.';
    }
    if (respiratoryRate != null &&
        (respiratoryRate < 4 || respiratoryRate > 60)) {
      fieldErrors['respiratory_rate'] = 'Respiratory rate must be 4 to 60.';
    }
    final bool hasReading =
        heartRateBpm != null ||
        spo2Pct != null ||
        temperatureC != null ||
        respiratoryRate != null;
    if (!hasReading) {
      fieldErrors['readings'] = 'Record at least one observation.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Vitals overlay failed validation.',
        fieldErrors: fieldErrors,
        code: 'tele_vitals_invalid',
      );
    }
    final DateTime now = DateTime.now().toUtc();
    final String? cleanNotes = notes?.trim();
    final TeleVitalsOverlay overlay = TeleVitalsOverlay(
      id: const Uuid().v4(),
      tenantId: consultation.tenantId,
      consultationId: consultation.id,
      observedBy: observedBy,
      heartRateBpm: heartRateBpm,
      spo2Pct: spo2Pct,
      temperatureC: temperatureC,
      respiratoryRate: respiratoryRate,
      notes: cleanNotes == null || cleanNotes.isEmpty ? null : cleanNotes,
      observedAt: now,
      createdAt: now,
      updatedAt: now,
    );
    return _repository.upsertOverlay(overlay);
  }
}

/// Archives a completed consultation. Requires `tele_archive.write`.
final class ArchiveTeleConsultationUseCase {
  ArchiveTeleConsultationUseCase({required this._repository});

  final TelemedicineRepository _repository;

  Future<TeleConsultationArchive> call({
    required AuthorizationPolicy policy,
    required TeleConsultation consultation,
    required String archivedBy,
    required int durationSeconds,
    required bool consentRecorded,
    String? recordingReference,
    String? transcriptReference,
  }) async {
    policy.require(NodexPermissions.teleArchiveWrite);
    if (consultation.status != TeleConsultationStatus.completed) {
      throw const AuthorizationError(
        message: 'Only a completed consultation can be archived.',
        code: 'tele_consultation_not_completed',
      );
    }
    if (!consentRecorded) {
      throw const ValidationError(
        message: 'Archiving requires recorded patient consent.',
        code: 'tele_consent_required',
      );
    }
    if (durationSeconds <= 0 || durationSeconds > 28800) {
      throw const ValidationError(
        message: 'Call duration must be 1 to 28800 seconds.',
        fieldErrors: <String, String>{
          'duration_seconds': 'Expected 1 to 28800.',
        },
        code: 'tele_archive_invalid',
      );
    }
    final TeleConsultationArchive? existing = await _repository
        .archiveForConsultation(consultation.id);
    if (existing != null) {
      throw const AuthorizationError(
        message: 'This consultation is already archived.',
        code: 'tele_archive_exists',
      );
    }
    final DateTime now = DateTime.now().toUtc();
    final String? recording = recordingReference?.trim();
    final String? transcript = transcriptReference?.trim();
    final TeleConsultationArchive archive = TeleConsultationArchive(
      id: const Uuid().v4(),
      tenantId: consultation.tenantId,
      consultationId: consultation.id,
      archivedBy: archivedBy,
      durationSeconds: durationSeconds,
      recordingReference: recording == null || recording.isEmpty
          ? null
          : recording,
      transcriptReference: transcript == null || transcript.isEmpty
          ? null
          : transcript,
      consentRecorded: true,
      archivedAt: now,
      createdAt: now,
      updatedAt: now,
    );
    return _repository.upsertArchive(archive);
  }
}

/// Copies a consultation forward with a new status, preserving every other
/// field so a transition never drops clinical context.
TeleConsultation _transition(
  TeleConsultation original,
  TeleConsultationStatus status, {
  DateTime? waitingAt,
  DateTime? startedAt,
  DateTime? completedAt,
  DateTime? cancelledAt,
  String? cancellationReason,
  DateTime? noShowAt,
  required DateTime updatedAt,
}) => TeleConsultation(
  id: original.id,
  tenantId: original.tenantId,
  patientId: original.patientId,
  encounterId: original.encounterId,
  clinicianId: original.clinicianId,
  bookedBy: original.bookedBy,
  visitCode: original.visitCode,
  channel: original.channel,
  status: status,
  reason: original.reason,
  scheduledAt: original.scheduledAt,
  waitingAt: waitingAt,
  startedAt: startedAt,
  completedAt: completedAt,
  cancelledAt: cancelledAt,
  cancellationReason: cancellationReason,
  noShowAt: noShowAt,
  createdAt: original.createdAt,
  updatedAt: updatedAt,
);
