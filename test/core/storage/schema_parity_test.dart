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
  // The clinician's own notes: private, on the device, never replicated.
  'scratchpads',
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
    r'create table (?:if not exists )?public\.([a-z0-9_]+)',
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
  final RegExp pattern = RegExp(r'from public\.([a-z0-9_]+)');
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
      r"static const String (\w+)\s*=\s*\n?\s*'([a-z0-9_]+)';",
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

/// Table names declared with `Table.localOnly`, which never replicate.
Set<String> _localOnlySchemaTables() {
  final String source = _read('lib/core/storage/local_schema.dart');
  final Map<String, String> constants = <String, String>{
    for (final RegExpMatch match in RegExp(
      r"static const String (\w+)\s*=\s*\n?\s*'([a-z0-9_]+)';",
    ).allMatches(source))
      match.group(1)!: match.group(2)!,
  };
  final Set<String> tables = <String>{};
  for (final RegExpMatch match in RegExp(
    r'static const Table _\w+ = Table\.localOnly\(\s*LocalTables\.(\w+)',
  ).allMatches(source)) {
    final String? table = constants[match.group(1)!];
    expect(table, isNotNull, reason: 'Unknown local-only table constant.');
    tables.add(table!);
  }
  return tables;
}

/// Table names referenced by the deployed sync config.
Set<String> _syncConfigTables() {
  final String source = _read('../powersync/sync-config.yaml');
  final Set<String> known = _localSchemaTables();
  return RegExp(r'\b(?:from|join)\s+([a-z][a-z0-9_]*)', caseSensitive: false)
      .allMatches(source)
      .map((RegExpMatch match) => match.group(1)!.toLowerCase())
      .where(known.contains)
      .toSet();
}

/// Table names in the full-coverage publication migration.
Set<String> _coverageMigrationTables() {
  final String source = _read(
    'supabase/migrations/20260918200001_expand_powersync_full_coverage.sql',
  );
  final RegExpMatch? block = RegExp(
    r'synced_tables\s+text\[\]\s*:=\s*array\[(.*?)\];',
    dotAll: true,
  ).firstMatch(source);
  expect(block, isNotNull, reason: 'Coverage migration table array not found.');
  return RegExp("'([a-z0-9_]+)'")
      .allMatches(block!.group(1)!)
      .map((RegExpMatch match) => match.group(1)!)
      .toSet();
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
    r'create trigger\s+\w+[^;]*?on\s+public\.([a-z0-9_]+)\b',
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
    r'create trigger\s+\w+[^;]*?on\s+public\.([a-z0-9_]+)\b[^;]*?tg_block_mutation\(\)',
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
  return RegExp(r'^  ([a-z0-9_]+):\s*\{', multiLine: true)
      .allMatches(source.substring(open, end))
      .map((RegExpMatch match) => match.group(1)!)
      .toSet();
}

/// Tables guarded by something other than the timestamp updater.
///
/// A table whose only trigger is `nodex.tg_set_updated_at()` has no rule
/// about what may be written to it: every column is editable forever. An
/// entity the client treats as append-only must not be one of them.
Set<String> _guardedBeyondTimestamp() {
  final Map<String, List<String>> functions = <String, List<String>>{};
  for (final FileSystemEntity entity in Directory(
    'supabase/migrations',
  ).listSync()) {
    if (entity is! File || !entity.path.endsWith('.sql')) continue;
    final String sql = entity.readAsStringSync();
    for (final RegExpMatch trigger in RegExp(
      r'create trigger\s+\w+[^;]*?on\s+public\.([a-z0-9_]+)\b[^;]*?execute function ([a-z0-9_.()]+)',
      caseSensitive: false,
      dotAll: true,
    ).allMatches(sql)) {
      functions
          .putIfAbsent(trigger.group(1)!, () => <String>[])
          .add(trigger.group(2)!);
    }
  }
  return <String>{
    for (final MapEntry<String, List<String>> entry in functions.entries)
      if (entry.value.any(
        (String function) => !function.endsWith('tg_set_updated_at'),
      ))
        entry.key,
  };
}

void main() {
  group('local schema covers replication', () {
    test('every synced table has a local table definition', () {
      final Set<String> missing = _syncConfigTables().difference(
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
      final Set<String> unknown = _syncConfigTables().difference(
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
          .difference(_syncConfigTables())
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

    test(
      'local schema declares 149 tables: 146 replicated and 3 local-only',
      () {
        final Set<String> replicated = _localSchemaTables();
        final Set<String> localOnly = _localOnlySchemaTables();
        expect(replicated.length, 146);
        expect(localOnly.length, 3);
        expect(replicated.intersection(localOnly), isEmpty);
        expect(replicated.union(localOnly).length, 149);
        expect(localOnly, _localOnlyTables);
      },
    );

    test('sync config covers every replicated table exactly', () {
      final Set<String> replicated = _localSchemaTables();
      final Set<String> synced = _syncConfigTables();
      expect(
        replicated.difference(synced),
        isEmpty,
        reason:
            'A replicated table with no sync-config query never materializes. '
            'Missing: ${replicated.difference(synced).toList()..sort()}',
      );
      expect(
        synced.difference(replicated),
        isEmpty,
        reason:
            'The sync config references a table the local schema does not '
            'declare: ${synced.difference(replicated).toList()..sort()}',
      );
      expect(synced.length, replicated.length);
    });

    test('legacy sync rules cover every replicated table exactly', () {
      final Set<String> replicated = _localSchemaTables();
      final Set<String> legacy = _syncedTables();
      expect(
        replicated.difference(legacy),
        isEmpty,
        reason:
            'The reviewed legacy rules dropped a replicated table: '
            '${replicated.difference(legacy).toList()..sort()}',
      );
      expect(
        legacy.difference(replicated),
        isEmpty,
        reason:
            'The legacy rules reference a table the local schema does not '
            'declare: ${legacy.difference(replicated).toList()..sort()}',
      );
    });

    test('publication migration covers every replicated table exactly', () {
      final Set<String> replicated = _localSchemaTables();
      final Set<String> published = _coverageMigrationTables();
      expect(
        replicated.difference(published),
        isEmpty,
        reason:
            'A replicated table is missing from the publication migration and '
            'will never emit WAL: '
            '${replicated.difference(published).toList()..sort()}',
      );
      expect(
        published.difference(replicated),
        isEmpty,
        reason:
            'The publication migration names a table the local schema does '
            'not declare: ${published.difference(replicated).toList()..sort()}',
      );
      expect(published.length, replicated.length);
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

    test('an append-only table is guarded by more than its timestamp', () {
      // A table whose only trigger is the timestamp updater has no rule
      // about what may be written to it. Calling such a table append-only in
      // the client is a claim the server does not keep.
      final Map<String, String> mappings = _conflictMappings();
      final Set<String> guarded = _guardedBeyondTimestamp();
      final List<String> unguarded = <String>[];
      for (final String resource in _appendOnlyResources()) {
        final Iterable<String> tables = mappings.entries
            .where((MapEntry<String, String> e) => e.value == resource)
            .map((MapEntry<String, String> e) => e.key);
        for (final String table in tables) {
          if (!guarded.contains(table)) unguarded.add('$table ($resource)');
        }
      }
      expect(
        unguarded,
        isEmpty,
        reason:
            'These tables are append-only in the client but nothing in '
            'PostgreSQL stops them being edited: ${unguarded.join(', ')}',
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
        'form_responses',
        'clinical_messages',
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
        writable.difference(_syncConfigTables()),
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
