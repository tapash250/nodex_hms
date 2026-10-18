/// Tests for the analytics warehouse repository over a fake local store
/// (Module 38).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/analytics/analytics.dart';
import 'package:nodex_hms/domain/analytics/analytics_repository.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';

/// A minimal in-memory store covering the four warehouse tables.
final class FakeAnalyticsStore implements PatientLocalStore {
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
      throw UnimplementedError('FakeAnalyticsStore cannot run: $sql');
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
  late FakeAnalyticsStore store;
  late DefaultAnalyticsRepository repository;

  setUp(() {
    store = FakeAnalyticsStore();
    repository = DefaultAnalyticsRepository(
      store: store,
      logger: NodexLogger(
        sinks: <NodexLogSink>[InMemoryLogSink()],
        minimumLevel: NodexLogLevel.trace,
      ),
    );
  });

  Future<String> seedDefinition({
    String id = '',
    String code = 'MORB-1',
    String name = 'Monthly morbidity',
    ReportCategory category = ReportCategory.morbidity,
    AnalyticsSource source = AnalyticsSource.encounters,
    AnalyticsGrain grain = AnalyticsGrain.month,
    int retentionDays = 3650,
    String status = 'draft',
    String? facilityId,
  }) => repository
      .registerDefinition(
        ReportDefinition.registerRow(
          tenantId: 'tenant-1',
          code: code,
          displayName: name,
          createdBy: 'user-1',
          category: category,
          primarySource: source,
          grain: grain,
          retentionDays: retentionDays,
          facilityId: facilityId,
          definitionId: id,
        ),
      )
      .then((String created) async {
        if (status == 'published') {
          await repository.updateDefinition(
            created,
            definitionPublishChanges(
              publishedBy: 'user-1',
              at: DateTime.utc(2026, 6, 12, 9),
            ),
          );
        } else if (status == 'retired') {
          await repository.updateDefinition(
            created,
            definitionPublishChanges(
              publishedBy: 'user-1',
              at: DateTime.utc(2026, 6, 12, 9),
            ),
          );
          await repository.updateDefinition(
            created,
            definitionRetireChanges(at: DateTime.utc(2026, 6, 13, 9)),
          );
        }
        return created;
      });

  Future<String> seedRollup({
    String id = '',
    required String definitionId,
    AnalyticsGrain grain = AnalyticsGrain.month,
    DateTime? periodStart,
    String status = 'materialised',
    int rowCount = 12,
    int numerator = 3,
    int denominator = 8,
    int incomeMinor = 100000,
    int expenditureMinor = 60000,
  }) => repository
      .registerRollup(
        AnalyticsRollup.registerRow(
          tenantId: 'tenant-1',
          definitionId: definitionId,
          periodStart: periodStart ?? DateTime.utc(2026, 5, 1),
          createdBy: 'user-1',
          grain: grain,
          rowCount: rowCount,
          numerator: numerator,
          denominator: denominator,
          incomeMinor: incomeMinor,
          expenditureMinor: expenditureMinor,
          rollupId: id,
        ),
      )
      .then((String created) async {
        if (status == 'superseded') {
          await repository.updateRollup(
            created,
            rollupSupersedeChanges(at: DateTime.utc(2026, 6, 12, 9)),
          );
        } else if (status == 'voided') {
          await repository.updateRollup(
            created,
            rollupVoidChanges(
              reason: 'Wrong period selected',
              at: DateTime.utc(2026, 6, 12, 9),
            ),
          );
        }
        return created;
      });

  Future<String> seedRun({
    String id = '',
    required String definitionId,
    String runNumber = 'RUN-1',
    AnalyticsGrain grain = AnalyticsGrain.month,
    DateTime? periodStart,
    String status = 'queued',
  }) => repository
      .registerRun(
        ReportRun.registerRow(
          tenantId: 'tenant-1',
          definitionId: definitionId,
          runNumber: runNumber,
          requestedBy: 'user-1',
          createdBy: 'user-1',
          periodStart: periodStart ?? DateTime.utc(2026, 5, 1),
          grain: grain,
          runId: id,
        ),
      )
      .then((String created) async {
        if (status == 'running') {
          await repository.updateRun(
            created,
            runStartChanges(at: DateTime.utc(2026, 6, 12, 9)),
          );
        } else if (status == 'succeeded') {
          await repository.updateRun(
            created,
            runStartChanges(at: DateTime.utc(2026, 6, 12, 9)),
          );
          await repository.updateRun(
            created,
            runSucceedChanges(
              servedFrom: RollupServedFrom.rollup,
              rowCount: 42,
              at: DateTime.utc(2026, 6, 12, 9, 1),
            ),
          );
        } else if (status == 'failed') {
          await repository.updateRun(
            created,
            runStartChanges(at: DateTime.utc(2026, 6, 12, 9)),
          );
          await repository.updateRun(
            created,
            runFailChanges(
              reason: 'The replica is not reachable.',
              at: DateTime.utc(2026, 6, 12, 9, 1),
            ),
          );
        } else if (status == 'cancelled') {
          await repository.updateRun(
            created,
            runCancelChanges(
              reason: 'Asked for the wrong period',
              at: DateTime.utc(2026, 6, 12, 9),
            ),
          );
        }
        return created;
      });

  Future<String> seedExport({
    String id = '',
    required String runId,
    String label = 'morbidity-2026-05.csv',
    DateTime? exportedAt,
  }) => repository.appendExport(
    AnalyticsExport.registerRow(
      tenantId: 'tenant-1',
      runId: runId,
      artifactLabel: label,
      exportedBy: 'user-1',
      exportedAt: exportedAt ?? DateTime.utc(2026, 6, 12, 10),
      exportId: id,
    ),
  );

  group('the report catalogue', () {
    test('lists the catalogue held for a tenant', () async {
      await seedDefinition(id: 'd-1', code: 'MORB-1');
      await seedDefinition(id: 'd-2', code: 'BURN-1', name: 'Pharmacy burn');
      final List<ReportDefinition> definitions = await repository
          .listDefinitions('tenant-1');
      expect(definitions.map((ReportDefinition d) => d.id).toSet(), <String>{
        'd-1',
        'd-2',
      });
    });

    test('filters the catalogue by category and by status', () async {
      await seedDefinition(
        id: 'd-1',
        code: 'MORB-1',
        category: ReportCategory.morbidity,
      );
      await seedDefinition(
        id: 'd-2',
        code: 'BURN-1',
        category: ReportCategory.pharmacy,
      );
      await seedDefinition(
        id: 'd-3',
        code: 'BAL-1',
        category: ReportCategory.morbidity,
        status: 'published',
      );
      final List<ReportDefinition> morbidity = await repository.listDefinitions(
        'tenant-1',
        category: 'morbidity',
      );
      expect(morbidity, hasLength(2));
      final List<ReportDefinition> published = await repository.listDefinitions(
        'tenant-1',
        status: 'published',
      );
      expect(published.single.id, 'd-3');
    });

    test('reads one definition by id', () async {
      await seedDefinition(
        id: 'd-1',
        code: 'MORB-1',
        category: ReportCategory.morbidity,
        source: AnalyticsSource.encounters,
        grain: AnalyticsGrain.month,
        retentionDays: 730,
      );
      final ReportDefinition? definition = await repository.definitionById(
        'd-1',
      );
      expect(definition, isNotNull);
      expect(definition!.code, 'MORB-1');
      expect(definition.displayName, 'Monthly morbidity');
      expect(definition.category, ReportCategory.morbidity);
      expect(definition.primarySource, AnalyticsSource.encounters);
      expect(definition.grain, AnalyticsGrain.month);
      expect(definition.retentionDays, 730);
      expect(definition.status, ReportDefinitionStatus.draft);
      expect(definition.isHospitalWide, isTrue);
      expect(definition.isRunnable, isFalse);
      expect(definition.isLive, isTrue);
    });

    test('reads a published definition as runnable', () async {
      await seedDefinition(id: 'd-1', status: 'published');
      final ReportDefinition definition = (await repository.definitionById(
        'd-1',
      ))!;
      expect(definition.status, ReportDefinitionStatus.published);
      expect(definition.publishedBy, 'user-1');
      expect(definition.publishedAt, DateTime.utc(2026, 6, 12, 9));
      expect(definition.isRunnable, isTrue);
    });

    test('reads a retired definition as settled', () async {
      await seedDefinition(id: 'd-1', status: 'retired');
      final ReportDefinition definition = (await repository.definitionById(
        'd-1',
      ))!;
      expect(definition.status, ReportDefinitionStatus.retired);
      expect(definition.retiredAt, DateTime.utc(2026, 6, 13, 9));
      expect(definition.isTerminal, isTrue);
      expect(definition.isRunnable, isFalse);
    });

    test('reads a facility-scoped definition as not hospital-wide', () async {
      await seedDefinition(id: 'd-1', facilityId: 'facility-1');
      final ReportDefinition definition = (await repository.definitionById(
        'd-1',
      ))!;
      expect(definition.facilityId, 'facility-1');
      expect(definition.isHospitalWide, isFalse);
    });

    test('returns null for a definition the device does not hold', () async {
      expect(await repository.definitionById('missing'), isNull);
    });

    test('applies a change set to a definition', () async {
      await seedDefinition(id: 'd-1');
      await repository.updateDefinition('d-1', <String, Object?>{
        'display_name': 'Renamed report',
      });
      expect(
        (await repository.definitionById('d-1'))!.displayName,
        'Renamed report',
      );
    });
  });

  group('figures', () {
    test('lists the figures held for a tenant', () async {
      final String definition = await seedDefinition(id: 'd-1');
      await seedRollup(id: 'g-1', definitionId: definition);
      await seedRollup(
        id: 'g-2',
        definitionId: definition,
        periodStart: DateTime.utc(2026, 6, 1),
      );
      final List<AnalyticsRollup> rollups = await repository.listRollups(
        'tenant-1',
      );
      expect(rollups.map((AnalyticsRollup r) => r.id).toSet(), <String>{
        'g-1',
        'g-2',
      });
    });

    test('filters figures by definition, grain and status', () async {
      final String first = await seedDefinition(id: 'd-1');
      final String second = await seedDefinition(id: 'd-2', code: 'BURN-1');
      await seedRollup(id: 'g-1', definitionId: first);
      await seedRollup(
        id: 'g-2',
        definitionId: first,
        periodStart: DateTime.utc(2026, 6, 1),
        status: 'superseded',
      );
      await seedRollup(
        id: 'g-3',
        definitionId: second,
        grain: AnalyticsGrain.week,
      );
      final List<AnalyticsRollup> forFirst = await repository.listRollups(
        'tenant-1',
        definitionId: first,
      );
      expect(forFirst, hasLength(2));
      final List<AnalyticsRollup> current = await repository.listRollups(
        'tenant-1',
        status: 'materialised',
      );
      expect(current.map((AnalyticsRollup r) => r.id).toSet(), <String>{
        'g-1',
        'g-3',
      });
      final List<AnalyticsRollup> weekly = await repository.listRollups(
        'tenant-1',
        grain: 'week',
      );
      expect(weekly.single.id, 'g-3');
    });

    test('reads one figure by id', () async {
      final String definition = await seedDefinition(id: 'd-1');
      await seedRollup(
        id: 'g-1',
        definitionId: definition,
        rowCount: 120,
        numerator: 9,
        denominator: 30,
        incomeMinor: 250000,
        expenditureMinor: 175000,
      );
      final AnalyticsRollup? rollup = await repository.rollupById('g-1');
      expect(rollup, isNotNull);
      expect(rollup!.definitionId, definition);
      expect(rollup.grain, AnalyticsGrain.month);
      expect(rollup.periodStart, DateTime.utc(2026, 5, 1));
      expect(rollup.periodEnd, DateTime.utc(2026, 5, 31));
      expect(rollup.rowCount, 120);
      expect(rollup.status, RollupStatus.materialised);
      expect(rollup.isCurrent, isTrue);
      expect(rollup.isTerminal, isFalse);
      expect(rollup.ratio, closeTo(30, 0.0001));
      expect(rollup.netPosition, 75000);
      expect(rollup.isSurplus, isTrue);
      expect(rollup.isDeficit, isFalse);
      expect(rollup.windowEnd, DateTime.utc(2026, 6, 1));
    });

    test('reads a superseded figure with the note kept', () async {
      final String definition = await seedDefinition(id: 'd-1');
      await seedRollup(
        id: 'g-1',
        definitionId: definition,
        status: 'superseded',
      );
      final AnalyticsRollup rollup = (await repository.rollupById('g-1'))!;
      expect(rollup.status, RollupStatus.superseded);
      expect(rollup.supersededAt, DateTime.utc(2026, 6, 12, 9));
      expect(rollup.isCurrent, isFalse);
      expect(rollup.isTerminal, isTrue);
    });

    test('reads a withdrawn figure with the reason kept', () async {
      final String definition = await seedDefinition(id: 'd-1');
      await seedRollup(id: 'g-1', definitionId: definition, status: 'voided');
      final AnalyticsRollup rollup = (await repository.rollupById('g-1'))!;
      expect(rollup.status, RollupStatus.voided);
      expect(rollup.voidReason, 'Wrong period selected');
      expect(rollup.voidedAt, DateTime.utc(2026, 6, 12, 9));
      expect(rollup.isTerminal, isTrue);
    });

    test('reads a figure that spent more than it made as a deficit', () async {
      final String definition = await seedDefinition(id: 'd-1');
      await seedRollup(
        id: 'g-1',
        definitionId: definition,
        incomeMinor: 40000,
        expenditureMinor: 90000,
      );
      final AnalyticsRollup rollup = (await repository.rollupById('g-1'))!;
      expect(rollup.netPosition, -50000);
      expect(rollup.isDeficit, isTrue);
      expect(rollup.isSurplus, isFalse);
    });

    test('returns null for a figure the device does not hold', () async {
      expect(await repository.rollupById('missing'), isNull);
    });

    test('applies a change set to a figure', () async {
      final String definition = await seedDefinition(id: 'd-1');
      await seedRollup(id: 'g-1', definitionId: definition);
      await repository.updateRollup('g-1', <String, Object?>{'row_count': 999});
      expect((await repository.rollupById('g-1'))!.rowCount, 999);
    });
  });

  group('runs', () {
    test('lists the runs held for a tenant', () async {
      final String definition = await seedDefinition(id: 'd-1');
      await seedRun(id: 'r-1', definitionId: definition);
      await seedRun(id: 'r-2', definitionId: definition, runNumber: 'RUN-2');
      final List<ReportRun> runs = await repository.listRuns('tenant-1');
      expect(runs.map((ReportRun r) => r.id).toSet(), <String>{'r-1', 'r-2'});
    });

    test('filters runs by definition and by status', () async {
      final String first = await seedDefinition(id: 'd-1');
      final String second = await seedDefinition(id: 'd-2', code: 'BURN-1');
      await seedRun(id: 'r-1', definitionId: first);
      await seedRun(
        id: 'r-2',
        definitionId: first,
        runNumber: 'RUN-2',
        status: 'running',
      );
      await seedRun(id: 'r-3', definitionId: second, runNumber: 'RUN-3');
      final List<ReportRun> forFirst = await repository.listRuns(
        'tenant-1',
        definitionId: first,
      );
      expect(forFirst, hasLength(2));
      final List<ReportRun> running = await repository.listRuns(
        'tenant-1',
        status: 'running',
      );
      expect(running.single.id, 'r-2');
    });

    test('reads one run by id', () async {
      final String definition = await seedDefinition(id: 'd-1');
      await seedRun(id: 'r-1', definitionId: definition);
      final ReportRun? run = await repository.runById('r-1');
      expect(run, isNotNull);
      expect(run!.definitionId, definition);
      expect(run.runNumber, 'RUN-1');
      expect(run.status, ReportRunStatus.queued);
      expect(run.isLive, isTrue);
      expect(run.isTerminal, isFalse);
      expect(run.requestedBy, 'user-1');
      expect(run.periodStart, DateTime.utc(2026, 5, 1));
      expect(run.periodEnd, DateTime.utc(2026, 5, 31));
      expect(run.servedFrom, isNull);
      expect(run.rowCount, isNull);
      expect(run.durationSeconds, isNull);
    });

    test('reads a running run with its start', () async {
      final String definition = await seedDefinition(id: 'd-1');
      await seedRun(id: 'r-1', definitionId: definition, status: 'running');
      final ReportRun run = (await repository.runById('r-1'))!;
      expect(run.status, ReportRunStatus.running);
      expect(run.startedAt, DateTime.utc(2026, 6, 12, 9));
      expect(run.servedFrom, isNull);
    });

    test('reads a finished run with what answered it', () async {
      final String definition = await seedDefinition(id: 'd-1');
      await seedRun(id: 'r-1', definitionId: definition, status: 'succeeded');
      final ReportRun run = (await repository.runById('r-1'))!;
      expect(run.status, ReportRunStatus.succeeded);
      expect(run.servedFrom, RollupServedFrom.rollup);
      expect(run.servedFromRollup, isTrue);
      expect(run.rowCount, 42);
      expect(run.durationSeconds, 60);
      expect(run.isTerminal, isTrue);
    });

    test('reads a failed run with the reason kept', () async {
      final String definition = await seedDefinition(id: 'd-1');
      await seedRun(id: 'r-1', definitionId: definition, status: 'failed');
      final ReportRun run = (await repository.runById('r-1'))!;
      expect(run.status, ReportRunStatus.failed);
      expect(run.failureReason, 'The replica is not reachable.');
      expect(run.finishedAt, DateTime.utc(2026, 6, 12, 9, 1));
    });

    test('reads an abandoned run with the reason kept', () async {
      final String definition = await seedDefinition(id: 'd-1');
      await seedRun(id: 'r-1', definitionId: definition, status: 'cancelled');
      final ReportRun run = (await repository.runById('r-1'))!;
      expect(run.status, ReportRunStatus.cancelled);
      expect(run.cancelReason, 'Asked for the wrong period');
      expect(run.cancelledAt, DateTime.utc(2026, 6, 12, 9));
    });

    test('returns null for a run the device does not hold', () async {
      expect(await repository.runById('missing'), isNull);
    });

    test('applies a change set to a run', () async {
      final String definition = await seedDefinition(id: 'd-1');
      await seedRun(id: 'r-1', definitionId: definition);
      await repository.updateRun('r-1', <String, Object?>{
        'status': 'running',
        'started_at': DateTime.utc(2026, 6, 12, 9).toIso8601String(),
      });
      expect((await repository.runById('r-1'))!.isLive, isTrue);
    });
  });

  group('the export log', () {
    test('lists the artefacts of a run', () async {
      final String definition = await seedDefinition(id: 'd-1');
      final String run = await seedRun(
        id: 'r-1',
        definitionId: definition,
        status: 'succeeded',
      );
      await seedExport(id: 'e-1', runId: run);
      await seedExport(id: 'e-2', runId: run, label: 'again.csv');
      final List<AnalyticsExport> exports = await repository.listExports(
        'tenant-1',
        runId: run,
      );
      expect(exports.map((AnalyticsExport e) => e.id).toSet(), <String>{
        'e-1',
        'e-2',
      });
    });

    test('reads one artefact with what it carried', () async {
      final String definition = await seedDefinition(id: 'd-1');
      final String run = await seedRun(
        id: 'r-1',
        definitionId: definition,
        status: 'succeeded',
      );
      await seedExport(id: 'e-1', runId: run);
      final AnalyticsExport export = (await repository.listExports(
        'tenant-1',
        runId: run,
      )).single;
      expect(export.runId, run);
      expect(export.artifactLabel, 'morbidity-2026-05.csv');
      expect(export.format, ExportFormat.csv);
      expect(export.destination, ExportDestination.download);
      expect(export.exportedBy, 'user-1');
      expect(export.exportedAt, DateTime.utc(2026, 6, 12, 10));
    });

    test('lists every artefact for a tenant when no run is named', () async {
      final String definition = await seedDefinition(id: 'd-1');
      final String run = await seedRun(
        id: 'r-1',
        definitionId: definition,
        status: 'succeeded',
      );
      await seedExport(id: 'e-1', runId: run);
      expect(await repository.listExports('tenant-1'), hasLength(1));
    });

    test('the log only takes appends', () async {
      final String definition = await seedDefinition(id: 'd-1');
      final String run = await seedRun(
        id: 'r-1',
        definitionId: definition,
        status: 'succeeded',
      );
      final String id = await seedExport(id: 'e-1', runId: run);
      expect(store.tables[LocalTables.analyticsExports]![id], isNotNull);
    });
  });

  group('failure mapping', () {
    test('maps a closed database to a persistence error', () async {
      store.closed = true;
      await expectLater(
        repository.listDefinitions('tenant-1'),
        throwsA(
          isA<PersistenceError>().having(
            (PersistenceError error) => error.code,
            'code',
            'database_not_open',
          ),
        ),
      );
      await expectLater(
        repository.listRollups('tenant-1'),
        throwsA(isA<PersistenceError>()),
      );
      await expectLater(
        repository.listRuns('tenant-1'),
        throwsA(isA<PersistenceError>()),
      );
      await expectLater(
        repository.listExports('tenant-1'),
        throwsA(isA<PersistenceError>()),
      );
    });

    test('maps a failed write to a persistence error', () async {
      store.closed = true;
      await expectLater(
        repository.registerDefinition(<String, Object?>{
          'id': 'd-9',
          'tenant_id': 'tenant-1',
        }),
        throwsA(isA<PersistenceError>()),
      );
      await expectLater(
        repository.registerRollup(<String, Object?>{
          'id': 'g-9',
          'tenant_id': 'tenant-1',
        }),
        throwsA(isA<PersistenceError>()),
      );
      await expectLater(
        repository.registerRun(<String, Object?>{
          'id': 'r-9',
          'tenant_id': 'tenant-1',
        }),
        throwsA(isA<PersistenceError>()),
      );
      await expectLater(
        repository.appendExport(<String, Object?>{
          'id': 'e-9',
          'tenant_id': 'tenant-1',
        }),
        throwsA(isA<PersistenceError>()),
      );
    });

    test('maps a failed read to a persistence error', () async {
      store.closed = true;
      await expectLater(
        repository.definitionById('d-1'),
        throwsA(isA<PersistenceError>()),
      );
      await expectLater(
        repository.rollupById('g-1'),
        throwsA(isA<PersistenceError>()),
      );
      await expectLater(
        repository.runById('r-1'),
        throwsA(isA<PersistenceError>()),
      );
      await expectLater(
        repository.updateRun('r-1', <String, Object?>{'status': 'running'}),
        throwsA(isA<PersistenceError>()),
      );
      await expectLater(
        repository.updateRollup('g-1', <String, Object?>{
          'status': 'superseded',
        }),
        throwsA(isA<PersistenceError>()),
      );
      await expectLater(
        repository.updateDefinition('d-1', <String, Object?>{
          'status': 'published',
        }),
        throwsA(isA<PersistenceError>()),
      );
    });
  });

  test('every warehouse table has a local projection constant', () {
    expect(
      LocalTables.analyticsReportDefinitions,
      'analytics_report_definitions',
    );
    expect(LocalTables.analyticsRollups, 'analytics_rollups');
    expect(LocalTables.analyticsReportRuns, 'analytics_report_runs');
    expect(LocalTables.analyticsExports, 'analytics_exports');
  });
}
