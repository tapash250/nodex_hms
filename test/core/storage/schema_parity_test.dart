/// Cross-artifact schema parity.
///
/// The local PowerSync schema, the replication rules, the server migrations and
/// the mutation-handler registry are four separate descriptions of the same
/// tables. They are edited by hand, in different languages, and a mismatch is
/// silent: a bucket whose table is missing locally simply never materializes,
/// and a table registered as append-only in the client is still mutable in
/// PostgreSQL.
///
/// These tests read the artifacts directly and assert the invariants. They are
/// intentionally structural rather than semantic: they do not prove a column
/// type agrees, they prove the four descriptions agree on which tables exist and
/// which of them are immutable.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';

/// Tables that exist only on the device and are never replicated.
const Set<String> _localOnlyTables = <String>{
  'local_mutation_log',
  'local_diagnostics',
};

String _read(String relativePath) {
  final File file = File(relativePath);
  expect(
    file.existsSync(),
    isTrue,
    reason: 'Expected $relativePath to exist relative to the package root.',
  );
  return file.readAsStringSync();
}

/// Table names created by the migration set.
Set<String> _migrationTables() {
  final RegExp pattern = RegExp(
    r'create table (?:if not exists )?public\.([a-z_]+)',
    caseSensitive: false,
  );
  final Set<String> tables = <String>{};
  final Directory directory = Directory('supabase/migrations');
  for (final FileSystemEntity entity in directory.listSync()) {
    if (entity is! File || !entity.path.endsWith('.sql')) {
      continue;
    }
    for (final RegExpMatch match in pattern.allMatches(
      entity.readAsStringSync(),
    )) {
      tables.add(match.group(1)!);
    }
  }
  return tables;
}

/// Table names referenced by the replication rules.
Set<String> _syncedTables() {
  final RegExp pattern = RegExp(r'from public\.([a-z_]+)');
  return pattern
      .allMatches(_read('powersync/sync-rules.yaml'))
      .map((RegExpMatch match) => match.group(1)!)
      .toSet();
}

/// Table names declared in the local schema, resolved through `LocalTables`.
Set<String> _localSchemaTables() {
  final String source = _read('lib/core/storage/local_schema.dart');
  final Map<String, String> constants = <String, String>{
    for (final RegExpMatch match in RegExp(
      r"static const String (\w+)\s*=\s*\n?\s*'([a-z_]+)';",
    ).allMatches(source))
      match.group(1)!: match.group(2)!,
  };
  final Set<String> tables = <String>{};
  for (final RegExpMatch match in RegExp(
    r'static const Table _\w+ = Table\(\s*LocalTables\.(\w+)',
  ).allMatches(source)) {
    final String? table = constants[match.group(1)!];
    expect(
      table,
      isNotNull,
      reason:
          'Table definition references LocalTables.${match.group(1)}, which is '
          'not declared as a table name constant.',
    );
    tables.add(table!);
  }
  return tables;
}

/// Table -> conflict resource mappings declared in the conflict registry.
Map<String, String> _conflictMappings() {
  final String source = _read('lib/core/sync/conflict_policy.dart');
  final RegExpMatch? block = RegExp(
    r'_tableToResource = <String, String>\{(.*?)\n  \}',
    dotAll: true,
  ).firstMatch(source);
  expect(block, isNotNull, reason: 'Conflict table map not found.');
  return <String, String>{
    for (final RegExpMatch match in RegExp(
      r"'([a-z_]+)':\s*(\w+)",
    ).allMatches(block!.group(1)!))
      match.group(1)!: match.group(2)!,
  };
}

/// Resource constants whose policy is `ConflictPolicy.appendOnly`.
Set<String> _appendOnlyResources() {
  final String source = _read('lib/core/sync/conflict_policy.dart');
  final Set<String> resources = <String>{};
  for (final RegExpMatch match in RegExp(
    r'^\s{4}(\w+): ConflictPolicyEntry\((.*?)\n    \),',
    dotAll: true,
    multiLine: true,
  ).allMatches(source)) {
    if (match.group(2)!.contains('ConflictPolicy.appendOnly')) {
      resources.add(match.group(1)!);
    }
  }
  return resources;
}

/// Tables carrying an append-only guard in the migration set.
///
/// Some append-only entities are guarded by `nodex.tg_block_mutation()`, which
/// refuses every update and delete. Others are guarded by a table-specific
/// state-machine trigger (a draft line may be edited, an issued one may not).
/// Both satisfy the invariant this test exists to protect: a table the client
/// treats as append-only must not be freely mutable in PostgreSQL.
Set<String> _guardedTables() {
  final RegExp pattern = RegExp(
    r'create trigger\s+\w+[^;]*?on\s+public\.([a-z_]+)\b',
    caseSensitive: false,
    dotAll: true,
  );
  final Set<String> tables = <String>{};
  final Directory directory = Directory('supabase/migrations');
  for (final FileSystemEntity entity in directory.listSync()) {
    if (entity is! File || !entity.path.endsWith('.sql')) {
      continue;
    }
    for (final RegExpMatch match in pattern.allMatches(
      entity.readAsStringSync(),
    )) {
      tables.add(match.group(1)!);
    }
  }
  return tables;
}

/// Tables guarded by the blanket immutability trigger specifically.
Set<String> _immutableTables() {
  final RegExp pattern = RegExp(
    r'create trigger\s+\w+[^;]*?on\s+public\.([a-z_]+)\b[^;]*?tg_block_mutation\(\)',
    caseSensitive: false,
    dotAll: true,
  );
  final Set<String> tables = <String>{};
  final Directory directory = Directory('supabase/migrations');
  for (final FileSystemEntity entity in directory.listSync()) {
    if (entity is! File || !entity.path.endsWith('.sql')) {
      continue;
    }
    for (final RegExpMatch match in pattern.allMatches(
      entity.readAsStringSync(),
    )) {
      tables.add(match.group(1)!);
    }
  }
  return tables;
}

/// Table names registered as writable in the edge mutation handler.
Set<String> _writableTables() {
  final String source = _read('supabase/functions/mutation-handler/index.ts');
  final int start = source.indexOf('const WRITABLE_TABLES');
  expect(start, isNonNegative, reason: 'WRITABLE_TABLES not found.');
  final int open = source.indexOf('{', start);
  int depth = 0;
  int end = -1;
  for (int i = open; i < source.length; i++) {
    if (source[i] == '{') {
      depth++;
    } else if (source[i] == '}') {
      depth--;
      if (depth == 0) {
        end = i;
        break;
      }
    }
  }
  expect(end, isNonNegative, reason: 'WRITABLE_TABLES is not balanced.');
  return RegExp(r'^  ([a-z_]+):\s*\{', multiLine: true)
      .allMatches(source.substring(open, end))
      .map((RegExpMatch match) => match.group(1)!)
      .toSet();
}

void main() {
  group('local schema covers replication', () {
    test('every synced table has a local table definition', () {
      final Set<String> missing = _syncedTables().difference(
        _localSchemaTables(),
      );
      expect(
        missing,
        isEmpty,
        reason:
            'A table in the sync rules without a local definition cannot '
            'materialize on a device. Missing: ${missing.toList()..sort()}',
      );
    });

    test('every synced table exists in the migrations', () {
      final Set<String> unknown = _syncedTables().difference(
        _migrationTables(),
      );
      expect(
        unknown,
        isEmpty,
        reason: 'Sync rules reference unknown tables: $unknown',
      );
    });

    test('local schema declares no unreplicated table outside the '
        'local-only allowlist', () {
      final Set<String> extra = _localSchemaTables()
          .difference(_syncedTables())
          .difference(_localOnlyTables);
      expect(
        extra,
        isEmpty,
        reason:
            'A local table with no bucket is dead weight and usually means a '
            'deleted bucket. Extra: ${extra.toList()..sort()}',
      );
    });

    test('schema build list matches the declared table constants', () {
      // NodexLocalSchema.build() is the source of truth for what is created on
      // a device; a constant declared but never listed is invisible at runtime.
      final String source = _read('lib/core/storage/local_schema.dart');
      final RegExpMatch? build = RegExp(
        r'static Schema build\(\) => const Schema\(<Table>\[(.*?)\n  \]\);',
        dotAll: true,
      ).firstMatch(source);
      expect(build, isNotNull, reason: 'Schema build list not found.');
      final Set<String> listed = RegExp(r'^\s*_(\w+),', multiLine: true)
          .allMatches(build!.group(1)!)
          .map((RegExpMatch m) => m.group(1)!)
          .toSet();
      final Set<String> declared = RegExp(r'static const Table _(\w+) = Table')
          .allMatches(source)
          .map((RegExpMatch m) => m.group(1)!)
          .toSet();
      expect(
        declared.difference(listed),
        isEmpty,
        reason: 'Declared but not built: ${declared.difference(listed)}',
      );
      expect(
        listed.difference(declared),
        isEmpty,
        reason: 'Built but not declared: ${listed.difference(declared)}',
      );
      expect(listed.length, NodexLocalSchema.build().tables.length);
    });
  });

  group('append-only invariant', () {
    test('every append-only resource is guarded in PostgreSQL', () {
      final Map<String, String> mappings = _conflictMappings();
      final Set<String> guarded = _guardedTables();
      final List<String> unguarded = <String>[];
      for (final String resource in _appendOnlyResources()) {
        final Iterable<String> tables = mappings.entries
            .where((MapEntry<String, String> e) => e.value == resource)
            .map((MapEntry<String, String> e) => e.key);
        for (final String table in tables) {
          if (!guarded.contains(table)) {
            unguarded.add('$table ($resource)');
          }
        }
      }
      expect(
        unguarded,
        isEmpty,
        reason:
            'A table registered append-only in the client has no trigger at '
            'all in PostgreSQL. Add nodex.tg_block_mutation() or a state-machine '
            'guard: $unguarded',
      );
    });

    test('the immutable ledgers refuse every update and delete', () {
      // These carry recorded facts that must never be rewritten in place: an
      // audit row, a clinical event, a money movement, an observation, a
      // handover, a stock movement, a ventilator event. A state-machine guard
      // is not enough here because there is no legitimate later state.
      const Set<String> immutable = <String>{
        'audit_events',
        'clinical_events',
        'payments',
        'refunds',
        'ledger_entries',
        'icu_vitals',
        'icu_nursing_handover',
        'stock_movements',
        'ventilator_events',
      };
      expect(
        immutable.difference(_immutableTables()),
        isEmpty,
        reason:
            'These tables must carry nodex.tg_block_mutation(): '
            '${immutable.difference(_immutableTables())}',
      );
    });

    test('every conflict-mapped table exists in the migrations', () {
      final Set<String> unknown = _conflictMappings().keys.toSet().difference(
        _migrationTables(),
      );
      expect(unknown, isEmpty, reason: 'Stale conflict mappings: $unknown');
    });
  });

  group('mutation path registry', () {
    test('every writable table is migrated, synced and conflict-mapped', () {
      final Set<String> writable = _writableTables();
      expect(writable, isNotEmpty);
      expect(
        writable.difference(_migrationTables()),
        isEmpty,
        reason: 'Writable table with no migration.',
      );
      expect(
        writable.difference(_syncedTables()),
        isEmpty,
        reason:
            'A writable table that is not replicated can never receive a local '
            'mutation.',
      );
      expect(
        writable.difference(_conflictMappings().keys.toSet()),
        isEmpty,
        reason: 'Writable table with no conflict policy.',
      );
    });
  });
}
