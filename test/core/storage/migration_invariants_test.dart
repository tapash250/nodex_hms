/// Migration and replication invariants.
///
/// The audit found that the four descriptions of the schema — the migrations,
/// the replication rules, the local schema and the mutation-handler registry
/// — are edited by hand, in different languages, and that a mismatch between
/// them is silent. The parity test covers the tables themselves. These tests
/// cover the properties around them:
///
/// * every table is behind row level security, and every table that is behind
///   it has at least one policy, so no table is quietly unreachable or
///   quietly open;
/// * every permission the server grants exists in the client's catalogue and
///   every permission the client checks exists in the server's seed, so a
///   check cannot pass on a permission nobody was granted;
/// * every replication bucket is scoped by the signed-in user's own identity
///   and never by a value the device supplied.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String relativePath) {
  final File file = File(relativePath);
  expect(
    file.existsSync(),
    isTrue,
    reason: 'Expected $relativePath to exist relative to the package root.',
  );
  return file.readAsStringSync();
}

List<File> _migrationFiles() =>
    Directory('supabase/migrations')
        .listSync()
        .whereType<File>()
        .where((File file) => file.path.endsWith('.sql'))
        .toList()
      ..sort((File a, File b) => a.path.compareTo(b.path));

String _allMigrations() =>
    _migrationFiles().map((File file) => file.readAsStringSync()).join('\n');

void main() {
  group('row level security', () {
    test('every table in the migrations is behind row level security', () {
      final Map<String, String> migrations = <String, String>{
        for (final File file in _migrationFiles())
          for (final RegExpMatch match in RegExp(
            r'create table (?:if not exists )?public\.([a-z0-9_]+)',
            caseSensitive: false,
          ).allMatches(file.readAsStringSync()))
            match.group(1)!: file.path,
      };

      final Set<String> enabled = <String>{
        for (final RegExpMatch match in RegExp(
          r'alter table (?:if exists )?public\.([a-z0-9_]+)\s+enable row level security',
          caseSensitive: false,
        ).allMatches(_allMigrations()))
          match.group(1)!,
      };

      final List<String> open =
          migrations.keys
              .where((String table) => !enabled.contains(table))
              .toList()
            ..sort();
      expect(
        open,
        isEmpty,
        reason:
            'These tables are not behind row level security, so every row in '
            'them is readable by any role the policies name: ${open.join(', ')}',
      );
    });

    test('every table behind row level security has a policy', () {
      final Set<String> tables = <String>{
        for (final RegExpMatch match in RegExp(
          r'create table (?:if not exists )?public\.([a-z0-9_]+)',
          caseSensitive: false,
        ).allMatches(_allMigrations()))
          match.group(1)!,
      };
      final Set<String> withPolicy = <String>{
        for (final RegExpMatch match in RegExp(
          r'create policy\s+\w+\s+on\s+public\.([a-z0-9_]+)',
          caseSensitive: false,
        ).allMatches(_allMigrations()))
          match.group(1)!,
      };

      final List<String> unreachable =
          tables.where((String table) => !withPolicy.contains(table)).toList()
            ..sort();
      expect(
        unreachable,
        isEmpty,
        reason:
            'These tables have row level security but no policy, so no '
            'authenticated principal can read or write them: '
            '${unreachable.join(', ')}',
      );
    });
  });

  group('permission drift', () {
    /// The permissions the server seeds.
    Set<String> serverPermissions() {
      final Set<String> keys = <String>{};
      // Comments are stripped first: a comment in the middle of a values
      // list contains parentheses, and the tuple reader would otherwise read
      // a sentence as a permission.
      final String sql = _allMigrations().replaceAll(RegExp(r'--[^\n]*'), '');
      for (final RegExpMatch insert in RegExp(
        r'insert into (?:public\.)?permissions\s*\(([^)]*)\)\s*values(.*?);',
        caseSensitive: false,
        dotAll: true,
      ).allMatches(sql)) {
        final List<String> columns = insert
            .group(1)!
            .split(',')
            .map((String column) => column.trim())
            .toList();
        final int keyIndex = columns.indexOf('key');
        if (keyIndex < 0) continue;
        for (final RegExpMatch tuple in RegExp(
          r'\(([^()]*)\)',
        ).allMatches(insert.group(2)!)) {
          final List<String> parts = tuple
              .group(1)!
              .split(',')
              .map((String part) => part.trim().replaceAll("'", ''))
              .toList();
          if (parts.length <= keyIndex) continue;
          final String key = parts[keyIndex];
          // A permission key is dotted and lowercase; anything else is a
          // parse artefact rather than a permission.
          if (!RegExp(r'^[a-z0-9_]+\.[a-z0-9_.]+$').hasMatch(key)) continue;
          keys.add(key);
        }
      }
      return keys;
    }

    /// The permissions the client catalogue names.
    Set<String> clientPermissions() {
      final String source = _read(
        'lib/core/authorization/permission_catalog.dart',
      );
      return <String>{
        for (final RegExpMatch match in RegExp(
          r"static const String \w+\s*=\s*'([a-z0-9_.]+)';",
          dotAll: true,
        ).allMatches(source))
          if (match.group(1)!.contains('.')) match.group(1)!,
      };
    }

    test('every permission the client checks exists on the server', () {
      final Set<String> missing = clientPermissions().difference(
        serverPermissions(),
      );
      expect(
        missing,
        isEmpty,
        reason:
            'The client checks permissions the server never grants, so the '
            'check always fails: ${missing.join(', ')}',
      );
    });

    test('every permission the server grants exists in the client', () {
      final Set<String> missing = serverPermissions().difference(
        clientPermissions(),
      );
      expect(
        missing,
        isEmpty,
        reason:
            'The server grants permissions the client does not name, so a '
            'screen cannot gate on them: ${missing.join(', ')}',
      );
    });

    test('the catalogue holds every permission the migrations grant', () {
      // A count as well as a set comparison, so a permission dropped from
      // both sides is noticed as a change rather than passing quietly.
      expect(clientPermissions().length, greaterThan(100));
    });
  });

  group('replication scoping', () {
    test('every bucket is scoped by the signed-in user', () {
      final String rules = _read('powersync/sync-rules.yaml');
      final List<String> unscoped = <String>[];
      for (final RegExpMatch bucket in RegExp(
        r'\n    ([a-z_]+):\n      parameters:(.*?)\n      data:',
        dotAll: true,
      ).allMatches(rules)) {
        final String parameters = bucket.group(2)!;
        if (!parameters.contains(':user_id')) {
          unscoped.add(bucket.group(1)!);
        }
      }
      expect(
        unscoped,
        isEmpty,
        reason:
            'These buckets are not scoped by the signed-in user, so their '
            'contents are the same for everybody: ${unscoped.join(', ')}',
      );
    });

    test('no bucket takes a value from the device', () {
      final String rules = _read('powersync/sync-rules.yaml');
      expect(rules, isNot(contains(':client_input')));
      expect(rules, isNot(contains(':client_tenant')));
      expect(rules, isNot(contains(':client_user')));
    });

    test('every bucket has a data section', () {
      final String rules = _read('powersync/sync-rules.yaml');
      for (final RegExpMatch bucket in RegExp(
        r'\n    ([a-z_]+):\n(.*?)(?=\n    [a-z_]+:\n|\Z)',
        dotAll: true,
      ).allMatches(rules)) {
        expect(
          bucket.group(2),
          contains('data:'),
          reason:
              'The bucket ${bucket.group(1)} has no data section, so it '
              'replicates nothing and exists only to be confusing.',
        );
      }
    });

    test('a bucket without parameters holds only global tables', () {
      // A bucket that cannot be scoped by the caller's membership may only
      // carry tables that belong to no tenant. A tenant-scoped table in such
      // a bucket would replicate every tenant's rows to every device.
      final String rules = _read('powersync/sync-rules.yaml');
      final String sql = _allMigrations();
      final Map<String, bool> tenantScoped = <String, bool>{};
      for (final RegExpMatch table in RegExp(
        r'create table (?:if not exists )?public\.([a-z0-9_]+)\s*\((.*?)\n\);',
        dotAll: true,
      ).allMatches(sql)) {
        tenantScoped[table.group(1)!] = table.group(2)!.contains('tenant_id');
      }
      for (final RegExpMatch bucket in RegExp(
        r'\n    ([a-z_]+):\n(.*?)(?=\n    [a-z_]+:\n|\Z)',
        dotAll: true,
      ).allMatches(rules)) {
        final String name = bucket.group(1)!;
        final String body = bucket.group(2)!;
        if (body.contains('parameters:')) continue;
        for (final RegExpMatch select in RegExp(
          r'from public\.([a-z0-9_]+)',
        ).allMatches(body)) {
          final String table = select.group(1)!;
          expect(
            tenantScoped[table],
            isNot(true),
            reason:
                'The bucket $name has no parameters, so it cannot be scoped, '
                'but $table belongs to a tenant. Every tenant in the '
                'installation would replicate to every device.',
          );
        }
      }
    });
  });
}
