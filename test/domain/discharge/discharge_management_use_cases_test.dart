/// Tests for the discharge management use-case chain (Module 23).
///
/// A patient passes through clinical clearance, medication reconciliation,
/// billing settlement and an optional reviewed AI summary before the discharge
/// can be authorized. Each step gates on its permission and refuses to run out
/// of order, and finalizing requires all three safety gates.
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

import 'discharge_management_repository_test.dart' show FakeDischargeStore;

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
  late FakeDischargeStore store;
  late DefaultDischargeManagementRepository repository;
  late RecordDischargeClearanceUseCase recordClearance;
  late GrantDischargeClearanceUseCase grantClearance;
  late StartDischargeReconciliationUseCase startReconciliation;
  late RecordDischargeMedicationUseCase recordMedication;
  late CompleteDischargeReconciliationUseCase completeReconciliation;
  late SettleDischargeBillingUseCase settle;
  late RecordDischargeAiSummaryUseCase recordSummary;
  late AcceptDischargeAiSummaryUseCase acceptSummary;
  late RejectDischargeAiSummaryUseCase rejectSummary;
  late CheckDischargeReadinessUseCase readiness;

  const Set<String> clinician = <String>{
    NodexPermissions.dischargeClearanceWrite,
  };
  const Set<String> pharmacist = <String>{
    NodexPermissions.dischargeReconciliationWrite,
  };
  const Set<String> accounts = <String>{NodexPermissions.billingSettle};
  const Set<String> reviewer = <String>{
    NodexPermissions.dischargeSummaryReview,
  };

  setUp(() {
    store = FakeDischargeStore();
    repository = DefaultDischargeManagementRepository(
      store: store,
      logger: NodexLogger(
        sinks: <NodexLogSink>[InMemoryLogSink()],
        minimumLevel: NodexLogLevel.trace,
      ),
    );
    recordClearance = RecordDischargeClearanceUseCase(repository: repository);
    grantClearance = GrantDischargeClearanceUseCase(repository: repository);
    startReconciliation = StartDischargeReconciliationUseCase(
      repository: repository,
    );
    recordMedication = RecordDischargeMedicationUseCase(repository: repository);
    completeReconciliation = CompleteDischargeReconciliationUseCase(
      repository: repository,
    );
    settle = SettleDischargeBillingUseCase(repository: repository);
    recordSummary = RecordDischargeAiSummaryUseCase(repository: repository);
    acceptSummary = AcceptDischargeAiSummaryUseCase(repository: repository);
    rejectSummary = RejectDischargeAiSummaryUseCase(repository: repository);
    readiness = CheckDischargeReadinessUseCase(repository: repository);
  });

  // Seeded rows predate "now" so a use case re-stamping `updatedAt` moves the
  // clock forward rather than backwards.
  DateTime at(int hour) => DateTime.utc(2026, 9, 1, hour);

  Discharge draftDischarge({
    String id = 'discharge-1',
    DischargeStatus status = DischargeStatus.draft,
  }) => Discharge(
    id: id,
    tenantId: 'tenant-1',
    patientId: 'patient-1',
    encounterId: 'encounter-1',
    createdBy: 'doctor-1',
    dischargeCode: 'DC-00$id',
    dischargeType: DischargeType.routine,
    status: status,
    createdAt: at(8),
  );

  /// Drives the chain to the point where a discharge may be authorized.
  Future<Discharge> clearedReconciledSettled() async {
    final Discharge discharge = draftDischarge();
    await recordClearance.call(
      policy: policyWith(clinician),
      discharge: discharge,
      reviewedBy: 'doctor-1',
      outstandingItems: 0,
    );
    await grantClearance.call(
      policy: policyWith(clinician),
      discharge: discharge,
      clearedBy: 'doctor-1',
    );
    await startReconciliation.call(
      policy: policyWith(pharmacist),
      discharge: discharge,
    );
    await recordMedication.call(
      policy: policyWith(pharmacist),
      discharge: discharge,
      medicationName: 'Paracetamol',
      action: DischargeMedicationAction.continueMedication,
      recordedBy: 'nurse-1',
    );
    await recordMedication.call(
      policy: policyWith(pharmacist),
      discharge: discharge,
      medicationName: 'Warfarin',
      action: DischargeMedicationAction.hold,
      recordedBy: 'nurse-1',
    );
    await completeReconciliation.call(
      policy: policyWith(pharmacist),
      discharge: discharge,
      reviewedBy: 'nurse-1',
    );
    await settle.call(
      policy: policyWith(accounts),
      discharge: discharge,
      invoiceId: 'invoice-1',
      amountMinor: 450000,
      settledBy: 'accounts-1',
    );
    return discharge;
  }

  group('clinical clearance', () {
    test('recording a review requires discharge_clearance.write', () {
      expect(
        recordClearance.call(
          policy: policyWith(pharmacist),
          discharge: draftDischarge(),
          reviewedBy: 'doctor-1',
          outstandingItems: 0,
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('a closed discharge takes no clearance', () {
      expect(
        recordClearance.call(
          policy: policyWith(clinician),
          discharge: draftDischarge(status: DischargeStatus.finalized),
          reviewedBy: 'doctor-1',
          outstandingItems: 0,
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'discharge_closed',
          ),
        ),
      );
    });

    test('a negative outstanding count is rejected', () {
      expect(
        recordClearance.call(
          policy: policyWith(clinician),
          discharge: draftDischarge(),
          reviewedBy: 'doctor-1',
          outstandingItems: -1,
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'discharge_clearance_invalid',
          ),
        ),
      );
    });

    test('clearance cannot be granted before a review exists', () {
      expect(
        grantClearance.call(
          policy: policyWith(clinician),
          discharge: draftDischarge(),
          clearedBy: 'doctor-1',
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'discharge_clearance_missing',
          ),
        ),
      );
    });

    test('outstanding items block the grant', () async {
      final Discharge discharge = draftDischarge();
      await recordClearance.call(
        policy: policyWith(clinician),
        discharge: discharge,
        reviewedBy: 'doctor-1',
        outstandingItems: 2,
      );
      expect(
        grantClearance.call(
          policy: policyWith(clinician),
          discharge: discharge,
          clearedBy: 'doctor-1',
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'discharge_clearance_outstanding',
          ),
        ),
      );
    });

    test('resolving the outstanding items permits the grant', () async {
      final Discharge discharge = draftDischarge();
      await recordClearance.call(
        policy: policyWith(clinician),
        discharge: discharge,
        reviewedBy: 'doctor-1',
        outstandingItems: 2,
      );
      await recordClearance.call(
        policy: policyWith(clinician),
        discharge: discharge,
        reviewedBy: 'doctor-1',
        outstandingItems: 0,
      );
      final DischargeClearance cleared = await grantClearance.call(
        policy: policyWith(clinician),
        discharge: discharge,
        clearedBy: 'doctor-2',
      );

      expect(cleared.isCleared, isTrue);
      expect(cleared.clearedBy, 'doctor-2');
      expect(cleared.clearedAt, isNotNull);
      expect(
        grantClearance.call(
          policy: policyWith(clinician),
          discharge: discharge,
          clearedBy: 'doctor-3',
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'discharge_clearance_closed',
          ),
        ),
      );
    });
  });

  group('medication reconciliation', () {
    test('starting requires discharge_reconciliation.write', () {
      expect(
        startReconciliation.call(
          policy: policyWith(clinician),
          discharge: draftDischarge(),
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('a discharge carries one reconciliation', () async {
      final Discharge discharge = draftDischarge();
      await startReconciliation.call(
        policy: policyWith(pharmacist),
        discharge: discharge,
      );
      expect(
        startReconciliation.call(
          policy: policyWith(pharmacist),
          discharge: discharge,
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'discharge_reconciliation_exists',
          ),
        ),
      );
    });

    test('a decision needs the reconciliation to exist', () {
      expect(
        recordMedication.call(
          policy: policyWith(pharmacist),
          discharge: draftDischarge(),
          medicationName: 'Paracetamol',
          action: DischargeMedicationAction.continueMedication,
          recordedBy: 'nurse-1',
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'discharge_reconciliation_missing',
          ),
        ),
      );
    });

    test('a decision needs the medication name', () async {
      final Discharge discharge = draftDischarge();
      await startReconciliation.call(
        policy: policyWith(pharmacist),
        discharge: discharge,
      );
      expect(
        recordMedication.call(
          policy: policyWith(pharmacist),
          discharge: discharge,
          medicationName: '  ',
          action: DischargeMedicationAction.continueMedication,
          recordedBy: 'nurse-1',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'discharge_medication_invalid',
          ),
        ),
      );
    });

    test(
      'a decision is flagged as a discrepancy unless it continues',
      () async {
        final Discharge discharge = draftDischarge();
        await startReconciliation.call(
          policy: policyWith(pharmacist),
          discharge: discharge,
        );
        final DischargeMedicationReconciliationItem stop =
            await recordMedication.call(
              policy: policyWith(pharmacist),
              discharge: discharge,
              medicationName: ' Warfarin ',
              action: DischargeMedicationAction.stop,
              recordedBy: 'nurse-1',
            );
        expect(stop.medicationName, 'Warfarin');
        expect(stop.discrepancy, isTrue);

        final DischargeMedicationReconciliationItem keep =
            await recordMedication.call(
              policy: policyWith(pharmacist),
              discharge: discharge,
              medicationName: 'Paracetamol',
              action: DischargeMedicationAction.continueMedication,
              recordedBy: 'nurse-1',
            );
        expect(keep.discrepancy, isFalse);
      },
    );

    test('a reconciliation that reviewed nothing cannot complete', () async {
      final Discharge discharge = draftDischarge();
      await startReconciliation.call(
        policy: policyWith(pharmacist),
        discharge: discharge,
      );
      expect(
        completeReconciliation.call(
          policy: policyWith(pharmacist),
          discharge: discharge,
          reviewedBy: 'nurse-1',
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'discharge_reconciliation_empty',
          ),
        ),
      );
    });

    test('completing records the reviewed and discrepancy counts', () async {
      final Discharge discharge = draftDischarge();
      await startReconciliation.call(
        policy: policyWith(pharmacist),
        discharge: discharge,
      );
      await recordMedication.call(
        policy: policyWith(pharmacist),
        discharge: discharge,
        medicationName: 'Paracetamol',
        action: DischargeMedicationAction.continueMedication,
        recordedBy: 'nurse-1',
      );
      await recordMedication.call(
        policy: policyWith(pharmacist),
        discharge: discharge,
        medicationName: 'Warfarin',
        action: DischargeMedicationAction.stop,
        recordedBy: 'nurse-1',
      );
      await recordMedication.call(
        policy: policyWith(pharmacist),
        discharge: discharge,
        medicationName: 'Ibuprofen',
        action: DischargeMedicationAction.hold,
        recordedBy: 'nurse-1',
      );

      final DischargeMedicationReconciliation done =
          await completeReconciliation.call(
            policy: policyWith(pharmacist),
            discharge: discharge,
            reviewedBy: 'nurse-1',
          );

      expect(done.isReconciled, isTrue);
      expect(done.medicationsReviewed, 3);
      expect(done.discrepanciesFound, 2);
      expect(done.reviewedBy, 'nurse-1');
    });

    test('a completed reconciliation takes no further decisions', () async {
      final Discharge discharge = draftDischarge();
      await startReconciliation.call(
        policy: policyWith(pharmacist),
        discharge: discharge,
      );
      await recordMedication.call(
        policy: policyWith(pharmacist),
        discharge: discharge,
        medicationName: 'Paracetamol',
        action: DischargeMedicationAction.continueMedication,
        recordedBy: 'nurse-1',
      );
      await completeReconciliation.call(
        policy: policyWith(pharmacist),
        discharge: discharge,
        reviewedBy: 'nurse-1',
      );

      expect(
        recordMedication.call(
          policy: policyWith(pharmacist),
          discharge: discharge,
          medicationName: 'Morphine',
          action: DischargeMedicationAction.continueMedication,
          recordedBy: 'nurse-1',
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'discharge_reconciliation_closed',
          ),
        ),
      );
      expect(
        completeReconciliation.call(
          policy: policyWith(pharmacist),
          discharge: discharge,
          reviewedBy: 'nurse-1',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });
  });

  group('billing settlement', () {
    test('settling requires billing.settle', () {
      expect(
        settle.call(
          policy: policyWith(clinician),
          discharge: draftDischarge(),
          invoiceId: 'invoice-1',
          amountMinor: 100,
          settledBy: 'accounts-1',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('settlement waits for the reconciliation', () {
      expect(
        settle.call(
          policy: policyWith(accounts),
          discharge: draftDischarge(),
          invoiceId: 'invoice-1',
          amountMinor: 100,
          settledBy: 'accounts-1',
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

    test('settlement validates the invoice and amount', () async {
      final Discharge discharge = draftDischarge();
      await startReconciliation.call(
        policy: policyWith(pharmacist),
        discharge: discharge,
      );
      await recordMedication.call(
        policy: policyWith(pharmacist),
        discharge: discharge,
        medicationName: 'Paracetamol',
        action: DischargeMedicationAction.continueMedication,
        recordedBy: 'nurse-1',
      );
      await completeReconciliation.call(
        policy: policyWith(pharmacist),
        discharge: discharge,
        reviewedBy: 'nurse-1',
      );

      expect(
        settle.call(
          policy: policyWith(accounts),
          discharge: discharge,
          invoiceId: '  ',
          amountMinor: 100,
          settledBy: 'accounts-1',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'discharge_settlement_invalid',
          ),
        ),
      );
      expect(
        settle.call(
          policy: policyWith(accounts),
          discharge: discharge,
          invoiceId: 'invoice-1',
          amountMinor: -5,
          settledBy: 'accounts-1',
        ),
        throwsA(isA<ValidationError>()),
      );
    });

    test('a discharge settles once', () async {
      final Discharge discharge = await clearedReconciledSettled();
      expect(
        settle.call(
          policy: policyWith(accounts),
          discharge: discharge,
          invoiceId: 'invoice-2',
          amountMinor: 200,
          settledBy: 'accounts-1',
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'discharge_settlement_exists',
          ),
        ),
      );
    });
  });

  group('AI summary', () {
    test('filing requires discharge_clearance.write', () {
      expect(
        recordSummary.call(
          policy: policyWith(pharmacist),
          discharge: draftDischarge(),
          modelId: 'clinical-summarizer-v2',
          summaryText: 'Admitted with pneumonia.',
          safetyDecision: 'allow',
          requestedBy: 'doctor-1',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('a summary is generated only after clearance', () {
      expect(
        recordSummary.call(
          policy: policyWith(clinician),
          discharge: draftDischarge(),
          modelId: 'clinical-summarizer-v2',
          summaryText: 'Admitted with pneumonia.',
          safetyDecision: 'allow',
          requestedBy: 'doctor-1',
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

    test('a summary needs model, text and safety decision', () async {
      final Discharge discharge = draftDischarge();
      await recordClearance.call(
        policy: policyWith(clinician),
        discharge: discharge,
        reviewedBy: 'doctor-1',
        outstandingItems: 0,
      );
      await grantClearance.call(
        policy: policyWith(clinician),
        discharge: discharge,
        clearedBy: 'doctor-1',
      );
      expect(
        recordSummary.call(
          policy: policyWith(clinician),
          discharge: discharge,
          modelId: ' ',
          summaryText: ' ',
          safetyDecision: ' ',
          requestedBy: 'doctor-1',
        ),
        throwsA(
          isA<ValidationError>()
              .having(
                (ValidationError error) => error.code,
                'code',
                'discharge_ai_summary_invalid',
              )
              .having(
                (ValidationError error) => error.fieldErrors.keys,
                'fields',
                containsAll(<String>{
                  'model_id',
                  'summary_text',
                  'safety_decision',
                }),
              ),
        ),
      );
    });

    test('a generated summary awaits review', () async {
      final Discharge discharge = draftDischarge();
      await recordClearance.call(
        policy: policyWith(clinician),
        discharge: discharge,
        reviewedBy: 'doctor-1',
        outstandingItems: 0,
      );
      await grantClearance.call(
        policy: policyWith(clinician),
        discharge: discharge,
        clearedBy: 'doctor-1',
      );
      final DischargeAiSummary summary = await recordSummary.call(
        policy: policyWith(clinician),
        discharge: discharge,
        modelId: ' clinical-summarizer-v2 ',
        summaryText: ' Admitted with pneumonia. ',
        safetyDecision: ' allow ',
        requestedBy: 'doctor-1',
      );

      expect(summary.isPendingReview, isTrue);
      expect(summary.modelId, 'clinical-summarizer-v2');
      expect(summary.summaryText, 'Admitted with pneumonia.');
      expect(summary.reviewedBy, isNull);
    });

    test('accepting requires discharge_summary.review', () async {
      final Discharge discharge = draftDischarge();
      await recordClearance.call(
        policy: policyWith(clinician),
        discharge: discharge,
        reviewedBy: 'doctor-1',
        outstandingItems: 0,
      );
      await grantClearance.call(
        policy: policyWith(clinician),
        discharge: discharge,
        clearedBy: 'doctor-1',
      );
      await recordSummary.call(
        policy: policyWith(clinician),
        discharge: discharge,
        modelId: 'clinical-summarizer-v2',
        summaryText: 'Admitted with pneumonia.',
        safetyDecision: 'allow',
        requestedBy: 'doctor-1',
      );
      expect(
        acceptSummary.call(
          policy: policyWith(clinician),
          discharge: discharge,
          reviewedBy: 'doctor-2',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('acceptance preserves the generated text', () async {
      final Discharge discharge = draftDischarge();
      await recordClearance.call(
        policy: policyWith(clinician),
        discharge: discharge,
        reviewedBy: 'doctor-1',
        outstandingItems: 0,
      );
      await grantClearance.call(
        policy: policyWith(clinician),
        discharge: discharge,
        clearedBy: 'doctor-1',
      );
      await recordSummary.call(
        policy: policyWith(clinician),
        discharge: discharge,
        modelId: 'clinical-summarizer-v2',
        summaryText: 'Admitted with pneumonia.',
        safetyDecision: 'allow',
        requestedBy: 'doctor-1',
      );

      final DischargeAiSummary accepted = await acceptSummary.call(
        policy: policyWith(reviewer),
        discharge: discharge,
        reviewedBy: 'doctor-2',
      );

      expect(accepted.isAccepted, isTrue);
      expect(accepted.reviewedBy, 'doctor-2');
      expect(accepted.reviewedAt, isNotNull);
      expect(accepted.summaryText, 'Admitted with pneumonia.');
      expect(
        acceptSummary.call(
          policy: policyWith(reviewer),
          discharge: discharge,
          reviewedBy: 'doctor-3',
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'discharge_ai_summary_reviewed',
          ),
        ),
      );
    });

    test('rejection needs a reason and freezes the decision', () async {
      final Discharge discharge = draftDischarge();
      await recordClearance.call(
        policy: policyWith(clinician),
        discharge: discharge,
        reviewedBy: 'doctor-1',
        outstandingItems: 0,
      );
      await grantClearance.call(
        policy: policyWith(clinician),
        discharge: discharge,
        clearedBy: 'doctor-1',
      );
      await recordSummary.call(
        policy: policyWith(clinician),
        discharge: discharge,
        modelId: 'clinical-summarizer-v2',
        summaryText: 'Admitted with pneumonia.',
        safetyDecision: 'allow',
        requestedBy: 'doctor-1',
      );

      expect(
        rejectSummary.call(
          policy: policyWith(reviewer),
          discharge: discharge,
          reviewedBy: 'doctor-2',
          reason: ' ',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'discharge_ai_summary_rejection_reason_required',
          ),
        ),
      );

      final DischargeAiSummary rejected = await rejectSummary.call(
        policy: policyWith(reviewer),
        discharge: discharge,
        reviewedBy: 'doctor-2',
        reason: ' Omits the penicillin allergy. ',
      );
      expect(rejected.status, DischargeAiSummaryStatus.rejected);
      expect(rejected.rejectionReason, 'Omits the penicillin allergy.');
    });
  });

  group('readiness', () {
    test('an untouched draft is not ready', () async {
      final DischargeReadiness state = await readiness.call(draftDischarge());
      expect(state.canFinalize, isFalse);
      expect(state.cleared, isFalse);
      expect(state.reconciled, isFalse);
      expect(state.settled, isFalse);
    });

    test('clearance alone is not enough', () async {
      final Discharge discharge = draftDischarge();
      await recordClearance.call(
        policy: policyWith(clinician),
        discharge: discharge,
        reviewedBy: 'doctor-1',
        outstandingItems: 0,
      );
      await grantClearance.call(
        policy: policyWith(clinician),
        discharge: discharge,
        clearedBy: 'doctor-1',
      );

      final DischargeReadiness state = await readiness.call(discharge);
      expect(state.cleared, isTrue);
      expect(state.reconciled, isFalse);
      expect(state.canFinalize, isFalse);
    });

    test('pending medications are reported while the review is open', () async {
      final Discharge discharge = draftDischarge();
      await startReconciliation.call(
        policy: policyWith(pharmacist),
        discharge: discharge,
      );
      await recordMedication.call(
        policy: policyWith(pharmacist),
        discharge: discharge,
        medicationName: 'Paracetamol',
        action: DischargeMedicationAction.continueMedication,
        recordedBy: 'nurse-1',
      );

      final DischargeReadiness state = await readiness.call(discharge);
      expect(state.pendingMedications, 1);
      expect(state.reconciled, isFalse);
    });

    test(
      'the full chain reports ready, with or without an AI summary',
      () async {
        final Discharge discharge = await clearedReconciledSettled();
        final DischargeReadiness state = await readiness.call(discharge);

        expect(state.canFinalize, isTrue);
        expect(state.cleared, isTrue);
        expect(state.reconciled, isTrue);
        expect(state.settled, isTrue);
        expect(state.pendingMedications, 0);
        expect(
          state.aiSummaryReviewed,
          isFalse,
          reason: 'an AI summary is optional',
        );
      },
    );
  });
}
