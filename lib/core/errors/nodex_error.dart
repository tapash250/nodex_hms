/// Normalized NODEX error model.
///
/// The specification defines a fixed set of error classes, each with required
/// handling behavior. Every layer below the presentation layer converts its
/// transport-, database- or provider-specific failures into one of these
/// classes, so that controllers reason about failure semantics rather than
/// about which SDK produced the error.
///
/// Handling contract (from the specification error model):
///
/// | Class                | Required behavior                                     |
/// |----------------------|-------------------------------------------------------|
/// | [ValidationError]    | User-correctable input problem                         |
/// | [AuthorizationError] | Access denied; never silently retried                 |
/// | [ConnectivityError]  | Local workflow continues where supported              |
/// | [SyncConflictError]  | Policy-driven merge/reconciliation                    |
/// | [PersistenceError]   | Clinical action must not appear successful             |
/// | [RemoteError]        | Server rejection remains visible until resolved       |
/// | [AiUnavailableError] | Fallback to manual workflow or deterministic tools     |
/// | [IntegrityError]     | Quarantine the operation and raise a high-priority event |
library;

import 'package:meta/meta.dart';

/// Base class for every normalized NODEX failure.
///
/// Carries only non-PHI diagnostic context. Implementations must not place
/// patient-identifying data in [message] or [context], because these values may
/// reach diagnostic sinks.
@immutable
sealed class NodexError implements Exception {
  /// Creates a normalized error.
  const NodexError({
    required this.message,
    this.code,
    this.context = const <String, Object?>{},
    this.cause,
  });

  /// Operator- and developer-facing description. Never contains PHI.
  final String message;

  /// Stable machine-readable code, where the originating layer provides one.
  final String? code;

  /// Non-PHI diagnostic context, safe to attach to telemetry.
  final Map<String, Object?> context;

  /// The originating error, retained for local debugging only.
  final Object? cause;

  /// Whether an automatic retry of the same operation is permitted.
  ///
  /// Authorization denials, validation failures and integrity faults are never
  /// retried automatically: doing so would either loop or mask a real fault.
  bool get isRetryable;

  /// Whether the local clinical workflow may continue despite this failure.
  bool get allowsLocalContinuation => false;

  /// Whether this failure must be surfaced to the user until explicitly resolved.
  bool get requiresUserVisibility => true;

  @override
  String toString() {
    final String codePart = code == null ? '' : ' [$code]';
    return '$runtimeType$codePart: $message';
  }
}

/// A user-correctable input problem detected by domain validation.
final class ValidationError extends NodexError {
  /// Creates a validation failure, optionally describing per-field problems.
  const ValidationError({
    required super.message,
    this.fieldErrors = const <String, String>{},
    super.code,
    super.context,
    super.cause,
  });

  /// Field name to human-readable problem description.
  ///
  /// Keys are field identifiers, not values, so this map carries no PHI.
  final Map<String, String> fieldErrors;

  @override
  bool get isRetryable => false;

  @override
  bool get allowsLocalContinuation => true;
}

/// Access was denied.
///
/// Raised by client-side offline authorization checks, by the backend mutation
/// path, and by PostgreSQL row level security. Never retried automatically.
final class AuthorizationError extends NodexError {
  /// Creates an authorization denial.
  const AuthorizationError({
    required super.message,
    this.requiredPermission,
    this.requiresOnlineRevalidation = false,
    super.code,
    super.context,
    super.cause,
  });

  /// The permission key that would have been required, when known.
  final String? requiredPermission;

  /// Whether the action could succeed after an online authorization refresh.
  ///
  /// True for privileged actions attempted from an offline snapshot; false for
  /// actions the principal is not entitled to perform at all.
  final bool requiresOnlineRevalidation;

  @override
  bool get isRetryable => false;
}

/// The network was unavailable or unreachable.
///
/// Local-first workflows continue against the local operational projection; the
/// mutation remains queued for upload.
final class ConnectivityError extends NodexError {
  /// Creates a connectivity failure.
  const ConnectivityError({
    required super.message,
    super.code,
    super.context,
    super.cause,
  });

  @override
  bool get isRetryable => true;

  @override
  bool get allowsLocalContinuation => true;

  @override
  bool get requiresUserVisibility => false;
}

/// A synchronization conflict requiring policy-driven reconciliation.
///
/// The conflict is never resolved by an undocumented global last-write-wins
/// rule; [policy] names the deterministic per-entity strategy that applies.
final class SyncConflictError extends NodexError {
  /// Creates a synchronization conflict.
  const SyncConflictError({
    required super.message,
    required this.resourceType,
    required this.policy,
    this.requiresHumanReview = false,
    this.conflictRecordId,
    super.code,
    super.context,
    super.cause,
  });

  /// The entity type whose write conflicted.
  final String resourceType;

  /// The deterministic conflict strategy that governs this entity.
  final String policy;

  /// Whether reconciliation requires a human decision rather than an automatic merge.
  final bool requiresHumanReview;

  /// Server-side conflict record identifier, when one has been created.
  final String? conflictRecordId;

  @override
  bool get isRetryable => false;

  @override
  bool get allowsLocalContinuation => true;
}

/// A local persistence failure.
///
/// A clinical action that hit this error must not appear successful in the UI:
/// the write did not commit to the local operational projection.
final class PersistenceError extends NodexError {
  /// Creates a local persistence failure.
  const PersistenceError({
    required super.message,
    super.code,
    super.context,
    super.cause,
  });

  @override
  bool get isRetryable => false;
}

/// The server rejected the operation.
///
/// Remains visible until resolved; a rejected mutation is never silently
/// discarded from the upload queue.
final class RemoteError extends NodexError {
  /// Creates a server-side rejection.
  const RemoteError({
    required super.message,
    this.statusCode,
    this.isTransient = false,
    super.code,
    super.context,
    super.cause,
  });

  /// HTTP status code, when the transport provided one.
  final int? statusCode;

  /// Whether the server indicated a transient condition such as 429 or 503.
  final bool isTransient;

  @override
  bool get isRetryable => isTransient;
}

/// No approved AI execution path was available.
///
/// Core workflows must remain usable when AI services are unavailable, so this
/// error directs the caller to a deterministic tool or a manual workflow.
final class AiUnavailableError extends NodexError {
  /// Creates an AI-unavailable failure.
  const AiUnavailableError({
    required super.message,
    required this.engineKey,
    this.exhaustedCandidates = const <String>[],
    this.manualWorkflowAvailable = true,
    super.code,
    super.context,
    super.cause,
  });

  /// The NODEX AI engine that could not be executed.
  final String engineKey;

  /// Model keys that were attempted and failed, in routing order.
  final List<String> exhaustedCandidates;

  /// Whether a manual workflow exists for this task.
  final bool manualWorkflowAvailable;

  @override
  bool get isRetryable => false;

  @override
  bool get allowsLocalContinuation => true;
}

/// A data or cryptographic integrity fault.
///
/// The affected operation is quarantined and a high-priority diagnostic event is
/// raised. Integrity faults are never retried and never silently absorbed.
final class IntegrityError extends NodexError {
  /// Creates an integrity fault.
  const IntegrityError({
    required super.message,
    required this.subject,
    super.code,
    super.context,
    super.cause,
  });

  /// What failed verification, for example `authorization_snapshot` or `local_database`.
  final String subject;

  @override
  bool get isRetryable => false;
}
