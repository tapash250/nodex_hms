/// Fleet & ambulance dispatch use cases (Module 27).
library;

import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/fleet/fleet.dart';
import 'package:nodex_hms/domain/fleet/fleet_repository.dart';

/// Registers a vehicle into the fleet.
final class RegisterAmbulanceUseCase {
  /// Creates the use case.
  RegisterAmbulanceUseCase({required this._repository});

  final FleetRepository _repository;

  Future<String> call({
    required AuthorizationPolicy policy,
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
  }) async {
    policy.require(NodexPermissions.fleetManage);
    return _repository.registerAmbulance(
      Ambulance.registerRow(
        tenantId: tenantId,
        createdBy: createdBy,
        facilityId: facilityId,
        callSign: callSign,
        vehicleType: vehicleType,
        capacity: capacity,
        registrationNo: registrationNo,
        capabilityNotes: capabilityNotes,
        serviceStatus: serviceStatus,
        ambulanceId: ambulanceId,
      ),
    );
  }
}

/// Updates a vehicle. An archived vehicle is a retained, frozen record.
final class UpdateAmbulanceUseCase {
  /// Creates the use case.
  UpdateAmbulanceUseCase({required this._repository});

  final FleetRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required Ambulance ambulance,
    required String facilityId,
    required String callSign,
    VehicleType? vehicleType,
    int? capacity,
    String? registrationNo,
    String? capabilityNotes,
    AmbulanceServiceStatus? serviceStatus,
  }) async {
    policy.require(NodexPermissions.fleetManage);
    if (!ambulance.isEditable) {
      throw const AuthorizationError(
        message:
            'An archived vehicle is retained as a historical record and '
            'cannot be edited.',
        code: 'ambulance_archived_immutable',
      );
    }
    await _repository.updateAmbulance(
      ambulance.id,
      ambulanceChanges(
        facilityId: facilityId,
        callSign: callSign,
        vehicleType: vehicleType,
        capacity: capacity,
        registrationNo: registrationNo,
        capabilityNotes: capabilityNotes,
        serviceStatus: serviceStatus,
      ),
    );
  }
}

/// Archives a vehicle. The row is retained because dispatches name it.
final class ArchiveAmbulanceUseCase {
  /// Creates the use case.
  ArchiveAmbulanceUseCase({required this._repository});

  final FleetRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required Ambulance ambulance,
  }) async {
    policy.require(NodexPermissions.fleetManage);
    if (ambulance.serviceStatus.isArchived) {
      throw const AuthorizationError(
        message: 'This vehicle is already archived.',
        code: 'ambulance_already_archived',
      );
    }
    await _repository.updateAmbulance(ambulance.id, ambulanceArchiveChanges());
  }
}

/// Books a driver onto a vehicle for a window.
///
/// The database forbids overlapping live duties for a vehicle or a driver; this
/// checks the same rule against the rows already on the device so the dispatcher
/// gets an immediate answer offline instead of a server rejection later.
final class ScheduleDutyUseCase {
  /// Creates the use case.
  ScheduleDutyUseCase({required this._repository});

  final FleetRepository _repository;

  Future<String> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String createdBy,
    required String ambulanceId,
    required String driverUserId,
    required DateTime startsAt,
    required DateTime endsAt,
    String? attendantUserId,
    String? notes,
    String dutyId = '',
  }) async {
    policy.require(NodexPermissions.fleetManage);
    final Map<String, Object?> row = AmbulanceDuty.registerRow(
      tenantId: tenantId,
      createdBy: createdBy,
      ambulanceId: ambulanceId,
      driverUserId: driverUserId,
      startsAt: startsAt,
      endsAt: endsAt,
      attendantUserId: attendantUserId,
      notes: notes,
      dutyId: dutyId,
    );
    final List<AmbulanceDuty> existing = await _repository.listDuties(tenantId);
    for (final AmbulanceDuty duty in existing) {
      if (!duty.status.occupiesResource) {
        continue;
      }
      final bool overlaps = dutyWindowsOverlap(
        aStart: duty.startsAt,
        aEnd: duty.endsAt,
        bStart: startsAt,
        bEnd: endsAt,
      );
      if (!overlaps) {
        continue;
      }
      if (duty.ambulanceId == ambulanceId) {
        throw const ValidationError(
          message: 'Duty assignment failed validation.',
          fieldErrors: <String, String>{
            'starts_at': 'This vehicle already has a duty in that window.',
          },
          code: 'ambulance_duty_overlap',
        );
      }
      if (duty.driverUserId == driverUserId) {
        throw const ValidationError(
          message: 'Duty assignment failed validation.',
          fieldErrors: <String, String>{
            'driver_user_id': 'This driver already has a duty in that window.',
          },
          code: 'ambulance_duty_overlap',
        );
      }
    }
    return _repository.registerDuty(row);
  }
}

/// Closes an open duty assignment. A closed duty is frozen.
final class CloseDutyUseCase {
  /// Creates the use case.
  CloseDutyUseCase({required this._repository});

  final FleetRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required AmbulanceDuty duty,
    required DutyStatus status,
  }) async {
    policy.require(NodexPermissions.fleetManage);
    if (!status.isTerminal) {
      throw const ValidationError(
        message: 'Duty assignment failed validation.',
        fieldErrors: <String, String>{
          'status': 'A duty is closed as completed or cancelled.',
        },
        code: 'ambulance_duty_close_invalid',
      );
    }
    if (!duty.isOpen) {
      throw const AuthorizationError(
        message: 'This duty assignment is already closed.',
        code: 'ambulance_duty_already_closed',
      );
    }
    await _repository.updateDuty(duty.id, <String, Object?>{
      'status': status.wireValue,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }
}

/// Raises an emergency transit job.
final class RaiseDispatchUseCase {
  /// Creates the use case.
  RaiseDispatchUseCase({required this._repository});

  final FleetRepository _repository;

  Future<String> call({
    required AuthorizationPolicy policy,
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
  }) async {
    policy.require(NodexPermissions.fleetDispatch);
    return _repository.createDispatch(
      AmbulanceDispatch.registerRow(
        tenantId: tenantId,
        createdBy: createdBy,
        facilityId: facilityId,
        pickupAddress: pickupAddress,
        priority: priority,
        patientId: patientId,
        patientNameText: patientNameText,
        requestingReference: requestingReference,
        destinationAddress: destinationAddress,
        destinationFacility: destinationFacility,
        notes: notes,
        dispatchId: dispatchId,
      ),
    );
  }
}

/// Advances a dispatch one stage. The stage order is the same rule the database
/// enforces.
final class AdvanceDispatchUseCase {
  /// Creates the use case.
  AdvanceDispatchUseCase({required this._repository});

  final FleetRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required AmbulanceDispatch dispatch,
    required DispatchStatus to,
    String? ambulanceId,
    String? driverUserId,
  }) async {
    policy.require(NodexPermissions.fleetDispatch);
    if (!dispatchCanAdvance(dispatch.status, to)) {
      throw ValidationError(
        message: 'Dispatch failed validation.',
        fieldErrors: <String, String>{
          'status':
              'A ${dispatch.status.label.toLowerCase()} dispatch cannot move '
              'to ${to.label.toLowerCase()}.',
        },
        code: 'ambulance_dispatch_transition_invalid',
      );
    }
    if (to != DispatchStatus.cancelled &&
        ambulanceId == null &&
        dispatch.ambulanceId == null) {
      throw const ValidationError(
        message: 'Dispatch failed validation.',
        fieldErrors: <String, String>{
          'ambulance_id': 'Assign a vehicle before progressing the dispatch.',
        },
        code: 'ambulance_dispatch_unassigned',
      );
    }
    await _repository.updateDispatch(
      dispatch.id,
      dispatchTransitionChanges(
        to: to,
        ambulanceId: ambulanceId ?? dispatch.ambulanceId,
        driverUserId: driverUserId ?? dispatch.driverUserId,
      ),
    );
  }
}

/// Cancels a live dispatch. The row is retained because an incident review names
/// it.
final class CancelDispatchUseCase {
  /// Creates the use case.
  CancelDispatchUseCase({required this._repository});

  final FleetRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required AmbulanceDispatch dispatch,
    String? reason,
  }) async {
    policy.require(NodexPermissions.fleetDispatch);
    if (!dispatch.isLive) {
      throw const AuthorizationError(
        message: 'This dispatch is already closed.',
        code: 'ambulance_dispatch_already_closed',
      );
    }
    await _repository.updateDispatch(
      dispatch.id,
      dispatchTransitionChanges(
        to: DispatchStatus.cancelled,
        cancellationReason: reason,
      ),
    );
  }
}

/// Records a coarse last-known position ping.
final class RecordPingUseCase {
  /// Creates the use case.
  RecordPingUseCase({required this._repository});

  final FleetRepository _repository;

  Future<String> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String ambulanceId,
    required double latitude,
    required double longitude,
    String? dispatchId,
    double? speedKph,
    String source = 'device',
    DateTime? recordedAt,
    String pingId = '',
  }) async {
    policy.require(NodexPermissions.fleetDispatch);
    return _repository.registerPing(
      TrackingPing.registerRow(
        tenantId: tenantId,
        ambulanceId: ambulanceId,
        latitude: latitude,
        longitude: longitude,
        dispatchId: dispatchId,
        speedKph: speedKph,
        source: source,
        recordedAt: recordedAt,
        pingId: pingId,
      ),
    );
  }
}

/// Reads the fleet board.
final class ReadFleetUseCase {
  /// Creates the use case.
  ReadFleetUseCase({required this._repository});

  final FleetRepository _repository;

  /// Vehicles for the tenant, excluding archived unless [includeArchived].
  Future<List<Ambulance>> ambulances({
    required AuthorizationPolicy policy,
    required String tenantId,
    String? facilityId,
    bool includeArchived = false,
  }) async {
    policy.require(NodexPermissions.fleetRead);
    final List<Ambulance> vehicles = await _repository.listAmbulances(
      tenantId,
      facilityId: facilityId,
    );
    return vehicles
        .where(
          (Ambulance vehicle) =>
              includeArchived || !vehicle.serviceStatus.isArchived,
        )
        .toList(growable: false);
  }

  /// Duty assignments, optionally for one vehicle, newest window first.
  Future<List<AmbulanceDuty>> duties({
    required AuthorizationPolicy policy,
    required String tenantId,
    String? ambulanceId,
    bool liveOnly = false,
  }) async {
    policy.require(NodexPermissions.fleetRead);
    final List<AmbulanceDuty> duties = await _repository.listDuties(
      tenantId,
      ambulanceId: ambulanceId,
    );
    final List<AmbulanceDuty> filtered =
        duties
            .where(
              (AmbulanceDuty duty) => !liveOnly || duty.status.occupiesResource,
            )
            .toList(growable: false)
          ..sort(
            (AmbulanceDuty a, AmbulanceDuty b) =>
                a.startsAt.compareTo(b.startsAt),
          );
    return filtered;
  }

  /// Dispatch jobs for the tenant, newest first. Live jobs come first when
  /// [activeFirst] is set.
  Future<List<AmbulanceDispatch>> dispatches({
    required AuthorizationPolicy policy,
    required String tenantId,
    String? facilityId,
    String? ambulanceId,
    String? patientId,
    bool activeOnly = false,
    bool activeFirst = false,
  }) async {
    policy.require(NodexPermissions.fleetRead);
    final List<AmbulanceDispatch> jobs = await _repository.listDispatches(
      tenantId,
      facilityId: facilityId,
      ambulanceId: ambulanceId,
      patientId: patientId,
    );
    final List<AmbulanceDispatch> filtered = jobs
        .where((AmbulanceDispatch job) => !activeOnly || job.status.isLive)
        .toList(growable: false);
    if (activeFirst) {
      filtered.sort((AmbulanceDispatch a, AmbulanceDispatch b) {
        if (a.status.isLive != b.status.isLive) {
          return a.status.isLive ? -1 : 1;
        }
        return b.requestedAt.compareTo(a.requestedAt);
      });
    } else {
      filtered.sort(
        (AmbulanceDispatch a, AmbulanceDispatch b) =>
            b.requestedAt.compareTo(a.requestedAt),
      );
    }
    return filtered;
  }

  /// The most recent position ping for a vehicle, or null if none is known.
  Future<TrackingPing?> lastKnownPing({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String ambulanceId,
  }) async {
    policy.require(NodexPermissions.fleetRead);
    final List<TrackingPing> pings = await _repository.listPings(
      tenantId,
      ambulanceId: ambulanceId,
      limit: 1,
    );
    return pings.isEmpty ? null : pings.first;
  }
}
