/// The patient's longitudinal journey (Module 50).
///
/// A journey is one story told across the modules that each hold part of it:
/// an encounter, a visit, a test, a prescription, an operation, a discharge.
/// The timeline assembles those parts into one chronological line, and it does
/// so from the rows the device already holds — the journey is not a second
/// record of the care, it is a reading of it.
library;

import 'package:meta/meta.dart';
import 'package:nodex_hms/domain/appointments/appointment.dart';
import 'package:nodex_hms/domain/discharge/discharge.dart';
import 'package:nodex_hms/domain/encounters/encounter.dart';
import 'package:nodex_hms/domain/laboratory/lab.dart';
import 'package:nodex_hms/domain/ot/ot.dart';
import 'package:nodex_hms/domain/prescriptions/prescription.dart';

/// What kind of event a point on the journey is.
enum TimelineEventKind {
  /// A clinic visit.
  outpatientVisit('outpatient_visit', 'Outpatient visit'),

  /// An admission.
  admission('admission', 'Admission'),

  /// An emergency attendance.
  emergency('emergency', 'Emergency visit'),

  /// A teleconsultation.
  telehealth('telehealth', 'Telehealth visit'),

  /// An operation.
  surgery('surgery', 'Surgery'),

  /// A laboratory order.
  labOrder('lab_order', 'Laboratory order'),

  /// A prescription.
  prescription('prescription', 'Prescription'),

  /// A discharge.
  discharge('discharge', 'Discharge');

  const TimelineEventKind(this.wireValue, this.label);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  final String label;
}

/// One point on the journey.
@immutable
final class TimelineEvent {
  /// Declares an event.
  const TimelineEvent({
    required this.id,
    required this.kind,
    required this.at,
    required this.title,
    this.detail,
    this.sourceId,
    this.priority,
  });

  /// Stable identifier of the event.
  final String id;

  /// What kind of event it is.
  final TimelineEventKind kind;

  /// When it happened.
  final DateTime at;

  /// The headline.
  final String title;

  /// The supporting line.
  final String? detail;

  /// The record this event came from, for navigation.
  final String? sourceId;

  /// Priority, when the source carries one.
  final String? priority;
}

/// A run of events that belong to the same month.
@immutable
final class TimelineGroup {
  /// Declares a group.
  const TimelineGroup({required this.label, required this.events});

  /// The month heading.
  final String label;

  /// The events in the group, newest first.
  final List<TimelineEvent> events;
}

/// The patient's journey.
@immutable
final class PatientTimeline {
  /// Declares a timeline.
  const PatientTimeline({required this.events});

  /// Every event, newest first.
  final List<TimelineEvent> events;

  /// How many events the journey holds.
  int get count => events.length;

  /// The events grouped by month, newest month first.
  List<TimelineGroup> groupedByMonth() {
    final List<TimelineGroup> groups = <TimelineGroup>[];
    for (final TimelineEvent event in events) {
      final String label = _monthLabel(event.at);
      if (groups.isNotEmpty && groups.last.label == label) {
        groups[groups.length - 1] = TimelineGroup(
          label: label,
          events: <TimelineEvent>[...groups.last.events, event],
        );
        continue;
      }
      groups.add(TimelineGroup(label: label, events: <TimelineEvent>[event]));
    }
    return groups;
  }

  static String _monthLabel(DateTime at) {
    final DateTime local = at.toLocal();
    const List<String> months = <String>[
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[local.month - 1]} ${local.year}';
  }
}

/// Builds the journey from the records the device holds.
///
/// The events are ordered newest first, because a clinician opening a journey
/// is usually asking about the most recent event first, and the older history
/// is the context for it.
PatientTimeline buildPatientTimeline({
  List<ClinicalEncounter> encounters = const <ClinicalEncounter>[],
  List<Appointment> appointments = const <Appointment>[],
  List<LabOrder> labOrders = const <LabOrder>[],
  List<Prescription> prescriptions = const <Prescription>[],
  List<Discharge> discharges = const <Discharge>[],
  List<OtBooking> surgeries = const <OtBooking>[],
}) {
  final List<TimelineEvent> events = <TimelineEvent>[
    ...timelineEventsFromEncounters(encounters),
    ...timelineEventsFromAppointments(appointments),
    ...timelineEventsFromLabOrders(labOrders),
    ...timelineEventsFromPrescriptions(prescriptions),
    ...timelineEventsFromDischarges(discharges),
    ...timelineEventsFromSurgeries(surgeries),
  ];
  events.sort((TimelineEvent a, TimelineEvent b) => b.at.compareTo(a.at));
  return PatientTimeline(events: List<TimelineEvent>.unmodifiable(events));
}

/// Turns encounters into journey events.
List<TimelineEvent> timelineEventsFromEncounters(
  List<ClinicalEncounter> encounters,
) => <TimelineEvent>[
  for (final ClinicalEncounter encounter in encounters)
    TimelineEvent(
      id: 'encounter-${encounter.id}',
      kind: _encounterKind(encounter.encounterType),
      at: encounter.createdAt ?? encounter.signedAt ?? DateTime.now().toUtc(),
      title: _encounterKind(encounter.encounterType).label,
      detail: encounter.diagnoses.isEmpty
          ? null
          : encounter.diagnoses
                .map((EncounterDiagnosis d) => d.description)
                .where((String description) => description.isNotEmpty)
                .join(', '),
      sourceId: encounter.id,
    ),
];

TimelineEventKind _encounterKind(EncounterType type) => switch (type) {
  EncounterType.outpatient => TimelineEventKind.outpatientVisit,
  EncounterType.inpatient => TimelineEventKind.admission,
  EncounterType.emergency => TimelineEventKind.emergency,
  EncounterType.telehealth => TimelineEventKind.telehealth,
};

/// Turns appointments into journey events.
///
/// A cancelled visit is not part of the journey: it never happened, and a
/// line that says so would read as a visit.
List<TimelineEvent> timelineEventsFromAppointments(
  List<Appointment> appointments,
) => <TimelineEvent>[
  for (final Appointment appointment in appointments)
    if (appointment.status != AppointmentStatus.cancelled)
      TimelineEvent(
        id: 'appointment-${appointment.id}',
        kind: TimelineEventKind.outpatientVisit,
        at:
            appointment.completedAt ??
            appointment.startedAt ??
            appointment.checkedInAt ??
            appointment.scheduledStart,
        title: 'Outpatient visit',
        detail: appointment.reason,
        sourceId: appointment.id,
        priority: appointment.priority.wireValue,
      ),
];

/// Turns laboratory orders into journey events.
List<TimelineEvent> timelineEventsFromLabOrders(List<LabOrder> orders) =>
    <TimelineEvent>[
      for (final LabOrder order in orders)
        if (order.status != LabOrderStatus.cancelled)
          TimelineEvent(
            id: 'lab-order-${order.id}',
            kind: TimelineEventKind.labOrder,
            at: order.orderedAt,
            title: 'Laboratory order · ${order.orderCode}',
            detail: order.clinicalIndication,
            sourceId: order.id,
            priority: order.priority.wireValue,
          ),
    ];

/// Turns prescriptions into journey events.
List<TimelineEvent> timelineEventsFromPrescriptions(
  List<Prescription> prescriptions,
) => <TimelineEvent>[
  for (final Prescription prescription in prescriptions)
    TimelineEvent(
      id: 'prescription-${prescription.id}',
      kind: TimelineEventKind.prescription,
      at: prescription.createdAt,
      title: 'Prescription · ${prescription.prescriptionCode}',
      detail: prescription.indication,
      sourceId: prescription.id,
    ),
];

/// Turns discharges into journey events.
List<TimelineEvent> timelineEventsFromDischarges(List<Discharge> discharges) =>
    <TimelineEvent>[
      for (final Discharge discharge in discharges)
        TimelineEvent(
          id: 'discharge-${discharge.id}',
          kind: TimelineEventKind.discharge,
          at: discharge.createdAt,
          title: 'Discharge · ${discharge.dischargeType.wireValue}',
          detail: discharge.summary,
          sourceId: discharge.id,
        ),
    ];

/// Turns theatre bookings into journey events.
List<TimelineEvent> timelineEventsFromSurgeries(List<OtBooking> bookings) =>
    <TimelineEvent>[
      for (final OtBooking booking in bookings)
        TimelineEvent(
          id: 'surgery-${booking.id}',
          kind: TimelineEventKind.surgery,
          at: booking.scheduledStart,
          title: 'Surgery · ${booking.procedureName}',
          detail: booking.theatreRoom,
          sourceId: booking.id,
        ),
    ];
