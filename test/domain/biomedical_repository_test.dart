/// Tests for the biomedical repository over a fake local store (Module 29).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/domain/biomedical/biomedical.dart';
import 'package:nodex_hms/domain/biomedical/biomedical_repository.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';

/// A minimal in-memory store covering the three biomedical tables.
final class FakeBiomedicalStore implements PatientLocalStore {
  final Map<String, Map<String, Map<String, Object?>>> tables =
      <String, Map<String, Map<String, Object?>>>{};
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
      throw UnimplementedError('FakeBiomedicalStore cannot run: $sql');
    }
    final String table = from.group(1)!;
    Iterable<Map<String, Object?>> rows = _table(table).values
        .where((Map<String, Object?> r) => r['tenant_id'] == parameters[0]);
    int next = 1;
    for (final RegExpMatch match in _filterPattern.allMatches(sql)) {
      final String column = match.group(1)!;
      final Object? expected = parameters[next++];
      rows = rows.where((Map<String, Object?> r) => r[column] == expected);
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
  late FakeBiomedicalStore store;
  late DefaultBiomedicalRepository repository;

  setUp(() {
    store = FakeBiomedicalStore();
    repository = DefaultBiomedicalRepository(
      store: store,
      logger: NodexLogger(
        sinks: <NodexLogSink>[InMemoryLogSink()],
        minimumLevel: NodexLogLevel.trace,
      ),
    );
  });

  String now() => DateTime.now().toUtc().toIso8601String();

  Future<String> seedAsset({
    required String id,
    String assetTag = 'A-1',
    String facilityId = 'f-1',
    String? departmentId = 'd-1',
    String status = 'in_service',
  }) => repository.registerAsset(<String, Object?>{
    'id': id,
    'tenant_id': 'tenant-1',
    'facility_id': facilityId,
    'department_id': departmentId,
    'asset_tag': assetTag,
    'name': 'Infusion pump',
    'category': 'pump',
    'manufacturer': 'Acme',
    'model_no': 'IP-9',
    'serial_no': 'SN-1',
    'criticality': 'high',
    'status': status,
    'commissioned_on': '2024-03-01',
    'warranty_until': null,
    'notes': null,
    'created_by': 'user-1',
    'created_at': now(),
    'updated_at': now(),
  });

  test(
    'registerAsset stores and resolves by id, parsing dates and enums',
    () async {
      final String id = await seedAsset(id: 'asset-1');
      final BiomedicalAsset? asset = await repository.assetById(id);
      expect(asset, isNotNull);
      expect(asset!.assetTag, 'A-1');
      expect(asset.criticality, AssetCriticality.high);
      expect(asset.status, AssetStatus.inService);
      expect(asset.commissionedOn, DateTime.utc(2024, 3, 1));
      expect(asset.warrantyUntil, isNull);
      expect(asset.serialNo, 'SN-1');
    },
  );

  test('listAssets filters by facility and department', () async {
    await seedAsset(id: 'asset-1', facilityId: 'f-1', departmentId: 'd-1');
    await seedAsset(
      id: 'asset-2',
      assetTag: 'A-2',
      facilityId: 'f-2',
      departmentId: 'd-2',
    );
    expect(
      await repository.listAssets('tenant-1', facilityId: 'f-1'),
      hasLength(1),
    );
    expect(
      await repository.listAssets('tenant-1', departmentId: 'd-2'),
      hasLength(1),
    );
  });

  test('updateAsset applies changes', () async {
    await seedAsset(id: 'asset-1');
    await repository.updateAsset('asset-1', <String, Object?>{
      'status': 'under_repair',
      'updated_at': now(),
    });
    expect(
      (await repository.assetById('asset-1'))!.status,
      AssetStatus.underRepair,
    );
  });

  test('breakdown tickets round-trip and list by asset', () async {
    await seedAsset(id: 'asset-1');
    await repository.registerTicket(<String, Object?>{
      'id': 'ticket-1',
      'tenant_id': 'tenant-1',
      'asset_id': 'asset-1',
      'facility_id': 'f-1',
      'reported_by': 'user-1',
      'reported_at': '2026-10-01T09:00:00.000Z',
      'priority': 'critical',
      'symptom': 'Alarm on every start',
      'status': 'reported',
      'created_by': 'user-1',
      'created_at': now(),
      'updated_at': now(),
    });
    final List<BreakdownTicket> tickets = await repository.listTickets(
      'tenant-1',
      assetId: 'asset-1',
    );
    expect(tickets, hasLength(1));
    expect(tickets.first.priority, TicketPriority.critical);
    expect(tickets.first.status, TicketStatus.reported);
    await repository.updateTicket('ticket-1', <String, Object?>{
      'status': 'acknowledged',
      'acknowledged_at': now(),
      'updated_at': now(),
    });
    expect(
      (await repository.ticketById('ticket-1'))!.status,
      TicketStatus.acknowledged,
    );
  });

  test('maintenance records round-trip and list by asset', () async {
    await seedAsset(id: 'asset-1');
    await repository.registerMaintenanceRecord(<String, Object?>{
      'id': 'maint-1',
      'tenant_id': 'tenant-1',
      'asset_id': 'asset-1',
      'ticket_id': null,
      'kind': 'calibration',
      'result': 'pass_adjusted',
      'performed_at': '2026-01-01T08:00:00.000Z',
      'performed_by': 'user-1',
      'provider': null,
      'next_due_at': '2026-07-01T08:00:00.000Z',
      'reference': 'CERT-9',
      'notes': null,
      'created_at': now(),
    });
    final List<MaintenanceRecord> records = await repository
        .listMaintenanceRecords('tenant-1', assetId: 'asset-1');
    expect(records, hasLength(1));
    expect(records.first.kind, MaintenanceKind.calibration);
    expect(records.first.result, MaintenanceResult.passAdjusted);
    expect(records.first.nextDueAt, DateTime.utc(2026, 7, 1, 8));
  });

  test('closed store raises and maps', () async {
    store.closed = true;
    expect(() => repository.listAssets('tenant-1'), throwsA(isA<NodexError>()));
  });
}
