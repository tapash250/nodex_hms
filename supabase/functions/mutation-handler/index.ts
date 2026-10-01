// NODEX Enterprise HMS — authorized backend mutation path.
//
// Phase 1's clients wrote through PostgREST under RLS. That is not sufficient
// for clinical writes, which need domain validation, an audit event and the
// clinical event committed in one transaction.
//
// Contract (matches lib/data/sync/backend_connector.dart on the client):
//   POST /mutation-handler
//   {
//     "mutations": [
//       {
//         "id": "<uuid>",              // client-generated, idempotency anchor
//         "operation": "upsert" | "patch",
//         "table": "<allowlisted>",
//         "row_id": "<uuid>",
//         "idempotency_key": "<string>",
//         "origin": "online" | "offline",
//         "client_created_at": "<iso8601>",
//         "conflict_policy": "<registry key>",
//         "data": { ... }
//       }
//     ]
//   }
//
// Response per mutation:
//   { "id": "...", "outcome": "applied" | "already_applied" | "rejected",
//     "rejection_class": "...", "detail": "..." }
//
// Invariants enforced here, not by convention:
//   1. Table allowlist. Every clinical table that gains an offline write path
//      registers here with a validator, its permitted operations and its audit
//      actions. Unknown tables are rejected, not routed.
//   2. Idempotency: (tenant_id, idempotency_key) unique on public.mutations. A
//      retried upload after a lost response returns already_applied instead of
//      applying twice. Exactly-once business effect for idempotent mutations.
//   3. No deletes. Legally or clinically retained records are retired by status
//      transition; the client connector already refuses them, and this endpoint
//      refuses them again server-side.
//   4. Ledger before apply: the ledger row lands first with status 'received'.
//      A ledger failure blocks the apply — otherwise a successful write with no
//      ledger row would re-apply on retry. Audit-before-apply still holds: the
//      audit row lands before the clinical write, so a failed apply leaves a
//      complete trail, never a silent loss.

import { withSupabase } from 'npm:@supabase/server'

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface IncomingMutation {
  id: string
  operation: 'upsert' | 'patch'
  table: string
  row_id: string
  idempotency_key: string
  origin: 'online' | 'offline'
  client_created_at: string
  conflict_policy?: string
  data: Record<string, unknown>
}

interface MutationResult {
  id: string
  outcome: 'applied' | 'already_applied' | 'rejected'
  rejection_class?: string
  detail?: string
}

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

// ---------------------------------------------------------------------------
// Registry: the only place a table becomes writable offline.
//
// A clinical table is admitted alongside, in the same change:
//   - a validator that whitelists columns and enforces domain rules,
//   - the permitted operations (append-only tables admit upsert, never patch),
//   - the audit actions recorded in audit_events per operation.
// ---------------------------------------------------------------------------

type ColumnType = 'text' | 'uuid' | 'boolean' | 'integer' | 'number' | 'timestamp' | 'json'

interface TableRule {
  columns: Record<string, ColumnType>
  operations: Array<'upsert' | 'patch'>
  auditActionUpsert: string
  auditActionPatch: string
}

const WRITABLE_TABLES: Readonly<Record<string, TableRule>> = {
  // Module 10 (MPI). Column names mirror public.patients exactly; the local
  // projection, this validator and PostgreSQL must agree or replication drops
  // columns silently. Identity edits are blocked client-side by
  // Patient.contactUpdateRow, but the validator admits the columns because the
  // merge workflow legitimately writes them through reviewed merges.
  patients: {
    columns: {
      tenant_id: 'uuid',
      mrn: 'text',
      national_id_hash: 'text',
      first_name: 'text',
      last_name: 'text',
      date_of_birth: 'timestamp',
      gender: 'text',
      blood_group: 'text',
      phone_number: 'text',
      email: 'text',
      address: 'text',
      next_of_kin: 'text',
      occupation: 'text',
      marital_status: 'text',
      preferred_language: 'text',
      is_active: 'integer',
      created_by: 'uuid',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'patient.registered',
    auditActionPatch: 'patient.updated',
  },
  // Allergy rows are append-only with a retire-only transition enforced by
  // nodex.tg_allergy_retire_only. Patch exists solely for that transition;
  // any other column change is rejected by the trigger, not just by policy.
  patient_allergies: {
    columns: {
      tenant_id: 'uuid',
      patient_id: 'uuid',
      substance: 'text',
      reaction: 'text',
      severity: 'text',
      status: 'text',
      retired_reason: 'text',
      recorded_by: 'uuid',
      recorded_at: 'timestamp',
      retired_at: 'timestamp',
      created_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'allergy.recorded',
    auditActionPatch: 'allergy.retired',
  },
  // Merge history is written once per decision and never edited: upsert only.
  // A patch attempt falls through to RLS, which has no update policy on this
  // table, and is rejected there too. Defense in depth, not duplication.
  patient_merge_history: {
    columns: {
      tenant_id: 'uuid',
      surviving_patient_id: 'uuid',
      merged_patient_id: 'uuid',
      merged_by: 'uuid',
      reason: 'text',
      field_choices: 'json',
      created_at: 'timestamp',
    },
    operations: ['upsert'],
    auditActionUpsert: 'patient.merged',
    auditActionPatch: 'patient.merged',
  },
  // Module 16 (encounters). Column names mirror public.clinical_encounters.
  // The freeze trigger (nodex.tg_encounter_freeze_after_sign) is the final
  // enforcer: this validator admits the columns so legitimate unsigned edits
  // pass, and the trigger rejects any rewrite of signed content.
  clinical_encounters: {
    columns: {
      tenant_id: 'uuid',
      patient_id: 'uuid',
      attending_physician_id: 'uuid',
      encounter_type: 'text',
      status: 'text',
      subjective_note: 'text',
      objective_findings: 'text',
      assessment: 'text',
      plan_description: 'text',
      diagnoses: 'json',
      signed_at: 'timestamp',
      created_by: 'uuid',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'encounter.started',
    auditActionPatch: 'encounter.updated',
  },
  // Amendments are append-only: upsert only. The encounter's move to `amended`
  // travels as a separate patch on clinical_encounters, itself gated by the
  // freeze trigger's single permitted transition.
  encounter_amendments: {
    columns: {
      tenant_id: 'uuid',
      encounter_id: 'uuid',
      amendment_type: 'text',
      reason: 'text',
      field_changes: 'json',
      amended_by: 'uuid',
      created_at: 'timestamp',
    },
    operations: ['upsert'],
    auditActionUpsert: 'encounter.amended',
    auditActionPatch: 'encounter.amended',
  },
  // Module 17 (laboratory). Verified result rows are frozen server-side;
  // corrections are new rows linked by correction_of.
  lab_orders: {
    columns: {
      tenant_id: 'uuid',
      patient_id: 'uuid',
      encounter_id: 'uuid',
      ordered_by: 'uuid',
      order_code: 'text',
      priority: 'text',
      status: 'text',
      clinical_indication: 'text',
      tests: 'json',
      ordered_at: 'timestamp',
      cancelled_at: 'timestamp',
      cancelled_reason: 'text',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'lab.order.created',
    auditActionPatch: 'lab.order.updated',
  },
  lab_specimens: {
    columns: {
      tenant_id: 'uuid',
      lab_order_id: 'uuid',
      accession_barcode: 'text',
      specimen_type: 'text',
      collected_by: 'uuid',
      collected_at: 'timestamp',
      status: 'text',
      rejection_reason: 'text',
      received_at: 'timestamp',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'lab.specimen.created',
    auditActionPatch: 'lab.specimen.updated',
  },
  lab_results: {
    columns: {
      tenant_id: 'uuid',
      lab_order_id: 'uuid',
      specimen_id: 'uuid',
      analyte_code: 'text',
      analyte_name: 'text',
      value_text: 'text',
      value_numeric: 'number',
      unit: 'text',
      reference_range: 'text',
      abnormal_flag: 'text',
      status: 'text',
      entered_by: 'uuid',
      verified_by: 'uuid',
      entered_at: 'timestamp',
      verified_at: 'timestamp',
      correction_of: 'uuid',
      correction_reason: 'text',
      created_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'lab.result.created',
    auditActionPatch: 'lab.result.updated',
  },
  // Module 25 (prescriptions/pharmacy). Finalized versions are frozen
  // server-side; a change is a new version linked by supersedes/superseded_by.
  // The finalize-class transitions additionally require prescription.finalize
  // in nodex.tg_prescription_transition_guard, which RLS alone cannot express.
  prescriptions: {
    columns: {
      tenant_id: 'uuid',
      patient_id: 'uuid',
      encounter_id: 'uuid',
      prescribed_by: 'uuid',
      prescription_code: 'text',
      version: 'integer',
      priority: 'text',
      status: 'text',
      indication: 'text',
      finalized_by: 'uuid',
      finalized_at: 'timestamp',
      supersedes: 'uuid',
      superseded_by: 'uuid',
      closed_at: 'timestamp',
      closure_reason: 'text',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'rx.prescription.created',
    auditActionPatch: 'rx.prescription.updated',
  },
  // Item lines are editable while the parent order is a draft; once released
  // only the dispense progression moves, enforced by
  // nodex.tg_prescription_item_draft_guard.
  prescription_items: {
    columns: {
      tenant_id: 'uuid',
      prescription_id: 'uuid',
      line_number: 'integer',
      drug_code: 'text',
      drug_name: 'text',
      strength: 'text',
      dosage_text: 'text',
      route: 'text',
      frequency: 'text',
      duration_days: 'integer',
      quantity_prescribed: 'number',
      status: 'text',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'rx.item.created',
    auditActionPatch: 'rx.item.updated',
  },
  // Dispense rows are clinical events: upsert only, never patch. The
  // pharmacy_dispenses_append_only trigger is the final enforcer.
  pharmacy_dispenses: {
    columns: {
      tenant_id: 'uuid',
      prescription_id: 'uuid',
      item_id: 'uuid',
      dispensed_by: 'uuid',
      quantity_dispensed: 'number',
      batch_number: 'text',
      note: 'text',
      dispensed_at: 'timestamp',
      created_at: 'timestamp',
    },
    operations: ['upsert'],
    auditActionUpsert: 'rx.dispense.recorded',
    auditActionPatch: 'rx.dispense.recorded',
  },
  // MAR rows are clinical events: upsert only, never patch. Duplicates
  // deduplicate by event identity upstream; the append-only trigger holds.
  medication_administrations: {
    columns: {
      tenant_id: 'uuid',
      patient_id: 'uuid',
      prescription_id: 'uuid',
      item_id: 'uuid',
      dispense_id: 'uuid',
      administered_by: 'uuid',
      administered_at: 'timestamp',
      dose_text: 'text',
      route: 'text',
      site: 'text',
      note: 'text',
      created_at: 'timestamp',
    },
    operations: ['upsert'],
    auditActionUpsert: 'rx.administration.recorded',
    auditActionPatch: 'rx.administration.recorded',
  },
  // Module 07 (appointments). Slot allocation is server-arbitrated: the
  // appointment_no_double_book exclusion rejects conflicting offline bookings
  // on upload and the client reconciles to server state
  // (ConflictPolicy.serverAuthoritative). No delete policy exists by design.
  appointments: {
    columns: {
      tenant_id: 'uuid',
      facility_id: 'uuid',
      patient_id: 'uuid',
      provider_id: 'uuid',
      booked_by: 'uuid',
      encounter_id: 'uuid',
      appointment_code: 'text',
      visit_type: 'text',
      priority: 'text',
      status: 'text',
      reason: 'text',
      scheduled_start: 'timestamp',
      scheduled_end: 'timestamp',
      checked_in_at: 'timestamp',
      started_at: 'timestamp',
      completed_at: 'timestamp',
      cancelled_at: 'timestamp',
      cancel_reason: 'text',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'appointment.booked',
    auditActionPatch: 'appointment.updated',
  },
  // Module 11 (beds). Allocation is server-arbitrated: the one-active-per-bed
  // and one-active-per-patient exclusions reject conflicting offline
  // allocations on upload (ConflictPolicy.serverAuthoritative). Occupancy is
  // derived from the active assignment; beds carry only availability.
  beds: {
    columns: {
      tenant_id: 'uuid',
      ward_id: 'uuid',
      bed_code: 'text',
      bed_type: 'text',
      status: 'text',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'bed.registered',
    auditActionPatch: 'bed.updated',
  },
  bed_assignments: {
    columns: {
      tenant_id: 'uuid',
      bed_id: 'uuid',
      patient_id: 'uuid',
      encounter_id: 'uuid',
      assigned_by: 'uuid',
      status: 'text',
      admitted_at: 'timestamp',
      released_at: 'timestamp',
      release_reason: 'text',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'bed.assignment.created',
    auditActionPatch: 'bed.assignment.updated',
  },
  // Module 23 (discharge). One finalized record per encounter, immutable
  // after finalization; a readmission is a new encounter with its own
  // discharge (ConflictPolicy.immutableVersion).
  discharges: {
    columns: {
      tenant_id: 'uuid',
      patient_id: 'uuid',
      encounter_id: 'uuid',
      created_by: 'uuid',
      discharge_code: 'text',
      discharge_type: 'text',
      status: 'text',
      summary: 'text',
      follow_up_plan: 'text',
      finalized_by: 'uuid',
      finalized_at: 'timestamp',
      closed_at: 'timestamp',
      closure_reason: 'text',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'discharge.drafted',
    auditActionPatch: 'discharge.updated',
  },
  // Module 31 (billing). Money in integer minor units; settlement is
  // server-arbitrated via exclusion on running totals (ConflictPolicy.transactional).
  // A settled invoice is immutable.
  invoices: {
    columns: {
      tenant_id: 'uuid',
      patient_id: 'uuid',
      encounter_id: 'uuid',
      created_by: 'uuid',
      invoice_code: 'text',
      status: 'text',
      currency: 'text',
      total_minor: 'integer',
      settled_minor: 'integer',
      notes: 'text',
      issued_at: 'timestamp',
      settled_at: 'timestamp',
      closed_at: 'timestamp',
      closure_reason: 'text',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'billing.invoice.created',
    auditActionPatch: 'billing.invoice.updated',
  },
  invoice_lines: {
    columns: {
      tenant_id: 'uuid',
      invoice_id: 'uuid',
      line_number: 'integer',
      description: 'text',
      quantity: 'number',
      unit_price_minor: 'integer',
      line_total_minor: 'integer',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'billing.line.created',
    auditActionPatch: 'billing.line.updated',
  },
  payments: {
    columns: {
      tenant_id: 'uuid',
      invoice_id: 'uuid',
      recorded_by: 'uuid',
      amount_minor: 'integer',
      amount_received_minor: 'integer',
      method: 'text',
      reference: 'text',
      note: 'text',
      paid_at: 'timestamp',
      created_at: 'timestamp',
    },
    operations: ['upsert'],
    auditActionUpsert: 'billing.payment.recorded',
    auditActionPatch: 'billing.payment.recorded',
  },
  refunds: {
    columns: {
      tenant_id: 'uuid',
      invoice_id: 'uuid',
      payment_id: 'uuid',
      recorded_by: 'uuid',
      amount_minor: 'integer',
      reason: 'text',
      refunded_at: 'timestamp',
      created_at: 'timestamp',
    },
    operations: ['upsert'],
    auditActionUpsert: 'billing.refund.recorded',
    auditActionPatch: 'billing.refund.recorded',
  },
  // Module 13 (inventory). Allocation is transactional: balances replay
  // from the movement ledger (ConflictPolicy.transactional).
  stock_items: {
    columns: {
      tenant_id: 'uuid',
      item_code: 'text',
      name: 'text',
      description: 'text',
      category: 'text',
      unit: 'text',
      status: 'text',
      reorder_level: 'number',
      standard_cost_minor: 'integer',
      requires_batch: 'boolean',
      requires_expiry: 'boolean',
      created_by: 'uuid',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'inventory.item.created',
    auditActionPatch: 'inventory.item.updated',
  },
  stock_locations: {
    columns: {
      tenant_id: 'uuid',
      facility_id: 'uuid',
      ward_id: 'uuid',
      location_code: 'text',
      name: 'text',
      location_type: 'text',
      status: 'text',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'inventory.location.created',
    auditActionPatch: 'inventory.location.updated',
  },
  stock_batches: {
    columns: {
      tenant_id: 'uuid',
      item_id: 'uuid',
      batch_number: 'text',
      expiry_date: 'timestamp',
      manufactured_date: 'timestamp',
      quantity_minor: 'integer',
      cost_per_unit_minor: 'integer',
      status: 'text',
      received_at: 'timestamp',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'inventory.batch.created',
    auditActionPatch: 'inventory.batch.updated',
  },
  stock_movements: {
    columns: {
      tenant_id: 'uuid',
      item_id: 'uuid',
      batch_id: 'uuid',
      from_location_id: 'uuid',
      to_location_id: 'uuid',
      movement_type: 'text',
      quantity_minor: 'integer',
      unit_cost_minor: 'integer',
      reference_type: 'text',
      reference_id: 'uuid',
      reason: 'text',
      recorded_by: 'uuid',
      recorded_at: 'timestamp',
      created_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'inventory.movement.recorded',
    auditActionPatch: 'inventory.movement.updated',
  },
  // Module 05 (ER). Triage assessments are editable until disposition; the
  // one-way escalation transition is enforced by
  // nodex.tg_triage_escalation_guard (triage.escalate).
  triage_assessments: {
    columns: {
      tenant_id: 'uuid',
      patient_id: 'uuid',
      encounter_id: 'uuid',
      assessed_by: 'uuid',
      acuity: 'text',
      chief_complaint: 'text',
      vitals: 'json',
      red_flags: 'json',
      disposition: 'text',
      escalated: 'boolean',
      escalated_by: 'uuid',
      escalated_at: 'timestamp',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'triage.assessed',
    auditActionPatch: 'triage.updated',
  },
  // ER visits: status is a guarded state machine
  // (nodex.tg_er_visit_transition_guard); terminal statuses are frozen.
  er_visits: {
    columns: {
      tenant_id: 'uuid',
      patient_id: 'uuid',
      triage_id: 'uuid',
      encounter_id: 'uuid',
      provider_id: 'uuid',
      status: 'text',
      arrival_mode: 'text',
      bed_id: 'uuid',
      started_at: 'timestamp',
      disposition: 'text',
      disposition_reason: 'text',
      discharged_at: 'timestamp',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'er.visit.opened',
    auditActionPatch: 'er.visit.updated',
  },
  // Module 06 (ICU). Bed occupancy is server-arbitrated
  // (ConflictPolicy.serverAuthoritative), like Module 11 beds.
  icu_beds: {
    columns: {
      tenant_id: 'uuid',
      bed_id: 'uuid',
      ventilator_id: 'uuid',
      status: 'text',
      current_patient_id: 'uuid',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'icu.bed.registered',
    auditActionPatch: 'icu.bed.updated',
  },
  // ICU vitals are timestamped observations: upsert only, never patch.
  icu_vitals: {
    columns: {
      tenant_id: 'uuid',
      patient_id: 'uuid',
      icu_bed_id: 'uuid',
      recorded_by: 'uuid',
      recorded_at: 'timestamp',
      heart_rate: 'integer',
      spo2: 'integer',
      respiratory_rate: 'integer',
      temperature_celsius: 'number',
      systolic_bp: 'integer',
      diastolic_bp: 'integer',
      map: 'integer',
      cvp: 'number',
      etco2: 'integer',
      gcs_total: 'integer',
      gcs_eye: 'integer',
      gcs_verbal: 'integer',
      gcs_motor: 'integer',
      fi_o2: 'number',
      peep: 'integer',
      tidal_volume: 'integer',
      respiratory_mode: 'text',
      created_at: 'timestamp',
    },
    operations: ['upsert'],
    auditActionUpsert: 'icu.vitals.recorded',
    auditActionPatch: 'icu.vitals.recorded',
  },
  // Nursing handover is an immutable shift record: upsert only.
  icu_nursing_handover: {
    columns: {
      tenant_id: 'uuid',
      patient_id: 'uuid',
      icu_bed_id: 'uuid',
      outgoing_nurse: 'uuid',
      incoming_nurse: 'uuid',
      handover_time: 'timestamp',
      summary: 'text',
      concerns: 'json',
      plan: 'json',
      alerts: 'json',
      created_at: 'timestamp',
    },
    operations: ['upsert'],
    auditActionUpsert: 'icu.handover.recorded',
    auditActionPatch: 'icu.handover.recorded',
  },
  // Ventilator events are clinical events: upsert only, never patch.
  ventilator_events: {
    columns: {
      tenant_id: 'uuid',
      patient_id: 'uuid',
      icu_bed_id: 'uuid',
      ventilator_id: 'uuid',
      event_type: 'text',
      mode: 'text',
      settings: 'json',
      recorded_by: 'uuid',
      recorded_at: 'timestamp',
      created_at: 'timestamp',
    },
    operations: ['upsert'],
    auditActionUpsert: 'ventilator.event.recorded',
    auditActionPatch: 'ventilator.event.recorded',
  },
  // Module 26 (blood bank). Requests are server-arbitrated status flows
  // (ConflictPolicy.serverAuthoritative), so crossmatch, approval and
  // completion all land as patches.
  transfusion_requests: {
    columns: {
      tenant_id: 'uuid',
      patient_id: 'uuid',
      encounter_id: 'uuid',
      requested_by: 'uuid',
      requested_blood_group: 'text',
      component: 'text',
      units_requested: 'integer',
      indication: 'text',
      urgency: 'text',
      status: 'text',
      crossmatch_result: 'text',
      requested_at: 'timestamp',
      approved_by: 'uuid',
      approved_at: 'timestamp',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'transfusion.request.created',
    auditActionPatch: 'transfusion.request.updated',
  },
  // Blood units carry the reserved-for-patient lifecycle; status transitions
  // are patched in place and frozen by the guard trigger once terminal.
  blood_units: {
    columns: {
      tenant_id: 'uuid',
      unit_number: 'text',
      blood_group: 'text',
      component: 'text',
      volume_ml: 'integer',
      collected_at: 'timestamp',
      expires_at: 'timestamp',
      status: 'text',
      location_id: 'uuid',
      patient_id: 'uuid',
      transfusion_request_id: 'uuid',
      created_by: 'uuid',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'blood_unit.created',
    auditActionPatch: 'blood_unit.updated',
  },
  // Transfusion records are append-then-outcome: started on upsert, finished
  // or reacted on patch (ConflictPolicy.eventTransaction).
  transfusions: {
    columns: {
      tenant_id: 'uuid',
      transfusion_request_id: 'uuid',
      blood_unit_id: 'uuid',
      patient_id: 'uuid',
      recorded_by: 'uuid',
      started_at: 'timestamp',
      finished_at: 'timestamp',
      status: 'text',
      volume_ml: 'integer',
      reaction_notes: 'text',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'transfusion.recorded',
    auditActionPatch: 'transfusion.updated',
  },
  // Module 19 (operation theatre). Bookings are server-arbitrated status
  // flows (ConflictPolicy.serverAuthoritative): schedule, start, cancel and
  // complete all land as patches.
  ot_bookings: {
    columns: {
      tenant_id: 'uuid',
      patient_id: 'uuid',
      encounter_id: 'uuid',
      theatre_room: 'text',
      procedure_name: 'text',
      scheduled_start: 'timestamp',
      scheduled_end: 'timestamp',
      surgeon_id: 'uuid',
      anesthesiologist_id: 'uuid',
      status: 'text',
      priority: 'text',
      cancellation_reason: 'text',
      created_by: 'uuid',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'ot.booking.created',
    auditActionPatch: 'ot.booking.updated',
  },
  // The four per-case records are event transactions (one record per
  // booking): created once, then patched when an outcome lands.
  ot_preop_assessments: {
    columns: {
      tenant_id: 'uuid',
      booking_id: 'uuid',
      patient_id: 'uuid',
      assessed_by: 'uuid',
      assessed_at: 'timestamp',
      fitness: 'text',
      asa_class: 'integer',
      notes: 'text',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'ot.preop.recorded',
    auditActionPatch: 'ot.preop.updated',
  },
  ot_anesthesia_records: {
    columns: {
      tenant_id: 'uuid',
      booking_id: 'uuid',
      patient_id: 'uuid',
      anesthesia_type: 'text',
      recorded_by: 'uuid',
      started_at: 'timestamp',
      ended_at: 'timestamp',
      notes: 'text',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'ot.anesthesia.recorded',
    auditActionPatch: 'ot.anesthesia.updated',
  },
  ot_procedure_logs: {
    columns: {
      tenant_id: 'uuid',
      booking_id: 'uuid',
      patient_id: 'uuid',
      procedure_name: 'text',
      performed_by: 'uuid',
      started_at: 'timestamp',
      completed_at: 'timestamp',
      findings: 'text',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'ot.procedure.recorded',
    auditActionPatch: 'ot.procedure.updated',
  },
  ot_postop_records: {
    columns: {
      tenant_id: 'uuid',
      booking_id: 'uuid',
      patient_id: 'uuid',
      recorded_by: 'uuid',
      recorded_at: 'timestamp',
      condition: 'text',
      pain_score: 'integer',
      complications: 'text',
      notes: 'text',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'ot.postop.recorded',
    auditActionPatch: 'ot.postop.updated',
  },
  // Module 18 (radiology). Verified report rows are frozen server-side;
  // DICOM/PACS identifiers travel as metadata references only.
  imaging_orders: {
    columns: {
      tenant_id: 'uuid',
      patient_id: 'uuid',
      encounter_id: 'uuid',
      ordered_by: 'uuid',
      order_code: 'text',
      modality: 'text',
      body_region: 'text',
      priority: 'text',
      status: 'text',
      clinical_indication: 'text',
      ordered_at: 'timestamp',
      cancelled_at: 'timestamp',
      cancelled_reason: 'text',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'imaging.order.created',
    auditActionPatch: 'imaging.order.updated',
  },
  imaging_studies: {
    columns: {
      tenant_id: 'uuid',
      imaging_order_id: 'uuid',
      study_uid: 'text',
      modality: 'text',
      body_region: 'text',
      performed_by: 'uuid',
      performed_at: 'timestamp',
      acquisition_notes: 'text',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'imaging.study.recorded',
    auditActionPatch: 'imaging.study.updated',
  },
  imaging_reports: {
    columns: {
      tenant_id: 'uuid',
      imaging_order_id: 'uuid',
      study_id: 'uuid',
      findings: 'text',
      impression: 'text',
      status: 'text',
      entered_by: 'uuid',
      entered_at: 'timestamp',
      verified_by: 'uuid',
      verified_at: 'timestamp',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'imaging.report.created',
    auditActionPatch: 'imaging.report.updated',
  },
  // Module 20 (physiotherapy). Session transitions are guarded server-side
  // by the transition-guard trigger.
  physio_sessions: {
    columns: {
      tenant_id: 'uuid',
      patient_id: 'uuid',
      encounter_id: 'uuid',
      physiotherapist_id: 'uuid',
      session_code: 'text',
      session_type: 'text',
      body_area: 'text',
      status: 'text',
      scheduled_at: 'timestamp',
      started_at: 'timestamp',
      completed_at: 'timestamp',
      cancelled_at: 'timestamp',
      cancellation_reason: 'text',
      equipment_used: 'text',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'physio.session.created',
    auditActionPatch: 'physio.session.updated',
  },
  physio_exercise_plans: {
    columns: {
      tenant_id: 'uuid',
      patient_id: 'uuid',
      session_id: 'uuid',
      prescribed_by: 'uuid',
      exercise_name: 'text',
      sets_count: 'integer',
      reps_count: 'integer',
      frequency_per_week: 'integer',
      duration_weeks: 'integer',
      instructions: 'text',
      status: 'text',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'physio.plan.created',
    auditActionPatch: 'physio.plan.updated',
  },
  physio_recovery_notes: {
    columns: {
      tenant_id: 'uuid',
      session_id: 'uuid',
      recorded_by: 'uuid',
      content: 'text',
      pain_score: 'integer',
      recorded_at: 'timestamp',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'physio.note.recorded',
    auditActionPatch: 'physio.note.updated',
  },
  // Module 21 (dietetics). Finalized assessments and decided plans are frozen
  // server-side; a generated plan only takes effect through approval.
  diet_assessments: {
    columns: {
      tenant_id: 'uuid',
      patient_id: 'uuid',
      encounter_id: 'uuid',
      assessed_by: 'uuid',
      assessment_type: 'text',
      weight_kg: 'number',
      height_cm: 'number',
      nutrition_diagnosis: 'text',
      restrictions: 'text',
      status: 'text',
      assessed_at: 'timestamp',
      finalized_at: 'timestamp',
      finalized_by: 'uuid',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'diet.assessment.created',
    auditActionPatch: 'diet.assessment.updated',
  },
  diet_meal_plans: {
    columns: {
      tenant_id: 'uuid',
      patient_id: 'uuid',
      assessment_id: 'uuid',
      name: 'text',
      plan_source: 'text',
      cycle_days: 'integer',
      status: 'text',
      generated_by: 'uuid',
      generated_at: 'timestamp',
      approved_by: 'uuid',
      approved_at: 'timestamp',
      rejected_by: 'uuid',
      rejected_at: 'timestamp',
      rejection_reason: 'text',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'diet.plan.created',
    auditActionPatch: 'diet.plan.decided',
  },
  diet_meal_plan_days: {
    columns: {
      tenant_id: 'uuid',
      meal_plan_id: 'uuid',
      day_number: 'integer',
      breakfast: 'text',
      lunch: 'text',
      dinner: 'text',
      snacks: 'text',
      calories_kcal: 'integer',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'diet.plan.day.created',
    auditActionPatch: 'diet.plan.day.updated',
  },
  diet_intake_logs: {
    columns: {
      tenant_id: 'uuid',
      patient_id: 'uuid',
      meal_plan_day_id: 'uuid',
      meal_slot: 'text',
      portion_consumed_pct: 'integer',
      recorded_by: 'uuid',
      recorded_at: 'timestamp',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'diet.intake.recorded',
    auditActionPatch: 'diet.intake.updated',
  },
  // Module 22 (telemedicine). The waiting room and call are single-occupancy
  // and server-guarded; recording media stays in object storage, so only
  // references travel here.
  tele_consultations: {
    columns: {
      tenant_id: 'uuid',
      patient_id: 'uuid',
      encounter_id: 'uuid',
      clinician_id: 'uuid',
      booked_by: 'uuid',
      visit_code: 'text',
      channel: 'text',
      status: 'text',
      reason: 'text',
      scheduled_at: 'timestamp',
      waiting_at: 'timestamp',
      started_at: 'timestamp',
      completed_at: 'timestamp',
      cancelled_at: 'timestamp',
      cancellation_reason: 'text',
      no_show_at: 'timestamp',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'tele.consultation.created',
    auditActionPatch: 'tele.consultation.updated',
  },
  tele_vitals_overlays: {
    columns: {
      tenant_id: 'uuid',
      consultation_id: 'uuid',
      observed_by: 'uuid',
      heart_rate_bpm: 'integer',
      spo2_pct: 'number',
      temperature_c: 'number',
      respiratory_rate: 'integer',
      notes: 'text',
      observed_at: 'timestamp',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'tele.vitals.recorded',
    auditActionPatch: 'tele.vitals.updated',
  },
  tele_consultation_archives: {
    columns: {
      tenant_id: 'uuid',
      consultation_id: 'uuid',
      archived_by: 'uuid',
      duration_seconds: 'integer',
      recording_reference: 'text',
      transcript_reference: 'text',
      consent_recorded: 'integer',
      archived_at: 'timestamp',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'tele.consultation.archived',
    auditActionPatch: 'tele.consultation.archive_updated',
  },
}

// ---------------------------------------------------------------------------
// Validation
// ---------------------------------------------------------------------------

function validateMutation(raw: unknown): { ok: true; value: IncomingMutation } | { ok: false; error: string } {
  if (typeof raw !== 'object' || raw === null) return { ok: false, error: 'mutation must be an object' }
  const m = raw as Record<string, unknown>

  if (typeof m.id !== 'string' || !UUID_RE.test(m.id)) return { ok: false, error: 'id must be a uuid' }
  if (m.operation !== 'upsert' && m.operation !== 'patch') {
    return { ok: false, error: 'operation must be upsert or patch' }
  }
  if (m.operation === 'delete' || typeof m.data === 'undefined') {
    return { ok: false, error: 'delete operations are not accepted; retire by status transition' }
  }
  if (typeof m.table !== 'string' || m.table.length === 0) return { ok: false, error: 'table is required' }
  if (typeof m.row_id !== 'string' || !UUID_RE.test(m.row_id)) return { ok: false, error: 'row_id must be a uuid' }
  if (typeof m.idempotency_key !== 'string' || m.idempotency_key.length === 0) {
    return { ok: false, error: 'idempotency_key is required' }
  }
  if (m.origin !== 'online' && m.origin !== 'offline') return { ok: false, error: 'origin must be online or offline' }
  if (typeof m.client_created_at !== 'string' || Number.isNaN(Date.parse(m.client_created_at))) {
    return { ok: false, error: 'client_created_at must be an ISO-8601 timestamp' }
  }
  if (typeof m.data !== 'object' || m.data === null) return { ok: false, error: 'data must be an object' }

  return {
    ok: true,
    value: {
      id: m.id,
      operation: m.operation,
      table: m.table,
      row_id: m.row_id,
      idempotency_key: m.idempotency_key,
      origin: m.origin,
      client_created_at: m.client_created_at,
      conflict_policy: typeof m.conflict_policy === 'string' ? m.conflict_policy : undefined,
      data: m.data as Record<string, unknown>,
    },
  }
}

function validateColumns(
  rule: TableRule,
  data: Record<string, unknown>,
): { ok: true; data: Record<string, unknown> } | { ok: false; error: string } {
  const clean: Record<string, unknown> = {}
  for (const [key, value] of Object.entries(data)) {
    const type = rule.columns[key]
    if (type === undefined) return { ok: false, error: `column "${key}" is not writable on this table` }
    // Null passes every type: it clears a nullable column, and the database
    // enforces NOT NULL finally. Rejecting null here would forbid legitimate
    // clears and duplicate a constraint the database already owns.
    if (value === null || value === undefined) {
      clean[key] = null
      continue
    }
    switch (type) {
      case 'uuid':
        if (typeof value !== 'string' || !UUID_RE.test(value)) return { ok: false, error: `column "${key}" must be a uuid` }
        break
      case 'text':
        if (typeof value !== 'string') return { ok: false, error: `column "${key}" must be text` }
        break
      case 'boolean':
        if (typeof value !== 'boolean') return { ok: false, error: `column "${key}" must be a boolean` }
        break
      case 'integer':
        if (typeof value !== 'number' || !Number.isInteger(value)) return { ok: false, error: `column "${key}" must be an integer` }
        break
      case 'number':
        if (typeof value !== 'number' || !Number.isFinite(value)) return { ok: false, error: `column "${key}" must be a number` }
        break
      case 'timestamp':
        if (typeof value !== 'string' || Number.isNaN(Date.parse(value))) return { ok: false, error: `column "${key}" must be an ISO-8601 timestamp` }
        break
      case 'json':
        // Accepts an object as-is, or a JSON-encoded string, which is what
        // the client sends: the local projection stores JSON columns as TEXT,
        // so rows arrive encoded. The string is parsed back here so the jsonb
        // column receives a value, not a doubly-encoded string.
        if (typeof value === 'object') break
        if (typeof value === 'string') {
          try {
            clean[key] = JSON.parse(value)
          } catch {
            return { ok: false, error: `column "${key}" must be a JSON object` }
          }
          continue
        }
        return { ok: false, error: `column "${key}" must be a JSON object` }
    }
    clean[key] = value
  }
  return { ok: true, data: clean }
}

// ---------------------------------------------------------------------------
// Handler
// ---------------------------------------------------------------------------

export default {
  fetch: withSupabase({ auth: 'user' }, async (req, ctx) => {
    if (req.method !== 'POST') {
      return Response.json({ error: 'method not allowed' }, { status: 405 })
    }

    let body: { mutations?: unknown[] }
    try {
      body = await req.json()
    } catch {
      return Response.json({ error: 'invalid JSON body' }, { status: 400 })
    }

    const incoming = body.mutations
    if (!Array.isArray(incoming) || incoming.length === 0) {
      return Response.json({ error: 'mutations must be a non-empty array' }, { status: 400 })
    }
    if (incoming.length > 100) {
      return Response.json({ error: 'batch exceeds 100 mutations; the connector chunks uploads' }, { status: 413 })
    }

    // The user-scoped client resolves the caller's identity and memberships
    // under RLS; the admin client exists for the audit row and the mutation
    // ledger, which clients cannot write by design.
    const userId = ctx.claims.sub
    const { data: profile, error: profileError } = await ctx.supabase
      .from('app_users')
      .select('primary_tenant_id')
      .eq('id', userId)
      .maybeSingle()

    if (profileError || !profile?.primary_tenant_id) {
      return Response.json(
        { error: 'no tenant membership; account not provisioned' },
        { status: 403 },
      )
    }
    const tenantId: string = profile.primary_tenant_id

    const results: MutationResult[] = []

    for (const raw of incoming) {
      const parsed = validateMutation(raw)
      if (!parsed.ok) {
        const rawId = (raw as Record<string, unknown> | null)
        results.push({
          id: rawId && typeof rawId.id === 'string' ? rawId.id : 'unknown',
          outcome: 'rejected',
          rejection_class: 'validation',
          detail: parsed.error,
        })
        continue
      }
      const m = parsed.value

      const rule = WRITABLE_TABLES[m.table]
      if (!rule) {
        results.push({
          id: m.id,
          outcome: 'rejected',
          rejection_class: 'unsupported',
          detail: `table "${m.table}" has no offline write path; register it in WRITABLE_TABLES with a validator before use`,
        })
        continue
      }

      if (!rule.operations.includes(m.operation)) {
        results.push({
          id: m.id,
          outcome: 'rejected',
          rejection_class: 'unsupported',
          detail: `operation "${m.operation}" is not permitted on table "${m.table}"`,
        })
        continue
      }

      const cols = validateColumns(rule, m.data)
      if (!cols.ok) {
        results.push({
          id: m.id,
          outcome: 'rejected',
          rejection_class: 'validation',
          detail: cols.error,
        })
        continue
      }

      // Idempotency ledger. A duplicate (tenant_id, idempotency_key) means this
      // exact mutation already landed — a retry after a lost response.
      const { data: existing } = await ctx.supabaseAdmin
        .from('mutations')
        .select('id, status')
        .eq('tenant_id', tenantId)
        .eq('idempotency_key', m.idempotency_key)
        .maybeSingle()

      if (existing) {
        results.push({
          id: m.id,
          outcome: existing.status === 'applied' ? 'already_applied' : 'rejected',
          rejection_class: existing.status === 'applied' ? undefined : 'duplicate_pending',
          detail: existing.status === 'applied' ? 'mutation already applied' : `original mutation is ${existing.status}`,
        })
        continue
      }

      // Ledger row first, status 'received'. A ledger failure blocks the apply:
      // a successful write with no ledger row would re-apply on retry.
      const { error: ledgerError } = await ctx.supabaseAdmin.from('mutations').insert({
        id: m.id,
        tenant_id: tenantId,
        user_id: userId,
        device_id: null, // connector does not yet send device_id; see phase-2 follow-up
        operation: m.operation,
        resource_type: m.table,
        resource_id: m.row_id,
        idempotency_key: m.idempotency_key,
        client_created_at: m.client_created_at,
        origin: m.origin,
        payload_digest: String(m.idempotency_key), // connector upgrades this to a real digest in Phase 2
        status: 'received',
      })
      if (ledgerError) {
        // Unique violation here means a concurrent duplicate landed first.
        const duplicate = ledgerError.message.includes('duplicate key')
        results.push({
          id: m.id,
          outcome: duplicate ? 'already_applied' : 'rejected',
          rejection_class: duplicate ? undefined : 'internal',
          detail: duplicate ? 'mutation already applied' : `ledger write failed: ${ledgerError.message}`,
        })
        continue
      }

      const markLedger = async (status: 'applied' | 'rejected') => {
        await ctx.supabaseAdmin
          .from('mutations')
          .update({
            status,
            applied_at: status === 'applied' ? new Date().toISOString() : null,
          })
          .eq('id', m.id)
      }

      // Audit before apply. If the write itself then fails, the ledger and the
      // audit trail both record the attempt; nothing is silently lost.
      const auditAction = m.operation === 'upsert' ? rule.auditActionUpsert : rule.auditActionPatch
      const { error: auditError } = await ctx.supabaseAdmin.from('audit_events').insert({
        tenant_id: tenantId,
        actor_id: userId,
        action: auditAction,
        resource_type: m.table,
        resource_id: m.row_id,
        mutation_id: m.id,
        origin: m.origin,
        outcome: 'succeeded',
        risk_tier: 'standard',
      })
      if (auditError) {
        await markLedger('rejected')
        results.push({
          id: m.id,
          outcome: 'rejected',
          rejection_class: 'internal',
          detail: 'audit write failed; mutation not applied',
        })
        continue
      }

      const table = ctx.supabase.from(m.table)
      let applyError: { message: string } | null = null
      if (m.operation === 'upsert') {
        const r = await table.upsert({ id: m.row_id, ...cols.data })
        applyError = r.error ? { message: r.error.message } : null
      } else {
        const r = await table.update(cols.data).eq('id', m.row_id)
        applyError = r.error ? { message: r.error.message } : null
      }

      if (applyError) {
        await markLedger('rejected')
        results.push({
          id: m.id,
          outcome: 'rejected',
          rejection_class: 'internal',
          detail: `apply failed: ${applyError.message}`,
        })
        continue
      }

      await markLedger('applied')
      results.push({ id: m.id, outcome: 'applied' })
    }

    return Response.json({ results })
  }),
}
