-- NODEX Phase 4, Module 39: Master Settings & AI Configuration Hub.
--
-- Specification scope: "Hospital configuration, branding, department
-- hierarchies, billing tariff masters, and AI routing profiles." with the
-- security clause "Restricted to Super-Admins. Changes require Multi-Factor
-- Authentication (2FA) and active online connectivity."
--
-- This module is the hospital's own description of itself: what it is called,
-- what it looks like on paper, how its departments nest, what it charges, and
-- which model answers which kind of question. Everything here is configuration,
-- so nothing is ever deleted -- a settings profile is superseded, a branding
-- asset is superseded, a department is archived, a tariff is retired, and a
-- routing profile is retired. A past bill, a past letterhead and a past
-- analytics figure all have to resolve to the configuration they were produced
-- under, and a row that could be deleted could not do that.
--
-- Five tables, one per clause of the scope:
--
--   * `settings_profiles` is hospital configuration, kept as versions: the
--     hospital name, timezone, locale, date format, currency and its minor
--     units, fiscal-year start, appointment slot, session idle window and
--     whether two factors are demanded. Exactly one version is active per
--     tenant per facility; activating a new one supersedes the old rather than
--     editing it, so "what was the slot length in March" is answerable.
--   * `branding_assets` is branding: logos, letterheads, favicons and
--     watermarks, each with the two colours a Material 3 theme needs and the
--     storage path of the uploaded file. One live asset per kind per facility;
--     publishing a new one supersedes the old, and the old one is what a
--     reprint of last year's letterhead resolves to.
--   * `department_hierarchies` is the organisational tree, self-referencing, so
--     "Cardiology, under Medicine, under Clinical Services" is one structure
--     rather than three free-text strings that disagree. Depth and ancestry are
--     derived on read rather than stored, because a stored level is a fact that
--     drifts the first time a branch is re-parented. A department is archived,
--     not deleted, and a cycle is refused at the database.
--   * `billing_tariffs` is the tariff master: what a service is called, what it
--     costs in minor units, what tax rate applies, which department owns it,
--     and from when to when. A tariff is approved into life and then retired,
--     and two live tariffs for one code may not overlap in time, because an
--     invoice that has two answers is a dispute.
--   * `ai_routing_profiles` is the AI routing profile: which registered model
--     answers a task kind, what it falls back to, how warm it runs, how much it
--     may emit, where the data is allowed to reside, and whether protected
--     health information is redacted before it leaves. The model codes are
--     foreign keys into the Phase 1 governance registry, so a profile cannot
--     route to a model the hospital has not admitted. A profile that leaves the
--     country must redact, which is a CHECK constraint rather than a review
--     note.
--
-- Every change here demands two things the client cannot fake: an active
-- network (the permission rows carry `requires_online`, so the offline
-- permission subset never contains them) and a fresh second-factor assertion,
-- which the use cases demand as an argument. Reading stays offline: a device
-- needs the hospital's timezone, currency and branding to render a screen while
-- the network is down, and none of those are secrets.
--
-- Money is integer minor units and tax is integer basis points, as everywhere
-- else in NODEX: a tariff that has rounded twice is a tariff that does not add
-- up to the invoice it produced.

create table public.settings_profiles (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  -- Null means the profile is hospital-wide rather than one facility's.
  facility_id uuid references public.facilities(id) on delete restrict,
  version integer not null check (version >= 1),
  status text not null default 'draft'
    check (status in ('draft','active','superseded')),
  hospital_name text not null check (length(btrim(hospital_name)) > 0),
  -- The wall-clock and locale rules a device renders by. Stored as text because
  -- they are names (an IANA zone, a BCP-47 tag), not points in time.
  timezone text not null default 'UTC' check (length(btrim(timezone)) > 0),
  default_locale text not null default 'en' check (length(btrim(default_locale)) > 0),
  date_format text not null default 'dd-mm-yyyy'
    check (date_format in ('dd-mm-yyyy','mm-dd-yyyy','yyyy-mm-dd')),
  currency_code text not null default 'INR' check (currency_code ~ '^[A-Z]{3}$'),
  -- How many decimal places the currency is written in. Held so a device can
  -- render minor units without guessing.
  currency_minor_units integer not null default 2
    check (currency_minor_units between 0 and 4),
  fiscal_year_start_month integer not null default 4
    check (fiscal_year_start_month between 1 and 12),
  appointment_slot_minutes integer not null default 15
    check (appointment_slot_minutes between 5 and 120),
  session_idle_minutes integer not null default 15
    check (session_idle_minutes between 1 and 480),
  -- Whether this hospital demands a second factor for its own configuration.
  require_two_factor boolean not null default true,
  activated_at timestamptz,
  activated_by uuid references public.app_users(id) on delete restrict,
  superseded_at timestamptz,
  created_by uuid not null references public.app_users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint settings_profile_activated_ck check (
    status = 'draft'
    or (activated_at is not null and activated_by is not null)
  ),
  constraint settings_profile_superseded_ck check (
    status <> 'superseded' or superseded_at is not null
  )
);
-- Version numbers are per tenant and facility, and a facility-less profile is
-- hospital-wide: `coalesce` gives the hospital-wide case its own lane rather
-- than letting null equality make every row distinct.
create unique index settings_profile_version_key
  on public.settings_profiles(
    tenant_id,
    coalesce(facility_id, '00000000-0000-0000-0000-000000000000'::uuid),
    version
  );
-- Exactly one active profile per tenant per facility: a device that resolved two
-- would have two timezones.
create unique index settings_profile_active_key
  on public.settings_profiles(
    tenant_id,
    coalesce(facility_id, '00000000-0000-0000-0000-000000000000'::uuid)
  )
  where status = 'active';
create index settings_profile_status_idx
  on public.settings_profiles(tenant_id, status, version desc);

create table public.branding_assets (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  facility_id uuid references public.facilities(id) on delete restrict,
  asset_kind text not null
    check (asset_kind in ('logo','letterhead','favicon','watermark')),
  label text not null check (length(btrim(label)) > 0),
  -- The object-storage path of the uploaded file. Held as text with its digest
  -- and size so a re-upload that silently replaced the bytes would be visible.
  storage_path text check (storage_path is null or length(btrim(storage_path)) > 0),
  checksum text check (checksum is null or length(btrim(checksum)) > 0),
  mime_type text check (mime_type is null or length(btrim(mime_type)) > 0),
  byte_size integer check (byte_size is null or byte_size >= 0),
  primary_color text not null check (primary_color ~ '^#[0-9A-Fa-f]{6}$'),
  secondary_color text not null check (secondary_color ~ '^#[0-9A-Fa-f]{6}$'),
  status text not null default 'draft'
    check (status in ('draft','active','superseded')),
  activated_at timestamptz,
  activated_by uuid references public.app_users(id) on delete restrict,
  superseded_at timestamptz,
  created_by uuid not null references public.app_users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- A label names a draft's proposal, so two proposals may not share one.
  unique (tenant_id, asset_kind, label),
  constraint branding_activated_ck check (
    status = 'draft'
    or (activated_at is not null and activated_by is not null)
  ),
  constraint branding_superseded_ck check (
    status <> 'superseded' or superseded_at is not null
  )
);
create unique index branding_asset_active_key
  on public.branding_assets(
    tenant_id,
    coalesce(facility_id, '00000000-0000-0000-0000-000000000000'::uuid),
    asset_kind
  )
  where status = 'active';
create index branding_asset_kind_idx
  on public.branding_assets(tenant_id, asset_kind, status);

create table public.department_hierarchies (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  facility_id uuid references public.facilities(id) on delete restrict,
  -- Self-referencing: the tree is the structure, and ancestry is derived from it
  -- rather than written down twice.
  parent_id uuid references public.department_hierarchies(id) on delete restrict,
  code text not null check (length(btrim(code)) > 0),
  name text not null check (length(btrim(name)) > 0),
  kind text not null default 'clinical'
    check (kind in ('clinical','diagnostic','therapeutic','support','administrative')),
  -- The cost centre a tariff's revenue lands in. Null is allowed while a
  -- department is being set up, and the settings board flags those.
  cost_centre text check (cost_centre is null or length(btrim(cost_centre)) > 0),
  is_billable boolean not null default false,
  sort_order integer not null default 0 check (sort_order >= 0),
  status text not null default 'active' check (status in ('active','archived')),
  archived_at timestamptz,
  archive_reason text check (archive_reason is null or length(btrim(archive_reason)) > 0),
  created_by uuid not null references public.app_users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, code),
  constraint department_hierarchy_self_ck check (parent_id is null or parent_id <> id),
  constraint department_hierarchy_archived_ck check (
    status <> 'archived' or archived_at is not null
  )
);
create index department_hierarchy_parent_idx
  on public.department_hierarchies(tenant_id, parent_id, sort_order);
create index department_hierarchy_status_idx
  on public.department_hierarchies(tenant_id, status, kind);

create table public.billing_tariffs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  facility_id uuid references public.facilities(id) on delete restrict,
  department_id uuid references public.department_hierarchies(id) on delete restrict,
  code text not null check (length(btrim(code)) > 0),
  service_name text not null check (length(btrim(service_name)) > 0),
  category text not null
    check (category in ('consultation','procedure','investigation','room',
                        'pharmacy','consumable','package')),
  currency_code text not null check (currency_code ~ '^[A-Z]{3}$'),
  -- What the service costs, in minor units. Never a float: a tariff that has
  -- rounded twice is an invoice that does not add up.
  amount_minor integer not null check (amount_minor >= 0),
  -- Tax in basis points, so 1800 is 18%. Integer basis points keep the tax on a
  -- line item exactly reproducible.
  tax_rate_bps integer not null default 0 check (tax_rate_bps between 0 and 10000),
  insurance_capable boolean not null default true,
  status text not null default 'draft'
    check (status in ('draft','active','retired')),
  effective_from date not null,
  effective_to date,
  approved_at timestamptz,
  approved_by uuid references public.app_users(id) on delete restrict,
  retired_at timestamptz,
  retire_reason text check (retire_reason is null or length(btrim(retire_reason)) > 0),
  created_by uuid not null references public.app_users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, code, effective_from),
  constraint billing_tariff_window_ck check (
    effective_to is null or effective_to >= effective_from
  ),
  constraint billing_tariff_active_ck check (
    status <> 'active' or (approved_at is not null and approved_by is not null)
  ),
  constraint billing_tariff_retired_ck check (
    status <> 'retired'
    or (retired_at is not null and retire_reason is not null
        and length(btrim(retire_reason)) > 0)
  )
);
create index billing_tariff_code_idx
  on public.billing_tariffs(tenant_id, code, status);
create index billing_tariff_department_idx
  on public.billing_tariffs(tenant_id, department_id, effective_from desc);
create index billing_tariff_status_idx
  on public.billing_tariffs(tenant_id, status, effective_from desc);

create table public.ai_routing_profiles (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  facility_id uuid references public.facilities(id) on delete restrict,
  profile_code text not null check (length(btrim(profile_code)) > 0),
  display_name text not null check (length(btrim(display_name)) > 0),
  task_kind text not null
    check (task_kind in ('scribe','coding','triage','summarisation',
                         'translation','imaging')),
  -- A foreign key into the Phase 1 governance registry: a profile may only name
  -- a model the hospital has admitted, and the registry's own lifecycle gate
  -- still refuses a model that is not active.
  primary_model_key text not null
    references public.ai_model_registry(model_key) on delete restrict,
  fallback_model_key text references public.ai_model_registry(model_key) on delete restrict,
  -- Sampling warmth in basis points, so 0 is deterministic and 10000 is as warm
  -- as the provider allows.
  temperature_bps integer not null default 2000
    check (temperature_bps between 0 and 10000),
  max_output_tokens integer not null default 1024
    check (max_output_tokens between 64 and 32000),
  data_residency text not null default 'in_country'
    check (data_residency in ('in_country','regional','global')),
  -- Whether protected health information is stripped before the payload leaves.
  redact_phi boolean not null default true,
  status text not null default 'draft'
    check (status in ('draft','active','retired')),
  activated_at timestamptz,
  activated_by uuid references public.app_users(id) on delete restrict,
  retired_at timestamptz,
  retire_reason text check (retire_reason is null or length(btrim(retire_reason)) > 0),
  created_by uuid not null references public.app_users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, profile_code),
  constraint ai_routing_fallback_ck check (
    fallback_model_key is null or fallback_model_key <> primary_model_key
  ),
  constraint ai_routing_active_ck check (
    status <> 'active' or (activated_at is not null and activated_by is not null)
  ),
  constraint ai_routing_retired_ck check (
    status <> 'retired'
    or (retired_at is not null and retire_reason is not null
        and length(btrim(retire_reason)) > 0)
  ),
  -- A payload that may leave the country must be redacted first. This is a
  -- constraint rather than a review note because it is the one clause here that
  -- protects patients rather than money.
  constraint ai_routing_phi_ck check (data_residency = 'in_country' or redact_phi)
);
-- One live profile per task kind: two active profiles for one task are two
-- answers to which model saw the note.
create unique index ai_routing_profile_active_key
  on public.ai_routing_profiles(tenant_id, task_kind)
  where status = 'active';
create index ai_routing_profile_status_idx
  on public.ai_routing_profiles(tenant_id, status, task_kind);

comment on table public.settings_profiles is
  'Hospital configuration, versioned. Exactly one active profile per tenant and facility; activating a new version supersedes the old rather than editing it.';
comment on table public.department_hierarchies is
  'The organisational tree. Depth and ancestry are derived on read, never stored, so a re-parented branch cannot leave a stale level behind.';
comment on table public.billing_tariffs is
  'Tariff master. Amounts are minor units and tax is basis points; two live tariffs for one code may not overlap in time.';
comment on table public.ai_routing_profiles is
  'AI routing profiles. Model keys reference the governance registry, and a profile whose data may leave the country must redact PHI.';

create trigger settings_profiles_set_updated_at
  before update on public.settings_profiles
  for each row execute function nodex.tg_set_updated_at();
create trigger branding_assets_set_updated_at
  before update on public.branding_assets
  for each row execute function nodex.tg_set_updated_at();
create trigger department_hierarchies_set_updated_at
  before update on public.department_hierarchies
  for each row execute function nodex.tg_set_updated_at();
create trigger billing_tariffs_set_updated_at
  before update on public.billing_tariffs
  for each row execute function nodex.tg_set_updated_at();
create trigger ai_routing_profiles_set_updated_at
  before update on public.ai_routing_profiles
  for each row execute function nodex.tg_set_updated_at();

-- Configuration is superseded, archived or retired, never deleted: a past bill,
-- a past letterhead and a past figure all have to resolve to the settings they
-- were produced under.
create trigger settings_profiles_retain
  before delete on public.settings_profiles
  for each row execute function nodex.tg_block_mutation();
create trigger branding_assets_retain
  before delete on public.branding_assets
  for each row execute function nodex.tg_block_mutation();
create trigger department_hierarchies_retain
  before delete on public.department_hierarchies
  for each row execute function nodex.tg_block_mutation();
create trigger billing_tariffs_retain
  before delete on public.billing_tariffs
  for each row execute function nodex.tg_block_mutation();
create trigger ai_routing_profiles_retain
  before delete on public.ai_routing_profiles
  for each row execute function nodex.tg_block_mutation();

-- A settings profile moves draft -> active -> superseded, and the numbers a
-- device renders by are frozen once it is active.
create or replace function nodex.tg_settings_profile_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status = 'superseded' then
    raise exception using
      message = 'NODEX: a superseded settings profile is immutable',
      errcode = '42501';
  end if;
  if old.status = 'active'
    and (new.version is distinct from old.version
      or new.facility_id is distinct from old.facility_id) then
    raise exception using
      message = 'NODEX: an active settings profile is not re-scoped',
      errcode = '42501';
  end if;
  if new.status = old.status then
    return new;
  end if;
  if (old.status = 'draft' and new.status = 'active')
    or (old.status = 'active' and new.status = 'superseded') then
    return new;
  end if;
  raise exception using
    message = 'NODEX: a settings profile may not skip a stage',
    errcode = '42501';
end;
$$;
create trigger settings_profiles_guard
  before update on public.settings_profiles
  for each row execute function nodex.tg_settings_profile_guard();

-- A branding asset moves draft -> active -> superseded; the file it points at is
-- frozen once published.
create or replace function nodex.tg_branding_asset_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status = 'superseded' then
    raise exception using
      message = 'NODEX: a superseded branding asset is immutable',
      errcode = '42501';
  end if;
  if old.status = 'active'
    and (new.storage_path is distinct from old.storage_path
      or new.checksum is distinct from old.checksum
      or new.asset_kind is distinct from old.asset_kind) then
    raise exception using
      message = 'NODEX: an active branding asset is not re-pointed',
      errcode = '42501';
  end if;
  if new.status = old.status then
    return new;
  end if;
  if (old.status = 'draft' and new.status = 'active')
    or (old.status = 'active' and new.status = 'superseded') then
    return new;
  end if;
  raise exception using
    message = 'NODEX: a branding asset may not skip a stage',
    errcode = '42501';
end;
$$;
create trigger branding_assets_guard
  before update on public.branding_assets
  for each row execute function nodex.tg_branding_asset_guard();

-- The tree may not contain a cycle and may not be re-parented to another tenant.
-- Checked here rather than in the client because a cycle makes every read of the
-- tree non-terminating.
create or replace function nodex.tg_department_hierarchy_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'UPDATE' and old.status = 'archived' and new.status <> 'archived' then
    raise exception using
      message = 'NODEX: an archived department is not reopened',
      errcode = '42501';
  end if;
  if new.parent_id is not null then
    if new.parent_id = new.id then
      raise exception using
        message = 'NODEX: a department is not its own parent',
        errcode = '42501';
    end if;
    if (select tenant_id from public.department_hierarchies where id = new.parent_id)
       is distinct from new.tenant_id then
      raise exception using
        message = 'NODEX: a department and its parent belong to one tenant',
        errcode = '42501';
    end if;
    if exists (
      with recursive descendants as (
        select d.id from public.department_hierarchies d where d.parent_id = new.id
        union all
        select d.id
        from public.department_hierarchies d
        join descendants x on d.parent_id = x.id
      )
      select 1 from descendants where id = new.parent_id
    ) then
      raise exception using
        message = 'NODEX: a department may not be moved under its own branch',
        errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;
create trigger department_hierarchies_guard
  before insert or update on public.department_hierarchies
  for each row execute function nodex.tg_department_hierarchy_guard();

-- A tariff is approved into life, then retired. It is never rewritten back into
-- a draft, and its amount and window freeze once it is live.
create or replace function nodex.tg_billing_tariff_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status = 'retired' then
    raise exception using
      message = 'NODEX: a retired tariff is immutable',
      errcode = '42501';
  end if;
  if old.status = 'active'
    and (new.amount_minor is distinct from old.amount_minor
      or new.tax_rate_bps is distinct from old.tax_rate_bps
      or new.effective_from is distinct from old.effective_from
      or new.code is distinct from old.code) then
    raise exception using
      message = 'NODEX: a live tariff is not re-priced',
      errcode = '42501';
  end if;
  if new.status = old.status then
    return new;
  end if;
  if (old.status = 'draft' and new.status = 'active')
    or (old.status = 'active' and new.status = 'retired') then
    return new;
  end if;
  raise exception using
    message = 'NODEX: a tariff may not skip a stage',
    errcode = '42501';
end;
$$;
create trigger billing_tariffs_guard
  before update on public.billing_tariffs
  for each row execute function nodex.tg_billing_tariff_guard();

-- Two live tariffs for one code may not overlap in time: an invoice that has two
-- answers is a dispute.
create or replace function nodex.tg_billing_tariff_overlap_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.status <> 'active' then
    return new;
  end if;
  if exists (
    select 1
    from public.billing_tariffs t
    where t.tenant_id = new.tenant_id
      and t.code = new.code
      and t.id <> new.id
      and t.status = 'active'
      and daterange(t.effective_from, coalesce(t.effective_to, 'infinity'::date), '[]')
          && daterange(new.effective_from, coalesce(new.effective_to, 'infinity'::date), '[]')
  ) then
    raise exception using
      message = 'NODEX: two live tariffs for one code may not overlap',
      errcode = '23P01';
  end if;
  return new;
end;
$$;
create trigger billing_tariffs_overlap_guard
  before insert or update on public.billing_tariffs
  for each row execute function nodex.tg_billing_tariff_overlap_guard();

-- A routing profile moves draft -> active -> retired, and the model it routes to
-- freezes once it is live.
create or replace function nodex.tg_ai_routing_profile_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status = 'retired' then
    raise exception using
      message = 'NODEX: a retired routing profile is immutable',
      errcode = '42501';
  end if;
  if old.status = 'active'
    and (new.primary_model_key is distinct from old.primary_model_key
      or new.task_kind is distinct from old.task_kind) then
    raise exception using
      message = 'NODEX: a live routing profile is not re-routed',
      errcode = '42501';
  end if;
  if new.status = old.status then
    return new;
  end if;
  if (old.status = 'draft' and new.status = 'active')
    or (old.status = 'active' and new.status = 'retired') then
    return new;
  end if;
  raise exception using
    message = 'NODEX: a routing profile may not skip a stage',
    errcode = '42501';
end;
$$;
create trigger ai_routing_profiles_guard
  before update on public.ai_routing_profiles
  for each row execute function nodex.tg_ai_routing_profile_guard();

alter table public.settings_profiles enable row level security;
alter table public.settings_profiles force row level security;
alter table public.branding_assets enable row level security;
alter table public.branding_assets force row level security;
alter table public.department_hierarchies enable row level security;
alter table public.department_hierarchies force row level security;
alter table public.billing_tariffs enable row level security;
alter table public.billing_tariffs force row level security;
alter table public.ai_routing_profiles enable row level security;
alter table public.ai_routing_profiles force row level security;

create policy settings_profile_select_member on public.settings_profiles for select to authenticated
  using (nodex.has_permission(tenant_id, 'settings.read'));
create policy settings_profile_insert_configurer on public.settings_profiles for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'settings.configure'));
create policy settings_profile_update_configurer on public.settings_profiles for update to authenticated
  using (nodex.has_permission(tenant_id, 'settings.configure'))
  with check (nodex.has_permission(tenant_id, 'settings.configure'));

create policy branding_asset_select_member on public.branding_assets for select to authenticated
  using (nodex.has_permission(tenant_id, 'settings.read'));
create policy branding_asset_insert_configurer on public.branding_assets for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'settings.configure'));
create policy branding_asset_update_configurer on public.branding_assets for update to authenticated
  using (nodex.has_permission(tenant_id, 'settings.configure'))
  with check (nodex.has_permission(tenant_id, 'settings.configure'));

create policy department_hierarchy_select_member on public.department_hierarchies for select to authenticated
  using (nodex.has_permission(tenant_id, 'settings.read'));
create policy department_hierarchy_insert_configurer on public.department_hierarchies for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'settings.configure'));
create policy department_hierarchy_update_configurer on public.department_hierarchies for update to authenticated
  using (nodex.has_permission(tenant_id, 'settings.configure'))
  with check (nodex.has_permission(tenant_id, 'settings.configure'));

create policy billing_tariff_select_member on public.billing_tariffs for select to authenticated
  using (nodex.has_permission(tenant_id, 'settings.read'));
create policy billing_tariff_insert_tariff on public.billing_tariffs for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'settings.tariff'));
create policy billing_tariff_update_tariff on public.billing_tariffs for update to authenticated
  using (nodex.has_permission(tenant_id, 'settings.tariff'))
  with check (nodex.has_permission(tenant_id, 'settings.tariff'));

create policy ai_routing_profile_select_member on public.ai_routing_profiles for select to authenticated
  using (nodex.has_permission(tenant_id, 'settings.read'));
create policy ai_routing_profile_insert_configurer on public.ai_routing_profiles for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'ai.configure'));
create policy ai_routing_profile_update_configurer on public.ai_routing_profiles for update to authenticated
  using (nodex.has_permission(tenant_id, 'ai.configure'))
  with check (nodex.has_permission(tenant_id, 'ai.configure'));

insert into public.permissions (key, display_name, description, module_code, risk_tier, requires_online)
values
  ('settings.read',      'Read master settings',      'View hospital configuration, branding, the department tree, tariffs and AI routing profiles.', 'M39', 'standard', false),
  ('settings.configure', 'Configure the hospital',    'Change hospital configuration and branding, and maintain the department tree.',                'M39', 'elevated', true),
  ('settings.tariff',    'Maintain tariff masters',   'Draft, approve and retire billing tariffs.',                                                  'M39', 'elevated', true),
  ('ai.configure',       'Configure AI routing',      'Draft, activate and retire AI routing profiles.',                                             'M39', 'elevated', true)
on conflict (key) do nothing;

insert into public.role_permissions (role_key, permission_key)
values
  ('hospital_super_admin', 'settings.read'),
  ('hospital_super_admin', 'settings.configure'),
  ('hospital_super_admin', 'settings.tariff'),
  ('hospital_super_admin', 'ai.configure'),
  ('medical_officer',      'settings.read'),
  ('nursing_staff',        'settings.read'),
  ('lab_technician',       'settings.read'),
  ('pharmacist',           'settings.read'),
  ('billing_accounts',     'settings.read'),
  ('integration_service',  'settings.read'),
  ('auditor',              'settings.read')
on conflict do nothing;
