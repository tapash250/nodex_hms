/// Tests for the insurance use cases, cover derivation and the request and
/// claim state machines (Module 32).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/authorization_snapshot.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/domain/insurance/insurance.dart';
import 'package:nodex_hms/domain/insurance/insurance_repository.dart';
import 'package:nodex_hms/domain/insurance/insurance_use_cases.dart';

import 'insurance_repository_test.dart' show FakeInsuranceStore;

AuthorizationPolicy policyWith(Set<String> permissions) {
  final DateTime issuedAt = DateTime.now().toUtc();
  return AuthorizationPolicy(
    snapshot: AuthorizationSnapshot(
      snapshotId: 'snapshot-1',
      tenantId: 'tenant-1',
      userId: 'admin-1',
      deviceId: 'device-1',
      revision: 1,
      issuedAt: issuedAt,
      expiresAt: issuedAt.add(const Duration(days: 30)),
      payloadDigest: 'digest',
      roles: const <String>{NodexRoles.hospitalSuperAdmin},
      permissions: permissions,
      offlinePermissions: permissions,
      facilityIds: const <String>{'facility-1'},
      departmentIds: const <String>{},
      wardIds: const <String>{},
    ),
    connectivity: ConnectivityState.online,
  );
}

void main() {
  late FakeInsuranceStore store;
  late DefaultInsuranceRepository repository;
  late RegisterPayerUseCase registerPayer;
  late UpdatePayerUseCase updatePayer;
  late RegisterPolicyUseCase registerPolicy;
  late UpdatePolicyUseCase updatePolicy;
  late VerifyPolicyUseCase verifyPolicy;
  late CancelPolicyUseCase cancelPolicy;
  late RaisePreAuthorisationUseCase raisePreAuth;
  late AdvancePreAuthorisationUseCase advancePreAuth;
  late CreateClaimUseCase createClaim;
  late AdvanceClaimUseCase advanceClaim;
  late ReadInsuranceUseCase readInsurance;

  const Set<String> manage = <String>{NodexPermissions.insuranceManage};
  const Set<String> verify = <String>{NodexPermissions.insuranceVerify};
  const Set<String> claim = <String>{NodexPermissions.insuranceClaim};
  const Set<String> reader = <String>{NodexPermissions.insuranceRead};

  final DateTime now = DateTime.utc(2026, 6, 1);

  setUp(() {
    store = FakeInsuranceStore();
    repository = DefaultInsuranceRepository(
      store: store,
      logger: NodexLogger(
        sinks: <NodexLogSink>[InMemoryLogSink()],
        minimumLevel: NodexLogLevel.trace,
      ),
    );
    registerPayer = RegisterPayerUseCase(repository: repository);
    updatePayer = UpdatePayerUseCase(repository: repository);
    registerPolicy = RegisterPolicyUseCase(repository: repository);
    updatePolicy = UpdatePolicyUseCase(repository: repository);
    verifyPolicy = VerifyPolicyUseCase(repository: repository);
    cancelPolicy = CancelPolicyUseCase(repository: repository);
    raisePreAuth = RaisePreAuthorisationUseCase(repository: repository);
    advancePreAuth = AdvancePreAuthorisationUseCase(repository: repository);
    createClaim = CreateClaimUseCase(repository: repository);
    advanceClaim = AdvanceClaimUseCase(repository: repository);
    readInsurance = ReadInsuranceUseCase(repository: repository);
  });

  Future<InsurancePayer> aPayer({
    String code = 'INS-1',
    String name = 'Metlife',
    bool isActive = true,
  }) async {
    final String id = await registerPayer(
      policy: policyWith(manage),
      tenantId: 'tenant-1',
      createdBy: 'user-1',
      code: code,
      name: name,
      isActive: isActive,
    );
    return (await repository.payerById(id))!;
  }

  Future<InsurancePolicy> aPolicy({
    String policyNo = 'POL-1',
    String? payerId,
    String patientId = 'patient-1',
    DateTime? validTo,
  }) async {
    final String payer = payerId ?? (await aPayer(code: 'INS-$policyNo')).id;
    final String id = await registerPolicy(
      policy: policyWith(manage),
      tenantId: 'tenant-1',
      patientId: patientId,
      payerId: payer,
      createdBy: 'user-1',
      policyNo: policyNo,
      validFrom: DateTime.utc(2026, 1, 1),
      validTo: validTo ?? DateTime.utc(2027, 1, 1),
      sumInsuredMinor: 5000000,
    );
    return (await repository.policyById(id))!;
  }

  Future<PreAuthorisationRequest> aPreAuth(InsurancePolicy cover) async {
    final String id = await raisePreAuth(
      policy: policyWith(verify),
      tenantId: 'tenant-1',
      policyId: cover.id,
      patientId: cover.patientId,
      facilityId: 'facility-1',
      requestedBy: 'user-1',
      diagnosis: 'Cholecystitis',
      procedureText: 'Laparoscopic cholecystectomy',
      estimatedCostMinor: 12000000,
    );
    return (await repository.preAuthorisationById(id))!;
  }

  Future<InsuranceClaim> aClaim(
    InsurancePolicy cover, {
    String claimNo = 'CLM-1',
    int claimed = 9000000,
  }) async {
    final String id = await createClaim(
      policy: policyWith(claim),
      tenantId: 'tenant-1',
      policyId: cover.id,
      patientId: cover.patientId,
      facilityId: 'facility-1',
      createdBy: 'user-1',
      claimNo: claimNo,
      claimedAmountMinor: claimed,
    );
    return (await repository.claimById(id))!;
  }

  group('derived facts', () {
    test('policyCoverState lets cancellation win over the window', () {
      expect(
        policyCoverState(
          validTo: DateTime.utc(2027, 1, 1),
          now: now,
          cancelled: true,
        ),
        PolicyCoverState.cancelled,
      );
    });

    test('policyCoverState reads expired, expiring soon and active', () {
      expect(
        policyCoverState(validTo: DateTime.utc(2026, 5, 31), now: now),
        PolicyCoverState.expired,
      );
      expect(
        policyCoverState(validTo: DateTime.utc(2026, 6, 1), now: now),
        PolicyCoverState.expiringSoon,
      );
      expect(
        policyCoverState(validTo: DateTime.utc(2026, 6, 30), now: now),
        PolicyCoverState.expiringSoon,
      );
      expect(
        policyCoverState(validTo: DateTime.utc(2026, 7, 2), now: now),
        PolicyCoverState.active,
      );
    });

    test('claimRecoveryGap never goes negative', () {
      expect(claimRecoveryGap(claimedMinor: 900, settledMinor: 400), 500);
      expect(claimRecoveryGap(claimedMinor: 900, settledMinor: 900), 0);
      expect(claimRecoveryGap(claimedMinor: 900, settledMinor: 1200), 0);
    });

    test('preAuthCanTransition admits one stage at a time', () {
      expect(
        preAuthCanTransition(PreAuthStatus.requested, PreAuthStatus.submitted),
        isTrue,
      );
      expect(
        preAuthCanTransition(PreAuthStatus.submitted, PreAuthStatus.approved),
        isTrue,
      );
      expect(
        preAuthCanTransition(
          PreAuthStatus.submitted,
          PreAuthStatus.partiallyApproved,
        ),
        isTrue,
      );
      expect(
        preAuthCanTransition(PreAuthStatus.submitted, PreAuthStatus.rejected),
        isTrue,
      );
      expect(
        preAuthCanTransition(PreAuthStatus.requested, PreAuthStatus.approved),
        isFalse,
      );
      expect(
        preAuthCanTransition(PreAuthStatus.requested, PreAuthStatus.cancelled),
        isTrue,
      );
      expect(
        preAuthCanTransition(PreAuthStatus.approved, PreAuthStatus.cancelled),
        isFalse,
      );
    });

    test('claimCanTransition requires a decision before settlement', () {
      expect(
        claimCanTransition(ClaimStatus.draft, ClaimStatus.submitted),
        isTrue,
      );
      expect(
        claimCanTransition(ClaimStatus.submitted, ClaimStatus.underReview),
        isTrue,
      );
      expect(
        claimCanTransition(ClaimStatus.underReview, ClaimStatus.approved),
        isTrue,
      );
      expect(
        claimCanTransition(ClaimStatus.approved, ClaimStatus.settled),
        isTrue,
      );
      expect(
        claimCanTransition(ClaimStatus.partiallyApproved, ClaimStatus.settled),
        isTrue,
      );
      expect(
        claimCanTransition(ClaimStatus.submitted, ClaimStatus.settled),
        isFalse,
      );
      expect(
        claimCanTransition(ClaimStatus.underReview, ClaimStatus.cancelled),
        isTrue,
      );
      expect(
        claimCanTransition(ClaimStatus.settled, ClaimStatus.cancelled),
        isFalse,
      );
    });
  });

  group('payer registry', () {
    test('registering a payer requires insurance.manage', () async {
      await expectLater(
        registerPayer(
          policy: policyWith(verify),
          tenantId: 'tenant-1',
          createdBy: 'user-1',
          code: 'INS-1',
          name: 'Metlife',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('a duplicate payer code is refused', () async {
      await aPayer(code: 'INS-1');
      await expectLater(
        registerPayer(
          policy: policyWith(manage),
          tenantId: 'tenant-1',
          createdBy: 'user-1',
          code: 'INS-1',
          name: 'Duplicate',
        ),
        throwsA(isA<ValidationError>()),
      );
    });

    test('a payer can be edited and taken out of contract', () async {
      final InsurancePayer payer = await aPayer();
      await updatePayer(
        policy: policyWith(manage),
        payer: payer,
        code: 'INS-1',
        name: 'Metlife Bangladesh',
        isActive: false,
      );
      final InsurancePayer updated = (await repository.payerById(payer.id))!;
      expect(updated.name, 'Metlife Bangladesh');
      expect(updated.isActive, isFalse);
    });
  });

  group('cover', () {
    test('registering cover requires insurance.manage', () async {
      final InsurancePayer payer = await aPayer();
      await expectLater(
        registerPolicy(
          policy: policyWith(verify),
          tenantId: 'tenant-1',
          patientId: 'patient-1',
          payerId: payer.id,
          createdBy: 'user-1',
          policyNo: 'POL-1',
          validFrom: DateTime.utc(2026, 1, 1),
          validTo: DateTime.utc(2027, 1, 1),
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('cover cannot be registered against an unknown payer', () async {
      await expectLater(
        registerPolicy(
          policy: policyWith(manage),
          tenantId: 'tenant-1',
          patientId: 'patient-1',
          payerId: 'payer-missing',
          createdBy: 'user-1',
          policyNo: 'POL-1',
          validFrom: DateTime.utc(2026, 1, 1),
          validTo: DateTime.utc(2027, 1, 1),
        ),
        throwsA(isA<ValidationError>()),
      );
    });

    test(
      'cover cannot be registered against a payer out of contract',
      () async {
        final InsurancePayer payer = await aPayer(isActive: false);
        await expectLater(
          registerPolicy(
            policy: policyWith(manage),
            tenantId: 'tenant-1',
            patientId: 'patient-1',
            payerId: payer.id,
            createdBy: 'user-1',
            policyNo: 'POL-1',
            validFrom: DateTime.utc(2026, 1, 1),
            validTo: DateTime.utc(2027, 1, 1),
          ),
          throwsA(isA<ValidationError>()),
        );
      },
    );

    test('a policy number cannot be reused in a tenant', () async {
      final InsurancePolicy cover = await aPolicy(policyNo: 'POL-1');
      await expectLater(
        registerPolicy(
          policy: policyWith(manage),
          tenantId: 'tenant-1',
          patientId: 'patient-2',
          payerId: cover.payerId,
          createdBy: 'user-1',
          policyNo: 'POL-1',
          validFrom: DateTime.utc(2026, 1, 1),
          validTo: DateTime.utc(2027, 1, 1),
        ),
        throwsA(isA<ValidationError>()),
      );
    });

    test('a window cannot close before it opens', () async {
      final InsurancePayer payer = await aPayer();
      await expectLater(
        registerPolicy(
          policy: policyWith(manage),
          tenantId: 'tenant-1',
          patientId: 'patient-1',
          payerId: payer.id,
          createdBy: 'user-1',
          policyNo: 'POL-1',
          validFrom: DateTime.utc(2027, 1, 1),
          validTo: DateTime.utc(2026, 1, 1),
        ),
        throwsA(isA<ValidationError>()),
      );
    });

    test(
      'verification requires insurance.verify and records the verifier',
      () async {
        final InsurancePolicy cover = await aPolicy();
        await expectLater(
          verifyPolicy(
            policy: policyWith(reader),
            insurancePolicy: cover,
            verifiedBy: 'user-2',
          ),
          throwsA(isA<AuthorizationError>()),
        );
        await verifyPolicy(
          policy: policyWith(verify),
          insurancePolicy: cover,
          verifiedBy: 'user-2',
          reference: 'REF-9',
        );
        final InsurancePolicy verified = (await repository.policyById(
          cover.id,
        ))!;
        expect(verified.isVerified, isTrue);
        expect(verified.verifiedBy, 'user-2');
        expect(verified.verificationReference, 'REF-9');
      },
    );

    test(
      'cancellation requires insurance.manage, a reason and is one-way',
      () async {
        final InsurancePolicy cover = await aPolicy();
        await expectLater(
          cancelPolicy(
            policy: policyWith(verify),
            insurancePolicy: cover,
            reason: 'Withdrawn',
          ),
          throwsA(isA<AuthorizationError>()),
        );
        await expectLater(
          cancelPolicy(
            policy: policyWith(manage),
            insurancePolicy: cover,
            reason: '   ',
          ),
          throwsA(isA<ValidationError>()),
        );
        await cancelPolicy(
          policy: policyWith(manage),
          insurancePolicy: cover,
          reason: 'Employer withdrew the scheme',
        );
        final InsurancePolicy cancelled = (await repository.policyById(
          cover.id,
        ))!;
        expect(cancelled.status, PolicyStatus.cancelled);
        await expectLater(
          cancelPolicy(
            policy: policyWith(manage),
            insurancePolicy: cancelled,
            reason: 'Again',
          ),
          throwsA(isA<AuthorizationError>()),
        );
        await expectLater(
          verifyPolicy(
            policy: policyWith(verify),
            insurancePolicy: cancelled,
            verifiedBy: 'user-2',
          ),
          throwsA(isA<AuthorizationError>()),
        );
      },
    );

    test('a cancelled policy cannot be edited', () async {
      final InsurancePolicy cover = await aPolicy();
      await cancelPolicy(
        policy: policyWith(manage),
        insurancePolicy: cover,
        reason: 'Withdrawn',
      );
      final InsurancePolicy cancelled = (await repository.policyById(
        cover.id,
      ))!;
      await expectLater(
        updatePolicy(
          policy: policyWith(manage),
          insurancePolicy: cancelled,
          policyNo: 'POL-1',
          validFrom: DateTime.utc(2026, 1, 1),
          validTo: DateTime.utc(2028, 1, 1),
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });
  });

  group('pre-authorisation', () {
    test('raising a request requires insurance.verify', () async {
      final InsurancePolicy cover = await aPolicy();
      await expectLater(
        raisePreAuth(
          policy: policyWith(reader),
          tenantId: 'tenant-1',
          policyId: cover.id,
          patientId: cover.patientId,
          facilityId: 'facility-1',
          requestedBy: 'user-1',
          diagnosis: 'Cholecystitis',
          procedureText: 'Cholecystectomy',
          estimatedCostMinor: 12000000,
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('a request needs a known, live policy', () async {
      await expectLater(
        raisePreAuth(
          policy: policyWith(verify),
          tenantId: 'tenant-1',
          policyId: 'pol-missing',
          patientId: 'patient-1',
          facilityId: 'facility-1',
          requestedBy: 'user-1',
          diagnosis: 'Cholecystitis',
          procedureText: 'Cholecystectomy',
          estimatedCostMinor: 12000000,
        ),
        throwsA(isA<ValidationError>()),
      );

      final InsurancePolicy cover = await aPolicy();
      await cancelPolicy(
        policy: policyWith(manage),
        insurancePolicy: cover,
        reason: 'Withdrawn',
      );
      final InsurancePolicy cancelled = (await repository.policyById(
        cover.id,
      ))!;
      await expectLater(aPreAuth(cancelled), throwsA(isA<ValidationError>()));
    });

    test('a request starts live and moves one stage at a time', () async {
      final InsurancePolicy cover = await aPolicy();
      final PreAuthorisationRequest request = await aPreAuth(cover);
      expect(request.status, PreAuthStatus.requested);

      await expectLater(
        advancePreAuth(
          policy: policyWith(verify),
          request: request,
          to: PreAuthStatus.approved,
          approvedAmountMinor: 12000000,
        ),
        throwsA(isA<ValidationError>()),
      );

      await advancePreAuth(
        policy: policyWith(verify),
        request: request,
        to: PreAuthStatus.submitted,
      );
      final PreAuthorisationRequest submitted = (await repository
          .preAuthorisationById(request.id))!;
      expect(submitted.status, PreAuthStatus.submitted);
      expect(submitted.isLive, isTrue);
    });

    test('an approval carries an amount and freezes the request', () async {
      final InsurancePolicy cover = await aPolicy();
      final PreAuthorisationRequest request = await aPreAuth(cover);
      await advancePreAuth(
        policy: policyWith(verify),
        request: request,
        to: PreAuthStatus.submitted,
      );
      final PreAuthorisationRequest submitted = (await repository
          .preAuthorisationById(request.id))!;

      await expectLater(
        advancePreAuth(
          policy: policyWith(verify),
          request: submitted,
          to: PreAuthStatus.approved,
        ),
        throwsA(isA<ValidationError>()),
      );

      await advancePreAuth(
        policy: policyWith(verify),
        request: submitted,
        to: PreAuthStatus.partiallyApproved,
        approvedAmountMinor: 10000000,
        payerReference: 'PA-7',
        decisionNotes: 'Room rent capped',
      );
      final PreAuthorisationRequest answered = (await repository
          .preAuthorisationById(request.id))!;
      expect(answered.status, PreAuthStatus.partiallyApproved);
      expect(answered.approvedAmountMinor, 10000000);
      expect(answered.answeredAt, isNotNull);
      expect(answered.payerReference, 'PA-7');
      expect(answered.shortfallMinor, 2000000);
      expect(answered.isLive, isFalse);

      await expectLater(
        advancePreAuth(
          policy: policyWith(verify),
          request: answered,
          to: PreAuthStatus.cancelled,
          cancellationReason: 'Too late',
        ),
        throwsA(isA<ValidationError>()),
      );
    });

    test('an approval cannot exceed the estimate', () async {
      final InsurancePolicy cover = await aPolicy();
      final PreAuthorisationRequest request = await aPreAuth(cover);
      await advancePreAuth(
        policy: policyWith(verify),
        request: request,
        to: PreAuthStatus.submitted,
      );
      final PreAuthorisationRequest submitted = (await repository
          .preAuthorisationById(request.id))!;
      await expectLater(
        advancePreAuth(
          policy: policyWith(verify),
          request: submitted,
          to: PreAuthStatus.approved,
          approvedAmountMinor: 13000000,
        ),
        throwsA(isA<ValidationError>()),
      );
    });

    test(
      'a refusal must say why, and a live request can be withdrawn',
      () async {
        final InsurancePolicy cover = await aPolicy();
        final PreAuthorisationRequest request = await aPreAuth(cover);
        await advancePreAuth(
          policy: policyWith(verify),
          request: request,
          to: PreAuthStatus.submitted,
        );
        final PreAuthorisationRequest submitted = (await repository
            .preAuthorisationById(request.id))!;

        await expectLater(
          advancePreAuth(
            policy: policyWith(verify),
            request: submitted,
            to: PreAuthStatus.rejected,
          ),
          throwsA(isA<ValidationError>()),
        );
        await advancePreAuth(
          policy: policyWith(verify),
          request: submitted,
          to: PreAuthStatus.rejected,
          decisionNotes: 'Procedure not covered',
        );
        final PreAuthorisationRequest refused = (await repository
            .preAuthorisationById(request.id))!;
        expect(refused.status, PreAuthStatus.rejected);
        expect(refused.decisionNotes, 'Procedure not covered');
        expect(refused.approvedAmountMinor, isNull);
      },
    );

    test('a request is withdrawn with a reason', () async {
      final InsurancePolicy cover = await aPolicy();
      final PreAuthorisationRequest request = await aPreAuth(cover);
      await expectLater(
        advancePreAuth(
          policy: policyWith(verify),
          request: request,
          to: PreAuthStatus.cancelled,
        ),
        throwsA(isA<ValidationError>()),
      );
      await advancePreAuth(
        policy: policyWith(verify),
        request: request,
        to: PreAuthStatus.cancelled,
        cancellationReason: 'Patient chose another hospital',
      );
      final PreAuthorisationRequest withdrawn = (await repository
          .preAuthorisationById(request.id))!;
      expect(withdrawn.status, PreAuthStatus.cancelled);
      expect(withdrawn.cancellationReason, 'Patient chose another hospital');
    });
  });

  group('claims', () {
    test('creating a claim requires insurance.claim', () async {
      final InsurancePolicy cover = await aPolicy();
      await expectLater(
        createClaim(
          policy: policyWith(verify),
          tenantId: 'tenant-1',
          policyId: cover.id,
          patientId: cover.patientId,
          facilityId: 'facility-1',
          createdBy: 'user-1',
          claimNo: 'CLM-1',
          claimedAmountMinor: 9000000,
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('a claim number cannot be reused in a tenant', () async {
      final InsurancePolicy cover = await aPolicy();
      await aClaim(cover, claimNo: 'CLM-1');
      await expectLater(
        createClaim(
          policy: policyWith(claim),
          tenantId: 'tenant-1',
          policyId: cover.id,
          patientId: cover.patientId,
          facilityId: 'facility-1',
          createdBy: 'user-1',
          claimNo: 'CLM-1',
          claimedAmountMinor: 100,
        ),
        throwsA(isA<ValidationError>()),
      );
    });

    test(
      'a claim starts as a draft and settles only after a decision',
      () async {
        final InsurancePolicy cover = await aPolicy();
        final InsuranceClaim draft = await aClaim(cover);
        expect(draft.status, ClaimStatus.draft);
        expect(draft.recoveryGapMinor, 9000000);

        await expectLater(
          advanceClaim(
            policy: policyWith(claim),
            claim: draft,
            to: ClaimStatus.settled,
            settledAmountMinor: 9000000,
          ),
          throwsA(isA<ValidationError>()),
        );

        await advanceClaim(
          policy: policyWith(claim),
          claim: draft,
          to: ClaimStatus.submitted,
          payerReference: 'TRK-1',
        );
        InsuranceClaim current = (await repository.claimById(draft.id))!;
        expect(current.status, ClaimStatus.submitted);
        expect(current.submittedAt, isNotNull);

        await advanceClaim(
          policy: policyWith(claim),
          claim: current,
          to: ClaimStatus.underReview,
        );
        current = (await repository.claimById(draft.id))!;
        expect(current.status, ClaimStatus.underReview);

        await expectLater(
          advanceClaim(
            policy: policyWith(claim),
            claim: current,
            to: ClaimStatus.approved,
          ),
          throwsA(isA<ValidationError>()),
        );

        await advanceClaim(
          policy: policyWith(claim),
          claim: current,
          to: ClaimStatus.partiallyApproved,
          approvedAmountMinor: 6000000,
        );
        current = (await repository.claimById(draft.id))!;
        expect(current.status, ClaimStatus.partiallyApproved);
        expect(current.approvedAmountMinor, 6000000);

        await expectLater(
          advanceClaim(
            policy: policyWith(claim),
            claim: current,
            to: ClaimStatus.settled,
            settledAmountMinor: 7000000,
          ),
          throwsA(isA<ValidationError>()),
        );

        await advanceClaim(
          policy: policyWith(claim),
          claim: current,
          to: ClaimStatus.settled,
        );
        current = (await repository.claimById(draft.id))!;
        expect(current.status, ClaimStatus.settled);
        expect(current.settledAmountMinor, 6000000);
        expect(current.settledAt, isNotNull);
        expect(current.recoveryGapMinor, 3000000);
        expect(current.isOpen, isFalse);
      },
    );

    test('a refusal must say why and freezes the claim', () async {
      final InsurancePolicy cover = await aPolicy();
      InsuranceClaim current = await aClaim(cover);
      for (final ClaimStatus to in <ClaimStatus>[
        ClaimStatus.submitted,
        ClaimStatus.underReview,
      ]) {
        await advanceClaim(policy: policyWith(claim), claim: current, to: to);
        current = (await repository.claimById(current.id))!;
      }

      await expectLater(
        advanceClaim(
          policy: policyWith(claim),
          claim: current,
          to: ClaimStatus.rejected,
        ),
        throwsA(isA<ValidationError>()),
      );
      await advanceClaim(
        policy: policyWith(claim),
        claim: current,
        to: ClaimStatus.rejected,
        rejectionReason: 'Treatment not covered by the plan',
      );
      final InsuranceClaim refused = (await repository.claimById(current.id))!;
      expect(refused.status, ClaimStatus.rejected);
      expect(refused.rejectionReason, 'Treatment not covered by the plan');
      expect(refused.recoveryGapMinor, 9000000);

      await expectLater(
        advanceClaim(
          policy: policyWith(claim),
          claim: refused,
          to: ClaimStatus.cancelled,
          cancellationReason: 'Too late',
        ),
        throwsA(isA<ValidationError>()),
      );
    });

    test('a live claim can be withdrawn with a reason', () async {
      final InsurancePolicy cover = await aPolicy();
      final InsuranceClaim draft = await aClaim(cover);
      await expectLater(
        advanceClaim(
          policy: policyWith(claim),
          claim: draft,
          to: ClaimStatus.cancelled,
        ),
        throwsA(isA<ValidationError>()),
      );
      await advanceClaim(
        policy: policyWith(claim),
        claim: draft,
        to: ClaimStatus.cancelled,
        cancellationReason: 'Duplicate of CLM-0',
      );
      final InsuranceClaim withdrawn = (await repository.claimById(draft.id))!;
      expect(withdrawn.status, ClaimStatus.cancelled);
      expect(withdrawn.cancellationReason, 'Duplicate of CLM-0');
    });
  });

  group('reading', () {
    test('every read requires insurance.read', () async {
      await expectLater(
        readInsurance.payers(policy: policyWith(verify), tenantId: 'tenant-1'),
        throwsA(isA<AuthorizationError>()),
      );
      await expectLater(
        readInsurance.board(policy: policyWith(verify), tenantId: 'tenant-1'),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('the registry hides payers out of contract by default', () async {
      await aPayer(code: 'INS-1');
      await aPayer(code: 'INS-2', name: 'Guardian', isActive: false);
      expect(
        await readInsurance.payers(
          policy: policyWith(reader),
          tenantId: 'tenant-1',
        ),
        hasLength(1),
      );
      expect(
        await readInsurance.payers(
          policy: policyWith(reader),
          tenantId: 'tenant-1',
          includeInactive: true,
        ),
        hasLength(2),
      );
    });

    test('closed requests and claims can be filtered out', () async {
      final InsurancePolicy cover = await aPolicy();
      final PreAuthorisationRequest request = await aPreAuth(cover);
      await advancePreAuth(
        policy: policyWith(verify),
        request: request,
        to: PreAuthStatus.cancelled,
        cancellationReason: 'Not needed',
      );
      final InsuranceClaim draft = await aClaim(cover);
      await advanceClaim(
        policy: policyWith(claim),
        claim: draft,
        to: ClaimStatus.cancelled,
        cancellationReason: 'Duplicate',
      );

      expect(
        await readInsurance.preAuthorisations(
          policy: policyWith(reader),
          tenantId: 'tenant-1',
        ),
        hasLength(1),
      );
      expect(
        await readInsurance.preAuthorisations(
          policy: policyWith(reader),
          tenantId: 'tenant-1',
          includeClosed: false,
        ),
        isEmpty,
      );
      expect(
        await readInsurance.claims(
          policy: policyWith(reader),
          tenantId: 'tenant-1',
          includeClosed: false,
        ),
        isEmpty,
      );
    });

    test('the board derives cover state, sorts by attention and sums the gap', () async {
      await aPolicy(policyNo: 'POL-A', validTo: DateTime.utc(2026, 5, 1));
      final InsurancePolicy expiring = await aPolicy(
        policyNo: 'POL-B',
        validTo: DateTime.utc(2026, 6, 10),
      );
      final InsurancePolicy active = await aPolicy(
        policyNo: 'POL-C',
        validTo: DateTime.utc(2027, 1, 1),
      );
      final InsurancePolicy toCancel = await aPolicy(
        policyNo: 'POL-D',
        validTo: DateTime.utc(2027, 1, 1),
      );
      await cancelPolicy(
        policy: policyWith(manage),
        insurancePolicy: toCancel,
        reason: 'Withdrawn',
      );

      // Two claims on the active cover — one live, one withdrawn: only the live
      // claim counts as open and only its gap reaches the board.
      final InsuranceClaim live = await aClaim(active, claimNo: 'CLM-L');
      final InsuranceClaim withdrawn = await aClaim(active, claimNo: 'CLM-R');
      await advanceClaim(
        policy: policyWith(claim),
        claim: withdrawn,
        to: ClaimStatus.cancelled,
        cancellationReason: 'Duplicate',
      );

      // A request on the expiring cover counts as open.
      final PreAuthorisationRequest request = await aPreAuth(expiring);
      expect(request.isLive, isTrue);

      final List<PolicyBoardEntry> board = await readInsurance.board(
        policy: policyWith(reader),
        tenantId: 'tenant-1',
        now: now,
      );
      expect(
        board.map((PolicyBoardEntry entry) => entry.policy.policyNo).toList(),
        <String>['POL-A', 'POL-B', 'POL-C', 'POL-D'],
      );
      expect(board[0].coverState, PolicyCoverState.expired);
      expect(board[0].needsAttention, isTrue);
      expect(board[1].coverState, PolicyCoverState.expiringSoon);
      expect(board[1].openPreAuthorisationCount, 1);
      expect(board[2].coverState, PolicyCoverState.active);
      expect(board[2].needsAttention, isTrue);
      expect(board[2].openClaimCount, 1);
      expect(board[2].recoveryGapMinor, live.recoveryGapMinor);
      expect(board[3].coverState, PolicyCoverState.cancelled);
    });

    test(
      'the board can be narrowed to one patient through the lists',
      () async {
        final InsurancePolicy mine = await aPolicy(
          policyNo: 'POL-1',
          patientId: 'patient-1',
        );
        await aPolicy(policyNo: 'POL-2', patientId: 'patient-2');
        expect(
          await readInsurance.policies(
            policy: policyWith(reader),
            tenantId: 'tenant-1',
            patientId: 'patient-1',
          ),
          hasLength(1),
        );
        expect(mine.patientId, 'patient-1');
      },
    );
  });
}
