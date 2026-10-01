/// Tests for problem-list and ambient-scribe entities (Module 16).
///
/// The invariants under test: a problem is recorded as an attributed clinical
/// assertion and closed only by an attributed note, and machine output can
/// never reach the record without a human accepting specific sections.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/encounters/problem_list.dart';

void main() {
  group('ClinicalProblemStatus', () {
    test('round-trips every wire value', () {
      for (final ClinicalProblemStatus status in ClinicalProblemStatus.values) {
        expect(ClinicalProblemStatus.fromWire(status.wireValue), status);
      }
    });

    test('falls back to active for an unknown value', () {
      expect(
        ClinicalProblemStatus.fromWire('entered_in_error'),
        ClinicalProblemStatus.active,
      );
    });
  });

  group('ScribeDraftStatus', () {
    test('round-trips every wire value', () {
      for (final ScribeDraftStatus status in ScribeDraftStatus.values) {
        expect(ScribeDraftStatus.fromWire(status.wireValue), status);
      }
    });

    test('only a pending draft is unreviewed', () {
      expect(ScribeDraftStatus.pendingReview.isReviewed, isFalse);
      expect(ScribeDraftStatus.accepted.isReviewed, isTrue);
      expect(ScribeDraftStatus.rejected.isReviewed, isTrue);
    });
  });

  group('ScribeSection', () {
    test('each section names its encounter column', () {
      expect(ScribeSection.subjective.column, 'subjective_note');
      expect(ScribeSection.objective.column, 'objective_findings');
      expect(ScribeSection.assessment.column, 'assessment');
      expect(ScribeSection.plan.column, 'plan_description');
      expect(ScribeSection.values.length, 4);
    });
  });

  group('ClinicalProblem.recordRow', () {
    test('records an active problem with trimmed text', () {
      final Map<String, Object?> row = ClinicalProblem.recordRow(
        tenantId: 'tenant-1',
        patientId: 'patient-1',
        problemCode: '  E11.9  ',
        description: '  Type 2 diabetes without complication  ',
        recordedBy: 'doctor-1',
      );

      expect(row['problem_code'], 'E11.9');
      expect(row['description'], 'Type 2 diabetes without complication');
      expect(row['clinical_status'], 'active');
      expect(row['recorded_by'], 'doctor-1');
      expect(row['resolved_at'], isNull);
      expect(row['resolved_by'], isNull);
      expect(row['onset_date'], isNull);
    });

    test('formats an onset date as a plain calendar date', () {
      final Map<String, Object?> row = ClinicalProblem.recordRow(
        tenantId: 'tenant-1',
        patientId: 'patient-1',
        problemCode: 'E11.9',
        description: 'Type 2 diabetes',
        recordedBy: 'doctor-1',
        onsetDate: DateTime.utc(2019, 3, 7),
      );
      expect(row['onset_date'], '2019-03-07');
    });

    test('requires an identity, a code, a description and a recorder', () {
      expect(
        () => ClinicalProblem.recordRow(
          tenantId: '',
          patientId: '',
          problemCode: '  ',
          description: '  ',
          recordedBy: '',
        ),
        throwsA(
          isA<ValidationError>()
              .having(
                (ValidationError error) => error.code,
                'code',
                'problem_invalid',
              )
              .having(
                (ValidationError error) => error.fieldErrors.keys,
                'fields',
                containsAll(<String>{
                  'tenant_id',
                  'patient_id',
                  'problem_code',
                  'description',
                  'recorded_by',
                }),
              ),
        ),
      );
    });
  });

  group('ClinicalProblem.resolutionChanges', () {
    test('closes the problem with an attributed note', () {
      final Map<String, Object?> changes = ClinicalProblem.resolutionChanges(
        resolvedBy: 'doctor-2',
        resolutionNote: '  Normal HbA1c for two years.  ',
      );
      expect(changes['clinical_status'], 'resolved');
      expect(changes['resolved_by'], 'doctor-2');
      expect(changes['resolution_note'], 'Normal HbA1c for two years.');
      expect(
        DateTime.parse(changes['resolved_at']! as String),
        isA<DateTime>(),
      );
    });

    test('requires a resolver and a note', () {
      expect(
        () => ClinicalProblem.resolutionChanges(
          resolvedBy: '',
          resolutionNote: '  ',
        ),
        throwsA(isA<ValidationError>()),
      );
    });
  });

  group('ClinicalProblem.fromRow', () {
    test('decodes an active problem', () {
      final ClinicalProblem problem = ClinicalProblem.fromRow(
        const <String, Object?>{
          'id': 'problem-1',
          'tenant_id': 'tenant-1',
          'patient_id': 'patient-1',
          'encounter_id': 'encounter-1',
          'problem_code': 'I10',
          'description': 'Essential hypertension',
          'clinical_status': 'active',
          'onset_date': '2020-01-15',
          'recorded_by': 'doctor-1',
          'resolved_at': null,
          'resolved_by': null,
          'resolution_note': null,
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
        },
      );

      expect(problem.problemCode, 'I10');
      expect(problem.isActive, isTrue);
      expect(problem.encounterId, 'encounter-1');
      expect(problem.onsetDate, DateTime.utc(2020, 1, 15));
      expect(problem.resolutionNote, isNull);
    });

    test('decodes a resolved problem', () {
      final ClinicalProblem problem = ClinicalProblem.fromRow(
        const <String, Object?>{
          'id': 'problem-2',
          'tenant_id': 'tenant-1',
          'patient_id': 'patient-1',
          'encounter_id': null,
          'problem_code': 'I10',
          'description': 'Essential hypertension',
          'clinical_status': 'resolved',
          'onset_date': null,
          'recorded_by': 'doctor-1',
          'resolved_at': '2026-02-01T09:00:00Z',
          'resolved_by': 'doctor-2',
          'resolution_note': 'Resolved.',
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-02-01T09:00:00Z',
        },
      );

      expect(problem.isActive, isFalse);
      expect(problem.resolvedBy, 'doctor-2');
      expect(problem.resolutionNote, 'Resolved.');
      expect(problem.encounterId, isNull);
    });
  });

  group('ScribeDraft.draftRow', () {
    test('records a pending draft awaiting review', () {
      final Map<String, Object?> row = ScribeDraft.draftRow(
        tenantId: 'tenant-1',
        encounterId: 'encounter-1',
        modelId: '  whisper-small  ',
        transcriptText: '  Patient reports no chest pain.  ',
        safetyDecision: 'allow',
        requestedBy: 'doctor-1',
        subjectiveNote: ' No chest pain. ',
        assessment: '  Stable angina. ',
        confidence: 0.82,
      );

      expect(row['model_id'], 'whisper-small');
      expect(row['transcript_text'], 'Patient reports no chest pain.');
      expect(row['status'], 'pending_review');
      expect(row['subjective_note'], 'No chest pain.');
      expect(row['assessment'], 'Stable angina.');
      expect(row['objective_findings'], isNull);
      expect(row['accepted_fields'], isEmpty);
      expect(row['reviewed_by'], isNull);
    });

    test('rejects a dictation with nothing structured to review', () {
      expect(
        () => ScribeDraft.draftRow(
          tenantId: 'tenant-1',
          encounterId: 'encounter-1',
          modelId: 'whisper-small',
          transcriptText: 'mumble',
          safetyDecision: 'allow',
          requestedBy: 'doctor-1',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.fieldErrors.keys,
            'fields',
            contains('structured_output'),
          ),
        ),
      );
    });

    test('validates the required identity and model fields', () {
      expect(
        () => ScribeDraft.draftRow(
          tenantId: '',
          encounterId: '',
          modelId: '  ',
          transcriptText: '  ',
          safetyDecision: '  ',
          requestedBy: '',
          assessment: 'x',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.fieldErrors.keys,
            'fields',
            containsAll(<String>{
              'tenant_id',
              'encounter_id',
              'model_id',
              'transcript_text',
              'safety_decision',
              'requested_by',
            }),
          ),
        ),
      );
    });

    test('a confidence outside 0 to 1 is rejected', () {
      expect(
        () => ScribeDraft.draftRow(
          tenantId: 'tenant-1',
          encounterId: 'encounter-1',
          modelId: 'whisper-small',
          transcriptText: 'text',
          safetyDecision: 'allow',
          requestedBy: 'doctor-1',
          assessment: 'x',
          confidence: 1.4,
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.fieldErrors.keys,
            'fields',
            contains('confidence'),
          ),
        ),
      );
    });
  });

  group('ScribeDraft.reviewChanges', () {
    test('acceptance records the reviewed text of each section', () {
      final Map<String, Object?> changes = ScribeDraft.reviewChanges(
        status: ScribeDraftStatus.accepted,
        reviewedBy: 'doctor-2',
        acceptedText: const <ScribeSection, String>{
          ScribeSection.assessment: '  Stable angina. ',
          ScribeSection.subjective: 'No chest pain. ',
        },
      );

      expect(changes['status'], 'accepted');
      expect(changes['reviewed_by'], 'doctor-2');
      expect(
        DateTime.parse(changes['reviewed_at']! as String),
        isA<DateTime>(),
      );
      expect(changes['accepted_fields'], <String>[
        'assessment',
        'subjective_note',
      ], reason: 'accepted sections are sorted so the list is stable');
      expect(changes['subjective_note'], 'No chest pain.');
      expect(changes['assessment'], 'Stable angina.');
      expect(changes['objective_findings'], isNull);
      expect(changes['rejection_reason'], isNull);
    });

    test('acceptance needs at least one section', () {
      expect(
        () => ScribeDraft.reviewChanges(
          status: ScribeDraftStatus.accepted,
          reviewedBy: 'doctor-2',
          acceptedText: const <ScribeSection, String>{},
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'scribe_review_invalid',
          ),
        ),
      );
    });

    test('an accepted section cannot be blank', () {
      expect(
        () => ScribeDraft.reviewChanges(
          status: ScribeDraftStatus.accepted,
          reviewedBy: 'doctor-2',
          acceptedText: const <ScribeSection, String>{
            ScribeSection.plan: '   ',
          },
        ),
        throwsA(isA<ValidationError>()),
      );
    });

    test('rejection requires a reason and accepts nothing', () {
      expect(
        () => ScribeDraft.reviewChanges(
          status: ScribeDraftStatus.rejected,
          reviewedBy: 'doctor-2',
          acceptedText: const <ScribeSection, String>{},
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.fieldErrors.keys,
            'fields',
            contains('rejection_reason'),
          ),
        ),
      );

      final Map<String, Object?> changes = ScribeDraft.reviewChanges(
        status: ScribeDraftStatus.rejected,
        reviewedBy: 'doctor-2',
        acceptedText: const <ScribeSection, String>{},
        rejectionReason: '  Transcription wrong.  ',
      );
      expect(changes['status'], 'rejected');
      expect(changes['rejection_reason'], 'Transcription wrong.');
      expect(changes['accepted_fields'], isEmpty);
    });

    test('a review needs a reviewer and a real decision', () {
      expect(
        () => ScribeDraft.reviewChanges(
          status: ScribeDraftStatus.accepted,
          reviewedBy: '',
          acceptedText: const <ScribeSection, String>{
            ScribeSection.plan: 'Review in clinic.',
          },
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'scribe_reviewer_required',
          ),
        ),
      );
      expect(
        () => ScribeDraft.reviewChanges(
          status: ScribeDraftStatus.pendingReview,
          reviewedBy: 'doctor-2',
          acceptedText: const <ScribeSection, String>{},
        ),
        throwsA(isA<ValidationError>()),
      );
    });
  });

  group('ScribeDraft.fromRow', () {
    ScribeDraft draft(Map<String, Object?> overrides) =>
        ScribeDraft.fromRow(<String, Object?>{
          'id': 'draft-1',
          'tenant_id': 'tenant-1',
          'encounter_id': 'encounter-1',
          'model_id': 'whisper-small',
          'transcript_text': 'transcript',
          'subjective_note': 'No chest pain.',
          'objective_findings': null,
          'assessment': 'Stable angina.',
          'plan_description': null,
          'confidence': 0.9,
          'safety_decision': 'allow',
          'status': 'pending_review',
          'requested_by': 'doctor-1',
          'reviewed_by': null,
          'reviewed_at': null,
          'rejection_reason': null,
          'accepted_fields': const <String>[],
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
          ...overrides,
        });

    test('decodes a pending draft', () {
      final ScribeDraft parsed = draft(const <String, Object?>{});
      expect(parsed.isPendingReview, isTrue);
      expect(parsed.acceptedSections, isEmpty);
      expect(parsed.confidence, 0.9);
      expect(parsed.sectionText(ScribeSection.subjective), 'No chest pain.');
      expect(parsed.sectionText(ScribeSection.plan), isNull);
    });

    test('decodes accepted sections from an encoded list', () {
      final ScribeDraft parsed = draft(<String, Object?>{
        'status': 'accepted',
        'reviewed_by': 'doctor-2',
        'reviewed_at': '2026-01-02T00:00:00Z',
        'accepted_fields': '["subjective_note","assessment"]',
      });
      expect(parsed.isPendingReview, isFalse);
      expect(parsed.acceptedSections, <ScribeSection>{
        ScribeSection.subjective,
        ScribeSection.assessment,
      });
    });

    test('ignores unknown accepted sections and malformed encoding', () {
      expect(
        draft(<String, Object?>{
          'accepted_fields': const <String>['assessment', 'not_a_section'],
        }).acceptedSections,
        <ScribeSection>{ScribeSection.assessment},
      );
      expect(
        draft(<String, Object?>{'accepted_fields': 'not json'})
            .acceptedSections,
        isEmpty,
      );
    });
  });
}
