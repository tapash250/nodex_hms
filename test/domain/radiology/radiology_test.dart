/// Radiology entity decoding tests (Module 18).
///
/// Order lifecycle, modality classification, and report signatures all decode
/// from snake_case projection rows; a wrong wire value silently reclassifies a
/// clinical record, so every enum and nullable column round trips through the
/// row form.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/domain/radiology/radiology.dart';

void main() {
  group('enum wire decoding', () {
    test('modality decodes every stored value', () {
      expect(ImagingModality.fromWire('ct'), ImagingModality.ct);
      expect(ImagingModality.fromWire('mri'), ImagingModality.mri);
      expect(
        ImagingModality.fromWire('ultrasound'),
        ImagingModality.ultrasound,
      );
      expect(ImagingModality.fromWire(''), ImagingModality.xray);
      expect(ImagingModality.xray.label, 'X-ray');
    });

    test('priority decodes and flags STAT', () {
      expect(ImagingPriority.fromWire('urgent'), ImagingPriority.urgent);
      expect(ImagingPriority.fromWire('stat'), ImagingPriority.stat);
      expect(ImagingPriority.fromWire('nope'), ImagingPriority.routine);
      expect(ImagingPriority.stat.isStat, isTrue);
      expect(ImagingPriority.routine.isStat, isFalse);
    });

    test('order status decodes and flags terminal cases', () {
      expect(
        ImagingOrderStatus.fromWire('completed'),
        ImagingOrderStatus.completed,
      );
      expect(
        ImagingOrderStatus.fromWire('cancelled'),
        ImagingOrderStatus.cancelled,
      );
      expect(ImagingOrderStatus.fromWire('nope'), ImagingOrderStatus.ordered);
      expect(ImagingOrderStatus.completed.isTerminal, isTrue);
      expect(ImagingOrderStatus.cancelled.isTerminal, isTrue);
      expect(ImagingOrderStatus.ordered.isTerminal, isFalse);
    });

    test('report status decodes and gates editability', () {
      expect(
        ImagingReportStatus.fromWire('verified'),
        ImagingReportStatus.verified,
      );
      expect(ImagingReportStatus.fromWire('nope'), ImagingReportStatus.draft);
      expect(ImagingReportStatus.draft.isEditable, isTrue);
      expect(ImagingReportStatus.draft.isVerified, isFalse);
      expect(ImagingReportStatus.verified.isEditable, isFalse);
      expect(ImagingReportStatus.verified.isVerified, isTrue);
    });
  });

  group('ImagingOrder.fromRow', () {
    test('decodes a fully-populated order row', () {
      final DateTime at = DateTime.utc(2026, 9, 20, 9);
      final ImagingOrder order = ImagingOrder.fromRow(<String, Object?>{
        'id': 'order-1',
        'tenant_id': 'tenant-1',
        'patient_id': 'patient-1',
        'encounter_id': 'enc-1',
        'ordered_by': 'doctor-1',
        'order_code': 'IMG-001',
        'modality': 'ct',
        'body_region': 'Chest',
        'priority': 'stat',
        'status': 'ordered',
        'clinical_indication': 'Suspected PE.',
        'ordered_at': at,
        'cancelled_at': null,
        'cancelled_reason': null,
        'created_at': at,
        'updated_at': at,
      });

      expect(order.modality, ImagingModality.ct);
      expect(order.priority, ImagingPriority.stat);
      expect(order.status, ImagingOrderStatus.ordered);
      expect(order.encounterId, 'enc-1');
      expect(order.clinicalIndication, 'Suspected PE.');
      expect(order.isOrdered, isTrue);
      expect(order.isTerminal, isFalse);
    });

    test('clears absent links and carries cancellation details', () {
      final DateTime at = DateTime.utc(2026, 9, 20, 9);
      final ImagingOrder order = ImagingOrder.fromRow(<String, Object?>{
        'id': 'order-2',
        'tenant_id': 'tenant-1',
        'patient_id': 'patient-1',
        'encounter_id': null,
        'ordered_by': 'doctor-1',
        'order_code': 'IMG-002',
        'modality': 'xray',
        'body_region': 'Ankle',
        'priority': 'routine',
        'status': 'cancelled',
        'clinical_indication': null,
        'ordered_at': at,
        'cancelled_at': at.add(const Duration(hours: 1)),
        'cancelled_reason': 'Patient refused.',
        'created_at': at,
        'updated_at': at,
      });

      expect(order.encounterId, isNull);
      expect(order.clinicalIndication, isNull);
      expect(order.cancelledReason, 'Patient refused.');
      expect(order.cancelledAt, isNotNull);
      expect(order.isTerminal, isTrue);
    });
  });

  group('ImagingStudy.fromRow', () {
    test('decodes acquisition metadata', () {
      final DateTime at = DateTime.utc(2026, 9, 20, 10);
      final ImagingStudy study = ImagingStudy.fromRow(<String, Object?>{
        'id': 'study-1',
        'tenant_id': 'tenant-1',
        'imaging_order_id': 'order-1',
        'study_uid': '1.2.840.113619.2.1',
        'modality': 'mri',
        'body_region': 'Brain',
        'performed_by': 'tech-1',
        'performed_at': at,
        'acquisition_notes': 'With contrast.',
        'created_at': at,
        'updated_at': at,
      });

      expect(study.studyUid, '1.2.840.113619.2.1');
      expect(study.modality, ImagingModality.mri);
      expect(study.acquisitionNotes, 'With contrast.');

      final ImagingStudy bare = ImagingStudy.fromRow(<String, Object?>{
        'id': 'study-2',
        'tenant_id': 'tenant-1',
        'imaging_order_id': 'order-1',
        'study_uid': '1.2.3',
        'modality': 'ultrasound',
        'body_region': 'Abdomen',
        'performed_by': 'tech-1',
        'performed_at': at,
        'acquisition_notes': null,
        'created_at': at,
        'updated_at': at,
      });
      expect(bare.acquisitionNotes, isNull);
      expect(bare.modality, ImagingModality.ultrasound);
    });
  });

  group('ImagingReport.fromRow', () {
    test('decodes a draft report', () {
      final DateTime at = DateTime.utc(2026, 9, 20, 11);
      final ImagingReport report = ImagingReport.fromRow(<String, Object?>{
        'id': 'report-1',
        'tenant_id': 'tenant-1',
        'imaging_order_id': 'order-1',
        'study_id': 'study-1',
        'findings': 'Right lower lobe infiltrate.',
        'impression': 'Consolidation.',
        'status': 'draft',
        'entered_by': 'doctor-1',
        'entered_at': at,
        'verified_by': null,
        'verified_at': null,
        'created_at': at,
        'updated_at': at,
      });

      expect(report.isDraft, isTrue);
      expect(report.verifiedBy, isNull);
      expect(report.impression, 'Consolidation.');
    });

    test('decodes a verified report with its signature', () {
      final DateTime at = DateTime.utc(2026, 9, 20, 12);
      final ImagingReport report = ImagingReport.fromRow(<String, Object?>{
        'id': 'report-2',
        'tenant_id': 'tenant-1',
        'imaging_order_id': 'order-1',
        'study_id': 'study-1',
        'findings': 'No acute abnormality.',
        'impression': 'Normal study.',
        'status': 'verified',
        'entered_by': 'resident-1',
        'entered_at': at,
        'verified_by': 'radiologist-1',
        'verified_at': at.add(const Duration(hours: 1)),
        'created_at': at,
        'updated_at': at,
      });

      expect(report.isVerified, isTrue);
      expect(report.verifiedBy, 'radiologist-1');
      expect(report.verifiedAt, isNotNull);
    });
  });
}
