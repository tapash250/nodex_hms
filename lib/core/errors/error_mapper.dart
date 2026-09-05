/// Maps transport-, database- and platform-specific failures onto the
/// normalized [NodexError] model.
///
/// This is the only place in the application permitted to interpret vendor
/// error shapes. Repositories call [NodexErrorMapper.map] so that no Supabase,
/// PostgreSQL or PowerSync error type escapes the data layer.
library;

import 'dart:async';
import 'dart:io';

import 'package:nodex_hms/core/errors/nodex_error.dart';

/// PostgreSQL error codes that NODEX interprets specifically.
///
/// See <https://www.postgresql.org/docs/current/errcodes-appendix.html>.
abstract final class PostgresErrorCode {
  /// `insufficient_privilege` - raised by RLS denials and NODEX guard triggers.
  static const String insufficientPrivilege = '42501';

  /// `invalid_authorization_specification` - no authenticated principal.
  static const String invalidAuthorization = '28000';

  /// `unique_violation` - typically a duplicate idempotency key on retry.
  static const String uniqueViolation = '23505';

  /// `foreign_key_violation` - references a row outside the device data scope.
  static const String foreignKeyViolation = '23503';

  /// `check_violation` - a domain invariant encoded as a table constraint.
  static const String checkViolation = '23514';

  /// `not_null_violation` - a required clinical field was absent.
  static const String notNullViolation = '23502';

  /// `serialization_failure` - concurrent transactional conflict.
  static const String serializationFailure = '40001';

  /// `deadlock_detected` - concurrent transactional conflict.
  static const String deadlockDetected = '40P01';

  /// `raise_exception` - explicit domain rejection raised by a PL/pgSQL guard.
  static const String raiseException = 'P0001';

  /// `invalid_parameter_value` - malformed client input rejected server-side.
  static const String invalidParameterValue = '22023';
}

/// Translates arbitrary caught objects into normalized NODEX errors.
abstract final class NodexErrorMapper {
  /// Converts [error] into a [NodexError].
  ///
  /// Already-normalized errors pass through unchanged. Unrecognised objects
  /// become [PersistenceError] rather than being reported as success, because a
  /// clinical write of unknown outcome must never appear to have committed.
  static NodexError map(
    Object error, {
    String? operation,
    Map<String, Object?> context = const <String, Object?>{},
  }) {
    if (error is NodexError) {
      return error;
    }

    final Map<String, Object?> mergedContext = <String, Object?>{
      'operation': ?operation,
      ...context,
    };

    if (error is TimeoutException) {
      return ConnectivityError(
        message: 'Operation timed out before the server responded.',
        code: 'timeout',
        context: mergedContext,
        cause: error,
      );
    }

    if (error is SocketException || error is HttpException) {
      return ConnectivityError(
        message: 'Network unreachable; continuing against the local database.',
        code: 'network_unreachable',
        context: mergedContext,
        cause: error,
      );
    }

    if (error is FormatException) {
      return ValidationError(
        message: 'Received a malformed payload that failed schema validation.',
        code: 'malformed_payload',
        context: mergedContext,
        cause: error,
      );
    }

    return PersistenceError(
      message: 'Unclassified failure; the operation outcome is unknown.',
      code: 'unclassified',
      context: mergedContext,
      cause: error,
    );
  }

  /// Maps a PostgreSQL/PostgREST failure identified by SQLSTATE [sqlState].
  ///
  /// Vendor SDK exceptions are unwrapped by the caller into their code, message
  /// and optional HTTP status so that this mapper stays free of SDK imports and
  /// remains unit-testable without a network or database.
  static NodexError mapPostgres({
    required String? sqlState,
    required String message,
    int? httpStatusCode,
    String? operation,
    String? resourceType,
    Map<String, Object?> context = const <String, Object?>{},
    Object? cause,
  }) {
    final Map<String, Object?> mergedContext = <String, Object?>{
      'operation': ?operation,
      'resource_type': ?resourceType,
      'sqlstate': ?sqlState,
      ...context,
    };

    switch (sqlState) {
      case PostgresErrorCode.insufficientPrivilege:
      case PostgresErrorCode.invalidAuthorization:
        return AuthorizationError(
          message: 'Server-side authorization denied this operation.',
          code: sqlState,
          context: mergedContext,
          cause: cause,
        );

      case PostgresErrorCode.uniqueViolation:
        // A repeated idempotency key means the mutation already landed. The
        // caller treats this as an already-applied write, not a new failure.
        return RemoteError(
          message: 'The server already holds a record for this operation.',
          code: sqlState,
          statusCode: httpStatusCode,
          context: mergedContext,
          cause: cause,
        );

      case PostgresErrorCode.checkViolation:
      case PostgresErrorCode.notNullViolation:
      case PostgresErrorCode.invalidParameterValue:
      case PostgresErrorCode.raiseException:
        return ValidationError(
          message: 'The server rejected this operation as invalid.',
          code: sqlState,
          context: mergedContext,
          cause: cause,
        );

      case PostgresErrorCode.foreignKeyViolation:
        return IntegrityError(
          message: 'The operation referenced a record outside this device data scope.',
          subject: resourceType ?? 'unknown_resource',
          code: sqlState,
          context: mergedContext,
          cause: cause,
        );

      case PostgresErrorCode.serializationFailure:
      case PostgresErrorCode.deadlockDetected:
        return SyncConflictError(
          message: 'A concurrent transaction conflicted with this operation.',
          resourceType: resourceType ?? 'unknown_resource',
          policy: 'transactional',
          code: sqlState,
          context: mergedContext,
          cause: cause,
        );
    }

    return _mapHttpStatus(
      httpStatusCode: httpStatusCode,
      message: message,
      context: mergedContext,
      cause: cause,
    );
  }

  static NodexError _mapHttpStatus({
    required int? httpStatusCode,
    required String message,
    required Map<String, Object?> context,
    Object? cause,
  }) {
    if (httpStatusCode == null) {
      return RemoteError(
        message: 'The server rejected this operation.',
        context: context,
        cause: cause,
      );
    }

    if (httpStatusCode == 401 || httpStatusCode == 403) {
      return AuthorizationError(
        message: 'The server denied access to this resource.',
        code: 'http_$httpStatusCode',
        context: context,
        cause: cause,
      );
    }

    if (httpStatusCode == 409) {
      return SyncConflictError(
        message: 'The server reported a conflicting state for this resource.',
        resourceType: context['resource_type'] as String? ?? 'unknown_resource',
        policy: 'server_authoritative',
        code: 'http_409',
        context: context,
        cause: cause,
      );
    }

    if (httpStatusCode == 408 || httpStatusCode == 429) {
      return RemoteError(
        message: 'The server asked the client to retry later.',
        statusCode: httpStatusCode,
        isTransient: true,
        code: 'http_$httpStatusCode',
        context: context,
        cause: cause,
      );
    }

    if (httpStatusCode >= 400 && httpStatusCode < 500) {
      return ValidationError(
        message: 'The server rejected this request as invalid.',
        code: 'http_$httpStatusCode',
        context: context,
        cause: cause,
      );
    }

    return RemoteError(
      message: 'The server failed to process this request.',
      statusCode: httpStatusCode,
      isTransient: true,
      code: 'http_$httpStatusCode',
      context: context,
      cause: cause,
    );
  }
}
