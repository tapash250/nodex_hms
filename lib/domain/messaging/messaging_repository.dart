/// Messaging repository and use cases (Module 43).
library;

import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/error_mapper.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/messaging/clinical_message.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';
import 'package:uuid/uuid.dart';

/// Repository operations for clinical messages.
abstract interface class MessagingRepository {
  /// The threads the signed-in clinician takes part in.
  Future<List<ClinicalThread>> listThreads();

  /// One thread by id, or null.
  Future<ClinicalThread?> getThread(String id);

  /// The messages in a thread, oldest first.
  Future<List<ClinicalMessage>> listMessages(String threadId);

  /// The files attached to a message.
  Future<List<ClinicalAttachment>> listAttachments(String messageId);

  /// Starts a thread.
  Future<String> startThread(Map<String, Object?> row);

  /// Posts a message.
  Future<String> sendMessage(Map<String, Object?> row);
}

/// PowerSync-backed messaging repository.
final class DefaultMessagingRepository implements MessagingRepository {
  /// Creates a repository over a local store.
  DefaultMessagingRepository({required this._store, required this._logger});

  static const String _module = 'domain.messaging';

  final PatientLocalStore _store;
  final NodexLogger _logger;

  @override
  Future<List<ClinicalThread>> listThreads() async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'SELECT * FROM ${LocalTables.clinicalThreads} '
        'ORDER BY last_message_at DESC',
        const <Object?>[],
      );
      return rows.map(ClinicalThread.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'messaging.threads');
    }
  }

  @override
  Future<ClinicalThread?> getThread(String id) async {
    final Map<String, Object?>? row = await _store.getById(
      LocalTables.clinicalThreads,
      id,
    );
    return row == null ? null : ClinicalThread.fromRow(row);
  }

  @override
  Future<List<ClinicalMessage>> listMessages(String threadId) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'SELECT * FROM ${LocalTables.clinicalMessages} WHERE thread_id = ? '
        'ORDER BY created_at',
        <Object?>[threadId],
      );
      return rows.map(ClinicalMessage.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'messaging.messages');
    }
  }

  @override
  Future<List<ClinicalAttachment>> listAttachments(String messageId) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'SELECT * FROM ${LocalTables.clinicalAttachments} WHERE message_id = ? '
        'ORDER BY created_at',
        <Object?>[messageId],
      );
      return rows.map(ClinicalAttachment.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'messaging.attachments');
    }
  }

  @override
  Future<String> startThread(Map<String, Object?> row) async {
    final String id = const Uuid().v4();
    try {
      await _store.insert(LocalTables.clinicalThreads, <String, Object?>{
        ...row,
        'id': id,
      });
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'messaging.startThread');
    }
  }

  @override
  Future<String> sendMessage(Map<String, Object?> row) async {
    final String id = const Uuid().v4();
    try {
      await _store.insert(LocalTables.clinicalMessages, <String, Object?>{
        ...row,
        'id': id,
      });
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'messaging.send');
    }
  }

  Never _mapped(Object error, StackTrace stackTrace, String operation) {
    if (error is NodexError) throw error;
    final NodexError mapped = NodexErrorMapper.map(error, operation: operation);
    _logger.error(
      _module,
      'Messaging repository failure.',
      operation: operation,
      outcome: 'failed',
      errorCode: mapped.code,
      stackTrace: stackTrace,
    );
    throw mapped;
  }
}

/// Reads the threads the signed-in clinician takes part in.
final class ListThreadsUseCase {
  /// Creates the use case.
  const ListThreadsUseCase({required this._repository});

  final MessagingRepository _repository;

  /// Reads the threads.
  Future<List<ClinicalThread>> call({
    required AuthorizationPolicy policy,
    required String userId,
  }) async {
    policy.require(NodexPermissions.messagingRead);
    final List<ClinicalThread> threads = await _repository.listThreads();
    // The server filters by participation; the device filters again, because
    // a device that synced a thread it has no business reading must not show
    // it, and the two rules must not drift apart silently.
    return threads
        .where((ClinicalThread thread) => thread.includes(userId))
        .toList(growable: false);
  }
}

/// Reads the messages of a thread.
final class ListMessagesUseCase {
  /// Creates the use case.
  const ListMessagesUseCase({required this._repository});

  final MessagingRepository _repository;

  /// Reads the messages.
  Future<List<ClinicalMessage>> call({
    required AuthorizationPolicy policy,
    required ClinicalThread thread,
    required String userId,
  }) async {
    policy.require(NodexPermissions.messagingRead);
    if (!thread.includes(userId)) {
      throw const AuthorizationError(
        message: 'You are not part of this discussion.',
        code: 'messaging_not_a_participant',
      );
    }
    return _repository.listMessages(thread.id);
  }
}

/// Starts a clinical discussion.
final class StartThreadUseCase {
  /// Creates the use case.
  const StartThreadUseCase({required this._repository});

  final MessagingRepository _repository;

  /// Starts the thread.
  Future<String> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String subject,
    required String createdBy,
    required List<String> participants,
    String? patientId,
    String? encounterId,
  }) async {
    policy.require(NodexPermissions.messagingSend);
    return _repository.startThread(
      ClinicalThread.startRow(
        tenantId: tenantId,
        subject: subject,
        createdBy: createdBy,
        participants: participants,
        patientId: patientId,
        encounterId: encounterId,
      ),
    );
  }
}

/// Posts a message to a thread.
final class SendMessageUseCase {
  /// Creates the use case.
  const SendMessageUseCase({required this._repository});

  final MessagingRepository _repository;

  /// Posts the message.
  Future<String> call({
    required AuthorizationPolicy policy,
    required ClinicalThread thread,
    required String tenantId,
    required String senderId,
    required String body,
    bool isUrgent = false,
  }) async {
    policy.require(NodexPermissions.messagingSend);
    if (!thread.includes(senderId)) {
      throw const AuthorizationError(
        message: 'You are not part of this discussion.',
        code: 'messaging_not_a_participant',
      );
    }
    return _repository.sendMessage(
      ClinicalMessage.sendRow(
        tenantId: tenantId,
        threadId: thread.id,
        senderId: senderId,
        body: body,
        isUrgent: isUrgent,
      ),
    );
  }
}
