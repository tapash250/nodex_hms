/// Master Settings & AI Configuration Hub entities (Module 39).
///
/// Specification scope: "Hospital configuration, branding, department
/// hierarchies, billing tariff masters, and AI routing profiles." with the
/// security clause "Restricted to Super-Admins. Changes require Multi-Factor
/// Authentication (2FA) and active online connectivity."
///
/// Everything here is the hospital's description of itself, so everything here
/// is versioned rather than edited: a settings profile is superseded, a branding
/// asset is superseded, a department is archived, a tariff is retired, and a
/// routing profile is retired. A past bill, a past letterhead and a past figure
/// resolve to the configuration they were produced under.
///
/// The facts a stored copy would let drift are derived instead. How deep a
/// department sits and what it sits under are [departmentLevel] and
/// [departmentAncestors], walked from the tree rather than written down twice,
/// because a stored level goes stale the first time a branch is re-parented.
/// Tax is [tariffTaxMinor] in integer basis points so a line item is exactly
/// reproducible, a tariff is live only while its own window says so
/// ([tariffIsLive]), and whether a routing profile may be used at all is
/// [AiRoutingProfile.isUsable] against its own residency and redaction rather
/// than a reviewer's memory. The two colours a theme needs are checked for
/// readability by [brandingContrastRatio], because a logo that cannot be read is
/// not branding.
// ignore_for_file: sort_constructors_first
library;

import 'dart:math';

import 'package:meta/meta.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';

/// Lifecycle status of a settings profile.
enum SettingsProfileStatus {
  /// Being written.
  draft('draft'),

  /// The configuration in force.
  active('active'),

  /// Replaced by a later version; kept so a past screen still resolves.
  superseded('superseded');

  const SettingsProfileStatus(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    SettingsProfileStatus.draft => 'Draft',
    SettingsProfileStatus.active => 'In force',
    SettingsProfileStatus.superseded => 'Superseded',
  };

  /// Parses a stored value.
  static SettingsProfileStatus fromWire(String value) =>
      SettingsProfileStatus.values.firstWhere(
        (SettingsProfileStatus value_) => value_.wireValue == value,
        orElse: () => SettingsProfileStatus.draft,
      );

  /// Whether the profile is the configuration in force.
  bool get isActive => this == SettingsProfileStatus.active;

  /// Whether the profile is settled.
  bool get isTerminal => this == SettingsProfileStatus.superseded;
}

/// Whether a settings profile may move from [from] to [to].
bool settingsProfileCanTransition(
  SettingsProfileStatus from,
  SettingsProfileStatus to,
) {
  if (from.isTerminal) {
    return false;
  }
  return switch (from) {
    SettingsProfileStatus.draft => to == SettingsProfileStatus.active,
    SettingsProfileStatus.active => to == SettingsProfileStatus.superseded,
    SettingsProfileStatus.superseded => false,
  };
}

/// How a date is written, so every device writes it the same way.
enum DateFormatStyle {
  /// Day first.
  dayMonthYear('dd-mm-yyyy'),

  /// Month first.
  monthDayYear('mm-dd-yyyy'),

  /// Year first, which sorts as text.
  yearMonthDay('yyyy-mm-dd');

  const DateFormatStyle(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    DateFormatStyle.dayMonthYear => 'Day-month-year',
    DateFormatStyle.monthDayYear => 'Month-day-year',
    DateFormatStyle.yearMonthDay => 'Year-month-day',
  };

  /// Parses a stored value.
  static DateFormatStyle fromWire(String value) =>
      DateFormatStyle.values.firstWhere(
        (DateFormatStyle value_) => value_.wireValue == value,
        orElse: () => DateFormatStyle.dayMonthYear,
      );
}

/// Hospital configuration, versioned.
@immutable
final class SettingsProfile {
  /// Creates a settings profile.
  const SettingsProfile({
    required this.id,
    required this.tenantId,
    required this.version,
    required this.status,
    required this.hospitalName,
    required this.timezone,
    required this.defaultLocale,
    required this.dateFormat,
    required this.currencyCode,
    required this.currencyMinorUnits,
    required this.fiscalYearStartMonth,
    required this.appointmentSlotMinutes,
    required this.sessionIdleMinutes,
    required this.requireTwoFactor,
    required this.createdBy,
    required this.updatedAt,
    this.facilityId,
    this.activatedAt,
    this.activatedBy,
    this.supersededAt,
    this.createdAt,
  });

  /// Validates and builds a new draft profile row.
  static Map<String, Object?> registerRow({
    required String tenantId,
    required int version,
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
    String profileId = '',
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (version < 1) {
      fieldErrors['version'] = 'A version number is required.';
    }
    if (hospitalName.trim().isEmpty) {
      fieldErrors['hospital_name'] = 'The hospital name is required.';
    }
    if (timezone.trim().isEmpty) {
      fieldErrors['timezone'] = 'A timezone is required.';
    }
    if (defaultLocale.trim().isEmpty) {
      fieldErrors['default_locale'] = 'A default locale is required.';
    }
    if (!currencyPattern.hasMatch(currencyCode)) {
      fieldErrors['currency_code'] =
          'A three-letter currency code is required.';
    }
    if (currencyMinorUnits < 0 || currencyMinorUnits > 4) {
      fieldErrors['currency_minor_units'] = 'Between zero and four decimals.';
    }
    if (fiscalYearStartMonth < 1 || fiscalYearStartMonth > 12) {
      fieldErrors['fiscal_year_start_month'] = 'A month between 1 and 12.';
    }
    if (appointmentSlotMinutes < 5 || appointmentSlotMinutes > 120) {
      fieldErrors['appointment_slot_minutes'] = 'Between 5 and 120 minutes.';
    }
    if (sessionIdleMinutes < 1 || sessionIdleMinutes > 480) {
      fieldErrors['session_idle_minutes'] = 'Between 1 and 480 minutes.';
    }
    if (createdBy.isEmpty) {
      fieldErrors['created_by'] = 'Creator is required.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Settings profile failed validation.',
        fieldErrors: fieldErrors,
        code: 'settings_profile_invalid',
      );
    }
    final String stamp = DateTime.now().toUtc().toIso8601String();
    return <String, Object?>{
      if (profileId.isNotEmpty) 'id': profileId,
      'tenant_id': tenantId,
      'facility_id': _trimmed(facilityId),
      'version': version,
      'status': SettingsProfileStatus.draft.wireValue,
      'hospital_name': hospitalName.trim(),
      'timezone': timezone.trim(),
      'default_locale': defaultLocale.trim(),
      'date_format': dateFormat.wireValue,
      'currency_code': currencyCode,
      'currency_minor_units': currencyMinorUnits,
      'fiscal_year_start_month': fiscalYearStartMonth,
      'appointment_slot_minutes': appointmentSlotMinutes,
      'session_idle_minutes': sessionIdleMinutes,
      'require_two_factor': requireTwoFactor ? 1 : 0,
      'activated_at': null,
      'activated_by': null,
      'superseded_at': null,
      'created_by': createdBy,
      'created_at': stamp,
      'updated_at': stamp,
    };
  }

  /// Materializes a profile from a local row.
  factory SettingsProfile.fromRow(Map<String, Object?> row) => SettingsProfile(
    id: row['id']! as String,
    tenantId: row['tenant_id']! as String,
    version: _asInt(row['version']),
    status: SettingsProfileStatus.fromWire(
      (row['status'] as String?) ?? SettingsProfileStatus.draft.wireValue,
    ),
    hospitalName: row['hospital_name']! as String,
    timezone: (row['timezone'] as String?) ?? 'UTC',
    defaultLocale: (row['default_locale'] as String?) ?? 'en',
    dateFormat: DateFormatStyle.fromWire(
      (row['date_format'] as String?) ?? DateFormatStyle.dayMonthYear.wireValue,
    ),
    currencyCode: (row['currency_code'] as String?) ?? 'INR',
    currencyMinorUnits: _asInt(row['currency_minor_units']),
    fiscalYearStartMonth: _asInt(row['fiscal_year_start_month']),
    appointmentSlotMinutes: _asInt(row['appointment_slot_minutes']),
    sessionIdleMinutes: _asInt(row['session_idle_minutes']),
    requireTwoFactor: _asBool(row['require_two_factor']),
    createdBy: row['created_by']! as String,
    updatedAt: _parse(row['updated_at']),
    facilityId: row['facility_id'] as String?,
    activatedAt: _parseNullable(row['activated_at']),
    activatedBy: row['activated_by'] as String?,
    supersededAt: _parseNullable(row['superseded_at']),
    createdAt: _parseNullable(row['created_at']),
  );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// Version number, per tenant and facility.
  final int version;

  /// Lifecycle status.
  final SettingsProfileStatus status;

  /// What the hospital is called on its own paper.
  final String hospitalName;

  /// IANA timezone, which is the wall clock everything local is written against.
  final String timezone;

  /// BCP-47 language tag the device renders in.
  final String defaultLocale;

  /// How a date is written.
  final DateFormatStyle dateFormat;

  /// ISO 4217 code.
  final String currencyCode;

  /// How many decimals the currency is written in.
  final int currencyMinorUnits;

  /// The month the fiscal year opens, 1-12.
  final int fiscalYearStartMonth;

  /// How long an appointment slot is, in minutes.
  final int appointmentSlotMinutes;

  /// How long a session may sit idle before it locks, in minutes.
  final int sessionIdleMinutes;

  /// Whether this hospital demands a second factor for its own configuration.
  final bool requireTwoFactor;

  /// Who raised the profile.
  final String createdBy;

  /// Last change, UTC.
  final DateTime updatedAt;

  /// The facility it is scoped to, or null for hospital-wide.
  final String? facilityId;

  /// When it came into force, UTC.
  final DateTime? activatedAt;

  /// Who activated it.
  final String? activatedBy;

  /// When it was superseded, UTC.
  final DateTime? supersededAt;

  /// When the row was raised, UTC.
  final DateTime? createdAt;

  /// Whether the profile is hospital-wide rather than one facility's.
  bool get isHospitalWide => facilityId == null;

  /// Whether the profile is the configuration in force.
  bool get isActive => status.isActive;

  /// Whether the profile is still being written.
  bool get isDraft => status == SettingsProfileStatus.draft;

  /// Whether the profile is settled.
  bool get isTerminal => status.isTerminal;

  /// Renders [minorUnits] the way this hospital writes money.
  ///
  /// This is the whole point of holding the currency and its decimals in
  /// configuration: two screens cannot disagree about where the point goes.
  String formatMoney(int minorUnits) {
    final int places = currencyMinorUnits;
    if (places == 0) {
      return '$currencyCode $minorUnits';
    }
    final bool negative = minorUnits < 0;
    final int absolute = minorUnits.abs();
    final int divisor = _pow10(places);
    final String units = (absolute ~/ divisor).toString();
    final String fraction = (absolute % divisor).toString().padLeft(
      places,
      '0',
    );
    return '$currencyCode ${negative ? '-' : ''}$units.$fraction';
  }

  /// The first day of the fiscal year that [year] opens.
  DateTime fiscalYearStart(int year) =>
      DateTime.utc(year, fiscalYearStartMonth);

  /// The fiscal year [at] falls in.
  int fiscalYearOf(DateTime at) {
    final DateTime moment = at.toUtc();
    return moment.month >= fiscalYearStartMonth ? moment.year : moment.year - 1;
  }

  /// The slot [at] falls in, as a UTC instant, so two screens agree which
  /// appointment a click belongs to.
  DateTime slotStart(DateTime at) {
    final DateTime moment = at.toUtc();
    final int minutes =
        moment.minute - (moment.minute % appointmentSlotMinutes);
    return DateTime.utc(
      moment.year,
      moment.month,
      moment.day,
      moment.hour,
      minutes,
    );
  }
}

/// The change set that brings a settings profile into force.
Map<String, Object?> settingsProfileActivateChanges({
  required String activatedBy,
  DateTime? at,
}) {
  if (activatedBy.isEmpty) {
    throw const ValidationError(
      message: 'Settings profile failed validation.',
      fieldErrors: <String, String>{
        'activated_by': 'An activator is required.',
      },
      code: 'settings_profile_activator_missing',
    );
  }
  final String now = (at ?? DateTime.now()).toUtc().toIso8601String();
  return <String, Object?>{
    'status': SettingsProfileStatus.active.wireValue,
    'activated_at': now,
    'activated_by': activatedBy,
    'updated_at': now,
  };
}

/// The change set that supersedes a settings profile.
Map<String, Object?> settingsProfileSupersedeChanges({DateTime? at}) {
  final String now = (at ?? DateTime.now()).toUtc().toIso8601String();
  return <String, Object?>{
    'status': SettingsProfileStatus.superseded.wireValue,
    'superseded_at': now,
    'updated_at': now,
  };
}

/// The version a new profile for [facilityId] should carry.
///
/// Version numbers are the hospital's own history, so the next one follows the
/// highest held rather than counting activations: a discarded draft must not
/// leave the numbering claiming a version that was never written.
int nextSettingsVersion(
  Iterable<SettingsProfile> profiles, {
  String? facilityId,
}) {
  int highest = 0;
  for (final SettingsProfile profile in profiles) {
    if (profile.facilityId != facilityId) {
      continue;
    }
    if (profile.version > highest) {
      highest = profile.version;
    }
  }
  return highest + 1;
}

/// The configuration in force for [facilityId], or null.
///
/// A facility-scoped profile wins over the hospital-wide one, because a
/// department's own opening hours are the more specific truth.
SettingsProfile? activeSettingsProfile(
  Iterable<SettingsProfile> profiles, {
  String? facilityId,
}) {
  SettingsProfile? hospitalWide;
  for (final SettingsProfile profile in profiles) {
    if (!profile.isActive) {
      continue;
    }
    if (profile.facilityId == facilityId) {
      return profile;
    }
    if (profile.facilityId == null) {
      hospitalWide = profile;
    }
  }
  return hospitalWide;
}

/// What kind of asset a branding file is.
enum BrandingAssetKind {
  /// The mark on the letterhead and the sign-in screen.
  logo('logo'),

  /// The full page furniture a document is printed on.
  letterhead('letterhead'),

  /// The mark in a browser tab.
  favicon('favicon'),

  /// A translucent mark behind a printed report.
  watermark('watermark');

  const BrandingAssetKind(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    BrandingAssetKind.logo => 'Logo',
    BrandingAssetKind.letterhead => 'Letterhead',
    BrandingAssetKind.favicon => 'Favicon',
    BrandingAssetKind.watermark => 'Watermark',
  };

  /// Parses a stored value.
  static BrandingAssetKind fromWire(String value) =>
      BrandingAssetKind.values.firstWhere(
        (BrandingAssetKind value_) => value_.wireValue == value,
        orElse: () => BrandingAssetKind.logo,
      );
}

/// Lifecycle status of a branding asset.
enum BrandingAssetStatus {
  /// Uploaded, not published.
  draft('draft'),

  /// The asset in use.
  active('active'),

  /// Replaced by a later asset of the same kind; kept so a reprint resolves.
  superseded('superseded');

  const BrandingAssetStatus(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    BrandingAssetStatus.draft => 'Draft',
    BrandingAssetStatus.active => 'In use',
    BrandingAssetStatus.superseded => 'Superseded',
  };

  /// Parses a stored value.
  static BrandingAssetStatus fromWire(String value) =>
      BrandingAssetStatus.values.firstWhere(
        (BrandingAssetStatus value_) => value_.wireValue == value,
        orElse: () => BrandingAssetStatus.draft,
      );

  /// Whether the asset is the one in use.
  bool get isActive => this == BrandingAssetStatus.active;

  /// Whether the asset is settled.
  bool get isTerminal => this == BrandingAssetStatus.superseded;
}

/// Whether a branding asset may move from [from] to [to].
bool brandingAssetCanTransition(
  BrandingAssetStatus from,
  BrandingAssetStatus to,
) {
  if (from.isTerminal) {
    return false;
  }
  return switch (from) {
    BrandingAssetStatus.draft => to == BrandingAssetStatus.active,
    BrandingAssetStatus.active => to == BrandingAssetStatus.superseded,
    BrandingAssetStatus.superseded => false,
  };
}

/// One branding asset.
@immutable
final class BrandingAsset {
  /// Creates a branding asset.
  const BrandingAsset({
    required this.id,
    required this.tenantId,
    required this.kind,
    required this.label,
    required this.primaryColor,
    required this.secondaryColor,
    required this.status,
    required this.createdBy,
    required this.updatedAt,
    this.facilityId,
    this.storagePath,
    this.checksum,
    this.mimeType,
    this.byteSize,
    this.activatedAt,
    this.activatedBy,
    this.supersededAt,
    this.createdAt,
  });

  /// Validates and builds a new draft branding row.
  static Map<String, Object?> registerRow({
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
    String assetId = '',
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (label.trim().isEmpty) {
      fieldErrors['label'] = 'A label is required.';
    }
    if (!colorPattern.hasMatch(primaryColor)) {
      fieldErrors['primary_color'] = 'A six-digit hex colour is required.';
    }
    if (!colorPattern.hasMatch(secondaryColor)) {
      fieldErrors['secondary_color'] = 'A six-digit hex colour is required.';
    }
    if (byteSize != null && byteSize < 0) {
      fieldErrors['byte_size'] = 'A size cannot be negative.';
    }
    if (createdBy.isEmpty) {
      fieldErrors['created_by'] = 'Creator is required.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Branding asset failed validation.',
        fieldErrors: fieldErrors,
        code: 'branding_asset_invalid',
      );
    }
    final String stamp = DateTime.now().toUtc().toIso8601String();
    return <String, Object?>{
      if (assetId.isNotEmpty) 'id': assetId,
      'tenant_id': tenantId,
      'facility_id': _trimmed(facilityId),
      'asset_kind': kind.wireValue,
      'label': label.trim(),
      'storage_path': _trimmed(storagePath),
      'checksum': _trimmed(checksum),
      'mime_type': _trimmed(mimeType),
      'byte_size': byteSize,
      'primary_color': primaryColor.toUpperCase(),
      'secondary_color': secondaryColor.toUpperCase(),
      'status': BrandingAssetStatus.draft.wireValue,
      'activated_at': null,
      'activated_by': null,
      'superseded_at': null,
      'created_by': createdBy,
      'created_at': stamp,
      'updated_at': stamp,
    };
  }

  /// Materializes an asset from a local row.
  factory BrandingAsset.fromRow(Map<String, Object?> row) => BrandingAsset(
    id: row['id']! as String,
    tenantId: row['tenant_id']! as String,
    kind: BrandingAssetKind.fromWire(
      (row['asset_kind'] as String?) ?? BrandingAssetKind.logo.wireValue,
    ),
    label: row['label']! as String,
    primaryColor: (row['primary_color'] as String?) ?? '#000000',
    secondaryColor: (row['secondary_color'] as String?) ?? '#FFFFFF',
    status: BrandingAssetStatus.fromWire(
      (row['status'] as String?) ?? BrandingAssetStatus.draft.wireValue,
    ),
    createdBy: row['created_by']! as String,
    updatedAt: _parse(row['updated_at']),
    facilityId: row['facility_id'] as String?,
    storagePath: row['storage_path'] as String?,
    checksum: row['checksum'] as String?,
    mimeType: row['mime_type'] as String?,
    byteSize: row['byte_size'] as int?,
    activatedAt: _parseNullable(row['activated_at']),
    activatedBy: row['activated_by'] as String?,
    supersededAt: _parseNullable(row['superseded_at']),
    createdAt: _parseNullable(row['created_at']),
  );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// What kind of asset it is.
  final BrandingAssetKind kind;

  /// The name of the proposal.
  final String label;

  /// The theme's primary colour, as `#RRGGBB`.
  final String primaryColor;

  /// The theme's secondary colour, as `#RRGGBB`.
  final String secondaryColor;

  /// Lifecycle status.
  final BrandingAssetStatus status;

  /// Who raised it.
  final String createdBy;

  /// Last change, UTC.
  final DateTime updatedAt;

  /// The facility it is scoped to, or null for hospital-wide.
  final String? facilityId;

  /// Where the uploaded file is stored.
  final String? storagePath;

  /// The digest of the uploaded file.
  final String? checksum;

  /// The media type of the uploaded file.
  final String? mimeType;

  /// The size of the uploaded file, in bytes.
  final int? byteSize;

  /// When it came into use, UTC.
  final DateTime? activatedAt;

  /// Who activated it.
  final String? activatedBy;

  /// When it was superseded, UTC.
  final DateTime? supersededAt;

  /// When the row was raised, UTC.
  final DateTime? createdAt;

  /// Whether the asset is hospital-wide rather than one facility's.
  bool get isHospitalWide => facilityId == null;

  /// Whether the asset is the one in use.
  bool get isActive => status.isActive;

  /// Whether the asset is settled.
  bool get isTerminal => status.isTerminal;

  /// Whether the asset is still being prepared.
  bool get isDraft => status == BrandingAssetStatus.draft;

  /// Whether a file has been uploaded for this asset.
  ///
  /// A colour pair without a file is a theme; a logo without a file is a
  /// placeholder, and the board says so.
  bool get hasFile => storagePath != null && checksum != null;

  /// How readable the primary colour is against the secondary.
  double get contrastRatio => brandingContrastRatio(this);
}

/// The change set that puts a branding asset into use.
Map<String, Object?> brandingActivateChanges({
  required String activatedBy,
  DateTime? at,
}) {
  if (activatedBy.isEmpty) {
    throw const ValidationError(
      message: 'Branding asset failed validation.',
      fieldErrors: <String, String>{
        'activated_by': 'An activator is required.',
      },
      code: 'branding_asset_activator_missing',
    );
  }
  final String now = (at ?? DateTime.now()).toUtc().toIso8601String();
  return <String, Object?>{
    'status': BrandingAssetStatus.active.wireValue,
    'activated_at': now,
    'activated_by': activatedBy,
    'updated_at': now,
  };
}

/// The change set that supersedes a branding asset.
Map<String, Object?> brandingSupersedeChanges({DateTime? at}) {
  final String now = (at ?? DateTime.now()).toUtc().toIso8601String();
  return <String, Object?>{
    'status': BrandingAssetStatus.superseded.wireValue,
    'superseded_at': now,
    'updated_at': now,
  };
}

/// The asset in use of [kind] for [facilityId], or null.
BrandingAsset? activeBrandingAsset(
  Iterable<BrandingAsset> assets, {
  required BrandingAssetKind kind,
  String? facilityId,
}) {
  BrandingAsset? hospitalWide;
  for (final BrandingAsset asset in assets) {
    if (asset.kind != kind || !asset.isActive) {
      continue;
    }
    if (asset.facilityId == facilityId) {
      return asset;
    }
    if (asset.facilityId == null) {
      hospitalWide = asset;
    }
  }
  return hospitalWide;
}

/// The contrast ratio between a branding asset's two colours.
///
/// WCAG relative luminance, because a theme whose own two colours cannot be told
/// apart is a theme somebody cannot read. A 4.5 ratio is the usual body-text
/// threshold; [brandingContrastIsReadable] applies it.
double brandingContrastRatio(BrandingAsset asset) {
  final double first = _relativeLuminance(asset.primaryColor);
  final double second = _relativeLuminance(asset.secondaryColor);
  final double lighter = first > second ? first : second;
  final double darker = first > second ? second : first;
  return (lighter + 0.05) / (darker + 0.05);
}

/// Whether the two colours are far enough apart to read text between them.
bool brandingContrastIsReadable(
  BrandingAsset asset, {
  double threshold = 4.5,
}) => asset.contrastRatio >= threshold;

/// What kind of department it is.
enum DepartmentKind {
  /// Sees patients.
  clinical('clinical'),

  /// Produces results: laboratory, radiology, pathology.
  diagnostic('diagnostic'),

  /// Treats patients: physiotherapy, dialysis.
  therapeutic('therapeutic'),

  /// Supports care without seeing patients.
  support('support'),

  /// Runs the hospital.
  administrative('administrative');

  const DepartmentKind(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    DepartmentKind.clinical => 'Clinical',
    DepartmentKind.diagnostic => 'Diagnostic',
    DepartmentKind.therapeutic => 'Therapeutic',
    DepartmentKind.support => 'Support',
    DepartmentKind.administrative => 'Administrative',
  };

  /// Parses a stored value.
  static DepartmentKind fromWire(String value) =>
      DepartmentKind.values.firstWhere(
        (DepartmentKind value_) => value_.wireValue == value,
        orElse: () => DepartmentKind.clinical,
      );
}

/// Lifecycle status of a department.
enum DepartmentStatus {
  /// Part of the current tree.
  active('active'),

  /// Closed, with the reason kept; terminal.
  archived('archived');

  const DepartmentStatus(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    DepartmentStatus.active => 'Active',
    DepartmentStatus.archived => 'Archived',
  };

  /// Parses a stored value.
  static DepartmentStatus fromWire(String value) =>
      DepartmentStatus.values.firstWhere(
        (DepartmentStatus value_) => value_.wireValue == value,
        orElse: () => DepartmentStatus.active,
      );

  /// Whether the department is settled.
  bool get isTerminal => this == DepartmentStatus.archived;
}

/// Whether a department may move from [from] to [to].
///
/// A department is opened and later archived; it is never reopened, because a
/// reopened code is a code whose past tariffs and past encounters have two
/// meanings.
bool departmentCanTransition(DepartmentStatus from, DepartmentStatus to) =>
    !from.isTerminal && to == DepartmentStatus.archived;

/// An entry in the departmental tree.
@immutable
final class DepartmentNode {
  /// Creates a department.
  const DepartmentNode({
    required this.id,
    required this.tenantId,
    required this.code,
    required this.name,
    required this.kind,
    required this.isBillable,
    required this.sortOrder,
    required this.status,
    required this.createdBy,
    required this.updatedAt,
    this.facilityId,
    this.parentId,
    this.costCentre,
    this.archivedAt,
    this.archiveReason,
    this.createdAt,
  });

  /// Validates and builds a new department row.
  static Map<String, Object?> registerRow({
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
    String departmentId = '',
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (code.trim().isEmpty) {
      fieldErrors['code'] = 'A department code is required.';
    }
    if (name.trim().isEmpty) {
      fieldErrors['name'] = 'A department name is required.';
    }
    if (sortOrder < 0) {
      fieldErrors['sort_order'] = 'A sort order cannot be negative.';
    }
    if (createdBy.isEmpty) {
      fieldErrors['created_by'] = 'Creator is required.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Department failed validation.',
        fieldErrors: fieldErrors,
        code: 'department_invalid',
      );
    }
    final String stamp = DateTime.now().toUtc().toIso8601String();
    return <String, Object?>{
      if (departmentId.isNotEmpty) 'id': departmentId,
      'tenant_id': tenantId,
      'facility_id': _trimmed(facilityId),
      'parent_id': _trimmed(parentId),
      'code': code.trim().toUpperCase(),
      'name': name.trim(),
      'kind': kind.wireValue,
      'cost_centre': _trimmed(costCentre),
      'is_billable': isBillable ? 1 : 0,
      'sort_order': sortOrder,
      'status': DepartmentStatus.active.wireValue,
      'archived_at': null,
      'archive_reason': null,
      'created_by': createdBy,
      'created_at': stamp,
      'updated_at': stamp,
    };
  }

  /// Materializes a department from a local row.
  factory DepartmentNode.fromRow(Map<String, Object?> row) => DepartmentNode(
    id: row['id']! as String,
    tenantId: row['tenant_id']! as String,
    code: row['code']! as String,
    name: row['name']! as String,
    kind: DepartmentKind.fromWire(
      (row['kind'] as String?) ?? DepartmentKind.clinical.wireValue,
    ),
    isBillable: _asBool(row['is_billable']),
    sortOrder: _asInt(row['sort_order']),
    status: DepartmentStatus.fromWire(
      (row['status'] as String?) ?? DepartmentStatus.active.wireValue,
    ),
    createdBy: row['created_by']! as String,
    updatedAt: _parse(row['updated_at']),
    facilityId: row['facility_id'] as String?,
    parentId: row['parent_id'] as String?,
    costCentre: row['cost_centre'] as String?,
    archivedAt: _parseNullable(row['archived_at']),
    archiveReason: row['archive_reason'] as String?,
    createdAt: _parseNullable(row['created_at']),
  );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// The code the rest of the hospital names it by.
  final String code;

  /// Display name.
  final String name;

  /// What kind of department it is.
  final DepartmentKind kind;

  /// Whether its work is billed.
  final bool isBillable;

  /// Where it sits among its siblings.
  final int sortOrder;

  /// Lifecycle status.
  final DepartmentStatus status;

  /// Who raised it.
  final String createdBy;

  /// Last change, UTC.
  final DateTime updatedAt;

  /// The facility it is scoped to, or null for hospital-wide.
  final String? facilityId;

  /// The department it sits under, or null when it is a root.
  final String? parentId;

  /// The cost centre its revenue lands in.
  final String? costCentre;

  /// When it was archived, UTC.
  final DateTime? archivedAt;

  /// Why it was archived.
  final String? archiveReason;

  /// When the row was raised, UTC.
  final DateTime? createdAt;

  /// Whether the department is a root of the tree.
  bool get isRoot => parentId == null;

  /// Whether the department is still part of the current tree.
  bool get isActive => status != DepartmentStatus.archived;

  /// Whether the department is settled.
  bool get isTerminal => status.isTerminal;

  /// Whether the department has a cost centre to report against.
  bool get hasCostCentre => costCentre != null;
}

/// The change set that archives a department.
Map<String, Object?> departmentArchiveChanges({
  required String reason,
  DateTime? at,
}) {
  if (reason.trim().isEmpty) {
    throw const ValidationError(
      message: 'Department failed validation.',
      fieldErrors: <String, String>{'archive_reason': 'A reason is required.'},
      code: 'department_archive_reason_missing',
    );
  }
  final String now = (at ?? DateTime.now()).toUtc().toIso8601String();
  return <String, Object?>{
    'status': DepartmentStatus.archived.wireValue,
    'archived_at': now,
    'archive_reason': reason.trim(),
    'updated_at': now,
  };
}

/// The department with [id], or null.
DepartmentNode? departmentById(
  Iterable<DepartmentNode> departments,
  String id,
) {
  for (final DepartmentNode department in departments) {
    if (department.id == id) {
      return department;
    }
  }
  return null;
}

/// How deep a department sits, counting a root as zero.
///
/// Walked from the tree rather than read from a stored level, and guarded
/// against a broken chain so a corrupt row cannot hang a screen.
int departmentLevel(Iterable<DepartmentNode> departments, String id) {
  int level = 0;
  String? current = id;
  final Set<String> seen = <String>{};
  while (current != null && seen.add(current)) {
    final DepartmentNode? node = departmentById(departments, current);
    if (node == null || node.parentId == null) {
      break;
    }
    current = node.parentId;
    level++;
  }
  return level;
}

/// The departments above [id], nearest parent first.
List<DepartmentNode> departmentAncestors(
  Iterable<DepartmentNode> departments,
  String id,
) {
  final List<DepartmentNode> chain = <DepartmentNode>[];
  final Set<String> seen = <String>{id};
  String? current = departmentById(departments, id)?.parentId;
  while (current != null && seen.add(current)) {
    final DepartmentNode? node = departmentById(departments, current);
    if (node == null) {
      break;
    }
    chain.add(node);
    current = node.parentId;
  }
  return chain;
}

/// The departments below [id], breadth first.
List<DepartmentNode> departmentDescendants(
  Iterable<DepartmentNode> departments,
  String id,
) {
  final List<DepartmentNode> found = <DepartmentNode>[];
  final Set<String> seen = <String>{id};
  final List<String> frontier = <String>[id];
  while (frontier.isNotEmpty) {
    final String parent = frontier.removeAt(0);
    for (final DepartmentNode node in departments) {
      if (node.parentId == parent && seen.add(node.id)) {
        found.add(node);
        frontier.add(node.id);
      }
    }
  }
  return found;
}

/// Whether [candidate] sits anywhere under [id].
///
/// This is what refuses a re-parenting that would fold a branch into itself.
bool departmentIsDescendant({
  required Iterable<DepartmentNode> departments,
  required String id,
  required String candidate,
}) => departmentDescendants(
  departments,
  id,
).any((DepartmentNode node) => node.id == candidate);

/// The codes from the root down to [id], joined by a slash.
String departmentPath(Iterable<DepartmentNode> departments, String id) {
  final List<String> codes = <String>[
    for (final DepartmentNode node in departmentAncestors(
      departments,
      id,
    ).reversed)
      node.code,
    if (departmentById(departments, id)?.code case final String code) code,
  ];
  return codes.where((String code) => code.isNotEmpty).join('/');
}

/// Whether a department may be archived without orphaning its branch.
bool departmentIsArchivable(
  Iterable<DepartmentNode> departments,
  DepartmentNode department,
) =>
    department.isActive &&
    departmentDescendants(
      departments,
      department.id,
    ).every((DepartmentNode node) => node.isTerminal);

/// What kind of service a tariff prices.
enum TariffCategory {
  /// A clinician's time.
  consultation('consultation'),

  /// A procedure or operation.
  procedure('procedure'),

  /// A laboratory or imaging investigation.
  investigation('investigation'),

  /// A bed or a theatre slot.
  room('room'),

  /// Medicines.
  pharmacy('pharmacy'),

  /// Consumables used during care.
  consumable('consumable'),

  /// A priced bundle of the above.
  package('package');

  const TariffCategory(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    TariffCategory.consultation => 'Consultation',
    TariffCategory.procedure => 'Procedure',
    TariffCategory.investigation => 'Investigation',
    TariffCategory.room => 'Room',
    TariffCategory.pharmacy => 'Pharmacy',
    TariffCategory.consumable => 'Consumable',
    TariffCategory.package => 'Package',
  };

  /// Parses a stored value.
  static TariffCategory fromWire(String value) =>
      TariffCategory.values.firstWhere(
        (TariffCategory value_) => value_.wireValue == value,
        orElse: () => TariffCategory.consultation,
      );
}

/// Lifecycle status of a tariff.
enum TariffStatus {
  /// Priced, not approved.
  draft('draft'),

  /// Approved into life.
  active('active'),

  /// Withdrawn, with the reason kept; terminal.
  retired('retired');

  const TariffStatus(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    TariffStatus.draft => 'Draft',
    TariffStatus.active => 'In force',
    TariffStatus.retired => 'Retired',
  };

  /// Parses a stored value.
  static TariffStatus fromWire(String value) => TariffStatus.values.firstWhere(
    (TariffStatus value_) => value_.wireValue == value,
    orElse: () => TariffStatus.draft,
  );

  /// Whether the tariff may be billed from.
  bool get isLive => this == TariffStatus.active;

  /// Whether the tariff is settled.
  bool get isTerminal => this == TariffStatus.retired;
}

/// Whether a tariff may move from [from] to [to].
bool tariffCanTransition(TariffStatus from, TariffStatus to) {
  if (from.isTerminal) {
    return false;
  }
  return switch (from) {
    TariffStatus.draft => to == TariffStatus.active,
    TariffStatus.active => to == TariffStatus.retired,
    TariffStatus.retired => false,
  };
}

/// One tariff master entry.
@immutable
final class BillingTariff {
  /// Creates a tariff.
  const BillingTariff({
    required this.id,
    required this.tenantId,
    required this.code,
    required this.serviceName,
    required this.category,
    required this.currencyCode,
    required this.amountMinor,
    required this.taxRateBps,
    required this.insuranceCapable,
    required this.status,
    required this.effectiveFrom,
    required this.createdBy,
    required this.updatedAt,
    this.facilityId,
    this.departmentId,
    this.effectiveTo,
    this.approvedAt,
    this.approvedBy,
    this.retiredAt,
    this.retireReason,
    this.createdAt,
  });

  /// Validates and builds a new draft tariff row.
  static Map<String, Object?> registerRow({
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
    String tariffId = '',
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (code.trim().isEmpty) {
      fieldErrors['code'] = 'A tariff code is required.';
    }
    if (serviceName.trim().isEmpty) {
      fieldErrors['service_name'] = 'A service name is required.';
    }
    if (!currencyPattern.hasMatch(currencyCode)) {
      fieldErrors['currency_code'] =
          'A three-letter currency code is required.';
    }
    if (amountMinor < 0) {
      fieldErrors['amount_minor'] = 'An amount cannot be negative.';
    }
    if (taxRateBps < 0 || taxRateBps > 10000) {
      fieldErrors['tax_rate_bps'] =
          'A tax rate between 0 and 100% is required.';
    }
    if (createdBy.isEmpty) {
      fieldErrors['created_by'] = 'Creator is required.';
    }
    final DateTime from = _dateOnly(effectiveFrom);
    final DateTime? to = effectiveTo == null ? null : _dateOnly(effectiveTo);
    if (to != null && to.isBefore(from)) {
      fieldErrors['effective_to'] = 'The window must end after it starts.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Billing tariff failed validation.',
        fieldErrors: fieldErrors,
        code: 'billing_tariff_invalid',
      );
    }
    final String stamp = DateTime.now().toUtc().toIso8601String();
    return <String, Object?>{
      if (tariffId.isNotEmpty) 'id': tariffId,
      'tenant_id': tenantId,
      'facility_id': _trimmed(facilityId),
      'department_id': _trimmed(departmentId),
      'code': code.trim().toUpperCase(),
      'service_name': serviceName.trim(),
      'category': category.wireValue,
      'currency_code': currencyCode,
      'amount_minor': amountMinor,
      'tax_rate_bps': taxRateBps,
      'insurance_capable': insuranceCapable ? 1 : 0,
      'status': TariffStatus.draft.wireValue,
      'effective_from': _formatDate(from),
      'effective_to': to == null ? null : _formatDate(to),
      'approved_at': null,
      'approved_by': null,
      'retired_at': null,
      'retire_reason': null,
      'created_by': createdBy,
      'created_at': stamp,
      'updated_at': stamp,
    };
  }

  /// Materializes a tariff from a local row.
  factory BillingTariff.fromRow(Map<String, Object?> row) => BillingTariff(
    id: row['id']! as String,
    tenantId: row['tenant_id']! as String,
    code: row['code']! as String,
    serviceName: row['service_name']! as String,
    category: TariffCategory.fromWire(
      (row['category'] as String?) ?? TariffCategory.consultation.wireValue,
    ),
    currencyCode: (row['currency_code'] as String?) ?? 'INR',
    amountMinor: _asInt(row['amount_minor']),
    taxRateBps: _asInt(row['tax_rate_bps']),
    insuranceCapable: _asBool(row['insurance_capable']),
    status: TariffStatus.fromWire(
      (row['status'] as String?) ?? TariffStatus.draft.wireValue,
    ),
    effectiveFrom: _parseDate(row['effective_from']),
    createdBy: row['created_by']! as String,
    updatedAt: _parse(row['updated_at']),
    facilityId: row['facility_id'] as String?,
    departmentId: row['department_id'] as String?,
    effectiveTo: _parseNullableDate(row['effective_to']),
    approvedAt: _parseNullable(row['approved_at']),
    approvedBy: row['approved_by'] as String?,
    retiredAt: _parseNullable(row['retired_at']),
    retireReason: row['retire_reason'] as String?,
    createdAt: _parseNullable(row['created_at']),
  );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// The code an invoice line carries.
  final String code;

  /// What the service is called.
  final String serviceName;

  /// What kind of service it is.
  final TariffCategory category;

  /// ISO 4217 code.
  final String currencyCode;

  /// The pre-tax price, in minor units.
  final int amountMinor;

  /// The tax rate, in basis points.
  final int taxRateBps;

  /// Whether an insurer may be billed for it.
  final bool insuranceCapable;

  /// Lifecycle status.
  final TariffStatus status;

  /// The first day the tariff applies, UTC midnight.
  final DateTime effectiveFrom;

  /// Who raised it.
  final String createdBy;

  /// Last change, UTC.
  final DateTime updatedAt;

  /// The facility it is scoped to, or null for hospital-wide.
  final String? facilityId;

  /// The department that owns the service.
  final String? departmentId;

  /// The last day the tariff applies, UTC midnight, or null while open-ended.
  final DateTime? effectiveTo;

  /// When it was approved, UTC.
  final DateTime? approvedAt;

  /// Who approved it.
  final String? approvedBy;

  /// When it was retired, UTC.
  final DateTime? retiredAt;

  /// Why it was retired.
  final String? retireReason;

  /// When the row was raised, UTC.
  final DateTime? createdAt;

  /// Whether the tariff is approved.
  bool get isLive => status.isLive;

  /// Whether the tariff is settled and may not be billed from.
  bool get isTerminal => status.isTerminal;

  /// The tax on the amount, in minor units, rounded half up.
  int get taxMinor => tariffTaxMinor(this);

  /// The amount with tax, in minor units.
  int get grossMinor => tariffGrossMinor(this);

  /// The tax as a percentage, for display.
  double get taxRatePercent => taxRateBps / 100;
}

/// The tax on a tariff's amount, in minor units, rounded half up.
int tariffTaxMinor(BillingTariff tariff) =>
    (tariff.amountMinor * tariff.taxRateBps + 5000) ~/ 10000;

/// A tariff's amount with tax, in minor units.
int tariffGrossMinor(BillingTariff tariff) =>
    tariff.amountMinor + tariffTaxMinor(tariff);

/// Whether a tariff may be billed from at [at].
///
/// Live means approved *and* inside its own window: an approved tariff whose
/// last day has passed is history, and a screen that offered it would price a
/// bill from a rule that no longer applies.
bool tariffIsLive(BillingTariff tariff, {required DateTime at}) {
  if (!tariff.isLive) {
    return false;
  }
  final DateTime day = _dateOnly(at);
  if (day.isBefore(tariff.effectiveFrom)) {
    return false;
  }
  final DateTime? to = tariff.effectiveTo;
  return to == null || !day.isAfter(to);
}

/// Whether two tariffs of one code overlap in time.
///
/// Two live rules for one code are two answers to what a service costs, and an
/// invoice that has two answers is a dispute.
bool tariffOverlaps(BillingTariff first, BillingTariff second) {
  if (first.code != second.code) {
    return false;
  }
  final DateTime firstEnd = first.effectiveTo ?? DateTime.utc(9999, 12, 31);
  final DateTime secondEnd = second.effectiveTo ?? DateTime.utc(9999, 12, 31);
  return !first.effectiveFrom.isAfter(secondEnd) &&
      !second.effectiveFrom.isAfter(firstEnd);
}

/// The change set that approves a tariff into life.
Map<String, Object?> tariffApproveChanges({
  required String approvedBy,
  DateTime? at,
}) {
  if (approvedBy.isEmpty) {
    throw const ValidationError(
      message: 'Billing tariff failed validation.',
      fieldErrors: <String, String>{'approved_by': 'An approver is required.'},
      code: 'billing_tariff_approver_missing',
    );
  }
  final String now = (at ?? DateTime.now()).toUtc().toIso8601String();
  return <String, Object?>{
    'status': TariffStatus.active.wireValue,
    'approved_at': now,
    'approved_by': approvedBy,
    'updated_at': now,
  };
}

/// The change set that retires a tariff.
Map<String, Object?> tariffRetireChanges({
  required String reason,
  DateTime? at,
}) {
  if (reason.trim().isEmpty) {
    throw const ValidationError(
      message: 'Billing tariff failed validation.',
      fieldErrors: <String, String>{'retire_reason': 'A reason is required.'},
      code: 'billing_tariff_retire_reason_missing',
    );
  }
  final String now = (at ?? DateTime.now()).toUtc().toIso8601String();
  return <String, Object?>{
    'status': TariffStatus.retired.wireValue,
    'retired_at': now,
    'retire_reason': reason.trim(),
    'updated_at': now,
  };
}

/// What kind of question a routing profile answers.
enum AiTaskKind {
  /// Dictation turned into a note.
  scribe('scribe'),

  /// Diagnoses and procedures turned into codes.
  coding('coding'),

  /// A presenting complaint turned into an urgency.
  triage('triage'),

  /// A record turned into a summary.
  summarisation('summarisation'),

  /// Text turned into another language.
  translation('translation'),

  /// An image turned into a finding.
  imaging('imaging');

  const AiTaskKind(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    AiTaskKind.scribe => 'Ambient scribe',
    AiTaskKind.coding => 'Clinical coding',
    AiTaskKind.triage => 'Triage support',
    AiTaskKind.summarisation => 'Summarisation',
    AiTaskKind.translation => 'Translation',
    AiTaskKind.imaging => 'Imaging support',
  };

  /// Parses a stored value.
  static AiTaskKind fromWire(String value) => AiTaskKind.values.firstWhere(
    (AiTaskKind value_) => value_.wireValue == value,
    orElse: () => AiTaskKind.scribe,
  );
}

/// Where the model is allowed to run.
enum AiDataResidency {
  /// The hospital's own country.
  inCountry('in_country'),

  /// The hospital's region, across a border.
  regional('regional'),

  /// Anywhere the provider runs.
  global('global');

  const AiDataResidency(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    AiDataResidency.inCountry => 'In country',
    AiDataResidency.regional => 'In region',
    AiDataResidency.global => 'Global',
  };

  /// Parses a stored value.
  static AiDataResidency fromWire(String value) =>
      AiDataResidency.values.firstWhere(
        (AiDataResidency value_) => value_.wireValue == value,
        orElse: () => AiDataResidency.inCountry,
      );

  /// Whether the payload crosses a border.
  bool get crossesBorder => this != AiDataResidency.inCountry;
}

/// Lifecycle status of a routing profile.
enum RoutingProfileStatus {
  /// Proposed, not routing anything.
  draft('draft'),

  /// Answering its task kind.
  active('active'),

  /// Withdrawn, with the reason kept; terminal.
  retired('retired');

  const RoutingProfileStatus(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    RoutingProfileStatus.draft => 'Draft',
    RoutingProfileStatus.active => 'Routing',
    RoutingProfileStatus.retired => 'Retired',
  };

  /// Parses a stored value.
  static RoutingProfileStatus fromWire(String value) =>
      RoutingProfileStatus.values.firstWhere(
        (RoutingProfileStatus value_) => value_.wireValue == value,
        orElse: () => RoutingProfileStatus.draft,
      );

  /// Whether the profile is answering its task kind.
  bool get isRouting => this == RoutingProfileStatus.active;

  /// Whether the profile is settled.
  bool get isTerminal => this == RoutingProfileStatus.retired;
}

/// Whether a routing profile may move from [from] to [to].
bool routingProfileCanTransition(
  RoutingProfileStatus from,
  RoutingProfileStatus to,
) {
  if (from.isTerminal) {
    return false;
  }
  return switch (from) {
    RoutingProfileStatus.draft => to == RoutingProfileStatus.active,
    RoutingProfileStatus.active => to == RoutingProfileStatus.retired,
    RoutingProfileStatus.retired => false,
  };
}

/// One AI routing profile.
@immutable
final class AiRoutingProfile {
  /// Creates a routing profile.
  const AiRoutingProfile({
    required this.id,
    required this.tenantId,
    required this.profileCode,
    required this.displayName,
    required this.taskKind,
    required this.primaryModelKey,
    required this.temperatureBps,
    required this.maxOutputTokens,
    required this.dataResidency,
    required this.redactPhi,
    required this.status,
    required this.createdBy,
    required this.updatedAt,
    this.facilityId,
    this.fallbackModelKey,
    this.activatedAt,
    this.activatedBy,
    this.retiredAt,
    this.retireReason,
    this.createdAt,
  });

  /// Validates and builds a new draft routing profile row.
  static Map<String, Object?> registerRow({
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
    String profileId = '',
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (profileCode.trim().isEmpty) {
      fieldErrors['profile_code'] = 'A profile code is required.';
    }
    if (displayName.trim().isEmpty) {
      fieldErrors['display_name'] = 'A display name is required.';
    }
    if (primaryModelKey.trim().isEmpty) {
      fieldErrors['primary_model_key'] = 'A registered model is required.';
    }
    if (fallbackModelKey != null &&
        fallbackModelKey.trim() == primaryModelKey.trim()) {
      fieldErrors['fallback_model_key'] =
          'A fallback has to be a different model.';
    }
    if (temperatureBps < 0 || temperatureBps > 10000) {
      fieldErrors['temperature_bps'] = 'A temperature between 0 and 1.0.';
    }
    if (maxOutputTokens < 64 || maxOutputTokens > 32000) {
      fieldErrors['max_output_tokens'] = 'Between 64 and 32000 tokens.';
    }
    // A payload that may cross a border must be redacted first. Checked here as
    // well as in the database, so the client cannot send what the database will
    // refuse.
    if (dataResidency.crossesBorder && !redactPhi) {
      fieldErrors['redact_phi'] =
          'Data leaving the country has to be redacted first.';
    }
    if (createdBy.isEmpty) {
      fieldErrors['created_by'] = 'Creator is required.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'AI routing profile failed validation.',
        fieldErrors: fieldErrors,
        code: 'ai_routing_profile_invalid',
      );
    }
    final String stamp = DateTime.now().toUtc().toIso8601String();
    return <String, Object?>{
      if (profileId.isNotEmpty) 'id': profileId,
      'tenant_id': tenantId,
      'facility_id': _trimmed(facilityId),
      'profile_code': profileCode.trim().toLowerCase(),
      'display_name': displayName.trim(),
      'task_kind': taskKind.wireValue,
      'primary_model_key': primaryModelKey.trim(),
      'fallback_model_key': _trimmed(fallbackModelKey),
      'temperature_bps': temperatureBps,
      'max_output_tokens': maxOutputTokens,
      'data_residency': dataResidency.wireValue,
      'redact_phi': redactPhi ? 1 : 0,
      'status': RoutingProfileStatus.draft.wireValue,
      'activated_at': null,
      'activated_by': null,
      'retired_at': null,
      'retire_reason': null,
      'created_by': createdBy,
      'created_at': stamp,
      'updated_at': stamp,
    };
  }

  /// Materializes a profile from a local row.
  factory AiRoutingProfile.fromRow(Map<String, Object?> row) =>
      AiRoutingProfile(
        id: row['id']! as String,
        tenantId: row['tenant_id']! as String,
        profileCode: row['profile_code']! as String,
        displayName: row['display_name']! as String,
        taskKind: AiTaskKind.fromWire(
          (row['task_kind'] as String?) ?? AiTaskKind.scribe.wireValue,
        ),
        primaryModelKey: row['primary_model_key']! as String,
        temperatureBps: _asInt(row['temperature_bps']),
        maxOutputTokens: _asInt(row['max_output_tokens']),
        dataResidency: AiDataResidency.fromWire(
          (row['data_residency'] as String?) ??
              AiDataResidency.inCountry.wireValue,
        ),
        redactPhi: _asBool(row['redact_phi']),
        status: RoutingProfileStatus.fromWire(
          (row['status'] as String?) ?? RoutingProfileStatus.draft.wireValue,
        ),
        createdBy: row['created_by']! as String,
        updatedAt: _parse(row['updated_at']),
        facilityId: row['facility_id'] as String?,
        fallbackModelKey: row['fallback_model_key'] as String?,
        activatedAt: _parseNullable(row['activated_at']),
        activatedBy: row['activated_by'] as String?,
        retiredAt: _parseNullable(row['retired_at']),
        retireReason: row['retire_reason'] as String?,
        createdAt: _parseNullable(row['created_at']),
      );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// The code a route is named by.
  final String profileCode;

  /// Display name.
  final String displayName;

  /// The kind of question it answers.
  final AiTaskKind taskKind;

  /// The governance registry key of the model that answers first.
  final String primaryModelKey;

  /// The warmth of the sampler, in basis points.
  final int temperatureBps;

  /// The most the model may emit, in tokens.
  final int maxOutputTokens;

  /// Where the payload is allowed to run.
  final AiDataResidency dataResidency;

  /// Whether protected health information is stripped before the payload leaves.
  final bool redactPhi;

  /// Lifecycle status.
  final RoutingProfileStatus status;

  /// Who raised it.
  final String createdBy;

  /// Last change, UTC.
  final DateTime updatedAt;

  /// The facility it is scoped to, or null for hospital-wide.
  final String? facilityId;

  /// The governance registry key of the model that answers when the first fails.
  final String? fallbackModelKey;

  /// When it started routing, UTC.
  final DateTime? activatedAt;

  /// Who activated it.
  final String? activatedBy;

  /// When it was retired, UTC.
  final DateTime? retiredAt;

  /// Why it was retired.
  final String? retireReason;

  /// When the row was raised, UTC.
  final DateTime? createdAt;

  /// Whether the profile is answering its task kind.
  bool get isRouting => status.isRouting;

  /// Whether the profile is settled.
  bool get isTerminal => status.isTerminal;

  /// Whether the profile names a model to fall back to.
  bool get hasFallback => fallbackModelKey != null;

  /// The sampler warmth as a fraction, for display.
  double get temperature => temperatureBps / 10000;

  /// Whether the payload crosses a border already redacted.
  bool get leavesRedacted => dataResidency.crossesBorder && redactPhi;

  /// Whether the profile may be routed to.
  ///
  /// Routing means active *and* lawful: a profile whose data may cross a border
  /// without redaction is refused even if somebody activated it, because the
  /// patient's protection is not a setting.
  bool get isUsable => isRouting && (!dataResidency.crossesBorder || redactPhi);
}

/// The change set that puts a routing profile to work.
Map<String, Object?> routingActivateChanges({
  required String activatedBy,
  DateTime? at,
}) {
  if (activatedBy.isEmpty) {
    throw const ValidationError(
      message: 'AI routing profile failed validation.',
      fieldErrors: <String, String>{
        'activated_by': 'An activator is required.',
      },
      code: 'ai_routing_profile_activator_missing',
    );
  }
  final String now = (at ?? DateTime.now()).toUtc().toIso8601String();
  return <String, Object?>{
    'status': RoutingProfileStatus.active.wireValue,
    'activated_at': now,
    'activated_by': activatedBy,
    'updated_at': now,
  };
}

/// The change set that retires a routing profile.
Map<String, Object?> routingRetireChanges({
  required String reason,
  DateTime? at,
}) {
  if (reason.trim().isEmpty) {
    throw const ValidationError(
      message: 'AI routing profile failed validation.',
      fieldErrors: <String, String>{'retire_reason': 'A reason is required.'},
      code: 'ai_routing_profile_retire_reason_missing',
    );
  }
  final String now = (at ?? DateTime.now()).toUtc().toIso8601String();
  return <String, Object?>{
    'status': RoutingProfileStatus.retired.wireValue,
    'retired_at': now,
    'retire_reason': reason.trim(),
    'updated_at': now,
  };
}

/// The profile routing [taskKind] for [facilityId], or null.
AiRoutingProfile? activeRoutingProfile(
  Iterable<AiRoutingProfile> profiles, {
  required AiTaskKind taskKind,
  String? facilityId,
}) {
  AiRoutingProfile? hospitalWide;
  for (final AiRoutingProfile profile in profiles) {
    if (profile.taskKind != taskKind || !profile.isUsable) {
      continue;
    }
    if (profile.facilityId == facilityId) {
      return profile;
    }
    if (profile.facilityId == null) {
      hospitalWide = profile;
    }
  }
  return hospitalWide;
}

/// A pattern a currency code has to match.
final RegExp currencyPattern = RegExp(r'^[A-Z]{3}$');

/// A pattern a `#RRGGBB` colour has to match.
final RegExp colorPattern = RegExp(r'^#[0-9A-Fa-f]{6}$');

String? _trimmed(String? value) {
  if (value == null) {
    return null;
  }
  final String trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

DateTime _dateOnly(DateTime value) =>
    DateTime.utc(value.toUtc().year, value.toUtc().month, value.toUtc().day);

String _formatDate(DateTime value) {
  final DateTime utc = value.toUtc();
  return '${utc.year.toString().padLeft(4, '0')}-'
      '${utc.month.toString().padLeft(2, '0')}-'
      '${utc.day.toString().padLeft(2, '0')}';
}

/// Parses a date-only column into UTC midnight.
///
/// The parts are read directly rather than through `DateTime.parse`, because a
/// date-only string parses as local midnight and a device west of UTC would then
/// read a tariff as starting the day before it does.
DateTime _parseDate(Object? value) {
  if (value is String) {
    final List<String> parts = value.split('-');
    if (parts.length == 3) {
      final int? year = int.tryParse(parts[0]);
      final int? month = int.tryParse(parts[1]);
      final int? day = int.tryParse(parts[2]);
      if (year != null && month != null && day != null) {
        return DateTime.utc(year, month, day);
      }
    }
  }
  return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}

DateTime? _parseNullableDate(Object? value) =>
    value is String && value.trim().isNotEmpty ? _parseDate(value) : null;

DateTime _parse(Object? value) => value is String
    ? DateTime.parse(value).toUtc()
    : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

DateTime? _parseNullable(Object? value) =>
    value is String ? DateTime.parse(value).toUtc() : null;

int _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.parse(value);
  }
  return 0;
}

/// Reads a boolean stored as an integer, with the text forms older rows use.
bool _asBool(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  if (value is String) {
    final String text = value.trim().toLowerCase();
    return text == 'true' || text == 't' || text == '1';
  }
  return false;
}

int _pow10(int exponent) {
  int value = 1;
  for (int index = 0; index < exponent; index++) {
    value *= 10;
  }
  return value;
}

double _relativeLuminance(String color) {
  final double red = _channel(color, 1);
  final double green = _channel(color, 3);
  final double blue = _channel(color, 5);
  return 0.2126 * red + 0.7152 * green + 0.0722 * blue;
}

double _channel(String color, int offset) {
  if (color.length < offset + 2) {
    return 0;
  }
  final int? value = int.tryParse(
    color.substring(offset, offset + 2),
    radix: 16,
  );
  if (value == null) {
    return 0;
  }
  final double ratio = value / 255;
  return ratio <= 0.03928
      ? ratio / 12.92
      : pow((ratio + 0.055) / 1.055, 2.4).toDouble();
}
