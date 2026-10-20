/// Form validation (Module 47).
///
/// The rules a form has to satisfy are stated once, here, and the runner and
/// the submission path both use them. A form that validates on screen but
/// fails on the server is a form that loses the clinician's work; a form that
/// validates on the server but not on screen is a form that is filled in
/// twice.
library;

import 'package:meta/meta.dart';
import 'package:nodex_hms/domain/forms/form_schema.dart';

/// The answers given so far.
typedef FormValues = Map<String, Object?>;

/// One thing that is wrong with an answer.
@immutable
final class FormValidationError {
  /// Declares an error.
  const FormValidationError({
    required this.fieldId,
    required this.message,
    required this.code,
  });

  /// The field the error belongs to.
  final String fieldId;

  /// The words shown to the clinician.
  final String message;

  /// A stable code for the error.
  final String code;

  @override
  String toString() => '$fieldId: $message';
}

/// Whether a field is asked, given the answers so far.
///
/// A field with no condition is always asked. A field whose condition is not
/// met is not asked — and, importantly, is not required: a hidden field must
/// never block a form, because the clinician was never given the chance to
/// answer it.
bool isFieldVisible(FormFieldSchema field, FormValues values) {
  final FormCondition? condition = field.visibleWhen;
  if (condition == null) return true;
  final Object? answer = values[condition.fieldId];
  return _matches(condition, answer);
}

bool _matches(FormCondition condition, Object? answer) {
  switch (condition.operator) {
    case ConditionOperator.equals:
      return _asText(answer) == _asText(condition.value);
    case ConditionOperator.notEquals:
      return _asText(answer) != _asText(condition.value);
    case ConditionOperator.contains:
      if (answer is List<Object?>) {
        return answer.map(_asText).contains(_asText(condition.value));
      }
      return _asText(answer).contains(_asText(condition.value));
    case ConditionOperator.greaterThan:
      final num? left = _asNum(answer);
      final num? right = _asNum(condition.value);
      return left != null && right != null && left > right;
    case ConditionOperator.lessThan:
      final num? left = _asNum(answer);
      final num? right = _asNum(condition.value);
      return left != null && right != null && left < right;
    case ConditionOperator.isTrue:
      return answer == true;
    case ConditionOperator.isFalse:
      return answer == false;
    case ConditionOperator.isNotEmpty:
      return _isEmpty(answer) == false;
    case ConditionOperator.isEmpty:
      return _isEmpty(answer);
  }
}

bool _isEmpty(Object? answer) {
  if (answer == null) return true;
  if (answer is String) return answer.trim().isEmpty;
  if (answer is List<Object?>) return answer.isEmpty;
  return false;
}

String _asText(Object? value) => value == null ? '' : '$value';

num? _asNum(Object? value) {
  if (value is num) return value;
  if (value is String) return num.tryParse(value.trim());
  return null;
}

/// Checks one answer against its field.
///
/// A field that is not shown is not checked: an answer that is not asked for
/// is not wrong.
List<FormValidationError> validateField(
  FormFieldSchema field,
  FormValues values,
) {
  if (!isFieldVisible(field, values)) return const <FormValidationError>[];
  final Object? answer = values[field.id];
  final List<FormValidationError> errors = <FormValidationError>[];

  if (_isEmpty(answer)) {
    if (field.required) {
      errors.add(
        FormValidationError(
          fieldId: field.id,
          message: '${field.label} is required.',
          code: 'field_required',
        ),
      );
    }
    return errors;
  }

  switch (field.type) {
    case FormFieldType.text:
    case FormFieldType.longText:
      final String text = _asText(answer);
      final int? maxLength = field.maxLength;
      if (maxLength != null && text.length > maxLength) {
        errors.add(
          FormValidationError(
            fieldId: field.id,
            message: '${field.label} must be $maxLength characters or fewer.',
            code: 'field_too_long',
          ),
        );
      }
      final String? pattern = field.pattern;
      if (pattern != null && !RegExp(pattern).hasMatch(text)) {
        errors.add(
          FormValidationError(
            fieldId: field.id,
            message: '${field.label} is not in the expected format.',
            code: 'field_pattern_mismatch',
          ),
        );
      }
    case FormFieldType.number:
    case FormFieldType.integer:
      final num? number = _asNum(answer);
      if (number == null) {
        errors.add(
          FormValidationError(
            fieldId: field.id,
            message: '${field.label} must be a number.',
            code: 'field_not_a_number',
          ),
        );
        break;
      }
      if (field.type == FormFieldType.integer &&
          number != number.roundToDouble()) {
        errors.add(
          FormValidationError(
            fieldId: field.id,
            message: '${field.label} must be a whole number.',
            code: 'field_not_an_integer',
          ),
        );
      }
      final num? min = field.minValue;
      if (min != null && number < min) {
        errors.add(
          FormValidationError(
            fieldId: field.id,
            message: '${field.label} must be $min or more.',
            code: 'field_too_small',
          ),
        );
      }
      final num? max = field.maxValue;
      if (max != null && number > max) {
        errors.add(
          FormValidationError(
            fieldId: field.id,
            message: '${field.label} must be $max or less.',
            code: 'field_too_large',
          ),
        );
      }
    case FormFieldType.boolean:
      if (answer is! bool) {
        errors.add(
          FormValidationError(
            fieldId: field.id,
            message: '${field.label} must be yes or no.',
            code: 'field_not_a_boolean',
          ),
        );
      }
    case FormFieldType.singleSelect:
      if (!field.options.any(
        (FormOption option) => option.value == _asText(answer),
      )) {
        errors.add(
          FormValidationError(
            fieldId: field.id,
            message: '${field.label} is not one of the offered choices.',
            code: 'field_not_an_option',
          ),
        );
      }
    case FormFieldType.multiSelect:
      if (answer is List<Object?>) {
        for (final Object? choice in answer) {
          if (!field.options.any(
            (FormOption option) => option.value == _asText(choice),
          )) {
            errors.add(
              FormValidationError(
                fieldId: field.id,
                message:
                    '${field.label} includes a choice that is not offered.',
                code: 'field_not_an_option',
              ),
            );
            break;
          }
        }
      } else {
        errors.add(
          FormValidationError(
            fieldId: field.id,
            message: '${field.label} must be a list of choices.',
            code: 'field_not_a_list',
          ),
        );
      }
    case FormFieldType.date:
      if (DateTime.tryParse(_asText(answer)) == null) {
        errors.add(
          FormValidationError(
            fieldId: field.id,
            message: '${field.label} must be a date.',
            code: 'field_not_a_date',
          ),
        );
      }
    case FormFieldType.icd10:
      final String code = _asText(answer).toUpperCase();
      if (!RegExp(r'^[A-Z][0-9]{2}(\.[0-9A-Z]{1,4})?$').hasMatch(code)) {
        errors.add(
          FormValidationError(
            fieldId: field.id,
            message: '${field.label} must be an ICD-10 code.',
            code: 'field_not_an_icd10_code',
          ),
        );
      }
  }
  return errors;
}

/// Checks every answer of one step.
///
/// The errors are keyed by field so the runner can put each message under the
/// control it belongs to.
Map<String, List<FormValidationError>> validateStep(
  FormSchema schema,
  int step,
  FormValues values,
) {
  final Map<String, List<FormValidationError>> errors =
      <String, List<FormValidationError>>{};
  for (final FormFieldSchema field in schema.fieldsForStep(step)) {
    final List<FormValidationError> fieldErrors = validateField(field, values);
    if (fieldErrors.isNotEmpty) errors[field.id] = fieldErrors;
  }
  return errors;
}

/// Checks every answer of the form.
List<FormValidationError> validateAll(FormSchema schema, FormValues values) {
  final List<FormValidationError> errors = <FormValidationError>[];
  for (final FormFieldSchema field in schema.fields) {
    errors.addAll(validateField(field, values));
  }
  return errors;
}

/// Whether a step may be left.
///
/// A step with an unanswered required field is not left: the clinician is
/// told which field stopped them, rather than being told the form is invalid.
bool canLeaveStep(
  FormSchema schema,
  int step,
  FormValues values, {
  Map<String, List<FormValidationError>>? errors,
}) {
  final Map<String, List<FormValidationError>> found =
      errors ?? validateStep(schema, step, values);
  return found.isEmpty;
}
