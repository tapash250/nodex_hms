# NODEX Phase 4 remediation report

Status: development deployment complete through the PowerSync service and sync
config. Migrations, the synthetic development seed, the live trigger/expiry
tests, the Edge Function deployment and the handler end-to-end tests are
complete. `SOURCE_DB_SETUP.sql` created the source role and publication, and the
`jp` instance `6ae4764ab0047aeb6df81fd9` is provisioned with the full 50-stream
configuration over 146 tables. The live PowerSync client checklist remains
pending. No production system was touched.

Date: 2026-10-30.

> Coverage update: the live instance now serves the full-coverage
> 50-stream/146-table configuration. The repository contains
> `sync-config.yaml` and migration
> `20260918200001_expand_powersync_full_coverage.sql`, both applied to the
> development project. Initial replication is complete, the slot is active and
> lag is zero. The live client checklist is still pending. See `DEPLOYMENT.md`.

## 1. Scope

This work closes the gaps found before a development deployment:

- every mutation that touches a patient or a patient-linked clinical record is
  authorized in the same PostgreSQL transaction as the write;
- membership expiry is a WAL event, with an exact-instant write guard;
- a client cannot extend or re-grant its own membership;
- the PowerSync target region, connection path and TLS mode are explicit;
- the source database setup publishes only the required tables and uses the
  minimum replica identity;
- synthetic tests cover authorization, tenant isolation, assignment scope,
  spoofing, expiry, revocation and idempotency;
- a development seed exists but is opt-in and is not a migration.

The target was the development project `neoernavfntxsotwvmwq`
(`ap-northeast-1`). No production project, role, publication, table, policy or
row was changed.

## 2. Deployment executed

| Step | Result |
| --- | --- |
| Supabase Cron (`pg_cron`) | enabled, version `1.6.4` |
| `20260918160000_phase4_patient_mutation_authorization` | applied and recorded |
| `20260918170000_phase4_membership_expiry` | applied and recorded |
| `20260918180000_phase4_permission_catalog_reconciliation` | applied and recorded |
| `20260918190000_phase4_membership_expiry_clock` | applied and recorded |
| `20260918200000_phase4_membership_updated_at_clock` | applied and recorded |
| `nodex-expire-memberships` cron job | active, every minute; 9 runs recorded, last status `succeeded` |
| `powersync/dev-seed.sql` | applied to the development project |
| `powersync/tests/authorization.sql` | all assertions passed; transaction rolled back |
| `mutation-handler` Edge Function | deployed, version 13, `ACTIVE`, `verify_jwt=true` |
| Handler end-to-end test (seeded doctor) | `applied`; repeat returned `already_applied` |
| Handler negative test (seeded billing user) | `rejected` / `forbidden` |
| `powersync/SOURCE_DB_SETUP.sql` | applied: role `powersync_role`, 18 grants, 18-table publication, replica identity `DEFAULT` |
| PowerSync `jp` instance | created `6ae4764ab0047aeb6df81fd9`, region `jp`, linked |
| `powersync validate` | all three checks pass |
| `powersync deploy --dry-run` | pass; sync config matches, service config reports a residual secret/JWKS diff |
| `powersync deploy service-config` | deployed; connection `connected`, initial replication done |
| `powersync deploy sync-config` | deployed; 7 streams active |
| GitHub push | pushed to `origin/main` at `34fd25e` |

The development project now contains 11 synthetic `auth.users`, 11
`app_users`, 10 memberships, 4 patients, 4 clinical encounters, 5 doctor
assignments and 4 devices from the opt-in seed. These are development fixtures,
not production identities.

## 3. Changed files

| Path | State | Purpose |
| --- | --- | --- |
| `nodex_hms/supabase/migrations/20260918160000_phase4_patient_mutation_authorization.sql` | committed, applied | 83-table scope catalogue, patient resolver, chain consistency, FK tenant guard, transactional trigger |
| `nodex_hms/supabase/migrations/20260918170000_phase4_membership_expiry.sql` | committed, applied | `expired` status, pg_cron sweep, self-escalation guard, exact-instant helper |
| `nodex_hms/supabase/migrations/20260918180000_phase4_permission_catalog_reconciliation.sql` | committed, applied | inserts missing Phase 2/3 permission rows and role grants; idempotent |
| `nodex_hms/supabase/migrations/20260918190000_phase4_membership_expiry_clock.sql` | committed, applied | wall-clock sweep predicate and `updated_at` |
| `nodex_hms/supabase/migrations/20260918200000_phase4_membership_updated_at_clock.sql` | committed, applied | membership-specific `updated_at` trigger using `clock_timestamp()` |
| `nodex_hms/supabase/functions/mutation-handler/index.ts` | committed, deployed | tenant resolution, membership validity, device checks, header forwarding, error classification |
| `powersync/sync-config.yaml` | reviewed, deployed | 7 streams, tenant-aware scope CTEs, catalog synthetic IDs, exclusions |
| `powersync/service.yaml` | reviewed, deployed | `jp` region, direct host, `verify-full`, Supabase auth |
| `powersync/SOURCE_DB_SETUP.sql` | reviewed, executed | 18 grants, 18 published tables, `REPLICA IDENTITY DEFAULT`, verification |
| `powersync/dev-seed.sql` | executed on development | opt-in deterministic development fixtures |
| `powersync/tests/authorization.sql` | executed on development | live-Postgres trigger and membership integration tests |
| `powersync/tests/test_config_static.py` | passing | offline static invariants |
| `powersync/tests/test_sync_scope.py` | passing | SQLite simulation of every stream query |
| `powersync/tests/README.md` | reviewed | test order, synthetic/live boundary, device limitation |
| `powersync/DEPLOYMENT.md` | reviewed | runbook, preconditions, limitations, execution status |
| `powersync/.env.example` | reviewed | placeholder secrets only |
| `powersync/cli.yaml` | linked | `jp` development instance `6ae4764ab0047aeb6df81fd9` |

`powersync/` is outside the `nodex_hms` git repository, so those files are not
in a commit. The handler and the first two migrations are in commit `d74b734`;
the three follow-up migrations are in commit `7db61da`; the handler context fix
is in commit `34fd25e`. Local `main` and `origin/main` both point at `34fd25e`.

## 4. What changed

### Phase A: transactional patient authorization

The trigger `nodex.tg_patient_mutation_guard` runs `BEFORE INSERT OR UPDATE` on
83 patient-linked tables. It:

- reads the actor from `auth.uid()`, never from the payload;
- locks the actor's current membership, the role grant, the role catalogue,
  the device, the patient, the encounter, the doctor assignment, the bed
  assignment and the ICU occupancy row `FOR SHARE`;
- resolves the patient through the relational chain, not from the payload
  alone;
- rejects a row whose direct patient differs from a patient reachable through
  any single-column foreign-key parent;
- rejects a foreign-key parent in another tenant, including an `app_users`
  parent that does not hold a current membership;
- requires a table write permission that matches the RLS write gate;
- applies the domain policy by role class:
  - clinical: active assignment, attending/creating encounter, or current
    intake;
  - nursing: active bed or ICU occupancy in a covered ward;
  - workflow: the table permission from a workflow membership;
  - patient: an unrevoked portal link;
  - administrative: tenant-wide with `tenant.administer`;
- checks `valid_from`/`valid_until` with `clock_timestamp()`, so a write is
  refused at the exact expiry instant;
- rejects a supplied device that is invalid, suspended, revoked, owned by
  another user or in another tenant;
- keeps creation attribution columns immutable after insert, including
  `assessed_by`.

The trigger is the only bypass for `service_role`. The handler uses the
caller-scoped client, so a client request always reaches the guard.

The handler resolves the row tenant (an upsert must name it; a patch reads it
from the visible row), checks a current membership, validates the device and
header/body agreement, forwards `x-device-id` to PostgREST before the write, and
maps `42501`/`28000`/`NODEX:` to `forbidden` and `23P01`/`23505` to `conflict`.

### Phase B: deterministic expiry

`nodex.expire_memberships()` flips `active` to `expired` when `valid_until` has
passed. The update emits WAL, so PowerSync evicts the buckets on the next
checkpoint. `pg_cron` runs it every minute.

`clock_timestamp()` is used for the sweep predicate and for `updated_at`.
`now()` is frozen at transaction start; a sweep in the same transaction as
another membership write could otherwise leave `updated_at` unchanged and emit
no usable row version. A membership-specific trigger
`nodex.tg_membership_set_updated_at()` uses the wall clock; the rest of the
schema keeps the shared `now()` trigger.

`nodex.tg_membership_self_guard` refuses a self-insert and any self-update of
role, tenant, scope, status or validity. It also makes `user_id` immutable and
refuses to reactivate a window whose `valid_until` is already past. Renewal is a
second-administrator action.

### Phase C: region and connectivity

`service.yaml` targets `region: jp` (AWS `ap-northeast-1`, Tokyo) and keeps the
direct host `db.neoernavfntxsotwvmwq.supabase.co:5432`. No Supavisor or
transaction-mode pooler is used. TLS is `sslmode: verify-full`. The direct host
resolves IPv6-only; the documented PowerSync Cloud IPv6 egress range is
`2602:817::/44`. If the deployed instance cannot reach it, use the Supabase IPv4
add-on, not a pooler.

The development instance `6ae4764ab0047aeb6df81fd9` is deployed in `jp`, the
same region as Supabase. The previous `us` instance was unprovisioned and was
destroyed with approval to free the plan slot; it is not reused.

### Phase D: source database and replication

`SOURCE_DB_SETUP.sql` is review-only and has not been executed. It creates one
login role, `powersync_role`, with `replication` and `bypassrls`, and grants
`SELECT` on exactly 18 tables. It sets `REPLICA IDENTITY DEFAULT` on all 18,
including `role_permissions`, whose primary key is
`(role_key, permission_key)`. It creates the `powersync` publication for the
same 18 tables and verifies `wal_level`, replication slots, role flags,
publication membership and replica identity.

The source database currently has `wal_level=logical`, no `powersync_role` and
no `powersync` publication. The script needs a generated password; the
repository keeps only the placeholder.

The sync config publishes 7 streams: `identity`, `tenant_master`, `patients`,
`patient_clinical`, `doctor_assignments`, `catalog`, `ward_census`. Scope CTEs
return `(tenant_id, patient_id)` and every stream uses composite equality joins,
so a same-id patient in another tenant cannot leak. The catalog stream
synthesizes `id` from `key` for `roles` and `permissions`, and from
`role_key || ':' || permission_key` for `role_permissions`.

Deliberate exclusions: appointments, prescriptions/lab/imaging workflow queues,
the staff directory, audit/mutations/conflicts, portal and AI tables. They are
fetched online or reviewed server-side.

### Phase E: seed and tests

`dev-seed.sql` refuses to run without `set nodex.dev_seed = 'on'`. It runs in one
transaction with a transaction-local `service_role` claim, uses deterministic
IDs and idempotent inserts, and includes staff, portal user, patients, beds,
encounters, a triage assessment, assignments, devices, prescriptions and billing
rows. It does not create passwords and must not be used to sign in.

`tests/authorization.sql` runs as `postgres`, starts a transaction and rolls
back. It covers assigned/unassigned doctors, registration, pre-assignment
triage, unauthorized encounters, parent-child spoofing, nursing ward scope,
device revocation, suspended/expired memberships, revoked grants, self-grant and
self-extension, cross-tenant writes, merge dual authorization, portal denial,
appointment conflict and the expiry sweep. It does not exercise RLS because
`postgres` bypasses it.

## 5. Live validation results

Applied on the development project:

| Check | Result |
| --- | --- |
| Migration history | five Phase 4 migrations recorded through `20260918200000` |
| Scope catalogue | 83 rules, 83 guard triggers, 0 rules without a trigger |
| Guard helpers | 5 functions present |
| Permission catalogue | 146 permissions; 0 rule permissions missing |
| `pg_cron` | installed `1.6.4`; job active every minute; 9 runs recorded, last status `succeeded` |
| Seed | 11 auth users, 11 app users, 10 memberships, 4 patients, 4 encounters, 5 assignments, 4 devices |
| `authorization.sql` | all assertions passed; transaction rolled back |
| Edge Function | `mutation-handler` version 13, `ACTIVE`, `verify_jwt=true` |
| Handler end-to-end (seeded doctor) | `applied`, ledger and audit one row each; repeat `already_applied`, no duplicate rows |
| Handler negative (seeded billing user) | `rejected` / `forbidden` (device not authorized) |
| Source role and publication | `powersync_role` login/replication/bypassrls; 18/18 select grants; 18/18 published tables; 18/18 replica identity `DEFAULT` |
| PowerSync instance | `6ae4764ab0047aeb6df81fd9`, region `jp`, `is_provisioned: true` |
| PowerSync replication | connection `connected`; initial replication done; 18 tables with `used_for_replication: yes` |
| `powersync validate` | configuration, connections and sync config all pass |
| `powersync deploy --dry-run` | exit 0; sync config matches; service config reports a residual secret/JWKS diff |
| `powersync deploy service-config` | completed successfully |
| `powersync deploy sync-config` | completed successfully; 7 streams active |

Offline checks, all passing after the follow-up migrations:

| Check | Result |
| --- | --- |
| `python3 powersync/tests/test_config_static.py` | 8/8 checks pass |
| `python3 powersync/tests/test_sync_scope.py` | 60 assertions pass |
| `node /tmp/opencode/validate-sync.mjs` | `sync config SQL: 0 errors` |
| `pglast` parse, 96 SQL files | pass; the psql meta-command in the test is stripped |
| YAML schema validation, both configs | pass with Draft 7 and an `!env` loader |
| `esbuild` bundle of the handler | pass, 98.4 kB |

The live test was executed through the Supabase SQL runner with the single psql
meta-command (`\set ON_ERROR_STOP on`) removed. The script's `begin;` and
`rollback;` were preserved. Expected failures were caught in subtransactions;
the run ended with the `TESTS_PASSED` marker.

Not run:

| Check | Why |
| --- | --- |
| Host-side IPv6 TLS connection | no local IPv6 route; the same connection passes from PowerSync Cloud |
| Live-service checklist in `tests/README.md` | needs a real PowerSync client to exercise sync, upload and revocation |
| Real client sync/upload round trip | no application client in this environment |

## 6. Findings during live execution

1. **Permission catalogue drift.** The remote development database had been
   provisioned from an earlier revision of
   `20260905161942_phase1_seed_roles_and_permissions.sql`. Twenty-eight
   permission keys referenced by the Phase 4 rules did not exist, including
   `triage.write`, `er.visit.write` and the ICU/OT/imaging keys. The first live
   test failed with `NODEX: missing write permission for triage_assessments`.
   Migration `20260918180000` inserts only the 32 missing catalogue rows and the
   intended role grants, is idempotent, and leaves existing rows untouched.
   After it was applied, the rule-permission gap was zero and the full test
   passed. This is a forward repair; the already-applied Phase 1 migration was
   not edited or replayed.

2. **Cron/test race on the expiry fixture.** The one-minute sweep could expire
   the seeded expired-membership row before the test reached its sweep
   assertion. The test now resets that fixture inside its transaction. The
   sweep also uses `clock_timestamp()` and a membership-specific `updated_at`
   trigger, so the WAL row version advances even when the test transaction has
   already touched the row.

3. **Handler deployment and authentication.** The handler was deployed as
   version 12, then as version 13 after the request context changed. Version 13
   reads the actor from `ctx.userClaims?.id`; the earlier code read `ctx.claims.sub`,
   which is undefined in `@supabase/server` 1.x and produced a 500. Version 13 is
   `ACTIVE` with JWT verification preserved.

4. **Handler end-to-end result.** A password grant for the seeded doctor
   succeeded after the seed normalised the GoTrue token columns. The handler
   applied one synthetic patient patch (`160bc1fb-c655-416f-b77c-b3a8851db596`):
   `public.mutations` and `public.audit_events` each hold exactly one row. A
   repeat of the same mutation id and idempotency key returned `already_applied`
   with no extra rows. The same request as the seeded billing user returned
   `rejected` / `forbidden`; the trigger refused the device binding. The patient
   phone was restored to `+8801700000001` afterwards.

5. **Seed auth rows were not GoTrue-safe.** The seed inserted `auth.users` rows
   with NULL token columns. GoTrue scans those columns into Go strings, so the
   password grant failed with `converting NULL to string is unsupported`.
   `dev-seed.sql` now sets `confirmation_token`, `recovery_token`,
   `email_change*`, `phone_change*` and `reauthentication_token` to empty
   strings, and repairs rows from an earlier seed run. The same normalisation
   was applied to the existing development users.

6. **Plan limit forced a dev-instance replacement.** The org already held two
   instances, and the Free/active plan refused a third with
   `PLAN_LIMIT_REACHED`. The old `Development` instance was in `us` and
   unprovisioned; its region is immutable. With explicit approval it was
   destroyed and replaced by `6ae4764ab0047aeb6df81fd9` in `jp`. The
   `Production` instance was not touched.

7. **Residual service-config diff.** A dry-run after the service deploy still
   reports changes in `client_auth` and `replication`. The deployed config
   returns `client_auth.jwks.keys: []` and a password `secret_ref`, which the
   local file does not round-trip. The sync config reports no diff, the
   connection is `connected`, and initial replication is done. Treat the
   residual diff as a secret/JWKS representation artifact, not a failed deploy.

## 7. Remaining deployment steps

```text
1. Run the live-service checklist in powersync/tests/README.md with a real
   PowerSync client (sync scope, upload, device revocation, expiry checkpoint).
2. Rotate POWERSYNC_DATABASE_PASSWORD after this session and redeploy the
   service config.
3. Keep the client URL set to
   https://6ae4764ab0047aeb6df81fd9.powersync.journeyapps.com.
```

The `us` instance is gone. Do not recreate it. Do not deploy `service.yaml` to
the `Production` instance. Do not run the seed or the authorization tests
against production. Do not paste the migrations into the production SQL editor
as a shortcut.

## 8. Remaining risks and limitations

1. Device binding is optional. The handler and trigger reject a supplied device
   that is invalid, suspended, revoked, owned by another user or in another
   tenant, but a caller that omits `x-device-id` is treated as an unbound
   mutation. A revoked device can keep uploading by dropping the header.
   Closing this needs a device-bound PowerSync token and a mandatory device
   claim on every mutation.
2. Device revocation cannot remove rows already synced to a device without a
   device-bound token. The next checkpoint removes scope only after the
   server-side state changes and the client reconnects.
3. An offline client keeps the last synced rows until it reconnects and receives
   the removal checkpoint. Server writes are refused at the exact expiry
   instant, but local reads can outlive the membership.
4. A future-dated membership with `status = 'active'` replicates its tenant
   scope before `valid_from`, because Sync Streams cannot compare time. Use a
   non-active status until the start time.
5. Facility/ward narrowing applies only to rows that carry `facility_id` or
   `ward_id`, and to bed/ICU rows through their bed. Tables without either
   column are tenant-scoped for a clinical role.
6. A clinician with `encounter.write` can open an initial encounter for any
   patient in the tenant by naming themselves as attending. This is the
   intentional intake exception.
7. Triage assessments and ER visits are gated by `triage.write` and
   `er.visit.write` for the whole tenant, before an assignment or bed exists.
   That is the intake exception; the patient/encounter chain is still checked.
8. `medical_officer` holds `clinical.dashboard.manage`, so a medical officer can
   create a dashboard assignment for themselves. The insert is the trusted act
   that creates the relationship; requiring an existing assignment would be
   circular. Treat self-assignment as a policy assumption, not a technical
   control.
9. Bed and ICU occupancy is gated by the table permission plus ward scope, not
   by a pre-existing patient assignment, because occupancy creates the location
   relationship. A ward-scoped user with `icu.bed.assign` can change
   `icu_beds.current_patient_id`.
10. Creation attribution is immutable after insert, but the trigger does not
    bind `created_by`/`recorded_by` to the authenticated actor on insert. A
    caller with the table permission can name a different current member. The
    ledger and audit row always name the verified actor, so the authoritative
    trail is independent of the row column. Shared-device drafting is the reason
    this is not rejected outright.
11. The patient portal self-service branch is latent: the patient role holds
    only `portal.access`, and no guarded table uses a portal-scoped write
    permission yet. A portal write needs a new permission and an RLS policy.
12. The Supabase direct host is IPv6-only. The documented PowerSync Cloud egress
    range is `2602:817::/44`. If the instance cannot reach it, use the Supabase
    IPv4 add-on; do not switch to transaction-mode pooling.
13. The development instance and Supabase project are both in
    `ap-northeast-1`; the replication path stays in-region.
14. The source database role and publication are created and the deployed
    connection is `connected`; initial replication is done.
15. The live service path (RLS through PostgREST, real sync/upload, device
    revocation checkpoint) has not been exercised. The trigger test runs as
    `postgres` and bypasses RLS.
16. The GitHub push is complete; `origin/main` is at `34fd25e`.

## 9. Redacted configuration

```yaml
# powersync/service.yaml (redacted)
_type: cloud
name: Development
region: jp
replication:
  connections:
    - type: postgresql
      uri: !env PS_DATABASE_URI
      password:
        secret: !env POWERSYNC_DATABASE_PASSWORD
      sslmode: verify-full
client_auth:
  supabase: true
```

The resolved URI is
`postgresql://powersync_role@db.neoernavfntxsotwvmwq.supabase.co:5432/postgres`
and contains no password. `PS_ADMIN_TOKEN` and `POWERSYNC_DATABASE_PASSWORD` are
placeholders in `.env.example`. The database password lives only in the
untracked `powersync/.env` (mode `600`). The PowerSync Cloud token was revoked
after the deploy and removed from `.env`. The client URL is
`https://6ae4764ab0047aeb6df81fd9.powersync.journeyapps.com`.

Streams: `identity`, `tenant_master`, `patients`, `patient_clinical`,
`doctor_assignments`, `catalog`, `ward_census`.

Published tables: `app_users`, `memberships`, `devices`, `tenants`,
`facilities`, `departments`, `wards`, `patients`, `patient_allergies`,
`clinical_encounters`, `clinical_problems`, `encounter_amendments`,
`doctor_assignments`, `beds`, `bed_assignments`, `roles`, `permissions`,
`role_permissions`.

## 10. Blockers

- No local IPv6 route; the direct Supabase TLS path cannot be tested from this
  host. The same connection passes from PowerSync Cloud.
- No live PowerSync client, so the live-service checklist and a real
  sync/upload round trip remain pending.
- The PowerSync Cloud token and GitHub PAT were revoked after the deploy. A new
  `PS_ADMIN_TOKEN` is needed for further Cloud commands; a new GitHub
  credential is needed for pushes.
- The generated development database password is temporary and must be rotated
  after this session; redeploy the service config after rotation.

## 11. Execution confirmation

The changes in this report were applied only to the development Supabase project
`neoernavfntxsotwvmwq` and the development PowerSync Cloud instance
`6ae4764ab0047aeb6df81fd9`. No production system, role, publication, table,
policy or row was changed. The seed contains synthetic development identities
only. The temporary development database password remains in the untracked
`powersync/.env` with mode `600`; no secret was committed to git. The revoked
PowerSync token was removed from `.env`, and the revoked GitHub token was
removed from the local `gh` configuration. The database password is scheduled
for rotation.
