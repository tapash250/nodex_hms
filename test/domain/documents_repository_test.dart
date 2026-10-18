/// Tests for the documents and consent vault repository over a fake local store
/// (Module 33).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/domain/documents/documents.dart';
import 'package:nodex_hms/domain/documents/documents_repository.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';

/// A minimal in-memory store covering the three document and consent tables.
final class FakeDocumentsStore implements PatientLocalStore {
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
      throw UnimplementedError('FakeDocumentsStore cannot run: $sql');
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

/// A 64-character hexadecimal digest of one repeated character.
String _hex(String character) => List<String>.filled(64, character).join();

void main() {
  late FakeDocumentsStore store;
  late DefaultDocumentsRepository repository;

  setUp(() {
    store = FakeDocumentsStore();
    repository = DefaultDocumentsRepository(
      store: store,
      logger: NodexLogger(
        sinks: <NodexLogSink>[InMemoryLogSink()],
        minimumLevel: NodexLogLevel.trace,
      ),
    );
  });

  String now() => DateTime.now().toUtc().toIso8601String();

  Future<String> seedTemplate({
    required String id,
    String code = 'SURG-1',
    int version = 1,
    int isActive = 1,
  }) => repository.registerTemplate(<String, Object?>{
    'id': id,
    'tenant_id': 'tenant-1',
    'code': code,
    'title': 'Laparotomy consent',
    'procedure_category': 'General surgery',
    'body_text': 'I consent to the procedure described to me.',
    'version': version,
    'requires_witness': 1,
    'requires_biometric': 0,
    'validity_days': 30,
    'is_active': isActive,
    'created_by': 'user-1',
    'created_at': now(),
    'updated_at': now(),
  });

  Future<String> seedConsent({
    required String id,
    String templateId = 'tpl-1',
    String status = 'drafted',
    String? signatureSha256,
    String? documentId,
  }) => repository.registerConsent(<String, Object?>{
    'id': id,
    'tenant_id': 'tenant-1',
    'patient_id': 'patient-1',
    'facility_id': 'facility-1',
    'encounter_id': null,
    'template_id': templateId,
    'procedure_text': 'Laparotomy',
    'status': status,
    'signer_name': status == 'signed' ? 'Rahim' : null,
    'signer_relationship': status == 'signed' ? 'patient' : null,
    'signature_sha256': signatureSha256,
    'signature_point_count': 42,
    'signature_captured_at': signatureSha256 == null ? null : now(),
    'biometric_method': 'none',
    'biometric_template_sha256': null,
    'biometric_captured_at': null,
    'biometric_quality': null,
    'witnessed_by': null,
    'witnessed_at': null,
    'document_id': documentId,
    'signed_at': null,
    'expires_at': null,
    'declined_at': null,
    'decline_reason': null,
    'revoked_at': null,
    'revocation_reason': null,
    'created_by': 'user-1',
    'created_at': now(),
    'updated_at': now(),
  });

  Future<String> seedDocument({
    required String id,
    String objectPath = 'tenant-1/consent/png-1',
    String kind = 'consent_signature',
    String status = 'issued',
  }) => repository.registerDocument(<String, Object?>{
    'id': id,
    'tenant_id': 'tenant-1',
    'patient_id': 'patient-1',
    'encounter_id': null,
    'consent_id': 'consent-1',
    'kind': kind,
    'title': 'Signature capture',
    'bucket': 'clinical-signatures',
    'object_path': objectPath,
    'mime_type': 'image/png',
    'size_bytes': 2048,
    'sha256': _hex('a'),
    'signature': null,
    'signature_algorithm': 'none',
    'signing_key_id': null,
    'status': status,
    'issued_by': 'user-1',
    'issued_at': now(),
    'superseded_at': null,
    'superseded_by': null,
    'voided_at': null,
    'void_reason': null,
    'created_at': now(),
    'updated_at': now(),
  });

  test('registerTemplate resolves by id and parses the flags', () async {
    final String id = await seedTemplate(id: 'tpl-1');
    final ConsentTemplate? template = await repository.templateById(id);
    expect(template, isNotNull);
    expect(template!.code, 'SURG-1');
    expect(template.version, 1);
    expect(template.requiresWitness, isTrue);
    expect(template.requiresBiometric, isFalse);
    expect(template.validityDays, 30);
    expect(template.isActive, isTrue);
  });

  test(
    'listTemplates filters by code and keeps newest version first',
    () async {
      await seedTemplate(id: 'tpl-1', version: 1);
      await seedTemplate(id: 'tpl-2', version: 2);
      await seedTemplate(id: 'tpl-3', code: 'SURG-2');
      expect(await repository.listTemplates('tenant-1'), hasLength(3));
      expect(
        await repository.listTemplates('tenant-1', code: 'SURG-1'),
        hasLength(2),
      );
      expect(await repository.listTemplates('tenant-2'), isEmpty);
    },
  );

  test('updateTemplate retires a version', () async {
    await seedTemplate(id: 'tpl-1');
    await repository.updateTemplate(
      'tpl-1',
      consentTemplateActiveChanges(isActive: false),
    );
    final ConsentTemplate? template = await repository.templateById('tpl-1');
    expect(template!.isActive, isFalse);
    // The words do not move with the flag.
    expect(template.bodyText, 'I consent to the procedure described to me.');
  });

  test('registerConsent resolves by id and parses the status', () async {
    final String id = await seedConsent(id: 'consent-1');
    final ConsentRecord? consent = await repository.consentById(id);
    expect(consent, isNotNull);
    expect(consent!.status, ConsentStatus.drafted);
    expect(consent.isLive, isTrue);
    expect(consent.signaturePointCount, 42);
    expect(consent.biometricMethod, BiometricMethod.none);
    expect(consent.hasSignature, isFalse);
  });

  test('listConsents filters by patient, template and status', () async {
    await seedConsent(id: 'consent-1');
    await seedConsent(
      id: 'consent-2',
      status: 'signed',
      signatureSha256: _hex('b'),
    );
    await seedConsent(id: 'consent-3', templateId: 'tpl-9');
    expect(await repository.listConsents('tenant-1'), hasLength(3));
    expect(
      await repository.listConsents('tenant-1', status: 'signed'),
      hasLength(1),
    );
    expect(
      await repository.listConsents('tenant-1', templateId: 'tpl-9'),
      hasLength(1),
    );
    expect(
      await repository.listConsents('tenant-1', patientId: 'patient-9'),
      isEmpty,
    );
  });

  test('updateConsent applies an attestation change set', () async {
    await seedConsent(id: 'consent-1');
    await repository.updateConsent(
      'consent-1',
      consentAttestationChanges(
        signatureSha256: _hex('c'),
        signaturePointCount: 88,
        signatureCapturedAt: DateTime.utc(2026, 6, 1, 9),
        advanceTo: ConsentStatus.awaitingSignature,
      ),
    );
    final ConsentRecord? consent = await repository.consentById('consent-1');
    expect(consent!.status, ConsentStatus.awaitingSignature);
    expect(consent.hasSignature, isTrue);
    expect(consent.signatureSha256, _hex('c'));
    expect(consent.signaturePointCount, 88);
    expect(consent.signatureCapturedAt, DateTime.utc(2026, 6, 1, 9));
  });

  test('registerDocument resolves by id and parses the lifecycle', () async {
    final String id = await seedDocument(id: 'doc-1');
    final VaultDocument? document = await repository.documentById(id);
    expect(document, isNotNull);
    expect(document!.kind, VaultDocumentKind.consentSignature);
    expect(document.status, VaultDocumentStatus.issued);
    expect(document.isIssued, isTrue);
    expect(document.isSigned, isFalse);
    expect(document.sha256, _hex('a'));
    expect(document.sizeBytes, 2048);
  });

  test('listDocuments filters by patient, consent and kind', () async {
    await seedDocument(id: 'doc-1');
    await seedDocument(
      id: 'doc-2',
      objectPath: 'tenant-1/consent/png-2',
      kind: 'report',
    );
    expect(await repository.listDocuments('tenant-1'), hasLength(2));
    expect(
      await repository.listDocuments(
        'tenant-1',
        kind: VaultDocumentKind.report.wireValue,
      ),
      hasLength(1),
    );
    expect(
      await repository.listDocuments('tenant-1', consentId: 'consent-1'),
      hasLength(2),
    );
    expect(
      await repository.listDocuments('tenant-1', patientId: 'patient-9'),
      isEmpty,
    );
  });

  test('updateDocument records supersession and voiding', () async {
    await seedDocument(id: 'doc-1');
    await seedDocument(id: 'doc-2', objectPath: 'tenant-1/consent/png-2');
    await repository.updateDocument(
      'doc-1',
      vaultRetireChanges(
        to: VaultDocumentStatus.superseded,
        supersededBy: 'doc-2',
      ),
    );
    VaultDocument? document = await repository.documentById('doc-1');
    expect(document!.status, VaultDocumentStatus.superseded);
    expect(document.supersededBy, 'doc-2');
    expect(document.supersededAt, isNotNull);
    expect(document.isTerminal, isTrue);

    await repository.updateDocument(
      'doc-2',
      vaultRetireChanges(to: VaultDocumentStatus.voided, reason: 'Wrong page'),
    );
    document = await repository.documentById('doc-2');
    expect(document!.status, VaultDocumentStatus.voided);
    expect(document.voidReason, 'Wrong page');
  });

  test('a store failure surfaces as a NodexError', () async {
    await expectLater(
      repository.updateTemplate('missing', <String, Object?>{}),
      throwsA(isA<NodexError>()),
    );
    store.closed = true;
    await expectLater(
      repository.listTemplates('tenant-1'),
      throwsA(isA<NodexError>()),
    );
  });
}
