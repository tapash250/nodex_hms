/// Tests for the quality hub repository over a fake local store (Module 35).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';
import 'package:nodex_hms/domain/quality/quality.dart';
import 'package:nodex_hms/domain/quality/quality_repository.dart';

/// A minimal in-memory store covering the three quality tables.
final class FakeQualityStore implements PatientLocalStore {
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
      throw UnimplementedError('FakeQualityStore cannot run: $sql');
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
  late FakeQualityStore store;
  late DefaultQualityRepository repository;

  setUp(() {
    store = FakeQualityStore();
    repository = DefaultQualityRepository(
      store: store,
      logger: NodexLogger(
        sinks: <NodexLogSink>[InMemoryLogSink()],
        minimumLevel: NodexLogLevel.trace,
      ),
    );
  });

  String stamp(DateTime value) => value.toUtc().toIso8601String();

  String day(DateTime value) =>
      value.toUtc().toIso8601String().substring(0, 10);

  Future<String> seedAudit({
    required String id,
    String status = 'planned',
    DateTime? scheduledFor,
    int? total,
    int? compliant,
  }) => repository.registerAudit(<String, Object?>{
    'id': id,
    'tenant_id': 'tenant-1',
    'facility_id': 'facility-1',
    'framework': 'nabh',
    'chapter': 'COP',
    'title': 'Care of patients',
    'standard_reference': 'COP 1',
    'auditor_id': 'user-9',
    'scheduled_for': stamp(scheduledFor ?? DateTime.utc(2026, 6, 1, 9)),
    'status': status,
    'conducted_at': status == 'planned'
        ? null
        : stamp(DateTime.utc(2026, 6, 1, 10)),
    'total_criteria': total,
    'compliant_criteria': compliant,
    'findings': null,
    'corrective_action_due_at': null,
    'completed_by': status == 'completed' ? 'user-9' : null,
    'cancelled_at': status == 'cancelled'
        ? stamp(DateTime.utc(2026, 6, 1, 11))
        : null,
    'cancel_reason': status == 'cancelled' ? 'Rescheduled' : null,
    'created_by': 'user-1',
    'created_at': stamp(DateTime.utc(2026, 5, 20)),
    'updated_at': stamp(DateTime.utc(2026, 5, 20)),
  });

  Future<String> seedIncident({
    required String id,
    String status = 'reported',
    String category = 'needle_stick',
    String severity = 'major',
    DateTime? occurredAt,
    DateTime? followUpDueAt,
  }) => repository.registerIncident(<String, Object?>{
    'id': id,
    'tenant_id': 'tenant-1',
    'facility_id': 'facility-1',
    'report_number': 'INC-$id',
    'category': category,
    'severity': severity,
    'title': 'Sharps injury in theatre',
    'description': 'Suture needle injury while clearing the trolley.',
    'occurred_at': stamp(occurredAt ?? DateTime.utc(2026, 6, 10, 14)),
    'reported_at': stamp(DateTime.utc(2026, 6, 10, 15)),
    'location': 'Theatre 3',
    'patient_id': null,
    'reported_by': 'user-2',
    'assigned_to': null,
    'immediate_action': 'Wound washed; PEP started',
    'status': status,
    'investigation_started_at': status == 'reported'
        ? null
        : stamp(DateTime.utc(2026, 6, 10, 16)),
    'action_plan': status == 'action_plan' || status == 'closed'
        ? 'Sharps bins replaced'
        : null,
    'action_plan_due_at': status == 'action_plan' || status == 'closed'
        ? stamp(DateTime.utc(2026, 6, 24))
        : null,
    'follow_up_due_at': ?followUpDueAt?.toUtc().toIso8601String(),
    'closed_at': status == 'closed' ? stamp(DateTime.utc(2026, 6, 20)) : null,
    'closure_note': status == 'closed' ? 'Bins replaced' : null,
    'voided_at': null,
    'void_reason': null,
    'created_by': 'user-2',
    'created_at': stamp(DateTime.utc(2026, 6, 10, 15)),
    'updated_at': stamp(DateTime.utc(2026, 6, 10, 15)),
  });

  Future<String> seedIndicator({
    required String id,
    String status = 'draft',
    String code = 'HAI-CLABSI',
    int numerator = 3,
    int denominator = 450,
    int? target = 1,
    String unit = 'per_1000_device_days',
  }) => repository.registerIndicator(<String, Object?>{
    'id': id,
    'tenant_id': 'tenant-1',
    'facility_id': 'facility-1',
    'code': code,
    'name': 'CLABSI rate',
    'category': 'infection_control',
    'unit': unit,
    'direction': 'lower_is_better',
    'period_start': day(DateTime.utc(2026, 5, 1)),
    'period_end': day(DateTime.utc(2026, 5, 31)),
    'numerator': numerator,
    'denominator': denominator,
    'target_value': target,
    'source_note': 'ICU line days',
    'status': status,
    'published_by': status == 'published' ? 'user-3' : null,
    'published_at': status == 'published'
        ? stamp(DateTime.utc(2026, 6, 2))
        : null,
    'retracted_at': null,
    'retract_reason': null,
    'created_by': 'user-3',
    'created_at': stamp(DateTime.utc(2026, 6, 1)),
    'updated_at': stamp(DateTime.utc(2026, 6, 1)),
  });

  group('compliance audits', () {
    test('lists the audits held for a tenant', () async {
      await seedAudit(id: 'a-1');
      await seedAudit(id: 'a-2');
      final List<ComplianceAudit> audits = await repository.listAudits(
        'tenant-1',
      );
      expect(audits.map((ComplianceAudit a) => a.id).toSet(), <String>{
        'a-1',
        'a-2',
      });
    });

    test('filters audits by status', () async {
      await seedAudit(id: 'a-1');
      await seedAudit(id: 'a-2', status: 'in_progress');
      final List<ComplianceAudit> live = await repository.listAudits(
        'tenant-1',
        status: 'in_progress',
      );
      expect(live.single.id, 'a-2');
      expect(live.single.status, AuditStatus.inProgress);
    });

    test('reads one audit by id', () async {
      await seedAudit(id: 'a-1', scheduledFor: DateTime.utc(2026, 7, 4, 8));
      final ComplianceAudit? audit = await repository.auditById('a-1');
      expect(audit, isNotNull);
      expect(audit!.framework, AccreditationFramework.nabh);
      expect(audit.scheduledFor, DateTime.utc(2026, 7, 4, 8));
    });

    test('returns null for an audit the device does not hold', () async {
      expect(await repository.auditById('missing'), isNull);
    });

    test('derives the score from the two criterion counts', () async {
      await seedAudit(id: 'a-1', status: 'completed', total: 20, compliant: 19);
      final ComplianceAudit audit = (await repository.auditById('a-1'))!;
      expect(audit.score, 95);
      expect(audit.verdict, AuditVerdict.conformant);
    });

    test('applies a change set to an audit', () async {
      await seedAudit(id: 'a-1');
      await repository.updateAudit('a-1', <String, Object?>{
        'status': 'in_progress',
      });
      expect(
        (await repository.auditById('a-1'))!.status,
        AuditStatus.inProgress,
      );
    });
  });

  group('incident reports', () {
    test('lists the incidents held for a tenant', () async {
      await seedIncident(id: 'i-1');
      await seedIncident(id: 'i-2', category: 'hai', severity: 'moderate');
      final List<IncidentReport> incidents = await repository.listIncidents(
        'tenant-1',
      );
      expect(incidents.map((IncidentReport i) => i.id).toSet(), <String>{
        'i-1',
        'i-2',
      });
    });

    test('filters incidents by status', () async {
      await seedIncident(id: 'i-1');
      await seedIncident(id: 'i-2', status: 'closed');
      final List<IncidentReport> open = await repository.listIncidents(
        'tenant-1',
        status: 'reported',
      );
      expect(open.single.id, 'i-1');
      expect(open.single.isNeedleStick, isTrue);
    });

    test('reads one incident by id', () async {
      await seedIncident(id: 'i-1');
      final IncidentReport? incident = await repository.incidentById('i-1');
      expect(incident, isNotNull);
      expect(incident!.category, IncidentCategory.needleStick);
      expect(incident.severity, IncidentSeverity.major);
      expect(incident.location, 'Theatre 3');
    });

    test('returns null for an incident the device does not hold', () async {
      expect(await repository.incidentById('missing'), isNull);
    });

    test('reads an HAI incident as an infection event', () async {
      await seedIncident(id: 'i-1', category: 'hai');
      final IncidentReport incident = (await repository.incidentById('i-1'))!;
      expect(incident.isHospitalAcquiredInfection, isTrue);
      expect(incident.isNeedleStick, isFalse);
    });

    test('applies a change set to an incident', () async {
      await seedIncident(id: 'i-1');
      await repository.updateIncident('i-1', <String, Object?>{
        'status': 'investigating',
      });
      expect(
        (await repository.incidentById('i-1'))!.status,
        IncidentStatus.investigating,
      );
    });
  });

  group('clinical indicators', () {
    test('lists the indicators held for a tenant', () async {
      await seedIndicator(id: 'n-1');
      await seedIndicator(id: 'n-2', code: 'HH-COMPLIANCE');
      final List<ClinicalIndicator> indicators = await repository
          .listIndicators('tenant-1');
      expect(indicators.map((ClinicalIndicator i) => i.id).toSet(), <String>{
        'n-1',
        'n-2',
      });
    });

    test('filters indicators by status', () async {
      await seedIndicator(id: 'n-1');
      await seedIndicator(id: 'n-2', status: 'published');
      final List<ClinicalIndicator> published = await repository.listIndicators(
        'tenant-1',
        status: 'published',
      );
      expect(published.single.id, 'n-2');
      expect(published.single.isPublished, isTrue);
    });

    test('reads one indicator by id', () async {
      await seedIndicator(id: 'n-1');
      final ClinicalIndicator? indicator = await repository.indicatorById(
        'n-1',
      );
      expect(indicator, isNotNull);
      expect(indicator!.unit, IndicatorUnit.perThousandDeviceDays);
      expect(indicator.periodStart, DateTime.utc(2026, 5, 1));
      expect(indicator.periodEnd, DateTime.utc(2026, 5, 31));
    });

    test('returns null for an indicator the device does not hold', () async {
      expect(await repository.indicatorById('missing'), isNull);
    });

    test('derives the value from the counts and the unit', () async {
      await seedIndicator(id: 'n-1');
      final ClinicalIndicator indicator = (await repository.indicatorById(
        'n-1',
      ))!;
      expect(indicator.value, closeTo(6.666, 0.001));
      expect(indicator.meetsTarget, isFalse);
    });

    test('applies a change set to an indicator', () async {
      await seedIndicator(id: 'n-1');
      await repository.updateIndicator('n-1', <String, Object?>{
        'status': 'published',
      });
      expect(
        (await repository.indicatorById('n-1'))!.status,
        IndicatorStatus.published,
      );
    });
  });

  group('failure mapping', () {
    test('maps a closed database to a persistence error', () async {
      store.closed = true;
      await expectLater(
        repository.listAudits('tenant-1'),
        throwsA(
          isA<PersistenceError>().having(
            (PersistenceError error) => error.code,
            'code',
            'database_not_open',
          ),
        ),
      );
      await expectLater(
        repository.listIncidents('tenant-1'),
        throwsA(isA<PersistenceError>()),
      );
      await expectLater(
        repository.listIndicators('tenant-1'),
        throwsA(isA<PersistenceError>()),
      );
    });

    test('maps a failed audit write to a persistence error', () async {
      store.closed = true;
      await expectLater(
        repository.updateAudit('a-1', <String, Object?>{'status': 'planned'}),
        throwsA(isA<PersistenceError>()),
      );
      await expectLater(
        repository.registerIncident(<String, Object?>{
          'id': 'i-9',
          'tenant_id': 'tenant-1',
        }),
        throwsA(isA<PersistenceError>()),
      );
      expect(store.tables, isEmpty);
    });

    test('maps a failed indicator read to a persistence error', () async {
      store.closed = true;
      await expectLater(
        repository.indicatorById('n-1'),
        throwsA(isA<PersistenceError>()),
      );
      await expectLater(
        repository.updateIndicator('n-1', <String, Object?>{'status': 'draft'}),
        throwsA(isA<PersistenceError>()),
      );
    });
  });

  test('every quality table has a local projection constant', () {
    expect(LocalTables.complianceAudits, 'compliance_audits');
    expect(LocalTables.incidentReports, 'incident_reports');
    expect(LocalTables.clinicalIndicators, 'clinical_indicators');
  });
}
