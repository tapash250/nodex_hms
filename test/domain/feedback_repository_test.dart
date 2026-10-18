/// Tests for the feedback and grievance repository over a fake local store
/// (Module 36).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/feedback/feedback.dart';
import 'package:nodex_hms/domain/feedback/feedback_repository.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';

/// A minimal in-memory store covering the three feedback tables.
final class FakeFeedbackStore implements PatientLocalStore {
  /// Rows by table name and id.
  final Map<String, Map<String, Map<String, Object?>>> tables =
      <String, Map<String, Map<String, Object?>>>{};

  /// Set when the store should behave as a closed database.
  bool closed = false;

  static final RegExp _filterPattern = RegExp(r' and (\w+) = \?');
  static final RegExp _fromPattern = RegExp(r'from (\w+) ');

  Map<String, Map<String, Object?>> _table(String name) =>
      tables.putIfAbsent(name, () => <String, Map<String, Object?>>{});

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
    final RegExpMatch? from = _fromPattern.firstMatch(sql);
    if (from == null) {
      throw UnimplementedError('FakeFeedbackStore cannot run: $sql');
    }
    final String table = from.group(1)!;
    Iterable<Map<String, Object?>> rows = _table(table).values
        .where((Map<String, Object?> row) => row['tenant_id'] == parameters[0]);
    int next = 1;
    for (final RegExpMatch match in _filterPattern.allMatches(sql)) {
      final String column = match.group(1)!;
      final Object? expected = parameters[next++];
      rows = rows.where((Map<String, Object?> row) => row[column] == expected);
    }
    if (sql.contains('limit ?')) {
      rows = rows.take(parameters.last! as int);
    }
    return rows.toList(growable: false);
  }

  @override
  Future<Map<String, Object?>?> getById(String table, String id) async {
    _guard();
    return _table(table)[id];
  }

  @override
  Future<void> insert(String table, Map<String, Object?> row) async {
    _guard();
    _table(table)[row['id']! as String] = <String, Object?>{...row};
  }

  @override
  Future<void> update(
    String table,
    String id,
    Map<String, Object?> changes,
  ) async {
    _guard();
    final Map<String, Object?>? row = _table(table)[id];
    if (row == null) {
      throw StateError('missing row $id');
    }
    row.addAll(changes);
  }
}

void main() {
  late FakeFeedbackStore store;
  late DefaultFeedbackRepository repository;

  setUp(() {
    store = FakeFeedbackStore();
    repository = DefaultFeedbackRepository(
      store: store,
      logger: NodexLogger(
        sinks: <NodexLogSink>[InMemoryLogSink()],
        minimumLevel: NodexLogLevel.trace,
      ),
    );
  });

  String stamp(DateTime value) => value.toUtc().toIso8601String();

  Future<String> seedSurvey({
    required String id,
    String status = 'recorded',
    int score = 9,
  }) => repository.registerSurvey(<String, Object?>{
    'id': id,
    'tenant_id': 'tenant-1',
    'facility_id': 'facility-1',
    'survey_number': 'SV-$id',
    'patient_id': null,
    'encounter_id': null,
    'touchpoint': 'opd',
    'nps_score': score,
    'comment': 'Staff were kind.',
    'recorded_at': stamp(DateTime.utc(2026, 6, 12, 9)),
    'status': status,
    'action_note': status == 'actioned' ? 'Called the patient' : null,
    'actioned_by': status == 'actioned' ? 'user-2' : null,
    'actioned_at': status == 'actioned'
        ? stamp(DateTime.utc(2026, 6, 12, 11))
        : null,
    'voided_at': status == 'voided'
        ? stamp(DateTime.utc(2026, 6, 12, 11))
        : null,
    'void_reason': status == 'voided' ? 'Duplicate' : null,
    'recorded_by': 'user-1',
    'created_by': 'user-1',
    'created_at': stamp(DateTime.utc(2026, 6, 12, 9)),
    'updated_at': stamp(DateTime.utc(2026, 6, 12, 9)),
  });

  Future<String> seedComplaint({
    required String id,
    String status = 'logged',
    String severity = 'high',
    String? departmentId,
  }) => repository.registerComplaint(<String, Object?>{
    'id': id,
    'tenant_id': 'tenant-1',
    'facility_id': 'facility-1',
    'complaint_number': 'CMP-$id',
    'patient_id': null,
    'complainant_name': 'Rahima Begum',
    'complainant_contact': '01700000000',
    'channel': 'counter',
    'category': 'waiting_time',
    'severity': severity,
    'description': 'Waited three hours in the OPD queue.',
    'received_at': stamp(DateTime.utc(2026, 6, 11, 8)),
    'routed_department_id': departmentId,
    'routed_to': null,
    'routed_at': departmentId == null
        ? null
        : stamp(DateTime.utc(2026, 6, 11, 9)),
    'status': status,
    'acknowledged_at': status == 'logged'
        ? null
        : stamp(DateTime.utc(2026, 6, 11, 9)),
    'investigation_started_at':
        status == 'investigating' ||
            status == 'resolved' ||
            status == 'closed' ||
            status == 'dismissed'
        ? stamp(DateTime.utc(2026, 6, 11, 10))
        : null,
    'resolved_at': status == 'resolved' || status == 'closed'
        ? stamp(DateTime.utc(2026, 6, 12, 10))
        : null,
    'resolved_by': status == 'resolved' || status == 'closed' ? 'user-3' : null,
    'resolution_summary': status == 'resolved' || status == 'closed'
        ? 'Queue re-opened and triage staffed'
        : null,
    'closed_at': status == 'closed'
        ? stamp(DateTime.utc(2026, 6, 13, 10))
        : null,
    'closure_note': status == 'closed' ? 'Complainant informed by phone' : null,
    'dismissed_at': status == 'dismissed'
        ? stamp(DateTime.utc(2026, 6, 12, 10))
        : null,
    'dismiss_reason': status == 'dismissed' ? 'Attended elsewhere' : null,
    'voided_at': status == 'voided'
        ? stamp(DateTime.utc(2026, 6, 11, 10))
        : null,
    'void_reason': status == 'voided' ? 'Filed in error' : null,
    'logged_by': 'user-1',
    'created_by': 'user-1',
    'created_at': stamp(DateTime.utc(2026, 6, 11, 8)),
    'updated_at': stamp(DateTime.utc(2026, 6, 11, 8)),
  });

  Future<String> seedEvent({
    required String id,
    required String complaintId,
    String eventType = 'routed',
  }) => repository.appendRoutingEvent(<String, Object?>{
    'id': id,
    'tenant_id': 'tenant-1',
    'complaint_id': complaintId,
    'event_type': eventType,
    'from_department_id': null,
    'to_department_id': 'department-1',
    'assigned_to': 'user-3',
    'note': 'Sent to the OPD manager.',
    'occurred_at': stamp(DateTime.utc(2026, 6, 11, 9)),
    'recorded_by': 'user-2',
    'created_at': stamp(DateTime.utc(2026, 6, 11, 9)),
  });

  group('survey responses', () {
    test('lists the responses held for a tenant', () async {
      await seedSurvey(id: 's-1');
      await seedSurvey(id: 's-2', score: 4);
      final List<FeedbackSurvey> surveys = await repository.listSurveys(
        'tenant-1',
      );
      expect(surveys.map((FeedbackSurvey s) => s.id).toSet(), <String>{
        's-1',
        's-2',
      });
    });

    test('filters responses by status', () async {
      await seedSurvey(id: 's-1');
      await seedSurvey(id: 's-2', status: 'actioned');
      final List<FeedbackSurvey> actioned = await repository.listSurveys(
        'tenant-1',
        status: 'actioned',
      );
      expect(actioned.single.id, 's-2');
      expect(actioned.single.status, SurveyStatus.actioned);
    });

    test('reads one response by id', () async {
      await seedSurvey(id: 's-1', score: 7);
      final FeedbackSurvey? survey = await repository.surveyById('s-1');
      expect(survey, isNotNull);
      expect(survey!.npsScore, 7);
      expect(survey.band, NpsBand.passive);
      expect(survey.touchpoint, FeedbackTouchpoint.opd);
      expect(survey.recordedAt, DateTime.utc(2026, 6, 12, 9));
      expect(survey.isAnonymous, isTrue);
    });

    test('returns null for a response the device does not hold', () async {
      expect(await repository.surveyById('missing'), isNull);
    });

    test('derives the band from the score', () async {
      await seedSurvey(id: 's-1', score: 10);
      await seedSurvey(id: 's-2', score: 6);
      final FeedbackSurvey promoter = (await repository.surveyById('s-1'))!;
      final FeedbackSurvey detractor = (await repository.surveyById('s-2'))!;
      expect(promoter.band, NpsBand.promoter);
      expect(promoter.isPromoter, isTrue);
      expect(detractor.band, NpsBand.detractor);
      expect(detractor.isDetractor, isTrue);
    });

    test('applies a change set to a response', () async {
      await seedSurvey(id: 's-1');
      await repository.updateSurvey('s-1', <String, Object?>{
        'status': 'voided',
        'void_reason': 'Duplicate',
      });
      expect((await repository.surveyById('s-1'))!.status, SurveyStatus.voided);
    });
  });

  group('grievances', () {
    test('lists the grievances held for a tenant', () async {
      await seedComplaint(id: 'c-1');
      await seedComplaint(id: 'c-2', severity: 'low');
      final List<FeedbackComplaint> complaints = await repository
          .listComplaints('tenant-1');
      expect(complaints.map((FeedbackComplaint c) => c.id).toSet(), <String>{
        'c-1',
        'c-2',
      });
    });

    test('filters grievances by status', () async {
      await seedComplaint(id: 'c-1');
      await seedComplaint(id: 'c-2', status: 'closed');
      final List<FeedbackComplaint> logged = await repository.listComplaints(
        'tenant-1',
        status: 'logged',
      );
      expect(logged.single.id, 'c-1');
      expect(logged.single.isUnacknowledged, isTrue);
    });

    test('filters grievances by routed department', () async {
      await seedComplaint(id: 'c-1', departmentId: 'department-1');
      await seedComplaint(id: 'c-2', departmentId: 'department-2');
      final List<FeedbackComplaint> routed = await repository.listComplaints(
        'tenant-1',
        departmentId: 'department-2',
      );
      expect(routed.single.id, 'c-2');
      expect(routed.single.isRouted, isTrue);
    });

    test('reads one grievance by id', () async {
      await seedComplaint(id: 'c-1', departmentId: 'department-1');
      final FeedbackComplaint? complaint = await repository.complaintById(
        'c-1',
      );
      expect(complaint, isNotNull);
      expect(complaint!.category, ComplaintCategory.waitingTime);
      expect(complaint.severity, ComplaintSeverity.high);
      expect(complaint.channel, ComplaintChannel.counter);
      expect(complaint.receivedAt, DateTime.utc(2026, 6, 11, 8));
      expect(complaint.routedAt, DateTime.utc(2026, 6, 11, 9));
    });

    test('returns null for a grievance the device does not hold', () async {
      expect(await repository.complaintById('missing'), isNull);
    });

    test('derives the resolution window from the severity', () async {
      await seedComplaint(id: 'c-1', severity: 'low');
      final FeedbackComplaint complaint = (await repository.complaintById(
        'c-1',
      ))!;
      expect(complaint.resolutionWindow, const Duration(days: 14));
    });

    test('reads a closed grievance as settled and answered', () async {
      await seedComplaint(id: 'c-1', status: 'closed');
      final FeedbackComplaint complaint = (await repository.complaintById(
        'c-1',
      ))!;
      expect(complaint.isTerminal, isTrue);
      expect(complaint.isResolved, isTrue);
      expect(complaint.resolutionSummary, isNotNull);
      expect(complaint.closureNote, 'Complainant informed by phone');
    });

    test('applies a change set to a grievance', () async {
      await seedComplaint(id: 'c-1');
      await repository.updateComplaint('c-1', <String, Object?>{
        'status': 'acknowledged',
        'acknowledged_at': stamp(DateTime.utc(2026, 6, 11, 9)),
      });
      expect(
        (await repository.complaintById('c-1'))!.status,
        ComplaintStatus.acknowledged,
      );
    });
  });

  group('routing history', () {
    test('lists the routing events of a grievance', () async {
      await seedComplaint(id: 'c-1');
      await seedEvent(id: 'e-1', complaintId: 'c-1', eventType: 'logged');
      await seedEvent(id: 'e-2', complaintId: 'c-1');
      final List<ComplaintRoutingEvent> events = await repository
          .listRoutingEvents('tenant-1', complaintId: 'c-1');
      expect(events.map((ComplaintRoutingEvent e) => e.id).toSet(), <String>{
        'e-1',
        'e-2',
      });
    });

    test('reads the type, the destination and the note of an event', () async {
      await seedComplaint(id: 'c-1');
      await seedEvent(id: 'e-1', complaintId: 'c-1');
      final ComplaintRoutingEvent event = (await repository.listRoutingEvents(
        'tenant-1',
        complaintId: 'c-1',
      )).single;
      expect(event.eventType, RoutingEventType.routed);
      expect(event.isMovement, isTrue);
      expect(event.toDepartmentId, 'department-1');
      expect(event.assignedTo, 'user-3');
      expect(event.note, 'Sent to the OPD manager.');
      expect(event.occurredAt, DateTime.utc(2026, 6, 11, 9));
    });

    test('reads an intake event as not a movement', () async {
      await seedComplaint(id: 'c-1');
      await seedEvent(id: 'e-1', complaintId: 'c-1', eventType: 'logged');
      final ComplaintRoutingEvent event = (await repository.listRoutingEvents(
        'tenant-1',
        complaintId: 'c-1',
      )).single;
      expect(event.eventType, RoutingEventType.logged);
      expect(event.isMovement, isFalse);
    });

    test(
      'lists every routing event for a tenant when no grievance is named',
      () async {
        await seedComplaint(id: 'c-1');
        await seedComplaint(id: 'c-2');
        await seedEvent(id: 'e-1', complaintId: 'c-1');
        await seedEvent(id: 'e-2', complaintId: 'c-2');
        final List<ComplaintRoutingEvent> events = await repository
            .listRoutingEvents('tenant-1');
        expect(events, hasLength(2));
      },
    );

    test('the routing history only takes appends', () async {
      await seedComplaint(id: 'c-1');
      final String id = await seedEvent(id: 'e-1', complaintId: 'c-1');
      expect(store.tables[LocalTables.complaintRoutingEvents]![id], isNotNull);
    });
  });

  group('failure mapping', () {
    test('maps a closed database to a persistence error', () async {
      store.closed = true;
      await expectLater(
        repository.listSurveys('tenant-1'),
        throwsA(
          isA<PersistenceError>().having(
            (PersistenceError error) => error.code,
            'code',
            'database_not_open',
          ),
        ),
      );
      await expectLater(
        repository.listComplaints('tenant-1'),
        throwsA(isA<PersistenceError>()),
      );
      await expectLater(
        repository.listRoutingEvents('tenant-1'),
        throwsA(isA<PersistenceError>()),
      );
    });

    test('maps a failed grievance write to a persistence error', () async {
      store.closed = true;
      await expectLater(
        repository.updateComplaint('c-1', <String, Object?>{
          'status': 'logged',
        }),
        throwsA(isA<PersistenceError>()),
      );
      await expectLater(
        repository.registerSurvey(<String, Object?>{
          'id': 's-9',
          'tenant_id': 'tenant-1',
        }),
        throwsA(isA<PersistenceError>()),
      );
      await expectLater(
        repository.appendRoutingEvent(<String, Object?>{
          'id': 'e-9',
          'tenant_id': 'tenant-1',
        }),
        throwsA(isA<PersistenceError>()),
      );
    });

    test('maps a failed grievance read to a persistence error', () async {
      store.closed = true;
      await expectLater(
        repository.complaintById('c-1'),
        throwsA(isA<PersistenceError>()),
      );
      await expectLater(
        repository.surveyById('s-1'),
        throwsA(isA<PersistenceError>()),
      );
      await expectLater(
        repository.updateSurvey('s-1', <String, Object?>{'status': 'recorded'}),
        throwsA(isA<PersistenceError>()),
      );
    });
  });

  test('every feedback table has a local projection constant', () {
    expect(LocalTables.feedbackSurveys, 'feedback_surveys');
    expect(LocalTables.feedbackComplaints, 'feedback_complaints');
    expect(LocalTables.complaintRoutingEvents, 'complaint_routing_events');
  });
}
