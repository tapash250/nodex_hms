-- NODEX Phase 4 follow-up: make the membership expiry sweep use the wall
-- clock, not the transaction start time.
--
-- `now()` is frozen for the whole transaction. If the same transaction has
-- already touched a membership row (for example, a test that moves valid_until
-- into the past), the sweep's `updated_at = now()` can write the same value the
-- row already carries. PowerSync then sees no change and keeps the expired
-- membership buckets. `clock_timestamp()` advances within the transaction and
-- matches the exact-instant semantics already used by membership_is_current().
--
-- The WHERE clause also uses clock_timestamp() so the decision and the WAL
-- event share one wall-clock instant.

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
         updated_at = clock_timestamp()
   where status = 'active'
     and valid_until is not null
     and valid_until <= clock_timestamp();

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

comment on function nodex.expire_memberships() is
  'Marks active memberships expired when valid_until has passed. The UPDATE is the WAL event PowerSync uses to evict the membership buckets. Uses clock_timestamp() so the event timestamp advances even inside a transaction that already touched the row.';

revoke all on function nodex.expire_memberships() from public;
