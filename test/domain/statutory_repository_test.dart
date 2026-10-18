/// Tests for the statutory registry repository over a fake local store
/// (Module 34).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';
import 'package:nodex_hms/domain/statutory/statutory.dart';
import 'package:nodex_hms/domain/statutory/statutory_repository.dart';

/// A minimal in-memory store covering the four statutory tables.
final class FakeStatutoryStore implements PatientLocalStore {
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
      throw UnimplementedError('FakeStatutoryStore cannot run: $sql');
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
  late FakeStatutoryStore store;
  late DefaultStatutoryRepository repository;

  setUp(() {
    store = FakeStatutoryStore();
    repository = DefaultStatutoryRepository(
      store: store,
      logger: NodexLogger(
        sinks: <NodexLogSink>[InMemoryLogSink()],
        minimumLevel: NodexLogLevel.trace,
      ),
    );
  });

  String stamp(DateTime value) => value.toUtc().toIso8601String();

  Future<String> seedBirth({
    required String id,
    String status = 'drafted',
    String? registrationNumber,
    DateTime? birthAt,
  }) => repository.registerBirth(<String, Object?>{
    'id': id,
    'tenant_id': 'tenant-1',
    'facility_id': 'facility-1',
    'registration_number': registrationNumber,
    'child_name': 'Baby of Rabeya',
    'sex': 'female',
    'birth_at': stamp(birthAt ?? DateTime.utc(2026, 6, 1, 4)),
    'place_of_birth': 'Labour room 2',
    'delivery_type': 'normal',
    'plurality': 'singleton',
    'weight_grams': 3100,
    'mother_patient_id': 'patient-1',
    'mother_name': 'Rabeya Khatun',
    'father_name': 'Karim Mia',
    'informant_name': 'Karim Mia',
    'attended_by': 'user-1',
    'status': status,
    'registration_at': status == 'drafted'
        ? null
        : stamp(DateTime.utc(2026, 6, 2)),
    'certificate_number': null,
    'certified_by': null,
    'certified_at': null,
    'voided_at': null,
    'void_reason': null,
    'created_by': 'user-1',
    'created_at': stamp(DateTime.utc(2026, 6, 1, 5)),
    'updated_at': stamp(DateTime.utc(2026, 6, 1, 5)),
  });

  Future<String> seedDeath({
    required String id,
    String status = 'drafted',
    String? icd10Code,
    String? manner,
  }) => repository.registerDeath(<String, Object?>{
    'id': id,
    'tenant_id': 'tenant-1',
    'facility_id': 'facility-1',
    'registration_number': status == 'drafted' ? null : 'D-$id',
    'patient_id': 'patient-2',
    'deceased_name': 'Abdul Hoque',
    'sex': 'male',
    'age_years': 71,
    'death_at': stamp(DateTime.utc(2026, 6, 3, 2)),
    'place_of_death': 'ICU bed 4',
    'cause_of_death_text': icd10Code == null
        ? null
        : 'Acute myocardial infarction',
    'icd10_code': icd10Code,
    'manner_of_death': manner,
    'is_medico_legal': 0,
    'certifying_clinician': icd10Code == null ? null : 'user-2',
    'informant_name': 'Rahima Begum',
    'informant_relationship': 'daughter',
    'status': status,
    'registration_at': status == 'drafted'
        ? null
        : stamp(DateTime.utc(2026, 6, 4)),
    'certificate_number': null,
    'certified_by': null,
    'certified_at': null,
    'voided_at': null,
    'void_reason': null,
    'created_by': 'user-1',
    'created_at': stamp(DateTime.utc(2026, 6, 3, 3)),
    'updated_at': stamp(DateTime.utc(2026, 6, 3, 3)),
  });

  Future<String> seedCase({required String id, String status = 'reported'}) =>
      repository.registerMlcIntimation(<String, Object?>{
        'id': id,
        'tenant_id': 'tenant-1',
        'facility_id': 'facility-1',
        'case_number': 'MLC-$id',
        'patient_id': 'patient-3',
        'subject_name': 'Jashim Uddin',
        'case_type': 'road_traffic_accident',
        'incident_at': stamp(DateTime.utc(2026, 6, 5, 20)),
        'reported_at': stamp(DateTime.utc(2026, 6, 5, 22)),
        'reporting_clinician': 'user-1',
        'police_station': status == 'reported' ? null : 'Kotwali',
        'police_officer_name': null,
        'police_contact': null,
        'police_reference': null,
        'status': status,
        'intimated_at': status == 'reported'
            ? null
            : stamp(DateTime.utc(2026, 6, 5, 23)),
        'acknowledged_at': null,
        'closed_at': null,
        'closure_reason': null,
        'voided_at': null,
        'void_reason': null,
        'created_by': 'user-1',
        'created_at': stamp(DateTime.utc(2026, 6, 5, 22)),
        'updated_at': stamp(DateTime.utc(2026, 6, 5, 22)),
      });

  group('births', () {
    test('lists the births held for a tenant', () async {
      await seedBirth(id: 'b-1', birthAt: DateTime.utc(2026, 6, 1));
      await seedBirth(id: 'b-2', birthAt: DateTime.utc(2026, 6, 9));
      final List<BirthRecord> births = await repository.listBirths('tenant-1');
      expect(births.map((BirthRecord b) => b.id).toSet(), <String>{
        'b-1',
        'b-2',
      });
    });

    test('filters births by status', () async {
      await seedBirth(id: 'b-1');
      await seedBirth(
        id: 'b-2',
        status: 'registered',
        registrationNumber: 'B-2',
      );
      final List<BirthRecord> registered = await repository.listBirths(
        'tenant-1',
        status: 'registered',
      );
      expect(registered.map((BirthRecord b) => b.id).toList(), <String>['b-2']);
    });

    test('reads one birth by id and null when absent', () async {
      await seedBirth(id: 'b-1');
      final BirthRecord? found = await repository.birthById('b-1');
      expect(found?.childName, 'Baby of Rabeya');
      expect(found?.status, BirthStatus.drafted);
      expect(found?.weightGrams, 3100);
      expect(await repository.birthById('missing'), isNull);
    });

    test('updates a birth registration in place', () async {
      await seedBirth(id: 'b-1');
      await repository.updateBirth(
        'b-1',
        birthRegisterChanges(
          registrationNumber: 'B-2026-0001',
          at: DateTime.utc(2026, 6, 2),
        ),
      );
      final BirthRecord? record = await repository.birthById('b-1');
      expect(record?.status, BirthStatus.registered);
      expect(record?.registrationNumber, 'B-2026-0001');
      expect(record?.registrationAt, DateTime.utc(2026, 6, 2));
    });

    test('exposes the register reference for the amendment log', () async {
      await seedBirth(id: 'b-1');
      final BirthRecord record = (await repository.birthById('b-1'))!;
      expect(record.ref.kind, StatutoryRegistryKind.birth);
      expect(record.ref.id, 'b-1');
      expect(record.ref.canVoid, isTrue);
      expect(record.isDraft, isTrue);
      expect(record.isTerminal, isFalse);
    });
  });

  group('deaths', () {
    test('lists deaths newest event first', () async {
      await seedDeath(id: 'd-1');
      await seedDeath(id: 'd-2');
      final List<DeathRecord> deaths = await repository.listDeaths('tenant-1');
      expect(deaths, hasLength(2));
    });

    test('round-trips the cause-of-death coding', () async {
      await seedDeath(id: 'd-1', icd10Code: 'I21.9', manner: 'natural');
      final DeathRecord? record = await repository.deathById('d-1');
      expect(record?.icd10Code, 'I21.9');
      expect(record?.mannerOfDeath, MannerOfDeath.natural);
      expect(record?.isCoded, isTrue);
      expect(record?.isMedicoLegal, isFalse);
    });

    test('reports an uncoded death as not coded', () async {
      await seedDeath(id: 'd-2');
      final DeathRecord record = (await repository.deathById('d-2'))!;
      expect(record.isCoded, isFalse);
      expect(record.mannerOfDeath, isNull);
    });

    test('applies coding changes to a draft row', () async {
      await seedDeath(id: 'd-1');
      await repository.updateDeath(
        'd-1',
        deathCodingChanges(
          causeOfDeathText: 'Acute myocardial infarction',
          icd10Code: 'I21.9',
          mannerOfDeath: MannerOfDeath.natural,
          isMedicoLegal: false,
          certifyingClinician: 'user-2',
        ),
      );
      final DeathRecord record = (await repository.deathById('d-1'))!;
      expect(record.isCoded, isTrue);
      expect(record.certifyingClinician, 'user-2');
    });

    test('filters deaths by status', () async {
      await seedDeath(id: 'd-1');
      await seedDeath(
        id: 'd-2',
        status: 'registered',
        icd10Code: 'I21.9',
        manner: 'natural',
      );
      final List<DeathRecord> registered = await repository.listDeaths(
        'tenant-1',
        status: 'registered',
      );
      expect(registered.map((DeathRecord d) => d.id).toList(), <String>['d-2']);
    });
  });

  group('medico-legal cases', () {
    test('lists cases newest report first', () async {
      await seedCase(id: 'm-1');
      await seedCase(id: 'm-2');
      final List<MlcIntimation> cases = await repository.listMlcIntimations(
        'tenant-1',
      );
      expect(cases, hasLength(2));
      expect(cases.first.caseType, MlcCaseType.roadTrafficAccident);
    });

    test('filters cases by status and reads one by id', () async {
      await seedCase(id: 'm-1');
      await seedCase(id: 'm-2', status: 'intimated');
      final List<MlcIntimation> intimated = await repository.listMlcIntimations(
        'tenant-1',
        status: 'intimated',
      );
      expect(intimated.map((MlcIntimation m) => m.id).toList(), <String>[
        'm-2',
      ]);
      final MlcIntimation? found = await repository.mlcIntimationById('m-1');
      expect(found?.policeStation, isNull);
      expect(found?.status.isLive, isTrue);
    });

    test('updates a case through its transitions', () async {
      await seedCase(id: 'm-1');
      await repository.updateMlcIntimation(
        'm-1',
        mlcIntimateChanges(
          policeStation: 'Kotwali',
          policeOfficerName: 'SI Rana',
        ),
      );
      final MlcIntimation record = (await repository.mlcIntimationById('m-1'))!;
      expect(record.status, MlcStatus.intimated);
      expect(record.policeStation, 'Kotwali');
    });
  });

  group('amendments', () {
    test('lists the amendments for one register row', () async {
      await repository.registerAmendment(
        StatutoryAmendment.registerRow(
          tenantId: 'tenant-1',
          record: const StatutoryRecordRef(
            kind: StatutoryRegistryKind.birth,
            id: 'b-1',
            status: 'registered',
          ),
          subjectField: 'child_name',
          previousValue: 'Baby of Rabeya',
          newValue: 'Nusrat Jahan',
          reason: 'Name given at discharge',
          amendedBy: 'user-1',
          at: DateTime.utc(2026, 6, 5),
        ),
      );
      await repository.registerAmendment(
        StatutoryAmendment.registerRow(
          tenantId: 'tenant-1',
          record: const StatutoryRecordRef(
            kind: StatutoryRegistryKind.birth,
            id: 'b-1',
            status: 'registered',
          ),
          subjectField: 'mother_name',
          newValue: 'Rabeya Khatun',
          reason: 'Spelling corrected',
          amendedBy: 'user-1',
          at: DateTime.utc(2026, 6, 7),
        ),
      );
      final List<StatutoryAmendment> amendments = await repository
          .listAmendments(
            'tenant-1',
            kind: StatutoryRegistryKind.birth,
            recordId: 'b-1',
          );
      expect(amendments, hasLength(2));
      expect(
        amendments.map((StatutoryAmendment a) => a.subjectField).toSet(),
        <String>{'mother_name', 'child_name'},
      );
      expect(
        amendments.every(
          (StatutoryAmendment a) => a.kind == StatutoryRegistryKind.birth,
        ),
        isTrue,
      );
      expect(
        amendments.every((StatutoryAmendment a) => a.recordId == 'b-1'),
        isTrue,
      );
    });

    test('links an amendment to whichever register it corrects', () async {
      await repository.registerAmendment(
        StatutoryAmendment.registerRow(
          tenantId: 'tenant-1',
          record: const StatutoryRecordRef(
            kind: StatutoryRegistryKind.mlc,
            id: 'm-1',
            status: 'intimated',
          ),
          subjectField: 'police_station',
          newValue: 'Kotwali',
          reason: 'Station recorded wrongly',
          amendedBy: 'user-1',
        ),
      );
      final Map<String, Object?> row =
          store.tables[LocalTables.statutoryRecordAmendments]!.values.single;
      expect(row['mlc_intimation_id'], 'm-1');
      expect(row['birth_record_id'], isNull);
      expect(row['death_record_id'], isNull);
    });
  });

  group('errors', () {
    test('maps a closed store to a persistence error', () async {
      store.closed = true;
      await expectLater(
        repository.listBirths('tenant-1'),
        throwsA(
          isA<PersistenceError>().having(
            (PersistenceError error) => error.code,
            'code',
            'database_not_open',
          ),
        ),
      );
    });

    test('maps a failed update to a NodexError', () async {
      await expectLater(
        repository.updateBirth('missing', <String, Object?>{'status': 'x'}),
        throwsA(
          isA<NodexError>().having(
            (NodexError error) => error.code,
            'code',
            isNotEmpty,
          ),
        ),
      );
    });
  });
}
