/// Tests for the waste use cases, certificate lifecycle and compliance
/// derivation (Module 30).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/authorization_snapshot.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/domain/waste/waste.dart';
import 'package:nodex_hms/domain/waste/waste_repository.dart';
import 'package:nodex_hms/domain/waste/waste_use_cases.dart';

import 'waste_repository_test.dart' show FakeWasteStore;

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
      facilityIds: const <String>{'f-1'},
      departmentIds: const <String>{},
      wardIds: const <String>{},
    ),
    connectivity: ConnectivityState.online,
  );
}

void main() {
  late FakeWasteStore store;
  late DefaultWasteRepository repository;
  late RegisterCategoryUseCase registerCategory;
  late UpdateCategoryUseCase updateCategory;
  late LogGenerationUseCase logGeneration;
  late IssueCertificateUseCase issueCertificate;
  late VoidCertificateUseCase voidCertificate;
  late ReadWasteUseCase readWaste;

  const Set<String> manage = <String>{NodexPermissions.wasteManage};
  const Set<String> record = <String>{NodexPermissions.wasteRecord};
  const Set<String> reader = <String>{NodexPermissions.wasteRead};

  setUp(() {
    store = FakeWasteStore();
    repository = DefaultWasteRepository(
      store: store,
      logger: NodexLogger(
        sinks: <NodexLogSink>[InMemoryLogSink()],
        minimumLevel: NodexLogLevel.trace,
      ),
    );
    registerCategory = RegisterCategoryUseCase(repository: repository);
    updateCategory = UpdateCategoryUseCase(repository: repository);
    logGeneration = LogGenerationUseCase(repository: repository);
    issueCertificate = IssueCertificateUseCase(repository: repository);
    voidCertificate = VoidCertificateUseCase(repository: repository);
    readWaste = ReadWasteUseCase(repository: repository);
  });

  Future<String> category({String code = 'YEL', String name = 'Yellow'}) =>
      registerCategory(
        policy: policyWith(manage),
        tenantId: 'tenant-1',
        createdBy: 'user-1',
        code: code,
        name: name,
      );

  Future<String> log({
    required String categoryId,
    required int grams,
    required DateTime at,
  }) => logGeneration(
    policy: policyWith(record),
    tenantId: 'tenant-1',
    facilityId: 'f-1',
    categoryId: categoryId,
    loggedBy: 'user-1',
    weightGrams: grams,
    loggedAt: at,
  );

  Future<String> certificate({
    required String categoryId,
    required String certificateNo,
    required String barcode,
    required int grams,
    required DateTime at,
  }) => issueCertificate(
    policy: policyWith(manage),
    tenantId: 'tenant-1',
    facilityId: 'f-1',
    categoryId: categoryId,
    issuedBy: 'user-1',
    certificateNo: certificateNo,
    barcode: barcode,
    disposalVendor: 'Stericycle',
    method: DisposalMethod.incineration,
    disposedAt: at,
    weightGrams: grams,
  );

  Future<void> seedCertificateRow({
    required String id,
    required String categoryId,
    required int grams,
    required DateTime at,
    String status = 'issued',
    String? voidReason,
  }) => repository.registerCertificate(<String, Object?>{
    'id': id,
    'tenant_id': 'tenant-1',
    'facility_id': 'f-1',
    'category_id': categoryId,
    'certificate_no': id,
    'barcode': id,
    'disposal_vendor': 'Stericycle',
    'vendor_licence': null,
    'method': 'incineration',
    'disposed_at': at.toIso8601String(),
    'weight_grams': grams,
    'manifest_reference': null,
    'status': status,
    'void_reason': voidReason,
    'issued_by': 'user-1',
    'created_at': at.toIso8601String(),
    'updated_at': at.toIso8601String(),
  });

  Future<void> seedGenerationRow({
    required String id,
    required String categoryId,
    required int grams,
    required DateTime at,
  }) => repository.registerGenerationLog(<String, Object?>{
    'id': id,
    'tenant_id': 'tenant-1',
    'facility_id': 'f-1',
    'category_id': categoryId,
    'department_id': null,
    'location_label': null,
    'weight_grams': grams,
    'container_count': 1,
    'logged_at': at.toIso8601String(),
    'logged_by': 'user-1',
    'notes': null,
    'created_at': at.toIso8601String(),
  });

  test('registering a category requires waste.manage and a code', () async {
    expect(
      () => registerCategory(
        policy: policyWith(<String>{}),
        tenantId: 'tenant-1',
        createdBy: 'user-1',
        code: 'YEL',
        name: 'Yellow',
      ),
      throwsA(isA<NodexError>()),
    );
    expect(
      () => registerCategory(
        policy: policyWith(manage),
        tenantId: 'tenant-1',
        createdBy: 'user-1',
        code: '   ',
        name: 'Yellow',
      ),
      throwsA(isA<NodexError>()),
    );
    expect(await category(), isNotEmpty);
  });

  test('updating a category moves it out of use without deleting it', () async {
    final String id = await category();
    final WasteCategory created = (await repository.categoryById(id))!;
    await updateCategory(
      policy: policyWith(manage),
      category: created,
      code: created.code,
      name: created.name,
      isActive: false,
    );
    final WasteCategory retired = (await repository.categoryById(id))!;
    expect(retired.isActive, isFalse);
    // Still readable, so history that names it stays legible.
    final List<WasteCategory> all = await readWaste.categories(
      policy: policyWith(reader),
      tenantId: 'tenant-1',
      includeInactive: true,
    );
    expect(all, hasLength(1));
    expect(
      await readWaste.categories(
        policy: policyWith(reader),
        tenantId: 'tenant-1',
      ),
      isEmpty,
    );
  });

  test(
    'logging generation needs waste.record and an in-use category',
    () async {
      final String id = await category();
      expect(
        () => logGeneration(
          policy: policyWith(<String>{}),
          tenantId: 'tenant-1',
          facilityId: 'f-1',
          categoryId: id,
          loggedBy: 'user-1',
          weightGrams: 100,
        ),
        throwsA(isA<NodexError>()),
        reason: 'waste.record is required',
      );
      expect(
        () => logGeneration(
          policy: policyWith(record),
          tenantId: 'tenant-1',
          facilityId: 'f-1',
          categoryId: 'missing',
          loggedBy: 'user-1',
          weightGrams: 100,
        ),
        throwsA(isA<NodexError>()),
        reason: 'the category must exist',
      );
      expect(
        () => logGeneration(
          policy: policyWith(record),
          tenantId: 'tenant-1',
          facilityId: 'f-1',
          categoryId: id,
          loggedBy: 'user-1',
          weightGrams: 0,
        ),
        throwsA(isA<NodexError>()),
        reason: 'weight must be positive',
      );

      final WasteCategory created = (await repository.categoryById(id))!;
      await updateCategory(
        policy: policyWith(manage),
        category: created,
        code: created.code,
        name: created.name,
        isActive: false,
      );
      expect(
        () => log(categoryId: id, grams: 100, at: DateTime.utc(2026, 10, 1)),
        throwsA(isA<NodexError>()),
        reason: 'a retired category cannot take new waste',
      );
    },
  );

  test('issuing a certificate refuses a duplicate number or barcode', () async {
    final String id = await category();
    expect(
      () => issueCertificate(
        policy: policyWith(<String>{}),
        tenantId: 'tenant-1',
        facilityId: 'f-1',
        categoryId: id,
        issuedBy: 'user-1',
        certificateNo: 'DC-1',
        barcode: 'BC-1',
        disposalVendor: 'Stericycle',
        method: DisposalMethod.incineration,
        disposedAt: DateTime.utc(2026, 10, 2),
        weightGrams: 1000,
      ),
      throwsA(isA<NodexError>()),
    );
    final String first = await certificate(
      categoryId: id,
      certificateNo: 'DC-1',
      barcode: 'BC-1',
      grams: 1000,
      at: DateTime.utc(2026, 10, 2),
    );
    expect(first, isNotEmpty);
    expect(
      () => certificate(
        categoryId: id,
        certificateNo: 'DC-1',
        barcode: 'BC-2',
        grams: 500,
        at: DateTime.utc(2026, 10, 3),
      ),
      throwsA(isA<NodexError>()),
      reason: 'the certificate number is unique per tenant',
    );
    expect(
      () => certificate(
        categoryId: id,
        certificateNo: 'DC-2',
        barcode: 'BC-1',
        grams: 500,
        at: DateTime.utc(2026, 10, 3),
      ),
      throwsA(isA<NodexError>()),
      reason: 'the barcode is unique per tenant',
    );
  });

  test('voiding a certificate is one-way and needs a reason', () async {
    final String id = await category();
    final String certId = await certificate(
      categoryId: id,
      certificateNo: 'DC-1',
      barcode: 'BC-1',
      grams: 1000,
      at: DateTime.utc(2026, 10, 2),
    );
    final DisposalCertificate issued = (await repository.certificateById(
      certId,
    ))!;

    expect(
      () => voidCertificate(
        policy: policyWith(manage),
        certificate: issued,
        reason: '   ',
      ),
      throwsA(isA<NodexError>()),
      reason: 'a void needs a reason',
    );
    expect(
      () => voidCertificate(
        policy: policyWith(<String>{}),
        certificate: issued,
        reason: 'Wrong vendor',
      ),
      throwsA(isA<NodexError>()),
      reason: 'waste.manage is required',
    );

    await voidCertificate(
      policy: policyWith(manage),
      certificate: issued,
      reason: 'Wrong vendor',
    );
    final DisposalCertificate voided = (await repository.certificateById(
      certId,
    ))!;
    expect(voided.status, CertificateStatus.voided);
    expect(voided.voidReason, 'Wrong vendor');
    expect(voided.isLive, isFalse);

    expect(
      () => voidCertificate(
        policy: policyWith(manage),
        certificate: voided,
        reason: 'Again',
      ),
      throwsA(isA<NodexError>()),
      reason: 'a voided certificate cannot be voided twice',
    );
  });

  test(
    'compliance reads the gap between generation and live certificates',
    () async {
      final String yellow = await category(code: 'YEL', name: 'Yellow');
      final String red = await category(code: 'RED', name: 'Red');
      await category(code: 'BLK', name: 'Black');

      final DateTime from = DateTime.utc(2026, 10, 1);
      final DateTime to = DateTime.utc(2026, 11, 1);

      await seedGenerationRow(
        id: 'g-1',
        categoryId: yellow,
        grams: 5000,
        at: DateTime.utc(2026, 10, 2),
      );
      await seedGenerationRow(
        id: 'g-2',
        categoryId: yellow,
        grams: 2000,
        at: DateTime.utc(2026, 10, 3),
      );
      await seedGenerationRow(
        id: 'g-3',
        categoryId: red,
        grams: 1000,
        at: DateTime.utc(2026, 10, 4),
      );
      // Outside the window: neither side counts it.
      await seedGenerationRow(
        id: 'g-4',
        categoryId: yellow,
        grams: 90000,
        at: DateTime.utc(2026, 9, 1),
      );

      await seedCertificateRow(
        id: 'c-1',
        categoryId: yellow,
        grams: 4000,
        at: DateTime.utc(2026, 10, 5),
      );
      // A voided certificate is withdrawn, not counted.
      await seedCertificateRow(
        id: 'c-2',
        categoryId: yellow,
        grams: 5000,
        at: DateTime.utc(2026, 10, 6),
        status: 'voided',
        voidReason: 'Wrong vendor',
      );
      await seedCertificateRow(
        id: 'c-3',
        categoryId: red,
        grams: 1000,
        at: DateTime.utc(2026, 10, 7),
      );
      await seedCertificateRow(
        id: 'c-4',
        categoryId: yellow,
        grams: 7000,
        at: DateTime.utc(2026, 9, 2),
      );

      final List<WasteCategoryCompliance> board = await readWaste.compliance(
        policy: policyWith(reader),
        tenantId: 'tenant-1',
        from: from,
        to: to,
      );
      expect(
        board.map((WasteCategoryCompliance e) => e.category.code).toList(),
        <String>['YEL', 'BLK', 'RED'],
      );
      expect(board[0].generatedGrams, 7000);
      expect(board[0].certificatedGrams, 4000);
      expect(board[0].gapGrams, 3000);
      expect(board[0].isCompliant, isFalse);
      expect(board[1].generatedGrams, 0);
      expect(board[1].certificatedGrams, 0);
      expect(board[1].isCompliant, isTrue);
      expect(board[2].generatedGrams, 1000);
      expect(board[2].gapGrams, 0);
      expect(board[2].isCompliant, isTrue);

      expect(
        () => readWaste.compliance(
          policy: policyWith(<String>{}),
          tenantId: 'tenant-1',
          from: from,
          to: to,
        ),
        throwsA(isA<NodexError>()),
      );
    },
  );

  test('certificates hide withdrawn ones unless asked for', () async {
    final String id = await category();
    await seedCertificateRow(
      id: 'c-1',
      categoryId: id,
      grams: 100,
      at: DateTime.utc(2026, 10, 2),
    );
    await seedCertificateRow(
      id: 'c-2',
      categoryId: id,
      grams: 200,
      at: DateTime.utc(2026, 10, 3),
      status: 'voided',
      voidReason: 'Wrong vendor',
    );
    expect(
      await readWaste.certificates(
        policy: policyWith(reader),
        tenantId: 'tenant-1',
      ),
      hasLength(1),
    );
    expect(
      await readWaste.certificates(
        policy: policyWith(reader),
        tenantId: 'tenant-1',
        includeVoided: true,
      ),
      hasLength(2),
    );
  });

  test(
    'the certificate lifecycle and compliance helpers behave as documented',
    () {
      expect(
        certificateCanTransition(
          CertificateStatus.issued,
          CertificateStatus.voided,
        ),
        isTrue,
      );
      expect(
        certificateCanTransition(
          CertificateStatus.voided,
          CertificateStatus.issued,
        ),
        isFalse,
      );
      expect(
        certificateCanTransition(
          CertificateStatus.voided,
          CertificateStatus.voided,
        ),
        isFalse,
      );

      expect(
        wasteComplianceGap(generatedGrams: 7000, certificatedGrams: 4000),
        3000,
      );
      expect(
        wasteComplianceGap(generatedGrams: 1000, certificatedGrams: 1000),
        0,
      );
      expect(
        wasteComplianceGap(generatedGrams: 1000, certificatedGrams: 9000),
        0,
        reason: 'a prior period surplus is not a negative gap',
      );

      expect(WasteColour.fromWire('blue'), WasteColour.blue);
      expect(
        WasteHazardClass.fromWire('radioactive'),
        WasteHazardClass.radioactive,
      );
      expect(DisposalMethod.fromWire('autoclave'), DisposalMethod.autoclave);
      expect(CertificateStatus.fromWire('voided').isLive, isFalse);
    },
  );
}
