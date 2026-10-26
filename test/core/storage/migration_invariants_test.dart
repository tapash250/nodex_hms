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

/// Splits on the commas that are not inside parentheses or quotes.
List<String> _splitTopLevel(String body) {
  final List<String> parts = <String>[];
  int depth = 0;
  bool quoted = false;
  String current = '';
  for (final String character in body.split('')) {
    if (character == "'") quoted = !quoted;
    if (!quoted) {
      if (character == '(') depth++;
      if (character == ')') depth--;
      if (character == ',' && depth == 0) {
        parts.add(current);
        current = '';
        continue;
      }
    }
    current += character;
  }
  if (current.trim().isNotEmpty) parts.add(current);
  return parts;
}

/// The columns the client declares for each local table.
Map<String, Set<String>> localColumns() {
  final String source = _read('lib/core/storage/local_schema.dart');
  final Map<String, String> names = <String, String>{
    for (final RegExpMatch match in RegExp(
      r"static const String (\w+)\s*=\s*\n?\s*'([a-z0-9_]+)';",
    ).allMatches(source))
      match.group(1)!: match.group(2)!,
  };
  final Map<String, Set<String>> columns = <String, Set<String>>{};
  for (final RegExpMatch table in RegExp(
    r"static const Table _\w+ = Table\(\s*LocalTables\.(\w+),\s*<Column>\[(.*?)\]\s*\)",
    dotAll: true,
  ).allMatches(source)) {
    final String? name = names[table.group(1)!];
    if (name == null) continue;
    columns
        .putIfAbsent(name, () => <String>{})
        .addAll(
          RegExp(r"Column\.\w+\('([a-z0-9_]+)'\)")
              .allMatches(table.group(2)!)
              .map((RegExpMatch match) => match.group(1)!),
        );
  }
  return columns;
}

/// The SQL type of a column declaration.
String _typeOf(String rest) {
  final String trimmed = rest.trim().toLowerCase();
  for (final String phrase in <String>[
    'double precision',
    'character varying',
    'timestamp with time zone',
    'timestamp without time zone',
  ]) {
    if (trimmed.startsWith(phrase)) return phrase;
  }
  final RegExpMatch? match = RegExp('^([a-z]+)').firstMatch(trimmed);
  return match?.group(1) ?? trimmed;
}

/// Whether the handler's declared type can carry the server's column.
///
/// The handler's type describes the *server* column, because that is what
/// the payload has to satisfy. The validator converts what the device
/// holds — 0/1 for a boolean, a JSON string for a jsonb column — into
/// what the server expects.
bool _handlerTypeFits(String declared, String serverType) {
  final String server = serverType.toLowerCase();
  switch (declared) {
    case 'boolean':
      return server == 'boolean';
    case 'uuid':
      return server == 'uuid';
    case 'text':
      // A date-only column carries a YYYY-MM-DD string, which is what keeps
      // a device west of UTC from shifting the first day.
      return server == 'text' ||
          server == 'character varying' ||
          server == 'date';
    case 'integer':
      return <String>{
        'integer',
        'int',
        'int4',
        'bigint',
        'int8',
        'smallint',
        'serial',
        'bigserial',
      }.contains(server);
    case 'number':
      return <String>{
        'numeric',
        'decimal',
        'real',
        'double',
        'float4',
        'float8',
        'integer',
        'bigint',
      }.contains(server);
    case 'timestamp':
      return server.startsWith('timestamp') || server == 'date';
    case 'json':
      return server == 'json' || server == 'jsonb';
  }
  return false;
}

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

  group('grants', () {
    /// The permissions each role holds.
    ///
    /// The grant seed contains a bulk statement —
    /// `select 'hospital_super_admin', key from public.permissions` — which
    /// grants every permission seeded before that file. The walk is therefore
    /// ordered: a permission seeded afterwards is not covered by it, and has
    /// to be granted explicitly.
    Map<String, Set<String>> grantedPermissions() {
      final Map<String, Set<String>> grants = <String, Set<String>>{};
      final Set<String> seededSoFar = <String>{};

      for (final File file in _migrationFiles()) {
        final String sql = file.readAsStringSync();
        final String withoutComments = sql.replaceAll(RegExp(r'--[^\n]*'), '');

        for (final RegExpMatch insert in RegExp(
          r'insert into (?:public\.)?role_permissions\s*\(([^)]*)\)\s*values(.*?);',
          caseSensitive: false,
          dotAll: true,
        ).allMatches(withoutComments)) {
          final List<String> columns = insert
              .group(1)!
              .split(',')
              .map((String column) => column.trim())
              .toList();
          if (columns.length < 2) continue;
          for (final RegExpMatch tuple in RegExp(
            r'\(([^()]*)\)',
          ).allMatches(insert.group(2)!)) {
            final List<String> parts = tuple
                .group(1)!
                .split(',')
                .map((String part) => part.trim().replaceAll("'", ''))
                .toList();
            if (parts.length < 2) continue;
            grants.putIfAbsent(parts[1], () => <String>{}).add(parts[0]);
          }
        }

        final RegExpMatch? bulk = RegExp(
          r"insert into (?:public\.)?role_permissions\s*\([^)]*\)\s*select\s*'([a-z_]+)'\s*,\s*key\s+from\s+public\.permissions",
          caseSensitive: false,
        ).firstMatch(withoutComments);
        if (bulk != null) {
          // The bulk statement grants a role every permission seeded so far,
          // so each of those permissions gains that role.
          for (final String key in seededSoFar) {
            grants.putIfAbsent(key, () => <String>{}).add(bulk.group(1)!);
          }
        }

        for (final RegExpMatch insert in RegExp(
          r'insert into (?:public\.)?permissions\s*\(([^)]*)\)\s*values(.*?);',
          caseSensitive: false,
          dotAll: true,
        ).allMatches(withoutComments)) {
          final List<String> columns = insert
              .group(1)!
              .split(',')
              .map((String column) => column.trim())
              .toList();
          if (!columns.contains('key')) continue;
          final int keyIndex = columns.indexOf('key');
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
            if (!RegExp(r'^[a-z0-9_]+\.[a-z0-9_.]+$').hasMatch(key)) continue;
            seededSoFar.add(key);
          }
        }
      }
      return grants;
    }

    test(
      'every permission a policy or a bucket names is granted to somebody',
      () {
        // A policy keyed on a permission no role holds is a policy that can
        // never match: the table it guards is unreachable for everyone, and the
        // failure is silent.
        final String sql = _allMigrations();
        final Set<String> used = <String>{
          for (final RegExpMatch match in RegExp(
            r"has_permission\(\s*\w+(?:\.\w+)*\s*,\s*'([a-z0-9_.]+)'",
          ).allMatches(sql))
            match.group(1)!,
        };
        final String rules = _read('powersync/sync-rules.yaml');
        used.addAll(
          RegExp(r"rp\.permission_key\s*=\s*'([a-z0-9_.]+)'")
              .allMatches(rules)
              .map((RegExpMatch match) => match.group(1)!)
              .toSet(),
        );

        final Map<String, Set<String>> grants = grantedPermissions();
        final List<String> orphaned =
            used
                .where(
                  (String key) => (grants[key] ?? const <String>{}).isEmpty,
                )
                .toList()
              ..sort();
        expect(
          orphaned,
          isEmpty,
          reason:
              'These permissions gate a policy or a bucket, but no role holds '
              'them, so the thing they guard is unreachable for everybody: '
              '${orphaned.join(', ')}',
        );
      },
    );
  });

  group('columns', () {
    /// The columns each server table has.
    ///
    /// The reader is deliberately simple: comments are stripped, the table
    /// body is taken by matching parentheses, and the body is split at the
    /// commas that are not inside parentheses. It is not a SQL parser, and it
    /// does not need to be — the tables in this repository are declared in a
    /// single style, and the alternative is a test that skips the tables it
    /// cannot read.
    Map<String, Set<String>> serverColumns() {
      final Map<String, Set<String>> columns = <String, Set<String>>{};
      for (final File file in _migrationFiles()) {
        final String sql = file
            .readAsStringSync()
            .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
            .replaceAll(RegExp(r'--[^\n]*'), '');

        for (final RegExpMatch table in RegExp(
          r'create table (?:if not exists )?public\.([a-z0-9_]+)\s*\(',
          caseSensitive: false,
        ).allMatches(sql)) {
          final int open = table.end - 1;
          int depth = 0;
          int close = open;
          for (int i = open; i < sql.length; i++) {
            if (sql[i] == '(') depth++;
            if (sql[i] == ')') {
              depth--;
              if (depth == 0) {
                close = i;
                break;
              }
            }
          }
          final Set<String> found = <String>{};
          for (final String part in _splitTopLevel(
            sql.substring(open + 1, close),
          )) {
            final String trimmed = part.trim();
            if (trimmed.isEmpty) continue;
            final String first = trimmed.split(' ').first.toLowerCase();
            if (<String>{
              'constraint',
              'primary',
              'unique',
              'check',
              'foreign',
              'exclude',
              'like',
            }.contains(first)) {
              continue;
            }
            if (RegExp(r'^[a-z_][a-z0-9_]*$').hasMatch(first)) found.add(first);
          }
          columns
              .putIfAbsent(table.group(1)!.toLowerCase(), () => <String>{})
              .addAll(found);
        }

        for (final RegExpMatch alter in RegExp(
          r'alter table (?:if exists )?public\.([a-z0-9_]+)\b([^;]*);',
          caseSensitive: false,
          dotAll: true,
        ).allMatches(sql)) {
          final Set<String> found = <String>{
            for (final RegExpMatch add in RegExp(
              'add column (?:if not exists )?([a-z_][a-z0-9_]*)',
            ).allMatches(alter.group(2)!))
              add.group(1)!.toLowerCase(),
          };
          columns
              .putIfAbsent(alter.group(1)!.toLowerCase(), () => <String>{})
              .addAll(found);
        }
      }
      return columns;
    }

    test('every column the client declares exists on the server', () {
      // A local column the server does not have is a value the device can
      // store and the server will reject. The failure arrives as a refused
      // mutation, one row at a time, long after the column was added.
      final Map<String, Set<String>> server = serverColumns();
      final Map<String, Set<String>> local = localColumns();
      final List<String> unknown = <String>[];
      for (final MapEntry<String, Set<String>> table in local.entries) {
        final Set<String>? serverColumns = server[table.key];
        if (serverColumns == null) continue;
        for (final String column in table.value) {
          if (column == 'id') continue;
          if (!serverColumns.contains(column)) {
            unknown.add('${table.key}.$column');
          }
        }
      }
      unknown.sort();
      expect(
        unknown,
        isEmpty,
        reason:
            'The client stores columns the server table does not have, so the '
            'values are written locally and refused on upload: '
            '${unknown.join(', ')}',
      );
    });

    test('every column the mutation handler offers is declared locally', () {
      // The handler filters what it uploads by the column list. A column the
      // handler offers but the local table lacks is a value the device never
      // had, so the upload sends nothing.
      final String source = _read(
        'supabase/functions/mutation-handler/index.ts',
      );
      final Map<String, Set<String>> local = localColumns();
      final List<String> unknown = <String>[];
      for (final RegExpMatch table in RegExp(
        r'^  ([a-z0-9_]+):\s*\{(.*?)^  \},',
        dotAll: true,
        multiLine: true,
      ).allMatches(source)) {
        final RegExpMatch? columns = RegExp(
          r'columns:\s*\{(.*?)\n    \},',
          dotAll: true,
        ).firstMatch(table.group(2)!);
        if (columns == null) continue;
        final Set<String>? declared = local[table.group(1)!];
        if (declared == null) {
          unknown.add('${table.group(1)!} (no local table)');
          continue;
        }
        for (final RegExpMatch column in RegExp(
          r'^\s+([a-z_][a-z0-9_]*):\s*',
          multiLine: true,
        ).allMatches(columns.group(1)!)) {
          final String name = column.group(1)!;
          if (name == 'id') continue;
          if (!declared.contains(name)) {
            unknown.add('${table.group(1)!}.$name');
          }
        }
      }
      unknown.sort();
      expect(
        unknown,
        isEmpty,
        reason:
            'The mutation handler offers columns the local table does not '
            'declare, so the device cannot hold the value it would upload: '
            '${unknown.join(', ')}',
      );
    });
  });

  group('column types', () {
    /// The type of every server column, as the handler must describe it.
    Map<String, Map<String, String>> serverTypes() {
      final Map<String, Map<String, String>> types =
          <String, Map<String, String>>{};
      for (final File file in _migrationFiles()) {
        final String sql = file
            .readAsStringSync()
            .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
            .replaceAll(RegExp(r'--[^\n]*'), '');

        for (final RegExpMatch table in RegExp(
          r'create table (?:if not exists )?public\.([a-z0-9_]+)\s*\(',
          caseSensitive: false,
        ).allMatches(sql)) {
          final int open = table.end - 1;
          int depth = 0;
          int close = open;
          for (int i = open; i < sql.length; i++) {
            if (sql[i] == '(') depth++;
            if (sql[i] == ')') {
              depth--;
              if (depth == 0) {
                close = i;
                break;
              }
            }
          }
          final Map<String, String> found = <String, String>{};
          for (final String part in _splitTopLevel(
            sql.substring(open + 1, close),
          )) {
            final String trimmed = part.trim();
            if (trimmed.isEmpty) continue;
            final String first = trimmed.split(' ').first.toLowerCase();
            if (<String>{
              'constraint',
              'primary',
              'unique',
              'check',
              'foreign',
              'exclude',
              'like',
            }.contains(first)) {
              continue;
            }
            if (!RegExp(r'^[a-z_][a-z0-9_]*$').hasMatch(first)) continue;
            String rest = trimmed.substring(first.length).trim();
            rest = rest.replaceFirst(
              RegExp('^(not null|null|default [^,]*)'),
              '',
            );
            found[first] = _typeOf(rest);
          }
          types
              .putIfAbsent(
                table.group(1)!.toLowerCase(),
                () => <String, String>{},
              )
              .addAll(found);
        }

        for (final RegExpMatch alter in RegExp(
          r'alter table (?:if exists )?public\.([a-z0-9_]+)\b([^;]*);',
          caseSensitive: false,
          dotAll: true,
        ).allMatches(sql)) {
          for (final RegExpMatch add in RegExp(
            r'add column (?:if not exists )?([a-z_][a-z0-9_]*)\s+([^,]+)',
            caseSensitive: false,
          ).allMatches(alter.group(2)!)) {
            types.putIfAbsent(
              alter.group(1)!.toLowerCase(),
              () => <String, String>{},
            )[add.group(1)!.toLowerCase()] = _typeOf(
              add.group(2)!,
            );
          }
        }
      }
      return types;
    }

    /// The handler's declared type for every column it will upload.
    Map<String, Map<String, String>> handlerTypes() {
      final String source = _read(
        'supabase/functions/mutation-handler/index.ts',
      );
      final Map<String, Map<String, String>> types =
          <String, Map<String, String>>{};
      for (final RegExpMatch table in RegExp(
        r'^  ([a-z0-9_]+):\s*\{(.*?)^  \},',
        dotAll: true,
        multiLine: true,
      ).allMatches(source)) {
        final RegExpMatch? columns = RegExp(
          r'columns:\s*\{(.*?)\n    \},',
          dotAll: true,
        ).firstMatch(table.group(2)!);
        if (columns == null) continue;
        final Map<String, String> found = <String, String>{};
        for (final RegExpMatch column in RegExp(
          r"^\s+([a-z_][a-z0-9_]*):\s*'([a-z]+)',",
          multiLine: true,
        ).allMatches(columns.group(1)!)) {
          found[column.group(1)!] = column.group(2)!;
        }
        types[table.group(1)!] = found;
      }
      return types;
    }

    test('every column the handler uploads has a type the server accepts', () {
      // A handler type that does not match the server column is a refused
      // write: a boolean column described as an integer arrives as 1, and
      // PostgreSQL will not take a number for a boolean.
      final Map<String, Map<String, String>> server = serverTypes();
      final List<String> wrong = <String>[];
      for (final MapEntry<String, Map<String, String>> table
          in handlerTypes().entries) {
        final Map<String, String>? columns = server[table.key];
        if (columns == null) continue;
        for (final MapEntry<String, String> column in table.value.entries) {
          final String? serverType = columns[column.key];
          if (serverType == null) continue;
          if (!_handlerTypeFits(column.value, serverType)) {
            wrong.add(
              '${table.key}.${column.key} (handler ${column.value}, '
              'server $serverType)',
            );
          }
        }
      }
      wrong.sort();
      expect(
        wrong,
        isEmpty,
        reason:
            'The mutation handler describes these columns with a type the '
            'server will not accept, so every write that carries them is '
            'refused: ${wrong.join(', ')}',
      );
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

    test('facility-scoped buckets filter replication on the facility', () {
      final String rules = _read('powersync/sync-rules.yaml');
      final List<RegExpMatch> buckets = RegExp(
        r'\n    ([a-z_]+):\n(.*?)(?=\n    [a-z_]+:\n|\Z)',
        dotAll: true,
      ).allMatches(rules).toList();
      final Map<String, String> blocks = <String, String>{};
      for (final RegExpMatch bucket in buckets) {
        blocks[bucket.group(1)!] = bucket.group(2)!;
      }
      const List<String> facilityScoped = <String>[
        'ward_census',
        'nursing_station',
        'icu_census',
        'staff_directory',
        'visitor',
        'contacts',
      ];
      for (final String name in facilityScoped) {
        final String block = blocks[name] ?? '';
        expect(
          block,
          contains('m.facility_id as facility_id'),
          reason:
              'The bucket $name must derive its offline scope from the '
              'membership facility, not from the tenant alone.',
        );
        expect(
          block,
          contains('facility_id = bucket.facility_id'),
          reason:
              'The bucket $name must filter replicated rows to the caller '
              'facility, so a ward-scoped device cannot hold another '
              'facility rows.',
        );
      }
    });
  });

  group('billing settlement accounting', () {
    test('a refund reduces the invoice settled total through the trigger', () {
      final String sql = _read(
        'supabase/migrations/20260918130000_phase4_refund_settlement_accounting.sql',
      ).replaceAll(RegExp(r'--[^\n]*'), '');
      expect(
        sql,
        contains('create or replace function nodex.tg_refund_reduce_settled()'),
      );
      expect(sql, contains('create trigger refunds_reduce_settled'));
      expect(
        sql,
        contains(
          'settled_minor = greatest(settled_minor - new.amount_minor, 0)',
        ),
      );
    });

    test('settled invoices are immutable outside the refund projection', () {
      final String sql = _read(
        'supabase/migrations/20260918130000_phase4_refund_settlement_accounting.sql',
      ).replaceAll(RegExp(r'--[^\n]*'), '');
      expect(sql, contains('NODEX: settled invoices are immutable'));
      expect(sql, contains('nodex.refund_projection'));
    });

    test('the settled check accepts net collections after a refund', () {
      final String sql = _read(
        'supabase/migrations/20260918130000_phase4_refund_settlement_accounting.sql',
      ).replaceAll(RegExp(r'--[^\n]*'), '');
      expect(sql, contains('settled_minor >= 0'));
    });
  });
}
