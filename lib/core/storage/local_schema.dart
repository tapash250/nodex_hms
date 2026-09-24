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

import 'package:powersync/powersync.dart'
    show Column, Index, IndexedColumn, Schema, Table;

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

  /// Clinical encounters (Module 16). Synced, tenant-scoped.
  static const String clinicalEncounters = 'clinical_encounters';

  /// Encounter amendments (Module 16). Synced, append-only.
  static const String encounterAmendments = 'encounter_amendments';

  /// Laboratory orders (Module 17).
  static const String labOrders = 'lab_orders';

  /// Barcode-tracked laboratory specimens (Module 17).
  static const String labSpecimens = 'lab_specimens';

  /// Laboratory results, immutable after verification (Module 17).
  static const String labResults = 'lab_results';

  /// Prescription orders, immutable versions after finalization (Module 25).
  static const String prescriptions = 'prescriptions';

  /// Prescription medication lines (Module 25).
  static const String prescriptionItems = 'prescription_items';

  /// Pharmacy dispense events (Module 25). Synced, append-only.
  static const String pharmacyDispenses = 'pharmacy_dispenses';

  /// Medication administration events (Module 25). Synced, append-only.
  static const String medicationAdministrations = 'medication_administrations';

  /// Visit bookings (Module 07). Synced, tenant-scoped.
  static const String appointments = 'appointments';

  /// Ward beds (Module 11). Synced, tenant-scoped.
  static const String beds = 'beds';

  /// Bed occupancy assignments (Module 11). Synced.
  static const String bedAssignments = 'bed_assignments';

  /// Invoices, one per patient encounter (Module 31). Synced.
  static const String invoices = 'invoices';

  /// Invoice line items (Module 31). Synced.
  static const String invoiceLines = 'invoice_lines';

  /// Payment events against invoices (Module 31). Synced, append-only.
  static const String payments = 'payments';

  /// Refund events against payments (Module 31). Synced, append-only.
  static const String refunds = 'refunds';

  /// Stock catalogue items (Module 13). Synced.
  static const String stockItems = 'stock_items';

  /// Storage locations (Module 13). Synced.
  static const String stockLocations = 'stock_locations';

  /// Stock batches with expiry tracking (Module 13). Synced.
  static const String stockBatches = 'stock_batches';

  /// Append-only stock movements (Module 13). Synced.
  static const String stockMovements = 'stock_movements';

  /// Discharge records, one per encounter (Module 23). Synced.
  static const String discharges = 'discharges';

  /// Triage assessments (Module 05). Synced, tenant-scoped.
  static const String triageAssessments = 'triage_assessments';

  /// Emergency department visits (Module 05). Synced.
  static const String erVisits = 'er_visits';

  /// ICU bed census (Module 06). Synced.
  static const String icuBeds = 'icu_beds';

  /// ICU continuous vitals observations (Module 06). Synced, append-only.
  static const String icuVitals = 'icu_vitals';

  /// ICU nursing handover records (Module 06). Synced, append-only.
  static const String icuNursingHandover = 'icu_nursing_handover';

  /// Ventilator event log (Module 06). Synced, append-only.
  static const String ventilatorEvents = 'ventilator_events';
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
    _clinicalEncounters,
    _encounterAmendments,
    _labOrders,
    _labSpecimens,
    _labResults,
    _prescriptions,
    _prescriptionItems,
    _pharmacyDispenses,
    _medicationAdministrations,
    _appointments,
    _beds,
    _bedAssignments,
    _invoices,
    _invoiceLines,
    _payments,
    _refunds,
    _stockItems,
    _stockLocations,
    _stockBatches,
    _stockMovements,
    _discharges,
    _triageAssessments,
    _erVisits,
    _icuBeds,
    _icuVitals,
    _icuNursingHandover,
    _ventilatorEvents,
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

  /// Clinical encounters (Module 16).
  ///
  /// Mirrors `public.clinical_encounters` exactly. The `diagnoses` JSON column
  /// travels as text through the local projection and the upload path; the
  /// server parses it as jsonb finally.
  static const Table _clinicalEncounters = Table(
    LocalTables.clinicalEncounters,
    <Column>[
      Column.text('tenant_id'),
      Column.text('patient_id'),
      Column.text('attending_physician_id'),
      Column.text('encounter_type'),
      Column.text('status'),
      Column.text('subjective_note'),
      Column.text('objective_findings'),
      Column.text('assessment'),
      Column.text('plan_description'),
      Column.text('diagnoses'),
      Column.text('signed_at'),
      Column.text('created_by'),
      Column.text('created_at'),
      Column.text('updated_at'),
    ],
    indexes: <Index>[
      Index('encounter_patient', <IndexedColumn>[
        IndexedColumn('patient_id'),
        IndexedColumn('created_at'),
      ]),
      Index('encounter_physician', <IndexedColumn>[
        IndexedColumn('tenant_id'),
        IndexedColumn('attending_physician_id'),
        IndexedColumn('status'),
      ]),
    ],
  );

  /// Encounter amendments (Module 16). Append-only, like the server table.
  static const Table _encounterAmendments = Table(
    LocalTables.encounterAmendments,
    <Column>[
      Column.text('tenant_id'),
      Column.text('encounter_id'),
      Column.text('amendment_type'),
      Column.text('reason'),
      Column.text('field_changes'),
      Column.text('amended_by'),
      Column.text('created_at'),
    ],
    indexes: <Index>[
      Index('amendment_encounter', <IndexedColumn>[
        IndexedColumn('encounter_id'),
      ]),
    ],
  );

  /// Laboratory orders (Module 17).
  static const Table _labOrders = Table(
    LocalTables.labOrders,
    <Column>[
      Column.text('tenant_id'),
      Column.text('patient_id'),
      Column.text('encounter_id'),
      Column.text('ordered_by'),
      Column.text('order_code'),
      Column.text('priority'),
      Column.text('status'),
      Column.text('clinical_indication'),
      Column.text('tests'),
      Column.text('ordered_at'),
      Column.text('cancelled_at'),
      Column.text('cancelled_reason'),
      Column.text('created_at'),
      Column.text('updated_at'),
    ],
    indexes: <Index>[
      Index('lab_order_patient', <IndexedColumn>[
        IndexedColumn('patient_id'),
        IndexedColumn('ordered_at'),
      ]),
      Index('lab_order_status', <IndexedColumn>[
        IndexedColumn('tenant_id'),
        IndexedColumn('status'),
      ]),
    ],
  );

  /// Barcode-tracked specimens (Module 17).
  static const Table _labSpecimens = Table(
    LocalTables.labSpecimens,
    <Column>[
      Column.text('tenant_id'),
      Column.text('lab_order_id'),
      Column.text('accession_barcode'),
      Column.text('specimen_type'),
      Column.text('collected_by'),
      Column.text('collected_at'),
      Column.text('status'),
      Column.text('rejection_reason'),
      Column.text('received_at'),
      Column.text('created_at'),
      Column.text('updated_at'),
    ],
    indexes: <Index>[
      Index('lab_specimen_order', <IndexedColumn>[
        IndexedColumn('lab_order_id'),
      ]),
      Index('lab_specimen_barcode', <IndexedColumn>[
        IndexedColumn('accession_barcode'),
      ]),
    ],
  );

  /// Results: verified rows are immutable; corrections are new rows linked by
  /// correction_of.
  static const Table _labResults = Table(
    LocalTables.labResults,
    <Column>[
      Column.text('tenant_id'),
      Column.text('lab_order_id'),
      Column.text('specimen_id'),
      Column.text('analyte_code'),
      Column.text('analyte_name'),
      Column.text('value_text'),
      Column.real('value_numeric'),
      Column.text('unit'),
      Column.text('reference_range'),
      Column.text('abnormal_flag'),
      Column.text('status'),
      Column.text('entered_by'),
      Column.text('verified_by'),
      Column.text('entered_at'),
      Column.text('verified_at'),
      Column.text('correction_of'),
      Column.text('correction_reason'),
      Column.text('created_at'),
    ],
    indexes: <Index>[
      Index('lab_result_order', <IndexedColumn>[
        IndexedColumn('lab_order_id'),
        IndexedColumn('created_at'),
      ]),
      Index('lab_result_specimen', <IndexedColumn>[
        IndexedColumn('specimen_id'),
      ]),
    ],
  );

  /// Prescriptions: finalized versions are immutable; a change is a new
  /// version linked by supersedes/superseded_by.
  static const Table _prescriptions = Table(
    LocalTables.prescriptions,
    <Column>[
      Column.text('tenant_id'),
      Column.text('patient_id'),
      Column.text('encounter_id'),
      Column.text('prescribed_by'),
      Column.text('prescription_code'),
      Column.text('version'),
      Column.text('priority'),
      Column.text('status'),
      Column.text('indication'),
      Column.text('finalized_by'),
      Column.text('finalized_at'),
      Column.text('supersedes'),
      Column.text('superseded_by'),
      Column.text('closed_at'),
      Column.text('closure_reason'),
      Column.text('created_at'),
      Column.text('updated_at'),
    ],
    indexes: <Index>[
      Index('prescription_patient', <IndexedColumn>[
        IndexedColumn('patient_id'),
        IndexedColumn('created_at'),
      ]),
      Index('prescription_status', <IndexedColumn>[
        IndexedColumn('tenant_id'),
        IndexedColumn('status'),
      ]),
    ],
  );

  /// Prescription medication lines, editable while the parent order is a draft.
  static const Table _prescriptionItems = Table(
    LocalTables.prescriptionItems,
    <Column>[
      Column.text('tenant_id'),
      Column.text('prescription_id'),
      Column.text('line_number'),
      Column.text('drug_code'),
      Column.text('drug_name'),
      Column.text('strength'),
      Column.text('dosage_text'),
      Column.text('route'),
      Column.text('frequency'),
      Column.text('duration_days'),
      Column.real('quantity_prescribed'),
      Column.text('status'),
      Column.text('created_at'),
      Column.text('updated_at'),
    ],
    indexes: <Index>[
      Index('prescription_item_order', <IndexedColumn>[
        IndexedColumn('prescription_id'),
      ]),
      Index('prescription_item_drug', <IndexedColumn>[
        IndexedColumn('drug_code'),
      ]),
    ],
  );

  /// Dispense events: append-only, deduplicated by event identity upstream.
  static const Table _pharmacyDispenses = Table(
    LocalTables.pharmacyDispenses,
    <Column>[
      Column.text('tenant_id'),
      Column.text('prescription_id'),
      Column.text('item_id'),
      Column.text('dispensed_by'),
      Column.real('quantity_dispensed'),
      Column.text('batch_number'),
      Column.text('note'),
      Column.text('dispensed_at'),
      Column.text('created_at'),
    ],
    indexes: <Index>[
      Index('dispense_item', <IndexedColumn>[IndexedColumn('item_id')]),
      Index('dispense_prescription', <IndexedColumn>[
        IndexedColumn('prescription_id'),
      ]),
    ],
  );

  /// MAR events: append-only, deduplicated by event identity upstream.
  static const Table _medicationAdministrations = Table(
    LocalTables.medicationAdministrations,
    <Column>[
      Column.text('tenant_id'),
      Column.text('patient_id'),
      Column.text('prescription_id'),
      Column.text('item_id'),
      Column.text('dispense_id'),
      Column.text('administered_by'),
      Column.text('administered_at'),
      Column.text('dose_text'),
      Column.text('route'),
      Column.text('site'),
      Column.text('note'),
      Column.text('created_at'),
    ],
    indexes: <Index>[
      Index('mar_patient', <IndexedColumn>[
        IndexedColumn('patient_id'),
        IndexedColumn('administered_at'),
      ]),
      Index('mar_item', <IndexedColumn>[IndexedColumn('item_id')]),
    ],
  );

  /// Ward beds: availability only; occupancy derives from assignments.
  static const Table _beds = Table(
    LocalTables.beds,
    <Column>[
      Column.text('tenant_id'),
      Column.text('ward_id'),
      Column.text('bed_code'),
      Column.text('bed_type'),
      Column.text('status'),
      Column.text('created_at'),
      Column.text('updated_at'),
    ],
    indexes: <Index>[
      Index('bed_ward', <IndexedColumn>[
        IndexedColumn('ward_id'),
        IndexedColumn('status'),
      ]),
    ],
  );

  /// Occupancy assignments: at most one active row per bed and per patient.
  static const Table _bedAssignments = Table(
    LocalTables.bedAssignments,
    <Column>[
      Column.text('tenant_id'),
      Column.text('bed_id'),
      Column.text('patient_id'),
      Column.text('encounter_id'),
      Column.text('assigned_by'),
      Column.text('status'),
      Column.text('admitted_at'),
      Column.text('released_at'),
      Column.text('release_reason'),
      Column.text('created_at'),
      Column.text('updated_at'),
    ],
    indexes: <Index>[
      Index('bed_assignment_bed', <IndexedColumn>[
        IndexedColumn('bed_id'),
        IndexedColumn('status'),
      ]),
      Index('bed_assignment_patient', <IndexedColumn>[
        IndexedColumn('patient_id'),
      ]),
    ],
  );

  /// Invoices: one per patient encounter, with status transitions.
  static const Table _invoices = Table(
    LocalTables.invoices,
    <Column>[
      Column.text('tenant_id'),
      Column.text('patient_id'),
      Column.text('encounter_id'),
      Column.text('created_by'),
      Column.text('invoice_code'),
      Column.text('status'),
      Column.text('currency'),
      Column.integer('total_minor'),
      Column.integer('settled_minor'),
      Column.text('notes'),
      Column.text('issued_at'),
      Column.text('settled_at'),
      Column.text('closed_at'),
      Column.text('closure_reason'),
      Column.text('created_at'),
      Column.text('updated_at'),
    ],
    indexes: <Index>[
      Index('invoice_patient', <IndexedColumn>[
        IndexedColumn('patient_id'),
        IndexedColumn('created_at'),
      ]),
      Index('invoice_status', <IndexedColumn>[
        IndexedColumn('tenant_id'),
        IndexedColumn('status'),
      ]),
    ],
  );

  /// Invoice lines: individual line items within an invoice.
  static const Table _invoiceLines = Table(
    LocalTables.invoiceLines,
    <Column>[
      Column.text('tenant_id'),
      Column.text('invoice_id'),
      Column.integer('line_number'),
      Column.text('description'),
      Column.real('quantity'),
      Column.integer('unit_price_minor'),
      Column.integer('line_total_minor'),
      Column.text('created_at'),
      Column.text('updated_at'),
    ],
    indexes: <Index>[
      Index('invoice_line_invoice', <IndexedColumn>[
        IndexedColumn('invoice_id'),
        IndexedColumn('line_number'),
      ]),
    ],
  );

  /// Payments: append-only events recording payments against invoices.
  static const Table _payments = Table(
    LocalTables.payments,
    <Column>[
      Column.text('tenant_id'),
      Column.text('invoice_id'),
      Column.text('recorded_by'),
      Column.integer('amount_minor'),
      Column.integer('amount_received_minor'),
      Column.text('method'),
      Column.text('reference'),
      Column.text('note'),
      Column.text('paid_at'),
      Column.text('created_at'),
    ],
    indexes: <Index>[
      Index('payment_invoice', <IndexedColumn>[
        IndexedColumn('invoice_id'),
        IndexedColumn('paid_at'),
      ]),
      Index('payment_running_total', <IndexedColumn>[
        IndexedColumn('invoice_id'),
        IndexedColumn('amount_received_minor'),
      ]),
    ],
  );

  /// Refunds: append-only events recording refunds against payments.
  static const Table _refunds = Table(
    LocalTables.refunds,
    <Column>[
      Column.text('tenant_id'),
      Column.text('invoice_id'),
      Column.text('payment_id'),
      Column.text('recorded_by'),
      Column.integer('amount_minor'),
      Column.text('reason'),
      Column.text('refunded_at'),
      Column.text('created_at'),
    ],
    indexes: <Index>[
      Index('refund_invoice', <IndexedColumn>[
        IndexedColumn('invoice_id'),
        IndexedColumn('refunded_at'),
      ]),
      Index('refund_payment', <IndexedColumn>[IndexedColumn('payment_id')]),
    ],
  );

  /// Stock items (Module 13).
  static const Table _stockItems = Table(
    LocalTables.stockItems,
    <Column>[
      Column.text('tenant_id'),
      Column.text('item_code'),
      Column.text('name'),
      Column.text('description'),
      Column.text('category'),
      Column.text('unit'),
      Column.text('status'),
      Column.real('reorder_level'),
      Column.integer('standard_cost_minor'),
      Column.integer('requires_batch'),
      Column.integer('requires_expiry'),
      Column.text('created_by'),
      Column.text('created_at'),
      Column.text('updated_at'),
    ],
    indexes: <Index>[
      Index('stock_item_tenant', <IndexedColumn>[IndexedColumn('tenant_id')]),
      Index('stock_item_code', <IndexedColumn>[IndexedColumn('item_code')]),
    ],
  );

  /// Stock locations.
  static const Table _stockLocations = Table(
    LocalTables.stockLocations,
    <Column>[
      Column.text('tenant_id'),
      Column.text('facility_id'),
      Column.text('ward_id'),
      Column.text('location_code'),
      Column.text('name'),
      Column.text('location_type'),
      Column.text('status'),
      Column.text('created_at'),
      Column.text('updated_at'),
    ],
    indexes: <Index>[
      Index('stock_location_facility', <IndexedColumn>[
        IndexedColumn('facility_id'),
      ]),
      Index('stock_location_ward', <IndexedColumn>[IndexedColumn('ward_id')]),
    ],
  );

  /// Stock batches with expiry tracking.
  static const Table _stockBatches = Table(
    LocalTables.stockBatches,
    <Column>[
      Column.text('tenant_id'),
      Column.text('item_id'),
      Column.text('batch_number'),
      Column.text('expiry_date'),
      Column.text('manufactured_date'),
      Column.integer('quantity_minor'),
      Column.integer('cost_per_unit_minor'),
      Column.text('status'),
      Column.text('received_at'),
      Column.text('created_at'),
      Column.text('updated_at'),
    ],
    indexes: <Index>[
      Index('stock_batch_item', <IndexedColumn>[IndexedColumn('item_id')]),
      Index('stock_batch_expiry', <IndexedColumn>[
        IndexedColumn('expiry_date'),
      ]),
    ],
  );

  /// Stock movements: receipt, issue, transfer, adjustment, return, write_off, cycle_count.
  static const Table _stockMovements = Table(
    LocalTables.stockMovements,
    <Column>[
      Column.text('tenant_id'),
      Column.text('item_id'),
      Column.text('batch_id'),
      Column.text('from_location_id'),
      Column.text('to_location_id'),
      Column.text('movement_type'),
      Column.integer('quantity_minor'),
      Column.integer('unit_cost_minor'),
      Column.text('reference_type'),
      Column.text('reference_id'),
      Column.text('reason'),
      Column.text('recorded_by'),
      Column.text('recorded_at'),
      Column.text('created_at'),
      Column.text('updated_at'),
    ],
    indexes: <Index>[
      Index('stock_movement_item', <IndexedColumn>[
        IndexedColumn('item_id'),
        IndexedColumn('recorded_at'),
      ]),
      Index('stock_movement_location', <IndexedColumn>[
        IndexedColumn('from_location_id'),
        IndexedColumn('to_location_id'),
      ]),
      Index('stock_movement_batch', <IndexedColumn>[IndexedColumn('batch_id')]),
      Index('stock_movement_type', <IndexedColumn>[
        IndexedColumn('movement_type'),
        IndexedColumn('recorded_at'),
      ]),
    ],
  );

  /// Discharge records: one finalized row per encounter, immutable after.
  static const Table _discharges = Table(
    LocalTables.discharges,
    <Column>[
      Column.text('tenant_id'),
      Column.text('patient_id'),
      Column.text('encounter_id'),
      Column.text('created_by'),
      Column.text('discharge_code'),
      Column.text('discharge_type'),
      Column.text('status'),
      Column.text('summary'),
      Column.text('follow_up_plan'),
      Column.text('finalized_by'),
      Column.text('finalized_at'),
      Column.text('closed_at'),
      Column.text('closure_reason'),
      Column.text('created_at'),
      Column.text('updated_at'),
    ],
    indexes: <Index>[
      Index('discharge_patient', <IndexedColumn>[
        IndexedColumn('patient_id'),
        IndexedColumn('created_at'),
      ]),
      Index('discharge_encounter', <IndexedColumn>[
        IndexedColumn('encounter_id'),
      ]),
    ],
  );

  /// Triage assessments (Module 05): acuity, complaint, disposition and
  /// one-way escalation. Mirrors `public.triage_assessments`.
  static const Table _triageAssessments = Table(
    LocalTables.triageAssessments,
    <Column>[
      Column.text('tenant_id'),
      Column.text('patient_id'),
      Column.text('encounter_id'),
      Column.text('assessed_by'),
      Column.text('acuity'),
      Column.text('chief_complaint'),
      Column.text('vitals'),
      Column.text('red_flags'),
      Column.text('disposition'),
      Column.integer('escalated'),
      Column.text('escalated_by'),
      Column.text('escalated_at'),
      Column.text('created_at'),
      Column.text('updated_at'),
    ],
    indexes: <Index>[
      Index('triage_patient', <IndexedColumn>[
        IndexedColumn('patient_id'),
        IndexedColumn('created_at'),
      ]),
      Index('triage_acuity', <IndexedColumn>[
        IndexedColumn('tenant_id'),
        IndexedColumn('acuity'),
      ]),
    ],
  );

  /// ER visits (Module 05): status is a guarded state machine. Mirrors
  /// `public.er_visits`.
  static const Table _erVisits = Table(
    LocalTables.erVisits,
    <Column>[
      Column.text('tenant_id'),
      Column.text('patient_id'),
      Column.text('triage_id'),
      Column.text('encounter_id'),
      Column.text('provider_id'),
      Column.text('status'),
      Column.text('arrival_mode'),
      Column.text('bed_id'),
      Column.text('started_at'),
      Column.text('disposition'),
      Column.text('disposition_reason'),
      Column.text('discharged_at'),
      Column.text('created_at'),
      Column.text('updated_at'),
    ],
    indexes: <Index>[
      Index('er_visit_patient', <IndexedColumn>[
        IndexedColumn('patient_id'),
        IndexedColumn('started_at'),
      ]),
      Index('er_visit_triage', <IndexedColumn>[IndexedColumn('triage_id')]),
      Index('er_visit_status', <IndexedColumn>[
        IndexedColumn('tenant_id'),
        IndexedColumn('status'),
      ]),
    ],
  );

  /// ICU beds (Module 06): occupancy projection, server-arbitrated. Mirrors
  /// `public.icu_beds`.
  static const Table _icuBeds = Table(
    LocalTables.icuBeds,
    <Column>[
      Column.text('tenant_id'),
      Column.text('bed_id'),
      Column.text('ventilator_id'),
      Column.text('status'),
      Column.text('current_patient_id'),
      Column.text('created_at'),
      Column.text('updated_at'),
    ],
    indexes: <Index>[
      Index('icu_bed_tenant', <IndexedColumn>[
        IndexedColumn('tenant_id'),
        IndexedColumn('status'),
      ]),
      Index('icu_bed_bed', <IndexedColumn>[IndexedColumn('bed_id')]),
    ],
  );

  /// ICU vitals (Module 06): append-only observations. Mirrors
  /// `public.icu_vitals`.
  static const Table _icuVitals = Table(
    LocalTables.icuVitals,
    <Column>[
      Column.text('tenant_id'),
      Column.text('patient_id'),
      Column.text('icu_bed_id'),
      Column.text('recorded_by'),
      Column.text('recorded_at'),
      Column.integer('heart_rate'),
      Column.integer('spo2'),
      Column.integer('respiratory_rate'),
      Column.real('temperature_celsius'),
      Column.integer('systolic_bp'),
      Column.integer('diastolic_bp'),
      Column.integer('map'),
      Column.real('cvp'),
      Column.integer('etco2'),
      Column.integer('gcs_total'),
      Column.integer('gcs_eye'),
      Column.integer('gcs_verbal'),
      Column.integer('gcs_motor'),
      Column.real('fi_o2'),
      Column.integer('peep'),
      Column.integer('tidal_volume'),
      Column.text('respiratory_mode'),
      Column.text('created_at'),
    ],
    indexes: <Index>[
      Index('icu_vitals_patient', <IndexedColumn>[
        IndexedColumn('patient_id'),
        IndexedColumn('recorded_at'),
      ]),
      Index('icu_vitals_bed', <IndexedColumn>[
        IndexedColumn('icu_bed_id'),
        IndexedColumn('recorded_at'),
      ]),
    ],
  );

  /// Nursing handover (Module 06): immutable shift record. Mirrors
  /// `public.icu_nursing_handover`.
  static const Table _icuNursingHandover = Table(
    LocalTables.icuNursingHandover,
    <Column>[
      Column.text('tenant_id'),
      Column.text('patient_id'),
      Column.text('icu_bed_id'),
      Column.text('outgoing_nurse'),
      Column.text('incoming_nurse'),
      Column.text('handover_time'),
      Column.text('summary'),
      Column.text('concerns'),
      Column.text('plan'),
      Column.text('alerts'),
      Column.text('created_at'),
    ],
    indexes: <Index>[
      Index('nursing_handover_patient', <IndexedColumn>[
        IndexedColumn('patient_id'),
        IndexedColumn('handover_time'),
      ]),
      Index('nursing_handover_bed', <IndexedColumn>[
        IndexedColumn('icu_bed_id'),
      ]),
    ],
  );

  /// Ventilator events (Module 06): append-only clinical events. Mirrors
  /// `public.ventilator_events`.
  static const Table _ventilatorEvents = Table(
    LocalTables.ventilatorEvents,
    <Column>[
      Column.text('tenant_id'),
      Column.text('patient_id'),
      Column.text('icu_bed_id'),
      Column.text('ventilator_id'),
      Column.text('event_type'),
      Column.text('mode'),
      Column.text('settings'),
      Column.text('recorded_by'),
      Column.text('recorded_at'),
      Column.text('created_at'),
    ],
    indexes: <Index>[
      Index('ventilator_event_patient', <IndexedColumn>[
        IndexedColumn('patient_id'),
        IndexedColumn('recorded_at'),
      ]),
      Index('ventilator_event_bed', <IndexedColumn>[
        IndexedColumn('icu_bed_id'),
      ]),
    ],
  );

  /// Visit bookings: the server arbitrates slots, the device holds the scope.
  static const Table _appointments = Table(
    LocalTables.appointments,
    <Column>[
      Column.text('tenant_id'),
      Column.text('facility_id'),
      Column.text('patient_id'),
      Column.text('provider_id'),
      Column.text('booked_by'),
      Column.text('encounter_id'),
      Column.text('appointment_code'),
      Column.text('visit_type'),
      Column.text('priority'),
      Column.text('status'),
      Column.text('reason'),
      Column.text('scheduled_start'),
      Column.text('scheduled_end'),
      Column.text('checked_in_at'),
      Column.text('started_at'),
      Column.text('completed_at'),
      Column.text('cancelled_at'),
      Column.text('cancel_reason'),
      Column.text('created_at'),
      Column.text('updated_at'),
    ],
    indexes: <Index>[
      Index('appointment_patient', <IndexedColumn>[
        IndexedColumn('patient_id'),
        IndexedColumn('scheduled_start'),
      ]),
      Index('appointment_provider', <IndexedColumn>[
        IndexedColumn('provider_id'),
        IndexedColumn('scheduled_start'),
      ]),
      Index('appointment_status', <IndexedColumn>[
        IndexedColumn('tenant_id'),
        IndexedColumn('status'),
      ]),
    ],
  );
}
