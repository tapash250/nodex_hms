/// Patient registration form (Module 10).
///
/// Writes locally first: the row commits to the encrypted projection
/// immediately and uploads in the background. The server enforces (tenant_id,
/// mrn) uniqueness finally. Raw national IDs are hashed in memory at submit
/// time and never stored, logged or transmitted.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/patients/patient.dart';
import 'package:nodex_hms/domain/session/session_state.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// Bottom-sheet patient registration form. Returns true when registered.
class RegisterPatientSheet extends ConsumerStatefulWidget {
  /// Creates the registration sheet.
  const RegisterPatientSheet({super.key});

  @override
  ConsumerState<RegisterPatientSheet> createState() =>
      _RegisterPatientSheetState();
}

class _RegisterPatientSheetState extends ConsumerState<RegisterPatientSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _mrnController = TextEditingController();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _dobController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _nationalIdController = TextEditingController();

  DateTime? _dateOfBirth;
  PatientGender _gender = PatientGender.unknown;
  BloodGroup? _bloodGroup;
  bool _isSubmitting = false;
  String? _errorMessage;
  Map<String, String> _fieldErrors = const <String, String>{};

  @override
  void dispose() {
    _mrnController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _dobController.dispose();
    _phoneController.dispose();
    _nationalIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double keyboard = MediaQuery.viewInsetsOf(context).bottom;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + keyboard),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Register patient',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Cancel',
                    onPressed: _isSubmitting
                        ? null
                        : () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Saved on this device first, then synchronized. Fields marked * are required.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _mrnController,
                decoration: _decoration(
                  'Medical record number *',
                  'Hospital-issued MRN',
                  'mrn',
                ),
                textInputAction: TextInputAction.next,
                enabled: !_isSubmitting,
                validator: (_) => _fieldErrors['mrn'],
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextFormField(
                      controller: _firstNameController,
                      decoration: _decoration(
                        'First name *',
                        null,
                        'first_name',
                      ),
                      textInputAction: TextInputAction.next,
                      enabled: !_isSubmitting,
                      validator: (_) => _fieldErrors['first_name'],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _lastNameController,
                      decoration: _decoration('Last name *', null, 'last_name'),
                      textInputAction: TextInputAction.next,
                      enabled: !_isSubmitting,
                      validator: (_) => _fieldErrors['last_name'],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _dobController,
                decoration:
                    _decoration(
                      'Date of birth *',
                      'YYYY-MM-DD',
                      'date_of_birth',
                    ).copyWith(
                      suffixIcon: const Icon(Icons.calendar_today_outlined),
                    ),
                readOnly: true,
                enabled: !_isSubmitting,
                validator: (_) => _fieldErrors['date_of_birth'],
                onTap: _isSubmitting ? null : _pickDate,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<PatientGender>(
                initialValue: _gender,
                decoration: const InputDecoration(labelText: 'Gender'),
                items: PatientGender.values
                    .map(
                      (PatientGender gender) => DropdownMenuItem<PatientGender>(
                        value: gender,
                        child: Text(_genderLabel(gender)),
                      ),
                    )
                    .toList(growable: false),
                onChanged: _isSubmitting
                    ? null
                    : (PatientGender? value) {
                        if (value != null) {
                          setState(() => _gender = value);
                        }
                      },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<BloodGroup?>(
                initialValue: _bloodGroup,
                decoration: const InputDecoration(
                  labelText: 'Blood group (optional)',
                ),
                items: <DropdownMenuItem<BloodGroup?>>[
                  const DropdownMenuItem<BloodGroup?>(
                    child: Text('Not recorded'),
                  ),
                  ...BloodGroup.values.map(
                    (BloodGroup group) => DropdownMenuItem<BloodGroup?>(
                      value: group,
                      child: Text(group.wireValue),
                    ),
                  ),
                ],
                onChanged: _isSubmitting
                    ? null
                    : (BloodGroup? value) =>
                          setState(() => _bloodGroup = value),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                decoration: _decoration(
                  'Phone (optional)',
                  null,
                  'phone_number',
                ),
                keyboardType: TextInputType.phone,
                enabled: !_isSubmitting,
                validator: (_) => _fieldErrors['phone_number'],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nationalIdController,
                decoration: const InputDecoration(
                  labelText: 'National ID (optional)',
                  helperText: 'Hashed on this device before saving. The raw number is never stored.',
                  helperMaxLines: 2,
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
                keyboardType: TextInputType.number,
                enabled: !_isSubmitting,
              ),
              if (_errorMessage != null) ...<Widget>[
                const SizedBox(height: 16),
                Semantics(
                  liveRegion: true,
                  child: Card(
                    color: theme.colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        _errorMessage!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _isSubmitting ? null : _submit,
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Register patient'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _decoration(String label, String? helper, String field) =>
      InputDecoration(
        labelText: label,
        helperText: helper,
        errorText: _fieldErrors[field],
      );

  static String _genderLabel(PatientGender gender) => switch (gender) {
    PatientGender.male => 'Male',
    PatientGender.female => 'Female',
    PatientGender.other => 'Other',
    PatientGender.unknown => 'Unknown / not recorded',
  };

  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 30, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null) {
      setState(() {
        _dateOfBirth = picked;
        _dobController.text =
            '${picked.year.toString().padLeft(4, '0')}-'
            '${picked.month.toString().padLeft(2, '0')}-'
            '${picked.day.toString().padLeft(2, '0')}';
      });
    }
  }

  Future<void> _submit() async {
    final SessionState session = ref.read(sessionProvider);
    final String? tenantId = session.tenantId;
    final String? userId = session.user?.userId;

    if (tenantId == null || userId == null) {
      setState(
        () => _errorMessage =
            'No active session. Sign in again to register patients.',
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
      _fieldErrors = const <String, String>{};
    });

    try {
      String? nationalIdHash;
      final String rawNationalId = _nationalIdController.text.trim();
      if (rawNationalId.isNotEmpty) {
        nationalIdHash = PatientIdentity.hashNationalId(rawNationalId);
      }
      // The raw number never leaves this method: hashed, then the controller
      // is cleared below regardless of outcome.
      _nationalIdController.clear();

      final DateTime dob =
          _dateOfBirth ??
          (throw const ValidationError(
            message: 'Date of birth is required.',
            fieldErrors: <String, String>{
              'date_of_birth': 'Choose the date of birth.',
            },
            code: 'patient_dob_required',
          ));

      await ref
          .read(registerPatientUseCaseProvider)
          .call(
            policy: session.authorization,
            tenantId: tenantId,
            userId: userId,
            mrn: _mrnController.text,
            firstName: _firstNameController.text,
            lastName: _lastNameController.text,
            dateOfBirth: dob,
            gender: _gender,
            nationalIdHash: nationalIdHash,
            bloodGroup: _bloodGroup,
            phoneNumber: _phoneController.text.trim().isEmpty
                ? null
                : _phoneController.text,
          );

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on ValidationError catch (error) {
      if (mounted) {
        setState(() {
          _errorMessage = error.message;
          _fieldErrors = error.fieldErrors;
        });
        _formKey.currentState?.validate();
      }
    } on NodexError catch (error) {
      if (mounted) {
        setState(() => _errorMessage = error.message);
      }
    } on Object {
      if (mounted) {
        setState(
          () => _errorMessage =
              'Registration could not be completed. The entry was not saved.',
        );
      }
    } finally {
      _nationalIdController.clear();
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }
}
