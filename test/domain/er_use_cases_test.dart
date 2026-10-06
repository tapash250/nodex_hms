/// Tests for the ER and triage use-case gates (Module 05).
///
/// The entities are covered elsewhere; this file pins the workflow
/// described in the spec: triage is recorded under `triage.write`,
/// escalation is a one-way transition that needs `triage.escalate`,
/// and an ER visit only moves forward until it reaches a terminal state.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/authorization_snapshot.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/er/er.dart';
import 'package:nodex_hms/domain/er/er_repository.dart';
import 'package:nodex_hms/domain/er/er_use_cases.dart';

/// Echoes entities back and records the writes it was asked to make.
final class RecordingErRepository implements ErRepository {
  final List<TriageAssessment> triageWrites = <TriageAssessment>[];
  final List<Map<String, Object?>> triageUpdates = <Map<String, Object?>>[];
  final List<ErVisit> visitWrites = <ErVisit>[];
  final List<Map<String, Object?>> visitUpdates = <Map<String, Object?>>[];

  @override
  Future<TriageAssessment?> triageById(String id) async => null;

  @override
  Future<List<TriageAssessment>> triageForPatient(String patientId) async =>
      <TriageAssessment>[];

  @override
  Future<TriageAssessment> createTriage(TriageAssessment assessment) async {
    triageWrites.add(assessment);
    return assessment;
  }

  @override
  Future<TriageAssessment> updateTriage(
    String id,
    Map<String, Object?> changes,
  ) async {
    triageUpdates.add(<String, Object?>{'id': id, ...changes});
    return triageWith(escalated: changes['escalated'] == true);
  }

  @override
  Future<ErVisit?> visitById(String id) async => null;

  @override
  Future<List<ErVisit>> visitsForPatient(String patientId) async => <ErVisit>[];

  @override
  Future<List<ErVisit>> openVisits() async => <ErVisit>[];

  @override
  Future<ErVisit> createVisit(ErVisit visit) async {
    visitWrites.add(visit);
    return visit;
  }

  @override
  Future<ErVisit> updateVisit(String id, Map<String, Object?> changes) async {
    visitUpdates.add(<String, Object?>{'id': id, ...changes});
    return visitWith();
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

TriageAssessment triageWith({bool escalated = false}) => TriageAssessment(
  id: 'triage-1',
  tenantId: 'tenant-1',
  patientId: 'patient-1',
  assessedBy: 'nurse-1',
  acuity: TriageAcuity.esi3,
  chiefComplaint: 'Chest pain',
  disposition: TriageDisposition.admit,
  escalated: escalated,
  createdAt: DateTime.utc(2026, 9, 12, 8),
  updatedAt: DateTime.utc(2026, 9, 12, 8),
);

ErVisit visitWith({ErVisitStatus status = ErVisitStatus.inProgress}) => ErVisit(
  id: 'visit-1',
  tenantId: 'tenant-1',
  patientId: 'patient-1',
  triageId: 'triage-1',
  providerId: 'doctor-1',
  status: status,
  startedAt: DateTime.utc(2026, 9, 12, 8),
  createdAt: DateTime.utc(2026, 9, 12, 8),
  updatedAt: DateTime.utc(2026, 9, 12, 8),
);

void main() {
  late RecordingErRepository repository;
  late RecordTriageUseCase recordTriage;
  late EscalateTriageUseCase escalateTriage;
  late OpenErVisitUseCase openVisit;
  late TransitionErVisitUseCase transitionVisit;

  const Set<String> triageWriter = <String>{NodexPermissions.triageWrite};
  const Set<String> escalator = <String>{NodexPermissions.triageEscalate};
  const Set<String> visitWriter = <String>{NodexPermissions.erVisitWrite};
  const Set<String> reader = <String>{NodexPermissions.triageRead};

  setUp(() {
    repository = RecordingErRepository();
    recordTriage = RecordTriageUseCase(repository: repository);
    escalateTriage = EscalateTriageUseCase(repository: repository);
    openVisit = OpenErVisitUseCase(repository: repository);
    transitionVisit = TransitionErVisitUseCase(repository: repository);
  });

  group('authorization gates', () {
    test('recording triage requires triage.write', () {
      expect(
        recordTriage.call(
          policy: policyWith(reader),
          tenantId: 'tenant-1',
          patientId: 'patient-1',
          assessedBy: 'nurse-1',
          acuity: TriageAcuity.esi2,
          chiefComplaint: 'Chest pain',
          disposition: TriageDisposition.admit,
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.requiredPermission,
            'requiredPermission',
            NodexPermissions.triageWrite,
          ),
        ),
      );
    });

    test('escalating requires triage.escalate', () {
      expect(
        escalateTriage.call(
          policy: policyWith(triageWriter),
          assessment: triageWith(),
          escalatedBy: 'nurse-1',
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.requiredPermission,
            'requiredPermission',
            NodexPermissions.triageEscalate,
          ),
        ),
      );
    });

    test('opening an ER visit requires er.visit.write', () {
      expect(
        openVisit.call(
          policy: policyWith(triageWriter),
          tenantId: 'tenant-1',
          patientId: 'patient-1',
          triageId: 'triage-1',
          providerId: 'doctor-1',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('transitioning an ER visit requires er.visit.write', () {
      expect(
        transitionVisit.call(
          policy: policyWith(reader),
          visit: visitWith(),
          nextStatus: ErVisitStatus.discharged,
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });
  });

  group('recording triage', () {
    test('stores the assessment with its acuity and complaints', () async {
      final TriageAssessment stored = await recordTriage.call(
        policy: policyWith(triageWriter),
        tenantId: 'tenant-1',
        patientId: 'patient-1',
        assessedBy: 'nurse-1',
        acuity: TriageAcuity.esi1,
        chiefComplaint: 'Unresponsive',
        disposition: TriageDisposition.admit,
        vitals: const <String, Object?>{'hr': 130},
        redFlags: const <String>['unresponsive'],
      );

      expect(repository.triageWrites, hasLength(1));
      expect(stored.acuity, TriageAcuity.esi1);
      expect(stored.chiefComplaint, 'Unresponsive');
      expect(stored.escalated, isFalse);
      expect(stored.redFlags, contains('unresponsive'));
    });
  });

  group('escalation', () {
    test('marks the assessment escalated by its escalator', () async {
      await escalateTriage.call(
        policy: policyWith(escalator),
        assessment: triageWith(),
        escalatedBy: 'nurse-2',
      );

      expect(repository.triageUpdates, hasLength(1));
      final Map<String, Object?> changes = repository.triageUpdates.single;
      expect(changes['id'], 'triage-1');
      expect(changes['escalated'], isTrue);
      expect(changes['escalated_by'], 'nurse-2');
      expect(changes['escalated_at'], isNotNull);
    });

    test('an escalated assessment cannot be escalated again', () {
      expect(
        escalateTriage.call(
          policy: policyWith(escalator),
          assessment: triageWith(escalated: true),
          escalatedBy: 'nurse-2',
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'triage_already_escalated',
          ),
        ),
      );
      expect(repository.triageUpdates, isEmpty);
    });

    test('the permission gate runs before the escalation check', () {
      // Without the escalate permission, an already-escalated assessment
      // must still fail as an authorization error, not a state error.
      expect(
        escalateTriage.call(
          policy: policyWith(triageWriter),
          assessment: triageWith(escalated: true),
          escalatedBy: 'nurse-2',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });
  });

  group('ER visits', () {
    test('a new visit starts in progress', () async {
      final ErVisit visit = await openVisit.call(
        policy: policyWith(visitWriter),
        tenantId: 'tenant-1',
        patientId: 'patient-1',
        triageId: 'triage-1',
        providerId: 'doctor-1',
        arrivalMode: ArrivalMode.ambulance,
        bedId: 'bed-1',
      );

      expect(repository.visitWrites, hasLength(1));
      expect(visit.status, ErVisitStatus.inProgress);
      expect(visit.arrivalMode, ArrivalMode.ambulance);
      expect(visit.bedId, 'bed-1');
      expect(visit.triageId, 'triage-1');
    });

    test('a transition records only the fields that were supplied', () async {
      await transitionVisit.call(
        policy: policyWith(visitWriter),
        visit: visitWith(),
        nextStatus: ErVisitStatus.discharged,
        disposition: 'Home with follow-up',
      );

      expect(repository.visitUpdates, hasLength(1));
      final Map<String, Object?> changes = repository.visitUpdates.single;
      expect(changes['status'], 'discharged');
      expect(changes['disposition'], 'Home with follow-up');
      expect(changes['updated_at'], isNotNull);
      expect(changes.containsKey('disposition_reason'), isFalse);
      expect(changes.containsKey('bed_id'), isFalse);
      expect(changes.containsKey('discharged_at'), isFalse);
    });

    test('an admitted visit can still transition', () async {
      await transitionVisit.call(
        policy: policyWith(visitWriter),
        visit: visitWith(status: ErVisitStatus.admitted),
        nextStatus: ErVisitStatus.discharged,
        bedId: 'ward-bed-1',
      );

      expect(repository.visitUpdates.single['status'], 'discharged');
      expect(repository.visitUpdates.single['bed_id'], 'ward-bed-1');
    });

    test('a terminal visit cannot transition', () {
      expect(
        transitionVisit.call(
          policy: policyWith(visitWriter),
          visit: visitWith(status: ErVisitStatus.discharged),
          nextStatus: ErVisitStatus.admitted,
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'er_visit_terminal',
          ),
        ),
      );
      expect(repository.visitUpdates, isEmpty);
    });
  });
}
