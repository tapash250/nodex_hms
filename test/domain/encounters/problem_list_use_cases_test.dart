/// Tests for the problem-list and scribe use cases (Module 16).
///
/// The properties that matter clinically: a problem may only be closed once and
/// never reopened; recording a dictation needs write access but *reviewing* one
/// needs AI review permission; machine output can only reach an encounter that
/// is still editable, and only the sections a clinician actually accepted.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/authorization_snapshot.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/encounters/encounter.dart';
import 'package:nodex_hms/domain/encounters/encounter_repository.dart';
import 'package:nodex_hms/domain/encounters/problem_list.dart';
import 'package:nodex_hms/domain/encounters/problem_list_repository.dart';
import 'package:nodex_hms/domain/encounters/problem_list_use_cases.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';

/// In-memory store covering the problem list, scribe drafts and encounters.
final class FakeEmrStore implements PatientLocalStore {
  final Map<String, Map<String, Map<String, Object?>>> tables =
      <String, Map<String, Map<String, Object?>>>{};

  bool closed = false;

  Map<String, Map<String, Object?>> _table(String name) =>
      tables.putIfAbsent(name, () => <String, Map<String, Object?>>{});

  /// Seeds one row, creating the table if needed.
  void seedRow(String table, String id, Map<String, Object?> row) =>
      _table(table)[id] = row;

  /// Drops every seeded problem and draft, as a sync purge would.
  void deleteProblemListRows() {
    _table(LocalTables.clinicalProblems).clear();
    _table(LocalTables.encounterScribeDrafts).clear();
  }

  void _guard() {
    if (closed) {
      throw const PersistenceError(
        message: 'The local clinical database has not been opened.',
        code: 'database_not_open',
      );
    }
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String sql,
    List<Object?> parameters,
  ) async {
    _guard();
    if (sql.contains(LocalTables.clinicalProblems)) {
      Iterable<Map<String, Object?>> rows = _table(LocalTables.clinicalProblems)
          .values
          .where((Map<String, Object?> r) => r['patient_id'] == parameters[0]);
      if (sql.contains("clinical_status = 'active'")) {
        rows = rows.where(
          (Map<String, Object?> r) => r['clinical_status'] == 'active',
        );
      }
      return rows.toList(growable: false);
    }
    if (sql.contains(LocalTables.encounterScribeDrafts)) {
      if (sql.contains("status = 'pending_review'")) {
        return _table(LocalTables.encounterScribeDrafts).values
            .where(
              (Map<String, Object?> r) =>
                  r['tenant_id'] == parameters[0] &&
                  r['status'] == 'pending_review',
            )
            .toList(growable: false);
      }
      return _table(LocalTables.encounterScribeDrafts).values
          .where((Map<String, Object?> r) => r['encounter_id'] == parameters[0])
          .toList(growable: false);
    }
    if (sql.contains(LocalTables.clinicalEncounters)) {
      return _table(LocalTables.clinicalEncounters).values
          .where((Map<String, Object?> r) => r['id'] == parameters[0])
          .toList(growable: false);
    }
    throw UnimplementedError('FakeEmrStore cannot run: $sql');
  }

  @override
  Future<Map<String, Object?>?> getById(String table, String id) async {
    _guard();
    return _table(table)[id];
  }

  @override
  Future<void> insert(String table, Map<String, Object?> row) async {
    _guard();
    _table(table)[row['id']! as String] = Map<String, Object?>.from(row);
  }

  @override
  Future<void> update(
    String table,
    String id,
    Map<String, Object?> changes,
  ) async {
    _guard();
    final Map<String, Object?>? existing = _table(table)[id];
    if (existing == null) throw StateError('row $id not found in $table');
    existing.addAll(changes);
  }
}

/// Minimal encounter seam, so the review gate can be tested without the whole
/// encounter repository.
final class FakeEncounterRepository implements EncounterRepository {
  FakeEncounterRepository(this.store);

  final FakeEmrStore store;
  final List<Map<String, Object?>> encounterWrites = <Map<String, Object?>>[];

  Map<String, Object?> seedEncounter({
    String id = 'encounter-1',
    EncounterStatus status = EncounterStatus.inProgress,
  }) {
    final Map<String, Object?> row = <String, Object?>{
      ...ClinicalEncounter.draftRow(
        tenantId: 'tenant-1',
        patientId: 'patient-1',
        attendingPhysicianId: 'doctor-1',
        encounterType: EncounterType.outpatient,
        createdBy: 'doctor-1',
      ),
      'id': id,
      'status': status.wireValue,
    };
    if (status.isSigned) {
      row['signed_at'] = DateTime.now().toUtc().toIso8601String();
    }
    store.seedRow(LocalTables.clinicalEncounters, id, row);
    return row;
  }

  @override
  Future<ClinicalEncounter?> getEncounter(String id) async {
    final Map<String, Object?>? row =
        store.tables[LocalTables.clinicalEncounters]?[id];
    return row == null ? null : ClinicalEncounter.fromRow(row);
  }

  @override
  Future<void> updateEncounter(String id, Map<String, Object?> changes) async {
    encounterWrites.add(changes);
    store.tables[LocalTables.clinicalEncounters]?[id]?.addAll(changes);
  }

  @override
  Future<String> createEncounter(Map<String, Object?> row) =>
      throw UnimplementedError();

  @override
  Future<String> amendEncounter({
    required String encounterId,
    required Map<String, Object?> amendmentRow,
  }) => throw UnimplementedError();

  @override
  Future<List<EncounterAmendment>> listAmendments(String encounterId) =>
      throw UnimplementedError();

  @override
  Future<List<ClinicalEncounter>> listForPatient(
    String patientId, {
    int limit = 50,
  }) => throw UnimplementedError();

  @override
  Future<List<ClinicalEncounter>> listForPhysician({
    required String tenantId,
    required String attendingPhysicianId,
    int limit = 50,
  }) => throw UnimplementedError();

  @override
  Future<void> signEncounter(String id) => throw UnimplementedError();
}

AuthorizationPolicy policyWith(Set<String> permissions) {
  final DateTime issuedAt = DateTime.now().toUtc();
  return AuthorizationPolicy(
    snapshot: AuthorizationSnapshot(
      snapshotId: 'snapshot-1',
      tenantId: 'tenant-1',
      userId: 'doctor-1',
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

void main() {
  late FakeEmrStore store;
  late FakeEncounterRepository encounters;
  late ProblemListRepository problems;
  late RecordProblemUseCase record;
  late ResolveProblemUseCase resolve;
  late RequestScribeDraftUseCase dictate;
  late ReviewScribeDraftUseCase review;

  const Set<String> author = <String>{NodexPermissions.encounterWrite};
  const Set<String> reviewer = <String>{NodexPermissions.aiOutputReview};

  setUp(() {
    store = FakeEmrStore();
    encounters = FakeEncounterRepository(store);
    problems = DefaultProblemListRepository(
      store: store,
      logger: NodexLogger(
        sinks: <NodexLogSink>[InMemoryLogSink()],
        minimumLevel: NodexLogLevel.trace,
      ),
    );
    record = RecordProblemUseCase(repository: problems);
    resolve = ResolveProblemUseCase(repository: problems);
    dictate = RequestScribeDraftUseCase(repository: problems);
    review = ReviewScribeDraftUseCase(
      repository: problems,
      encounters: encounters,
    );
  });

  Future<ClinicalProblem> seedProblem({
    String id = 'problem-1',
    String patientId = 'patient-1',
    String code = 'E11.9',
    String description = 'Type 2 diabetes',
    ClinicalProblemStatus status = ClinicalProblemStatus.active,
  }) async {
    store.seedRow(LocalTables.clinicalProblems, id, <String, Object?>{
      'id': id,
      'tenant_id': 'tenant-1',
      'patient_id': patientId,
      'encounter_id': null,
      'problem_code': code,
      'description': description,
      'clinical_status': status.wireValue,
      'onset_date': null,
      'resolved_at': status.isActive
          ? null
          : DateTime.now().toUtc().toIso8601String(),
      'resolution_note': status.isActive ? null : 'Resolved.',
      'recorded_by': 'doctor-1',
      'resolved_by': status.isActive ? null : 'doctor-2',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    return (await problems.problemById(id))!;
  }

  Future<ScribeDraft> seedDraft({
    String id = 'draft-1',
    String encounterId = 'encounter-1',
    ScribeDraftStatus status = ScribeDraftStatus.pendingReview,
  }) async {
    store.seedRow(LocalTables.encounterScribeDrafts, id, <String, Object?>{
      'id': id,
      'tenant_id': 'tenant-1',
      'encounter_id': encounterId,
      'model_id': 'whisper-small',
      'transcript_text': 'transcript',
      'subjective_note': 'Machine subjective.',
      'objective_findings': null,
      'assessment': 'Machine assessment.',
      'plan_description': null,
      'confidence': 0.9,
      'safety_decision': 'allow',
      'status': status.wireValue,
      'requested_by': 'doctor-1',
      'reviewed_by': status.isReviewed ? 'doctor-2' : null,
      'reviewed_at': status.isReviewed
          ? DateTime.now().toUtc().toIso8601String()
          : null,
      'rejection_reason': status == ScribeDraftStatus.rejected
          ? 'Wrong.'
          : null,
      'accepted_fields': status == ScribeDraftStatus.accepted
          ? <String>['assessment']
          : const <String>[],
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    return (await problems.draftById(id))!;
  }

  group('problem list', () {
    test('recording a problem requires encounter.write', () {
      expect(
        record.call(
          policy: policyWith(reviewer),
          tenantId: 'tenant-1',
          patientId: 'patient-1',
          problemCode: 'E11.9',
          description: 'Type 2 diabetes',
          recordedBy: 'doctor-1',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('a recorded problem is active and attributed', () async {
      final String id = await record.call(
        policy: policyWith(author),
        tenantId: 'tenant-1',
        patientId: 'patient-1',
        problemCode: 'E11.9',
        description: 'Type 2 diabetes',
        recordedBy: 'doctor-1',
      );
      final ClinicalProblem problem = (await problems.problemById(id))!;
      expect(problem.isActive, isTrue);
      expect(problem.recordedBy, 'doctor-1');
      expect(problem.problemCode, 'E11.9');
    });

    test('the list can be narrowed to active problems', () async {
      await seedProblem(id: 'p1');
      await seedProblem(
        id: 'p2',
        code: 'I10',
        description: 'Hypertension',
        status: ClinicalProblemStatus.resolved,
      );

      expect((await problems.problemsForPatient('patient-1')).length, 2);
      final List<ClinicalProblem> active = await problems.problemsForPatient(
        'patient-1',
        activeOnly: true,
      );
      expect(active.single.id, 'p1');
    });

    test('a problem belongs to one patient', () async {
      await seedProblem(id: 'p1');
      await seedProblem(id: 'p2', patientId: 'patient-2', code: 'I10');
      expect((await problems.problemsForPatient('patient-2')).single.id, 'p2');
    });

    test('resolution requires write access and an active problem', () async {
      final ClinicalProblem problem = await seedProblem();
      expect(
        resolve.call(
          policy: policyWith(reviewer),
          problem: problem,
          resolvedBy: 'doctor-2',
          resolutionNote: 'Resolved.',
        ),
        throwsA(isA<AuthorizationError>()),
      );

      await resolve.call(
        policy: policyWith(author),
        problem: problem,
        resolvedBy: 'doctor-2',
        resolutionNote: 'HbA1c normal for two years.',
      );
      final ClinicalProblem closed = (await problems.problemById(problem.id))!;
      expect(closed.isActive, isFalse);
      expect(closed.resolvedBy, 'doctor-2');
      expect(closed.resolutionNote, 'HbA1c normal for two years.');
      expect(closed.problemCode, problem.problemCode);
    });

    test('a resolved problem cannot be resolved again or reopened', () async {
      final ClinicalProblem resolved = await seedProblem(
        status: ClinicalProblemStatus.resolved,
      );
      expect(
        resolve.call(
          policy: policyWith(author),
          problem: resolved,
          resolvedBy: 'doctor-3',
          resolutionNote: 'Again.',
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'problem_already_resolved',
          ),
        ),
      );
    });

    test('resolution needs an attributed note', () async {
      final ClinicalProblem problem = await seedProblem();
      expect(
        resolve.call(
          policy: policyWith(author),
          problem: problem,
          resolvedBy: '',
          resolutionNote: '  ',
        ),
        throwsA(isA<ValidationError>()),
      );
    });
  });

  group('ambient dictation', () {
    test('recording a dictation requires encounter.write', () {
      expect(
        dictate.call(
          policy: policyWith(reviewer),
          tenantId: 'tenant-1',
          encounterId: 'encounter-1',
          modelId: 'whisper-small',
          transcriptText: 'text',
          safetyDecision: 'allow',
          requestedBy: 'doctor-1',
          assessment: 'Stable angina.',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test(
      'a dictation is stored pending review and nothing is signed off',
      () async {
        encounters.seedEncounter();
        final String id = await dictate.call(
          policy: policyWith(author),
          tenantId: 'tenant-1',
          encounterId: 'encounter-1',
          modelId: 'whisper-small',
          transcriptText: 'No chest pain.',
          safetyDecision: 'allow',
          requestedBy: 'doctor-1',
          assessment: 'Machine assessment.',
          confidence: 0.7,
        );

        final ScribeDraft draft = (await problems.draftById(id))!;
        expect(draft.isPendingReview, isTrue);
        expect(draft.acceptedSections, isEmpty);
        expect(
          encounters.encounterWrites,
          isEmpty,
          reason: 'recording a dictation must not touch the encounter',
        );
      },
    );

    test('pending drafts are listed for review', () async {
      encounters.seedEncounter();
      await seedDraft(id: 'd1');
      await seedDraft(id: 'd2', status: ScribeDraftStatus.accepted);
      expect((await problems.pendingDrafts('tenant-1')).single.id, 'd1');
      expect((await problems.draftsForEncounter('encounter-1')).length, 2);
    });

    test('reviewing requires the AI review permission, not write access', () {
      const ScribeDraft draft = ScribeDraft(
        id: 'draft-1',
        tenantId: 'tenant-1',
        encounterId: 'encounter-1',
        modelId: 'whisper-small',
        transcriptText: 'text',
        safetyDecision: 'allow',
        status: ScribeDraftStatus.pendingReview,
        requestedBy: 'doctor-1',
        assessment: 'Machine assessment.',
      );
      expect(
        review.call(
          policy: policyWith(author),
          draft: draft,
          reviewedBy: 'doctor-1',
          acceptedText: const <ScribeSection, String>{
            ScribeSection.assessment: 'Reviewed.',
          },
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'notGranted',
          ),
        ),
      );
    });

    test(
      'accepting writes only the reviewed sections into the encounter',
      () async {
        encounters.seedEncounter();
        final ScribeDraft draft = await seedDraft();

        final ScribeReviewOutcome outcome = await review.call(
          policy: policyWith(reviewer),
          draft: draft,
          reviewedBy: 'doctor-2',
          acceptedText: const <ScribeSection, String>{
            ScribeSection.assessment: '  Reviewed assessment.  ',
          },
        );

        expect(outcome.rejected, isFalse);
        expect(outcome.encounterChanges['assessment'], 'Reviewed assessment.');
        expect(
          outcome.encounterChanges.containsKey('subjective_note'),
          isFalse,
          reason: 'a section the clinician did not accept is not written',
        );

        final ScribeDraft reviewed = (await problems.draftById(draft.id))!;
        expect(reviewed.status, ScribeDraftStatus.accepted);
        expect(reviewed.acceptedSections, <ScribeSection>{
          ScribeSection.assessment,
        });
        expect(
          reviewed.assessment,
          'Reviewed assessment.',
          reason: 'the stored draft carries what was signed off, not the machine text',
        );
        expect(reviewed.subjectiveNote, 'Machine subjective.');
        expect(reviewed.reviewedBy, 'doctor-2');
      },
    );

    test('machine text never reaches a signed encounter', () async {
      encounters.seedEncounter(status: EncounterStatus.signedAndLocked);
      final ScribeDraft draft = await seedDraft();

      expect(
        review.call(
          policy: policyWith(reviewer),
          draft: draft,
          reviewedBy: 'doctor-2',
          acceptedText: const <ScribeSection, String>{
            ScribeSection.assessment: 'Reviewed.',
          },
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'encounter_signed_frozen',
          ),
        ),
      );
      expect(
        encounters.encounterWrites,
        isEmpty,
        reason: 'the attempt must not reach the frozen encounter at all',
      );
    });

    test('a missing encounter stops acceptance', () async {
      final ScribeDraft draft = await seedDraft(encounterId: 'absent');
      expect(
        review.call(
          policy: policyWith(reviewer),
          draft: draft,
          reviewedBy: 'doctor-2',
          acceptedText: const <ScribeSection, String>{
            ScribeSection.plan: 'Plan.',
          },
        ),
        throwsA(
          isA<PersistenceError>().having(
            (PersistenceError error) => error.code,
            'code',
            'encounter_not_found_locally',
          ),
        ),
      );
    });

    test('rejecting leaves the encounter untouched', () async {
      encounters.seedEncounter();
      final ScribeDraft draft = await seedDraft();

      final ScribeReviewOutcome outcome = await review.call(
        policy: policyWith(reviewer),
        draft: draft,
        reviewedBy: 'doctor-2',
        rejectionReason: '  Transcription misheard.  ',
      );

      expect(outcome.rejected, isTrue);
      expect(outcome.rejectionReason, 'Transcription misheard.');
      expect(outcome.encounterChanges, isEmpty);
      expect(encounters.encounterWrites, isEmpty);

      final ScribeDraft rejected = (await problems.draftById(draft.id))!;
      expect(rejected.status, ScribeDraftStatus.rejected);
      expect(rejected.acceptedSections, isEmpty);
      expect(rejected.rejectionReason, 'Transcription misheard.');
    });

    test('a draft can only be reviewed once', () async {
      encounters.seedEncounter();
      final ScribeDraft draft = await seedDraft();
      await review.call(
        policy: policyWith(reviewer),
        draft: draft,
        reviewedBy: 'doctor-2',
        rejectionReason: 'Wrong.',
      );

      expect(
        review.call(
          policy: policyWith(reviewer),
          draft: draft,
          reviewedBy: 'doctor-3',
          rejectionReason: 'Again.',
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'scribe_already_reviewed',
          ),
        ),
      );
    });

    test('a stale pending copy cannot be reviewed a second time', () async {
      encounters.seedEncounter();
      final ScribeDraft draft = await seedDraft();
      await review.call(
        policy: policyWith(reviewer),
        draft: draft,
        reviewedBy: 'doctor-2',
        rejectionReason: 'Wrong.',
      );

      // `draft` still says pending in this scope. The stored state decides.
      expect(draft.isPendingReview, isTrue);
      expect(
        review.call(
          policy: policyWith(reviewer),
          draft: draft,
          reviewedBy: 'doctor-3',
          acceptedText: const <ScribeSection, String>{
            ScribeSection.assessment: 'Reviewed.',
          },
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'scribe_already_reviewed',
          ),
        ),
      );
      expect(encounters.encounterWrites, isEmpty);
    });

    test('a draft that is not held locally cannot be reviewed', () async {
      final ScribeDraft ghost = await seedDraft(id: 'draft-1');
      store.deleteProblemListRows();
      expect(
        review.call(
          policy: policyWith(reviewer),
          draft: ghost,
          reviewedBy: 'doctor-2',
          rejectionReason: 'Wrong.',
        ),
        throwsA(
          isA<PersistenceError>().having(
            (PersistenceError error) => error.code,
            'code',
            'scribe_draft_not_found_locally',
          ),
        ),
      );
    });

    test('acceptance with nothing accepted is refused', () async {
      encounters.seedEncounter();
      final ScribeDraft draft = await seedDraft();
      expect(
        review.call(
          policy: policyWith(reviewer),
          draft: draft,
          reviewedBy: 'doctor-2',
        ),
        throwsA(isA<ValidationError>()),
      );
    });
  });
}
