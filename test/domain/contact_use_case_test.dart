/// Tests for the hospital contacts use-case gates and directory helpers
/// (Module 42).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/authorization_snapshot.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/domain/contacts/contact.dart';
import 'package:nodex_hms/domain/contacts/contact_repository.dart';
import 'package:nodex_hms/domain/contacts/contact_use_cases.dart';

import 'contact_repository_test.dart' show FakeContactStore;

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
      roles: const <String>{NodexRoles.hospitalSuperAdmin},
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
  late FakeContactStore store;
  late DefaultContactRepository repository;
  late RegisterContactUseCase register;
  late UpdateContactUseCase update;
  late ArchiveContactUseCase archive;
  late ListContactsUseCase list;

  const Set<String> admin = <String>{NodexPermissions.contactsAdminister};
  const Set<String> reader = <String>{NodexPermissions.contactsRead};

  setUp(() {
    store = FakeContactStore();
    repository = DefaultContactRepository(
      store: store,
      logger: NodexLogger(
        sinks: <NodexLogSink>[InMemoryLogSink()],
        minimumLevel: NodexLogLevel.trace,
      ),
    );
    register = RegisterContactUseCase(repository: repository);
    update = UpdateContactUseCase(repository: repository);
    archive = ArchiveContactUseCase(repository: repository);
    list = ListContactsUseCase(repository: repository);
  });

  test('register requires administration permission', () async {
    expect(
      () => register(
        policy: policyWith(<String>{}),
        tenantId: 'tenant-1',
        createdBy: 'user-1',
        name: 'Switchboard',
        phonePrimary: '555-0001',
      ),
      throwsA(isA<NodexError>()),
    );
    final String id = await register(
      policy: policyWith(admin),
      tenantId: 'tenant-1',
      createdBy: 'user-1',
      name: 'Switchboard',
      phonePrimary: '555-0001',
    );
    expect(id, isNotEmpty);
  });

  test('register rejects an empty phone and a malformed email', () async {
    expect(
      () => register(
        policy: policyWith(admin),
        tenantId: 'tenant-1',
        createdBy: 'user-1',
        name: 'No number',
        phonePrimary: '   ',
      ),
      throwsA(isA<NodexError>()),
    );
    expect(
      () => register(
        policy: policyWith(admin),
        tenantId: 'tenant-1',
        createdBy: 'user-1',
        name: 'Bad email',
        phonePrimary: '555-0002',
        email: 'not-an-email',
      ),
      throwsA(isA<NodexError>()),
    );
  });

  test('register stores the directory facts', () async {
    final String id = await register(
      policy: policyWith(admin),
      tenantId: 'tenant-1',
      createdBy: 'user-1',
      name: 'Blood bank help desk',
      phonePrimary: '555-0003',
      category: ContactCategory.clinical,
      extension: '4321',
      isEmergency: true,
    );
    final DirectoryContact? contact = await repository.contactById(id);
    expect(contact, isNotNull);
    expect(contact!.category, ContactCategory.clinical);
    expect(contact.extension, '4321');
    expect(contact.isEmergency, isTrue);
  });

  test(
    'list requires the read permission and searches the directory',
    () async {
      expect(
        () => list(policy: policyWith(<String>{}), tenantId: 'tenant-1'),
        throwsA(isA<NodexError>()),
      );

      await register(
        policy: policyWith(admin),
        tenantId: 'tenant-1',
        createdBy: 'user-1',
        name: 'Radiology reception',
        phonePrimary: '555-0010',
        category: ContactCategory.clinical,
      );
      await register(
        policy: policyWith(admin),
        tenantId: 'tenant-1',
        createdBy: 'user-1',
        name: 'Emergency control room',
        phonePrimary: '555-0911',
        category: ContactCategory.emergency,
        isEmergency: true,
      );

      final List<DirectoryContact> found = await list(
        policy: policyWith(reader),
        tenantId: 'tenant-1',
        query: 'radio',
      );
      expect(found, hasLength(1));
      expect(found.first.name, 'Radiology reception');

      final List<DirectoryContact> all = await list(
        policy: policyWith(reader),
        tenantId: 'tenant-1',
      );
      // Emergency contacts sort to the top.
      expect(all.first.isEmergency, isTrue);
    },
  );

  test('update after archive is refused', () async {
    final String id = await register(
      policy: policyWith(admin),
      tenantId: 'tenant-1',
      createdBy: 'user-1',
      name: 'Switchboard',
      phonePrimary: '555-0001',
    );
    final DirectoryContact contact = (await repository.contactById(id))!;
    await archive(policy: policyWith(admin), contact: contact);
    final DirectoryContact archived = (await repository.contactById(id))!;
    expect(
      () => update(
        policy: policyWith(admin),
        contact: archived,
        name: 'New switchboard',
      ),
      throwsA(isA<NodexError>()),
    );
  });

  test('archive is idempotent-guarded and requires administration', () async {
    final String id = await register(
      policy: policyWith(admin),
      tenantId: 'tenant-1',
      createdBy: 'user-1',
      name: 'Switchboard',
      phonePrimary: '555-0001',
    );
    final DirectoryContact contact = (await repository.contactById(id))!;
    expect(
      () => archive(policy: policyWith(<String>{}), contact: contact),
      throwsA(isA<NodexError>()),
    );
    await archive(policy: policyWith(admin), contact: contact);
    final DirectoryContact archived = (await repository.contactById(id))!;
    expect(archived.status, ContactStatus.archived);
    expect(
      () => archive(policy: policyWith(admin), contact: archived),
      throwsA(isA<NodexError>()),
    );
  });

  test('directory helpers order and match as documented', () {
    expect(ContactCategory.fromWire('external'), ContactCategory.external);
    expect(ContactCategory.fromWire('nonsense'), ContactCategory.support);
    expect(ContactStatus.fromWire('archived'), ContactStatus.archived);

    final DirectoryContact routine = DirectoryContact.fromRow(
      DirectoryContact.registerRow(
        tenantId: 'tenant-1',
        createdBy: 'user-1',
        name: 'Portering',
        phonePrimary: '555-0001',
        contactId: 'c-routine',
        displayOrder: 5,
      ),
    );
    final DirectoryContact emergency = DirectoryContact.fromRow(
      DirectoryContact.registerRow(
        tenantId: 'tenant-1',
        createdBy: 'user-1',
        name: 'Emergency',
        phonePrimary: '555-0911',
        contactId: 'c-emergency',
        isEmergency: true,
        displayOrder: 900,
      ),
    );
    expect(compareContacts(emergency, routine), lessThan(0));
    expect(contactMatchesQuery(routine, 'port'), isTrue);
    expect(contactMatchesQuery(routine, '555-0001'), isTrue);
    expect(contactMatchesQuery(routine, 'xyz'), isFalse);
    expect(contactMatchesQuery(routine, ''), isTrue);
  });
}
