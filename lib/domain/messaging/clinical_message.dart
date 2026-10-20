/// Clinical messages (Module 43).
///
/// A thread is a discussion between clinicians; a message is what was said in
/// it. Both are records: a message is never edited, because a message that
/// can be changed after the fact is not a record of what was said.
// ignore_for_file: sort_constructors_first
library;

import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';

/// A clinical discussion thread.
@immutable
final class ClinicalThread {
  /// Creates a thread.
  const ClinicalThread({
    required this.id,
    required this.tenantId,
    required this.subject,
    required this.createdBy,
    required this.participants,
    this.patientId,
    this.encounterId,
    this.status = 'open',
    this.lastMessageAt,
    this.createdAt,
  });

  /// Validates and builds a new thread row.
  static Map<String, Object?> startRow({
    required String tenantId,
    required String subject,
    required String createdBy,
    required List<String> participants,
    String? patientId,
    String? encounterId,
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.trim().isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (subject.trim().isEmpty) {
      fieldErrors['subject'] = 'Say what the thread is about.';
    }
    if (createdBy.trim().isEmpty) {
      fieldErrors['created_by'] = 'The author is required.';
    }
    if (participants.isEmpty) {
      fieldErrors['participants'] = 'A thread needs somebody to talk to.';
    } else if (!participants.contains(createdBy)) {
      // The author is in the thread by definition; a thread whose author
      // cannot read it is a thread that lost its first message.
      fieldErrors['participants'] = 'The author must be a participant.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Starting a clinical thread failed validation.',
        fieldErrors: fieldErrors,
        code: 'clinical_thread_invalid',
      );
    }
    final String now = DateTime.now().toUtc().toIso8601String();
    return <String, Object?>{
      'tenant_id': tenantId,
      'subject': subject.trim(),
      'patient_id': patientId,
      'encounter_id': encounterId,
      'created_by': createdBy,
      'participants': participants,
      'status': 'open',
      'last_message_at': null,
      'created_at': now,
      'updated_at': now,
    };
  }

  /// Reads a thread from a local row.
  factory ClinicalThread.fromRow(Map<String, Object?> row) => ClinicalThread(
    id: row['id']! as String,
    tenantId: row['tenant_id']! as String,
    subject: row['subject']! as String,
    patientId: row['patient_id'] as String?,
    encounterId: row['encounter_id'] as String?,
    createdBy: row['created_by']! as String,
    participants: _participants(row['participants']),
    status: row['status']! as String,
    lastMessageAt: _parse(row['last_message_at']),
    createdAt: _parse(row['created_at']),
  );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// What the thread is about.
  final String subject;

  /// The patient the thread concerns.
  final String? patientId;

  /// The encounter the thread belongs to.
  final String? encounterId;

  /// The author.
  final String createdBy;

  /// The people in the thread.
  final List<String> participants;

  /// Whether the thread is still open.
  final String status;

  /// When the last message was sent.
  final DateTime? lastMessageAt;

  /// When the thread was started.
  final DateTime? createdAt;

  /// Whether [userId] is in the thread.
  bool includes(String userId) => participants.contains(userId);
}

/// A message in a clinical thread.
@immutable
final class ClinicalMessage {
  /// Creates a message.
  const ClinicalMessage({
    required this.id,
    required this.tenantId,
    required this.threadId,
    required this.senderId,
    required this.body,
    this.isUrgent = false,
    this.createdAt,
  });

  /// Validates and builds a new message row.
  static Map<String, Object?> sendRow({
    required String tenantId,
    required String threadId,
    required String senderId,
    required String body,
    bool isUrgent = false,
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.trim().isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (threadId.trim().isEmpty) {
      fieldErrors['thread_id'] = 'The thread is required.';
    }
    if (senderId.trim().isEmpty) {
      fieldErrors['sender_id'] = 'The sender is required.';
    }
    if (body.trim().isEmpty) {
      fieldErrors['body'] = 'A message cannot be empty.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Sending a message failed validation.',
        fieldErrors: fieldErrors,
        code: 'clinical_message_invalid',
      );
    }
    return <String, Object?>{
      'tenant_id': tenantId,
      'thread_id': threadId,
      'sender_id': senderId,
      'body': body.trim(),
      'is_urgent': isUrgent,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  /// Reads a message from a local row.
  factory ClinicalMessage.fromRow(Map<String, Object?> row) => ClinicalMessage(
    id: row['id']! as String,
    tenantId: row['tenant_id']! as String,
    threadId: row['thread_id']! as String,
    senderId: row['sender_id']! as String,
    body: row['body']! as String,
    isUrgent: (row['is_urgent'] as int?) == 1,
    createdAt: _parse(row['created_at']),
  );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// The thread the message is in.
  final String threadId;

  /// Who sent it.
  final String senderId;

  /// What was said.
  final String body;

  /// Whether it was flagged urgent.
  final bool isUrgent;

  /// When it was sent.
  final DateTime? createdAt;
}

/// A file attached to a message.
@immutable
final class ClinicalAttachment {
  /// Creates an attachment.
  const ClinicalAttachment({
    required this.id,
    required this.tenantId,
    required this.messageId,
    required this.fileName,
    required this.contentType,
    required this.sizeBytes,
    required this.storagePath,
    this.createdAt,
  });

  /// Reads an attachment from a local row.
  factory ClinicalAttachment.fromRow(Map<String, Object?> row) =>
      ClinicalAttachment(
        id: row['id']! as String,
        tenantId: row['tenant_id']! as String,
        messageId: row['message_id']! as String,
        fileName: row['file_name']! as String,
        contentType: row['content_type']! as String,
        sizeBytes: (row['size_bytes'] as int?) ?? 0,
        storagePath: row['storage_path']! as String,
        createdAt: _parse(row['created_at']),
      );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// The message the file belongs to.
  final String messageId;

  /// The name of the file.
  final String fileName;

  /// Its type.
  final String contentType;

  /// Its size in bytes.
  final int sizeBytes;

  /// Where it is held.
  final String storagePath;

  /// When it was attached.
  final DateTime? createdAt;
}

List<String> _participants(Object? value) {
  if (value is List<Object?>) {
    return value.map((Object? id) => '$id').toList(growable: false);
  }
  if (value is String && value.isNotEmpty) {
    final String text = value.trim();
    if (text.startsWith('[')) {
      // The participants arrive as the JSON array the server holds.
      try {
        final Object? decoded = jsonDecode(text);
        if (decoded is List<Object?>) {
          return decoded.map((Object? id) => '$id').toList(growable: false);
        }
      } on FormatException {
        // Fall through to the brace-separated form below.
      }
    }
    return text
        .replaceAll('[', '')
        .replaceAll(']', '')
        .replaceAll('{', '')
        .replaceAll('}', '')
        .replaceAll('"', '')
        .split(',')
        .map((String id) => id.trim())
        .where((String id) => id.isNotEmpty)
        .toList(growable: false);
  }
  return const <String>[];
}

DateTime? _parse(Object? value) =>
    value == null ? null : DateTime.parse(value as String);
