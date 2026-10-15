/// Tests for the practitioner directory use-case gates (Module 08).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/authorization_snapshot.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/domain/roster/practitioner.dart';
import 'package:nodex_hms/domain/roster/practitioner_repository.dart';
import 'package:nodex_hms/domain/roster/practitioner_use_cases.dart';

import 'practitioner_repository_test.dart' show FakePractitionerStore;

AuthorizationPolicy policyWith(Set<String> permissions) {
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
  late FakePractitionerStore store;
  late DefaultPractitionerRepository repository;
  late RecordPractitionerProfileUseCase record;
  late UpdatePractitionerProfileUseCase update;
  late RetirePractitionerProfileUseCase retire;
  late ScheduleOnCallRotationUseCase schedule;
  late AttachOnCallNoteUseCase attachNote;
  late SearchPractitionersUseCase search;
  late PractitionerOnCallUseCase onCall;

  const Set<String> admin = <String>{NodexPermissions.staffDirectoryAdminister};
  const Set<String> reader = <String>{NodexPermissions.staffDirectoryRead};

  setUp(() {
    store = FakePractitionerStore();
    repository = DefaultPractitionerRepository(
      store: store,
      logger: NodexLogger(
        sinks: <NodexLogSink>[InMemoryLogSink()],
        minimumLevel: NodexLogLevel.trace,
      ),
    );
    record = RecordPractitionerProfileUseCase(repository: repository);
    update = UpdatePractitionerProfileUseCase(repository: repository);
    retire = RetirePractitionerProfileUseCase(repository: repository);
    schedule = ScheduleOnCallRotationUseCase(repository: repository);
    attachNote = AttachOnCallNoteUseCase(repository: repository);
    search = SearchPractitionersUseCase(repository: repository);
    onCall = PractitionerOnCallUseCase(repository: repository);
  });

  test('record requires administration permission', () async {
    final String id = await record(
      policy: policyWith(admin),
      tenantId: 'tenant-1',
      userId: 'u-1',
      facilityId: 'f-1',
      specialty: 'Cardiology',
    );
    expect(id, isNotEmpty);

    expect(
      () => record(
        policy: policyWith(reader),
        tenantId: 'tenant-1',
        userId: 'u-2',
        facilityId: 'f-1',
        specialty: 'Neurology',
      ),
      throwsA(isA<NodexError>()),
    );
  });

  test('record returns id and stores profile', () async {
    final String id = await record(
      policy: policyWith(admin),
      tenantId: 'tenant-1',
      userId: 'u-1',
      facilityId: 'f-1',
      specialty: 'Cardiology',
      yearsExperience: 8,
      credentials: 'MBBS, MD',
      acceptingReferrals: true,
    );
    final PractitionerProfile? profile = await repository.profileById(id);
    expect(profile, isNotNull);
    expect(profile!.specialty, 'Cardiology');
    expect(profile.credentials, 'MBBS, MD');
    expect(profile.yearsExperience, 8);
  });

  test('search requires read permission', () async {
    expect(
      () => search(policy: policyWith(<String>{}), tenantId: 'tenant-1'),
      throwsA(isA<NodexError>()),
    );
    final List<PractitionerProfile> result = await search(
      policy: policyWith(reader),
      tenantId: 'tenant-1',
    );
    expect(result, isEmpty);
  });

  test('search filters by specialty', () async {
    await record(
      policy: policyWith(admin),
      tenantId: 'tenant-1',
      userId: 'u-1',
      facilityId: 'f-1',
      specialty: 'Cardiology',
      profileId: 'p-1',
    );
    await record(
      policy: policyWith(admin),
      tenantId: 'tenant-1',
      userId: 'u-2',
      facilityId: 'f-1',
      specialty: 'Neurology',
      profileId: 'p-2',
    );
    final List<PractitionerProfile> cardios = await search(
      policy: policyWith(reader),
      tenantId: 'tenant-1',
      specialty: 'Cardiology',
    );
    expect(cardios, hasLength(1));
    expect(cardios.first.id, 'p-1');
  });

  test('update after retirement is refused', () async {
    final String id = await record(
      policy: policyWith(admin),
      tenantId: 'tenant-1',
      userId: 'u-1',
      facilityId: 'f-1',
      specialty: 'Cardiology',
      profileId: 'p-r',
    );
    final PractitionerProfile profile = (await repository.profileById(id))!;
    await retire(
      policy: policyWith(admin),
      profile: profile,
      retiredBy: 'admin-1',
      reason: 'Left service',
    );
    final PractitionerProfile retired = (await repository.profileById(id))!;
    expect(
      () => update(
        policy: policyWith(admin),
        profile: retired,
        acceptingReferrals: false,
      ),
      throwsA(isA<NodexError>()),
    );
  });

  test('retire requires reason', () async {
    final String id = await record(
      policy: policyWith(admin),
      tenantId: 'tenant-1',
      userId: 'u-1',
      facilityId: 'f-1',
      specialty: 'Cardiology',
      profileId: 'p-s',
    );
    final PractitionerProfile profile = (await repository.profileById(id))!;
    expect(
      () => retire(
        policy: policyWith(admin),
        profile: profile,
        retiredBy: 'admin-1',
        reason: '   ',
      ),
      throwsA(isA<NodexError>()),
    );
  });

  test('schedule on-call requires administration', () async {
    final String id = await repository.registerProfile(<String, Object?>{
      'id': 'p-on',
      'tenant_id': 'tenant-1',
      'user_id': 'u-on',
      'facility_id': 'f-1',
      'specialty': 'General',
      'years_experience': 0,
      'accepting_referrals': 1,
      'status': 'active',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    final now = DateTime.now().toUtc();
    final String rid = await schedule(
      policy: policyWith(admin),
      tenantId: 'tenant-1',
      practitionerId: id,
      rotationType: OnCallType.primary,
      startsAt: now,
      endsAt: now.add(const Duration(hours: 8)),
      recordedBy: 'admin-1',
    );
    expect(rid, isNotEmpty);

    expect(
      () => schedule(
        policy: policyWith(reader),
        tenantId: 'tenant-1',
        practitionerId: id,
        rotationType: OnCallType.primary,
        startsAt: now,
        endsAt: now.add(const Duration(hours: 8)),
        recordedBy: 'admin-1',
      ),
      throwsA(isA<NodexError>()),
    );
  });

  test('attach note uses admin gate', () async {
    final String pid = await repository.registerProfile(<String, Object?>{
      'id': 'p-an',
      'tenant_id': 'tenant-1',
      'user_id': 'u-an',
      'facility_id': 'f-1',
      'specialty': 'General',
      'years_experience': 0,
      'accepting_referrals': 1,
      'status': 'active',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    final now = DateTime.now().toUtc();
    final String rid = await schedule(
      policy: policyWith(admin),
      tenantId: 'tenant-1',
      practitionerId: pid,
      rotationType: OnCallType.primary,
      startsAt: now,
      endsAt: now.add(const Duration(hours: 8)),
      recordedBy: 'admin-1',
      rotationId: 'oc-note',
    );
    expect(rid, 'oc-note');
    final OnCallRotation rotation = (await repository.listOnCalls(pid)).first;
    await attachNote(
      policy: policyWith(admin),
      rotation: rotation,
      contactNote: 'Call ward 3',
    );
    final OnCallRotation updated = (await repository.listOnCalls(pid)).first;
    expect(updated.contactNote, 'Call ward 3');
  });

  test('on-call list returns rotations', () async {
    final String pid = await repository.registerProfile(<String, Object?>{
      'id': 'p-lc',
      'tenant_id': 'tenant-1',
      'user_id': 'u-lc',
      'facility_id': 'f-1',
      'specialty': 'General',
      'years_experience': 0,
      'accepting_referrals': 1,
      'status': 'active',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    final now = DateTime.now().toUtc();
    await schedule(
      policy: policyWith(admin),
      tenantId: 'tenant-1',
      practitionerId: pid,
      rotationType: OnCallType.ward,
      startsAt: now,
      endsAt: now.add(const Duration(hours: 8)),
      recordedBy: 'admin-1',
    );
    final List<OnCallRotation> rotations = await onCall.forPractitioner(
      policy: policyWith(reader),
      practitionerId: pid,
    );
    expect(rotations, hasLength(1));
  });

  test('on-call window invalid throws', () async {
    final String pid = await repository.registerProfile(<String, Object?>{
      'id': 'p-inv',
      'tenant_id': 'tenant-1',
      'user_id': 'u-inv',
      'facility_id': 'f-1',
      'specialty': 'General',
      'years_experience': 0,
      'accepting_referrals': 1,
      'status': 'active',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    final now = DateTime.now().toUtc();
    expect(
      () => schedule(
        policy: policyWith(admin),
        tenantId: 'tenant-1',
        practitionerId: pid,
        rotationType: OnCallType.ward,
        startsAt: now,
        endsAt: now,
        recordedBy: 'admin-1',
      ),
      throwsA(isA<NodexError>()),
    );
  });

  test('PractitionerStatus enum parses', () {
    expect(PractitionerStatus.fromWire('retired'), PractitionerStatus.retired);
    expect(OnCallType.fromWire('ward'), OnCallType.ward);
  });
}
