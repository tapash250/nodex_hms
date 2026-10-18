/// Tests for the statutory registry use cases, the derived overdue windows and
/// the birth, death and medico-legal state machines (Module 34).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/authorization_snapshot.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/domain/statutory/statutory.dart';
import 'package:nodex_hms/domain/statutory/statutory_repository.dart';
import 'package:nodex_hms/domain/statutory/statutory_use_cases.dart';

import 'statutory_repository_test.dart' show FakeStatutoryStore;

AuthorizationPolicy policyWith(
  Set<String> permissions, {
  ConnectivityState connectivity = ConnectivityState.online,
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
          : const <String>{},
      facilityIds: const <String>{'facility-1'},
      departmentIds: const <String>{},
      wardIds: const <String>{},
    ),
    connectivity: connectivity,
  );
}

void main() {
  late FakeStatutoryStore store;
  late DefaultStatutoryRepository repository;
  late RaiseBirthUseCase raiseBirth;
  late RegisterBirthUseCase registerBirth;
  late CertifyBirthUseCase certifyBirth;
  late RaiseDeathUseCase raiseDeath;
  late RecordDeathCodingUseCase recordCoding;
  late RegisterDeathUseCase registerDeath;
  late CertifyDeathUseCase certifyDeath;
  late RaiseMlcIntimationUseCase raiseCase;
  late IntimatePoliceUseCase intimatePolice;
  late AcknowledgeMlcUseCase acknowledgeCase;
  late CloseMlcUseCase closeCase;
  late VoidStatutoryRecordUseCase voidRecord;
  late AppendStatutoryAmendmentUseCase amend;
  late ReadStatutoryRegistryUseCase readRegistry;

  const Set<String> canRegister = <String>{NodexPermissions.statutoryRegister};
  const Set<String> canCertify = <String>{NodexPermissions.statutoryCertify};
  const Set<String> canAmend = <String>{NodexPermissions.statutoryAmend};
  const Set<String> canRead = <String>{NodexPermissions.statutoryRead};

  final AuthorizationPolicy registrar = policyWith(canRegister);
  final DateTime now = DateTime.utc(2026, 6, 10);

  setUp(() {
    store = FakeStatutoryStore();
    repository = DefaultStatutoryRepository(
      store: store,
      logger: NodexLogger(
        sinks: <NodexLogSink>[InMemoryLogSink()],
        minimumLevel: NodexLogLevel.trace,
      ),
    );
    raiseBirth = RaiseBirthUseCase(repository: repository);
    registerBirth = RegisterBirthUseCase(repository: repository);
    certifyBirth = CertifyBirthUseCase(repository: repository);
    raiseDeath = RaiseDeathUseCase(repository: repository);
    recordCoding = RecordDeathCodingUseCase(repository: repository);
    registerDeath = RegisterDeathUseCase(repository: repository);
    certifyDeath = CertifyDeathUseCase(repository: repository);
    raiseCase = RaiseMlcIntimationUseCase(repository: repository);
    intimatePolice = IntimatePoliceUseCase(repository: repository);
    acknowledgeCase = AcknowledgeMlcUseCase(repository: repository);
    closeCase = CloseMlcUseCase(repository: repository);
    voidRecord = VoidStatutoryRecordUseCase(repository: repository);
    amend = AppendStatutoryAmendmentUseCase(repository: repository);
    readRegistry = ReadStatutoryRegistryUseCase(repository: repository);
  });

  Future<BirthRecord> aBirth({DateTime? birthAt}) async {
    final String id = await raiseBirth(
      policy: registrar,
      tenantId: 'tenant-1',
      facilityId: 'facility-1',
      childName: 'Baby of Rabeya',
      sex: StatutorySex.female,
      birthAt: birthAt ?? DateTime.utc(2026, 6, 1),
      placeOfBirth: 'Labour room 2',
      motherName: 'Rabeya Khatun',
      createdBy: 'user-1',
      weightGrams: 3100,
    );
    return (await repository.birthById(id))!;
  }

  Future<DeathRecord> aDeath({String? icd10, MannerOfDeath? manner}) async {
    final String id = await raiseDeath(
      policy: registrar,
      tenantId: 'tenant-1',
      facilityId: 'facility-1',
      deceasedName: 'Abdul Hoque',
      sex: StatutorySex.male,
      deathAt: DateTime.utc(2026, 6, 3),
      placeOfDeath: 'ICU bed 4',
      createdBy: 'user-1',
      ageYears: 71,
      icd10Code: icd10,
      mannerOfDeath: manner,
      causeOfDeathText: icd10 == null ? null : 'Acute myocardial infarction',
    );
    return (await repository.deathById(id))!;
  }

  Future<MlcIntimation> aCase() async {
    final String id = await raiseCase(
      policy: registrar,
      tenantId: 'tenant-1',
      facilityId: 'facility-1',
      caseNumber: 'MLC-2026-0001',
      subjectName: 'Jashim Uddin',
      caseType: MlcCaseType.roadTrafficAccident,
      createdBy: 'user-1',
      incidentAt: DateTime.utc(2026, 6, 5, 20),
      reportedAt: DateTime.utc(2026, 6, 5, 22),
    );
    return (await repository.mlcIntimationById(id))!;
  }

  group('state machines', () {
    test('a birth advances one stage at a time', () {
      expect(
        birthCanTransition(BirthStatus.drafted, BirthStatus.registered),
        isTrue,
      );
      expect(
        birthCanTransition(BirthStatus.registered, BirthStatus.certified),
        isTrue,
      );
      expect(
        birthCanTransition(BirthStatus.drafted, BirthStatus.voided),
        isTrue,
      );
      expect(
        birthCanTransition(BirthStatus.drafted, BirthStatus.certified),
        isFalse,
      );
      expect(
        birthCanTransition(BirthStatus.certified, BirthStatus.voided),
        isFalse,
      );
      expect(
        birthCanTransition(BirthStatus.voided, BirthStatus.registered),
        isFalse,
      );
    });

    test('a death advances one stage at a time', () {
      expect(
        deathCanTransition(DeathStatus.drafted, DeathStatus.registered),
        isTrue,
      );
      expect(
        deathCanTransition(DeathStatus.registered, DeathStatus.certified),
        isTrue,
      );
      expect(
        deathCanTransition(DeathStatus.registered, DeathStatus.voided),
        isTrue,
      );
      expect(
        deathCanTransition(DeathStatus.certified, DeathStatus.registered),
        isFalse,
      );
    });

    test('a medico-legal case advances one stage at a time', () {
      expect(mlcCanTransition(MlcStatus.reported, MlcStatus.intimated), isTrue);
      expect(
        mlcCanTransition(MlcStatus.intimated, MlcStatus.acknowledged),
        isTrue,
      );
      expect(
        mlcCanTransition(MlcStatus.acknowledged, MlcStatus.closed),
        isTrue,
      );
      expect(mlcCanTransition(MlcStatus.reported, MlcStatus.closed), isFalse);
      expect(
        mlcCanTransition(MlcStatus.acknowledged, MlcStatus.voided),
        isFalse,
      );
      expect(mlcCanTransition(MlcStatus.closed, MlcStatus.voided), isFalse);
    });

    test('recognises an ICD-10 code', () {
      expect(isIcd10Code('I21.9'), isTrue);
      expect(isIcd10Code('I21'), isTrue);
      expect(isIcd10Code('S72.001A'), isTrue);
      expect(isIcd10Code('i21.9'), isFalse);
      expect(isIcd10Code('21.9'), isFalse);
      expect(isIcd10Code('I21999'), isFalse);
      expect(isIcd10Code(''), isFalse);
    });
  });

  group('derived facts', () {
    test('a registration is overdue only while unregistered', () {
      expect(
        isStatutoryRegistrationOverdue(
          occurredAt: DateTime.utc(2026, 5, 1),
          registeredAt: DateTime.utc(2026, 5, 2),
          now: now,
          limit: birthRegistrationWindow,
        ),
        isFalse,
      );
      expect(
        isStatutoryRegistrationOverdue(
          occurredAt: DateTime.utc(2026, 6, 5),
          registeredAt: null,
          now: now,
          limit: birthRegistrationWindow,
        ),
        isFalse,
      );
      expect(
        isStatutoryRegistrationOverdue(
          occurredAt: DateTime.utc(2026, 5, 1),
          registeredAt: null,
          now: now,
          limit: birthRegistrationWindow,
        ),
        isTrue,
      );
    });

    test('a case is overdue only while the police are unanswered', () async {
      final MlcIntimation reported = await aCase();
      expect(
        isMlcIntimationOverdue(
          record: reported,
          now: DateTime.utc(2026, 6, 5, 23),
        ),
        isFalse,
      );
      expect(
        isMlcIntimationOverdue(record: reported, now: DateTime.utc(2026, 6, 7)),
        isTrue,
      );
    });

    test('an intimated case is never overdue for intimation', () async {
      final MlcIntimation reported = await aCase();
      await intimatePolice(
        policy: registrar,
        record: reported,
        policeStation: 'Kotwali',
      );
      final MlcIntimation intimated = (await repository.mlcIntimationById(
        reported.id,
      ))!;
      expect(
        isMlcIntimationOverdue(
          record: intimated,
          now: DateTime.utc(2026, 7, 1),
        ),
        isFalse,
      );
    });

    test('replays the amendments to the value a reader should act on', () {
      StatutoryAmendment amendment({
        required String id,
        required String field,
        required String value,
        required DateTime at,
      }) => StatutoryAmendment(
        id: id,
        tenantId: 'tenant-1',
        kind: StatutoryRegistryKind.death,
        recordId: 'd-1',
        subjectField: field,
        newValue: value,
        reason: 'corrected',
        amendedBy: 'user-1',
        amendedAt: at,
      );
      final Map<String, String> values = effectiveStatutoryValues(
        <StatutoryAmendment>[
          amendment(
            id: 'a-2',
            field: 'icd10_code',
            value: 'I21.9',
            at: DateTime.utc(2026, 6, 8),
          ),
          amendment(
            id: 'a-1',
            field: 'icd10_code',
            value: 'I21.4',
            at: DateTime.utc(2026, 6, 6),
          ),
          amendment(
            id: 'a-3',
            field: 'manner_of_death',
            value: 'accident',
            at: DateTime.utc(2026, 6, 7),
          ),
        ],
      );
      expect(values['icd10_code'], 'I21.9');
      expect(values['manner_of_death'], 'accident');
    });

    test('breaks an amendment tie on the row id', () {
      StatutoryAmendment amendment(String id) => StatutoryAmendment(
        id: id,
        tenantId: 'tenant-1',
        kind: StatutoryRegistryKind.birth,
        recordId: 'b-1',
        subjectField: 'child_name',
        newValue: id,
        reason: 'corrected',
        amendedBy: 'user-1',
        amendedAt: DateTime.utc(2026, 6, 8),
      );
      final Map<String, String> values = effectiveStatutoryValues(
        <StatutoryAmendment>[amendment('a-2'), amendment('a-1')],
      );
      expect(values['child_name'], 'a-2');
    });
  });

  group('birth registration', () {
    test('raises a draft with no register number', () async {
      final BirthRecord record = await aBirth();
      expect(record.status, BirthStatus.drafted);
      expect(record.registrationNumber, isNull);
      expect(record.certificateNumber, isNull);
      expect(record.weightGrams, 3100);
    });

    test('denies raising without the register permission', () async {
      await expectLater(
        raiseBirth(
          policy: policyWith(canRead),
          tenantId: 'tenant-1',
          facilityId: 'facility-1',
          childName: 'Baby',
          sex: StatutorySex.female,
          birthAt: DateTime.utc(2026, 6, 1),
          placeOfBirth: 'Labour room 2',
          motherName: 'Rabeya',
          createdBy: 'user-1',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('refuses a birth without a child name', () async {
      await expectLater(
        raiseBirth(
          policy: registrar,
          tenantId: 'tenant-1',
          facilityId: 'facility-1',
          childName: '   ',
          sex: StatutorySex.female,
          birthAt: DateTime.utc(2026, 6, 1),
          placeOfBirth: 'Labour room 2',
          motherName: 'Rabeya',
          createdBy: 'user-1',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'birth_record_invalid',
          ),
        ),
      );
    });

    test('enters a draft in the register', () async {
      final BirthRecord record = await aBirth();
      await registerBirth(
        policy: registrar,
        record: record,
        registrationNumber: 'B-2026-0001',
        at: DateTime.utc(2026, 6, 2),
      );
      final BirthRecord registered = (await repository.birthById(record.id))!;
      expect(registered.status, BirthStatus.registered);
      expect(registered.registrationNumber, 'B-2026-0001');
    });

    test('refuses a register number already used', () async {
      final BirthRecord first = await aBirth();
      await registerBirth(
        policy: registrar,
        record: first,
        registrationNumber: 'B-2026-0001',
      );
      final BirthRecord second = await aBirth();
      await expectLater(
        registerBirth(
          policy: registrar,
          record: second,
          registrationNumber: 'B-2026-0001',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'birth_registration_number_duplicate',
          ),
        ),
      );
    });

    test('refuses to register an entry twice', () async {
      final BirthRecord record = await aBirth();
      await registerBirth(
        policy: registrar,
        record: record,
        registrationNumber: 'B-1',
      );
      final BirthRecord registered = (await repository.birthById(record.id))!;
      await expectLater(
        registerBirth(
          policy: registrar,
          record: registered,
          registrationNumber: 'B-2',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('refuses a register number that is blank', () async {
      final BirthRecord record = await aBirth();
      await expectLater(
        registerBirth(
          policy: registrar,
          record: record,
          registrationNumber: '  ',
        ),
        throwsA(isA<ValidationError>()),
      );
    });

    test('certifies a registered birth', () async {
      final BirthRecord record = await aBirth();
      await registerBirth(
        policy: registrar,
        record: record,
        registrationNumber: 'B-1',
      );
      final BirthRecord registered = (await repository.birthById(record.id))!;
      await certifyBirth(
        policy: policyWith(canCertify),
        record: registered,
        certificateNumber: 'CERT-1',
        certifiedBy: 'user-2',
      );
      final BirthRecord certified = (await repository.birthById(record.id))!;
      expect(certified.status, BirthStatus.certified);
      expect(certified.certificateNumber, 'CERT-1');
      expect(certified.certifiedBy, 'user-2');
      expect(certified.isCertified, isTrue);
      expect(certified.isTerminal, isTrue);
    });

    test('refuses to certify a draft', () async {
      final BirthRecord record = await aBirth();
      await expectLater(
        certifyBirth(
          policy: policyWith(canCertify),
          record: record,
          certificateNumber: 'CERT-1',
          certifiedBy: 'user-2',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('refuses to certify without the certify permission', () async {
      final BirthRecord record = await aBirth();
      await registerBirth(
        policy: registrar,
        record: record,
        registrationNumber: 'B-1',
      );
      final BirthRecord registered = (await repository.birthById(record.id))!;
      await expectLater(
        certifyBirth(
          policy: registrar,
          record: registered,
          certificateNumber: 'CERT-1',
          certifiedBy: 'user-2',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test(
      'refuses to certify offline, because a certificate is final',
      () async {
        final BirthRecord record = await aBirth();
        await registerBirth(
          policy: registrar,
          record: record,
          registrationNumber: 'B-1',
        );
        final BirthRecord registered = (await repository.birthById(record.id))!;
        await expectLater(
          certifyBirth(
            policy: policyWith(
              canCertify,
              connectivity: ConnectivityState.offline,
            ),
            record: registered,
            certificateNumber: 'CERT-1',
            certifiedBy: 'user-2',
          ),
          throwsA(isA<AuthorizationError>()),
        );
      },
    );
  });

  group('death registration', () {
    test('raises a draft death without coding', () async {
      final DeathRecord record = await aDeath();
      expect(record.status, DeathStatus.drafted);
      expect(record.isCoded, isFalse);
    });

    test('refuses a malformed ICD-10 code at raise', () async {
      await expectLater(
        raiseDeath(
          policy: registrar,
          tenantId: 'tenant-1',
          facilityId: 'facility-1',
          deceasedName: 'Abdul Hoque',
          sex: StatutorySex.male,
          deathAt: DateTime.utc(2026, 6, 3),
          placeOfDeath: 'ICU bed 4',
          createdBy: 'user-1',
          icd10Code: 'i21.9',
          mannerOfDeath: MannerOfDeath.natural,
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'death_record_invalid',
          ),
        ),
      );
    });

    test('records the cause-of-death coding on a draft', () async {
      final DeathRecord record = await aDeath();
      await recordCoding(
        policy: registrar,
        record: record,
        causeOfDeathText: 'Acute myocardial infarction',
        icd10Code: 'I21.9',
        mannerOfDeath: MannerOfDeath.natural,
        certifyingClinician: 'user-2',
      );
      final DeathRecord coded = (await repository.deathById(record.id))!;
      expect(coded.isCoded, isTrue);
      expect(coded.icd10Code, 'I21.9');
      expect(coded.mannerOfDeath, MannerOfDeath.natural);
    });

    test('refuses to recode a registered death', () async {
      final DeathRecord record = await aDeath(
        icd10: 'I21.9',
        manner: MannerOfDeath.natural,
      );
      await registerDeath(
        policy: registrar,
        record: record,
        registrationNumber: 'D-1',
      );
      final DeathRecord registered = (await repository.deathById(record.id))!;
      await expectLater(
        recordCoding(
          policy: registrar,
          record: registered,
          causeOfDeathText: 'Something else',
          icd10Code: 'I25.1',
          mannerOfDeath: MannerOfDeath.natural,
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'death_record_coding_immutable',
          ),
        ),
      );
    });

    test('refuses a coding correction with a malformed code', () async {
      final DeathRecord record = await aDeath();
      await expectLater(
        recordCoding(
          policy: registrar,
          record: record,
          causeOfDeathText: 'Acute myocardial infarction',
          icd10Code: 'nonsense',
          mannerOfDeath: MannerOfDeath.natural,
        ),
        throwsA(isA<ValidationError>()),
      );
    });

    test('refuses to register an uncoded death', () async {
      final DeathRecord record = await aDeath();
      await expectLater(
        registerDeath(
          policy: registrar,
          record: record,
          registrationNumber: 'D-1',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'death_coding_missing',
          ),
        ),
      );
    });

    test('registers a coded death', () async {
      final DeathRecord record = await aDeath(
        icd10: 'I21.9',
        manner: MannerOfDeath.natural,
      );
      await registerDeath(
        policy: registrar,
        record: record,
        registrationNumber: 'D-2026-0001',
      );
      final DeathRecord registered = (await repository.deathById(record.id))!;
      expect(registered.status, DeathStatus.registered);
      expect(registered.registrationNumber, 'D-2026-0001');
    });

    test('refuses a duplicate register number', () async {
      final DeathRecord first = await aDeath(
        icd10: 'I21.9',
        manner: MannerOfDeath.natural,
      );
      await registerDeath(
        policy: registrar,
        record: first,
        registrationNumber: 'D-1',
      );
      final DeathRecord second = await aDeath(
        icd10: 'I21.9',
        manner: MannerOfDeath.natural,
      );
      await expectLater(
        registerDeath(
          policy: registrar,
          record: second,
          registrationNumber: 'D-1',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'death_registration_number_duplicate',
          ),
        ),
      );
    });

    test('certifies a registered death and refuses a draft', () async {
      final DeathRecord draft = await aDeath(
        icd10: 'I21.9',
        manner: MannerOfDeath.natural,
      );
      await expectLater(
        certifyDeath(
          policy: policyWith(canCertify),
          record: draft,
          certificateNumber: 'DC-1',
          certifiedBy: 'user-2',
        ),
        throwsA(isA<AuthorizationError>()),
      );
      await registerDeath(
        policy: registrar,
        record: draft,
        registrationNumber: 'D-1',
      );
      final DeathRecord registered = (await repository.deathById(draft.id))!;
      await certifyDeath(
        policy: policyWith(canCertify),
        record: registered,
        certificateNumber: 'DC-1',
        certifiedBy: 'user-2',
      );
      final DeathRecord certified = (await repository.deathById(draft.id))!;
      expect(certified.status, DeathStatus.certified);
      expect(certified.certifiedAt, isNotNull);
    });
  });

  group('medico-legal cases', () {
    test('logs a case and refuses a duplicate case number', () async {
      final MlcIntimation record = await aCase();
      expect(record.status, MlcStatus.reported);
      expect(record.status.awaitsPolice, isTrue);
      await expectLater(
        raiseCase(
          policy: registrar,
          tenantId: 'tenant-1',
          facilityId: 'facility-1',
          caseNumber: 'MLC-2026-0001',
          subjectName: 'Someone else',
          caseType: MlcCaseType.assault,
          createdBy: 'user-1',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'mlc_case_number_duplicate',
          ),
        ),
      );
    });

    test('tells the police, requiring a station', () async {
      final MlcIntimation record = await aCase();
      await expectLater(
        intimatePolice(policy: registrar, record: record, policeStation: '  '),
        throwsA(isA<ValidationError>()),
      );
      await intimatePolice(
        policy: registrar,
        record: record,
        policeStation: 'Kotwali',
        policeOfficerName: 'SI Rana',
      );
      final MlcIntimation intimated = (await repository.mlcIntimationById(
        record.id,
      ))!;
      expect(intimated.status, MlcStatus.intimated);
      expect(intimated.policeStation, 'Kotwali');
      expect(intimated.intimatedAt, isNotNull);
    });

    test('refuses to intimate a case twice', () async {
      final MlcIntimation record = await aCase();
      await intimatePolice(
        policy: registrar,
        record: record,
        policeStation: 'Kotwali',
      );
      final MlcIntimation intimated = (await repository.mlcIntimationById(
        record.id,
      ))!;
      await expectLater(
        intimatePolice(
          policy: registrar,
          record: intimated,
          policeStation: 'Kotwali',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('records the police acknowledgement with a reference', () async {
      final MlcIntimation record = await aCase();
      await intimatePolice(
        policy: registrar,
        record: record,
        policeStation: 'Kotwali',
      );
      final MlcIntimation intimated = (await repository.mlcIntimationById(
        record.id,
      ))!;
      await expectLater(
        acknowledgeCase(
          policy: registrar,
          record: intimated,
          policeReference: ' ',
        ),
        throwsA(isA<ValidationError>()),
      );
      await acknowledgeCase(
        policy: registrar,
        record: intimated,
        policeReference: 'GD-441',
      );
      final MlcIntimation acknowledged = (await repository.mlcIntimationById(
        record.id,
      ))!;
      expect(acknowledged.status, MlcStatus.acknowledged);
      expect(acknowledged.policeReference, 'GD-441');
      expect(acknowledged.status.awaitsPolice, isFalse);
    });

    test(
      'refuses to acknowledge a case the police have not been told about',
      () async {
        final MlcIntimation record = await aCase();
        await expectLater(
          acknowledgeCase(
            policy: registrar,
            record: record,
            policeReference: 'GD-441',
          ),
          throwsA(isA<AuthorizationError>()),
        );
      },
    );

    test('closes an acknowledged case with a reason', () async {
      final MlcIntimation record = await aCase();
      await intimatePolice(
        policy: registrar,
        record: record,
        policeStation: 'Kotwali',
      );
      final MlcIntimation intimated = (await repository.mlcIntimationById(
        record.id,
      ))!;
      // A case the police have not acknowledged cannot be closed at all.
      await expectLater(
        closeCase(policy: registrar, record: intimated, reason: 'Done'),
        throwsA(isA<AuthorizationError>()),
      );
      await acknowledgeCase(
        policy: registrar,
        record: intimated,
        policeReference: 'GD-441',
      );
      final MlcIntimation acknowledged = (await repository.mlcIntimationById(
        record.id,
      ))!;
      // Closing it requires a reason the file can be read against.
      await expectLater(
        closeCase(policy: registrar, record: acknowledged, reason: '   '),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'mlc_closure_reason_missing',
          ),
        ),
      );
      await closeCase(
        policy: registrar,
        record: acknowledged,
        reason: 'Case disposed of by the magistrate',
      );
      final MlcIntimation closed = (await repository.mlcIntimationById(
        record.id,
      ))!;
      expect(closed.status, MlcStatus.closed);
      expect(closed.isTerminal, isTrue);
    });

    test('denies logging a case without the register permission', () async {
      await expectLater(
        raiseCase(
          policy: policyWith(canRead),
          tenantId: 'tenant-1',
          facilityId: 'facility-1',
          caseNumber: 'MLC-1',
          subjectName: 'Jashim',
          caseType: MlcCaseType.assault,
          createdBy: 'user-1',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });
  });

  group('withdrawal', () {
    test('withdraws a draft birth with a reason', () async {
      final BirthRecord record = await aBirth();
      await expectLater(
        voidRecord(
          policy: policyWith(canAmend),
          record: record.ref,
          reason: ' ',
        ),
        throwsA(isA<ValidationError>()),
      );
      await voidRecord(
        policy: policyWith(canAmend),
        record: record.ref,
        reason: 'Duplicate entry',
      );
      final BirthRecord voided = (await repository.birthById(record.id))!;
      expect(voided.status, BirthStatus.voided);
      expect(voided.voidReason, 'Duplicate entry');
      expect(voided.isTerminal, isTrue);
    });

    test('refuses to withdraw a certified birth', () async {
      final BirthRecord record = await aBirth();
      await registerBirth(
        policy: registrar,
        record: record,
        registrationNumber: 'B-1',
      );
      final BirthRecord registered = (await repository.birthById(record.id))!;
      await certifyBirth(
        policy: policyWith(canCertify),
        record: registered,
        certificateNumber: 'CERT-1',
        certifiedBy: 'user-2',
      );
      final BirthRecord certified = (await repository.birthById(record.id))!;
      await expectLater(
        voidRecord(
          policy: policyWith(canAmend),
          record: certified.ref,
          reason: 'Mistake',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('withdraws a reported case and refuses a closed one', () async {
      final MlcIntimation record = await aCase();
      await voidRecord(
        policy: policyWith(canAmend),
        record: record.ref,
        reason: 'Not a medico-legal case',
      );
      final MlcIntimation voided = (await repository.mlcIntimationById(
        record.id,
      ))!;
      expect(voided.status, MlcStatus.voided);
      await expectLater(
        voidRecord(
          policy: policyWith(canAmend),
          record: voided.ref,
          reason: 'Again',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('denies withdrawal without the amendment permission', () async {
      final BirthRecord record = await aBirth();
      await expectLater(
        voidRecord(policy: registrar, record: record.ref, reason: 'Mistake'),
        throwsA(isA<AuthorizationError>()),
      );
    });
  });

  group('amendments', () {
    test('appends a correction against a register row', () async {
      final BirthRecord record = await aBirth();
      await registerBirth(
        policy: registrar,
        record: record,
        registrationNumber: 'B-1',
      );
      final BirthRecord registered = (await repository.birthById(record.id))!;
      final String id = await amend(
        policy: policyWith(canAmend),
        tenantId: 'tenant-1',
        record: registered.ref,
        subjectField: 'child_name',
        previousValue: 'Baby of Rabeya',
        newValue: 'Nusrat Jahan',
        reason: 'Name given at discharge',
        amendedBy: 'user-1',
      );
      expect(id, isNotEmpty);
      final List<StatutoryAmendment> amendments = await readRegistry.amendments(
        policy: policyWith(canRead),
        tenantId: 'tenant-1',
        kind: StatutoryRegistryKind.birth,
        recordId: record.id,
      );
      expect(amendments, hasLength(1));
      expect(
        effectiveStatutoryValues(amendments)['child_name'],
        'Nusrat Jahan',
      );
    });

    test('refuses a correction that changes nothing', () async {
      final BirthRecord record = await aBirth();
      await expectLater(
        amend(
          policy: policyWith(canAmend),
          tenantId: 'tenant-1',
          record: record.ref,
          subjectField: 'child_name',
          previousValue: 'Baby of Rabeya',
          newValue: 'Baby of Rabeya',
          reason: 'Typo',
          amendedBy: 'user-1',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'statutory_amendment_invalid',
          ),
        ),
      );
    });

    test('refuses a correction without a reason', () async {
      final BirthRecord record = await aBirth();
      await expectLater(
        amend(
          policy: policyWith(canAmend),
          tenantId: 'tenant-1',
          record: record.ref,
          subjectField: 'child_name',
          newValue: 'Nusrat Jahan',
          reason: '',
          amendedBy: 'user-1',
        ),
        throwsA(isA<ValidationError>()),
      );
    });

    test(
      'refuses a correction without a tenant and without permission',
      () async {
        final BirthRecord record = await aBirth();
        await expectLater(
          amend(
            policy: policyWith(canAmend),
            record: record.ref,
            subjectField: 'child_name',
            newValue: 'Nusrat Jahan',
            reason: 'Name given',
            amendedBy: 'user-1',
          ),
          throwsA(isA<ValidationError>()),
        );
        await expectLater(
          amend(
            policy: registrar,
            tenantId: 'tenant-1',
            record: record.ref,
            subjectField: 'child_name',
            newValue: 'Nusrat Jahan',
            reason: 'Name given',
            amendedBy: 'user-1',
          ),
          throwsA(isA<AuthorizationError>()),
        );
      },
    );
  });

  group('reading the register', () {
    test('hides closed records when asked', () async {
      final BirthRecord draft = await aBirth();
      final BirthRecord voided = await aBirth();
      await voidRecord(
        policy: policyWith(canAmend),
        record: voided.ref,
        reason: 'Duplicate',
      );
      final List<BirthRecord> live = await readRegistry.births(
        policy: policyWith(canRead),
        tenantId: 'tenant-1',
        includeClosed: false,
      );
      expect(live.map((BirthRecord b) => b.id).toList(), <String>[draft.id]);
      final List<BirthRecord> all = await readRegistry.births(
        policy: policyWith(canRead),
        tenantId: 'tenant-1',
      );
      expect(all, hasLength(2));
    });

    test('denies reading without the read permission', () async {
      await expectLater(
        readRegistry.births(
          policy: policyWith(canRegister),
          tenantId: 'tenant-1',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test(
      'orders the board live entries first and derives the overdue flags',
      () async {
        final DeathRecord settled = await aDeath(
          icd10: 'I21.9',
          manner: MannerOfDeath.natural,
        );
        await registerDeath(
          policy: registrar,
          record: settled,
          registrationNumber: 'D-1',
        );
        final BirthRecord overdue = await aBirth(
          birthAt: DateTime.utc(2026, 1, 1),
        );
        final StatutoryBoard board = await readRegistry.board(
          policy: policyWith(canRead),
          tenantId: 'tenant-1',
          now: now,
        );
        expect(board.births.first.id, overdue.id);
        expect(board.birthOverdue(overdue), isTrue);
        expect(board.deathOverdue(settled), isFalse);
        expect(board.hasOverdue, isTrue);
      },
    );

    test(
      'reports a case as overdue on the board until the police are told',
      () async {
        final MlcIntimation record = await aCase();
        final StatutoryBoard board = await readRegistry.board(
          policy: policyWith(canRead),
          tenantId: 'tenant-1',
          now: DateTime.utc(2026, 6, 12),
        );
        expect(board.intimations.single.id, record.id);
        expect(board.caseOverdue(record), isTrue);
        await intimatePolice(
          policy: registrar,
          record: record,
          policeStation: 'Kotwali',
        );
        final MlcIntimation intimated = (await repository.mlcIntimationById(
          record.id,
        ))!;
        expect(board.caseOverdue(intimated), isFalse);
        // The board snapshot still holds the row it was built from, so a
        // refreshed board is what clears the marker on screen; the derived flag
        // itself answers from the row it is handed.
        expect(board.caseOverdue(board.intimations.single), isTrue);
      },
    );

    test('lists cases and honours the live-only filter', () async {
      final MlcIntimation record = await aCase();
      await intimatePolice(
        policy: registrar,
        record: record,
        policeStation: 'Kotwali',
      );
      final MlcIntimation intimated = (await repository.mlcIntimationById(
        record.id,
      ))!;
      final List<MlcIntimation> live = await readRegistry.intimations(
        policy: policyWith(canRead),
        tenantId: 'tenant-1',
        includeClosed: false,
      );
      expect(live.single.id, intimated.id);
      expect(live.single.status, MlcStatus.intimated);
    });
  });
}
