-- NODEX Phase 4, Module 08: Doctor & Specialist Directory.
--
-- Specification scope: "Enterprise registry of doctors, sub-specialties,
-- credentials, consultation rooms, and on-call rotations", as a global
-- read-only catalog replicated across all authenticated devices.
--
-- The registry entry hangs off an existing app_user rather than duplicating
-- identity: name, contact and employment status already live there and are
-- owned by user administration (Module 52/13). What this table owns is the
-- clinical directory facts — specialty, sub-specialty, credentials, the
-- consultation room they practise from — which is what a clinician searching
-- for a specialist actually filters on.
--
-- The directory is read-only for its consumers: `staff_directory.read` selects
-- and `staff_directory.administer` writes. A clinician browsing the directory
-- cannot edit a colleague's credentials, and the registry is reconciled against
-- the credentialing record rather than by whoever is holding the tablet.
--
-- On-call rotations are stored per practitioner and never overwritten: an
-- expiring rotation stays on the row it describes, so a question about who was
-- on call last Tuesday is answerable from the local projection. FKs target
-- app_users, and RLS is membership-derived.

-- One directory entry per practitioner per tenant. A user with memberships in
-- several tenants has a row in each: their specialty is the same everywhere, but
-- the consultation room and department are not.
create table public.practitioner_profiles (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  user_id uuid not null references public.app_users(id) on delete restrict,
  facility_id uuid not null references public.facilities(id) on delete restrict,
  department_id uuid references public.departments(id) on delete restrict,
  specialty text not null check (length(btrim(specialty)) > 0),
  sub_specialty text check (sub_specialty is null or length(btrim(sub_specialty)) > 0),
  -- Qualifications and registrations as free text: the credentialing record is
  -- the authority, and this is the human-readable summary a search returns.
  credentials text check (credentials is null or length(btrim(credentials)) > 0),
  registration_no text unique check (registration_no is null or length(btrim(registration_no)) > 0),
  years_experience integer not null default 0 check (years_experience >= 0 and years_experience <= 80),
  -- Where they consult from, when it is a real room in the floor map.
  consultation_room_id uuid references public.ward_rooms(id) on delete set null,
  accepting_referrals boolean not null default true,
  status text not null default 'active' check (status in ('active','suspended','retired')),
  retired_by uuid references public.app_users(id) on delete restrict,
  retired_at timestamptz,
  retirement_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, user_id),
  constraint practitioner_retired_ck check (
    (status = 'retired' and retired_at is not null and retirement_reason is not null and length(btrim(retirement_reason)) > 0)
    or (status <> 'retired' and retired_at is null and retired_by is null and retirement_reason is null)
  )
);
create index practitioner_profiles_specialty_idx on public.practitioner_profiles(tenant_id, specialty, sub_specialty);
create index practitioner_profiles_facility_idx on public.practitioner_profiles(facility_id, status);

create trigger practitioner_profiles_set_updated_at before update on public.practitioner_profiles for each row execute function nodex.tg_set_updated_at();

-- A retired practitioner profile is a credential record: it freezes on
-- retirement so a historical referral still names the specialist who saw it.
create or replace function nodex.tg_practitioner_retirement_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status = 'retired' then
    if new.tenant_id is distinct from old.tenant_id
      or new.user_id is distinct from old.user_id
      or new.facility_id is distinct from old.facility_id
      or new.specialty is distinct from old.specialty
      or new.credentials is distinct from old.credentials
      or new.registration_no is distinct from old.registration_no
      or new.retired_by is distinct from old.retired_by
      or new.retired_at is distinct from old.retired_at
      or new.retirement_reason is distinct from old.retirement_reason then
      raise exception using message = 'NODEX: retired practitioner profiles are immutable', errcode = '42501';
    end if;
  end if;
  if new.status = 'retired' and (new.retired_at is null or new.retirement_reason is null) then
    raise exception using message = 'NODEX: retiring a practitioner requires timestamp and reason', errcode = '22000';
  end if;
  return new;
end;
$$;
create trigger practitioner_profiles_retirement_guard before update on public.practitioner_profiles for each row execute function nodex.tg_practitioner_retirement_guard();
create trigger practitioner_profiles_append_only_delete before delete on public.practitioner_profiles for each row execute function nodex.tg_block_mutation();

-- One on-call rotation. Overlaps are allowed deliberately: a call rota and a
-- ward cover can name the same practitioner for the same hours, and forbidding
-- that would be a scheduling rule the registry has no business enforcing.
create table public.practitioner_on_calls (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  practitioner_id uuid not null references public.practitioner_profiles(id) on delete restrict,
  rotation_type text not null check (rotation_type in ('primary','secondary','ward','theatre','consult','respite')),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  location text check (location is null or length(btrim(location)) > 0),
  contact_note text check (contact_note is null or length(btrim(contact_note)) > 0),
  recorded_by uuid not null references public.app_users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint practitioner_on_call_window_ck check (ends_at > starts_at)
);
create index practitioner_on_calls_window_idx on public.practitioner_on_calls(practitioner_id, starts_at, ends_at);
create index practitioner_on_calls_tenant_idx on public.practitioner_on_calls(tenant_id, starts_at);

create trigger practitioner_on_calls_set_updated_at before update on public.practitioner_on_calls for each row execute function nodex.tg_set_updated_at();
create trigger practitioner_on_calls_append_only_delete before delete on public.practitioner_on_calls for each row execute function nodex.tg_block_mutation();

alter table public.practitioner_profiles enable row level security;
alter table public.practitioner_profiles force row level security;
alter table public.practitioner_on_calls enable row level security;
alter table public.practitioner_on_calls force row level security;

-- Reading is the directory's ordinary use and needs only the read permission.
-- Writing is administration: a clinician may not edit a colleague's
-- credentials or the call rota from a clinical tablet.
create policy practitioner_profiles_select_member on public.practitioner_profiles for select to authenticated using (nodex.has_permission(tenant_id,'staff_directory.read'));
create policy practitioner_profiles_insert_admin on public.practitioner_profiles for insert to authenticated with check (nodex.has_permission(tenant_id,'staff_directory.administer'));
create policy practitioner_profiles_update_admin on public.practitioner_profiles for update to authenticated using (nodex.has_permission(tenant_id,'staff_directory.administer')) with check (nodex.has_permission(tenant_id,'staff_directory.administer'));

create policy practitioner_on_calls_select_member on public.practitioner_on_calls for select to authenticated using (nodex.has_permission(tenant_id,'staff_directory.read'));
create policy practitioner_on_calls_insert_admin on public.practitioner_on_calls for insert to authenticated with check (nodex.has_permission(tenant_id,'staff_directory.administer'));
create policy practitioner_on_calls_update_admin on public.practitioner_on_calls for update to authenticated using (nodex.has_permission(tenant_id,'staff_directory.administer')) with check (nodex.has_permission(tenant_id,'staff_directory.administer'));

-- The directory's write permission. Reading already existed as
-- staff_directory.read; the specification makes this a read-mostly catalog, so
-- the write gate is a distinct, separately grantable permission rather than
-- reuse of user administration.
insert into public.permissions (key, name, description, module_code, risk_tier, requires_online)
values ('staff_directory.administer', 'Administer the staff directory',
        'Create and maintain practitioner directory entries and on-call rotations.',
        'M08', 'elevated', true)
on conflict (key) do nothing;
