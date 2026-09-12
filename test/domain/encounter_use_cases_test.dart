/// Tests for the encounter use-case gates (Module 16).
///
/// Use cases are where authorization policy meets clinical workflow. These
/// tests pin the gates that must hold regardless of screen behavior: writes
/// require `encounter.write`, only the recorded attending clinician may sign,
/// signed records refuse edits, and amendments require a signed record.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/authorization_snapshot.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/encounters/encounter.dart';
import 'package:nodex_hms/domain/encounters/encounter_repository.dart';
import 'package:nodex_hms/domain/encounters/encounter_use_cases.dart';

import 'encounter_repository_test.dart' show FakeEncounterStore;

/// Builds a policy holding exactly [permissions].
///
/// The window is anchored to the real clock: the policy evaluates expiry
/// against now, so a fixed historical window would read as expired.
AuthorizationPolicy policyWith(Set<String> permissions) {
  final DateTime issuedAt = DateTime.now().toUtc();
  return AuthorizationPolicy(
    snapshot: AuthorizationSnapshot(
      snapshotId: 'snapshot-1',
      tenantId: 'tenant-1',
      userId: 'doctor-1',
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
    connectivity: ConnectivityState.online,
  );
}

void main() {
  late FakeEncounterStore store;
  late DefaultEncounterRepository repository;
  late StartEncounterUseCase start;
  late SaveEncounterDraftUseCase save;
  late SignEncounterUseCase sign;
  late AmendEncounterUseCase amend;

  const Set<String> writer = <String>{NodexPermissions.encounterWrite};
  const Set<String> reader = <String>{NodexPermissions.encounterRead};

  setUp(() {
    store = FakeEncounterStore();
    repository = DefaultEncounterRepository(
      store: store,
      logger: NodexLogger(
        sinks: <NodexLogSink>[InMemoryLogSink()],
        minimumLevel: NodexLogLevel.trace,
      ),
    );
    start = StartEncounterUseCase(repository: repository);
    save = SaveEncounterDraftUseCase(repository: repository);
    sign = SignEncounterUseCase(repository: repository);
    amend = AmendEncounterUseCase(repository: repository);
  });

  Future<String> seedEncounter({String status = 'in_progress'}) async {
    final String id = await repository.createEncounter(
      ClinicalEncounter.draftRow(
        tenantId: 'tenant-1',
        patientId: 'patient-1',
        attendingPhysicianId: 'doctor-1',
        encounterType: EncounterType.outpatient,
        createdBy: 'doctor-1',
      ),
    );
    if (status == 'signed_and_locked') {
      await repository.signEncounter(id);
    }
    return id;
  }

  group('authorization gates', () {
    test('starting an encounter requires encounter.write', () {
      expect(
        start.call(
          policy: policyWith(reader),
          tenantId: 'tenant-1',
          patientId: 'patient-1',
          attendingPhysicianId: 'doctor-1',
          encounterType: EncounterType.outpatient,
          createdBy: 'doctor-1',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('a reader cannot save, sign or amend', () async {
      final String id = await seedEncounter();
      final ClinicalEncounter encounter = (await repository.getEncounter(id))!;

      await expectLater(
        save.call(
          policy: policyWith(reader),
          encounter: encounter,
          assessment: 'x',
        ),
        throwsA(isA<AuthorizationError>()),
      );
      await expectLater(
        sign.call(
          policy: policyWith(reader),
          encounterId: id,
          signerUserId: 'doctor-1',
        ),
        throwsA(isA<AuthorizationError>()),
      );
      await expectLater(
        amend.call(
          policy: policyWith(reader),
          encounter: encounter,
          reason: 'x',
          fieldChanges: const <String, Object?>{'assessment': 'y'},
          amendedBy: 'doctor-1',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });
  });

  group('signature accountability', () {
    test('only the recorded attending clinician may sign', () async {
      final String id = await seedEncounter();

      await expectLater(
        sign.call(
          policy: policyWith(writer),
          encounterId: id,
          signerUserId: 'doctor-2',
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError e) => e.code,
            'code',
            'encounter_signer_mismatch',
          ),
        ),
      );

      // The rightful signer succeeds.
      await sign.call(
        policy: policyWith(writer),
        encounterId: id,
        signerUserId: 'doctor-1',
      );
      expect(
        (await repository.getEncounter(id))?.status,
        EncounterStatus.signedAndLocked,
      );
    });

    test('signing twice is refused', () async {
      final String id = await seedEncounter();
      await sign.call(
        policy: policyWith(writer),
        encounterId: id,
        signerUserId: 'doctor-1',
      );

      await expectLater(
        sign.call(
          policy: policyWith(writer),
          encounterId: id,
          signerUserId: 'doctor-1',
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError e) => e.code,
            'code',
            'encounter_already_signed',
          ),
        ),
      );
    });

    test('signing a missing encounter reports it as missing', () async {
      await expectLater(
        sign.call(
          policy: policyWith(writer),
          encounterId: 'missing',
          signerUserId: 'doctor-1',
        ),
        throwsA(
          isA<PersistenceError>().having(
            (PersistenceError e) => e.code,
            'code',
            'encounter_not_found_locally',
          ),
        ),
      );
    });
  });

  group('signed-record protection', () {
    test('saving to a signed encounter is refused before any write', () async {
      final String id = await seedEncounter(status: 'signed_and_locked');
      final ClinicalEncounter encounter = (await repository.getEncounter(id))!;

      await expectLater(
        save.call(
          policy: policyWith(writer),
          encounter: encounter,
          assessment: 'Rewritten',
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError e) => e.code,
            'code',
            'encounter_signed_frozen',
          ),
        ),
      );
    });

    test('amending an unsigned encounter is refused', () async {
      final String id = await seedEncounter();
      final ClinicalEncounter encounter = (await repository.getEncounter(id))!;

      await expectLater(
        amend.call(
          policy: policyWith(writer),
          encounter: encounter,
          reason: 'x',
          fieldChanges: const <String, Object?>{'assessment': 'y'},
          amendedBy: 'doctor-1',
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError e) => e.code,
            'code',
            'encounter_not_signed',
          ),
        ),
      );
    });

    test('amending a signed encounter succeeds end to end', () async {
      final String id = await seedEncounter(status: 'signed_and_locked');
      final ClinicalEncounter encounter = (await repository.getEncounter(id))!;

      final String amendmentId = await amend.call(
        policy: policyWith(writer),
        encounter: encounter,
        reason: 'Reclassified after review',
        fieldChanges: const <String, Object?>{'assessment': 'Revised'},
        amendedBy: 'doctor-1',
      );

      expect(amendmentId, isNotEmpty);
      expect(
        (await repository.getEncounter(id))?.status,
        EncounterStatus.amended,
      );
      expect(
        (await repository.listAmendments(id)).single.reason,
        'Reclassified after review',
      );
    });
  });

  group('start encounter', () {
    test('creates an unsigned draft for the patient', () async {
      final String id = await start.call(
        policy: policyWith(writer),
        tenantId: 'tenant-1',
        patientId: 'patient-9',
        attendingPhysicianId: 'doctor-1',
        encounterType: EncounterType.emergency,
        createdBy: 'doctor-1',
      );

      final ClinicalEncounter? created = await repository.getEncounter(id);
      expect(created?.encounterType, EncounterType.emergency);
      expect(created?.isEditable, isTrue);
      expect(
        await store.getById(LocalTables.clinicalEncounters, id),
        isNotNull,
      );
    });
  });
}
