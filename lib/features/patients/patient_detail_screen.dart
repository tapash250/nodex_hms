/// Patient detail screen (Module 10).
///
/// Shows identity, contact details and the allergy list. Contact fields edit
/// through the contact update use case (mergeable columns only); allergies
/// are recorded and retired, never edited. Identity correction goes through the
/// merge workflow, which this screen links to rather than implements inline.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/patients/patient.dart';
import 'package:nodex_hms/domain/session/session_state.dart';
import 'package:nodex_hms/features/encounters/encounter_list_section.dart';
import 'package:nodex_hms/features/patients/patients_controller.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// Detail screen for one patient.
class PatientDetailScreen extends ConsumerWidget {
  /// Creates the detail screen.
  const PatientDetailScreen({required this.patientId, super.key});

  /// Local patient id.
  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<PatientDetail> detail = ref.watch(
      patientDetailProvider(patientId),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Patient record')),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace _) => _DetailError(
          error: error,
          onRetry: () => ref.invalidate(patientDetailProvider(patientId)),
        ),
        data: (PatientDetail bundle) => _DetailBody(bundle: bundle),
      ),
    );
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({required this.bundle});

  final PatientDetail bundle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final SessionState session = ref.watch(sessionProvider);
    final bool canWrite = session.authorization.can(
      NodexPermissions.patientWrite,
    );
    final Patient patient = bundle.patient;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    CircleAvatar(
                      radius: 28,
                      child: Text(
                        _initials(patient),
                        style: theme.textTheme.headlineSmall,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            patient.displayName,
                            style: theme.textTheme.titleLarge,
                          ),
                          Text(
                            'MRN ${patient.mrn} · ${patient.ageAt()}y · ${patient.gender.wireValue}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 32),
                _FactRow(
                  label: 'Date of birth',
                  value: _formatDate(patient.dateOfBirth),
                ),
                if (patient.bloodGroup != null)
                  _FactRow(
                    label: 'Blood group',
                    value: patient.bloodGroup!.wireValue,
                  ),
                if (patient.phoneNumber != null)
                  _FactRow(label: 'Phone', value: patient.phoneNumber!),
                if (patient.email != null)
                  _FactRow(label: 'Email', value: patient.email!),
                if (patient.address != null)
                  _FactRow(label: 'Address', value: patient.address!),
                if (patient.nextOfKin != null)
                  _FactRow(label: 'Next of kin', value: patient.nextOfKin!),
                if (patient.occupation != null)
                  _FactRow(label: 'Occupation', value: patient.occupation!),
                if (patient.maritalStatus != null)
                  _FactRow(
                    label: 'Marital status',
                    value: patient.maritalStatus!,
                  ),
                if (patient.preferredLanguage != null)
                  _FactRow(
                    label: 'Preferred language',
                    value: patient.preferredLanguage!,
                  ),
                if (canWrite) ...<Widget>[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit contact details'),
                    onPressed: () => _editContact(context, ref, patient),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            Expanded(
              child: Text('Allergies', style: theme.textTheme.titleMedium),
            ),
            if (canWrite)
              TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Record'),
                onPressed: () => _recordAllergy(context, ref, patient),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (bundle.allergies.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'No allergies recorded. An empty list means "not yet asked", '
                'not "no known allergies" — confirm with the patient.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          )
        else
          ...bundle.allergies.map(
            (PatientAllergy allergy) => _AllergyCard(
              allergy: allergy,
              canWrite: canWrite,
              onRetire: () => _retireAllergy(context, ref, allergy),
            ),
          ),
        const SizedBox(height: 16),
        EncounterListSection(patient: bundle.patient),
      ],
    );
  }

  static String _initials(Patient patient) {
    final String a = patient.firstName.trim().isEmpty
        ? '?'
        : patient.firstName.trim()[0].toUpperCase();
    final String b = patient.lastName.trim().isEmpty
        ? ''
        : patient.lastName.trim()[0].toUpperCase();
    return '$a$b';
  }

  static String _formatDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  Future<void> _editContact(
    BuildContext context,
    WidgetRef ref,
    Patient patient,
  ) async {
    final Map<String, Object?>? changes =
        await showModalBottomSheet<Map<String, Object?>>(
          context: context,
          isScrollControlled: true,
          builder: (BuildContext context) =>
              _ContactEditSheet(patient: patient),
        );
    if (changes == null || changes.isEmpty) {
      return;
    }

    final SessionState session = ref.read(sessionProvider);
    try {
      await ref
          .read(updatePatientContactUseCaseProvider)
          .call(
            policy: session.authorization,
            patientId: patient.id,
            changes: changes,
          );
      ref.invalidate(patientDetailProvider(patient.id));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Contact details saved on this device.'),
          ),
        );
      }
    } on NodexError catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _recordAllergy(
    BuildContext context,
    WidgetRef ref,
    Patient patient,
  ) async {
    final _AllergyDraft? draft = await showModalBottomSheet<_AllergyDraft>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) => const _AllergyReportSheet(),
    );
    if (draft == null) {
      return;
    }

    final SessionState session = ref.read(sessionProvider);
    final String? tenantId = session.tenantId;
    final String? userId = session.user?.userId;
    if (tenantId == null || userId == null) {
      return;
    }

    try {
      await ref
          .read(recordAllergyUseCaseProvider)
          .call(
            policy: session.authorization,
            tenantId: tenantId,
            patientId: patient.id,
            substance: draft.substance,
            severity: draft.severity,
            reaction: draft.reaction,
            recordedBy: userId,
          );
      ref.invalidate(patientDetailProvider(patient.id));
    } on NodexError catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _retireAllergy(
    BuildContext context,
    WidgetRef ref,
    PatientAllergy allergy,
  ) async {
    final TextEditingController reasonController = TextEditingController();
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        final ThemeData theme = Theme.of(context);
        return AlertDialog(
          title: Text('Retire allergy: ${allergy.substance}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'The record stays in history; it stops appearing as active. '
                'To correct a wrong substance, retire this row and record a replacement.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: reasonController,
                decoration: const InputDecoration(
                  labelText: 'Reason *',
                  helperText: 'Required. Recorded permanently.',
                ),
                maxLines: 3,
                autofocus: true,
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Retire'),
            ),
          ],
        );
      },
    );

    final String reason = reasonController.text;
    reasonController.dispose();
    if (!(confirmed ?? false)) {
      return;
    }

    final SessionState session = ref.read(sessionProvider);
    try {
      await ref
          .read(retireAllergyUseCaseProvider)
          .call(
            policy: session.authorization,
            allergyId: allergy.id,
            reason: reason,
          );
      ref.invalidate(patientDetailProvider(allergy.patientId));
    } on NodexError catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AllergyCard extends StatelessWidget {
  const _AllergyCard({
    required this.allergy,
    required this.canWrite,
    required this.onRetire,
  });

  final PatientAllergy allergy;
  final bool canWrite;
  final VoidCallback onRetire;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool retired = !allergy.isActive;
    final Color severityColor = switch (allergy.severity) {
      AllergySeverity.severe => theme.colorScheme.error,
      AllergySeverity.moderate => theme.colorScheme.tertiary,
      _ => theme.colorScheme.primary,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          retired ? Icons.history_outlined : Icons.warning_amber_outlined,
          color: retired ? theme.colorScheme.onSurfaceVariant : severityColor,
        ),
        title: Text(
          allergy.substance,
          style: retired
              ? TextStyle(
                  decoration: TextDecoration.lineThrough,
                  color: theme.colorScheme.onSurfaceVariant,
                )
              : null,
        ),
        subtitle: Text(
          <String>[
            allergy.severity.wireValue,
            if (allergy.reaction != null) allergy.reaction!,
            if (retired && allergy.retiredReason != null)
              'Retired: ${allergy.retiredReason!}',
          ].join(' · '),
        ),
        trailing: canWrite && !retired
            ? TextButton(onPressed: onRetire, child: const Text('Retire'))
            : null,
      ),
    );
  }
}

class _ContactEditSheet extends StatefulWidget {
  const _ContactEditSheet({required this.patient});

  final Patient patient;

  @override
  State<_ContactEditSheet> createState() => _ContactEditSheetState();
}

class _ContactEditSheetState extends State<_ContactEditSheet> {
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _addressController;
  late final TextEditingController _nextOfKinController;
  late final TextEditingController _occupationController;
  late final TextEditingController _languageController;
  String? _maritalStatus;

  @override
  void initState() {
    super.initState();
    final Patient patient = widget.patient;
    _phoneController = TextEditingController(text: patient.phoneNumber ?? '');
    _emailController = TextEditingController(text: patient.email ?? '');
    _addressController = TextEditingController(text: patient.address ?? '');
    _nextOfKinController = TextEditingController(text: patient.nextOfKin ?? '');
    _occupationController = TextEditingController(
      text: patient.occupation ?? '',
    );
    _languageController = TextEditingController(
      text: patient.preferredLanguage ?? '',
    );
    _maritalStatus = patient.maritalStatus;
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _nextOfKinController.dispose();
    _occupationController.dispose();
    _languageController.dispose();
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
            Text('Edit contact details', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Identity fields (name, MRN, date of birth) change only through the merge workflow.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _phoneController,
              decoration: const InputDecoration(labelText: 'Phone'),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _addressController,
              decoration: const InputDecoration(labelText: 'Address'),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nextOfKinController,
              decoration: const InputDecoration(labelText: 'Next of kin'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _occupationController,
              decoration: const InputDecoration(labelText: 'Occupation'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _maritalStatus,
              decoration: const InputDecoration(labelText: 'Marital status'),
              items: const <DropdownMenuItem<String?>>[
                DropdownMenuItem<String?>(child: Text('Not recorded')),
                DropdownMenuItem<String?>(
                  value: 'single',
                  child: Text('Single'),
                ),
                DropdownMenuItem<String?>(
                  value: 'married',
                  child: Text('Married'),
                ),
                DropdownMenuItem<String?>(
                  value: 'divorced',
                  child: Text('Divorced'),
                ),
                DropdownMenuItem<String?>(
                  value: 'widowed',
                  child: Text('Widowed'),
                ),
                DropdownMenuItem<String?>(value: 'other', child: Text('Other')),
                DropdownMenuItem<String?>(
                  value: 'unknown',
                  child: Text('Unknown'),
                ),
              ],
              onChanged: (String? value) =>
                  setState(() => _maritalStatus = value),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _languageController,
              decoration: const InputDecoration(
                labelText: 'Preferred language',
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(_collectChanges()),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Map<String, Object?> _collectChanges() {
    String? clean(TextEditingController controller) {
      final String value = controller.text.trim();
      return value.isEmpty ? null : value;
    }

    final Patient patient = widget.patient;
    final Map<String, Object?> changes = <String, Object?>{};

    void put(String key, String? next, String? current) {
      if (next != current) {
        changes[key] = next;
      }
    }

    put('phone_number', clean(_phoneController), patient.phoneNumber);
    put('email', clean(_emailController), patient.email);
    put('address', clean(_addressController), patient.address);
    put('next_of_kin', clean(_nextOfKinController), patient.nextOfKin);
    put('occupation', clean(_occupationController), patient.occupation);
    put(
      'preferred_language',
      clean(_languageController),
      patient.preferredLanguage,
    );
    if (_maritalStatus != patient.maritalStatus) {
      changes['marital_status'] = _maritalStatus;
    }
    return changes;
  }
}

class _AllergyDraft {
  const _AllergyDraft({
    required this.substance,
    required this.severity,
    this.reaction,
  });

  final String substance;
  final AllergySeverity severity;
  final String? reaction;
}

class _AllergyReportSheet extends StatefulWidget {
  const _AllergyReportSheet();

  @override
  State<_AllergyReportSheet> createState() => _AllergyReportSheetState();
}

class _AllergyReportSheetState extends State<_AllergyReportSheet> {
  final TextEditingController _substanceController = TextEditingController();
  final TextEditingController _reactionController = TextEditingController();
  AllergySeverity _severity = AllergySeverity.unknown;

  @override
  void dispose() {
    _substanceController.dispose();
    _reactionController.dispose();
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
            Text('Record allergy', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _substanceController,
              decoration: const InputDecoration(
                labelText: 'Substance *',
                helperText: 'Drug, food or environmental trigger',
              ),
              autofocus: true,
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<AllergySeverity>(
              initialValue: _severity,
              decoration: const InputDecoration(labelText: 'Severity'),
              items: AllergySeverity.values
                  .map(
                    (AllergySeverity severity) =>
                        DropdownMenuItem<AllergySeverity>(
                          value: severity,
                          child: Text(severity.wireValue),
                        ),
                  )
                  .toList(growable: false),
              onChanged: (AllergySeverity? value) {
                if (value != null) {
                  setState(() => _severity = value);
                }
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reactionController,
              decoration: const InputDecoration(
                labelText: 'Reaction (optional)',
                helperText: 'What happens on exposure',
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () {
                final String substance = _substanceController.text.trim();
                if (substance.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Enter the substance.')),
                  );
                  return;
                }
                final String reaction = _reactionController.text.trim();
                Navigator.of(context).pop(
                  _AllergyDraft(
                    substance: substance,
                    severity: _severity,
                    reaction: reaction.isEmpty ? null : reaction,
                  ),
                );
              },
              child: const Text('Record allergy'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailError extends StatelessWidget {
  const _DetailError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String message = error is NodexError
        ? (error as NodexError).message
        : 'This record could not be loaded.';
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
