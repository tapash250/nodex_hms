/// PowerSync backend connector.
///
/// Bridges the encrypted local operational projection to the authoritative cloud
/// system of record. Two responsibilities, both narrow by design:
///
/// 1. Supply short-lived credentials for the PowerSync service, sourced from the
///    Supabase session. No long-lived secret is held.
/// 2. Upload queued local mutations through the authorized backend path, where
///    domain validation, mutation authorization and audit creation happen before
///    anything reaches PostgreSQL.
///
/// The connector never resolves conflicts itself. A rejection is classified,
/// recorded and surfaced; a conflicting write is handed to the entity's
/// registered conflict policy. Nothing is silently discarded, and nothing is
/// resolved by an implicit last-write-wins.
library;

import 'package:nodex_hms/core/errors/error_mapper.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/sync/conflict_policy.dart';
import 'package:nodex_hms/data/remote/supabase_gateway.dart';
import 'package:nodex_hms/data/sync/mutation_batch.dart';
import 'package:powersync/powersync.dart';

/// Outcome of attempting to upload one batch of local mutations.
enum UploadOutcome {
  /// Every entry in the batch was accepted; the batch was cleared.
  accepted,

  /// A transient failure occurred; the batch stays queued for retry.
  retryLater,

  /// The server permanently rejected an entry; it is recorded for review.
  rejected,

  /// A conflict was detected; the entity's conflict policy applies.
  conflicted,
}

/// Submits a batch of mutations to the authorized backend path.
typedef MutationSubmitter = Future<List<MutationDecision>> Function(
  List<Map<String, Object?>> mutations, {
  String? deviceId,
});

/// Connects PowerSync to Supabase through the authorized mutation path.
final class NodexBackendConnector extends PowerSyncBackendConnector {
  /// Creates a connector.
  ///
  /// [resolveDeviceId] resolves the enrolled device UUID for each upload. It is
  /// read per batch rather than captured once because the device is enrolled as
  /// part of snapshot issuance, which happens after this connector is
  /// constructed. When it resolves to null — the device is not yet enrolled —
  /// the mutation is uploaded without a device binding, and the server records
  /// the ledger row with a null device rather than a fabricated one.
  NodexBackendConnector({
    required this._gateway,
    required this._logger,
    required this._powerSyncUrl,
    String? Function()? resolveDeviceId,
  }) : _deviceId = resolveDeviceId;

  final SupabaseGateway _gateway;
  final NodexLogger _logger;
  final String _powerSyncUrl;
  final String? Function()? _deviceId;

  @override
  Future<PowerSyncCredentials?> fetchCredentials() async {
    final SupabaseSessionSnapshot? session = _gateway.currentSession();
    if (session == null) {
      // Not signed in. Returning null leaves the client local-only rather than
      // retrying against an endpoint that will reject it.
      return null;
    }

    return PowerSyncCredentials(
      endpoint: _powerSyncUrl,
      token: session.accessToken,
      userId: session.userId,
      expiresAt: session.expiresAt,
    );
  }

  @override
  Future<void> uploadData(PowerSyncDatabase database) async {
    final CrudTransaction? transaction = await database
        .getNextCrudTransaction();
    if (transaction == null) {
      return;
    }

    final MutationUploader uploader = MutationUploader(
      submit: _gateway.submitMutations,
      logger: _logger,
    );
    await uploader.upload(transaction, deviceId: _deviceId?.call());
  }
}

/// Uploads one PowerSync transaction in server-sized chunks.
///
/// Kept separate from [NodexBackendConnector] so the upload contract is
/// testable without a live PowerSync database or Supabase client. The connector
/// is the only production caller.
final class MutationUploader {
  /// Creates an uploader over [submit].
  factory MutationUploader({
    required MutationSubmitter submit,
    required NodexLogger logger,
  }) => MutationUploader._(submit, logger);

  MutationUploader._(this._submit, this._logger);

  static const String _module = 'sync.connector';

  /// Maximum mutations the server accepts in one request.
  ///
  /// The mutation-handler rejects a batch larger than this with HTTP 413. The
  /// connector chunks a PowerSync transaction instead of sending one oversized
  /// request, and completes the transaction only after every chunk succeeds.
  static const int maxMutationsPerBatch = 100;

  final MutationSubmitter _submit;
  final NodexLogger _logger;

  /// Uploads [transaction], returning the aggregate outcome.
  ///
  /// A permanent rejection is logged and the queue entry is cleared. A conflict
  /// is routed to the table's registered conflict policy: a server-authoritative
  /// entity reconciles by discarding the local projection, while every other
  /// policy leaves the batch queued for the reconciler. A malformed response or
  /// a transient failure leaves the whole transaction queued.
  Future<UploadOutcome> upload(
    CrudTransaction transaction, {
    String? deviceId,
  }) async {
    try {
      _rejectHardDeletes(transaction.crud);

      bool sawRejection = false;
      bool sawConflict = false;

      for (
        int start = 0;
        start < transaction.crud.length;
        start += maxMutationsPerBatch
      ) {
        final int end = start + maxMutationsPerBatch < transaction.crud.length
            ? start + maxMutationsPerBatch
            : transaction.crud.length;
        final List<CrudEntry> chunk = transaction.crud.sublist(start, end);
        final List<Map<String, Object?>> payload =
            buildMutationPayloadForEntries(
              entries: chunk,
              transactionId: transaction.transactionId,
              deviceId: deviceId,
            );

        final List<MutationDecision> decisions = await _submit(
          payload,
          deviceId: deviceId,
        );
        final List<DecisionMatch> matches = matchMutationDecisions(
          entries: chunk,
          transactionId: transaction.transactionId,
          decisions: decisions,
        );

        for (final DecisionMatch match in matches) {
          switch (match.decision.outcome) {
            case MutationOutcome.applied:
            case MutationOutcome.alreadyApplied:
              break;
            case MutationOutcome.rejected:
              if (match.decision.rejectionClass == 'conflict') {
                sawConflict = true;
                _handleConflict(match.entry, match.decision);
              } else {
                sawRejection = true;
                _logRejection(match.entry, match.decision);
              }
          }
        }
      }

      await transaction.complete();

      _logger.info(
        _module,
        'Uploaded a local mutation transaction'
        '${sawConflict
            ? ' with conflicts'
            : sawRejection
            ? ' with rejections'
            : ''}.',
        operation: 'sync.upload',
        outcome: sawConflict
            ? 'conflicted'
            : sawRejection
            ? 'partial'
            : 'accepted',
        dimensions: <String, Object?>{
          'entry_count': transaction.crud.length,
          'rejected_count': sawRejection ? 1 : 0,
          'transaction_id': transaction.transactionId,
        },
      );

      if (sawConflict) {
        return UploadOutcome.conflicted;
      }
      return sawRejection ? UploadOutcome.rejected : UploadOutcome.accepted;
    } on NodexError catch (error) {
      return _handleUploadFailure(error, transaction);
    } on Object catch (error, stackTrace) {
      final NodexError mapped = NodexErrorMapper.map(
        error,
        operation: 'sync.upload',
      );
      _logger.error(
        _module,
        'Unclassified upload failure; the batch remains queued.',
        operation: 'sync.upload',
        outcome: 'retry_later',
        errorCode: mapped.code,
        stackTrace: stackTrace,
      );
      // Rethrowing keeps the batch queued: PowerSync retries after its
      // configured delay. Committing here would drop a clinical mutation.
      rethrow;
    }
  }

  /// Refuses a hard delete before any network call.
  ///
  /// Retirement is a status transition, never a delete. The guard runs inside
  /// [upload]'s try block so the resulting [IntegrityError] is classified and
  /// the transaction is completed instead of wedging the retry queue.
  void _rejectHardDeletes(List<CrudEntry> entries) {
    for (final CrudEntry entry in entries) {
      if (entry.op == UpdateType.delete) {
        throw IntegrityError(
          message:
              'A hard delete reached the upload path for table '
              '"${entry.table}". Clinical records are retired by status '
              'transition, never deleted.',
          subject: entry.table,
          code: 'hard_delete_attempted',
          context: <String, Object?>{'resource_type': entry.table},
        );
      }
    }
  }

  /// Routes a server-reported conflict through the entity's policy.
  void _handleConflict(CrudEntry entry, MutationDecision decision) {
    final ConflictPolicyEntry policy = ConflictPolicyRegistry.policyFor(
      entry.table,
    );

    if (policy.policy == ConflictPolicy.serverAuthoritative) {
      _logger.warning(
        _module,
        'Mutation conflicted; the server-authoritative policy discards the '
        'local projection and re-replicates the server value.',
        operation: 'sync.upload',
        outcome: UploadOutcome.conflicted.name,
        errorCode: decision.rejectionClass,
        dimensions: <String, Object?>{
          'resource_type': entry.table,
          'row_id': entry.id,
          'conflict_policy': policy.policy.wireValue,
        },
      );
      return;
    }

    // The batch stays queued for the reconciler. Completing it here would
    // silently discard a clinical fact the device recorded.
    throw SyncConflictError(
      message:
          'The server reported a conflict for table "${entry.table}"; the '
          'registered conflict policy must reconcile it.',
      resourceType: entry.table,
      policy: policy.policy.wireValue,
      requiresHumanReview: !policy.policy.isAutomatic,
      code: 'conflict',
      context: <String, Object?>{
        'resource_type': entry.table,
        'row_id': entry.id,
        'detail': decision.detail,
      },
    );
  }

  void _logRejection(CrudEntry entry, MutationDecision decision) {
    _logger.error(
      _module,
      'Mutation permanently rejected by the backend path.',
      operation: 'sync.upload',
      outcome: UploadOutcome.rejected.name,
      errorCode: decision.rejectionClass,
      dimensions: <String, Object?>{
        'resource_type': entry.table,
        'row_id': entry.id,
        'detail': decision.detail,
      },
    );
  }

  Future<UploadOutcome> _handleUploadFailure(
    NodexError error,
    CrudTransaction transaction,
  ) async {
    // Permanent rejections must leave the queue, or the client retries forever
    // against a server that will never accept the write. The mutation is recorded
    // as rejected so it stays visible in sync diagnostics.
    final bool isPermanent =
        error is ValidationError ||
        error is AuthorizationError ||
        error is IntegrityError;

    if (error is SyncConflictError) {
      _logger.warning(
        _module,
        'Upload conflicted; the entity conflict policy applies.',
        operation: 'sync.upload',
        outcome: UploadOutcome.conflicted.name,
        errorCode: error.code,
        dimensions: <String, Object?>{
          'resource_type': error.resourceType,
          'conflict_policy': error.policy,
          'requires_review': error.requiresHumanReview,
        },
      );

      final ConflictPolicyEntry entry = ConflictPolicyRegistry.policyFor(
        error.resourceType,
      );
      // Server-authoritative entities reconcile by discarding the local
      // projection and re-replicating. Everything else needs either an automatic
      // merge or a human decision, so the batch stays queued for the sync
      // reconciler rather than being dropped here.
      if (entry.policy == ConflictPolicy.serverAuthoritative) {
        await transaction.complete();
        return UploadOutcome.conflicted;
      }
      throw error;
    }

    if (isPermanent) {
      _logger.error(
        _module,
        'Upload permanently rejected; the mutation is retained for review.',
        operation: 'sync.upload',
        outcome: UploadOutcome.rejected.name,
        errorCode: error.code,
        dimensions: <String, Object?>{
          'entry_count': transaction.crud.length,
          'error_class': error.runtimeType.toString(),
        },
      );
      // Clearing the batch is safe only because the rejection has been recorded.
      await transaction.complete();
      return UploadOutcome.rejected;
    }

    _logger.warning(
      _module,
      'Upload failed transiently; the batch remains queued for retry.',
      operation: 'sync.upload',
      outcome: UploadOutcome.retryLater.name,
      errorCode: error.code,
    );
    throw error;
  }
}

/// One queue entry paired with the decision the server returned for it.
final class DecisionMatch {
  /// Creates a match.
  const DecisionMatch({required this.entry, required this.decision});

  /// The local queue entry.
  final CrudEntry entry;

  /// The server decision whose mutation id matched [entry].
  final MutationDecision decision;
}

/// Matches server decisions to queue entries by stable mutation id.
///
/// The server returns one decision per submitted mutation, but positional
/// coupling is unsafe: a short response would silently skip the tail of a
/// transaction, and a reordered response would apply the wrong decision to the
/// wrong row. Every decision must name an expected mutation id exactly once,
/// and the count must match. A mismatch throws a retryable [RemoteError] before
/// the caller completes the transaction.
List<DecisionMatch> matchMutationDecisions({
  required List<CrudEntry> entries,
  required int? transactionId,
  required List<MutationDecision> decisions,
}) {
  if (decisions.length != entries.length) {
    throw RemoteError(
      message:
          'The mutation path returned ${decisions.length} decisions for '
          '${entries.length} mutations.',
      isTransient: true,
      code: 'mutation_decision_count_mismatch',
      context: <String, Object?>{
        'expected': entries.length,
        'actual': decisions.length,
      },
    );
  }

  final Map<String, CrudEntry> expected = <String, CrudEntry>{};
  for (final CrudEntry entry in entries) {
    final String mutationId = NodexMutationId.forQueueEntry(
      transactionId: transactionId,
      clientId: entry.clientId,
    );
    if (expected.containsKey(mutationId)) {
      throw const RemoteError(
        message:
            'Two queue entries derived the same mutation id; the batch cannot '
            'be matched safely.',
        isTransient: true,
        code: 'mutation_decision_duplicate_entry',
      );
    }
    expected[mutationId] = entry;
  }

  final Set<String> seen = <String>{};
  final List<DecisionMatch> matches = <DecisionMatch>[];
  for (final MutationDecision decision in decisions) {
    final CrudEntry? entry = expected[decision.mutationId];
    if (entry == null) {
      throw const RemoteError(
        message:
            'The mutation path returned a decision for an unknown mutation id.',
        isTransient: true,
        code: 'mutation_decision_id_mismatch',
      );
    }
    if (!seen.add(decision.mutationId)) {
      throw const RemoteError(
        message:
            'The mutation path returned more than one decision for the same '
            'mutation id.',
        isTransient: true,
        code: 'mutation_decision_duplicate_id',
      );
    }
    matches.add(DecisionMatch(entry: entry, decision: decision));
  }

  if (matches.length != entries.length) {
    throw const RemoteError(
      message: 'The mutation path did not decide every submitted mutation.',
      isTransient: true,
      code: 'mutation_decision_missing',
    );
  }

  return matches;
}

/// Builds the upload payload for one chunk of a transaction.
///
/// [transactionId] and each entry's `clientId` are replayed unchanged by
/// PowerSync after a lost response, so the idempotency key and mutation id are
/// stable across retries.
List<Map<String, Object?>> buildMutationPayloadForEntries({
  required List<CrudEntry> entries,
  required int? transactionId,
  String? deviceId,
}) {
  return <Map<String, Object?>>[
    for (final CrudEntry entry in entries)
      () {
        final String stableKey = '${transactionId ?? 'tx'}-${entry.clientId}';
        return <String, Object?>{
          'id': NodexMutationId.forQueueEntry(
            transactionId: transactionId,
            clientId: entry.clientId,
          ),
          'operation': entry.op == UpdateType.put ? 'upsert' : 'patch',
          'table': entry.table,
          'row_id': entry.id,
          'idempotency_key': stableKey,
          'origin': 'online',
          'client_created_at': DateTime.now().toUtc().toIso8601String(),
          if (deviceId case final String bound) 'device_id': bound,
          'data': entry.opData ?? const <String, Object?>{},
        };
      }(),
  ];
}

/// Builds the upload payload for [transaction].
///
/// [deviceId], when supplied, is attached to every entry in the batch. It is
/// omitted otherwise rather than sent as null: the ledger records an unbound
/// mutation as unbound, and identity still rests on
/// (tenant_id, idempotency_key, actor).
///
/// A top-level function rather than a method so it can be exercised directly:
/// the connector needs a real gateway to construct, and this is pure.
List<Map<String, Object?>> buildMutationPayload(
  CrudTransaction transaction, {
  String? deviceId,
}) {
  return buildMutationPayloadForEntries(
    entries: transaction.crud,
    transactionId: transaction.transactionId,
    deviceId: deviceId,
  );
}
