/// Tests for the radiology use-case gates (Module 18).
///
/// Ordering needs `imaging_order.write`, study acquisition needs
/// `imaging_study.record`, drafting needs `imaging_report.enter`, and
/// revising or releasing a report needs `imaging_report.verify`. A report
/// requires a recorded study, verification freezes the report and completes
/// the order, and cancellation carries a reason.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/authorization_snapshot.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/domain/radiology/radiology.dart';
import 'package:nodex_hms/domain/radiology/radiology_repository.dart';
import 'package:nodex_hms/domain/radiology/radiology_use_cases.dart';

import 'radiology_repository_test.dart' show FakeRadiologyStore;

/// Builds a policy holding exactly [permissions].
AuthorizationPolicy policyWith(Set<String> permissions) {
  final DateTime issuedAt = DateTime.now().toUtc();
  return AuthorizationPolicy(
    snapshot: AuthorizationSnapshot(
      snapshotId: 'snapshot-1',
      tenantId: 'tenant-1',
      userId: 'clinician-1',
      deviceId: 'device-1',
      revision: 1,
      issuedAt: issuedAt,
      expiresAt: issuedAt.add(const Duration(days: 30)),
      payloadDigest: 'digest',
      roles: const <String>{NodexRoles.medicalOfficer},
      permissions: permissions,
      offlinePermissions: permissions,
      facilityIds: const <String>{},
      departmentIds: const <String>{},
      wardIds: const <String>{},
    ),
    connectivity: ConnectivityState.online,
  );
}

void main() {
  late FakeRadiologyStore store;
  late DefaultRadiologyRepository repository;
  late OrderImagingUseCase orderCase;
  late CancelImagingOrderUseCase cancel;
  late RecordImagingStudyUseCase recordStudy;
  late EnterImagingReportUseCase enterReport;
  late ReviseImagingReportUseCase reviseReport;
  late VerifyImagingReportUseCase verifyReport;

  const Set<String> orderer = <String>{NodexPermissions.imagingOrderWrite};
  const Set<String> recorder = <String>{NodexPermissions.imagingStudyRecord};
  const Set<String> enterer = <String>{NodexPermissions.imagingReportEnter};
  const Set<String> verifier = <String>{NodexPermissions.imagingReportVerify};

  setUp(() {
    store = FakeRadiologyStore();
    repository = DefaultRadiologyRepository(
      store: store,
      logger: NodexLogger(
        sinks: <NodexLogSink>[InMemoryLogSink()],
        minimumLevel: NodexLogLevel.trace,
      ),
    );
    orderCase = OrderImagingUseCase(repository: repository);
    cancel = CancelImagingOrderUseCase(repository: repository);
    recordStudy = RecordImagingStudyUseCase(repository: repository);
    enterReport = EnterImagingReportUseCase(repository: repository);
    reviseReport = ReviseImagingReportUseCase(repository: repository);
    verifyReport = VerifyImagingReportUseCase(repository: repository);
  });

  // Seeded rows predate "now" so a use case re-stamping `updatedAt` moves the
  // clock forward rather than backwards.
  DateTime at(int hour) => DateTime.utc(2026, 9, 1, hour);

  Future<ImagingOrder> seedOrder({
    ImagingOrderStatus status = ImagingOrderStatus.ordered,
    String id = 'order-1',
  }) async {
    final ImagingOrder order = ImagingOrder(
      id: id,
      tenantId: 'tenant-1',
      patientId: 'patient-1',
      orderedBy: 'doctor-1',
      orderCode: 'IMG-00$id',
      modality: ImagingModality.ct,
      bodyRegion: 'Chest',
      priority: ImagingPriority.routine,
      status: status,
      orderedAt: at(8),
      createdAt: at(8),
      updatedAt: at(8),
    );
    await repository.upsertOrder(order);
    return order;
  }

  Future<ImagingStudy> seedStudy(ImagingOrder order) async {
    final ImagingStudy study = ImagingStudy(
      id: 'study-1',
      tenantId: order.tenantId,
      imagingOrderId: order.id,
      studyUid: '1.2.840.1',
      modality: order.modality,
      bodyRegion: order.bodyRegion,
      performedBy: 'tech-1',
      performedAt: at(9),
      createdAt: at(9),
      updatedAt: at(9),
    );
    await repository.upsertStudy(study);
    return study;
  }

  Future<ImagingReport> seedReport(ImagingOrder order) async {
    final ImagingReport report = ImagingReport(
      id: 'report-1',
      tenantId: order.tenantId,
      imagingOrderId: order.id,
      studyId: 'study-1',
      findings: 'Clear lungs.',
      impression: 'Normal.',
      status: ImagingReportStatus.draft,
      enteredBy: 'doctor-1',
      enteredAt: at(10),
      createdAt: at(10),
      updatedAt: at(10),
    );
    await repository.upsertReport(report);
    return report;
  }

  group('ordering', () {
    test('an imaging order requires imaging_order.write', () {
      expect(
        orderCase.call(
          policy: policyWith(recorder),
          tenantId: 'tenant-1',
          patientId: 'patient-1',
          orderedBy: 'doctor-1',
          orderCode: 'IMG-100',
          modality: ImagingModality.xray,
          bodyRegion: 'Chest',
          priority: ImagingPriority.routine,
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('an order is created in the ordered state', () async {
      final ImagingOrder order = await orderCase.call(
        policy: policyWith(orderer),
        tenantId: 'tenant-1',
        patientId: 'patient-1',
        orderedBy: 'doctor-1',
        orderCode: 'IMG-100',
        modality: ImagingModality.mri,
        bodyRegion: 'Brain',
        priority: ImagingPriority.urgent,
        clinicalIndication: ' Headache. ',
      );

      expect(order.status, ImagingOrderStatus.ordered);
      expect(order.modality, ImagingModality.mri);
      expect(order.priority, ImagingPriority.urgent);
      expect(order.clinicalIndication, 'Headache.');
      expect((await repository.orderById(order.id))!.id, order.id);
    });

    test('an order missing identity or region is rejected', () {
      expect(
        orderCase.call(
          policy: policyWith(orderer),
          tenantId: 'tenant-1',
          patientId: 'patient-1',
          orderedBy: 'doctor-1',
          orderCode: '  ',
          modality: ImagingModality.xray,
          bodyRegion: 'Chest',
          priority: ImagingPriority.routine,
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.fieldErrors.keys,
            'fields',
            contains('order_code'),
          ),
        ),
      );
      expect(
        orderCase.call(
          policy: policyWith(orderer),
          tenantId: 'tenant-1',
          patientId: 'patient-1',
          orderedBy: 'doctor-1',
          orderCode: 'IMG-101',
          modality: ImagingModality.xray,
          bodyRegion: ' ',
          priority: ImagingPriority.routine,
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'imaging_order_invalid',
          ),
        ),
      );
    });

    test('cancellation requires imaging_order.write', () async {
      final ImagingOrder order = await seedOrder();
      expect(
        cancel.call(
          policy: policyWith(recorder),
          original: order,
          reason: 'Patient refused.',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('cancellation requires a reason', () async {
      final ImagingOrder order = await seedOrder();
      expect(
        cancel.call(policy: policyWith(orderer), original: order, reason: ' '),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'imaging_cancellation_reason_required',
          ),
        ),
      );
    });

    test('cancellation stamps the reason and freezes the order', () async {
      final ImagingOrder order = await seedOrder();
      final ImagingOrder cancelled = await cancel.call(
        policy: policyWith(orderer),
        original: order,
        reason: 'Patient refused.',
      );

      expect(cancelled.status, ImagingOrderStatus.cancelled);
      expect(cancelled.cancelledReason, 'Patient refused.');
      expect(cancelled.isTerminal, isTrue);
      expect(
        cancel.call(
          policy: policyWith(orderer),
          original: cancelled,
          reason: 'Another.',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });
  });

  group('study acquisition', () {
    test('recording a study requires imaging_study.record', () async {
      final ImagingOrder order = await seedOrder();
      expect(
        recordStudy.call(
          policy: policyWith(orderer),
          order: order,
          studyUid: '1.2.3',
          performedBy: 'tech-1',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('a study needs a PACS/DICOM identifier', () async {
      final ImagingOrder order = await seedOrder();
      expect(
        recordStudy.call(
          policy: policyWith(recorder),
          order: order,
          studyUid: '  ',
          performedBy: 'tech-1',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'imaging_study_uid_required',
          ),
        ),
      );
    });

    test('a closed order cannot receive a study', () async {
      final ImagingOrder order = await seedOrder(
        status: ImagingOrderStatus.cancelled,
      );
      expect(
        recordStudy.call(
          policy: policyWith(recorder),
          order: order,
          studyUid: '1.2.3',
          performedBy: 'tech-1',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('a second study for the same order is refused', () async {
      final ImagingOrder order = await seedOrder();
      await seedStudy(order);
      expect(
        recordStudy.call(
          policy: policyWith(recorder),
          order: order,
          studyUid: '1.2.840.2',
          performedBy: 'tech-1',
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'imaging_study_exists',
          ),
        ),
      );
    });

    test('a taken study identifier is refused', () async {
      final ImagingOrder first = await seedOrder();
      await seedStudy(first);
      final ImagingOrder second = await seedOrder(id: 'order-2');
      expect(
        recordStudy.call(
          policy: policyWith(recorder),
          order: second,
          studyUid: '1.2.840.1',
          performedBy: 'tech-1',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'imaging_study_uid_taken',
          ),
        ),
      );
    });

    test('acquisition records the study against the order', () async {
      final ImagingOrder order = await seedOrder();
      final ImagingStudy study = await recordStudy.call(
        policy: policyWith(recorder),
        order: order,
        studyUid: ' 1.2.840.9 ',
        performedBy: 'tech-1',
        acquisitionNotes: 'Portable. ',
      );

      expect(study.studyUid, '1.2.840.9');
      expect(study.acquisitionNotes, 'Portable.');
      expect((await repository.studyForOrder(order.id))!.id, study.id);
    });
  });

  group('report drafting', () {
    test('drafting requires imaging_report.enter', () async {
      final ImagingOrder order = await seedOrder();
      await seedStudy(order);
      expect(
        enterReport.call(
          policy: policyWith(verifier),
          order: order,
          findings: 'Clear lungs.',
          impression: 'Normal.',
          enteredBy: 'doctor-1',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('a report requires a recorded study', () async {
      final ImagingOrder order = await seedOrder();
      expect(
        enterReport.call(
          policy: policyWith(enterer),
          order: order,
          findings: 'Clear lungs.',
          impression: 'Normal.',
          enteredBy: 'doctor-1',
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'imaging_study_required',
          ),
        ),
      );
    });

    test('a second report for the same order is refused', () async {
      final ImagingOrder order = await seedOrder();
      await seedStudy(order);
      await seedReport(order);
      expect(
        enterReport.call(
          policy: policyWith(enterer),
          order: order,
          findings: 'More text.',
          impression: 'Still normal.',
          enteredBy: 'doctor-1',
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'imaging_report_exists',
          ),
        ),
      );
    });

    test('findings and impression are both required', () async {
      final ImagingOrder order = await seedOrder();
      await seedStudy(order);
      expect(
        enterReport.call(
          policy: policyWith(enterer),
          order: order,
          findings: 'Clear lungs.',
          impression: '  ',
          enteredBy: 'doctor-1',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'imaging_report_text_required',
          ),
        ),
      );
    });

    test('drafting files the report against the study', () async {
      final ImagingOrder order = await seedOrder();
      await seedStudy(order);
      final ImagingReport report = await enterReport.call(
        policy: policyWith(enterer),
        order: order,
        findings: ' Clear lungs. ',
        impression: ' Normal. ',
        enteredBy: 'doctor-1',
      );

      expect(report.status, ImagingReportStatus.draft);
      expect(report.findings, 'Clear lungs.');
      expect(report.studyId, 'study-1');
      expect((await repository.reportForOrder(order.id))!.id, report.id);
    });
  });

  group('revision and verification', () {
    test('revision requires imaging_report.verify', () async {
      final ImagingOrder order = await seedOrder();
      await seedStudy(order);
      final ImagingReport report = await seedReport(order);
      expect(
        reviseReport.call(
          policy: policyWith(enterer),
          report: report,
          findings: 'Updated.',
          impression: 'Still normal.',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('revision replaces the draft in place', () async {
      final ImagingOrder order = await seedOrder();
      await seedStudy(order);
      final ImagingReport report = await seedReport(order);

      final ImagingReport revised = await reviseReport.call(
        policy: policyWith(verifier),
        report: report,
        findings: 'Updated findings.',
        impression: ' Updated impression. ',
      );

      expect(revised.id, report.id);
      expect(revised.findings, 'Updated findings.');
      expect(revised.impression, 'Updated impression.');
      expect(revised.status, ImagingReportStatus.draft);
      expect(
        store.tables['imaging_reports']!.length,
        1,
        reason: 'one order holds exactly one report row',
      );
    });

    test('a verified report cannot be revised or re-verified', () async {
      final ImagingOrder order = await seedOrder();
      await seedStudy(order);
      final ImagingReport report = await seedReport(order);
      final ImagingReport verified = await verifyReport.call(
        policy: policyWith(verifier),
        report: report,
        verifierId: 'radiologist-1',
      );

      expect(
        reviseReport.call(
          policy: policyWith(verifier),
          report: verified,
          findings: 'Changed.',
          impression: 'Changed.',
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'imaging_report_not_draft',
          ),
        ),
      );
      expect(
        verifyReport.call(
          policy: policyWith(verifier),
          report: verified,
          verifierId: 'radiologist-1',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('verification requires imaging_report.verify', () async {
      final ImagingOrder order = await seedOrder();
      await seedStudy(order);
      final ImagingReport report = await seedReport(order);
      expect(
        verifyReport.call(
          policy: policyWith(enterer),
          report: report,
          verifierId: 'doctor-1',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('verification freezes the report and completes the order', () async {
      final ImagingOrder order = await seedOrder();
      await seedStudy(order);
      final ImagingReport report = await seedReport(order);

      final ImagingReport verified = await verifyReport.call(
        policy: policyWith(verifier),
        report: report,
        verifierId: 'radiologist-1',
      );

      expect(verified.isVerified, isTrue);
      expect(verified.verifiedBy, 'radiologist-1');
      expect(verified.verifiedAt, isNotNull);
      expect(
        (await repository.orderById(order.id))!.status,
        ImagingOrderStatus.completed,
      );
    });

    test('verification leaves a cancelled order untouched', () async {
      final ImagingOrder order = await seedOrder();
      await seedStudy(order);
      await seedReport(order);
      final ImagingOrder cancelled = await cancel.call(
        policy: policyWith(orderer),
        original: order,
        reason: 'Patient moved.',
      );

      final ImagingReport verified = await verifyReport.call(
        policy: policyWith(verifier),
        report: await repository.reportForOrder(order.id) as ImagingReport,
        verifierId: 'radiologist-1',
      );

      expect(verified.isVerified, isTrue);
      expect(
        (await repository.orderById(cancelled.id))!.status,
        ImagingOrderStatus.cancelled,
        reason: 'a cancelled order stays cancelled',
      );
    });
  });
}
