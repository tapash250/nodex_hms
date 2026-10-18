/// Tests for the master settings use cases, the version history and the derived
/// configuration facts (Module 39).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/authorization_snapshot.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/security/second_factor.dart';
import 'package:nodex_hms/domain/settings/settings.dart';
import 'package:nodex_hms/domain/settings/settings_repository.dart';
import 'package:nodex_hms/domain/settings/settings_use_cases.dart';

import 'settings_repository_test.dart' show FakeSettingsStore;

AuthorizationPolicy policyWith(
  Set<String> permissions, {
  Set<String> roles = const <String>{NodexRoles.hospitalSuperAdmin},
  ConnectivityState connectivity = ConnectivityState.online,
  Set<String>? offlinePermissions,
}) {
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
      roles: roles,
      permissions: permissions,
      offlinePermissions: connectivity.isOnline
          ? permissions
          : (offlinePermissions ?? const <String>{}),
      facilityIds: const <String>{'facility-1'},
      departmentIds: const <String>{'department-1'},
      wardIds: const <String>{'ward-1'},
    ),
    connectivity: connectivity,
  );
}

void main() {
  late FakeSettingsStore store;
  late DefaultSettingsRepository repository;
  late DraftSettingsProfileUseCase draftProfile;
  late ActivateSettingsProfileUseCase activateProfile;
  late DraftBrandingAssetUseCase draftBranding;
  late PublishBrandingAssetUseCase publishBranding;
  late DefineDepartmentUseCase defineDepartment;
  late CloseDepartmentUseCase closeDepartment;
  late SetTariffUseCase setTariff;
  late ApproveTariffUseCase approveTariff;
  late RetireTariffUseCase retireTariff;
  late DefineRoutingProfileUseCase defineRouting;
  late ActivateRoutingProfileUseCase activateRouting;
  late RetireRoutingProfileUseCase retireRouting;
  late ReadMasterSettingsUseCase readHub;

  const Set<String> canRead = <String>{NodexPermissions.settingsRead};
  const Set<String> canConfigure = <String>{NodexPermissions.settingsConfigure};
  const Set<String> canTariff = <String>{NodexPermissions.settingsTariff};
  const Set<String> canAi = <String>{NodexPermissions.aiConfigure};

  final AuthorizationPolicy reader = policyWith(canRead);
  final AuthorizationPolicy configurer = policyWith(canConfigure);
  final AuthorizationPolicy biller = policyWith(canTariff);
  final AuthorizationPolicy scientist = policyWith(canAi);
  final DateTime now = DateTime.utc(2026, 6, 11, 12);

  SecondFactorAssertion assertionFor(
    String purpose, {
    String userId = 'admin-1',
    String tenantId = 'tenant-1',
    Duration age = Duration.zero,
  }) => SecondFactorAssertion(
    assertionId: 'assertion-1',
    tenantId: tenantId,
    userId: userId,
    purpose: purpose,
    verifiedAt: now.subtract(age),
  );

  setUp(() {
    store = FakeSettingsStore();
    repository = DefaultSettingsRepository(
      store: store,
      logger: NodexLogger(
        sinks: <NodexLogSink>[InMemoryLogSink()],
        minimumLevel: NodexLogLevel.trace,
      ),
    );
    draftProfile = DraftSettingsProfileUseCase(repository: repository);
    activateProfile = ActivateSettingsProfileUseCase(repository: repository);
    draftBranding = DraftBrandingAssetUseCase(repository: repository);
    publishBranding = PublishBrandingAssetUseCase(repository: repository);
    defineDepartment = DefineDepartmentUseCase(repository: repository);
    closeDepartment = CloseDepartmentUseCase(repository: repository);
    setTariff = SetTariffUseCase(repository: repository);
    approveTariff = ApproveTariffUseCase(repository: repository);
    retireTariff = RetireTariffUseCase(repository: repository);
    defineRouting = DefineRoutingProfileUseCase(repository: repository);
    activateRouting = ActivateRoutingProfileUseCase(repository: repository);
    retireRouting = RetireRoutingProfileUseCase(repository: repository);
    readHub = ReadMasterSettingsUseCase(repository: repository);
  });

  Future<String> seedProfile({
    int version = 1,
    String facilityId = '',
    String hospitalName = 'Nodex General',
    String profileId = '',
  }) => draftProfile.call(
    policy: configurer,
    secondFactor: assertionFor(settingsPurposeConfigure),
    tenantId: 'tenant-1',
    hospitalName: hospitalName,
    createdBy: 'admin-1',
    facilityId: facilityId.isEmpty ? null : facilityId,
    at: now,
    profileId: profileId,
  );

  Future<BrandingAsset> seedAsset({
    String label = 'Hospital mark',
    BrandingAssetKind kind = BrandingAssetKind.logo,
    String primary = '#0B5FFF',
    String secondary = '#FFFFFF',
    bool withFile = true,
  }) async {
    final String id = await draftBranding.call(
      policy: configurer,
      secondFactor: assertionFor(settingsPurposeBranding),
      tenantId: 'tenant-1',
      kind: kind,
      label: label,
      primaryColor: primary,
      secondaryColor: secondary,
      createdBy: 'admin-1',
      storagePath: withFile ? 'branding/$label.svg' : null,
      checksum: withFile ? 'sha256-$label' : null,
      mimeType: withFile ? 'image/svg+xml' : null,
      byteSize: withFile ? 2048 : null,
      at: now,
    );
    return (await repository.brandingAssetById(id))!;
  }

  Future<DepartmentNode> seedDepartment({
    String code = 'MED',
    String name = 'Medicine',
    String? parentId,
    String? costCentre = 'CC-100',
    String departmentId = '',
  }) async {
    final String id = await defineDepartment.call(
      policy: configurer,
      secondFactor: assertionFor(settingsPurposeConfigure),
      tenantId: 'tenant-1',
      code: code,
      name: name,
      createdBy: 'admin-1',
      parentId: parentId,
      costCentre: costCentre,
      at: now,
      departmentId: departmentId,
    );
    return (await repository.departmentById(id))!;
  }

  Future<BillingTariff> seedTariff({
    String code = 'CONS-01',
    DateTime? from,
    DateTime? to,
    int amountMinor = 50000,
    int taxRateBps = 1800,
    String tariffId = '',
  }) async {
    final String id = await setTariff.call(
      policy: biller,
      secondFactor: assertionFor(settingsPurposeTariff),
      tenantId: 'tenant-1',
      code: code,
      serviceName: 'First consultation',
      effectiveFrom: from ?? DateTime.utc(2026, 4, 1),
      createdBy: 'admin-1',
      amountMinor: amountMinor,
      taxRateBps: taxRateBps,
      effectiveTo: to,
      at: now,
      tariffId: tariffId,
    );
    return (await repository.tariffById(id))!;
  }

  Future<AiRoutingProfile> seedRouting({
    String profileCode = 'scribe-standard',
    AiTaskKind taskKind = AiTaskKind.scribe,
    String primaryModelKey = 'stub_clinical_note_v1',
    String? fallbackModelKey,
    AiDataResidency residency = AiDataResidency.inCountry,
    bool redactPhi = true,
    String profileId = '',
  }) async {
    final String id = await defineRouting.call(
      policy: scientist,
      secondFactor: assertionFor(settingsPurposeAiRouting),
      tenantId: 'tenant-1',
      profileCode: profileCode,
      displayName: 'Scribe standard',
      primaryModelKey: primaryModelKey,
      createdBy: 'admin-1',
      taskKind: taskKind,
      fallbackModelKey: fallbackModelKey,
      dataResidency: residency,
      redactPhi: redactPhi,
      at: now,
      profileId: profileId,
    );
    return (await repository.routingProfileById(id))!;
  }

  group('configuration', () {
    test('a new version continues the hospital\'s own numbering', () async {
      await seedProfile(version: 1);
      await seedProfile(version: 2);
      await seedProfile();

      final List<SettingsProfile> profiles = await repository
          .listSettingsProfiles('tenant-1');
      expect(profiles, hasLength(3));
      expect(
        profiles.map((SettingsProfile profile) => profile.version),
        containsAll(<int>[1, 2, 3]),
      );
    });

    test('a facility numbers its versions apart from the hospital', () async {
      await seedProfile();
      final String facility = await seedProfile(facilityId: 'facility-1');

      final SettingsProfile profile = (await repository.settingsProfileById(
        facility,
      ))!;

      expect(profile.version, 1);
      expect(profile.facilityId, 'facility-1');
    });

    test('putting a version in force supersedes the one it replaced', () async {
      final String first = await seedProfile();
      final String second = await seedProfile();

      await activateProfile.call(
        policy: configurer,
        secondFactor: assertionFor(settingsPurposeConfigure),
        profile: (await repository.settingsProfileById(first))!,
        activatedBy: 'admin-1',
        at: now,
      );
      await activateProfile.call(
        policy: configurer,
        secondFactor: assertionFor(settingsPurposeConfigure),
        profile: (await repository.settingsProfileById(second))!,
        activatedBy: 'admin-1',
        at: now,
      );

      final SettingsProfile replaced = (await repository.settingsProfileById(
        first,
      ))!;
      final SettingsProfile inForce = (await repository.settingsProfileById(
        second,
      ))!;

      expect(replaced.status, SettingsProfileStatus.superseded);
      expect(replaced.supersededAt, DateTime.utc(2026, 6, 11, 12));
      expect(inForce.status, SettingsProfileStatus.active);
      expect(inForce.activatedBy, 'admin-1');

      final List<SettingsProfile> active = await repository
          .listSettingsProfiles('tenant-1', status: 'active');
      expect(active, hasLength(1));
      expect(active.single.id, second);
    });

    test('a version already in force is not put in force again', () async {
      final String id = await seedProfile();
      final SettingsProfile profile = (await repository.settingsProfileById(
        id,
      ))!;

      await activateProfile.call(
        policy: configurer,
        secondFactor: assertionFor(settingsPurposeConfigure),
        profile: profile,
        activatedBy: 'admin-1',
        at: now,
      );

      await expectLater(
        activateProfile.call(
          policy: configurer,
          secondFactor: assertionFor(settingsPurposeConfigure),
          profile: (await repository.settingsProfileById(id))!,
          activatedBy: 'admin-1',
          at: now,
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('a superseded version is never reopened', () async {
      final String id = await seedProfile();
      await repository.updateSettingsProfile(
        id,
        settingsProfileSupersedeChanges(at: now),
      );

      await expectLater(
        activateProfile.call(
          policy: configurer,
          secondFactor: assertionFor(settingsPurposeConfigure),
          profile: (await repository.settingsProfileById(id))!,
          activatedBy: 'admin-1',
          at: now,
        ),
        throwsA(isA<AuthorizationError>()),
      );
      expect(
        settingsProfileCanTransition(
          SettingsProfileStatus.superseded,
          SettingsProfileStatus.active,
        ),
        isFalse,
      );
    });

    test('a change without a second factor is refused', () async {
      await expectLater(
        draftProfile.call(
          policy: configurer,
          secondFactor: null,
          tenantId: 'tenant-1',
          hospitalName: 'Nodex General',
          createdBy: 'admin-1',
          at: now,
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'settings_second_factor_required',
          ),
        ),
      );
    });

    test('a second factor proved for somebody else is refused', () async {
      await expectLater(
        draftProfile.call(
          policy: configurer,
          secondFactor: assertionFor(
            settingsPurposeConfigure,
            userId: 'admin-2',
          ),
          tenantId: 'tenant-1',
          hospitalName: 'Nodex General',
          createdBy: 'admin-1',
          at: now,
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'settings_second_factor_foreign',
          ),
        ),
      );
    });

    test('a stale second factor is refused', () async {
      await expectLater(
        draftProfile.call(
          policy: configurer,
          secondFactor: assertionFor(
            settingsPurposeConfigure,
            age: const Duration(minutes: 30),
          ),
          tenantId: 'tenant-1',
          hospitalName: 'Nodex General',
          createdBy: 'admin-1',
          at: now,
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'settings_second_factor_stale',
          ),
        ),
      );
    });

    test('a second factor proved at another door is refused', () async {
      await expectLater(
        draftProfile.call(
          policy: configurer,
          secondFactor: assertionFor(settingsPurposeTariff),
          tenantId: 'tenant-1',
          hospitalName: 'Nodex General',
          createdBy: 'admin-1',
          at: now,
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'settings_second_factor_purpose_mismatch',
          ),
        ),
      );
    });

    test(
      'someone who is not a hospital administrator cannot change it',
      () async {
        final AuthorizationPolicy officer = policyWith(
          canConfigure,
          roles: const <String>{NodexRoles.medicalOfficer},
        );

        await expectLater(
          draftProfile.call(
            policy: officer,
            secondFactor: assertionFor(settingsPurposeConfigure),
            tenantId: 'tenant-1',
            hospitalName: 'Nodex General',
            createdBy: 'admin-1',
            at: now,
          ),
          throwsA(
            isA<AuthorizationError>().having(
              (AuthorizationError error) => error.code,
              'code',
              'settings_super_admin_required',
            ),
          ),
        );
      },
    );

    test('configuration cannot be changed without a network', () async {
      await expectLater(
        draftProfile.call(
          policy: policyWith(
            canConfigure,
            connectivity: ConnectivityState.offline,
            offlinePermissions: canRead,
          ),
          secondFactor: assertionFor(settingsPurposeConfigure),
          tenantId: 'tenant-1',
          hospitalName: 'Nodex General',
          createdBy: 'admin-1',
          at: now,
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('the configuration in force prefers the facility\'s own profile', () {
      final SettingsProfile hospitalWide = SettingsProfile(
        id: 'hospital-1',
        tenantId: 'tenant-1',
        version: 1,
        status: SettingsProfileStatus.active,
        hospitalName: 'Nodex General',
        timezone: 'UTC',
        defaultLocale: 'en',
        dateFormat: DateFormatStyle.dayMonthYear,
        currencyCode: 'INR',
        currencyMinorUnits: 2,
        fiscalYearStartMonth: 4,
        appointmentSlotMinutes: 15,
        sessionIdleMinutes: 15,
        requireTwoFactor: true,
        createdBy: 'admin-1',
        updatedAt: now,
      );
      final SettingsProfile facility = SettingsProfile(
        id: 'facility-1',
        tenantId: 'tenant-1',
        version: 1,
        status: SettingsProfileStatus.active,
        hospitalName: 'Nodex General North',
        timezone: 'Asia/Kolkata',
        defaultLocale: 'en-IN',
        dateFormat: DateFormatStyle.dayMonthYear,
        currencyCode: 'INR',
        currencyMinorUnits: 2,
        fiscalYearStartMonth: 4,
        appointmentSlotMinutes: 20,
        sessionIdleMinutes: 10,
        requireTwoFactor: true,
        createdBy: 'admin-1',
        updatedAt: now,
        facilityId: 'facility-1',
      );

      final SettingsProfile? resolved = activeSettingsProfile(<SettingsProfile>[
        hospitalWide,
        facility,
      ], facilityId: 'facility-1');
      final SettingsProfile? fallback = activeSettingsProfile(<SettingsProfile>[
        hospitalWide,
        facility,
      ], facilityId: 'facility-2');

      expect(resolved?.id, 'facility-1');
      expect(fallback?.id, 'hospital-1');
    });

    test('money and the fiscal year are written the hospital\'s way', () {
      final SettingsProfile profile = SettingsProfile(
        id: 'profile-1',
        tenantId: 'tenant-1',
        version: 1,
        status: SettingsProfileStatus.active,
        hospitalName: 'Nodex General',
        timezone: 'Asia/Kolkata',
        defaultLocale: 'en-IN',
        dateFormat: DateFormatStyle.dayMonthYear,
        currencyCode: 'INR',
        currencyMinorUnits: 2,
        fiscalYearStartMonth: 4,
        appointmentSlotMinutes: 15,
        sessionIdleMinutes: 15,
        requireTwoFactor: true,
        createdBy: 'admin-1',
        updatedAt: now,
      );

      expect(profile.formatMoney(59000), 'INR 590.00');
      expect(profile.formatMoney(-250), 'INR -2.50');
      expect(profile.fiscalYearStart(2026), DateTime.utc(2026, 4, 1));
      expect(profile.fiscalYearOf(DateTime.utc(2026, 3, 31)), 2025);
      expect(profile.fiscalYearOf(DateTime.utc(2026, 4, 1)), 2026);
      expect(
        profile.slotStart(DateTime.utc(2026, 6, 11, 9, 44)),
        DateTime.utc(2026, 6, 11, 9, 30),
      );
    });

    test('a currency minor unit count of zero writes whole units', () {
      final SettingsProfile profile = SettingsProfile(
        id: 'profile-1',
        tenantId: 'tenant-1',
        version: 1,
        status: SettingsProfileStatus.active,
        hospitalName: 'Nodex General',
        timezone: 'UTC',
        defaultLocale: 'en',
        dateFormat: DateFormatStyle.yearMonthDay,
        currencyCode: 'JPY',
        currencyMinorUnits: 0,
        fiscalYearStartMonth: 1,
        appointmentSlotMinutes: 10,
        sessionIdleMinutes: 5,
        requireTwoFactor: true,
        createdBy: 'admin-1',
        updatedAt: now,
      );

      expect(profile.formatMoney(1500), 'JPY 1500');
    });
  });

  group('branding', () {
    test('publishing artwork supersedes the piece it replaced', () async {
      final BrandingAsset first = await seedAsset(label: 'First mark');
      final BrandingAsset second = await seedAsset(label: 'Second mark');

      await publishBranding.call(
        policy: configurer,
        secondFactor: assertionFor(settingsPurposeBranding),
        asset: first,
        activatedBy: 'admin-1',
        at: now,
      );
      await publishBranding.call(
        policy: configurer,
        secondFactor: assertionFor(settingsPurposeBranding),
        asset: second,
        activatedBy: 'admin-1',
        at: now,
      );

      expect(
        (await repository.brandingAssetById(first.id))!.status,
        BrandingAssetStatus.superseded,
      );
      expect((await repository.brandingAssetById(second.id))!.isActive, isTrue);
    });

    test('artwork without a file is not put into use', () async {
      final BrandingAsset placeholder = await seedAsset(withFile: false);

      await expectLater(
        publishBranding.call(
          policy: configurer,
          secondFactor: assertionFor(settingsPurposeBranding),
          asset: placeholder,
          activatedBy: 'admin-1',
          at: now,
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'branding_asset_file_missing',
          ),
        ),
      );
    });

    test('slug of two colours that cannot be told apart is flagged', () async {
      final BrandingAsset unreadable = await seedAsset(
        label: 'Low contrast',
        primary: '#777777',
        secondary: '#888888',
      );
      final BrandingAsset readable = await seedAsset(
        label: 'High contrast',
        primary: '#0B5FFF',
        secondary: '#FFFFFF',
      );

      expect(brandingContrastRatio(unreadable), lessThan(4.5));
      expect(brandingContrastIsReadable(unreadable), isFalse);
      expect(brandingContrastIsReadable(readable), isTrue);

      await publishBranding.call(
        policy: configurer,
        secondFactor: assertionFor(settingsPurposeBranding),
        asset: unreadable,
        activatedBy: 'admin-1',
        at: now,
      );

      final MasterSettingsBoard board = await readHub.board(
        policy: reader,
        tenantId: 'tenant-1',
        now: now,
      );

      expect(
        board.unreadableBranding.map((BrandingAsset asset) => asset.label),
        <String>['Low contrast'],
      );
      expect(board.activeDepartments, isEmpty);
    });

    test('a colour that is not a hex pair is refused', () async {
      await expectLater(
        draftBranding.call(
          policy: configurer,
          secondFactor: assertionFor(settingsPurposeBranding),
          tenantId: 'tenant-1',
          kind: BrandingAssetKind.logo,
          label: 'Bad colour',
          primaryColor: 'blue',
          secondaryColor: '#FFFFFF',
          createdBy: 'admin-1',
          at: now,
        ),
        throwsA(isA<ValidationError>()),
      );
    });
  });

  group('departments', () {
    test('a department code is unique in the hospital', () async {
      await seedDepartment(code: 'MED', name: 'Medicine');

      await expectLater(
        seedDepartment(code: 'med', name: 'Another medicine'),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'department_code_duplicate',
          ),
        ),
      );
    });

    test('a branch is not added under a closed department', () async {
      final DepartmentNode parent = await seedDepartment();

      await closeDepartment.call(
        policy: configurer,
        secondFactor: assertionFor(settingsPurposeConfigure),
        department: parent,
        reason: 'Merged into Surgery.',
        userId: 'admin-1',
        at: now,
      );

      await expectLater(
        seedDepartment(code: 'CARD', name: 'Cardiology', parentId: parent.id),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'department_parent_archived',
          ),
        ),
      );
    });

    test('a department with live departments under it is not closed', () async {
      final DepartmentNode parent = await seedDepartment();
      await seedDepartment(
        code: 'CARD',
        name: 'Cardiology',
        parentId: parent.id,
      );

      await expectLater(
        closeDepartment.call(
          policy: configurer,
          secondFactor: assertionFor(settingsPurposeConfigure),
          department: parent,
          reason: 'Tidying up.',
          userId: 'admin-1',
          at: now,
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'department_has_live_children',
          ),
        ),
      );
    });

    test('closing a branch keeps the reason and the whole branch', () async {
      final DepartmentNode parent = await seedDepartment();
      final DepartmentNode child = await seedDepartment(
        code: 'CARD',
        name: 'Cardiology',
        parentId: parent.id,
      );

      await closeDepartment.call(
        policy: configurer,
        secondFactor: assertionFor(settingsPurposeConfigure),
        department: child,
        reason: 'Moved to the Cardiac Centre.',
        userId: 'admin-1',
        at: now,
      );

      final DepartmentNode closed = (await repository.departmentById(
        child.id,
      ))!;
      expect(closed.isTerminal, isTrue);
      expect(closed.archiveReason, 'Moved to the Cardiac Centre.');

      final MasterSettingsBoard board = await readHub.board(
        policy: reader,
        tenantId: 'tenant-1',
        now: now,
      );
      expect(board.activeDepartments, hasLength(1));
      expect(board.roots.single.id, parent.id);
      expect(board.childrenOf(parent.id), isEmpty);
    });

    test('a branch is walked from the tree rather than stored', () async {
      final DepartmentNode root = await seedDepartment(
        code: 'CLIN',
        name: 'Clinical services',
        costCentre: null,
      );
      final DepartmentNode middle = await seedDepartment(
        code: 'MED',
        name: 'Medicine',
        parentId: root.id,
      );
      final DepartmentNode leaf = await seedDepartment(
        code: 'CARD',
        name: 'Cardiology',
        parentId: middle.id,
      );

      final MasterSettingsBoard board = await readHub.board(
        policy: reader,
        tenantId: 'tenant-1',
        now: now,
      );
      final List<DepartmentNode> tree = board.departments;
      final List<DepartmentNode> detached = <DepartmentNode>[
        for (final DepartmentNode node in tree)
          if (node.id != middle.id) node,
      ];

      expect(departmentLevel(tree, root.id), 0);
      expect(departmentLevel(tree, middle.id), 1);
      expect(departmentLevel(tree, leaf.id), 2);
      expect(board.levelOf(leaf.id), 2);
      expect(board.pathOf(leaf.id), 'CLIN/MED/CARD');
      expect(
        departmentAncestors(
          tree,
          leaf.id,
        ).map((DepartmentNode node) => node.code).toList(),
        <String>['MED', 'CLIN'],
      );
      expect(
        departmentDescendants(
          tree,
          root.id,
        ).map((DepartmentNode node) => node.code),
        containsAll(<String>['MED', 'CARD']),
      );
      expect(
        departmentIsDescendant(
          departments: tree,
          id: root.id,
          candidate: leaf.id,
        ),
        isTrue,
      );
      expect(
        departmentIsDescendant(
          departments: detached,
          id: root.id,
          candidate: leaf.id,
        ),
        isFalse,
      );
      expect(
        board.departmentsWithoutCostCentre.map(
          (DepartmentNode node) => node.code,
        ),
        contains('CLIN'),
      );
    });

    test('a department with a negative sort order is refused', () {
      expect(
        () => DepartmentNode.registerRow(
          tenantId: 'tenant-1',
          code: 'MED',
          name: 'Medicine',
          createdBy: 'admin-1',
          sortOrder: -1,
        ),
        throwsA(isA<ValidationError>()),
      );
      expect(
        departmentCanTransition(
          DepartmentStatus.active,
          DepartmentStatus.archived,
        ),
        isTrue,
      );
      expect(
        departmentCanTransition(
          DepartmentStatus.archived,
          DepartmentStatus.active,
        ),
        isFalse,
      );
    });

    test('a department cannot be closed without a reason', () {
      expect(
        () => departmentArchiveChanges(reason: '   '),
        throwsA(isA<ValidationError>()),
      );
    });
  });

  group('tariffs', () {
    test('two live tariffs for one code may not overlap', () async {
      final BillingTariff first = await seedTariff(
        from: DateTime.utc(2026, 4, 1),
        to: DateTime.utc(2026, 6, 30),
      );
      final BillingTariff second = await seedTariff(
        from: DateTime.utc(2026, 6, 1),
        to: DateTime.utc(2026, 12, 31),
      );

      expect(tariffOverlaps(first, second), isTrue);

      await approveTariff.call(
        policy: biller,
        secondFactor: assertionFor(settingsPurposeTariff),
        tariff: first,
        approvedBy: 'admin-1',
        at: now,
      );

      await expectLater(
        approveTariff.call(
          policy: biller,
          secondFactor: assertionFor(settingsPurposeTariff),
          tariff: (await repository.tariffById(second.id))!,
          approvedBy: 'admin-1',
          at: now,
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'billing_tariff_window_overlap',
          ),
        ),
      );
    });

    test('a tariff that starts after the live one ends is approved', () async {
      await seedTariff(
        from: DateTime.utc(2026, 4, 1),
        to: DateTime.utc(2026, 6, 30),
        tariffId: 'tariff-1',
      );
      await seedTariff(from: DateTime.utc(2026, 7, 1), tariffId: 'tariff-2');

      await approveTariff.call(
        policy: biller,
        secondFactor: assertionFor(settingsPurposeTariff),
        tariff: (await repository.tariffById('tariff-1'))!,
        approvedBy: 'admin-1',
        at: now,
      );
      await approveTariff.call(
        policy: biller,
        secondFactor: assertionFor(settingsPurposeTariff),
        tariff: (await repository.tariffById('tariff-2'))!,
        approvedBy: 'admin-1',
        at: now,
      );

      final List<BillingTariff> live = await repository.listTariffs(
        'tenant-1',
        status: 'active',
      );
      expect(live, hasLength(2));
    });

    test('a draft tariff is discarded, not retired', () async {
      final BillingTariff draft = await seedTariff();

      await expectLater(
        retireTariff.call(
          policy: biller,
          secondFactor: assertionFor(settingsPurposeTariff),
          tariff: draft,
          reason: 'Not needed.',
          userId: 'admin-1',
          at: now,
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('a tariff is live only inside its own window', () async {
      final BillingTariff tariff = await seedTariff(
        from: DateTime.utc(2026, 4, 1),
        to: DateTime.utc(2026, 6, 30),
      );

      expect(tariffIsLive(tariff, at: DateTime.utc(2026, 5, 1)), isFalse);
      expect(tariff.taxMinor, 9000);
      expect(tariff.grossMinor, 59000);
      expect(tariff.taxRatePercent, 18);

      await approveTariff.call(
        policy: biller,
        secondFactor: assertionFor(settingsPurposeTariff),
        tariff: tariff,
        approvedBy: 'admin-1',
        at: now,
      );

      final BillingTariff live = (await repository.tariffById(tariff.id))!;

      expect(tariffIsLive(live, at: DateTime.utc(2026, 5, 1)), isTrue);
      expect(tariffIsLive(live, at: DateTime.utc(2026, 4, 1)), isTrue);
      expect(tariffIsLive(live, at: DateTime.utc(2026, 6, 30)), isTrue);
      expect(tariffIsLive(live, at: DateTime.utc(2026, 7, 1)), isFalse);
      expect(tariffIsLive(live, at: DateTime.utc(2026, 3, 31)), isFalse);
      expect(live.approvedBy, 'admin-1');
    });

    test('retiring a live tariff keeps the reason', () async {
      final BillingTariff tariff = await seedTariff();
      await approveTariff.call(
        policy: biller,
        secondFactor: assertionFor(settingsPurposeTariff),
        tariff: tariff,
        approvedBy: 'admin-1',
        at: now,
      );

      await retireTariff.call(
        policy: biller,
        secondFactor: assertionFor(settingsPurposeTariff),
        tariff: (await repository.tariffById(tariff.id))!,
        reason: 'Replaced by the 2027 schedule.',
        userId: 'admin-1',
        at: now,
      );

      final BillingTariff retired = (await repository.tariffById(tariff.id))!;
      expect(retired.isTerminal, isTrue);
      expect(retired.retireReason, 'Replaced by the 2027 schedule.');
      expect(tariffIsLive(retired, at: DateTime.utc(2026, 5, 1)), isFalse);
    });

    test('a window that ends before it starts is refused', () {
      expect(
        () => BillingTariff.registerRow(
          tenantId: 'tenant-1',
          code: 'X-1',
          serviceName: 'Something',
          effectiveFrom: DateTime.utc(2026, 6, 1),
          effectiveTo: DateTime.utc(2026, 5, 1),
          createdBy: 'admin-1',
        ),
        throwsA(isA<ValidationError>()),
      );
      expect(
        () => BillingTariff.registerRow(
          tenantId: 'tenant-1',
          code: 'X-1',
          serviceName: 'Something',
          effectiveFrom: DateTime.utc(2026, 6, 1),
          createdBy: 'admin-1',
          taxRateBps: 10001,
        ),
        throwsA(isA<ValidationError>()),
      );
    });

    test('a date-only window is read as the day it was written', () {
      final BillingTariff tariff = BillingTariff.fromRow(
        const <String, Object?>{
          'id': 'tariff-1',
          'tenant_id': 'tenant-1',
          'code': 'CONS-01',
          'service_name': 'First consultation',
          'category': 'consultation',
          'currency_code': 'INR',
          'amount_minor': 500,
          'tax_rate_bps': 0,
          'insurance_capable': 1,
          'status': 'draft',
          'effective_from': '2026-04-01',
          'created_by': 'admin-1',
          'updated_at': '2026-04-01T00:00:00.000Z',
        },
      );

      expect(tariff.effectiveFrom, DateTime.utc(2026, 4, 1));
      expect(tariff.effectiveTo, isNull);
      expect(tariff.insuranceCapable, isTrue);
    });
  });

  group('ai routing', () {
    test('putting a profile to work supersedes the one it replaced', () async {
      final AiRoutingProfile first = await seedRouting(
        profileCode: 'scribe-first',
      );
      final AiRoutingProfile second = await seedRouting(
        profileCode: 'scribe-second',
      );

      await activateRouting.call(
        policy: scientist,
        secondFactor: assertionFor(settingsPurposeAiRouting),
        profile: first,
        activatedBy: 'admin-1',
        at: now,
      );
      await activateRouting.call(
        policy: scientist,
        secondFactor: assertionFor(settingsPurposeAiRouting),
        profile: second,
        activatedBy: 'admin-1',
        at: now,
      );

      final AiRoutingProfile replaced = (await repository.routingProfileById(
        first.id,
      ))!;
      final AiRoutingProfile routing = (await repository.routingProfileById(
        second.id,
      ))!;

      expect(replaced.status, RoutingProfileStatus.retired);
      expect(replaced.retireReason, 'Replaced by scribe-second.');
      expect(routing.isUsable, isTrue);
    });

    test('a profile that may leave the country must redact first', () async {
      await expectLater(
        defineRouting.call(
          policy: scientist,
          secondFactor: assertionFor(settingsPurposeAiRouting),
          tenantId: 'tenant-1',
          profileCode: 'scribe-global',
          displayName: 'Scribe global',
          primaryModelKey: 'stub_clinical_note_v1',
          createdBy: 'admin-1',
          dataResidency: AiDataResidency.global,
          redactPhi: false,
          at: now,
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.fieldErrors.keys,
            'fields',
            contains('redact_phi'),
          ),
        ),
      );
    });

    test('a regional profile that redacts is accepted and usable', () async {
      final AiRoutingProfile profile = await seedRouting(
        profileCode: 'scribe-regional',
        residency: AiDataResidency.regional,
      );

      expect(profile.leavesRedacted, isTrue);
      expect(profile.isUsable, isFalse);

      await activateRouting.call(
        policy: scientist,
        secondFactor: assertionFor(settingsPurposeAiRouting),
        profile: profile,
        activatedBy: 'admin-1',
        at: now,
      );

      final AiRoutingProfile routing = (await repository.routingProfileById(
        profile.id,
      ))!;
      expect(routing.isRouting, isTrue);
      expect(routing.isUsable, isTrue);
      expect(routing.leavesRedacted, isTrue);
    });

    test('a routing profile code is unique in the hospital', () async {
      await seedRouting(profileCode: 'scribe-standard');

      await expectLater(
        seedRouting(profileCode: 'SCRIBE-STANDARD'),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'ai_routing_profile_code_duplicate',
          ),
        ),
      );
    });

    test('a fallback has to be a different model', () {
      expect(
        () => AiRoutingProfile.registerRow(
          tenantId: 'tenant-1',
          profileCode: 'scribe-standard',
          displayName: 'Scribe standard',
          primaryModelKey: 'stub_clinical_note_v1',
          fallbackModelKey: 'stub_clinical_note_v1',
          createdBy: 'admin-1',
        ),
        throwsA(isA<ValidationError>()),
      );
      expect(
        routingProfileCanTransition(
          RoutingProfileStatus.active,
          RoutingProfileStatus.retired,
        ),
        isTrue,
      );
      expect(
        routingProfileCanTransition(
          RoutingProfileStatus.retired,
          RoutingProfileStatus.active,
        ),
        isFalse,
      );
    });

    test('a draft profile is discarded, not retired', () async {
      final AiRoutingProfile draft = await seedRouting();

      await expectLater(
        retireRouting.call(
          policy: scientist,
          secondFactor: assertionFor(settingsPurposeAiRouting),
          profile: draft,
          reason: 'Not needed.',
          userId: 'admin-1',
          at: now,
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });
  });

  group('reading the hub', () {
    test('the board gates every read', () async {
      await expectLater(
        readHub.board(
          policy: policyWith(const <String>{}),
          tenantId: 'tenant-1',
          now: now,
        ),
        throwsA(isA<AuthorizationError>()),
      );
      await expectLater(
        readHub.tariffsOf(
          policy: policyWith(const <String>{}),
          tenantId: 'tenant-1',
        ),
        throwsA(isA<AuthorizationError>()),
      );
      await expectLater(
        readHub.routingProfilesOf(
          policy: policyWith(const <String>{}),
          tenantId: 'tenant-1',
        ),
        throwsA(isA<AuthorizationError>()),
      );
      await expectLater(
        readHub.departmentsOf(
          policy: policyWith(const <String>{}),
          tenantId: 'tenant-1',
        ),
        throwsA(isA<AuthorizationError>()),
      );
      await expectLater(
        readHub.assetsOf(
          policy: policyWith(const <String>{}),
          tenantId: 'tenant-1',
        ),
        throwsA(isA<AuthorizationError>()),
      );
      await expectLater(
        readHub.profilesOf(
          policy: policyWith(const <String>{}),
          tenantId: 'tenant-1',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('the hub reads offline, because a device renders by it', () async {
      final MasterSettingsBoard board = await readHub.board(
        policy: policyWith(
          canRead,
          connectivity: ConnectivityState.offline,
          offlinePermissions: canRead,
        ),
        tenantId: 'tenant-1',
        now: now,
      );

      expect(board.profiles, isEmpty);
      expect(board.configurationFor(), isNull);
      expect(board.needsAttention, isTrue);
    });

    test('the board reports what wants a decision', () async {
      final String profileId = await seedProfile();
      await activateProfile.call(
        policy: configurer,
        secondFactor: assertionFor(settingsPurposeConfigure),
        profile: (await repository.settingsProfileById(profileId))!,
        activatedBy: 'admin-1',
        at: now,
      );
      await seedDepartment(code: 'CLIN', name: 'Clinical', costCentre: null);
      await seedTariff();
      await seedRouting(profileCode: 'scribe-first');
      await activateRouting.call(
        policy: scientist,
        secondFactor: assertionFor(settingsPurposeAiRouting),
        profile: (await repository.listRoutingProfiles('tenant-1')).single,
        activatedBy: 'admin-1',
        at: now,
      );

      final MasterSettingsBoard board = await readHub.board(
        policy: reader,
        tenantId: 'tenant-1',
        now: now,
      );

      expect(board.configurationFor()?.id, profileId);
      expect(board.departmentsWithoutCostCentre, hasLength(1));
      expect(board.tariffsAwaitingApproval, hasLength(1));
      expect(
        board.routingProfilesWithoutFallback.map(
          (AiRoutingProfile profile) => profile.profileCode,
        ),
        <String>['scribe-first'],
      );
      expect(board.unroutedTaskKinds, hasLength(AiTaskKind.values.length - 1));
      expect(board.liveTariffs, isEmpty);
      expect(board.needsAttention, isTrue);
      expect(board.historyFor().single.id, profileId);
    });

    test('a live tariff is the one the counter bills from', () async {
      final BillingTariff tariff = await seedTariff(
        from: DateTime.utc(2026, 4, 1),
        to: DateTime.utc(2026, 12, 31),
      );
      await approveTariff.call(
        policy: biller,
        secondFactor: assertionFor(settingsPurposeTariff),
        tariff: tariff,
        approvedBy: 'admin-1',
        at: now,
      );

      final MasterSettingsBoard board = await readHub.board(
        policy: reader,
        tenantId: 'tenant-1',
        now: DateTime.utc(2026, 6, 11, 12),
      );

      expect(board.tariffFor('CONS-01')?.id, tariff.id);
      expect(board.tariffFor('NOT-A-CODE'), isNull);
      expect(board.liveTariffs, hasLength(1));
      expect(board.tariffsAwaitingApproval, isEmpty);
    });

    test('a routing profile answers the task it was written for', () async {
      final AiRoutingProfile scribe = await seedRouting(
        profileCode: 'scribe-standard',
        taskKind: AiTaskKind.scribe,
      );
      await activateRouting.call(
        policy: scientist,
        secondFactor: assertionFor(settingsPurposeAiRouting),
        profile: scribe,
        activatedBy: 'admin-1',
        at: now,
      );

      final MasterSettingsBoard board = await readHub.board(
        policy: reader,
        tenantId: 'tenant-1',
        now: now,
      );

      expect(board.routingFor(taskKind: AiTaskKind.scribe)?.id, scribe.id);
      expect(board.routingFor(taskKind: AiTaskKind.coding), isNull);
    });
  });
}
