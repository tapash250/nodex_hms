/// Tests for the visitor and pass repository over a fake local store
/// (Module 37).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';
import 'package:nodex_hms/domain/visitor/visitor.dart';
import 'package:nodex_hms/domain/visitor/visitor_repository.dart';

/// A minimal in-memory store covering the four visitor tables.
final class FakeVisitorStore implements PatientLocalStore {
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
      throw UnimplementedError('FakeVisitorStore cannot run: $sql');
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
  late FakeVisitorStore store;
  late DefaultVisitorRepository repository;

  setUp(() {
    store = FakeVisitorStore();
    repository = DefaultVisitorRepository(
      store: store,
      logger: NodexLogger(
        sinks: <NodexLogSink>[InMemoryLogSink()],
        minimumLevel: NodexLogLevel.trace,
      ),
    );
  });

  String stamp(DateTime value) => value.toUtc().toIso8601String();

  Future<String> seedWindow({
    required String id,
    String wardId = 'ward-1',
    int dayOfWeek = 1,
    int startsMinute = 600,
    int endsMinute = 720,
    int maxVisitors = 2,
    bool allowsChildren = false,
    String status = 'active',
  }) async {
    final String created = await repository.registerVisitingWindow(
      WardVisitingWindow.registerRow(
        tenantId: 'tenant-1',
        facilityId: 'facility-1',
        wardId: wardId,
        dayOfWeek: dayOfWeek,
        startsMinute: startsMinute,
        endsMinute: endsMinute,
        createdBy: 'user-1',
        maxVisitors: maxVisitors,
        allowsChildren: allowsChildren,
        windowId: id,
      ),
    );
    if (status != 'active') {
      await repository.updateVisitingWindow(
        created,
        wardVisitingWindowArchiveChanges(at: DateTime.utc(2026, 6, 12, 9)),
      );
    }
    return created;
  }

  Future<String> seedRegistration({
    required String id,
    String number = 'VR-1',
    String status = 'registered',
    String? wardId = 'ward-1',
    int? ageYears = 30,
    bool withDocument = false,
  }) => repository
      .registerRegistration(
        VisitorRegistration.registerRow(
          tenantId: 'tenant-1',
          facilityId: 'facility-1',
          registrationNumber: number,
          fullName: 'Rahima Begum',
          registeredBy: 'user-1',
          createdBy: 'user-1',
          purpose: VisitorPurpose.patientVisit,
          phone: '01700000000',
          wardId: wardId,
          ageYears: ageYears,
          idDocumentType: withDocument ? VisitorIdType.nationalId : null,
          idDocumentNumber: withDocument ? '1990123456789' : null,
          registeredAt: DateTime.utc(2026, 6, 11, 8),
          registrationId: id,
        ),
      )
      .then((String created) async {
        if (status == 'on_site') {
          await repository.updateRegistration(
            created,
            visitorRegistrationCheckInChanges(at: DateTime.utc(2026, 6, 11, 9)),
          );
        } else if (status == 'left') {
          await repository.updateRegistration(
            created,
            visitorRegistrationCheckInChanges(at: DateTime.utc(2026, 6, 11, 9)),
          );
          await repository.updateRegistration(
            created,
            visitorRegistrationCheckOutChanges(
              at: DateTime.utc(2026, 6, 11, 11),
            ),
          );
        } else if (status == 'refused') {
          await repository.updateRegistration(
            created,
            visitorRegistrationRefuseChanges(
              reason: 'No document to show',
              at: DateTime.utc(2026, 6, 11, 9),
            ),
          );
        } else if (status == 'voided') {
          await repository.updateRegistration(
            created,
            visitorRegistrationVoidChanges(
              reason: 'Taken against the wrong patient',
              at: DateTime.utc(2026, 6, 11, 9),
            ),
          );
        }
        return created;
      });

  Future<String> seedPass({
    required String id,
    required String registrationId,
    String badgeNumber = 'B-1',
    String status = 'issued',
    DateTime? validUntil,
    int escortCount = 0,
  }) => repository
      .registerPass(
        VisitorPass.registerRow(
          tenantId: 'tenant-1',
          facilityId: 'facility-1',
          registrationId: registrationId,
          badgeNumber: badgeNumber,
          issuedBy: 'user-1',
          createdBy: 'user-1',
          validUntil: validUntil ?? DateTime.utc(2026, 6, 11, 18),
          validFrom: DateTime.utc(2026, 6, 11, 9),
          escortCount: escortCount,
          accessScope: VisitorAccessScope.ward,
          passId: id,
        ),
      )
      .then((String created) async {
        if (status == 'active') {
          await repository.updatePass(
            created,
            visitorPassActivateChanges(at: DateTime.utc(2026, 6, 11, 9, 30)),
          );
        } else if (status == 'returned') {
          await repository.updatePass(
            created,
            visitorPassActivateChanges(at: DateTime.utc(2026, 6, 11, 9, 30)),
          );
          await repository.updatePass(
            created,
            visitorPassReturnChanges(at: DateTime.utc(2026, 6, 11, 12)),
          );
        } else if (status == 'revoked') {
          await repository.updatePass(
            created,
            visitorPassRevokeChanges(
              reason: 'Left without the badge',
              at: DateTime.utc(2026, 6, 11, 10),
            ),
          );
        }
        return created;
      });

  Future<String> seedPrint({
    required String id,
    required String passId,
    String badgeNumber = 'B-1',
    int printOrdinal = 1,
  }) => repository.appendBadgePrint(
    VisitorBadgePrint.registerRow(
      tenantId: 'tenant-1',
      passId: passId,
      badgeNumber: badgeNumber,
      printOrdinal: printOrdinal,
      printerLabel: 'Gate desk printer',
      printedBy: 'user-1',
      printedAt: DateTime.utc(2026, 6, 11, 9, 15),
      printId: id,
    ),
  );

  group('visiting windows', () {
    test('lists the windows held for a tenant', () async {
      await seedWindow(id: 'w-1');
      await seedWindow(id: 'w-2', wardId: 'ward-2');
      final List<WardVisitingWindow> windows = await repository
          .listVisitingWindows('tenant-1');
      expect(windows.map((WardVisitingWindow w) => w.id).toSet(), <String>{
        'w-1',
        'w-2',
      });
    });

    test('filters windows by ward and by status', () async {
      await seedWindow(id: 'w-1', wardId: 'ward-1');
      await seedWindow(id: 'w-2', wardId: 'ward-2');
      await seedWindow(id: 'w-3', wardId: 'ward-1', status: 'archived');
      final List<WardVisitingWindow> wardOne = await repository
          .listVisitingWindows('tenant-1', wardId: 'ward-1');
      expect(wardOne, hasLength(2));
      final List<WardVisitingWindow> active = await repository
          .listVisitingWindows('tenant-1', status: 'active');
      expect(active.map((WardVisitingWindow w) => w.id).toSet(), <String>{
        'w-1',
        'w-2',
      });
    });

    test('reads one window by id', () async {
      await seedWindow(id: 'w-1', startsMinute: 960, endsMinute: 1080);
      final WardVisitingWindow? window = await repository.visitingWindowById(
        'w-1',
      );
      expect(window, isNotNull);
      expect(window!.wardId, 'ward-1');
      expect(window.dayOfWeek, 1);
      expect(window.startsMinute, 960);
      expect(window.endsMinute, 1080);
      expect(window.duration, const Duration(hours: 2));
      expect(window.maxVisitors, 2);
      expect(window.allowsChildren, isFalse);
      expect(window.status, VisitorWindowStatus.active);
      expect(window.isActive, isTrue);
    });

    test('reads the children flag and the visitor limit', () async {
      await seedWindow(id: 'w-1', allowsChildren: true, maxVisitors: 4);
      final WardVisitingWindow window = (await repository.visitingWindowById(
        'w-1',
      ))!;
      expect(window.allowsChildren, isTrue);
      expect(window.maxVisitors, 4);
    });

    test('applies a change set to a window', () async {
      await seedWindow(id: 'w-1');
      await repository.updateVisitingWindow('w-1', <String, Object?>{
        'max_visitors': 6,
      });
      expect((await repository.visitingWindowById('w-1'))!.maxVisitors, 6);
    });

    test('returns null for a window the device does not hold', () async {
      expect(await repository.visitingWindowById('missing'), isNull);
    });
  });

  group('visitor registrations', () {
    test('lists the registrations held for a tenant', () async {
      await seedRegistration(id: 'r-1');
      await seedRegistration(id: 'r-2', number: 'VR-2');
      final List<VisitorRegistration> registrations = await repository
          .listRegistrations('tenant-1');
      expect(
        registrations.map((VisitorRegistration r) => r.id).toSet(),
        <String>{'r-1', 'r-2'},
      );
    });

    test('filters registrations by status and by ward', () async {
      await seedRegistration(id: 'r-1');
      await seedRegistration(id: 'r-2', number: 'VR-2', status: 'on_site');
      await seedRegistration(id: 'r-3', number: 'VR-3', wardId: 'ward-2');
      final List<VisitorRegistration> inside = await repository
          .listRegistrations('tenant-1', status: 'on_site');
      expect(inside.single.id, 'r-2');
      final List<VisitorRegistration> wardTwo = await repository
          .listRegistrations('tenant-1', wardId: 'ward-2');
      expect(wardTwo.single.id, 'r-3');
    });

    test('reads one registration by id', () async {
      await seedRegistration(id: 'r-1', withDocument: true, ageYears: 16);
      final VisitorRegistration? registration = await repository
          .registrationById('r-1');
      expect(registration, isNotNull);
      expect(registration!.registrationNumber, 'VR-1');
      expect(registration.fullName, 'Rahima Begum');
      expect(registration.purpose, VisitorPurpose.patientVisit);
      expect(registration.status, VisitorRegistrationStatus.registered);
      expect(registration.phone, '01700000000');
      expect(registration.wardId, 'ward-1');
      expect(registration.registeredAt, DateTime.utc(2026, 6, 11, 8));
      expect(registration.hasIdentityDocument, isTrue);
      expect(registration.idDocumentType, VisitorIdType.nationalId);
      expect(registration.isMinor, isTrue);
      expect(registration.isLive, isTrue);
      expect(registration.isOnSite, isFalse);
    });

    test(
      'an unaccompanied registration has no document and is not a minor',
      () async {
        await seedRegistration(id: 'r-1', ageYears: 41);
        final VisitorRegistration registration = (await repository
            .registrationById('r-1'))!;
        expect(registration.hasIdentityDocument, isFalse);
        expect(registration.isMinor, isFalse);
      },
    );

    test('reads a departed visitor as settled', () async {
      await seedRegistration(id: 'r-1', status: 'left');
      final VisitorRegistration registration = (await repository
          .registrationById('r-1'))!;
      expect(registration.status, VisitorRegistrationStatus.left);
      expect(registration.isTerminal, isTrue);
      expect(registration.isLive, isFalse);
      expect(registration.checkedInAt, DateTime.utc(2026, 6, 11, 9));
      expect(registration.checkedOutAt, DateTime.utc(2026, 6, 11, 11));
    });

    test('reads a refused visitor with the reason kept', () async {
      await seedRegistration(id: 'r-1', status: 'refused');
      final VisitorRegistration registration = (await repository
          .registrationById('r-1'))!;
      expect(registration.status, VisitorRegistrationStatus.refused);
      expect(registration.refuseReason, 'No document to show');
      expect(registration.refusedAt, DateTime.utc(2026, 6, 11, 9));
    });

    test('returns null for a registration the device does not hold', () async {
      expect(await repository.registrationById('missing'), isNull);
    });

    test('applies a change set to a registration', () async {
      await seedRegistration(id: 'r-1');
      await repository.updateRegistration('r-1', <String, Object?>{
        'status': 'on_site',
        'checked_in_at': stamp(DateTime.utc(2026, 6, 11, 9)),
      });
      final VisitorRegistration registration = (await repository
          .registrationById('r-1'))!;
      expect(registration.status, VisitorRegistrationStatus.onSite);
      expect(registration.isOnSite, isTrue);
    });
  });

  group('entry passes', () {
    test('lists the passes held for a tenant', () async {
      final String registration = await seedRegistration(id: 'r-1');
      await seedPass(id: 'p-1', registrationId: registration);
      await seedPass(
        id: 'p-2',
        registrationId: registration,
        badgeNumber: 'B-2',
      );
      final List<VisitorPass> passes = await repository.listPasses('tenant-1');
      expect(passes.map((VisitorPass p) => p.id).toSet(), <String>{
        'p-1',
        'p-2',
      });
    });

    test('filters passes by status and by registration', () async {
      final String registration = await seedRegistration(id: 'r-1');
      final String other = await seedRegistration(id: 'r-2', number: 'VR-2');
      await seedPass(id: 'p-1', registrationId: registration, status: 'active');
      await seedPass(id: 'p-2', registrationId: other, badgeNumber: 'B-2');
      final List<VisitorPass> active = await repository.listPasses(
        'tenant-1',
        status: 'active',
      );
      expect(active.single.id, 'p-1');
      final List<VisitorPass> forOther = await repository.listPasses(
        'tenant-1',
        registrationId: other,
      );
      expect(forOther.single.id, 'p-2');
    });

    test('reads one pass by id', () async {
      final String registration = await seedRegistration(id: 'r-1');
      await seedPass(id: 'p-1', registrationId: registration, escortCount: 1);
      final VisitorPass? pass = await repository.passById('p-1');
      expect(pass, isNotNull);
      expect(pass!.badgeNumber, 'B-1');
      expect(pass.accessScope, VisitorAccessScope.ward);
      expect(pass.escortCount, 1);
      expect(pass.status, VisitorPassStatus.issued);
      expect(pass.issuedBy, 'user-1');
      expect(pass.registrationId, registration);
      expect(pass.validFrom, DateTime.utc(2026, 6, 11, 9));
      expect(pass.validUntil, DateTime.utc(2026, 6, 11, 18));
      expect(pass.validity, const Duration(hours: 9));
      expect(pass.isTerminal, isFalse);
    });

    test('an issued pass is not expired before its window closes', () async {
      final String registration = await seedRegistration(id: 'r-1');
      await seedPass(id: 'p-1', registrationId: registration);
      final VisitorPass pass = (await repository.passById('p-1'))!;
      expect(
        isVisitorPassExpired(pass: pass, now: DateTime.utc(2026, 6, 11, 12)),
        isFalse,
      );
      expect(
        isVisitorPassExpired(pass: pass, now: DateTime.utc(2026, 6, 11, 19)),
        isTrue,
      );
    });

    test('reads a returned pass as settled', () async {
      final String registration = await seedRegistration(id: 'r-1');
      await seedPass(
        id: 'p-1',
        registrationId: registration,
        status: 'returned',
      );
      final VisitorPass pass = (await repository.passById('p-1'))!;
      expect(pass.status, VisitorPassStatus.returned);
      expect(pass.isTerminal, isTrue);
      expect(pass.isActive, isFalse);
      expect(pass.activatedAt, DateTime.utc(2026, 6, 11, 9, 30));
      expect(pass.returnedAt, DateTime.utc(2026, 6, 11, 12));
    });

    test('reads a revoked pass with the reason kept', () async {
      final String registration = await seedRegistration(id: 'r-1');
      await seedPass(
        id: 'p-1',
        registrationId: registration,
        status: 'revoked',
      );
      final VisitorPass pass = (await repository.passById('p-1'))!;
      expect(pass.status, VisitorPassStatus.revoked);
      expect(pass.revokeReason, 'Left without the badge');
      expect(pass.revokedAt, DateTime.utc(2026, 6, 11, 10));
      expect(pass.isTerminal, isTrue);
    });

    test('reads an active pass as admitting its holder', () async {
      final String registration = await seedRegistration(id: 'r-1');
      await seedPass(id: 'p-1', registrationId: registration, status: 'active');
      final VisitorPass pass = (await repository.passById('p-1'))!;
      expect(pass.status, VisitorPassStatus.active);
      expect(pass.isActive, isTrue);
      expect(
        isVisitorPassUsable(pass: pass, now: DateTime.utc(2026, 6, 11, 12)),
        isTrue,
      );
      expect(
        isVisitorPassUsable(pass: pass, now: DateTime.utc(2026, 6, 11, 19)),
        isFalse,
      );
    });

    test('returns null for a pass the device does not hold', () async {
      expect(await repository.passById('missing'), isNull);
    });

    test('applies a change set to a pass', () async {
      final String registration = await seedRegistration(id: 'r-1');
      await seedPass(id: 'p-1', registrationId: registration);
      await repository.updatePass('p-1', <String, Object?>{
        'status': 'active',
        'activated_at': stamp(DateTime.utc(2026, 6, 11, 10)),
      });
      expect((await repository.passById('p-1'))!.isActive, isTrue);
    });
  });

  group('badge print log', () {
    test('lists the prints of a pass', () async {
      final String registration = await seedRegistration(id: 'r-1');
      final String pass = await seedPass(
        id: 'p-1',
        registrationId: registration,
      );
      await seedPrint(id: 'g-1', passId: pass);
      await seedPrint(id: 'g-2', passId: pass, printOrdinal: 2);
      final List<VisitorBadgePrint> prints = await repository.listBadgePrints(
        'tenant-1',
        passId: pass,
      );
      expect(prints.map((VisitorBadgePrint p) => p.id).toSet(), <String>{
        'g-1',
        'g-2',
      });
    });

    test('reads a first print as not a reprint', () async {
      final String registration = await seedRegistration(id: 'r-1');
      final String pass = await seedPass(
        id: 'p-1',
        registrationId: registration,
      );
      await seedPrint(id: 'g-1', passId: pass);
      final VisitorBadgePrint print = (await repository.listBadgePrints(
        'tenant-1',
        passId: pass,
      )).single;
      expect(print.badgeNumber, 'B-1');
      expect(print.printOrdinal, 1);
      expect(print.printerLabel, 'Gate desk printer');
      expect(print.printedBy, 'user-1');
      expect(print.printedAt, DateTime.utc(2026, 6, 11, 9, 15));
      expect(print.isReprint, isFalse);
    });

    test('reads a second print as a reprint', () async {
      final String registration = await seedRegistration(id: 'r-1');
      final String pass = await seedPass(
        id: 'p-1',
        registrationId: registration,
      );
      await seedPrint(id: 'g-2', passId: pass, printOrdinal: 2);
      final VisitorBadgePrint print = (await repository.listBadgePrints(
        'tenant-1',
        passId: pass,
      )).single;
      expect(print.printOrdinal, 2);
      expect(print.isReprint, isTrue);
    });

    test('lists every print for a tenant when no pass is named', () async {
      final String registration = await seedRegistration(id: 'r-1');
      final String pass = await seedPass(
        id: 'p-1',
        registrationId: registration,
      );
      await seedPrint(id: 'g-1', passId: pass);
      expect(await repository.listBadgePrints('tenant-1'), hasLength(1));
    });

    test('the print log only takes appends', () async {
      final String registration = await seedRegistration(id: 'r-1');
      final String pass = await seedPass(
        id: 'p-1',
        registrationId: registration,
      );
      final String id = await seedPrint(id: 'g-1', passId: pass);
      expect(store.tables[LocalTables.visitorBadgePrints]![id], isNotNull);
    });
  });

  group('failure mapping', () {
    test('maps a closed database to a persistence error', () async {
      store.closed = true;
      await expectLater(
        repository.listVisitingWindows('tenant-1'),
        throwsA(
          isA<PersistenceError>().having(
            (PersistenceError error) => error.code,
            'code',
            'database_not_open',
          ),
        ),
      );
      await expectLater(
        repository.listRegistrations('tenant-1'),
        throwsA(isA<PersistenceError>()),
      );
      await expectLater(
        repository.listPasses('tenant-1'),
        throwsA(isA<PersistenceError>()),
      );
      await expectLater(
        repository.listBadgePrints('tenant-1'),
        throwsA(isA<PersistenceError>()),
      );
    });

    test('maps a failed write to a persistence error', () async {
      store.closed = true;
      await expectLater(
        repository.updateRegistration('r-1', <String, Object?>{
          'status': 'on_site',
        }),
        throwsA(isA<PersistenceError>()),
      );
      await expectLater(
        repository.registerPass(<String, Object?>{
          'id': 'p-9',
          'tenant_id': 'tenant-1',
        }),
        throwsA(isA<PersistenceError>()),
      );
      await expectLater(
        repository.appendBadgePrint(<String, Object?>{
          'id': 'g-9',
          'tenant_id': 'tenant-1',
        }),
        throwsA(isA<PersistenceError>()),
      );
      await expectLater(
        repository.registerVisitingWindow(<String, Object?>{
          'id': 'w-9',
          'tenant_id': 'tenant-1',
        }),
        throwsA(isA<PersistenceError>()),
      );
    });

    test('maps a failed read to a persistence error', () async {
      store.closed = true;
      await expectLater(
        repository.registrationById('r-1'),
        throwsA(isA<PersistenceError>()),
      );
      await expectLater(
        repository.passById('p-1'),
        throwsA(isA<PersistenceError>()),
      );
      await expectLater(
        repository.visitingWindowById('w-1'),
        throwsA(isA<PersistenceError>()),
      );
      await expectLater(
        repository.updatePass('p-1', <String, Object?>{'status': 'active'}),
        throwsA(isA<PersistenceError>()),
      );
      await expectLater(
        repository.updateVisitingWindow('w-1', <String, Object?>{
          'status': 'active',
        }),
        throwsA(isA<PersistenceError>()),
      );
    });
  });

  test('every visitor table has a local projection constant', () {
    expect(LocalTables.wardVisitingWindows, 'ward_visiting_windows');
    expect(LocalTables.visitorRegistrations, 'visitor_registrations');
    expect(LocalTables.visitorPasses, 'visitor_passes');
    expect(LocalTables.visitorBadgePrints, 'visitor_badge_prints');
  });
}
