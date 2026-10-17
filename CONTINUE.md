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
| Migrations | `supabase/migrations/` — 64 files (Phase 1 foundation plus the Phase 2–4 vertical slices). Statement content verified against `supabase_migrations.schema_migrations` for the applied set. Note: the migration tool strips `--` comments when recording, so verify semantics not bytes. |
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

Expected: no formatting changes, no analyzer issues, 1210 tests passing. If any of
those fail on a clean checkout, fix that before writing new code — CI enforces
all three.

### Verify the backend matches

```bash
supabase link --project-ref neoernavfntxsotwvmwq
supabase migration list     # compare local and remote; unapplied slices are expected until `db push` runs
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

The backend mutation path is shipped and MPI is landed. The PowerSync instance
is still the gating item: without it, MPI writes queue locally but never
upload, and no replicated data reaches a device.

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

### 3. First clinical modules (MPI, encounters, laboratory and Rx vertical slices landed)

**Master Patient Index (module 10)** and **Longitudinal EMR encounters
(module 16)** are implemented as reference vertical slices: Postgres schema
with RLS, PowerSync local schema, repository with test seam, `*.write`-gated
use cases, screens, field-level merge (MPI) and signature-gated freeze with
append-only amendments (encounters), the laboratory state machine (order ->
specimen -> entered result -> verified/corrected), and the prescription
lifecycle (draft -> finalized version -> dispense events -> MAR events, module
25). All clinical tables are registered in the mutation-handler allowlist,
local schema/repositories/use-case tests are present, and the patient detail
UI now links to encounter, laboratory and prescription workflows.

Handbook deviations applied while building it (all deliberate, all documented
in the migration headers):
- `(tenant_id, mrn)` uniqueness instead of global `mrn UNIQUE`
- FKs to `app_users(id)`, not `users(id)`
- Membership-derived RLS instead of `auth.jwt() ->> 'tenant_id'`
- Allergies as a separate frozen-column entity instead of JSONB columns
- Registry `mergeableFields` corrected to real column names (`phone_number`,
  not `phone`); six contact columns added to match
- Prescription series code is unique per `(tenant_id, code, version)`, with a
  forward `superseded_by` link, because each version is its own row
- Prescription finalize-class transitions enforce `prescription.finalize` in
  the trigger (RLS cannot distinguish them from draft edits); item release
  rides on the header authorization so prescribers need no dispense permission

**Doctor & Specialist Directory (module 08)** landed after that (1,056 tests
passing): `practitioner_profiles` and `practitioner_on_calls` with a
retirement-only profile lifecycle and an immutable credential record, the
`staff_directory.read` / `staff_directory.administer` permission split, the
directory screen reachable at `/staff-directory`, a dedicated
`staff_directory` PowerSync bucket, and mutation-handler registration for both
tables. On-call rotations are never overwritten, so historical cover stays
answerable offline.

**Clinical Departments Registry (module 12)** followed: the registry over the
Phase 1 `departments` row, with a register/edit/archive lifecycle (archived
departments are retained as historical references, never deleted),
`department.administer`-gated use cases, the `/departments` screen, a
`department` server-authoritative conflict policy, and mutation-handler
registration. Departments already replicate in `tenant_master_data`.

**Allied Staff & Workforce Manager (module 09)** came next, over the three
specification entities `staff_shifts`, `duty_allocations` and `attendance_logs`.
The slice keeps three different kinds of fact distinct: a shift is configuration
(a dated block of cover a ward needs), an allocation is a commitment (a named
person filling it, or approved leave), and attendance is a fact (appended, never
rewritten). Shift windows and headcounts freeze on close so an attendance report
can always be explained; a duty allocation cannot overlap another commitment
(rejected against the local projection and again by a database trigger); and
leave is modelled as an allocation whose role and status are both `leave`, so it
participates in the same overlap guard. New `workforce.read` / `workforce.manage`
permissions gate the `/workforce` screen, a dedicated `workforce` PowerSync
bucket scopes the rosters to `workforce.read`, and each table has a conflict
policy (shifts and allocations server-authoritative, attendance append-only).

**Human Resources & Payroll Suite (module 13)** followed, over `hr_employees`,
`hr_leave_requests`, `hr_holidays`, `hr_payroll_periods` and `hr_payslips`.
Attendance is deliberately not duplicated: Module 09 already owns
`attendance_logs`, and HR reads those facts. The slice keeps three kinds of
record distinct: the employment record (a lifecycle over an `app_users`
identity, retained on separation rather than deleted), the leave *workflow* (an
application and its decision, with overlapping live applications refused by a
trigger and an approved window frozen except for cancellation — distinct from
the roster block the approval produces in Module 09), and the payroll run (a
draft → finalized → paid state machine whose financials freeze when it leaves
draft, with `hr_payslips.net_minor` constrained by the database to equal gross
less deductions). Money uses integer minor units, matching the billing engine.
Four permissions split the surface: `hr.read`/`hr.manage` for the HR file and
`payroll.read`/`payroll.manage` for salary, with `payroll.manage`
`requires_online` so a payslip cannot be finalized from an offline snapshot.
Two PowerSync buckets (`hr`, `payroll`) keep salary from riding along with the
roster, the `/hr` screen is linked from navigation, and mutation-handler
registration plus per-table conflict policies (employee and holiday field-level
merge; leave and both payroll tables server-authoritative) are in place.

**Nurse Ward Station (module 06)** came next, over `ward_vitals`,
`ward_handovers` and `ward_tasks`. Beds and the MAR are deliberately not
duplicated: occupancy is the Module 11 bed assignment and the MAR event is the
Module 25 medication administration, and the station reads them rather than
keeping a second copy. Vitals and handovers are append-only facts (a second set
of observations is a second row, not an edit); the task queue is the one living
record and is a guarded state machine (open → in_progress → done/cancelled with
closed tasks frozen). Writing observations reuses the existing `vitals.record`
key, so no duplicate vitals permission was invented; `nursing.handover.record`
and `nursing_task.write` are new, and `nursing_station.read` scopes the
`nursing_station` PowerSync bucket. The `/ward-station` screen shows the open
task board, recent observations and the last handovers. An observation carries
an advisory alert band (normal/watch/urgent) derived by a pure function — a
triage aid for the board, explicitly not a validated early-warning score.

**Hospital Contacts Directory (module 42)** followed, over `directory_contacts`.
It is deliberately distinct from the staff directory (Module 08, people and
credentials) and the department registry (Module 12, organisational structure):
a contact is an operational reachability fact, and internal contact points are
often role-based ("Duty biomedical engineer", "Blood bank help desk") because
the number outlives whoever holds the phone — which is why the row does not hang
off an `app_users` identity. Contacts are archived, never deleted, and archiving
is one-way: the row freezes so a number a historical document or incident report
names stays answerable, and a contact that must return is registered afresh.
`contacts.read` is standard and offline (an emergency number must be reachable
without a network) and `contacts.administer` is elevated; a dedicated `contacts`
PowerSync bucket scopes the directory to `contacts.read`, the `/contacts` screen
searches by name, role and number (emergency contacts pinned first), and the
table is registered with a server-authoritative conflict policy and a
mutation-handler entry.

While building this slice a latent migration bug was found and fixed: the last
four migrations (`practitioner_directory`, `allied_staff_workforce`,
`hr_payroll_suite`, `nurse_ward_station`) inserted new permissions into a
`name` column, but `public.permissions` names it `display_name`. None of those
migrations had been applied, so the bug was invisible; all four now insert into
`display_name`. Verify any unapplied slice against the real column names before
`supabase db push`.

**Institutional Calendar & Shift Overlay (module 40)** followed, over
`calendar_events`. It owns only the institutional event; the "shift overlay" is
reading the Module 09 roster on the same time axis rather than storing a second
copy, and the calendar domain takes plain `ShiftSlice` projections so it does
not depend on the workforce domain — `buildCalendarOverlay` is a pure function
over events and shift slices. It also does not duplicate the HR holiday
entitlement (Module 13 `hr_holidays`): an operational holiday is an event here
with type `holiday`. An event is scheduled or cancelled and cancellation is
one-way, freezing the row so a document that names the cancelled event stays
answerable; events may overlap by design. `calendar.read` is standard and
offline, `calendar.manage` is elevated, and a `calendar` PowerSync bucket scopes
events to `calendar.read`, with a server-authoritative conflict policy and a
mutation-handler entry. The `/calendar` screen lists the next 30 days, overlaying
roster shifts when the session also holds `workforce.read`.

**Fleet & Ambulance Dispatch (module 27)** followed, the next unbuilt slice in
Domain C (Hospital Logistics, Supply Chain, Finance & Governance), over four
tables: `ambulances` (the fleet registry), `ambulance_duty_assignments` (the
driver roster), `ambulance_dispatches` (the emergency transit job) and
`ambulance_tracking_pings` (the coarse last-known position). This is a distinct
domain from the Module 09 ward roster: a crew is assigned to a *vehicle* for a
duty window, and the database forbids overlapping live duties for the same
vehicle or the same driver, so two offline tablets cannot both claim one
ambulance. A dispatch is a guarded state machine (`requested → assigned →
en_route → on_scene → completed`, cancellable from any live stage) and terminal
jobs freeze, because the stage times are what an incident review turns on. The
position ping is deliberately not a live GPS stream: a device buffers a ping and
it syncs when the network returns, answering "where was it last seen" without
pretending to be real-time telemetry. `fleet.read` is standard and offline,
`fleet.dispatch` and `fleet.manage` are elevated but offline — an emergency
dispatch cannot wait for connectivity — and a `fleet` PowerSync bucket scopes all
four tables to `fleet.read`, with server-authoritative policies for the registry,
roster and dispatch and an append-only policy for the ping. The `/fleet` screen
is a two-tab board: a dispatch board with stage progression and vehicle
assignment, and a vehicle registry with live duty rosters.

**Biomedical Assets & Calibration (module 29)** followed, over three tables:
`biomedical_assets` (the equipment registry), `biomedical_breakdown_tickets`
(the fault report, a guarded state machine) and `biomedical_maintenance_records`
(the append-only service history covering maintenance and calibration alike).
This is the serialized equipment estate, distinct from central inventory
(Module 28), which holds consumable stock: an asset is an individually
accountable instrument with a location, a lifecycle and a calibration
obligation, not a quantity on a shelf. The calibration-due state is *derived*
from the latest record's next-due date rather than stored twice and allowed to
drift. An asset with an open breakdown ticket cannot be decommissioned, a rule
the database enforces and the client checks so the answer is immediate offline;
a ticket advances one stage at a time (`reported → acknowledged → in_repair →
resolved`, cancellable from any live stage) and moves the instrument's lifecycle
with it — into repair takes it out of service, resolving returns it. Recording a
service does not need the registry, so `biomedical.maintain` is separate from
`biomedical.manage`: `biomedical.read` is standard and offline, both write tiers
are elevated and offline. A `biomedical` PowerSync bucket scopes all three tables
to `biomedical.read`, with server-authoritative policies for the registry and
tickets and an append-only policy for the service history. The `/biomedical`
screen is a two-tab board: the equipment list with derived calibration state and
open-ticket counts, and the breakdown queue.

**Bio-Medical Waste Management (module 30)** followed, over three tables:
`waste_categories` (the governed, colour-coded stream catalogue), `waste_generation_logs`
(the append-only record of what left where and when) and
`waste_disposal_certificates` (the barcoded proof of lawful destruction). This is
the regulated waste estate: waste is a quantity that leaves the building and is
accounted for by weight, so it is distinct from central inventory (Module 28,
consumables held on a shelf) and from the equipment registry (Module 29,
serialized instruments). Categories are tenant-scoped because the colour codes,
hazard classes and retention rules differ by jurisdiction; a category is
deactivated and retained rather than deleted, so history that names it stays
legible. A certificate is issued and may be voided, and voiding is one-way and
freezes the row — a certificate declared void must not be quietly resurrected. A
certificate's number and barcode are unique within the tenant, a rule the
database enforces and the client checks against the rows on the device, so a
duplicate is refused immediately offline. Compliance is *derived*, not stored:
the gap between weight generated and weight covered by live certificates per
category over a half-open window. Weight is an integer number of grams, matching
the integer-minor-unit convention money uses — no float on a compliance figure.
`waste.read` is standard and offline, `waste.record` (logging generation) and
`waste.manage` (categories and certificates) are elevated and offline so a ward
can log a bin without connectivity. A `waste` PowerSync bucket scopes all three
tables to `waste.read`, with a server-authoritative policy for the catalogue and
certificates and an append-only policy for the generation log. The `/waste`
screen is a four-tab board: generation, certificates, the derived compliance
window and the category catalogue.

**Health Insurance & TPA (module 32)** followed, over `insurance_payers`,
`insurance_policies`, `pre_authorisation_requests` and `insurance_claims`. It is
the payer side of the money, distinct from Module 31, which bills the patient:
here the counterparty is an insurer or a TPA and the money is recovered rather
than collected. The payer registry is tenant-scoped governed configuration, so a
payer is deactivated and retained rather than deleted — policies and claims name
it. Verification is a fact recorded on the policy row (who and when) instead of a
second copy of the cover, and cancellation is one-way: a trigger freezes a
cancelled policy, because the terms the payer asserted must stay readable.
Pre-authorisation and claim are both guarded state machines — `requested →
submitted → approved | partially_approved | rejected`, and `draft → submitted →
under_review → approved | partially_approved | rejected`, then `approved |
partially_approved → settled` — cancellable while live and frozen once answered or
closed. Two facts are derived rather than stored, so they cannot drift: the cover
state of a policy (expired, expiring soon, active or cancelled) from its validity
window, and the recovery gap of a claim (claimed minus settled, floored at zero).
Verification is separated from registry administration and from claims, so an
insurance desk can verify cover without being able to edit the payer registry:
`insurance.read` is standard and offline; `insurance.verify` (verification and
pre-authorisation), `insurance.claim` (claims, decisions and settlements) and
`insurance.manage` (registry and policies) are elevated and offline. An
`insurance` PowerSync bucket scopes all four tables to `insurance.read` with a
server-authoritative policy on every one, since a payer's decision and a claim
reference are single facts the server owns. The `/insurance` screen is a
patient-scoped four-tab board: cover, pre-auth, claims and payers.

The agreed run of four modules (13 → 06 → 42 → 40) is complete; modules 27, 29, 30
and 32 continue the sequence into Domain C. Next: continue with the remaining
clinical modules one vertical slice at a time, following the same pattern
(Postgres schema + RLS, PowerSync local schema, repository + test seam,
`*.write`-gated use cases, screens, sync bucket, mutation-handler registration,
conflict policy, tests, then format/analyze/test). The next unbuilt slice in
Domain C sequence is **module 33** (modules 31 and 32 are built; 33–39 remain).
Hardware barcode scanning, PowerSync device verification and clinical deployment
validation also remain across all slices.

---

## Known gaps

Deferred deliberately, not overlooked.

- **Release signing material pending (config wired).** `android/app/build.gradle.kts`
  now loads a gitignored `android/key.properties` (`key.properties.example` shows
  the format) and signs release builds with a real upload keystore when present;
  it still falls back to the debug key when absent so CI verification builds
  pass. Supplying the keystore + passwords (see the example file) is the step left
  before distributing anything. No Android toolchain here to build-verify it.
- ~~**No widget or integration tests**~~ — **resolved.** The shell/route-guard/
  session-lock widget coverage and the cross-module integration flow
  (appointment → encounter → prescription → pharmacy → billing) are committed and
  mutation-verified (1210 tests).
- ~~**No storage buckets**~~ — **defined; apply pending.** Migration
  `20260917260000_phase3_storage_buckets.sql` creates three private, tenant-scoped
  buckets with membership-derived RLS, a SHA-256 checksum required on upload, and
  no delete policy. Apply with `supabase db push`; the app-side signed-URL client
  is still to build (see `supabase/README.md`).
- ~~**No backup or restore procedure**~~ — **defined; rehearsal pending.**
  RPO/RTO targets, the restore procedure and the rehearsal checklist are in
  `supabase/BACKUP_RESTORE.md`. Only the operational rehearsal (a test restore to
  a scratch project, measured RTO recorded) is left.
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
