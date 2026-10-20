/// Tests for the clinical forms engine (Module 47).
///
/// The engine's job is to ask the right questions, in the right order, and to
/// refuse a form that was not answered. These tests pin the rules that make
/// that true: a hidden field is never required, a visible one is, a step is
/// not left until it is answered, and the same rules apply when the response
/// is written.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/authorization_snapshot.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/forms/form_repository.dart';
import 'package:nodex_hms/domain/forms/form_schema.dart';
import 'package:nodex_hms/domain/forms/form_template.dart';
import 'package:nodex_hms/domain/forms/form_use_cases.dart';
import 'package:nodex_hms/domain/forms/form_validation.dart';
import 'package:nodex_hms/domain/forms/icd10.dart';

/// A template with a triage-style branching question.
final FormSchema _schema = FormSchema.fromJson(const <String, Object?>{
  'code': 'TRIAGE',
  'title': 'Triage assessment',
  'version': 1,
  'steps': <Object?>[
    <String, Object?>{'title': 'Presentation'},
    <String, Object?>{'title': 'Risk'},
  ],
  'fields': <Object?>[
    {
      'id': 'complaint',
      'label': 'Presenting complaint',
      'type': 'text',
      'required': true,
      'step': 0,
      'maxLength': 10,
    },
    {
      'id': 'breathing',
      'label': 'Breathing difficulty',
      'type': 'boolean',
      'step': 0,
    },
    {
      'id': 'respiratory_rate',
      'label': 'Respiratory rate',
      'type': 'integer',
      'required': true,
      'step': 1,
      'minValue': 5,
      'maxValue': 40,
      'visibleWhen': {'fieldId': 'breathing', 'operator': 'is_true'},
    },
    {
      'id': 'severity',
      'label': 'Severity',
      'type': 'single_select',
      'required': true,
      'step': 1,
      'options': <Object?>[
        <String, Object?>{'value': 'minor', 'label': 'Minor'},
        <String, Object?>{'value': 'major', 'label': 'Major'},
      ],
    },
  ],
});

FormTemplate _template({
  FormTemplateStatus status = FormTemplateStatus.published,
}) => FormTemplate(
  id: 'template-1',
  tenantId: 'tenant-1',
  templateCode: 'TRIAGE',
  title: 'Triage assessment',
  version: 1,
  schema: _schema,
  status: status,
  createdBy: 'doctor-1',
);

/// A policy holding the given permissions.
AuthorizationPolicy _policy(Set<String> permissions) {
  final DateTime issuedAt = DateTime.now().toUtc();
  return AuthorizationPolicy(
    snapshot: AuthorizationSnapshot(
      snapshotId: 'snapshot-1',
      tenantId: 'tenant-1',
      userId: 'user-1',
      deviceId: 'device-1',
      revision: 1,
      issuedAt: issuedAt,
      expiresAt: issuedAt.add(const Duration(days: 30)),
      payloadDigest: 'digest',
      roles: const <String>{NodexRoles.medicalOfficer},
      permissions: permissions,
      offlinePermissions: permissions,
      facilityIds: const <String>{},
      departmentIds: const <String>{},
      wardIds: const <String>{},
    ),
    connectivity: ConnectivityState.online,
  );
}

/// A repository that records what it was asked to write.
final class _RecordingFormRepository implements FormRepository {
  final List<Map<String, Object?>> responses = <Map<String, Object?>>[];
  List<FormTemplate> templates = <FormTemplate>[];
  List<Icd10Code> codes = <Icd10Code>[];

  @override
  Future<List<FormTemplate>> listTemplates() async => templates;

  @override
  Future<FormTemplate?> getTemplate(String id) async =>
      templates.where((FormTemplate t) => t.id == id).firstOrNull;

  @override
  Future<List<Icd10Code>> listIcd10Codes() async => codes;

  @override
  Future<String> submitResponse(Map<String, Object?> row) async {
    responses.add(row);
    return 'response-1';
  }

  @override
  Future<List<FormResponse>> listResponses(String patientId) async =>
      <FormResponse>[];
}

void main() {
  group('reading a schema', () {
    test('reads the fields, the steps and the conditions', () {
      expect(_schema.fields, hasLength(4));
      expect(_schema.stepCount, 2);
      expect(_schema.fieldsForStep(0), hasLength(2));
      expect(_schema.fieldById('severity')?.type, FormFieldType.singleSelect);
      expect(
        _schema.fieldById('respiratory_rate')?.visibleWhen?.operator,
        ConditionOperator.isTrue,
      );
    });

    test('a schema with no fields is refused', () {
      expect(
        () => FormSchema.fromJson(const <String, Object?>{'title': 'Empty'}),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'form_schema_invalid',
          ),
        ),
      );
    });

    test('a schema with fields but no steps still has one step', () {
      final FormSchema flat = FormSchema.fromJson(const <String, Object?>{
        'fields': <Object?>[
          <String, Object?>{'id': 'a', 'label': 'A', 'type': 'text'},
        ],
      });
      expect(flat.stepCount, 1);
      expect(flat.fieldsForStep(0), hasLength(1));
    });

    test('a schema survives a round trip through JSON', () {
      final Map<String, Object?> json = _schema.toJson();
      final FormSchema again = FormSchema.fromJson(json);
      expect(again.fields, hasLength(_schema.fields.length));
      expect(again.stepCount, _schema.stepCount);
      expect(again.fieldById('complaint')?.maxLength, 10);
    });
  });

  group('conditional branching', () {
    test('a field with no condition is always asked', () {
      expect(
        isFieldVisible(
          _schema.fieldById('complaint')!,
          const <String, Object?>{},
        ),
        isTrue,
      );
    });

    test('a field is hidden until its condition is met', () {
      expect(
        isFieldVisible(
          _schema.fieldById('respiratory_rate')!,
          const <String, Object?>{'breathing': false},
        ),
        isFalse,
      );
      expect(
        isFieldVisible(
          _schema.fieldById('respiratory_rate')!,
          const <String, Object?>{'breathing': true},
        ),
        isTrue,
      );
    });

    test('a hidden field is never required', () {
      final FormFieldSchema field = _schema.fieldById('respiratory_rate')!;
      expect(field.required, isTrue);
      final List<FormValidationError> errors = validateField(
        field,
        const <String, Object?>{'breathing': false},
      );
      expect(errors, isEmpty);
    });

    test('a visible required field must be answered', () {
      final List<FormValidationError> errors = validateField(
        _schema.fieldById('respiratory_rate')!,
        const <String, Object?>{'breathing': true},
      );
      expect(errors, hasLength(1));
      expect(errors.single.code, 'field_required');
    });

    test('a condition can compare a value', () {
      const FormFieldSchema field = FormFieldSchema(
        id: 'smoker',
        label: 'Smoker',
        type: FormFieldType.boolean,
        visibleWhen: FormCondition(
          fieldId: 'tobacco',
          operator: ConditionOperator.equals,
          value: 'yes',
        ),
      );
      expect(
        isFieldVisible(field, const <String, Object?>{'tobacco': 'yes'}),
        isTrue,
      );
      expect(
        isFieldVisible(field, const <String, Object?>{'tobacco': 'no'}),
        isFalse,
      );
    });

    test('a condition can look for a chosen value', () {
      const FormFieldSchema field = FormFieldSchema(
        id: 'smoker',
        label: 'Smoker',
        type: FormFieldType.boolean,
        visibleWhen: FormCondition(
          fieldId: 'habits',
          operator: ConditionOperator.contains,
          value: 'smoking',
        ),
      );
      expect(
        isFieldVisible(field, const <String, Object?>{
          'habits': <Object?>['smoking'],
        }),
        isTrue,
      );
      expect(
        isFieldVisible(field, const <String, Object?>{
          'habits': <Object?>['alcohol'],
        }),
        isFalse,
      );
    });
  });

  group('validating answers', () {
    test('a required text field must hold something', () {
      final List<FormValidationError> errors = validateField(
        _schema.fieldById('complaint')!,
        const <String, Object?>{'complaint': '   '},
      );
      expect(errors.single.code, 'field_required');
    });

    test('text longer than the limit is refused', () {
      final List<FormValidationError> errors = validateField(
        _schema.fieldById('complaint')!,
        const <String, Object?>{'complaint': 'twelve chars'},
      );
      expect(errors.single.code, 'field_too_long');
    });

    test('a number outside its range is refused', () {
      final List<FormValidationError> errors = validateField(
        _schema.fieldById('respiratory_rate')!,
        const <String, Object?>{'breathing': true, 'respiratory_rate': 44},
      );
      expect(errors.single.code, 'field_too_large');
    });

    test('a number that is not a number is refused', () {
      final List<FormValidationError> errors = validateField(
        _schema.fieldById('respiratory_rate')!,
        const <String, Object?>{'breathing': true, 'respiratory_rate': 'high'},
      );
      expect(errors.single.code, 'field_not_a_number');
    });

    test('a whole-number field refuses a fraction', () {
      const FormFieldSchema field = FormFieldSchema(
        id: 'rate',
        label: 'Rate',
        type: FormFieldType.integer,
      );
      final List<FormValidationError> errors = validateField(
        field,
        const <String, Object?>{'rate': 12.5},
      );
      expect(errors.single.code, 'field_not_an_integer');
    });

    test('a choice that is not offered is refused', () {
      final List<FormValidationError> errors = validateField(
        _schema.fieldById('severity')!,
        const <String, Object?>{'severity': 'catastrophic'},
      );
      expect(errors.single.code, 'field_not_an_option');
    });

    test('an offered choice is accepted', () {
      final List<FormValidationError> errors = validateField(
        _schema.fieldById('severity')!,
        const <String, Object?>{'severity': 'minor'},
      );
      expect(errors, isEmpty);
    });

    test('an ICD-10 answer must look like a code', () {
      const FormFieldSchema field = FormFieldSchema(
        id: 'diagnosis',
        label: 'Diagnosis',
        type: FormFieldType.icd10,
      );
      expect(
        validateField(field, const <String, Object?>{
          'diagnosis': 'E11.9',
        }).isEmpty,
        isTrue,
      );
      expect(
        validateField(field, const <String, Object?>{
          'diagnosis': 'diabetes',
        }).single.code,
        'field_not_an_icd10_code',
      );
    });

    test('a date answer must be a date', () {
      const FormFieldSchema field = FormFieldSchema(
        id: 'onset',
        label: 'Onset',
        type: FormFieldType.date,
      );
      expect(
        validateField(field, const <String, Object?>{
          'onset': '2026-09-12',
        }).isEmpty,
        isTrue,
      );
      expect(
        validateField(field, const <String, Object?>{
          'onset': 'yesterday',
        }).single.code,
        'field_not_a_date',
      );
    });

    test('a step is checked as a whole', () {
      final Map<String, List<FormValidationError>> errors = validateStep(
        _schema,
        0,
        const <String, Object?>{'complaint': 'chest pain'},
      );
      expect(errors, isEmpty);
    });

    test('a step with a missing answer is not left', () {
      expect(canLeaveStep(_schema, 0, const <String, Object?>{}), isFalse);
      expect(
        canLeaveStep(_schema, 0, const <String, Object?>{
          'complaint': 'chest pain',
        }),
        isTrue,
      );
    });
  });

  group('recording a response', () {
    test('a complete form is written', () {
      final Map<String, Object?> row = buildResponseRow(
        tenantId: 'tenant-1',
        template: _template(),
        submittedBy: 'doctor-1',
        values: const <String, Object?>{
          'complaint': 'chest pain',
          'severity': 'minor',
        },
      );
      expect(row['template_id'], 'template-1');
      expect(row['template_version'], 1);
      expect(
        (jsonDecode(row['values_json']! as String)
            as Map<String, Object?>)['complaint'],
        'chest pain',
      );
    });

    test('an incomplete form is refused', () {
      expect(
        () => buildResponseRow(
          tenantId: 'tenant-1',
          template: _template(),
          submittedBy: 'doctor-1',
          values: const <String, Object?>{'severity': 'minor'},
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'form_response_invalid',
          ),
        ),
      );
    });

    test('a form that is not published is refused', () {
      expect(
        () => buildResponseRow(
          tenantId: 'tenant-1',
          template: _template(status: FormTemplateStatus.draft),
          submittedBy: 'doctor-1',
          values: const <String, Object?>{
            'complaint': 'chest pain',
            'severity': 'minor',
          },
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'form_template_not_published',
          ),
        ),
      );
    });
  });

  group('the ICD-10 catalogue', () {
    final List<Icd10Code> codes = <Icd10Code>[
      const Icd10Code(code: 'E11.9', description: 'Type 2 diabetes mellitus'),
      const Icd10Code(code: 'E10.9', description: 'Type 1 diabetes mellitus'),
      const Icd10Code(code: 'I10', description: 'Essential hypertension'),
      const Icd10Code(code: 'J45.9', description: 'Asthma, unspecified'),
    ];

    test('an exact code comes first', () {
      final List<Icd10Code> hits = searchIcd10(codes, 'E11.9');
      expect(hits.first.code, 'E11.9');
    });

    test('a prefix matches before a description does', () {
      final List<Icd10Code> hits = searchIcd10(codes, 'E1');
      // Both diabetes codes match the prefix; the tie is broken by the code
      // itself so the order never moves under the reader.
      expect(hits.map((Icd10Code c) => c.code), <String>['E10.9', 'E11.9']);
    });

    test('a description is searched too', () {
      final List<Icd10Code> hits = searchIcd10(codes, 'asthma');
      expect(hits.single.code, 'J45.9');
    });

    test('the search is case insensitive', () {
      expect(searchIcd10(codes, 'i10').single.code, 'I10');
    });

    test('an empty query matches nothing', () {
      expect(searchIcd10(codes, '  '), isEmpty);
    });

    test('a query that matches nothing returns nothing', () {
      expect(searchIcd10(codes, 'zzzz'), isEmpty);
    });
  });

  group('use-case gates', () {
    test('listing the forms requires the read permission', () async {
      await expectLater(
        ListFormTemplatesUseCase(repository: _RecordingFormRepository())
            .call(policy: _policy(<String>{NodexPermissions.formsSubmit})),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('submitting a form requires the submit permission', () async {
      await expectLater(
        SubmitFormResponseUseCase(repository: _RecordingFormRepository()).call(
          policy: _policy(<String>{NodexPermissions.formsRead}),
          tenantId: 'tenant-1',
          template: _template(),
          submittedBy: 'doctor-1',
          values: const <String, Object?>{
            'complaint': 'chest pain',
            'severity': 'minor',
          },
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('submitting a form writes it', () async {
      final _RecordingFormRepository repository = _RecordingFormRepository();
      await SubmitFormResponseUseCase(repository: repository).call(
        policy: _policy(<String>{NodexPermissions.formsSubmit}),
        tenantId: 'tenant-1',
        template: _template(),
        submittedBy: 'doctor-1',
        values: const <String, Object?>{
          'complaint': 'chest pain',
          'severity': 'minor',
        },
      );
      expect(repository.responses, hasLength(1));
    });

    test('searching the catalogue requires the read permission', () async {
      await expectLater(
        SearchIcd10UseCase(repository: _RecordingFormRepository())
            .call(policy: _policy(<String>{}), query: 'E11'),
        throwsA(isA<AuthorizationError>()),
      );
    });
  });
}
