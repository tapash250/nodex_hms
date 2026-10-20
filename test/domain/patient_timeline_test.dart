/// Tests for the patient journey (Module 50).
///
/// The journey is a reading of the record, not a second record: it must show
/// what happened, in order, without the parts that did not happen. These tests
/// pin the assembly — what becomes an event, what is left out, and how the
/// events are ordered and grouped.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/authorization_snapshot.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/appointments/appointment.dart';
import 'package:nodex_hms/domain/discharge/discharge.dart';
import 'package:nodex_hms/domain/encounters/encounter.dart';
import 'package:nodex_hms/domain/laboratory/lab.dart';
import 'package:nodex_hms/domain/ot/ot.dart';
import 'package:nodex_hms/domain/prescriptions/prescription.dart';
import 'package:nodex_hms/domain/timeline/patient_timeline.dart';
import 'package:nodex_hms/domain/timeline/timeline_repository.dart';
import 'package:nodex_hms/domain/timeline/timeline_use_cases.dart';

ClinicalEncounter _encounter({
  required String id,
  required EncounterType type,
  required DateTime createdAt,
  EncounterStatus status = EncounterStatus.signedAndLocked,
  List<EncounterDiagnosis> diagnoses = const <EncounterDiagnosis>[],
}) => ClinicalEncounter(
  id: id,
  tenantId: 'tenant-1',
  patientId: 'patient-1',
  attendingPhysicianId: 'doctor-1',
  encounterType: type,
  status: status,
  diagnoses: diagnoses,
  createdAt: createdAt,
);

Appointment _appointment({
  required String id,
  required DateTime scheduledStart,
  AppointmentStatus status = AppointmentStatus.completed,
  String? reason,
}) => Appointment(
  id: id,
  tenantId: 'tenant-1',
  patientId: 'patient-1',
  providerId: 'doctor-1',
  bookedBy: 'reception-1',
  appointmentCode: 'APT-1',
  visitType: VisitType.outpatient,
  priority: AppointmentPriority.routine,
  status: status,
  scheduledStart: scheduledStart,
  scheduledEnd: scheduledStart.add(const Duration(minutes: 20)),
  createdAt: scheduledStart,
  completedAt: status == AppointmentStatus.completed ? scheduledStart : null,
  reason: reason,
);

LabOrder _labOrder({
  required String id,
  required DateTime orderedAt,
  LabOrderStatus status = LabOrderStatus.collected,
}) => LabOrder(
  id: id,
  tenantId: 'tenant-1',
  patientId: 'patient-1',
  orderedBy: 'doctor-1',
  orderCode: 'LAB-1',
  priority: LabPriority.routine,
  status: status,
  tests: const <LabTestRequest>[],
  orderedAt: orderedAt,
);

Prescription _prescription({required String id, required DateTime createdAt}) =>
    Prescription(
      id: id,
      tenantId: 'tenant-1',
      patientId: 'patient-1',
      prescribedBy: 'doctor-1',
      prescriptionCode: 'RX-1',
      version: 1,
      priority: PrescriptionPriority.routine,
      status: PrescriptionStatus.draft,
      createdAt: createdAt,
    );

Discharge _discharge({required String id, required DateTime createdAt}) =>
    Discharge(
      id: id,
      tenantId: 'tenant-1',
      patientId: 'patient-1',
      encounterId: 'encounter-1',
      createdBy: 'doctor-1',
      dischargeCode: 'DC-1',
      dischargeType: DischargeType.routine,
      status: DischargeStatus.draft,
      createdAt: createdAt,
    );

OtBooking _booking({required String id, required DateTime scheduledStart}) =>
    OtBooking(
      id: id,
      tenantId: 'tenant-1',
      patientId: 'patient-1',
      theatreRoom: 'Theatre 1',
      procedureName: 'Laparoscopic cholecystectomy',
      scheduledStart: scheduledStart,
      scheduledEnd: scheduledStart.add(const Duration(hours: 2)),
      surgeonId: 'surgeon-1',
      status: OtBookingStatus.scheduled,
      priority: OtPriority.routine,
      createdBy: 'scheduler-1',
      createdAt: scheduledStart,
      updatedAt: scheduledStart,
    );

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

/// A repository that hands back a fixed journey.
final class _FixedTimelineRepository implements TimelineRepository {
  _FixedTimelineRepository(this.timeline);

  final PatientTimeline timeline;
  String? lastPatientId;

  @override
  Future<PatientTimeline> readTimeline(String patientId) async {
    lastPatientId = patientId;
    return timeline;
  }
}

void main() {
  group('assembling the journey', () {
    test('orders the events newest first', () {
      final PatientTimeline timeline = buildPatientTimeline(
        encounters: <ClinicalEncounter>[
          _encounter(
            id: 'encounter-1',
            type: EncounterType.outpatient,
            createdAt: DateTime.utc(2026, 3, 1),
          ),
        ],
        labOrders: <LabOrder>[
          _labOrder(id: 'lab-1', orderedAt: DateTime.utc(2026, 6, 1)),
        ],
        discharges: <Discharge>[
          _discharge(id: 'discharge-1', createdAt: DateTime.utc(2026, 1, 1)),
        ],
      );

      expect(
        timeline.events.map((TimelineEvent event) => event.kind),
        <TimelineEventKind>[
          TimelineEventKind.labOrder,
          TimelineEventKind.outpatientVisit,
          TimelineEventKind.discharge,
        ],
      );
    });

    test('reads the kind of an encounter from its type', () {
      final PatientTimeline timeline = buildPatientTimeline(
        encounters: <ClinicalEncounter>[
          _encounter(
            id: 'encounter-1',
            type: EncounterType.inpatient,
            createdAt: DateTime.utc(2026, 3, 1),
          ),
          _encounter(
            id: 'encounter-2',
            type: EncounterType.emergency,
            createdAt: DateTime.utc(2026, 3, 2),
          ),
          _encounter(
            id: 'encounter-3',
            type: EncounterType.telehealth,
            createdAt: DateTime.utc(2026, 3, 3),
          ),
        ],
      );

      expect(
        timeline.events.map((TimelineEvent event) => event.kind).toSet(),
        <TimelineEventKind>{
          TimelineEventKind.admission,
          TimelineEventKind.emergency,
          TimelineEventKind.telehealth,
        },
      );
    });

    test('carries the diagnoses of an encounter as its detail', () {
      final PatientTimeline timeline = buildPatientTimeline(
        encounters: <ClinicalEncounter>[
          _encounter(
            id: 'encounter-1',
            type: EncounterType.outpatient,
            createdAt: DateTime.utc(2026, 3, 1),
            diagnoses: const <EncounterDiagnosis>[
              EncounterDiagnosis(code: 'J06.9', description: 'Acute URI'),
            ],
          ),
        ],
      );
      expect(timeline.events.single.detail, 'Acute URI');
    });

    test('leaves out a cancelled visit', () {
      final PatientTimeline timeline = buildPatientTimeline(
        appointments: <Appointment>[
          _appointment(
            id: 'appointment-1',
            scheduledStart: DateTime.utc(2026, 3, 1),
            status: AppointmentStatus.cancelled,
          ),
        ],
      );
      expect(timeline.count, 0);
    });

    test('leaves out a cancelled laboratory order', () {
      final PatientTimeline timeline = buildPatientTimeline(
        labOrders: <LabOrder>[
          _labOrder(
            id: 'lab-1',
            orderedAt: DateTime.utc(2026, 3, 1),
            status: LabOrderStatus.cancelled,
          ),
        ],
      );
      expect(timeline.count, 0);
    });

    test('keeps a prescription and a discharge', () {
      final PatientTimeline timeline = buildPatientTimeline(
        prescriptions: <Prescription>[
          _prescription(id: 'rx-1', createdAt: DateTime.utc(2026, 3, 1)),
        ],
        discharges: <Discharge>[
          _discharge(id: 'discharge-1', createdAt: DateTime.utc(2026, 3, 2)),
        ],
      );
      expect(timeline.count, 2);
      expect(
        timeline.events.map((TimelineEvent event) => event.kind).toSet(),
        <TimelineEventKind>{
          TimelineEventKind.prescription,
          TimelineEventKind.discharge,
        },
      );
    });

    test('shows an operation as a surgery', () {
      final PatientTimeline timeline = buildPatientTimeline(
        surgeries: <OtBooking>[
          _booking(id: 'booking-1', scheduledStart: DateTime.utc(2026, 3, 1)),
        ],
      );
      expect(timeline.events.single.kind, TimelineEventKind.surgery);
      expect(timeline.events.single.title, contains('Laparoscopic'));
    });

    test('keeps the record behind each event so it can be opened', () {
      final PatientTimeline timeline = buildPatientTimeline(
        labOrders: <LabOrder>[
          _labOrder(id: 'lab-1', orderedAt: DateTime.utc(2026, 3, 1)),
        ],
      );
      expect(timeline.events.single.sourceId, 'lab-1');
    });

    test('carries the priority of the order that was placed', () {
      final PatientTimeline timeline = buildPatientTimeline(
        labOrders: <LabOrder>[
          LabOrder(
            id: 'lab-1',
            tenantId: 'tenant-1',
            patientId: 'patient-1',
            orderedBy: 'doctor-1',
            orderCode: 'LAB-1',
            priority: LabPriority.stat,
            status: LabOrderStatus.collected,
            tests: const <LabTestRequest>[],
            orderedAt: DateTime.utc(2026, 3, 1),
          ),
        ],
      );
      expect(timeline.events.single.priority, 'stat');
    });

    test('an empty journey is empty, not broken', () {
      final PatientTimeline timeline = buildPatientTimeline();
      expect(timeline.count, 0);
      expect(timeline.groupedByMonth(), isEmpty);
    });
  });

  group('grouping by month', () {
    test('puts the events of a month under one heading', () {
      final PatientTimeline timeline = buildPatientTimeline(
        labOrders: <LabOrder>[
          _labOrder(id: 'lab-1', orderedAt: DateTime.utc(2026, 3, 1)),
          _labOrder(id: 'lab-2', orderedAt: DateTime.utc(2026, 3, 20)),
        ],
      );
      final List<TimelineGroup> groups = timeline.groupedByMonth();
      expect(groups, hasLength(1));
      expect(groups.single.events, hasLength(2));
      expect(groups.single.label, 'March 2026');
    });

    test('keeps the months apart, newest first', () {
      final PatientTimeline timeline = buildPatientTimeline(
        labOrders: <LabOrder>[
          _labOrder(id: 'lab-1', orderedAt: DateTime.utc(2026, 3, 1)),
          _labOrder(id: 'lab-2', orderedAt: DateTime.utc(2026, 5, 1)),
        ],
      );
      final List<TimelineGroup> groups = timeline.groupedByMonth();
      expect(groups, hasLength(2));
      expect(groups.first.label, 'May 2026');
      expect(groups.last.label, 'March 2026');
    });
  });

  group('reading the journey', () {
    test('requires the patient read permission', () async {
      final _FixedTimelineRepository repository = _FixedTimelineRepository(
        const PatientTimeline(events: <TimelineEvent>[]),
      );
      await expectLater(
        ReadPatientTimelineUseCase(repository: repository).call(
          policy: _policy(<String>{NodexPermissions.labOrderWrite}),
          patientId: 'patient-1',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('reads the journey for the patient asked for', () async {
      final _FixedTimelineRepository repository = _FixedTimelineRepository(
        const PatientTimeline(events: <TimelineEvent>[]),
      );
      await ReadPatientTimelineUseCase(repository: repository).call(
        policy: _policy(<String>{NodexPermissions.patientRead}),
        patientId: 'patient-1',
      );
      expect(repository.lastPatientId, 'patient-1');
    });
  });
}
