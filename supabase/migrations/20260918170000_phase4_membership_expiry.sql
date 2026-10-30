-- NODEX Phase 4 follow-up: deterministic membership expiry.
--
-- PowerSync Sync Streams cannot evaluate now(). A membership whose valid_until
-- passed but whose status is still 'active' keeps its replication buckets until
-- some row changes. This migration makes expiry a WAL event and keeps the
-- zero-latency write guard in the existing RLS helpers and the new mutation
-- trigger.
--
-- Two layers:
--   1. nodex.expire_memberships() flips active -> expired when valid_until has
--      passed. pg_cron runs it every minute. The UPDATE emits WAL, so PowerSync
--      removes the buckets on the next replication checkpoint.
--   2. RLS helpers already require status='active' and valid_until > now().
--      The mutation trigger in 20260918160000 uses clock_timestamp() so a write
--      is refused at the exact expiry instant, without waiting for the sweep.
--
-- Clients cannot extend their own membership: the guard below refuses a
-- self-insert and any self-update of role, scope, status or validity. A second
-- administrator performs a renewal.

-- ---------------------------------------------------------------------------
-- 1. Status vocabulary.
-- ---------------------------------------------------------------------------

do $$
declare
  c record;
begin
  for c in
    select conname
      from pg_constraint
     where conrelid = 'public.memberships'::regclass
       and contype = 'c'
       and pg_get_constraintdef(oid) like '%status%'
  loop
    execute format('alter table public.memberships drop constraint %I', c.conname);
  end loop;
end;
$$;

alter table public.memberships
  add constraint memberships_status_check
  check (status in ('active', 'suspended', 'revoked', 'expired'));

create index if not exists memberships_expiry_idx
  on public.memberships (valid_until)
  where status = 'active' and valid_until is not null;

-- ---------------------------------------------------------------------------
-- 2. WAL-driven sweep.
-- ---------------------------------------------------------------------------

create or replace function nodex.expire_memberships()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  update public.memberships
     set status = 'expired',
         updated_at = now()
   where status = 'active'
     and valid_until is not null
     and valid_until <= now();

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

comment on function nodex.expire_memberships() is
  'Marks active memberships expired when valid_until has passed. The UPDATE is the WAL event PowerSync uses to evict the membership buckets.';

revoke all on function nodex.expire_memberships() from public;

-- pg_cron is a Supabase-managed extension. The migration runner is the
-- `postgres` role, which is not a superuser and cannot install it. Fail with a
-- clear precondition instead of a cryptic permission error from CREATE
-- EXTENSION. Enable Supabase Cron in the dashboard, then rerun this migration.
do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise exception using
      message = 'NODEX: pg_cron is not enabled; enable Supabase Cron (Dashboard > Integrations > Cron) and rerun this migration',
      errcode = '55000',
      hint = 'The membership expiry sweep must emit WAL so PowerSync evicts expired buckets.';
  end if;

  if to_regclass('cron.job') is null then
    raise exception using
      message = 'NODEX: the cron.job table is missing; repair the pg_cron installation and rerun this migration',
      errcode = '55000';
  end if;
end;
$$;

-- The schedule is idempotent by job name: remove an earlier job before adding
-- the current definition.
do $$
begin
  perform cron.unschedule('nodex-expire-memberships')
   where exists (
     select 1 from cron.job where jobname = 'nodex-expire-memberships'
   );
end;
$$;

select cron.schedule(
  'nodex-expire-memberships',
  '* * * * *',
  'select nodex.expire_memberships()'
);

-- ---------------------------------------------------------------------------
-- 3. Client self-escalation guard.
-- ---------------------------------------------------------------------------

create or replace function nodex.tg_membership_self_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if nodex.is_service_role() then
    return new;
  end if;

  -- A SQL-editor / migration path has no end-user identity. It is an
  -- administrative path, not a client mutation.
  if auth.uid() is null then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.user_id = auth.uid() then
      raise exception using
        message = 'NODEX: a membership cannot be self-granted; a second administrator must grant it',
        errcode = '42501';
    end if;
    return new;
  end if;

  -- The subject of a membership is immutable. Without this, an administrator
  -- could move another user's existing grant onto their own identity instead of
  -- creating a self-grant, which the INSERT branch above already refuses.
  if new.user_id is distinct from old.user_id then
    raise exception using
      message = 'NODEX: membership user_id is immutable; revoke and regrant instead',
      errcode = '42501';
  end if;

  -- Reactivating an already-expired validity window is not a renewal.
  if new.status = 'active'
     and new.valid_until is not null
     and new.valid_until <= clock_timestamp() then
    raise exception using
      message = 'NODEX: an active membership must have a future valid_until; renew the window first',
      errcode = '42501';
  end if;

  if old.user_id = auth.uid() then
    if new.role_key      is distinct from old.role_key
       or new.tenant_id  is distinct from old.tenant_id
       or new.status     is distinct from old.status
       or new.valid_from is distinct from old.valid_from
       or new.valid_until is distinct from old.valid_until
       or new.facility_id is distinct from old.facility_id
       or new.department_id is distinct from old.department_id
       or new.ward_id    is distinct from old.ward_id
       or new.granted_by is distinct from old.granted_by
       or new.created_at is distinct from old.created_at then
      raise exception using
        message = 'NODEX: a membership cannot change its own role, scope, status or validity',
        errcode = '42501';
    end if;
  end if;

  return new;
end;
$$;

comment on function nodex.tg_membership_self_guard() is
  'Refuses self-grant and self-extension of a membership. Renewal is a second-administrator action.';

drop trigger if exists memberships_self_guard on public.memberships;
create trigger memberships_self_guard
  before insert or update on public.memberships
  for each row execute function nodex.tg_membership_self_guard();

-- ---------------------------------------------------------------------------
-- 4. Verification helpers.
-- ---------------------------------------------------------------------------

create or replace function nodex.membership_is_current(
  p_tenant_id uuid,
  p_user_id   uuid default auth.uid()
)
returns boolean
language sql
volatile
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.memberships m
     where m.user_id = p_user_id
       and m.tenant_id = p_tenant_id
       and m.status = 'active'
       and m.valid_from <= clock_timestamp()
       and (m.valid_until is null or m.valid_until > clock_timestamp())
  );
$$;

comment on function nodex.membership_is_current(uuid, uuid) is
  'Exact-instant membership check for the mutation path. RLS helpers remain statement-stable and are equivalent at statement boundaries.';

-- Internal helper. A client must not be able to probe another user's
-- membership by supplying an arbitrary p_user_id.
revoke all on function nodex.membership_is_current(uuid, uuid) from public;
