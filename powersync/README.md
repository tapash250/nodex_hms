# PowerSync instance configuration for NODEX Enterprise HMS

This directory holds the PowerSync-side configuration that does **not** live in
the Supabase database: sync rules and the operational setup checklist.

There is deliberately no instance provisioned yet. When you create one:

1. Create the instance in the PowerSync dashboard, choosing the Supabase
   integration and this project.
2. Paste `sync-rules.yaml` into the instance's sync rules editor and deploy.
3. Complete the reader-role setup in `SETUP.md` **before** first client connect.
4. Set `NODEX_POWERSYNC_URL` in CI secrets and build defines to the instance URL.

## Why sync rules are versioned here

Sync streams are the Tier 2 security boundary: they define what data a device is
allowed to hold offline. They must mirror the same tenant/role/assignment
policy that the PostgreSQL RLS helpers enforce, and they are reviewed like
code because a mistake here replicates data to a device that must never have it.

The rules below derive every parameter from the Supabase JWT the client presents
(`request.user_id()`), never from client-supplied query parameters. A device
cannot ask for another ward's rows; it can only be itself.

## Scope model

Buckets mirror the membership graph in `public.memberships`:

| Bucket | Rows | Guard |
|---|---|---|
| `tenant_master_data` | tenants, facilities, departments, wards, roles, permissions, role_permissions, app directory within tenant | `request.user_id()` must hold any active membership in the tenant |
| `membership_self` | the caller's own memberships and app_users row | `user_id = request.user_id()` |
| `device_self` | the caller's own device registrations and sync cursors | `assigned_user_id = request.user_id()` |
| `ai_configuration` | model registry, routing policies, deployment profiles | read-only global configuration, no PHI, no credentials |
| `audit_self` | audit rows the caller authored | `actor_id = request.user_id()` |

Clinical buckets arrive per-module in Phase 2 with the same review: each
module's stream must reproduce the scope its RLS helpers enforce, and the
acceptance test inspects the local database, not the UI. Defined so far:
`mpi_patients` (Module 10), `emr_encounters` (Module 16), `lab_workflows`
(Module 17), `rx_pharmacy` (Module 25, including superseded versions and the
MAR), `appt_schedule` (Module 07), `ward_census` (Module 11, beds with active
assignments), `billing_ledger` (Module 31, invoices, lines, payments, refunds),
`inventory_stock` (Module 13, items, locations, batches, movements);
discharges (Module 23) travel inside `emr_encounters` with their encounter.
Added: `er_triage` (Module 05, triage assessments and ER
visits), `icu_census` (Module 06, ICU beds, vitals, handover, ventilator),
`blood_bank` (Module 26, transfusion requests, blood units, transfusions),
`operation_theatre` (Module 19, bookings, pre-op, anesthesia, procedure and
post-op records), `radiology` (Module 18, imaging orders, studies and
reports), `physiotherapy` (Module 20, sessions, exercise regimens and
recovery notes), `nutrition` (Module 21, assessments, seven-day meal plans,
day menus and intake logs). Remaining: the rest of the 54-module scope.

## Upload path

Sync rules only govern downloads. Uploads flow through the authorized backend
mutation path (`supabase/functions/mutation-handler`), which applies domain
validation, writes the audit event and commits — never through the sync rules.

See `SETUP.md` for the reader-role grant matrix and the RLS interaction notes.
