/// Clinical form schemas (Module 47).
///
/// A template is a JSON document: a list of fields, each with a type, a step,
/// and the conditions that decide whether it is asked. Nothing in the engine
/// knows what a form is *for* — a consent, a triage score, a discharge
/// checklist — because the schema says what to ask and the engine says how to
/// ask it.
// ignore_for_file: sort_constructors_first
library;

import 'package:meta/meta.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';

/// The kind of answer a field expects.
enum FormFieldType {
  /// A single line of text.
  text('text'),

  /// Several lines of text.
  longText('long_text'),

  /// A number.
  number('number'),

  /// A whole number.
  integer('integer'),

  /// A yes or no.
  boolean('boolean'),

  /// One choice from a list.
  singleSelect('single_select'),

  /// Several choices from a list.
  multiSelect('multi_select'),

  /// A date.
  date('date'),

  /// An ICD-10 diagnosis code.
  icd10('icd10');

  const FormFieldType(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Parses a stored value.
  static FormFieldType fromWire(String value) =>
      FormFieldType.values.firstWhere(
        (FormFieldType type) => type.wireValue == value,
        orElse: () => FormFieldType.text,
      );
}

/// One choice of a selection field.
@immutable
final class FormOption {
  /// Declares an option.
  const FormOption({required this.value, required this.label});

  /// The stored value.
  final String value;

  /// The words shown.
  final String label;

  /// Reads an option from JSON.
  factory FormOption.fromJson(Map<String, Object?> json) => FormOption(
    value: (json['value'] ?? '').toString(),
    label: (json['label'] ?? json['value'] ?? '').toString(),
  );

  /// Writes the option to JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'value': value,
    'label': label,
  };
}

/// How a condition compares an answer.
enum ConditionOperator {
  /// The answer is the same as the condition's value.
  equals('equals'),

  /// The answer differs from the condition's value.
  notEquals('not_equals'),

  /// The answer contains the condition's value.
  contains('contains'),

  /// The answer is greater than the condition's value.
  greaterThan('greater_than'),

  /// The answer is less than the condition's value.
  lessThan('less_than'),

  /// The answer is yes.
  isTrue('is_true'),

  /// The answer is no.
  isFalse('is_false'),

  /// The answer holds something.
  isNotEmpty('is_not_empty'),

  /// The answer holds nothing.
  isEmpty('is_empty');

  const ConditionOperator(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Parses a stored value.
  static ConditionOperator fromWire(String value) =>
      ConditionOperator.values.firstWhere(
        (ConditionOperator operator) => operator.wireValue == value,
        orElse: () => ConditionOperator.equals,
      );
}

/// The rule that decides whether a field is asked.
@immutable
final class FormCondition {
  /// Declares a condition.
  const FormCondition({
    required this.fieldId,
    required this.operator,
    this.value,
  });

  /// The field the condition watches.
  final String fieldId;

  /// How the answer is compared.
  final ConditionOperator operator;

  /// The value the answer is compared with.
  final Object? value;

  /// Reads a condition from JSON.
  factory FormCondition.fromJson(Map<String, Object?> json) => FormCondition(
    fieldId: (json['fieldId'] ?? '').toString(),
    operator: ConditionOperator.fromWire(
      (json['operator'] ?? 'equals').toString(),
    ),
    value: json['value'],
  );

  /// Writes the condition to JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'fieldId': fieldId,
    'operator': operator.wireValue,
    'value': value,
  };
}

/// One field of a form.
@immutable
final class FormFieldSchema {
  /// Declares a field.
  const FormFieldSchema({
    required this.id,
    required this.label,
    required this.type,
    this.required = false,
    this.step = 0,
    this.helpText,
    this.options = const <FormOption>[],
    this.minValue,
    this.maxValue,
    this.maxLength,
    this.pattern,
    this.visibleWhen,
  });

  /// Identifier, unique within the template.
  final String id;

  /// The words shown above the control.
  final String label;

  /// The kind of answer.
  final FormFieldType type;

  /// Whether the field must be answered.
  final bool required;

  /// The step the field belongs to.
  final int step;

  /// Guidance shown under the control.
  final String? helpText;

  /// The choices of a selection field.
  final List<FormOption> options;

  /// Lowest acceptable number.
  final num? minValue;

  /// Highest acceptable number.
  final num? maxValue;

  /// Longest acceptable text.
  final int? maxLength;

  /// A pattern the text must match.
  final String? pattern;

  /// The rule that decides whether the field is asked.
  final FormCondition? visibleWhen;

  /// Reads a field from JSON.
  factory FormFieldSchema.fromJson(Map<String, Object?> json) {
    final Object? rawOptions = json['options'];
    return FormFieldSchema(
      id: (json['id'] ?? '').toString(),
      label: (json['label'] ?? '').toString(),
      type: FormFieldType.fromWire((json['type'] ?? 'text').toString()),
      required: json['required'] == true,
      step: _asInt(json['step']),
      helpText: json['helpText'] as String?,
      options: rawOptions is List<Object?>
          ? rawOptions
                .whereType<Map<Object?, Object?>>()
                .map(
                  (Map<Object?, Object?> option) =>
                      FormOption.fromJson(option.cast<String, Object?>()),
                )
                .toList(growable: false)
          : const <FormOption>[],
      minValue: _asNum(json['minValue']),
      maxValue: _asNum(json['maxValue']),
      maxLength: json['maxLength'] == null ? null : _asInt(json['maxLength']),
      pattern: json['pattern'] as String?,
      visibleWhen: json['visibleWhen'] is Map<Object?, Object?>
          ? FormCondition.fromJson(
              (json['visibleWhen']! as Map<Object?, Object?>)
                  .cast<String, Object?>(),
            )
          : null,
    );
  }

  /// Writes the field to JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'label': label,
    'type': type.wireValue,
    'required': required,
    'step': step,
    if (helpText != null) 'helpText': helpText,
    if (options.isNotEmpty)
      'options': options.map((FormOption option) => option.toJson()).toList(),
    if (minValue != null) 'minValue': minValue,
    if (maxValue != null) 'maxValue': maxValue,
    if (maxLength != null) 'maxLength': maxLength,
    if (pattern != null) 'pattern': pattern,
    if (visibleWhen != null) 'visibleWhen': visibleWhen!.toJson(),
  };

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse((value ?? '').toString()) ?? 0;
  }

  static num? _asNum(Object? value) {
    if (value is num) return value;
    if (value is String) return num.tryParse(value);
    return null;
  }
}

/// One step of a form.
@immutable
final class FormStepSchema {
  /// Declares a step.
  const FormStepSchema({required this.title, this.description});

  /// The heading of the step.
  final String title;

  /// Guidance shown under the heading.
  final String? description;

  /// Reads a step from JSON.
  factory FormStepSchema.fromJson(Map<String, Object?> json) => FormStepSchema(
    title: (json['title'] ?? '').toString(),
    description: json['description'] as String?,
  );

  /// Writes the step to JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'title': title,
    if (description != null) 'description': description,
  };
}

/// A whole form.
@immutable
final class FormSchema {
  /// Declares a form.
  const FormSchema({
    required this.code,
    required this.title,
    required this.version,
    required this.fields,
    this.description,
    this.steps = const <FormStepSchema>[],
  });

  /// The template code.
  final String code;

  /// The title of the form.
  final String title;

  /// The version of the template this schema came from.
  final int version;

  /// The fields of the form.
  final List<FormFieldSchema> fields;

  /// What the form is for.
  final String? description;

  /// The steps of the form.
  final List<FormStepSchema> steps;

  /// Reads a form from JSON.
  ///
  /// A schema that cannot be read is a template nobody can fill in, so this
  /// fails loudly rather than producing a form with no fields.
  factory FormSchema.fromJson(
    Map<String, Object?> json, {
    String? code,
    int version = 1,
    String? title,
  }) {
    final Object? rawFields = json['fields'];
    if (rawFields is! List<Object?>) {
      throw const ValidationError(
        message: 'The form template has no fields.',
        code: 'form_schema_invalid',
      );
    }
    final Object? rawSteps = json['steps'];
    return FormSchema(
      code: code ?? (json['code'] ?? '').toString(),
      title: title ?? (json['title'] ?? '').toString(),
      version: version,
      description: json['description'] as String?,
      fields: rawFields
          .whereType<Map<Object?, Object?>>()
          .map(
            (Map<Object?, Object?> field) =>
                FormFieldSchema.fromJson(field.cast<String, Object?>()),
          )
          .toList(growable: false),
      steps: rawSteps is List<Object?>
          ? rawSteps
                .whereType<Map<Object?, Object?>>()
                .map(
                  (Map<Object?, Object?> step) =>
                      FormStepSchema.fromJson(step.cast<String, Object?>()),
                )
                .toList(growable: false)
          : const <FormStepSchema>[],
    );
  }

  /// Writes the form to JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'code': code,
    'title': title,
    'version': version,
    if (description != null) 'description': description,
    'steps': steps.map((FormStepSchema step) => step.toJson()).toList(),
    'fields': fields.map((FormFieldSchema field) => field.toJson()).toList(),
  };

  /// The fields of one step.
  List<FormFieldSchema> fieldsForStep(int step) => fields
      .where((FormFieldSchema field) => field.step == step)
      .toList(growable: false);

  /// How many steps the form has.
  ///
  /// A schema with no declared steps still has one: its fields all live on
  /// step zero.
  int get stepCount {
    if (steps.isNotEmpty) return steps.length;
    int highest = 0;
    for (final FormFieldSchema field in fields) {
      if (field.step > highest) highest = field.step;
    }
    return highest + 1;
  }

  /// The field with the given id, or null.
  FormFieldSchema? fieldById(String id) {
    for (final FormFieldSchema field in fields) {
      if (field.id == id) return field;
    }
    return null;
  }
}
