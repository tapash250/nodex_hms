/// Telemedicine & virtual care entities (Module 22).
///
/// Consultation flow: schedule -> waiting room -> in call -> completed, with
/// cancellation and no-show as the terminal exits. Live vitals overlays are
/// observations taken only while the call is in progress, and a completed
/// consultation is archived with recorded consent; recording media stays in
/// encrypted object storage and only a reference is held here.
// ignore_for_file: sort_constructors_first
library;

import 'package:meta/meta.dart';

/// Media channel of a virtual consultation.
enum TeleChannel {
  audio('audio'),
  video('video');

  const TeleChannel(this.wireValue);

  final String wireValue;

  String get label => switch (this) {
    TeleChannel.audio => 'Audio only',
    TeleChannel.video => 'Video',
  };

  static TeleChannel fromWire(String value) => TeleChannel.values.firstWhere(
    (TeleChannel channel) => channel.wireValue == value,
    orElse: () => TeleChannel.video,
  );
}

/// Lifecycle of a virtual consultation.
enum TeleConsultationStatus {
  scheduled('scheduled'),
  waiting('waiting'),
  inCall('in_call'),
  completed('completed'),
  cancelled('cancelled'),
  noShow('no_show');

  const TeleConsultationStatus(this.wireValue);

  final String wireValue;

  String get label => switch (this) {
    TeleConsultationStatus.scheduled => 'Scheduled',
    TeleConsultationStatus.waiting => 'In waiting room',
    TeleConsultationStatus.inCall => 'In call',
    TeleConsultationStatus.completed => 'Completed',
    TeleConsultationStatus.cancelled => 'Cancelled',
    TeleConsultationStatus.noShow => 'No show',
  };

  bool get isTerminal =>
      this == completed || this == cancelled || this == noShow;

  bool get isScheduled => this == scheduled;

  bool get isWaiting => this == waiting;

  bool get isInCall => this == inCall;

  /// Whether the patient has not yet been admitted, so a no-show is still
  /// possible.
  bool get isPreCall => this == scheduled || this == waiting;

  static TeleConsultationStatus fromWire(String value) =>
      TeleConsultationStatus.values.firstWhere(
        (TeleConsultationStatus status) => status.wireValue == value,
        orElse: () => TeleConsultationStatus.scheduled,
      );
}

/// A scheduled virtual consultation and its call lifecycle.
@immutable
final class TeleConsultation {
  const TeleConsultation({
    required this.id,
    required this.tenantId,
    required this.patientId,
    required this.clinicianId,
    required this.bookedBy,
    required this.visitCode,
    required this.channel,
    required this.status,
    required this.scheduledAt,
    required this.createdAt,
    required this.updatedAt,
    this.encounterId,
    this.reason,
    this.waitingAt,
    this.startedAt,
    this.completedAt,
    this.cancelledAt,
    this.cancellationReason,
    this.noShowAt,
  });

  factory TeleConsultation.fromRow(Map<String, Object?> row) {
    final Object? encounter = row['encounter_id'];
    final Object? reason = row['reason'];
    final Object? waitingAt = row['waiting_at'];
    final Object? startedAt = row['started_at'];
    final Object? completedAt = row['completed_at'];
    final Object? cancelledAt = row['cancelled_at'];
    final Object? cancellationReason = row['cancellation_reason'];
    final Object? noShowAt = row['no_show_at'];
    return TeleConsultation(
      id: row['id']! as String,
      tenantId: row['tenant_id']! as String,
      patientId: row['patient_id']! as String,
      encounterId: encounter is String ? encounter : null,
      clinicianId: row['clinician_id']! as String,
      bookedBy: row['booked_by']! as String,
      visitCode: row['visit_code']! as String,
      channel: TeleChannel.fromWire(row['channel']! as String),
      status: TeleConsultationStatus.fromWire(row['status']! as String),
      reason: reason is String ? reason : null,
      scheduledAt: row['scheduled_at']! as DateTime,
      waitingAt: waitingAt is DateTime ? waitingAt : null,
      startedAt: startedAt is DateTime ? startedAt : null,
      completedAt: completedAt is DateTime ? completedAt : null,
      cancelledAt: cancelledAt is DateTime ? cancelledAt : null,
      cancellationReason: cancellationReason is String
          ? cancellationReason
          : null,
      noShowAt: noShowAt is DateTime ? noShowAt : null,
      createdAt: row['created_at']! as DateTime,
      updatedAt: row['updated_at']! as DateTime,
    );
  }

  final String id;
  final String tenantId;
  final String patientId;
  final String? encounterId;
  final String clinicianId;
  final String bookedBy;
  final String visitCode;
  final TeleChannel channel;
  final TeleConsultationStatus status;
  final String? reason;
  final DateTime scheduledAt;
  final DateTime? waitingAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime? cancelledAt;
  final String? cancellationReason;
  final DateTime? noShowAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isTerminal => status.isTerminal;

  bool get isScheduled => status.isScheduled;

  bool get isWaiting => status.isWaiting;

  bool get isInCall => status.isInCall;

  bool get isPreCall => status.isPreCall;
}

/// A live vitals reading taken while a call is in progress.
@immutable
final class TeleVitalsOverlay {
  const TeleVitalsOverlay({
    required this.id,
    required this.tenantId,
    required this.consultationId,
    required this.observedBy,
    required this.observedAt,
    required this.createdAt,
    required this.updatedAt,
    this.heartRateBpm,
    this.spo2Pct,
    this.temperatureC,
    this.respiratoryRate,
    this.notes,
  });

  factory TeleVitalsOverlay.fromRow(Map<String, Object?> row) {
    final Object? heartRate = row['heart_rate_bpm'];
    final Object? spo2 = row['spo2_pct'];
    final Object? temperature = row['temperature_c'];
    final Object? respiratoryRate = row['respiratory_rate'];
    final Object? notes = row['notes'];
    return TeleVitalsOverlay(
      id: row['id']! as String,
      tenantId: row['tenant_id']! as String,
      consultationId: row['consultation_id']! as String,
      observedBy: row['observed_by']! as String,
      heartRateBpm: heartRate is num ? heartRate.toInt() : null,
      spo2Pct: spo2 is num ? spo2.toDouble() : null,
      temperatureC: temperature is num ? temperature.toDouble() : null,
      respiratoryRate: respiratoryRate is num ? respiratoryRate.toInt() : null,
      notes: notes is String ? notes : null,
      observedAt: row['observed_at']! as DateTime,
      createdAt: row['created_at']! as DateTime,
      updatedAt: row['updated_at']! as DateTime,
    );
  }

  final String id;
  final String tenantId;
  final String consultationId;
  final String observedBy;
  final int? heartRateBpm;
  final double? spo2Pct;
  final double? temperatureC;
  final int? respiratoryRate;
  final String? notes;
  final DateTime observedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
}

/// The retained archive of a completed consultation.
@immutable
final class TeleConsultationArchive {
  const TeleConsultationArchive({
    required this.id,
    required this.tenantId,
    required this.consultationId,
    required this.archivedBy,
    required this.durationSeconds,
    required this.consentRecorded,
    required this.archivedAt,
    required this.createdAt,
    required this.updatedAt,
    this.recordingReference,
    this.transcriptReference,
  });

  factory TeleConsultationArchive.fromRow(Map<String, Object?> row) {
    final Object? recording = row['recording_reference'];
    final Object? transcript = row['transcript_reference'];
    final Object? consent = row['consent_recorded'];
    return TeleConsultationArchive(
      id: row['id']! as String,
      tenantId: row['tenant_id']! as String,
      consultationId: row['consultation_id']! as String,
      archivedBy: row['archived_by']! as String,
      durationSeconds: (row['duration_seconds']! as num).toInt(),
      recordingReference: recording is String ? recording : null,
      transcriptReference: transcript is String ? transcript : null,
      consentRecorded: consent == null || consent == 1 || consent == true,
      archivedAt: row['archived_at']! as DateTime,
      createdAt: row['created_at']! as DateTime,
      updatedAt: row['updated_at']! as DateTime,
    );
  }

  final String id;
  final String tenantId;
  final String consultationId;
  final String archivedBy;
  final int durationSeconds;
  final String? recordingReference;
  final String? transcriptReference;
  final bool consentRecorded;
  final DateTime archivedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
}
