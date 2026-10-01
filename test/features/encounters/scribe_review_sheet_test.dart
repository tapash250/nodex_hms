/// Widget tests for the scribe review sheet's section selection (Module 16).
///
/// The sheet is private, so it is driven through the exported panel: expand a
/// pending dictation, open the review sheet, tick and edit sections, accept.
/// The use cases under it are real ones wired to recording repositories, so
/// these tests assert on what actually reaches the command rather than on what
/// the widget claims it sent.
///
/// The behaviour worth protecting: only ticked sections are accepted, an edit to
/// a ticked section is the text that travels, unticking removes a section, and
/// nothing is accepted while the box is empty.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/authorization_snapshot.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/domain/encounters/encounter.dart';
import 'package:nodex_hms/domain/encounters/encounter_repository.dart';
import 'package:nodex_hms/domain/encounters/problem_list.dart';
import 'package:nodex_hms/domain/encounters/problem_list_repository.dart';
import 'package:nodex_hms/domain/encounters/problem_list_use_cases.dart';
import 'package:nodex_hms/domain/session/session_state.dart';
import 'package:nodex_hms/features/encounters/encounters_controller.dart';
import 'package:nodex_hms/features/encounters/problem_list_panels.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// Records what the review command was asked to do.
final class RecordingProblemRepository implements ProblemListRepository {
  RecordingProblemRepository(this.storedDraft);

  /// The draft the review command will re-read, as the use case insists on
  /// checking stored state rather than trusting the caller's copy.
  final ScribeDraft storedDraft;

  Map<ScribeSection, String>? accepted;
  String? rejectionReason;
  int reviews = 0;

  @override
  Future<void> reviewDraft(String id, Map<String, Object?> changes) async {
    reviews++;
    final List<Object?> fields = changes['accepted_fields']! as List<Object?>;
    accepted = <ScribeSection, String>{};
    for (final Object? column in fields) {
      final ScribeSection section = ScribeSection.values.firstWhere(
        (ScribeSection s) => s.column == column,
      );
      accepted![section] = changes[section.column]! as String;
    }
    rejectionReason = changes['rejection_reason'] as String?;
  }

  @override
  Future<ScribeDraft?> draftById(String id) async => storedDraft;

  @override
  Future<List<ScribeDraft>> draftsForEncounter(String encounterId) async =>
      throw UnimplementedError();

  @override
  Future<List<ScribeDraft>> pendingDrafts(String tenantId) async =>
      throw UnimplementedError();

  @override
  Future<List<ClinicalProblem>> problemsForPatient(
    String patientId, {
    bool activeOnly = false,
  }) async => const <ClinicalProblem>[];

  @override
  Future<ClinicalProblem?> problemById(String id) async => null;

  @override
  Future<String> recordDraft(Map<String, Object?> row) async =>
      throw UnimplementedError();

  @override
  Future<String> recordProblem(Map<String, Object?> row) async =>
      throw UnimplementedError();

  @override
  Future<void> resolveProblem(String id, Map<String, Object?> changes) async =>
      throw UnimplementedError();
}

/// Minimal encounter seam that accepts writes.
final class AcceptingEncounterRepository implements EncounterRepository {
  AcceptingEncounterRepository(this.encounter);

  final List<Map<String, Object?>> writes = <Map<String, Object?>>[];
  ClinicalEncounter encounter;

  @override
  Future<ClinicalEncounter?> getEncounter(String id) async => encounter;

  @override
  Future<void> updateEncounter(String id, Map<String, Object?> changes) async {
    writes.add(changes);
  }

  @override
  Future<String> createEncounter(Map<String, Object?> row) async =>
      throw UnimplementedError();

  @override
  Future<String> amendEncounter({
    required String encounterId,
    required Map<String, Object?> amendmentRow,
  }) => throw UnimplementedError();

  @override
  Future<List<EncounterAmendment>> listAmendments(String encounterId) async =>
      const <EncounterAmendment>[];

  @override
  Future<List<ClinicalEncounter>> listForPatient(
    String patientId, {
    int limit = 50,
  }) async => const <ClinicalEncounter>[];

  @override
  Future<List<ClinicalEncounter>> listForPhysician({
    required String tenantId,
    required String attendingPhysicianId,
    int limit = 50,
  }) async => const <ClinicalEncounter>[];

  @override
  Future<void> signEncounter(String id) => throw UnimplementedError();
}

SessionState sessionWith(Set<String> permissions) {
  final DateTime issuedAt = DateTime.now().toUtc();
  return SessionState(
    phase: SessionPhase.active,
    connectivity: ConnectivityState.online,
    user: const SessionUser(userId: 'doctor-2', fullName: 'Dr Reviewer'),
    tenantId: 'tenant-1',
    snapshot: AuthorizationSnapshot(
      snapshotId: 'snapshot-1',
      tenantId: 'tenant-1',
      userId: 'doctor-2',
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
  );
}

ClinicalEncounter encounterWith(EncounterStatus status) => ClinicalEncounter(
  id: 'encounter-1',
  tenantId: 'tenant-1',
  patientId: 'patient-1',
  attendingPhysicianId: 'doctor-1',
  encounterType: EncounterType.outpatient,
  status: status,
  diagnoses: const <EncounterDiagnosis>[],
  createdAt: DateTime.now().toUtc(),
);

ScribeDraft draftWith({
  ScribeDraftStatus status = ScribeDraftStatus.pendingReview,
  String? subjective = 'Machine subjective.',
  String? objective = 'Machine objective.',
  String? assessment = 'Machine assessment.',
  String? plan = 'Machine plan.',
}) => ScribeDraft(
  id: 'draft-1',
  tenantId: 'tenant-1',
  encounterId: 'encounter-1',
  modelId: 'whisper-small',
  transcriptText: 'Patient reports chest pain on exertion.',
  safetyDecision: 'allow',
  status: status,
  requestedBy: 'doctor-1',
  subjectiveNote: subjective,
  objectiveFindings: objective,
  assessment: assessment,
  planDescription: plan,
  confidence: 0.82,
);

void main() {
  late RecordingProblemRepository problems;
  late AcceptingEncounterRepository encounters;

  setUp(() {
    problems = RecordingProblemRepository(draftWith());
    encounters = AcceptingEncounterRepository(
      encounterWith(EncounterStatus.inProgress),
    );
  });

  /// A tall viewport so the whole review sheet is laid out at once.
  ///
  /// The sheet is a lazy ListView, so on a short viewport its accept button
  /// would simply not be built and assertions would pass or fail for reasons
  /// unrelated to section selection. Giving the test a tall surface keeps the
  /// tests about behaviour rather than about scroll offsets.
  void useTallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  /// Ticks the checkbox on the section row labelled [label].
  ///
  /// The tap targets the row title rather than the tile centre: the centre of a
  /// section row is its editable text field, and tapping there would move the
  /// caret rather than tick the box.
  Future<void> tickSection(WidgetTester tester, String label) async {
    final Finder title = find.descendant(
      of: find.widgetWithText(CheckboxListTile, label),
      matching: find.text(label),
    );
    await tester.tap(title.first);
    await tester.pumpAndSettle();
  }

  /// Taps the accept button for [count] sections.
  Future<void> acceptSections(WidgetTester tester, int count) async {
    await tester.tap(find.text('Accept $count section(s)'));
    await tester.pumpAndSettle();
  }

  /// Pumps the panel for [draft] with [permissions] held by the session.
  Future<void> pumpPanel(
    WidgetTester tester, {
    required ScribeDraft draft,
    required Set<String> permissions,
    EncounterStatus status = EncounterStatus.inProgress,
  }) async {
    encounters.encounter = encounterWith(status);
    useTallViewport(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionProvider.overrideWithBuild(
            (Ref ref, SessionController notifier) => sessionWith(permissions),
          ),
          problemListRepositoryProvider.overrideWithValue(problems),
          encounterRepositoryProvider.overrideWithValue(encounters),
          reviewScribeDraftUseCaseProvider.overrideWith(
            (Ref ref) => ReviewScribeDraftUseCase(
              repository: problems,
              encounters: encounters,
            ),
          ),
          recordProblemUseCaseProvider.overrideWith(
            (Ref ref) => RecordProblemUseCase(repository: problems),
          ),
          resolveProblemUseCaseProvider.overrideWith(
            (Ref ref) => ResolveProblemUseCase(repository: problems),
          ),
          scribeDraftsForEncounterProvider.overrideWith(
            (Ref ref, String encounterId) async => <ScribeDraft>[draft],
          ),
          problemsForPatientProvider.overrideWith(
            (Ref ref, String patientId) async => const <ClinicalProblem>[],
          ),
          activeProblemsProvider.overrideWith(
            (Ref ref, String patientId) async => const <ClinicalProblem>[],
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ScribeDraftPanel(encounter: encounters.encounter),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Expands the dictation card and opens the review sheet.
  Future<void> openReviewSheet(WidgetTester tester) async {
    await tester.tap(find.text('whisper-small'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review and accept'));
    await tester.pumpAndSettle();
  }

  group('dictation presentation', () {
    testWidgets('shows the transcript beside the machine text', (
      WidgetTester tester,
    ) async {
      await pumpPanel(
        tester,
        draft: draftWith(),
        permissions: <String>{NodexPermissions.aiOutputReview},
      );
      expect(
        find.text('Dictations'),
        findsOneWidget,
        reason: 'the panel is reachable',
      );
      expect(
        find.textContaining('Machine assessment.'),
        findsNothing,
        reason: 'sections stay collapsed until the card is expanded',
      );

      await tester.tap(find.text('whisper-small'));
      await tester.pumpAndSettle();

      expect(
        find.text('Patient reports chest pain on exertion.'),
        findsOneWidget,
      );
      expect(find.text('Machine assessment.'), findsOneWidget);
      expect(find.text('Machine subjective.'), findsOneWidget);
    });

    testWidgets('a reviewed dictation offers no acceptance', (
      WidgetTester tester,
    ) async {
      await pumpPanel(
        tester,
        draft: draftWith(status: ScribeDraftStatus.accepted),
        permissions: <String>{NodexPermissions.aiOutputReview},
      );
      await tester.tap(find.text('whisper-small'));
      await tester.pumpAndSettle();
      expect(find.text('Review and accept'), findsNothing);
      expect(find.text('Reject all'), findsNothing);
    });

    testWidgets('without the review permission no control is offered', (
      WidgetTester tester,
    ) async {
      await pumpPanel(
        tester,
        draft: draftWith(),
        permissions: <String>{NodexPermissions.encounterWrite},
      );
      await tester.tap(find.text('whisper-small'));
      await tester.pumpAndSettle();

      expect(find.text('Review and accept'), findsNothing);
      expect(
        find.textContaining('does not hold'),
        findsOneWidget,
        reason: 'the panel explains why rather than showing a dead button',
      );
    });

    testWidgets('a pending dictation on a signed encounter explains itself', (
      WidgetTester tester,
    ) async {
      await pumpPanel(
        tester,
        draft: draftWith(),
        permissions: <String>{NodexPermissions.aiOutputReview},
        status: EncounterStatus.signedAndLocked,
      );
      await tester.tap(find.text('whisper-small'));
      await tester.pumpAndSettle();

      expect(find.text('Review and accept'), findsNothing);
      expect(find.textContaining('This encounter is signed'), findsOneWidget);
    });
  });

  group('section selection', () {
    testWidgets('nothing is accepted while every box is unticked', (
      WidgetTester tester,
    ) async {
      await pumpPanel(
        tester,
        draft: draftWith(),
        permissions: <String>{NodexPermissions.aiOutputReview},
      );
      await openReviewSheet(tester);
      final Finder accept = find.widgetWithText(
        FilledButton,
        'Accept 0 section(s)',
      );
      expect(accept, findsOneWidget);
      expect(
        tester.widget<FilledButton>(accept).onPressed,
        isNull,
        reason: 'accepting nothing is not a valid review',
      );
      expect(problems.reviews, 0);
    });

    testWidgets('ticking one section accepts exactly that section', (
      WidgetTester tester,
    ) async {
      await pumpPanel(
        tester,
        draft: draftWith(),
        permissions: <String>{NodexPermissions.aiOutputReview},
      );
      await openReviewSheet(tester);

      await tickSection(tester, 'Assessment');
      await acceptSections(tester, 1);

      expect(problems.reviews, 1);
      expect(problems.accepted, <ScribeSection, String>{
        ScribeSection.assessment: 'Machine assessment.',
      }, reason: 'an unticked section is discarded, not sent as null');
      expect(encounters.writes.single['assessment'], 'Machine assessment.');
    });

    testWidgets('ticking several sections accepts each of them', (
      WidgetTester tester,
    ) async {
      await pumpPanel(
        tester,
        draft: draftWith(),
        permissions: <String>{NodexPermissions.aiOutputReview},
      );
      await openReviewSheet(tester);

      await tickSection(tester, 'Subjective');
      await tickSection(tester, 'Plan');
      await acceptSections(tester, 2);

      expect(problems.accepted, <ScribeSection, String>{
        ScribeSection.subjective: 'Machine subjective.',
        ScribeSection.plan: 'Machine plan.',
      });
    });

    testWidgets('unticking removes a section from the acceptance', (
      WidgetTester tester,
    ) async {
      await pumpPanel(
        tester,
        draft: draftWith(),
        permissions: <String>{NodexPermissions.aiOutputReview},
      );
      await openReviewSheet(tester);

      await tickSection(tester, 'Assessment');
      await tickSection(tester, 'Plan');
      await tickSection(tester, 'Plan');

      expect(find.text('Accept 1 section(s)'), findsOneWidget);
      await acceptSections(tester, 1);

      expect(problems.accepted, <ScribeSection, String>{
        ScribeSection.assessment: 'Machine assessment.',
      });
    });

    testWidgets('an edit to a ticked section is the text that travels', (
      WidgetTester tester,
    ) async {
      await pumpPanel(
        tester,
        draft: draftWith(),
        permissions: <String>{NodexPermissions.aiOutputReview},
      );
      await openReviewSheet(tester);

      await tickSection(tester, 'Assessment');

      // Find the assessment field among the section editors and correct it.
      final Finder editors = find.descendant(
        of: find.widgetWithText(CheckboxListTile, 'Assessment'),
        matching: find.byType(TextField),
      );
      await tester.enterText(editors.first, 'Reviewed: exertional angina.');
      await tester.pumpAndSettle();

      await acceptSections(tester, 1);

      expect(problems.accepted, <ScribeSection, String>{
        ScribeSection.assessment: 'Reviewed: exertional angina.',
      });
      expect(
        encounters.writes.single['assessment'],
        'Reviewed: exertional angina.',
        reason: 'the clinician edit wins over the machine text',
      );
    });

    testWidgets('a section the model left empty is not offered', (
      WidgetTester tester,
    ) async {
      await pumpPanel(
        tester,
        draft: draftWith(objective: null, plan: null),
        permissions: <String>{NodexPermissions.aiOutputReview},
      );
      await openReviewSheet(tester);
      expect(
        find.widgetWithText(CheckboxListTile, 'Subjective'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(CheckboxListTile, 'Assessment'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(CheckboxListTile, 'Objective'),
        findsNothing,
        reason:
            'there is nothing to accept for a section the model produced '
            'no text for',
      );
      expect(find.widgetWithText(CheckboxListTile, 'Plan'), findsNothing);
    });

    testWidgets('rejecting sends no sections and a reason', (
      WidgetTester tester,
    ) async {
      await pumpPanel(
        tester,
        draft: draftWith(),
        permissions: <String>{NodexPermissions.aiOutputReview},
      );
      await tester.tap(find.text('whisper-small'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reject all'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Misheard.');
      await tester.tap(find.widgetWithText(FilledButton, 'Reject'));
      await tester.pumpAndSettle();

      expect(problems.reviews, 1);
      expect(problems.rejectionReason, 'Misheard.');
      expect(problems.accepted, isEmpty, reason: 'a rejection accepts nothing');
      expect(encounters.writes, isEmpty);
    });

    testWidgets('dismissing the sheet accepts nothing', (
      WidgetTester tester,
    ) async {
      await pumpPanel(
        tester,
        draft: draftWith(),
        permissions: <String>{NodexPermissions.aiOutputReview},
      );
      await openReviewSheet(tester);

      // Ticking is not enough on its own; leaving the sheet must not commit.
      await tickSection(tester, 'Assessment');
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(problems.reviews, 0);
      expect(encounters.writes, isEmpty);
    });
  });
}
