/// Tests for the department registry use-case gates (Module 12).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/authorization_snapshot.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/domain/departments/department.dart';
import 'package:nodex_hms/domain/departments/department_repository.dart';
import 'package:nodex_hms/domain/departments/department_use_cases.dart';

import 'department_repository_test.dart' show FakeDepartmentStore;

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
      facilityIds: const <String>{'f-1'},
      departmentIds: const <String>{},
      wardIds: const <String>{},
    ),
    connectivity: ConnectivityState.online,
  );
}

void main() {
  late FakeDepartmentStore store;
  late DefaultDepartmentRepository repository;
  late RegisterDepartmentUseCase register;
  late UpdateDepartmentUseCase update;
  late ArchiveDepartmentUseCase archive;
  late ListDepartmentsUseCase list;

  const Set<String> admin = <String>{NodexPermissions.departmentAdminister};

  setUp(() {
    store = FakeDepartmentStore();
    repository = DefaultDepartmentRepository(
      store: store,
      logger: NodexLogger(
        sinks: <NodexLogSink>[InMemoryLogSink()],
        minimumLevel: NodexLogLevel.trace,
      ),
    );
    register = RegisterDepartmentUseCase(repository: repository);
    update = UpdateDepartmentUseCase(repository: repository);
    archive = ArchiveDepartmentUseCase(repository: repository);
    list = ListDepartmentsUseCase(repository: repository);
  });

  test('register requires administration permission', () async {
    final String id = await register(
      policy: policyWith(admin),
      tenantId: 'tenant-1',
      facilityId: 'f-1',
      code: 'CARD',
      displayName: 'Cardiology',
    );
    expect(id, isNotEmpty);

    expect(
      () => register(
        policy: policyWith(<String>{}),
        tenantId: 'tenant-1',
        facilityId: 'f-1',
        code: 'NEURO',
        displayName: 'Neurology',
      ),
      throwsA(isA<NodexError>()),
    );
  });

  test('register stores the department facts', () async {
    final String id = await register(
      policy: policyWith(admin),
      tenantId: 'tenant-1',
      facilityId: 'f-1',
      code: 'CARD',
      displayName: 'Cardiology',
      specialty: 'Cardiology',
    );
    final Department? department = await repository.departmentById(id);
    expect(department, isNotNull);
    expect(department!.displayName, 'Cardiology');
    expect(department.specialty, 'Cardiology');
  });

  test('list requires administration permission', () async {
    expect(
      () => list(policy: policyWith(<String>{}), tenantId: 'tenant-1'),
      throwsA(isA<NodexError>()),
    );
    final List<Department> result = await list(
      policy: policyWith(admin),
      tenantId: 'tenant-1',
    );
    expect(result, isEmpty);
  });

  test('update after archive is refused', () async {
    final String id = await register(
      policy: policyWith(admin),
      tenantId: 'tenant-1',
      facilityId: 'f-1',
      code: 'CARD',
      displayName: 'Cardiology',
    );
    final Department department = (await repository.departmentById(id))!;
    await archive(policy: policyWith(admin), department: department);
    final Department archived = (await repository.departmentById(id))!;
    expect(
      () => update(
        policy: policyWith(admin),
        department: archived,
        displayName: 'Cardiology and thoracic surgery',
      ),
      throwsA(isA<NodexError>()),
    );
  });

  test('archive is idempotent-guarded', () async {
    final String id = await register(
      policy: policyWith(admin),
      tenantId: 'tenant-1',
      facilityId: 'f-1',
      code: 'CARD',
      displayName: 'Cardiology',
    );
    final Department department = (await repository.departmentById(id))!;
    await archive(policy: policyWith(admin), department: department);
    final Department archived = (await repository.departmentById(id))!;
    expect(
      () => archive(policy: policyWith(admin), department: archived),
      throwsA(isA<NodexError>()),
    );
  });

  test('DepartmentStatus parses', () {
    expect(DepartmentStatus.fromWire('archived'), DepartmentStatus.archived);
    expect(DepartmentStatus.fromWire('unknown'), DepartmentStatus.active);
  });
}
