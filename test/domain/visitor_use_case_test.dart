/// Tests for the visitor and pass use cases, the derived validity window and
/// the ward visiting hours (Module 37).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/authorization_snapshot.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/domain/visitor/visitor.dart';
import 'package:nodex_hms/domain/visitor/visitor_repository.dart';
import 'package:nodex_hms/domain/visitor/visitor_use_cases.dart';

import 'visitor_repository_test.dart' show FakeVisitorStore;

AuthorizationPolicy policyWith(
  Set<String> permissions, {
  ConnectivityState connectivity = ConnectivityState.online,
  Set<String>? offlinePermissions,
}) {
  final DateTime issuedAt = DateTime.now().toUtc();
  return AuthorizationPolicy(
    snapshot: AuthorizationSnapshot(
      snapshotId: 'snapshot-1',
      tenantId: 'tenant-1',
      userId: 'admin-1',
      deviceId: 'device-1',
      revision: 1,
      issuedAt: issuedAt,
      expiresAt: issuedAt.add(const Duration(days: 30)),
      payloadDigest: 'digest',
      roles: const <String>{NodexRoles.hospitalSuperAdmin},
      permissions: permissions,
      offlinePermissions: connectivity.isOnline
          ? permissions
          : (offlinePermissions ?? const <String>{}),
      facilityIds: const <String>{'facility-1'},
      departmentIds: const <String>{'department-1'},
      wardIds: const <String>{'ward-1', 'ward-2'},
    ),
    connectivity: connectivity,
  );
}

void main() {
  late FakeVisitorStore store;
  late DefaultVisitorRepository repository;
  late SetVisitingWindowUseCase setWindow;
  late ArchiveVisitingWindowUseCase archiveWindow;
  late RegisterVisitorUseCase registerVisitor;
  late AdmitVisitorUseCase admitVisitor;
  late RecordVisitorDepartureUseCase recordDeparture;
  late RefuseVisitorUseCase refuseVisitor;
  late VoidVisitorRegistrationUseCase voidRegistration;
  late IssueVisitorPassUseCase issuePass;
  late ActivateVisitorPassUseCase activatePass;
  late ReturnVisitorPassUseCase returnPass;
  late RevokeVisitorPassUseCase revokePass;
  late RecordBadgePrintUseCase printBadge;
  late ReadVisitorDeskUseCase readDesk;

  const Set<String> canRead = <String>{NodexPermissions.visitorRead};
  const Set<String> canRegister = <String>{NodexPermissions.visitorRegister};
  const Set<String> canPass = <String>{NodexPermissions.visitorPass};
  const Set<String> canConfigure = <String>{NodexPermissions.visitorConfigure};

  final AuthorizationPolicy reader = policyWith(canRead);
  final AuthorizationPolicy desk = policyWith(canRegister);
  final AuthorizationPolicy gate = policyWith(canPass);
  final AuthorizationPolicy administrator = policyWith(canConfigure);
  final DateTime now = DateTime.utc(2026, 6, 11, 12);

  setUp(() {
    store = FakeVisitorStore();
    repository = DefaultVisitorRepository(
      store: store,
      logger: NodexLogger(
        sinks: <NodexLogSink>[InMemoryLogSink()],
        minimumLevel: NodexLogLevel.trace,
      ),
    );
    setWindow = SetVisitingWindowUseCase(repository: repository);
    archiveWindow = ArchiveVisitingWindowUseCase(repository: repository);
    registerVisitor = RegisterVisitorUseCase(repository: repository);
    admitVisitor = AdmitVisitorUseCase(repository: repository);
    recordDeparture = RecordVisitorDepartureUseCase(repository: repository);
    refuseVisitor = RefuseVisitorUseCase(repository: repository);
    voidRegistration = VoidVisitorRegistrationUseCase(repository: repository);
    issuePass = IssueVisitorPassUseCase(repository: repository);
    activatePass = ActivateVisitorPassUseCase(repository: repository);
    returnPass = ReturnVisitorPassUseCase(repository: repository);
    revokePass = RevokeVisitorPassUseCase(repository: repository);
    printBadge = RecordBadgePrintUseCase(repository: repository);
    readDesk = ReadVisitorDeskUseCase(repository: repository);
  });

  Future<String> seedWindow({
    String id = '',
    String wardId = 'ward-1',
    int dayOfWeek = 4,
    int startsMinute = 600,
    int endsMinute = 720,
    int maxVisitors = 2,
    bool allowsChildren = false,
  }) => setWindow(
    policy: administrator,
    tenantId: 'tenant-1',
    facilityId: 'facility-1',
    wardId: wardId,
    dayOfWeek: dayOfWeek,
    startsMinute: startsMinute,
    endsMinute: endsMinute,
    createdBy: 'admin-1',
    maxVisitors: maxVisitors,
    allowsChildren: allowsChildren,
    windowId: id,
  );

  Future<String> seedVisitor({
    String id = '',
    String number = 'VR-1',
    VisitorPurpose purpose = VisitorPurpose.patientVisit,
    String? wardId = 'ward-1',
    int? ageYears = 30,
    VisitorIdType? document,
    String? documentNumber,
    DateTime? registeredAt,
  }) => registerVisitor(
    policy: desk,
    tenantId: 'tenant-1',
    facilityId: 'facility-1',
    registrationNumber: number,
    fullName: 'Rahima Begum',
    registeredBy: 'admin-1',
    createdBy: 'admin-1',
    purpose: purpose,
    wardId: wardId,
    ageYears: ageYears,
    idDocumentType: document,
    idDocumentNumber: documentNumber,
    registeredAt: registeredAt ?? DateTime.utc(2026, 6, 11, 8),
    registrationId: id,
  );

  Future<String> seedPass({
    required String registrationId,
    String id = '',
    String badgeNumber = 'B-1',
    DateTime? validFrom,
    DateTime? validUntil,
    int escortCount = 0,
    VisitorAccessScope accessScope = VisitorAccessScope.ward,
  }) async {
    final VisitorRegistration registration = (await repository.registrationById(
      registrationId,
    ))!;
    return issuePass(
      policy: gate,
      registration: registration,
      badgeNumber: badgeNumber,
      issuedBy: 'admin-1',
      createdBy: 'admin-1',
      validUntil: validUntil ?? DateTime.utc(2026, 6, 11, 18),
      validFrom: validFrom ?? DateTime.utc(2026, 6, 11, 9),
      escortCount: escortCount,
      accessScope: accessScope,
      passId: id,
    );
  }

  group('registration state machine', () {
    test('a registration is admitted, refused or withdrawn, then settled', () {
      expect(
        visitorRegistrationCanTransition(
          VisitorRegistrationStatus.registered,
          VisitorRegistrationStatus.onSite,
        ),
        isTrue,
      );
      expect(
        visitorRegistrationCanTransition(
          VisitorRegistrationStatus.registered,
          VisitorRegistrationStatus.refused,
        ),
        isTrue,
      );
      expect(
        visitorRegistrationCanTransition(
          VisitorRegistrationStatus.registered,
          VisitorRegistrationStatus.voided,
        ),
        isTrue,
      );
      expect(
        visitorRegistrationCanTransition(
          VisitorRegistrationStatus.onSite,
          VisitorRegistrationStatus.left,
        ),
        isTrue,
      );
    });

    test('a visitor inside is checked out, not refused or withdrawn', () {
      expect(
        visitorRegistrationCanTransition(
          VisitorRegistrationStatus.onSite,
          VisitorRegistrationStatus.refused,
        ),
        isFalse,
      );
      expect(
        visitorRegistrationCanTransition(
          VisitorRegistrationStatus.onSite,
          VisitorRegistrationStatus.voided,
        ),
        isFalse,
      );
      expect(VisitorRegistrationStatus.onSite.isOnSite, isTrue);
      expect(VisitorRegistrationStatus.onSite.isTerminal, isFalse);
    });

    test('a settled registration goes nowhere', () {
      for (final VisitorRegistrationStatus status
          in <VisitorRegistrationStatus>[
            VisitorRegistrationStatus.left,
            VisitorRegistrationStatus.refused,
            VisitorRegistrationStatus.voided,
          ]) {
        expect(status.isTerminal, isTrue, reason: status.wireValue);
        expect(status.isLive, isFalse, reason: status.wireValue);
        expect(
          visitorRegistrationCanTransition(
            status,
            VisitorRegistrationStatus.onSite,
          ),
          isFalse,
        );
      }
    });
  });

  group('pass state machine', () {
    test('a pass is activated, then returned', () {
      expect(
        visitorPassCanTransition(
          VisitorPassStatus.issued,
          VisitorPassStatus.active,
        ),
        isTrue,
      );
      expect(
        visitorPassCanTransition(
          VisitorPassStatus.active,
          VisitorPassStatus.returned,
        ),
        isTrue,
      );
    });

    test('a pass is revoked from either live stage', () {
      expect(
        visitorPassCanTransition(
          VisitorPassStatus.issued,
          VisitorPassStatus.revoked,
        ),
        isTrue,
      );
      expect(
        visitorPassCanTransition(
          VisitorPassStatus.active,
          VisitorPassStatus.revoked,
        ),
        isTrue,
      );
      expect(
        visitorPassCanTransition(
          VisitorPassStatus.issued,
          VisitorPassStatus.returned,
        ),
        isFalse,
      );
    });

    test('a settled pass goes nowhere', () {
      expect(VisitorPassStatus.returned.isTerminal, isTrue);
      expect(VisitorPassStatus.revoked.isTerminal, isTrue);
      expect(
        visitorPassCanTransition(
          VisitorPassStatus.returned,
          VisitorPassStatus.active,
        ),
        isFalse,
      );
      expect(
        visitorPassCanTransition(
          VisitorPassStatus.revoked,
          VisitorPassStatus.active,
        ),
        isFalse,
      );
    });
  });

  group('derived visiting hours', () {
    test('the weekday is read as the database stores it', () {
      // 2026-06-14 is a Sunday and 2026-06-15 a Monday.
      expect(dayOfWeekFor(DateTime.utc(2026, 6, 14)), 0);
      expect(dayOfWeekFor(DateTime.utc(2026, 6, 15)), 1);
      expect(dayOfWeekFor(DateTime.utc(2026, 6, 20)), 6);
    });

    test('the minute of day is read from the wall clock, not from UTC', () {
      expect(minuteOfDayFor(DateTime(2026, 6, 11, 10, 30)), 630);
      expect(minuteOfDayFor(DateTime(2026, 6, 11, 0, 0)), 0);
      expect(minuteOfDayFor(DateTime(2026, 6, 11, 23, 59)), 1439);
    });

    test('the window in force is resolved from the ward and the day', () {
      final WardVisitingWindow monday = WardVisitingWindow.fromRow(
        WardVisitingWindow.registerRow(
          tenantId: 'tenant-1',
          facilityId: 'facility-1',
          wardId: 'ward-1',
          dayOfWeek: 1,
          startsMinute: 600,
          endsMinute: 720,
          createdBy: 'admin-1',
          windowId: 'w-1',
        ),
      );
      final WardVisitingWindow found = visitingWindowFor(
        wardId: 'ward-1',
        dayOfWeek: 1,
        windows: <WardVisitingWindow>[monday],
      )!;
      expect(found, same(monday));
      expect(
        visitingWindowFor(
          wardId: 'ward-1',
          dayOfWeek: 2,
          windows: <WardVisitingWindow>[monday],
        ),
        isNull,
      );
      expect(
        visitingWindowFor(
          wardId: 'ward-2',
          dayOfWeek: 1,
          windows: <WardVisitingWindow>[monday],
        ),
        isNull,
      );
    });

    test('a retired window is not in force', () {
      final WardVisitingWindow retired = WardVisitingWindow.fromRow(
        <String, Object?>{
          ...WardVisitingWindow.registerRow(
            tenantId: 'tenant-1',
            facilityId: 'facility-1',
            wardId: 'ward-1',
            dayOfWeek: 1,
            startsMinute: 600,
            endsMinute: 720,
            createdBy: 'admin-1',
          ),
          'id': 'w-1',
          'status': 'archived',
        },
      );
      expect(retired.isActive, isFalse);
      expect(
        visitingWindowFor(
          wardId: 'ward-1',
          dayOfWeek: 1,
          windows: <WardVisitingWindow>[retired],
        ),
        isNull,
      );
    });

    test('the end minute is exclusive', () {
      final WardVisitingWindow window = WardVisitingWindow.fromRow(
        <String, Object?>{
          ...WardVisitingWindow.registerRow(
            tenantId: 'tenant-1',
            facilityId: 'facility-1',
            wardId: 'ward-1',
            dayOfWeek: 1,
            startsMinute: 600,
            endsMinute: 720,
            createdBy: 'admin-1',
          ),
          'id': 'w-1',
        },
      );
      expect(isWithinVisitingWindow(window: window, minuteOfDay: 599), isFalse);
      expect(isWithinVisitingWindow(window: window, minuteOfDay: 600), isTrue);
      expect(isWithinVisitingWindow(window: window, minuteOfDay: 719), isTrue);
      expect(isWithinVisitingWindow(window: window, minuteOfDay: 720), isFalse);
    });

    test('refuses a window that closes before it opens', () {
      expect(
        () => WardVisitingWindow.registerRow(
          tenantId: 'tenant-1',
          facilityId: 'facility-1',
          wardId: 'ward-1',
          dayOfWeek: 1,
          startsMinute: 720,
          endsMinute: 600,
          createdBy: 'admin-1',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.fieldErrors.keys.toSet(),
            'fields',
            contains('ends_minute'),
          ),
        ),
      );
    });

    test('refuses a window with no ward, day or creator', () {
      expect(
        () => WardVisitingWindow.registerRow(
          tenantId: 'tenant-1',
          facilityId: 'facility-1',
          wardId: '',
          dayOfWeek: 9,
          startsMinute: 600,
          endsMinute: 720,
          createdBy: '',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.fieldErrors.keys.toSet(),
            'fields',
            containsAll(<String>['ward_id', 'day_of_week', 'created_by']),
          ),
        ),
      );
    });
  });

  group('derived pass validity', () {
    VisitorPass passWith({
      required DateTime validUntil,
      String status = 'active',
    }) => VisitorPass.fromRow(<String, Object?>{
      ...VisitorPass.registerRow(
        tenantId: 'tenant-1',
        facilityId: 'facility-1',
        registrationId: 'r-1',
        badgeNumber: 'B-1',
        issuedBy: 'admin-1',
        createdBy: 'admin-1',
        validFrom: DateTime.utc(2026, 6, 11, 9),
        validUntil: validUntil,
      ),
      'id': 'p-1',
      'status': status,
    });

    test('a pass is expired only after its window closes', () {
      final VisitorPass pass = passWith(
        validUntil: DateTime.utc(2026, 6, 11, 18),
      );
      expect(isVisitorPassExpired(pass: pass, now: now), isFalse);
      expect(
        isVisitorPassExpired(pass: pass, now: DateTime.utc(2026, 6, 11, 18)),
        isFalse,
      );
      expect(
        isVisitorPassExpired(pass: pass, now: DateTime.utc(2026, 6, 11, 18, 1)),
        isTrue,
      );
    });

    test('an issued pass is not usable however fresh', () {
      final VisitorPass pass = passWith(
        validUntil: DateTime.utc(2026, 6, 11, 18),
        status: 'issued',
      );
      expect(isVisitorPassUsable(pass: pass, now: now), isFalse);
    });

    test('an active but expired pass is not usable', () {
      final VisitorPass pass = passWith(
        validUntil: DateTime.utc(2026, 6, 11, 10),
      );
      expect(isVisitorPassUsable(pass: pass, now: now), isFalse);
    });

    test('an active and unexpired pass is usable', () {
      final VisitorPass pass = passWith(
        validUntil: DateTime.utc(2026, 6, 11, 18),
      );
      expect(isVisitorPassUsable(pass: pass, now: now), isTrue);
    });
  });

  group('registration validation', () {
    test('refuses a registration with no number or name', () {
      expect(
        () => VisitorRegistration.registerRow(
          tenantId: 'tenant-1',
          facilityId: 'facility-1',
          registrationNumber: '  ',
          fullName: '',
          registeredBy: '',
          createdBy: 'admin-1',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.fieldErrors.keys.toSet(),
            'fields',
            containsAll(<String>[
              'registration_number',
              'full_name',
              'registered_by',
            ]),
          ),
        ),
      );
    });

    test('refuses half a document, and an unbelievable age', () {
      expect(
        () => VisitorRegistration.registerRow(
          tenantId: 'tenant-1',
          facilityId: 'facility-1',
          registrationNumber: 'VR-1',
          fullName: 'Rahima Begum',
          registeredBy: 'admin-1',
          createdBy: 'admin-1',
          ageYears: 200,
          idDocumentType: VisitorIdType.nationalId,
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.fieldErrors.keys.toSet(),
            'fields',
            containsAll(<String>['age_years', 'id_document_number']),
          ),
        ),
      );
    });

    test('accepts a document with both a type and a number', () {
      final Map<String, Object?> row = VisitorRegistration.registerRow(
        tenantId: 'tenant-1',
        facilityId: 'facility-1',
        registrationNumber: ' VR-1 ',
        fullName: ' Rahima Begum ',
        registeredBy: 'admin-1',
        createdBy: 'admin-1',
        idDocumentType: VisitorIdType.passport,
        idDocumentNumber: ' BM1234567 ',
      );
      expect(row['registration_number'], 'VR-1');
      expect(row['full_name'], 'Rahima Begum');
      expect(row['id_document_type'], 'passport');
      expect(row['id_document_number'], 'BM1234567');
      expect(row['status'], 'registered');
    });

    test('the refuse and void change sets need a reason', () {
      expect(
        () => visitorRegistrationRefuseChanges(reason: '  '),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'visitor_refuse_reason_missing',
          ),
        ),
      );
      expect(
        () => visitorRegistrationVoidChanges(reason: ''),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'visitor_registration_void_reason_missing',
          ),
        ),
      );
    });
  });

  group('pass validation', () {
    test('refuses a pass with no badge, registration or issuer', () {
      expect(
        () => VisitorPass.registerRow(
          tenantId: 'tenant-1',
          facilityId: 'facility-1',
          registrationId: '',
          badgeNumber: ' ',
          issuedBy: '',
          createdBy: 'admin-1',
          validUntil: DateTime.utc(2026, 6, 11, 18),
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.fieldErrors.keys.toSet(),
            'fields',
            containsAll(<String>[
              'registration_id',
              'badge_number',
              'issued_by',
            ]),
          ),
        ),
      );
    });

    test('refuses a pass that ends before it starts', () {
      expect(
        () => VisitorPass.registerRow(
          tenantId: 'tenant-1',
          facilityId: 'facility-1',
          registrationId: 'r-1',
          badgeNumber: 'B-1',
          issuedBy: 'admin-1',
          createdBy: 'admin-1',
          validFrom: DateTime.utc(2026, 6, 11, 18),
          validUntil: DateTime.utc(2026, 6, 11, 9),
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.fieldErrors.keys.toSet(),
            'fields',
            contains('valid_until'),
          ),
        ),
      );
    });

    test('the revoke change set needs a reason', () {
      expect(
        () => visitorPassRevokeChanges(reason: ' '),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'visitor_pass_revoke_reason_missing',
          ),
        ),
      );
    });

    test('refuses a print with no printer, badge or ordinal', () {
      expect(
        () => VisitorBadgePrint.registerRow(
          tenantId: 'tenant-1',
          passId: '',
          badgeNumber: '',
          printOrdinal: 0,
          printerLabel: ' ',
          printedBy: '',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.fieldErrors.keys.toSet(),
            'fields',
            containsAll(<String>[
              'pass_id',
              'badge_number',
              'print_ordinal',
              'printer_label',
              'printed_by',
            ]),
          ),
        ),
      );
    });
  });

  group('setting visiting hours', () {
    test('sets a window for a ward on a day', () async {
      final String id = await seedWindow(
        wardId: 'ward-1',
        dayOfWeek: 4,
        startsMinute: 600,
        endsMinute: 720,
        maxVisitors: 3,
        allowsChildren: true,
      );
      final WardVisitingWindow window = (await repository.visitingWindowById(
        id,
      ))!;
      expect(window.wardId, 'ward-1');
      expect(window.dayOfWeek, 4);
      expect(window.startsMinute, 600);
      expect(window.endsMinute, 720);
      expect(window.maxVisitors, 3);
      expect(window.allowsChildren, isTrue);
      expect(window.isActive, isTrue);
    });

    test('refuses a second window for the same ward on the same day', () async {
      await seedWindow(wardId: 'ward-1', dayOfWeek: 4);
      await expectLater(
        seedWindow(wardId: 'ward-1', dayOfWeek: 4, startsMinute: 840),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'ward_visiting_window_duplicate',
          ),
        ),
      );
    });

    test('a second day for the same ward is a different window', () async {
      await seedWindow(wardId: 'ward-1', dayOfWeek: 4);
      final String second = await seedWindow(wardId: 'ward-1', dayOfWeek: 5);
      expect((await repository.visitingWindowById(second))!.dayOfWeek, 5);
    });

    test('a retired window is replaced rather than duplicated', () async {
      final String first = await seedWindow(wardId: 'ward-1', dayOfWeek: 4);
      await archiveWindow(
        policy: administrator,
        window: (await repository.visitingWindowById(first))!,
      );
      final String second = await seedWindow(
        wardId: 'ward-1',
        dayOfWeek: 4,
        startsMinute: 840,
        endsMinute: 960,
      );
      expect((await repository.visitingWindowById(second))!.isActive, isTrue);
    });

    test(
      'a caller without the configure permission cannot set hours',
      () async {
        await expectLater(
          setWindow(
            policy: desk,
            tenantId: 'tenant-1',
            facilityId: 'facility-1',
            wardId: 'ward-1',
            dayOfWeek: 4,
            startsMinute: 600,
            endsMinute: 720,
            createdBy: 'admin-1',
          ),
          throwsA(isA<AuthorizationError>()),
        );
      },
    );

    test('a retired window cannot be retired twice', () async {
      final String id = await seedWindow();
      await archiveWindow(
        policy: administrator,
        window: (await repository.visitingWindowById(id))!,
      );
      await expectLater(
        archiveWindow(
          policy: administrator,
          window: (await repository.visitingWindowById(id))!,
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'ward_visiting_window_transition_invalid',
          ),
        ),
      );
    });

    test('retiring a window records the retired status', () async {
      final String id = await seedWindow();
      await archiveWindow(
        policy: administrator,
        window: (await repository.visitingWindowById(id))!,
        at: now,
      );
      final WardVisitingWindow window = (await repository.visitingWindowById(
        id,
      ))!;
      expect(window.status, VisitorWindowStatus.archived);
      expect(window.isActive, isFalse);
    });
  });

  group('the gate', () {
    test('takes a visitor with their purpose and document', () async {
      final String id = await seedVisitor(
        purpose: VisitorPurpose.attendant,
        document: VisitorIdType.nationalId,
        documentNumber: '1990123456789',
        ageYears: 42,
      );
      final VisitorRegistration registration = (await repository
          .registrationById(id))!;
      expect(registration.status, VisitorRegistrationStatus.registered);
      expect(registration.purpose, VisitorPurpose.attendant);
      expect(registration.hasIdentityDocument, isTrue);
      expect(registration.isMinor, isFalse);
      expect(registration.isLive, isTrue);
    });

    test('refuses a second registration with the same number', () async {
      await seedVisitor(number: 'VR-7');
      await expectLater(
        seedVisitor(number: 'VR-7', wardId: 'ward-2'),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'visitor_registration_number_duplicate',
          ),
        ),
      );
    });

    test(
      'a caller without the register permission cannot take a visitor',
      () async {
        await expectLater(
          registerVisitor(
            policy: reader,
            tenantId: 'tenant-1',
            facilityId: 'facility-1',
            registrationNumber: 'VR-1',
            fullName: 'Rahima Begum',
            registeredBy: 'admin-1',
            createdBy: 'admin-1',
          ),
          throwsA(isA<AuthorizationError>()),
        );
      },
    );

    test('admits a registered visitor and records the moment', () async {
      final String id = await seedVisitor();
      await admitVisitor(
        policy: desk,
        registration: (await repository.registrationById(id))!,
        at: now,
      );
      final VisitorRegistration registration = (await repository
          .registrationById(id))!;
      expect(registration.status, VisitorRegistrationStatus.onSite);
      expect(registration.isOnSite, isTrue);
      expect(registration.checkedInAt, now);
    });

    test('an admitted visitor is not admitted twice', () async {
      final String id = await seedVisitor();
      await admitVisitor(
        policy: desk,
        registration: (await repository.registrationById(id))!,
      );
      await expectLater(
        admitVisitor(
          policy: desk,
          registration: (await repository.registrationById(id))!,
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'visitor_registration_transition_invalid',
          ),
        ),
      );
    });

    test('records a departure and settles the registration', () async {
      final String id = await seedVisitor();
      await admitVisitor(
        policy: desk,
        registration: (await repository.registrationById(id))!,
        at: DateTime.utc(2026, 6, 11, 9),
      );
      await recordDeparture(
        policy: desk,
        registration: (await repository.registrationById(id))!,
        at: now,
      );
      final VisitorRegistration registration = (await repository
          .registrationById(id))!;
      expect(registration.status, VisitorRegistrationStatus.left);
      expect(registration.isTerminal, isTrue);
      expect(registration.checkedOutAt, now);
    });

    test('an unadmitted visitor has nothing to check out', () async {
      final String id = await seedVisitor();
      await expectLater(
        recordDeparture(
          policy: desk,
          registration: (await repository.registrationById(id))!,
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'visitor_registration_transition_invalid',
          ),
        ),
      );
    });

    test('refuses a registered visitor with the reason kept', () async {
      final String id = await seedVisitor();
      await refuseVisitor(
        policy: desk,
        registration: (await repository.registrationById(id))!,
        reason: 'No document to show',
        at: now,
      );
      final VisitorRegistration registration = (await repository
          .registrationById(id))!;
      expect(registration.status, VisitorRegistrationStatus.refused);
      expect(registration.refuseReason, 'No document to show');
      expect(registration.refusedAt, now);
      expect(registration.isTerminal, isTrue);
    });

    test('refusing without a reason is refused', () async {
      final String id = await seedVisitor();
      await expectLater(
        refuseVisitor(
          policy: desk,
          registration: (await repository.registrationById(id))!,
          reason: '   ',
        ),
        throwsA(isA<ValidationError>()),
      );
    });

    test('a visitor already inside is not refused at the gate', () async {
      final String id = await seedVisitor();
      await admitVisitor(
        policy: desk,
        registration: (await repository.registrationById(id))!,
      );
      await expectLater(
        refuseVisitor(
          policy: desk,
          registration: (await repository.registrationById(id))!,
          reason: 'Changed our mind',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('withdraws a fresh registration with the reason kept', () async {
      final String id = await seedVisitor();
      await voidRegistration(
        policy: desk,
        registration: (await repository.registrationById(id))!,
        reason: 'Taken against the wrong patient',
        at: now,
      );
      final VisitorRegistration registration = (await repository
          .registrationById(id))!;
      expect(registration.status, VisitorRegistrationStatus.voided);
      expect(registration.voidReason, 'Taken against the wrong patient');
      expect(registration.voidedAt, now);
    });

    test('a visitor who came in is checked out, not withdrawn', () async {
      final String id = await seedVisitor();
      await admitVisitor(
        policy: desk,
        registration: (await repository.registrationById(id))!,
      );
      await expectLater(
        voidRegistration(
          policy: desk,
          registration: (await repository.registrationById(id))!,
          reason: 'Changed our mind',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('a reader cannot admit or refuse a visitor', () async {
      final String id = await seedVisitor();
      final VisitorRegistration registration = (await repository
          .registrationById(id))!;
      await expectLater(
        admitVisitor(policy: reader, registration: registration),
        throwsA(isA<AuthorizationError>()),
      );
      await expectLater(
        refuseVisitor(
          policy: reader,
          registration: registration,
          reason: 'No document',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });
  });

  group('issuing passes', () {
    test('issues a pass against a live registration', () async {
      final String visitor = await seedVisitor();
      final String id = await seedPass(
        registrationId: visitor,
        escortCount: 1,
        accessScope: VisitorAccessScope.icu,
      );
      final VisitorPass pass = (await repository.passById(id))!;
      expect(pass.registrationId, visitor);
      expect(pass.badgeNumber, 'B-1');
      expect(pass.accessScope, VisitorAccessScope.icu);
      expect(pass.escortCount, 1);
      expect(pass.status, VisitorPassStatus.issued);
      expect(pass.isLive, isTrue);
    });

    test('refuses a pass against a refused visitor', () async {
      final String visitor = await seedVisitor();
      await refuseVisitor(
        policy: desk,
        registration: (await repository.registrationById(visitor))!,
        reason: 'No document to show',
      );
      await expectLater(
        issuePass(
          policy: gate,
          registration: (await repository.registrationById(visitor))!,
          badgeNumber: 'B-1',
          issuedBy: 'admin-1',
          createdBy: 'admin-1',
          validUntil: DateTime.utc(2026, 6, 11, 18),
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'visitor_pass_registration_settled',
          ),
        ),
      );
    });

    test('refuses a second pass with the same badge number', () async {
      final String visitor = await seedVisitor();
      final String other = await seedVisitor(number: 'VR-2', wardId: 'ward-2');
      await seedPass(registrationId: visitor, badgeNumber: 'B-7');
      await expectLater(
        seedPass(registrationId: other, badgeNumber: 'B-7'),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'visitor_pass_badge_duplicate',
          ),
        ),
      );
    });

    test('a caller without the pass permission cannot issue', () async {
      final String visitor = await seedVisitor();
      await expectLater(
        issuePass(
          policy: desk,
          registration: (await repository.registrationById(visitor))!,
          badgeNumber: 'B-1',
          issuedBy: 'admin-1',
          createdBy: 'admin-1',
          validUntil: DateTime.utc(2026, 6, 11, 18),
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });
  });

  group('working passes', () {
    test('activates an issued pass at the gate', () async {
      final String visitor = await seedVisitor();
      final String id = await seedPass(registrationId: visitor);
      await activatePass(
        policy: gate,
        pass: (await repository.passById(id))!,
        at: now,
      );
      final VisitorPass pass = (await repository.passById(id))!;
      expect(pass.status, VisitorPassStatus.active);
      expect(pass.activatedAt, now);
      expect(
        isVisitorPassUsable(pass: pass, now: DateTime.utc(2026, 6, 11, 18)),
        isTrue,
      );
    });

    test('refuses to activate a pass whose window has closed', () async {
      final String visitor = await seedVisitor();
      final String id = await seedPass(
        registrationId: visitor,
        validFrom: DateTime.utc(2026, 6, 10, 9),
        validUntil: DateTime.utc(2026, 6, 10, 18),
      );
      await expectLater(
        activatePass(
          policy: gate,
          pass: (await repository.passById(id))!,
          at: now,
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'visitor_pass_expired',
          ),
        ),
      );
    });

    test('an active pass is not activated twice', () async {
      final String visitor = await seedVisitor();
      final String id = await seedPass(registrationId: visitor);
      await activatePass(
        policy: gate,
        pass: (await repository.passById(id))!,
        at: now,
      );
      await expectLater(
        activatePass(policy: gate, pass: (await repository.passById(id))!),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('takes the badge back and settles the pass', () async {
      final String visitor = await seedVisitor();
      final String id = await seedPass(registrationId: visitor);
      await activatePass(
        policy: gate,
        pass: (await repository.passById(id))!,
        at: now,
      );
      await returnPass(
        policy: gate,
        pass: (await repository.passById(id))!,
        at: now,
      );
      final VisitorPass pass = (await repository.passById(id))!;
      expect(pass.status, VisitorPassStatus.returned);
      expect(pass.returnedAt, now);
      expect(pass.isTerminal, isTrue);
    });

    test('a badge is returned once it has been active', () async {
      final String visitor = await seedVisitor();
      final String id = await seedPass(registrationId: visitor);
      await expectLater(
        returnPass(policy: gate, pass: (await repository.passById(id))!),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('revokes a pass before its window closes', () async {
      final String visitor = await seedVisitor();
      final String id = await seedPass(registrationId: visitor);
      await revokePass(
        policy: gate,
        pass: (await repository.passById(id))!,
        reason: 'Issued to the wrong visitor',
        at: now,
      );
      final VisitorPass pass = (await repository.passById(id))!;
      expect(pass.status, VisitorPassStatus.revoked);
      expect(pass.revokeReason, 'Issued to the wrong visitor');
      expect(pass.revokedAt, now);
    });

    test('revoking without a reason is refused', () async {
      final String visitor = await seedVisitor();
      final String id = await seedPass(registrationId: visitor);
      await expectLater(
        revokePass(
          policy: gate,
          pass: (await repository.passById(id))!,
          reason: ' ',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'visitor_pass_revoke_reason_missing',
          ),
        ),
      );
    });

    test('a returned pass cannot be revoked', () async {
      final String visitor = await seedVisitor();
      final String id = await seedPass(registrationId: visitor);
      await activatePass(
        policy: gate,
        pass: (await repository.passById(id))!,
        at: now,
      );
      await returnPass(policy: gate, pass: (await repository.passById(id))!);
      await expectLater(
        revokePass(
          policy: gate,
          pass: (await repository.passById(id))!,
          reason: 'Too late',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('a reader cannot activate or revoke a pass', () async {
      final String visitor = await seedVisitor();
      final String id = await seedPass(registrationId: visitor);
      final VisitorPass pass = (await repository.passById(id))!;
      await expectLater(
        activatePass(policy: reader, pass: pass),
        throwsA(isA<AuthorizationError>()),
      );
      await expectLater(
        revokePass(policy: reader, pass: pass, reason: 'No'),
        throwsA(isA<AuthorizationError>()),
      );
    });
  });

  group('printing badges', () {
    test('numbers the first print one', () async {
      final String visitor = await seedVisitor();
      final String id = await seedPass(registrationId: visitor);
      await printBadge(
        policy: gate,
        pass: (await repository.passById(id))!,
        printerLabel: 'Gate desk printer',
        printedBy: 'admin-1',
        at: now,
      );
      final VisitorBadgePrint print = (await repository.listBadgePrints(
        'tenant-1',
        passId: id,
      )).single;
      expect(print.printOrdinal, 1);
      expect(print.isReprint, isFalse);
      expect(print.badgeNumber, 'B-1');
      expect(print.printerLabel, 'Gate desk printer');
      expect(print.printedBy, 'admin-1');
      expect(print.printedAt, now);
    });

    test('numbers a reprint from the log rather than overwriting', () async {
      final String visitor = await seedVisitor();
      final String id = await seedPass(registrationId: visitor);
      final VisitorPass pass = (await repository.passById(id))!;
      await printBadge(
        policy: gate,
        pass: pass,
        printerLabel: 'Gate desk printer',
        printedBy: 'admin-1',
      );
      await printBadge(
        policy: gate,
        pass: pass,
        printerLabel: 'Ward printer',
        printedBy: 'admin-1',
        note: 'First badge damaged',
      );
      final List<VisitorBadgePrint> prints = await repository.listBadgePrints(
        'tenant-1',
        passId: id,
      );
      expect(prints, hasLength(2));
      final VisitorBadgePrint reprint = prints.firstWhere(
        (VisitorBadgePrint p) => p.isReprint,
      );
      expect(reprint.printOrdinal, 2);
      expect(reprint.printerLabel, 'Ward printer');
      expect(reprint.note, 'First badge damaged');
    });

    test('a settled pass is not printed again', () async {
      final String visitor = await seedVisitor();
      final String id = await seedPass(registrationId: visitor);
      await activatePass(
        policy: gate,
        pass: (await repository.passById(id))!,
        at: now,
      );
      await returnPass(policy: gate, pass: (await repository.passById(id))!);
      await expectLater(
        printBadge(
          policy: gate,
          pass: (await repository.passById(id))!,
          printerLabel: 'Gate desk printer',
          printedBy: 'admin-1',
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'visitor_pass_transition_invalid',
          ),
        ),
      );
    });

    test('a reader cannot print a badge', () async {
      final String visitor = await seedVisitor();
      final String id = await seedPass(registrationId: visitor);
      await expectLater(
        printBadge(
          policy: reader,
          pass: (await repository.passById(id))!,
          printerLabel: 'Gate desk printer',
          printedBy: 'admin-1',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });
  });

  group('reading the desk', () {
    test('lists the registrations, the passes and the windows', () async {
      await seedWindow();
      final String visitor = await seedVisitor();
      await seedPass(registrationId: visitor);
      final VisitorDeskBoard board = await readDesk.board(
        policy: reader,
        tenantId: 'tenant-1',
        now: now,
      );
      expect(board.registrations, hasLength(1));
      expect(board.passes, hasLength(1));
      expect(board.windows, hasLength(1));
      expect(board.asOf, now);
    });

    test('the desk lists the newest visitor first', () async {
      await seedVisitor(
        id: 'r-old',
        number: 'VR-1',
        registeredAt: DateTime.utc(2026, 6, 10, 8),
      );
      await seedVisitor(
        id: 'r-new',
        number: 'VR-2',
        wardId: 'ward-2',
        registeredAt: DateTime.utc(2026, 6, 11, 8),
      );
      final VisitorDeskBoard board = await readDesk.board(
        policy: reader,
        tenantId: 'tenant-1',
        now: now,
      );
      expect(board.registrations.first.id, 'r-new');
      expect(board.registrations.last.id, 'r-old');
    });

    test('the desk lists the passes that fall out of time first', () async {
      final String visitor = await seedVisitor();
      await seedPass(
        registrationId: visitor,
        id: 'p-late',
        badgeNumber: 'B-1',
        validUntil: DateTime.utc(2026, 6, 11, 22),
      );
      await seedPass(
        registrationId: visitor,
        id: 'p-early',
        badgeNumber: 'B-2',
        validUntil: DateTime.utc(2026, 6, 11, 14),
      );
      final VisitorDeskBoard board = await readDesk.board(
        policy: reader,
        tenantId: 'tenant-1',
        now: now,
      );
      expect(board.passes.first.id, 'p-early');
      expect(board.passes.last.id, 'p-late');
    });

    test('a live registration without a pass needs attention', () async {
      final String visitor = await seedVisitor();
      final String other = await seedVisitor(number: 'VR-2', wardId: 'ward-2');
      await seedPass(registrationId: other);
      final VisitorDeskBoard board = await readDesk.board(
        policy: reader,
        tenantId: 'tenant-1',
        now: now,
      );
      expect(board.registrationsWithoutLivePass.single.id, visitor);
      expect(board.needsAttention, isTrue);
    });

    test('a settled registration is not owed a pass', () async {
      final String visitor = await seedVisitor();
      await refuseVisitor(
        policy: desk,
        registration: (await repository.registrationById(visitor))!,
        reason: 'No document to show',
      );
      final VisitorDeskBoard board = await readDesk.board(
        policy: reader,
        tenantId: 'tenant-1',
        now: now,
      );
      expect(board.liveRegistrations, isEmpty);
      expect(board.registrationsWithoutLivePass, isEmpty);
      expect(board.needsAttention, isFalse);
    });

    test('a pass awaiting activation is listed until it is used', () async {
      final String visitor = await seedVisitor();
      final String id = await seedPass(registrationId: visitor);
      VisitorDeskBoard board = await readDesk.board(
        policy: reader,
        tenantId: 'tenant-1',
        now: now,
      );
      expect(board.passesAwaitingActivation.single.id, id);
      await activatePass(
        policy: gate,
        pass: (await repository.passById(id))!,
        at: now,
      );
      board = await readDesk.board(
        policy: reader,
        tenantId: 'tenant-1',
        now: now,
      );
      expect(board.passesAwaitingActivation, isEmpty);
    });

    test('a live pass that has run out is marked', () async {
      final String visitor = await seedVisitor();
      final String id = await seedPass(
        registrationId: visitor,
        validFrom: DateTime.utc(2026, 6, 11, 9),
        validUntil: DateTime.utc(2026, 6, 11, 10),
      );
      await activatePass(
        policy: gate,
        pass: (await repository.passById(id))!,
        at: DateTime.utc(2026, 6, 11, 9, 30),
      );
      final VisitorDeskBoard board = await readDesk.board(
        policy: reader,
        tenantId: 'tenant-1',
        now: now,
      );
      expect(board.expiredLivePasses.single.id, id);
      expect(board.passesAwaitingActivation, isEmpty);
      expect(board.needsAttention, isTrue);
    });

    test('the desk counts who is inside a ward', () async {
      final String first = await seedVisitor();
      final String second = await seedVisitor(number: 'VR-2');
      await seedVisitor(number: 'VR-3', wardId: 'ward-2');
      await admitVisitor(
        policy: desk,
        registration: (await repository.registrationById(first))!,
      );
      await admitVisitor(
        policy: desk,
        registration: (await repository.registrationById(second))!,
      );
      final VisitorDeskBoard board = await readDesk.board(
        policy: reader,
        tenantId: 'tenant-1',
        now: now,
      );
      expect(board.onSiteVisitors, hasLength(2));
      expect(board.visitorsOnSiteForWard('ward-1'), 2);
      expect(board.visitorsOnSiteForWard('ward-2'), 0);
    });

    test('the desk resolves the ward window and judges the hour', () async {
      await seedWindow(
        wardId: 'ward-1',
        dayOfWeek: 4,
        startsMinute: 600,
        endsMinute: 720,
      );
      await seedVisitor();
      final VisitorDeskBoard board = await readDesk.board(
        policy: reader,
        tenantId: 'tenant-1',
        now: now,
      );
      final VisitorRegistration registration = board.registrations.single;
      final WardVisitingWindow window = board.windowForRegistration(
        registration,
        dayOfWeek: 4,
      )!;
      expect(window.wardId, 'ward-1');
      expect(
        board.isOutsideVisitingHours(
          registration,
          dayOfWeek: 4,
          minuteOfDay: 660,
        ),
        isFalse,
      );
      expect(
        board.isOutsideVisitingHours(
          registration,
          dayOfWeek: 4,
          minuteOfDay: 780,
        ),
        isTrue,
      );
    });

    test('a ward with no visiting hours admits nobody by default', () async {
      await seedVisitor(wardId: 'ward-9');
      await seedVisitor(number: 'VR-2', wardId: null);
      final VisitorDeskBoard board = await readDesk.board(
        policy: reader,
        tenantId: 'tenant-1',
        now: now,
      );
      final VisitorRegistration unset = board.registrations.firstWhere(
        (VisitorRegistration r) => r.wardId == 'ward-9',
      );
      expect(board.windowForRegistration(unset, dayOfWeek: 4), isNull);
      expect(
        board.isOutsideVisitingHours(unset, dayOfWeek: 4, minuteOfDay: 660),
        isTrue,
      );
      final VisitorRegistration noWard = board.registrations.firstWhere(
        (VisitorRegistration r) => r.wardId == null,
      );
      expect(
        board.isOutsideVisitingHours(noWard, dayOfWeek: 4, minuteOfDay: 660),
        isFalse,
      );
    });

    test('hiding the settled records leaves only the gate queue', () async {
      final String visitor = await seedVisitor();
      await seedVisitor(number: 'VR-2', wardId: 'ward-2');
      await refuseVisitor(
        policy: desk,
        registration: (await repository.registrationById(visitor))!,
        reason: 'No document to show',
      );
      final List<VisitorRegistration> live = await readDesk.registrations(
        policy: reader,
        tenantId: 'tenant-1',
        includeSettled: false,
      );
      expect(live.single.registrationNumber, 'VR-2');
    });

    test('filters reach the register', () async {
      await seedVisitor(number: 'VR-1');
      await seedVisitor(number: 'VR-2', wardId: 'ward-2');
      final List<VisitorRegistration> wardTwo = await readDesk.registrations(
        policy: reader,
        tenantId: 'tenant-1',
        wardId: 'ward-2',
      );
      expect(wardTwo.single.registrationNumber, 'VR-2');
    });

    test('the badge print log is read where it matters', () async {
      final String visitor = await seedVisitor();
      final String id = await seedPass(registrationId: visitor);
      await printBadge(
        policy: gate,
        pass: (await repository.passById(id))!,
        printerLabel: 'Gate desk printer',
        printedBy: 'admin-1',
      );
      final List<VisitorBadgePrint> prints = await readDesk.badgePrints(
        policy: reader,
        tenantId: 'tenant-1',
        passId: id,
      );
      expect(prints.single.printOrdinal, 1);
    });

    test('reading the desk needs the read permission', () async {
      await expectLater(
        readDesk.board(policy: desk, tenantId: 'tenant-1', now: now),
        throwsA(isA<AuthorizationError>()),
      );
      await expectLater(
        readDesk.registrations(policy: gate, tenantId: 'tenant-1'),
        throwsA(isA<AuthorizationError>()),
      );
      await expectLater(
        readDesk.passes(policy: gate, tenantId: 'tenant-1'),
        throwsA(isA<AuthorizationError>()),
      );
      await expectLater(
        readDesk.windows(policy: gate, tenantId: 'tenant-1'),
        throwsA(isA<AuthorizationError>()),
      );
      await expectLater(
        readDesk.badgePrints(policy: gate, tenantId: 'tenant-1', passId: 'p-1'),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('an offline registrar sees the desk they hold', () async {
      await seedVisitor();
      final VisitorDeskBoard board = await readDesk.board(
        policy: policyWith(
          canRead,
          connectivity: ConnectivityState.offline,
          offlinePermissions: canRead,
        ),
        tenantId: 'tenant-1',
        now: now,
      );
      expect(board.registrations, hasLength(1));
    });
  });
}
