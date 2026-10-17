/// Biomedical waste management use cases (Module 30).
library;

import 'package:meta/meta.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/waste/waste.dart';
import 'package:nodex_hms/domain/waste/waste_repository.dart';

/// Registers a governed waste stream.
final class RegisterCategoryUseCase {
  /// Creates the use case.
  RegisterCategoryUseCase({required this._repository});

  final WasteRepository _repository;

  Future<String> call({
    required AuthorizationPolicy policy,
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
  }) async {
    policy.require(NodexPermissions.wasteManage);
    return _repository.registerCategory(
      WasteCategory.registerRow(
        tenantId: tenantId,
        createdBy: createdBy,
        code: code,
        name: name,
        colour: colour,
        hazardClass: hazardClass,
        requiresTreatment: requiresTreatment,
        treatmentMethod: treatmentMethod,
        retentionDays: retentionDays,
        isActive: isActive,
        categoryId: categoryId,
      ),
    );
  }
}

/// Updates a waste stream.
final class UpdateCategoryUseCase {
  /// Creates the use case.
  UpdateCategoryUseCase({required this._repository});

  final WasteRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required WasteCategory category,
    required String code,
    required String name,
    WasteColour? colour,
    WasteHazardClass? hazardClass,
    bool? requiresTreatment,
    String? treatmentMethod,
    int? retentionDays,
    bool? isActive,
  }) async {
    policy.require(NodexPermissions.wasteManage);
    await _repository.updateCategory(
      category.id,
      wasteCategoryChanges(
        code: code,
        name: name,
        colour: colour,
        hazardClass: hazardClass,
        requiresTreatment: requiresTreatment,
        treatmentMethod: treatmentMethod,
        retentionDays: retentionDays,
        isActive: isActive,
      ),
    );
  }
}

/// Records waste generated. The category must be one that is in use.
final class LogGenerationUseCase {
  /// Creates the use case.
  LogGenerationUseCase({required this._repository});

  final WasteRepository _repository;

  Future<String> call({
    required AuthorizationPolicy policy,
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
  }) async {
    policy.require(NodexPermissions.wasteRecord);
    await _requireActiveCategory(tenantId, categoryId);
    return _repository.registerGenerationLog(
      WasteGenerationLog.registerRow(
        tenantId: tenantId,
        facilityId: facilityId,
        categoryId: categoryId,
        loggedBy: loggedBy,
        weightGrams: weightGrams,
        departmentId: departmentId,
        locationLabel: locationLabel,
        containerCount: containerCount,
        loggedAt: loggedAt,
        notes: notes,
        logId: logId,
      ),
    );
  }

  Future<void> _requireActiveCategory(
    String tenantId,
    String categoryId,
  ) async {
    final WasteCategory? category = await _repository.categoryById(categoryId);
    if (category == null) {
      throw const ValidationError(
        message: 'Waste generation log failed validation.',
        fieldErrors: <String, String>{
          'category_id': 'That waste category does not exist.',
        },
        code: 'waste_category_missing',
      );
    }
    if (!category.isActive) {
      throw const ValidationError(
        message: 'Waste generation log failed validation.',
        fieldErrors: <String, String>{
          'category_id': 'That waste category is no longer in use.',
        },
        code: 'waste_category_inactive',
      );
    }
  }
}

/// Issues a barcoded disposal certificate.
///
/// The certificate number and barcode are unique within the tenant, a rule the
/// database enforces; this checks the same rule against the rows already on the
/// device so a duplicate is refused immediately offline.
final class IssueCertificateUseCase {
  /// Creates the use case.
  IssueCertificateUseCase({required this._repository});

  final WasteRepository _repository;

  Future<String> call({
    required AuthorizationPolicy policy,
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
  }) async {
    policy.require(NodexPermissions.wasteManage);
    final WasteCategory? category = await _repository.categoryById(categoryId);
    if (category == null || !category.isActive) {
      throw const ValidationError(
        message: 'Disposal certificate failed validation.',
        fieldErrors: <String, String>{
          'category_id': 'That waste category is not in use.',
        },
        code: 'waste_category_missing',
      );
    }
    final List<DisposalCertificate> existing = await _repository
        .listCertificates(tenantId);
    for (final DisposalCertificate certificate in existing) {
      if (certificate.certificateNo == certificateNo.trim()) {
        throw const ValidationError(
          message: 'Disposal certificate failed validation.',
          fieldErrors: <String, String>{
            'certificate_no': 'That certificate number is already used.',
          },
          code: 'waste_certificate_duplicate',
        );
      }
      if (certificate.barcode == barcode.trim()) {
        throw const ValidationError(
          message: 'Disposal certificate failed validation.',
          fieldErrors: <String, String>{
            'barcode': 'That barcode is already used.',
          },
          code: 'waste_certificate_duplicate',
        );
      }
    }
    return _repository.registerCertificate(
      DisposalCertificate.registerRow(
        tenantId: tenantId,
        facilityId: facilityId,
        categoryId: categoryId,
        issuedBy: issuedBy,
        certificateNo: certificateNo,
        barcode: barcode,
        disposalVendor: disposalVendor,
        method: method,
        disposedAt: disposedAt,
        weightGrams: weightGrams,
        vendorLicence: vendorLicence,
        manifestReference: manifestReference,
        certificateId: certificateId,
      ),
    );
  }
}

/// Voids a disposal certificate. Voiding is one-way and freezes the row.
final class VoidCertificateUseCase {
  /// Creates the use case.
  VoidCertificateUseCase({required this._repository});

  final WasteRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required DisposalCertificate certificate,
    required String reason,
  }) async {
    policy.require(NodexPermissions.wasteManage);
    if (reason.trim().isEmpty) {
      throw const ValidationError(
        message: 'Disposal certificate failed validation.',
        fieldErrors: <String, String>{
          'void_reason': 'Say why the certificate is void.',
        },
        code: 'waste_certificate_reason_required',
      );
    }
    if (!certificateCanTransition(
      certificate.status,
      CertificateStatus.voided,
    )) {
      throw const AuthorizationError(
        message: 'This certificate is already void and cannot be changed.',
        code: 'waste_certificate_already_void',
      );
    }
    await _repository.updateCertificate(
      certificate.id,
      certificateVoidChanges(reason: reason),
    );
  }
}

/// A per-category compliance row: the weight generated in a window against the
/// weight covered by live certificates.
@immutable
final class WasteCategoryCompliance {
  /// Creates a compliance row.
  const WasteCategoryCompliance({
    required this.category,
    required this.generatedGrams,
    required this.certificatedGrams,
  });

  /// The waste stream.
  final WasteCategory category;

  /// Weight generated in the window, in grams.
  final int generatedGrams;

  /// Weight covered by live certificates in the window, in grams.
  final int certificatedGrams;

  /// The uncovered weight, in grams.
  int get gapGrams => wasteComplianceGap(
    generatedGrams: generatedGrams,
    certificatedGrams: certificatedGrams,
  );

  /// Whether every gram generated is covered by a live certificate.
  bool get isCompliant => gapGrams == 0;
}

/// Reads the waste board, logs, certificates and compliance.
final class ReadWasteUseCase {
  /// Creates the use case.
  ReadWasteUseCase({required this._repository});

  final WasteRepository _repository;

  /// Waste categories, excluding inactive unless [includeInactive].
  Future<List<WasteCategory>> categories({
    required AuthorizationPolicy policy,
    required String tenantId,
    bool includeInactive = false,
  }) async {
    policy.require(NodexPermissions.wasteRead);
    final List<WasteCategory> categories = await _repository.listCategories(
      tenantId,
    );
    return categories
        .where((WasteCategory category) => includeInactive || category.isActive)
        .toList(growable: false);
  }

  /// Generation logs, newest first, within the half-open window `[from, to)`
  /// when supplied.
  Future<List<WasteGenerationLog>> generationLogs({
    required AuthorizationPolicy policy,
    required String tenantId,
    String? categoryId,
    String? facilityId,
    DateTime? from,
    DateTime? to,
  }) async {
    policy.require(NodexPermissions.wasteRead);
    final List<WasteGenerationLog> logs = await _repository.listGenerationLogs(
      tenantId,
      categoryId: categoryId,
      facilityId: facilityId,
    );
    final List<WasteGenerationLog> filtered = logs
        .where((WasteGenerationLog log) => _inWindow(log.loggedAt, from, to))
        .toList(growable: false);
    filtered.sort(
      (WasteGenerationLog a, WasteGenerationLog b) =>
          b.loggedAt.compareTo(a.loggedAt),
    );
    return filtered;
  }

  /// Disposal certificates, newest first, within the half-open window
  /// `[from, to)` when supplied. Voided certificates are excluded unless
  /// [includeVoided].
  Future<List<DisposalCertificate>> certificates({
    required AuthorizationPolicy policy,
    required String tenantId,
    String? categoryId,
    String? facilityId,
    DateTime? from,
    DateTime? to,
    bool includeVoided = false,
  }) async {
    policy.require(NodexPermissions.wasteRead);
    final List<DisposalCertificate> certificates = await _repository
        .listCertificates(
          tenantId,
          categoryId: categoryId,
          facilityId: facilityId,
        );
    final List<DisposalCertificate> filtered = certificates
        .where(
          (DisposalCertificate certificate) =>
              (includeVoided || certificate.isLive) &&
              _inWindow(certificate.disposedAt, from, to),
        )
        .toList(growable: false);
    filtered.sort(
      (DisposalCertificate a, DisposalCertificate b) =>
          b.disposedAt.compareTo(a.disposedAt),
    );
    return filtered;
  }

  /// The compliance board for the half-open window `[from, to)`: each category
  /// with the weight generated against the weight covered by live certificates,
  /// largest gap first.
  Future<List<WasteCategoryCompliance>> compliance({
    required AuthorizationPolicy policy,
    required String tenantId,
    required DateTime from,
    required DateTime to,
    String? facilityId,
  }) async {
    policy.require(NodexPermissions.wasteRead);
    final List<WasteCategory> categories = await _repository.listCategories(
      tenantId,
    );
    final List<WasteGenerationLog> logs = await _repository.listGenerationLogs(
      tenantId,
      facilityId: facilityId,
    );
    final List<DisposalCertificate> certificates = await _repository
        .listCertificates(tenantId, facilityId: facilityId);

    final Map<String, int> generated = <String, int>{};
    final Map<String, int> certificated = <String, int>{};
    for (final WasteGenerationLog log in logs) {
      if (_inWindow(log.loggedAt, from, to)) {
        generated.update(
          log.categoryId,
          (int value) => value + log.weightGrams,
          ifAbsent: () => log.weightGrams,
        );
      }
    }
    for (final DisposalCertificate certificate in certificates) {
      if (certificate.isLive && _inWindow(certificate.disposedAt, from, to)) {
        certificated.update(
          certificate.categoryId,
          (int value) => value + certificate.weightGrams,
          ifAbsent: () => certificate.weightGrams,
        );
      }
    }

    final Set<String> active = <String>{
      for (final WasteCategory category in categories)
        if (category.isActive) category.id,
    };
    final List<WasteCategoryCompliance> board = <WasteCategoryCompliance>[
      for (final WasteCategory category in categories)
        if (active.contains(category.id) ||
            generated.containsKey(category.id) ||
            certificated.containsKey(category.id))
          WasteCategoryCompliance(
            category: category,
            generatedGrams: generated[category.id] ?? 0,
            certificatedGrams: certificated[category.id] ?? 0,
          ),
    ];
    board.sort((WasteCategoryCompliance a, WasteCategoryCompliance b) {
      final int gap = b.gapGrams - a.gapGrams;
      if (gap != 0) {
        return gap;
      }
      return a.category.code.compareTo(b.category.code);
    });
    return board;
  }
}

bool _inWindow(DateTime value, DateTime? from, DateTime? to) {
  final DateTime at = value.toUtc();
  if (from != null && at.isBefore(from.toUtc())) {
    return false;
  }
  if (to != null && !at.isBefore(to.toUtc())) {
    return false;
  }
  return true;
}
