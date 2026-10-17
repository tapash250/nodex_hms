/// Tests for the waste repository over a fake local store (Module 30).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';
import 'package:nodex_hms/domain/waste/waste.dart';
import 'package:nodex_hms/domain/waste/waste_repository.dart';

/// A minimal in-memory store covering the three waste tables.
final class FakeWasteStore implements PatientLocalStore {
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
      throw UnimplementedError('FakeWasteStore cannot run: $sql');
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
  late FakeWasteStore store;
  late DefaultWasteRepository repository;

  setUp(() {
    store = FakeWasteStore();
    repository = DefaultWasteRepository(
      store: store,
      logger: NodexLogger(
        sinks: <NodexLogSink>[InMemoryLogSink()],
        minimumLevel: NodexLogLevel.trace,
      ),
    );
  });

  String now() => DateTime.now().toUtc().toIso8601String();

  Future<String> seedCategory({
    required String id,
    String code = 'YEL',
    String name = 'Yellow stream',
    String colour = 'yellow',
    String hazardClass = 'infectious',
    int requiresTreatment = 1,
    int isActive = 1,
  }) => repository.registerCategory(<String, Object?>{
    'id': id,
    'tenant_id': 'tenant-1',
    'code': code,
    'name': name,
    'colour': colour,
    'hazard_class': hazardClass,
    'requires_treatment': requiresTreatment,
    'treatment_method': 'Incineration',
    'retention_days': 3,
    'is_active': isActive,
    'created_by': 'user-1',
    'created_at': now(),
    'updated_at': now(),
  });

  test('registerCategory resolves by id and parses the enums', () async {
    final String id = await seedCategory(id: 'cat-1');
    final WasteCategory? category = await repository.categoryById(id);
    expect(category, isNotNull);
    expect(category!.code, 'YEL');
    expect(category.colour, WasteColour.yellow);
    expect(category.hazardClass, WasteHazardClass.infectious);
    expect(category.requiresTreatment, isTrue);
    expect(category.isActive, isTrue);
    expect(category.retentionDays, 3);
    expect(category.treatmentMethod, 'Incineration');
  });

  test('listCategories scopes to the tenant', () async {
    await seedCategory(id: 'cat-1');
    await seedCategory(id: 'cat-2', code: 'RED');
    expect(await repository.listCategories('tenant-1'), hasLength(2));
    expect(await repository.listCategories('tenant-2'), isEmpty);
  });

  test('updateCategory applies changes', () async {
    await seedCategory(id: 'cat-1');
    await repository.updateCategory('cat-1', <String, Object?>{
      'is_active': 0,
      'updated_at': now(),
    });
    expect((await repository.categoryById('cat-1'))!.isActive, isFalse);
  });

  test('generation logs round-trip and filter by category', () async {
    await seedCategory(id: 'cat-1');
    await repository.registerGenerationLog(<String, Object?>{
      'id': 'log-1',
      'tenant_id': 'tenant-1',
      'facility_id': 'f-1',
      'category_id': 'cat-1',
      'department_id': 'd-1',
      'location_label': 'Ward 3',
      'weight_grams': 4500,
      'container_count': 2,
      'logged_at': '2026-10-01T09:00:00.000Z',
      'logged_by': 'user-1',
      'notes': null,
      'created_at': now(),
    });
    final List<WasteGenerationLog> logs = await repository.listGenerationLogs(
      'tenant-1',
      categoryId: 'cat-1',
    );
    expect(logs, hasLength(1));
    expect(logs.first.weightGrams, 4500);
    expect(logs.first.containerCount, 2);
    expect(logs.first.loggedAt, DateTime.utc(2026, 10, 1, 9));
    expect(logs.first.locationLabel, 'Ward 3');
    expect(
      await repository.listGenerationLogs('tenant-1', categoryId: 'cat-9'),
      isEmpty,
    );
  });

  test('disposal certificates round-trip and keep the void', () async {
    await seedCategory(id: 'cat-1');
    await repository.registerCertificate(<String, Object?>{
      'id': 'cert-1',
      'tenant_id': 'tenant-1',
      'facility_id': 'f-1',
      'category_id': 'cat-1',
      'certificate_no': 'DC-1',
      'barcode': 'BC-1',
      'disposal_vendor': 'Stericycle',
      'vendor_licence': 'LIC-9',
      'method': 'autoclave',
      'disposed_at': '2026-10-02T09:00:00.000Z',
      'weight_grams': 4200,
      'manifest_reference': 'MF-1',
      'status': 'issued',
      'void_reason': null,
      'issued_by': 'user-1',
      'created_at': now(),
      'updated_at': now(),
    });
    final DisposalCertificate? issued = await repository.certificateById(
      'cert-1',
    );
    expect(issued, isNotNull);
    expect(issued!.method, DisposalMethod.autoclave);
    expect(issued.status, CertificateStatus.issued);
    expect(issued.isLive, isTrue);

    await repository.updateCertificate('cert-1', <String, Object?>{
      'status': 'voided',
      'void_reason': 'Wrong vendor recorded',
      'updated_at': now(),
    });
    final DisposalCertificate? voided = await repository.certificateById(
      'cert-1',
    );
    expect(voided!.status, CertificateStatus.voided);
    expect(voided.voidReason, 'Wrong vendor recorded');
    expect(voided.isLive, isFalse);
  });

  test('listCertificates filters by category and facility', () async {
    await seedCategory(id: 'cat-1');
    Future<void> seed(String id, String categoryId, String facilityId) =>
        repository.registerCertificate(<String, Object?>{
          'id': id,
          'tenant_id': 'tenant-1',
          'facility_id': facilityId,
          'category_id': categoryId,
          'certificate_no': id,
          'barcode': id,
          'disposal_vendor': 'Vendor',
          'vendor_licence': null,
          'method': 'incineration',
          'disposed_at': '2026-10-02T09:00:00.000Z',
          'weight_grams': 100,
          'manifest_reference': null,
          'status': 'issued',
          'void_reason': null,
          'issued_by': 'user-1',
          'created_at': now(),
          'updated_at': now(),
        });
    await seed('cert-1', 'cat-1', 'f-1');
    await seed('cert-2', 'cat-1', 'f-2');
    expect(
      await repository.listCertificates('tenant-1', facilityId: 'f-1'),
      hasLength(1),
    );
    expect(
      await repository.listCertificates('tenant-1', categoryId: 'cat-1'),
      hasLength(2),
    );
  });

  test('closed store raises and maps', () async {
    store.closed = true;
    expect(
      () => repository.listCategories('tenant-1'),
      throwsA(isA<NodexError>()),
    );
  });
}
