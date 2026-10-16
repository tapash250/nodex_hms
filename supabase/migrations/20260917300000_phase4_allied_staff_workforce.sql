-- NODEX Phase 4, Module 09: Allied Staff & Workforce Manager.
--
-- Specification scope: "Shift management, duty rosters, task delegation, and
-- leave tracking for nursing, technicians, and orderlies", with the entities
-- `staff_shifts`, `duty_allocations` and `attendance_logs`.
--
-- A shift is a dated, staffable block of cover: a ward or department declares
-- it needs a headcount of a given staff category between two instants. Duty
-- allocations name the people filling it; attendance logs record what actually
-- happened. The three tables are separated because they fail differently: a
-- shift is configuration, an allocation is a commitment, and attendance is a
-- fact. Only the last is append-only.
--
-- The registry is membership-derived: `workforce.read` selects and
-- `workforce.manage` writes. Both are offline-capable, because a ward must be
-- able to see its own roster and record an unplanned absence while the network
-- is down; the server reconciles roster edits as authoritative (see the
-- `staff_shift`, `duty_allocation` and `attendance_log` conflict policies).
--
-- Leave is modelled as an allocation whose role and status are both `leave`.
-- A leave block therefore participates in the same overlap guard as a duty:
-- staff cannot be rostered onto a shift while recorded on approved leave.

-- One dated block of cover. A code identifies it within a facility and a day,
-- matching the `(tenant_id, facility_id, shift_date, shift_code)` uniqueness
-- the registry enforces.
create table public.staff_shifts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  facility_id uuid not null references public.facilities(id) on delete restrict,
  department_id uuid references public.departments(id) on delete set null,
  shift_date date not null,
  shift_code text not null check (length(btrim(shift_code)) > 0),
  display_name text not null check (length(btrim(display_name)) > 0),
  staff_category text not null check (staff_category in ('nursing','technician','orderly','allied','admin')),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  required_headcount integer not null default 1 check (required_headcount > 0 and required_headcount <= 200),
  status text not null default 'scheduled' check (status in ('scheduled','cancelled','closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, facility_id, shift_date, shift_code),
  constraint staff_shift_window_ck check (ends_at > starts_at)
);
create index staff_shifts_day_idx on public.staff_shifts(tenant_id, facility_id, shift_date);
create index staff_shifts_department_idx on public.staff_shifts(department_id, shift_date);
create index staff_shifts_window_idx on public.staff_shifts(starts_at, ends_at);

create trigger staff_shifts_set_updated_at before update on public.staff_shifts for each row execute function nodex.tg_set_updated_at();

-- A closed shift is a historical roster: its window and headcount are frozen
-- so an attendance report can always be explained.
create or replace function nodex.tg_staff_shift_close_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status = 'closed' then
    if new.tenant_id is distinct from old.tenant_id
      or new.facility_id is distinct from old.facility_id
      or new.department_id is distinct from old.department_id
      or new.shift_date is distinct from old.shift_date
      or new.shift_code is distinct from old.shift_code
      or new.display_name is distinct from old.display_name
      or new.staff_category is distinct from old.staff_category
      or new.starts_at is distinct from old.starts_at
      or new.ends_at is distinct from old.ends_at
      or new.required_headcount is distinct from old.required_headcount then
      raise exception using message = 'NODEX: closed staff shifts are immutable', errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;
create trigger staff_shifts_close_guard before update on public.staff_shifts for each row execute function nodex.tg_staff_shift_close_guard();
create trigger staff_shifts_append_only_delete before delete on public.staff_shifts for each row execute function nodex.tg_block_mutation();

-- One person's commitment to one shift. The unique key keeps a person from
-- being allocated twice to the same block; the overlap guard below keeps them
-- from being allocated to a second block that runs at the same time.
create table public.duty_allocations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  shift_id uuid not null references public.staff_shifts(id) on delete restrict,
  staff_user_id uuid not null references public.app_users(id) on delete restrict,
  allocation_role text not null default 'primary' check (allocation_role in ('primary','relief','supervisor','leave')),
  status text not null default 'allocated' check (status in ('allocated','completed','withdrawn','leave')),
  note text check (note is null or length(btrim(note)) > 0),
  allocated_by uuid not null references public.app_users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (shift_id, staff_user_id),
  constraint duty_allocation_leave_ck check (
    (allocation_role = 'leave' and status = 'leave')
    or (allocation_role <> 'leave' and status <> 'leave')
  )
);
create index duty_allocations_staff_idx on public.duty_allocations(staff_user_id, status);
create index duty_allocations_shift_idx on public.duty_allocations(shift_id, status);

create trigger duty_allocations_set_updated_at before update on public.duty_allocations for each row execute function nodex.tg_set_updated_at();
create trigger duty_allocations_append_only_delete before delete on public.duty_allocations for each row execute function nodex.tg_block_mutation();

-- A person cannot hold two concurrent commitments. Withdrawn rows and leave
-- blocks are excluded: withdrawing releases the window, and leave is the block
-- that duty must avoid rather than a duty itself.
create or replace function nodex.tg_duty_allocation_overlap_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_starts timestamptz;
  v_ends timestamptz;
begin
  if new.status = 'withdrawn' or new.allocation_role = 'leave' then
    return new;
  end if;
  select s.starts_at, s.ends_at into v_starts, v_ends
    from public.staff_shifts s where s.id = new.shift_id;
  if exists (
    select 1
      from public.duty_allocations a
      join public.staff_shifts s2 on s2.id = a.shift_id
     where a.staff_user_id = new.staff_user_id
       and a.id <> new.id
       and a.status in ('allocated','completed','leave')
       and s2.starts_at < v_ends
       and v_starts < s2.ends_at
  ) then
    raise exception using message = 'NODEX: staff member is already allocated to an overlapping shift', errcode = '23P01';
  end if;
  return new;
end;
$$;
create trigger duty_allocations_overlap_guard before insert or update on public.duty_allocations for each row execute function nodex.tg_duty_allocation_overlap_guard();

-- What actually happened: a fact, appended and never rewritten. A correction
-- is a further event, matching the append-only stance taken across the schema.
create table public.attendance_logs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  allocation_id uuid not null references public.duty_allocations(id) on delete restrict,
  staff_user_id uuid not null references public.app_users(id) on delete restrict,
  event_type text not null check (event_type in ('clock_in','clock_out','break_start','break_end','absence')),
  occurred_at timestamptz not null,
  recorded_by uuid not null references public.app_users(id) on delete restrict,
  note text check (note is null or length(btrim(note)) > 0),
  created_at timestamptz not null default now()
);
create index attendance_logs_allocation_idx on public.attendance_logs(allocation_id, occurred_at);
create index attendance_logs_staff_idx on public.attendance_logs(staff_user_id, occurred_at);
create trigger attendance_logs_append_only before update or delete on public.attendance_logs for each row execute function nodex.tg_block_mutation();

alter table public.staff_shifts enable row level security;
alter table public.staff_shifts force row level security;
alter table public.duty_allocations enable row level security;
alter table public.duty_allocations force row level security;
alter table public.attendance_logs enable row level security;
alter table public.attendance_logs force row level security;

-- Reading a roster is ordinary clinical-operations work; writing it is
-- administration. Attendance is recorded by the ward, so it rides on the same
-- manage grant rather than a separate permission.
create policy staff_shifts_select_member on public.staff_shifts for select to authenticated using (nodex.has_permission(tenant_id,'workforce.read'));
create policy staff_shifts_insert_manager on public.staff_shifts for insert to authenticated with check (nodex.has_permission(tenant_id,'workforce.manage'));
create policy staff_shifts_update_manager on public.staff_shifts for update to authenticated using (nodex.has_permission(tenant_id,'workforce.manage')) with check (nodex.has_permission(tenant_id,'workforce.manage'));

create policy duty_allocations_select_member on public.duty_allocations for select to authenticated using (nodex.has_permission(tenant_id,'workforce.read'));
create policy duty_allocations_insert_manager on public.duty_allocations for insert to authenticated with check (nodex.has_permission(tenant_id,'workforce.manage'));
create policy duty_allocations_update_manager on public.duty_allocations for update to authenticated using (nodex.has_permission(tenant_id,'workforce.manage')) with check (nodex.has_permission(tenant_id,'workforce.manage'));

create policy attendance_logs_select_member on public.attendance_logs for select to authenticated using (nodex.has_permission(tenant_id,'workforce.read'));
create policy attendance_logs_insert_manager on public.attendance_logs for insert to authenticated with check (nodex.has_permission(tenant_id,'workforce.manage'));

-- The workforce permissions. Read is standard and offline-capable so a ward
-- always has its roster; manage is elevated but deliberately not online-only,
-- because an unplanned absence has to be recordable at the bedside.
insert into public.permissions (key, display_name, description, module_code, risk_tier, requires_online)
values
  ('workforce.read',   'Read workforce rosters',  'View shifts, duty allocations and attendance.',            'M09', 'standard', false),
  ('workforce.manage', 'Manage workforce rosters','Create shifts, allocate duties and record attendance.',    'M09', 'elevated', false)
on conflict (key) do nothing;

-- Granted to the roles that staff a ward. Explicit because the Phase 1
-- all-permissions grant to hospital_super_admin ran before these keys existed.
insert into public.role_permissions (role_key, permission_key)
values
  ('hospital_super_admin', 'workforce.read'),
  ('hospital_super_admin', 'workforce.manage'),
  ('medical_officer',      'workforce.read'),
  ('nursing_staff',        'workforce.read'),
  ('nursing_staff',        'workforce.manage'),
  ('lab_technician',       'workforce.read'),
  ('pharmacist',           'workforce.read'),
  ('auditor',              'workforce.read')
on conflict do nothing;
