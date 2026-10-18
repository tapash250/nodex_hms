/// Tests for the consent use cases, the derived validity, the missing
/// attestations and the consent and vault state machines (Module 33).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/authorization_snapshot.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/domain/documents/documents.dart';
import 'package:nodex_hms/domain/documents/documents_repository.dart';
import 'package:nodex_hms/domain/documents/documents_use_cases.dart';

import 'documents_repository_test.dart' show FakeDocumentsStore;

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
      facilityIds: const <String>{'facility-1'},
      departmentIds: const <String>{},
      wardIds: const <String>{},
    ),
    connectivity: ConnectivityState.online,
  );
}

/// A 64-character hexadecimal digest of one repeated character.
String hex(String character) => List<String>.filled(64, character).join();

void main() {
  late FakeDocumentsStore store;
  late DefaultDocumentsRepository repository;
  late RegisterConsentTemplateUseCase registerTemplate;
  late SetConsentTemplateActiveUseCase setTemplateActive;
  late RaiseConsentUseCase raiseConsent;
  late CaptureConsentAttestationUseCase captureAttestation;
  late SignConsentUseCase signConsent;
  late DeclineConsentUseCase declineConsent;
  late RevokeConsentUseCase revokeConsent;
  late RegisterVaultDocumentUseCase registerDocument;
  late RetireVaultDocumentUseCase retireDocument;
  late ReadConsentVaultUseCase readConsentVault;

  const Set<String> canManage = <String>{NodexPermissions.documentsManage};
  const Set<String> canConsent = <String>{NodexPermissions.documentsConsent};
  const Set<String> canVault = <String>{NodexPermissions.documentsVault};
  const Set<String> canRead = <String>{NodexPermissions.documentsRead};

  final DateTime now = DateTime.utc(2026, 6, 1);

  setUp(() {
    store = FakeDocumentsStore();
    repository = DefaultDocumentsRepository(
      store: store,
      logger: NodexLogger(
        sinks: <NodexLogSink>[InMemoryLogSink()],
        minimumLevel: NodexLogLevel.trace,
      ),
    );
    registerTemplate = RegisterConsentTemplateUseCase(repository: repository);
    setTemplateActive = SetConsentTemplateActiveUseCase(repository: repository);
    raiseConsent = RaiseConsentUseCase(repository: repository);
    captureAttestation = CaptureConsentAttestationUseCase(
      repository: repository,
    );
    signConsent = SignConsentUseCase(repository: repository);
    declineConsent = DeclineConsentUseCase(repository: repository);
    revokeConsent = RevokeConsentUseCase(repository: repository);
    registerDocument = RegisterVaultDocumentUseCase(repository: repository);
    retireDocument = RetireVaultDocumentUseCase(repository: repository);
    readConsentVault = ReadConsentVaultUseCase(repository: repository);
  });

  Future<ConsentTemplate> aTemplate({
    String code = 'SURG-1',
    int version = 1,
    bool requiresWitness = true,
    bool requiresBiometric = false,
    int? validityDays = 30,
    bool isActive = true,
  }) async {
    final String id = await registerTemplate(
      policy: policyWith(canManage),
      tenantId: 'tenant-1',
      createdBy: 'user-1',
      code: code,
      title: 'Laparotomy consent',
      bodyText: 'I consent to the procedure described to me.',
      version: version,
      requiresWitness: requiresWitness,
      requiresBiometric: requiresBiometric,
      validityDays: validityDays,
      isActive: isActive,
    );
    return (await repository.templateById(id))!;
  }

  Future<ConsentRecord> aConsent({
    String? templateId,
    String procedureText = 'Laparotomy',
  }) async {
    final String template = templateId ?? (await aTemplate()).id;
    final String id = await raiseConsent(
      policy: policyWith(canConsent),
      tenantId: 'tenant-1',
      patientId: 'patient-1',
      facilityId: 'facility-1',
      templateId: template,
      procedureText: procedureText,
      createdBy: 'user-1',
      now: now,
    );
    return (await repository.consentById(id))!;
  }

  Future<VaultDocument> aDocument({
    String objectPath = 'tenant-1/consent/png-1',
    String? sha256,
    VaultDocumentKind kind = VaultDocumentKind.consentSignature,
    String? signature,
    SignatureAlgorithm algorithm = SignatureAlgorithm.none,
    String? keyId,
  }) async {
    final String id = await registerDocument(
      policy: policyWith(canVault),
      tenantId: 'tenant-1',
      issuedBy: 'user-1',
      kind: kind,
      title: 'Signature capture',
      bucket: 'clinical-signatures',
      objectPath: objectPath,
      mimeType: 'image/png',
      sizeBytes: 2048,
      sha256: sha256 ?? hex('a'),
      patientId: 'patient-1',
      consentId: 'consent-1',
      signature: signature,
      signatureAlgorithm: algorithm,
      signingKeyId: keyId,
    );
    return (await repository.documentById(id))!;
  }

  /// Captures a signature and a witness, then vaults the artefact the signature
  /// digest names, returning the signed-ready consent and its document.
  Future<(ConsentRecord, VaultDocument)> readyToSign(
    ConsentRecord consent,
  ) async {
    await captureAttestation(
      policy: policyWith(canConsent),
      consent: consent,
      signatureSha256: hex('c'),
      signaturePointCount: 88,
      signatureCapturedAt: now,
      witnessedBy: 'user-1',
      witnessedAt: now,
    );
    final VaultDocument document = await aDocument(sha256: hex('c'));
    final ConsentRecord refreshed = (await repository.consentById(consent.id))!;
    return (refreshed, document);
  }

  group('template versions', () {
    test('publishes a version and resolves it', () async {
      final ConsentTemplate template = await aTemplate();
      expect(template.code, 'SURG-1');
      expect(template.version, 1);
      expect(template.isActive, isTrue);
      expect(template.requiresWitness, isTrue);
    });

    test('refuses a duplicate version of the same code', () async {
      await aTemplate(version: 1);
      await expectLater(
        aTemplate(version: 1),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'consent_template_duplicate',
          ),
        ),
      );
    });

    test('allows the next version of the same code', () async {
      await aTemplate(version: 1);
      final ConsentTemplate second = await aTemplate(version: 2);
      expect(second.version, 2);
    });

    test('validates the text and the version number', () async {
      await expectLater(
        registerTemplate(
          policy: policyWith(canManage),
          tenantId: 'tenant-1',
          createdBy: 'user-1',
          code: 'SURG-2',
          title: 'Consent',
          bodyText: '   ',
          version: 0,
        ),
        throwsA(isA<ValidationError>()),
      );
    });

    test('refuses a writer without the manage tier', () async {
      await expectLater(
        registerTemplate(
          policy: policyWith(canConsent),
          tenantId: 'tenant-1',
          createdBy: 'user-1',
          code: 'SURG-3',
          title: 'Consent',
          bodyText: 'Text',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('retires a version without touching its text', () async {
      final ConsentTemplate template = await aTemplate();
      await setTemplateActive(
        policy: policyWith(canManage),
        template: template,
        isActive: false,
      );
      final ConsentTemplate retired = (await repository.templateById(
        template.id,
      ))!;
      expect(retired.isActive, isFalse);
      expect(retired.bodyText, template.bodyText);
    });

    test('refuses a retirement that changes nothing', () async {
      final ConsentTemplate template = await aTemplate();
      await expectLater(
        setTemplateActive(
          policy: policyWith(canManage),
          template: template,
          isActive: true,
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });
  });

  group('raising a consent', () {
    test('raises against an active version and fixes the expiry', () async {
      final ConsentRecord consent = await aConsent();
      expect(consent.status, ConsentStatus.drafted);
      expect(consent.isLive, isTrue);
      expect(consent.expiresAt, DateTime.utc(2026, 7, 1));
      expect(consent.hasSignature, isFalse);
    });

    test('refuses a consent against a retired version', () async {
      final ConsentTemplate template = await aTemplate(isActive: false);
      await expectLater(
        raiseConsent(
          policy: policyWith(canConsent),
          tenantId: 'tenant-1',
          patientId: 'patient-1',
          facilityId: 'facility-1',
          templateId: template.id,
          procedureText: 'Laparotomy',
          createdBy: 'user-1',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'consent_template_retired',
          ),
        ),
      );
    });

    test('refuses a template that is not on this device', () async {
      await expectLater(
        raiseConsent(
          policy: policyWith(canConsent),
          tenantId: 'tenant-1',
          patientId: 'patient-1',
          facilityId: 'facility-1',
          templateId: 'missing',
          procedureText: 'Laparotomy',
          createdBy: 'user-1',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'consent_template_missing',
          ),
        ),
      );
    });

    test('refuses a second open consent for the same template', () async {
      final ConsentTemplate template = await aTemplate();
      await aConsent(templateId: template.id);
      await expectLater(
        aConsent(templateId: template.id),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'consent_record_duplicate',
          ),
        ),
      );
    });

    test('allows a new consent once the first is closed', () async {
      final ConsentTemplate template = await aTemplate();
      final ConsentRecord first = await aConsent(templateId: template.id);
      await declineConsent(
        policy: policyWith(canConsent),
        consent: first,
        reason: 'Patient changed their mind',
      );
      final ConsentRecord second = await aConsent(templateId: template.id);
      expect(second.isLive, isTrue);
    });
  });

  group('capturing attestations', () {
    test('a signature moves a drafted consent to awaiting signature', () async {
      final ConsentRecord consent = await aConsent();
      await captureAttestation(
        policy: policyWith(canConsent),
        consent: consent,
        signatureSha256: hex('c'),
        signaturePointCount: 120,
        signatureCapturedAt: now,
      );
      final ConsentRecord captured = (await repository.consentById(
        consent.id,
      ))!;
      expect(captured.status, ConsentStatus.awaitingSignature);
      expect(captured.hasSignature, isTrue);
      expect(captured.signaturePointCount, 120);
    });

    test('a witness alone leaves the consent drafted', () async {
      final ConsentRecord consent = await aConsent();
      await captureAttestation(
        policy: policyWith(canConsent),
        consent: consent,
        witnessedBy: 'user-2',
        witnessedAt: now,
      );
      final ConsentRecord captured = (await repository.consentById(
        consent.id,
      ))!;
      expect(captured.status, ConsentStatus.drafted);
      expect(captured.witnessedBy, 'user-2');
    });

    test('refuses a capture on a signed consent', () async {
      final (ConsentRecord consent, VaultDocument document) = await readyToSign(
        await aConsent(),
      );
      await signConsent(
        policy: policyWith(canConsent),
        consent: consent,
        documentId: document.id,
        signerName: 'Rahim',
        signerRelationship: SignerRelationship.patient,
      );
      final ConsentRecord signed = (await repository.consentById(consent.id))!;
      await expectLater(
        captureAttestation(
          policy: policyWith(canConsent),
          consent: signed,
          witnessedBy: 'user-3',
          witnessedAt: now,
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('refuses a malformed digest', () async {
      final ConsentRecord consent = await aConsent();
      await expectLater(
        captureAttestation(
          policy: policyWith(canConsent),
          consent: consent,
          signatureSha256: 'not-a-digest',
          signatureCapturedAt: now,
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'consent_attestation_invalid',
          ),
        ),
      );
    });

    test('refuses a biometric method without a digest and a time', () async {
      final ConsentRecord consent = await aConsent();
      await expectLater(
        captureAttestation(
          policy: policyWith(canConsent),
          consent: consent,
          biometricMethod: BiometricMethod.thumbprint,
        ),
        throwsA(isA<ValidationError>()),
      );
    });

    test('refuses a witness that is not a person and a moment', () async {
      final ConsentRecord consent = await aConsent();
      await expectLater(
        captureAttestation(
          policy: policyWith(canConsent),
          consent: consent,
          witnessedBy: 'user-2',
        ),
        throwsA(isA<ValidationError>()),
      );
    });
  });

  group('signing', () {
    test(
      'signs once the signature, witness and artefact are present',
      () async {
        final (ConsentRecord consent, VaultDocument document) =
            await readyToSign(await aConsent());
        await signConsent(
          policy: policyWith(canConsent),
          consent: consent,
          documentId: document.id,
          signerName: 'Rahim',
          signerRelationship: SignerRelationship.patient,
          signedAt: now,
        );
        final ConsentRecord signed = (await repository.consentById(
          consent.id,
        ))!;
        expect(signed.status, ConsentStatus.signed);
        expect(signed.signerName, 'Rahim');
        expect(signed.signerRelationship, SignerRelationship.patient);
        expect(signed.documentId, document.id);
        expect(signed.signedAt, now);
      },
    );

    test('refuses an artefact carrying a different digest', () async {
      final ConsentRecord consent = await aConsent();
      await captureAttestation(
        policy: policyWith(canConsent),
        consent: consent,
        signatureSha256: hex('c'),
        signatureCapturedAt: now,
        witnessedBy: 'user-1',
        witnessedAt: now,
      );
      final VaultDocument other = await aDocument(
        objectPath: 'tenant-1/consent/png-2',
        sha256: hex('d'),
      );
      final ConsentRecord refreshed = (await repository.consentById(
        consent.id,
      ))!;
      await expectLater(
        signConsent(
          policy: policyWith(canConsent),
          consent: refreshed,
          documentId: other.id,
          signerName: 'Rahim',
          signerRelationship: SignerRelationship.patient,
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'vault_document_digest_mismatch',
          ),
        ),
      );
    });

    test('refuses an artefact of the wrong kind', () async {
      final ConsentRecord consent = await aConsent();
      await captureAttestation(
        policy: policyWith(canConsent),
        consent: consent,
        signatureSha256: hex('c'),
        signatureCapturedAt: now,
        witnessedBy: 'user-1',
        witnessedAt: now,
      );
      final VaultDocument report = await aDocument(
        sha256: hex('c'),
        kind: VaultDocumentKind.report,
      );
      final ConsentRecord refreshed = (await repository.consentById(
        consent.id,
      ))!;
      await expectLater(
        signConsent(
          policy: policyWith(canConsent),
          consent: refreshed,
          documentId: report.id,
          signerName: 'Rahim',
          signerRelationship: SignerRelationship.patient,
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'vault_document_kind_mismatch',
          ),
        ),
      );
    });

    test('refuses an artefact that does not exist', () async {
      final ConsentRecord consent = await aConsent();
      await expectLater(
        signConsent(
          policy: policyWith(canConsent),
          consent: consent,
          documentId: 'missing',
          signerName: 'Rahim',
          signerRelationship: SignerRelationship.patient,
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'vault_document_missing',
          ),
        ),
      );
    });

    test('refuses a signed consent with a missing witness', () async {
      final ConsentRecord consent = await aConsent();
      await captureAttestation(
        policy: policyWith(canConsent),
        consent: consent,
        signatureSha256: hex('c'),
        signatureCapturedAt: now,
      );
      final VaultDocument document = await aDocument(sha256: hex('c'));
      final ConsentRecord refreshed = (await repository.consentById(
        consent.id,
      ))!;
      await expectLater(
        signConsent(
          policy: policyWith(canConsent),
          consent: refreshed,
          documentId: document.id,
          signerName: 'Rahim',
          signerRelationship: SignerRelationship.patient,
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'consent_attestation_missing',
          ),
        ),
      );
    });

    test('refuses a signed consent whose template wants a biometric', () async {
      final ConsentTemplate template = await aTemplate(
        requiresBiometric: true,
        requiresWitness: false,
      );
      final ConsentRecord consent = await aConsent(templateId: template.id);
      await captureAttestation(
        policy: policyWith(canConsent),
        consent: consent,
        signatureSha256: hex('c'),
        signatureCapturedAt: now,
      );
      final VaultDocument document = await aDocument(sha256: hex('c'));
      final ConsentRecord refreshed = (await repository.consentById(
        consent.id,
      ))!;
      await expectLater(
        signConsent(
          policy: policyWith(canConsent),
          consent: refreshed,
          documentId: document.id,
          signerName: 'Rahim',
          signerRelationship: SignerRelationship.patient,
        ),
        throwsA(isA<ValidationError>()),
      );
    });

    test('a biometric capture unblocks the signature', () async {
      final ConsentTemplate template = await aTemplate(
        requiresBiometric: true,
        requiresWitness: false,
      );
      final ConsentRecord consent = await aConsent(templateId: template.id);
      await captureAttestation(
        policy: policyWith(canConsent),
        consent: consent,
        signatureSha256: hex('c'),
        signatureCapturedAt: now,
      );
      final ConsentRecord withSignature = (await repository.consentById(
        consent.id,
      ))!;
      await captureAttestation(
        policy: policyWith(canConsent),
        consent: withSignature,
        biometricMethod: BiometricMethod.thumbprint,
        biometricTemplateSha256: hex('e'),
        biometricCapturedAt: now,
        biometricQuality: 91,
      );
      final VaultDocument document = await aDocument(sha256: hex('c'));
      final ConsentRecord ready = (await repository.consentById(consent.id))!;
      await signConsent(
        policy: policyWith(canConsent),
        consent: ready,
        documentId: document.id,
        signerName: 'Rahim',
        signerRelationship: SignerRelationship.guardian,
      );
      final ConsentRecord signed = (await repository.consentById(consent.id))!;
      expect(signed.status, ConsentStatus.signed);
      expect(signed.biometricMethod, BiometricMethod.thumbprint);
      expect(signed.biometricQuality, 91);
      expect(signed.signerRelationship, SignerRelationship.guardian);
    });

    test('refuses to sign a consent that was declined', () async {
      final ConsentRecord consent = await aConsent();
      await declineConsent(
        policy: policyWith(canConsent),
        consent: consent,
        reason: 'The patient refused',
      );
      final ConsentRecord declined = (await repository.consentById(
        consent.id,
      ))!;
      await expectLater(
        signConsent(
          policy: policyWith(canConsent),
          consent: declined,
          documentId: 'doc',
          signerName: 'Rahim',
          signerRelationship: SignerRelationship.patient,
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });
  });

  group('declining and revoking', () {
    test('declines with a reason', () async {
      final ConsentRecord consent = await aConsent();
      await declineConsent(
        policy: policyWith(canConsent),
        consent: consent,
        reason: 'The patient refused',
      );
      final ConsentRecord declined = (await repository.consentById(
        consent.id,
      ))!;
      expect(declined.status, ConsentStatus.declined);
      expect(declined.declineReason, 'The patient refused');
      expect(declined.isTerminal, isTrue);
    });

    test('refuses a decline without a reason', () async {
      final ConsentRecord consent = await aConsent();
      await expectLater(
        declineConsent(
          policy: policyWith(canConsent),
          consent: consent,
          reason: '  ',
        ),
        throwsA(isA<ValidationError>()),
      );
    });

    test('a signed consent is revoked, not declined', () async {
      final (ConsentRecord consent, VaultDocument document) = await readyToSign(
        await aConsent(),
      );
      await signConsent(
        policy: policyWith(canConsent),
        consent: consent,
        documentId: document.id,
        signerName: 'Rahim',
        signerRelationship: SignerRelationship.patient,
      );
      final ConsentRecord signed = (await repository.consentById(consent.id))!;
      await expectLater(
        declineConsent(
          policy: policyWith(canConsent),
          consent: signed,
          reason: 'Too late',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('revokes a signed consent one way', () async {
      final (ConsentRecord consent, VaultDocument document) = await readyToSign(
        await aConsent(),
      );
      await signConsent(
        policy: policyWith(canConsent),
        consent: consent,
        documentId: document.id,
        signerName: 'Rahim',
        signerRelationship: SignerRelationship.patient,
      );
      final ConsentRecord signed = (await repository.consentById(consent.id))!;
      await revokeConsent(
        policy: policyWith(canConsent),
        consent: signed,
        reason: 'Procedure cancelled',
      );
      final ConsentRecord revoked = (await repository.consentById(consent.id))!;
      expect(revoked.status, ConsentStatus.revoked);
      expect(revoked.revocationReason, 'Procedure cancelled');
      expect(revoked.isTerminal, isTrue);

      await expectLater(
        captureAttestation(
          policy: policyWith(canConsent),
          consent: revoked,
          witnessedBy: 'user-9',
          witnessedAt: now,
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('refuses to revoke an unsigned consent', () async {
      final ConsentRecord consent = await aConsent();
      await expectLater(
        revokeConsent(
          policy: policyWith(canConsent),
          consent: consent,
          reason: 'Not yet signed',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });
  });

  group('the vault index', () {
    test('records a digest and rejects a duplicate path', () async {
      final VaultDocument document = await aDocument();
      expect(document.sha256, hex('a'));
      expect(document.isIssued, isTrue);
      await expectLater(
        aDocument(),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'vault_document_duplicate',
          ),
        ),
      );
    });

    test('records a detached signature as a coherent triple', () async {
      final VaultDocument document = await aDocument(
        signature: 'c2ln',
        algorithm: SignatureAlgorithm.ed25519,
        keyId: 'key-1',
      );
      expect(document.isSigned, isTrue);
      expect(document.signatureAlgorithm, SignatureAlgorithm.ed25519);
      expect(document.signingKeyId, 'key-1');
    });

    test('refuses an algorithm without a signature', () async {
      await expectLater(
        aDocument(algorithm: SignatureAlgorithm.hmacSha256),
        throwsA(isA<ValidationError>()),
      );
    });

    test('refuses a signature without an algorithm and key', () async {
      await expectLater(
        aDocument(signature: 'c2ln'),
        throwsA(isA<ValidationError>()),
      );
    });

    test('refuses a malformed digest', () async {
      await expectLater(
        aDocument(sha256: 'abc'),
        throwsA(isA<ValidationError>()),
      );
    });

    test('supersedes a document with its replacement', () async {
      final VaultDocument first = await aDocument();
      final VaultDocument second = await aDocument(
        objectPath: 'tenant-1/consent/png-2',
      );
      await retireDocument(
        policy: policyWith(canVault),
        document: first,
        to: VaultDocumentStatus.superseded,
        supersededBy: second.id,
      );
      final VaultDocument superseded = (await repository.documentById(
        first.id,
      ))!;
      expect(superseded.status, VaultDocumentStatus.superseded);
      expect(superseded.supersededBy, second.id);
    });

    test('refuses a supersession without a replacement', () async {
      final VaultDocument document = await aDocument();
      await expectLater(
        retireDocument(
          policy: policyWith(canVault),
          document: document,
          to: VaultDocumentStatus.superseded,
        ),
        throwsA(isA<ValidationError>()),
      );
    });

    test('voids a document with a reason', () async {
      final VaultDocument document = await aDocument();
      await retireDocument(
        policy: policyWith(canVault),
        document: document,
        to: VaultDocumentStatus.voided,
        reason: 'Wrong patient page',
      );
      final VaultDocument voided = (await repository.documentById(
        document.id,
      ))!;
      expect(voided.status, VaultDocumentStatus.voided);
      expect(voided.voidReason, 'Wrong patient page');
      expect(voided.isTerminal, isTrue);
    });

    test('refuses a void without a reason', () async {
      final VaultDocument document = await aDocument();
      await expectLater(
        retireDocument(
          policy: policyWith(canVault),
          document: document,
          to: VaultDocumentStatus.voided,
        ),
        throwsA(isA<ValidationError>()),
      );
    });

    test('refuses to retire a document twice', () async {
      final VaultDocument document = await aDocument();
      await retireDocument(
        policy: policyWith(canVault),
        document: document,
        to: VaultDocumentStatus.voided,
        reason: 'Wrong patient page',
      );
      final VaultDocument retired = (await repository.documentById(
        document.id,
      ))!;
      await expectLater(
        retireDocument(
          policy: policyWith(canVault),
          document: retired,
          to: VaultDocumentStatus.superseded,
          supersededBy: 'doc-9',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('refuses a writer without the vault tier', () async {
      await expectLater(
        registerDocument(
          policy: policyWith(canConsent),
          tenantId: 'tenant-1',
          issuedBy: 'user-1',
          kind: VaultDocumentKind.report,
          title: 'Report',
          bucket: 'clinical-documents',
          objectPath: 'tenant-1/report/1.pdf',
          mimeType: 'application/pdf',
          sizeBytes: 10,
          sha256: hex('f'),
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });
  });

  group('the derived board', () {
    test('orders consents by how much attention they need', () async {
      final ConsentTemplate template = await aTemplate();
      await aConsent(templateId: template.id);
      final List<ConsentBoardEntry> board = await readConsentVault.board(
        policy: policyWith(canRead),
        tenantId: 'tenant-1',
        now: now,
      );
      expect(board.single.validity, ConsentValidity.pending);
      expect(board.single.missing, contains(ConsentAttestation.signature));
      expect(board.single.missing, contains(ConsentAttestation.document));
      expect(board.single.missing, contains(ConsentAttestation.witness));
    });

    test('a signed consent past its expiry is expired', () async {
      expect(
        consentValidity(
          status: ConsentStatus.signed,
          expiresAt: DateTime.utc(2026, 5, 1),
          now: now,
        ),
        ConsentValidity.expired,
      );
      expect(
        consentValidity(
          status: ConsentStatus.signed,
          expiresAt: null,
          now: now,
        ),
        ConsentValidity.signed,
      );
    });

    test('a refusal and a revocation win over the dates', () {
      expect(
        consentValidity(
          status: ConsentStatus.declined,
          expiresAt: DateTime.utc(2027, 1, 1),
          now: now,
        ),
        ConsentValidity.declined,
      );
      expect(
        consentValidity(
          status: ConsentStatus.revoked,
          expiresAt: null,
          now: now,
        ),
        ConsentValidity.revoked,
      );
      expect(
        consentValidity(
          status: ConsentStatus.drafted,
          expiresAt: null,
          now: now,
        ),
        ConsentValidity.pending,
      );
      expect(
        consentValidity(
          status: ConsentStatus.awaitingSignature,
          expiresAt: null,
          now: now,
        ),
        ConsentValidity.awaitingSignature,
      );
    });

    test('missing attestations follow the template requirements', () {
      final ConsentTemplate template = ConsentTemplate.fromRow(
        const <String, Object?>{
          'id': 'tpl-1',
          'tenant_id': 'tenant-1',
          'code': 'SURG-1',
          'title': 'Consent',
          'procedure_category': null,
          'body_text': 'Text',
          'version': 1,
          'requires_witness': 1,
          'requires_biometric': 1,
          'validity_days': null,
          'is_active': 1,
          'created_by': 'user-1',
          'created_at': null,
          'updated_at': null,
        },
      );
      final ConsentRecord bare = ConsentRecord.fromRow(<String, Object?>{
        'id': 'consent-1',
        'tenant_id': 'tenant-1',
        'patient_id': 'patient-1',
        'facility_id': 'facility-1',
        'template_id': 'tpl-1',
        'procedure_text': 'Laparotomy',
        'status': 'drafted',
        'signature_point_count': 0,
        'biometric_method': 'none',
        'created_by': 'user-1',
        'updated_at': DateTime.utc(2026, 6, 1).toIso8601String(),
      });
      expect(
        missingConsentAttestations(template: template, record: bare),
        <ConsentAttestation>{
          ConsentAttestation.signature,
          ConsentAttestation.biometric,
          ConsentAttestation.witness,
          ConsentAttestation.document,
        },
      );
      expect(
        missingConsentAttestations(template: null, record: bare),
        <ConsentAttestation>{
          ConsentAttestation.signature,
          ConsentAttestation.document,
        },
      );
    });

    test('the read filters honour retirement and closure', () async {
      await aTemplate(isActive: false);
      await aTemplate(code: 'SURG-2');
      expect(
        await readConsentVault.templates(
          policy: policyWith(canRead),
          tenantId: 'tenant-1',
        ),
        hasLength(2),
      );
      expect(
        await readConsentVault.templates(
          policy: policyWith(canRead),
          tenantId: 'tenant-1',
          includeRetired: false,
        ),
        hasLength(1),
      );

      final VaultDocument document = await aDocument();
      await retireDocument(
        policy: policyWith(canVault),
        document: document,
        to: VaultDocumentStatus.voided,
        reason: 'Wrong patient page',
      );
      expect(
        await readConsentVault.documents(
          policy: policyWith(canRead),
          tenantId: 'tenant-1',
        ),
        hasLength(1),
      );
      expect(
        await readConsentVault.documents(
          policy: policyWith(canRead),
          tenantId: 'tenant-1',
          includeRetired: false,
        ),
        isEmpty,
      );
    });

    test('refuses a reader without the read tier', () async {
      await expectLater(
        readConsentVault.board(
          policy: policyWith(canConsent),
          tenantId: 'tenant-1',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });
  });

  group('the state machines', () {
    test('a consent advances one stage at a time', () {
      expect(
        consentCanTransition(
          ConsentStatus.drafted,
          ConsentStatus.awaitingSignature,
        ),
        isTrue,
      );
      expect(
        consentCanTransition(ConsentStatus.drafted, ConsentStatus.signed),
        isTrue,
      );
      expect(
        consentCanTransition(
          ConsentStatus.awaitingSignature,
          ConsentStatus.declined,
        ),
        isTrue,
      );
      expect(
        consentCanTransition(ConsentStatus.drafted, ConsentStatus.revoked),
        isFalse,
      );
      expect(
        consentCanTransition(ConsentStatus.signed, ConsentStatus.declined),
        isFalse,
      );
      expect(
        consentCanTransition(ConsentStatus.signed, ConsentStatus.revoked),
        isTrue,
      );
      expect(
        consentCanTransition(ConsentStatus.revoked, ConsentStatus.signed),
        isFalse,
      );
      expect(
        consentCanTransition(ConsentStatus.declined, ConsentStatus.drafted),
        isFalse,
      );
    });

    test('a vault document has two one-way endings', () {
      expect(
        documentCanTransition(
          VaultDocumentStatus.issued,
          VaultDocumentStatus.superseded,
        ),
        isTrue,
      );
      expect(
        documentCanTransition(
          VaultDocumentStatus.issued,
          VaultDocumentStatus.voided,
        ),
        isTrue,
      );
      expect(
        documentCanTransition(
          VaultDocumentStatus.voided,
          VaultDocumentStatus.superseded,
        ),
        isFalse,
      );
      expect(
        documentCanTransition(
          VaultDocumentStatus.superseded,
          VaultDocumentStatus.issued,
        ),
        isFalse,
      );
    });

    test('a digest is lowercase hexadecimal and nothing else', () {
      expect(isSha256Hex(hex('a')), isTrue);
      expect(isSha256Hex(hex('A')), isFalse);
      expect(isSha256Hex(hex('a').substring(0, 63)), isFalse);
      expect(isSha256Hex(''), isFalse);
    });
  });
}
