# Open workstreams

Everything the code cannot close on its own.

54 of the 54 clinical modules have a vertical slice. Module 01, the global
executive dashboard, is the home landing surface: snapshots are captured
server-side and reduced to four deterministic risk points. What is left is work
that needs a decision, a device, a key or a person who is not the engineer: the
list below says what each item is, what it needs, and how to tell it is done.

Nothing here is forgotten work. Each item was deliberately deferred, and each
one has a place in the code or the configuration where it would land.

## 1. Infrastructure the repository cannot provision

| Workstream | State | What it needs | Done when |
|---|---|---|---|
| PowerSync instance | Rules written (`powersync/sync-rules.yaml`, 50 buckets), instance missing | A PowerSync account and a deployed instance against the Supabase project | A device replicates the rows of the buckets its membership allows, and a device in one ward does not hold another ward's rows |
| Migrations applied | 88 files in `supabase/migrations/`, remote state partial (latest applied `20260918155213`; Phase 4 module migrations are pending) | `supabase db push` against project `neoernavfntxsotwvmwq`, with a restore rehearsal first | `supabase migration list` shows no pending migration, and a test restore to a scratch project is measured against the RTO in `supabase/BACKUP_RESTORE.md` |
| Storage buckets | Migration written (`20260917260000_phase3_storage_buckets.sql`), not applied | `supabase db push` | The three buckets exist, are private, and a signed URL expires in 60 seconds |
| Release signing | Config wired (`android/key.properties`, gitignored), key absent | An upload keystore and its passwords | A release APK is signed with the upload key and installs over the store build |
| Push notifications | No FCM integration | A Firebase project, the `google-services.json`, and a device-token table | A critical result reaches a locked device as a notification |

## 2. Hardware and platform integration

| Workstream | State | What it needs | Done when |
|---|---|---|---|
| Barcode scanning | No scanner integration; specimens are entered by hand | A camera-based scanner (ML Kit) or a hardware wedge | A specimen barcode opens the specimen record without typing |
| Thermal printing | No print bridge | An ESC/POS bridge (Bluetooth or LAN) and a paper-roll test | A discharge summary prints with the hospital's letterhead and a QR code to the portal |
| Thumbprint capture | `local_auth` handles device biometrics only | A fingerprint SDK and the hospital's registration process | A patient's fingerprint is captured at registration and verified at admission |
| Background work | No WorkManager integration | The AndroidX WorkManager dependency and a job policy | The upload queue retries on a schedule when the device is charging, without the app running |

## 3. Real-time transport

| Workstream | State | What it needs | Done when |
|---|---|---|---|
| WebRTC telehealth | Consultations are records without live audio or video | A signalling server, TURN, and a clinical consent flow | A remote consultation carries two-way audio with the patient's consent recorded |

## 4. AI beyond the governance layer

The AI subsystem ships with its orchestrator, gateway, model registry,
deterministic routing and circuit breaker, and with **stub adapters**. The
following are not implemented, and each one is named in a module that now
exists:

| Where | What is missing | What it needs |
|---|---|---|
| Module 01 executive dashboard | The approved AI narrative over the four deterministic risk points | A model key, a pre-vetted prompt and a governance approval; the narrative must cite the figures it was derived from and is shown only when attached to a snapshot |
| Module 04 doctor cockpit | The AI-assisted summary of the day | The same, plus the safety policy the orchestrator already enforces |
| Module 05 patient portal | The plain-language explainer for a diagnosis | A clinical governance sign-off per explanation, because an unreviewed explainer is a clinical statement |
| On-device speech | The local Whisper pipeline and PCM capture | The edge runtime and a device with the microphone permission |
| On-device vision | The imaging pipeline | The edge runtime and a model per modality |

Every AI call in this application goes through the orchestrator. A clinical
workflow never receives a provider-specific endpoint, credential or response
shape, so adding an adapter is a change inside the adapter and nothing else.

## 5. Phase 6 hardening

Deferred because it needs a target to harden against and a person to run it.

- **Performance baseline.** A measured cold-start, first-replication and
  ward-round frame profile on a real 6" phone and an 11" tablet. The budgets
  are not written down yet; that is the first step.
- **Negative testing.** A red-team pass over the authorisation model: RLS
  policies, the mutation-handler allowlist, the offline authorization window
  and the append-only guards. The guards are tested in the repository; the
  attempt to bypass them from outside is not.
- **Restore rehearsal.** See §1.
- **Clinical validation.** No part of this repository is evidence of
  regulatory certification or clinical validation, and nothing in it should be
  read that way.

## 6. Known partials inside shipped modules

These are deliberate and stated in the commit that introduced them, so nobody
finds them by surprise:

- **Second-factor step-up** runs against `StubSecondFactorVerifier`, which
  accepts a well-formed six-digit code. The gate above it is real. The
  implementation to wire is Supabase Auth MFA (`auth.mfa.enroll` /
  `challenge` / `verify` and the `aal2` assurance level).
- **Module 43 payloads are replicated, not end-to-end encrypted.** A clinician
  must read a discussion on a ward with no signal, so the device holds the
  conversation. Device-bound encryption and encryption at rest for the
  messages are not implemented.
- **Module 01's AI narrative is not built.** The four risk points are derived
  deterministically from the stored figures and each cites its baseline. The
  optional `ai_executive_summary` column is shown only when an approved summary
  is attached; no model has been approved, so no narrative is generated.
- **Model approval is wired, but the evaluation pipeline is not.** The
  governance screen approves an evaluated model and activates an approved one
  through the mutation handler; RLS and `tg_ai_model_governance_guard` re-check
  the permission, the evidence and the approver. Producing
  `evaluation_status = 'passed'` against a locked acceptance set is an
  evaluation harness that lives outside this repository.

## 7. Security residuals

The Phase 1 audit's three findings are closed locally:

- **Facility scope on the ward buckets.** `ward_census`, `nursing_station`,
  `icu_census`, `staff_directory`, `visitor` and `contacts` derive
  `facility_id` from the caller's membership and filter every replicated query
  on it. A nurse scoped to one facility no longer replicates another
  facility's beds, observations, handovers, tasks, practitioners, visitors or
  contacts.
- **Facility scope on the executive bucket.** `executive` derives one facility
  per active facility from the membership and filters every snapshot to it, so
  a facility-bound device does not hold another facility's executive reading.
- **Refund accounting.** `invoices.settled_minor` is net collections.
  `20260918130000_phase4_refund_settlement_accounting.sql` reduces it from the
  append-only refund row through `nodex.tg_refund_reduce_settled`, and the
  settled-invoice guard accepts that projection while refusing every other
  rewrite. The executive revenue reading can now subtract refunds.
- **Storage immutability.** `20260918120000_phase4_storage_immutability.sql`
  drops the UPDATE policies on the three clinical buckets. A correction is a
  new object at a new path; an existing path cannot be rewritten.

What remains is the breadth of the facility scope and the deployed proof:

- **Facility scope does not yet cover every bucket with a facility
  dimension.** `er_triage`, `blood_bank`, `operation_theatre`, `radiology`,
  `physiotherapy`, `nutrition`, `telemedicine`, `discharge_management`,
  `floor_map`, `workforce`, `analytics`, `operations`, `performance`,
  `clinical_dashboard`, `task_engine`, `form_builder`, `patient_portal`,
  `clinical_messaging` and `productivity` still select by `tenant_id`.
  Closing them needs the same membership parameter and a replication test per
  bucket. Acceptance: a device in one facility holds no row from another
  facility in any bucket that has a facility dimension.
- **The deployed instance must prove the rules.** The replication tests are
  textual until PowerSync is provisioned; acceptance is a facility-scoped
  device syncing only its facility's rows.

## 8. How to close an item

1. Write the decision down here, with the acceptance criteria above.
2. Make the change on its own branch, with the module's pattern: schema, local
   schema, repository, use cases, screens, bucket, mutation handler, conflict
   policy, tests.
3. Verify: `dart format --output=none --set-exit-if-changed .`,
   `flutter analyze --fatal-infos --fatal-warnings`, `flutter test`.
4. Commit, push, and tick the item off in this file.
