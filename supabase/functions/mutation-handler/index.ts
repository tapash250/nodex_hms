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
  /** Originating device, when the connector could bind one. */
  device_id?: string
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
// Ledger integrity helpers
//
// payload_digest records exactly what the client asked to apply. It is a real
// SHA-256 over the canonical JSON of the mutation payload, so a later
// disagreement about what a mutation contained is detectable rather than
// argued. The previous value echoed the idempotency key, which identified the
// mutation but attested nothing about its contents.
// ---------------------------------------------------------------------------

/// Canonical JSON: object keys sorted recursively, no insignificant whitespace.
/// `JSON.stringify` with a replacer that re-inserts keys in sorted order gives
/// the same text for semantically identical payloads regardless of key order,
/// which is what makes the digest comparable across client versions.
///
/// Exported so the digest's invariants are testable without a request; the
/// ledger's tamper-evidence rests entirely on this being deterministic.
export function canonicalJson(value: unknown): string {
  return JSON.stringify(value, (_key: string, val: unknown) => {
    if (val === null || typeof val !== 'object' || Array.isArray(val)) {
      return val
    }
    const sorted: Record<string, unknown> = {}
    for (const key of Object.keys(val as Record<string, unknown>).sort()) {
      sorted[key] = (val as Record<string, unknown>)[key]
    }
    return sorted
  })
}

/// Lowercase hex SHA-256 of [text].
export async function sha256Hex(text: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text))
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('')
}

/// Resolves the originating device for a mutation.
///
/// The body field is authoritative — the connector sets it per batch — and the
/// `x-device-id` header is the fallback for a transport that already knows the
/// device (a retry proxy, a service caller). Anything else stays null: identity
/// rests on (tenant_id, idempotency_key) plus actor, and a guessed UUID would
/// lie about provenance in the ledger.
export function resolveDeviceId(req: Request, m: { device_id?: unknown }): string | null {
  const fromBody = m.device_id
  if (typeof fromBody === 'string' && UUID_RE.test(fromBody)) {
    return fromBody
  }
  const fromHeader = req.headers.get('x-device-id')
  if (fromHeader !== null && UUID_RE.test(fromHeader)) {
    return fromHeader
  }
  return null
}

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
  // Module 16 (problem list). A problem is resolved by recording when and by
  // whom it resolved; the row is never deleted and never reopened, which the
  // clinical_problems guard trigger enforces.
  clinical_problems: {
    columns: {
      tenant_id: 'uuid',
      patient_id: 'uuid',
      encounter_id: 'uuid',
      problem_code: 'text',
      description: 'text',
      clinical_status: 'text',
      onset_date: 'timestamp',
      resolved_at: 'timestamp',
      resolution_note: 'text',
      recorded_by: 'uuid',
      resolved_by: 'uuid',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'problem.recorded',
    auditActionPatch: 'problem.resolved',
  },
  // Module 16 (ambient scribe). Recording a dictation is authoring the
  // encounter, so upsert is permitted; the decision to accept or reject is a
  // review event that travels as a patch, and the server's review guard keeps
  // reviewed machine output immutable.
  encounter_scribe_drafts: {
    columns: {
      tenant_id: 'uuid',
      encounter_id: 'uuid',
      model_id: 'text',
      transcript_text: 'text',
      subjective_note: 'text',
      objective_findings: 'text',
      assessment: 'text',
      plan_description: 'text',
      confidence: 'number',
      safety_decision: 'text',
      status: 'text',
      requested_by: 'uuid',
      reviewed_by: 'uuid',
      reviewed_at: 'timestamp',
      rejection_reason: 'text',
      accepted_fields: 'json',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'scribe.dictated',
    auditActionPatch: 'scribe.reviewed',
  },
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
  // The running balance is not a client-writable column: it is absent from the
  // whitelist below, so a device can open an account and move its status but can
  // never assert a balance of its own.
  patient_accounts: {
    columns: {
      tenant_id: 'uuid',
      patient_id: 'uuid',
      account_code: 'text',
      currency: 'text',
      status: 'text',
      last_activity_at: 'timestamp',
      opened_at: 'timestamp',
      closed_at: 'timestamp',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'billing.account.opened',
    auditActionPatch: 'billing.account.updated',
  },
  ledger_entries: {
    columns: {
      tenant_id: 'uuid',
      account_id: 'uuid',
      invoice_id: 'uuid',
      payment_id: 'uuid',
      refund_id: 'uuid',
      transaction_type: 'text',
      direction: 'text',
      account_code: 'text',
      amount_minor: 'integer',
      currency: 'text',
      payment_method: 'text',
      memo: 'text',
      recorded_by: 'uuid',
      occurred_at: 'timestamp',
      created_at: 'timestamp',
    },
    operations: ['upsert'],
    auditActionUpsert: 'billing.ledger.posted',
    auditActionPatch: 'billing.ledger.posted',
  },
  payment_allocations: {
    columns: {
      tenant_id: 'uuid',
      payment_id: 'uuid',
      invoice_id: 'uuid',
      amount_minor: 'integer',
      created_at: 'timestamp',
    },
    operations: ['upsert'],
    auditActionUpsert: 'billing.allocation.recorded',
    auditActionPatch: 'billing.allocation.recorded',
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
    operations: ['upsert'],
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
      // JSON array of {path, sha256} for images in clinical-images. Arrives as
      // a JSON-encoded string because the local projection stores it as TEXT.
      image_refs: 'json',
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
  // Module 23 (discharge management). Clearance, reconciliation, settlement
  // and the AI summary are the artifacts that gate discharge authorization;
  // settlement rides on billing.settle and summary review on
  // discharge_summary.review.
  discharge_clearances: {
    columns: {
      tenant_id: 'uuid',
      discharge_id: 'uuid',
      reviewed_by: 'uuid',
      status: 'text',
      outstanding_items: 'integer',
      notes: 'text',
      cleared_by: 'uuid',
      cleared_at: 'timestamp',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'discharge.clearance.recorded',
    auditActionPatch: 'discharge.clearance.updated',
  },
  discharge_medication_reconciliations: {
    columns: {
      tenant_id: 'uuid',
      discharge_id: 'uuid',
      status: 'text',
      medications_reviewed: 'integer',
      discrepancies_found: 'integer',
      reviewed_by: 'uuid',
      reviewed_at: 'timestamp',
      notes: 'text',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'discharge.reconciliation.started',
    auditActionPatch: 'discharge.reconciliation.completed',
  },
  discharge_medication_reconciliation_items: {
    columns: {
      tenant_id: 'uuid',
      reconciliation_id: 'uuid',
      medication_name: 'text',
      action: 'text',
      discrepancy: 'integer',
      detail: 'text',
      recorded_by: 'uuid',
      recorded_at: 'timestamp',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'discharge.medication.recorded',
    auditActionPatch: 'discharge.medication.updated',
  },
  discharge_settlements: {
    columns: {
      tenant_id: 'uuid',
      discharge_id: 'uuid',
      invoice_id: 'uuid',
      amount_minor: 'integer',
      settled_by: 'uuid',
      settled_at: 'timestamp',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'discharge.settlement.recorded',
    auditActionPatch: 'discharge.settlement.updated',
  },
  // Module 24 (floor map). Room geometry is facility-scoped layout data and
  // is never deleted: a room leaves the plan by retiring it with a reason, so
  // the floors already drawn on a client stay interpretable.
  ward_rooms: {
    columns: {
      tenant_id: 'uuid',
      facility_id: 'uuid',
      ward_id: 'uuid',
      room_code: 'text',
      room_name: 'text',
      room_type: 'text',
      floor_label: 'text',
      capacity: 'integer',
      grid_x: 'integer',
      grid_y: 'integer',
      grid_span_x: 'integer',
      grid_span_y: 'integer',
      status: 'text',
      retired_by: 'uuid',
      retired_at: 'timestamp',
      retirement_reason: 'text',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'ward.room.registered',
    auditActionPatch: 'ward.room.updated',
  },
  // Module 06 (nurse ward station). Vitals and handovers are append-only facts,
  // so they accept an insert/upsert but no patch.
  ward_vitals: {
    columns: {
      tenant_id: 'uuid',
      patient_id: 'uuid',
      encounter_id: 'uuid',
      ward_id: 'uuid',
      bed_id: 'uuid',
      recorded_by: 'uuid',
      observed_at: 'timestamp',
      temperature_celsius: 'number',
      pulse_bpm: 'integer',
      respiratory_rate: 'integer',
      systolic_bp: 'integer',
      diastolic_bp: 'integer',
      spo2: 'integer',
      pain_score: 'integer',
      consciousness: 'text',
      on_oxygen: 'boolean',
      notes: 'text',
      created_at: 'timestamp',
    },
    operations: ['upsert'],
    auditActionUpsert: 'nursing.vitals.recorded',
  },
  ward_handovers: {
    columns: {
      tenant_id: 'uuid',
      ward_id: 'uuid',
      shift_id: 'uuid',
      from_user: 'uuid',
      to_user: 'uuid',
      handover_at: 'timestamp',
      summary: 'text',
      pending_items: 'text',
      created_at: 'timestamp',
    },
    operations: ['upsert'],
    auditActionUpsert: 'nursing.handover.recorded',
  },
  ward_tasks: {
    columns: {
      tenant_id: 'uuid',
      ward_id: 'uuid',
      patient_id: 'uuid',
      encounter_id: 'uuid',
      title: 'text',
      detail: 'text',
      task_type: 'text',
      priority: 'text',
      due_at: 'timestamp',
      assigned_to: 'uuid',
      status: 'text',
      created_by: 'uuid',
      completed_by: 'uuid',
      completed_at: 'timestamp',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'nursing.task.created',
    auditActionPatch: 'nursing.task.updated',
  },
  // Module 41 (clinical & administrative task engine). Every column a client
  // may set is listed; the transition guard in the migration owns the state
  // machine, so a patch can move a task but cannot invent a completion.
  hospital_tasks: {
    columns: {
      tenant_id: 'uuid',
      task_code: 'text',
      title: 'text',
      detail: 'text',
      category: 'text',
      priority: 'text',
      status: 'text',
      patient_id: 'uuid',
      encounter_id: 'uuid',
      from_location: 'text',
      to_location: 'text',
      requested_by: 'uuid',
      assigned_to: 'uuid',
      due_at: 'timestamp',
      claimed_at: 'timestamp',
      started_at: 'timestamp',
      completed_by: 'uuid',
      completed_at: 'timestamp',
      completion_note: 'text',
      cancellation_reason: 'text',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'tasks.task.raised',
    auditActionPatch: 'tasks.task.transitioned',
  },
  // Module 47 (clinical forms builder). A template is authored and then frozen
  // by the server; a response is written once and never patched, so the
  // handler refuses updates to it.
  form_templates: {
    columns: {
      tenant_id: 'uuid',
      template_code: 'text',
      title: 'text',
      description: 'text',
      version: 'integer',
      schema_json: 'json',
      status: 'text',
      created_by: 'uuid',
      published_at: 'timestamp',
      retired_at: 'timestamp',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'forms.template.created',
    auditActionPatch: 'forms.template.updated',
  },
  form_responses: {
    columns: {
      tenant_id: 'uuid',
      template_id: 'uuid',
      template_version: 'integer',
      patient_id: 'uuid',
      encounter_id: 'uuid',
      submitted_by: 'uuid',
      values_json: 'json',
      submitted_at: 'timestamp',
      created_at: 'timestamp',
    },
    operations: ['upsert'],
    auditActionUpsert: 'forms.response.submitted',
  },
  // Module 02 (operations dashboard). A reading of a moment is written once.
  operational_department_metrics: {
    columns: {
      tenant_id: 'uuid',
      facility_id: 'uuid',
      department_id: 'uuid',
      metric_timestamp: 'timestamp',
      registrations: 'integer',
      waiting_count: 'integer',
      completed_count: 'integer',
      average_wait_minutes: 'number',
      bottleneck: 'text',
      created_at: 'timestamp',
    },
    operations: ['upsert'],
    auditActionUpsert: 'operations.metric.recorded',
  },
  // Module 03 (performance analytics). A reading of a period is written once.
  clinical_performance_indices: {
    columns: {
      tenant_id: 'uuid',
      indicator_code: 'text',
      indicator_name: 'text',
      category: 'text',
      period_start: 'timestamp',
      period_end: 'timestamp',
      value: 'number',
      baseline_mean: 'number',
      baseline_stddev: 'number',
      sample_size: 'integer',
      lower_is_better: 'boolean',
      created_at: 'timestamp',
    },
    operations: ['upsert'],
    auditActionUpsert: 'performance.index.recorded',
  },
  // Module 04 (doctor clinical dashboard). An assignment is taken on and
  // concluded; it is never deleted, because the record of who was
  // responsible is part of the patient's story.
  doctor_assignments: {
    columns: {
      tenant_id: 'uuid',
      doctor_id: 'uuid',
      patient_id: 'uuid',
      assignment_type: 'text',
      status: 'text',
      assigned_at: 'timestamp',
      concluded_at: 'timestamp',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'clinical_dashboard.assignment.created',
    auditActionPatch: 'clinical_dashboard.assignment.updated',
  },
  // Module 43 (secure clinical messaging). A message is written once and never
  // patched; a thread's participant list may grow, never shrink.
  clinical_threads: {
    columns: {
      tenant_id: 'uuid',
      subject: 'text',
      patient_id: 'uuid',
      encounter_id: 'uuid',
      created_by: 'uuid',
      participants: 'json',
      status: 'text',
      last_message_at: 'timestamp',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'messaging.thread.started',
    auditActionPatch: 'messaging.thread.updated',
  },
  clinical_messages: {
    columns: {
      tenant_id: 'uuid',
      thread_id: 'uuid',
      sender_id: 'uuid',
      body: 'text',
      is_urgent: 'boolean',
      created_at: 'timestamp',
    },
    operations: ['upsert'],
    auditActionUpsert: 'messaging.message.sent',
  },
  clinical_attachments: {
    columns: {
      tenant_id: 'uuid',
      message_id: 'uuid',
      file_name: 'text',
      content_type: 'text',
      size_bytes: 'number',
      storage_path: 'text',
      created_at: 'timestamp',
    },
    operations: ['upsert'],
    auditActionUpsert: 'messaging.attachment.added',
  },
  // Module 44 (productivity apps). A card moves between lanes and a ticket
  // is worked on, so both are patchable; the guards in the migration own the
  // state machines.
  work_items: {
    columns: {
      tenant_id: 'uuid',
      board_key: 'text',
      title: 'text',
      detail: 'text',
      lane: 'text',
      position: 'integer',
      priority: 'text',
      patient_id: 'uuid',
      ward_id: 'uuid',
      department_id: 'uuid',
      created_by: 'uuid',
      assigned_to: 'uuid',
      due_at: 'timestamp',
      completed_at: 'timestamp',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'productivity.card.created',
    auditActionPatch: 'productivity.card.moved',
  },
  it_tickets: {
    columns: {
      tenant_id: 'uuid',
      ticket_code: 'text',
      title: 'text',
      detail: 'text',
      category: 'text',
      priority: 'text',
      status: 'text',
      reported_by: 'uuid',
      assigned_to: 'uuid',
      resolution_note: 'text',
      opened_at: 'timestamp',
      closed_at: 'timestamp',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'productivity.ticket.raised',
    auditActionPatch: 'productivity.ticket.updated',
  },
  // Module 13 (human resources & payroll suite).
  hr_employees: {
    columns: {
      tenant_id: 'uuid',
      user_id: 'uuid',
      employee_code: 'text',
      department_id: 'uuid',
      designation: 'text',
      employment_type: 'text',
      employment_status: 'text',
      grade: 'text',
      reports_to: 'uuid',
      joined_on: 'text',
      confirmation_on: 'text',
      separated_on: 'text',
      notes: 'text',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'hr.employee.registered',
    auditActionPatch: 'hr.employee.updated',
  },
  hr_leave_requests: {
    columns: {
      tenant_id: 'uuid',
      employee_id: 'uuid',
      leave_type: 'text',
      starts_on: 'text',
      ends_on: 'text',
      reason: 'text',
      status: 'text',
      requested_by: 'uuid',
      decided_by: 'uuid',
      decided_at: 'timestamp',
      decision_note: 'text',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'hr.leave.requested',
    auditActionPatch: 'hr.leave.decided',
  },
  hr_holidays: {
    columns: {
      tenant_id: 'uuid',
      facility_id: 'uuid',
      holiday_date: 'text',
      display_name: 'text',
      holiday_type: 'text',
      is_paid: 'boolean',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'hr.holiday.set',
    auditActionPatch: 'hr.holiday.updated',
  },
  hr_payroll_periods: {
    columns: {
      tenant_id: 'uuid',
      facility_id: 'uuid',
      period_start: 'text',
      period_end: 'text',
      pay_date: 'text',
      currency: 'text',
      status: 'text',
      finalized_by: 'uuid',
      finalized_at: 'timestamp',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'hr.payroll.opened',
    auditActionPatch: 'hr.payroll.updated',
  },
  hr_payslips: {
    columns: {
      tenant_id: 'uuid',
      period_id: 'uuid',
      employee_id: 'uuid',
      gross_minor: 'integer',
      deductions_minor: 'integer',
      net_minor: 'integer',
      status: 'text',
      paid_on: 'text',
      note: 'text',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'hr.payslip.created',
    auditActionPatch: 'hr.payslip.updated',
  },
  // Module 09 (allied staff & workforce rosters).
  staff_shifts: {
    columns: {
      tenant_id: 'uuid',
      facility_id: 'uuid',
      department_id: 'uuid',
      shift_date: 'text',
      shift_code: 'text',
      display_name: 'text',
      staff_category: 'text',
      starts_at: 'timestamp',
      ends_at: 'timestamp',
      required_headcount: 'integer',
      status: 'text',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'workforce.shift.scheduled',
    auditActionPatch: 'workforce.shift.updated',
  },
  duty_allocations: {
    columns: {
      tenant_id: 'uuid',
      shift_id: 'uuid',
      staff_user_id: 'uuid',
      allocation_role: 'text',
      status: 'text',
      note: 'text',
      allocated_by: 'uuid',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'workforce.duty.allocated',
    auditActionPatch: 'workforce.duty.updated',
  },
  attendance_logs: {
    columns: {
      tenant_id: 'uuid',
      allocation_id: 'uuid',
      staff_user_id: 'uuid',
      event_type: 'text',
      occurred_at: 'timestamp',
      recorded_by: 'uuid',
      note: 'text',
      created_at: 'timestamp',
    },
    operations: ['upsert'],
    auditActionUpsert: 'workforce.attendance.recorded',
  },
  // Module 12 (clinical departments registry).
  departments: {
    columns: {
      tenant_id: 'uuid',
      facility_id: 'uuid',
      code: 'text',
      display_name: 'text',
      specialty: 'text',
      head_user_id: 'uuid',
      status: 'text',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'directory.department.registered',
    auditActionPatch: 'directory.department.updated',
  },
  // Module 42 (hospital contacts directory).
  directory_contacts: {
    columns: {
      tenant_id: 'uuid',
      facility_id: 'uuid',
      department_id: 'uuid',
      name: 'text',
      category: 'text',
      contact_role: 'text',
      organisation: 'text',
      phone_primary: 'text',
      phone_secondary: 'text',
      extension: 'text',
      email: 'text',
      address: 'text',
      notes: 'text',
      is_emergency: 'boolean',
      available_24_7: 'boolean',
      display_order: 'integer',
      status: 'text',
      created_by: 'uuid',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'directory.contact.registered',
    auditActionPatch: 'directory.contact.updated',
  },
  // Module 40 (institutional calendar & shift overlay).
  calendar_events: {
    columns: {
      tenant_id: 'uuid',
      facility_id: 'uuid',
      department_id: 'uuid',
      title: 'text',
      description: 'text',
      event_type: 'text',
      starts_at: 'timestamp',
      ends_at: 'timestamp',
      all_day: 'boolean',
      location: 'text',
      status: 'text',
      created_by: 'uuid',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'calendar.event.created',
    auditActionPatch: 'calendar.event.updated',
  },
  // Module 27 (fleet & ambulance dispatch).
  ambulances: {
    columns: {
      tenant_id: 'uuid',
      facility_id: 'uuid',
      call_sign: 'text',
      registration_no: 'text',
      vehicle_type: 'text',
      capacity: 'integer',
      capability_notes: 'text',
      service_status: 'text',
      created_by: 'uuid',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'fleet.vehicle.registered',
    auditActionPatch: 'fleet.vehicle.updated',
  },
  ambulance_duty_assignments: {
    columns: {
      tenant_id: 'uuid',
      ambulance_id: 'uuid',
      driver_user_id: 'uuid',
      attendant_user_id: 'uuid',
      starts_at: 'timestamp',
      ends_at: 'timestamp',
      status: 'text',
      notes: 'text',
      created_by: 'uuid',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'fleet.duty.scheduled',
    auditActionPatch: 'fleet.duty.updated',
  },
  ambulance_dispatches: {
    columns: {
      tenant_id: 'uuid',
      facility_id: 'uuid',
      ambulance_id: 'uuid',
      duty_assignment_id: 'uuid',
      driver_user_id: 'uuid',
      patient_id: 'uuid',
      patient_name_text: 'text',
      priority: 'text',
      status: 'text',
      requesting_reference: 'text',
      pickup_address: 'text',
      destination_address: 'text',
      destination_facility: 'text',
      requested_at: 'timestamp',
      dispatched_at: 'timestamp',
      on_scene_at: 'timestamp',
      completed_at: 'timestamp',
      cancellation_reason: 'text',
      notes: 'text',
      created_by: 'uuid',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'fleet.dispatch.raised',
    auditActionPatch: 'fleet.dispatch.updated',
  },
  ambulance_tracking_pings: {
    columns: {
      tenant_id: 'uuid',
      ambulance_id: 'uuid',
      dispatch_id: 'uuid',
      latitude: 'number',
      longitude: 'number',
      speed_kph: 'number',
      recorded_at: 'timestamp',
      source: 'text',
      created_at: 'timestamp',
    },
    operations: ['upsert'],
    auditActionUpsert: 'fleet.tracking.pinged',
  },
  // Module 29 (biomedical assets & calibration).
  biomedical_assets: {
    columns: {
      tenant_id: 'uuid',
      facility_id: 'uuid',
      department_id: 'uuid',
      asset_tag: 'text',
      name: 'text',
      category: 'text',
      manufacturer: 'text',
      model_no: 'text',
      serial_no: 'text',
      criticality: 'text',
      status: 'text',
      commissioned_on: 'timestamp',
      warranty_until: 'timestamp',
      notes: 'text',
      created_by: 'uuid',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'biomedical.asset.registered',
    auditActionPatch: 'biomedical.asset.updated',
  },
  biomedical_breakdown_tickets: {
    columns: {
      tenant_id: 'uuid',
      asset_id: 'uuid',
      facility_id: 'uuid',
      reported_by: 'uuid',
      reported_at: 'timestamp',
      priority: 'text',
      symptom: 'text',
      status: 'text',
      acknowledged_at: 'timestamp',
      resolved_at: 'timestamp',
      resolution_notes: 'text',
      cancellation_reason: 'text',
      created_by: 'uuid',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'biomedical.ticket.raised',
    auditActionPatch: 'biomedical.ticket.updated',
  },
  biomedical_maintenance_records: {
    columns: {
      tenant_id: 'uuid',
      asset_id: 'uuid',
      ticket_id: 'uuid',
      kind: 'text',
      result: 'text',
      performed_at: 'timestamp',
      performed_by: 'uuid',
      provider: 'text',
      next_due_at: 'timestamp',
      reference: 'text',
      notes: 'text',
      created_at: 'timestamp',
    },
    operations: ['upsert'],
    auditActionUpsert: 'biomedical.maintenance.recorded',
  },
  // Module 30 (bio-medical waste management).
  waste_categories: {
    columns: {
      tenant_id: 'uuid',
      code: 'text',
      name: 'text',
      colour: 'text',
      hazard_class: 'text',
      requires_treatment: 'integer',
      treatment_method: 'text',
      retention_days: 'integer',
      is_active: 'integer',
      created_by: 'uuid',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'waste.category.registered',
    auditActionPatch: 'waste.category.updated',
  },
  waste_generation_logs: {
    columns: {
      tenant_id: 'uuid',
      facility_id: 'uuid',
      category_id: 'uuid',
      department_id: 'uuid',
      location_label: 'text',
      weight_grams: 'integer',
      container_count: 'integer',
      logged_at: 'timestamp',
      logged_by: 'uuid',
      notes: 'text',
      created_at: 'timestamp',
    },
    operations: ['upsert'],
    auditActionUpsert: 'waste.generation.logged',
  },
  waste_disposal_certificates: {
    columns: {
      tenant_id: 'uuid',
      facility_id: 'uuid',
      category_id: 'uuid',
      certificate_no: 'text',
      barcode: 'text',
      disposal_vendor: 'text',
      vendor_licence: 'text',
      method: 'text',
      disposed_at: 'timestamp',
      weight_grams: 'integer',
      manifest_reference: 'text',
      status: 'text',
      void_reason: 'text',
      issued_by: 'uuid',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'waste.certificate.issued',
    auditActionPatch: 'waste.certificate.voided',
  },
  // Module 32 (health insurance & TPA).
  insurance_payers: {
    columns: {
      tenant_id: 'uuid',
      code: 'text',
      name: 'text',
      payer_type: 'text',
      claim_portal_ref: 'text',
      contact_phone: 'text',
      contact_email: 'text',
      is_active: 'boolean',
      notes: 'text',
      created_by: 'uuid',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'insurance.payer.registered',
    auditActionPatch: 'insurance.payer.updated',
  },
  insurance_policies: {
    columns: {
      tenant_id: 'uuid',
      patient_id: 'uuid',
      payer_id: 'uuid',
      policy_no: 'text',
      member_id: 'text',
      plan_name: 'text',
      coverage_type: 'text',
      currency: 'text',
      sum_insured_minor: 'integer',
      valid_from: 'timestamp',
      valid_to: 'timestamp',
      status: 'text',
      verified_at: 'timestamp',
      verified_by: 'uuid',
      verification_reference: 'text',
      cancelled_at: 'timestamp',
      cancellation_reason: 'text',
      notes: 'text',
      created_by: 'uuid',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'insurance.policy.registered',
    auditActionPatch: 'insurance.policy.updated',
  },
  pre_authorisation_requests: {
    columns: {
      tenant_id: 'uuid',
      policy_id: 'uuid',
      patient_id: 'uuid',
      facility_id: 'uuid',
      encounter_id: 'uuid',
      requested_by: 'uuid',
      requested_at: 'timestamp',
      diagnosis: 'text',
      procedure_text: 'text',
      currency: 'text',
      estimated_cost_minor: 'integer',
      status: 'text',
      payer_reference: 'text',
      answered_at: 'timestamp',
      approved_amount_minor: 'integer',
      valid_until: 'timestamp',
      decision_notes: 'text',
      cancellation_reason: 'text',
      created_by: 'uuid',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'insurance.pre_authorisation.raised',
    auditActionPatch: 'insurance.pre_authorisation.updated',
  },
  insurance_claims: {
    columns: {
      tenant_id: 'uuid',
      policy_id: 'uuid',
      patient_id: 'uuid',
      facility_id: 'uuid',
      pre_authorisation_id: 'uuid',
      invoice_id: 'uuid',
      claim_no: 'text',
      currency: 'text',
      claimed_amount_minor: 'integer',
      approved_amount_minor: 'integer',
      settled_amount_minor: 'integer',
      status: 'text',
      payer_reference: 'text',
      submitted_at: 'timestamp',
      decided_at: 'timestamp',
      settled_at: 'timestamp',
      rejection_reason: 'text',
      cancellation_reason: 'text',
      notes: 'text',
      created_by: 'uuid',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'insurance.claim.created',
    auditActionPatch: 'insurance.claim.updated',
  },
  // Module 33 (documents & biometric e-consent vault).
  consent_templates: {
    columns: {
      tenant_id: 'uuid',
      code: 'text',
      title: 'text',
      procedure_category: 'text',
      body_text: 'text',
      version: 'integer',
      requires_witness: 'boolean',
      requires_biometric: 'boolean',
      validity_days: 'integer',
      is_active: 'boolean',
      created_by: 'uuid',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'documents.consent_template.published',
    auditActionPatch: 'documents.consent_template.updated',
  },
  consent_records: {
    columns: {
      tenant_id: 'uuid',
      patient_id: 'uuid',
      facility_id: 'uuid',
      encounter_id: 'uuid',
      template_id: 'uuid',
      procedure_text: 'text',
      status: 'text',
      signer_name: 'text',
      signer_relationship: 'text',
      signature_sha256: 'text',
      signature_point_count: 'integer',
      signature_captured_at: 'timestamp',
      biometric_method: 'text',
      biometric_template_sha256: 'text',
      biometric_captured_at: 'timestamp',
      biometric_quality: 'integer',
      witnessed_by: 'uuid',
      witnessed_at: 'timestamp',
      document_id: 'uuid',
      signed_at: 'timestamp',
      expires_at: 'timestamp',
      declined_at: 'timestamp',
      decline_reason: 'text',
      revoked_at: 'timestamp',
      revocation_reason: 'text',
      created_by: 'uuid',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'documents.consent.raised',
    auditActionPatch: 'documents.consent.updated',
  },
  document_vault_documents: {
    columns: {
      tenant_id: 'uuid',
      patient_id: 'uuid',
      encounter_id: 'uuid',
      consent_id: 'uuid',
      kind: 'text',
      title: 'text',
      bucket: 'text',
      object_path: 'text',
      mime_type: 'text',
      size_bytes: 'integer',
      sha256: 'text',
      signature: 'text',
      signature_algorithm: 'text',
      signing_key_id: 'text',
      status: 'text',
      issued_by: 'uuid',
      issued_at: 'timestamp',
      superseded_at: 'timestamp',
      superseded_by: 'uuid',
      voided_at: 'timestamp',
      void_reason: 'text',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'documents.vault.issued',
    auditActionPatch: 'documents.vault.updated',
  },
  // Module 34 (statutory records & birth/death registry).
  statutory_birth_records: {
    columns: {
      tenant_id: 'uuid',
      facility_id: 'uuid',
      registration_number: 'text',
      child_name: 'text',
      sex: 'text',
      birth_at: 'timestamp',
      place_of_birth: 'text',
      delivery_type: 'text',
      plurality: 'text',
      weight_grams: 'integer',
      mother_patient_id: 'uuid',
      mother_name: 'text',
      father_name: 'text',
      informant_name: 'text',
      attended_by: 'uuid',
      status: 'text',
      registration_at: 'timestamp',
      certificate_number: 'text',
      certified_by: 'uuid',
      certified_at: 'timestamp',
      voided_at: 'timestamp',
      void_reason: 'text',
      created_by: 'uuid',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'statutory.birth.raised',
    auditActionPatch: 'statutory.birth.updated',
  },
  statutory_death_records: {
    columns: {
      tenant_id: 'uuid',
      facility_id: 'uuid',
      registration_number: 'text',
      patient_id: 'uuid',
      deceased_name: 'text',
      sex: 'text',
      age_years: 'integer',
      death_at: 'timestamp',
      place_of_death: 'text',
      cause_of_death_text: 'text',
      icd10_code: 'text',
      manner_of_death: 'text',
      is_medico_legal: 'boolean',
      certifying_clinician: 'uuid',
      informant_name: 'text',
      informant_relationship: 'text',
      status: 'text',
      registration_at: 'timestamp',
      certificate_number: 'text',
      certified_by: 'uuid',
      certified_at: 'timestamp',
      voided_at: 'timestamp',
      void_reason: 'text',
      created_by: 'uuid',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'statutory.death.raised',
    auditActionPatch: 'statutory.death.updated',
  },
  statutory_mlc_intimations: {
    columns: {
      tenant_id: 'uuid',
      facility_id: 'uuid',
      case_number: 'text',
      patient_id: 'uuid',
      subject_name: 'text',
      case_type: 'text',
      incident_at: 'timestamp',
      reported_at: 'timestamp',
      reporting_clinician: 'uuid',
      police_station: 'text',
      police_officer_name: 'text',
      police_contact: 'text',
      police_reference: 'text',
      status: 'text',
      intimated_at: 'timestamp',
      acknowledged_at: 'timestamp',
      closed_at: 'timestamp',
      closure_reason: 'text',
      voided_at: 'timestamp',
      void_reason: 'text',
      created_by: 'uuid',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'statutory.mlc.logged',
    auditActionPatch: 'statutory.mlc.updated',
  },
  statutory_record_amendments: {
    columns: {
      tenant_id: 'uuid',
      birth_record_id: 'uuid',
      death_record_id: 'uuid',
      mlc_intimation_id: 'uuid',
      subject_field: 'text',
      previous_value: 'text',
      new_value: 'text',
      reason: 'text',
      amended_by: 'uuid',
      created_at: 'timestamp',
    },
    operations: ['upsert'],
    auditActionUpsert: 'statutory.amendment.appended',
  },
  // Module 35 (quality & NABH compliance hub).
  compliance_audits: {
    columns: {
      tenant_id: 'uuid',
      facility_id: 'uuid',
      framework: 'text',
      chapter: 'text',
      title: 'text',
      standard_reference: 'text',
      auditor_id: 'uuid',
      scheduled_for: 'timestamp',
      status: 'text',
      conducted_at: 'timestamp',
      total_criteria: 'integer',
      compliant_criteria: 'integer',
      findings: 'text',
      corrective_action_due_at: 'timestamp',
      completed_by: 'uuid',
      cancelled_at: 'timestamp',
      cancel_reason: 'text',
      created_by: 'uuid',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'quality.audit.scheduled',
    auditActionPatch: 'quality.audit.updated',
  },
  incident_reports: {
    columns: {
      tenant_id: 'uuid',
      facility_id: 'uuid',
      report_number: 'text',
      category: 'text',
      severity: 'text',
      title: 'text',
      description: 'text',
      occurred_at: 'timestamp',
      reported_at: 'timestamp',
      location: 'text',
      patient_id: 'uuid',
      reported_by: 'uuid',
      assigned_to: 'uuid',
      immediate_action: 'text',
      status: 'text',
      investigation_started_at: 'timestamp',
      action_plan: 'text',
      action_plan_due_at: 'timestamp',
      follow_up_due_at: 'timestamp',
      closed_at: 'timestamp',
      closure_note: 'text',
      voided_at: 'timestamp',
      void_reason: 'text',
      created_by: 'uuid',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'quality.incident.reported',
    auditActionPatch: 'quality.incident.updated',
  },
  clinical_indicators: {
    columns: {
      tenant_id: 'uuid',
      facility_id: 'uuid',
      code: 'text',
      name: 'text',
      category: 'text',
      unit: 'text',
      direction: 'text',
      period_start: 'text',
      period_end: 'text',
      numerator: 'integer',
      denominator: 'integer',
      target_value: 'integer',
      source_note: 'text',
      status: 'text',
      published_by: 'uuid',
      published_at: 'timestamp',
      retracted_at: 'timestamp',
      retract_reason: 'text',
      created_by: 'uuid',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'quality.indicator.recorded',
    auditActionPatch: 'quality.indicator.updated',
  },
  // Module 36 (patient feedback & grievance redressal).
  feedback_surveys: {
    columns: {
      tenant_id: 'uuid',
      facility_id: 'uuid',
      survey_number: 'text',
      patient_id: 'uuid',
      encounter_id: 'uuid',
      touchpoint: 'text',
      nps_score: 'integer',
      comment: 'text',
      recorded_at: 'timestamp',
      status: 'text',
      action_note: 'text',
      actioned_by: 'uuid',
      actioned_at: 'timestamp',
      voided_at: 'timestamp',
      void_reason: 'text',
      recorded_by: 'uuid',
      created_by: 'uuid',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'feedback.survey.recorded',
    auditActionPatch: 'feedback.survey.updated',
  },
  feedback_complaints: {
    columns: {
      tenant_id: 'uuid',
      facility_id: 'uuid',
      complaint_number: 'text',
      patient_id: 'uuid',
      complainant_name: 'text',
      complainant_contact: 'text',
      channel: 'text',
      category: 'text',
      severity: 'text',
      description: 'text',
      received_at: 'timestamp',
      routed_department_id: 'uuid',
      routed_to: 'uuid',
      routed_at: 'timestamp',
      status: 'text',
      acknowledged_at: 'timestamp',
      investigation_started_at: 'timestamp',
      resolved_at: 'timestamp',
      resolved_by: 'uuid',
      resolution_summary: 'text',
      closed_at: 'timestamp',
      closure_note: 'text',
      dismissed_at: 'timestamp',
      dismiss_reason: 'text',
      voided_at: 'timestamp',
      void_reason: 'text',
      logged_by: 'uuid',
      created_by: 'uuid',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'feedback.complaint.logged',
    auditActionPatch: 'feedback.complaint.updated',
  },
  complaint_routing_events: {
    columns: {
      tenant_id: 'uuid',
      complaint_id: 'uuid',
      event_type: 'text',
      from_department_id: 'uuid',
      to_department_id: 'uuid',
      assigned_to: 'uuid',
      note: 'text',
      occurred_at: 'timestamp',
      recorded_by: 'uuid',
      created_at: 'timestamp',
    },
    operations: ['upsert'],
    auditActionUpsert: 'feedback.routing.appended',
  },
  // Module 37 (visitor & pass security).
  ward_visiting_windows: {
    columns: {
      tenant_id: 'uuid',
      facility_id: 'uuid',
      ward_id: 'uuid',
      day_of_week: 'integer',
      starts_minute: 'integer',
      ends_minute: 'integer',
      max_visitors: 'integer',
      allows_children: 'boolean',
      status: 'text',
      created_by: 'uuid',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'visitor.window.set',
    auditActionPatch: 'visitor.window.updated',
  },
  visitor_registrations: {
    columns: {
      tenant_id: 'uuid',
      facility_id: 'uuid',
      registration_number: 'text',
      full_name: 'text',
      phone: 'text',
      sex: 'text',
      age_years: 'integer',
      id_document_type: 'text',
      id_document_number: 'text',
      relationship: 'text',
      purpose: 'text',
      patient_id: 'uuid',
      ward_id: 'uuid',
      registered_at: 'timestamp',
      status: 'text',
      checked_in_at: 'timestamp',
      checked_out_at: 'timestamp',
      refused_at: 'timestamp',
      refuse_reason: 'text',
      voided_at: 'timestamp',
      void_reason: 'text',
      registered_by: 'uuid',
      created_by: 'uuid',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'visitor.registered',
    auditActionPatch: 'visitor.updated',
  },
  visitor_passes: {
    columns: {
      tenant_id: 'uuid',
      facility_id: 'uuid',
      registration_id: 'uuid',
      badge_number: 'text',
      access_scope: 'text',
      escort_count: 'integer',
      valid_from: 'timestamp',
      valid_until: 'timestamp',
      status: 'text',
      activated_at: 'timestamp',
      returned_at: 'timestamp',
      revoked_at: 'timestamp',
      revoke_reason: 'text',
      issued_by: 'uuid',
      created_by: 'uuid',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'visitor.pass.issued',
    auditActionPatch: 'visitor.pass.updated',
  },
  visitor_badge_prints: {
    columns: {
      tenant_id: 'uuid',
      pass_id: 'uuid',
      badge_number: 'text',
      print_ordinal: 'integer',
      printer_label: 'text',
      note: 'text',
      printed_at: 'timestamp',
      printed_by: 'uuid',
      created_at: 'timestamp',
    },
    operations: ['upsert'],
    auditActionUpsert: 'visitor.badge.printed',
  },
  // Module 38 (reports & operational analytics warehouse). The two tables the
  // client writes from a gate or a request are the catalogue and the run; the
  // export log only takes appends, because an artefact that left the building is
  // a fact about the past. Period boundaries are date-only and held as text.
  analytics_report_definitions: {
    columns: {
      tenant_id: 'uuid',
      facility_id: 'uuid',
      code: 'text',
      display_name: 'text',
      description: 'text',
      category: 'text',
      primary_source: 'text',
      grain: 'text',
      retention_days: 'integer',
      status: 'text',
      published_at: 'timestamp',
      published_by: 'uuid',
      retired_at: 'timestamp',
      created_by: 'uuid',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'analytics.definition.created',
    auditActionPatch: 'analytics.definition.updated',
  },
  analytics_rollups: {
    columns: {
      tenant_id: 'uuid',
      definition_id: 'uuid',
      facility_id: 'uuid',
      grain: 'text',
      period_start: 'text',
      period_end: 'text',
      row_count: 'integer',
      numerator: 'integer',
      denominator: 'integer',
      income_minor: 'integer',
      expenditure_minor: 'integer',
      materialised_at: 'timestamp',
      materialised_by: 'uuid',
      status: 'text',
      superseded_at: 'timestamp',
      supersede_note: 'text',
      voided_at: 'timestamp',
      void_reason: 'text',
      created_by: 'uuid',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'analytics.rollup.materialised',
    auditActionPatch: 'analytics.rollup.settled',
  },
  analytics_report_runs: {
    columns: {
      tenant_id: 'uuid',
      definition_id: 'uuid',
      facility_id: 'uuid',
      run_number: 'text',
      grain: 'text',
      period_start: 'text',
      period_end: 'text',
      filter_note: 'text',
      status: 'text',
      served_from: 'text',
      row_count: 'integer',
      requested_by: 'uuid',
      started_at: 'timestamp',
      finished_at: 'timestamp',
      failure_reason: 'text',
      cancelled_at: 'timestamp',
      cancel_reason: 'text',
      created_by: 'uuid',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'analytics.run.queued',
    auditActionPatch: 'analytics.run.updated',
  },
  analytics_exports: {
    columns: {
      tenant_id: 'uuid',
      run_id: 'uuid',
      artifact_label: 'text',
      format: 'text',
      destination: 'text',
      byte_size: 'integer',
      checksum: 'text',
      note: 'text',
      exported_at: 'timestamp',
      exported_by: 'uuid',
      created_at: 'timestamp',
    },
    operations: ['upsert'],
    auditActionUpsert: 'analytics.report.exported',
  },
  // Module 39 (master settings & AI configuration hub). Date-only windows are
  // 'text' holding YYYY-MM-DD, so a device west of UTC cannot shift a tariff's
  // first day; booleans are 'boolean', and the client stores them as integers.
  settings_profiles: {
    columns: {
      tenant_id: 'uuid',
      facility_id: 'uuid',
      hospital_name: 'text',
      timezone: 'text',
      default_locale: 'text',
      date_format: 'text',
      currency_code: 'text',
      currency_minor_units: 'integer',
      fiscal_year_start_month: 'integer',
      appointment_slot_minutes: 'integer',
      session_idle_minutes: 'integer',
      require_two_factor: 'boolean',
      version: 'integer',
      status: 'text',
      activated_at: 'timestamp',
      activated_by: 'uuid',
      superseded_at: 'timestamp',
      created_by: 'uuid',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert'],
    auditActionUpsert: 'settings.profile.activated',
  },
  branding_assets: {
    columns: {
      tenant_id: 'uuid',
      facility_id: 'uuid',
      asset_kind: 'text',
      label: 'text',
      storage_path: 'text',
      checksum: 'text',
      mime_type: 'text',
      byte_size: 'integer',
      primary_color: 'text',
      secondary_color: 'text',
      status: 'text',
      activated_at: 'timestamp',
      activated_by: 'uuid',
      superseded_at: 'timestamp',
      created_by: 'uuid',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert'],
    auditActionUpsert: 'settings.branding.activated',
  },
  department_hierarchies: {
    columns: {
      tenant_id: 'uuid',
      facility_id: 'uuid',
      parent_id: 'uuid',
      code: 'text',
      name: 'text',
      kind: 'text',
      cost_centre: 'text',
      is_billable: 'boolean',
      sort_order: 'integer',
      status: 'text',
      archived_at: 'timestamp',
      archive_reason: 'text',
      created_by: 'uuid',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert'],
    auditActionUpsert: 'settings.department.defined',
  },
  billing_tariffs: {
    columns: {
      tenant_id: 'uuid',
      facility_id: 'uuid',
      department_id: 'uuid',
      code: 'text',
      service_name: 'text',
      category: 'text',
      currency_code: 'text',
      amount_minor: 'integer',
      tax_rate_bps: 'integer',
      insurance_capable: 'boolean',
      status: 'text',
      effective_from: 'text',
      effective_to: 'text',
      approved_at: 'timestamp',
      approved_by: 'uuid',
      retired_at: 'timestamp',
      retire_reason: 'text',
      created_by: 'uuid',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert'],
    auditActionUpsert: 'settings.tariff.approved',
  },
  ai_routing_profiles: {
    columns: {
      tenant_id: 'uuid',
      facility_id: 'uuid',
      profile_code: 'text',
      display_name: 'text',
      task_kind: 'text',
      primary_model_key: 'text',
      fallback_model_key: 'text',
      temperature_bps: 'integer',
      max_output_tokens: 'integer',
      data_residency: 'text',
      redact_phi: 'boolean',
      status: 'text',
      activated_at: 'timestamp',
      activated_by: 'uuid',
      retired_at: 'timestamp',
      retire_reason: 'text',
      created_by: 'uuid',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert'],
    auditActionUpsert: 'settings.ai_profile.activated',
  },
  // Module 08 (doctor & specialist directory).
  practitioner_profiles: {
    columns: {
      tenant_id: 'uuid',
      user_id: 'uuid',
      facility_id: 'uuid',
      department_id: 'uuid',
      specialty: 'text',
      sub_specialty: 'text',
      credentials: 'text',
      registration_no: 'text',
      years_experience: 'integer',
      consultation_room_id: 'uuid',
      accepting_referrals: 'boolean',
      status: 'text',
      retired_by: 'uuid',
      retired_at: 'timestamp',
      retirement_reason: 'text',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'directory.practitioner.registered',
    auditActionPatch: 'directory.practitioner.updated',
  },
  practitioner_on_calls: {
    columns: {
      tenant_id: 'uuid',
      practitioner_id: 'uuid',
      rotation_type: 'text',
      starts_at: 'timestamp',
      ends_at: 'timestamp',
      location: 'text',
      contact_note: 'text',
      recorded_by: 'uuid',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'directory.practitioner.on_call.recorded',
    auditActionPatch: 'directory.practitioner.on_call.updated',
  },
  discharge_ai_summaries: {
    columns: {
      tenant_id: 'uuid',
      discharge_id: 'uuid',
      model_id: 'text',
      summary_text: 'text',
      status: 'text',
      safety_decision: 'text',
      requested_by: 'uuid',
      reviewed_by: 'uuid',
      reviewed_at: 'timestamp',
      rejection_reason: 'text',
      created_at: 'timestamp',
      updated_at: 'timestamp',
    },
    operations: ['upsert', 'patch'],
    auditActionUpsert: 'discharge.summary.generated',
    auditActionPatch: 'discharge.summary.reviewed',
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
      device_id: typeof m.device_id === 'string' ? m.device_id : undefined,
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
        if (typeof value === 'boolean') break
        if (typeof value === 'number' && (value === 0 || value === 1)) {
          clean[key] = value !== 0
          continue
        }
        return { ok: false, error: `column "${key}" must be a boolean` }
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
      //
      // payload_digest attests the contents: a canonical-JSON SHA-256 over the
      // mutation's identity and data, so the ledger can later prove what was
      // asked rather than merely which key it arrived under.
      const { error: ledgerError } = await ctx.supabaseAdmin.from('mutations').insert({
        id: m.id,
        tenant_id: tenantId,
        user_id: userId,
        device_id: resolveDeviceId(req, m),
        operation: m.operation,
        resource_type: m.table,
        resource_id: m.row_id,
        idempotency_key: m.idempotency_key,
        client_created_at: m.client_created_at,
        origin: m.origin,
        payload_digest: await sha256Hex(
          canonicalJson({
            id: m.id,
            operation: m.operation,
            table: m.table,
            row_id: m.row_id,
            idempotency_key: m.idempotency_key,
            origin: m.origin,
            client_created_at: m.client_created_at,
            conflict_policy: m.conflict_policy ?? null,
            data: m.data,
          }),
        ),
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
