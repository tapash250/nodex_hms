/// Tests for privacy-preserving diagnostic logging.
///
/// The specification prohibits PHI in general-purpose application logs. These
/// tests assert the redaction net catches the shapes most likely to be
/// interpolated into a log message by accident, and that structural identifiers
/// used for diagnosis survive.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';

void main() {
  group('LogRedactor.redact', () {
    test('redacts JWTs', () {
      const String message =
          'token eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.abc123def';
      expect(LogRedactor.redact(message), isNot(contains('eyJhbGciOiJIUzI1')));
      expect(LogRedactor.redact(message), contains('[redacted]'));
    });

    test('redacts bearer tokens', () {
      expect(
        LogRedactor.redact('Authorization: Bearer sk-abc123.def456'),
        isNot(contains('sk-abc123')),
      );
    });

    test('redacts email addresses', () {
      final String output = LogRedactor.redact(
        'contacting nurse.rahman@hospital.example for handover',
      );
      expect(output, isNot(contains('nurse.rahman@hospital.example')));
      expect(output, contains('[redacted]'));
    });

    test('redacts ISO dates, which are usually a date of birth', () {
      expect(
        LogRedactor.redact('patient born 1984-03-17'),
        isNot(contains('1984-03-17')),
      );
    });

    test('redacts long digit runs such as MRNs and phone numbers', () {
      expect(
        LogRedactor.redact('MRN 1234567890 admitted'),
        isNot(contains('1234567890')),
      );
      expect(
        LogRedactor.redact('mobile 01712345678'),
        isNot(contains('01712345678')),
      );
    });

    test('redacts identity-bearing key/value pairs', () {
      final String output = LogRedactor.redact(
        'patient_name=Abdul Karim diagnosis recorded',
      );
      expect(output, isNot(contains('Abdul')));
    });

    test('leaves short numbers and clinical vocabulary intact', () {
      // Diagnostic values such as counts, durations and status codes must survive
      // or the logs become useless for troubleshooting.
      const String message = 'uploaded 12 mutations in 340 ms, status 200';
      expect(LogRedactor.redact(message), message);
    });
  });

  group('LogRedactor.redactDimensions', () {
    test('keeps scalar values', () {
      final Map<String, Object?> safe = LogRedactor.redactDimensions(
        <String, Object?>{
          'attempt_number': 2,
          'latency_ms': 340,
          'succeeded': true,
          'nullable': null,
        },
      );

      expect(safe['attempt_number'], 2);
      expect(safe['latency_ms'], 340);
      expect(safe['succeeded'], isTrue);
      expect(safe['nullable'], isNull);
    });

    test('masks identity-bearing keys', () {
      final Map<String, Object?> safe = LogRedactor.redactDimensions(
        <String, Object?>{
          'patient_id': 'abc-123',
          'full_name': 'Abdul Karim',
          'phone': '01712345678',
        },
      );

      expect(safe['patient_id'], '[redacted]');
      expect(safe['full_name'], '[redacted]');
      expect(safe['phone'], '[redacted]');
    });

    test('preserves structural identifiers used for diagnosis', () {
      final Map<String, Object?> safe = LogRedactor.redactDimensions(
        <String, Object?>{
          'engine_key': 'ai_triage_advisory',
          'model_key': 'clinical_reasoning_cloud_01',
          'permission_key': 'prescription.finalize',
          'role_key': 'nursing_staff',
          'idempotency_key': 'mutation-9',
        },
      );

      expect(safe['engine_key'], 'ai_triage_advisory');
      expect(safe['model_key'], 'clinical_reasoning_cloud_01');
      expect(safe['permission_key'], 'prescription.finalize');
      expect(safe['role_key'], 'nursing_staff');
      expect(safe['idempotency_key'], 'mutation-9');
    });

    test('drops nested structures rather than walking them', () {
      // A nested map could carry a clinical payload wholesale.
      final Map<String, Object?> safe = LogRedactor.redactDimensions(
        <String, Object?>{
          'payload': <String, Object?>{'diagnosis': 'sensitive'},
          'items': <String>['a', 'b'],
        },
      );

      expect(safe['payload'], '[redacted]');
      expect(safe['items'], '[redacted]');
    });

    test('converts Duration to milliseconds', () {
      final Map<String, Object?> safe = LogRedactor.redactDimensions(
        <String, Object?>{'elapsed': const Duration(milliseconds: 250)},
      );
      expect(safe['elapsed'], 250);
    });

    test('redacts string values as well as keys', () {
      final Map<String, Object?> safe = LogRedactor.redactDimensions(
        <String, Object?>{'detail': 'failed for 1234567890'},
      );
      expect(safe['detail'], isNot(contains('1234567890')));
    });
  });

  group('NodexLogger', () {
    test('redacts the message before it reaches a sink', () {
      final InMemoryLogSink sink = InMemoryLogSink();
      final NodexLogger logger = NodexLogger(
        sinks: <NodexLogSink>[sink],
        minimumLevel: NodexLogLevel.trace,
      );

      logger.info('sync', 'uploaded record for patient MRN 9988776655');

      expect(sink.records, hasLength(1));
      expect(sink.records.single.message, isNot(contains('9988776655')));
    });

    test('discards records below the minimum level', () {
      final InMemoryLogSink sink = InMemoryLogSink();
      final NodexLogger logger = NodexLogger(
        sinks: <NodexLogSink>[sink],
        minimumLevel: NodexLogLevel.warning,
      );

      logger.trace('sync', 'trace');
      logger.info('sync', 'info');
      logger.warning('sync', 'warning');
      logger.error('sync', 'error');
      logger.critical('sync', 'critical');

      expect(sink.records.map((NodexLogRecord r) => r.level), <NodexLogLevel>[
        NodexLogLevel.warning,
        NodexLogLevel.error,
        NodexLogLevel.critical,
      ]);
    });

    test('records module, operation, outcome and error code', () {
      final InMemoryLogSink sink = InMemoryLogSink();
      final NodexLogger logger = NodexLogger(
        sinks: <NodexLogSink>[sink],
        minimumLevel: NodexLogLevel.trace,
      );

      logger.error(
        'ai.orchestrator',
        'attempt failed',
        operation: 'orchestrator.run',
        outcome: 'failed',
        errorCode: 'timeout',
        dimensions: <String, Object?>{'attempt_number': 2},
      );

      final NodexLogRecord record = sink.records.single;
      expect(record.module, 'ai.orchestrator');
      expect(record.operation, 'orchestrator.run');
      expect(record.outcome, 'failed');
      expect(record.errorCode, 'timeout');
      expect(record.dimensions['attempt_number'], 2);
      expect(record.timestamp.isUtc, isTrue);
    });

    test('fans out to every configured sink', () {
      final InMemoryLogSink first = InMemoryLogSink();
      final InMemoryLogSink second = InMemoryLogSink();
      final NodexLogger logger = NodexLogger(
        sinks: <NodexLogSink>[first, second],
        minimumLevel: NodexLogLevel.trace,
      );

      logger.info('sync', 'event');

      expect(first.records, hasLength(1));
      expect(second.records, hasLength(1));
    });
  });

  group('InMemoryLogSink', () {
    test('bounds retention at its capacity', () {
      final InMemoryLogSink sink = InMemoryLogSink(capacity: 3);
      final NodexLogger logger = NodexLogger(
        sinks: <NodexLogSink>[sink],
        minimumLevel: NodexLogLevel.trace,
      );

      for (int i = 0; i < 10; i++) {
        logger.info('sync', 'event $i');
      }

      expect(sink.records, hasLength(3));
      // Oldest evicted first.
      expect(sink.records.first.message, 'event 7');
      expect(sink.records.last.message, 'event 9');
    });

    test('clear discards retained records', () {
      final InMemoryLogSink sink = InMemoryLogSink();
      final NodexLogger logger = NodexLogger(
        sinks: <NodexLogSink>[sink],
        minimumLevel: NodexLogLevel.trace,
      );

      logger.info('sync', 'event');
      sink.clear();

      expect(sink.records, isEmpty);
    });
  });
}
