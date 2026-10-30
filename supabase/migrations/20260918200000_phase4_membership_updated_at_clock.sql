-- NODEX Phase 4 follow-up: give memberships a wall-clock updated_at.
--
-- The shared nodex.tg_set_updated_at() trigger uses now(), which is frozen at
-- transaction start. A sweep that runs in the same transaction as another
-- membership write can therefore leave updated_at unchanged, and PowerSync
-- sees no row version to replicate. Memberships drive authorization buckets,
-- so their updated_at must advance on every real update. This dedicated
-- trigger keeps the rest of the schema on the shared behaviour.

create or replace function nodex.tg_membership_set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := clock_timestamp();
  return new;
end;
$$;

revoke all on function nodex.tg_membership_set_updated_at() from public;

drop trigger if exists memberships_set_updated_at on public.memberships;

create trigger memberships_set_updated_at
  before update on public.memberships
  for each row execute function nodex.tg_membership_set_updated_at();
