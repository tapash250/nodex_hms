/// Documents & Biometric E-Consent Vault (Module 33).
///
/// Three tabs: the consent board (patient-scoped, like the insurance board,
/// because a consent belongs to a person), the versioned template catalogue, and
/// the vault index. A consent is captured at the bedside: the stylus signature
/// and its witness are recorded here, the artefact is uploaded under a SHA-256
/// digest, and the vault entry that indexes it is what the consent is signed
/// against.
///
/// The upload needs connectivity, and the module states that honestly: a device
/// that is offline can raise, prepare and witness a consent, but the signature
/// itself completes when the artefact reaches the vault. Biometric capture is
/// recorded when a reader supplies a template digest; the screen itself does not
/// synthesise one, so a version that requires a biometric cannot be signed on a
/// device without a reader.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/storage/storage_service.dart';
import 'package:nodex_hms/domain/documents/documents.dart';
import 'package:nodex_hms/domain/documents/documents_use_cases.dart';
import 'package:nodex_hms/domain/patients/patient.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// The consent and document vault board.
class ConsentVaultScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const ConsentVaultScreen({super.key});

  @override
  ConsumerState<ConsentVaultScreen> createState() => _ConsentVaultScreenState();
}

class _ConsentVaultScreenState extends ConsumerState<ConsentVaultScreen> {
  List<ConsentBoardEntry> _board = const <ConsentBoardEntry>[];
  List<ConsentTemplate> _templates = const <ConsentTemplate>[];
  List<VaultDocument> _documents = const <VaultDocument>[];
  Patient? _patient;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = ref.read(sessionProvider);
    final String? tenantId = session.tenantId;
    if (tenantId == null) {
      setState(() {
        _error = 'Session is not ready.';
        _loading = false;
      });
      return;
    }
    try {
      final ReadConsentVaultUseCase read = ref.read(
        readConsentVaultUseCaseProvider,
      );
      final List<ConsentBoardEntry> board = await read.board(
        policy: session.authorization,
        tenantId: tenantId,
        patientId: _patient?.id,
      );
      final List<ConsentTemplate> templates = await read.templates(
        policy: session.authorization,
        tenantId: tenantId,
      );
      final List<VaultDocument> documents = await read.documents(
        policy: session.authorization,
        tenantId: tenantId,
        patientId: _patient?.id,
      );
      if (!mounted) return;
      setState(() {
        _board = board;
        _templates = templates;
        _documents = documents;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      await _load();
    } on Object catch (error) {
      if (!mounted) return;
      _snack(error.toString());
    }
  }

  List<ConsentTemplate> get _activeTemplates => _templates
      .where((ConsentTemplate template) => template.isActive)
      .toList(growable: false);

  List<VaultDocument> get _issuedDocuments => _documents
      .where((VaultDocument document) => document.isIssued)
      .toList(growable: false);

  String _templateLabel(String templateId) {
    for (final ConsentTemplate template in _templates) {
      if (template.id == templateId) {
        return '${template.code} v${template.version}';
      }
    }
    return 'Template';
  }

  String? _documentTitle(String? documentId) {
    if (documentId == null) {
      return null;
    }
    for (final VaultDocument document in _documents) {
      if (document.id == documentId) {
        return document.title;
      }
    }
    return null;
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _choosePatient() async {
    final Patient? patient = await showDialog<Patient>(
      context: context,
      builder: (BuildContext context) => const _PatientPickerDialog(),
    );
    if (patient == null) return;
    setState(() {
      _patient = patient;
      _loading = true;
    });
    await _load();
  }

  Future<void> _clearPatient() async {
    setState(() {
      _patient = null;
      _loading = true;
    });
    await _load();
  }

  Future<String?> _askReason({
    required String title,
    required String label,
    required String confirm,
  }) async {
    final TextEditingController controller = TextEditingController();
    final String? value = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(labelText: label),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: Text(confirm),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  Future<void> _registerTemplate() async {
    final session = ref.read(sessionProvider);
    final String? tenantId = session.tenantId;
    final String? userId = session.user?.userId;
    if (tenantId == null || userId == null) return;
    final _TemplateFormResult? result = await showDialog<_TemplateFormResult>(
      context: context,
      builder: (BuildContext context) => const _TemplateFormDialog(),
    );
    if (result == null) return;
    await _run(() async {
      await ref
          .read(registerConsentTemplateUseCaseProvider)
          .call(
            policy: session.authorization,
            tenantId: tenantId,
            createdBy: userId,
            code: result.code,
            title: result.title,
            bodyText: result.bodyText,
            version: result.version,
            procedureCategory: result.procedureCategory,
            requiresWitness: result.requiresWitness,
            requiresBiometric: result.requiresBiometric,
            validityDays: result.validityDays,
          );
    });
  }

  Future<void> _setTemplateActive(
    ConsentTemplate template, {
    required bool isActive,
  }) async {
    final session = ref.read(sessionProvider);
    await _run(() async {
      await ref
          .read(setConsentTemplateActiveUseCaseProvider)
          .call(
            policy: session.authorization,
            template: template,
            isActive: isActive,
          );
    });
  }

  Future<void> _raiseConsent() async {
    final session = ref.read(sessionProvider);
    final String? tenantId = session.tenantId;
    final String? userId = session.user?.userId;
    final Set<String> facilities =
        session.snapshot?.facilityIds ?? const <String>{};
    final String? facilityId = facilities.isEmpty ? null : facilities.first;
    final Patient? patient = _patient;
    if (tenantId == null || userId == null || facilityId == null) return;
    if (patient == null) {
      _snack('Choose a patient first.');
      return;
    }
    if (_activeTemplates.isEmpty) {
      _snack('Publish a consent template first.');
      return;
    }
    final _ConsentFormResult? result = await showDialog<_ConsentFormResult>(
      context: context,
      builder: (BuildContext context) =>
          _ConsentFormDialog(templates: _activeTemplates),
    );
    if (result == null) return;
    await _run(() async {
      await ref
          .read(raiseConsentUseCaseProvider)
          .call(
            policy: session.authorization,
            tenantId: tenantId,
            patientId: patient.id,
            facilityId: facilityId,
            templateId: result.templateId,
            procedureText: result.procedureText,
            createdBy: userId,
          );
    });
  }

  /// Captures the stylus signature, vaults the artefact under its digest, and
  /// signs the consent against that vault entry.
  Future<void> _captureAndSign(ConsentRecord consent) async {
    final session = ref.read(sessionProvider);
    final String? tenantId = session.tenantId;
    final String? userId = session.user?.userId;
    if (tenantId == null || userId == null) return;
    ConsentTemplate? template;
    for (final ConsentTemplate candidate in _templates) {
      if (candidate.id == consent.templateId) {
        template = candidate;
      }
    }
    final _CaptureResult? result = await showDialog<_CaptureResult>(
      context: context,
      builder: (BuildContext context) =>
          _CaptureSignatureDialog(consent: consent, template: template),
    );
    if (result == null) return;
    await _run(() async {
      final StorageService storage = ref.read(storageServiceProvider);
      final StoredObject stored = await storage.uploadFile(
        tenantId: tenantId,
        bucket: ClinicalBuckets.signatures,
        objectPath: 'consent/${consent.id}-signature.png',
        bytes: result.bytes,
        mimeType: 'image/png',
      );
      final String documentId = await ref
          .read(registerVaultDocumentUseCaseProvider)
          .call(
            policy: session.authorization,
            tenantId: tenantId,
            issuedBy: userId,
            kind: VaultDocumentKind.consentSignature,
            title: 'Signature for ${consent.procedureText}',
            bucket: stored.bucket,
            objectPath: stored.path,
            mimeType: 'image/png',
            sizeBytes: result.bytes.length,
            sha256: stored.sha256,
            patientId: consent.patientId,
            encounterId: consent.encounterId,
            consentId: consent.id,
          );
      await ref
          .read(captureConsentAttestationUseCaseProvider)
          .call(
            policy: session.authorization,
            consent: consent,
            signatureSha256: stored.sha256,
            signaturePointCount: result.pointCount,
            signatureCapturedAt: DateTime.now().toUtc(),
            witnessedBy: result.witnessed ? userId : null,
            witnessedAt: result.witnessed ? DateTime.now().toUtc() : null,
          );
      final ConsentRecord? captured = await _reloadConsent(
        tenantId,
        consent.id,
      );
      if (captured == null) {
        return;
      }
      await ref
          .read(signConsentUseCaseProvider)
          .call(
            policy: session.authorization,
            consent: captured,
            documentId: documentId,
            signerName: result.signerName,
            signerRelationship: result.signerRelationship,
          );
    });
  }

  /// Re-reads a consent after a capture, so the signature the row now carries
  /// is the digest the signature is checked against.
  Future<ConsentRecord?> _reloadConsent(
    String tenantId,
    String consentId,
  ) async {
    final session = ref.read(sessionProvider);
    final List<ConsentRecord> consents = await ref
        .read(readConsentVaultUseCaseProvider)
        .consents(policy: session.authorization, tenantId: tenantId);
    for (final ConsentRecord consent in consents) {
      if (consent.id == consentId) {
        return consent;
      }
    }
    return null;
  }

  Future<void> _recordWitness(ConsentRecord consent) async {
    final session = ref.read(sessionProvider);
    final String? userId = session.user?.userId;
    if (userId == null) return;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Record witness'),
        content: const Text(
          'Record that you witnessed this consent being taken?',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Record'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() async {
      await ref
          .read(captureConsentAttestationUseCaseProvider)
          .call(
            policy: session.authorization,
            consent: consent,
            witnessedBy: userId,
            witnessedAt: DateTime.now().toUtc(),
          );
    });
  }

  Future<void> _declineConsent(ConsentRecord consent) async {
    final session = ref.read(sessionProvider);
    final String? reason = await _askReason(
      title: 'Record refusal',
      label: 'Reason',
      confirm: 'Record',
    );
    if (reason == null) return;
    await _run(() async {
      await ref
          .read(declineConsentUseCaseProvider)
          .call(
            policy: session.authorization,
            consent: consent,
            reason: reason,
          );
    });
  }

  Future<void> _revokeConsent(ConsentRecord consent) async {
    final session = ref.read(sessionProvider);
    final String? reason = await _askReason(
      title: 'Revoke consent',
      label: 'Reason',
      confirm: 'Revoke',
    );
    if (reason == null) return;
    await _run(() async {
      await ref
          .read(revokeConsentUseCaseProvider)
          .call(
            policy: session.authorization,
            consent: consent,
            reason: reason,
          );
    });
  }

  Future<void> _supersedeDocument(VaultDocument document) async {
    final session = ref.read(sessionProvider);
    final List<VaultDocument> replacements = _issuedDocuments
        .where((VaultDocument other) => other.id != document.id)
        .toList(growable: false);
    if (replacements.isEmpty) {
      _snack('Issue the replacement document first.');
      return;
    }
    final VaultDocument? replacement = await showDialog<VaultDocument>(
      context: context,
      builder: (BuildContext context) => SimpleDialog(
        title: const Text('Replacement document'),
        children: <Widget>[
          for (final VaultDocument other in replacements)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(other),
              child: Text('${other.title} · ${_shortDigest(other.sha256)}'),
            ),
        ],
      ),
    );
    if (replacement == null) return;
    await _run(() async {
      await ref
          .read(retireVaultDocumentUseCaseProvider)
          .call(
            policy: session.authorization,
            document: document,
            to: VaultDocumentStatus.superseded,
            supersededBy: replacement.id,
          );
    });
  }

  Future<void> _voidDocument(VaultDocument document) async {
    final session = ref.read(sessionProvider);
    final String? reason = await _askReason(
      title: 'Void document',
      label: 'Reason',
      confirm: 'Void',
    );
    if (reason == null) return;
    await _run(() async {
      await ref
          .read(retireVaultDocumentUseCaseProvider)
          .call(
            policy: session.authorization,
            document: document,
            to: VaultDocumentStatus.voided,
            reason: reason,
          );
    });
  }

  Future<void> _showConsent(ConsentBoardEntry entry) async {
    final ConsentRecord consent = entry.consent;
    await showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.draw_outlined),
              title: Text('${consent.procedureText} · ${entry.validity.label}'),
              subtitle: Text(
                <String>[
                  _templateLabel(consent.templateId),
                  if (entry.template case final ConsentTemplate template)
                    'Requires ${_requirementText(template)}',
                  if (consent.hasSignature)
                    'Signature ${_shortDigest(consent.signatureSha256!)}',
                  if (consent.biometricMethod != BiometricMethod.none)
                    'Biometric ${consent.biometricMethod.label}',
                  if (consent.witnessedBy != null) 'Witnessed',
                  if (entry.missing.isNotEmpty)
                    'Still to capture: ${entry.missing.map((ConsentAttestation a) => a.label).join(', ')}',
                  if (consent.signedAt case final DateTime signedAt)
                    'Signed ${_formatMoment(signedAt)} by ${consent.signerName ?? 'unknown'}',
                  if (consent.expiresAt case final DateTime expiresAt)
                    'Valid until ${_formatMoment(expiresAt)}',
                  if (consent.declineReason case final String why)
                    'Declined: $why',
                  if (consent.revocationReason case final String why)
                    'Revoked: $why',
                  if (_documentTitle(consent.documentId)
                      case final String title)
                    title,
                ].join(' · '),
              ),
            ),
            if (consent.isLive) ...<Widget>[
              ListTile(
                leading: const Icon(Icons.fingerprint),
                title: const Text('Capture signature and sign'),
                onTap: () {
                  Navigator.of(context).pop();
                  _captureAndSign(consent);
                },
              ),
              ListTile(
                leading: const Icon(Icons.visibility_outlined),
                title: const Text('Record witness'),
                onTap: () {
                  Navigator.of(context).pop();
                  _recordWitness(consent);
                },
              ),
              ListTile(
                leading: const Icon(Icons.block_outlined),
                title: const Text('Record refusal'),
                onTap: () {
                  Navigator.of(context).pop();
                  _declineConsent(consent);
                },
              ),
            ],
            if (consent.isSigned)
              ListTile(
                leading: const Icon(Icons.undo_outlined),
                title: const Text('Revoke consent'),
                onTap: () {
                  Navigator.of(context).pop();
                  _revokeConsent(consent);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDocument(VaultDocument document) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            ListTile(
              leading: Icon(_documentIcon(document.kind)),
              title: Text('${document.title} · ${document.status.label}'),
              subtitle: Text(
                <String>[
                  document.kind.label,
                  '${document.bucket}/${document.objectPath}',
                  document.mimeType,
                  '${document.sizeBytes} bytes',
                  'SHA-256 ${document.sha256}',
                  if (document.isSigned)
                    'Signed with ${document.signatureAlgorithm.label}',
                  if (document.voidReason case final String why) 'Void: $why',
                ].join('\n'),
              ),
            ),
            if (document.isIssued) ...<Widget>[
              ListTile(
                leading: const Icon(Icons.swap_horiz_outlined),
                title: const Text('Supersede with a later document'),
                onTap: () {
                  Navigator.of(context).pop();
                  _supersedeDocument(document);
                },
              ),
              ListTile(
                leading: const Icon(Icons.block_outlined),
                title: const Text('Void document'),
                onTap: () {
                  Navigator.of(context).pop();
                  _voidDocument(document);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Consents')),
        body: Center(child: Text(_error!)),
      );
    }
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Documents & consent vault'),
          actions: <Widget>[
            if (_patient == null)
              TextButton.icon(
                icon: const Icon(Icons.person_search_outlined),
                label: const Text('Patient'),
                onPressed: _choosePatient,
              )
            else
              TextButton.icon(
                icon: const Icon(Icons.close),
                label: Text(_patient!.displayName),
                onPressed: _clearPatient,
              ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabs: <Widget>[
              Tab(text: 'Consents'),
              Tab(text: 'Templates'),
              Tab(text: 'Vault'),
            ],
          ),
        ),
        body: TabBarView(
          children: <Widget>[_consentTab(), _templateTab(), _vaultTab()],
        ),
      ),
    );
  }

  Widget _consentTab() {
    return Stack(
      children: <Widget>[
        if (_board.isEmpty)
          const Center(child: Text('No consents on the board.'))
        else
          ListView.builder(
            itemCount: _board.length,
            itemBuilder: (BuildContext context, int index) {
              final ConsentBoardEntry entry = _board[index];
              final ConsentRecord consent = entry.consent;
              return ListTile(
                leading: Icon(
                  entry.needsAttention
                      ? Icons.error_outline
                      : Icons.check_circle_outline,
                  color: entry.validity.needsAttention
                      ? Theme.of(context).colorScheme.error
                      : null,
                ),
                title: Text(consent.procedureText),
                subtitle: Text(
                  <String>[
                    entry.validity.label,
                    _templateLabel(consent.templateId),
                    if (entry.missing.isNotEmpty)
                      'Missing ${entry.missing.map((ConsentAttestation a) => a.label).join(', ')}',
                  ].join(' · '),
                ),
                onTap: () => _showConsent(entry),
              );
            },
          ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            onPressed: _raiseConsent,
            icon: const Icon(Icons.add),
            label: const Text('Raise consent'),
          ),
        ),
      ],
    );
  }

  Widget _templateTab() {
    return Stack(
      children: <Widget>[
        if (_templates.isEmpty)
          const Center(child: Text('No consent templates published.'))
        else
          ListView.builder(
            itemCount: _templates.length,
            itemBuilder: (BuildContext context, int index) {
              final ConsentTemplate template = _templates[index];
              return ListTile(
                leading: Icon(
                  template.isActive
                      ? Icons.article_outlined
                      : Icons.history_outlined,
                ),
                title: Text('${template.code} v${template.version}'),
                subtitle: Text(
                  <String>[
                    template.title,
                    _requirementText(template),
                    if (template.validityDays case final int days)
                      'Valid $days days',
                    template.isActive ? 'Active' : 'Retired',
                  ].join(' · '),
                ),
                trailing: TextButton(
                  onPressed: () => _setTemplateActive(
                    template,
                    isActive: !template.isActive,
                  ),
                  child: Text(template.isActive ? 'Retire' : 'Activate'),
                ),
              );
            },
          ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            onPressed: _registerTemplate,
            icon: const Icon(Icons.add),
            label: const Text('New version'),
          ),
        ),
      ],
    );
  }

  Widget _vaultTab() {
    if (_documents.isEmpty) {
      return const Center(child: Text('The vault is empty.'));
    }
    return ListView.builder(
      itemCount: _documents.length,
      itemBuilder: (BuildContext context, int index) {
        final VaultDocument document = _documents[index];
        return ListTile(
          leading: Icon(_documentIcon(document.kind)),
          title: Text(document.title),
          subtitle: Text(
            <String>[
              document.kind.label,
              document.status.label,
              _shortDigest(document.sha256),
              if (document.isSigned) document.signatureAlgorithm.label,
            ].join(' · '),
          ),
          onTap: () => _showDocument(document),
        );
      },
    );
  }
}

/// Opens the signature capture and reports what was captured.
class _CaptureResult {
  const _CaptureResult({
    required this.bytes,
    required this.pointCount,
    required this.signerName,
    required this.signerRelationship,
    required this.witnessed,
  });

  final Uint8List bytes;
  final int pointCount;
  final String signerName;
  final SignerRelationship signerRelationship;
  final bool witnessed;
}

class _CaptureSignatureDialog extends StatefulWidget {
  const _CaptureSignatureDialog({required this.consent, this.template});

  final ConsentRecord consent;
  final ConsentTemplate? template;

  @override
  State<_CaptureSignatureDialog> createState() =>
      _CaptureSignatureDialogState();
}

class _CaptureSignatureDialogState extends State<_CaptureSignatureDialog> {
  final GlobalKey _boundary = GlobalKey();
  final TextEditingController _signer = TextEditingController();
  final List<List<Offset>> _strokes = <List<Offset>>[];
  SignerRelationship _relationship = SignerRelationship.patient;
  bool _witnessed = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _signer.text = '';
  }

  @override
  void dispose() {
    _signer.dispose();
    super.dispose();
  }

  int get _pointCount => _strokes.fold(
    0,
    (int total, List<Offset> stroke) => total + stroke.length,
  );

  Future<Uint8List?> _rasterise() async {
    final RenderObject? renderObject = _boundary.currentContext
        ?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) {
      return null;
    }
    final ui.Image image = await renderObject.toImage(pixelRatio: 2);
    final ByteData? data = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    image.dispose();
    return data?.buffer.asUint8List();
  }

  Future<void> _confirm() async {
    if (_strokes.isEmpty || _pointCount < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Capture a signature first.')),
      );
      return;
    }
    if (_signer.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Name the signer.')));
      return;
    }
    setState(() => _busy = true);
    final Uint8List? bytes = await _rasterise();
    if (!mounted) return;
    if (bytes == null) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The signature could not be captured.')),
      );
      return;
    }
    Navigator.of(context).pop(
      _CaptureResult(
        bytes: bytes,
        pointCount: _pointCount,
        signerName: _signer.text.trim(),
        signerRelationship: _relationship,
        witnessed: _witnessed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ConsentTemplate? template = widget.template;
    return AlertDialog(
      title: const Text('Capture signature'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              widget.consent.procedureText,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (template != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                template.bodyText,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (template != null && template.requiresBiometric)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'This version requires a biometric attestation. Thumbprint '
                  'capture awaits device hardware, so this consent cannot be '
                  'signed on a device without a reader.',
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _signer,
              decoration: const InputDecoration(labelText: 'Signer name'),
            ),
            DropdownButtonFormField<SignerRelationship>(
              initialValue: _relationship,
              decoration: const InputDecoration(labelText: 'Signer is the'),
              items: <DropdownMenuItem<SignerRelationship>>[
                for (final SignerRelationship value
                    in SignerRelationship.values)
                  DropdownMenuItem<SignerRelationship>(
                    value: value,
                    child: Text(value.label),
                  ),
              ],
              onChanged: (SignerRelationship? value) {
                if (value != null) setState(() => _relationship = value);
              },
            ),
            CheckboxListTile(
              value: _witnessed,
              contentPadding: EdgeInsets.zero,
              title: const Text('I witnessed this signature'),
              onChanged: (bool? value) =>
                  setState(() => _witnessed = value ?? false),
            ),
            const SizedBox(height: 8),
            RepaintBoundary(
              key: _boundary,
              child: Container(
                height: 180,
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: GestureDetector(
                  onPanStart: (DragStartDetails details) => setState(
                    () => _strokes.add(<Offset>[details.localPosition]),
                  ),
                  onPanUpdate: (DragUpdateDetails details) =>
                      setState(() => _strokes.last.add(details.localPosition)),
                  child: CustomPaint(
                    painter: _SignaturePainter(strokes: _strokes),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                TextButton(
                  onPressed: _strokes.isEmpty
                      ? null
                      : () => setState(_strokes.clear),
                  child: const Text('Clear'),
                ),
                const Spacer(),
                Text('$_pointCount points'),
              ],
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _confirm,
          child: Text(_busy ? 'Signing…' : 'Sign'),
        ),
      ],
    );
  }
}

/// Paints captured stylus strokes.
class _SignaturePainter extends CustomPainter {
  const _SignaturePainter({required this.strokes});

  final List<List<Offset>> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = const Color(0xFF111111)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final List<Offset> stroke in strokes) {
      if (stroke.length < 2) {
        continue;
      }
      final Path path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (final Offset point in stroke.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_SignaturePainter oldDelegate) =>
      oldDelegate.strokes.length != strokes.length ||
      (strokes.isNotEmpty &&
          oldDelegate.strokes.isNotEmpty &&
          oldDelegate.strokes.last.length != strokes.last.length);
}

class _TemplateFormResult {
  const _TemplateFormResult({
    required this.code,
    required this.title,
    required this.bodyText,
    required this.version,
    required this.requiresWitness,
    required this.requiresBiometric,
    this.procedureCategory,
    this.validityDays,
  });

  final String code;
  final String title;
  final String bodyText;
  final int version;
  final bool requiresWitness;
  final bool requiresBiometric;
  final String? procedureCategory;
  final int? validityDays;
}

class _TemplateFormDialog extends StatefulWidget {
  const _TemplateFormDialog();

  @override
  State<_TemplateFormDialog> createState() => _TemplateFormDialogState();
}

class _TemplateFormDialogState extends State<_TemplateFormDialog> {
  final TextEditingController _code = TextEditingController();
  final TextEditingController _title = TextEditingController();
  final TextEditingController _category = TextEditingController();
  final TextEditingController _body = TextEditingController();
  final TextEditingController _version = TextEditingController(text: '1');
  final TextEditingController _validity = TextEditingController();
  bool _requiresWitness = false;
  bool _requiresBiometric = false;

  @override
  void dispose() {
    for (final TextEditingController controller in <TextEditingController>[
      _code,
      _title,
      _category,
      _body,
      _version,
      _validity,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Publish consent template'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _code,
            decoration: const InputDecoration(labelText: 'Code'),
          ),
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          TextField(
            controller: _category,
            decoration: const InputDecoration(labelText: 'Procedure category'),
          ),
          TextField(
            controller: _body,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Consent text'),
          ),
          TextField(
            controller: _version,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Version'),
          ),
          TextField(
            controller: _validity,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Valid for days (optional)',
            ),
          ),
          CheckboxListTile(
            value: _requiresWitness,
            contentPadding: EdgeInsets.zero,
            title: const Text('A witness is required'),
            onChanged: (bool? value) =>
                setState(() => _requiresWitness = value ?? false),
          ),
          CheckboxListTile(
            value: _requiresBiometric,
            contentPadding: EdgeInsets.zero,
            title: const Text('A biometric attestation is required'),
            onChanged: (bool? value) =>
                setState(() => _requiresBiometric = value ?? false),
          ),
        ],
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(
          _TemplateFormResult(
            code: _code.text.trim(),
            title: _title.text.trim(),
            bodyText: _body.text.trim(),
            version: int.tryParse(_version.text.trim()) ?? 1,
            requiresWitness: _requiresWitness,
            requiresBiometric: _requiresBiometric,
            procedureCategory: _nullIfEmpty(_category),
            validityDays: int.tryParse(_validity.text.trim()),
          ),
        ),
        child: const Text('Publish'),
      ),
    ],
  );

  String? _nullIfEmpty(TextEditingController controller) {
    final String value = controller.text.trim();
    return value.isEmpty ? null : value;
  }
}

class _ConsentFormResult {
  const _ConsentFormResult({
    required this.templateId,
    required this.procedureText,
  });

  final String templateId;
  final String procedureText;
}

class _ConsentFormDialog extends StatefulWidget {
  const _ConsentFormDialog({required this.templates});

  final List<ConsentTemplate> templates;

  @override
  State<_ConsentFormDialog> createState() => _ConsentFormDialogState();
}

class _ConsentFormDialogState extends State<_ConsentFormDialog> {
  final TextEditingController _procedure = TextEditingController();
  late String _templateId = widget.templates.first.id;

  @override
  void dispose() {
    _procedure.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Raise consent'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          DropdownButtonFormField<String>(
            initialValue: _templateId,
            decoration: const InputDecoration(labelText: 'Template version'),
            items: <DropdownMenuItem<String>>[
              for (final ConsentTemplate template in widget.templates)
                DropdownMenuItem<String>(
                  value: template.id,
                  child: Text('${template.code} v${template.version}'),
                ),
            ],
            onChanged: (String? value) {
              if (value != null) setState(() => _templateId = value);
            },
          ),
          TextField(
            controller: _procedure,
            decoration: const InputDecoration(labelText: 'Procedure'),
          ),
        ],
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(
          _ConsentFormResult(
            templateId: _templateId,
            procedureText: _procedure.text.trim(),
          ),
        ),
        child: const Text('Raise'),
      ),
    ],
  );
}

class _PatientPickerDialog extends ConsumerStatefulWidget {
  const _PatientPickerDialog();

  @override
  ConsumerState<_PatientPickerDialog> createState() =>
      _PatientPickerDialogState();
}

class _PatientPickerDialogState extends ConsumerState<_PatientPickerDialog> {
  final TextEditingController _query = TextEditingController();
  List<Patient> _results = const <Patient>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    final session = ref.read(sessionProvider);
    final String? tenantId = session.tenantId;
    if (tenantId == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final List<Patient> patients = await ref
          .read(patientRepositoryProvider)
          .searchPatients(tenantId: tenantId, query: query);
      if (!mounted) return;
      setState(() {
        _results = patients;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Choose patient'),
    content: SizedBox(
      width: 420,
      height: 360,
      child: Column(
        children: <Widget>[
          TextField(
            controller: _query,
            decoration: const InputDecoration(labelText: 'MRN, name or phone'),
            onSubmitted: _search,
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _results.isEmpty
                ? const Center(child: Text('No matching patient.'))
                : ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (BuildContext context, int index) {
                      final Patient patient = _results[index];
                      return ListTile(
                        title: Text(patient.displayName),
                        subtitle: Text(patient.mrn),
                        onTap: () => Navigator.of(context).pop(patient),
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Close'),
      ),
      FilledButton(
        onPressed: () => _search(_query.text.trim()),
        child: const Text('Search'),
      ),
    ],
  );
}

String _requirementText(ConsentTemplate template) {
  final List<String> requirements = <String>[];
  if (template.requiresWitness) {
    requirements.add('witness');
  }
  if (template.requiresBiometric) {
    requirements.add('biometric');
  }
  return requirements.isEmpty
      ? 'signature only'
      : 'signature and ${requirements.join(' and ')}';
}

IconData _documentIcon(VaultDocumentKind kind) => switch (kind) {
  VaultDocumentKind.consentForm => Icons.article_outlined,
  VaultDocumentKind.consentSignature => Icons.gesture,
  VaultDocumentKind.report => Icons.description_outlined,
  VaultDocumentKind.other => Icons.folder_outlined,
};

String _shortDigest(String sha256) =>
    sha256.length <= 12 ? sha256 : '${sha256.substring(0, 12)}…';

String _formatMoment(DateTime value) {
  final DateTime utc = value.toUtc();
  return '${utc.year}-${utc.month.toString().padLeft(2, '0')}-'
      '${utc.day.toString().padLeft(2, '0')} '
      '${utc.hour.toString().padLeft(2, '0')}:'
      '${utc.minute.toString().padLeft(2, '0')}';
}
