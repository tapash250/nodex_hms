/// Tests for the blood bank use-case gates (Module 26).
///
/// Raising and approving need `transfusion.request`, crossmatch and unit
/// lifecycle need `blood_unit.write`, and administration needs
/// `transfusion.administer`. Approval also needs `transfusion.finalize`, issue
/// refuses anything but an approved request, and terminal rows stay frozen.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/authorization_snapshot.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/domain/blood_bank/blood_bank.dart';
import 'package:nodex_hms/domain/blood_bank/blood_bank_repository.dart';
import 'package:nodex_hms/domain/blood_bank/blood_bank_use_cases.dart';

import 'blood_bank_repository_test.dart' show FakeBloodBankStore;

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
  late FakeBloodBankStore store;
  late DefaultBloodBankRepository repository;
  late CreateBloodUnitUseCase createUnit;
  late RequestTransfusionUseCase requestTransfusion;
  late RecordCrossmatchUseCase crossmatch;
  late ApproveTransfusionRequestUseCase approve;
  late ReserveBloodUnitUseCase reserve;
  late IssueBloodUnitUseCase issue;
  late RecordTransfusionUseCase startTransfusion;
  late RecordTransfusionOutcomeUseCase recordOutcome;
  late DiscardBloodUnitUseCase discard;
  late CompleteTransfusionRequestUseCase complete;

  const Set<String> requester = <String>{NodexPermissions.transfusionRequest};
  const Set<String> labTech = <String>{NodexPermissions.bloodUnitWrite};
  const Set<String> approver = <String>{
    NodexPermissions.transfusionRequest,
    NodexPermissions.transfusionFinalize,
  };
  const Set<String> nurse = <String>{NodexPermissions.transfusionAdminister};

  setUp(() {
    store = FakeBloodBankStore();
    repository = DefaultBloodBankRepository(
      store: store,
      logger: NodexLogger(
        sinks: <NodexLogSink>[InMemoryLogSink()],
        minimumLevel: NodexLogLevel.trace,
      ),
    );
    createUnit = CreateBloodUnitUseCase(repository: repository);
    requestTransfusion = RequestTransfusionUseCase(repository: repository);
    crossmatch = RecordCrossmatchUseCase(repository: repository);
    approve = ApproveTransfusionRequestUseCase(repository: repository);
    reserve = ReserveBloodUnitUseCase(repository: repository);
    issue = IssueBloodUnitUseCase(repository: repository);
    startTransfusion = RecordTransfusionUseCase(repository: repository);
    recordOutcome = RecordTransfusionOutcomeUseCase(repository: repository);
    discard = DiscardBloodUnitUseCase(repository: repository);
    complete = CompleteTransfusionRequestUseCase(repository: repository);
  });

  // Seeded rows predate "now" so a use case re-stamping `updatedAt` moves the
  // clock forward rather than backwards.
  DateTime at(int hour) => DateTime.utc(2026, 9, 1, hour);

  Future<TransfusionRequest> seedRequest({
    TransfusionRequestStatus status = TransfusionRequestStatus.pending,
  }) async {
    final TransfusionRequest request = TransfusionRequest(
      id: 'req-1',
      tenantId: 'tenant-1',
      patientId: 'patient-1',
      requestedBy: 'doctor-1',
      requestedBloodGroup: BloodGroup.oPositive,
      component: BloodComponent.redCells,
      unitsRequested: 1,
      urgency: TransfusionUrgency.routine,
      status: status,
      crossmatchResult: status == TransfusionRequestStatus.approved
          ? CrossmatchResult.compatible
          : CrossmatchResult.pending,
      requestedAt: at(8),
      approvedBy: status == TransfusionRequestStatus.approved
          ? 'doctor-1'
          : null,
      approvedAt: status == TransfusionRequestStatus.approved ? at(9) : null,
      createdAt: at(8),
      updatedAt: at(9),
    );
    await repository.upsertRequest(request);
    return request;
  }

  Future<BloodUnit> seedUnit({
    BloodUnitStatus status = BloodUnitStatus.available,
    String? requestId = 'req-1',
  }) async {
    final BloodUnit unit = BloodUnit(
      id: 'unit-1',
      tenantId: 'tenant-1',
      unitNumber: 'BU-0001',
      bloodGroup: BloodGroup.oPositive,
      component: BloodComponent.redCells,
      volumeMl: 450,
      collectedAt: at(6),
      expiresAt: at(6).add(const Duration(days: 21)),
      status: status,
      patientId: status == BloodUnitStatus.available ? null : 'patient-1',
      transfusionRequestId: requestId,
      createdBy: 'lab-1',
      createdAt: at(6),
      updatedAt: at(7),
    );
    await repository.upsertBloodUnit(unit);
    return unit;
  }

  group('transfusion requests', () {
    test('raising a request requires transfusion.request', () {
      expect(
        requestTransfusion.call(
          policy: policyWith(labTech),
          tenantId: 'tenant-1',
          patientId: 'patient-1',
          requestedBy: 'doctor-1',
          requestedBloodGroup: BloodGroup.oPositive,
          component: BloodComponent.redCells,
          unitsRequested: 1,
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('raising a request creates a pending row', () async {
      final TransfusionRequest request = await requestTransfusion.call(
        policy: policyWith(requester),
        tenantId: 'tenant-1',
        patientId: 'patient-1',
        requestedBy: 'doctor-1',
        requestedBloodGroup: BloodGroup.aNegative,
        component: BloodComponent.platelets,
        unitsRequested: 2,
        indication: 'Symptomatic anaemia',
        urgency: TransfusionUrgency.urgent,
      );

      expect(request.status, TransfusionRequestStatus.pending);
      expect(request.crossmatchResult, CrossmatchResult.pending);
      expect(request.unitsRequested, 2);
      expect(request.isApproved, isFalse);
      expect((await repository.requestById(request.id))!.id, request.id);
    });

    test('a zero-unit request is rejected', () {
      expect(
        requestTransfusion.call(
          policy: policyWith(requester),
          tenantId: 'tenant-1',
          patientId: 'patient-1',
          requestedBy: 'doctor-1',
          requestedBloodGroup: BloodGroup.oPositive,
          component: BloodComponent.redCells,
          unitsRequested: 0,
        ),
        throwsA(isA<ValidationError>()),
      );
    });

    test('crossmatch requires blood_unit.write', () async {
      final TransfusionRequest request = await seedRequest();
      expect(
        crossmatch.call(
          policy: policyWith(requester),
          original: request,
          crossmatchResult: CrossmatchResult.compatible,
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('a compatible crossmatch advances a pending request', () async {
      final TransfusionRequest request = await seedRequest();
      final TransfusionRequest updated = await crossmatch.call(
        policy: policyWith(labTech),
        original: request,
        crossmatchResult: CrossmatchResult.compatible,
      );

      expect(updated.crossmatchResult, CrossmatchResult.compatible);
      expect(updated.status, TransfusionRequestStatus.crossmatched);
      expect(updated.updatedAt.isAfter(request.updatedAt), isTrue);
    });

    test(
      'an incompatible crossmatch records without advancing status',
      () async {
        final TransfusionRequest request = await seedRequest();
        final TransfusionRequest updated = await crossmatch.call(
          policy: policyWith(labTech),
          original: request,
          crossmatchResult: CrossmatchResult.incompatible,
        );

        expect(updated.crossmatchResult, CrossmatchResult.incompatible);
        expect(updated.status, TransfusionRequestStatus.pending);
      },
    );

    test('closed requests refuse a crossmatch', () async {
      final TransfusionRequest request = await seedRequest(
        status: TransfusionRequestStatus.cancelled,
      );
      expect(
        crossmatch.call(
          policy: policyWith(labTech),
          original: request,
          crossmatchResult: CrossmatchResult.compatible,
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('approval also requires transfusion.finalize', () async {
      final TransfusionRequest request = await seedRequest();
      expect(
        approve.call(
          policy: policyWith(requester),
          original: request,
          approvedBy: 'doctor-1',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('approval stamps the approver and timestamp', () async {
      final TransfusionRequest request = await seedRequest();
      final TransfusionRequest approved = await approve.call(
        policy: policyWith(approver),
        original: request,
        approvedBy: 'doctor-1',
      );

      expect(approved.status, TransfusionRequestStatus.approved);
      expect(approved.approvedBy, 'doctor-1');
      expect(approved.approvedAt, isNotNull);
      expect(approved.isApproved, isTrue);
    });

    test('only an approved request can complete', () async {
      final TransfusionRequest pending = await seedRequest();
      expect(
        complete.call(policy: policyWith(requester), original: pending),
        throwsA(isA<AuthorizationError>()),
      );

      final TransfusionRequest approved = await seedRequest(
        status: TransfusionRequestStatus.approved,
      );
      final TransfusionRequest done = await complete.call(
        policy: policyWith(requester),
        original: approved,
      );
      expect(done.status, TransfusionRequestStatus.completed);
      expect(done.isTerminal, isTrue);
    });
  });

  group('blood units', () {
    test('registration requires blood_unit.write', () {
      expect(
        createUnit.call(
          policy: policyWith(requester),
          tenantId: 'tenant-1',
          unitNumber: 'BU-0001',
          bloodGroup: BloodGroup.oPositive,
          component: BloodComponent.redCells,
          createdBy: 'lab-1',
          expiresAt: at(6).add(const Duration(days: 21)),
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('expiry must follow collection', () {
      expect(
        createUnit.call(
          policy: policyWith(labTech),
          tenantId: 'tenant-1',
          unitNumber: 'BU-0001',
          bloodGroup: BloodGroup.oPositive,
          component: BloodComponent.redCells,
          createdBy: 'lab-1',
          collectedAt: at(6),
          expiresAt: at(5),
        ),
        throwsA(isA<ValidationError>()),
      );
    });

    test('registration starts a unit available', () async {
      final BloodUnit unit = await createUnit.call(
        policy: policyWith(labTech),
        tenantId: 'tenant-1',
        unitNumber: 'BU-0001',
        bloodGroup: BloodGroup.oPositive,
        component: BloodComponent.redCells,
        createdBy: 'lab-1',
        collectedAt: at(6),
        expiresAt: at(6).add(const Duration(days: 21)),
        volumeMl: 450,
      );

      expect(unit.status, BloodUnitStatus.available);
      expect(unit.isAvailable, isTrue);
      expect((await repository.bloodUnitById(unit.id))!.unitNumber, 'BU-0001');
    });

    test('reservation requires an available unit', () async {
      final BloodUnit issued = await seedUnit(status: BloodUnitStatus.issued);
      expect(
        reserve.call(
          policy: policyWith(labTech),
          original: issued,
          patientId: 'patient-1',
          transfusionRequestId: 'req-1',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('reservation binds the unit to patient and request', () async {
      final BloodUnit available = await seedUnit();
      final BloodUnit reserved = await reserve.call(
        policy: policyWith(labTech),
        original: available,
        patientId: 'patient-1',
        transfusionRequestId: 'req-1',
      );

      expect(reserved.status, BloodUnitStatus.reserved);
      expect(reserved.patientId, 'patient-1');
      expect(reserved.transfusionRequestId, 'req-1');
    });

    test('issue requires a reservation', () async {
      final BloodUnit available = await seedUnit();
      expect(
        issue.call(policy: policyWith(labTech), original: available),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('issue requires an approved request', () async {
      await seedRequest(status: TransfusionRequestStatus.pending);
      final BloodUnit reserved = await seedUnit(
        status: BloodUnitStatus.reserved,
      );

      expect(
        issue.call(policy: policyWith(labTech), original: reserved),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'transfusion_request_not_approved',
          ),
        ),
      );
      expect(
        (await repository.bloodUnitById('unit-1'))!.status,
        BloodUnitStatus.reserved,
      );
    });

    test('issue advances the unit to issued', () async {
      await seedRequest(status: TransfusionRequestStatus.approved);
      final BloodUnit reserved = await seedUnit(
        status: BloodUnitStatus.reserved,
      );

      final BloodUnit issued = await issue.call(
        policy: policyWith(labTech),
        original: reserved,
      );
      expect(issued.status, BloodUnitStatus.issued);
      expect(issued.isIssued, isTrue);
    });

    test('discard freezes a collected unit', () async {
      final BloodUnit available = await seedUnit();
      final BloodUnit discarded = await discard.call(
        policy: policyWith(labTech),
        original: available,
      );
      expect(discarded.status, BloodUnitStatus.discarded);
      expect(discarded.isTerminal, isTrue);

      expect(
        discard.call(policy: policyWith(labTech), original: discarded),
        throwsA(isA<AuthorizationError>()),
      );
    });
  });

  group('transfusion administration', () {
    test('starting requires transfusion.administer', () {
      expect(
        startTransfusion.call(
          policy: policyWith(labTech),
          tenantId: 'tenant-1',
          transfusionRequestId: 'req-1',
          bloodUnitId: 'unit-1',
          patientId: 'patient-1',
          recordedBy: 'nurse-1',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('a started transfusion records against the unit', () async {
      await seedRequest(status: TransfusionRequestStatus.approved);
      await seedUnit(status: BloodUnitStatus.issued);

      final Transfusion transfusion = await startTransfusion.call(
        policy: policyWith(nurse),
        tenantId: 'tenant-1',
        transfusionRequestId: 'req-1',
        bloodUnitId: 'unit-1',
        patientId: 'patient-1',
        recordedBy: 'nurse-1',
      );

      expect(transfusion.status, TransfusionStatus.started);
      expect(transfusion.isComplete, isFalse);
      expect(
        (await repository.transfusionsForPatient('patient-1')).single.id,
        transfusion.id,
      );
    });

    test('an outcome other than started is required', () async {
      final Transfusion transfusion = await seedTransfusion(repository);
      expect(
        recordOutcome.call(
          policy: policyWith(nurse),
          original: transfusion,
          status: TransfusionStatus.started,
        ),
        throwsA(isA<ValidationError>()),
      );
    });

    test('a reaction requires notes', () async {
      final Transfusion transfusion = await seedTransfusion(repository);
      expect(
        recordOutcome.call(
          policy: policyWith(nurse),
          original: transfusion,
          status: TransfusionStatus.reaction,
        ),
        throwsA(isA<ValidationError>()),
      );
    });

    test('an outcome closes the record', () async {
      final Transfusion transfusion = await seedTransfusion(repository);
      final Transfusion closed = await recordOutcome.call(
        policy: policyWith(nurse),
        original: transfusion,
        status: TransfusionStatus.transfused,
        volumeMl: 450,
      );

      expect(closed.status, TransfusionStatus.transfused);
      expect(closed.isComplete, isTrue);
      expect(closed.finishedAt, isNotNull);
      expect(closed.volumeMl, 450);

      expect(
        recordOutcome.call(
          policy: policyWith(nurse),
          original: closed,
          status: TransfusionStatus.stopped,
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });
  });
}

Future<Transfusion> seedTransfusion(BloodBankRepository repository) async {
  final DateTime started = DateTime.utc(2026, 9, 2, 10);
  final Transfusion transfusion = Transfusion(
    id: 'tr-1',
    tenantId: 'tenant-1',
    transfusionRequestId: 'req-1',
    bloodUnitId: 'unit-1',
    patientId: 'patient-1',
    recordedBy: 'nurse-1',
    startedAt: started,
    status: TransfusionStatus.started,
    createdAt: started,
    updatedAt: started,
  );
  await repository.upsertTransfusion(transfusion);
  return transfusion;
}
