/// Tests for the master settings repository over a fake local store
/// (Module 39).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';
import 'package:nodex_hms/domain/settings/settings.dart';
import 'package:nodex_hms/domain/settings/settings_repository.dart';

/// A minimal in-memory store covering the five master settings tables.
final class FakeSettingsStore implements PatientLocalStore {
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
      throw UnimplementedError('FakeSettingsStore cannot run: $sql');
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
  late FakeSettingsStore store;
  late DefaultSettingsRepository repository;

  setUp(() {
    store = FakeSettingsStore();
    repository = DefaultSettingsRepository(
      store: store,
      logger: NodexLogger(
        sinks: <NodexLogSink>[InMemoryLogSink()],
        minimumLevel: NodexLogLevel.trace,
      ),
    );
  });

  Future<String> seedProfile({
    String id = 'profile-1',
    int version = 1,
    String facilityId = '',
    String hospitalName = 'Nodex General',
  }) => repository.registerSettingsProfile(
    SettingsProfile.registerRow(
      tenantId: 'tenant-1',
      version: version,
      hospitalName: hospitalName,
      createdBy: 'admin-1',
      facilityId: facilityId.isEmpty ? null : facilityId,
      profileId: id,
    ),
  );

  group('settings profiles', () {
    test('a draft profile is stored with its own defaults', () async {
      final String id = await seedProfile();

      final SettingsProfile? profile = await repository.settingsProfileById(id);

      expect(profile, isNotNull);
      expect(profile!.hospitalName, 'Nodex General');
      expect(profile.version, 1);
      expect(profile.status, SettingsProfileStatus.draft);
      expect(profile.currencyCode, 'INR');
      expect(profile.currencyMinorUnits, 2);
      expect(profile.fiscalYearStartMonth, 4);
      expect(profile.requireTwoFactor, isTrue);
      expect(profile.isHospitalWide, isTrue);
      expect(profile.activatedAt, isNull);
      expect(profile.isActive, isFalse);
    });

    test('a boolean column reads back from its integer form', () async {
      final String id = await repository.registerSettingsProfile(
        SettingsProfile.registerRow(
          tenantId: 'tenant-1',
          version: 1,
          hospitalName: 'Nodex General',
          createdBy: 'admin-1',
          requireTwoFactor: false,
        ),
      );

      final SettingsProfile profile = (await repository.settingsProfileById(
        id,
      ))!;

      expect(profile.requireTwoFactor, isFalse);
    });

    test('profiles are listed for one tenant only', () async {
      await seedProfile(id: 'profile-1');
      await repository.registerSettingsProfile(
        SettingsProfile.registerRow(
          tenantId: 'tenant-2',
          version: 1,
          hospitalName: 'Elsewhere',
          createdBy: 'admin-2',
          profileId: 'profile-2',
        ),
      );

      final List<SettingsProfile> profiles = await repository
          .listSettingsProfiles('tenant-1');

      expect(profiles.map((SettingsProfile p) => p.id), <String>['profile-1']);
    });

    test('profiles are filtered by status', () async {
      await seedProfile(id: 'profile-1');
      await repository.updateSettingsProfile(
        'profile-1',
        settingsProfileActivateChanges(
          activatedBy: 'admin-1',
          at: DateTime.utc(2026, 5, 1),
        ),
      );
      await seedProfile(id: 'profile-2', version: 2);

      final List<SettingsProfile> active = await repository
          .listSettingsProfiles('tenant-1', status: 'active');

      expect(active, hasLength(1));
      expect(active.single.id, 'profile-1');
      expect(active.single.isActive, isTrue);
      expect(active.single.activatedBy, 'admin-1');
      expect(active.single.activatedAt, DateTime.utc(2026, 5, 1));
    });

    test('a facility profile is scoped and read back as such', () async {
      final String id = await seedProfile(facilityId: 'facility-1', version: 3);

      final SettingsProfile profile = (await repository.settingsProfileById(
        id,
      ))!;

      expect(profile.facilityId, 'facility-1');
      expect(profile.isHospitalWide, isFalse);
      expect(profile.version, 3);
    });

    test('an unknown profile is null rather than an error', () async {
      expect(await repository.settingsProfileById('missing'), isNull);
    });

    test('a closed database surfaces as a persistence error', () async {
      store.closed = true;

      await expectLater(
        repository.listSettingsProfiles('tenant-1'),
        throwsA(isA<PersistenceError>()),
      );
    });
  });

  group('branding assets', () {
    test('an asset keeps its colours and its file facts', () async {
      final String id = await repository.registerBrandingAsset(
        BrandingAsset.registerRow(
          tenantId: 'tenant-1',
          kind: BrandingAssetKind.logo,
          label: 'Hospital mark',
          primaryColor: '#0B5FFF',
          secondaryColor: '#FFFFFF',
          createdBy: 'admin-1',
          storagePath: 'branding/logo.svg',
          checksum: 'sha256-abc',
          mimeType: 'image/svg+xml',
          byteSize: 4096,
          assetId: 'asset-1',
        ),
      );

      final BrandingAsset asset = (await repository.brandingAssetById(id))!;

      expect(asset.kind, BrandingAssetKind.logo);
      expect(asset.label, 'Hospital mark');
      expect(asset.primaryColor, '#0B5FFF');
      expect(asset.secondaryColor, '#FFFFFF');
      expect(asset.storagePath, 'branding/logo.svg');
      expect(asset.checksum, 'sha256-abc');
      expect(asset.mimeType, 'image/svg+xml');
      expect(asset.byteSize, 4096);
      expect(asset.hasFile, isTrue);
      expect(asset.status, BrandingAssetStatus.draft);
    });

    test('an asset with no uploaded file says so', () async {
      final String id = await repository.registerBrandingAsset(
        BrandingAsset.registerRow(
          tenantId: 'tenant-1',
          kind: BrandingAssetKind.watermark,
          label: 'Faint mark',
          primaryColor: '#123456',
          secondaryColor: '#FEDCBA',
          createdBy: 'admin-1',
          assetId: 'asset-2',
        ),
      );

      final BrandingAsset asset = (await repository.brandingAssetById(id))!;

      expect(asset.hasFile, isFalse);
      expect(asset.byteSize, isNull);
      expect(asset.kind, BrandingAssetKind.watermark);
    });

    test('assets are filtered by kind', () async {
      await repository.registerBrandingAsset(
        BrandingAsset.registerRow(
          tenantId: 'tenant-1',
          kind: BrandingAssetKind.logo,
          label: 'Mark',
          primaryColor: '#000000',
          secondaryColor: '#FFFFFF',
          createdBy: 'admin-1',
          assetId: 'asset-1',
        ),
      );
      await repository.registerBrandingAsset(
        BrandingAsset.registerRow(
          tenantId: 'tenant-1',
          kind: BrandingAssetKind.letterhead,
          label: 'Paper',
          primaryColor: '#FFFFFF',
          secondaryColor: '#000000',
          createdBy: 'admin-1',
          assetId: 'asset-2',
        ),
      );

      final List<BrandingAsset> logos = await repository.listBrandingAssets(
        'tenant-1',
        assetKind: 'logo',
      );

      expect(logos, hasLength(1));
      expect(logos.single.id, 'asset-1');
    });
  });

  group('department tree', () {
    test('a root department is stored with no parent', () async {
      final String id = await repository.registerDepartment(
        DepartmentNode.registerRow(
          tenantId: 'tenant-1',
          code: 'med',
          name: 'Medicine',
          createdBy: 'admin-1',
          costCentre: 'CC-100',
          departmentId: 'dept-1',
        ),
      );

      final DepartmentNode node = (await repository.departmentById(id))!;

      expect(node.code, 'MED');
      expect(node.isRoot, isTrue);
      expect(node.parentId, isNull);
      expect(node.costCentre, 'CC-100');
      expect(node.hasCostCentre, isTrue);
      expect(node.status, DepartmentStatus.active);
      expect(node.isBillable, isFalse);
    });

    test('a child department keeps its parent', () async {
      await repository.registerDepartment(
        DepartmentNode.registerRow(
          tenantId: 'tenant-1',
          code: 'MED',
          name: 'Medicine',
          createdBy: 'admin-1',
          departmentId: 'dept-1',
        ),
      );
      final String child = await repository.registerDepartment(
        DepartmentNode.registerRow(
          tenantId: 'tenant-1',
          code: 'CARD',
          name: 'Cardiology',
          createdBy: 'admin-1',
          parentId: 'dept-1',
          kind: DepartmentKind.clinical,
          isBillable: true,
          sortOrder: 2,
          departmentId: 'dept-2',
        ),
      );

      final DepartmentNode node = (await repository.departmentById(child))!;

      expect(node.parentId, 'dept-1');
      expect(node.isRoot, isFalse);
      expect(node.isBillable, isTrue);
      expect(node.sortOrder, 2);
      expect(node.kind, DepartmentKind.clinical);
    });

    test('an archived department keeps its reason', () async {
      await repository.registerDepartment(
        DepartmentNode.registerRow(
          tenantId: 'tenant-1',
          code: 'OLD',
          name: 'Closed wing',
          createdBy: 'admin-1',
          departmentId: 'dept-1',
        ),
      );
      await repository.updateDepartment(
        'dept-1',
        departmentArchiveChanges(
          reason: 'Merged into Medicine.',
          at: DateTime.utc(2026, 6, 1),
        ),
      );

      final DepartmentNode node = (await repository.departmentById('dept-1'))!;

      expect(node.status, DepartmentStatus.archived);
      expect(node.isActive, isFalse);
      expect(node.isTerminal, isTrue);
      expect(node.archiveReason, 'Merged into Medicine.');
      expect(node.archivedAt, DateTime.utc(2026, 6, 1));
    });

    test('departments are filtered by status', () async {
      await repository.registerDepartment(
        DepartmentNode.registerRow(
          tenantId: 'tenant-1',
          code: 'LIVE',
          name: 'Live',
          createdBy: 'admin-1',
          departmentId: 'dept-1',
        ),
      );
      await repository.registerDepartment(
        DepartmentNode.registerRow(
          tenantId: 'tenant-1',
          code: 'GONE',
          name: 'Gone',
          createdBy: 'admin-1',
          departmentId: 'dept-2',
        ),
      );
      await repository.updateDepartment(
        'dept-2',
        departmentArchiveChanges(
          reason: 'Closed.',
          at: DateTime.utc(2026, 6, 1),
        ),
      );

      final List<DepartmentNode> live = await repository.listDepartments(
        'tenant-1',
        status: 'active',
      );

      expect(live.map((DepartmentNode node) => node.id), <String>['dept-1']);
    });
  });

  group('tariff masters', () {
    test('a tariff keeps its money, its tax and its window', () async {
      final String id = await repository.registerTariff(
        BillingTariff.registerRow(
          tenantId: 'tenant-1',
          code: 'cons-01',
          serviceName: 'First consultation',
          effectiveFrom: DateTime.utc(2026, 4, 1),
          createdBy: 'admin-1',
          category: TariffCategory.consultation,
          amountMinor: 50000,
          taxRateBps: 1800,
          departmentId: 'dept-1',
          tariffId: 'tariff-1',
        ),
      );

      final BillingTariff tariff = (await repository.tariffById(id))!;

      expect(tariff.code, 'CONS-01');
      expect(tariff.category, TariffCategory.consultation);
      expect(tariff.amountMinor, 50000);
      expect(tariff.taxRateBps, 1800);
      expect(tariff.taxMinor, 9000);
      expect(tariff.grossMinor, 59000);
      expect(tariff.effectiveFrom, DateTime.utc(2026, 4, 1));
      expect(tariff.effectiveTo, isNull);
      expect(tariff.status, TariffStatus.draft);
      expect(tariff.departmentId, 'dept-1');
      expect(tariff.insuranceCapable, isTrue);
    });

    test('a closed window reads back as the day it was written', () async {
      final String id = await repository.registerTariff(
        BillingTariff.registerRow(
          tenantId: 'tenant-1',
          code: 'ROOM-01',
          serviceName: 'Private room',
          effectiveFrom: DateTime.utc(2026, 4, 1),
          effectiveTo: DateTime.utc(2026, 6, 30),
          createdBy: 'admin-1',
          category: TariffCategory.room,
          amountMinor: 250000,
          tariffId: 'tariff-2',
        ),
      );

      final BillingTariff tariff = (await repository.tariffById(id))!;

      expect(tariff.effectiveTo, DateTime.utc(2026, 6, 30));
      expect(tariff.insuranceCapable, isTrue);
    });

    test('a tax-free, cash-only tariff reads that way', () async {
      final String id = await repository.registerTariff(
        BillingTariff.registerRow(
          tenantId: 'tenant-1',
          code: 'CASH-01',
          serviceName: 'Records copy',
          effectiveFrom: DateTime.utc(2026, 4, 1),
          createdBy: 'admin-1',
          amountMinor: 2000,
          insuranceCapable: false,
          tariffId: 'tariff-3',
        ),
      );

      final BillingTariff tariff = (await repository.tariffById(id))!;

      expect(tariff.taxRateBps, 0);
      expect(tariff.grossMinor, 2000);
      expect(tariff.insuranceCapable, isFalse);
    });

    test('tariffs are filtered by code', () async {
      await repository.registerTariff(
        BillingTariff.registerRow(
          tenantId: 'tenant-1',
          code: 'A-1',
          serviceName: 'One',
          effectiveFrom: DateTime.utc(2026, 4, 1),
          createdBy: 'admin-1',
          tariffId: 'tariff-1',
        ),
      );
      await repository.registerTariff(
        BillingTariff.registerRow(
          tenantId: 'tenant-1',
          code: 'B-1',
          serviceName: 'Two',
          effectiveFrom: DateTime.utc(2026, 4, 1),
          createdBy: 'admin-1',
          tariffId: 'tariff-2',
        ),
      );

      final List<BillingTariff> found = await repository.listTariffs(
        'tenant-1',
        code: 'A-1',
      );

      expect(found, hasLength(1));
      expect(found.single.serviceName, 'One');
    });

    test('an approved then retired tariff keeps both stamps', () async {
      await repository.registerTariff(
        BillingTariff.registerRow(
          tenantId: 'tenant-1',
          code: 'X-1',
          serviceName: 'Something',
          effectiveFrom: DateTime.utc(2026, 4, 1),
          createdBy: 'admin-1',
          tariffId: 'tariff-1',
        ),
      );
      await repository.updateTariff(
        'tariff-1',
        tariffApproveChanges(
          approvedBy: 'admin-1',
          at: DateTime.utc(2026, 4, 2),
        ),
      );
      await repository.updateTariff(
        'tariff-1',
        tariffRetireChanges(
          reason: 'Replaced by the 2027 schedule.',
          at: DateTime.utc(2026, 12, 1),
        ),
      );

      final BillingTariff tariff = (await repository.tariffById('tariff-1'))!;

      expect(tariff.status, TariffStatus.retired);
      expect(tariff.approvedBy, 'admin-1');
      expect(tariff.approvedAt, DateTime.utc(2026, 4, 2));
      expect(tariff.retireReason, 'Replaced by the 2027 schedule.');
      expect(tariff.retiredAt, DateTime.utc(2026, 12, 1));
      expect(tariff.isTerminal, isTrue);
    });
  });

  group('ai routing profiles', () {
    test('a profile keeps its route and its residency', () async {
      final String id = await repository.registerRoutingProfile(
        AiRoutingProfile.registerRow(
          tenantId: 'tenant-1',
          profileCode: 'Scribe-Standard',
          displayName: 'Scribe standard',
          primaryModelKey: 'stub_clinical_note_v1',
          fallbackModelKey: 'stub_clinical_note_v0',
          createdBy: 'admin-1',
          taskKind: AiTaskKind.scribe,
          temperatureBps: 2500,
          maxOutputTokens: 2048,
          dataResidency: AiDataResidency.regional,
          profileId: 'routing-1',
        ),
      );

      final AiRoutingProfile profile = (await repository.routingProfileById(
        id,
      ))!;

      expect(profile.profileCode, 'scribe-standard');
      expect(profile.displayName, 'Scribe standard');
      expect(profile.taskKind, AiTaskKind.scribe);
      expect(profile.primaryModelKey, 'stub_clinical_note_v1');
      expect(profile.fallbackModelKey, 'stub_clinical_note_v0');
      expect(profile.temperatureBps, 2500);
      expect(profile.temperature, 0.25);
      expect(profile.maxOutputTokens, 2048);
      expect(profile.dataResidency, AiDataResidency.regional);
      expect(profile.redactPhi, isTrue);
      expect(profile.leavesRedacted, isTrue);
      expect(profile.hasFallback, isTrue);
      expect(profile.status, RoutingProfileStatus.draft);
    });

    test('a domestic profile is usable once it routes', () async {
      await repository.registerRoutingProfile(
        AiRoutingProfile.registerRow(
          tenantId: 'tenant-1',
          profileCode: 'scribe-domestic',
          displayName: 'Scribe domestic',
          primaryModelKey: 'stub_clinical_note_v1',
          createdBy: 'admin-1',
          profileId: 'routing-1',
        ),
      );
      await repository.updateRoutingProfile(
        'routing-1',
        routingActivateChanges(
          activatedBy: 'admin-1',
          at: DateTime.utc(2026, 5, 1),
        ),
      );

      final AiRoutingProfile profile = (await repository.routingProfileById(
        'routing-1',
      ))!;

      expect(profile.isRouting, isTrue);
      expect(profile.isUsable, isTrue);
      expect(profile.hasFallback, isFalse);
      expect(profile.leavesRedacted, isFalse);
      expect(profile.activatedBy, 'admin-1');
    });

    test('profiles are filtered by task kind', () async {
      await repository.registerRoutingProfile(
        AiRoutingProfile.registerRow(
          tenantId: 'tenant-1',
          profileCode: 'scribe-1',
          displayName: 'Scribe',
          primaryModelKey: 'stub_clinical_note_v1',
          createdBy: 'admin-1',
          taskKind: AiTaskKind.scribe,
          profileId: 'routing-1',
        ),
      );
      await repository.registerRoutingProfile(
        AiRoutingProfile.registerRow(
          tenantId: 'tenant-1',
          profileCode: 'code-1',
          displayName: 'Coding',
          primaryModelKey: 'stub_clinical_note_v1',
          createdBy: 'admin-1',
          taskKind: AiTaskKind.coding,
          profileId: 'routing-2',
        ),
      );

      final List<AiRoutingProfile> found = await repository.listRoutingProfiles(
        'tenant-1',
        taskKind: 'coding',
      );

      expect(found, hasLength(1));
      expect(found.single.profileCode, 'code-1');
    });

    test('a retired profile keeps its reason', () async {
      await repository.registerRoutingProfile(
        AiRoutingProfile.registerRow(
          tenantId: 'tenant-1',
          profileCode: 'scribe-old',
          displayName: 'Scribe old',
          primaryModelKey: 'stub_clinical_note_v1',
          createdBy: 'admin-1',
          profileId: 'routing-1',
        ),
      );
      await repository.updateRoutingProfile(
        'routing-1',
        routingActivateChanges(
          activatedBy: 'admin-1',
          at: DateTime.utc(2026, 5, 1),
        ),
      );
      await repository.updateRoutingProfile(
        'routing-1',
        routingRetireChanges(
          reason: 'Superseded by the 2027 model.',
          at: DateTime.utc(2026, 11, 1),
        ),
      );

      final AiRoutingProfile profile = (await repository.routingProfileById(
        'routing-1',
      ))!;

      expect(profile.status, RoutingProfileStatus.retired);
      expect(profile.retireReason, 'Superseded by the 2027 model.');
      expect(profile.retiredAt, DateTime.utc(2026, 11, 1));
      expect(profile.isUsable, isFalse);
    });

    test('an unknown profile is null rather than an error', () async {
      expect(await repository.routingProfileById('missing'), isNull);
    });
  });

  test('every table the repository writes is a declared local table', () {
    expect(LocalTables.settingsProfiles, 'settings_profiles');
    expect(LocalTables.brandingAssets, 'branding_assets');
    expect(LocalTables.departmentHierarchies, 'department_hierarchies');
    expect(LocalTables.billingTariffs, 'billing_tariffs');
    expect(LocalTables.aiRoutingProfiles, 'ai_routing_profiles');
  });
}
