# Supabase backend

The authoritative cloud system of record for NODEX Enterprise HMS.

PostgreSQL is authoritative; the encrypted PowerSync SQLite database on each
device is an operational projection of the rows that device is authorized to
hold. Row level security is the authoritative CRUD boundary, and PowerSync sync
streams define replication scope from the same authorization model.

## Applied migrations

Phase 1 established the foundation schema directly against the project. The
migration history is recorded in `supabase_migrations.schema_migrations`:

| Version | Name |
|---|---|
| 20260905155521 | `phase1_foundation_schema_and_helpers` |
| 20260905155624 | `phase1_tenancy_and_identity` |
| 20260905155707 | `phase1_users_roles_permissions` |
| 20260905155746 | `phase1_authorization_helper_functions` |
| 20260905155821 | `phase1_devices_and_offline_authorization` |
| 20260905155844 | `phase1_snapshot_revocation_guard` |
| 20260905155932 | `phase1_audit_and_clinical_events` |
| 20260905160818 | `phase1_sync_mutations_and_conflicts` |
| 20260905161314 | `phase1_ai_governance_registry` |
| 20260905161411 | `phase1_ai_execution_and_safety_records` |
| 20260905161515 | `phase1_enable_rls_and_core_policies` |
| 20260905161622 | `phase1_rls_policies_devices_audit_sync_ai` |
| 20260905161711 | `phase1_app_users_admin_field_guard` |
| 20260905161801 | `phase1_app_user_self_update_guard` |
| 20260905161834 | `phase1_dedupe_app_user_guard` |
| 20260905161942 | `phase1_seed_roles_and_permissions` |
| 20260905162031 | `phase1_seed_role_permission_grants` |
| 20260905162157 | `phase1_snapshot_issuance_rpc` |
| 20260905162531 | `phase1_revoke_anon_rpc_execute` |

### Pull them into source control

`migrations/` is intentionally empty in this repository. Run the following once
against the linked project to materialise the SQL locally, then commit it — from
that point on the schema is reproducible from source control and every further
change goes through a migration file:

```bash
supabase login
supabase link --project-ref <project-ref>
supabase db pull            # writes the current schema as a migration
supabase migration list     # confirms local and remote are in step
```

From then on, apply changes with `supabase migration new <name>` followed by
`supabase db push`. Do not edit the schema through the dashboard: the
specification prohibits uncontrolled schema changes, and an out-of-band edit
breaks the correspondence between RLS policies and sync stream definitions.

## What Phase 1 established

### Tenancy and identity

`tenants` → `facilities` → `departments` → `wards` form the scope hierarchy.
`app_users` is the authorization subject, mirroring `auth.users` with clinical
and HR attributes. `memberships` binds a user to a role within a tenant and an
optional facility, department or ward, and is the single source both RLS and sync
streams derive scope from.

### Role-based access control

`roles`, `permissions` and `role_permissions` implement the specification's role
matrix. Two permission attributes carry security weight:

- `requires_online` — the action must not execute from a cached offline
  authorization snapshot. The snapshot issuance function excludes these from the
  offline subset by construction rather than relying on client filtering.
- `risk_tier` — `high_risk` actions require backend/domain authorization beyond
  generic row-level access and always produce an audit event.

### Authorization helpers

`nodex.has_tenant_access`, `nodex.has_permission`, `nodex.has_role`,
`nodex.has_facility_access`, `nodex.has_department_access` and
`nodex.has_ward_access` are `SECURITY DEFINER` with a locked empty
`search_path`, so a membership lookup inside a policy cannot re-enter RLS and
recurse. Every policy consumes these rather than inlining its own subquery.

### Devices and offline authorization

`devices` is the enforcement point for lost or stolen device procedures:
revoking a device or setting `wipe_requested_at` stops snapshot issuance.
`authorization_snapshots` records every issued snapshot. It is append-only
except for a single permitted transition — setting `revoked_at` from the backend
path — enforced by `nodex.tg_snapshot_revocation_only`.

`public.issue_authorization_snapshot(...)` is the authorized issuance path. It
derives roles, permissions and scopes server-side from the membership graph and
never trusts client-supplied authorization input. `EXECUTE` is granted to
`authenticated` only; the `anon` grant is revoked.

### Audit and clinical events

`audit_events` is the high-risk audit envelope and `clinical_events` the
immutable per-aggregate event stream. Both block `UPDATE` and `DELETE` at the
database level through `nodex.tg_block_mutation`, so application-facing history
cannot be silently rewritten. Administrative tools query and export; they do not
edit.

### Synchronization bookkeeping

`mutations` carries a unique `(tenant_id, idempotency_key)`, which is what makes
reconnection produce exactly-once business effect for idempotent mutations.
`mutation_attempts` separates transient failures from permanent rejections.
`conflict_records.entity_policy` names the deterministic per-entity strategy
applied; there is no global last-write-wins for clinical data.

### AI governance

`ai_model_registry` encodes the governance gate as a table constraint: a model
cannot reach `approved` or `active` without `evaluation_status = 'passed'`, a
recorded `evaluation_set_revision`, and a recorded approver. A provider catalog
scan therefore cannot promote a model into clinical production.

`ai_routing_policies` holds a per-engine primary/secondary/tertiary/offline
chain — deliberately not one universal chain shared by every engine.
`ai_requests`, `ai_responses`, `ai_safety_decisions` and `ai_reviews` record
engine, policy revision, profile revision, model, provider, attempt number,
failure class, circuit state and the human review decision.

## Remaining backend work

- **PowerSync sync streams.** Not yet defined. Each stream must mirror the same
  tenant/role/assignment policy the RLS helpers implement, and must use trusted
  authentication parameters rather than client input. A record a device is not
  authorized to hold must never be replicated merely because the interface hides
  it.
- **Backend mutation path.** Clients currently write through PostgREST under
  RLS. High-risk clinical mutations need an Edge Function that applies domain
  validation, records the audit event and creates the clinical event inside one
  transaction.
- **Storage buckets.** DICOM, PDFs, scans and signatures need tenant-scoped
  buckets with short-lived signed URLs and checksum validation on upload.
- **Backup and restore.** RPO/RTO targets defined and a restore actually
  exercised, not merely documented.
