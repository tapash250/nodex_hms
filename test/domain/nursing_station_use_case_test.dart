/// Tests for the nurse ward station use-case gates and alert derivation
/// (Module 06).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/authorization_snapshot.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/domain/nursing_station/nursing_station.dart';
import 'package:nodex_hms/domain/nursing_station/nursing_station_repository.dart';
import 'package:nodex_hms/domain/nursing_station/nursing_station_use_cases.dart';

import 'nursing_station_repository_test.dart' show FakeNursingStore;

AuthorizationPolicy policyWith(Set<String> permissions) {
  final DateTime issuedAt = DateTime.now().toUtc();
  return AuthorizationPolicy(
    snapshot: AuthorizationSnapshot(
      snapshotId: 'snapshot-1',
      tenantId: 'tenant-1',
      userId: 'nurse-1',
      deviceId: 'device-1',
      revision: 1,
      issuedAt: issuedAt,
      expiresAt: issuedAt.add(const Duration(days: 30)),
      payloadDigest: 'digest',
      roles: const <String>{NodexRoles.nursingStaff},
      permissions: permissions,
      offlinePermissions: permissions,
      facilityIds: const <String>{'facility-1'},
      departmentIds: const <String>{},
      wardIds: const <String>{'ward-1'},
    ),
    connectivity: ConnectivityState.online,
  );
}

WardVital buildVital({
  int? pulseBpm,
  int? spo2,
  int? systolicBp,
  int? respiratoryRate,
  double? temperatureCelsius,
  int? painScore,
  ConsciousnessLevel consciousness = ConsciousnessLevel.alert,
  bool onOxygen = false,
}) => WardVital.fromRow(
  WardVital.registerRow(
    tenantId: 'tenant-1',
    patientId: 'patient-1',
    wardId: 'ward-1',
    recordedBy: 'nurse-1',
    vitalId: 'vital-1',
    pulseBpm: pulseBpm,
    spo2: spo2,
    systolicBp: systolicBp,
    respiratoryRate: respiratoryRate,
    temperatureCelsius: temperatureCelsius,
    painScore: painScore,
    consciousness: consciousness,
    onOxygen: onOxygen,
  ),
);

void main() {
  late FakeNursingStore store;
  late DefaultNursingStationRepository repository;

  const Set<String> recordVitals = <String>{NodexPermissions.vitalsRecord};
  const Set<String> recordHandover = <String>{
    NodexPermissions.nursingHandoverRecord,
  };
  const Set<String> writeTasks = <String>{NodexPermissions.nursingTaskWrite};
  const Set<String> readStation = <String>{NodexPermissions.nursingStationRead};

  setUp(() {
    store = FakeNursingStore();
    repository = DefaultNursingStationRepository(
      store: store,
      logger: NodexLogger(
        sinks: <NodexLogSink>[InMemoryLogSink()],
        minimumLevel: NodexLogLevel.trace,
      ),
    );
  });

  group('advisory alert band', () {
    test('a normal observation is normal', () {
      expect(
        buildVital(pulseBpm: 80, spo2: 98, systolicBp: 120).alert,
        VitalAlert.normal,
      );
    });

    test('a single out-of-range parameter is a warning', () {
      expect(buildVital(spo2: 92).alert, VitalAlert.warning);
      expect(buildVital(pulseBpm: 120).alert, VitalAlert.warning);
      expect(buildVital(painScore: 8).alert, VitalAlert.warning);
    });

    test('a critical parameter overrides warnings', () {
      expect(buildVital(systolicBp: 85, spo2: 92).alert, VitalAlert.critical);
      expect(
        buildVital(spo2: 97, consciousness: ConsciousnessLevel.voice).alert,
        VitalAlert.critical,
      );
      expect(buildVital(spo2: 88).alert, VitalAlert.critical);
    });
  });

  test('recording vitals requires vitals.record and a measurement', () async {
    final useCase = RecordWardVitalsUseCase(repository: repository);
    expect(
      () => useCase.call(
        policy: policyWith(<String>{}),
        tenantId: 'tenant-1',
        patientId: 'patient-1',
        wardId: 'ward-1',
        recordedBy: 'nurse-1',
        pulseBpm: 80,
      ),
      throwsA(isA<NodexError>()),
    );
    expect(
      () => useCase.call(
        policy: policyWith(recordVitals),
        tenantId: 'tenant-1',
        patientId: 'patient-1',
        wardId: 'ward-1',
        recordedBy: 'nurse-1',
      ),
      throwsA(isA<NodexError>()),
    );
    final String id = await useCase.call(
      policy: policyWith(recordVitals),
      tenantId: 'tenant-1',
      patientId: 'patient-1',
      wardId: 'ward-1',
      recordedBy: 'nurse-1',
      spo2: 97,
    );
    expect((await repository.vitalById(id))!.spo2, 97);
  });

  test('recording a handover requires nursing.handover.record', () async {
    final useCase = RecordWardHandoverUseCase(repository: repository);
    expect(
      () => useCase.call(
        policy: policyWith(<String>{}),
        tenantId: 'tenant-1',
        wardId: 'ward-1',
        fromUser: 'nurse-1',
        summary: 'Stable',
      ),
      throwsA(isA<NodexError>()),
    );
    final String id = await useCase.call(
      policy: policyWith(recordHandover),
      tenantId: 'tenant-1',
      wardId: 'ward-1',
      fromUser: 'nurse-1',
      summary: 'Stable',
    );
    expect((await repository.handoverById(id))!.summary, 'Stable');
  });

  test('creating a task requires nursing_task.write', () async {
    final useCase = CreateWardTaskUseCase(repository: repository);
    expect(
      () => useCase.call(
        policy: policyWith(<String>{}),
        tenantId: 'tenant-1',
        wardId: 'ward-1',
        createdBy: 'nurse-1',
        title: 'Obs',
      ),
      throwsA(isA<NodexError>()),
    );
    final String id = await useCase.call(
      policy: policyWith(writeTasks),
      tenantId: 'tenant-1',
      wardId: 'ward-1',
      createdBy: 'nurse-1',
      title: 'Obs',
    );
    expect((await repository.taskById(id))!.status, WardTaskStatus.open);
  });

  test('task lifecycle is a guarded state machine', () async {
    final String id = await repository.createTask(<String, Object?>{
      'tenant_id': 'tenant-1',
      'ward_id': 'ward-1',
      'title': 'Obs',
      'task_type': 'observation',
      'priority': 'routine',
      'status': 'open',
      'created_by': 'nurse-1',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    final WardTask open = (await repository.taskById(id))!;
    final StartWardTaskUseCase start = StartWardTaskUseCase(
      repository: repository,
    );
    await start.call(policy: policyWith(writeTasks), task: open);
    final WardTask started = (await repository.taskById(id))!;
    expect(started.status, WardTaskStatus.inProgress);
    expect(
      () => start.call(policy: policyWith(writeTasks), task: started),
      throwsA(isA<NodexError>()),
    );

    final CloseWardTaskUseCase close = CloseWardTaskUseCase(
      repository: repository,
    );
    await close.call(
      policy: policyWith(writeTasks),
      task: started,
      status: WardTaskStatus.done,
      completedBy: 'nurse-1',
    );
    final WardTask done = (await repository.taskById(id))!;
    expect(done.status, WardTaskStatus.done);
    expect(done.completedBy, 'nurse-1');
    expect(
      () => close.call(
        policy: policyWith(writeTasks),
        task: done,
        status: WardTaskStatus.cancelled,
        completedBy: 'nurse-1',
      ),
      throwsA(isA<NodexError>()),
    );
    expect(
      () => AssignWardTaskUseCase(
        repository: repository,
      ).call(policy: policyWith(writeTasks), task: done, assignedTo: 'nurse-2'),
      throwsA(isA<NodexError>()),
    );
  });

  test('reads are gated and urgent filters to warning or critical', () async {
    final ReadWardStationUseCase read = ReadWardStationUseCase(
      repository: repository,
    );
    expect(
      () => read.recentVitals(
        policy: policyWith(<String>{}),
        tenantId: 'tenant-1',
        wardId: 'ward-1',
      ),
      throwsA(isA<NodexError>()),
    );

    await repository.recordVitals(
      WardVital.registerRow(
        tenantId: 'tenant-1',
        patientId: 'patient-1',
        wardId: 'ward-1',
        recordedBy: 'nurse-1',
        spo2: 88,
      ),
    );
    await repository.recordVitals(
      WardVital.registerRow(
        tenantId: 'tenant-1',
        patientId: 'patient-2',
        wardId: 'ward-1',
        recordedBy: 'nurse-1',
        spo2: 98,
        pulseBpm: 78,
      ),
    );
    final List<WardVital> urgent = await read.urgentVitals(
      policy: policyWith(readStation),
      tenantId: 'tenant-1',
      wardId: 'ward-1',
    );
    expect(urgent, hasLength(1));
    expect(urgent.first.patientId, 'patient-1');
  });
}
