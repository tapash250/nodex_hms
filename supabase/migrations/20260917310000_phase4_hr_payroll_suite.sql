-- NODEX Phase 4, Module 13: Human Resources & Payroll Suite.
--
-- Specification scope: "Employee lifecycle, attendance, leave, payroll,
-- payslips, holidays, badges."
--
-- This slice covers the employment record, the leave workflow, the holiday
-- calendar, and the payroll run. Attendance already lives in Module 09
-- (`attendance_logs`), so it is deliberately not duplicated here: HR reads the
-- same workforce facts rather than keeping a second copy that could disagree.
-- Leave is split by purpose: `hr_leave_requests` is the *application and
-- approval* workflow, while `duty_allocations` with role `leave` is the roster
-- block an approval produces. Keeping them apart means an unapproved request
-- cannot silently remove someone from a shift, and an approved one leaves an
-- auditable trail.
--
-- Payroll is separated from HR because it is the one part that touches money
-- and must be online-only: `payroll.manage` carries `requires_online = true`,
-- so it never enters an offline snapshot and a finalized payslip cannot be
-- manufactured on a disconnected device. Viewing is a separate, offline-capable
-- permission.
--
-- Every table here is retained, never deleted: separating an employee archives
-- the record, and a finalised payroll run is frozen. Corrections are new rows
-- or guarded transitions, matching the schema-wide stance.

-- The employment record layered on `app_users`. One row per person per tenant.
create table public.hr_employees (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  user_id uuid not null references public.app_users(id) on delete restrict,
  employee_code text not null check (length(btrim(employee_code)) > 0),
  department_id uuid references public.departments(id) on delete set null,
  designation text check (designation is null or length(btrim(designation)) > 0),
  employment_type text not null default 'permanent'
    check (employment_type in ('permanent','contract','part_time','intern','locum')),
  employment_status text not null default 'probation'
    check (employment_status in ('probation','active','on_leave','suspended','separated')),
  grade text check (grade is null or length(btrim(grade)) > 0),
  reports_to uuid references public.app_users(id) on delete set null,
  joined_on date not null,
  confirmation_on date,
  separated_on date,
  notes text check (notes is null or length(btrim(notes)) > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, user_id),
  unique (tenant_id, employee_code),
  constraint hr_employee_confirmation_ck check (
    confirmation_on is null or confirmation_on >= joined_on
  ),
  constraint hr_employee_separation_ck check (
    separated_on is null or separated_on >= joined_on
  ),
  constraint hr_employee_separated_ck check (
    employment_status <> 'separated' or separated_on is not null
  )
);
create index hr_employees_department_idx on public.hr_employees(tenant_id, department_id);
create index hr_employees_status_idx on public.hr_employees(tenant_id, employment_status);
create trigger hr_employees_set_updated_at before update on public.hr_employees
  for each row execute function nodex.tg_set_updated_at();
create trigger hr_employees_retain before delete on public.hr_employees
  for each row execute function nodex.tg_block_mutation();

-- A leave application. Approval is a decision, not an edit: once decided the
-- application is frozen, and an approved block is frozen except for its
-- cancellation. Overlapping live applications for one person are refused.
create table public.hr_leave_requests (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  employee_id uuid not null references public.hr_employees(id) on delete restrict,
  leave_type text not null
    check (leave_type in ('annual','sick','maternity','paternity','unpaid','study','casual','bereavement','other')),
  starts_on date not null,
  ends_on date not null,
  reason text check (reason is null or length(btrim(reason)) > 0),
  status text not null default 'requested'
    check (status in ('requested','approved','rejected','cancelled')),
  requested_by uuid not null references public.app_users(id) on delete restrict,
  decided_by uuid references public.app_users(id) on delete set null,
  decided_at timestamptz,
  decision_note text check (decision_note is null or length(btrim(decision_note)) > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint hr_leave_window_ck check (ends_on >= starts_on),
  constraint hr_leave_decision_ck check (
    (status = 'requested' and decided_by is null and decided_at is null)
    or (status <> 'requested' and decided_by is not null and decided_at is not null)
  )
);
create index hr_leave_requests_employee_idx
  on public.hr_leave_requests(employee_id, status, starts_on);
create trigger hr_leave_requests_set_updated_at before update on public.hr_leave_requests
  for each row execute function nodex.tg_set_updated_at();
create trigger hr_leave_requests_retain before delete on public.hr_leave_requests
  for each row execute function nodex.tg_block_mutation();

create or replace function nodex.tg_hr_leave_request_decision_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status in ('rejected', 'cancelled') then
    raise exception using
      message = 'NODEX: a decided leave application is immutable',
      errcode = '42501';
  end if;
  if old.status = 'approved' and new.status <> 'cancelled' then
    if new.employee_id is distinct from old.employee_id
      or new.leave_type is distinct from old.leave_type
      or new.starts_on is distinct from old.starts_on
      or new.ends_on is distinct from old.ends_on
      or new.reason is distinct from old.reason
      or new.decided_by is distinct from old.decided_by
      or new.decided_at is distinct from old.decided_at then
      raise exception using
        message = 'NODEX: an approved leave application is frozen except for cancellation',
        errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;
create trigger hr_leave_request_decision_guard
  before update on public.hr_leave_requests
  for each row execute function nodex.tg_hr_leave_request_decision_guard();

create or replace function nodex.tg_hr_leave_request_overlap_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.status not in ('requested', 'approved') then
    return new;
  end if;
  if exists (
    select 1 from public.hr_leave_requests r
     where r.employee_id = new.employee_id
       and r.id <> new.id
       and r.status in ('requested', 'approved')
       and r.starts_on <= new.ends_on
       and new.starts_on <= r.ends_on
  ) then
    raise exception using
      message = 'NODEX: this employee already has a live leave application over that window',
      errcode = '23P01';
  end if;
  return new;
end;
$$;
create trigger hr_leave_request_overlap_guard
  before insert or update on public.hr_leave_requests
  for each row execute function nodex.tg_hr_leave_request_overlap_guard();

-- The holiday calendar. A null facility is a tenant-wide holiday; the unique
-- index coalesces it so a tenant-wide and a facility holiday can coexist but
-- the same holiday cannot be entered twice.
create table public.hr_holidays (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  facility_id uuid references public.facilities(id) on delete cascade,
  holiday_date date not null,
  display_name text not null check (length(btrim(display_name)) > 0),
  holiday_type text not null default 'public'
    check (holiday_type in ('public','religious','national','institutional','optional')),
  is_paid boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index hr_holidays_unique
  on public.hr_holidays(
    tenant_id,
    coalesce(facility_id, '00000000-0000-0000-0000-000000000000'::uuid),
    holiday_date,
    display_name
  );
create index hr_holidays_date_idx on public.hr_holidays(tenant_id, holiday_date);
create trigger hr_holidays_set_updated_at before update on public.hr_holidays
  for each row execute function nodex.tg_set_updated_at();
create trigger hr_holidays_retain before delete on public.hr_holidays
  for each row execute function nodex.tg_block_mutation();

-- A monthly payroll run. It is a guarded state machine: draft -> finalized ->
-- paid. Once it leaves draft the financial window is frozen, and only the
-- status advances.
create table public.hr_payroll_periods (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  facility_id uuid not null references public.facilities(id) on delete restrict,
  period_start date not null,
  period_end date not null,
  pay_date date not null,
  currency text not null default 'BDT' check (currency ~ '^[A-Z]{3}$'),
  status text not null default 'draft'
    check (status in ('draft','finalized','paid')),
  finalized_by uuid references public.app_users(id) on delete set null,
  finalized_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, facility_id, period_start),
  constraint hr_payroll_window_ck check (period_end >= period_start),
  constraint hr_payroll_pay_date_ck check (pay_date >= period_end),
  constraint hr_payroll_finalized_ck check (
    (status = 'draft' and finalized_by is null and finalized_at is null)
    or (status <> 'draft' and finalized_by is not null and finalized_at is not null)
  )
);
create index hr_payroll_periods_status_idx
  on public.hr_payroll_periods(tenant_id, status, period_start);
create trigger hr_payroll_periods_set_updated_at before update on public.hr_payroll_periods
  for each row execute function nodex.tg_set_updated_at();
create trigger hr_payroll_periods_retain before delete on public.hr_payroll_periods
  for each row execute function nodex.tg_block_mutation();

create or replace function nodex.tg_hr_payroll_period_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status <> 'draft' then
    if new.facility_id is distinct from old.facility_id
      or new.period_start is distinct from old.period_start
      or new.period_end is distinct from old.period_end
      or new.pay_date is distinct from old.pay_date
      or new.currency is distinct from old.currency
      or new.finalized_by is distinct from old.finalized_by
      or new.finalized_at is distinct from old.finalized_at then
      raise exception using
        message = 'NODEX: a finalized payroll period is frozen',
        errcode = '42501';
    end if;
  end if;
  if old.status = 'paid' and new.status <> 'paid' then
    raise exception using
      message = 'NODEX: a paid payroll period cannot be reopened',
      errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger hr_payroll_period_guard
  before update on public.hr_payroll_periods
  for each row execute function nodex.tg_hr_payroll_period_guard();

-- A payslip under a period. Financial fields freeze when the period is no
-- longer a draft; `net_minor` is kept equal to gross less deductions by the
-- database so a total that does not add up cannot be stored. Amounts are
-- integer minor units, matching the billing engine's stance against
-- floating-point money.
create table public.hr_payslips (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  period_id uuid not null references public.hr_payroll_periods(id) on delete restrict,
  employee_id uuid not null references public.hr_employees(id) on delete restrict,
  gross_minor bigint not null check (gross_minor >= 0),
  deductions_minor bigint not null default 0 check (deductions_minor >= 0),
  net_minor bigint not null check (net_minor >= 0),
  status text not null default 'draft'
    check (status in ('draft','finalized','paid')),
  paid_on date,
  note text check (note is null or length(btrim(note)) > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (period_id, employee_id),
  constraint hr_payslip_net_ck check (net_minor = gross_minor - deductions_minor)
);
create index hr_payslips_employee_idx
  on public.hr_payslips(employee_id, status);
create trigger hr_payslips_set_updated_at before update on public.hr_payslips
  for each row execute function nodex.tg_set_updated_at();
create trigger hr_payslips_retain before delete on public.hr_payslips
  for each row execute function nodex.tg_block_mutation();

create or replace function nodex.tg_hr_payslip_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_period_status text;
begin
  select status into v_period_status
    from public.hr_payroll_periods where id = new.period_id;
  if tg_op = 'INSERT' and v_period_status <> 'draft' then
    raise exception using
      message = 'NODEX: payslips may only be added to a draft payroll period',
      errcode = '42501';
  end if;
  if tg_op = 'UPDATE' and old.status <> 'draft' then
    if new.gross_minor is distinct from old.gross_minor
      or new.deductions_minor is distinct from old.deductions_minor
      or new.net_minor is distinct from old.net_minor
      or new.employee_id is distinct from old.employee_id
      or new.period_id is distinct from old.period_id then
      raise exception using
        message = 'NODEX: a finalized payslip is frozen',
        errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;
create trigger hr_payslip_guard
  before insert or update on public.hr_payslips
  for each row execute function nodex.tg_hr_payslip_guard();

alter table public.hr_employees enable row level security;
alter table public.hr_employees force row level security;
alter table public.hr_leave_requests enable row level security;
alter table public.hr_leave_requests force row level security;
alter table public.hr_holidays enable row level security;
alter table public.hr_holidays force row level security;
alter table public.hr_payroll_periods enable row level security;
alter table public.hr_payroll_periods force row level security;
alter table public.hr_payslips enable row level security;
alter table public.hr_payslips force row level security;

-- HR data is ordinary administrative data: read by members, written by HR.
create policy hr_employees_select_member on public.hr_employees for select to authenticated
  using (nodex.has_permission(tenant_id, 'hr.read'));
create policy hr_employees_insert_manager on public.hr_employees for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'hr.manage'));
create policy hr_employees_update_manager on public.hr_employees for update to authenticated
  using (nodex.has_permission(tenant_id, 'hr.manage'))
  with check (nodex.has_permission(tenant_id, 'hr.manage'));

create policy hr_leave_requests_select_member on public.hr_leave_requests for select to authenticated
  using (nodex.has_permission(tenant_id, 'hr.read'));
create policy hr_leave_requests_insert_manager on public.hr_leave_requests for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'hr.manage'));
create policy hr_leave_requests_update_manager on public.hr_leave_requests for update to authenticated
  using (nodex.has_permission(tenant_id, 'hr.manage'))
  with check (nodex.has_permission(tenant_id, 'hr.manage'));

create policy hr_holidays_select_member on public.hr_holidays for select to authenticated
  using (nodex.has_permission(tenant_id, 'hr.read'));
create policy hr_holidays_insert_manager on public.hr_holidays for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'hr.manage'));
create policy hr_holidays_update_manager on public.hr_holidays for update to authenticated
  using (nodex.has_permission(tenant_id, 'hr.manage'))
  with check (nodex.has_permission(tenant_id, 'hr.manage'));

-- Payroll is money: read is its own permission, and writing it is online-only.
create policy hr_payroll_periods_select_reader on public.hr_payroll_periods for select to authenticated
  using (nodex.has_permission(tenant_id, 'payroll.read'));
create policy hr_payroll_periods_insert_manager on public.hr_payroll_periods for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'payroll.manage'));
create policy hr_payroll_periods_update_manager on public.hr_payroll_periods for update to authenticated
  using (nodex.has_permission(tenant_id, 'payroll.manage'))
  with check (nodex.has_permission(tenant_id, 'payroll.manage'));

create policy hr_payslips_select_reader on public.hr_payslips for select to authenticated
  using (nodex.has_permission(tenant_id, 'payroll.read'));
create policy hr_payslips_insert_manager on public.hr_payslips for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'payroll.manage'));
create policy hr_payslips_update_manager on public.hr_payslips for update to authenticated
  using (nodex.has_permission(tenant_id, 'payroll.manage'))
  with check (nodex.has_permission(tenant_id, 'payroll.manage'));

-- The HR and payroll permissions. Payroll management is the only one that must
-- not run from an offline snapshot: a finalized payslip is a financial act.
insert into public.permissions (key, name, description, module_code, risk_tier, requires_online)
values
  ('hr.read',         'Read HR records',       'View employee records, leave applications and holidays.', 'M13', 'standard', false),
  ('hr.manage',       'Manage HR records',     'Maintain employee records, decide leave and set holidays.', 'M13', 'elevated', false),
  ('payroll.read',    'Read payroll',          'View payroll periods and payslips.',                      'M13', 'elevated', false),
  ('payroll.manage',  'Manage payroll',        'Create and finalize payroll runs and payslips.',          'M13', 'elevated', true)
on conflict (key) do nothing;

insert into public.role_permissions (role_key, permission_key)
values
  ('hospital_super_admin', 'hr.read'),
  ('hospital_super_admin', 'hr.manage'),
  ('hospital_super_admin', 'payroll.read'),
  ('hospital_super_admin', 'payroll.manage'),
  ('medical_officer',      'hr.read'),
  ('nursing_staff',        'hr.read'),
  ('lab_technician',       'hr.read'),
  ('pharmacist',           'hr.read'),
  ('auditor',              'hr.read'),
  ('auditor',              'payroll.read')
on conflict do nothing;
