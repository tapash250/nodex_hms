/// Fleet & ambulance dispatch entities (Module 27).
///
/// Specification scope: "Vehicles, GPS, dispatch, driver rosters, emergency
/// transit."
///
/// This is the hospital's operational reach — the vehicles that move a patient
/// to definitive care. It is a distinct domain from the ward roster (Module 09
/// `staff_shifts`): a crew is assigned to a *vehicle* for a duty window, and the
/// vehicle, not the ward, is the scheduled resource.
///
/// Four records, mirroring the four moving parts: the [Ambulance] registry, the
/// [AmbulanceDuty] driver roster, the [AmbulanceDispatch] transit job (a guarded
/// state machine), and the append-only [TrackingPing] last-known position. The
/// ping is deliberately coarse: a device buffers it and it syncs when the
/// network returns, so it answers "where was the vehicle last seen" without
/// pretending to be a live GPS feed.
// ignore_for_file: sort_constructors_first
library;

import 'package:meta/meta.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';

/// The capability class of a vehicle.
enum VehicleType {
  /// Advanced life support.
  als('als'),

  /// Basic life support.
  bls('bls'),

  /// Non-urgent patient transport.
  patientTransport('patient_transport'),

  /// Neonatal transport.
  neonatal('neonatal'),

  /// Air ambulance.
  air('air'),

  /// Anything else.
  other('other');

  const VehicleType(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    VehicleType.als => 'Advanced life support',
    VehicleType.bls => 'Basic life support',
    VehicleType.patientTransport => 'Patient transport',
    VehicleType.neonatal => 'Neonatal',
    VehicleType.air => 'Air ambulance',
    VehicleType.other => 'Other',
  };

  /// Parses a stored value.
  static VehicleType fromWire(String value) => VehicleType.values.firstWhere(
    (VehicleType type) => type.wireValue == value,
    orElse: () => VehicleType.other,
  );
}

/// Registry status of a vehicle.
enum AmbulanceServiceStatus {
  /// On the road or ready to be dispatched.
  inService('in_service'),

  /// Temporarily off the road for maintenance.
  maintenance('maintenance'),

  /// Withdrawn from service.
  outOfService('out_of_service'),

  /// Retired; retained as a historical record and frozen.
  archived('archived');

  const AmbulanceServiceStatus(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    AmbulanceServiceStatus.inService => 'In service',
    AmbulanceServiceStatus.maintenance => 'Maintenance',
    AmbulanceServiceStatus.outOfService => 'Out of service',
    AmbulanceServiceStatus.archived => 'Archived',
  };

  /// Parses a stored value.
  static AmbulanceServiceStatus fromWire(String value) =>
      AmbulanceServiceStatus.values.firstWhere(
        (AmbulanceServiceStatus status) => status.wireValue == value,
        orElse: () => AmbulanceServiceStatus.inService,
      );

  /// Whether the vehicle is archived and therefore frozen.
  bool get isArchived => this == AmbulanceServiceStatus.archived;
}

/// Lifecycle status of a duty assignment.
enum DutyStatus {
  /// Booked for a future window.
  scheduled('scheduled'),

  /// On duty now.
  active('active'),

  /// Finished; retained and frozen.
  completed('completed'),

  /// Called off; retained and frozen.
  cancelled('cancelled');

  const DutyStatus(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Parses a stored value.
  static DutyStatus fromWire(String value) => DutyStatus.values.firstWhere(
    (DutyStatus status) => status.wireValue == value,
    orElse: () => DutyStatus.scheduled,
  );

  /// Whether the duty is closed and therefore frozen.
  bool get isTerminal =>
      this == DutyStatus.completed || this == DutyStatus.cancelled;

  /// Whether the duty occupies the vehicle and driver in its window.
  bool get occupiesResource =>
      this == DutyStatus.scheduled || this == DutyStatus.active;
}

/// Priority of a dispatch.
enum DispatchPriority {
  /// Lights-and-sirens emergency.
  emergency('emergency'),

  /// Time-sensitive but not immediately life-threatening.
  urgent('urgent'),

  /// Planned transport.
  routine('routine');

  const DispatchPriority(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    DispatchPriority.emergency => 'Emergency',
    DispatchPriority.urgent => 'Urgent',
    DispatchPriority.routine => 'Routine',
  };

  /// Parses a stored value.
  static DispatchPriority fromWire(String value) =>
      DispatchPriority.values.firstWhere(
        (DispatchPriority priority) => priority.wireValue == value,
        orElse: () => DispatchPriority.emergency,
      );
}

/// The transit state machine's states.
enum DispatchStatus {
  /// Raised, no vehicle yet.
  requested('requested'),

  /// A vehicle and crew are committed.
  assigned('assigned'),

  /// The vehicle is travelling to the scene.
  enRoute('en_route'),

  /// The crew is with the patient.
  onScene('on_scene'),

  /// Delivered; retained and frozen.
  completed('completed'),

  /// Called off; retained and frozen.
  cancelled('cancelled');

  const DispatchStatus(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    DispatchStatus.requested => 'Requested',
    DispatchStatus.assigned => 'Assigned',
    DispatchStatus.enRoute => 'En route',
    DispatchStatus.onScene => 'On scene',
    DispatchStatus.completed => 'Completed',
    DispatchStatus.cancelled => 'Cancelled',
  };

  /// Parses a stored value.
  static DispatchStatus fromWire(String value) =>
      DispatchStatus.values.firstWhere(
        (DispatchStatus status) => status.wireValue == value,
        orElse: () => DispatchStatus.requested,
      );

  /// Whether the dispatch is closed and therefore frozen.
  bool get isTerminal =>
      this == DispatchStatus.completed || this == DispatchStatus.cancelled;

  /// Whether the dispatch is live and awaiting progress.
  bool get isLive => !isTerminal;
}

/// Whether a dispatch may move from [from] to [to].
///
/// The transit moves one stage at a time — `requested -> assigned -> en_route
/// -> on_scene -> completed` — and may be cancelled from any live stage. It may
/// never skip a stage. This is the same rule the database enforces.
bool dispatchCanAdvance(DispatchStatus from, DispatchStatus to) {
  if (from.isTerminal || from == to) {
    return false;
  }
  if (to == DispatchStatus.cancelled) {
    return true;
  }
  return switch (from) {
    DispatchStatus.requested => to == DispatchStatus.assigned,
    DispatchStatus.assigned => to == DispatchStatus.enRoute,
    DispatchStatus.enRoute => to == DispatchStatus.onScene,
    DispatchStatus.onScene => to == DispatchStatus.completed,
    DispatchStatus.completed || DispatchStatus.cancelled => false,
  };
}

/// Whether two half-open duty windows `[aStart, aEnd)` and `[bStart, bEnd)`
/// overlap.
bool dutyWindowsOverlap({
  required DateTime aStart,
  required DateTime aEnd,
  required DateTime bStart,
  required DateTime bEnd,
}) => aStart.isBefore(bEnd) && bStart.isBefore(aEnd);

/// A vehicle in the fleet registry.
@immutable
final class Ambulance {
  /// Creates a vehicle.
  const Ambulance({
    required this.id,
    required this.tenantId,
    required this.facilityId,
    required this.callSign,
    required this.vehicleType,
    required this.capacity,
    required this.serviceStatus,
    required this.createdBy,
    required this.updatedAt,
    this.registrationNo,
    this.capabilityNotes,
    this.createdAt,
  });

  /// Validates and builds a new vehicle row.
  static Map<String, Object?> registerRow({
    required String tenantId,
    required String createdBy,
    required String facilityId,
    required String callSign,
    VehicleType vehicleType = VehicleType.bls,
    int capacity = 1,
    String? registrationNo,
    String? capabilityNotes,
    AmbulanceServiceStatus serviceStatus = AmbulanceServiceStatus.inService,
    String ambulanceId = '',
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (createdBy.isEmpty) {
      fieldErrors['created_by'] = 'Creator is required.';
    }
    if (facilityId.isEmpty) {
      fieldErrors['facility_id'] = 'A base facility is required.';
    }
    if (callSign.trim().isEmpty) {
      fieldErrors['call_sign'] = 'A call sign is required.';
    }
    if (capacity < 0 || capacity > 12) {
      fieldErrors['capacity'] = 'Expected a capacity between 0 and 12.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Vehicle entry failed validation.',
        fieldErrors: fieldErrors,
        code: 'ambulance_invalid',
      );
    }
    final String now = DateTime.now().toUtc().toIso8601String();
    return <String, Object?>{
      if (ambulanceId.isNotEmpty) 'id': ambulanceId,
      'tenant_id': tenantId,
      'facility_id': facilityId,
      'call_sign': callSign.trim(),
      'registration_no': _trimmed(registrationNo),
      'vehicle_type': vehicleType.wireValue,
      'capacity': capacity,
      'capability_notes': _trimmed(capabilityNotes),
      'service_status': serviceStatus.wireValue,
      'created_by': createdBy,
      'created_at': now,
      'updated_at': now,
    };
  }

  /// Materializes a vehicle from a local row.
  factory Ambulance.fromRow(Map<String, Object?> row) => Ambulance(
    id: row['id']! as String,
    tenantId: row['tenant_id']! as String,
    facilityId: row['facility_id']! as String,
    callSign: row['call_sign']! as String,
    vehicleType: VehicleType.fromWire(
      (row['vehicle_type'] as String?) ?? VehicleType.bls.wireValue,
    ),
    capacity: _asInt(row['capacity']),
    serviceStatus: AmbulanceServiceStatus.fromWire(
      (row['service_status'] as String?) ??
          AmbulanceServiceStatus.inService.wireValue,
    ),
    createdBy: row['created_by']! as String,
    updatedAt: _parse(row['updated_at']),
    registrationNo: row['registration_no'] as String?,
    capabilityNotes: row['capability_notes'] as String?,
    createdAt: _parseNullable(row['created_at']),
  );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// Facility the vehicle is stationed at.
  final String facilityId;

  /// Call sign.
  final String callSign;

  /// Registration number, when recorded.
  final String? registrationNo;

  /// Vehicle capability class.
  final VehicleType vehicleType;

  /// Seat/stretcher capacity.
  final int capacity;

  /// Capability notes.
  final String? capabilityNotes;

  /// Registry status.
  final AmbulanceServiceStatus serviceStatus;

  /// Who registered the vehicle.
  final String createdBy;

  /// Last change, UTC.
  final DateTime updatedAt;

  /// When the vehicle was registered, UTC.
  final DateTime? createdAt;

  /// Whether the vehicle may be edited or archived.
  bool get isEditable => !serviceStatus.isArchived;
}

/// The full editable change set for a vehicle.
Map<String, Object?> ambulanceChanges({
  required String facilityId,
  required String callSign,
  VehicleType? vehicleType,
  int? capacity,
  String? registrationNo,
  String? capabilityNotes,
  AmbulanceServiceStatus? serviceStatus,
}) => <String, Object?>{
  'facility_id': facilityId,
  'call_sign': callSign.trim(),
  'registration_no': _trimmed(registrationNo),
  if (vehicleType != null) 'vehicle_type': vehicleType.wireValue,
  'capacity': ?capacity,
  'capability_notes': _trimmed(capabilityNotes),
  if (serviceStatus != null) 'service_status': serviceStatus.wireValue,
  'updated_at': DateTime.now().toUtc().toIso8601String(),
};

/// The change set for archiving a vehicle. The row is retained and frozen.
Map<String, Object?> ambulanceArchiveChanges() => <String, Object?>{
  'service_status': AmbulanceServiceStatus.archived.wireValue,
  'updated_at': DateTime.now().toUtc().toIso8601String(),
};

/// A driver (and optional attendant) assigned to a vehicle for a window.
@immutable
final class AmbulanceDuty {
  /// Creates a duty assignment.
  const AmbulanceDuty({
    required this.id,
    required this.tenantId,
    required this.ambulanceId,
    required this.driverUserId,
    required this.startsAt,
    required this.endsAt,
    required this.status,
    required this.createdBy,
    required this.updatedAt,
    this.attendantUserId,
    this.notes,
    this.createdAt,
  });

  /// Validates and builds a new duty row.
  static Map<String, Object?> registerRow({
    required String tenantId,
    required String createdBy,
    required String ambulanceId,
    required String driverUserId,
    required DateTime startsAt,
    required DateTime endsAt,
    String? attendantUserId,
    String? notes,
    DutyStatus status = DutyStatus.scheduled,
    String dutyId = '',
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (createdBy.isEmpty) {
      fieldErrors['created_by'] = 'Creator is required.';
    }
    if (ambulanceId.isEmpty) {
      fieldErrors['ambulance_id'] = 'A vehicle is required.';
    }
    if (driverUserId.isEmpty) {
      fieldErrors['driver_user_id'] = 'A driver is required.';
    }
    if (!endsAt.isAfter(startsAt)) {
      fieldErrors['ends_at'] = 'Must end after it starts.';
    }
    if (attendantUserId != null &&
        attendantUserId.isNotEmpty &&
        attendantUserId == driverUserId) {
      fieldErrors['attendant_user_id'] = 'Must differ from the driver.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Duty assignment failed validation.',
        fieldErrors: fieldErrors,
        code: 'ambulance_duty_invalid',
      );
    }
    final String now = DateTime.now().toUtc().toIso8601String();
    return <String, Object?>{
      if (dutyId.isNotEmpty) 'id': dutyId,
      'tenant_id': tenantId,
      'ambulance_id': ambulanceId,
      'driver_user_id': driverUserId,
      'attendant_user_id': _trimmed(attendantUserId),
      'starts_at': startsAt.toUtc().toIso8601String(),
      'ends_at': endsAt.toUtc().toIso8601String(),
      'status': status.wireValue,
      'notes': _trimmed(notes),
      'created_by': createdBy,
      'created_at': now,
      'updated_at': now,
    };
  }

  /// Materializes a duty from a local row.
  factory AmbulanceDuty.fromRow(Map<String, Object?> row) => AmbulanceDuty(
    id: row['id']! as String,
    tenantId: row['tenant_id']! as String,
    ambulanceId: row['ambulance_id']! as String,
    driverUserId: row['driver_user_id']! as String,
    startsAt: DateTime.parse(row['starts_at']! as String).toUtc(),
    endsAt: DateTime.parse(row['ends_at']! as String).toUtc(),
    status: DutyStatus.fromWire(
      (row['status'] as String?) ?? DutyStatus.scheduled.wireValue,
    ),
    createdBy: row['created_by']! as String,
    updatedAt: _parse(row['updated_at']),
    attendantUserId: row['attendant_user_id'] as String?,
    notes: row['notes'] as String?,
    createdAt: _parseNullable(row['created_at']),
  );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// Vehicle assigned.
  final String ambulanceId;

  /// Driver assigned.
  final String driverUserId;

  /// Attendant assigned, when any.
  final String? attendantUserId;

  /// Cover start, UTC.
  final DateTime startsAt;

  /// Cover end, UTC.
  final DateTime endsAt;

  /// Lifecycle status.
  final DutyStatus status;

  /// Free-text note.
  final String? notes;

  /// Who booked the duty.
  final String createdBy;

  /// Last change, UTC.
  final DateTime updatedAt;

  /// When the duty was booked, UTC.
  final DateTime? createdAt;

  /// Whether the duty may be edited or closed.
  bool get isOpen => !status.isTerminal;
}

/// The full editable change set for a duty assignment.
Map<String, Object?> ambulanceDutyChanges({
  required String ambulanceId,
  required String driverUserId,
  required DateTime startsAt,
  required DateTime endsAt,
  String? attendantUserId,
  String? notes,
  DutyStatus? status,
}) => <String, Object?>{
  'ambulance_id': ambulanceId,
  'driver_user_id': driverUserId,
  'attendant_user_id': _trimmed(attendantUserId),
  'starts_at': startsAt.toUtc().toIso8601String(),
  'ends_at': endsAt.toUtc().toIso8601String(),
  'notes': _trimmed(notes),
  if (status != null) 'status': status.wireValue,
  'updated_at': DateTime.now().toUtc().toIso8601String(),
};

/// An emergency transit job.
@immutable
final class AmbulanceDispatch {
  /// Creates a dispatch.
  const AmbulanceDispatch({
    required this.id,
    required this.tenantId,
    required this.facilityId,
    required this.priority,
    required this.status,
    required this.pickupAddress,
    required this.requestedAt,
    required this.createdBy,
    required this.updatedAt,
    this.ambulanceId,
    this.dutyAssignmentId,
    this.driverUserId,
    this.patientId,
    this.patientNameText,
    this.requestingReference,
    this.destinationAddress,
    this.destinationFacility,
    this.dispatchedAt,
    this.onSceneAt,
    this.completedAt,
    this.cancellationReason,
    this.notes,
    this.createdAt,
  });

  /// Validates and builds a new dispatch row.
  static Map<String, Object?> registerRow({
    required String tenantId,
    required String createdBy,
    required String facilityId,
    required String pickupAddress,
    DispatchPriority priority = DispatchPriority.emergency,
    String? patientId,
    String? patientNameText,
    String? requestingReference,
    String? destinationAddress,
    String? destinationFacility,
    String? notes,
    String dispatchId = '',
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (createdBy.isEmpty) {
      fieldErrors['created_by'] = 'Creator is required.';
    }
    if (facilityId.isEmpty) {
      fieldErrors['facility_id'] = 'A facility is required.';
    }
    if (pickupAddress.trim().isEmpty) {
      fieldErrors['pickup_address'] = 'A pickup address is required.';
    }
    if ((patientId == null || patientId.isEmpty) &&
        (patientNameText == null || patientNameText.trim().isEmpty)) {
      fieldErrors['patient'] = 'Name a patient or take a name in the field.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Dispatch failed validation.',
        fieldErrors: fieldErrors,
        code: 'ambulance_dispatch_invalid',
      );
    }
    final String now = DateTime.now().toUtc().toIso8601String();
    return <String, Object?>{
      if (dispatchId.isNotEmpty) 'id': dispatchId,
      'tenant_id': tenantId,
      'facility_id': facilityId,
      'patient_id': _trimmed(patientId),
      'patient_name_text': _trimmed(patientNameText),
      'priority': priority.wireValue,
      'status': DispatchStatus.requested.wireValue,
      'requesting_reference': _trimmed(requestingReference),
      'pickup_address': pickupAddress.trim(),
      'destination_address': _trimmed(destinationAddress),
      'destination_facility': _trimmed(destinationFacility),
      'requested_at': now,
      'notes': _trimmed(notes),
      'created_by': createdBy,
      'created_at': now,
      'updated_at': now,
    };
  }

  /// Materializes a dispatch from a local row.
  factory AmbulanceDispatch.fromRow(Map<String, Object?> row) =>
      AmbulanceDispatch(
        id: row['id']! as String,
        tenantId: row['tenant_id']! as String,
        facilityId: row['facility_id']! as String,
        priority: DispatchPriority.fromWire(
          (row['priority'] as String?) ?? DispatchPriority.emergency.wireValue,
        ),
        status: DispatchStatus.fromWire(
          (row['status'] as String?) ?? DispatchStatus.requested.wireValue,
        ),
        pickupAddress: row['pickup_address']! as String,
        requestedAt: _parse(row['requested_at']),
        createdBy: row['created_by']! as String,
        updatedAt: _parse(row['updated_at']),
        ambulanceId: row['ambulance_id'] as String?,
        dutyAssignmentId: row['duty_assignment_id'] as String?,
        driverUserId: row['driver_user_id'] as String?,
        patientId: row['patient_id'] as String?,
        patientNameText: row['patient_name_text'] as String?,
        requestingReference: row['requesting_reference'] as String?,
        destinationAddress: row['destination_address'] as String?,
        destinationFacility: row['destination_facility'] as String?,
        dispatchedAt: _parseNullable(row['dispatched_at']),
        onSceneAt: _parseNullable(row['on_scene_at']),
        completedAt: _parseNullable(row['completed_at']),
        cancellationReason: row['cancellation_reason'] as String?,
        notes: row['notes'] as String?,
        createdAt: _parseNullable(row['created_at']),
      );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// Facility raising the dispatch.
  final String facilityId;

  /// Responding vehicle, once assigned.
  final String? ambulanceId;

  /// Duty assignment the crew came from, when any.
  final String? dutyAssignmentId;

  /// Driver, once known.
  final String? driverUserId;

  /// Registered patient, when known.
  final String? patientId;

  /// Field name for an unidentified patient.
  final String? patientNameText;

  /// Priority.
  final DispatchPriority priority;

  /// Transit stage.
  final DispatchStatus status;

  /// Who or what requested the dispatch.
  final String? requestingReference;

  /// Pickup address.
  final String pickupAddress;

  /// Destination address.
  final String? destinationAddress;

  /// Destination facility.
  final String? destinationFacility;

  /// When raised, UTC.
  final DateTime requestedAt;

  /// When committed to a vehicle, UTC.
  final DateTime? dispatchedAt;

  /// When the crew reached the scene, UTC.
  final DateTime? onSceneAt;

  /// When the transit completed, UTC.
  final DateTime? completedAt;

  /// Why it was cancelled.
  final String? cancellationReason;

  /// Free-text note.
  final String? notes;

  /// Who raised the dispatch.
  final String createdBy;

  /// Last change, UTC.
  final DateTime updatedAt;

  /// When the dispatch was created, UTC.
  final DateTime? createdAt;

  /// Whether the dispatch may still be progressed.
  bool get isLive => !status.isTerminal;

  /// The name to show: the registered patient's identity is resolved by the
  /// caller; this is the field name when the patient is unidentified.
  String get displayName => patientNameText ?? 'Registered patient';
}

/// The transition change set for a dispatch.
///
/// Sets the new status, stamps the stage timestamp the new status implies at
/// the supplied time (or now), and carries the vehicle and driver when a job is
/// assigned.
Map<String, Object?> dispatchTransitionChanges({
  required DispatchStatus to,
  String? ambulanceId,
  String? driverUserId,
  DateTime? at,
  String? cancellationReason,
}) {
  final String now = (at ?? DateTime.now().toUtc()).toUtc().toIso8601String();
  return <String, Object?>{
    'status': to.wireValue,
    'ambulance_id': ?ambulanceId,
    'driver_user_id': ?driverUserId,
    if (to == DispatchStatus.assigned) 'dispatched_at': now,
    if (to == DispatchStatus.onScene) 'on_scene_at': now,
    if (to == DispatchStatus.completed) 'completed_at': now,
    if (to == DispatchStatus.cancelled)
      'cancellation_reason': _trimmed(cancellationReason),
    'updated_at': now,
  };
}

/// A coarse last-known position.
@immutable
final class TrackingPing {
  /// Creates a ping.
  const TrackingPing({
    required this.id,
    required this.tenantId,
    required this.ambulanceId,
    required this.latitude,
    required this.longitude,
    required this.recordedAt,
    required this.source,
    required this.createdAt,
    this.dispatchId,
    this.speedKph,
  });

  /// Validates and builds a new ping row.
  static Map<String, Object?> registerRow({
    required String tenantId,
    required String ambulanceId,
    required double latitude,
    required double longitude,
    DateTime? recordedAt,
    String? dispatchId,
    double? speedKph,
    String source = 'device',
    String pingId = '',
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (ambulanceId.isEmpty) {
      fieldErrors['ambulance_id'] = 'A vehicle is required.';
    }
    if (latitude < -90 || latitude > 90) {
      fieldErrors['latitude'] = 'Expected a latitude between -90 and 90.';
    }
    if (longitude < -180 || longitude > 180) {
      fieldErrors['longitude'] = 'Expected a longitude between -180 and 180.';
    }
    if (source != 'device' && source != 'manual') {
      fieldErrors['source'] = "Expected 'device' or 'manual'.";
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Tracking ping failed validation.',
        fieldErrors: fieldErrors,
        code: 'tracking_ping_invalid',
      );
    }
    final DateTime when = (recordedAt ?? DateTime.now().toUtc()).toUtc();
    return <String, Object?>{
      if (pingId.isNotEmpty) 'id': pingId,
      'tenant_id': tenantId,
      'ambulance_id': ambulanceId,
      'dispatch_id': _trimmed(dispatchId),
      'latitude': latitude,
      'longitude': longitude,
      'speed_kph': speedKph,
      'recorded_at': when.toIso8601String(),
      'source': source,
      'created_at': when.toIso8601String(),
    };
  }

  /// Materializes a ping from a local row.
  factory TrackingPing.fromRow(Map<String, Object?> row) => TrackingPing(
    id: row['id']! as String,
    tenantId: row['tenant_id']! as String,
    ambulanceId: row['ambulance_id']! as String,
    latitude: _asDouble(row['latitude']),
    longitude: _asDouble(row['longitude']),
    recordedAt: _parse(row['recorded_at']),
    source: (row['source'] as String?) ?? 'device',
    createdAt: _parse(row['created_at']),
    dispatchId: row['dispatch_id'] as String?,
    speedKph: row['speed_kph'] == null ? null : _asDouble(row['speed_kph']),
  );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// Vehicle seen.
  final String ambulanceId;

  /// Related dispatch, when any.
  final String? dispatchId;

  /// Latitude.
  final double latitude;

  /// Longitude.
  final double longitude;

  /// Speed, when reported.
  final double? speedKph;

  /// When the position was observed, UTC.
  final DateTime recordedAt;

  /// `device` or `manual`.
  final String source;

  /// When the ping was recorded locally, UTC.
  final DateTime createdAt;
}

String? _trimmed(String? value) {
  final String? trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

DateTime _parse(Object? value) => value is String
    ? DateTime.parse(value).toUtc()
    : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

DateTime? _parseNullable(Object? value) =>
    value is String ? DateTime.parse(value).toUtc() : null;

int _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.parse(value);
  }
  return 0;
}

double _asDouble(Object? value) {
  if (value is double) {
    return value;
  }
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.parse(value);
  }
  return 0;
}
