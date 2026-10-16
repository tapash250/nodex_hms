-- NODEX Phase 4, Module 40: Institutional Calendar & Shift Overlay.
--
-- Specification scope: an institutional calendar that overlays the operational
-- roster, so a training day, an audit, a planned outage and the shift cover for
-- the same day can be read together.
--
-- The calendar owns only the institutional event. It deliberately does not own
-- the roster: shifts are Module 09 `staff_shifts`, and the "overlay" is the act
-- of reading them on the same axis, not a second copy that can drift. This
-- table also does not duplicate the HR holiday entitlement (Module 13
-- `hr_holidays`, which is a payroll-relevant entitlement); an institutional
-- holiday that matters operationally is an event here with type `holiday`.
--
-- An event is scheduled or cancelled, and cancellation is one-way: the row is
-- retained and frozen so a record that names the cancelled event stays
-- answerable. Events may overlap by design — a training day and a maintenance
-- window are allowed to coincide, and the calendar has no business forbidding
-- it.

create table public.calendar_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  -- Null facility means the event is institution-wide.
  facility_id uuid references public.facilities(id) on delete restrict,
  department_id uuid references public.departments(id) on delete set null,
  title text not null check (length(btrim(title)) > 0),
  description text check (description is null or length(btrim(description)) > 0),
  event_type text not null default 'other'
    check (event_type in ('holiday','training','audit','maintenance','academic','meeting','other')),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  -- A display hint that the event occupies whole days; times still bound it.
  all_day boolean not null default false,
  location text check (location is null or length(btrim(location)) > 0),
  status text not null default 'scheduled' check (status in ('scheduled','cancelled')),
  created_by uuid not null references public.app_users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint calendar_event_window_ck check (ends_at >= starts_at)
);
create index calendar_events_window_idx
  on public.calendar_events(tenant_id, starts_at, ends_at);
create index calendar_events_type_idx
  on public.calendar_events(tenant_id, event_type, status);

create trigger calendar_events_set_updated_at before update on public.calendar_events
  for each row execute function nodex.tg_set_updated_at();

-- A cancelled event is a retained record: it freezes so a document that names
-- the cancelled event cannot be quietly rewritten. Cancellation is one-way.
create or replace function nodex.tg_calendar_event_cancel_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status = 'cancelled' then
    if new.status is distinct from old.status
      or new.title is distinct from old.title
      or new.description is distinct from old.description
      or new.event_type is distinct from old.event_type
      or new.starts_at is distinct from old.starts_at
      or new.ends_at is distinct from old.ends_at
      or new.all_day is distinct from old.all_day
      or new.location is distinct from old.location
      or new.facility_id is distinct from old.facility_id
      or new.department_id is distinct from old.department_id then
      raise exception using message = 'NODEX: cancelled calendar events are immutable', errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;
create trigger calendar_events_cancel_guard before update on public.calendar_events
  for each row execute function nodex.tg_calendar_event_cancel_guard();
create trigger calendar_events_retain before delete on public.calendar_events
  for each row execute function nodex.tg_block_mutation();

alter table public.calendar_events enable row level security;
alter table public.calendar_events force row level security;

create policy calendar_events_select_member on public.calendar_events for select to authenticated
  using (nodex.has_permission(tenant_id, 'calendar.read'));
create policy calendar_events_insert_admin on public.calendar_events for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'calendar.manage'));
create policy calendar_events_update_admin on public.calendar_events for update to authenticated
  using (nodex.has_permission(tenant_id, 'calendar.manage'))
  with check (nodex.has_permission(tenant_id, 'calendar.manage'));

insert into public.permissions (key, display_name, description, module_code, risk_tier, requires_online)
values
  ('calendar.read',   'Read institutional calendar', 'View institutional events and the shift overlay.', 'M40', 'standard', false),
  ('calendar.manage', 'Manage institutional calendar', 'Create, edit and cancel institutional calendar events.', 'M40', 'elevated', false)
on conflict (key) do nothing;

insert into public.role_permissions (role_key, permission_key)
values
  ('hospital_super_admin', 'calendar.read'),
  ('hospital_super_admin', 'calendar.manage'),
  ('medical_officer',      'calendar.read'),
  ('nursing_staff',        'calendar.read'),
  ('lab_technician',       'calendar.read'),
  ('pharmacist',           'calendar.read'),
  ('billing_accounts',     'calendar.read'),
  ('auditor',              'calendar.read')
on conflict do nothing;
