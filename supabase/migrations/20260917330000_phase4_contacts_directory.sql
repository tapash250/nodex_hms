-- NODEX Phase 4, Module 42: Hospital Contacts Directory.
--
-- Specification scope: the institution's contact book — who to call. It is
-- deliberately not the staff directory (Module 08), which is a registry of
-- people and their professional credentials, nor the department registry
-- (Module 12), which describes organisational structure. A contact is an
-- operational reachability fact: an emergency number, a ward help desk, a
-- duty engineer, a reference laboratory, an ambulance provider, an external
-- referral partner.
--
-- Internal contact points are frequently role-based rather than person-based
-- ("Duty biomedical engineer", "Blood bank help desk") because the number
-- outlives the person holding the phone at 03:00. That is why this table does
-- not hang off an `app_users` row the way the staff directory does.
--
-- The directory is retained, never deleted: an archived contact still explains
-- the number a historical document or an incident report names, so the row
-- freezes on archive and only its status moves. A corrected contact is an edit
-- while active, or a new row once archived.
--
-- Reading is the directory's ordinary use and carries `contacts.read`
-- (standard, offline — an emergency number must be reachable when the network
-- is not). Maintaining it carries `contacts.administer` (elevated). Both are
-- granted explicitly here because the Phase 1 all-permissions seed predates
-- these keys.

create table public.directory_contacts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  -- Null facility means the contact is tenant-wide (a corporate switchboard or
  -- a shared external partner).
  facility_id uuid references public.facilities(id) on delete restrict,
  department_id uuid references public.departments(id) on delete set null,
  name text not null check (length(btrim(name)) > 0),
  category text not null default 'support'
    check (category in ('emergency','clinical','support','administrative','external')),
  -- The role or position the contact reaches, when it is role-based.
  contact_role text check (contact_role is null or length(btrim(contact_role)) > 0),
  -- External counterpart organisation, when the contact is not internal.
  organisation text check (organisation is null or length(btrim(organisation)) > 0),
  phone_primary text not null check (length(btrim(phone_primary)) > 0),
  phone_secondary text check (phone_secondary is null or length(btrim(phone_secondary)) > 0),
  extension text check (extension is null or length(btrim(extension)) > 0),
  email text check (
    email is null
    or email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
  ),
  address text check (address is null or length(btrim(address)) > 0),
  notes text check (notes is null or length(btrim(notes)) > 0),
  is_emergency boolean not null default false,
  available_24_7 boolean not null default false,
  -- Ordering hint, lowest first. Emergency contacts are surfaced by the
  -- category regardless, this only breaks ties within a category.
  display_order integer not null default 100 check (display_order between 0 and 10000),
  status text not null default 'active' check (status in ('active','archived')),
  created_by uuid not null references public.app_users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index directory_contacts_tenant_idx
  on public.directory_contacts(tenant_id, category, status, display_order);
create index directory_contacts_facility_idx
  on public.directory_contacts(tenant_id, facility_id, status);
create index directory_contacts_name_idx
  on public.directory_contacts(tenant_id, lower(name));

create trigger directory_contacts_set_updated_at before update on public.directory_contacts
  for each row execute function nodex.tg_set_updated_at();

-- An archived contact is a historical reference: it freezes so the number a
-- past incident named cannot be rewritten. Reactivation is deliberately not
-- offered — a contact that must come back is registered afresh, which leaves
-- the archive honest about what was retired and when.
create or replace function nodex.tg_directory_contact_archive_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  -- An archived row is frozen in full, status included: archiving is a one-way
  -- transition because a contact that must return is registered afresh.
  if old.status = 'archived' then
    if new.status is distinct from old.status
      or new.name is distinct from old.name
      or new.category is distinct from old.category
      or new.phone_primary is distinct from old.phone_primary
      or new.phone_secondary is distinct from old.phone_secondary
      or new.extension is distinct from old.extension
      or new.email is distinct from old.email
      or new.contact_role is distinct from old.contact_role
      or new.organisation is distinct from old.organisation
      or new.address is distinct from old.address
      or new.notes is distinct from old.notes
      or new.facility_id is distinct from old.facility_id
      or new.department_id is distinct from old.department_id
      or new.is_emergency is distinct from old.is_emergency
      or new.available_24_7 is distinct from old.available_24_7
      or new.display_order is distinct from old.display_order then
      raise exception using message = 'NODEX: archived contacts are immutable', errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;
create trigger directory_contacts_archive_guard before update on public.directory_contacts
  for each row execute function nodex.tg_directory_contact_archive_guard();
create trigger directory_contacts_retain before delete on public.directory_contacts
  for each row execute function nodex.tg_block_mutation();

alter table public.directory_contacts enable row level security;
alter table public.directory_contacts force row level security;

create policy directory_contacts_select_member on public.directory_contacts for select to authenticated
  using (nodex.has_permission(tenant_id, 'contacts.read'));
create policy directory_contacts_insert_admin on public.directory_contacts for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'contacts.administer'));
create policy directory_contacts_update_admin on public.directory_contacts for update to authenticated
  using (nodex.has_permission(tenant_id, 'contacts.administer'))
  with check (nodex.has_permission(tenant_id, 'contacts.administer'));

insert into public.permissions (key, display_name, description, module_code, risk_tier, requires_online)
values
  ('contacts.read',       'Read contacts directory',  'Browse the hospital contacts directory.', 'M42', 'standard', false),
  ('contacts.administer', 'Administer contacts directory', 'Register, maintain and archive hospital contacts.', 'M42', 'elevated', false)
on conflict (key) do nothing;

insert into public.role_permissions (role_key, permission_key)
values
  ('hospital_super_admin', 'contacts.read'),
  ('hospital_super_admin', 'contacts.administer'),
  ('medical_officer',      'contacts.read'),
  ('nursing_staff',        'contacts.read'),
  ('lab_technician',       'contacts.read'),
  ('pharmacist',           'contacts.read'),
  ('billing_accounts',     'contacts.read'),
  ('auditor',              'contacts.read')
on conflict do nothing;
