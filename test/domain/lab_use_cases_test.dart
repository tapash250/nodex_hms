/// Tests for the laboratory use-case gates (Module 17).
///
/// The entities are covered by `lab_test.dart`; this file pins the
/// workflow that sits on top of them: who may order, enter, collect,
/// verify and correct, and — critically — that a verified result is
/// never edited in place. Corrections must be explicit new rows that
/// name their reason and link back to the original.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/authorization_snapshot.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/laboratory/lab.dart';
import 'package:nodex_hms/domain/laboratory/lab_repository.dart';
import 'package:nodex_hms/domain/laboratory/lab_use_cases.dart';

/// Records what the laboratory commands were asked to write.
final class RecordingLabRepository implements LabRepository {
  final List<Map<String, Object?>> orders = <Map<String, Object?>>[];
  final List<Map<String, Object?>> specimens = <Map<String, Object?>>[];
  final List<Map<String, Object?>> collected = <Map<String, Object?>>[];
  final List<Map<String, Object?>> results = <Map<String, Object?>>[];
  final List<Map<String, Object?>> verifications = <Map<String, Object?>>[];
  final List<Map<String, Object?>> corrections = <Map<String, Object?>>[];

  @override
  Future<List<LabOrder>> listOrdersForPatient(String patientId) async =>
      <LabOrder>[];

  @override
  Future<LabOrder?> getOrder(String id) async => null;

  @override
  Future<List<LabSpecimen>> listSpecimens(String orderId) async =>
      <LabSpecimen>[];

  @override
  Future<List<LabResult>> listResults(String orderId) async => <LabResult>[];

  @override
  Future<String> createOrder(Map<String, Object?> row) async {
    orders.add(row);
    return 'order-new';
  }

  @override
  Future<String> createSpecimen(Map<String, Object?> row) async {
    specimens.add(row);
    return 'specimen-new';
  }

  @override
  Future<void> collectSpecimen(String id, Map<String, Object?> changes) async {
    collected.add(<String, Object?>{'id': id, ...changes});
  }

  @override
  Future<String> enterResult(Map<String, Object?> row) async {
    results.add(row);
    return 'result-new';
  }

  @override
  Future<void> verifyResult(String id, Map<String, Object?> changes) async {
    verifications.add(<String, Object?>{'id': id, ...changes});
  }

  @override
  Future<String> correctResult(Map<String, Object?> row) async {
    corrections.add(row);
    return 'result-correction';
  }
}

/// Builds a policy holding exactly [permissions].
AuthorizationPolicy policyWith(Set<String> permissions) {
  final DateTime issuedAt = DateTime.now().toUtc();
  return AuthorizationPolicy(
    snapshot: AuthorizationSnapshot(
      snapshotId: 'snapshot-1',
      tenantId: 'tenant-1',
      userId: 'tech-1',
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

/// A stored result in [status], owned by the standard fixture identity.
LabResult resultWith({
  LabResultStatus status = LabResultStatus.entered,
  String id = 'result-1',
}) => LabResult(
  id: id,
  tenantId: 'tenant-1',
  labOrderId: 'order-1',
  specimenId: 'specimen-1',
  analyteCode: 'HB',
  analyteName: 'Haemoglobin',
  status: status,
  enteredBy: 'tech-1',
  enteredAt: DateTime.utc(2026, 9, 12, 10),
  valueText: '13.2',
  unit: 'g/dL',
  referenceRange: '13.0-17.0',
  abnormalFlag: 'normal',
  verifiedBy: status == LabResultStatus.verified ? 'doctor-1' : null,
  verifiedAt: status == LabResultStatus.verified
      ? DateTime.utc(2026, 9, 12, 10, 5)
      : null,
);

void main() {
  late RecordingLabRepository repository;
  late CreateLabOrderUseCase createOrder;
  late RegisterSpecimenUseCase registerSpecimen;
  late CollectSpecimenUseCase collectSpecimen;
  late EnterLabResultUseCase enterResult;
  late VerifyLabResultUseCase verifyResult;
  late CorrectLabResultUseCase correctResult;

  const Set<String> orderer = <String>{NodexPermissions.labOrderWrite};
  const Set<String> enterer = <String>{NodexPermissions.labResultEnter};
  const Set<String> verifier = <String>{NodexPermissions.labResultVerify};
  const Set<String> reader = <String>{NodexPermissions.encounterRead};

  setUp(() {
    repository = RecordingLabRepository();
    createOrder = CreateLabOrderUseCase(repository: repository);
    registerSpecimen = RegisterSpecimenUseCase(repository: repository);
    collectSpecimen = CollectSpecimenUseCase(repository: repository);
    enterResult = EnterLabResultUseCase(repository: repository);
    verifyResult = VerifyLabResultUseCase(repository: repository);
    correctResult = CorrectLabResultUseCase(repository: repository);
  });

  Future<String> seedOrder(Set<String> permissions) => createOrder.call(
    policy: policyWith(permissions),
    tenantId: 'tenant-1',
    patientId: 'patient-1',
    orderedBy: 'doctor-1',
    orderCode: 'LAB-001',
    priority: LabPriority.stat,
    tests: const <LabTestRequest>[
      LabTestRequest(code: 'HB', name: 'Haemoglobin'),
    ],
  );

  group('authorization gates', () {
    test('creating an order requires lab_order.write', () {
      expect(
        seedOrder(reader),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.requiredPermission,
            'requiredPermission',
            NodexPermissions.labOrderWrite,
          ),
        ),
      );
    });

    test('registering a specimen requires lab_result.enter', () {
      expect(
        registerSpecimen.call(
          policy: policyWith(orderer),
          tenantId: 'tenant-1',
          labOrderId: 'order-1',
          accessionBarcode: 'ACC-001',
          specimenType: 'blood',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('collecting a specimen requires lab_result.enter', () {
      expect(
        collectSpecimen.call(
          policy: policyWith(orderer),
          specimenId: 'specimen-1',
          collectorId: 'nurse-1',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('entering a result requires lab_result.enter', () {
      expect(
        enterResult.call(
          policy: policyWith(orderer),
          tenantId: 'tenant-1',
          labOrderId: 'order-1',
          specimenId: 'specimen-1',
          analyteCode: 'HB',
          analyteName: 'Haemoglobin',
          enteredBy: 'tech-1',
          valueText: '13.2',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('verifying a result requires lab_result.verify', () {
      expect(
        verifyResult.call(
          policy: policyWith(enterer),
          result: resultWith(),
          verifierId: 'doctor-1',
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.requiredPermission,
            'requiredPermission',
            NodexPermissions.labResultVerify,
          ),
        ),
      );
    });

    test('correcting a result requires lab_result.enter', () {
      expect(
        correctResult.call(
          policy: policyWith(verifier),
          original: resultWith(status: LabResultStatus.verified),
          enteredBy: 'tech-1',
          valueText: '12.8',
          reason: 'Recalibrated analyzer',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('the permission gate runs before the correction preconditions', () {
      // Lacking the permission and given an empty reason on an unverified
      // result, the failure must still be an authorization failure.
      expect(
        correctResult.call(
          policy: policyWith(verifier),
          original: resultWith(),
          enteredBy: 'tech-1',
          valueText: '12.8',
          reason: '   ',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });
  });

  group('ordering', () {
    test('records an ordered row with its attribution', () async {
      final String id = await seedOrder(orderer);

      expect(id, 'order-new');
      expect(repository.orders, hasLength(1));
      expect(repository.orders.single['status'], 'ordered');
      expect(repository.orders.single['priority'], 'stat');
      expect(repository.orders.single['tenant_id'], 'tenant-1');
      expect(repository.orders.single['patient_id'], 'patient-1');
      expect(repository.orders.single['ordered_by'], 'doctor-1');
    });
  });

  group('specimen collection', () {
    test('registers a pending specimen', () async {
      await registerSpecimen.call(
        policy: policyWith(enterer),
        tenantId: 'tenant-1',
        labOrderId: 'order-1',
        accessionBarcode: 'ACC-001',
        specimenType: 'blood',
      );

      expect(repository.specimens, hasLength(1));
      expect(repository.specimens.single['status'], 'pending');
      expect(repository.specimens.single['accession_barcode'], 'ACC-001');
      expect(repository.specimens.single['specimen_type'], 'blood');
    });

    test('records the collection against the specimen', () async {
      await collectSpecimen.call(
        policy: policyWith(enterer),
        specimenId: 'specimen-1',
        collectorId: 'nurse-1',
      );

      expect(repository.collected, hasLength(1));
      expect(repository.collected.single['id'], 'specimen-1');
      expect(repository.collected.single['status'], 'collected');
      expect(repository.collected.single['collected_by'], 'nurse-1');
      expect(repository.collected.single['collected_at'], isNotNull);
    });
  });

  group('result entry', () {
    test('records an entered row with its analyte and value', () async {
      await enterResult.call(
        policy: policyWith(enterer),
        tenantId: 'tenant-1',
        labOrderId: 'order-1',
        specimenId: 'specimen-1',
        analyteCode: 'HB',
        analyteName: 'Haemoglobin',
        enteredBy: 'tech-1',
        valueNumeric: 13.2,
        unit: 'g/dL',
      );

      expect(repository.results, hasLength(1));
      expect(repository.results.single['status'], 'entered');
      expect(repository.results.single['analyte_code'], 'HB');
      expect(repository.results.single['value_numeric'], 13.2);
      expect(repository.results.single['verified_by'], isNull);
    });
  });

  group('verification', () {
    test('verifies an entered result and records the verifier', () async {
      await verifyResult.call(
        policy: policyWith(verifier),
        result: resultWith(),
        verifierId: 'doctor-1',
      );

      expect(repository.verifications, hasLength(1));
      expect(repository.verifications.single['id'], 'result-1');
      expect(repository.verifications.single['status'], 'verified');
      expect(repository.verifications.single['verified_by'], 'doctor-1');
    });

    test('a verified result cannot be verified again', () {
      expect(
        verifyResult.call(
          policy: policyWith(verifier),
          result: resultWith(status: LabResultStatus.verified),
          verifierId: 'doctor-1',
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'lab_result_immutable',
          ),
        ),
      );
      expect(repository.verifications, isEmpty);
    });

    test('a corrected result cannot be verified again', () {
      expect(
        verifyResult.call(
          policy: policyWith(verifier),
          result: resultWith(status: LabResultStatus.corrected),
          verifierId: 'doctor-1',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });
  });

  group('corrections', () {
    test('a correction is a new row that links to its original', () async {
      final LabResult original = resultWith(status: LabResultStatus.verified);

      await correctResult.call(
        policy: policyWith(enterer),
        original: original,
        enteredBy: 'tech-2',
        valueText: ' 12.8 ',
        reason: ' Analyzer recalibration ',
      );

      expect(repository.corrections, hasLength(1));
      final Map<String, Object?> row = repository.corrections.single;
      expect(row['status'], 'corrected');
      expect(row['correction_of'], original.id);
      expect(row['correction_reason'], 'Analyzer recalibration');
      expect(row['value_text'], '12.8');
      expect(row['entered_by'], 'tech-2');
      expect(row['verified_by'], 'tech-2');
      // The analyte's unit and ranges follow the correction.
      expect(row['unit'], original.unit);
      expect(row['reference_range'], original.referenceRange);
      expect(row['abnormal_flag'], original.abnormalFlag);
    });

    test('a correction requires a reason', () {
      expect(
        correctResult.call(
          policy: policyWith(enterer),
          original: resultWith(status: LabResultStatus.verified),
          enteredBy: 'tech-1',
          valueText: '12.8',
          reason: '   ',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'lab_correction_reason_required',
          ),
        ),
      );
      expect(repository.corrections, isEmpty);
    });

    test('only a verified result can be corrected', () {
      expect(
        correctResult.call(
          policy: policyWith(enterer),
          original: resultWith(),
          enteredBy: 'tech-1',
          valueText: '12.8',
          reason: 'Recalibrated analyzer',
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'lab_result_not_verified',
          ),
        ),
      );
      expect(repository.corrections, isEmpty);
    });
  });
}
