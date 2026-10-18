/// Documents & Biometric E-Consent Vault use cases (Module 33).
library;

import 'package:meta/meta.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/documents/documents.dart';
import 'package:nodex_hms/domain/documents/documents_repository.dart';

/// Publishes a new version of a consent form.
final class RegisterConsentTemplateUseCase {
  /// Creates the use case.
  RegisterConsentTemplateUseCase({required this._repository});

  final DocumentsRepository _repository;

  Future<String> call({
    required AuthorizationPolicy policy,
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
  }) async {
    policy.require(NodexPermissions.documentsManage);
    await _requireFreeVersion(tenantId, code, version, exceptId: templateId);
    return _repository.registerTemplate(
      ConsentTemplate.registerRow(
        tenantId: tenantId,
        createdBy: createdBy,
        code: code,
        title: title,
        bodyText: bodyText,
        version: version,
        procedureCategory: procedureCategory,
        requiresWitness: requiresWitness,
        requiresBiometric: requiresBiometric,
        validityDays: validityDays,
        isActive: isActive,
        templateId: templateId,
      ),
    );
  }

  /// A version number is unique within a tenant and code — the words a patient
  /// signed must not be overwritten by a later draft — so a duplicate version
  /// is refused immediately, offline included.
  Future<void> _requireFreeVersion(
    String tenantId,
    String code,
    int version, {
    required String exceptId,
  }) async {
    final List<ConsentTemplate> templates = await _repository.listTemplates(
      tenantId,
      code: code.trim(),
    );
    for (final ConsentTemplate template in templates) {
      if (template.version == version && template.id != exceptId) {
        throw const ValidationError(
          message: 'Consent template failed validation.',
          fieldErrors: <String, String>{
            'version': 'That version already exists; publish the next one.',
          },
          code: 'consent_template_duplicate',
        );
      }
    }
  }
}

/// Activates or retires a template version.
///
/// A version is never edited or deleted: the words stay as they were when a
/// patient signed them, so retiring it is the only lifecycle change.
final class SetConsentTemplateActiveUseCase {
  /// Creates the use case.
  SetConsentTemplateActiveUseCase({required this._repository});

  final DocumentsRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required ConsentTemplate template,
    required bool isActive,
  }) async {
    policy.require(NodexPermissions.documentsManage);
    if (template.isActive == isActive) {
      throw AuthorizationError(
        message: isActive
            ? 'That version is already active.'
            : 'That version is already retired.',
        code: 'consent_template_unchanged',
      );
    }
    await _repository.updateTemplate(
      template.id,
      consentTemplateActiveChanges(isActive: isActive),
    );
  }
}

/// Raises a consent for a patient against a template version.
final class RaiseConsentUseCase {
  /// Creates the use case.
  RaiseConsentUseCase({required this._repository});

  final DocumentsRepository _repository;

  Future<String> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String patientId,
    required String facilityId,
    required String templateId,
    required String procedureText,
    required String createdBy,
    String? encounterId,
    DateTime? now,
    String consentId = '',
  }) async {
    policy.require(NodexPermissions.documentsConsent);
    final ConsentTemplate? template = await _repository.templateById(
      templateId,
    );
    if (template == null) {
      throw const ValidationError(
        message: 'Consent record failed validation.',
        fieldErrors: <String, String>{
          'template_id': 'That consent template does not exist.',
        },
        code: 'consent_template_missing',
      );
    }
    if (!template.isActive) {
      throw const ValidationError(
        message: 'Consent record failed validation.',
        fieldErrors: <String, String>{
          'template_id': 'That version is retired; choose a current one.',
        },
        code: 'consent_template_retired',
      );
    }
    await _requireNoLiveConsent(tenantId, patientId, templateId);
    return _repository.registerConsent(
      ConsentRecord.registerRow(
        tenantId: tenantId,
        patientId: patientId,
        facilityId: facilityId,
        templateId: templateId,
        procedureText: procedureText,
        createdBy: createdBy,
        encounterId: encounterId,
        validityDays: template.validityDays,
        now: now,
        consentId: consentId,
      ),
    );
  }

  /// One live consent per patient and template version: two open forms for the
  /// same procedure are two answers to one question.
  Future<void> _requireNoLiveConsent(
    String tenantId,
    String patientId,
    String templateId,
  ) async {
    final List<ConsentRecord> existing = await _repository.listConsents(
      tenantId,
      patientId: patientId,
      templateId: templateId,
    );
    for (final ConsentRecord record in existing) {
      if (record.isLive) {
        throw const ValidationError(
          message: 'Consent record failed validation.',
          fieldErrors: <String, String>{
            'template_id': 'That patient already has an open consent.',
          },
          code: 'consent_record_duplicate',
        );
      }
    }
  }
}

/// Records a stylus signature, a biometric attestation or a witness on a live
/// consent.
///
/// A capture that produces a signature moves a drafted consent to awaiting
/// signature, which is the state the ward works from.
final class CaptureConsentAttestationUseCase {
  /// Creates the use case.
  CaptureConsentAttestationUseCase({required this._repository});

  final DocumentsRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required ConsentRecord consent,
    String? signatureSha256,
    int? signaturePointCount,
    DateTime? signatureCapturedAt,
    BiometricMethod? biometricMethod,
    String? biometricTemplateSha256,
    DateTime? biometricCapturedAt,
    int? biometricQuality,
    String? witnessedBy,
    DateTime? witnessedAt,
  }) async {
    policy.require(NodexPermissions.documentsConsent);
    if (!consent.isLive) {
      throw AuthorizationError(
        message: consent.isSigned
            ? 'A signed consent accepts no further capture.'
            : 'This consent is closed and accepts no further capture.',
        code: 'consent_record_not_live',
      );
    }
    final ConsentStatus? advanceTo =
        consent.status == ConsentStatus.drafted && signatureSha256 != null
        ? ConsentStatus.awaitingSignature
        : null;
    await _repository.updateConsent(
      consent.id,
      consentAttestationChanges(
        signatureSha256: signatureSha256,
        signaturePointCount: signaturePointCount,
        signatureCapturedAt: signatureCapturedAt,
        biometricMethod: biometricMethod,
        biometricTemplateSha256: biometricTemplateSha256,
        biometricCapturedAt: biometricCapturedAt,
        biometricQuality: biometricQuality,
        witnessedBy: witnessedBy,
        witnessedAt: witnessedAt,
        advanceTo: advanceTo,
      ),
    );
  }
}

/// Signs a consent against a vaulted artefact.
///
/// Everything the template requires must be captured first: the signature, the
/// biometric and the witness where they are mandatory, and the artefact that
/// carries the signature.
final class SignConsentUseCase {
  /// Creates the use case.
  SignConsentUseCase({required this._repository});

  final DocumentsRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required ConsentRecord consent,
    required String documentId,
    required String signerName,
    required SignerRelationship signerRelationship,
    DateTime? signedAt,
  }) async {
    policy.require(NodexPermissions.documentsConsent);
    if (!consentCanTransition(consent.status, ConsentStatus.signed)) {
      throw AuthorizationError(
        message:
            'A consent at ${consent.status.label.toLowerCase()} '
            'cannot be signed.',
        code: 'consent_record_transition_invalid',
      );
    }
    final ConsentTemplate? template = await _repository.templateById(
      consent.templateId,
    );
    if (template == null) {
      throw const ValidationError(
        message: 'Consent record failed validation.',
        fieldErrors: <String, String>{
          'template_id': 'The template version has not reached this device.',
        },
        code: 'consent_template_missing',
      );
    }
    final VaultDocument? document = await _repository.documentById(documentId);
    if (document == null) {
      throw const ValidationError(
        message: 'Consent record failed validation.',
        fieldErrors: <String, String>{
          'document_id': 'That vaulted document does not exist.',
        },
        code: 'vault_document_missing',
      );
    }
    if (!document.isIssued) {
      throw const ValidationError(
        message: 'Consent record failed validation.',
        fieldErrors: <String, String>{
          'document_id': 'That vaulted document has been retired.',
        },
        code: 'vault_document_not_issued',
      );
    }
    if (document.kind != VaultDocumentKind.consentSignature &&
        document.kind != VaultDocumentKind.consentForm) {
      throw const ValidationError(
        message: 'Consent record failed validation.',
        fieldErrors: <String, String>{
          'document_id': 'A consent is signed against its form or capture.',
        },
        code: 'vault_document_kind_mismatch',
      );
    }
    if (document.sha256 != consent.signatureSha256) {
      throw const ValidationError(
        message: 'Consent record failed validation.',
        fieldErrors: <String, String>{
          'document_id': 'That artefact does not carry this signature.',
        },
        code: 'vault_document_digest_mismatch',
      );
    }
    final Set<ConsentAttestation> missing = missingConsentAttestations(
      template: template,
      record: consent,
    );
    // The artefact is the one passed in and has just been checked, so it is no
    // longer outstanding even though the row does not carry it yet.
    missing.remove(ConsentAttestation.document);
    if (missing.isNotEmpty) {
      throw ValidationError(
        message: 'Consent record failed validation.',
        fieldErrors: <String, String>{
          'status':
              'Still to capture: '
              '${missing.map((ConsentAttestation a) => a.label).join(', ')}.',
        },
        code: 'consent_attestation_missing',
      );
    }
    await _repository.updateConsent(
      consent.id,
      consentSignChanges(
        signerName: signerName,
        signerRelationship: signerRelationship,
        signatureSha256: consent.signatureSha256!,
        documentId: documentId,
        signedAt: signedAt,
      ),
    );
  }
}

/// Records that the patient declined a consent.
final class DeclineConsentUseCase {
  /// Creates the use case.
  DeclineConsentUseCase({required this._repository});

  final DocumentsRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required ConsentRecord consent,
    required String reason,
  }) async {
    policy.require(NodexPermissions.documentsConsent);
    if (!consentCanTransition(consent.status, ConsentStatus.declined)) {
      throw AuthorizationError(
        message: consent.isSigned
            ? 'A signed consent is revoked, not declined.'
            : 'This consent is already closed.',
        code: 'consent_record_transition_invalid',
      );
    }
    await _repository.updateConsent(
      consent.id,
      consentDeclineChanges(reason: reason),
    );
  }
}

/// Withdraws a signed consent. Revocation is one-way and freezes the record.
final class RevokeConsentUseCase {
  /// Creates the use case.
  RevokeConsentUseCase({required this._repository});

  final DocumentsRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required ConsentRecord consent,
    required String reason,
  }) async {
    policy.require(NodexPermissions.documentsConsent);
    if (!consentCanTransition(consent.status, ConsentStatus.revoked)) {
      throw AuthorizationError(
        message: consent.isSigned
            ? 'This consent is already revoked.'
            : 'Only a signed consent can be revoked.',
        code: 'consent_record_transition_invalid',
      );
    }
    await _repository.updateConsent(
      consent.id,
      consentRevokeChanges(reason: reason),
    );
  }
}

/// Indexes an artefact in the document vault.
final class RegisterVaultDocumentUseCase {
  /// Creates the use case.
  RegisterVaultDocumentUseCase({required this._repository});

  final DocumentsRepository _repository;

  Future<String> call({
    required AuthorizationPolicy policy,
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
  }) async {
    policy.require(NodexPermissions.documentsVault);
    await _requireFreePath(tenantId, objectPath, exceptId: documentId);
    return _repository.registerDocument(
      VaultDocument.registerRow(
        tenantId: tenantId,
        issuedBy: issuedBy,
        kind: kind,
        title: title,
        bucket: bucket,
        objectPath: objectPath,
        mimeType: mimeType,
        sizeBytes: sizeBytes,
        sha256: sha256,
        patientId: patientId,
        encounterId: encounterId,
        consentId: consentId,
        signature: signature,
        signatureAlgorithm: signatureAlgorithm,
        signingKeyId: signingKeyId,
        issuedAt: issuedAt,
        documentId: documentId,
      ),
    );
  }

  /// One artefact per object path: a path is a location, not a version.
  Future<void> _requireFreePath(
    String tenantId,
    String objectPath, {
    required String exceptId,
  }) async {
    final List<VaultDocument> documents = await _repository.listDocuments(
      tenantId,
    );
    for (final VaultDocument document in documents) {
      if (document.objectPath == objectPath.trim() && document.id != exceptId) {
        throw const ValidationError(
          message: 'Vault document failed validation.',
          fieldErrors: <String, String>{
            'object_path': 'That object path is already indexed.',
          },
          code: 'vault_document_duplicate',
        );
      }
    }
  }
}

/// Supersedes or voids a vault entry. Both endings are one-way.
final class RetireVaultDocumentUseCase {
  /// Creates the use case.
  RetireVaultDocumentUseCase({required this._repository});

  final DocumentsRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required VaultDocument document,
    required VaultDocumentStatus to,
    String? supersededBy,
    String? reason,
  }) async {
    policy.require(NodexPermissions.documentsVault);
    if (!documentCanTransition(document.status, to)) {
      throw AuthorizationError(
        message:
            'A document that is ${document.status.label.toLowerCase()} '
            'cannot become ${to.label.toLowerCase()}.',
        code: 'vault_document_transition_invalid',
      );
    }
    await _repository.updateDocument(
      document.id,
      vaultRetireChanges(to: to, supersededBy: supersededBy, reason: reason),
    );
  }
}

/// A consent as the board shows it: where it stands, what it still needs.
@immutable
final class ConsentBoardEntry {
  /// Creates a board row.
  const ConsentBoardEntry({
    required this.consent,
    required this.validity,
    required this.missing,
    this.template,
  });

  /// The consent record.
  final ConsentRecord consent;

  /// Where the consent stands, derived from its status and expiry.
  final ConsentValidity validity;

  /// What is still to be captured before it may be signed.
  final Set<ConsentAttestation> missing;

  /// The template version the patient was shown, when it is on this device.
  final ConsentTemplate? template;

  /// Whether the consent needs an attention marker.
  bool get needsAttention => validity.needsAttention;
}

/// Reads the consent board, the template catalogue and the vault index.
final class ReadConsentVaultUseCase {
  /// Creates the use case.
  ReadConsentVaultUseCase({required this._repository});

  final DocumentsRepository _repository;

  /// The template catalogue, by code and version.
  Future<List<ConsentTemplate>> templates({
    required AuthorizationPolicy policy,
    required String tenantId,
    String? code,
    bool includeRetired = true,
  }) async {
    policy.require(NodexPermissions.documentsRead);
    final List<ConsentTemplate> templates = await _repository.listTemplates(
      tenantId,
      code: code,
    );
    return templates
        .where(
          (ConsentTemplate template) => includeRetired || template.isActive,
        )
        .toList(growable: false);
  }

  /// Consent records, newest first.
  Future<List<ConsentRecord>> consents({
    required AuthorizationPolicy policy,
    required String tenantId,
    String? patientId,
    String? templateId,
    ConsentStatus? status,
    bool includeClosed = true,
  }) async {
    policy.require(NodexPermissions.documentsRead);
    final List<ConsentRecord> consents = await _repository.listConsents(
      tenantId,
      patientId: patientId,
      templateId: templateId,
      status: status?.wireValue,
    );
    return consents
        .where(
          (ConsentRecord consent) =>
              includeClosed || consent.isLive || consent.isSigned,
        )
        .toList(growable: false);
  }

  /// Vault entries, newest first.
  Future<List<VaultDocument>> documents({
    required AuthorizationPolicy policy,
    required String tenantId,
    String? patientId,
    String? consentId,
    VaultDocumentKind? kind,
    bool includeRetired = true,
  }) async {
    policy.require(NodexPermissions.documentsRead);
    final List<VaultDocument> documents = await _repository.listDocuments(
      tenantId,
      patientId: patientId,
      consentId: consentId,
      kind: kind?.wireValue,
    );
    return documents
        .where((VaultDocument document) => includeRetired || document.isIssued)
        .toList(growable: false);
  }

  /// The consent board: every consent with its derived validity and what it
  /// still needs, most needing attention first.
  Future<List<ConsentBoardEntry>> board({
    required AuthorizationPolicy policy,
    required String tenantId,
    String? patientId,
    DateTime? now,
  }) async {
    policy.require(NodexPermissions.documentsRead);
    final DateTime asOf = (now ?? DateTime.now().toUtc()).toUtc();
    final List<ConsentRecord> consents = await _repository.listConsents(
      tenantId,
      patientId: patientId,
    );
    final List<ConsentTemplate> templates = await _repository.listTemplates(
      tenantId,
    );
    final Map<String, ConsentTemplate> templateById = <String, ConsentTemplate>{
      for (final ConsentTemplate template in templates) template.id: template,
    };

    final List<ConsentBoardEntry> board = <ConsentBoardEntry>[];
    for (final ConsentRecord consent in consents) {
      final ConsentTemplate? template = templateById[consent.templateId];
      board.add(
        ConsentBoardEntry(
          consent: consent,
          validity: consentValidity(
            status: consent.status,
            expiresAt: consent.expiresAt,
            now: asOf,
          ),
          // With no template on the device the requirements cannot be known, so
          // only the two unconditional attestations are reported as missing.
          missing: missingConsentAttestations(
            template: template,
            record: consent,
          ),
          template: template,
        ),
      );
    }
    board.sort((ConsentBoardEntry a, ConsentBoardEntry b) {
      final int rank = _validityRank(a.validity) - _validityRank(b.validity);
      if (rank != 0) {
        return rank;
      }
      return b.consent.id.compareTo(a.consent.id);
    });
    return board;
  }

  static int _validityRank(ConsentValidity validity) => switch (validity) {
    ConsentValidity.expired => 0,
    ConsentValidity.awaitingSignature => 1,
    ConsentValidity.pending => 2,
    ConsentValidity.signed => 3,
    ConsentValidity.declined => 4,
    ConsentValidity.revoked => 5,
  };
}
