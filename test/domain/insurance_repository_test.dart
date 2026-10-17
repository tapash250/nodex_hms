/// Tests for the insurance repository over a fake local store (Module 32).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/domain/insurance/insurance.dart';
import 'package:nodex_hms/domain/insurance/insurance_repository.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';

/// A minimal in-memory store covering the four insurance tables.
final class FakeInsuranceStore implements PatientLocalStore {
  /// Rows by table name and id.
  final Map<String, Map<String, Map<String, Object?>>> tables =
      <String, Map<String, Map<String, Object?>>>{};

  /// Set when the store should behave as a closed database.
  bool closed = false;

  static final RegExp _filterPattern = RegExp(r' and (\w+) = \?');
  static final RegExp _fromPattern = RegExp(r'from (\w+) ');

  Map<String, Map<String, Object?>> _table(String name) =>
      tables.putIfAbsent(name, () => <String, Map<String, Object?>>{});

  void _guard() {
    if (closed) {
      throw const PersistenceError(
        message: 'The local clinical database has not been opened.',
        code: 'database_not_open',
      );
    }
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String sql,
    List<Object?> parameters,
  ) async {
    _guard();
    final RegExpMatch? from = _fromPattern.firstMatch(sql);
    if (from == null) {
      throw UnimplementedError('FakeInsuranceStore cannot run: $sql');
    }
    final String table = from.group(1)!;
    Iterable<Map<String, Object?>> rows = _table(table).values
        .where((Map<String, Object?> row) => row['tenant_id'] == parameters[0]);
    int next = 1;
    for (final RegExpMatch match in _filterPattern.allMatches(sql)) {
      final String column = match.group(1)!;
      final Object? expected = parameters[next++];
      rows = rows.where((Map<String, Object?> row) => row[column] == expected);
    }
    if (sql.contains('limit ?')) {
      rows = rows.take(parameters.last! as int);
    }
    return rows.toList(growable: false);
  }

  @override
  Future<Map<String, Object?>?> getById(String table, String id) async {
    _guard();
    return _table(table)[id];
  }

  @override
  Future<void> insert(String table, Map<String, Object?> row) async {
    _guard();
    _table(table)[row['id']! as String] = <String, Object?>{...row};
  }

  @override
  Future<void> update(
    String table,
    String id,
    Map<String, Object?> changes,
  ) async {
    _guard();
    final Map<String, Object?>? row = _table(table)[id];
    if (row == null) {
      throw StateError('missing row $id');
    }
    row.addAll(changes);
  }
}

void main() {
  late FakeInsuranceStore store;
  late DefaultInsuranceRepository repository;

  setUp(() {
    store = FakeInsuranceStore();
    repository = DefaultInsuranceRepository(
      store: store,
      logger: NodexLogger(
        sinks: <NodexLogSink>[InMemoryLogSink()],
        minimumLevel: NodexLogLevel.trace,
      ),
    );
  });

  String now() => DateTime.now().toUtc().toIso8601String();

  Future<String> seedPayer({
    required String id,
    String code = 'INS-1',
    String name = 'Metlife',
    String payerType = 'insurer',
    int isActive = 1,
  }) => repository.registerPayer(<String, Object?>{
    'id': id,
    'tenant_id': 'tenant-1',
    'code': code,
    'name': name,
    'payer_type': payerType,
    'claim_portal_ref': 'PORTAL-1',
    'contact_phone': '555-0100',
    'contact_email': 'claims@example.com',
    'is_active': isActive,
    'notes': null,
    'created_by': 'user-1',
    'created_at': now(),
    'updated_at': now(),
  });

  Future<String> seedPolicy({
    required String id,
    String patientId = 'patient-1',
    String payerId = 'payer-1',
    String policyNo = 'POL-1',
    String validTo = '2027-01-01',
  }) => repository.registerPolicy(<String, Object?>{
    'id': id,
    'tenant_id': 'tenant-1',
    'patient_id': patientId,
    'payer_id': payerId,
    'policy_no': policyNo,
    'member_id': 'M-1',
    'plan_name': 'Gold',
    'coverage_type': 'cashless',
    'currency': 'BDT',
    'sum_insured_minor': 5000000,
    'valid_from': '2026-01-01',
    'valid_to': validTo,
    'status': 'active',
    'verified_at': null,
    'verified_by': null,
    'verification_reference': null,
    'cancelled_at': null,
    'cancellation_reason': null,
    'notes': null,
    'created_by': 'user-1',
    'created_at': now(),
    'updated_at': now(),
  });

  Future<String> seedPreAuth({required String id, String policyId = 'pol-1'}) =>
      repository.registerPreAuthorisation(<String, Object?>{
        'id': id,
        'tenant_id': 'tenant-1',
        'policy_id': policyId,
        'patient_id': 'patient-1',
        'facility_id': 'facility-1',
        'encounter_id': null,
        'requested_by': 'user-1',
        'requested_at': now(),
        'diagnosis': 'Cholecystitis',
        'procedure_text': 'Laparoscopic cholecystectomy',
        'currency': 'BDT',
        'estimated_cost_minor': 12000000,
        'status': 'requested',
        'payer_reference': null,
        'answered_at': null,
        'approved_amount_minor': null,
        'valid_until': null,
        'decision_notes': null,
        'cancellation_reason': null,
        'created_by': 'user-1',
        'created_at': now(),
        'updated_at': now(),
      });

  Future<String> seedClaim({
    required String id,
    String policyId = 'pol-1',
    String status = 'draft',
  }) => repository.registerClaim(<String, Object?>{
    'id': id,
    'tenant_id': 'tenant-1',
    'policy_id': policyId,
    'patient_id': 'patient-1',
    'facility_id': 'facility-1',
    'pre_authorisation_id': null,
    'invoice_id': null,
    'claim_no': 'CLM-$id',
    'currency': 'BDT',
    'claimed_amount_minor': 9000000,
    'approved_amount_minor': null,
    'settled_amount_minor': null,
    'status': status,
    'payer_reference': null,
    'submitted_at': null,
    'decided_at': null,
    'settled_at': null,
    'rejection_reason': null,
    'cancellation_reason': null,
    'notes': null,
    'created_by': 'user-1',
    'created_at': now(),
    'updated_at': now(),
  });

  test('registerPayer resolves by id and parses the fields', () async {
    final String id = await seedPayer(
      id: 'payer-1',
      payerType: 'tpa',
      isActive: 0,
    );
    final InsurancePayer? payer = await repository.payerById(id);
    expect(payer, isNotNull);
    expect(payer!.code, 'INS-1');
    expect(payer.name, 'Metlife');
    expect(payer.payerType, PayerType.tpa);
    expect(payer.isActive, isFalse);
    expect(payer.claimPortalRef, 'PORTAL-1');
    expect(payer.contactEmail, 'claims@example.com');
  });

  test('listPayers scopes to the tenant', () async {
    await seedPayer(id: 'payer-1');
    await seedPayer(id: 'payer-2', code: 'INS-2', name: 'Guardian');
    expect(await repository.listPayers('tenant-1'), hasLength(2));
    expect(await repository.listPayers('tenant-2'), isEmpty);
  });

  test('updatePayer applies a change set', () async {
    await seedPayer(id: 'payer-1');
    await repository.updatePayer(
      'payer-1',
      payerChanges(code: 'INS-1', name: 'Metlife Bangladesh', isActive: false),
    );
    final InsurancePayer? payer = await repository.payerById('payer-1');
    expect(payer!.name, 'Metlife Bangladesh');
    expect(payer.isActive, isFalse);
  });

  test(
    'registerPolicy resolves by id and parses dates and minor units',
    () async {
      final String id = await seedPolicy(id: 'pol-1');
      final InsurancePolicy? cover = await repository.policyById(id);
      expect(cover, isNotNull);
      expect(cover!.policyNo, 'POL-1');
      expect(cover.coverageType, CoverageType.cashless);
      expect(cover.currency, 'BDT');
      expect(cover.sumInsuredMinor, 5000000);
      expect(cover.validFrom, DateTime.utc(2026, 1, 1));
      expect(cover.validTo, DateTime.utc(2027, 1, 1));
      expect(cover.status, PolicyStatus.active);
      expect(cover.isVerified, isFalse);
      expect(cover.isEditable, isTrue);
    },
  );

  test('listPolicies filters by patient and payer', () async {
    await seedPolicy(id: 'pol-1');
    await seedPolicy(id: 'pol-2', policyNo: 'POL-2', payerId: 'payer-2');
    await seedPolicy(id: 'pol-3', policyNo: 'POL-3', patientId: 'patient-2');
    expect(await repository.listPolicies('tenant-1'), hasLength(3));
    expect(
      await repository.listPolicies('tenant-1', patientId: 'patient-2'),
      hasLength(1),
    );
    expect(
      await repository.listPolicies('tenant-1', payerId: 'payer-2'),
      hasLength(1),
    );
  });

  test('updatePolicy records verification and cancellation', () async {
    await seedPolicy(id: 'pol-1');
    await repository.updatePolicy(
      'pol-1',
      policyVerifyChanges(verifiedBy: 'user-2', reference: 'REF-9'),
    );
    InsurancePolicy? cover = await repository.policyById('pol-1');
    expect(cover!.isVerified, isTrue);
    expect(cover.verifiedBy, 'user-2');
    expect(cover.verificationReference, 'REF-9');

    await repository.updatePolicy(
      'pol-1',
      policyCancelChanges(reason: 'Employer withdrew the scheme'),
    );
    cover = await repository.policyById('pol-1');
    expect(cover!.status, PolicyStatus.cancelled);
    expect(cover.cancelledAt, isNotNull);
    expect(cover.cancellationReason, 'Employer withdrew the scheme');
    expect(cover.isEditable, isFalse);
  });

  test(
    'registerPreAuthorisation resolves by id and waits on the payer',
    () async {
      final String id = await seedPreAuth(id: 'pre-1');
      final PreAuthorisationRequest? request = await repository
          .preAuthorisationById(id);
      expect(request, isNotNull);
      expect(request!.status, PreAuthStatus.requested);
      expect(request.isLive, isTrue);
      expect(request.estimatedCostMinor, 12000000);
      expect(request.approvedAmountMinor, isNull);
      expect(request.shortfallMinor, isNull);
    },
  );

  test('listPreAuthorisations filters by policy and patient', () async {
    await seedPreAuth(id: 'pre-1');
    await seedPreAuth(id: 'pre-2', policyId: 'pol-2');
    expect(await repository.listPreAuthorisations('tenant-1'), hasLength(2));
    expect(
      await repository.listPreAuthorisations('tenant-1', policyId: 'pol-2'),
      hasLength(1),
    );
    expect(
      await repository.listPreAuthorisations(
        'tenant-1',
        patientId: 'patient-9',
      ),
      isEmpty,
    );
  });

  test('registerClaim resolves by id and derives the recovery gap', () async {
    final String id = await seedClaim(id: 'clm-1');
    final InsuranceClaim? claim = await repository.claimById(id);
    expect(claim, isNotNull);
    expect(claim!.claimNo, 'CLM-clm-1');
    expect(claim.status, ClaimStatus.draft);
    expect(claim.isOpen, isTrue);
    expect(claim.recoveryGapMinor, 9000000);
  });

  test('listClaims filters by status', () async {
    await seedClaim(id: 'clm-1');
    await seedClaim(id: 'clm-2', status: 'settled');
    expect(await repository.listClaims('tenant-1'), hasLength(2));
    expect(
      await repository.listClaims('tenant-1', status: 'settled'),
      hasLength(1),
    );
  });

  test('a store failure surfaces as a NodexError', () async {
    await expectLater(
      repository.updatePayer('missing', <String, Object?>{}),
      throwsA(isA<NodexError>()),
    );
    store.closed = true;
    await expectLater(
      repository.listPayers('tenant-1'),
      throwsA(isA<NodexError>()),
    );
  });
}
