/// Tests for the clinical dashboard (Module 04).
///
/// A patient is on the doctor's dashboard because there is an assignment, and
/// the assignment says who is responsible and for what. These tests pin that
/// the assignment is the source and that it cannot be quietly rewritten.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/authorization_snapshot.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/clinical_dashboard/clinical_dashboard_repository.dart';
import 'package:nodex_hms/domain/clinical_dashboard/doctor_assignment.dart';

/// A repository that returns fixed assignments.
final class _FixedClinicalDashboardRepository
    implements ClinicalDashboardRepository {
  _FixedClinicalDashboardRepository(this.assignments);

  final List<DoctorAssignment> assignments;

  @override
  Future<List<DoctorAssignment>> listAssignments(String doctorId) async =>
      assignments
          .where((DoctorAssignment a) => a.doctorId == doctorId)
          .toList(growable: false);

  @override
  Future<List<DoctorAssignment>> listAllAssignments() async => assignments;
}

/// A policy holding the given permissions.
AuthorizationPolicy _policy(Set<String> permissions) {
  final DateTime issuedAt = DateTime.now().toUtc();
  return AuthorizationPolicy(
    snapshot: AuthorizationSnapshot(
      snapshotId: 'snapshot-1',
      tenantId: 'tenant-1',
      userId: 'user-1',
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
  group('reading an assignment', () {
    test('an assignment is read from a local row', () {
      final DoctorAssignment assignment = DoctorAssignment.fromRow(
        const <String, Object?>{
          'id': 'assignment-1',
          'tenant_id': 'tenant-1',
          'doctor_id': 'doctor-1',
          'patient_id': 'patient-1',
          'assignment_type': 'primary_attending',
          'status': 'active',
          'assigned_at': '2026-09-12T09:00:00.000Z',
          'concluded_at': null,
        },
      );
      expect(assignment.assignmentType, AssignmentType.primaryAttending);
      expect(assignment.isActive, isTrue);
      expect(assignment.concludedAt, isNull);
    });

    test('a concluded assignment is not active', () {
      final DoctorAssignment assignment = DoctorAssignment.fromRow(
        const <String, Object?>{
          'id': 'assignment-2',
          'tenant_id': 'tenant-1',
          'doctor_id': 'doctor-1',
          'patient_id': 'patient-1',
          'assignment_type': 'consulting',
          'status': 'concluded',
          'assigned_at': '2026-09-01T09:00:00.000Z',
          'concluded_at': '2026-09-12T09:00:00.000Z',
        },
      );
      expect(assignment.isActive, isFalse);
      expect(assignment.assignmentType, AssignmentType.consulting);
    });

    test('an unknown assignment type falls back to the attending', () {
      expect(
        AssignmentType.fromWire('something_new'),
        AssignmentType.primaryAttending,
      );
    });
  });

  group('the dashboard', () {
    test('reading it requires the read permission', () async {
      await expectLater(
        ListDoctorAssignmentsUseCase(
          repository: _FixedClinicalDashboardRepository(
            const <DoctorAssignment>[],
          ),
        ).call(
          policy: _policy(<String>{NodexPermissions.clinicalDashboardManage}),
          doctorId: 'doctor-1',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('a clinician sees their own assignments', () async {
      const DoctorAssignment theirs = DoctorAssignment(
        id: 'assignment-1',
        tenantId: 'tenant-1',
        doctorId: 'doctor-1',
        patientId: 'patient-1',
        assignmentType: AssignmentType.primaryAttending,
        status: 'active',
      );
      const DoctorAssignment someoneElse = DoctorAssignment(
        id: 'assignment-2',
        tenantId: 'tenant-1',
        doctorId: 'doctor-2',
        patientId: 'patient-2',
        assignmentType: AssignmentType.primaryAttending,
        status: 'active',
      );
      final List<DoctorAssignment> assignments =
          await ListDoctorAssignmentsUseCase(
            repository: _FixedClinicalDashboardRepository(<DoctorAssignment>[
              theirs,
              someoneElse,
            ]),
          ).call(
            policy: _policy(<String>{NodexPermissions.clinicalDashboardRead}),
            doctorId: 'doctor-1',
          );
      expect(assignments, hasLength(1));
      expect(assignments.single.patientId, 'patient-1');
    });
  });
}
