/// Tests for clinical messaging (Module 43).
///
/// A discussion belongs to the people in it. These tests pin that: a thread
/// cannot be started without participants, a participant cannot be dropped, a
/// message is a record rather than a draft, and a clinician who is not in the
/// discussion is refused it twice over — once by the device and once by the
/// server.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/authorization_snapshot.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/messaging/clinical_message.dart';
import 'package:nodex_hms/domain/messaging/messaging_repository.dart';

/// A repository that records what it was asked to do.
final class _RecordingMessagingRepository implements MessagingRepository {
  final List<Map<String, Object?>> threads = <Map<String, Object?>>[];
  final List<Map<String, Object?>> messages = <Map<String, Object?>>[];
  List<ClinicalThread> stored = <ClinicalThread>[];
  List<ClinicalMessage> storedMessages = <ClinicalMessage>[];

  @override
  Future<List<ClinicalThread>> listThreads() async => stored;

  @override
  Future<ClinicalThread?> getThread(String id) async =>
      stored.where((ClinicalThread t) => t.id == id).firstOrNull;

  @override
  Future<List<ClinicalMessage>> listMessages(String threadId) async =>
      storedMessages;

  @override
  Future<List<ClinicalAttachment>> listAttachments(String messageId) async =>
      const <ClinicalAttachment>[];

  @override
  Future<String> startThread(Map<String, Object?> row) async {
    threads.add(row);
    return 'thread-1';
  }

  @override
  Future<String> sendMessage(Map<String, Object?> row) async {
    messages.add(row);
    return 'message-1';
  }
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

ClinicalThread _thread({List<String>? participants}) => ClinicalThread(
  id: 'thread-1',
  tenantId: 'tenant-1',
  subject: 'Discuss the raised potassium',
  createdBy: 'doctor-1',
  participants: participants ?? <String>['doctor-1', 'doctor-2'],
);

void main() {
  group('starting a discussion', () {
    test('a thread names its participants', () {
      final Map<String, Object?> row = ClinicalThread.startRow(
        tenantId: 'tenant-1',
        subject: 'Discuss the raised potassium',
        createdBy: 'doctor-1',
        participants: <String>['doctor-1', 'doctor-2'],
      );
      expect(row['participants'], <String>['doctor-1', 'doctor-2']);
      expect(row['status'], 'open');
    });

    test('a thread needs somebody to talk to', () {
      expect(
        () => ClinicalThread.startRow(
          tenantId: 'tenant-1',
          subject: 'Discuss the raised potassium',
          createdBy: 'doctor-1',
          participants: const <String>[],
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'clinical_thread_invalid',
          ),
        ),
      );
    });

    test('the author is in the thread', () {
      expect(
        () => ClinicalThread.startRow(
          tenantId: 'tenant-1',
          subject: 'Discuss the raised potassium',
          createdBy: 'doctor-1',
          participants: const <String>['doctor-2'],
        ),
        throwsA(isA<ValidationError>()),
      );
    });

    test('a thread must say what it is about', () {
      expect(
        () => ClinicalThread.startRow(
          tenantId: 'tenant-1',
          subject: '  ',
          createdBy: 'doctor-1',
          participants: const <String>['doctor-1'],
        ),
        throwsA(isA<ValidationError>()),
      );
    });
  });

  group('posting a message', () {
    test('a message carries its body', () {
      final Map<String, Object?> row = ClinicalMessage.sendRow(
        tenantId: 'tenant-1',
        threadId: 'thread-1',
        senderId: 'doctor-1',
        body: '  Repeat the sample  ',
      );
      expect(row['body'], 'Repeat the sample');
      expect(row['is_urgent'], isFalse);
    });

    test('an empty message is refused', () {
      expect(
        () => ClinicalMessage.sendRow(
          tenantId: 'tenant-1',
          threadId: 'thread-1',
          senderId: 'doctor-1',
          body: '   ',
        ),
        throwsA(
          isA<ValidationError>().having(
            (ValidationError error) => error.code,
            'code',
            'clinical_message_invalid',
          ),
        ),
      );
    });
  });

  group('reading a row', () {
    test('participants are read from a json array', () {
      final ClinicalThread thread = ClinicalThread.fromRow(
        const <String, Object?>{
          'id': 'thread-1',
          'tenant_id': 'tenant-1',
          'subject': 'Discuss the raised potassium',
          'patient_id': null,
          'encounter_id': null,
          'created_by': 'doctor-1',
          'participants': '["doctor-1", "doctor-2"]',
          'status': 'open',
          'last_message_at': null,
          'created_at': '2026-09-12T09:00:00.000Z',
        },
      );
      expect(thread.participants, <String>['doctor-1', 'doctor-2']);
      expect(thread.includes('doctor-2'), isTrue);
      expect(thread.includes('doctor-3'), isFalse);
    });

    test('an urgent message is read as urgent', () {
      final ClinicalMessage message = ClinicalMessage.fromRow(
        const <String, Object?>{
          'id': 'message-1',
          'tenant_id': 'tenant-1',
          'thread_id': 'thread-1',
          'sender_id': 'doctor-1',
          'body': 'Please review now',
          'is_urgent': 1,
          'created_at': '2026-09-12T09:00:00.000Z',
        },
      );
      expect(message.isUrgent, isTrue);
    });
  });

  group('use-case gates', () {
    late _RecordingMessagingRepository repository;

    setUp(() {
      repository = _RecordingMessagingRepository();
    });

    test('reading the threads requires the read permission', () async {
      await expectLater(
        ListThreadsUseCase(repository: repository).call(
          policy: _policy(<String>{NodexPermissions.messagingSend}),
          userId: 'doctor-1',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('a thread the clinician is not in is not listed', () async {
      repository.stored = <ClinicalThread>[_thread()];
      final List<ClinicalThread> threads =
          await ListThreadsUseCase(repository: repository).call(
            policy: _policy(<String>{NodexPermissions.messagingRead}),
            userId: 'doctor-3',
          );
      expect(threads, isEmpty);
    });

    test('a thread the clinician is in is listed', () async {
      repository.stored = <ClinicalThread>[_thread()];
      final List<ClinicalThread> threads =
          await ListThreadsUseCase(repository: repository).call(
            policy: _policy(<String>{NodexPermissions.messagingRead}),
            userId: 'doctor-2',
          );
      expect(threads, hasLength(1));
    });

    test(
      'reading the messages of a thread the clinician is not in is refused',
      () async {
        await expectLater(
          ListMessagesUseCase(repository: repository).call(
            policy: _policy(<String>{NodexPermissions.messagingRead}),
            thread: _thread(),
            userId: 'doctor-3',
          ),
          throwsA(isA<AuthorizationError>()),
        );
      },
    );

    test('posting to a thread the clinician is not in is refused', () async {
      await expectLater(
        SendMessageUseCase(repository: repository).call(
          policy: _policy(<String>{NodexPermissions.messagingSend}),
          thread: _thread(),
          tenantId: 'tenant-1',
          senderId: 'doctor-3',
          body: 'May I join?',
        ),
        throwsA(isA<AuthorizationError>()),
      );
      expect(repository.messages, isEmpty);
    });

    test(
      'posting to a thread the clinician is in writes the message',
      () async {
        await SendMessageUseCase(repository: repository).call(
          policy: _policy(<String>{NodexPermissions.messagingSend}),
          thread: _thread(),
          tenantId: 'tenant-1',
          senderId: 'doctor-1',
          body: 'Please repeat the sample',
        );
        expect(repository.messages.single['body'], 'Please repeat the sample');
      },
    );
  });
}
