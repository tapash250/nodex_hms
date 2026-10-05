/// Widget tests for the problem list panel (Module 16).
///
/// The add sheet and the resolution dialog are private, so they are
/// driven through the exported panel. The use cases under the panel
/// are the real ones wired to a recording repository, so these tests
/// assert on what actually reaches the repository rather than on
/// what the widget claims it sent.
///
/// The behaviour worth protecting: resolution records an attributed
/// note against exactly the problem that was closed, nothing is
/// resolved without a note, a resolved problem is closed for good,
/// and a new problem is recorded with its code, description and
/// attribution.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/authorization_snapshot.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/domain/encounters/problem_list.dart';
import 'package:nodex_hms/domain/encounters/problem_list_repository.dart';
import 'package:nodex_hms/domain/session/session_state.dart';
import 'package:nodex_hms/features/encounters/encounters_controller.dart';
import 'package:nodex_hms/features/encounters/problem_list_panels.dart';
import 'package:nodex_hms/features/session/session_controller.dart';

/// Records what the problem-list commands were asked to do.
final class RecordingProblemRepository implements ProblemListRepository {
  RecordingProblemRepository(this.storedProblems);

  /// The list the panel renders, exactly as given.
  final List<ClinicalProblem> storedProblems;

  /// Rows handed to [ProblemListRepository.recordProblem].
  final List<Map<String, Object?>> recorded = <Map<String, Object?>>[];

  /// Resolution calls, each carrying the id of the problem it targeted.
  final List<Map<String, Object?>> resolutions = <Map<String, Object?>>[];

  @override
  Future<List<ClinicalProblem>> problemsForPatient(
    String patientId, {
    bool activeOnly = false,
  }) async => storedProblems;

  @override
  Future<ClinicalProblem?> problemById(String id) async => null;

  @override
  Future<String> recordProblem(Map<String, Object?> row) async {
    recorded.add(row);
    return 'problem-new';
  }

  @override
  Future<void> resolveProblem(String id, Map<String, Object?> changes) async {
    resolutions.add(<String, Object?>{'id': id, ...changes});
  }

  @override
  Future<List<ScribeDraft>> draftsForEncounter(String encounterId) async =>
      throw UnimplementedError();

  @override
  Future<ScribeDraft?> draftById(String id) async => throw UnimplementedError();

  @override
  Future<List<ScribeDraft>> pendingDrafts(String tenantId) async =>
      throw UnimplementedError();

  @override
  Future<String> recordDraft(Map<String, Object?> row) async =>
      throw UnimplementedError();

  @override
  Future<void> reviewDraft(String id, Map<String, Object?> changes) async =>
      throw UnimplementedError();
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

ClinicalProblem problemWith({
  ClinicalProblemStatus status = ClinicalProblemStatus.active,
  String id = 'problem-1',
  String resolutionNote = 'Settled on insulin.',
}) => ClinicalProblem(
  id: id,
  tenantId: 'tenant-1',
  patientId: 'patient-1',
  problemCode: 'E11.9',
  description: 'Type 2 diabetes mellitus',
  clinicalStatus: status,
  recordedBy: 'doctor-1',
  encounterId: 'encounter-1',
  resolvedBy: status.isResolved ? 'doctor-1' : null,
  resolutionNote: status.isResolved ? resolutionNote : null,
);

void main() {
  late RecordingProblemRepository repository;

  setUp(() {
    repository = RecordingProblemRepository(<ClinicalProblem>[]);
  });

  /// A tall viewport so dialogs and sheets lay out without clipping.
  void useTallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  /// Pumps the panel for [problems] with [permissions] held by the
  /// session. The use cases are the real ones; only the repository
  /// and the lists they read are substituted.
  Future<void> pumpPanel(
    WidgetTester tester, {
    required List<ClinicalProblem> problems,
    required Set<String> permissions,
    bool editable = true,
    Error? listError,
  }) async {
    useTallViewport(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionProvider.overrideWithBuild(
            (Ref ref, SessionController notifier) => sessionWith(permissions),
          ),
          problemListRepositoryProvider.overrideWithValue(repository),
          problemsForPatientProvider.overrideWith((
            Ref ref,
            String patientId,
          ) async {
            if (listError != null) throw listError;
            return problems;
          }),
          activeProblemsProvider.overrideWith(
            (Ref ref, String patientId) async => const <ClinicalProblem>[],
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ProblemListPanel(
              patientId: 'patient-1',
              encounterId: 'encounter-1',
              editable: editable,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('problem list', () {
    testWidgets('shows an empty list when nothing is recorded', (
      WidgetTester tester,
    ) async {
      await pumpPanel(
        tester,
        problems: const <ClinicalProblem>[],
        permissions: <String>{NodexPermissions.encounterWrite},
      );

      expect(find.text('No problems recorded.'), findsOneWidget);
    });

    testWidgets('an unreadable list says so', (WidgetTester tester) async {
      await pumpPanel(
        tester,
        problems: const <ClinicalProblem>[],
        permissions: <String>{NodexPermissions.encounterWrite},
        listError: StateError('boom'),
      );

      expect(
        find.text('Problem list unavailable: Bad state: boom'),
        findsOneWidget,
      );
    });
  });

  group('recording', () {
    testWidgets('records a new problem with its attribution', (
      WidgetTester tester,
    ) async {
      await pumpPanel(
        tester,
        problems: const <ClinicalProblem>[],
        permissions: <String>{NodexPermissions.encounterWrite},
      );

      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(find.text('Add problem'), findsOneWidget);

      await tester.enterText(find.byType(TextField).at(0), 'I10');
      await tester.enterText(
        find.byType(TextField).at(1),
        'Essential hypertension',
      );
      await tester.tap(
        find.widgetWithText(FilledButton, 'Add to problem list'),
      );
      await tester.pumpAndSettle();

      expect(repository.recorded, hasLength(1));
      expect(repository.recorded.single['problem_code'], 'I10');
      expect(
        repository.recorded.single['description'],
        'Essential hypertension',
      );
      expect(repository.recorded.single['patient_id'], 'patient-1');
      expect(repository.recorded.single['tenant_id'], 'tenant-1');
      expect(repository.recorded.single['encounter_id'], 'encounter-1');
      expect(repository.recorded.single['recorded_by'], 'doctor-2');
      expect(repository.recorded.single['clinical_status'], 'active');
      expect(find.text('Problem added to the list.'), findsOneWidget);
    });

    testWidgets('a problem cannot be added without a code or description', (
      WidgetTester tester,
    ) async {
      await pumpPanel(
        tester,
        problems: const <ClinicalProblem>[],
        permissions: <String>{NodexPermissions.encounterWrite},
      );

      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Add to problem list'),
      );
      await tester.pumpAndSettle();

      // Blank counts as empty, so the sheet stays open either way.
      await tester.enterText(find.byType(TextField).at(0), '   ');
      await tester.enterText(find.byType(TextField).at(1), '   ');
      await tester.tap(
        find.widgetWithText(FilledButton, 'Add to problem list'),
      );
      await tester.pumpAndSettle();

      expect(repository.recorded, isEmpty);
      expect(find.text('Add problem'), findsOneWidget);
    });

    testWidgets('recording needs the write permission', (
      WidgetTester tester,
    ) async {
      await pumpPanel(
        tester,
        problems: const <ClinicalProblem>[],
        permissions: const <String>{},
      );

      expect(find.text('Add'), findsNothing);
    });
  });

  group('resolution', () {
    testWidgets('records an attributed note against the resolved problem', (
      WidgetTester tester,
    ) async {
      await pumpPanel(
        tester,
        problems: <ClinicalProblem>[problemWith()],
        permissions: <String>{NodexPermissions.encounterWrite},
      );

      await tester.tap(find.text('Resolve'));
      await tester.pumpAndSettle();
      final Finder noteField = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(noteField, 'Settled on insulin.');
      await tester.tap(find.widgetWithText(FilledButton, 'Resolve'));
      await tester.pumpAndSettle();

      expect(repository.resolutions, hasLength(1));
      expect(repository.resolutions.single['id'], 'problem-1');
      expect(repository.resolutions.single['clinical_status'], 'resolved');
      expect(repository.resolutions.single['resolved_by'], 'doctor-2');
      expect(
        repository.resolutions.single['resolution_note'],
        'Settled on insulin.',
      );
      expect(find.text('Problem resolved.'), findsOneWidget);
    });

    testWidgets('an empty note resolves nothing', (WidgetTester tester) async {
      await pumpPanel(
        tester,
        problems: <ClinicalProblem>[problemWith()],
        permissions: <String>{NodexPermissions.encounterWrite},
      );

      await tester.tap(find.text('Resolve'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Resolve'));
      await tester.pumpAndSettle();

      expect(repository.resolutions, isEmpty);
      expect(find.byType(AlertDialog), findsNothing);
      // Not even a validation error: the empty note was never sent.
      expect(find.text('A problem must say how it resolved.'), findsNothing);
    });

    testWidgets('a resolved problem is closed for good', (
      WidgetTester tester,
    ) async {
      await pumpPanel(
        tester,
        problems: <ClinicalProblem>[
          problemWith(status: ClinicalProblemStatus.resolved),
        ],
        permissions: <String>{NodexPermissions.encounterWrite},
      );

      expect(find.text('E11.9 · Type 2 diabetes mellitus'), findsOneWidget);
      expect(find.text('Resolved · Settled on insulin.'), findsOneWidget);
      expect(find.text('Resolve'), findsNothing);
    });

    testWidgets('resolution needs the write permission', (
      WidgetTester tester,
    ) async {
      await pumpPanel(
        tester,
        problems: <ClinicalProblem>[problemWith()],
        permissions: const <String>{},
      );

      expect(find.text('Resolve'), findsNothing);
    });

    testWidgets('a closed encounter offers no resolution', (
      WidgetTester tester,
    ) async {
      await pumpPanel(
        tester,
        problems: <ClinicalProblem>[problemWith()],
        permissions: <String>{NodexPermissions.encounterWrite},
        editable: false,
      );

      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Resolve'), findsNothing);
      expect(find.text('Add'), findsNothing);
    });
  });
}
