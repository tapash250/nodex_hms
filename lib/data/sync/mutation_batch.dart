/// Mutation batch assembly for the authorized backend mutation path.
///
/// The connector and the Edge Function share a contract: every mutation carries
/// a stable id derived from its PowerSync queue position, so a retry after a
/// lost response lands on the same idempotency ledger row instead of applying
/// twice. UUIDv5 derives that stable key into a valid UUID the server accepts.
///
/// The response side of the same contract lives here too: the per-mutation
/// decisions the function returns are decoded by [decodeMutationDecision], so
/// the decoding is unit-testable without any Supabase dependency.
library;

import 'package:uuid/uuid.dart';

/// Outcome for one mutation as decided by the mutation-handler function.
enum MutationOutcome {
  /// The server applied the write.
  applied,

  /// A previous attempt already applied it; this retry changed nothing.
  alreadyApplied,

  /// The server permanently refused this mutation.
  rejected,
}

/// One mutation's decision returned by the authorized mutation path.
final class MutationDecision {
  /// Creates a decision.
  const MutationDecision({
    required this.mutationId,
    required this.outcome,
    this.rejectionClass,
    this.detail,
  });

  /// Client-generated mutation id from the request.
  final String mutationId;

  /// Server decision for this mutation.
  final MutationOutcome outcome;

  /// Rejection class, when the outcome is rejected.
  final String? rejectionClass;

  /// Non-PHI detail, when the outcome is rejected.
  final String? detail;
}

/// Decodes one decision object from the mutation-handler response.
///
/// Unknown outcomes decode as rejections: a decision the client does not
/// understand must never be treated as success, because a clinical write of
/// unknown status must not appear to have committed.
MutationDecision decodeMutationDecision(Map<String, Object?> raw) {
  final String id = raw['id'] is String ? raw['id']! as String : 'unknown';
  final String outcome = raw['outcome'] is String
      ? raw['outcome']! as String
      : 'rejected';
  final String? rejectionClass = raw['rejection_class'] is String
      ? raw['rejection_class']! as String
      : null;
  final String? detail = raw['detail'] is String
      ? raw['detail']! as String
      : null;

  return MutationDecision(
    mutationId: id,
    outcome: switch (outcome) {
      'applied' => MutationOutcome.applied,
      'already_applied' => MutationOutcome.alreadyApplied,
      _ => MutationOutcome.rejected,
    },
    rejectionClass: rejectionClass,
    detail: detail,
  );
}

/// Derives the stable mutation id for a queue position.
abstract final class NodexMutationId {
  /// RFC 4122 OID namespace: stable, standard, and carries no project data.
  static const String _namespace = '6ba7b810-9dad-11d1-80b4-00c04fd430c8';

  /// Derives the mutation id from a PowerSync transaction and client entry id.
  ///
  /// [transactionId] and [clientId] are both replayed unchanged by PowerSync
  /// when a batch is retried, so the derived id is identical on every attempt.
  static String forQueueEntry({
    required int? transactionId,
    required int clientId,
  }) => const Uuid().v5(_namespace, 'nodex-mutation:$transactionId:$clientId');
}
