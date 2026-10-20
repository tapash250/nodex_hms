/// The clinical form runner (Module 47).
///
/// The runner walks the steps of a template, asks only the fields the answers
/// so far call for, and refuses to move on until the step is answered. The
/// same rules run on submission, so a form that the runner accepted is a form
/// the record accepts.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/forms/form_schema.dart';
import 'package:nodex_hms/domain/forms/form_template.dart';
import 'package:nodex_hms/domain/forms/form_validation.dart';
import 'package:nodex_hms/domain/forms/icd10.dart';
import 'package:nodex_hms/domain/session/session_state.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// One template, read from the device.
final formTemplateProvider = FutureProvider.autoDispose
    .family<FormTemplate?, String>((Ref ref, String templateId) async {
      return ref.watch(formRepositoryProvider).getTemplate(templateId);
    });

/// The ICD-10 suggestions for what has been typed.
final icd10SuggestionsProvider = FutureProvider.autoDispose
    .family<List<Icd10Code>, String>((Ref ref, String query) async {
      if (query.trim().isEmpty) return const <Icd10Code>[];
      return ref
          .watch(searchIcd10UseCaseProvider)
          .call(
            policy: ref.watch(sessionProvider).authorization,
            query: query,
            limit: 8,
          );
    });

/// Fills in one clinical form.
class FormRunnerScreen extends ConsumerStatefulWidget {
  /// Creates the runner.
  const FormRunnerScreen({required this.templateId, this.patientId, super.key});

  /// The template being filled in.
  final String templateId;

  /// The patient the form is about, when there is one.
  final String? patientId;

  @override
  ConsumerState<FormRunnerScreen> createState() => _FormRunnerScreenState();
}

class _FormRunnerScreenState extends ConsumerState<FormRunnerScreen> {
  final Map<String, Object?> _values = <String, Object?>{};
  final Map<String, List<FormValidationError>> _errors =
      <String, List<FormValidationError>>{};
  int _step = 0;
  bool _submitting = false;

  Future<void> _advance(FormTemplate template) async {
    final Map<String, List<FormValidationError>> found = validateStep(
      template.schema,
      _step,
      _values,
    );
    setState(() {
      _errors
        ..clear()
        ..addAll(found);
    });
    if (found.isNotEmpty) return;

    if (_step < template.schema.stepCount - 1) {
      setState(() => _step++);
      return;
    }
    await _submit(template);
  }

  void _back() {
    if (_step == 0) return;
    setState(() {
      _step--;
      _errors.clear();
    });
  }

  Future<void> _submit(FormTemplate template) async {
    final SessionState session = ref.read(sessionProvider);
    final String? tenantId = session.tenantId;
    final String? userId = session.user?.userId;
    if (tenantId == null || userId == null) return;
    setState(() => _submitting = true);
    try {
      await ref
          .read(submitFormResponseUseCaseProvider)
          .call(
            policy: session.authorization,
            tenantId: tenantId,
            template: template,
            submittedBy: userId,
            values: _values,
            patientId: widget.patientId,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Form recorded.')));
      Navigator.of(context).pop(true);
    } on NodexError catch (error) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<FormTemplate?> template = ref.watch(
      formTemplateProvider(widget.templateId),
    );
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Form')),
      body: template.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace _) => Center(
          child: Text(
            error is NodexError ? error.message : 'The form is unavailable.',
          ),
        ),
        data: (FormTemplate? value) {
          if (value == null) {
            return const Center(child: Text('This form is not on the device.'));
          }
          if (!value.isFillable) {
            return const Center(
              child: Text('Only a published form can be filled in.'),
            );
          }
          final FormSchema schema = value.schema;
          final List<FormFieldSchema> fields = schema
              .fieldsForStep(_step)
              .where((FormFieldSchema field) => isFieldVisible(field, _values))
              .toList(growable: false);
          final String stepTitle = _step < schema.steps.length
              ? schema.steps[_step].title
              : 'Step ${_step + 1} of ${schema.stepCount}';

          return Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(value.title, style: theme.textTheme.titleMedium),
                    Text(stepTitle, style: theme.textTheme.bodySmall),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: schema.stepCount == 0
                          ? 1
                          : (_step + 1) / schema.stepCount,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: <Widget>[
                    for (final FormFieldSchema field in fields)
                      _FieldControl(
                        field: field,
                        value: _values[field.id],
                        errors:
                            _errors[field.id] ?? const <FormValidationError>[],
                        onChanged: (Object? answer) =>
                            setState(() => _values[field.id] = answer),
                      ),
                  ],
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: <Widget>[
                      if (_step > 0)
                        TextButton(onPressed: _back, child: const Text('Back')),
                      const Spacer(),
                      FilledButton(
                        onPressed: _submitting ? null : () => _advance(value),
                        child: Text(
                          _step < schema.stepCount - 1 ? 'Next' : 'Submit',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One field of the form.
class _FieldControl extends ConsumerWidget {
  const _FieldControl({
    required this.field,
    required this.value,
    required this.errors,
    required this.onChanged,
  });

  final FormFieldSchema field;
  final Object? value;
  final List<FormValidationError> errors;
  final ValueChanged<Object?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final String? firstError = errors.isEmpty ? null : errors.first.message;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            field.required ? '${field.label} *' : field.label,
            style: theme.textTheme.labelLarge,
          ),
          if (field.helpText != null)
            Text(field.helpText!, style: theme.textTheme.bodySmall),
          const SizedBox(height: 4),
          switch (field.type) {
            FormFieldType.text => TextFormField(
              initialValue: value as String? ?? '',
              onChanged: onChanged,
              decoration: InputDecoration(errorText: firstError),
            ),
            FormFieldType.longText => TextFormField(
              initialValue: value as String? ?? '',
              onChanged: onChanged,
              maxLines: 4,
              decoration: InputDecoration(errorText: firstError),
            ),
            FormFieldType.number || FormFieldType.integer => TextFormField(
              initialValue: value?.toString() ?? '',
              onChanged: (String text) =>
                  onChanged(text.trim().isEmpty ? null : num.tryParse(text)),
              keyboardType: const TextInputType.numberWithOptions(
                signed: true,
                decimal: true,
              ),
              decoration: InputDecoration(errorText: firstError),
            ),
            FormFieldType.boolean => SwitchListTile(
              value: value == true,
              onChanged: onChanged,
              title: const SizedBox.shrink(),
              contentPadding: EdgeInsets.zero,
            ),
            FormFieldType.singleSelect => DropdownButtonFormField<String>(
              initialValue: value as String?,
              decoration: InputDecoration(errorText: firstError),
              items: field.options
                  .map(
                    (FormOption option) => DropdownMenuItem<String>(
                      value: option.value,
                      child: Text(option.label),
                    ),
                  )
                  .toList(growable: false),
              onChanged: onChanged,
            ),
            FormFieldType.multiSelect => Column(
              children: <Widget>[
                for (final FormOption option in field.options)
                  CheckboxListTile(
                    value:
                        (value as List<Object?>?)?.contains(option.value) ??
                        false,
                    title: Text(option.label),
                    onChanged: (bool? checked) {
                      final List<Object?> chosen = <Object?>[
                        ...(value as List<Object?>?) ?? const <Object?>[],
                      ];
                      if (checked == true) {
                        chosen.add(option.value);
                      } else {
                        chosen.remove(option.value);
                      }
                      onChanged(chosen);
                    },
                  ),
              ],
            ),
            FormFieldType.date => TextFormField(
              initialValue: value as String? ?? '',
              readOnly: true,
              decoration: InputDecoration(
                errorText: firstError,
                suffixIcon: const Icon(Icons.event_outlined),
              ),
              onTap: () async {
                final DateTime now = DateTime.now();
                final DateTime? picked = await showDatePicker(
                  context: context,
                  initialDate: now,
                  firstDate: DateTime(now.year - 5),
                  lastDate: DateTime(now.year + 5),
                );
                if (picked != null) {
                  onChanged(picked.toIso8601String().split('T').first);
                }
              },
            ),
            FormFieldType.icd10 => _Icd10Field(
              value: value as String?,
              error: firstError,
              onChanged: onChanged,
            ),
          },
        ],
      ),
    );
  }
}

/// A field that offers ICD-10 codes as they are typed.
class _Icd10Field extends ConsumerWidget {
  const _Icd10Field({
    required this.value,
    required this.error,
    required this.onChanged,
  });

  final String? value;
  final String? error;
  final ValueChanged<Object?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Icd10Code>> suggestions = ref.watch(
      icd10SuggestionsProvider(value ?? ''),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TextFormField(
          initialValue: value ?? '',
          onChanged: onChanged,
          decoration: InputDecoration(
            errorText: error,
            hintText: 'E11.9',
            suffixIcon: const Icon(Icons.search),
          ),
        ),
        suggestions.when(
          loading: () => const SizedBox.shrink(),
          error: (Object error, StackTrace _) => const SizedBox.shrink(),
          data: (List<Icd10Code> codes) => codes.isEmpty
              ? const SizedBox.shrink()
              : Column(
                  children: <Widget>[
                    for (final Icd10Code code in codes)
                      ListTile(
                        dense: true,
                        title: Text('${code.code} — ${code.description}'),
                        onTap: () => onChanged(code.code),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
