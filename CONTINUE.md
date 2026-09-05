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
| Migrations | `supabase/migrations/` — 19 files, verified byte-identical to what is applied remotely |
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

Expected: no formatting changes, no analyzer issues, 234 tests passing. If any of
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

### 1. PowerSync sync streams

Without them no data reaches a device, so no clinical module can be tested
offline. There is no PowerSync instance provisioned yet.

Each stream must mirror the same tenant/role/assignment policy the RLS helpers
implement, and must use trusted authentication parameters rather than client
input. The membership graph is the shared source: a stream should resolve scope
the same way `nodex.has_facility_access` and `nodex.has_ward_access` do.

Acceptance: a device holding a ward-scoped nursing membership replicates rows for
that ward only. Verify by inspecting the local database directly, not by checking
that the interface hides other wards.

### 2. Backend mutation path

Clients currently write through PostgREST under RLS. That is sufficient for
Phase 1's own tables but not for clinical writes, which need domain validation,
an audit event and a clinical event committed in one transaction.

Build as a Supabase Edge Function. `lib/data/sync/backend_connector.dart` already
routes uploads through `SupabaseGateway.upsert`/`patch`; point it at the function
instead. The connector already classifies rejections and refuses hard deletes, so
that logic does not need rewriting.

Note the skill available for this: `supabase-server` covers `@supabase/server`
auth modes and should be loaded before writing the function.

### 3. First clinical module

Once 1 and 2 exist, build **Master Patient Index** (module 10) as the reference
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
- **No widget or integration tests.** All 234 tests are unit tests. The adaptive
  shell, route guards and session lifecycle have no widget coverage; the spec's
  integration flows (appointment → encounter → prescription → pharmacy → billing)
  have none either.
- **No storage buckets.** DICOM, PDFs, scans and signatures need tenant-scoped
  buckets with short-lived signed URLs and checksum validation on upload.
- **No backup or restore procedure.** RPO/RTO targets must be defined and a
  restore actually exercised, not merely documented.
- **`app_users` rows are not created automatically.** A user authenticating for
  the first time has no `app_users` row and therefore no membership, so snapshot
  issuance fails with "no active membership in tenant". Either add a trigger on
  `auth.users` insert or provision through an admin flow. **This blocks the first
  real sign-in** — worth handling early.
- **No seeded tenant.** The database has roles and permissions but no tenant,
  facility or user, so there is nothing to sign into yet.

---

## Fastest path to a running app

Roughly in order, for whoever wants to see it work before building Phase 2:

1. Create a tenant and facility row.
2. Create an `auth.users` record, then a matching `app_users` row, then a
   `memberships` row granting `medical_officer` in that tenant.
3. Build with `--dart-define=NODEX_SUPABASE_URL=…` and
   `--dart-define=NODEX_SUPABASE_PUBLISHABLE_KEY=…` (publishable, never a secret
   key — startup validation rejects privileged keys).
4. Sign in with the tenant UUID, email and password. The app will issue a
   snapshot, land on the role-aware home, and show which modules that role
   reaches.

Replication stays disconnected until `NODEX_POWERSYNC_URL` is supplied; the app
runs local-only and says so in the settings screen.
