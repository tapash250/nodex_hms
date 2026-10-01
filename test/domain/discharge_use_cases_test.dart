/// Tests for the discharge use-case gates (Module 23).
///
/// Drafting rides on `encounter.write`; finalizing needs the online-only
/// `discharge.finalize`. Finalized records never mutate, and an encounter
/// holds at most one discharge.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/authorization_snapshot.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/domain/discharge/discharge.dart';
import 'package:nodex_hms/domain/discharge/discharge_management.dart';
import 'package:nodex_hms/domain/discharge/discharge_management_repository.dart';
import 'package:nodex_hms/domain/discharge/discharge_management_use_cases.dart';
import 'package:nodex_hms/domain/discharge/discharge_repository.dart';
import 'package:nodex_hms/domain/discharge/discharge_use_cases.dart';

import 'discharge_repository_test.dart' show FakeDischargeStore;

/// Builds a policy holding exactly [permissions].
AuthorizationPolicy policyWith(Set<String> permissions) {
  final DateTime issuedAt = DateTime.now().toUtc();
  return AuthorizationPolicy(
    snapshot: AuthorizationSnapshot(
      snapshotId: 'snapshot-1',
      tenantId: 'tenant-1',
      userId: 'doctor-1',
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
  late FakeDischargeStore store;
  late DefaultDischargeRepository repository;
  late DefaultDischargeManagementRepository management;
  late DraftDischargeUseCase draft;
  late FinalizeDischargeUseCase finalize;
  late CancelDischargeUseCase cancel;
  late RecordDischargeClearanceUseCase recordClearance;
  late GrantDischargeClearanceUseCase grantClearance;
  late StartDischargeReconciliationUseCase startReconciliation;
  late RecordDischargeMedicationUseCase recordMedication;
  late CompleteDischargeReconciliationUseCase completeReconciliation;
  late SettleDischargeBillingUseCase settle;

  const Set<String> writer = <String>{NodexPermissions.encounterWrite};
  const Set<String> finalizer = <String>{NodexPermissions.dischargeFinalize};
  const Set<String> reader = <String>{NodexPermissions.encounterRead};
  const Set<String> clinician = <String>{
    NodexPermissions.dischargeClearanceWrite,
  };
  const Set<String> pharmacist = <String>{
    NodexPermissions.dischargeReconciliationWrite,
  };
  const Set<String> accounts = <String>{NodexPermissions.billingSettle};

  setUp(() {
    store = FakeDischargeStore();
    repository = DefaultDischargeRepository(
      store: store,
      logger: NodexLogger(
        sinks: <NodexLogSink>[InMemoryLogSink()],
        minimumLevel: NodexLogLevel.trace,
      ),
    );
    management = DefaultDischargeManagementRepository(
      store: store,
      logger: NodexLogger(
        sinks: <NodexLogSink>[InMemoryLogSink()],
        minimumLevel: NodexLogLevel.trace,
      ),
    );
    draft = DraftDischargeUseCase(repository: repository);
    finalize = FinalizeDischargeUseCase(
      repository: repository,
      managementRepository: management,
    );
    cancel = CancelDischargeUseCase(repository: repository);
    recordClearance = RecordDischargeClearanceUseCase(repository: management);
    grantClearance = GrantDischargeClearanceUseCase(repository: management);
    startReconciliation = StartDischargeReconciliationUseCase(
      repository: management,
    );
    recordMedication = RecordDischargeMedicationUseCase(repository: management);
    completeReconciliation = CompleteDischargeReconciliationUseCase(
      repository: management,
    );
    settle = SettleDischargeBillingUseCase(repository: management);
  });

  Future<Discharge> seedDraft({String encounterId = 'enc-1'}) async {
    final String id = await draft.call(
      policy: policyWith(writer),
      tenantId: 'tenant-1',
      patientId: 'patient-1',
      encounterId: encounterId,
      createdBy: 'doctor-1',
      dischargeCode: 'D-001',
      dischargeType: DischargeType.routine,
    );
    return (await repository.getDischarge(id))!;
  }

  /// Satisfies the three readiness gates so a discharge can be authorized.
  Future<void> satisfyReadiness(Discharge record) async {
    await recordClearance.call(
      policy: policyWith(clinician),
      discharge: record,
      reviewedBy: 'doctor-1',
      outstandingItems: 0,
    );
    await grantClearance.call(
      policy: policyWith(clinician),
      discharge: record,
      clearedBy: 'doctor-1',
    );
    await startReconciliation.call(
      policy: policyWith(pharmacist),
      discharge: record,
    );
    await recordMedication.call(
      policy: policyWith(pharmacist),
      discharge: record,
      medicationName: 'Paracetamol',
      action: DischargeMedicationAction.continueMedication,
      recordedBy: 'nurse-1',
    );
    await completeReconciliation.call(
      policy: policyWith(pharmacist),
      discharge: record,
      reviewedBy: 'nurse-1',
    );
    await settle.call(
      policy: policyWith(accounts),
      discharge: record,
      invoiceId: 'invoice-1',
      amountMinor: 450000,
      settledBy: 'accounts-1',
    );
  }

  group('authorization gates', () {
    test('drafting requires encounter.write', () {
      expect(
        draft.call(
          policy: policyWith(reader),
          tenantId: 'tenant-1',
          patientId: 'patient-1',
          encounterId: 'enc-1',
          createdBy: 'doctor-1',
          dischargeCode: 'D-001',
          dischargeType: DischargeType.routine,
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('finalizing requires discharge.finalize', () async {
      final Discharge record = await seedDraft();
      await expectLater(
        finalize.call(
          policy: policyWith(writer),
          discharge: record,
          finalizerId: 'doctor-1',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });
  });

  group('readiness gate', () {
    test('finalizing without clearance is refused', () async {
      final Discharge record = await seedDraft();
      await expectLater(
        finalize.call(
          policy: policyWith(finalizer),
          discharge: record,
          finalizerId: 'doctor-1',
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'discharge_clearance_required',
          ),
        ),
      );
    });

    test('finalizing without reconciliation is refused', () async {
      final Discharge record = await seedDraft();
      await recordClearance.call(
        policy: policyWith(clinician),
        discharge: record,
        reviewedBy: 'doctor-1',
        outstandingItems: 0,
      );
      await grantClearance.call(
        policy: policyWith(clinician),
        discharge: record,
        clearedBy: 'doctor-1',
      );
      await expectLater(
        finalize.call(
          policy: policyWith(finalizer),
          discharge: record,
          finalizerId: 'doctor-1',
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'discharge_reconciliation_required',
          ),
        ),
      );
    });

    test('finalizing without settlement is refused', () async {
      final Discharge record = await seedDraft();
      await recordClearance.call(
        policy: policyWith(clinician),
        discharge: record,
        reviewedBy: 'doctor-1',
        outstandingItems: 0,
      );
      await grantClearance.call(
        policy: policyWith(clinician),
        discharge: record,
        clearedBy: 'doctor-1',
      );
      await startReconciliation.call(
        policy: policyWith(pharmacist),
        discharge: record,
      );
      await recordMedication.call(
        policy: policyWith(pharmacist),
        discharge: record,
        medicationName: 'Paracetamol',
        action: DischargeMedicationAction.continueMedication,
        recordedBy: 'nurse-1',
      );
      await completeReconciliation.call(
        policy: policyWith(pharmacist),
        discharge: record,
        reviewedBy: 'nurse-1',
      );
      await expectLater(
        finalize.call(
          policy: policyWith(finalizer),
          discharge: record,
          finalizerId: 'doctor-1',
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'discharge_settlement_required',
          ),
        ),
      );
    });
  });

  group('lifecycle', () {
    test('draft to finalized once the discharge is ready', () async {
      final Discharge record = await seedDraft();
      await satisfyReadiness(record);
      await finalize.call(
        policy: policyWith(finalizer),
        discharge: record,
        finalizerId: 'doctor-1',
      );
      final Discharge released = (await repository.getDischarge(record.id))!;
      expect(released.status, DischargeStatus.finalized);
      expect(released.finalizedBy, 'doctor-1');
    });

    test('an encounter holds at most one discharge', () async {
      await seedDraft();
      await expectLater(
        draft.call(
          policy: policyWith(writer),
          tenantId: 'tenant-1',
          patientId: 'patient-1',
          encounterId: 'enc-1',
          createdBy: 'doctor-1',
          dischargeCode: 'D-002',
          dischargeType: DischargeType.routine,
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('finalized records refuse finalizing again', () async {
      final Discharge record = await seedDraft();
      await satisfyReadiness(record);
      await finalize.call(
        policy: policyWith(finalizer),
        discharge: record,
        finalizerId: 'doctor-1',
      );
      final Discharge released = (await repository.getDischarge(record.id))!;
      await expectLater(
        finalize.call(
          policy: policyWith(finalizer),
          discharge: released,
          finalizerId: 'doctor-1',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('cancelling retires a draft with a reason', () async {
      final Discharge record = await seedDraft();
      await cancel.call(
        policy: policyWith(writer),
        discharge: record,
        reason: 'Wrong encounter',
      );
      final Discharge closed = (await repository.getDischarge(record.id))!;
      expect(closed.status, DischargeStatus.cancelled);
      expect(closed.closureReason, 'Wrong encounter');
    });
  });
}
