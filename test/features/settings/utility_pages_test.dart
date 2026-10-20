/// Tests for the operational utilities (Module 53).
///
/// The utilities are opened when something has gone wrong, so the two
/// things they get wrong are bad in different ways: a size that is
/// misreported sends a support engineer to the wrong place, and a cache
/// clear that removes queued clinical work loses a result.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/features/settings/utility_pages.dart';

void main() {
  group('reading a size', () {
    test('bytes are read as bytes', () {
      expect(formatBytes(512), '512 B');
    });

    test('kilobytes are read as kilobytes', () {
      expect(formatBytes(2048), '2.0 KB');
    });

    test('megabytes are read as megabytes', () {
      expect(formatBytes(5 * 1024 * 1024), '5.0 MB');
    });

    test('a large size keeps one decimal', () {
      expect(formatBytes(123 * 1024 * 1024), '123 MB');
    });
  });

  group('reading a round trip', () {
    test('a fast round trip is good', () {
      expect(
        verdictFor(const Duration(milliseconds: 120)),
        LatencyVerdict.good,
      );
    });

    test('a round trip under a second is fair', () {
      expect(
        verdictFor(const Duration(milliseconds: 700)),
        LatencyVerdict.fair,
      );
    });

    test('a slow round trip is poor', () {
      expect(verdictFor(const Duration(seconds: 4)), LatencyVerdict.poor);
    });
  });

  group('the cache clear plan', () {
    test('the upload queue is never cleared', () {
      expect(
        CacheClearPlan.standard.withheld,
        contains(LocalTables.localMutationLog),
      );
      expect(
        CacheClearPlan.standard.removable,
        isNot(contains(LocalTables.localMutationLog)),
      );
    });

    test('the plan says why the queue is kept', () {
      expect(CacheClearPlan.standard.withheldReason, contains('server'));
    });

    test('the diagnostic buffer and the scratchpad are cleared', () {
      expect(
        CacheClearPlan.standard.removable,
        containsAll(<String>[
          LocalTables.localDiagnostics,
          LocalTables.scratchpads,
        ]),
      );
    });
  });
}
