-- NODEX Phase 3, Module 24: Hospital floor map visualizer.
--
-- Rooms are the layout unit the floor map draws: each belongs to a facility,
-- optionally to a ward, and carries the floor it sits on plus grid geometry
-- and a declared capacity. Real-time occupancy is not stored here: it is
-- derived from beds and bed assignments, which the census already replicates,
-- so occupancy can never drift from the authoritative allocation.
--
-- Room layout and capacity are shared hospital configuration. Two devices
-- cannot both claim the same room code or disagree about a room's capacity, so
-- the server arbitrates and the client reconciles.
--
-- RLS uses membership-derived permissions, and FKs target app_users.

create table public.ward_rooms (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  facility_id uuid not null references public.facilities(id) on delete restrict,
  ward_id uuid references public.wards(id) on delete restrict,
  room_code text not null check (length(btrim(room_code)) > 0),
  room_name text not null check (length(btrim(room_name)) > 0),
  room_type text not null check (room_type in ('ward','icu','theatre','emergency','diagnostics','pharmacy','utility','office')),
  floor_label text not null check (length(btrim(floor_label)) > 0),
  capacity integer not null default 1 check (capacity > 0 and capacity <= 500),
  grid_x integer not null default 0 check (grid_x >= 0 and grid_x < 200),
  grid_y integer not null default 0 check (grid_y >= 0 and grid_y < 200),
  grid_span_x integer not null default 1 check (grid_span_x > 0 and grid_span_x <= 20),
  grid_span_y integer not null default 1 check (grid_span_y > 0 and grid_span_y <= 20),
  status text not null default 'active' check (status in ('active','retired')),
  retired_by uuid references public.app_users(id) on delete restrict,
  retired_at timestamptz,
  retirement_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- Room codes repeat across buildings, so uniqueness is per facility.
  unique (tenant_id, facility_id, room_code),
  constraint ward_room_retired_ck check ((status = 'retired' and retired_at is not null and retirement_reason is not null and length(btrim(retirement_reason)) > 0) or status = 'active')
);
create index ward_rooms_floor_idx on public.ward_rooms(tenant_id, floor_label, room_code);
create index ward_rooms_ward_idx on public.ward_rooms(ward_id, floor_label);

create trigger ward_rooms_set_updated_at before update on public.ward_rooms for each row execute function nodex.tg_set_updated_at();

-- A retired room is out of the layout: its code, capacity and geometry are
-- frozen so a historical floor map still reads correctly.
create or replace function nodex.tg_ward_room_retirement_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status = 'retired' then
    if new.tenant_id is distinct from old.tenant_id
      or new.facility_id is distinct from old.facility_id
      or new.ward_id is distinct from old.ward_id
      or new.room_code is distinct from old.room_code
      or new.room_name is distinct from old.room_name
      or new.room_type is distinct from old.room_type
      or new.floor_label is distinct from old.floor_label
      or new.capacity is distinct from old.capacity
      or new.grid_x is distinct from old.grid_x
      or new.grid_y is distinct from old.grid_y
      or new.grid_span_x is distinct from old.grid_span_x
      or new.grid_span_y is distinct from old.grid_span_y
      or new.retired_by is distinct from old.retired_by
      or new.retired_at is distinct from old.retired_at
      or new.retirement_reason is distinct from old.retirement_reason then
      raise exception using message = 'NODEX: retired ward rooms are immutable', errcode = '42501';
    end if;
  end if;
  if new.status = 'retired' and (new.retired_at is null or new.retirement_reason is null) then
    raise exception using message = 'NODEX: retiring a ward room requires timestamp and reason', errcode = '22000';
  end if;
  return new;
end;
$$;
create trigger ward_rooms_retirement_guard before update on public.ward_rooms for each row execute function nodex.tg_ward_room_retirement_guard();
create trigger ward_rooms_append_only_delete before delete on public.ward_rooms for each row execute function nodex.tg_block_mutation();

alter table public.ward_rooms enable row level security;
alter table public.ward_rooms force row level security;

-- Layout is administrative configuration, readable by anyone who may see the
-- ward census and writable only by ward administration.
create policy ward_rooms_select_member on public.ward_rooms for select to authenticated using (nodex.has_permission(tenant_id,'ward_floor.read'));
create policy ward_rooms_insert_writer on public.ward_rooms for insert to authenticated with check (nodex.has_permission(tenant_id,'ward_room.write'));
create policy ward_rooms_update_writer on public.ward_rooms for update to authenticated using (nodex.has_permission(tenant_id,'ward_room.write')) with check (nodex.has_permission(tenant_id,'ward_room.write'));
