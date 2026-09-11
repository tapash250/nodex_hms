/// Tests for the PowerSync local schema and the permission/navigation catalogues.
///
/// Local table and column names must mirror the PostgreSQL schema exactly:
/// PowerSync replicates by name, so a mismatch silently drops a column rather
/// than failing loudly. These tests pin the shape of the local projection and
/// check that the client-side catalogues stay consistent with the database.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/app/router/navigation_destinations.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/authorization_snapshot.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:powersync_sqlcipher/powersync.dart';

void main() {
  group('NodexLocalSchema', () {
    late Schema schema;

    setUp(() {
      schema = NodexLocalSchema.build();
    });

    test('passes PowerSync validation', () {
      expect(schema.validate, returnsNormally);
    });

    test('declares every Phase 1 table plus Module 10 (MPI)', () {
      final Set<String> tableNames = schema.tables
          .map((Table table) => table.name)
          .toSet();

      expect(tableNames, <String>{
        LocalTables.tenants,
        LocalTables.facilities,
        LocalTables.departments,
        LocalTables.wards,
        LocalTables.appUsers,
        LocalTables.roles,
        LocalTables.permissions,
        LocalTables.rolePermissions,
        LocalTables.memberships,
        LocalTables.devices,
        LocalTables.syncCursors,
        LocalTables.aiModelRegistry,
        LocalTables.aiRoutingPolicies,
        LocalTables.localMutationLog,
        LocalTables.localDiagnostics,
        LocalTables.patients,
        LocalTables.patientAllergies,
        LocalTables.patientMergeHistory,
      });
    });

    test('does not replicate audit or clinical event tables to the device', () {
      // Append-only history is read through the server, not held locally: a
      // device must not carry an unbounded audit trail.
      final Set<String> tableNames = schema.tables
          .map((Table table) => table.name)
          .toSet();

      expect(tableNames, isNot(contains('audit_events')));
      expect(tableNames, isNot(contains('clinical_events')));
      expect(tableNames, isNot(contains('authorization_snapshots')));
    });

    test('marks diagnostics and the mutation ledger as local-only', () {
      // Local-only tables are never uploaded; they are device bookkeeping.
      for (final String name in <String>[
        LocalTables.localMutationLog,
        LocalTables.localDiagnostics,
      ]) {
        final Table table = schema.tables.firstWhere(
          (Table t) => t.name == name,
        );
        expect(table.localOnly, isTrue, reason: '$name must be local-only');
      }
    });

    test('replicated tables are not local-only', () {
      const Set<String> localOnly = <String>{
        LocalTables.localMutationLog,
        LocalTables.localDiagnostics,
      };

      for (final Table table in schema.tables) {
        if (localOnly.contains(table.name)) {
          continue;
        }
        expect(
          table.localOnly,
          isFalse,
          reason: '${table.name} must participate in replication',
        );
      }
    });

    test('no table declares an explicit id column', () {
      // PowerSync adds `id` as the primary key; declaring it is an error.
      for (final Table table in schema.tables) {
        expect(
          table.columns.map((Column c) => c.name),
          isNot(contains('id')),
          reason: '${table.name} must not declare an id column',
        );
      }
    });

    test('memberships carries the fields the authorization model needs', () {
      final Table memberships = schema.tables.firstWhere(
        (Table t) => t.name == LocalTables.memberships,
      );
      final Set<String> columns = memberships.columns
          .map((Column c) => c.name)
          .toSet();

      expect(
        columns,
        containsAll(<String>[
          'tenant_id',
          'user_id',
          'role_key',
          'facility_id',
          'department_id',
          'ward_id',
          'status',
          'valid_from',
          'valid_until',
        ]),
      );
    });

    test('the AI registry mirrors the governance columns', () {
      final Table registry = schema.tables.firstWhere(
        (Table t) => t.name == LocalTables.aiModelRegistry,
      );
      final Set<String> columns = registry.columns
          .map((Column c) => c.name)
          .toSet();

      expect(
        columns,
        containsAll(<String>[
          'model_key',
          'provider',
          'provider_model_id',
          'clinical_risk_tier',
          'privacy_class',
          'model_revision',
          'evaluation_set_revision',
          'evaluation_status',
          'lifecycle_status',
          'enabled',
        ]),
      );
    });

    test('routing policies mirror the per-engine candidate chain', () {
      final Table policies = schema.tables.firstWhere(
        (Table t) => t.name == LocalTables.aiRoutingPolicies,
      );
      final Set<String> columns = policies.columns
          .map((Column c) => c.name)
          .toSet();

      expect(
        columns,
        containsAll(<String>[
          'engine_key',
          'primary_model_key',
          'secondary_model_key',
          'tertiary_model_key',
          'offline_fallback_model_key',
          'require_human_review',
          'policy_revision',
        ]),
      );
    });

    test('the local mutation ledger records what diagnostics need', () {
      final Table ledger = schema.tables.firstWhere(
        (Table t) => t.name == LocalTables.localMutationLog,
      );
      final Set<String> columns = ledger.columns
          .map((Column c) => c.name)
          .toSet();

      expect(
        columns,
        containsAll(<String>[
          'operation',
          'resource_type',
          'idempotency_key',
          'conflict_policy',
          'status',
          'attempt_count',
          'rejection_class',
        ]),
      );
    });

    test('MPI tables mirror the PostgreSQL patient schema', () {
      // Rule 1 of the local schema file: names mirror PostgreSQL exactly, or
      // PowerSync silently drops the column. The mergeable contact columns
      // must be present or field-level merge has nothing to merge.
      Table byName(String name) =>
          schema.tables.firstWhere((Table table) => table.name == name);

      final Set<String> patientColumns = byName(LocalTables.patients).columns
          .map((Column c) => c.name)
          .toSet();
      expect(
        patientColumns,
        containsAll(<String>{
          'tenant_id',
          'mrn',
          'national_id_hash',
          'first_name',
          'last_name',
          'date_of_birth',
          'gender',
          'blood_group',
          'phone_number',
          'email',
          'address',
          'next_of_kin',
          'occupation',
          'marital_status',
          'preferred_language',
          'is_active',
        }),
      );

      final Set<String> allergyColumns = byName(LocalTables.patientAllergies)
          .columns
          .map((Column c) => c.name)
          .toSet();
      expect(
        allergyColumns,
        containsAll(<String>{
          'tenant_id',
          'patient_id',
          'substance',
          'reaction',
          'severity',
          'status',
          'retired_reason',
          'retired_at',
        }),
      );

      expect(
        byName(LocalTables.patientMergeHistory).columns
            .map((Column c) => c.name)
            .toSet(),
        containsAll(<String>{
          'tenant_id',
          'surviving_patient_id',
          'merged_patient_id',
          'reason',
          'field_choices',
        }),
      );
    });

    test('every declared index references an existing column', () {
      // Schema.validate already checks this, but asserting it here documents the
      // invariant and catches a bad index without relying on error text.
      for (final Table table in schema.tables) {
        final Set<String> columns = table.columns
            .map((Column c) => c.name)
            .toSet();
        for (final Index index in table.indexes) {
          for (final IndexedColumn indexed in index.columns) {
            expect(
              columns,
              contains(indexed.column),
              reason:
                  '${table.name}.${index.name} references '
                  'missing column ${indexed.column}',
            );
          }
        }
      }
    });
  });

  group('NodexPermissions catalogue', () {
    test('every permission key uses the dotted convention', () {
      final RegExp pattern = RegExp(r'^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$');
      final Set<String> allKeys = <String>{
        ...NodexPermissions.requiresOnline,
        ...NodexPermissions.highRisk,
      };

      for (final String key in allKeys) {
        expect(
          pattern.hasMatch(key),
          isTrue,
          reason: '$key must match the permission key pattern',
        );
      }
    });

    test('the online-only set covers the specification list', () {
      // Operations the specification names as requiring online revalidation or
      // elevated control.
      expect(
        NodexPermissions.requiresOnline,
        containsAll(<String>[
          NodexPermissions.membershipGrant,
          NodexPermissions.tenantAdminister,
          NodexPermissions.userAdminister,
          NodexPermissions.transfusionFinalize,
          NodexPermissions.billingSettle,
          NodexPermissions.dischargeFinalize,
          NodexPermissions.prescriptionFinalize,
        ]),
      );
    });

    test('high-risk clinical actions are catalogued', () {
      expect(
        NodexPermissions.highRisk,
        containsAll(<String>[
          NodexPermissions.prescriptionFinalize,
          NodexPermissions.medicationAdminister,
          NodexPermissions.pharmacyDispense,
          NodexPermissions.labResultVerify,
          NodexPermissions.triageEscalate,
          NodexPermissions.dischargeFinalize,
          NodexPermissions.transfusionFinalize,
          NodexPermissions.billingSettle,
        ]),
      );
    });

    test('bedside high-risk actions remain available offline', () {
      // Medication administration, dispensing and triage escalation happen at the
      // bedside, where connectivity cannot be assumed. They are high-risk but not
      // online-only; the audit trail records that they occurred offline.
      for (final String permission in <String>[
        NodexPermissions.medicationAdminister,
        NodexPermissions.pharmacyDispense,
        NodexPermissions.triageEscalate,
      ]) {
        expect(
          NodexPermissions.highRisk.contains(permission),
          isTrue,
          reason: '$permission must be classified high risk',
        );
        expect(
          NodexPermissions.requiresOnline.contains(permission),
          isFalse,
          reason: '$permission must remain possible at the bedside offline',
        );
      }
    });

    test('routine clinical reads are neither high-risk nor online-only', () {
      for (final String permission in <String>[
        NodexPermissions.patientRead,
        NodexPermissions.encounterRead,
        NodexPermissions.vitalsRecord,
        NodexPermissions.appointmentRead,
      ]) {
        expect(NodexPermissions.highRisk.contains(permission), isFalse);
        expect(NodexPermissions.requiresOnline.contains(permission), isFalse);
      }
    });

    test('role keys match the database pattern', () {
      final RegExp pattern = RegExp(r'^[a-z][a-z0-9_]{2,49}$');
      for (final String role in NodexRoles.all) {
        expect(pattern.hasMatch(role), isTrue, reason: '$role is malformed');
      }
    });

    test('every specification role is catalogued', () {
      expect(NodexRoles.all, hasLength(9));
      expect(
        NodexRoles.all,
        containsAll(<String>[
          NodexRoles.hospitalSuperAdmin,
          NodexRoles.medicalOfficer,
          NodexRoles.nursingStaff,
          NodexRoles.labTechnician,
          NodexRoles.pharmacist,
          NodexRoles.billingAccounts,
          NodexRoles.patient,
          NodexRoles.integrationService,
          NodexRoles.auditor,
        ]),
      );
    });
  });

  group('NodexDestinations', () {
    // Bound to wall-clock time so the snapshot is live: an expired snapshot
    // authorizes nothing, which would make these assertions pass vacuously.
    final DateTime issuedAt = DateTime.now().toUtc();

    AuthorizationPolicy policyWith(Set<String> permissions) =>
        AuthorizationPolicy(
          snapshot: AuthorizationSnapshot(
            snapshotId: 's',
            tenantId: 't',
            userId: 'u',
            deviceId: 'd',
            revision: 1,
            issuedAt: issuedAt,
            expiresAt: issuedAt.add(const Duration(hours: 12)),
            payloadDigest: 'digest',
            roles: const <String>{},
            permissions: permissions,
            offlinePermissions: permissions,
            facilityIds: const <String>{},
            departmentIds: const <String>{},
            wardIds: const <String>{},
          ),
          connectivity: ConnectivityState.online,
        );

    test('destination paths are unique and rooted', () {
      final Set<String> paths = <String>{};
      for (final NavigationDestinationSpec spec in NodexDestinations.all) {
        expect(spec.routePath.startsWith('/'), isTrue);
        expect(
          paths.add(spec.routePath),
          isTrue,
          reason: 'duplicate route ${spec.routePath}',
        );
      }
    });

    test('every destination cites a module code', () {
      for (final NavigationDestinationSpec spec in NodexDestinations.all) {
        expect(
          RegExp(r'^M\d{2}$').hasMatch(spec.moduleCode),
          isTrue,
          reason: '${spec.label} must cite a specification module code',
        );
      }
    });

    test('a destination with no declared permissions is always visible', () {
      expect(
        NodexDestinations.home.isVisibleTo(policyWith(const <String>{})),
        isTrue,
      );
      expect(
        NodexDestinations.syncDiagnostics.isVisibleTo(
          policyWith(const <String>{}),
        ),
        isTrue,
      );
    });

    test('a permission-gated destination is hidden without the permission', () {
      expect(
        NodexDestinations.patients.isVisibleTo(policyWith(const <String>{})),
        isFalse,
      );
      expect(
        NodexDestinations.audit.isVisibleTo(policyWith(const <String>{})),
        isFalse,
      );
    });

    test('a permission-gated destination appears once granted', () {
      expect(
        NodexDestinations.patients.isVisibleTo(
          policyWith(<String>{NodexPermissions.patientRead}),
        ),
        isTrue,
      );
    });

    test('visibleTo filters by permission and by primary flag', () {
      final AuthorizationPolicy policy = policyWith(<String>{
        NodexPermissions.patientRead,
        NodexPermissions.auditRead,
      });

      final List<NavigationDestinationSpec> all = NodexDestinations.visibleTo(
        policy,
      );
      final List<NavigationDestinationSpec> primary =
          NodexDestinations.visibleTo(policy, primaryOnly: true);

      expect(all, contains(NodexDestinations.audit));
      // Audit is reachable but not a primary navigation destination: a phone
      // bottom bar cannot hold every module.
      expect(primary, isNot(contains(NodexDestinations.audit)));
      expect(primary, contains(NodexDestinations.patients));
    });

    test(
      'a nurse sees ward-relevant destinations and not billing analytics',
      () {
        final AuthorizationPolicy nurse = policyWith(<String>{
          NodexPermissions.patientRead,
          NodexPermissions.vitalsRecord,
          NodexPermissions.medicationAdminister,
        });

        final List<NavigationDestinationSpec> visible =
            NodexDestinations.visibleTo(nurse);

        expect(visible, contains(NodexDestinations.patients));
        expect(visible, contains(NodexDestinations.home));
        expect(visible, isNot(contains(NodexDestinations.aiGovernance)));
        expect(visible, isNot(contains(NodexDestinations.audit)));
      },
    );
  });
}
