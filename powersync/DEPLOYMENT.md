# PowerSync deployment runbook

Status: development deployment complete through the original PowerSync service
and sync config. Five Phase 4 migrations, the synthetic seed, the live
authorization/expiry tests and the handler end-to-end tests ran on the
development project; the handler is deployed at version 13. `SOURCE_DB_SETUP.sql`
created the source role and the initial 18-table publication, and the `jp`
instance `6ae4764ab0047aeb6df81fd9` now serves the full 50-stream/146-table
configuration.

The repository now contains the full-coverage configuration: 50 streams over
146 replicated tables, plus migration
`20260918200001_expand_powersync_full_coverage.sql`, which extends the grant,
replica identity and publication to the same 146 tables. The migration is
applied to the development project (146/146 granted, published and DEFAULT
identity). The 50-stream sync config passes `powersync validate` with no
warnings and is deployed to the live instance: version 3 is active, initial
replication is done, all 146 tables report `used_for_replication: yes`, and the
replication slot is active with zero lag. The live-service client checklist
remains pending.

Validation performed:

| Check | Result |
| --- | --- |
| `powersync/tests/test_config_static.py` | pass locally: 50 streams / 146 tables / 146-table coverage migration |
| `powersync/tests/test_sync_scope.py` (SQLite scope simulation) | pass |
| `@powersync/service-sync-rules` compiler | `sync config SQL: 0 errors` |
| YAML schema validation for both configs | pass (Draft 7) |
| Migrations, seed and `tests/authorization.sql` | applied and passed on the development project |
| `mutation-handler` end-to-end and idempotency test | pass: `applied`, then `already_applied` |
| `mutation-handler` negative authorization test | pass: `rejected` / `forbidden` |
| `powersync/SOURCE_DB_SETUP.sql` | applied live: 18 initial grants, 18 published tables, replica identity `DEFAULT` |
| `20260918200001_expand_powersync_full_coverage.sql` | applied to development project: 146 grants, 146 published tables, replica identity `DEFAULT` |
| `powersync validate` | configuration, connections, sync config pass with 0 warnings |
| `powersync deploy sync-config --dry-run` | exit 0; validates the 50-stream config, nothing deployed |
| `powersync deploy service-config` | deployed; connection `connected`, slot active, zero lag |
| `powersync deploy sync-config` | deployed: 50 streams / 146 tables active; slot `powersync_6ae4764ab0047aeb6df81fd9_1_1f0b` active, zero lag |

Linked instance:

| Field | Value |
| --- | --- |
| Instance | `Development` (`6ae4764ab0047aeb6df81fd9`) |
| Linked instance region | `jp` (AWS `ap-northeast-1`, Tokyo) |
| Previous instance | `6adeb1c6501b259d0e4e6813` (`us`) destroyed with approval; it was unprovisioned |
| Supabase project | `neoernavfntxsotwvmwq` (`ap-northeast-1`) |

The `jp` instance is linked in `powersync/cli.yaml`. The old `us` instance was
unprovisioned and blocked a new instance under the plan limit; it was destroyed
with explicit approval and replaced. The `Production` instance was not touched.

## 1. Preconditions

- The reviewed sync config and service config are approved.
- Supabase Cron is enabled on the project. `pg_cron` 1.6.4 is installed and the
  `nodex-expire-memberships` job is active every minute.
- The PowerSync plan permits the `jp` region. No Free-plan region restriction is
  documented, but confirm the plan and region in the dashboard before creating
  the instance.
- The `powersync_role` password was rotated on 2026-10-30 and is stored only in
  the untracked `.env` (mode `600`). The service config was redeployed with the
  new credential; the connection is `connected` and the replication slot is
  active with zero lag.
- `powersync` CLI 0.10.2 is installed.
- A PowerSync Cloud token is available in the untracked `.env` as
  `PS_ADMIN_TOKEN`. It was revoked after the development deploy and the entry
  is now blank; obtain a new token before running further Cloud commands.
- The `jp` instance is created and linked. The old `us` instance was
  unprovisioned and was destroyed to free the plan slot.

## 2. Create the source database role and publication

Run `SOURCE_DB_SETUP.sql` as the Supabase `postgres` role, after replacing
`<GENERATED_PASSWORD>`.

The script creates:

- `powersync_role` with `REPLICATION BYPASSRLS LOGIN`.
- `SELECT` only on the 15 initially synced tables plus the global `roles`,
  `permissions` and `role_permissions` catalogue (read by stream lookups and the
  catalog stream). Migration
  `20260918200001_expand_powersync_full_coverage.sql` extends the grant to the
  remaining replicated tables, for 146 in total.
- `REPLICA IDENTITY DEFAULT` on all 18 initial tables, then on all 146 after the
  coverage migration. Every replicated table has a primary key, including the
  composite `(role_key, permission_key)` on `role_permissions`; `FULL` is
  reserved for a table with no primary key.
- A `powersync` publication limited to those 18 tables initially, then expanded
  to 146 by the coverage migration, so membership, role and permission changes
  update client scope.

The Phase 4 migrations are already applied to the development project:

```text
nodex_hms/supabase/migrations/20260918160000_phase4_patient_mutation_authorization.sql
nodex_hms/supabase/migrations/20260918170000_phase4_membership_expiry.sql
nodex_hms/supabase/migrations/20260918180000_phase4_permission_catalog_reconciliation.sql
nodex_hms/supabase/migrations/20260918190000_phase4_membership_expiry_clock.sql
nodex_hms/supabase/migrations/20260918200000_phase4_membership_updated_at_clock.sql
nodex_hms/supabase/migrations/20260918200001_expand_powersync_full_coverage.sql
```

The first installs the transactional patient-scope trigger; the second adds
`expired` status, the pg_cron sweep and the self-escalation guard. The third
repairs the permission catalogue drift found by the live test. The next two use
the wall clock for the sweep and for `memberships.updated_at`. The final
migration extends SELECT, REPLICA IDENTITY DEFAULT and the `powersync`
publication from 18 to 146 tables. Apply them through the normal Supabase
migration path, in timestamp order. Do not paste them into the production SQL
editor as a shortcut.

### 2a. Test order

Run only against a dedicated development project. Never run the seed or the
authorization tests against production.

```text
1. enable Supabase Cron (pg_cron)                                  [done]
2. apply migrations through 20260918200000                         [done]
3. run powersync/SOURCE_DB_SETUP.sql once, with the real password [done]
4. apply 20260918200001_expand_powersync_full_coverage.sql         [done]
5. set nodex.dev_seed = 'on'; run powersync/dev-seed.sql           [done]
6. run powersync/tests/authorization.sql as postgres               [done, all passed]
7. run the live-service checklist in powersync/tests/README.md     [pending: no client]
8. run powersync validate, then both dry-runs, then deploy         [done: 50-stream config live]
```

`tests/authorization.sql` exercises the trigger and the membership guard, not
RLS. The live-service checklist covers RLS, PostgREST header forwarding, the
actual PowerSync sync/upload path, and device revocation. `tests/README.md`
states which tests are synthetic and which require a running service.

`SOURCE_DB_SETUP.sql` is a one-time script: `create role` and
`create publication` are not idempotent. If it fails partway, inspect the
existing role/publication before rerunning; do not drop a publication that is
already serving replication.

## 3. Load the environment

```bash
cd /root/opencode-workspace/Nodex
set -a; . powersync/.env; set +a
```

Confirm the secret is present without printing it:

```bash
test -n "$PS_DATABASE_URI" && test -n "$POWERSYNC_DATABASE_PASSWORD" && echo ok
```

## 4. Authenticate

```bash
powersync login
# or: export PS_ADMIN_TOKEN=...
powersync fetch instances
```

## 5. Validate before any deploy

```bash
powersync validate --directory=powersync --output=human
```

This runs three checks: local configuration schema, the source database
connection (including the `powersync` publication and replication privileges),
and the sync config against the linked instance.

The linked instance is in `jp`, matching the Supabase project. The source
connection check covers the `powersync` publication and the `powersync_role`
replication privileges. Validation also checks the sync config against the
linked instance.

Do not deploy `service.yaml` to the `Production` instance; region and database
target differ.

## 6. Dry-run both deploys

```bash
powersync deploy service-config --directory=powersync --dry-run
powersync deploy sync-config --directory=powersync --dry-run
```

`--dry-run` prints the target instance, validation results and the change set,
then exits without deploying.

## 7. Deploy (executed)

The `jp` instance `6ae4764ab0047aeb6df81fd9` was created and linked, then the
service config and sync config were deployed in that order.

```bash
powersync deploy service-config --directory=powersync
powersync deploy sync-config --directory=powersync
```

The live service deploy provisioned the connection and Supabase auth. The
full-coverage sync deploy is active: `powersync status` shows the connection
`connected`, initial replication done, and all 146 tables with
`used_for_replication: yes`. The first sync-config attempts failed with
`connect ECONNREFUSED` to the Supabase IPv6 endpoint and left the deployment
stuck. Stopping the instance and redeploying the service config, then the sync
config, cleared the stuck deployment and completed initial replication. Use
that sequence if a future deploy stalls before creating the replication slot.

A later `powersync deploy --dry-run` exits 0 and reports that the sync config
matches. It still lists `client_auth` and `replication` as service-config
changes because the deployed config returns `jwks.keys: []` and a password
`secret_ref` that the local file does not round-trip. This is a representation
artifact, not a failed deploy.

## 8. Client configuration

Set the instance URL as a build define; it is not a secret. The current
development value is the `jp` instance.

```bash
flutter run \
  --dart-define=NODEX_POWERSYNC_URL=https://6ae4764ab0047aeb6df81fd9.powersync.journeyapps.com
```

Never put `PS_DATABASE_URI`, `POWERSYNC_DATABASE_PASSWORD` or `PS_ADMIN_TOKEN`
in Flutter code, `--dart-define`, or any client environment.

## 9. Rotate the database password

The `powersync_role` password is stored only in the untracked `powersync/.env`
(mode `600`). Rotation ran on 2026-10-30 and the service config was redeployed
with the new credential. To repeat the rotation later:

```bash
cd /root/opencode-workspace/Nodex
powersync/scripts/rotate-db-password.sh
set -a; . powersync/.env; set +a
powersync deploy service-config --directory=powersync
powersync status
```

The script generates a fresh random password, runs `ALTER ROLE
powersync_role`, verifies the new credential, and rewrites only the
`POWERSYNC_DATABASE_PASSWORD` line in `.env`. It never prints the password. If
the Cloud token has been revoked, restore `PS_ADMIN_TOKEN` before the deploy
step, or rotate the password through the Supabase SQL editor and update `.env`
manually.

## Known limitations

- Sync Streams cannot evaluate `now()`, so `memberships.valid_until` is not
  checked inside a stream query. Expiry is instead a WAL event:
  `nodex.expire_memberships()` runs every minute under pg_cron and flips
  `status` to `expired`; every scope query joins `status = 'active'`. The
  mutation trigger checks `valid_until` with `clock_timestamp()` at the exact
  instant, so the write path does not wait for the sweep.
- A client that is offline when its membership expires keeps the last synced
  rows until it reconnects and receives the removal checkpoint. The local
  authorization snapshot has its own validity window; server writes are refused
  at the exact expiry instant.
- Device binding is optional on the server path. The handler and trigger reject
  a supplied device that is invalid, suspended, revoked, assigned to another
  user, or in another tenant, but a caller that omits `x-device-id` is treated
  as an unbound mutation. A revoked device can therefore continue uploading if
  it stops sending the header. Enforcing device binding end-to-end needs a
  device-bound PowerSync token and a mandatory device claim on every mutation.
- A future-dated membership with `status = 'active'` can replicate its tenant
  scope before `valid_from`; Sync Streams cannot compare time. The write guard
  still refuses at the exact instant. Use `valid_from` in the future only with a
  non-active status until the start time.
- Facility/ward narrowing is enforced on rows that carry `facility_id` or
  `ward_id`, and on bed/ICU rows through their bed. Tables without either column
  (for example `clinical_encounters`, `clinical_problems`, `doctor_assignments`)
  are tenant-scoped for a clinical role; a facility-scoped membership does not
  narrow those rows.
- A clinician with `encounter.write` can open an initial encounter for any
  patient in the tenant by naming themselves as attending physician. This is the
  intentional intake exception; it creates the care relationship. A separate
  registration/assignment approval is required if hospitals must prevent it.
- Triage assessments and ER visits are gated by `triage.write` and
  `er.visit.write` for the whole tenant, before an assignment or bed exists.
  That is the intake exception. The patient and encounter chain is still
  verified, and the tables have no facility/ward column for narrowing.
- `medical_officer` holds `clinical.dashboard.manage`, so a medical officer can
  create a dashboard assignment for themselves. The insert is the trusted act
  that creates the relationship, and requiring an existing assignment would be
  circular. Treat self-assignment as a policy assumption, not a technical
  control.
- Bed and ICU occupancy is gated by the table permission plus ward scope, not by
  a pre-existing patient assignment, because occupancy creates the location
  relationship. A ward-scoped user with `icu.bed.assign` can change
  `icu_beds.current_patient_id`; the ICU row is not otherwise patient-scoped.
- Creation attribution columns are immutable after insert, but the trigger does
  not bind them to the authenticated actor on insert. A caller with the table
  permission can name a different current member as `created_by` or
  `recorded_by`. The handler should set provenance from the verified claims; the
  database prevents later rewriting, not initial misattribution.
- The patient portal self-service branch is latent: the patient role holds only
  `portal.access`, and no guarded table uses a portal-scoped write permission
  yet. A portal write capability needs both a new permission and an RLS policy.
- The Supabase direct host resolves to IPv6 only. The deployed `jp` instance
  reaches it with `sslmode: verify-full` and reports `connected`; the host-side
  IPv6 path is still untested from this machine. A stopped/stuck deployment can
  fail with `connect ECONNREFUSED` to that IPv6 endpoint even though the
  connection test passes; stop the instance, redeploy the service config, then
  the sync config.
- The `jp` instance and Supabase project are both in `ap-northeast-1`, so the
  replication path stays in-region.
- The service-config dry-run reports `client_auth` and `replication` changes
  because secrets and the JWKS list do not round-trip through `fetch config`.
  The sync-config dry-run validates the deployed 50-stream config; the live
  instance serves 50 streams over 146 tables.
- The `powersync_role` password was rotated and the service config redeployed on
  2026-10-30. The 50-stream sync config is deployed; the replication slot is
  active and caught up.
- The PowerSync Cloud token was restored for this session. The GitHub PAT is
  still revoked; a new credential is needed for pushes.
- The live-service checklist has not run because no real PowerSync client is
  available. The endpoint resolves and the connection/replication path is
  healthy.
- The three commits (`d74b734`, `7db61da`, `34fd25e`) are pushed;
  `origin/main` is at `34fd25e`.
