/// Form templates and responses (Module 47).
library;

import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/forms/form_schema.dart';
import 'package:nodex_hms/domain/forms/form_validation.dart';

/// Where a template stands.
enum FormTemplateStatus {
  /// Being written; nobody but its author can rely on it.
  draft('draft'),

  /// In force. Frozen.
  published('published'),

  /// Withdrawn. Kept because responses still refer to it.
  retired('retired');

  const FormTemplateStatus(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Parses a stored value.
  static FormTemplateStatus fromWire(String value) =>
      FormTemplateStatus.values.firstWhere(
        (FormTemplateStatus status) => status.wireValue == value,
        orElse: () => FormTemplateStatus.draft,
      );
}

/// A form template as the device holds it.
@immutable
final class FormTemplate {
  /// Creates a template.
  const FormTemplate({
    required this.id,
    required this.tenantId,
    required this.templateCode,
    required this.title,
    required this.version,
    required this.schema,
    required this.status,
    required this.createdBy,
    this.description,
    this.publishedAt,
    this.createdAt,
  });

  /// Reads a template from a local row.
  ///
  /// The schema is stored as the JSON the server holds, so a template that
  /// arrives on a device is the template the server published.
  factory FormTemplate.fromRow(Map<String, Object?> row) {
    final Object? rawSchema = row['schema_json'];
    final Map<String, Object?> decoded = switch (rawSchema) {
      final String text when text.trim().isNotEmpty =>
        jsonDecode(text) as Map<String, Object?>,
      final Map<Object?, Object?> map => map.cast<String, Object?>(),
      _ => <String, Object?>{},
    };
    return FormTemplate(
      id: row['id']! as String,
      tenantId: row['tenant_id']! as String,
      templateCode: row['template_code']! as String,
      title: row['title']! as String,
      description: row['description'] as String?,
      version: (row['version'] as int?) ?? 1,
      schema: FormSchema.fromJson(
        decoded,
        code: row['template_code']! as String,
        version: (row['version'] as int?) ?? 1,
        title: row['title']! as String,
      ),
      status: FormTemplateStatus.fromWire(row['status']! as String),
      createdBy: row['created_by']! as String,
      publishedAt: _parse(row['published_at']),
      createdAt: _parse(row['created_at']),
    );
  }

  static DateTime? _parse(Object? value) =>
      value == null ? null : DateTime.parse(value as String);

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// The code the form is referred to by.
  final String templateCode;

  /// The title of the form.
  final String title;

  /// What the form is for.
  final String? description;

  /// The version of the template.
  final int version;

  /// The schema the form is built from.
  final FormSchema schema;

  /// Where the template stands.
  final FormTemplateStatus status;

  /// The author.
  final String createdBy;

  /// When it was published.
  final DateTime? publishedAt;

  /// When it was written.
  final DateTime? createdAt;

  /// Whether the template may be filled in.
  bool get isFillable => status == FormTemplateStatus.published;
}

/// A filled form.
@immutable
final class FormResponse {
  /// Creates a response.
  const FormResponse({
    required this.id,
    required this.tenantId,
    required this.templateId,
    required this.templateVersion,
    required this.submittedBy,
    required this.values,
    required this.submittedAt,
    this.patientId,
    this.encounterId,
  });

  /// Reads a response from a local row.
  factory FormResponse.fromRow(Map<String, Object?> row) {
    final Object? rawValues = row['values_json'];
    return FormResponse(
      id: row['id']! as String,
      tenantId: row['tenant_id']! as String,
      templateId: row['template_id']! as String,
      templateVersion: (row['template_version'] as int?) ?? 1,
      patientId: row['patient_id'] as String?,
      encounterId: row['encounter_id'] as String?,
      submittedBy: row['submitted_by']! as String,
      values: switch (rawValues) {
        final String text when text.trim().isNotEmpty =>
          (jsonDecode(text) as Map<String, Object?>),
        final Map<Object?, Object?> map => map.cast<String, Object?>(),
        _ => <String, Object?>{},
      },
      submittedAt: DateTime.parse(row['submitted_at']! as String),
    );
  }

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// The template that was filled in.
  final String templateId;

  /// The version of the template that was filled in.
  final int templateVersion;

  /// The patient the form is about.
  final String? patientId;

  /// The encounter the form belongs to.
  final String? encounterId;

  /// The clinician who filled it in.
  final String submittedBy;

  /// The answers.
  final Map<String, Object?> values;

  /// When it was filled in.
  final DateTime submittedAt;
}

/// Builds the row that records a filled form.
///
/// The answers are validated against the schema before the row is built, so a
/// response that does not satisfy the form it claims to satisfy is never
/// written.
Map<String, Object?> buildResponseRow({
  required String tenantId,
  required FormTemplate template,
  required String submittedBy,
  required Map<String, Object?> values,
  String? patientId,
  String? encounterId,
}) {
  if (!template.isFillable) {
    throw const ValidationError(
      message: 'Only a published form can be filled in.',
      code: 'form_template_not_published',
    );
  }
  final List<FormValidationError> errors = validateTemplateValues(
    template,
    values,
  );
  if (errors.isNotEmpty) {
    throw ValidationError(
      message: 'The form is not complete.',
      fieldErrors: <String, String>{
        for (final FormValidationError error in errors)
          error.fieldId: error.message,
      },
      code: 'form_response_invalid',
    );
  }
  return <String, Object?>{
    'tenant_id': tenantId,
    'template_id': template.id,
    'template_version': template.version,
    'patient_id': patientId,
    'encounter_id': encounterId,
    'submitted_by': submittedBy,
    'values_json': jsonEncode(values),
    'submitted_at': DateTime.now().toUtc().toIso8601String(),
  };
}

/// Validates the answers against a template.
///
/// Kept in one place so the runner and the submission path agree on what a
/// complete form is.
List<FormValidationError> validateTemplateValues(
  FormTemplate template,
  Map<String, Object?> values,
) => validateAll(template.schema, values);
