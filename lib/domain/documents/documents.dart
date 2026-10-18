/// Documents & Biometric E-Consent Vault entities (Module 33).
///
/// Specification scope: "Procedure and surgical consent forms, high-resolution
/// stylus signature capture, biometric thumbprint capture, and PDF vault."
/// Security: "Generated documents are cryptographically signed, hashed
/// (SHA-256), and stored in tenant-isolated encrypted storage buckets."
///
/// This is the documentary estate: the moment a patient agrees to a procedure
/// and the artefact that proves it. It is distinct from the clinical record it
/// attests: an encounter holds the treatment, a consent authorises it.
///
/// Three records, mirroring the scope: the versioned [ConsentTemplate]
/// catalogue, the [ConsentRecord] the patient signs, and the
/// [VaultDocument] index of what the vault holds. Two facts are *derived*
/// rather than stored, so they cannot drift: the validity of a consent
/// ([consentValidity]) from its status and expiry, and what is still missing
/// before it may be signed ([missingConsentAttestations]).
///
/// Every vaulted artefact carries a mandatory lowercase hexadecimal SHA-256
/// digest, which is the same digest the storage bucket requires in the object
/// metadata. The detached signature is optional and is recorded as a coherent
/// triple (signature, algorithm, key id) or not at all: NODEX does not
/// fabricate a signature it cannot verify.
// ignore_for_file: sort_constructors_first
library;

import 'package:meta/meta.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';

/// Who signed a consent, in relation to the patient.
enum SignerRelationship {
  /// The patient themselves.
  patient('patient'),

  /// A legal guardian.
  guardian('guardian'),

  /// A relative acting for the patient.
  relative('relative'),

  /// Anyone else, recorded on the row.
  other('other');

  const SignerRelationship(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    SignerRelationship.patient => 'Patient',
    SignerRelationship.guardian => 'Guardian',
    SignerRelationship.relative => 'Relative',
    SignerRelationship.other => 'Other',
  };

  /// Parses a stored value.
  static SignerRelationship fromWire(String value) =>
      SignerRelationship.values.firstWhere(
        (SignerRelationship value_) => value_.wireValue == value,
        orElse: () => SignerRelationship.patient,
      );
}

/// How a biometric attestation was captured.
enum BiometricMethod {
  /// No biometric was taken.
  none('none'),

  /// A thumbprint captured by a reader.
  thumbprint('thumbprint'),

  /// A fingerprint taken from a sensor.
  fingerprintSensor('fingerprint_sensor'),

  /// A face capture.
  face('face');

  const BiometricMethod(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    BiometricMethod.none => 'None',
    BiometricMethod.thumbprint => 'Thumbprint',
    BiometricMethod.fingerprintSensor => 'Fingerprint sensor',
    BiometricMethod.face => 'Face',
  };

  /// Parses a stored value.
  static BiometricMethod fromWire(String value) =>
      BiometricMethod.values.firstWhere(
        (BiometricMethod value_) => value_.wireValue == value,
        orElse: () => BiometricMethod.none,
      );
}

/// Lifecycle status of a consent record.
enum ConsentStatus {
  /// Raised; attestations still being captured.
  drafted('drafted'),

  /// Prepared and being shown to the patient for signature.
  awaitingSignature('awaiting_signature'),

  /// Signed; retained and frozen but for revocation.
  signed('signed'),

  /// The patient refused.
  declined('declined'),

  /// A signed consent withdrawn after the fact.
  revoked('revoked');

  const ConsentStatus(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    ConsentStatus.drafted => 'Drafted',
    ConsentStatus.awaitingSignature => 'Awaiting signature',
    ConsentStatus.signed => 'Signed',
    ConsentStatus.declined => 'Declined',
    ConsentStatus.revoked => 'Revoked',
  };

  /// Parses a stored value.
  static ConsentStatus fromWire(String value) =>
      ConsentStatus.values.firstWhere(
        (ConsentStatus value_) => value_.wireValue == value,
        orElse: () => ConsentStatus.drafted,
      );

  /// Whether the consent has still to be decided: signed or declined.
  bool get isLive =>
      this == ConsentStatus.drafted || this == ConsentStatus.awaitingSignature;

  /// Whether the patient has signed.
  bool get isSigned => this == ConsentStatus.signed;

  /// Whether the consent is closed.
  bool get isTerminal => !isLive && !isSigned;
}

/// Whether a consent may move from [from] to [to].
///
/// One stage at a time, declined from either live stage, and a signed consent
/// may only be revoked. This is the same rule the database enforces.
bool consentCanTransition(ConsentStatus from, ConsentStatus to) {
  if (from.isTerminal) {
    return false;
  }
  if (from == ConsentStatus.signed) {
    return to == ConsentStatus.revoked;
  }
  return switch (from) {
    ConsentStatus.drafted =>
      to == ConsentStatus.awaitingSignature ||
          to == ConsentStatus.signed ||
          to == ConsentStatus.declined,
    ConsentStatus.awaitingSignature =>
      to == ConsentStatus.signed || to == ConsentStatus.declined,
    _ => false,
  };
}

/// Where a consent stands, derived from its status and expiry.
enum ConsentValidity {
  /// Raised, attestations still being captured.
  pending('pending'),

  /// Waiting on the patient's signature.
  awaitingSignature('awaiting signature'),

  /// Signed and still within its validity.
  signed('signed'),

  /// Signed but past its expiry.
  expired('expired'),

  /// Refused by the patient.
  declined('declined'),

  /// Withdrawn after signing.
  revoked('revoked');

  const ConsentValidity(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    ConsentValidity.pending => 'Pending',
    ConsentValidity.awaitingSignature => 'Awaiting signature',
    ConsentValidity.signed => 'Signed',
    ConsentValidity.expired => 'Expired',
    ConsentValidity.declined => 'Declined',
    ConsentValidity.revoked => 'Revoked',
  };

  /// Whether the consent needs an attention marker on the board.
  bool get needsAttention =>
      this == ConsentValidity.expired ||
      this == ConsentValidity.awaitingSignature ||
      this == ConsentValidity.pending;
}

/// The validity of a consent, derived from its status and its expiry.
///
/// A refusal or a revocation wins over the dates: a withdrawn consent is
/// withdrawn whatever its expiry says. A signed consent without an expiry never
/// lapses.
ConsentValidity consentValidity({
  required ConsentStatus status,
  required DateTime now,
  DateTime? expiresAt,
}) {
  switch (status) {
    case ConsentStatus.declined:
      return ConsentValidity.declined;
    case ConsentStatus.revoked:
      return ConsentValidity.revoked;
    case ConsentStatus.drafted:
      return ConsentValidity.pending;
    case ConsentStatus.awaitingSignature:
      return ConsentValidity.awaitingSignature;
    case ConsentStatus.signed:
      if (expiresAt != null && expiresAt.toUtc().isBefore(now.toUtc())) {
        return ConsentValidity.expired;
      }
      return ConsentValidity.signed;
  }
}

/// What a consent still needs before it may be signed.
enum ConsentAttestation {
  /// A captured stylus signature.
  signature('signature'),

  /// A captured biometric attestation.
  biometric('biometric'),

  /// A witness attestation.
  witness('witness'),

  /// The vaulted artefact that carries the signature.
  document('document');

  const ConsentAttestation(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    ConsentAttestation.signature => 'Signature',
    ConsentAttestation.biometric => 'Biometric',
    ConsentAttestation.witness => 'Witness',
    ConsentAttestation.document => 'Vaulted document',
  };
}

/// What is still missing before [record] may be signed under [template].
///
/// The signature and the vaulted artefact are always required — a consent
/// without either is not a consent. The biometric and the witness are required
/// only when the template version says so, which is why this is derived from
/// the template as well as the record. A null [template] means the version has
/// not reached this device, so only the unconditional requirements are known;
/// the server refuses the signature in that case anyway.
Set<ConsentAttestation> missingConsentAttestations({
  required ConsentTemplate? template,
  required ConsentRecord record,
}) {
  final Set<ConsentAttestation> missing = <ConsentAttestation>{};
  if (record.signatureSha256 == null) {
    missing.add(ConsentAttestation.signature);
  }
  if (template != null &&
      template.requiresBiometric &&
      record.biometricMethod == BiometricMethod.none) {
    missing.add(ConsentAttestation.biometric);
  }
  if (template != null &&
      template.requiresWitness &&
      record.witnessedBy == null) {
    missing.add(ConsentAttestation.witness);
  }
  if (record.documentId == null) {
    missing.add(ConsentAttestation.document);
  }
  return missing;
}

/// The kind of artefact a vault entry indexes.
enum VaultDocumentKind {
  /// The consent form itself.
  consentForm('consent_form'),

  /// The captured stylus signature image.
  consentSignature('consent_signature'),

  /// A clinical report or summary.
  report('report'),

  /// Anything else the vault holds.
  other('other');

  const VaultDocumentKind(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    VaultDocumentKind.consentForm => 'Consent form',
    VaultDocumentKind.consentSignature => 'Signature capture',
    VaultDocumentKind.report => 'Report',
    VaultDocumentKind.other => 'Other',
  };

  /// Parses a stored value.
  static VaultDocumentKind fromWire(String value) =>
      VaultDocumentKind.values.firstWhere(
        (VaultDocumentKind value_) => value_.wireValue == value,
        orElse: () => VaultDocumentKind.other,
      );
}

/// The algorithm a detached signature was produced with.
enum SignatureAlgorithm {
  /// No signature was supplied.
  none('none'),

  /// HMAC over the digest with a shared key.
  hmacSha256('hmac_sha256'),

  /// An Ed25519 signature.
  ed25519('ed25519'),

  /// An RSA-PSS signature over SHA-256.
  rsaPssSha256('rsa_pss_sha256');

  const SignatureAlgorithm(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    SignatureAlgorithm.none => 'None',
    SignatureAlgorithm.hmacSha256 => 'HMAC-SHA256',
    SignatureAlgorithm.ed25519 => 'Ed25519',
    SignatureAlgorithm.rsaPssSha256 => 'RSA-PSS (SHA-256)',
  };

  /// Parses a stored value.
  static SignatureAlgorithm fromWire(String value) =>
      SignatureAlgorithm.values.firstWhere(
        (SignatureAlgorithm value_) => value_.wireValue == value,
        orElse: () => SignatureAlgorithm.none,
      );
}

/// Lifecycle status of a vaulted document.
enum VaultDocumentStatus {
  /// Issued and current.
  issued('issued'),

  /// Replaced by a later document.
  superseded('superseded'),

  /// Withdrawn as wrong.
  voided('voided');

  const VaultDocumentStatus(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    VaultDocumentStatus.issued => 'Issued',
    VaultDocumentStatus.superseded => 'Superseded',
    VaultDocumentStatus.voided => 'Voided',
  };

  /// Parses a stored value.
  static VaultDocumentStatus fromWire(String value) =>
      VaultDocumentStatus.values.firstWhere(
        (VaultDocumentStatus value_) => value_.wireValue == value,
        orElse: () => VaultDocumentStatus.issued,
      );

  /// Whether the document is still current.
  bool get isIssued => this == VaultDocumentStatus.issued;

  /// Whether the document is retired.
  bool get isTerminal => !isIssued;
}

/// Whether a vaulted document may move from [from] to [to].
///
/// Both endings are one-way; this is the same rule the database enforces.
bool documentCanTransition(VaultDocumentStatus from, VaultDocumentStatus to) {
  if (from.isTerminal) {
    return false;
  }
  return to == VaultDocumentStatus.superseded ||
      to == VaultDocumentStatus.voided;
}

/// Whether [value] is a lowercase hexadecimal SHA-256 digest.
bool isSha256Hex(String value) => RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

/// A version of a consent form's text.
@immutable
final class ConsentTemplate {
  /// Creates a template version.
  const ConsentTemplate({
    required this.id,
    required this.tenantId,
    required this.code,
    required this.title,
    required this.bodyText,
    required this.version,
    required this.requiresWitness,
    required this.requiresBiometric,
    required this.isActive,
    required this.createdBy,
    required this.updatedAt,
    this.procedureCategory,
    this.validityDays,
    this.createdAt,
  });

  /// Validates and builds a new template version row.
  static Map<String, Object?> registerRow({
    required String tenantId,
    required String createdBy,
    required String code,
    required String title,
    required String bodyText,
    int version = 1,
    String? procedureCategory,
    bool requiresWitness = false,
    bool requiresBiometric = false,
    int? validityDays,
    bool isActive = true,
    String templateId = '',
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
    if (title.trim().isEmpty) {
      fieldErrors['title'] = 'A title is required.';
    }
    if (bodyText.trim().isEmpty) {
      fieldErrors['body_text'] = 'The consent text is required.';
    }
    if (version < 1) {
      fieldErrors['version'] = 'Expected version 1 or later.';
    }
    if (validityDays != null && validityDays <= 0) {
      fieldErrors['validity_days'] = 'Expected one day or more.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Consent template failed validation.',
        fieldErrors: fieldErrors,
        code: 'consent_template_invalid',
      );
    }
    final String now = DateTime.now().toUtc().toIso8601String();
    return <String, Object?>{
      if (templateId.isNotEmpty) 'id': templateId,
      'tenant_id': tenantId,
      'code': code.trim(),
      'title': title.trim(),
      'procedure_category': _trimmed(procedureCategory),
      'body_text': bodyText.trim(),
      'version': version,
      'requires_witness': requiresWitness ? 1 : 0,
      'requires_biometric': requiresBiometric ? 1 : 0,
      'validity_days': validityDays,
      'is_active': isActive ? 1 : 0,
      'created_by': createdBy,
      'created_at': now,
      'updated_at': now,
    };
  }

  /// Materializes a template from a local row.
  factory ConsentTemplate.fromRow(Map<String, Object?> row) => ConsentTemplate(
    id: row['id']! as String,
    tenantId: row['tenant_id']! as String,
    code: row['code']! as String,
    title: row['title']! as String,
    bodyText: row['body_text']! as String,
    version: _asInt(row['version']),
    requiresWitness: _asBool(row['requires_witness']),
    requiresBiometric: _asBool(row['requires_biometric']),
    isActive: _asBool(row['is_active']),
    createdBy: row['created_by']! as String,
    updatedAt: _parse(row['updated_at']),
    procedureCategory: row['procedure_category'] as String?,
    validityDays: row['validity_days'] == null
        ? null
        : _asInt(row['validity_days']),
    createdAt: _parseNullable(row['created_at']),
  );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// Stable code shared by every version of the form.
  final String code;

  /// Display title.
  final String title;

  /// The consent text the patient is shown.
  final String bodyText;

  /// Version of the form; a version is immutable once written.
  final int version;

  /// Whether a witness attestation is required before signing.
  final bool requiresWitness;

  /// Whether a biometric attestation is required before signing.
  final bool requiresBiometric;

  /// Whether the version is still offered for new consents.
  final bool isActive;

  /// Who published the version.
  final String createdBy;

  /// Last change, UTC.
  final DateTime updatedAt;

  /// Procedure category the version applies to.
  final String? procedureCategory;

  /// Days a signature under this version stays valid.
  final int? validityDays;

  /// When the version was published, UTC.
  final DateTime? createdAt;
}

/// The change set for activating or retiring a template version.
///
/// Nothing else about a version changes: the words must stay as they were.
Map<String, Object?> consentTemplateActiveChanges({required bool isActive}) =>
    <String, Object?>{
      'is_active': isActive ? 1 : 0,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

/// A patient's decision about a procedure.
@immutable
final class ConsentRecord {
  /// Creates a consent record.
  const ConsentRecord({
    required this.id,
    required this.tenantId,
    required this.patientId,
    required this.facilityId,
    required this.templateId,
    required this.procedureText,
    required this.status,
    required this.signaturePointCount,
    required this.biometricMethod,
    required this.createdBy,
    required this.updatedAt,
    this.encounterId,
    this.signerName,
    this.signerRelationship,
    this.signatureSha256,
    this.signatureCapturedAt,
    this.biometricTemplateSha256,
    this.biometricCapturedAt,
    this.biometricQuality,
    this.witnessedBy,
    this.witnessedAt,
    this.documentId,
    this.signedAt,
    this.expiresAt,
    this.declinedAt,
    this.declineReason,
    this.revokedAt,
    this.revocationReason,
    this.createdAt,
  });

  /// Validates and builds a new consent row.
  ///
  /// A signature is not recorded here: a consent is raised first and signed
  /// when the patient, the attestations and the vaulted artefact are all
  /// present.
  static Map<String, Object?> registerRow({
    required String tenantId,
    required String patientId,
    required String facilityId,
    required String templateId,
    required String procedureText,
    required String createdBy,
    String? encounterId,
    int? validityDays,
    DateTime? now,
    String consentId = '',
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (patientId.isEmpty) {
      fieldErrors['patient_id'] = 'A patient is required.';
    }
    if (facilityId.isEmpty) {
      fieldErrors['facility_id'] = 'A facility is required.';
    }
    if (templateId.isEmpty) {
      fieldErrors['template_id'] = 'A consent template is required.';
    }
    if (procedureText.trim().isEmpty) {
      fieldErrors['procedure_text'] = 'A procedure is required.';
    }
    if (createdBy.isEmpty) {
      fieldErrors['created_by'] = 'Creator is required.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Consent record failed validation.',
        fieldErrors: fieldErrors,
        code: 'consent_record_invalid',
      );
    }
    final DateTime at = (now ?? DateTime.now()).toUtc();
    final String stamp = at.toIso8601String();
    return <String, Object?>{
      if (consentId.isNotEmpty) 'id': consentId,
      'tenant_id': tenantId,
      'patient_id': patientId,
      'facility_id': facilityId,
      'encounter_id': _trimmed(encounterId),
      'template_id': templateId,
      'procedure_text': procedureText.trim(),
      'status': ConsentStatus.drafted.wireValue,
      'signer_name': null,
      'signer_relationship': null,
      'signature_sha256': null,
      'signature_point_count': 0,
      'signature_captured_at': null,
      'biometric_method': BiometricMethod.none.wireValue,
      'biometric_template_sha256': null,
      'biometric_captured_at': null,
      'biometric_quality': null,
      'witnessed_by': null,
      'witnessed_at': null,
      'document_id': null,
      'signed_at': null,
      // The validity window is fixed when the consent is raised, so it does not
      // silently shorten if the template is re-versioned later.
      'expires_at': validityDays == null
          ? null
          : at.add(Duration(days: validityDays)).toIso8601String(),
      'declined_at': null,
      'decline_reason': null,
      'revoked_at': null,
      'revocation_reason': null,
      'created_by': createdBy,
      'created_at': stamp,
      'updated_at': stamp,
    };
  }

  /// Materializes a consent from a local row.
  factory ConsentRecord.fromRow(Map<String, Object?> row) => ConsentRecord(
    id: row['id']! as String,
    tenantId: row['tenant_id']! as String,
    patientId: row['patient_id']! as String,
    facilityId: row['facility_id']! as String,
    templateId: row['template_id']! as String,
    procedureText: row['procedure_text']! as String,
    status: ConsentStatus.fromWire(
      (row['status'] as String?) ?? ConsentStatus.drafted.wireValue,
    ),
    signaturePointCount: _asInt(row['signature_point_count']),
    biometricMethod: BiometricMethod.fromWire(
      (row['biometric_method'] as String?) ?? BiometricMethod.none.wireValue,
    ),
    createdBy: row['created_by']! as String,
    updatedAt: _parse(row['updated_at']),
    encounterId: row['encounter_id'] as String?,
    signerName: row['signer_name'] as String?,
    signerRelationship: row['signer_relationship'] == null
        ? null
        : SignerRelationship.fromWire(row['signer_relationship']! as String),
    signatureSha256: row['signature_sha256'] as String?,
    signatureCapturedAt: _parseNullable(row['signature_captured_at']),
    biometricTemplateSha256: row['biometric_template_sha256'] as String?,
    biometricCapturedAt: _parseNullable(row['biometric_captured_at']),
    biometricQuality: row['biometric_quality'] == null
        ? null
        : _asInt(row['biometric_quality']),
    witnessedBy: row['witnessed_by'] as String?,
    witnessedAt: _parseNullable(row['witnessed_at']),
    documentId: row['document_id'] as String?,
    signedAt: _parseNullable(row['signed_at']),
    expiresAt: _parseNullable(row['expires_at']),
    declinedAt: _parseNullable(row['declined_at']),
    declineReason: row['decline_reason'] as String?,
    revokedAt: _parseNullable(row['revoked_at']),
    revocationReason: row['revocation_reason'] as String?,
    createdAt: _parseNullable(row['created_at']),
  );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// The patient who is consenting.
  final String patientId;

  /// The facility where consent is taken.
  final String facilityId;

  /// The template version the patient was shown.
  final String templateId;

  /// The procedure consented to, as it is written on the form.
  final String procedureText;

  /// Lifecycle status.
  final ConsentStatus status;

  /// Number of stylus points captured; a proxy for capture quality.
  final int signaturePointCount;

  /// How a biometric attestation was captured, if one was.
  final BiometricMethod biometricMethod;

  /// Who raised the consent.
  final String createdBy;

  /// Last change, UTC.
  final DateTime updatedAt;

  /// The encounter the consent authorises, when there is one.
  final String? encounterId;

  /// Who signed.
  final String? signerName;

  /// How the signer stands to the patient.
  final SignerRelationship? signerRelationship;

  /// SHA-256 of the captured signature image.
  final String? signatureSha256;

  /// When the signature was captured, UTC.
  final DateTime? signatureCapturedAt;

  /// SHA-256 of the biometric template hash the device reported.
  final String? biometricTemplateSha256;

  /// When the biometric was captured, UTC.
  final DateTime? biometricCapturedAt;

  /// Capture quality, 0–100, when the reader reported one.
  final int? biometricQuality;

  /// Who witnessed the signature.
  final String? witnessedBy;

  /// When the signature was witnessed, UTC.
  final DateTime? witnessedAt;

  /// The vaulted artefact that carries the signature.
  final String? documentId;

  /// When the consent was signed, UTC.
  final DateTime? signedAt;

  /// When the consent lapses, UTC, when the template sets a validity.
  final DateTime? expiresAt;

  /// When the consent was declined, UTC.
  final DateTime? declinedAt;

  /// Why the consent was declined.
  final String? declineReason;

  /// When the consent was revoked, UTC.
  final DateTime? revokedAt;

  /// Why the consent was revoked.
  final String? revocationReason;

  /// When the record was raised, UTC.
  final DateTime? createdAt;

  /// Whether the consent has still to be decided.
  bool get isLive => status.isLive;

  /// Whether the patient has signed.
  bool get isSigned => status.isSigned;

  /// Whether the consent is closed.
  bool get isTerminal => status.isTerminal;

  /// Whether a stylus signature has been captured.
  bool get hasSignature => signatureSha256 != null;
}

/// The change set for capturing attestations on a live consent.
///
/// [advanceTo] carries the stage the capture moves the record to, so a capture
/// that completes a signature also marks the consent as awaiting signature.
Map<String, Object?> consentAttestationChanges({
  String? signatureSha256,
  int? signaturePointCount,
  DateTime? signatureCapturedAt,
  BiometricMethod? biometricMethod,
  String? biometricTemplateSha256,
  DateTime? biometricCapturedAt,
  int? biometricQuality,
  String? witnessedBy,
  DateTime? witnessedAt,
  ConsentStatus? advanceTo,
}) {
  final Map<String, String> fieldErrors = <String, String>{};
  if (signatureSha256 != null && !isSha256Hex(signatureSha256)) {
    fieldErrors['signature_sha256'] = 'Expected a SHA-256 digest.';
  }
  if (biometricTemplateSha256 != null &&
      !isSha256Hex(biometricTemplateSha256)) {
    fieldErrors['biometric_template_sha256'] = 'Expected a SHA-256 digest.';
  }
  if (signaturePointCount != null && signaturePointCount < 0) {
    fieldErrors['signature_point_count'] = 'Expected zero or more.';
  }
  if (biometricQuality != null &&
      (biometricQuality < 0 || biometricQuality > 100)) {
    fieldErrors['biometric_quality'] = 'Expected a value from 0 to 100.';
  }
  if (biometricMethod != null &&
      biometricMethod != BiometricMethod.none &&
      (biometricTemplateSha256 == null || biometricCapturedAt == null)) {
    fieldErrors['biometric_template_sha256'] =
        'A biometric attestation needs a digest and a capture time.';
  }
  if ((witnessedBy == null) != (witnessedAt == null)) {
    fieldErrors['witnessed_by'] = 'A witness is a person and a moment.';
  }
  if (fieldErrors.isNotEmpty) {
    throw ValidationError(
      message: 'Consent record failed validation.',
      fieldErrors: fieldErrors,
      code: 'consent_attestation_invalid',
    );
  }
  return <String, Object?>{
    if (advanceTo != null) 'status': advanceTo.wireValue,
    'signature_sha256': ?signatureSha256,
    'signature_point_count': ?signaturePointCount,
    'signature_captured_at': ?_stamp(signatureCapturedAt),
    if (biometricMethod != null) 'biometric_method': biometricMethod.wireValue,
    'biometric_template_sha256': ?biometricTemplateSha256,
    'biometric_captured_at': ?_stamp(biometricCapturedAt),
    'biometric_quality': ?biometricQuality,
    'witnessed_by': ?_trimmed(witnessedBy),
    'witnessed_at': ?_stamp(witnessedAt),
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  };
}

/// The change set for signing a consent.
Map<String, Object?> consentSignChanges({
  required String signerName,
  required SignerRelationship signerRelationship,
  required String signatureSha256,
  required String documentId,
  DateTime? signedAt,
}) {
  final Map<String, String> fieldErrors = <String, String>{};
  if (signerName.trim().isEmpty) {
    fieldErrors['signer_name'] = 'A signer is required.';
  }
  if (!isSha256Hex(signatureSha256)) {
    fieldErrors['signature_sha256'] = 'Expected a SHA-256 digest.';
  }
  if (documentId.isEmpty) {
    fieldErrors['document_id'] = 'A vaulted document is required.';
  }
  if (fieldErrors.isNotEmpty) {
    throw ValidationError(
      message: 'Consent record failed validation.',
      fieldErrors: fieldErrors,
      code: 'consent_signature_invalid',
    );
  }
  final DateTime at = (signedAt ?? DateTime.now()).toUtc();
  return <String, Object?>{
    'status': ConsentStatus.signed.wireValue,
    'signer_name': signerName.trim(),
    'signer_relationship': signerRelationship.wireValue,
    'signature_sha256': signatureSha256,
    'document_id': documentId,
    'signed_at': at.toIso8601String(),
    'updated_at': at.toIso8601String(),
  };
}

/// The change set for declining a consent.
Map<String, Object?> consentDeclineChanges({required String reason}) {
  if (reason.trim().isEmpty) {
    throw const ValidationError(
      message: 'Consent record failed validation.',
      fieldErrors: <String, String>{'decline_reason': 'A reason is required.'},
      code: 'consent_decline_reason_missing',
    );
  }
  final String now = DateTime.now().toUtc().toIso8601String();
  return <String, Object?>{
    'status': ConsentStatus.declined.wireValue,
    'declined_at': now,
    'decline_reason': reason.trim(),
    'updated_at': now,
  };
}

/// The change set for revoking a signed consent.
Map<String, Object?> consentRevokeChanges({required String reason}) {
  if (reason.trim().isEmpty) {
    throw const ValidationError(
      message: 'Consent record failed validation.',
      fieldErrors: <String, String>{
        'revocation_reason': 'A reason is required.',
      },
      code: 'consent_revocation_reason_missing',
    );
  }
  final String now = DateTime.now().toUtc().toIso8601String();
  return <String, Object?>{
    'status': ConsentStatus.revoked.wireValue,
    'revoked_at': now,
    'revocation_reason': reason.trim(),
    'updated_at': now,
  };
}

/// An artefact indexed in the document vault.
@immutable
final class VaultDocument {
  /// Creates a vault entry.
  const VaultDocument({
    required this.id,
    required this.tenantId,
    required this.kind,
    required this.title,
    required this.bucket,
    required this.objectPath,
    required this.mimeType,
    required this.sizeBytes,
    required this.sha256,
    required this.signatureAlgorithm,
    required this.status,
    required this.issuedBy,
    required this.updatedAt,
    this.patientId,
    this.encounterId,
    this.consentId,
    this.signature,
    this.signingKeyId,
    this.issuedAt,
    this.supersededAt,
    this.supersededBy,
    this.voidedAt,
    this.voidReason,
    this.createdAt,
  });

  /// Validates and builds a new vault row.
  static Map<String, Object?> registerRow({
    required String tenantId,
    required String issuedBy,
    required VaultDocumentKind kind,
    required String title,
    required String bucket,
    required String objectPath,
    required String mimeType,
    required int sizeBytes,
    required String sha256,
    String? patientId,
    String? encounterId,
    String? consentId,
    String? signature,
    SignatureAlgorithm signatureAlgorithm = SignatureAlgorithm.none,
    String? signingKeyId,
    DateTime? issuedAt,
    String documentId = '',
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (issuedBy.isEmpty) {
      fieldErrors['issued_by'] = 'Issuer is required.';
    }
    if (title.trim().isEmpty) {
      fieldErrors['title'] = 'A title is required.';
    }
    if (bucket.trim().isEmpty) {
      fieldErrors['bucket'] = 'A bucket is required.';
    }
    if (objectPath.trim().isEmpty) {
      fieldErrors['object_path'] = 'An object path is required.';
    }
    if (mimeType.trim().isEmpty) {
      fieldErrors['mime_type'] = 'A MIME type is required.';
    }
    if (sizeBytes < 0) {
      fieldErrors['size_bytes'] = 'Expected zero or more.';
    }
    if (!isSha256Hex(sha256)) {
      fieldErrors['sha256'] = 'Expected a SHA-256 digest.';
    }
    if (signature == null && signatureAlgorithm != SignatureAlgorithm.none) {
      fieldErrors['signature'] =
          'An algorithm without a signature attests nothing.';
    }
    if (signature != null &&
        (signatureAlgorithm == SignatureAlgorithm.none ||
            (signingKeyId == null || signingKeyId.trim().isEmpty))) {
      fieldErrors['signing_key_id'] =
          'A detached signature names its algorithm and key.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Vault document failed validation.',
        fieldErrors: fieldErrors,
        code: 'vault_document_invalid',
      );
    }
    final String now = (issuedAt ?? DateTime.now()).toUtc().toIso8601String();
    return <String, Object?>{
      if (documentId.isNotEmpty) 'id': documentId,
      'tenant_id': tenantId,
      'patient_id': _trimmed(patientId),
      'encounter_id': _trimmed(encounterId),
      'consent_id': _trimmed(consentId),
      'kind': kind.wireValue,
      'title': title.trim(),
      'bucket': bucket.trim(),
      'object_path': objectPath.trim(),
      'mime_type': mimeType.trim(),
      'size_bytes': sizeBytes,
      'sha256': sha256,
      'signature': _trimmed(signature),
      'signature_algorithm': signatureAlgorithm.wireValue,
      'signing_key_id': _trimmed(signingKeyId),
      'status': VaultDocumentStatus.issued.wireValue,
      'issued_by': issuedBy,
      'issued_at': now,
      'superseded_at': null,
      'superseded_by': null,
      'voided_at': null,
      'void_reason': null,
      'created_at': now,
      'updated_at': now,
    };
  }

  /// Materializes a vault entry from a local row.
  factory VaultDocument.fromRow(Map<String, Object?> row) => VaultDocument(
    id: row['id']! as String,
    tenantId: row['tenant_id']! as String,
    kind: VaultDocumentKind.fromWire(
      (row['kind'] as String?) ?? VaultDocumentKind.other.wireValue,
    ),
    title: row['title']! as String,
    bucket: row['bucket']! as String,
    objectPath: row['object_path']! as String,
    mimeType: row['mime_type']! as String,
    sizeBytes: _asInt(row['size_bytes']),
    sha256: row['sha256']! as String,
    signatureAlgorithm: SignatureAlgorithm.fromWire(
      (row['signature_algorithm'] as String?) ??
          SignatureAlgorithm.none.wireValue,
    ),
    status: VaultDocumentStatus.fromWire(
      (row['status'] as String?) ?? VaultDocumentStatus.issued.wireValue,
    ),
    issuedBy: row['issued_by']! as String,
    updatedAt: _parse(row['updated_at']),
    patientId: row['patient_id'] as String?,
    encounterId: row['encounter_id'] as String?,
    consentId: row['consent_id'] as String?,
    signature: row['signature'] as String?,
    signingKeyId: row['signing_key_id'] as String?,
    issuedAt: _parseNullable(row['issued_at']),
    supersededAt: _parseNullable(row['superseded_at']),
    supersededBy: row['superseded_by'] as String?,
    voidedAt: _parseNullable(row['voided_at']),
    voidReason: row['void_reason'] as String?,
    createdAt: _parseNullable(row['created_at']),
  );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// What the artefact is.
  final VaultDocumentKind kind;

  /// Display title.
  final String title;

  /// Storage bucket holding the bytes.
  final String bucket;

  /// Path within the bucket, including the tenant segment.
  final String objectPath;

  /// MIME type of the stored object.
  final String mimeType;

  /// Size of the stored object in bytes.
  final int sizeBytes;

  /// Lowercase hexadecimal SHA-256 of the stored bytes.
  final String sha256;

  /// Algorithm the detached signature was produced with.
  final SignatureAlgorithm signatureAlgorithm;

  /// Lifecycle status.
  final VaultDocumentStatus status;

  /// Who issued the entry.
  final String issuedBy;

  /// Last change, UTC.
  final DateTime updatedAt;

  /// The patient the artefact belongs to, when it does.
  final String? patientId;

  /// The encounter the artefact belongs to, when it does.
  final String? encounterId;

  /// The consent the artefact carries, when it does.
  final String? consentId;

  /// The detached signature over the digest, when one was supplied.
  final String? signature;

  /// Identifier of the key that produced the signature.
  final String? signingKeyId;

  /// When the entry was issued, UTC.
  final DateTime? issuedAt;

  /// When the entry was superseded, UTC.
  final DateTime? supersededAt;

  /// The document that replaced this one.
  final String? supersededBy;

  /// When the entry was voided, UTC.
  final DateTime? voidedAt;

  /// Why the entry was voided.
  final String? voidReason;

  /// When the entry was created, UTC.
  final DateTime? createdAt;

  /// Whether the artefact is still current.
  bool get isIssued => status.isIssued;

  /// Whether the artefact is retired.
  bool get isTerminal => status.isTerminal;

  /// Whether a detached signature was recorded.
  bool get isSigned => signature != null;
}

/// The change set for retiring a vault entry.
Map<String, Object?> vaultRetireChanges({
  required VaultDocumentStatus to,
  String? supersededBy,
  String? reason,
  DateTime? at,
}) {
  final String now = (at ?? DateTime.now()).toUtc().toIso8601String();
  switch (to) {
    case VaultDocumentStatus.superseded:
      if (supersededBy == null || supersededBy.isEmpty) {
        throw const ValidationError(
          message: 'Vault document failed validation.',
          fieldErrors: <String, String>{
            'superseded_by': 'A superseded document names its replacement.',
          },
          code: 'vault_supersession_missing',
        );
      }
      return <String, Object?>{
        'status': VaultDocumentStatus.superseded.wireValue,
        'superseded_at': now,
        'superseded_by': supersededBy,
        'updated_at': now,
      };
    case VaultDocumentStatus.voided:
      if (reason == null || reason.trim().isEmpty) {
        throw const ValidationError(
          message: 'Vault document failed validation.',
          fieldErrors: <String, String>{'void_reason': 'A reason is required.'},
          code: 'vault_void_reason_missing',
        );
      }
      return <String, Object?>{
        'status': VaultDocumentStatus.voided.wireValue,
        'voided_at': now,
        'void_reason': reason.trim(),
        'updated_at': now,
      };
    case VaultDocumentStatus.issued:
      throw const ValidationError(
        message: 'Vault document failed validation.',
        fieldErrors: <String, String>{
          'status': 'A retired document is not reinstated.',
        },
        code: 'vault_document_transition_invalid',
      );
  }
}

String? _trimmed(String? value) {
  if (value == null) {
    return null;
  }
  final String trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// Formats an instant for storage, keeping null as null.
String? _stamp(DateTime? value) => value?.toUtc().toIso8601String();

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
