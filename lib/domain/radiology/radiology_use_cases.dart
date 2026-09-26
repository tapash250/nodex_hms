/// Radiology workflow use cases (Module 18).
///
/// Each write gates on the authorization policy before touching the
/// repository. Ordering requires `imaging_order.write`, study acquisition
/// requires `imaging_study.record`, drafts require `imaging_report.enter`,
/// and revising or releasing a report requires `imaging_report.verify`.
library;

import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/radiology/radiology.dart';
import 'package:nodex_hms/domain/radiology/radiology_repository.dart';
import 'package:uuid/uuid.dart';

/// Raises an imaging order. Requires `imaging_order.write`.
final class OrderImagingUseCase {
  OrderImagingUseCase({required this._repository});

  final RadiologyRepository _repository;

  Future<ImagingOrder> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String patientId,
    required String orderedBy,
    required String orderCode,
    required ImagingModality modality,
    required String bodyRegion,
    required ImagingPriority priority,
    String? encounterId,
    String? clinicalIndication,
  }) async {
    policy.require(NodexPermissions.imagingOrderWrite);
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (patientId.isEmpty) {
      fieldErrors['patient_id'] = 'Patient is required.';
    }
    if (orderedBy.isEmpty) {
      fieldErrors['ordered_by'] = 'Ordering clinician is required.';
    }
    if (orderCode.trim().isEmpty) {
      fieldErrors['order_code'] = 'Order code is required.';
    }
    if (bodyRegion.trim().isEmpty) {
      fieldErrors['body_region'] = 'Body region is required.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Imaging order failed validation.',
        fieldErrors: fieldErrors,
        code: 'imaging_order_invalid',
      );
    }
    final DateTime now = DateTime.now().toUtc();
    final String? indication = clinicalIndication?.trim();
    final ImagingOrder order = ImagingOrder(
      id: const Uuid().v4(),
      tenantId: tenantId,
      patientId: patientId,
      encounterId: encounterId,
      orderedBy: orderedBy,
      orderCode: orderCode.trim(),
      modality: modality,
      bodyRegion: bodyRegion.trim(),
      priority: priority,
      status: ImagingOrderStatus.ordered,
      clinicalIndication: indication == null || indication.isEmpty
          ? null
          : indication,
      orderedAt: now,
      createdAt: now,
      updatedAt: now,
    );
    return _repository.upsertOrder(order);
  }
}

/// Cancels an imaging order with a reason. Requires `imaging_order.write`.
final class CancelImagingOrderUseCase {
  CancelImagingOrderUseCase({required this._repository});

  final RadiologyRepository _repository;

  Future<ImagingOrder> call({
    required AuthorizationPolicy policy,
    required ImagingOrder original,
    required String reason,
  }) async {
    policy.require(NodexPermissions.imagingOrderWrite);
    if (original.isTerminal) {
      throw const AuthorizationError(
        message: 'Closed imaging orders cannot be cancelled.',
        code: 'imaging_order_closed',
      );
    }
    if (reason.trim().isEmpty) {
      throw const ValidationError(
        message: 'Cancelling an imaging order requires a reason.',
        code: 'imaging_cancellation_reason_required',
      );
    }
    final DateTime now = DateTime.now().toUtc();
    return _repository.upsertOrder(
      ImagingOrder(
        id: original.id,
        tenantId: original.tenantId,
        patientId: original.patientId,
        encounterId: original.encounterId,
        orderedBy: original.orderedBy,
        orderCode: original.orderCode,
        modality: original.modality,
        bodyRegion: original.bodyRegion,
        priority: original.priority,
        status: ImagingOrderStatus.cancelled,
        clinicalIndication: original.clinicalIndication,
        orderedAt: original.orderedAt,
        cancelledAt: now,
        cancelledReason: reason.trim(),
        createdAt: original.createdAt,
        updatedAt: now,
      ),
    );
  }
}

/// Records the acquisition of a study for an order. Requires
/// `imaging_study.record`.
final class RecordImagingStudyUseCase {
  RecordImagingStudyUseCase({required this._repository});

  final RadiologyRepository _repository;

  Future<ImagingStudy> call({
    required AuthorizationPolicy policy,
    required ImagingOrder order,
    required String studyUid,
    required String performedBy,
    DateTime? performedAt,
    String? acquisitionNotes,
  }) async {
    policy.require(NodexPermissions.imagingStudyRecord);
    if (order.isTerminal) {
      throw const AuthorizationError(
        message: 'Closed imaging orders cannot receive a study.',
        code: 'imaging_order_closed',
      );
    }
    if (studyUid.trim().isEmpty) {
      throw const ValidationError(
        message: 'A study needs a PACS/DICOM identifier.',
        code: 'imaging_study_uid_required',
      );
    }
    final ImagingStudy? forOrder = await _repository.studyForOrder(order.id);
    if (forOrder != null) {
      throw const AuthorizationError(
        message: 'This imaging order already has a study.',
        code: 'imaging_study_exists',
      );
    }
    final ImagingStudy? taken = await _repository.studyByUid(studyUid.trim());
    if (taken != null) {
      throw const ValidationError(
        message: 'That study identifier is already in use.',
        code: 'imaging_study_uid_taken',
      );
    }
    final String? notes = acquisitionNotes?.trim();
    final DateTime now = DateTime.now().toUtc();
    final ImagingStudy study = ImagingStudy(
      id: const Uuid().v4(),
      tenantId: order.tenantId,
      imagingOrderId: order.id,
      studyUid: studyUid.trim(),
      modality: order.modality,
      bodyRegion: order.bodyRegion,
      performedBy: performedBy,
      performedAt: performedAt ?? now,
      acquisitionNotes: notes == null || notes.isEmpty ? null : notes,
      createdAt: now,
      updatedAt: now,
    );
    return _repository.upsertStudy(study);
  }
}

/// Files a draft report for an order. Requires `imaging_report.enter`.
final class EnterImagingReportUseCase {
  EnterImagingReportUseCase({required this._repository});

  final RadiologyRepository _repository;

  Future<ImagingReport> call({
    required AuthorizationPolicy policy,
    required ImagingOrder order,
    required String findings,
    required String impression,
    required String enteredBy,
    DateTime? enteredAt,
  }) async {
    policy.require(NodexPermissions.imagingReportEnter);
    if (order.isTerminal) {
      throw const AuthorizationError(
        message: 'Closed imaging orders cannot receive a report.',
        code: 'imaging_order_closed',
      );
    }
    final ImagingStudy? study = await _repository.studyForOrder(order.id);
    if (study == null) {
      throw const AuthorizationError(
        message: 'Record the study before filing a report.',
        code: 'imaging_study_required',
      );
    }
    final ImagingReport? existing = await _repository.reportForOrder(order.id);
    if (existing != null) {
      throw const AuthorizationError(
        message: 'This imaging order already has a report.',
        code: 'imaging_report_exists',
      );
    }
    final String cleanFindings = findings.trim();
    final String cleanImpression = impression.trim();
    if (cleanFindings.isEmpty || cleanImpression.isEmpty) {
      throw const ValidationError(
        message: 'A report needs findings and an impression.',
        code: 'imaging_report_text_required',
      );
    }
    final DateTime now = DateTime.now().toUtc();
    final ImagingReport report = ImagingReport(
      id: const Uuid().v4(),
      tenantId: order.tenantId,
      imagingOrderId: order.id,
      studyId: study.id,
      findings: cleanFindings,
      impression: cleanImpression,
      status: ImagingReportStatus.draft,
      enteredBy: enteredBy,
      enteredAt: enteredAt ?? now,
      createdAt: now,
      updatedAt: now,
    );
    return _repository.upsertReport(report);
  }
}

/// Revises a draft report. Requires `imaging_report.verify`: report updates
/// are verifier-gated server-side, mirroring laboratory result updates.
final class ReviseImagingReportUseCase {
  ReviseImagingReportUseCase({required this._repository});

  final RadiologyRepository _repository;

  Future<ImagingReport> call({
    required AuthorizationPolicy policy,
    required ImagingReport report,
    required String findings,
    required String impression,
  }) async {
    policy.require(NodexPermissions.imagingReportVerify);
    if (!report.isDraft) {
      throw const AuthorizationError(
        message: 'Verified imaging reports are immutable.',
        code: 'imaging_report_not_draft',
      );
    }
    final String cleanFindings = findings.trim();
    final String cleanImpression = impression.trim();
    if (cleanFindings.isEmpty || cleanImpression.isEmpty) {
      throw const ValidationError(
        message: 'A report needs findings and an impression.',
        code: 'imaging_report_text_required',
      );
    }
    return _repository.upsertReport(
      ImagingReport(
        id: report.id,
        tenantId: report.tenantId,
        imagingOrderId: report.imagingOrderId,
        studyId: report.studyId,
        findings: cleanFindings,
        impression: cleanImpression,
        status: report.status,
        enteredBy: report.enteredBy,
        enteredAt: report.enteredAt,
        createdAt: report.createdAt,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }
}

/// Verifies a draft report and completes the order. Requires
/// `imaging_report.verify`.
final class VerifyImagingReportUseCase {
  VerifyImagingReportUseCase({required this._repository});

  final RadiologyRepository _repository;

  Future<ImagingReport> call({
    required AuthorizationPolicy policy,
    required ImagingReport report,
    required String verifierId,
  }) async {
    policy.require(NodexPermissions.imagingReportVerify);
    if (!report.isDraft) {
      throw const AuthorizationError(
        message: 'Verified imaging reports are immutable.',
        code: 'imaging_report_not_draft',
      );
    }
    final DateTime now = DateTime.now().toUtc();
    final ImagingReport verified = await _repository.upsertReport(
      ImagingReport(
        id: report.id,
        tenantId: report.tenantId,
        imagingOrderId: report.imagingOrderId,
        studyId: report.studyId,
        findings: report.findings,
        impression: report.impression,
        status: ImagingReportStatus.verified,
        enteredBy: report.enteredBy,
        enteredAt: report.enteredAt,
        verifiedBy: verifierId,
        verifiedAt: now,
        createdAt: report.createdAt,
        updatedAt: now,
      ),
    );
    final ImagingOrder? order = await _repository.orderById(
      report.imagingOrderId,
    );
    if (order != null && order.isOrdered) {
      await _repository.upsertOrder(
        ImagingOrder(
          id: order.id,
          tenantId: order.tenantId,
          patientId: order.patientId,
          encounterId: order.encounterId,
          orderedBy: order.orderedBy,
          orderCode: order.orderCode,
          modality: order.modality,
          bodyRegion: order.bodyRegion,
          priority: order.priority,
          status: ImagingOrderStatus.completed,
          clinicalIndication: order.clinicalIndication,
          orderedAt: order.orderedAt,
          createdAt: order.createdAt,
          updatedAt: now,
        ),
      );
    }
    return verified;
  }
}
