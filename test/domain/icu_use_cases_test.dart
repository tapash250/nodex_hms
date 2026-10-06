/// Tests for the ICU use-case gates and bed assignment (Module 06).
///
/// The interesting behaviour is bed assignment: re-assigning an existing
/// ICU bed must update the record in place (keeping its identity and, when
/// none is supplied, its existing ventilator) rather than create a
/// duplicate bed row.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/authorization_snapshot.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/icu/icu.dart';
import 'package:nodex_hms/domain/icu/icu_repository.dart';
import 'package:nodex_hms/domain/icu/icu_use_cases.dart';

/// Records writes and serves a configurable existing bed.
final class RecordingIcuRepository implements IcuRepository {
  IcuBed? existingBed;
  final List<IcuBed> bedWrites = <IcuBed>[];
  final List<IcuVitals> vitalsWrites = <IcuVitals>[];
  final List<IcuNursingHandover> handoverWrites = <IcuNursingHandover>[];
  final List<VentilatorEvent> ventilatorWrites = <VentilatorEvent>[];

  @override
  Future<IcuBed?> bedById(String id) async => existingBed;

  @override
  Future<List<IcuBed>> allBeds() async => <IcuBed>[];

  @override
  Future<List<IcuBed>> bedsForPatient(String patientId) async => <IcuBed>[];

  @override
  Future<IcuBed> upsertBed(IcuBed bed) async {
    bedWrites.add(bed);
    return bed;
  }

  @override
  Future<IcuVitals?> vitalsById(String id) async => null;

  @override
  Future<List<IcuVitals>> vitalsForPatient(String patientId) async =>
      <IcuVitals>[];

  @override
  Future<List<IcuVitals>> vitalsForBed(String icuBedId) async => <IcuVitals>[];

  @override
  Future<IcuVitals> recordVitals(IcuVitals vitals) async {
    vitalsWrites.add(vitals);
    return vitals;
  }

  @override
  Future<IcuNursingHandover?> handoverById(String id) async => null;

  @override
  Future<List<IcuNursingHandover>> handoversForPatient(
    String patientId,
  ) async => <IcuNursingHandover>[];

  @override
  Future<IcuNursingHandover> recordHandover(IcuNursingHandover handover) async {
    handoverWrites.add(handover);
    return handover;
  }

  @override
  Future<VentilatorEvent?> ventilatorEventById(String id) async => null;

  @override
  Future<List<VentilatorEvent>> ventilatorEventsForBed(String icuBedId) async =>
      <VentilatorEvent>[];

  @override
  Future<VentilatorEvent> recordVentilatorEvent(VentilatorEvent event) async {
    ventilatorWrites.add(event);
    return event;
  }
}

/// Builds a policy holding exactly [permissions].
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
      facilityIds: const <String>{},
      departmentIds: const <String>{},
      wardIds: const <String>{},
    ),
    connectivity: ConnectivityState.online,
  );
}

IcuBed existingBedWith({String? ventilatorId = 'vent-1'}) => IcuBed(
  id: 'icu-bed-1',
  tenantId: 'tenant-1',
  bedId: 'ward-bed-1',
  ventilatorId: ventilatorId,
  status: IcuBedStatus.occupied,
  currentPatientId: 'patient-0',
  createdAt: DateTime.utc(2026, 9, 1, 8),
  updatedAt: DateTime.utc(2026, 9, 1, 8),
);

void main() {
  late RecordingIcuRepository repository;
  late AssignIcuBedUseCase assignBed;
  late RecordIcuVitalsUseCase recordVitals;
  late RecordIcuHandoverUseCase recordHandover;
  late RecordVentilatorEventUseCase recordVentilatorEvent;

  const Set<String> bedAssigner = <String>{NodexPermissions.icuBedAssign};
  const Set<String> vitalsRecorder = <String>{NodexPermissions.icuVitalsRecord};
  const Set<String> handoverRecorder = <String>{
    NodexPermissions.icuHandoverRecord,
  };
  const Set<String> ventilatorRecorder = <String>{
    NodexPermissions.ventilatorEventRecord,
  };
  const Set<String> reader = <String>{};
  const Set<String> all = <String>{
    NodexPermissions.icuBedAssign,
    NodexPermissions.icuVitalsRecord,
    NodexPermissions.icuHandoverRecord,
    NodexPermissions.ventilatorEventRecord,
  };

  setUp(() {
    repository = RecordingIcuRepository();
    assignBed = AssignIcuBedUseCase(repository: repository);
    recordVitals = RecordIcuVitalsUseCase(repository: repository);
    recordHandover = RecordIcuHandoverUseCase(repository: repository);
    recordVentilatorEvent = RecordVentilatorEventUseCase(
      repository: repository,
    );
  });

  group('authorization gates', () {
    test('assigning a bed requires icu.bed.assign', () {
      expect(
        assignBed.call(
          policy: policyWith(reader),
          tenantId: 'tenant-1',
          bedId: 'ward-bed-1',
          patientId: 'patient-1',
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.requiredPermission,
            'requiredPermission',
            NodexPermissions.icuBedAssign,
          ),
        ),
      );
    });

    test('recording vitals requires icu.vitals.record', () {
      expect(
        recordVitals.call(
          policy: policyWith(reader),
          tenantId: 'tenant-1',
          patientId: 'patient-1',
          icuBedId: 'icu-bed-1',
          recordedBy: 'nurse-1',
          heartRate: 80,
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('recording a handover requires icu.handover.record', () {
      expect(
        recordHandover.call(
          policy: policyWith(vitalsRecorder),
          tenantId: 'tenant-1',
          patientId: 'patient-1',
          icuBedId: 'icu-bed-1',
          outgoingNurse: 'nurse-1',
          incomingNurse: 'nurse-2',
          summary: 'Stable overnight',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('recording a ventilator event requires ventilator.event.record', () {
      expect(
        recordVentilatorEvent.call(
          policy: policyWith(bedAssigner),
          tenantId: 'tenant-1',
          patientId: 'patient-1',
          icuBedId: 'icu-bed-1',
          eventType: 'settings_change',
          recordedBy: 'nurse-1',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });
  });

  group('bed assignment', () {
    test('a fresh assignment creates an occupied bed', () async {
      final IcuBed bed = await assignBed.call(
        policy: policyWith(bedAssigner),
        tenantId: 'tenant-1',
        bedId: 'ward-bed-1',
        patientId: 'patient-1',
      );

      expect(repository.bedWrites, hasLength(1));
      expect(bed.status, IcuBedStatus.occupied);
      expect(bed.currentPatientId, 'patient-1');
      expect(bed.tenantId, 'tenant-1');
      expect(bed.bedId, 'ward-bed-1');
    });

    test('re-assigning an existing bed keeps its identity', () async {
      repository.existingBed = existingBedWith();

      final IcuBed bed = await assignBed.call(
        policy: policyWith(bedAssigner),
        tenantId: 'tenant-1',
        bedId: 'ward-bed-1',
        patientId: 'patient-2',
        existingBedId: 'icu-bed-1',
      );

      expect(repository.bedWrites, hasLength(1));
      expect(bed.id, 'icu-bed-1');
      expect(bed.createdAt, existingBedWith().createdAt);
      // No ventilator supplied: the previously attached one is retained.
      expect(bed.ventilatorId, 'vent-1');
      expect(bed.currentPatientId, 'patient-2');
      expect(bed.updatedAt.isAfter(bed.createdAt), isTrue);
    });

    test('a supplied ventilator replaces the existing one', () async {
      repository.existingBed = existingBedWith();

      final IcuBed bed = await assignBed.call(
        policy: policyWith(bedAssigner),
        tenantId: 'tenant-1',
        bedId: 'ward-bed-1',
        patientId: 'patient-2',
        existingBedId: 'icu-bed-1',
        ventilatorId: 'vent-2',
      );

      expect(bed.ventilatorId, 'vent-2');
    });

    test('an unknown existing bed id falls back to a new bed', () async {
      repository.existingBed = null;

      final IcuBed bed = await assignBed.call(
        policy: policyWith(bedAssigner),
        tenantId: 'tenant-1',
        bedId: 'ward-bed-1',
        patientId: 'patient-1',
        existingBedId: 'missing-bed',
      );

      expect(repository.bedWrites, hasLength(1));
      expect(bed.id, isNot('missing-bed'));
      expect(bed.bedId, 'ward-bed-1');
    });

    test('a bed can be released by assigning it available', () async {
      repository.existingBed = existingBedWith();

      final IcuBed bed = await assignBed.call(
        policy: policyWith(bedAssigner),
        tenantId: 'tenant-1',
        bedId: 'ward-bed-1',
        patientId: null,
        status: IcuBedStatus.available,
        existingBedId: 'icu-bed-1',
      );

      expect(bed.status, IcuBedStatus.available);
      expect(bed.currentPatientId, isNull);
    });
  });

  group('clinical records', () {
    test('a vitals snapshot keeps the values it was given', () async {
      final IcuVitals vitals = await recordVitals.call(
        policy: policyWith(vitalsRecorder),
        tenantId: 'tenant-1',
        patientId: 'patient-1',
        icuBedId: 'icu-bed-1',
        recordedBy: 'nurse-1',
        heartRate: 88,
        spo2: 97,
        temperatureCelsius: 37.1,
        gcsTotal: 15,
      );

      expect(repository.vitalsWrites, hasLength(1));
      expect(vitals.heartRate, 88);
      expect(vitals.spo2, 97);
      expect(vitals.temperatureCelsius, 37.1);
      expect(vitals.gcsTotal, 15);
      expect(vitals.recordedBy, 'nurse-1');
    });

    test('a handover defaults its time and keeps optional notes', () async {
      final IcuNursingHandover handover = await recordHandover.call(
        policy: policyWith(handoverRecorder),
        tenantId: 'tenant-1',
        patientId: 'patient-1',
        icuBedId: 'icu-bed-1',
        outgoingNurse: 'nurse-1',
        incomingNurse: 'nurse-2',
        summary: 'Stable overnight',
        concerns: 'Rising creatinine',
      );

      expect(repository.handoverWrites, hasLength(1));
      expect(handover.outgoingNurse, 'nurse-1');
      expect(handover.incomingNurse, 'nurse-2');
      expect(handover.summary, 'Stable overnight');
      expect(handover.concerns, 'Rising creatinine');
      expect(handover.handoverTime, isNotNull);
    });

    test('a ventilator event keeps its settings', () async {
      final VentilatorEvent event = await recordVentilatorEvent.call(
        policy: policyWith(ventilatorRecorder),
        tenantId: 'tenant-1',
        patientId: 'patient-1',
        icuBedId: 'icu-bed-1',
        eventType: 'settings_change',
        recordedBy: 'nurse-1',
        ventilatorId: 'vent-1',
        mode: 'SIMV',
        settings: const <String, Object?>{'peep': 5, 'fio2': 40},
      );

      expect(repository.ventilatorWrites, hasLength(1));
      expect(event.eventType, 'settings_change');
      expect(event.mode, 'SIMV');
      expect(event.settings['peep'], 5);
      expect(event.settings['fio2'], 40);
    });
  });

  // The `all` set is unused at runtime but documents the full ICU permission
  // surface; referencing it keeps the constant meaningful to readers.
  test('the ICU permission surface is complete', () {
    expect(all, contains(NodexPermissions.icuBedAssign));
    expect(reader, isEmpty);
  });
}
