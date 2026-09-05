/// Tests for the normalized error model and vendor error mapping.
///
/// Each error class in the specification carries required handling behavior:
/// authorization denials are never retried, connectivity failures allow local
/// continuation, persistence failures must not appear successful, and RLS
/// denials map to authorization rather than to a generic server error.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/errors/error_mapper.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';

void main() {
  group('error class handling contract', () {
    test('ValidationError is user-correctable and not retried', () {
      const ValidationError error = ValidationError(
        message: 'Dose is required.',
        fieldErrors: <String, String>{'dose': 'Enter a dose'},
      );

      expect(error.isRetryable, isFalse);
      expect(error.allowsLocalContinuation, isTrue);
      expect(error.requiresUserVisibility, isTrue);
      expect(error.fieldErrors.keys, contains('dose'));
    });

    test('AuthorizationError is never silently retried', () {
      const AuthorizationError error = AuthorizationError(
        message: 'Denied.',
        requiredPermission: 'prescription.finalize',
      );

      expect(error.isRetryable, isFalse);
      expect(error.requiresUserVisibility, isTrue);
    });

    test('ConnectivityError allows the local workflow to continue', () {
      const ConnectivityError error = ConnectivityError(message: 'Offline.');

      expect(error.isRetryable, isTrue);
      expect(error.allowsLocalContinuation, isTrue);
      // Working offline is a supported mode, not an error to interrupt the user.
      expect(error.requiresUserVisibility, isFalse);
    });

    test('SyncConflictError carries a deterministic policy', () {
      const SyncConflictError error = SyncConflictError(
        message: 'Conflict.',
        resourceType: 'patient',
        policy: 'field_level_merge',
        requiresHumanReview: true,
      );

      expect(error.isRetryable, isFalse);
      expect(error.allowsLocalContinuation, isTrue);
      expect(error.policy, 'field_level_merge');
      expect(error.requiresHumanReview, isTrue);
    });

    test('PersistenceError is not retryable and stays visible', () {
      const PersistenceError error = PersistenceError(message: 'Write failed.');

      expect(error.isRetryable, isFalse);
      expect(error.allowsLocalContinuation, isFalse);
      expect(error.requiresUserVisibility, isTrue);
    });

    test('RemoteError retries only when the server said it was transient', () {
      const RemoteError transient = RemoteError(
        message: 'Busy.',
        statusCode: 503,
        isTransient: true,
      );
      const RemoteError permanent = RemoteError(
        message: 'Rejected.',
        statusCode: 422,
      );

      expect(transient.isRetryable, isTrue);
      expect(permanent.isRetryable, isFalse);
    });

    test('AiUnavailableError directs the caller to a manual workflow', () {
      const AiUnavailableError error = AiUnavailableError(
        message: 'No approved model available.',
        engineKey: 'ai_triage_advisory',
        exhaustedCandidates: <String>['model_a', 'model_b'],
      );

      expect(error.isRetryable, isFalse);
      expect(error.allowsLocalContinuation, isTrue);
      expect(error.manualWorkflowAvailable, isTrue);
      expect(error.exhaustedCandidates, hasLength(2));
    });

    test('IntegrityError is terminal for the affected operation', () {
      const IntegrityError error = IntegrityError(
        message: 'Digest mismatch.',
        subject: 'authorization_snapshot',
      );

      expect(error.isRetryable, isFalse);
      expect(error.allowsLocalContinuation, isFalse);
      expect(error.requiresUserVisibility, isTrue);
    });

    test('toString includes the code without leaking the cause', () {
      const ValidationError error = ValidationError(
        message: 'Invalid.',
        code: 'bad_input',
        cause: 'raw vendor detail',
      );

      expect(error.toString(), contains('bad_input'));
      expect(error.toString(), contains('Invalid.'));
      expect(error.toString(), isNot(contains('raw vendor detail')));
    });
  });

  group('NodexErrorMapper.map', () {
    test('passes an already-normalized error through unchanged', () {
      const ValidationError original = ValidationError(message: 'Invalid.');
      expect(NodexErrorMapper.map(original), same(original));
    });

    test('maps TimeoutException to ConnectivityError', () {
      final NodexError mapped = NodexErrorMapper.map(
        TimeoutException('slow'),
        operation: 'data.select',
      );

      expect(mapped, isA<ConnectivityError>());
      expect(mapped.code, 'timeout');
      expect(mapped.context['operation'], 'data.select');
    });

    test('maps SocketException to ConnectivityError', () {
      expect(
        NodexErrorMapper.map(const SocketException('unreachable')),
        isA<ConnectivityError>(),
      );
    });

    test('maps FormatException to ValidationError', () {
      expect(
        NodexErrorMapper.map(const FormatException('bad json')),
        isA<ValidationError>(),
      );
    });

    test('maps an unknown object to PersistenceError, not to success', () {
      // A clinical write of unknown outcome must never appear to have committed.
      final NodexError mapped = NodexErrorMapper.map(Object());

      expect(mapped, isA<PersistenceError>());
      expect(mapped.code, 'unclassified');
    });
  });

  group('NodexErrorMapper.mapPostgres', () {
    test('maps an RLS denial (42501) to AuthorizationError', () {
      final NodexError mapped = NodexErrorMapper.mapPostgres(
        sqlState: PostgresErrorCode.insufficientPrivilege,
        message: 'new row violates row-level security policy',
        resourceType: 'prescriptions',
      );

      expect(mapped, isA<AuthorizationError>());
      expect(mapped.isRetryable, isFalse);
      expect(mapped.context['resource_type'], 'prescriptions');
    });

    test('maps a missing principal (28000) to AuthorizationError', () {
      expect(
        NodexErrorMapper.mapPostgres(
          sqlState: PostgresErrorCode.invalidAuthorization,
          message: 'authentication required',
        ),
        isA<AuthorizationError>(),
      );
    });

    test('maps a unique violation to RemoteError for idempotent retries', () {
      // A repeated idempotency key means the mutation already landed.
      final NodexError mapped = NodexErrorMapper.mapPostgres(
        sqlState: PostgresErrorCode.uniqueViolation,
        message: 'duplicate key value violates unique constraint',
      );

      expect(mapped, isA<RemoteError>());
    });

    test('maps constraint and guard violations to ValidationError', () {
      for (final String sqlState in <String>[
        PostgresErrorCode.checkViolation,
        PostgresErrorCode.notNullViolation,
        PostgresErrorCode.invalidParameterValue,
        PostgresErrorCode.raiseException,
      ]) {
        expect(
          NodexErrorMapper.mapPostgres(sqlState: sqlState, message: 'rejected'),
          isA<ValidationError>(),
          reason: '$sqlState should be user-correctable',
        );
      }
    });

    test('maps a foreign key violation to IntegrityError', () {
      // Referencing a row outside the device data scope is a scope fault.
      final NodexError mapped = NodexErrorMapper.mapPostgres(
        sqlState: PostgresErrorCode.foreignKeyViolation,
        message: 'violates foreign key constraint',
        resourceType: 'lab_results',
      );

      expect(mapped, isA<IntegrityError>());
      expect((mapped as IntegrityError).subject, 'lab_results');
    });

    test(
      'maps serialization failures to a transactional SyncConflictError',
      () {
        for (final String sqlState in <String>[
          PostgresErrorCode.serializationFailure,
          PostgresErrorCode.deadlockDetected,
        ]) {
          final NodexError mapped = NodexErrorMapper.mapPostgres(
            sqlState: sqlState,
            message: 'could not serialize access',
            resourceType: 'stock_movement',
          );

          expect(mapped, isA<SyncConflictError>());
          expect((mapped as SyncConflictError).policy, 'transactional');
        }
      },
    );

    test('falls back to HTTP status when no SQLSTATE is present', () {
      expect(
        NodexErrorMapper.mapPostgres(
          sqlState: null,
          message: 'forbidden',
          httpStatusCode: 403,
        ),
        isA<AuthorizationError>(),
      );

      expect(
        NodexErrorMapper.mapPostgres(
          sqlState: null,
          message: 'conflict',
          httpStatusCode: 409,
        ),
        isA<SyncConflictError>(),
      );

      final NodexError rateLimited = NodexErrorMapper.mapPostgres(
        sqlState: null,
        message: 'slow down',
        httpStatusCode: 429,
      );
      expect(rateLimited, isA<RemoteError>());
      expect(rateLimited.isRetryable, isTrue);

      expect(
        NodexErrorMapper.mapPostgres(
          sqlState: null,
          message: 'bad request',
          httpStatusCode: 400,
        ),
        isA<ValidationError>(),
      );

      final NodexError serverError = NodexErrorMapper.mapPostgres(
        sqlState: null,
        message: 'internal',
        httpStatusCode: 500,
      );
      expect(serverError, isA<RemoteError>());
      expect(serverError.isRetryable, isTrue);
    });

    test('produces a RemoteError when nothing identifies the failure', () {
      expect(
        NodexErrorMapper.mapPostgres(sqlState: null, message: 'unknown'),
        isA<RemoteError>(),
      );
    });

    test('records the sqlstate in the diagnostic context', () {
      final NodexError mapped = NodexErrorMapper.mapPostgres(
        sqlState: PostgresErrorCode.checkViolation,
        message: 'rejected',
        operation: 'data.upsert',
      );

      expect(mapped.context['sqlstate'], PostgresErrorCode.checkViolation);
      expect(mapped.context['operation'], 'data.upsert');
    });
  });
}
