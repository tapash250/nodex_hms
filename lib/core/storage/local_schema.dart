/// PowerSync local schema: the authoritative local operational projection.
///
/// The local database is not a cache. During interactive clinical operation it
/// is the primary source for the currently authorized device scope, while
/// Supabase PostgreSQL remains the authoritative cloud system of record.
///
/// Two rules shape this file:
///
/// 1. Table and column names mirror the PostgreSQL schema exactly. PowerSync
///    replicates by name, and a mismatch would silently drop a column.
/// 2. Only data required for authorized offline workflows appears here. Rows a
///    device is not entitled to hold must never be replicated, which is enforced
///    by sync stream definitions on the server, not by omission in the UI.
///
/// Phase 1 covers identity, tenancy, device state, sync diagnostics and AI
/// configuration. Clinical tables arrive with their modules in Phase 2, each
/// carrying its own conflict policy.
library;

import 'package:powersync_sqlcipher/powersync.dart';

/// Local table names, referenced by repositories instead of inline literals.
abstract final class LocalTables {
  /// Tenant catalogue.
  static const String tenants = 'tenants';

  /// Facility catalogue.
  static const String facilities = 'facilities';

  /// Department catalogue.
  static const String departments = 'departments';

  /// Ward catalogue.
  static const String wards = 'wards';

  /// Application user profiles within the device scope.
  static const String appUsers = 'app_users';

  /// Role catalogue.
  static const String roles = 'roles';

  /// Permission catalogue.
  static const String permissions = 'permissions';

  /// Role to permission grants.
  static const String rolePermissions = 'role_permissions';

  /// Role assignments for the signed-in principal.
  static const String memberships = 'memberships';

  /// This device's registration record.
  static const String devices = 'devices';

  /// Per-stream sync health for this device.
  static const String syncCursors = 'sync_cursors';

  /// AI model registry, replicated as read-only configuration.
  static const String aiModelRegistry = 'ai_model_registry';

  /// Per-engine routing policy, replicated as read-only configuration.
  static const String aiRoutingPolicies = 'ai_routing_policies';

  /// Local-only mirror of the outbound mutation ledger.
  static const String localMutationLog = 'local_mutation_log';

  /// Local-only diagnostics ring buffer.
  static const String localDiagnostics = 'local_diagnostics';

  /// Master Patient Index (Module 10). Synced, tenant-scoped.
  static const String patients = 'patients';

  /// Allergy records (Module 10). Synced, tenant-scoped, append-only semantics.
  static const String patientAllergies = 'patient_allergies';

  /// Master-merge audit trail (Module 10). Synced, append-only.
  static const String patientMergeHistory = 'patient_merge_history';
}

/// Builds the PowerSync schema for the Phase 1 foundation.
///
/// `id` is added automatically by PowerSync as the primary key of every synced
/// table and must not be declared explicitly.
abstract final class NodexLocalSchema {
  /// The schema handed to the PowerSync database on open.
  static Schema build() => const Schema(<Table>[
    _tenants,
    _facilities,
    _departments,
    _wards,
    _appUsers,
    _roles,
    _permissions,
    _rolePermissions,
    _memberships,
    _devices,
    _syncCursors,
    _aiModelRegistry,
    _aiRoutingPolicies,
    _localMutationLog,
    _localDiagnostics,
    _patients,
    _patientAllergies,
    _patientMergeHistory,
  ]);

  static const Table _tenants = Table(LocalTables.tenants, <Column>[
    Column.text('slug'),
    Column.text('display_name'),
    Column.text('legal_name'),
    Column.text('country_code'),
    Column.text('timezone'),
    Column.text('locale'),
    Column.text('status'),
    Column.text('settings'),
    Column.text('updated_at'),
  ]);

  static const Table _facilities = Table(
    LocalTables.facilities,
    <Column>[
      Column.text('tenant_id'),
      Column.text('code'),
      Column.text('display_name'),
      Column.text('facility_type'),
      Column.text('timezone'),
      Column.text('address'),
      Column.text('status'),
      Column.text('updated_at'),
    ],
    indexes: <Index>[
      Index('facility_tenant', <IndexedColumn>[IndexedColumn('tenant_id')]),
    ],
  );

  static const Table _departments = Table(
    LocalTables.departments,
    <Column>[
      Column.text('tenant_id'),
      Column.text('facility_id'),
      Column.text('code'),
      Column.text('display_name'),
      Column.text('specialty'),
      Column.text('head_user_id'),
      Column.text('status'),
      Column.text('updated_at'),
    ],
    indexes: <Index>[
      Index('department_facility', <IndexedColumn>[
        IndexedColumn('facility_id'),
      ]),
    ],
  );

  static const Table _wards = Table(
    LocalTables.wards,
    <Column>[
      Column.text('tenant_id'),
      Column.text('facility_id'),
      Column.text('department_id'),
      Column.text('code'),
      Column.text('display_name'),
      Column.text('ward_type'),
      Column.text('floor_label'),
      Column.integer('bed_capacity'),
      Column.text('status'),
      Column.text('updated_at'),
    ],
    indexes: <Index>[
      Index('ward_facility', <IndexedColumn>[IndexedColumn('facility_id')]),
    ],
  );

  static const Table _appUsers = Table(
    LocalTables.appUsers,
    <Column>[
      Column.text('primary_tenant_id'),
      Column.text('employee_code'),
      Column.text('full_name'),
      Column.text('display_name'),
      Column.text('email'),
      Column.text('phone'),
      Column.text('designation'),
      Column.text('registration_no'),
      Column.text('status'),
      Column.text('locale'),
      Column.text('avatar_path'),
      Column.text('last_login_at'),
      Column.text('updated_at'),
    ],
    indexes: <Index>[
      Index('app_user_tenant', <IndexedColumn>[
        IndexedColumn('primary_tenant_id'),
      ]),
    ],
  );

  // Role, permission and grant catalogues are configuration. They are read-only
  // on the device: the local copy exists so navigation and the offline
  // authorization policy can resolve permission metadata without a round trip.
  static const Table _roles = Table(LocalTables.roles, <Column>[
    Column.text('key'),
    Column.text('display_name'),
    Column.text('description'),
    Column.text('role_class'),
    Column.integer('is_privileged'),
    Column.integer('offline_capable'),
  ]);

  static const Table _permissions = Table(LocalTables.permissions, <Column>[
    Column.text('key'),
    Column.text('display_name'),
    Column.text('description'),
    Column.text('module_code'),
    Column.text('risk_tier'),
    Column.integer('requires_online'),
  ]);

  static const Table _rolePermissions = Table(
    LocalTables.rolePermissions,
    <Column>[Column.text('role_key'), Column.text('permission_key')],
    indexes: <Index>[
      Index('role_permission_role', <IndexedColumn>[IndexedColumn('role_key')]),
    ],
  );

  static const Table _memberships = Table(
    LocalTables.memberships,
    <Column>[
      Column.text('tenant_id'),
      Column.text('user_id'),
      Column.text('role_key'),
      Column.text('facility_id'),
      Column.text('department_id'),
      Column.text('ward_id'),
      Column.text('status'),
      Column.text('valid_from'),
      Column.text('valid_until'),
      Column.text('updated_at'),
    ],
    indexes: <Index>[
      Index('membership_user', <IndexedColumn>[
        IndexedColumn('user_id'),
        IndexedColumn('tenant_id'),
      ]),
    ],
  );

  static const Table _devices = Table(LocalTables.devices, <Column>[
    Column.text('tenant_id'),
    Column.text('device_fingerprint'),
    Column.text('display_name'),
    Column.text('platform'),
    Column.text('form_factor'),
    Column.text('os_version'),
    Column.text('app_version'),
    Column.text('assigned_user_id'),
    Column.text('assigned_facility_id'),
    Column.text('status'),
    Column.integer('offline_window_minutes'),
    Column.text('last_seen_at'),
    Column.text('last_sync_at'),
    Column.text('revoked_at'),
    Column.text('revoked_reason'),
    Column.text('wipe_requested_at'),
    Column.text('wipe_confirmed_at'),
    Column.text('updated_at'),
  ]);

  static const Table _syncCursors = Table(
    LocalTables.syncCursors,
    <Column>[
      Column.text('tenant_id'),
      Column.text('device_id'),
      Column.text('stream_name'),
      Column.text('last_synced_at'),
      Column.text('checkpoint'),
      Column.integer('queue_depth'),
      Column.text('oldest_pending_at'),
      Column.text('health'),
      Column.text('last_error'),
      Column.text('updated_at'),
    ],
    indexes: <Index>[
      Index('sync_cursor_device', <IndexedColumn>[IndexedColumn('device_id')]),
    ],
  );

  static const Table _aiModelRegistry = Table(
    LocalTables.aiModelRegistry,
    <Column>[
      Column.text('model_key'),
      Column.text('provider'),
      Column.text('provider_model_id'),
      Column.text('display_name'),
      Column.text('modality'),
      Column.text('clinical_risk_tier'),
      Column.text('privacy_class'),
      Column.integer('context_window'),
      Column.integer('max_output_tokens'),
      Column.integer('supports_structured_json'),
      Column.integer('supports_tool_calling'),
      Column.integer('supports_vision'),
      Column.integer('latency_target_ms'),
      Column.integer('memory_requirement_mb'),
      Column.text('model_revision'),
      Column.text('evaluation_set_revision'),
      Column.text('evaluation_status'),
      Column.text('lifecycle_status'),
      Column.integer('enabled'),
      Column.integer('priority'),
      Column.text('intended_use'),
      Column.text('updated_at'),
    ],
    indexes: <Index>[
      Index('ai_model_lifecycle', <IndexedColumn>[
        IndexedColumn('lifecycle_status'),
      ]),
    ],
  );

  static const Table _aiRoutingPolicies = Table(
    LocalTables.aiRoutingPolicies,
    <Column>[
      Column.text('engine_key'),
      Column.text('environment'),
      Column.text('primary_model_key'),
      Column.text('secondary_model_key'),
      Column.text('tertiary_model_key'),
      Column.text('offline_fallback_model_key'),
      Column.integer('timeout_ms'),
      Column.integer('max_attempts'),
      Column.integer('circuit_breaker_threshold'),
      Column.integer('circuit_breaker_seconds'),
      Column.integer('require_structured_output'),
      Column.integer('require_human_review'),
      Column.text('minimum_risk_capability'),
      Column.integer('allow_manual_fallback'),
      Column.text('policy_revision'),
      Column.integer('enabled'),
      Column.text('updated_at'),
    ],
    indexes: <Index>[
      Index('ai_routing_engine', <IndexedColumn>[IndexedColumn('engine_key')]),
    ],
  );

  /// Local-only ledger mirroring what this device has queued for upload.
  ///
  /// PowerSync owns the upload queue itself. This table records the NODEX-level
  /// view of each mutation (operation, resource, idempotency key, attempt count,
  /// rejection class) so the sync diagnostics screen can show a failed mutation
  /// that the queue has already surrendered, satisfying the requirement that
  /// failed synchronization is visible and never silently discarded.
  static const Table _localMutationLog = Table.localOnly(
    LocalTables.localMutationLog,
    <Column>[
      Column.text('tenant_id'),
      Column.text('user_id'),
      Column.text('device_id'),
      Column.text('operation'),
      Column.text('resource_type'),
      Column.text('resource_id'),
      Column.text('idempotency_key'),
      Column.text('conflict_policy'),
      Column.text('status'),
      Column.integer('attempt_count'),
      Column.text('origin'),
      Column.text('payload_digest'),
      Column.text('rejection_class'),
      Column.text('rejection_detail'),
      Column.text('client_created_at'),
      Column.text('last_attempt_at'),
      Column.text('resolved_at'),
    ],
    indexes: <Index>[
      Index('local_mutation_status', <IndexedColumn>[IndexedColumn('status')]),
      Index('local_mutation_idempotency', <IndexedColumn>[
        IndexedColumn('idempotency_key'),
      ]),
    ],
  );

  /// Local-only diagnostics ring buffer surfaced by the sync diagnostics screen.
  ///
  /// Records are redacted before insertion by the logging layer; this table must
  /// never hold PHI.
  static const Table _localDiagnostics = Table.localOnly(
    LocalTables.localDiagnostics,
    <Column>[
      Column.text('recorded_at'),
      Column.text('level'),
      Column.text('module'),
      Column.text('operation'),
      Column.text('outcome'),
      Column.text('error_code'),
      Column.text('message'),
      Column.text('dimensions'),
    ],
    indexes: <Index>[
      Index('local_diagnostic_time', <IndexedColumn>[
        IndexedColumn('recorded_at'),
      ]),
    ],
  );

  /// Master Patient Index (Module 10).
  ///
  /// Mirrors `public.patients` exactly: PowerSync replicates by name, and the
  /// mutation-handler allowlist validates these same columns server-side.
  /// Dates travel as ISO-8601 text; booleans as integers.
  static const Table _patients = Table(
    LocalTables.patients,
    <Column>[
      Column.text('tenant_id'),
      Column.text('mrn'),
      Column.text('national_id_hash'),
      Column.text('first_name'),
      Column.text('last_name'),
      Column.text('date_of_birth'),
      Column.text('gender'),
      Column.text('blood_group'),
      Column.text('phone_number'),
      Column.text('email'),
      Column.text('address'),
      Column.text('next_of_kin'),
      Column.text('occupation'),
      Column.text('marital_status'),
      Column.text('preferred_language'),
      Column.integer('is_active'),
      Column.text('created_by'),
      Column.text('created_at'),
      Column.text('updated_at'),
    ],
    indexes: <Index>[
      Index('patient_tenant_name', <IndexedColumn>[
        IndexedColumn('tenant_id'),
        IndexedColumn('last_name'),
        IndexedColumn('first_name'),
      ]),
      Index('patient_tenant_mrn', <IndexedColumn>[
        IndexedColumn('tenant_id'),
        IndexedColumn('mrn'),
      ]),
      Index('patient_tenant_phone', <IndexedColumn>[
        IndexedColumn('tenant_id'),
        IndexedColumn('phone_number'),
      ]),
    ],
  );

  /// Allergy records (Module 10).
  ///
  /// Append-only semantics are enforced server-side by
  /// `nodex.tg_allergy_retire_only`; the local projection mirrors the same
  /// rule by convention — repositories retire, never edit.
  static const Table _patientAllergies = Table(
    LocalTables.patientAllergies,
    <Column>[
      Column.text('tenant_id'),
      Column.text('patient_id'),
      Column.text('substance'),
      Column.text('reaction'),
      Column.text('severity'),
      Column.text('status'),
      Column.text('retired_reason'),
      Column.text('recorded_by'),
      Column.text('recorded_at'),
      Column.text('retired_at'),
      Column.text('created_at'),
    ],
    indexes: <Index>[
      Index('allergy_patient', <IndexedColumn>[
        IndexedColumn('patient_id'),
        IndexedColumn('status'),
      ]),
    ],
  );

  /// Master-merge audit trail (Module 10). Written once per merge, never edited.
  static const Table _patientMergeHistory = Table(
    LocalTables.patientMergeHistory,
    <Column>[
      Column.text('tenant_id'),
      Column.text('surviving_patient_id'),
      Column.text('merged_patient_id'),
      Column.text('merged_by'),
      Column.text('reason'),
      Column.text('field_choices'),
      Column.text('created_at'),
    ],
    indexes: <Index>[
      Index('merge_surviving', <IndexedColumn>[
        IndexedColumn('surviving_patient_id'),
      ]),
    ],
  );
}
