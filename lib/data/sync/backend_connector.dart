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

  static const String _module = 'sync.connector';

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

    // Delete entries never enter the batch loop: the connector refuses them
    // before any network call, because retirement is a status transition.
    for (final CrudEntry entry in transaction.crud) {
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

    try {
      final String? deviceId = _deviceId?.call();
      final List<Map<String, Object?>> payload = buildUploadPayload(
        transaction,
        deviceId: deviceId,
      );

      final List<MutationDecision> decisions = await _gateway.submitMutations(
        payload,
        deviceId: deviceId,
      );

      // Map every decision before completing the batch. A rejected entry
      // means the server permanently refused it: the local row stays, but the
      // queue entry is cleared because retrying can never succeed, and the
      // rejection is logged for sync diagnostics.
      bool sawRejection = false;
      for (int i = 0; i < decisions.length; i++) {
        final MutationDecision decision = decisions[i];
        final CrudEntry entry = transaction.crud[i];

        switch (decision.outcome) {
          case MutationOutcome.applied:
          case MutationOutcome.alreadyApplied:
            break;
          case MutationOutcome.rejected:
            sawRejection = true;
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
      }

      await transaction.complete();

      _logger.info(
        _module,
        'Uploaded a local mutation transaction${sawRejection ? ' with rejections' : ''}.',
        operation: 'sync.upload',
        outcome: sawRejection ? 'partial' : 'accepted',
        dimensions: <String, Object?>{
          'entry_count': transaction.crud.length,
          'rejected_count': decisions
              .where(
                (MutationDecision d) => d.outcome == MutationOutcome.rejected,
              )
              .length,
          'transaction_id': transaction.transactionId,
        },
      );
    } on NodexError catch (error) {
      await _handleUploadFailure(error, transaction);
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

  Future<void> _handleUploadFailure(
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
        return;
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
      return;
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

  /// Builds the upload payload for [transaction].
  ///
  /// Exposed so the payload's shape is testable without a live PowerSync
  /// database; [uploadData] is the only production caller.
  List<Map<String, Object?>> buildUploadPayload(
    CrudTransaction transaction, {
    String? deviceId,
  }) => buildMutationPayload(transaction, deviceId: deviceId);
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
  return <Map<String, Object?>>[
    for (final CrudEntry entry in transaction.crud)
      () {
        // Stable across retries: PowerSync replays the same transactionId
        // and clientId after a lost response, so the idempotency ledger
        // recognises the retry instead of applying it twice.
        final String stableKey =
            '${transaction.transactionId ?? 'tx'}-${entry.clientId}';
        return <String, Object?>{
          'id': NodexMutationId.forQueueEntry(
            transactionId: transaction.transactionId,
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
