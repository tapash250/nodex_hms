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
import 'package:powersync/powersync.dart';

void main() {
  group('NodexLocalSchema', () {
    late Schema schema;

    setUp(() {
      schema = NodexLocalSchema.build();
    });

    test('passes PowerSync validation', () {
      expect(schema.validate, returnsNormally);
    });

    test(
      'declares every Phase 1 table plus Modules 05, 06, 07, 10, 11, 13, 16, '
      '17, 18, 19, 20, 21, 22, 23, 25, 26 and 31',
      () {
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
          LocalTables.clinicalEncounters,
          LocalTables.encounterAmendments,
          LocalTables.labOrders,
          LocalTables.labSpecimens,
          LocalTables.labResults,
          LocalTables.prescriptions,
          LocalTables.prescriptionItems,
          LocalTables.pharmacyDispenses,
          LocalTables.medicationAdministrations,
          LocalTables.appointments,
          LocalTables.beds,
          LocalTables.bedAssignments,
          LocalTables.invoices,
          LocalTables.invoiceLines,
          LocalTables.payments,
          LocalTables.refunds,
          LocalTables.stockItems,
          LocalTables.stockLocations,
          LocalTables.stockBatches,
          LocalTables.stockMovements,
          LocalTables.discharges,
          LocalTables.triageAssessments,
          LocalTables.erVisits,
          LocalTables.icuBeds,
          LocalTables.icuVitals,
          LocalTables.icuNursingHandover,
          LocalTables.ventilatorEvents,
          LocalTables.transfusionRequests,
          LocalTables.bloodUnits,
          LocalTables.transfusions,
          LocalTables.otBookings,
          LocalTables.otPreOpAssessments,
          LocalTables.otAnesthesiaRecords,
          LocalTables.otProcedureLogs,
          LocalTables.otPostOpRecords,
          LocalTables.imagingOrders,
          LocalTables.imagingStudies,
          LocalTables.imagingReports,
          LocalTables.physioSessions,
          LocalTables.physioExercisePlans,
          LocalTables.physioRecoveryNotes,
          LocalTables.dietAssessments,
          LocalTables.dietMealPlans,
          LocalTables.dietMealPlanDays,
          LocalTables.dietIntakeLogs,
          LocalTables.teleConsultations,
          LocalTables.teleVitalsOverlays,
          LocalTables.teleConsultationArchives,
          LocalTables.dischargeClearances,
          LocalTables.dischargeReconciliations,
          LocalTables.dischargeReconciliationItems,
          LocalTables.dischargeSettlements,
          LocalTables.dischargeAiSummaries,
          LocalTables.wardRooms,
          LocalTables.clinicalProblems,
          LocalTables.encounterScribeDrafts,
        });
      },
    );

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

    test('encounter tables mirror the PostgreSQL EMR schema', () {
      Table byName(String name) =>
          schema.tables.firstWhere((Table table) => table.name == name);

      expect(
        byName(LocalTables.clinicalEncounters).columns
            .map((Column c) => c.name)
            .toSet(),
        containsAll(<String>{
          'tenant_id',
          'patient_id',
          'attending_physician_id',
          'encounter_type',
          'status',
          'subjective_note',
          'objective_findings',
          'assessment',
          'plan_description',
          'diagnoses',
          'signed_at',
        }),
      );

      expect(
        byName(LocalTables.encounterAmendments).columns
            .map((Column c) => c.name)
            .toSet(),
        containsAll(<String>{
          'tenant_id',
          'encounter_id',
          'amendment_type',
          'reason',
          'field_changes',
          'amended_by',
        }),
      );
    });

    test('laboratory tables mirror the Module 17 state machine schema', () {
      Table byName(String name) =>
          schema.tables.firstWhere((Table table) => table.name == name);

      expect(
        byName(LocalTables.labOrders).columns.map((Column c) => c.name).toSet(),
        containsAll(<String>{
          'tenant_id',
          'patient_id',
          'order_code',
          'priority',
          'status',
          'tests',
        }),
      );
      expect(
        byName(LocalTables.labSpecimens).columns
            .map((Column c) => c.name)
            .toSet(),
        containsAll(<String>{
          'lab_order_id',
          'accession_barcode',
          'specimen_type',
          'status',
          'collected_at',
        }),
      );
      expect(
        byName(LocalTables.labResults).columns
            .map((Column c) => c.name)
            .toSet(),
        containsAll(<String>{
          'lab_order_id',
          'specimen_id',
          'analyte_code',
          'value_text',
          'value_numeric',
          'status',
          'verified_at',
          'correction_of',
          'correction_reason',
        }),
      );
    });

    test('prescription tables mirror the Module 25 state machine schema', () {
      Table byName(String name) =>
          schema.tables.firstWhere((Table table) => table.name == name);

      expect(
        byName(LocalTables.prescriptions).columns
            .map((Column c) => c.name)
            .toSet(),
        containsAll(<String>{
          'tenant_id',
          'patient_id',
          'prescription_code',
          'version',
          'priority',
          'status',
          'finalized_by',
          'finalized_at',
          'supersedes',
          'superseded_by',
          'closed_at',
          'closure_reason',
        }),
      );
      expect(
        byName(LocalTables.prescriptionItems).columns
            .map((Column c) => c.name)
            .toSet(),
        containsAll(<String>{
          'prescription_id',
          'line_number',
          'drug_code',
          'drug_name',
          'dosage_text',
          'quantity_prescribed',
          'status',
        }),
      );
      expect(
        byName(LocalTables.pharmacyDispenses).columns
            .map((Column c) => c.name)
            .toSet(),
        containsAll(<String>{
          'prescription_id',
          'item_id',
          'dispensed_by',
          'quantity_dispensed',
          'dispensed_at',
        }),
      );
      expect(
        byName(LocalTables.medicationAdministrations).columns
            .map((Column c) => c.name)
            .toSet(),
        containsAll(<String>{
          'patient_id',
          'prescription_id',
          'item_id',
          'administered_by',
          'administered_at',
          'dose_text',
        }),
      );
    });

    test('bed tables mirror the Module 11 census schema', () {
      Table byName(String name) =>
          schema.tables.firstWhere((Table table) => table.name == name);

      expect(
        byName(LocalTables.beds).columns.map((Column c) => c.name).toSet(),
        containsAll(<String>{
          'tenant_id',
          'ward_id',
          'bed_code',
          'bed_type',
          'status',
        }),
      );
      expect(
        byName(LocalTables.bedAssignments).columns
            .map((Column c) => c.name)
            .toSet(),
        containsAll(<String>{
          'tenant_id',
          'bed_id',
          'patient_id',
          'assigned_by',
          'status',
          'admitted_at',
          'released_at',
          'release_reason',
        }),
      );
    });

    test('discharge table mirrors the Module 23 record schema', () {
      Table byName(String name) =>
          schema.tables.firstWhere((Table table) => table.name == name);

      expect(
        byName(LocalTables.discharges).columns
            .map((Column c) => c.name)
            .toSet(),
        containsAll(<String>{
          'tenant_id',
          'patient_id',
          'encounter_id',
          'created_by',
          'discharge_code',
          'discharge_type',
          'status',
          'summary',
          'follow_up_plan',
          'finalized_by',
          'finalized_at',
        }),
      );
    });

    test('ER and triage tables mirror the Module 05 schema', () {
      Table byName(String name) =>
          schema.tables.firstWhere((Table table) => table.name == name);

      expect(
        byName(LocalTables.triageAssessments).columns
            .map((Column c) => c.name)
            .toSet(),
        containsAll(<String>{
          'tenant_id',
          'patient_id',
          'encounter_id',
          'assessed_by',
          'acuity',
          'chief_complaint',
          'vitals',
          'red_flags',
          'disposition',
          'escalated',
          'escalated_by',
          'escalated_at',
          'created_at',
          'updated_at',
        }),
      );
      expect(
        byName(LocalTables.erVisits).columns.map((Column c) => c.name).toSet(),
        containsAll(<String>{'tenant_id', 'patient_id', 'triage_id', 'status'}),
      );
    });

    test('ICU tables mirror the Module 06 schema', () {
      Table byName(String name) =>
          schema.tables.firstWhere((Table table) => table.name == name);

      expect(
        byName(LocalTables.icuBeds).columns.map((Column c) => c.name).toSet(),
        containsAll(<String>{
          'tenant_id',
          'bed_id',
          'ventilator_id',
          'status',
          'current_patient_id',
          'created_at',
          'updated_at',
        }),
      );
      expect(
        byName(LocalTables.icuVitals).columns.map((Column c) => c.name).toSet(),
        containsAll(<String>{
          'tenant_id',
          'patient_id',
          'icu_bed_id',
          'recorded_by',
          'recorded_at',
        }),
      );
      expect(
        byName(LocalTables.icuNursingHandover).columns
            .map((Column c) => c.name)
            .toSet(),
        containsAll(<String>{
          'tenant_id',
          'patient_id',
          'icu_bed_id',
          'outgoing_nurse',
          'incoming_nurse',
          'handover_time',
        }),
      );
      expect(
        byName(LocalTables.ventilatorEvents).columns
            .map((Column c) => c.name)
            .toSet(),
        containsAll(<String>{
          'tenant_id',
          'patient_id',
          'icu_bed_id',
          'ventilator_id',
          'event_type',
          'recorded_by',
          'recorded_at',
        }),
      );
    });

    test('blood bank tables mirror the Module 26 schema', () {
      Table byName(String name) =>
          schema.tables.firstWhere((Table table) => table.name == name);

      expect(
        byName(LocalTables.transfusionRequests).columns
            .map((Column c) => c.name)
            .toSet(),
        containsAll(<String>{
          'tenant_id',
          'patient_id',
          'requested_by',
          'requested_blood_group',
          'component',
          'units_requested',
          'urgency',
          'status',
          'crossmatch_result',
          'requested_at',
          'approved_by',
          'approved_at',
        }),
      );
      expect(
        byName(LocalTables.bloodUnits).columns
            .map((Column c) => c.name)
            .toSet(),
        containsAll(<String>{
          'tenant_id',
          'unit_number',
          'blood_group',
          'component',
          'volume_ml',
          'collected_at',
          'expires_at',
          'status',
          'location_id',
          'patient_id',
          'transfusion_request_id',
          'created_by',
        }),
      );
      expect(
        byName(LocalTables.transfusions).columns
            .map((Column c) => c.name)
            .toSet(),
        containsAll(<String>{
          'tenant_id',
          'transfusion_request_id',
          'blood_unit_id',
          'patient_id',
          'recorded_by',
          'started_at',
          'finished_at',
          'status',
          'volume_ml',
          'reaction_notes',
        }),
      );
    });

    test('operation theatre tables mirror the Module 19 schema', () {
      Table byName(String name) =>
          schema.tables.firstWhere((Table table) => table.name == name);

      expect(
        byName(LocalTables.otBookings).columns
            .map((Column c) => c.name)
            .toSet(),
        containsAll(<String>{
          'tenant_id',
          'patient_id',
          'theatre_room',
          'procedure_name',
          'scheduled_start',
          'scheduled_end',
          'surgeon_id',
          'status',
          'priority',
          'cancellation_reason',
        }),
      );
      expect(
        byName(LocalTables.otPreOpAssessments).columns
            .map((Column c) => c.name)
            .toSet(),
        containsAll(<String>{
          'tenant_id',
          'booking_id',
          'assessed_by',
          'fitness',
          'asa_class',
          'notes',
        }),
      );
      expect(
        byName(LocalTables.otAnesthesiaRecords).columns
            .map((Column c) => c.name)
            .toSet(),
        containsAll(<String>{
          'tenant_id',
          'booking_id',
          'anesthesia_type',
          'started_at',
          'ended_at',
        }),
      );
      expect(
        byName(LocalTables.otProcedureLogs).columns
            .map((Column c) => c.name)
            .toSet(),
        containsAll(<String>{
          'tenant_id',
          'booking_id',
          'procedure_name',
          'performed_by',
          'completed_at',
          'findings',
        }),
      );
      expect(
        byName(LocalTables.otPostOpRecords).columns
            .map((Column c) => c.name)
            .toSet(),
        containsAll(<String>{
          'tenant_id',
          'booking_id',
          'condition',
          'pain_score',
          'complications',
        }),
      );
    });

    test('radiology tables mirror the Module 18 schema', () {
      Table byName(String name) =>
          schema.tables.firstWhere((Table table) => table.name == name);

      expect(
        byName(LocalTables.imagingOrders).columns
            .map((Column c) => c.name)
            .toSet(),
        containsAll(<String>{
          'tenant_id',
          'patient_id',
          'ordered_by',
          'order_code',
          'modality',
          'body_region',
          'priority',
          'status',
          'cancelled_reason',
        }),
      );
      expect(
        byName(LocalTables.imagingStudies).columns
            .map((Column c) => c.name)
            .toSet(),
        containsAll(<String>{
          'tenant_id',
          'imaging_order_id',
          'study_uid',
          'modality',
          'performed_by',
          'performed_at',
        }),
      );
      expect(
        byName(LocalTables.imagingReports).columns
            .map((Column c) => c.name)
            .toSet(),
        containsAll(<String>{
          'tenant_id',
          'imaging_order_id',
          'study_id',
          'findings',
          'impression',
          'status',
          'verified_by',
        }),
      );
    });

    test('physiotherapy tables mirror the Module 20 schema', () {
      Table byName(String name) =>
          schema.tables.firstWhere((Table table) => table.name == name);

      expect(
        byName(LocalTables.physioSessions).columns
            .map((Column c) => c.name)
            .toSet(),
        containsAll(<String>{
          'tenant_id',
          'patient_id',
          'physiotherapist_id',
          'session_code',
          'session_type',
          'body_area',
          'status',
          'scheduled_at',
          'cancellation_reason',
          'equipment_used',
        }),
      );
      expect(
        byName(LocalTables.physioExercisePlans).columns
            .map((Column c) => c.name)
            .toSet(),
        containsAll(<String>{
          'tenant_id',
          'patient_id',
          'session_id',
          'prescribed_by',
          'exercise_name',
          'sets_count',
          'reps_count',
          'frequency_per_week',
          'duration_weeks',
          'status',
        }),
      );
      expect(
        byName(LocalTables.physioRecoveryNotes).columns
            .map((Column c) => c.name)
            .toSet(),
        containsAll(<String>{
          'tenant_id',
          'session_id',
          'recorded_by',
          'content',
          'pain_score',
          'recorded_at',
        }),
      );
    });

    test('nutrition tables mirror the Module 21 schema', () {
      Table byName(String name) =>
          schema.tables.firstWhere((Table table) => table.name == name);

      expect(
        byName(LocalTables.dietAssessments).columns
            .map((Column c) => c.name)
            .toSet(),
        containsAll(<String>{
          'tenant_id',
          'patient_id',
          'assessed_by',
          'assessment_type',
          'weight_kg',
          'height_cm',
          'nutrition_diagnosis',
          'restrictions',
          'status',
          'finalized_by',
        }),
      );
      expect(
        byName(LocalTables.dietMealPlans).columns
            .map((Column c) => c.name)
            .toSet(),
        containsAll(<String>{
          'tenant_id',
          'patient_id',
          'assessment_id',
          'name',
          'plan_source',
          'cycle_days',
          'status',
          'approved_by',
          'rejection_reason',
        }),
      );
      expect(
        byName(LocalTables.dietMealPlanDays).columns
            .map((Column c) => c.name)
            .toSet(),
        containsAll(<String>{
          'tenant_id',
          'meal_plan_id',
          'day_number',
          'breakfast',
          'lunch',
          'dinner',
          'snacks',
          'calories_kcal',
        }),
      );
      expect(
        byName(LocalTables.dietIntakeLogs).columns
            .map((Column c) => c.name)
            .toSet(),
        containsAll(<String>{
          'tenant_id',
          'patient_id',
          'meal_plan_day_id',
          'meal_slot',
          'portion_consumed_pct',
          'recorded_by',
          'recorded_at',
        }),
      );
    });

    test('telemedicine tables mirror the Module 22 schema', () {
      Table byName(String name) =>
          schema.tables.firstWhere((Table table) => table.name == name);

      expect(
        byName(LocalTables.teleConsultations).columns
            .map((Column c) => c.name)
            .toSet(),
        containsAll(<String>{
          'tenant_id',
          'patient_id',
          'clinician_id',
          'booked_by',
          'visit_code',
          'channel',
          'status',
          'scheduled_at',
          'waiting_at',
          'started_at',
          'completed_at',
          'cancellation_reason',
          'no_show_at',
        }),
      );
      expect(
        byName(LocalTables.teleVitalsOverlays).columns
            .map((Column c) => c.name)
            .toSet(),
        containsAll(<String>{
          'tenant_id',
          'consultation_id',
          'observed_by',
          'heart_rate_bpm',
          'spo2_pct',
          'temperature_c',
          'respiratory_rate',
          'observed_at',
        }),
      );
      expect(
        byName(LocalTables.teleConsultationArchives).columns
            .map((Column c) => c.name)
            .toSet(),
        containsAll(<String>{
          'tenant_id',
          'consultation_id',
          'archived_by',
          'duration_seconds',
          'recording_reference',
          'transcript_reference',
          'consent_recorded',
          'archived_at',
        }),
      );
    });

    test('the problem list mirrors the PostgreSQL schema', () {
      Table byName(String name) =>
          schema.tables.firstWhere((Table table) => table.name == name);

      expect(
        byName(LocalTables.clinicalProblems).columns
            .map((Column c) => c.name)
            .toSet(),
        containsAll(<String>{
          'tenant_id',
          'patient_id',
          'encounter_id',
          'problem_code',
          'description',
          'clinical_status',
          'onset_date',
          'resolved_at',
          'resolution_note',
          'recorded_by',
          'resolved_by',
        }),
      );
    });

    test('scribe drafts mirror the PostgreSQL schema', () {
      Table byName(String name) =>
          schema.tables.firstWhere((Table table) => table.name == name);

      expect(
        byName(LocalTables.encounterScribeDrafts).columns
            .map((Column c) => c.name)
            .toSet(),
        containsAll(<String>{
          'tenant_id',
          'encounter_id',
          'model_id',
          'transcript_text',
          'subjective_note',
          'objective_findings',
          'assessment',
          'plan_description',
          'confidence',
          'safety_decision',
          'status',
          'requested_by',
          'reviewed_by',
          'reviewed_at',
          'rejection_reason',
          'accepted_fields',
        }),
      );
    });

    test('ward rooms mirror the Module 24 floor layout schema', () {
      Table byName(String name) =>
          schema.tables.firstWhere((Table table) => table.name == name);

      expect(
        byName(LocalTables.wardRooms).columns.map((Column c) => c.name).toSet(),
        containsAll(<String>{
          'tenant_id',
          'facility_id',
          'ward_id',
          'room_code',
          'room_name',
          'room_type',
          'floor_label',
          'capacity',
          'grid_x',
          'grid_y',
          'grid_span_x',
          'grid_span_y',
          'status',
          'retirement_reason',
        }),
      );
    });

    test('discharge management tables mirror the Module 23 schema', () {
      Table byName(String name) =>
          schema.tables.firstWhere((Table table) => table.name == name);

      expect(
        byName(LocalTables.dischargeClearances).columns
            .map((Column c) => c.name)
            .toSet(),
        containsAll(<String>{
          'tenant_id',
          'discharge_id',
          'reviewed_by',
          'status',
          'outstanding_items',
          'cleared_by',
          'cleared_at',
        }),
      );
      expect(
        byName(LocalTables.dischargeReconciliations).columns
            .map((Column c) => c.name)
            .toSet(),
        containsAll(<String>{
          'tenant_id',
          'discharge_id',
          'status',
          'medications_reviewed',
          'discrepancies_found',
          'reviewed_by',
          'reviewed_at',
        }),
      );
      expect(
        byName(LocalTables.dischargeReconciliationItems).columns
            .map((Column c) => c.name)
            .toSet(),
        containsAll(<String>{
          'tenant_id',
          'reconciliation_id',
          'medication_name',
          'action',
          'discrepancy',
          'recorded_by',
          'recorded_at',
        }),
      );
      expect(
        byName(LocalTables.dischargeSettlements).columns
            .map((Column c) => c.name)
            .toSet(),
        containsAll(<String>{
          'tenant_id',
          'discharge_id',
          'invoice_id',
          'amount_minor',
          'settled_by',
          'settled_at',
        }),
      );
      expect(
        byName(LocalTables.dischargeAiSummaries).columns
            .map((Column c) => c.name)
            .toSet(),
        containsAll(<String>{
          'tenant_id',
          'discharge_id',
          'model_id',
          'summary_text',
          'status',
          'safety_decision',
          'requested_by',
          'reviewed_by',
          'rejection_reason',
        }),
      );
    });

    test('appointment table mirrors the Module 07 schedule schema', () {
      Table byName(String name) =>
          schema.tables.firstWhere((Table table) => table.name == name);

      expect(
        byName(LocalTables.appointments).columns
            .map((Column c) => c.name)
            .toSet(),
        containsAll(<String>{
          'tenant_id',
          'patient_id',
          'provider_id',
          'booked_by',
          'encounter_id',
          'appointment_code',
          'visit_type',
          'status',
          'scheduled_start',
          'scheduled_end',
          'cancel_reason',
        }),
      );
    });

    test('billing tables mirror the Module 31 schema', () {
      Table byName(String name) =>
          schema.tables.firstWhere((Table table) => table.name == name);

      expect(
        byName(LocalTables.invoices).columns.map((Column c) => c.name).toSet(),
        containsAll(<String>{
          'tenant_id',
          'patient_id',
          'encounter_id',
          'created_by',
          'invoice_code',
          'status',
          'currency',
          'total_minor',
          'settled_minor',
          'notes',
          'issued_at',
          'settled_at',
          'closed_at',
          'closure_reason',
        }),
      );
      expect(
        byName(LocalTables.invoiceLines).columns
            .map((Column c) => c.name)
            .toSet(),
        containsAll(<String>{
          'tenant_id',
          'invoice_id',
          'line_number',
          'description',
          'quantity',
          'unit_price_minor',
          'line_total_minor',
        }),
      );
      expect(
        byName(LocalTables.payments).columns.map((Column c) => c.name).toSet(),
        containsAll(<String>{
          'tenant_id',
          'invoice_id',
          'recorded_by',
          'amount_minor',
          'amount_received_minor',
          'method',
          'reference',
          'note',
          'paid_at',
        }),
      );
      expect(
        byName(LocalTables.refunds).columns.map((Column c) => c.name).toSet(),
        containsAll(<String>{
          'tenant_id',
          'invoice_id',
          'payment_id',
          'recorded_by',
          'amount_minor',
          'reason',
          'refunded_at',
        }),
      );
    });

    test('inventory tables mirror the Module 13 schema', () {
      Table byName(String name) =>
          schema.tables.firstWhere((Table table) => table.name == name);

      expect(
        byName(LocalTables.stockItems).columns
            .map((Column c) => c.name)
            .toSet(),
        containsAll(<String>{
          'tenant_id',
          'item_code',
          'name',
          'description',
          'category',
          'unit',
          'status',
          'reorder_level',
          'standard_cost_minor',
          'requires_batch',
          'requires_expiry',
          'created_by',
        }),
      );
      expect(
        byName(LocalTables.stockLocations).columns
            .map((Column c) => c.name)
            .toSet(),
        containsAll(<String>{
          'tenant_id',
          'facility_id',
          'ward_id',
          'location_code',
          'name',
          'location_type',
          'status',
        }),
      );
      expect(
        byName(LocalTables.stockBatches).columns
            .map((Column c) => c.name)
            .toSet(),
        containsAll(<String>{
          'tenant_id',
          'item_id',
          'batch_number',
          'expiry_date',
          'manufactured_date',
          'quantity_minor',
          'cost_per_unit_minor',
          'status',
          'received_at',
        }),
      );
      expect(
        byName(LocalTables.stockMovements).columns
            .map((Column c) => c.name)
            .toSet(),
        containsAll(<String>{
          'tenant_id',
          'item_id',
          'batch_id',
          'from_location_id',
          'to_location_id',
          'movement_type',
          'quantity_minor',
          'unit_cost_minor',
          'reference_type',
          'reference_id',
          'reason',
          'recorded_by',
          'recorded_at',
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
          NodexPermissions.otFinalize,
          NodexPermissions.imagingReportVerify,
          NodexPermissions.dietPlanApprove,
          NodexPermissions.teleArchiveWrite,
          NodexPermissions.dischargeSummaryReview,
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
          NodexPermissions.transfusionAdminister,
          NodexPermissions.otFinalize,
          NodexPermissions.imagingReportVerify,
          NodexPermissions.dietPlanApprove,
          NodexPermissions.teleArchiveWrite,
          NodexPermissions.dischargeSummaryReview,
          NodexPermissions.billingSettle,
        ]),
      );
    });

    test('bedside high-risk actions remain available offline', () {
      // Medication administration, dispensing, triage escalation and
      // transfusion administration happen at the bedside, where connectivity
      // cannot be assumed. They are high-risk but not online-only; the audit
      // trail records that they occurred offline.
      for (final String permission in <String>[
        NodexPermissions.medicationAdminister,
        NodexPermissions.pharmacyDispense,
        NodexPermissions.triageEscalate,
        NodexPermissions.transfusionAdminister,
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

    test('a bed manager sees the ward census and appointments with read', () {
      final AuthorizationPolicy manager = policyWith(<String>{
        NodexPermissions.bedAssign,
        NodexPermissions.appointmentRead,
      });

      final List<NavigationDestinationSpec> visible =
          NodexDestinations.visibleTo(manager);

      expect(visible, contains(NodexDestinations.wards));
      expect(visible, contains(NodexDestinations.appointments));
      expect(visible, isNot(contains(NodexDestinations.audit)));
    });
  });
}
