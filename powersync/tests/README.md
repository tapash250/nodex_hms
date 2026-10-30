# Nodex PowerSync and authorization tests

This directory contains four layers of validation. They are not
interchangeable. The first two run offline; the last two need a running
development service.

| Layer | File | Needs | Covers |
| --- | --- | --- | --- |
| Static configuration | `test_config_static.py` | Python 3 + PyYAML | Stream count, table lists, grants, publication, replica identity, region/TLS, migration and handler invariants, seed guard |
| Synthetic scope | `test_sync_scope.py` | Python 3 + PyYAML | Every stream query against an in-memory SQLite fixture with synthetic tenants, users, patients, beds and assignments |
| Trigger integration | `authorization.sql` | Dedicated development PostgreSQL with migrations and `dev-seed.sql` applied | Transactional patient-scope trigger, device checks, membership status/expiry, self-escalation guard, parent-child spoofing, role-grant revocation, conflicts |
| Live service | manual checklist below | Deployed Supabase project, PowerSync instance and client | RLS, PostgREST header forwarding, real sync/upload, device revocation, membership expiry checkpoint |

## 1. Offline checks

Run from the repository root:

```bash
python3 powersync/tests/test_config_static.py
python3 powersync/tests/test_sync_scope.py
node /tmp/opencode/validate-sync.mjs powersync/sync-config.yaml
```

The last command uses the installed `@powersync/service-sync-rules` compiler
with a synthetic schema. It must print `sync config SQL: 0 errors`. The
compiler does not connect to a database.

YAML schema validation uses the schemas referenced in each config file. The
service config uses the `!env` tag, so a loader must resolve that tag before
validation.

These checks do not prove PostgreSQL behaviour. They do not execute PL/pgSQL.

## 2. Development database setup

Never run this section against production. Use a dedicated development
project.

```text
1. Enable Supabase Cron (pg_cron) in the dashboard.
2. Apply migrations through 20260918200000 in timestamp order:
     20260918160000_phase4_patient_mutation_authorization.sql
     20260918170000_phase4_membership_expiry.sql
     20260918180000_phase4_permission_catalog_reconciliation.sql
     20260918190000_phase4_membership_expiry_clock.sql
     20260918200000_phase4_membership_updated_at_clock.sql
3. Run powersync/SOURCE_DB_SETUP.sql once, with a generated password.
4. In one transaction:
     set nodex.dev_seed = 'on';
     \i powersync/dev-seed.sql
5. Run powersync/tests/authorization.sql as the postgres role.
```

On the development project, steps 1-5 are done. The generated `powersync_role`
password is temporary and lives only in the untracked `powersync/.env`. The live
test was run through the Supabase SQL runner with the `\set ON_ERROR_STOP on`
meta-command removed; the script's `begin;`/`rollback;` were preserved and all
assertions passed.

`SOURCE_DB_SETUP.sql` creates a login role and a publication. It is not
idempotent; inspect a partial run before rerunning.

`dev-seed.sql` refuses to run without the `nodex.dev_seed = 'on'` opt-in. It
sets a transaction-local `service_role` claim so the patient-scope trigger
treats the seed as an administrative backfill. It does not create passwords and
must not be used to sign in.

`authorization.sql` starts with `begin;` and ends with `rollback;`. It uses
`\set ON_ERROR_STOP on` and `\i`-style psql execution, so run it with `psql`,
not the Supabase SQL editor. It runs as `postgres`, which bypasses RLS, so it
tests the trigger and membership guard only. Expected failures are caught in
subtransactions and reported as `ok forbidden:` notices. A successful run ends
with:

```text
all authorization integration assertions passed
```

The test covers:

- assigned doctor succeeds; unassigned doctor fails;
- a medical officer registers a patient; a billing user without `patient.write`
  is refused;
- a triage nurse amends a pre-assignment triage assessment; a billing user
  cannot;
- encounter belonging to another patient fails;
- attending doctor succeeds on their own planned encounter;
- parent-child spoofing through an encounter, a prescription item and a payment
  allocation fails;
- ward nurse succeeds inside the ward and fails outside it;
- active device succeeds; revoked, suspended, another user's and another
  tenant's device fail;
- suspended membership and past `valid_until` fail;
- revoked `patient.write` grant fails immediately and can be restored;
- self-grant, self-extension, self-suspension and subject reassignment fail;
- a second administrator can renew and grant;
- cross-tenant patient, appointment and tenant move fail;
- a merge requires scope over both patients;
- the portal patient cannot write a staff row;
- an overlapping appointment raises SQLSTATE `23P01`;
- the expiry sweep sets `status = 'expired'` and advances `updated_at`, and a
  write after the sweep fails.

## 3. Live service checklist

Run after a development deploy, with a real client. Use synthetic development
users only.

1. Sign in as an assigned doctor. Confirm the client receives only the assigned
   patients and their clinical rows, not every patient in the tenant.
2. Sign in as a nurse. Confirm the ward census contains only the covered
   ward/facility beds and bed assignments.
3. Sign in as a billing user with `patient.read` but no clinical role. Confirm
   the patient list is tenant-scoped but clinical rows are absent.
4. Attempt a write to an unassigned patient through the normal mutation
   handler. Confirm a clean `forbidden` response and a ledger/audit row.
5. Revoke a device while the client is online. Confirm the next upload is
   rejected with a device error.
6. Suspend a membership. Confirm the next upload is rejected. Confirm the
   client removes the tenant scope after the WAL checkpoint.
7. Set `valid_until` in the past while `status` is still `active`. Confirm the
   next write is rejected before the minute sweep, then confirm the sweep
   changes `status` to `expired` and the client removes the scope.
8. Change a role's permission grant. Confirm the next sync checkpoint adds or
   removes the corresponding rows.
9. Confirm an RLS-only read outside the stream scope is still denied by
   PostgREST, so the stream is not the only boundary.
10. Confirm no production project, role, publication or table was touched.

## 4. Device revocation limitation

The handler and trigger reject a supplied device that is invalid, suspended,
revoked, assigned to another user, or in another tenant. A caller that omits
`x-device-id` is treated as an unbound mutation, so a revoked device can keep
uploading by dropping the header. Closing that gap needs a device-bound
PowerSync token and a mandatory device claim on every mutation. Device
revocation also cannot remove rows already synced to a device unless the sync
token is bound to that device; the next checkpoint removes scope only after the
server-side membership/device state changes and the client reconnects.

## 5. What is synthetic

`test_config_static.py` and `test_sync_scope.py` use synthetic fixtures only.
They do not connect to Supabase, PowerSync Cloud or a PostgreSQL server.
`authorization.sql` uses the synthetic development seed and a transaction that
rolls back. No test in this directory proves production data, production RLS or
a deployed PowerSync instance.
