-- NODEX Enterprise HMS — PowerSync source database setup.
--
-- REVIEW ONLY. Do not run until the sync configuration has been approved.
-- Run as the Supabase `postgres` role (SQL Editor or `supabase db query`).
--
-- Executed on the development project on 2026-10-30 with a generated,
-- temporary password. The script is not idempotent; inspect a partial run
-- before rerunning.
--
-- Replace <GENERATED_PASSWORD> with a fresh secret, for example:
--   openssl rand -base64 32
-- Store the same value in the untracked .env file as
-- POWERSYNC_DATABASE_PASSWORD. Never commit it and never paste it into a chat.

-- ---------------------------------------------------------------------------
-- 1. Dedicated replication role.
--
-- REPLICATION: required for logical replication.
-- BYPASSRLS:    lookup queries in the sync config read memberships and
--               role_permissions, which have RLS enabled. The role must not be
--               the postgres superuser.
-- ---------------------------------------------------------------------------
create role powersync_role with replication bypassrls login
  password '<GENERATED_PASSWORD>';

grant usage on schema public to powersync_role;

-- ---------------------------------------------------------------------------
-- 2. Read-only access, limited to the tables the sync config reads.
--
-- The 15 initially synced tables plus the global role/permission catalogue,
-- which the stream lookup queries and the catalog stream read. This is the
-- initial 18-table set. Migration
-- 20260918200001_expand_powersync_full_coverage.sql extends the grant,
-- replica identity and publication to all 146 replicated tables. No table
-- outside that full set is granted.
-- ---------------------------------------------------------------------------
grant select on table
  public.app_users,
  public.memberships,
  public.devices,
  public.tenants,
  public.facilities,
  public.departments,
  public.wards,
  public.patients,
  public.patient_allergies,
  public.clinical_encounters,
  public.clinical_problems,
  public.encounter_amendments,
  public.doctor_assignments,
  public.beds,
  public.bed_assignments,
  public.roles,
  public.permissions,
  public.role_permissions
to powersync_role;

-- ---------------------------------------------------------------------------
-- 3. Replica identity.
--
-- Every table below has a primary key, including role_permissions, whose
-- primary key is (role_key, permission_key). REPLICA IDENTITY DEFAULT publishes
-- the primary key in the old tuple, which is enough for PowerSync to identify
-- the row to update or remove. FULL is only required for a table with no
-- primary key; using it here would enlarge every WAL record for no benefit.
-- ---------------------------------------------------------------------------
alter table public.app_users            replica identity default;
alter table public.memberships          replica identity default;
alter table public.devices              replica identity default;
alter table public.tenants              replica identity default;
alter table public.facilities           replica identity default;
alter table public.departments          replica identity default;
alter table public.wards                replica identity default;
alter table public.patients             replica identity default;
alter table public.patient_allergies    replica identity default;
alter table public.clinical_encounters  replica identity default;
alter table public.clinical_problems    replica identity default;
alter table public.encounter_amendments replica identity default;
alter table public.doctor_assignments   replica identity default;
alter table public.beds                 replica identity default;
alter table public.bed_assignments      replica identity default;
alter table public.roles                replica identity default;
alter table public.permissions          replica identity default;
alter table public.role_permissions     replica identity default;

-- ---------------------------------------------------------------------------
-- 4. Publication.
--
-- Initial synced tables plus the role/permission catalogue. PowerSync evaluates
-- stream lookup queries while it consumes replication, so a lookup table that
-- is not published cannot update a client's scope when it changes. The
-- full-coverage migration adds the remaining replicated tables; any later sync
-- config addition must also be granted and published there.
-- ---------------------------------------------------------------------------
create publication powersync for table
  public.app_users,
  public.memberships,
  public.devices,
  public.tenants,
  public.facilities,
  public.departments,
  public.wards,
  public.patients,
  public.patient_allergies,
  public.clinical_encounters,
  public.clinical_problems,
  public.encounter_amendments,
  public.doctor_assignments,
  public.beds,
  public.bed_assignments,
  public.roles,
  public.permissions,
  public.role_permissions;

-- ---------------------------------------------------------------------------
-- 5. Verification.
-- ---------------------------------------------------------------------------

-- Logical replication must already be enabled by the platform.
select name, setting, unit
from pg_settings
where name in ('wal_level', 'max_replication_slots', 'max_wal_senders')
order by name;

select rolname, rolreplication, rolbypassrls
from pg_roles
where rolname = 'powersync_role';

select tablename
from pg_publication_tables
where pubname = 'powersync'
order by tablename;

select c.relname, c.relreplident
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in (
    'app_users', 'memberships', 'devices', 'tenants', 'facilities',
    'departments', 'wards', 'patients', 'patient_allergies',
    'clinical_encounters', 'clinical_problems', 'encounter_amendments',
    'doctor_assignments', 'beds', 'bed_assignments', 'roles',
    'permissions', 'role_permissions'
  )
order by c.relname;
