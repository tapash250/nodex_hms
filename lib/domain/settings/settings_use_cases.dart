/// Master settings use cases (Module 39).
///
/// Every mutation here demands three things the client cannot fake, because this
/// module changes what every other module means:
///
///   * the hospital-administrator role, checked before the permission, because
///     the specification restricts the hub to Super-Admins rather than to
///     whoever holds a key;
///   * an active network, carried on the permission rows themselves
///     (`requires_online`), so the offline permission subset never contains
///     them; and
///   * a fresh [SecondFactorAssertion], so a device that was unlocked and left
///     on a desk cannot change the currency.
///
/// Reading stays open, and offline: a device needs the hospital's timezone, its
/// currency and its branding to render a screen while the network is down, and
/// none of those are secrets.
library;

import 'package:meta/meta.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/security/second_factor.dart';
import 'package:nodex_hms/domain/settings/settings.dart';
import 'package:nodex_hms/domain/settings/settings_repository.dart';

/// Refuses a change that the specification reserves to hospital administrators.
void _requireAdministrator(AuthorizationPolicy policy) {
  if (!policy.hasRole(NodexRoles.hospitalSuperAdmin)) {
    throw const AuthorizationError(
      message: 'Only a hospital administrator changes the hospital itself.',
      code: 'settings_super_admin_required',
    );
  }
}

/// Refuses a change made without a fresh second factor.
///
/// The assertion has to belong to the person making the change, in the tenant
/// they are making it in, and it has to have been proved moments ago: an
/// assertion is evidence, and evidence goes stale.
void _requireSecondFactor({
  required AuthorizationPolicy policy,
  required SecondFactorAssertion? secondFactor,
  required String tenantId,
  required String userId,
  required DateTime now,
  required String purpose,
}) {
  if (secondFactor == null) {
    throw const AuthorizationError(
      message: 'This change needs a second factor proved a moment ago.',
      code: 'settings_second_factor_required',
    );
  }
  if (!secondFactor.belongsTo(tenantId: tenantId, userId: userId)) {
    throw const AuthorizationError(
      message: 'That second factor was proved for somebody else.',
      code: 'settings_second_factor_foreign',
    );
  }
  if (!secondFactor.isFreshAt(now)) {
    throw const AuthorizationError(
      message: 'That second factor has expired. Prove it again.',
      code: 'settings_second_factor_stale',
    );
  }
  if (secondFactor.purpose != purpose) {
    throw const AuthorizationError(
      message: 'That second factor was proved for a different change.',
      code: 'settings_second_factor_purpose_mismatch',
    );
  }
}

/// Writes a new draft settings profile.
final class DraftSettingsProfileUseCase {
  /// Creates the use case.
  DraftSettingsProfileUseCase({required this._repository});

  final SettingsRepository _repository;

  Future<String> call({
    required AuthorizationPolicy policy,
    required SecondFactorAssertion? secondFactor,
    required String tenantId,
    required String hospitalName,
    required String createdBy,
    String timezone = 'UTC',
    String defaultLocale = 'en',
    DateFormatStyle dateFormat = DateFormatStyle.dayMonthYear,
    String currencyCode = 'INR',
    int currencyMinorUnits = 2,
    int fiscalYearStartMonth = 4,
    int appointmentSlotMinutes = 15,
    int sessionIdleMinutes = 15,
    bool requireTwoFactor = true,
    String? facilityId,
    DateTime? at,
    String profileId = '',
  }) async {
    policy.require(NodexPermissions.settingsConfigure);
    _requireAdministrator(policy);
    final DateTime now = (at ?? DateTime.now()).toUtc();
    _requireSecondFactor(
      policy: policy,
      secondFactor: secondFactor,
      tenantId: tenantId,
      userId: createdBy,
      now: now,
      purpose: settingsPurposeConfigure,
    );
    final List<SettingsProfile> existing = await _repository
        .listSettingsProfiles(tenantId);
    return _repository.registerSettingsProfile(
      SettingsProfile.registerRow(
        tenantId: tenantId,
        version: nextSettingsVersion(existing, facilityId: facilityId),
        hospitalName: hospitalName,
        createdBy: createdBy,
        timezone: timezone,
        defaultLocale: defaultLocale,
        dateFormat: dateFormat,
        currencyCode: currencyCode,
        currencyMinorUnits: currencyMinorUnits,
        fiscalYearStartMonth: fiscalYearStartMonth,
        appointmentSlotMinutes: appointmentSlotMinutes,
        sessionIdleMinutes: sessionIdleMinutes,
        requireTwoFactor: requireTwoFactor,
        facilityId: facilityId,
        profileId: profileId,
      ),
    );
  }
}

/// Brings a settings profile into force, superseding the one it replaces.
final class ActivateSettingsProfileUseCase {
  /// Creates the use case.
  ActivateSettingsProfileUseCase({required this._repository});

  final SettingsRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required SecondFactorAssertion? secondFactor,
    required SettingsProfile profile,
    required String activatedBy,
    DateTime? at,
  }) async {
    policy.require(NodexPermissions.settingsConfigure);
    _requireAdministrator(policy);
    final DateTime now = (at ?? DateTime.now()).toUtc();
    _requireSecondFactor(
      policy: policy,
      secondFactor: secondFactor,
      tenantId: profile.tenantId,
      userId: activatedBy,
      now: now,
      purpose: settingsPurposeConfigure,
    );
    if (!settingsProfileCanTransition(
      profile.status,
      SettingsProfileStatus.active,
    )) {
      throw AuthorizationError(
        message: profile.status.isTerminal
            ? 'That version has already been replaced.'
            : 'That version is already in force.',
        code: 'settings_profile_transition_invalid',
      );
    }
    // The profile in force is superseded rather than edited: a device that
    // rendered yesterday's screen still has to be able to explain it.
    final List<SettingsProfile> existing = await _repository
        .listSettingsProfiles(profile.tenantId, status: 'active');
    for (final SettingsProfile other in existing) {
      if (other.id != profile.id && other.facilityId == profile.facilityId) {
        await _repository.updateSettingsProfile(
          other.id,
          settingsProfileSupersedeChanges(at: at),
        );
      }
    }
    await _repository.updateSettingsProfile(
      profile.id,
      settingsProfileActivateChanges(activatedBy: activatedBy, at: at),
    );
  }
}

/// Registers a branding asset, awaiting publication.
final class DraftBrandingAssetUseCase {
  /// Creates the use case.
  DraftBrandingAssetUseCase({required this._repository});

  final SettingsRepository _repository;

  Future<String> call({
    required AuthorizationPolicy policy,
    required SecondFactorAssertion? secondFactor,
    required String tenantId,
    required BrandingAssetKind kind,
    required String label,
    required String primaryColor,
    required String secondaryColor,
    required String createdBy,
    String? facilityId,
    String? storagePath,
    String? checksum,
    String? mimeType,
    int? byteSize,
    DateTime? at,
    String assetId = '',
  }) async {
    policy.require(NodexPermissions.settingsConfigure);
    _requireAdministrator(policy);
    final DateTime now = (at ?? DateTime.now()).toUtc();
    _requireSecondFactor(
      policy: policy,
      secondFactor: secondFactor,
      tenantId: tenantId,
      userId: createdBy,
      now: now,
      purpose: settingsPurposeBranding,
    );
    return _repository.registerBrandingAsset(
      BrandingAsset.registerRow(
        tenantId: tenantId,
        kind: kind,
        label: label,
        primaryColor: primaryColor,
        secondaryColor: secondaryColor,
        createdBy: createdBy,
        facilityId: facilityId,
        storagePath: storagePath,
        checksum: checksum,
        mimeType: mimeType,
        byteSize: byteSize,
        assetId: assetId,
      ),
    );
  }
}

/// Publishes a branding asset, superseding the one it replaces.
final class PublishBrandingAssetUseCase {
  /// Creates the use case.
  PublishBrandingAssetUseCase({required this._repository});

  final SettingsRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required SecondFactorAssertion? secondFactor,
    required BrandingAsset asset,
    required String activatedBy,
    DateTime? at,
  }) async {
    policy.require(NodexPermissions.settingsConfigure);
    _requireAdministrator(policy);
    final DateTime now = (at ?? DateTime.now()).toUtc();
    _requireSecondFactor(
      policy: policy,
      secondFactor: secondFactor,
      tenantId: asset.tenantId,
      userId: activatedBy,
      now: now,
      purpose: settingsPurposeBranding,
    );
    if (!brandingAssetCanTransition(asset.status, BrandingAssetStatus.active)) {
      throw AuthorizationError(
        message: asset.status.isTerminal
            ? 'That artwork has already been replaced.'
            : 'That artwork is already in use.',
        code: 'branding_asset_transition_invalid',
      );
    }
    if (!asset.hasFile) {
      throw const ValidationError(
        message: 'Branding asset failed validation.',
        fieldErrors: <String, String>{
          'storage_path': 'Upload the file before putting it into use.',
        },
        code: 'branding_asset_file_missing',
      );
    }
    final List<BrandingAsset> existing = await _repository.listBrandingAssets(
      asset.tenantId,
      assetKind: asset.kind.wireValue,
      status: 'active',
    );
    for (final BrandingAsset other in existing) {
      if (other.id != asset.id && other.facilityId == asset.facilityId) {
        await _repository.updateBrandingAsset(
          other.id,
          brandingSupersedeChanges(at: at),
        );
      }
    }
    await _repository.updateBrandingAsset(
      asset.id,
      brandingActivateChanges(activatedBy: activatedBy, at: at),
    );
  }
}

/// Adds a department to the tree.
final class DefineDepartmentUseCase {
  /// Creates the use case.
  DefineDepartmentUseCase({required this._repository});

  final SettingsRepository _repository;

  Future<String> call({
    required AuthorizationPolicy policy,
    required SecondFactorAssertion? secondFactor,
    required String tenantId,
    required String code,
    required String name,
    required String createdBy,
    DepartmentKind kind = DepartmentKind.clinical,
    String? parentId,
    String? facilityId,
    String? costCentre,
    bool isBillable = false,
    int sortOrder = 0,
    DateTime? at,
    String departmentId = '',
  }) async {
    policy.require(NodexPermissions.settingsConfigure);
    _requireAdministrator(policy);
    final DateTime now = (at ?? DateTime.now()).toUtc();
    _requireSecondFactor(
      policy: policy,
      secondFactor: secondFactor,
      tenantId: tenantId,
      userId: createdBy,
      now: now,
      purpose: settingsPurposeConfigure,
    );
    final List<DepartmentNode> departments = await _repository.listDepartments(
      tenantId,
    );
    for (final DepartmentNode other in departments) {
      if (other.code == code.trim().toUpperCase() && other.id != departmentId) {
        throw const ValidationError(
          message: 'Department failed validation.',
          fieldErrors: <String, String>{
            'code': 'That department code is already in use.',
          },
          code: 'department_code_duplicate',
        );
      }
    }
    if (parentId != null) {
      final DepartmentNode? parent = departmentById(departments, parentId);
      if (parent == null) {
        throw const ValidationError(
          message: 'Department failed validation.',
          fieldErrors: <String, String>{
            'parent_id': 'That parent department is not on this device.',
          },
          code: 'department_parent_missing',
        );
      }
      if (parent.isTerminal) {
        throw const ValidationError(
          message: 'Department failed validation.',
          fieldErrors: <String, String>{
            'parent_id': 'An archived department cannot take a new branch.',
          },
          code: 'department_parent_archived',
        );
      }
    }
    return _repository.registerDepartment(
      DepartmentNode.registerRow(
        tenantId: tenantId,
        code: code,
        name: name,
        createdBy: createdBy,
        kind: kind,
        parentId: parentId,
        facilityId: facilityId,
        costCentre: costCentre,
        isBillable: isBillable,
        sortOrder: sortOrder,
        departmentId: departmentId,
      ),
    );
  }
}

/// Closes a department, with the reason kept.
final class CloseDepartmentUseCase {
  /// Creates the use case.
  CloseDepartmentUseCase({required this._repository});

  final SettingsRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required SecondFactorAssertion? secondFactor,
    required DepartmentNode department,
    required String reason,
    required String userId,
    List<DepartmentNode>? tree,
    DateTime? at,
  }) async {
    policy.require(NodexPermissions.settingsConfigure);
    _requireAdministrator(policy);
    final DateTime now = (at ?? DateTime.now()).toUtc();
    _requireSecondFactor(
      policy: policy,
      secondFactor: secondFactor,
      tenantId: department.tenantId,
      userId: userId,
      now: now,
      purpose: settingsPurposeConfigure,
    );
    if (!departmentCanTransition(
      department.status,
      DepartmentStatus.archived,
    )) {
      throw const AuthorizationError(
        message: 'That department is already closed.',
        code: 'department_transition_invalid',
      );
    }
    final List<DepartmentNode> departments =
        tree ?? await _repository.listDepartments(department.tenantId);
    if (!departmentIsArchivable(departments, department)) {
      throw const AuthorizationError(
        message: 'A department with live departments under it is not closed.',
        code: 'department_has_live_children',
      );
    }
    await _repository.updateDepartment(
      department.id,
      departmentArchiveChanges(reason: reason, at: at),
    );
  }
}

/// Prices a service into a draft tariff.
final class SetTariffUseCase {
  /// Creates the use case.
  SetTariffUseCase({required this._repository});

  final SettingsRepository _repository;

  Future<String> call({
    required AuthorizationPolicy policy,
    required SecondFactorAssertion? secondFactor,
    required String tenantId,
    required String code,
    required String serviceName,
    required DateTime effectiveFrom,
    required String createdBy,
    TariffCategory category = TariffCategory.consultation,
    int amountMinor = 0,
    int taxRateBps = 0,
    bool insuranceCapable = true,
    String currencyCode = 'INR',
    DateTime? effectiveTo,
    String? departmentId,
    String? facilityId,
    DateTime? at,
    String tariffId = '',
  }) async {
    policy.require(NodexPermissions.settingsTariff);
    _requireAdministrator(policy);
    final DateTime now = (at ?? DateTime.now()).toUtc();
    _requireSecondFactor(
      policy: policy,
      secondFactor: secondFactor,
      tenantId: tenantId,
      userId: createdBy,
      now: now,
      purpose: settingsPurposeTariff,
    );
    return _repository.registerTariff(
      BillingTariff.registerRow(
        tenantId: tenantId,
        code: code,
        serviceName: serviceName,
        effectiveFrom: effectiveFrom,
        createdBy: createdBy,
        category: category,
        amountMinor: amountMinor,
        taxRateBps: taxRateBps,
        insuranceCapable: insuranceCapable,
        currencyCode: currencyCode,
        effectiveTo: effectiveTo,
        departmentId: departmentId,
        facilityId: facilityId,
        tariffId: tariffId,
      ),
    );
  }
}

/// Approves a tariff into life.
final class ApproveTariffUseCase {
  /// Creates the use case.
  ApproveTariffUseCase({required this._repository});

  final SettingsRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required SecondFactorAssertion? secondFactor,
    required BillingTariff tariff,
    required String approvedBy,
    DateTime? at,
  }) async {
    policy.require(NodexPermissions.settingsTariff);
    _requireAdministrator(policy);
    final DateTime now = (at ?? DateTime.now()).toUtc();
    _requireSecondFactor(
      policy: policy,
      secondFactor: secondFactor,
      tenantId: tariff.tenantId,
      userId: approvedBy,
      now: now,
      purpose: settingsPurposeTariff,
    );
    if (!tariffCanTransition(tariff.status, TariffStatus.active)) {
      throw AuthorizationError(
        message: tariff.status.isTerminal
            ? 'That tariff has been retired.'
            : 'That tariff is already in force.',
        code: 'billing_tariff_transition_invalid',
      );
    }
    // Two live tariffs for one code are two answers to what a service costs, and
    // an invoice that has two answers is a dispute.
    final List<BillingTariff> live = await _repository.listTariffs(
      tariff.tenantId,
      code: tariff.code,
      status: 'active',
    );
    for (final BillingTariff other in live) {
      if (other.id != tariff.id && tariffOverlaps(other, tariff)) {
        throw const ValidationError(
          message: 'Billing tariff failed validation.',
          fieldErrors: <String, String>{
            'effective_from':
                'That window overlaps a live tariff for the code.',
          },
          code: 'billing_tariff_window_overlap',
        );
      }
    }
    await _repository.updateTariff(
      tariff.id,
      tariffApproveChanges(approvedBy: approvedBy, at: at),
    );
  }
}

/// Retires a tariff, with the reason kept.
final class RetireTariffUseCase {
  /// Creates the use case.
  RetireTariffUseCase({required this._repository});

  final SettingsRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required SecondFactorAssertion? secondFactor,
    required BillingTariff tariff,
    required String reason,
    required String userId,
    DateTime? at,
  }) async {
    policy.require(NodexPermissions.settingsTariff);
    _requireAdministrator(policy);
    final DateTime now = (at ?? DateTime.now()).toUtc();
    _requireSecondFactor(
      policy: policy,
      secondFactor: secondFactor,
      tenantId: tariff.tenantId,
      userId: userId,
      now: now,
      purpose: settingsPurposeTariff,
    );
    if (!tariffCanTransition(tariff.status, TariffStatus.retired)) {
      throw AuthorizationError(
        message: tariff.status.isTerminal
            ? 'That tariff is already retired.'
            : 'A draft tariff is discarded, not retired.',
        code: 'billing_tariff_transition_invalid',
      );
    }
    await _repository.updateTariff(
      tariff.id,
      tariffRetireChanges(reason: reason, at: at),
    );
  }
}

/// Proposes a routing profile.
final class DefineRoutingProfileUseCase {
  /// Creates the use case.
  DefineRoutingProfileUseCase({required this._repository});

  final SettingsRepository _repository;

  Future<String> call({
    required AuthorizationPolicy policy,
    required SecondFactorAssertion? secondFactor,
    required String tenantId,
    required String profileCode,
    required String displayName,
    required String primaryModelKey,
    required String createdBy,
    AiTaskKind taskKind = AiTaskKind.scribe,
    String? fallbackModelKey,
    int temperatureBps = 2000,
    int maxOutputTokens = 1024,
    AiDataResidency dataResidency = AiDataResidency.inCountry,
    bool redactPhi = true,
    String? facilityId,
    DateTime? at,
    String profileId = '',
  }) async {
    policy.require(NodexPermissions.aiConfigure);
    _requireAdministrator(policy);
    final DateTime now = (at ?? DateTime.now()).toUtc();
    _requireSecondFactor(
      policy: policy,
      secondFactor: secondFactor,
      tenantId: tenantId,
      userId: createdBy,
      now: now,
      purpose: settingsPurposeAiRouting,
    );
    final List<AiRoutingProfile> existing = await _repository
        .listRoutingProfiles(tenantId);
    for (final AiRoutingProfile other in existing) {
      if (other.profileCode == profileCode.trim().toLowerCase() &&
          other.id != profileId) {
        throw const ValidationError(
          message: 'AI routing profile failed validation.',
          fieldErrors: <String, String>{
            'profile_code': 'That profile code is already in use.',
          },
          code: 'ai_routing_profile_code_duplicate',
        );
      }
    }
    return _repository.registerRoutingProfile(
      AiRoutingProfile.registerRow(
        tenantId: tenantId,
        profileCode: profileCode,
        displayName: displayName,
        primaryModelKey: primaryModelKey,
        createdBy: createdBy,
        taskKind: taskKind,
        fallbackModelKey: fallbackModelKey,
        temperatureBps: temperatureBps,
        maxOutputTokens: maxOutputTokens,
        dataResidency: dataResidency,
        redactPhi: redactPhi,
        facilityId: facilityId,
        profileId: profileId,
      ),
    );
  }
}

/// Puts a routing profile to work, superseding the one it replaces.
final class ActivateRoutingProfileUseCase {
  /// Creates the use case.
  ActivateRoutingProfileUseCase({required this._repository});

  final SettingsRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required SecondFactorAssertion? secondFactor,
    required AiRoutingProfile profile,
    required String activatedBy,
    DateTime? at,
  }) async {
    policy.require(NodexPermissions.aiConfigure);
    _requireAdministrator(policy);
    final DateTime now = (at ?? DateTime.now()).toUtc();
    _requireSecondFactor(
      policy: policy,
      secondFactor: secondFactor,
      tenantId: profile.tenantId,
      userId: activatedBy,
      now: now,
      purpose: settingsPurposeAiRouting,
    );
    if (!routingProfileCanTransition(
      profile.status,
      RoutingProfileStatus.active,
    )) {
      throw AuthorizationError(
        message: profile.status.isTerminal
            ? 'That profile has been retired.'
            : 'That profile is already routing.',
        code: 'ai_routing_profile_transition_invalid',
      );
    }
    final List<AiRoutingProfile> existing = await _repository
        .listRoutingProfiles(profile.tenantId, status: 'active');
    for (final AiRoutingProfile other in existing) {
      if (other.id != profile.id && other.taskKind == profile.taskKind) {
        await _repository.updateRoutingProfile(
          other.id,
          routingRetireChanges(
            reason: 'Replaced by ${profile.profileCode}.',
            at: at,
          ),
        );
      }
    }
    await _repository.updateRoutingProfile(
      profile.id,
      routingActivateChanges(activatedBy: activatedBy, at: at),
    );
  }
}

/// Retires a routing profile, with the reason kept.
final class RetireRoutingProfileUseCase {
  /// Creates the use case.
  RetireRoutingProfileUseCase({required this._repository});

  final SettingsRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required SecondFactorAssertion? secondFactor,
    required AiRoutingProfile profile,
    required String reason,
    required String userId,
    DateTime? at,
  }) async {
    policy.require(NodexPermissions.aiConfigure);
    _requireAdministrator(policy);
    final DateTime now = (at ?? DateTime.now()).toUtc();
    _requireSecondFactor(
      policy: policy,
      secondFactor: secondFactor,
      tenantId: profile.tenantId,
      userId: userId,
      now: now,
      purpose: settingsPurposeAiRouting,
    );
    if (!routingProfileCanTransition(
      profile.status,
      RoutingProfileStatus.retired,
    )) {
      throw AuthorizationError(
        message: profile.status.isTerminal
            ? 'That profile is already retired.'
            : 'A draft profile is discarded, not retired.',
        code: 'ai_routing_profile_transition_invalid',
      );
    }
    await _repository.updateRoutingProfile(
      profile.id,
      routingRetireChanges(reason: reason, at: at),
    );
  }
}

/// The purpose a second factor is proved for, per kind of change.
const String settingsPurposeConfigure = 'settings.configure';
const String settingsPurposeBranding = 'settings.branding';
const String settingsPurposeTariff = 'settings.tariff';
const String settingsPurposeAiRouting = 'ai.routing';

/// The master settings hub as one screen's worth of state.
@immutable
final class MasterSettingsBoard {
  /// Creates the board.
  const MasterSettingsBoard({
    required this.asOf,
    required this.profiles,
    required this.assets,
    required this.departments,
    required this.tariffs,
    required this.routingProfiles,
  });

  /// The moment the board was read.
  final DateTime asOf;

  /// Settings profiles, newest version first.
  final List<SettingsProfile> profiles;

  /// Branding assets, by kind then label.
  final List<BrandingAsset> assets;

  /// The department tree, by sort order then code.
  final List<DepartmentNode> departments;

  /// Tariffs, newest window first.
  final List<BillingTariff> tariffs;

  /// Routing profiles, by code.
  final List<AiRoutingProfile> routingProfiles;

  /// The configuration in force for [facilityId], or null.
  SettingsProfile? configurationFor({String? facilityId}) =>
      activeSettingsProfile(profiles, facilityId: facilityId);

  /// The branding asset in use for [kind], or null.
  BrandingAsset? brandingFor({
    required BrandingAssetKind kind,
    String? facilityId,
  }) => activeBrandingAsset(assets, kind: kind, facilityId: facilityId);

  /// The profile routing [taskKind], or null.
  AiRoutingProfile? routingFor({
    required AiTaskKind taskKind,
    String? facilityId,
  }) => activeRoutingProfile(
    routingProfiles,
    taskKind: taskKind,
    facilityId: facilityId,
  );

  /// The versions held for [facilityId], newest first.
  List<SettingsProfile> historyFor({String? facilityId}) => <SettingsProfile>[
    for (final SettingsProfile profile in profiles)
      if (profile.facilityId == facilityId) profile,
  ];

  /// The departments that are still part of the tree.
  List<DepartmentNode> get activeDepartments => <DepartmentNode>[
    for (final DepartmentNode department in departments)
      if (department.isActive) department,
  ];

  /// The roots of the tree.
  List<DepartmentNode> get roots => <DepartmentNode>[
    for (final DepartmentNode department in departments)
      if (department.isRoot && department.isActive) department,
  ];

  /// The live departments directly under [id].
  List<DepartmentNode> childrenOf(String id) => <DepartmentNode>[
    for (final DepartmentNode department in departments)
      if (department.parentId == id && department.isActive) department,
  ];

  /// How deep a department sits, counting a root as zero.
  int levelOf(String id) => departmentLevel(departments, id);

  /// The codes from the root down to a department.
  String pathOf(String id) => departmentPath(departments, id);

  /// The departments with no cost centre to report against.
  List<DepartmentNode> get departmentsWithoutCostCentre => <DepartmentNode>[
    for (final DepartmentNode department in activeDepartments)
      if (!department.hasCostCentre) department,
  ];

  /// The tariffs waiting on an approver.
  List<BillingTariff> get tariffsAwaitingApproval => <BillingTariff>[
    for (final BillingTariff tariff in tariffs)
      if (tariff.status == TariffStatus.draft) tariff,
  ];

  /// The tariffs that may be billed from now.
  List<BillingTariff> get liveTariffs => <BillingTariff>[
    for (final BillingTariff tariff in tariffs)
      if (tariffIsLive(tariff, at: asOf)) tariff,
  ];

  /// The tariffs still in force that are to be billed from.
  BillingTariff? tariffFor(String code, {String? facilityId}) {
    for (final BillingTariff tariff in tariffs) {
      if (tariff.code != code) {
        continue;
      }
      if (facilityId != null &&
          tariff.facilityId != null &&
          tariff.facilityId != facilityId) {
        continue;
      }
      if (tariffIsLive(tariff, at: asOf)) {
        return tariff;
      }
    }
    return null;
  }

  /// The branding assets that hold colours but no file.
  List<BrandingAsset> get brandingPlaceholders => <BrandingAsset>[
    for (final BrandingAsset asset in assets)
      if (!asset.hasFile) asset,
  ];

  /// The live branding assets whose own two colours cannot be told apart.
  List<BrandingAsset> get unreadableBranding => <BrandingAsset>[
    for (final BrandingAsset asset in assets)
      if (asset.isActive && !brandingContrastIsReadable(asset)) asset,
  ];

  /// The routing profiles that are routing without a fallback.
  List<AiRoutingProfile> get routingProfilesWithoutFallback =>
      <AiRoutingProfile>[
        for (final AiRoutingProfile profile in routingProfiles)
          if (profile.isRouting && !profile.hasFallback) profile,
      ];

  /// The task kinds with nothing routing them.
  List<AiTaskKind> get unroutedTaskKinds => <AiTaskKind>[
    for (final AiTaskKind kind in AiTaskKind.values)
      if (routingFor(taskKind: kind) == null) kind,
  ];

  /// Whether anything on the board wants a decision.
  bool get needsAttention =>
      configurationFor() == null ||
      departmentsWithoutCostCentre.isNotEmpty ||
      tariffsAwaitingApproval.isNotEmpty ||
      routingProfilesWithoutFallback.isNotEmpty ||
      unreadableBranding.isNotEmpty;
}

/// Reads the master settings hub and its derived markers.
final class ReadMasterSettingsUseCase {
  /// Creates the use case.
  ReadMasterSettingsUseCase({required this._repository});

  final SettingsRepository _repository;

  Future<MasterSettingsBoard> board({
    required AuthorizationPolicy policy,
    required String tenantId,
    DateTime? now,
  }) async {
    policy.require(NodexPermissions.settingsRead);
    return MasterSettingsBoard(
      asOf: (now ?? DateTime.now()).toUtc(),
      profiles: await profilesOf(policy: policy, tenantId: tenantId),
      assets: await assetsOf(policy: policy, tenantId: tenantId),
      departments: await departmentsOf(policy: policy, tenantId: tenantId),
      tariffs: await tariffsOf(policy: policy, tenantId: tenantId),
      routingProfiles: await routingProfilesOf(
        policy: policy,
        tenantId: tenantId,
      ),
    );
  }

  /// The settings profiles, newest version first.
  Future<List<SettingsProfile>> profilesOf({
    required AuthorizationPolicy policy,
    required String tenantId,
    String? status,
    String? facilityId,
  }) async {
    policy.require(NodexPermissions.settingsRead);
    final List<SettingsProfile> profiles = await _repository
        .listSettingsProfiles(tenantId, status: status, facilityId: facilityId);
    return <SettingsProfile>[...profiles]..sort(
      (SettingsProfile a, SettingsProfile b) => b.version.compareTo(a.version),
    );
  }

  /// The branding assets, by kind then label.
  Future<List<BrandingAsset>> assetsOf({
    required AuthorizationPolicy policy,
    required String tenantId,
    String? assetKind,
    String? status,
  }) async {
    policy.require(NodexPermissions.settingsRead);
    final List<BrandingAsset> assets = await _repository.listBrandingAssets(
      tenantId,
      assetKind: assetKind,
      status: status,
    );
    return <BrandingAsset>[...assets]..sort((BrandingAsset a, BrandingAsset b) {
      final int byKind = a.kind.wireValue.compareTo(b.kind.wireValue);
      return byKind != 0 ? byKind : a.label.compareTo(b.label);
    });
  }

  /// The department tree, by sort order then code.
  Future<List<DepartmentNode>> departmentsOf({
    required AuthorizationPolicy policy,
    required String tenantId,
    String? status,
    String? kind,
  }) async {
    policy.require(NodexPermissions.settingsRead);
    final List<DepartmentNode> departments = await _repository.listDepartments(
      tenantId,
      status: status,
      kind: kind,
    );
    return <DepartmentNode>[...departments]
      ..sort((DepartmentNode a, DepartmentNode b) {
        final int byOrder = a.sortOrder.compareTo(b.sortOrder);
        return byOrder != 0 ? byOrder : a.code.compareTo(b.code);
      });
  }

  /// The tariffs, newest window first.
  Future<List<BillingTariff>> tariffsOf({
    required AuthorizationPolicy policy,
    required String tenantId,
    String? code,
    String? departmentId,
    String? status,
  }) async {
    policy.require(NodexPermissions.settingsRead);
    final List<BillingTariff> tariffs = await _repository.listTariffs(
      tenantId,
      code: code,
      departmentId: departmentId,
      status: status,
    );
    return <BillingTariff>[...tariffs]
      ..sort((BillingTariff a, BillingTariff b) {
        final int byFrom = b.effectiveFrom.compareTo(a.effectiveFrom);
        return byFrom != 0 ? byFrom : a.code.compareTo(b.code);
      });
  }

  /// The routing profiles, by code.
  Future<List<AiRoutingProfile>> routingProfilesOf({
    required AuthorizationPolicy policy,
    required String tenantId,
    String? taskKind,
    String? status,
  }) async {
    policy.require(NodexPermissions.settingsRead);
    final List<AiRoutingProfile> profiles = await _repository
        .listRoutingProfiles(tenantId, taskKind: taskKind, status: status);
    return <AiRoutingProfile>[...profiles]..sort(
      (AiRoutingProfile a, AiRoutingProfile b) =>
          a.profileCode.compareTo(b.profileCode),
    );
  }
}
