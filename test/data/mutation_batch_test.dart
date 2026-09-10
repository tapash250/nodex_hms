/// Tests for the mutation-path contract shared by the upload connector and the
/// Edge Function.
///
/// Two properties matter and are asserted here: mutation ids are stable across
/// retries of the same queue entry (so the server idempotency ledger recognises
/// a retry instead of applying it twice), and an undecodable server decision is
/// treated as a rejection rather than as success.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/data/sync/mutation_batch.dart';

void main() {
  group('NodexMutationId.forQueueEntry', () {
    test('returns a valid UUID', () {
      final String id = NodexMutationId.forQueueEntry(
        transactionId: 42,
        clientId: 7,
      );

      expect(
        id,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
    });

    test('is stable for the same queue entry across retries', () {
      final String first = NodexMutationId.forQueueEntry(
        transactionId: 42,
        clientId: 7,
      );
      final String second = NodexMutationId.forQueueEntry(
        transactionId: 42,
        clientId: 7,
      );

      expect(second, first);
    });

    test('differs across queue entries', () {
      final String base = NodexMutationId.forQueueEntry(
        transactionId: 42,
        clientId: 7,
      );

      expect(
        NodexMutationId.forQueueEntry(transactionId: 42, clientId: 8),
        isNot(base),
      );
      expect(
        NodexMutationId.forQueueEntry(transactionId: 43, clientId: 7),
        isNot(base),
      );
      expect(
        NodexMutationId.forQueueEntry(transactionId: null, clientId: 7),
        isNot(base),
      );
    });

    test('accepts a null transaction id', () {
      final String id = NodexMutationId.forQueueEntry(
        transactionId: null,
        clientId: 1,
      );

      expect(id, isNotEmpty);
      expect(
        id,
        NodexMutationId.forQueueEntry(transactionId: null, clientId: 1),
      );
    });
  });

  group('decodeMutationDecision', () {
    test('decodes an applied decision', () {
      final MutationDecision decision = decodeMutationDecision(
        <String, Object?>{'id': 'mutation-1', 'outcome': 'applied'},
      );

      expect(decision.mutationId, 'mutation-1');
      expect(decision.outcome, MutationOutcome.applied);
      expect(decision.rejectionClass, isNull);
      expect(decision.detail, isNull);
    });

    test('decodes an already-applied retry', () {
      final MutationDecision decision = decodeMutationDecision(
        <String, Object?>{'id': 'mutation-1', 'outcome': 'already_applied'},
      );

      expect(decision.outcome, MutationOutcome.alreadyApplied);
    });

    test('decodes a rejection with class and detail', () {
      final MutationDecision decision = decodeMutationDecision(
        <String, Object?>{
          'id': 'mutation-1',
          'outcome': 'rejected',
          'rejection_class': 'unsupported',
          'detail': 'table "patients" has no offline write path',
        },
      );

      expect(decision.outcome, MutationOutcome.rejected);
      expect(decision.rejectionClass, 'unsupported');
      expect(decision.detail, contains('patients'));
    });

    test('treats an unknown outcome as a rejection, never as success', () {
      final MutationDecision decision = decodeMutationDecision(
        <String, Object?>{
          'id': 'mutation-1',
          'outcome': 'definitely_applied_trust_me',
        },
      );

      expect(decision.outcome, MutationOutcome.rejected);
    });

    test('treats a missing outcome as a rejection', () {
      final MutationDecision decision = decodeMutationDecision(
        <String, Object?>{'id': 'mutation-1'},
      );

      expect(decision.outcome, MutationOutcome.rejected);
    });

    test('falls back to an unknown id rather than throwing', () {
      final MutationDecision decision = decodeMutationDecision(
        <String, Object?>{'outcome': 'applied'},
      );

      expect(decision.mutationId, 'unknown');
      expect(decision.outcome, MutationOutcome.applied);
    });

    test('ignores non-string rejection fields', () {
      final MutationDecision decision = decodeMutationDecision(
        <String, Object?>{
          'id': 'mutation-1',
          'outcome': 'rejected',
          'rejection_class': 42,
          'detail': <String>['not', 'a', 'string'],
        },
      );

      expect(decision.outcome, MutationOutcome.rejected);
      expect(decision.rejectionClass, isNull);
      expect(decision.detail, isNull);
    });
  });
}
