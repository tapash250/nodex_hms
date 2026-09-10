# Continuation notes

Written at the end of the Phase 1 session so the next session can resume without
re-deriving decisions. Read this first, then `README.md` for architecture.

---

## Where everything is

| Thing | Location |
|---|---|
| Repository | `github.com/tapash250/nodex_hms`, branch `main` |
| Phase 1 commit | `fe07e07` — "Implement Phase 1 platform foundation" |
| Supabase project | ref `neoernavfntxsotwvmwq`, name `Nodex_HMS`, region `ap-northeast-1`, PostgreSQL 17 |
| Migrations | `supabase/migrations/` — 21 files. Statement content verified against `supabase_migrations.schema_migrations`. Note: the migration tool strips `--` comments when recording, so verify semantics not bytes. |
| Source spec | `NODEX_HMS_Final.pdf`, 44 pages (read with `pdftotext -layout`; the PDF reader tool cannot handle PDFs on this model) |

---

## Resuming

### Toolchain

The verification toolchain is Flutter 3.47.2 stable. If the sandbox was reset,
reinstall before doing anything else:

```bash
git clone --depth 1 --branch stable https://github.com/flutter/flutter.git /opt/sdk/flutter
export PATH=/opt/sdk/flutter/bin:$PATH
flutter --version          # first run downloads the Dart SDK; ~6 min on a slow link
flutter config --no-analytics
```

On aarch64 the Dart SDK download and the `flutter_tools` snapshot build each take
several minutes and will exceed a 120 s command timeout. Run them detached
(`setsid nohup … &`) and poll, rather than waiting inline. If a run is
interrupted, delete `/opt/sdk/flutter/bin/cache/lockfile` before retrying.

### Verify the checkout is sound

```bash
cd /root/workspace/nodex_hms
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos --fatal-warnings
flutter test
```

Expected: no formatting changes, no analyzer issues, 245 tests passing. If any of
those fail on a clean checkout, fix that before writing new code — CI enforces
all three.

### Verify the backend matches

```bash
supabase link --project-ref neoernavfntxsotwvmwq
supabase migration list     # local and remote should agree on all 19
```

---

## Decisions already made

Recorded so they are not relitigated. Each was a real choice with alternatives.

**Migrations are kept unsquashed.** Two of the nineteen supersede earlier work
(`phase1_snapshot_revocation_guard`, `phase1_dedupe_app_user_guard`). They stay
because the history explains why the first attempt was wrong — a blanket UPDATE
block on snapshots also blocked legitimate device revocation.

**Governance gates live in the database, not the client.** The AI model lifecycle
gate is a CHECK constraint; audit immutability is a trigger. A client bug cannot
route around either.

**The offline permission subset is computed server-side.** `requires_online` is a
column on `permissions`, and the issuance RPC filters on it. The client's
catalogue in `permission_catalog.dart` is a defensive second gate for stale
snapshots, not the source of truth.

**Bedside high-risk actions stay available offline.** Medication administration,
dispensing and triage escalation are `high_risk` but not `requires_online`: they
happen where connectivity cannot be assumed, and the audit trail records that
they occurred offline. Finalization actions (prescription, discharge, transfusion,
billing settlement) are online-only.

**AI adapters ship unconfigured.** Every engine resolves to a manual workflow.
This is the correct state before any model has passed evaluation, and it means
the Orchestrator's failover path is exercised by real code rather than mocked.

**`ClinicalDocumentExtraction` is `onDeviceOnly`.** LFM2.5-VL-450M is the
designated edge vision model, so document images do not leave the device unless a
separately validated cloud vision model is explicitly enabled in the profile.

**Analysis is strict on purpose.** `discarded_futures` and `unawaited_futures` are
errors because an unawaited future in a clinical write path silently drops a
mutation. `avoid_print` is an error because PHI must not reach a general log.

---

## Phase 2 in dependency order

Two backend gaps block all clinical modules. Do these first, in this order.

### 1. PowerSync instance (rules done, instance missing)

Rules are written at `powersync/sync-rules.yaml` with parameters derived from
the JWT (`request.user_id()`) plus the membership graph — never client input.
`powersync/SETUP.md` documents the reader-role grant matrix, including why the
reader needs BYPASSRLS (ten tables are FORCE RLS with `TO authenticated`
policies, so a non-bypass reader sees zero rows and every bucket comes back
silently empty).

Still missing: the instance itself. Without it no data reaches a device, so no
clinical module can be tested offline.

Acceptance: a device holding a ward-scoped nursing membership replicates rows for
that ward only. Verify by inspecting the local database directly, not by checking
that the interface hides other wards.

### 2. Backend mutation path (shipped)

`supabase/functions/mutation-handler` is deployed with `verify_jwt: true` and
uses `withSupabase({ auth: 'user' })` per the supabase-server skill (auth key is
`auth`, not `allow`; modes are `user`/`publishable`/`secret`/`none`). The
Flutter connector submits CRUD batches with stable UUIDv5 ids and decodes
per-mutation outcomes; unknown outcomes decode as rejections. The table
allowlist is empty by design: a table registers with a validator in the same
change that adds its offline write path.

Next on this path: `device_id` in the mutations ledger (connector currently
sends null) and a real SHA-256 `payload_digest` instead of the idempotency-key
placeholder.

### 3. First clinical module

Once 1 exists, build **Master Patient Index** (module 10) as the reference
implementation. It is the right first module because every other clinical module
references a patient, and it exercises the field-level merge conflict policy,
which is the most intricate of the eight.

Work through the module definition of done in `README.md`. Treat the result as
the template later modules copy.

---

## Known gaps

Deferred deliberately, not overlooked.

- **Release signing is not configured.** The release build type falls back to the
  debug key so verification builds succeed. Supply real signing material before
  distributing anything.
- **No widget or integration tests.** All 245 tests are unit tests. The adaptive
  shell, route guards and session lifecycle have no widget coverage; the spec's
  integration flows (appointment → encounter → prescription → pharmacy → billing)
  have none either.
- **No storage buckets.** DICOM, PDFs, scans and signatures need tenant-scoped
  buckets with short-lived signed URLs and checksum validation on upload.
- **No backup or restore procedure.** RPO/RTO targets must be defined and a
  restore actually exercised, not merely documented.
- ~~**`app_users` rows are not created automatically**~~ — **resolved.**
  `phase1_user_provisioning` adds `user_invites` plus an `AFTER INSERT` trigger
  on `auth.users`: invited emails auto-provision `app_users` + membership on
  first signup; uninvited signups get nothing. Verified end-to-end with a
  dry-run, including proof that the append-only audit guard cannot be bypassed
  even by the table owner.
- ~~**No seeded tenant**~~ — **resolved.** `phase1_bootstrap_tenant_seed`
  creates `nodex-bootstrap` (Asia/Dhaka, fixed UUIDs): 1 facility, 2
  departments, 2 wards.

---

## Fastest path to a running app

1. Insert a `user_invites` row (needs `user.administer` in the tenant, or run as
   owner): tenant `10000000-0000-4000-8000-000000000001`, the admin email,
   `role_key = 'hospital_super_admin'`.
2. Create the Supabase Auth user for the same email (dashboard or API). The
   provisioning trigger creates `app_users` + membership automatically.
3. Build with `--dart-define=NODEX_SUPABASE_URL=…` and
   `--dart-define=NODEX_SUPABASE_PUBLISHABLE_KEY=…` (publishable, never a secret
   key — startup validation rejects privileged keys).
4. Sign in with the tenant UUID, email and password. The app will issue a
   snapshot, land on the role-aware home, and show which modules that role
   reaches. An uninvited account lands on the awaiting-authorization screen with
   a first-run explanation instead of a database error string.

Replication stays disconnected until `NODEX_POWERSYNC_URL` is supplied; the app
runs local-only and says so in the settings screen.
