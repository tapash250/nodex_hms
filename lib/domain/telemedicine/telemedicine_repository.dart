/// Telemedicine repository contract and PowerSync-backed implementation
/// (Module 22).
library;

import 'package:nodex_hms/core/errors/error_mapper.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';
import 'package:nodex_hms/domain/telemedicine/telemedicine.dart';

/// Read and write access to consultations, live vitals overlays and archives.
abstract interface class TelemedicineRepository {
  /// One consultation by id, or null.
  Future<TeleConsultation?> consultationById(String id);

  /// Consultations for one patient, newest first.
  Future<List<TeleConsultation>> consultationsForPatient(String patientId);

  /// Every consultation on the device, newest first.
  Future<List<TeleConsultation>> allConsultations();

  /// Inserts or updates a consultation row.
  Future<TeleConsultation> upsertConsultation(TeleConsultation consultation);

  /// Vitals overlays recorded during a consultation, oldest first.
  Future<List<TeleVitalsOverlay>> overlaysForConsultation(
    String consultationId,
  );

  /// Inserts or updates an overlay row.
  Future<TeleVitalsOverlay> upsertOverlay(TeleVitalsOverlay overlay);

  /// The archive of a consultation, or null.
  Future<TeleConsultationArchive?> archiveForConsultation(
    String consultationId,
  );

  /// Inserts or updates an archive row.
  Future<TeleConsultationArchive> upsertArchive(
    TeleConsultationArchive archive,
  );
}

/// Default repository over the encrypted local projection.
final class DefaultTelemedicineRepository implements TelemedicineRepository {
  const DefaultTelemedicineRepository({
    required this._store,
    required this._logger,
  });

  static const String _module = 'domain.telemedicine';

  final PatientLocalStore _store;
  final NodexLogger _logger;

  @override
  Future<TeleConsultation?> consultationById(String id) async {
    try {
      final Map<String, Object?>? row = await _store.getById(
        LocalTables.teleConsultations,
        id,
      );
      return row == null ? null : TeleConsultation.fromRow(row);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'telemedicine.consultationById');
    }
  }

  @override
  Future<List<TeleConsultation>> consultationsForPatient(
    String patientId,
  ) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select * from ${LocalTables.teleConsultations} where patient_id = ? '
        'order by scheduled_at desc',
        <Object?>[patientId],
      );
      return rows.map(TeleConsultation.fromRow).toList();
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'telemedicine.consultationsForPatient');
    }
  }

  @override
  Future<List<TeleConsultation>> allConsultations() async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select * from ${LocalTables.teleConsultations} '
        'order by scheduled_at desc',
        const <Object?>[],
      );
      return rows.map(TeleConsultation.fromRow).toList();
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'telemedicine.allConsultations');
    }
  }

  @override
  Future<TeleConsultation> upsertConsultation(
    TeleConsultation consultation,
  ) async {
    try {
      final Map<String, Object?>? existing = await _store.getById(
        LocalTables.teleConsultations,
        consultation.id,
      );
      final Map<String, Object?> changes = <String, Object?>{
        'patient_id': consultation.patientId,
        'encounter_id': consultation.encounterId,
        'clinician_id': consultation.clinicianId,
        'booked_by': consultation.bookedBy,
        'visit_code': consultation.visitCode,
        'channel': consultation.channel.wireValue,
        'status': consultation.status.wireValue,
        'reason': consultation.reason,
        'scheduled_at': consultation.scheduledAt,
        'waiting_at': consultation.waitingAt,
        'started_at': consultation.startedAt,
        'completed_at': consultation.completedAt,
        'cancelled_at': consultation.cancelledAt,
        'cancellation_reason': consultation.cancellationReason,
        'no_show_at': consultation.noShowAt,
        'updated_at': consultation.updatedAt,
      };
      if (existing == null) {
        await _store.insert(LocalTables.teleConsultations, <String, Object?>{
          ...changes,
          'id': consultation.id,
          'tenant_id': consultation.tenantId,
          'created_at': consultation.createdAt,
        });
      } else {
        await _store.update(
          LocalTables.teleConsultations,
          consultation.id,
          changes,
        );
      }
      return consultation;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'telemedicine.upsertConsultation');
    }
  }

  @override
  Future<List<TeleVitalsOverlay>> overlaysForConsultation(
    String consultationId,
  ) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select * from ${LocalTables.teleVitalsOverlays} '
        'where consultation_id = ? order by observed_at asc',
        <Object?>[consultationId],
      );
      return rows.map(TeleVitalsOverlay.fromRow).toList();
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'telemedicine.overlaysForConsultation');
    }
  }

  @override
  Future<TeleVitalsOverlay> upsertOverlay(TeleVitalsOverlay overlay) async {
    try {
      final Map<String, Object?>? existing = await _store.getById(
        LocalTables.teleVitalsOverlays,
        overlay.id,
      );
      final Map<String, Object?> changes = <String, Object?>{
        'consultation_id': overlay.consultationId,
        'observed_by': overlay.observedBy,
        'heart_rate_bpm': overlay.heartRateBpm,
        'spo2_pct': overlay.spo2Pct,
        'temperature_c': overlay.temperatureC,
        'respiratory_rate': overlay.respiratoryRate,
        'notes': overlay.notes,
        'observed_at': overlay.observedAt,
        'updated_at': overlay.updatedAt,
      };
      if (existing == null) {
        await _store.insert(LocalTables.teleVitalsOverlays, <String, Object?>{
          ...changes,
          'id': overlay.id,
          'tenant_id': overlay.tenantId,
          'created_at': overlay.createdAt,
        });
      } else {
        await _store.update(
          LocalTables.teleVitalsOverlays,
          overlay.id,
          changes,
        );
      }
      return overlay;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'telemedicine.upsertOverlay');
    }
  }

  @override
  Future<TeleConsultationArchive?> archiveForConsultation(
    String consultationId,
  ) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select * from ${LocalTables.teleConsultationArchives} '
        'where consultation_id = ?',
        <Object?>[consultationId],
      );
      if (rows.isEmpty) return null;
      return TeleConsultationArchive.fromRow(rows.first);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'telemedicine.archiveForConsultation');
    }
  }

  @override
  Future<TeleConsultationArchive> upsertArchive(
    TeleConsultationArchive archive,
  ) async {
    try {
      final Map<String, Object?>? existing = await _store.getById(
        LocalTables.teleConsultationArchives,
        archive.id,
      );
      final Map<String, Object?> changes = <String, Object?>{
        'consultation_id': archive.consultationId,
        'archived_by': archive.archivedBy,
        'duration_seconds': archive.durationSeconds,
        'recording_reference': archive.recordingReference,
        'transcript_reference': archive.transcriptReference,
        'consent_recorded': archive.consentRecorded,
        'archived_at': archive.archivedAt,
        'updated_at': archive.updatedAt,
      };
      if (existing == null) {
        await _store.insert(
          LocalTables.teleConsultationArchives,
          <String, Object?>{
            ...changes,
            'id': archive.id,
            'tenant_id': archive.tenantId,
            'created_at': archive.createdAt,
          },
        );
      } else {
        await _store.update(
          LocalTables.teleConsultationArchives,
          archive.id,
          changes,
        );
      }
      return archive;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'telemedicine.upsertArchive');
    }
  }

  Never _mapped(Object error, StackTrace stackTrace, String operation) {
    if (error is NodexError) throw error;
    final NodexError mapped = NodexErrorMapper.map(error, operation: operation);
    _logger.error(
      _module,
      'Telemedicine repository failure.',
      operation: operation,
      outcome: 'failed',
      errorCode: mapped.code,
      stackTrace: stackTrace,
    );
    throw mapped;
  }
}
