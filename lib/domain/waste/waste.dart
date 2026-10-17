/// Biomedical waste management entities (Module 30).
///
/// Specification scope: "Waste categories, generation logs, barcoded disposal
/// certificates, compliance."
///
/// This is the regulated waste estate: what the hospital discards, where it came
/// from, and the certificate that proves it was destroyed lawfully. It is
/// distinct from central inventory (Module 28, consumables) and the equipment
/// registry (Module 29, serialized instruments): waste is a quantity that leaves
/// the building and is accounted for by weight.
///
/// Three records, mirroring the scope: the governed [WasteCategory] catalogue,
/// the append-only [WasteGenerationLog], and the barcoded [DisposalCertificate].
/// Compliance is *derived* ([wasteComplianceGap]) rather than stored, so it
/// cannot drift from the facts it summarises. Weight is an integer number of
/// grams, matching the integer-minor-unit convention money uses — no floats on
/// a compliance figure.
// ignore_for_file: sort_constructors_first
library;

import 'package:meta/meta.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';

/// The colour coding of a waste stream.
enum WasteColour {
  /// Human anatomical and infected waste.
  yellow('yellow'),

  /// Contaminated recyclable plastic.
  red('red'),

  /// Sharps and broken glass.
  white('white'),

  /// Glassware and metallic implants.
  blue('blue'),

  /// Discarded medicines.
  black('black'),

  /// General non-hazardous waste.
  green('green'),

  /// Anything else.
  other('other');

  const WasteColour(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    WasteColour.yellow => 'Yellow',
    WasteColour.red => 'Red',
    WasteColour.white => 'White',
    WasteColour.blue => 'Blue',
    WasteColour.black => 'Black',
    WasteColour.green => 'Green',
    WasteColour.other => 'Other',
  };

  /// Parses a stored value.
  static WasteColour fromWire(String value) => WasteColour.values.firstWhere(
    (WasteColour colour) => colour.wireValue == value,
    orElse: () => WasteColour.other,
  );
}

/// The hazard class of a waste stream.
enum WasteHazardClass {
  /// Infectious or potentially infectious.
  infectious('infectious'),

  /// Sharps.
  sharps('sharps'),

  /// Discarded pharmaceuticals.
  pharmaceutical('pharmaceutical'),

  /// Chemical waste.
  chemical('chemical'),

  /// Radioactive waste.
  radioactive('radioactive'),

  /// Non-hazardous general waste.
  general('general'),

  /// Anything else.
  other('other');

  const WasteHazardClass(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    WasteHazardClass.infectious => 'Infectious',
    WasteHazardClass.sharps => 'Sharps',
    WasteHazardClass.pharmaceutical => 'Pharmaceutical',
    WasteHazardClass.chemical => 'Chemical',
    WasteHazardClass.radioactive => 'Radioactive',
    WasteHazardClass.general => 'General',
    WasteHazardClass.other => 'Other',
  };

  /// Parses a stored value.
  static WasteHazardClass fromWire(String value) =>
      WasteHazardClass.values.firstWhere(
        (WasteHazardClass hazard) => hazard.wireValue == value,
        orElse: () => WasteHazardClass.other,
      );
}

/// The treatment method a certificate records.
enum DisposalMethod {
  /// High-temperature incineration.
  incineration('incineration'),

  /// Steam sterilisation.
  autoclave('autoclave'),

  /// Chemical disinfection.
  chemical('chemical'),

  /// Microwave treatment.
  microwave('microwave'),

  /// Engineered landfill.
  landfill('landfill'),

  /// Material recovery.
  recycling('recycling'),

  /// Anything else.
  other('other');

  const DisposalMethod(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    DisposalMethod.incineration => 'Incineration',
    DisposalMethod.autoclave => 'Autoclave',
    DisposalMethod.chemical => 'Chemical',
    DisposalMethod.microwave => 'Microwave',
    DisposalMethod.landfill => 'Landfill',
    DisposalMethod.recycling => 'Recycling',
    DisposalMethod.other => 'Other',
  };

  /// Parses a stored value.
  static DisposalMethod fromWire(String value) =>
      DisposalMethod.values.firstWhere(
        (DisposalMethod method) => method.wireValue == value,
        orElse: () => DisposalMethod.other,
      );
}

/// Lifecycle status of a disposal certificate.
enum CertificateStatus {
  /// Issued and standing.
  issued('issued'),

  /// Withdrawn with a reason; retained and frozen.
  voided('voided');

  const CertificateStatus(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    CertificateStatus.issued => 'Issued',
    CertificateStatus.voided => 'Voided',
  };

  /// Parses a stored value.
  static CertificateStatus fromWire(String value) =>
      CertificateStatus.values.firstWhere(
        (CertificateStatus status) => status.wireValue == value,
        orElse: () => CertificateStatus.issued,
      );

  /// Whether the certificate stands as a compliance assertion.
  bool get isLive => this == CertificateStatus.issued;
}

/// Whether a certificate may move from [from] to [to]. Voiding is the only
/// transition and it is one-way. This is the same rule the database enforces.
bool certificateCanTransition(CertificateStatus from, CertificateStatus to) =>
    from == CertificateStatus.issued && to == CertificateStatus.voided;

/// The weight generated but not yet covered by a live disposal certificate.
///
/// Negative results are impossible — a certificate for more than the window's
/// generation is a prior period's batch, not a negative gap — so the floor is
/// zero.
int wasteComplianceGap({
  required int generatedGrams,
  required int certificatedGrams,
}) {
  final int gap = generatedGrams - certificatedGrams;
  return gap > 0 ? gap : 0;
}

/// A governed waste stream.
@immutable
final class WasteCategory {
  /// Creates a category.
  const WasteCategory({
    required this.id,
    required this.tenantId,
    required this.code,
    required this.name,
    required this.colour,
    required this.hazardClass,
    required this.requiresTreatment,
    required this.isActive,
    required this.createdBy,
    required this.updatedAt,
    this.treatmentMethod,
    this.retentionDays,
    this.createdAt,
  });

  /// Validates and builds a new category row.
  static Map<String, Object?> registerRow({
    required String tenantId,
    required String createdBy,
    required String code,
    required String name,
    WasteColour colour = WasteColour.yellow,
    WasteHazardClass hazardClass = WasteHazardClass.infectious,
    bool requiresTreatment = true,
    String? treatmentMethod,
    int? retentionDays,
    bool isActive = true,
    String categoryId = '',
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (createdBy.isEmpty) {
      fieldErrors['created_by'] = 'Creator is required.';
    }
    if (code.trim().isEmpty) {
      fieldErrors['code'] = 'A code is required.';
    }
    if (name.trim().isEmpty) {
      fieldErrors['name'] = 'A name is required.';
    }
    if (retentionDays != null && retentionDays < 0) {
      fieldErrors['retention_days'] = 'Expected zero days or more.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Waste category failed validation.',
        fieldErrors: fieldErrors,
        code: 'waste_category_invalid',
      );
    }
    final String now = DateTime.now().toUtc().toIso8601String();
    return <String, Object?>{
      if (categoryId.isNotEmpty) 'id': categoryId,
      'tenant_id': tenantId,
      'code': code.trim(),
      'name': name.trim(),
      'colour': colour.wireValue,
      'hazard_class': hazardClass.wireValue,
      'requires_treatment': requiresTreatment ? 1 : 0,
      'treatment_method': _trimmed(treatmentMethod),
      'retention_days': retentionDays,
      'is_active': isActive ? 1 : 0,
      'created_by': createdBy,
      'created_at': now,
      'updated_at': now,
    };
  }

  /// Materializes a category from a local row.
  factory WasteCategory.fromRow(Map<String, Object?> row) => WasteCategory(
    id: row['id']! as String,
    tenantId: row['tenant_id']! as String,
    code: row['code']! as String,
    name: row['name']! as String,
    colour: WasteColour.fromWire(
      (row['colour'] as String?) ?? WasteColour.yellow.wireValue,
    ),
    hazardClass: WasteHazardClass.fromWire(
      (row['hazard_class'] as String?) ?? WasteHazardClass.infectious.wireValue,
    ),
    requiresTreatment: _asBool(row['requires_treatment']),
    isActive: _asBool(row['is_active']),
    createdBy: row['created_by']! as String,
    updatedAt: _parse(row['updated_at']),
    treatmentMethod: row['treatment_method'] as String?,
    retentionDays: row['retention_days'] == null
        ? null
        : _asInt(row['retention_days']),
    createdAt: _parseNullable(row['created_at']),
  );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// Unique short code.
  final String code;

  /// Display name.
  final String name;

  /// Colour code of the stream.
  final WasteColour colour;

  /// Hazard class.
  final WasteHazardClass hazardClass;

  /// Whether the stream must be treated before disposal.
  final bool requiresTreatment;

  /// Required treatment method, when any.
  final String? treatmentMethod;

  /// Retention period in days, when a rule applies.
  final int? retentionDays;

  /// Whether the category is currently in use.
  final bool isActive;

  /// Who created the category.
  final String createdBy;

  /// Last change, UTC.
  final DateTime updatedAt;

  /// When the category was created, UTC.
  final DateTime? createdAt;
}

/// The full editable change set for a category.
Map<String, Object?> wasteCategoryChanges({
  required String code,
  required String name,
  WasteColour? colour,
  WasteHazardClass? hazardClass,
  bool? requiresTreatment,
  String? treatmentMethod,
  int? retentionDays,
  bool? isActive,
}) => <String, Object?>{
  'code': code.trim(),
  'name': name.trim(),
  'treatment_method': _trimmed(treatmentMethod),
  'retention_days': retentionDays,
  if (colour != null) 'colour': colour.wireValue,
  if (hazardClass != null) 'hazard_class': hazardClass.wireValue,
  if (requiresTreatment != null)
    'requires_treatment': requiresTreatment ? 1 : 0,
  if (isActive != null) 'is_active': isActive ? 1 : 0,
  'updated_at': DateTime.now().toUtc().toIso8601String(),
};

/// An append-only record of waste generated.
@immutable
final class WasteGenerationLog {
  /// Creates a generation log.
  const WasteGenerationLog({
    required this.id,
    required this.tenantId,
    required this.facilityId,
    required this.categoryId,
    required this.weightGrams,
    required this.containerCount,
    required this.loggedAt,
    required this.loggedBy,
    required this.createdAt,
    this.departmentId,
    this.locationLabel,
    this.notes,
  });

  /// Validates and builds a new generation log row.
  static Map<String, Object?> registerRow({
    required String tenantId,
    required String facilityId,
    required String categoryId,
    required String loggedBy,
    required int weightGrams,
    String? departmentId,
    String? locationLabel,
    int containerCount = 1,
    DateTime? loggedAt,
    String? notes,
    String logId = '',
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (facilityId.isEmpty) {
      fieldErrors['facility_id'] = 'A facility is required.';
    }
    if (categoryId.isEmpty) {
      fieldErrors['category_id'] = 'A waste category is required.';
    }
    if (loggedBy.isEmpty) {
      fieldErrors['logged_by'] = 'A recorder is required.';
    }
    if (weightGrams <= 0) {
      fieldErrors['weight_grams'] = 'Expected a weight greater than zero.';
    }
    if (containerCount < 0) {
      fieldErrors['container_count'] = 'Expected zero containers or more.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Waste generation log failed validation.',
        fieldErrors: fieldErrors,
        code: 'waste_generation_invalid',
      );
    }
    final String now = (loggedAt ?? DateTime.now().toUtc())
        .toUtc()
        .toIso8601String();
    return <String, Object?>{
      if (logId.isNotEmpty) 'id': logId,
      'tenant_id': tenantId,
      'facility_id': facilityId,
      'category_id': categoryId,
      'department_id': _trimmed(departmentId),
      'location_label': _trimmed(locationLabel),
      'weight_grams': weightGrams,
      'container_count': containerCount,
      'logged_at': now,
      'logged_by': loggedBy,
      'notes': _trimmed(notes),
      'created_at': now,
    };
  }

  /// Materializes a generation log from a local row.
  factory WasteGenerationLog.fromRow(Map<String, Object?> row) =>
      WasteGenerationLog(
        id: row['id']! as String,
        tenantId: row['tenant_id']! as String,
        facilityId: row['facility_id']! as String,
        categoryId: row['category_id']! as String,
        weightGrams: _asInt(row['weight_grams']),
        containerCount: _asInt(row['container_count']),
        loggedAt: _parse(row['logged_at']),
        loggedBy: row['logged_by']! as String,
        createdAt: _parse(row['created_at']),
        departmentId: row['department_id'] as String?,
        locationLabel: row['location_label'] as String?,
        notes: row['notes'] as String?,
      );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// Facility.
  final String facilityId;

  /// Waste stream.
  final String categoryId;

  /// Originating department, when known.
  final String? departmentId;

  /// Free-text location.
  final String? locationLabel;

  /// Weight in grams.
  final int weightGrams;

  /// Number of containers the weight represents.
  final int containerCount;

  /// When the waste was logged, UTC.
  final DateTime loggedAt;

  /// Who logged it.
  final String loggedBy;

  /// Free-text note.
  final String? notes;

  /// When the row was captured locally, UTC.
  final DateTime createdAt;
}

/// A barcoded disposal certificate.
@immutable
final class DisposalCertificate {
  /// Creates a certificate.
  const DisposalCertificate({
    required this.id,
    required this.tenantId,
    required this.facilityId,
    required this.categoryId,
    required this.certificateNo,
    required this.barcode,
    required this.disposalVendor,
    required this.method,
    required this.disposedAt,
    required this.weightGrams,
    required this.status,
    required this.issuedBy,
    required this.updatedAt,
    this.vendorLicence,
    this.manifestReference,
    this.voidReason,
    this.createdAt,
  });

  /// Validates and builds a new certificate row.
  static Map<String, Object?> registerRow({
    required String tenantId,
    required String facilityId,
    required String categoryId,
    required String issuedBy,
    required String certificateNo,
    required String barcode,
    required String disposalVendor,
    required DisposalMethod method,
    required DateTime disposedAt,
    required int weightGrams,
    String? vendorLicence,
    String? manifestReference,
    String certificateId = '',
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (facilityId.isEmpty) {
      fieldErrors['facility_id'] = 'A facility is required.';
    }
    if (categoryId.isEmpty) {
      fieldErrors['category_id'] = 'A waste category is required.';
    }
    if (issuedBy.isEmpty) {
      fieldErrors['issued_by'] = 'An issuer is required.';
    }
    if (certificateNo.trim().isEmpty) {
      fieldErrors['certificate_no'] = 'A certificate number is required.';
    }
    if (barcode.trim().isEmpty) {
      fieldErrors['barcode'] = 'A barcode is required.';
    }
    if (disposalVendor.trim().isEmpty) {
      fieldErrors['disposal_vendor'] = 'A disposal vendor is required.';
    }
    if (weightGrams <= 0) {
      fieldErrors['weight_grams'] = 'Expected a weight greater than zero.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Disposal certificate failed validation.',
        fieldErrors: fieldErrors,
        code: 'waste_certificate_invalid',
      );
    }
    final String now = DateTime.now().toUtc().toIso8601String();
    return <String, Object?>{
      if (certificateId.isNotEmpty) 'id': certificateId,
      'tenant_id': tenantId,
      'facility_id': facilityId,
      'category_id': categoryId,
      'certificate_no': certificateNo.trim(),
      'barcode': barcode.trim(),
      'disposal_vendor': disposalVendor.trim(),
      'vendor_licence': _trimmed(vendorLicence),
      'method': method.wireValue,
      'disposed_at': disposedAt.toUtc().toIso8601String(),
      'weight_grams': weightGrams,
      'manifest_reference': _trimmed(manifestReference),
      'status': CertificateStatus.issued.wireValue,
      'issued_by': issuedBy,
      'created_at': now,
      'updated_at': now,
    };
  }

  /// Materializes a certificate from a local row.
  factory DisposalCertificate.fromRow(Map<String, Object?> row) =>
      DisposalCertificate(
        id: row['id']! as String,
        tenantId: row['tenant_id']! as String,
        facilityId: row['facility_id']! as String,
        categoryId: row['category_id']! as String,
        certificateNo: row['certificate_no']! as String,
        barcode: row['barcode']! as String,
        disposalVendor: row['disposal_vendor']! as String,
        method: DisposalMethod.fromWire(
          (row['method'] as String?) ?? DisposalMethod.other.wireValue,
        ),
        disposedAt: _parse(row['disposed_at']),
        weightGrams: _asInt(row['weight_grams']),
        status: CertificateStatus.fromWire(
          (row['status'] as String?) ?? CertificateStatus.issued.wireValue,
        ),
        issuedBy: row['issued_by']! as String,
        updatedAt: _parse(row['updated_at']),
        vendorLicence: row['vendor_licence'] as String?,
        manifestReference: row['manifest_reference'] as String?,
        voidReason: row['void_reason'] as String?,
        createdAt: _parseNullable(row['created_at']),
      );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// Facility.
  final String facilityId;

  /// Waste stream certified.
  final String categoryId;

  /// Human certificate number.
  final String certificateNo;

  /// Barcode that identifies the certificate.
  final String barcode;

  /// Disposal vendor.
  final String disposalVendor;

  /// Vendor licence number, when recorded.
  final String? vendorLicence;

  /// Treatment method.
  final DisposalMethod method;

  /// When the waste was disposed of, UTC.
  final DateTime disposedAt;

  /// Weight in grams certified.
  final int weightGrams;

  /// Manifest reference, when any.
  final String? manifestReference;

  /// Lifecycle status.
  final CertificateStatus status;

  /// Why the certificate was voided.
  final String? voidReason;

  /// Who issued the certificate.
  final String issuedBy;

  /// Last change, UTC.
  final DateTime updatedAt;

  /// When the certificate was captured locally, UTC.
  final DateTime? createdAt;

  /// Whether the certificate still stands as a compliance assertion.
  bool get isLive => status.isLive;
}

/// The change set for voiding a certificate. The row is retained and frozen.
Map<String, Object?> certificateVoidChanges({required String reason}) =>
    <String, Object?>{
      'status': CertificateStatus.voided.wireValue,
      'void_reason': reason.trim(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

String? _trimmed(String? value) {
  final String? trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

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

bool _asBool(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  if (value is String) {
    return value == '1' || value.toLowerCase() == 'true';
  }
  return false;
}
