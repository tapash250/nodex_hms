# Backup and restore

How NODEX protects the Postgres system of record and how to bring it back.
This defines the targets and the procedure; **exercising a restore is a
rehearsal you run against a scratch project, never against production** (see
[Rehearsal](#rehearsal)).

## What is authoritative

Postgres (project `neoernavfntxsotwvmwq`, `Nodex_HMS`) is the single source of
truth for clinical data. Device-side SQLite is a replicated projection with a
retention policy; losing a device loses no record. Everything a user could ever
need to reconstruct a full day of work is in Postgres.

## Targets

Clinical defaults (confirm with the hospital's clinical governance before
sign-off; these are proposed, not agreed):

| Metric | Target | Rationale |
| --- | --- | --- |
| **RPO** (max data loss) | ≤ 5 minutes | Point-in-time recovery (PITR) on the database bounds loss to the WAL window; a 5-minute target has headroom over the minimum granularity. |
| **RTO** (max downtime) | ≤ 2 hours | Time to provision a recovery target and promote it. Clinical downtime beyond this escalates to the downtime procedure. |

If the plan is Free/Pro without PITR, RPO is instead the daily-backup interval
(up to 24h) — which does **not** meet the target, so enable PITR before go-live.

## Two recovery modes

1. **Point-in-time recovery (preferred).** Restores to any second within the
   retention window. Use for logical corruption — a bad migration, a mistaken
   bulk update, a dropped table — where the damage is recent and the rest of the
   data is fine.
2. **Full backup restore.** Used when PITR is unavailable or the whole database
   must be relocated (e.g. a new project/region). Loses everything since the
   backup taken.

## Procedure

Record every step in the incident ticket. Nothing here is done causally.

### 1. Declare and freeze
- Open an incident, note the trigger time (what went wrong, when).
- **Stop writes to the affected system.** If the app is still mutating, disable
  the mutation path first; restoring under live writes re-corrupts.

### 2. Choose the recovery target
- PITR: pick the timestamp **just before** the first bad write. When in doubt,
  err earlier — an earlier restore followed by replaying known-good work is
  recoverable; an after-the-fact restore is not.

### 3. Restore to a NEW project/instance
Never restore in place over production. Create a fresh project (same region,
same Postgres major) and restore into it, then verify, then cut over:
- `pg_restore` into the target, or PITR via the dashboard/API on the clone.
- Supabase-specific state to re-check after any restore: storage objects
  (Postgres restore does not move object bytes — reconcile the `clinical-*`
  buckets), auth users (`auth.*` is part of the DB but re-verify integrations),
  and the PowerSync reader role's grants (`powersync/SETUP.md`).

### 4. Verify before cutover
Restores that look complete but aren't are worse than an outage. At minimum:
- Row counts on the highest-churn tables (appointments, prescriptions,
  invoices, audit) are within the expected range for the recovery instant.
- Newest expected rows are present and the first bad row is absent.
- A tenant-scoped read returns the right tenant's rows **only** (membership RLS
  still holds after restore — proves the role/grant graph survived).
- One end-to-end mutation round-trips against the mutation handler.

### 5. Cut over
- Repoint the publishable key / API URL (and `NODEX_POWERSYNC_URL` if moving),
  redeploy the app + mutation handler, restore writes.
- Keep the damaged project read-only for forensics until the incident closes.

## Rehearsal

A restore that has never been run is a hypothesis. On a schedule (proposed:
quarterly, and after any material schema change):
1. Take a fresh backup (or use the newest).
2. Restore it to a scratch project.
3. Run the §4 verification checklist and time it end-to-end.
4. Record **measured RTO** against the ≤2h target and any gaps found.
5. If it failed, the incident is the runbook — fix the runbook or the setup, then
   re-rehearse.

Store the rehearsal result (date, measured RTO, outcome) next to this file's
incident log so the last-known-good date is always current.

## Roles

- Restore and cutover require the project owner / a role with database admin.
- The PowerSync reader and the mutation handler use their own least-privilege
  roles (see `powersync/SETUP.md` and the revoke-anon migration); a restored
  database must be re-checked so a restore hasn't silently widened them.
