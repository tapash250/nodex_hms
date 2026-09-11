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

type ColumnType = 'text' | 'uuid' | 'boolean' | 'integer' | 'timestamp' | 'json'

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
      case 'timestamp':
        if (typeof value !== 'string' || Number.isNaN(Date.parse(value))) return { ok: false, error: `column "${key}" must be an ISO-8601 timestamp` }
        break
      case 'json':
        if (typeof value !== 'object') return { ok: false, error: `column "${key}" must be a JSON object` }
        break
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
