-- NODEX Phase 2, Module 10 (Master Patient Index): patient identity tables.
--
-- Adapted from the Engineering Handbook Module 10 with three corrections:
--   1. Handbook declares `mrn TEXT UNIQUE` globally. In a multi-tenant system
--      two hospitals legitimately issue the same local MRN, so uniqueness is
--      (tenant_id, mrn). A global constraint would reject valid registrations.
--   2. Handbook references `users(id)`. The authorization subject is
--      `app_users(id)`; every FK points there.
--   3. Handbook RLS reads `auth.jwt() ->> 'tenant_id'`. A single JWT claim
--      cannot represent a principal holding memberships in several tenants, so
--      all policies here use the membership-derived nodex.has_* helpers, the
--      same source the snapshot issuance RPC derives scopes from.
--
-- Allergies are a separate entity (not JSONB columns) per the authoritative
-- spec's shared data model: allergy changes are safety-critical and retain
-- immutable history — a correction retires a row and inserts a new one, never
-- edits substance/reaction/severity in place.
--
-- Writes from devices route through the mutation-handler Edge Function, which
-- writes the audit row (audit-before-apply). RLS write policies additionally
-- admit direct patient.write inserts for admin/backfill paths.

create table public.patients (
  id                uuid primary key default gen_random_uuid(),
  tenant_id         uuid not null references public.tenants (id) on delete restrict,
  mrn               text not null check (length(btrim(mrn)) > 0),
  national_id_hash  text,
  first_name        text not null check (length(btrim(first_name)) > 0),
  last_name         text not null check (length(btrim(last_name)) > 0),
  date_of_birth     date not null check (date_of_birth <= current_date),
  gender            text not null check (gender in ('male', 'female', 'other', 'unknown')),
  blood_group       text check (blood_group is null or blood_group in
                      ('A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-')),
  phone_number      text,
  is_active         boolean not null default true,
  created_by        uuid references public.app_users (id) on delete set null,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  unique (tenant_id, mrn)
);

comment on table public.patients is
  'Master Patient Index: one row per person per tenant. national_id_hash holds a hash only — raw national IDs are never stored.';
comment on column public.patients.mrn is
  'Medical record number, unique within a tenant. Local hospital numbering schemes collide across tenants by design.';

create unique index patients_national_id_hash_key
  on public.patients (tenant_id, national_id_hash)
  where national_id_hash is not null;

create index patients_tenant_name_idx
  on public.patients (tenant_id, lower(last_name), lower(first_name))
  where is_active;

create index patients_tenant_phone_idx
  on public.patients (tenant_id, phone_number)
  where is_active and phone_number is not null;

create index patients_tenant_dob_idx
  on public.patients (tenant_id, date_of_birth)
  where is_active;

create trigger patients_set_updated_at
  before update on public.patients
  for each row execute function nodex.tg_set_updated_at();

create table public.patient_allergies (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null references public.tenants (id) on delete restrict,
  patient_id      uuid not null references public.patients (id) on delete cascade,
  substance       text not null check (length(btrim(substance)) > 0),
  reaction        text,
  severity        text not null default 'unknown'
                  check (severity in ('mild', 'moderate', 'severe', 'unknown')),
  status          text not null default 'active'
                  check (status in ('active', 'retired')),
  retired_reason  text,
  recorded_by     uuid references public.app_users (id) on delete set null,
  recorded_at     timestamptz not null default now(),
  retired_at      timestamptz,
  created_at      timestamptz not null default now(),
  constraint patient_allergies_retirement_ck check (
    (status = 'active' and retired_at is null)
    or (status = 'retired' and retired_at is not null
        and retired_reason is not null and length(btrim(retired_reason)) > 0)
  )
);

comment on table public.patient_allergies is
  'Allergy records. Clinical columns are immutable after insert: a correction retires the row (with a reason) and inserts a new one, preserving exactly what was believed at the time of any administration.';

create index patient_allergies_patient_idx
  on public.patient_allergies (patient_id, status);

-- Allergy immutability guard: only the active -> retired transition is
-- permitted, and only with a reason and timestamp. Substance, reaction and
-- severity can never be edited in place.
create or replace function nodex.tg_allergy_retire_only()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.status = 'retired' then
    raise exception using
      message = 'NODEX: retired allergy ' || old.id || ' is immutable history',
      errcode = '42501';
  end if;

  if new.status = 'active' then
    raise exception using
      message = 'NODEX: allergy rows are append-only; correct by retiring with a reason and inserting a new row',
      errcode = '42501';
  end if;

  if new.status <> 'retired' or new.retired_at is null
     or new.retired_reason is null or btrim(new.retired_reason) = '' then
    raise exception using
      message = 'NODEX: retiring an allergy requires retired_at and retired_reason',
      errcode = '22000';
  end if;

  new.id          := old.id;
  new.tenant_id   := old.tenant_id;
  new.patient_id  := old.patient_id;
  new.substance   := old.substance;
  new.reaction    := old.reaction;
  new.severity    := old.severity;
  new.recorded_by := old.recorded_by;
  new.recorded_at := old.recorded_at;
  new.created_at  := old.created_at;

  return new;
end;
$$;

comment on function nodex.tg_allergy_retire_only() is
  'BEFORE UPDATE guard on patient_allergies: the only permitted transition is active -> retired with reason and timestamp. Clinical columns are frozen.';

create trigger patient_allergies_retire_only
  before update on public.patient_allergies
  for each row execute function nodex.tg_allergy_retire_only();

create table public.patient_merge_history (
  id                    uuid primary key default gen_random_uuid(),
  tenant_id             uuid not null references public.tenants (id) on delete restrict,
  surviving_patient_id  uuid not null references public.patients (id) on delete restrict,
  merged_patient_id     uuid not null references public.patients (id) on delete restrict,
  merged_by             uuid references public.app_users (id) on delete set null,
  reason                text not null check (length(btrim(reason)) > 0),
  field_choices         jsonb not null default '{}'::jsonb,
  created_at            timestamptz not null default now(),
  constraint patient_merge_history_distinct_ck check (surviving_patient_id <> merged_patient_id)
);

comment on table public.patient_merge_history is
  'Append-only record of master-patient merges: which record survived, which was absorbed, who decided, why, and per-field winners.';

create index patient_merge_history_surviving_idx
  on public.patient_merge_history (surviving_patient_id, created_at desc);
create index patient_merge_history_merged_idx
  on public.patient_merge_history (merged_patient_id, created_at desc);

create trigger patient_merge_history_append_only_update
  before update on public.patient_merge_history
  for each row execute function nodex.tg_block_mutation();

create trigger patient_merge_history_append_only_delete
  before delete on public.patient_merge_history
  for each row execute function nodex.tg_block_mutation();

-- ---------------------------------------------------------------------------
-- Row level security: membership-derived, never JWT claims.
-- ---------------------------------------------------------------------------

alter table public.patients enable row level security;
alter table public.patients force row level security;
alter table public.patient_allergies enable row level security;
alter table public.patient_allergies force row level security;
alter table public.patient_merge_history enable row level security;
alter table public.patient_merge_history force row level security;

create policy patients_select_member on public.patients
  for select to authenticated
  using (nodex.has_permission(tenant_id, 'patient.read'));

create policy patients_insert_writer on public.patients
  for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'patient.write'));

create policy patients_update_writer on public.patients
  for update to authenticated
  using (nodex.has_permission(tenant_id, 'patient.write'))
  with check (nodex.has_permission(tenant_id, 'patient.write'));

create policy patient_allergies_select_member on public.patient_allergies
  for select to authenticated
  using (nodex.has_permission(tenant_id, 'patient.read'));

create policy patient_allergies_insert_writer on public.patient_allergies
  for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'patient.write'));

create policy patient_allergies_update_writer on public.patient_allergies
  for update to authenticated
  using (nodex.has_permission(tenant_id, 'patient.write'))
  with check (nodex.has_permission(tenant_id, 'patient.write'));

create policy patient_merge_history_select_member on public.patient_merge_history
  for select to authenticated
  using (nodex.has_permission(tenant_id, 'patient.read'));

create policy patient_merge_history_insert_writer on public.patient_merge_history
  for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'patient.write'));
