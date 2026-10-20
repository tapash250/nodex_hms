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
| Migrations | `supabase/migrations/` — 81 files (Phase 1 foundation plus the Phase 2–4 vertical slices). Statement content verified against `supabase_migrations.schema_migrations` for the applied set. Note: the migration tool strips `--` comments when recording, so verify semantics not bytes. |
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
cd /root/opencode-workspace/Nodex/nodex_hms
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos --fatal-warnings
flutter test
```

Expected: no formatting changes, no analyzer issues, 2147 tests passing. If any of
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

**Documents & Biometric E-Consent Vault (module 33)** followed, over
`consent_templates`, `consent_records` and `document_vault_documents`. This is
the documentary estate: the moment a patient agrees to a procedure and the
artefact that proves it, distinct from the encounter that records the treatment
the consent authorises. A template version is immutable once written — the words
a patient signed must never change under them — so a correction is a new version,
a duplicate version of a code is refused offline against the rows on the device,
and retiring a version only flips `is_active`; the row is never edited or deleted.
A consent record is a guarded state machine (`drafted → awaiting_signature →
signed`, declined from either live stage, `signed → revoked` one-way) and a
signed consent is frozen but for the revocation: what it attests is the record of
an act. The vault holds one artefact per object path, each with a mandatory
lowercase hexadecimal SHA-256 digest — the same digest the storage bucket
requires in the object metadata — and an optional detached signature that is
validated as a coherent (signature, algorithm, key id) triple or not at all,
because NODEX does not fabricate a signature it cannot verify. The address and the
digest of a vault entry are immutable once issued, and its two endings
(`superseded`, naming the replacement; `voided`, with a reason) are both one-way.
Two facts are derived rather than stored: the validity of a consent (pending,
awaiting signature, signed, expired, declined, revoked) from its status and
expiry, and what is still to be captured before it may be signed (signature,
biometric, witness, vaulted artefact) from the template's requirements.
`documents.read` is standard and offline; `documents.consent` (raise, capture,
sign, decline, revoke), `documents.vault` (index, supersede, void) and
`documents.manage` (template versions) are elevated and offline, so a ward nurse
can take a signature at the bedside without being able to register or retire what
the vault holds. A `documents` PowerSync bucket scopes all three tables to
`documents.read` with a server-authoritative policy on every one, since one
signature at one moment is a single fact the server owns. The `/consents` screen
is a three-tab board — consents, templates, vault — whose capture dialog records
the stylus signature on a canvas, rasterises it to PNG, uploads it under its
digest and signs the consent against the vault entry that indexes it.

Two gaps are named rather than papered over: the vault upload needs
connectivity, so a consent can be raised, witnessed and prepared offline but the
signature itself completes when the artefact reaches the vault; and thumbprint
capture awaits device hardware, so a template version that requires a biometric
attestation is refused on a device without a reader instead of being signed
without one.

**Statutory Records & Birth/Death Registry (module 34)** followed, over
`statutory_birth_records`, `statutory_death_records`,
`statutory_mlc_intimations` and `statutory_record_amendments`. This is the
register a hospital is legally obliged to keep, distinct from the clinical record
that holds the care and from the document vault that holds the artefacts: a birth
registration is the fact the civil registry is told, and a medico-legal
intimation is the fact the police are told. Each register is a guarded state
machine advancing one stage at a time — a birth and a death run `drafted →
registered → certified`, a case runs `reported → intimated → acknowledged →
closed` — and registration is a freeze: after it, a fact changes only by an
appended amendment naming the field, the previous value, the new value, the
reason and who attested it, never by an edit. That invariant is enforced in three
places, as the encounters amendment pattern does: the row guard refuses a fact
edit once registered, the amendment table has no update or delete policy, and an
append-only trigger blocks both. A death cannot be registered until its cause is
coded — free text plus a validated ICD-10 code plus the manner of death — because
an uncoded death is an unfinished record rather than a registration, and the
client checks the same rule so the answer is immediate offline. Registering and
certifying are separated: `statutory.read` is standard and offline,
`statutory.register` (raise, code, log, intimate, acknowledge, close) and
`statutory.amend` (append a correction, withdraw a live entry) are elevated and
offline, and `statutory.certify` is elevated and `requires_online`, because a
certificate is a finalization act like a discharge; the trigger enforces that
tier because RLS alone cannot tell the transition from a draft edit. Two facts
are derived rather than stored, so changing a window re-derives every marker:
whether a registration is past its statutory window (21 days for a birth, 7 for a
death) and whether a case is past its 24-hour intimation window. The
`statutory` PowerSync bucket scopes all four tables to `statutory.read`, with the
three registers server-authoritative and the amendment log append-only, and the
`/statutory` screen is a three-tab board — births, deaths, medico-legal — that
marks the overdue rows and offers the amendment sheet as the only edit control on
a registered row.

**Quality & NABH Compliance Hub (module 35)** followed, over `compliance_audits`,
`incident_reports` and `clinical_indicators`. This is the evidence estate: the
record a hospital presents to an accreditation body, distinct from the clinical
record that holds the care (an encounter records the treatment; an audit records
whether the treatment met a standard) and from the statutory register (the law
requires a birth certificate; a surveyor requires a hand-hygiene rate). Each of
the three is a guarded state machine. An audit is `planned → in_progress →
completed`, cancellable with a reason from either live stage; a started audit
stops being re-scoped, and a completed audit is frozen with its score because
that score is what was presented. An incident is `reported → investigating →
action_plan → closed`, voidable with a reason from either of the two live stages;
what happened freezes once the investigation opens, and the corrective action
cannot be agreed before the investigation and cannot be closed before the action
plan exists. An indicator is `draft → published → retracted`; a published figure
is frozen but for the retraction that withdraws it, because a figure an
accreditation body has read is a fact and not a working note.

The same discipline as Module 34 applies to what a stored copy would let drift:
the values are derived, not stored. The compliance score is the met criteria as
a whole percentage and the verdict follows from it against the conformance
thresholds, so a score cannot disagree with the criteria it summarises. An
indicator's value is its ratio times its unit's multiplier (a percentage by a
hundred, a rate per thousand device days by a thousand, a count or an hours
reading its numerator alone), and whether it meets its target reads the
direction, so one rule serves a hand-hygiene rate that must rise and an infection
rate that must fall. The response window an incident is held to is derived from
its severity — a day for a sentinel event or major harm, three days for a
moderate one, a week for a minor one or a near miss — so changing a threshold
re-derives every overdue marker on every device, and an incident already under
investigation is not overdue however late it was.

Permissions follow the tiers: `quality.read` is standard and offline, and
`quality.audit` (plan, start, score, complete, cancel), `quality.incident`
(report, investigate, agree the action plan, close, withdraw) and
`quality.indicator` (record, publish, retract) are elevated and offline. Nothing
here is a legal finalization, so no permission is `requires_online`: a ward logs
a needle-stick at the bedside and an audit is scored where it was conducted, and
correctness is preserved by the guards and the derived values rather than by
requiring a network. An incident number is unique per tenant and an indicator
code is unique per tenant and period, because two files for one incident split
the evidence and two readings of one period are one figure. The `quality`
PowerSync bucket scopes all three tables to `quality.read`, with a
server-authoritative policy on every one since an audit score, an incident file
and a published indicator are single facts the server owns, and the `/quality`
screen is a three-tab board — audits, incidents, indicators — that marks the
overdue and below-target rows from the row and the clock.

**Patient Feedback & Grievance Redressal (module 36)** followed, over
`feedback_surveys`, `feedback_complaints` and `complaint_routing_events`. This is
the patient's voice: what the hospital hears about itself after the care is
delivered. It is distinct from the clinical record (an encounter records what was
done; a survey records how it was received) and from the quality hub (an incident
is a harm the hospital found in itself; a complaint is a harm the patient brought
to it). A survey response is `recorded → actioned | voided`, with the band a score
falls in and the net promoter score itself derived from the responses, so the
headline number cannot disagree with the answers behind it. A grievance runs
`logged → acknowledged → investigating → resolved → closed`, with `dismissed`
available from any live stage and `voided` only from a freshly logged one, because
an old grievance is dismissed on its merits rather than erased. What a grievance
records freezes once it is logged, since the acknowledgement and resolution
deadlines are measured from that moment and from the severity, while where it is
routed stays editable: re-routing a grievance to the right department is the point
of the registry, and each move is appended to `complaint_routing_events` so the
answer to "who had this and when" is a query over the log rather than an
overwritten column. The deadlines are derived too: 24 hours to acknowledge and,
by severity, three days to resolve a high-severity grievance, seven a medium one
and fourteen a low one. Permissions follow the counter and the clinician:
`feedback.read` is standard and offline, `feedback.record` is the front desk's
tier and `feedback.resolve` is the clinical tier, so the person who takes a
complaint at the counter cannot also be the person who decides it was unfounded.
Nothing here is a legal finalization, so nothing requires a network. A complaint
number is unique per tenant and a survey number is unique per tenant, because two
files for one grievance split the deadline and two responses filed once would
move the score. The `feedback` PowerSync bucket scopes all three tables to
`feedback.read`, with a server-authoritative policy on the two registers and
`appendOnly` on the routing log, and the `/feedback` screen is a two-tab board —
surveys with the derived score, grievances with the missed deadlines marked — that
shows the routing history in the grievance detail sheet.

**Visitor & Pass Security Management (module 37)** followed, over
`ward_visiting_windows`, `visitor_registrations`, `visitor_passes` and
`visitor_badge_prints`. This is the front door: who came in, on whose authority,
where they were allowed to go, and what the gate printed for them. It is distinct
from the clinical record (an encounter records the patient; a registration records
the person who came to see them) and from the workforce rosters (a shift is staff
on duty; a pass is a visitor allowed in). The visiting window is configuration
rather than an event: one row per ward per weekday, archived rather than deleted so
a past pass still resolves to the rule it was issued under. A registration runs
`registered → on_site → left`, with `refused` and `voided` as the two ways out of
the first stage, and what the gate recorded freezes the moment the visitor steps
past it. A pass runs `issued → active → returned`, with `revoked` from either live
stage, and carries no `expired` status: expiry is derived from the clock against
the validity window, so a badge cannot sit on a device claiming to be valid after
its own window closed, and activation refuses a pass whose window has already
closed. The badge print log is append-only and numbered by ordinal, because a
thermal badge is a physical token and the number of times it was made is a fact
worth keeping. Window boundaries are stored as minutes from local midnight and the
client passes the local minute of day, because visiting hours are a wall-clock rule
and a `timestamptz` boundary would quietly move 10:00 for a server on another
clock. Permissions follow the counter and the clinician: `visitor.read` is standard
and offline, `visitor.register` and `visitor.pass` are elevated and offline (a gate
works while the network does not), and `visitor.configure` is held only by the
administrator and the medical officer, because a ward's visiting hours are a rule
rather than a shift. Nothing here is a legal finalization, so nothing requires a
network. A registration number is unique per tenant and a badge number is unique
per tenant, because two gate rows sharing a number make the log unreadable and two
badges sharing one number would let one person's access stand for another's. The
`visitor` PowerSync bucket scopes all four tables to `visitor.read`, with a
server-authoritative policy on the three registers and `appendOnly` on the print
log, and the `/visitors` screen is a three-tab desk — the gate, the passes and the
ward hours — that reads the badge print log in the pass sheet.

**Reports & Operational Analytics Warehouse (module 38)** followed, over
`analytics_report_definitions`, `analytics_rollups`, `analytics_report_runs` and
`analytics_exports`. This is the warehouse the spec asks for — morbidity reports,
department productivity, pharmacy burn rate and financial balance sheets — and it
stores conclusions rather than facts: an encounter, a dispense and an invoice stay
in the modules that own them, and what lives here is what those add up to over a
period, plus the record of who asked. A definition runs `draft → published →
retired`, and its code, category, source, grain and facility are frozen at
publication because a device that re-scoped them locally would quietly change what
every figure it already holds means. A rollup runs `materialised → superseded |
voided`, one current row per definition, grain and period: re-materialising a
period supersedes the row already holding it rather than sitting beside it, because
two current rows for one period are two answers to one question, and the superseded
row is kept so a figure that was published can still be explained. A run runs
`queued → running → succeeded | failed`, with `cancelled` from either live stage,
and records whether the rolling rollup or the read replica answered it. The export
log is append-only, because the question a balance sheet raises is not what it says
but who has one. Nothing that could drift is stored: what period a grain covers is
`analyticsPeriodEnd`, a rate is the rollup's own ratio (null over an empty
denominator — a rate of zero would be a claim), a bottom line is
`rollupNetPosition`, growth needs a non-zero period before it, and whether a figure
has gone out of date is the clock against the period it claims. Period starts are
date-only `YYYY-MM-DD` text parsed by splitting the parts into a UTC midnight, so a
device west of UTC does not report the previous month's rollup. Permissions follow
the warehouse and the counter: `analytics.read` is standard and offline, so a nurse
can see the board's figures; `analytics.define` is elevated and offline, because a
report's contract is settled at a desk; and `analytics.materialise` and
`analytics.export` are elevated and **require a network**, because both read the
read replica and a rollup computed from a stale local copy would be a number no
other device agrees with. A report code is unique per tenant, a run number is
unique per tenant and an artefact name is unique per run, because two rows sharing
one make the log unreadable. The `analytics` PowerSync bucket scopes all four
tables to `analytics.read`, with a server-authoritative policy on the definition,
the rollup and the run (each is a conclusion only the warehouse can observe) and
`appendOnly` on the export log, and the `/analytics` screen is a three-tab
warehouse — the catalogue, the runs and the figures — that reads the export log in
the run sheet.

**Master Settings & AI Configuration Hub (module 39)** closed Domain C, over
`settings_profiles`, `branding_assets`, `department_hierarchies`, `billing_tariffs`
and `ai_routing_profiles`. This is the hospital's own description of itself, and
every clause of the scope is versioned rather than edited: a settings profile and a
branding asset run `draft → active → superseded`, a department is archived, and a
tariff and a routing profile run `draft → active → retired`. A past bill, a past
letterhead and a past analytics figure all have to resolve to the configuration they
were produced under, and a row that could be deleted could not do that. Hospital
configuration is kept as versions per tenant and facility with exactly one profile
active at a time, because two profiles in force are two timezones on one screen; the
currency and its minor units live there so two screens cannot disagree about where
the point goes, and the fiscal-year start, appointment slot and session idle window
are read from it rather than hard-coded. The department tree is self-referencing and
its depth and ancestry are derived on read (`departmentLevel`, `departmentAncestors`,
`departmentPath`) rather than stored, because a stored level goes stale the first
time a branch is re-parented; a cycle is refused at the database by a recursive
guard, and a department with live branches under it is not closed. A tariff carries
its amount in minor units and its tax in basis points, so a line item is exactly
reproducible; a draft is approved into life and then retired, and two live tariffs
for one code may not overlap in time because an invoice that has two answers is a
dispute. A routing profile names a model from the Phase 1 governance registry (the
foreign key is what stops a profile routing to a model the hospital never admitted),
holds the warmth in basis points and the residency, and a profile whose data may
leave the country must redact PHI — a CHECK constraint, not a review note, because
it is the one clause here that protects patients rather than money. Nothing is
computed twice: contrast is `brandingContrastRatio`, tax is `tariffTaxMinor`, a
tariff is live only inside its own window, and a profile is usable only if it is
routing and lawful. The security clause is met in three ways: the changes are
restricted to `hospital_super_admin` by role before the permission is even weighed,
the permissions (`settings.configure`, `settings.tariff`, `ai.configure`) carry
`requires_online` so the offline permission subset never contains them, and every
mutating use case demands a fresh `SecondFactorAssertion` whose identity, purpose and
expiry are checked — the verifier is a port because a code this app generated and
this app checked would be a code an attacker on this device could generate too, and
`StubSecondFactorVerifier` stands in for the identity provider's own challenge until
Supabase Auth MFA is wired. Reading stays offline, because a device needs the
hospital's timezone, currency and branding to render a screen while the network is
down, and none of those are secrets. All five tables are server-authoritative for one
reason rather than five: every change to them is made online with a second factor,
so there is no offline edit to reconcile. The `settings` PowerSync bucket scopes all
five to `settings.read`, and `/master-settings` is a five-tab hub — configuration,
branding, departments, tariffs and AI routing — whose every write asks for the code
first and hands the use case the assertion, not the code.

The agreed run of four modules (13 → 06 → 42 → 40) is complete; modules 27, 29,
30, 32, 33, 34, 35, 36, 37, 38 and 39 continue the sequence into Domain C.

**All 54 clinical modules now have a vertical slice.** The run after the audit
was: 31 (patient accounts, ledger and payment splits) → 41 (task engine) → 45
(widget library) → 48 (master data tables) → 49 (chart engine) → 46 (adaptive
component system) → 50 (patient journey) → 47 (forms builder) → 44 (productivity
apps) → 43 (clinical messaging) → 02 (operations dashboard) → 03 (performance
dashboard) → 04 (doctor cockpit) → 05 (patient portal) → 51 (icon repository) →
52 (security suite) → 53 (operational utilities) → 54 (global search). Each was
committed on its own with the same pattern: Postgres schema + RLS, PowerSync
local schema, repository with a test seam, permission-gated use cases, screens,
sync bucket, mutation-handler registration, conflict policy, tests, then
format/analyze/test.

What is left is no longer a module. It is the work that needs a decision, a
device or a person who is not this session — listed in **Known gaps** below and
summarised in `docs/OPEN_WORKSTREAMS.md`.

---

## Known gaps

Deferred deliberately, not overlooked.

- **Release signing material pending (config wired).** `android/app/build.gradle.kts`
  now loads a gitignored `android/key.properties` (`key.properties.example` shows
  the format) and signs release builds with a real upload keystore when present;
  it still falls back to the debug key when absent so CI verification builds
  pass. Supplying the keystore + passwords (see the example file) is the step left
  before distributing anything. No Android toolchain here to build-verify it.
- **Second-factor step-up is a port with a stub behind it.** The Module 39 master
  settings use cases demand a fresh `SecondFactorAssertion`, and the gate itself is
  real and tested (identity, purpose and expiry are all checked, and the signature
  of an assertion this app generated is refused by the domain, not by the stub).
  What stands behind the port is `StubSecondFactorVerifier`, which accepts a
  well-formed six-digit code. The real factor belongs to the identity provider:
  Supabase Auth MFA (`auth.mfa.enroll` / `challenge` / `verify`, and the
  `aal2` assurance level) is the implementation to wire, at which point the stub is
  replaced rather than extended. Until then the hub is usable in development and
  the step-up is honest about being a placeholder.
- ~~**No widget or integration tests**~~ — **resolved.** The shell/route-guard/
  session-lock widget coverage and the cross-module integration flow
  (appointment → encounter → prescription → pharmacy → billing) are committed and
  mutation-verified (2147 tests).
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
