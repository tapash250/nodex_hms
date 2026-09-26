/// Radiology repository contract and PowerSync-backed implementation
/// (Module 18).
library;

import 'package:nodex_hms/core/errors/error_mapper.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';
import 'package:nodex_hms/domain/radiology/radiology.dart';

/// Read and write access to imaging orders, studies and reports.
abstract interface class RadiologyRepository {
  /// One order by id, or null.
  Future<ImagingOrder?> orderById(String id);

  /// Orders for one patient, newest first.
  Future<List<ImagingOrder>> ordersForPatient(String patientId);

  /// Every order on the device, newest first.
  Future<List<ImagingOrder>> allOrders();

  /// Inserts or updates an order row.
  Future<ImagingOrder> upsertOrder(ImagingOrder order);

  /// The study recorded for an order, or null.
  Future<ImagingStudy?> studyForOrder(String orderId);

  /// A study by its PACS/DICOM identifier, or null.
  Future<ImagingStudy?> studyByUid(String studyUid);

  /// Inserts or updates a study row.
  Future<ImagingStudy> upsertStudy(ImagingStudy study);

  /// The report filed for an order, or null.
  Future<ImagingReport?> reportForOrder(String orderId);

  /// Inserts or updates a report row.
  Future<ImagingReport> upsertReport(ImagingReport report);
}

/// Default repository over the encrypted local projection.
final class DefaultRadiologyRepository implements RadiologyRepository {
  const DefaultRadiologyRepository({
    required this._store,
    required this._logger,
  });

  static const String _module = 'domain.radiology';

  final PatientLocalStore _store;
  final NodexLogger _logger;

  @override
  Future<ImagingOrder?> orderById(String id) async {
    try {
      final Map<String, Object?>? row = await _store.getById(
        LocalTables.imagingOrders,
        id,
      );
      return row == null ? null : ImagingOrder.fromRow(row);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'radiology.orderById');
    }
  }

  @override
  Future<List<ImagingOrder>> ordersForPatient(String patientId) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select * from ${LocalTables.imagingOrders} where patient_id = ? '
        'order by ordered_at desc',
        <Object?>[patientId],
      );
      return rows.map(ImagingOrder.fromRow).toList();
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'radiology.ordersForPatient');
    }
  }

  @override
  Future<List<ImagingOrder>> allOrders() async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select * from ${LocalTables.imagingOrders} order by ordered_at desc',
        const <Object?>[],
      );
      return rows.map(ImagingOrder.fromRow).toList();
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'radiology.allOrders');
    }
  }

  @override
  Future<ImagingOrder> upsertOrder(ImagingOrder order) async {
    try {
      final Map<String, Object?>? existing = await _store.getById(
        LocalTables.imagingOrders,
        order.id,
      );
      final Map<String, Object?> changes = <String, Object?>{
        'patient_id': order.patientId,
        'encounter_id': order.encounterId,
        'ordered_by': order.orderedBy,
        'order_code': order.orderCode,
        'modality': order.modality.wireValue,
        'body_region': order.bodyRegion,
        'priority': order.priority.wireValue,
        'status': order.status.wireValue,
        'clinical_indication': order.clinicalIndication,
        'ordered_at': order.orderedAt,
        'cancelled_at': order.cancelledAt,
        'cancelled_reason': order.cancelledReason,
        'updated_at': order.updatedAt,
      };
      if (existing == null) {
        await _store.insert(LocalTables.imagingOrders, <String, Object?>{
          ...changes,
          'id': order.id,
          'tenant_id': order.tenantId,
          'created_at': order.createdAt,
        });
      } else {
        await _store.update(LocalTables.imagingOrders, order.id, changes);
      }
      return order;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'radiology.upsertOrder');
    }
  }

  @override
  Future<ImagingStudy?> studyForOrder(String orderId) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select * from ${LocalTables.imagingStudies} '
        'where imaging_order_id = ?',
        <Object?>[orderId],
      );
      if (rows.isEmpty) return null;
      return ImagingStudy.fromRow(rows.first);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'radiology.studyForOrder');
    }
  }

  @override
  Future<ImagingStudy?> studyByUid(String studyUid) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select * from ${LocalTables.imagingStudies} where study_uid = ?',
        <Object?>[studyUid],
      );
      if (rows.isEmpty) return null;
      return ImagingStudy.fromRow(rows.first);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'radiology.studyByUid');
    }
  }

  @override
  Future<ImagingStudy> upsertStudy(ImagingStudy study) async {
    try {
      final Map<String, Object?>? existing = await _store.getById(
        LocalTables.imagingStudies,
        study.id,
      );
      final Map<String, Object?> changes = <String, Object?>{
        'imaging_order_id': study.imagingOrderId,
        'study_uid': study.studyUid,
        'modality': study.modality.wireValue,
        'body_region': study.bodyRegion,
        'performed_by': study.performedBy,
        'performed_at': study.performedAt,
        'acquisition_notes': study.acquisitionNotes,
        'updated_at': study.updatedAt,
      };
      if (existing == null) {
        await _store.insert(LocalTables.imagingStudies, <String, Object?>{
          ...changes,
          'id': study.id,
          'tenant_id': study.tenantId,
          'created_at': study.createdAt,
        });
      } else {
        await _store.update(LocalTables.imagingStudies, study.id, changes);
      }
      return study;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'radiology.upsertStudy');
    }
  }

  @override
  Future<ImagingReport?> reportForOrder(String orderId) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select * from ${LocalTables.imagingReports} '
        'where imaging_order_id = ?',
        <Object?>[orderId],
      );
      if (rows.isEmpty) return null;
      return ImagingReport.fromRow(rows.first);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'radiology.reportForOrder');
    }
  }

  @override
  Future<ImagingReport> upsertReport(ImagingReport report) async {
    try {
      final Map<String, Object?>? existing = await _store.getById(
        LocalTables.imagingReports,
        report.id,
      );
      final Map<String, Object?> changes = <String, Object?>{
        'imaging_order_id': report.imagingOrderId,
        'study_id': report.studyId,
        'findings': report.findings,
        'impression': report.impression,
        'status': report.status.wireValue,
        'entered_by': report.enteredBy,
        'entered_at': report.enteredAt,
        'verified_by': report.verifiedBy,
        'verified_at': report.verifiedAt,
        'updated_at': report.updatedAt,
      };
      if (existing == null) {
        await _store.insert(LocalTables.imagingReports, <String, Object?>{
          ...changes,
          'id': report.id,
          'tenant_id': report.tenantId,
          'created_at': report.createdAt,
        });
      } else {
        await _store.update(LocalTables.imagingReports, report.id, changes);
      }
      return report;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'radiology.upsertReport');
    }
  }

  Never _mapped(Object error, StackTrace stackTrace, String operation) {
    if (error is NodexError) throw error;
    final NodexError mapped = NodexErrorMapper.map(error, operation: operation);
    _logger.error(
      _module,
      'Radiology repository failure.',
      operation: operation,
      outcome: 'failed',
      errorCode: mapped.code,
      stackTrace: stackTrace,
    );
    throw mapped;
  }
}
