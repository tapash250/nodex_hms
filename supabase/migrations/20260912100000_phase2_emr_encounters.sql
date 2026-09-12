-- NODEX Phase 2, Module 16 (Longitudinal EMR/EHR): clinical encounters.
--
-- Handbook corrections carried over from Module 10:
--   1. FKs point at app_users(id), not the non-existent users(id).
--   2. RLS derives scope from memberships, not auth.jwt() claims, so a
--      principal with memberships in several tenants works correctly.
--
-- The defining clinical invariant is the signature gate: once an encounter is
-- signed it is frozen. Corrections never edit the signed record; they are
-- append-only amendments referencing it. Enforced in three places — a CHECK
-- for signature consistency, a BEFORE UPDATE trigger for the freeze, and RLS
-- with no update policy on the amendments table.

create table public.clinical_encounters (
  id                     uuid primary key default gen_random_uuid(),
  tenant_id              uuid not null references public.tenants (id) on delete restrict,
  patient_id             uuid not null references public.patients (id) on delete restrict,
  attending_physician_id uuid not null references public.app_users (id) on delete restrict,
  encounter_type         text not null
                         check (encounter_type in ('outpatient', 'inpatient', 'emergency', 'telehealth')),
  status                 text not null default 'in_progress'
                         check (status in ('planned', 'in_progress', 'signed_and_locked', 'amended')),
  subjective_note        text,
  objective_findings     text,
  assessment             text,
  plan_description       text,
  diagnoses              jsonb not null default '[]'::jsonb,
  signed_at              timestamptz,
  created_by             uuid references public.app_users (id) on delete set null,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  -- A signature timestamp and a signed status are inseparable: neither may
  -- exist without the other, so a record cannot appear signed without evidence
  -- or be locked without recording when.
  constraint clinical_encounters_signature_ck check (
    (status in ('planned', 'in_progress') and signed_at is null)
    or (status in ('signed_and_locked', 'amended') and signed_at is not null)
  )
);

comment on table public.clinical_encounters is
  'Longitudinal encounter record. Frozen once signed; corrections exist only as rows in encounter_amendments.';
comment on column public.clinical_encounters.diagnoses is
  'Coded diagnoses as JSON. Codes, not free text, so downstream rule engines and the clinical event stream can consume them.';

create index clinical_encounters_patient_idx
  on public.clinical_encounters (tenant_id, patient_id, created_at desc);
create index clinical_encounters_physician_idx
  on public.clinical_encounters (tenant_id, attending_physician_id, status);

create trigger clinical_encounters_set_updated_at
  before update on public.clinical_encounters
  for each row execute function nodex.tg_set_updated_at();

create table public.encounter_amendments (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references public.tenants (id) on delete restrict,
  encounter_id   uuid not null references public.clinical_encounters (id) on delete restrict,
  amendment_type text not null default 'correction'
                 check (amendment_type in ('correction', 'addendum')),
  reason         text not null check (length(btrim(reason)) > 0),
  field_changes  jsonb not null default '{}'::jsonb,
  amended_by     uuid not null references public.app_users (id) on delete restrict,
  created_at     timestamptz not null default now()
);

comment on table public.encounter_amendments is
  'Append-only correction to a signed encounter. The original signed row is never edited; this records what changed, why, and by whom.';

create index encounter_amendments_encounter_idx
  on public.encounter_amendments (encounter_id, created_at desc);

create trigger encounter_amendments_append_only_update
  before update on public.encounter_amendments
  for each row execute function nodex.tg_block_mutation();

create trigger encounter_amendments_append_only_delete
  before delete on public.encounter_amendments
  for each row execute function nodex.tg_block_mutation();

-- The signature gate. Once signed, clinical content is immutable and the only
-- permitted status transition is signed_and_locked -> amended, which happens
-- when an amendment is recorded. Everything else raises, so a bug or a
-- malicious client cannot quietly rewrite a signed note.
create or replace function nodex.tg_encounter_freeze_after_sign()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.status in ('signed_and_locked', 'amended') then
    if new.tenant_id              is distinct from old.tenant_id
       or new.patient_id             is distinct from old.patient_id
       or new.attending_physician_id is distinct from old.attending_physician_id
       or new.encounter_type         is distinct from old.encounter_type
       or new.subjective_note        is distinct from old.subjective_note
       or new.objective_findings     is distinct from old.objective_findings
       or new.assessment             is distinct from old.assessment
       or new.plan_description       is distinct from old.plan_description
       or new.diagnoses              is distinct from old.diagnoses
       or new.signed_at              is distinct from old.signed_at
       or new.created_by             is distinct from old.created_by
       or new.created_at             is distinct from old.created_at
    then
      raise exception using
        message = 'NODEX: encounter ' || old.id || ' is signed; correct it with an amendment, not an edit',
        errcode = '42501';
    end if;

    if new.status is distinct from old.status
       and not (old.status = 'signed_and_locked' and new.status = 'amended')
    then
      raise exception using
        message = 'NODEX: the only transition from a signed encounter is signed_and_locked -> amended',
        errcode = '42501';
    end if;
  end if;

  return new;
end;
$$;

comment on function nodex.tg_encounter_freeze_after_sign() is
  'BEFORE UPDATE guard: freezes a signed encounter and permits only signed_and_locked -> amended.';

create trigger clinical_encounters_freeze_after_sign
  before update on public.clinical_encounters
  for each row execute function nodex.tg_encounter_freeze_after_sign();

alter table public.clinical_encounters enable row level security;
alter table public.clinical_encounters force row level security;
alter table public.encounter_amendments enable row level security;
alter table public.encounter_amendments force row level security;

create policy clinical_encounters_select_member on public.clinical_encounters
  for select to authenticated
  using (nodex.has_permission(tenant_id, 'encounter.read'));

create policy clinical_encounters_insert_writer on public.clinical_encounters
  for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'encounter.write'));

create policy clinical_encounters_update_writer on public.clinical_encounters
  for update to authenticated
  using (nodex.has_permission(tenant_id, 'encounter.write'))
  with check (nodex.has_permission(tenant_id, 'encounter.write'));

create policy encounter_amendments_select_member on public.encounter_amendments
  for select to authenticated
  using (nodex.has_permission(tenant_id, 'encounter.read'));

-- Insert only. No update or delete policy exists, so an amendment can never be
-- rewritten once recorded, matching the append-only triggers.
create policy encounter_amendments_insert_writer on public.encounter_amendments
  for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'encounter.write'));
