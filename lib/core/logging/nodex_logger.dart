/// Privacy-preserving diagnostic logging.
///
/// The specification prohibits PHI in general-purpose application logs. This
/// logger enforces that structurally: log call sites accept a fixed set of
/// non-PHI dimensions (module, operation, outcome, identifiers of
/// infrastructure objects) and a free-text message that is redacted before it
/// reaches any sink.
///
/// Redaction is deliberately conservative. It is a safety net, not a licence to
/// pass clinical content into a log call.
library;

import 'package:logging/logging.dart' as logging;
import 'package:meta/meta.dart';

/// Severity levels used by NODEX diagnostics.
enum NodexLogLevel {
  /// Fine-grained tracing, disabled in release builds.
  trace(500),

  /// Normal operational events.
  info(800),

  /// Recoverable anomalies worth investigating.
  warning(900),

  /// Failures affecting a user-visible operation.
  error(1000),

  /// Faults requiring immediate operator attention, such as integrity failures.
  critical(1200);

  const NodexLogLevel(this.value);

  /// Numeric severity, aligned with `package:logging` levels.
  final int value;

  /// The `package:logging` level corresponding to this severity.
  logging.Level get asLoggingLevel => logging.Level('NODEX', value);
}

/// A single redacted diagnostic record.
@immutable
final class NodexLogRecord {
  /// Creates a diagnostic record.
  const NodexLogRecord({
    required this.level,
    required this.module,
    required this.message,
    required this.timestamp,
    this.operation,
    this.outcome,
    this.dimensions = const <String, Object?>{},
    this.errorCode,
    this.stackTrace,
  });

  /// Severity of the record.
  final NodexLogLevel level;

  /// Emitting module or subsystem, for example `sync` or `ai.orchestrator`.
  final String module;

  /// Redacted human-readable message.
  final String message;

  /// When the record was created.
  final DateTime timestamp;

  /// The operation being performed, for example `prescription.save_draft`.
  final String? operation;

  /// Result of the operation, for example `succeeded` or `rejected`.
  final String? outcome;

  /// Additional non-PHI dimensions.
  final Map<String, Object?> dimensions;

  /// Normalized error code, when the record describes a failure.
  final String? errorCode;

  /// Stack trace, retained locally for failure diagnosis.
  final StackTrace? stackTrace;
}

/// Destination for redacted diagnostic records.
abstract interface class NodexLogSink {
  /// Writes [record] to the destination.
  void write(NodexLogRecord record);
}

/// Forwards records to `package:logging`, which the app bootstrap wires to a
/// platform sink. Used in debug and profile builds.
final class LoggingPackageSink implements NodexLogSink {
  /// Creates a sink writing to the `package:logging` root logger.
  LoggingPackageSink([logging.Logger? logger])
    : _logger = logger ?? logging.Logger('nodex');

  final logging.Logger _logger;

  @override
  void write(NodexLogRecord record) {
    final StringBuffer buffer = StringBuffer()
      ..write('[')
      ..write(record.module)
      ..write(']');

    if (record.operation != null) {
      buffer
        ..write(' ')
        ..write(record.operation);
    }
    if (record.outcome != null) {
      buffer
        ..write(' outcome=')
        ..write(record.outcome);
    }
    if (record.errorCode != null) {
      buffer
        ..write(' code=')
        ..write(record.errorCode);
    }
    buffer
      ..write(' ')
      ..write(record.message);

    for (final MapEntry<String, Object?> entry in record.dimensions.entries) {
      buffer
        ..write(' ')
        ..write(entry.key)
        ..write('=')
        ..write(entry.value);
    }

    _logger.log(
      record.level.asLoggingLevel,
      buffer.toString(),
      null,
      record.stackTrace,
    );
  }
}

/// Retains records in memory. Used by tests and by the on-device diagnostics
/// screen, which shows recent sync and AI activity without exposing PHI.
final class InMemoryLogSink implements NodexLogSink {
  /// Creates an in-memory sink retaining at most [capacity] records.
  InMemoryLogSink({this.capacity = 500})
    : assert(capacity > 0, 'capacity must be positive');

  /// Maximum number of retained records.
  final int capacity;

  final List<NodexLogRecord> _records = <NodexLogRecord>[];

  /// Records retained so far, oldest first.
  List<NodexLogRecord> get records =>
      List<NodexLogRecord>.unmodifiable(_records);

  @override
  void write(NodexLogRecord record) {
    _records.add(record);
    if (_records.length > capacity) {
      _records.removeRange(0, _records.length - capacity);
    }
  }

  /// Discards all retained records, for example on sign-out.
  void clear() => _records.clear();
}

/// Redacts values that resemble patient-identifying or secret material.
///
/// The patterns cover the shapes most likely to be interpolated into a message
/// by accident: bearer tokens and JWTs, long digit runs such as national IDs and
/// phone numbers, email addresses, dates of birth, and `key=value` pairs whose
/// key names denote identity fields.
abstract final class LogRedactor {
  static const String _mask = '[redacted]';

  static final List<RegExp> _patterns = <RegExp>[
    // JWTs and bearer tokens.
    RegExp(r'\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]+'),
    RegExp(r'\b[Bb]earer\s+[A-Za-z0-9._\-]+'),
    // Email addresses.
    RegExp(r'\b[\w.+-]+@[\w-]+\.[\w.-]+\b'),
    // ISO dates, which in a clinical message are usually a date of birth.
    RegExp(r'\b\d{4}-\d{2}-\d{2}(?:[T ]\d{2}:\d{2}(?::\d{2})?)?\b'),
    // Runs of 7 or more digits: national IDs, phone numbers, MRNs.
    RegExp(r'\b\d{7,}\b'),
    // Identity-bearing key/value pairs.
    RegExp(
      r'\b(?:name|patient|patient_name|mrn|nid|phone|mobile|email|address|dob|guardian)'
      r'\s*[:=]\s*[^\s,;}]+',
      caseSensitive: false,
    ),
  ];

  /// Returns [input] with recognised sensitive substrings replaced.
  static String redact(String input) {
    String output = input;
    for (final RegExp pattern in _patterns) {
      output = output.replaceAll(pattern, _mask);
    }
    return output;
  }

  /// Returns [dimensions] with disallowed keys removed and values redacted.
  ///
  /// Only scalar values survive: a nested structure could carry a clinical
  /// payload wholesale, so maps and lists are dropped rather than walked.
  static Map<String, Object?> redactDimensions(
    Map<String, Object?> dimensions,
  ) {
    final Map<String, Object?> safe = <String, Object?>{};
    for (final MapEntry<String, Object?> entry in dimensions.entries) {
      if (_isDisallowedKey(entry.key)) {
        safe[entry.key] = _mask;
        continue;
      }
      final Object? value = entry.value;
      if (value == null || value is num || value is bool) {
        safe[entry.key] = value;
      } else if (value is String) {
        safe[entry.key] = redact(value);
      } else if (value is Duration) {
        safe[entry.key] = value.inMilliseconds;
      } else {
        safe[entry.key] = _mask;
      }
    }
    return safe;
  }

  static final RegExp _disallowedKey = RegExp(
    '(name|patient|mrn|nid|phone|mobile|email|address|dob|note|diagnosis|'
    'medication|token|secret|password|key)',
    caseSensitive: false,
  );

  static bool _isDisallowedKey(String key) {
    // Structural identifiers are safe: they name infrastructure objects, not people.
    const Set<String> allowed = <String>{
      'engine_key',
      'model_key',
      'permission_key',
      'role_key',
      'idempotency_key',
      'stream_key',
      'policy_key',
    };
    if (allowed.contains(key)) {
      return false;
    }
    return _disallowedKey.hasMatch(key);
  }
}

/// Application logger. Every record is redacted before reaching a sink.
final class NodexLogger {
  /// Creates a logger writing to [sinks] at or above [minimumLevel].
  NodexLogger({
    required List<NodexLogSink> sinks,
    this.minimumLevel = NodexLogLevel.info,
  }) : _sinks = List<NodexLogSink>.unmodifiable(sinks);

  final List<NodexLogSink> _sinks;

  /// Records below this severity are discarded.
  final NodexLogLevel minimumLevel;

  /// Emits a trace-level record.
  void trace(
    String module,
    String message, {
    String? operation,
    Map<String, Object?> dimensions = const <String, Object?>{},
  }) => _emit(
    NodexLogLevel.trace,
    module,
    message,
    operation: operation,
    dimensions: dimensions,
  );

  /// Emits an info-level record.
  void info(
    String module,
    String message, {
    String? operation,
    String? outcome,
    Map<String, Object?> dimensions = const <String, Object?>{},
  }) => _emit(
    NodexLogLevel.info,
    module,
    message,
    operation: operation,
    outcome: outcome,
    dimensions: dimensions,
  );

  /// Emits a warning-level record.
  void warning(
    String module,
    String message, {
    String? operation,
    String? outcome,
    String? errorCode,
    Map<String, Object?> dimensions = const <String, Object?>{},
  }) => _emit(
    NodexLogLevel.warning,
    module,
    message,
    operation: operation,
    outcome: outcome,
    errorCode: errorCode,
    dimensions: dimensions,
  );

  /// Emits an error-level record.
  void error(
    String module,
    String message, {
    String? operation,
    String? outcome,
    String? errorCode,
    StackTrace? stackTrace,
    Map<String, Object?> dimensions = const <String, Object?>{},
  }) => _emit(
    NodexLogLevel.error,
    module,
    message,
    operation: operation,
    outcome: outcome,
    errorCode: errorCode,
    stackTrace: stackTrace,
    dimensions: dimensions,
  );

  /// Emits a critical record, used for integrity and security faults.
  void critical(
    String module,
    String message, {
    String? operation,
    String? outcome,
    String? errorCode,
    StackTrace? stackTrace,
    Map<String, Object?> dimensions = const <String, Object?>{},
  }) => _emit(
    NodexLogLevel.critical,
    module,
    message,
    operation: operation,
    outcome: outcome,
    errorCode: errorCode,
    stackTrace: stackTrace,
    dimensions: dimensions,
  );

  void _emit(
    NodexLogLevel level,
    String module,
    String message, {
    String? operation,
    String? outcome,
    String? errorCode,
    StackTrace? stackTrace,
    Map<String, Object?> dimensions = const <String, Object?>{},
  }) {
    if (level.value < minimumLevel.value) {
      return;
    }

    final NodexLogRecord record = NodexLogRecord(
      level: level,
      module: module,
      message: LogRedactor.redact(message),
      timestamp: DateTime.now().toUtc(),
      operation: operation,
      outcome: outcome,
      errorCode: errorCode,
      stackTrace: stackTrace,
      dimensions: LogRedactor.redactDimensions(dimensions),
    );

    for (final NodexLogSink sink in _sinks) {
      sink.write(record);
    }
  }
}
