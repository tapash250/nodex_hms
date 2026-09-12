/// Encounter editor screen (Module 16).
///
/// One screen for the whole encounter lifecycle: document SOAP content while
/// unsigned, sign to freeze, and amend after signing. The screen never decides
/// what is permitted — the use cases and the server trigger do. It only
/// renders the state it is given and routes each action to the right command:
/// save for drafts, sign for commitment, amend for corrections.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/encounters/encounter.dart';
import 'package:nodex_hms/domain/session/session_state.dart';
import 'package:nodex_hms/features/encounters/encounters_controller.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// Editor for one encounter.
class EncounterEditorScreen extends ConsumerStatefulWidget {
  /// Creates the editor.
  const EncounterEditorScreen({required this.encounterId, super.key});

  /// Local encounter id.
  final String encounterId;

  @override
  ConsumerState<EncounterEditorScreen> createState() =>
      _EncounterEditorScreenState();
}

class _EncounterEditorScreenState extends ConsumerState<EncounterEditorScreen> {
  final TextEditingController _subjectiveController = TextEditingController();
  final TextEditingController _objectiveController = TextEditingController();
  final TextEditingController _assessmentController = TextEditingController();
  final TextEditingController _planController = TextEditingController();
  final TextEditingController _diagnosesController = TextEditingController();

  bool _initialized = false;
  bool _isBusy = false;
  String? _errorMessage;

  @override
  void dispose() {
    _subjectiveController.dispose();
    _objectiveController.dispose();
    _assessmentController.dispose();
    _planController.dispose();
    _diagnosesController.dispose();
    super.dispose();
  }

  void _fillOnce(ClinicalEncounter encounter) {
    if (_initialized) {
      return;
    }
    _initialized = true;
    _subjectiveController.text = encounter.subjectiveNote ?? '';
    _objectiveController.text = encounter.objectiveFindings ?? '';
    _assessmentController.text = encounter.assessment ?? '';
    _planController.text = encounter.planDescription ?? '';
    _diagnosesController.text = encounter.diagnoses
        .map((EncounterDiagnosis d) => d.code)
        .join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<EncounterDetail> detail = ref.watch(
      encounterDetailProvider(widget.encounterId),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Encounter')),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace _) => _EditorError(
          error: error,
          onRetry: () =>
              ref.invalidate(encounterDetailProvider(widget.encounterId)),
        ),
        data: (EncounterDetail bundle) {
          _fillOnce(bundle.encounter);
          return _EditorBody(
            bundle: bundle,
            controllers: _Controllers(
              subjective: _subjectiveController,
              objective: _objectiveController,
              assessment: _assessmentController,
              plan: _planController,
              diagnoses: _diagnosesController,
            ),
            isBusy: _isBusy,
            errorMessage: _errorMessage,
            onSave: () => _save(bundle.encounter),
            onSign: () => _sign(bundle.encounter),
            onAmend: () => _amend(bundle.encounter),
          );
        },
      ),
    );
  }

  Future<void> _save(ClinicalEncounter encounter) async {
    final SessionState session = ref.read(sessionProvider);
    setState(() {
      _isBusy = true;
      _errorMessage = null;
    });
    try {
      await ref
          .read(saveEncounterDraftUseCaseProvider)
          .call(
            policy: session.authorization,
            encounter: encounter,
            subjectiveNote: _subjectiveController.text,
            objectiveFindings: _objectiveController.text,
            assessment: _assessmentController.text,
            planDescription: _planController.text,
          );
      ref.invalidate(encounterDetailProvider(widget.encounterId));
      ref.invalidate(encountersForPatientProvider(encounter.patientId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Draft saved on this device.')),
        );
      }
    } on NodexError catch (error) {
      if (mounted) {
        setState(() => _errorMessage = error.message);
      }
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _sign(ClinicalEncounter encounter) async {
    final SessionState session = ref.read(sessionProvider);
    final String? userId = session.user?.userId;
    if (userId == null) {
      return;
    }

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Sign this encounter?'),
        content: const Text(
          'Signing freezes this record. Further corrections require a '
          'recorded amendment with a reason — the signed content itself can '
          'never be edited again.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign and lock'),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false)) {
      return;
    }

    setState(() {
      _isBusy = true;
      _errorMessage = null;
    });
    try {
      // Save first so the signature covers the latest content: a signature
      // over stale text would freeze the wrong words. The use case re-reads
      // before signing, so a double-tap cannot sign twice.
      await ref
          .read(saveEncounterDraftUseCaseProvider)
          .call(
            policy: session.authorization,
            encounter: encounter,
            subjectiveNote: _subjectiveController.text,
            objectiveFindings: _objectiveController.text,
            assessment: _assessmentController.text,
            planDescription: _planController.text,
          );
      await ref
          .read(signEncounterUseCaseProvider)
          .call(
            policy: session.authorization,
            encounterId: encounter.id,
            signerUserId: userId,
          );
      ref.invalidate(encounterDetailProvider(widget.encounterId));
      ref.invalidate(encountersForPatientProvider(encounter.patientId));
    } on NodexError catch (error) {
      if (mounted) {
        setState(() => _errorMessage = error.message);
      }
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _amend(ClinicalEncounter encounter) async {
    final _AmendmentDraft? draft = await showModalBottomSheet<_AmendmentDraft>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) => const _AmendmentSheet(),
    );
    if (draft == null) {
      return;
    }

    final SessionState session = ref.read(sessionProvider);
    final String? userId = session.user?.userId;
    if (userId == null) {
      return;
    }

    setState(() {
      _isBusy = true;
      _errorMessage = null;
    });
    try {
      await ref
          .read(amendEncounterUseCaseProvider)
          .call(
            policy: session.authorization,
            encounter: encounter,
            reason: draft.reason,
            fieldChanges: draft.fieldChanges,
            amendedBy: userId,
            amendmentType: draft.amendmentType,
          );
      ref.invalidate(encounterDetailProvider(widget.encounterId));
      ref.invalidate(encountersForPatientProvider(encounter.patientId));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Amendment recorded.')));
      }
    } on NodexError catch (error) {
      if (mounted) {
        setState(() => _errorMessage = error.message);
      }
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }
}

class _Controllers {
  const _Controllers({
    required this.subjective,
    required this.objective,
    required this.assessment,
    required this.plan,
    required this.diagnoses,
  });

  final TextEditingController subjective;
  final TextEditingController objective;
  final TextEditingController assessment;
  final TextEditingController plan;
  final TextEditingController diagnoses;
}

class _EditorBody extends ConsumerWidget {
  const _EditorBody({
    required this.bundle,
    required this.controllers,
    required this.isBusy,
    required this.errorMessage,
    required this.onSave,
    required this.onSign,
    required this.onAmend,
  });

  final EncounterDetail bundle;
  final _Controllers controllers;
  final bool isBusy;
  final String? errorMessage;
  final VoidCallback onSave;
  final VoidCallback onSign;
  final VoidCallback onAmend;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final SessionState session = ref.watch(sessionProvider);
    final bool canWrite = session.authorization.can(
      NodexPermissions.encounterWrite,
    );
    final ClinicalEncounter encounter = bundle.encounter;
    final bool editable = canWrite && encounter.isEditable && !isBusy;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _StatusBanner(encounter: encounter),
        const SizedBox(height: 16),
        _SoapField(
          controller: controllers.subjective,
          label: 'Subjective',
          hint: 'Patient-reported symptoms and history',
          enabled: editable,
        ),
        const SizedBox(height: 12),
        _SoapField(
          controller: controllers.objective,
          label: 'Objective',
          hint: 'Examination findings, vitals, observations',
          enabled: editable,
        ),
        const SizedBox(height: 12),
        _SoapField(
          controller: controllers.assessment,
          label: 'Assessment',
          hint: 'Clinical impression',
          enabled: editable,
        ),
        const SizedBox(height: 12),
        _SoapField(
          controller: controllers.plan,
          label: 'Plan',
          hint: 'Orders, referrals, follow-up',
          enabled: editable,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: controllers.diagnoses,
          decoration: const InputDecoration(
            labelText: 'Diagnosis codes',
            helperText: 'Comma-separated codes, e.g. J06.9, R50.9',
            prefixIcon: Icon(Icons.tag_outlined),
          ),
          enabled: editable,
        ),
        if (errorMessage != null) ...<Widget>[
          const SizedBox(height: 16),
          Semantics(
            liveRegion: true,
            child: Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  errorMessage!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        if (encounter.isEditable && canWrite) ...<Widget>[
          FilledButton(
            onPressed: isBusy ? null : onSave,
            child: isBusy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save draft'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.verified_outlined),
            label: const Text('Sign and lock'),
            onPressed: isBusy ? null : onSign,
          ),
        ],
        if (encounter.isSigned && canWrite) ...<Widget>[
          OutlinedButton.icon(
            icon: const Icon(Icons.history_outlined),
            label: const Text('Record amendment'),
            onPressed: isBusy ? null : onAmend,
          ),
        ],
        if (bundle.amendments.isNotEmpty) ...<Widget>[
          const SizedBox(height: 24),
          Text('Amendments', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          ...bundle.amendments.map(
            (EncounterAmendment amendment) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.history_outlined),
                title: Text(amendment.reason),
                subtitle: Text(
                  '${amendment.amendmentType} · ${_formatDateTime(amendment.createdAt)}',
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  static String _formatDateTime(DateTime date) {
    final DateTime local = date.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.encounter});

  final ClinicalEncounter encounter;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final (IconData icon, String text) = switch (encounter.status) {
      EncounterStatus.planned => (
        Icons.event_outlined,
        'Planned — documentation has not started.',
      ),
      EncounterStatus.inProgress => (
        Icons.edit_note_outlined,
        'In progress — content is editable until signed.',
      ),
      EncounterStatus.signedAndLocked => (
        Icons.lock_outline,
        'Signed and locked. Corrections require a recorded amendment.',
      ),
      EncounterStatus.amended => (
        Icons.history_outlined,
        'Signed with amendments. The original content is unchanged; see below.',
      ),
    };
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: <Widget>[
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '${encounter.encounterType.label} encounter',
                    style: theme.textTheme.titleSmall,
                  ),
                  Text(
                    text,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SoapField extends StatelessWidget {
  const _SoapField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.enabled,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final bool enabled;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    decoration: InputDecoration(labelText: label, helperText: hint),
    maxLines: 4,
    minLines: 2,
    enabled: enabled,
    textCapitalization: TextCapitalization.sentences,
  );
}

class _AmendmentDraft {
  const _AmendmentDraft({
    required this.reason,
    required this.fieldChanges,
    required this.amendmentType,
  });

  final String reason;
  final Map<String, Object?> fieldChanges;
  final String amendmentType;
}

class _AmendmentSheet extends StatefulWidget {
  const _AmendmentSheet();

  @override
  State<_AmendmentSheet> createState() => _AmendmentSheetState();
}

class _AmendmentSheetState extends State<_AmendmentSheet> {
  final TextEditingController _reasonController = TextEditingController();
  final TextEditingController _changesController = TextEditingController();
  String _amendmentType = 'correction';

  @override
  void dispose() {
    _reasonController.dispose();
    _changesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double keyboard = MediaQuery.viewInsetsOf(context).bottom;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + keyboard),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('Record amendment', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'The signed record stays untouched. Describe what changed and why.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _amendmentType,
              decoration: const InputDecoration(labelText: 'Type'),
              items: const <DropdownMenuItem<String>>[
                DropdownMenuItem<String>(
                  value: 'correction',
                  child: Text('Correction'),
                ),
                DropdownMenuItem<String>(
                  value: 'addendum',
                  child: Text('Addendum'),
                ),
              ],
              onChanged: (String? value) {
                if (value != null) {
                  setState(() => _amendmentType = value);
                }
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason *',
                helperText: 'Required. Recorded permanently.',
              ),
              maxLines: 3,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _changesController,
              decoration: const InputDecoration(
                labelText: 'What changed *',
                helperText: 'Free-text summary, e.g. "Assessment revised"',
              ),
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () {
                final String reason = _reasonController.text.trim();
                final String changes = _changesController.text.trim();
                if (reason.isEmpty || changes.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Reason and changes are both required.'),
                    ),
                  );
                  return;
                }
                Navigator.of(context).pop(
                  _AmendmentDraft(
                    reason: reason,
                    fieldChanges: <String, Object?>{'summary': changes},
                    amendmentType: _amendmentType,
                  ),
                );
              },
              child: const Text('Record amendment'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditorError extends StatelessWidget {
  const _EditorError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String message = error is NodexError
        ? (error as NodexError).message
        : 'This encounter could not be loaded.';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.error_outline, size: 56, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(
              message,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}
