/// Tests for the fleet repository over a fake local store (Module 27).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/domain/fleet/fleet.dart';
import 'package:nodex_hms/domain/fleet/fleet_repository.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';

/// A minimal in-memory store covering the four fleet tables.
final class FakeFleetStore implements PatientLocalStore {
  final Map<String, Map<String, Map<String, Object?>>> tables =
      <String, Map<String, Map<String, Object?>>>{};
  bool closed = false;

  static final RegExp _filterPattern = RegExp(r' and (\w+) = \?');
  static final RegExp _fromPattern = RegExp(r'from (\w+) ');

  Map<String, Map<String, Object?>> _table(String name) =>
      tables.putIfAbsent(name, () => <String, Map<String, Object?>>{});

  void _guard() {
    if (closed) {
      throw const PersistenceError(
        message: 'The local clinical database has not been opened.',
        code: 'database_not_open',
      );
    }
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String sql,
    List<Object?> parameters,
  ) async {
    _guard();
    final RegExpMatch? from = _fromPattern.firstMatch(sql);
    if (from == null) {
      throw UnimplementedError('FakeFleetStore cannot run: $sql');
    }
    final String table = from.group(1)!;
    Iterable<Map<String, Object?>> rows = _table(table).values
        .where((Map<String, Object?> r) => r['tenant_id'] == parameters[0]);
    int next = 1;
    for (final RegExpMatch match in _filterPattern.allMatches(sql)) {
      final String column = match.group(1)!;
      final Object? expected = parameters[next++];
      rows = rows.where((Map<String, Object?> r) => r[column] == expected);
    }
    if (sql.contains('limit ?')) {
      rows = rows.take(parameters.last! as int);
    }
    return rows.toList(growable: false);
  }

  @override
  Future<Map<String, Object?>?> getById(String table, String id) async {
    _guard();
    return _table(table)[id];
  }

  @override
  Future<void> insert(String table, Map<String, Object?> row) async {
    _guard();
    _table(table)[row['id']! as String] = <String, Object?>{...row};
  }

  @override
  Future<void> update(
    String table,
    String id,
    Map<String, Object?> changes,
  ) async {
    _guard();
    final Map<String, Object?>? row = _table(table)[id];
    if (row == null) {
      throw StateError('missing row $id');
    }
    row.addAll(changes);
  }
}

void main() {
  late FakeFleetStore store;
  late DefaultFleetRepository repository;

  setUp(() {
    store = FakeFleetStore();
    repository = DefaultFleetRepository(
      store: store,
      logger: NodexLogger(
        sinks: <NodexLogSink>[InMemoryLogSink()],
        minimumLevel: NodexLogLevel.trace,
      ),
    );
  });

  String now() => DateTime.now().toUtc().toIso8601String();

  Future<String> seedVehicle({
    required String id,
    String callSign = 'UNIT-1',
    String serviceStatus = 'in_service',
    String? facilityId = 'f-1',
  }) => repository.registerAmbulance(<String, Object?>{
    'id': id,
    'tenant_id': 'tenant-1',
    'facility_id': facilityId,
    'call_sign': callSign,
    'registration_no': null,
    'vehicle_type': 'bls',
    'capacity': 2,
    'capability_notes': null,
    'service_status': serviceStatus,
    'created_by': 'user-1',
    'created_at': now(),
    'updated_at': now(),
  });

  Future<String> seedDispatch({
    required String id,
    String status = 'requested',
    String? facilityId = 'f-1',
    String? ambulanceId,
    String? patientId = 'p-1',
    String priority = 'emergency',
  }) => repository.createDispatch(<String, Object?>{
    'id': id,
    'tenant_id': 'tenant-1',
    'facility_id': facilityId,
    'ambulance_id': ambulanceId,
    'patient_id': patientId,
    'patient_name_text': null,
    'priority': priority,
    'status': status,
    'pickup_address': '12 Main St',
    'requested_at': now(),
    'created_by': 'user-1',
    'created_at': now(),
    'updated_at': now(),
  });

  test('registerAmbulance stores and resolves by id', () async {
    final String id = await seedVehicle(id: 'a-1', callSign: 'UNIT-7');
    final Ambulance? vehicle = await repository.ambulanceById(id);
    expect(vehicle, isNotNull);
    expect(vehicle!.callSign, 'UNIT-7');
    expect(vehicle.vehicleType, VehicleType.bls);
    expect(vehicle.serviceStatus, AmbulanceServiceStatus.inService);
    expect(vehicle.capacity, 2);
  });

  test('listAmbulances filters by facility', () async {
    await seedVehicle(id: 'a-1', facilityId: 'f-1');
    await seedVehicle(id: 'a-2', facilityId: 'f-2');
    final List<Ambulance> one = await repository.listAmbulances(
      'tenant-1',
      facilityId: 'f-1',
    );
    expect(one, hasLength(1));
    expect(one.first.id, 'a-1');
  });

  test('updateAmbulance applies changes', () async {
    await seedVehicle(id: 'a-1');
    await repository.updateAmbulance('a-1', <String, Object?>{
      'service_status': 'maintenance',
      'updated_at': now(),
    });
    expect(
      (await repository.ambulanceById('a-1'))!.serviceStatus,
      AmbulanceServiceStatus.maintenance,
    );
  });

  test('duty assignments round-trip and list by vehicle', () async {
    await seedVehicle(id: 'a-1');
    await repository.registerDuty(<String, Object?>{
      'id': 'd-1',
      'tenant_id': 'tenant-1',
      'ambulance_id': 'a-1',
      'driver_user_id': 'driver-1',
      'attendant_user_id': null,
      'starts_at': '2026-10-20T08:00:00.000Z',
      'ends_at': '2026-10-20T16:00:00.000Z',
      'status': 'scheduled',
      'notes': null,
      'created_by': 'user-1',
      'created_at': now(),
      'updated_at': now(),
    });
    final List<AmbulanceDuty> duties = await repository.listDuties(
      'tenant-1',
      ambulanceId: 'a-1',
    );
    expect(duties, hasLength(1));
    expect(duties.first.driverUserId, 'driver-1');
    expect(duties.first.status, DutyStatus.scheduled);
    await repository.updateDuty('d-1', <String, Object?>{
      'status': 'active',
      'updated_at': now(),
    });
    final List<AmbulanceDuty> again = await repository.listDuties(
      'tenant-1',
      ambulanceId: 'a-1',
    );
    expect(again.first.status, DutyStatus.active);
  });

  test(
    'dispatches round-trip and filter by facility, vehicle and patient',
    () async {
      await seedDispatch(id: 'x-1', facilityId: 'f-1', patientId: 'p-1');
      await seedDispatch(id: 'x-2', facilityId: 'f-2', patientId: 'p-2');
      expect((await repository.dispatchById('x-1'))!.patientId, 'p-1');

      final List<AmbulanceDispatch> byFacility = await repository
          .listDispatches('tenant-1', facilityId: 'f-1');
      expect(byFacility, hasLength(1));
      expect(byFacility.first.id, 'x-1');

      final List<AmbulanceDispatch> byPatient = await repository.listDispatches(
        'tenant-1',
        patientId: 'p-2',
      );
      expect(byPatient, hasLength(1));
      expect(byPatient.first.id, 'x-2');
    },
  );

  test('tracking pings round-trip and list by vehicle', () async {
    await seedVehicle(id: 'a-1');
    await repository.registerPing(<String, Object?>{
      'id': 'g-1',
      'tenant_id': 'tenant-1',
      'ambulance_id': 'a-1',
      'dispatch_id': null,
      'latitude': 23.8103,
      'longitude': 90.4125,
      'speed_kph': 40.0,
      'recorded_at': '2026-10-20T09:00:00.000Z',
      'source': 'device',
      'created_at': now(),
    });
    final List<TrackingPing> pings = await repository.listPings(
      'tenant-1',
      ambulanceId: 'a-1',
    );
    expect(pings, hasLength(1));
    expect(pings.first.latitude, closeTo(23.8103, 0.000001));
    expect(pings.first.speedKph, 40.0);
  });

  test('closed store raises and maps', () async {
    store.closed = true;
    expect(
      () => repository.listAmbulances('tenant-1'),
      throwsA(isA<NodexError>()),
    );
  });
}
