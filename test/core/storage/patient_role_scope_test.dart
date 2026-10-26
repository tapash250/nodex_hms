/// The patient role's containment boundary.
///
/// A portal account is a patient, not a member of staff. Phase 1 seeded the
/// `patient` role with five staff permissions before the portal existed. Every
/// clinical table gates its SELECT on one of them, so the grants let one
/// patient read every patient's encounters, results, prescriptions and
/// invoices — and admitted the account to twenty-two staff replication
/// buckets, because a bucket parameter checked the permission and not the
/// role.
///
/// Module 05 states the intended boundary: the portal reads through its own
/// bucket and holds no clinical read permission. These tests hold the seed and
/// the rules to that boundary, so a later re-grant is a failing test rather
/// than a silent disclosure.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The staff permissions that, granted to the patient role, expose another
/// patient's record.
const Set<String> _staffOnlyForPatients = <String>{
  'patient.read',
  'encounter.read',
  'appointment.read',
  'appointment.write',
  'billing.read',
};

/// The key the portal bucket checks, and the only clinical capability the role
/// keeps.
const String _portalAccess = 'portal.access';

String _read(String relativePath) {
  final File file = File(relativePath);
  expect(
    file.existsSync(),
    isTrue,
    reason: 'Expected $relativePath to exist relative to the package root.',
  );
  return file.readAsStringSync();
}

List<File> _migrationFiles() {
  final List<File> files = Directory('supabase/migrations')
      .listSync()
      .whereType<File>()
      .where((File file) => file.path.endsWith('.sql'))
      .toList();
  files.sort((File a, File b) => a.path.compareTo(b.path));
  return files;
}

String _withoutComments(String sql) => sql.replaceAll(RegExp(r'--[^\n]*'), '');

/// The grants each role holds after every insert and delete, applied in
/// migration order.
Map<String, Set<String>> _effectiveGrants() {
  final Map<String, Set<String>> grants = <String, Set<String>>{};
  for (final File file in _migrationFiles()) {
    final String sql = _withoutComments(file.readAsStringSync());

    for (final RegExpMatch insert in RegExp(
      r'insert into (?:public\.)?role_permissions\s*\(([^)]*)\)\s*values(.*?);',
      caseSensitive: false,
      dotAll: true,
    ).allMatches(sql)) {
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
        grants.putIfAbsent(parts[0], () => <String>{}).add(parts[1]);
      }
    }

    for (final RegExpMatch revoke in RegExp(
      r"delete from (?:public\.)?role_permissions\s+where\s+role_key\s*=\s*'([a-z_]+)'\s+and\s+permission_key\s+in\s*\(([^)]*)\)",
      caseSensitive: false,
      dotAll: true,
    ).allMatches(sql)) {
      final String role = revoke.group(1)!;
      final Set<String> revoked = RegExp("'([a-z0-9_.]+)'")
          .allMatches(revoke.group(2)!)
          .map((RegExpMatch m) => m.group(1)!)
          .toSet();
      grants[role]?.removeAll(revoked);
    }
  }
  return grants;
}

/// The full text of one bucket definition.
String _bucketBlock(String name) {
  final String rules = _read('powersync/sync-rules.yaml');
  final List<RegExpMatch> headers = RegExp(r'\n    ([a-z_]+):\n')
      .allMatches(rules)
      .toList();
  for (int index = 0; index < headers.length; index += 1) {
    if (headers[index].group(1) != name) continue;
    final int start = headers[index].end;
    final int end = index + 1 < headers.length
        ? headers[index + 1].start
        : rules.length;
    return rules.substring(start, end);
  }
  return '';
}

/// Bucket name to the text of its parameter section, comments stripped.
Map<String, String> _bucketParameters() {
  final String rules = _read('powersync/sync-rules.yaml');
  final Map<String, String> parameters = <String, String>{};
  final List<RegExpMatch> headers = RegExp(r'\n    ([a-z_]+):\n')
      .allMatches(rules)
      .toList();
  for (int index = 0; index < headers.length; index += 1) {
    final int start = headers[index].end;
    final int end = index + 1 < headers.length
        ? headers[index + 1].start
        : rules.length;
    final String block = rules.substring(start, end);
    final int parametersAt = block.indexOf('parameters:');
    if (parametersAt < 0) continue;
    final int dataAt = block.indexOf('data:', parametersAt);
    final String section = dataAt < 0
        ? block.substring(parametersAt)
        : block.substring(parametersAt, dataAt);
    parameters[headers[index].group(1)!] = section.replaceAll(
      RegExp(r'#[^\n]*'),
      '',
    );
  }
  return parameters;
}

void main() {
  group('patient role containment', () {
    test('the patient role holds no staff clinical permission', () {
      final Set<String> grants =
          _effectiveGrants()['patient'] ?? const <String>{};

      expect(
        grants.intersection(_staffOnlyForPatients),
        isEmpty,
        reason:
            'A staff clinical permission on the patient role exposes every '
            'patient in the tenant through RLS and admits the portal account '
            'to the staff replication buckets: '
            '${grants.intersection(_staffOnlyForPatients).join(', ')}',
      );
    });

    test('the patient role keeps the portal capability', () {
      final Set<String> grants =
          _effectiveGrants()['patient'] ?? const <String>{};

      expect(
        grants,
        contains(_portalAccess),
        reason:
            'Without portal.access the portal bucket matches nothing and the '
            'patient sees an empty record after the staff grants are removed.',
      );
    });

    test('every bucket keyed on a staff clinical permission excludes the '
        'patient role', () {
      final Map<String, String> buckets = _bucketParameters();
      final List<String> exposed = <String>[];

      for (final MapEntry<String, String> entry in buckets.entries) {
        final Set<String> keys = RegExp(r"permission_key\s*=\s*'([a-z0-9_.]+)'")
            .allMatches(entry.value)
            .map((RegExpMatch m) => m.group(1)!)
            .toSet();
        if (keys.intersection(_staffOnlyForPatients).isEmpty) continue;
        if (!entry.value.contains("role_key <> 'patient'")) {
          exposed.add(entry.key);
        }
      }

      expect(
        exposed,
        isEmpty,
        reason:
            'These buckets replicate clinical rows to any member holding the '
            'permission. The patient role has held that permission before; '
            'without the role filter one bad seed re-opens the disclosure: '
            '${exposed.join(', ')}',
      );
    });

    test('the portal bucket still reads the link, not the tenant', () {
      final String parameters = _bucketParameters()['patient_portal'] ?? '';
      final String bucket = _bucketBlock('patient_portal');

      expect(parameters, contains("permission_key = 'portal.access'"));
      expect(
        bucket,
        contains('l.portal_user_id = :user_id'),
        reason:
            'The portal bucket must resolve rows through a live link. A '
            'tenant-wide select would hand a portal account every patient.',
      );
      expect(bucket, contains('l.revoked_at is null'));
      expect(
        bucket,
        contains("p.status = 'finalized'"),
        reason:
            'The screen hides a draft prescription, but the device still '
            'stores what the bucket replicates. Only a finalized order may '
            'reach the phone.',
      );
      expect(
        bucket,
        contains('from public.prescription_items i'),
        reason:
            'A prescription row carries an order code and an indication, not '
            'a drug. Without its lines the portal cannot name the medicine or '
            'its dose.',
      );
    });

    test('the hardening migration revokes the grants and arms the guard', () {
      final String sql = _withoutComments(
        _read(
          'supabase/migrations/20260917570000_phase4_patient_role_scope.sql',
        ),
      );

      expect(sql, contains('delete from public.role_permissions'));
      expect(sql, contains('function nodex.tg_patient_role_scope_guard'));
      expect(sql, contains('trigger role_permissions_patient_scope'));
      for (final String permission in _staffOnlyForPatients) {
        expect(
          sql,
          contains("'$permission'"),
          reason: 'The revocation must name $permission explicitly.',
        );
      }
    });

    test('clinical object reads require a clinical permission', () {
      final String sql = _withoutComments(
        _read(
          'supabase/migrations/20260917580000_phase4_storage_read_scope.sql',
        ),
      );
      final RegExp policy = RegExp(
        r'create policy (\w+_read) on storage\.objects(.*?);',
        caseSensitive: false,
        dotAll: true,
      );
      final List<RegExpMatch> policies = policy.allMatches(sql).toList();

      expect(policies.length, 3);
      for (final RegExpMatch match in policies) {
        expect(
          match.group(2),
          contains('has_permission'),
          reason:
              '${match.group(1)} gates storage reads on tenancy alone. A '
              'portal account or a non-clinical clerk could then download '
              'every image, document and signature in the tenant.',
        );
      }
    });

    test('clinical object writes are write-once', () {
      final String sql = _withoutComments(
        _read(
          'supabase/migrations/20260918120000_phase4_storage_immutability.sql',
        ),
      );

      expect(
        sql,
        contains(
          'drop policy if exists clinical_images_update on storage.objects',
        ),
        reason:
            'Clinical media must be superseded by a new object, not rewritten.',
      );
      expect(
        sql,
        contains(
          'drop policy if exists clinical_documents_update on storage.objects',
        ),
        reason: 'Clinical documents share the write-once contract.',
      );
      expect(
        sql,
        contains(
          'drop policy if exists clinical_signatures_update on storage.objects',
        ),
        reason: 'Clinical signatures share the write-once contract.',
      );
      expect(
        sql,
        isNot(contains('for update on storage.objects')),
        reason: 'The write-once migration must not recreate an update policy.',
      );
    });

    test('the staff directory is scoped by staff_directory.read', () {
      final String rules = _read('powersync/sync-rules.yaml');
      final int start = rules.indexOf('tenant_master_data:');
      final int end = rules.indexOf('membership_self:', start);
      final String bucket = rules.substring(start, end);

      expect(
        bucket,
        contains("rp.permission_key = 'staff_directory.read'"),
        reason:
            'PowerSync bypasses RLS. Replicating every app_users row to every '
            'member leaks staff names, designations and employee codes that '
            'the database withholds from roles without the permission.',
      );
    });
  });
}
