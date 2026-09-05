# NODEX Enterprise HMS — Android

> Android-first Flutter clinical operating system. Offline-first, encrypted
> local-first storage, hybrid edge/cloud AI under human clinical governance.

NODEX is a hospital management and clinical operations platform for enterprise
hospital networks, multi-specialty tertiary centres, diagnostic laboratories,
emergency facilities, ward tablets and mobile clinical workflows.

The core design assumption is that **clinical work must continue when
connectivity is poor or temporarily unavailable**. The device is not a thin
client with a cache bolted on; it holds an authoritative local operational
projection of the data it is authorized to hold, and the cloud remains the
authoritative system of record.

---

## Status

**Phase 1 (Platform Foundation) is implemented.** Clinical modules are not.

| Delivered | Detail |
|---|---|
| Backend foundation | Tenancy, identity, RBAC, devices, offline authorization, audit, clinical events, sync ledger, AI governance — all with RLS |
| Security boundaries | Three-tier model wired end to end; snapshot issuance is server-derived |
| Local storage | Encrypted PowerSync SQLite under SQLCipher, key in Android Keystore |
| Error model | Eight normalized error classes with defined handling behaviour |
| Conflict policies | Per-entity deterministic strategies, registered and tested |
| AI subsystem | Orchestrator, Gateway, model registry, deterministic routing, circuit breaker — with stub adapters |
| Application shell | Role-aware GoRouter, Material 3 adaptive navigation, session lifecycle |
| Verification | 234 unit tests; `flutter analyze --fatal-infos --fatal-warnings` clean |

Not yet built: the 54 clinical modules, PowerSync sync stream definitions, the
backend mutation path for high-risk writes, real AI provider adapters, the
on-device vision and speech pipelines, WebRTC telehealth, and thermal printing.

This repository is **not** evidence of regulatory certification or clinical
validation.

---

## Architecture

### Technology

| Layer | Choice |
|---|---|
| Application | Flutter 3.47 / Dart 3.13 |
| UI | Material 3, adaptive |
| State | Riverpod 3 |
| Routing | GoRouter 18 |
| Local database | PowerSync SQLite + SQLCipher |
| Key protection | Android Keystore via `flutter_secure_storage` |
| Backend | Supabase, PostgreSQL 17 |
| Server authorization | PostgreSQL RLS + `SECURITY DEFINER` helpers |
| Biometrics | Android BiometricPrompt via `local_auth` |
| AI orchestration | NODEX AI Orchestrator + Gateway (provider-agnostic) |

### Layering

```text
Screen  →  Riverpod Controller  →  Use Case  →  Repository
                                                    ↓
                                     Encrypted PowerSync SQLite
                                                    ↓
                                          PowerSync upload queue
                                                    ↓
                                        Authorized backend path
                                                    ↓
                                         Supabase PostgreSQL + RLS
```

Presentation code never touches Supabase. The SDK is confined to
`lib/data/remote/supabase_gateway.dart`, which is the only file permitted to
import it — that makes the specification's first engineering prohibition
mechanically checkable rather than a convention.

### Three security tiers

1. **Client UX** — route guards and permission-filtered navigation. Shapes the
   interface; never the authorization boundary.
2. **Device data scope** — PowerSync sync streams decide which rows reach a
   device. A record a device may not hold is never replicated merely because the
   interface hides it.
3. **Server authorization** — PostgreSQL RLS plus domain authorization on the
   backend mutation path. Authoritative even if the client is decompiled.

### Offline authorization

The server issues a device-bound, time-bounded snapshot containing the minimum
needed to continue approved offline workflows. Three properties are enforced
rather than assumed:

- It can only ever **deny more** than the server does.
- The offline permission subset is **computed server-side** from
  `permissions.requires_online`, so the offline boundary is not a client
  decision.
- Its digest is **recomputed on load**. A mismatch quarantines the session and
  wipes local data rather than trusting an altered permission set.

Privileged actions — role changes, tenant administration, transfusion
finalization, financial settlement, discharge finalization — are excluded from
the offline subset. Bedside high-risk actions such as medication administration
and triage escalation remain available offline, with the audit trail recording
that they occurred offline.

### Conflict resolution

No global last-write-wins. Each entity declares a deterministic strategy in
`lib/core/sync/conflict_policy.dart`, and an unregistered entity raises an
`IntegrityError` instead of falling back to a permissive merge:

| Entity | Strategy |
|---|---|
| Patient demographics | Field-level merge; overlapping edits escalate |
| Clinical notes | Versioned revisions |
| Prescriptions | Immutable versioned orders |
| Medication administration | Event transaction, deduplicated by identity |
| Laboratory results | Immutable with explicit correction |
| Inventory, billing | Transactional replay |
| Bed assignment, appointments | Server-authoritative |

### AI subsystem

The boundary is strict and enforced by the code's shape:

- The **Orchestrator** decides what runs and under which policy. It contains no
  provider formatting, authentication or transport.
- The **Gateway** reaches providers through `AiProviderAdapter` implementations.
  It cannot decide clinical routing or override policy.
- Clinical workflow code depends only on `lib/ai/contracts/ai_contracts.dart`.

Governance invariants, all covered by tests:

- **An available model is not an approved model.**
  `ModelRecord.isEligibleForClinicalExecution` requires ACTIVE lifecycle,
  enablement, a passed evaluation and a recorded acceptance-set revision.
- **Failover changes the execution source, never the safety boundary.** The
  human-review requirement and the engine's risk, modality, privacy and
  structured-output minimums come from the policy, not from whichever candidate
  answered.
- **Only eligible failures advance the chain.** Safety blocks, authorization
  faults and invalid input terminate the attempt; they are not something a
  different provider can fix.
- **No silent degradation.** When no approved candidate is available the task
  returns a manual-workflow outcome.

Phase 1 registers unconfigured adapters, so every engine currently resolves to a
manual workflow. That is the correct state before any model has passed
evaluation, and the AI governance screen says so plainly.

### PHI in logs

`NodexLogger` redacts every record before it reaches a sink. Log call sites accept
non-PHI dimensions; identity-bearing keys are masked, nested structures are
dropped rather than walked, and JWTs, emails, ISO dates and long digit runs are
pattern-matched out of message text. Redaction is a safety net, not a licence to
pass clinical content into a log call.

---

## Repository layout

```text
lib/
├── main.dart                 # Bootstrap and composition root
├── app/
│   ├── app.dart              # Root widget, lifecycle, idle lock
│   ├── providers.dart        # Riverpod composition
│   ├── router/               # GoRouter, destination catalogue
│   ├── shell/                # Adaptive navigation, session status bar
│   └── theme/                # Material 3 clinical theme
├── core/
│   ├── authorization/        # Snapshot, policy, permission catalogue
│   ├── config/               # Build-time environment validation
│   ├── errors/               # Normalized error model and mapping
│   ├── logging/              # Redacting logger
│   ├── security/             # Key lifecycle, digest verification
│   ├── storage/              # PowerSync local schema
│   └── sync/                 # Conflict policy registry
├── data/
│   ├── local/                # Encrypted database lifecycle
│   ├── remote/               # Supabase transport boundary
│   └── sync/                 # PowerSync backend connector
├── domain/session/           # Session state and repository
├── features/                 # Auth, home, session, diagnostics, AI, audit, settings
└── ai/
    ├── contracts/            # Provider-neutral types
    ├── gateway/              # Gateway and adapters
    ├── model_registry/       # Registry and routing policy
    └── orchestrator/         # Routing, circuit breaker, engine catalogue
```

---

## Building

### Prerequisites

Flutter 3.47+, Android SDK with API 36, JDK 17.

Minimum supported device is **API 23**: SQLCipher and
`EncryptedSharedPreferences` both require it, and a device below that level
cannot store clinical data under the required protection.

### Configuration

Backend configuration is supplied at build time and never committed:

| Define | Required | Purpose |
|---|---|---|
| `NODEX_SUPABASE_URL` | yes | Supabase project URL |
| `NODEX_SUPABASE_PUBLISHABLE_KEY` | yes | Publishable (anon) key |
| `NODEX_POWERSYNC_URL` | no | PowerSync instance; omit to run local-only |
| `NODEX_ENVIRONMENT` | no | `development` \| `staging` \| `production` |
| `NODEX_AI_PROFILE_REVISION` | production | Versioned AI deployment profile |
| `NODEX_OFFLINE_WINDOW_MINUTES` | no | Requested offline window (default 720) |
| `NODEX_SESSION_IDLE_MINUTES` | no | Idle lock timeout (default 15) |

Startup validation refuses to run rather than shipping a misconfigured clinical
app. It rejects a `service_role` JWT or an `sb_secret_` key outright — those
bypass RLS and would defeat the tier-3 boundary — and refuses cleartext
transport in a production build.

```bash
flutter pub get

flutter run \
  --dart-define=NODEX_SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=NODEX_SUPABASE_PUBLISHABLE_KEY=sb_publishable_... \
  --dart-define=NODEX_POWERSYNC_URL=https://your-instance.powersync.journeyapps.com

flutter build apk --release --split-per-abi \
  --dart-define=NODEX_ENVIRONMENT=production \
  --dart-define=NODEX_SUPABASE_URL=... \
  --dart-define=NODEX_SUPABASE_PUBLISHABLE_KEY=... \
  --dart-define=NODEX_AI_PROFILE_REVISION=20260901.01
```

Release signing is not configured. The release build type currently falls back to
the debug key so verification builds succeed; supply real signing material before
distributing anything.

### Verification

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos --fatal-warnings
flutter test
```

CI runs all three on every push, builds a debug APK as an artifact, and builds
split-per-ABI release APKs for `v*` tags. A release build fails fast if backend
secrets are absent, because a production build with placeholder configuration
would look installable while reaching nothing.

---

## Roadmap

| Phase | Scope | State |
|---|---|---|
| 1 | Platform foundation | Done |
| 2 | Core clinical: MPI, timeline, appointments, EMR, prescriptions, lab, pharmacy, beds, discharge, billing | Next |
| 3 | Acute and enterprise: emergency, ICU, OT, radiology, blood bank, inventory, HR, insurance, consent, quality, reports | Planned |
| 4 | AI foundation: real adapters, edge GGUF runtime, Whisper/MedASR, LFM2.5-VL-450M, rule engine, validators, benchmark harness | Planned |
| 5 | Hardware and telehealth: barcode, FCM, WorkManager, WebRTC, thermal printing | Planned |
| 6 | Production hardening: performance, security review, RLS audit, conflict testing, DR, observability | Planned |

### Module definition of done

Before a module is complete: documented entities and invariants; PostgreSQL
schema and RLS implemented and tested; PowerSync schema and sync behaviour
defined; layered without boundary violations; offline create/read/update tested;
conflict and retry behaviour tested; audit events defined; RBAC/ABAC matrix
complete; phone and tablet adaptation with accessibility basics; loading, empty,
error and sync states; explicit AI safety boundaries where AI is used; unit,
integration and end-to-end tests; documentation and migrations included.

---

## Clinical governance

NODEX provides technical controls that support healthcare security and governance
programmes: strong authentication, least privilege, auditability, encryption,
tenant isolation, data minimisation and controlled clinical AI.

The architecture is not itself a claim of regulatory certification or clinical
validation. AI output is advisory and non-autonomous until intended-use
validation and governance approve deployment. Deployment-specific legal,
administrative, contractual, policy, security, clinical and operational controls
must be validated separately.

## References

- [PowerSync: RLS and sync streams](https://docs.powersync.com/integrations/supabase/rls-and-sync-streams)
- [PowerSync: client architecture](https://docs.powersync.com/architecture/client-architecture)
- [FCM message priority](https://firebase.google.com/docs/cloud-messaging/customize-messages/setting-message-priority) — FCM is not designed for life-critical use, so NODEX treats it as a secondary channel
- [FDA: Good Machine Learning Practice](https://www.fda.gov/medical-devices/software-medical-device-samd/good-machine-learning-practice-medical-device-development-guiding-principles)
- [WHO: Ethics and governance of AI for health](https://www.who.int/publications/i/item/9789240084759)

## License

Add the organisation's approved licence before publishing.
