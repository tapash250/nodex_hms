-- NODEX Phase 4, Module 37: Visitor & Pass Security Management.
--
-- Specification scope: "Visitor registration, digital entry passes, ward visiting
-- hour restrictions, and security thermal badge printing."
--
-- This is the front door: who came in, on whose authority, where they were
-- allowed to go, and what the gate printed for them. It is distinct from the
-- clinical record (an encounter records the patient; a registration records the
-- person who came to see them) and from the workforce rosters (a shift is staff
-- on duty; a pass is a visitor allowed in).
--
-- Four tables, one per clause of the scope:
--
--   * `ward_visiting_windows` is the visiting-hour restriction: which ward, on
--     which weekday, between which minutes, and how many visitors. It is the one
--     table here that is configuration rather than an event, and it is archived
--     rather than deleted so a past pass still resolves to the rule it was issued
--     under.
--   * `visitor_registrations` is one visitor at the gate: who they are, the
--     document they showed, the patient or ward they came for and the purpose.
--     It runs `registered → on_site → left`, with `refused` and `voided` as the
--     two ways out of the first stage. What the gate recorded freezes the moment
--     the visitor steps past it.
--   * `visitor_passes` is the digital entry pass issued against a registration:
--     the badge number, the access scope and the validity window. It runs
--     `issued → active → returned`, with `revoked` from either live stage. It
--     carries no `expired` status: expiry is a derivation from the clock and the
--     window, not a state a row has to be updated into.
--   * `visitor_badge_prints` is the append-only print log: which pass was printed
--     onto which badge, at which printer, by whom, and whether it was a reprint.
--     A thermal badge is a physical token, so the number of times it was made is
--     a fact worth keeping.
--
-- The window boundaries are stored as minutes from local midnight rather than as
-- a `time`, and in Dart the caller passes the local minute of day. Visiting hours
-- are a wall-clock rule, and a facility's wall clock is a client-side fact; a
-- `timestamptz` boundary would quietly turn 10:00 into 16:00 for a server on a
-- different clock.
--
-- Two permissions are operation and one is configuration: `visitor.read` is
-- standard and offline, `visitor.register` and `visitor.pass` are elevated and
-- offline (a gate works while the network does not), and `visitor.configure` is
-- elevated and offline but held only by the administrator and the medical
-- officer, because a ward's visiting hours are a rule rather than a shift.
--
-- Four permissions are granted explicitly because the Phase 1 all-permissions
-- seed predates these keys.

create table public.ward_visiting_windows (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  facility_id uuid not null references public.facilities(id) on delete restrict,
  ward_id uuid not null references public.wards(id) on delete restrict,
  -- 0 is Sunday, matching Dart's DateTime.weekday convention shifted by one, so
  -- the client resolves a window without a lookup table.
  day_of_week integer not null check (day_of_week between 0 and 6),
  starts_minute integer not null check (starts_minute between 0 and 1439),
  ends_minute integer not null check (ends_minute between 1 and 1440),
  max_visitors integer not null default 2 check (max_visitors between 1 and 50),
  allows_children boolean not null default false,
  status text not null default 'active'
    check (status in ('active','archived')),
  created_by uuid not null references public.app_users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- One window per ward per day: a ward with two windows has two rows only if
  -- they are on different days, which is what makes the resolution unambiguous.
  unique (tenant_id, ward_id, day_of_week),
  constraint ward_visiting_window_order_ck check (ends_minute > starts_minute)
);
create index ward_visiting_window_ward_idx
  on public.ward_visiting_windows(tenant_id, facility_id, ward_id, status);

create table public.visitor_registrations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  facility_id uuid not null references public.facilities(id) on delete restrict,
  registration_number text not null
    check (length(btrim(registration_number)) > 0),
  full_name text not null check (length(btrim(full_name)) > 0),
  phone text check (phone is null or length(btrim(phone)) > 0),
  sex text check (sex in ('male','female','other')),
  age_years integer check (age_years between 0 and 130),
  id_document_type text
    check (id_document_type in ('national_id','passport','driving_licence',
                                'service_id','other')),
  id_document_number text
    check (id_document_number is null
           or length(btrim(id_document_number)) > 0),
  relationship text check (relationship is null or length(btrim(relationship)) > 0),
  purpose text not null
    check (purpose in ('patient_visit','attendant','vendor','service','official',
                       'other')),
  patient_id uuid references public.patients(id) on delete set null,
  ward_id uuid references public.wards(id) on delete set null,
  registered_at timestamptz not null default now(),
  status text not null default 'registered'
    check (status in ('registered','on_site','left','refused','voided')),
  checked_in_at timestamptz,
  checked_out_at timestamptz,
  refused_at timestamptz,
  refuse_reason text check (refuse_reason is null or length(btrim(refuse_reason)) > 0),
  voided_at timestamptz,
  void_reason text check (void_reason is null or length(btrim(void_reason)) > 0),
  registered_by uuid not null references public.app_users(id) on delete restrict,
  created_by uuid not null references public.app_users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- One registration number per tenant: the gate log is a sequence, and two rows
  -- sharing a number would make the sequence unreadable.
  unique (tenant_id, registration_number),
  constraint visitor_registration_on_site_ck check (
    status <> 'on_site' or checked_in_at is not null
  ),
  constraint visitor_registration_left_ck check (
    status <> 'left'
    or (checked_in_at is not null and checked_out_at is not null)
  ),
  constraint visitor_registration_refused_ck check (
    status <> 'refused'
    or (refused_at is not null and refuse_reason is not null
        and length(btrim(refuse_reason)) > 0)
  ),
  constraint visitor_registration_voided_ck check (
    status <> 'voided'
    or (voided_at is not null and void_reason is not null
        and length(btrim(void_reason)) > 0)
  )
);
create index visitor_registration_status_idx
  on public.visitor_registrations(tenant_id, status, registered_at desc);
create index visitor_registration_ward_idx
  on public.visitor_registrations(tenant_id, ward_id, status);
create index visitor_registration_patient_idx
  on public.visitor_registrations(tenant_id, patient_id, registered_at desc);

create table public.visitor_passes (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  facility_id uuid not null references public.facilities(id) on delete restrict,
  registration_id uuid not null
    references public.visitor_registrations(id) on delete restrict,
  badge_number text not null check (length(btrim(badge_number)) > 0),
  access_scope text not null default 'ward'
    check (access_scope in ('ward','opd','icu','whole_facility')),
  escort_count integer not null default 0 check (escort_count between 0 and 10),
  valid_from timestamptz not null default now(),
  valid_until timestamptz not null,
  status text not null default 'issued'
    check (status in ('issued','active','returned','revoked')),
  activated_at timestamptz,
  returned_at timestamptz,
  revoked_at timestamptz,
  revoke_reason text check (revoke_reason is null or length(btrim(revoke_reason)) > 0),
  issued_by uuid not null references public.app_users(id) on delete restrict,
  created_by uuid not null references public.app_users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- A badge number identifies one badge. Two passes sharing it would let one
  -- person's access stand for another's.
  unique (tenant_id, badge_number),
  constraint visitor_pass_window_ck check (valid_until > valid_from),
  constraint visitor_pass_active_ck check (
    status <> 'active' or activated_at is not null
  ),
  constraint visitor_pass_returned_ck check (
    status <> 'returned'
    or (activated_at is not null and returned_at is not null)
  ),
  constraint visitor_pass_revoked_ck check (
    status <> 'revoked'
    or (revoked_at is not null and revoke_reason is not null
        and length(btrim(revoke_reason)) > 0)
  )
);
create index visitor_pass_status_idx
  on public.visitor_passes(tenant_id, status, valid_until);
create index visitor_pass_registration_idx
  on public.visitor_passes(tenant_id, registration_id);

create table public.visitor_badge_prints (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  pass_id uuid not null references public.visitor_passes(id) on delete restrict,
  badge_number text not null check (length(btrim(badge_number)) > 0),
  print_ordinal integer not null check (print_ordinal between 1 and 20),
  printer_label text not null check (length(btrim(printer_label)) > 0),
  note text check (note is null or length(btrim(note)) > 0),
  printed_at timestamptz not null default now(),
  printed_by uuid not null references public.app_users(id) on delete restrict,
  created_at timestamptz not null default now(),
  -- Reprints are numbered rather than overwritten: the ordinal is what makes
  -- "this badge was made three times" a fact the log can show.
  unique (pass_id, print_ordinal)
);
create index visitor_badge_print_pass_idx
  on public.visitor_badge_prints(tenant_id, pass_id, print_ordinal);

comment on table public.visitor_badge_prints is
  'Append-only log of thermal badge prints. One row per badge made, numbered by ordinal, so a reprint is recorded rather than hidden.';

create trigger ward_visiting_windows_set_updated_at
  before update on public.ward_visiting_windows
  for each row execute function nodex.tg_set_updated_at();
create trigger visitor_registrations_set_updated_at
  before update on public.visitor_registrations
  for each row execute function nodex.tg_set_updated_at();
create trigger visitor_passes_set_updated_at
  before update on public.visitor_passes
  for each row execute function nodex.tg_set_updated_at();

-- The gate log, the pass register and the print log are records: a hard delete is
-- refused at the table as well as by RLS. A visiting window is configuration, so
-- it is also blocked here and retired by archiving it instead.
create trigger ward_visiting_windows_retain
  before delete on public.ward_visiting_windows
  for each row execute function nodex.tg_block_mutation();
create trigger visitor_registrations_retain
  before delete on public.visitor_registrations
  for each row execute function nodex.tg_block_mutation();
create trigger visitor_passes_retain
  before delete on public.visitor_passes
  for each row execute function nodex.tg_block_mutation();
create trigger visitor_badge_prints_append_only
  before update or delete on public.visitor_badge_prints
  for each row execute function nodex.tg_block_mutation();

-- An archived window is what the ward's past passes were issued under, so it is
-- immutable once retired.
create or replace function nodex.tg_ward_visiting_window_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status = 'archived' then
    raise exception using
      message = 'NODEX: an archived visiting window is immutable',
      errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger ward_visiting_windows_guard
  before update on public.ward_visiting_windows
  for each row execute function nodex.tg_ward_visiting_window_guard();

-- What the gate recorded is a fact: it freezes once the visitor is no longer
-- merely registered, because that is the version the pass was issued against.
create or replace function nodex.tg_visitor_registration_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status in ('left','refused','voided') then
    raise exception using
      message = 'NODEX: a settled visitor registration is immutable',
      errcode = '42501';
  end if;
  if old.status <> 'registered' then
    if new.registration_number is distinct from old.registration_number
      or new.full_name is distinct from old.full_name
      or new.phone is distinct from old.phone
      or new.sex is distinct from old.sex
      or new.age_years is distinct from old.age_years
      or new.id_document_type is distinct from old.id_document_type
      or new.id_document_number is distinct from old.id_document_number
      or new.relationship is distinct from old.relationship
      or new.purpose is distinct from old.purpose
      or new.patient_id is distinct from old.patient_id
      or new.ward_id is distinct from old.ward_id
      or new.registered_at is distinct from old.registered_at
      or new.registered_by is distinct from old.registered_by then
      raise exception using
        message = 'NODEX: what the gate recorded is immutable',
        errcode = '42501';
    end if;
  end if;
  if new.status = old.status then
    return new;
  end if;
  if (old.status = 'registered'
        and new.status in ('on_site','refused','voided'))
    or (old.status = 'on_site' and new.status = 'left') then
    return new;
  end if;
  raise exception using
    message = 'NODEX: a visitor registration may not skip a stage',
    errcode = '42501';
end;
$$;
create trigger visitor_registrations_guard
  before update on public.visitor_registrations
  for each row execute function nodex.tg_visitor_registration_guard();

-- A settled pass is immutable, and a pass moves forward only.
create or replace function nodex.tg_visitor_pass_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status in ('returned','revoked') then
    raise exception using
      message = 'NODEX: a settled visitor pass is immutable',
      errcode = '42501';
  end if;
  if old.status <> 'issued'
    and (new.badge_number is distinct from old.badge_number
      or new.access_scope is distinct from old.access_scope
      or new.escort_count is distinct from old.escort_count
      or new.valid_from is distinct from old.valid_from
      or new.valid_until is distinct from old.valid_until
      or new.registration_id is distinct from old.registration_id) then
    raise exception using
      message = 'NODEX: an active pass is not re-scoped',
      errcode = '42501';
  end if;
  if new.status = old.status then
    return new;
  end if;
  if (old.status = 'issued' and new.status in ('active','revoked'))
    or (old.status = 'active' and new.status in ('returned','revoked')) then
    return new;
  end if;
  raise exception using
    message = 'NODEX: a visitor pass may not skip a stage',
    errcode = '42501';
end;
$$;
create trigger visitor_passes_guard
  before update on public.visitor_passes
  for each row execute function nodex.tg_visitor_pass_guard();

alter table public.ward_visiting_windows enable row level security;
alter table public.ward_visiting_windows force row level security;
alter table public.visitor_registrations enable row level security;
alter table public.visitor_registrations force row level security;
alter table public.visitor_passes enable row level security;
alter table public.visitor_passes force row level security;
alter table public.visitor_badge_prints enable row level security;
alter table public.visitor_badge_prints force row level security;

create policy ward_visiting_window_select_member on public.ward_visiting_windows for select to authenticated
  using (nodex.has_permission(tenant_id, 'visitor.read'));
create policy ward_visiting_window_insert_configurer on public.ward_visiting_windows for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'visitor.configure'));
create policy ward_visiting_window_update_configurer on public.ward_visiting_windows for update to authenticated
  using (nodex.has_permission(tenant_id, 'visitor.configure'))
  with check (nodex.has_permission(tenant_id, 'visitor.configure'));

create policy visitor_registration_select_member on public.visitor_registrations for select to authenticated
  using (nodex.has_permission(tenant_id, 'visitor.read'));
create policy visitor_registration_insert_registrar on public.visitor_registrations for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'visitor.register'));
create policy visitor_registration_update_registrar on public.visitor_registrations for update to authenticated
  using (nodex.has_permission(tenant_id, 'visitor.register'))
  with check (nodex.has_permission(tenant_id, 'visitor.register'));

create policy visitor_pass_select_member on public.visitor_passes for select to authenticated
  using (nodex.has_permission(tenant_id, 'visitor.read'));
create policy visitor_pass_insert_issuer on public.visitor_passes for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'visitor.pass'));
create policy visitor_pass_update_issuer on public.visitor_passes for update to authenticated
  using (nodex.has_permission(tenant_id, 'visitor.pass'))
  with check (nodex.has_permission(tenant_id, 'visitor.pass'));

create policy visitor_badge_print_select_member on public.visitor_badge_prints for select to authenticated
  using (nodex.has_permission(tenant_id, 'visitor.read'));
-- The desk that registers a visitor also prints the badge, so the print log takes
-- either the registrar's tier or the issuer's.
create policy visitor_badge_print_insert_operator on public.visitor_badge_prints for insert to authenticated
  with check (
    nodex.has_permission(tenant_id, 'visitor.register')
    or nodex.has_permission(tenant_id, 'visitor.pass')
  );

insert into public.permissions (key, display_name, description, module_code, risk_tier, requires_online)
values
  ('visitor.read',      'Read visitor records',   'View visitor registrations, entry passes and ward visiting windows.', 'M37', 'standard', false),
  ('visitor.register',  'Register visitors',      'Register a visitor at the gate, admit them and record their departure.', 'M37', 'elevated', false),
  ('visitor.pass',      'Issue visitor passes',   'Issue, activate, return and revoke a digital entry pass, and print the badge.', 'M37', 'elevated', false),
  ('visitor.configure', 'Configure visiting hours', 'Set and retire a ward''s visiting window and its visitor limit.', 'M37', 'elevated', false)
on conflict (key) do nothing;

insert into public.role_permissions (role_key, permission_key)
values
  ('hospital_super_admin', 'visitor.read'),
  ('hospital_super_admin', 'visitor.register'),
  ('hospital_super_admin', 'visitor.pass'),
  ('hospital_super_admin', 'visitor.configure'),
  ('medical_officer',      'visitor.read'),
  ('medical_officer',      'visitor.register'),
  ('medical_officer',      'visitor.pass'),
  ('medical_officer',      'visitor.configure'),
  ('nursing_staff',        'visitor.read'),
  ('nursing_staff',        'visitor.register'),
  ('nursing_staff',        'visitor.pass'),
  ('auditor',              'visitor.read')
on conflict do nothing;
