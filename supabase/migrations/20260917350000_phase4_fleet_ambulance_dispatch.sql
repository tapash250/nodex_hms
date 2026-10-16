-- NODEX Phase 4, Module 27: Fleet & Ambulance Dispatch.
--
-- Specification scope: "Vehicles, GPS, dispatch, driver rosters, emergency
-- transit."
--
-- This is the operational reach of the hospital: the vehicles that move a
-- patient to definitive care. It is a distinct domain from the ward roster
-- (Module 09 `staff_shifts`), which schedules clinical cover inside the
-- building; an ambulance crew is assigned to a vehicle for a duty window, and
-- the vehicle — not the ward — is the resource being scheduled.
--
-- Four tables, matching the four moving parts:
--
--   * `ambulances` is the fleet registry: the vehicle, its capability and its
--     service status. It is a living record while in service and freezes when
--     archived.
--   * `ambulance_duty_assignments` is the driver roster: a driver (and optional
--     attendant) assigned to a vehicle for a window. Two overlapping duties may
--     never claim the same vehicle or the same driver — a rule the database
--     enforces, not the UI.
--   * `ambulance_dispatches` is the emergency transit job. It is a guarded state
--     machine (requested -> assigned -> en_route -> on_scene -> completed, or
--     cancelled) because "this vehicle reached this scene at this time" is an
--     assertion an incident review is audited on. Terminal jobs freeze.
--   * `ambulance_tracking_pings` is the coarse last-known position, append-only.
--     This is *not* a live GPS stream: a device buffers a ping and the ping
--     syncs when the network returns, which is enough to answer "where was the
--     vehicle last seen" and deliberately does not pretend to be real-time
--     telemetry.
--
-- Dispatching must work when the network does not: `fleet.dispatch` is
-- therefore elevated but offline-capable. The three permissions are granted
-- explicitly because the Phase 1 all-permissions seed predates these keys.

create table public.ambulances (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  -- The facility the vehicle is stationed at.
  facility_id uuid not null references public.facilities(id) on delete restrict,
  call_sign text not null check (length(btrim(call_sign)) > 0),
  registration_no text
    check (registration_no is null or length(btrim(registration_no)) > 0),
  vehicle_type text not null default 'bls'
    check (vehicle_type in ('als','bls','patient_transport','neonatal','air','other')),
  capacity int not null default 1 check (capacity between 0 and 12),
  capability_notes text
    check (capability_notes is null or length(btrim(capability_notes)) > 0),
  service_status text not null default 'in_service'
    check (service_status in ('in_service','maintenance','out_of_service','archived')),
  created_by uuid not null references public.app_users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, call_sign),
  -- Null registration numbers are distinct, so a vehicle without a plate may be
  -- registered; a plate that is recorded is unique within the tenant.
  unique (tenant_id, registration_no)
);
create index ambulances_facility_idx
  on public.ambulances(tenant_id, facility_id, service_status);

create trigger ambulances_set_updated_at before update on public.ambulances
  for each row execute function nodex.tg_set_updated_at();

-- A vehicle in service is routinely moved between service, maintenance and
-- out-of-service. Archiving is terminal and freezes the whole row, so the
-- registration and call sign a historical dispatch names cannot be rewritten.
create or replace function nodex.tg_ambulance_archive_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.service_status = 'archived' then
    if new.service_status is distinct from old.service_status
      or new.call_sign is distinct from old.call_sign
      or new.registration_no is distinct from old.registration_no
      or new.vehicle_type is distinct from old.vehicle_type
      or new.capacity is distinct from old.capacity
      or new.capability_notes is distinct from old.capability_notes
      or new.facility_id is distinct from old.facility_id then
      raise exception using
        message = 'NODEX: an archived vehicle is immutable',
        errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;
create trigger ambulances_archive_guard before update on public.ambulances
  for each row execute function nodex.tg_ambulance_archive_guard();
create trigger ambulances_retain before delete on public.ambulances
  for each row execute function nodex.tg_block_mutation();

-- The driver roster: a crew assigned to a vehicle for a duty window.
create table public.ambulance_duty_assignments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  ambulance_id uuid not null references public.ambulances(id) on delete restrict,
  driver_user_id uuid not null references public.app_users(id) on delete restrict,
  attendant_user_id uuid references public.app_users(id) on delete set null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  status text not null default 'scheduled'
    check (status in ('scheduled','active','completed','cancelled')),
  notes text check (notes is null or length(btrim(notes)) > 0),
  created_by uuid not null references public.app_users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ambulance_duty_window_ck check (ends_at > starts_at),
  constraint ambulance_duty_attendant_ck check (
    attendant_user_id is null or attendant_user_id <> driver_user_id
  )
);
create index ambulance_duty_vehicle_idx
  on public.ambulance_duty_assignments(tenant_id, ambulance_id, starts_at);
create index ambulance_duty_driver_idx
  on public.ambulance_duty_assignments(tenant_id, driver_user_id, starts_at);

create trigger ambulance_duty_set_updated_at before update on public.ambulance_duty_assignments
  for each row execute function nodex.tg_set_updated_at();

-- Live duties (scheduled or active) may not overlap for the same vehicle or the
-- same driver, and a completed or cancelled duty is frozen. Enforced in the
-- database because two tablets can be scheduling at once and neither can see the
-- other's un-synced row.
create or replace function nodex.tg_ambulance_duty_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'UPDATE' and old.status in ('completed', 'cancelled') then
    if new.status is distinct from old.status
      or new.ambulance_id is distinct from old.ambulance_id
      or new.driver_user_id is distinct from old.driver_user_id
      or new.attendant_user_id is distinct from old.attendant_user_id
      or new.starts_at is distinct from old.starts_at
      or new.ends_at is distinct from old.ends_at
      or new.notes is distinct from old.notes then
      raise exception using
        message = 'NODEX: a closed duty assignment is immutable',
        errcode = '42501';
    end if;
  end if;

  if new.status in ('completed', 'cancelled') and (tg_op = 'INSERT' or old.status not in ('scheduled', 'active')) then
    raise exception using
      message = 'NODEX: only a scheduled or active duty may be closed',
      errcode = '42501';
  end if;

  if new.status in ('scheduled', 'active') then
    if exists (
      select 1 from public.ambulance_duty_assignments d
      where d.tenant_id = new.tenant_id
        and d.id <> new.id
        and d.status in ('scheduled', 'active')
        and d.ambulance_id = new.ambulance_id
        and tstzrange(d.starts_at, d.ends_at, '[)') && tstzrange(new.starts_at, new.ends_at, '[)')
    ) then
      raise exception using
        message = 'NODEX: this vehicle already has a duty in that window',
        errcode = '23505';
    end if;
    if exists (
      select 1 from public.ambulance_duty_assignments d
      where d.tenant_id = new.tenant_id
        and d.id <> new.id
        and d.status in ('scheduled', 'active')
        and d.driver_user_id = new.driver_user_id
        and tstzrange(d.starts_at, d.ends_at, '[)') && tstzrange(new.starts_at, new.ends_at, '[)')
    ) then
      raise exception using
        message = 'NODEX: this driver already has a duty in that window',
        errcode = '23505';
    end if;
  end if;
  return new;
end;
$$;
create trigger ambulance_duty_guard before insert or update on public.ambulance_duty_assignments
  for each row execute function nodex.tg_ambulance_duty_guard();
create trigger ambulance_duty_retain before delete on public.ambulance_duty_assignments
  for each row execute function nodex.tg_block_mutation();

-- The emergency transit job.
create table public.ambulance_dispatches (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  facility_id uuid not null references public.facilities(id) on delete restrict,
  ambulance_id uuid references public.ambulances(id) on delete set null,
  duty_assignment_id uuid references public.ambulance_duty_assignments(id) on delete set null,
  driver_user_id uuid references public.app_users(id) on delete set null,
  -- Either a registered patient or, for a scene call, a name taken in the field.
  patient_id uuid references public.patients(id) on delete set null,
  patient_name_text text
    check (patient_name_text is null or length(btrim(patient_name_text)) > 0),
  priority text not null default 'emergency'
    check (priority in ('emergency','urgent','routine')),
  status text not null default 'requested'
    check (status in ('requested','assigned','en_route','on_scene','completed','cancelled')),
  requesting_reference text
    check (requesting_reference is null or length(btrim(requesting_reference)) > 0),
  pickup_address text not null check (length(btrim(pickup_address)) > 0),
  destination_address text
    check (destination_address is null or length(btrim(destination_address)) > 0),
  destination_facility text
    check (destination_facility is null or length(btrim(destination_facility)) > 0),
  requested_at timestamptz not null default now(),
  dispatched_at timestamptz,
  on_scene_at timestamptz,
  completed_at timestamptz,
  cancellation_reason text
    check (cancellation_reason is null or length(btrim(cancellation_reason)) > 0),
  notes text check (notes is null or length(btrim(notes)) > 0),
  created_by uuid not null references public.app_users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- A job must be able to name the patient, even at a scene.
  constraint ambulance_dispatch_patient_ck check (
    patient_id is not null or patient_name_text is not null
  ),
  -- From the point it is assigned, a job must name the responding vehicle. A
  -- cancelled job is exempt: it may have been called off before assignment.
  constraint ambulance_dispatch_assignment_ck check (
    status in ('requested', 'cancelled') or ambulance_id is not null
  ),
  constraint ambulance_dispatch_completion_ck check (
    (status = 'completed' and completed_at is not null)
    or (status <> 'completed' and completed_at is null)
  )
);
create index ambulance_dispatches_active_idx
  on public.ambulance_dispatches(tenant_id, status, priority, requested_at);
create index ambulance_dispatches_vehicle_idx
  on public.ambulance_dispatches(tenant_id, ambulance_id, requested_at desc);
create index ambulance_dispatches_patient_idx
  on public.ambulance_dispatches(tenant_id, patient_id, requested_at desc);

create trigger ambulance_dispatches_set_updated_at before update on public.ambulance_dispatches
  for each row execute function nodex.tg_set_updated_at();
create trigger ambulance_dispatches_retain before delete on public.ambulance_dispatches
  for each row execute function nodex.tg_block_mutation();

-- The transit state machine. A job moves forward one step at a time and may be
-- cancelled from any live state; a terminal job is frozen so the times an
-- incident review turns on cannot be rewritten.
create or replace function nodex.tg_ambulance_dispatch_transition_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status in ('completed', 'cancelled') then
    raise exception using
      message = 'NODEX: a closed dispatch is immutable',
      errcode = '42501';
  end if;
  if new.status = old.status then
    return new;
  end if;
  if new.status = 'cancelled' then
    return new;
  end if;
  if (old.status = 'requested' and new.status = 'assigned')
    or (old.status = 'assigned' and new.status = 'en_route')
    or (old.status = 'en_route' and new.status = 'on_scene')
    or (old.status = 'on_scene' and new.status = 'completed') then
    return new;
  end if;
  raise exception using
    message = 'NODEX: a dispatch may not skip a stage',
    errcode = '42501';
end;
$$;
create trigger ambulance_dispatches_transition_guard
  before update on public.ambulance_dispatches
  for each row execute function nodex.tg_ambulance_dispatch_transition_guard();

-- Coarse last-known position. Append-only: a ping is a moment, and a second ping
-- is a second row.
create table public.ambulance_tracking_pings (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  ambulance_id uuid not null references public.ambulances(id) on delete restrict,
  dispatch_id uuid references public.ambulance_dispatches(id) on delete set null,
  latitude numeric(9,6) not null check (latitude between -90 and 90),
  longitude numeric(9,6) not null check (longitude between -180 and 180),
  speed_kph numeric(6,2) check (speed_kph is null or speed_kph between 0 and 400),
  recorded_at timestamptz not null default now(),
  source text not null default 'device' check (source in ('device','manual')),
  created_at timestamptz not null default now()
);
create index ambulance_tracking_vehicle_idx
  on public.ambulance_tracking_pings(tenant_id, ambulance_id, recorded_at desc);
create index ambulance_tracking_dispatch_idx
  on public.ambulance_tracking_pings(dispatch_id, recorded_at desc);
create trigger ambulance_tracking_append_only
  before update or delete on public.ambulance_tracking_pings
  for each row execute function nodex.tg_block_mutation();

alter table public.ambulances enable row level security;
alter table public.ambulances force row level security;
alter table public.ambulance_duty_assignments enable row level security;
alter table public.ambulance_duty_assignments force row level security;
alter table public.ambulance_dispatches enable row level security;
alter table public.ambulance_dispatches force row level security;
alter table public.ambulance_tracking_pings enable row level security;
alter table public.ambulance_tracking_pings force row level security;

create policy ambulances_select_member on public.ambulances for select to authenticated
  using (nodex.has_permission(tenant_id, 'fleet.read'));
create policy ambulances_insert_manager on public.ambulances for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'fleet.manage'));
create policy ambulances_update_manager on public.ambulances for update to authenticated
  using (nodex.has_permission(tenant_id, 'fleet.manage'))
  with check (nodex.has_permission(tenant_id, 'fleet.manage'));

create policy ambulance_duty_select_member on public.ambulance_duty_assignments for select to authenticated
  using (nodex.has_permission(tenant_id, 'fleet.read'));
create policy ambulance_duty_insert_manager on public.ambulance_duty_assignments for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'fleet.manage'));
create policy ambulance_duty_update_manager on public.ambulance_duty_assignments for update to authenticated
  using (nodex.has_permission(tenant_id, 'fleet.manage'))
  with check (nodex.has_permission(tenant_id, 'fleet.manage'));

create policy ambulance_dispatches_select_member on public.ambulance_dispatches for select to authenticated
  using (nodex.has_permission(tenant_id, 'fleet.read'));
create policy ambulance_dispatches_insert_dispatcher on public.ambulance_dispatches for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'fleet.dispatch'));
create policy ambulance_dispatches_update_dispatcher on public.ambulance_dispatches for update to authenticated
  using (nodex.has_permission(tenant_id, 'fleet.dispatch'))
  with check (nodex.has_permission(tenant_id, 'fleet.dispatch'));

create policy ambulance_tracking_select_member on public.ambulance_tracking_pings for select to authenticated
  using (nodex.has_permission(tenant_id, 'fleet.read'));
create policy ambulance_tracking_insert_dispatcher on public.ambulance_tracking_pings for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'fleet.dispatch'));

insert into public.permissions (key, display_name, description, module_code, risk_tier, requires_online)
values
  ('fleet.read',     'Read fleet and dispatch',  'View vehicles, driver rosters, dispatches and tracking.', 'M27', 'standard', false),
  ('fleet.dispatch', 'Dispatch ambulances',      'Raise, progress and cancel emergency ambulance dispatches.', 'M27', 'elevated', false),
  ('fleet.manage',   'Manage fleet',             'Register vehicles and maintain driver duty rosters.',      'M27', 'elevated', false)
on conflict (key) do nothing;

insert into public.role_permissions (role_key, permission_key)
values
  ('hospital_super_admin', 'fleet.read'),
  ('hospital_super_admin', 'fleet.dispatch'),
  ('hospital_super_admin', 'fleet.manage'),
  ('medical_officer',      'fleet.read'),
  ('medical_officer',      'fleet.dispatch'),
  ('nursing_staff',        'fleet.read'),
  ('nursing_staff',        'fleet.dispatch'),
  ('auditor',              'fleet.read')
on conflict do nothing;
