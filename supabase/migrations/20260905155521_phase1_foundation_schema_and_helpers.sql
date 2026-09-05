-- NODEX Enterprise HMS - Phase 1 Foundation
-- Creates the private `nodex` schema used for authorization helper functions,
-- shared trigger utilities and append-only enforcement.
--
-- Design notes:
--   * PostgreSQL is the authoritative cloud system of record.
--   * RLS is the authoritative server-side CRUD boundary (Tier 3).
--   * Helper functions are SECURITY DEFINER + locked search_path so that
--     membership lookups inside policies cannot recurse into RLS.

create schema if not exists nodex;

revoke all on schema nodex from public;
grant usage on schema nodex to authenticated, service_role;

comment on schema nodex is
  'NODEX internal authorization helpers and trigger utilities. Not a client-facing API surface.';

-- ---------------------------------------------------------------------------
-- Shared trigger utilities
-- ---------------------------------------------------------------------------

create or replace function nodex.tg_set_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

comment on function nodex.tg_set_updated_at() is
  'BEFORE UPDATE trigger: maintains updated_at on mutable projection tables.';

-- Append-only enforcement for audit / clinical event tables.
-- Application-facing audit records must never be silently rewritten.
create or replace function nodex.tg_block_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception
    'NODEX append-only violation: % is not permitted on %.%',
    tg_op, tg_table_schema, tg_table_name
    using errcode = '42501';
end;
$$;

comment on function nodex.tg_block_mutation() is
  'BEFORE UPDATE/DELETE trigger: enforces append-only semantics on audit and clinical event tables.';

-- ---------------------------------------------------------------------------
-- Identity primitives used by every policy
-- ---------------------------------------------------------------------------

create or replace function nodex.current_user_id()
returns uuid
language sql
stable
security invoker
set search_path = ''
as $$
  select auth.uid();
$$;

comment on function nodex.current_user_id() is
  'Authenticated Supabase user id for the current request, or NULL.';

create or replace function nodex.is_service_role()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'),
    ''
  ) = 'service_role';
$$;

comment on function nodex.is_service_role() is
  'True when the request presents the Supabase service_role JWT (server-to-server only; never shipped in Android builds).';
