-- NODEX Phase 4, Module 34: Statutory Records & Birth/Death Registry.
--
-- Specification scope: "Birth and death certificate registries, cause-of-death
-- coding, and Medico-Legal Case (MLC) police intimations."
-- Audit invariant: "Append-only records. Modifications generate linked amendment
-- events; hard deletions are blocked by PostgreSQL RLS."
--
-- This is the statutory estate: the register a hospital is legally obliged to
-- keep. It is distinct from the clinical record (Module 16 encounters hold the
-- care; a birth registration is the fact the civil registry is told) and from
-- the document vault (Module 33 holds artefacts; this module holds the register
-- entries those artefacts are issued against).
--
-- Four tables, three registers and the amendment log that the audit invariant
-- demands:
--
--   * `statutory_birth_records` is the birth register entry: who was born, when,
--     where, to whom, and the certificate number once one is issued. It is a
--     guarded state machine `drafted → registered → certified`, voidable from
--     either live stage with a reason.
--   * `statutory_death_records` is the death register entry, carrying the
--     cause-of-death coding (free text plus the ICD-10 code and the manner of
--     death). A death cannot be registered without that coding, a rule the
--     database enforces and the client checks so the answer is immediate
--     offline. Same state machine as a birth.
--   * `statutory_mlc_intimations` is the medico-legal case: the police
--     intimation the law requires when a death or injury is not natural.
--     `reported → intimated → acknowledged → closed`, voidable from either of
--     the two live stages. The dates and the police reference are the facts an
--     inquest turns on, so a closed case is frozen.
--   * `statutory_record_amendments` is the only way a registered fact changes:
--     an append-only row naming the field, the previous value, the new value, a
--     reason and who attested the correction. It is linked to exactly one of the
--     three registers (a CHECK enforces that), and it is the reason the three
--     register tables can be frozen the moment they are registered.
--
-- The append-only invariant is enforced in three places, as the encounters
-- amendment pattern does: no UPDATE or DELETE policy on the amendment table, an
-- append-only trigger that blocks both, and a guard that freezes a register row
-- once it reaches `registered`. A correction is therefore never an edit.
--
-- Two facts are derived rather than stored, because a stored copy drifts from
-- the fact it summarises: the corrected value of a registered fact, computed by
-- replaying the amendments over the row, and whether a registration or an
-- intimation is overdue against its statutory window.
--
-- Four permissions are granted explicitly because the Phase 1 all-permissions
-- seed predates these keys. Registering a birth or death and certifying it are
-- separated (as Module 33 separates consent capture from the vault), so a ward
-- midwife can register a birth at the bedside without being able to issue the
-- legal certificate, and certification is `requires_online` because a
-- certificate is a finalization act, like a discharge. Amending a registered
-- fact is its own tier, offline, because a correction must be recordable where
-- the error was found.

create table public.statutory_birth_records (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  facility_id uuid not null references public.facilities(id) on delete restrict,
  registration_number text
    check (registration_number is null
           or length(btrim(registration_number)) > 0),
  child_name text not null check (length(btrim(child_name)) > 0),
  sex text not null check (sex in ('male','female','ambiguous','unknown')),
  birth_at timestamptz not null,
  place_of_birth text not null check (length(btrim(place_of_birth)) > 0),
  delivery_type text not null default 'normal'
    check (delivery_type in ('normal','assisted','cesarean','breech','other')),
  plurality text not null default 'singleton'
    check (plurality in ('singleton','twin','triplet','higher')),
  weight_grams integer
    check (weight_grams is null or (weight_grams > 0 and weight_grams <= 20000)),
  mother_patient_id uuid references public.patients(id) on delete set null,
  mother_name text not null check (length(btrim(mother_name)) > 0),
  father_name text check (father_name is null or length(btrim(father_name)) > 0),
  informant_name text
    check (informant_name is null or length(btrim(informant_name)) > 0),
  attended_by uuid references public.app_users(id) on delete set null,
  status text not null default 'drafted'
    check (status in ('drafted','registered','certified','voided')),
  registration_at timestamptz,
  certificate_number text
    check (certificate_number is null
           or length(btrim(certificate_number)) > 0),
  certified_by uuid references public.app_users(id) on delete set null,
  certified_at timestamptz,
  voided_at timestamptz,
  void_reason text check (void_reason is null or length(btrim(void_reason)) > 0),
  created_by uuid not null references public.app_users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- A register number is a fact once assigned: no two entries share one.
  unique (tenant_id, registration_number),
  -- Entry into the register assigns the number and the moment, together.
  constraint birth_registered_ck check (
    status = 'drafted'
    or (registration_number is not null and registration_at is not null)
  ),
  -- A certificate exists only on a certified entry, and names who issued it.
  constraint birth_certified_ck check (
    status <> 'certified'
    or (certificate_number is not null and certified_at is not null
        and certified_by is not null)
  ),
  constraint birth_no_certificate_ck check (
    status = 'certified' or certificate_number is null
  ),
  constraint birth_voided_ck check (
    status <> 'voided'
    or (voided_at is not null and void_reason is not null
        and length(btrim(void_reason)) > 0)
  )
);
create index statutory_birth_tenant_idx
  on public.statutory_birth_records(tenant_id, status, birth_at desc);
create index statutory_birth_mother_idx
  on public.statutory_birth_records(tenant_id, mother_patient_id);

create table public.statutory_death_records (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  facility_id uuid not null references public.facilities(id) on delete restrict,
  registration_number text
    check (registration_number is null
           or length(btrim(registration_number)) > 0),
  patient_id uuid references public.patients(id) on delete set null,
  deceased_name text not null check (length(btrim(deceased_name)) > 0),
  sex text not null check (sex in ('male','female','ambiguous','unknown')),
  age_years integer check (age_years is null or age_years between 0 and 130),
  death_at timestamptz not null,
  place_of_death text not null check (length(btrim(place_of_death)) > 0),
  cause_of_death_text text
    check (cause_of_death_text is null
           or length(btrim(cause_of_death_text)) > 0),
  icd10_code text
    check (icd10_code is null or icd10_code ~ '^[A-Z][0-9]{2}(\.[0-9A-Z]{1,4})?$'),
  manner_of_death text
    check (manner_of_death is null
           or manner_of_death in ('natural','accident','suicide','homicide',
                                  'undetermined','pending')),
  is_medico_legal boolean not null default false,
  certifying_clinician uuid references public.app_users(id) on delete set null,
  informant_name text
    check (informant_name is null or length(btrim(informant_name)) > 0),
  informant_relationship text
    check (informant_relationship is null
           or length(btrim(informant_relationship)) > 0),
  status text not null default 'drafted'
    check (status in ('drafted','registered','certified','voided')),
  registration_at timestamptz,
  certificate_number text
    check (certificate_number is null
           or length(btrim(certificate_number)) > 0),
  certified_by uuid references public.app_users(id) on delete set null,
  certified_at timestamptz,
  voided_at timestamptz,
  void_reason text check (void_reason is null or length(btrim(void_reason)) > 0),
  created_by uuid not null references public.app_users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, registration_number),
  -- A death enters the register with its cause coded: an uncoded death is an
  -- unfinished record, not a registration.
  constraint death_registered_ck check (
    status = 'drafted'
    or (registration_number is not null and registration_at is not null
        and cause_of_death_text is not null and icd10_code is not null
        and manner_of_death is not null and certifying_clinician is not null)
  ),
  constraint death_certified_ck check (
    status <> 'certified'
    or (certificate_number is not null and certified_at is not null
        and certified_by is not null)
  ),
  constraint death_no_certificate_ck check (
    status = 'certified' or certificate_number is null
  ),
  constraint death_voided_ck check (
    status <> 'voided'
    or (voided_at is not null and void_reason is not null
        and length(btrim(void_reason)) > 0)
  )
);
create index statutory_death_tenant_idx
  on public.statutory_death_records(tenant_id, status, death_at desc);
create index statutory_death_coding_idx
  on public.statutory_death_records(tenant_id, icd10_code);

create table public.statutory_mlc_intimations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  facility_id uuid not null references public.facilities(id) on delete restrict,
  case_number text not null check (length(btrim(case_number)) > 0),
  patient_id uuid references public.patients(id) on delete set null,
  subject_name text not null check (length(btrim(subject_name)) > 0),
  case_type text not null
    check (case_type in ('road_traffic_accident','assault','poisoning','burn',
                         'sexual_assault','drowning','firearm','fall','other')),
  incident_at timestamptz,
  reported_at timestamptz not null default now(),
  reporting_clinician uuid references public.app_users(id) on delete set null,
  police_station text
    check (police_station is null or length(btrim(police_station)) > 0),
  police_officer_name text
    check (police_officer_name is null
           or length(btrim(police_officer_name)) > 0),
  police_contact text
    check (police_contact is null or length(btrim(police_contact)) > 0),
  police_reference text
    check (police_reference is null or length(btrim(police_reference)) > 0),
  status text not null default 'reported'
    check (status in ('reported','intimated','acknowledged','closed','voided')),
  intimated_at timestamptz,
  acknowledged_at timestamptz,
  closed_at timestamptz,
  closure_reason text
    check (closure_reason is null or length(btrim(closure_reason)) > 0),
  voided_at timestamptz,
  void_reason text check (void_reason is null or length(btrim(void_reason)) > 0),
  created_by uuid not null references public.app_users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- One case number per tenant: two files for one incident are one incident.
  unique (tenant_id, case_number),
  -- Intimating the police names the station and the moment.
  constraint mlc_intimated_ck check (
    status in ('reported','voided')
    or (police_station is not null and intimated_at is not null)
  ),
  -- Acknowledgement is the police reference and its moment.
  constraint mlc_acknowledged_ck check (
    status in ('reported','intimated','voided')
    or (police_reference is not null and acknowledged_at is not null)
  ),
  -- A case closes with a reason; a statutory file does not just stop.
  constraint mlc_closed_ck check (
    status <> 'closed'
    or (closed_at is not null and closure_reason is not null
        and length(btrim(closure_reason)) > 0)
  ),
  constraint mlc_voided_ck check (
    status <> 'voided'
    or (voided_at is not null and void_reason is not null
        and length(btrim(void_reason)) > 0)
  )
);
create index statutory_mlc_tenant_idx
  on public.statutory_mlc_intimations(tenant_id, status, reported_at desc);
create index statutory_mlc_patient_idx
  on public.statutory_mlc_intimations(tenant_id, patient_id);

-- The amendment log. It is the only mechanism by which a registered fact
-- changes, which is what lets the register tables freeze on registration.
create table public.statutory_record_amendments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  birth_record_id uuid
    references public.statutory_birth_records(id) on delete restrict,
  death_record_id uuid
    references public.statutory_death_records(id) on delete restrict,
  mlc_intimation_id uuid
    references public.statutory_mlc_intimations(id) on delete restrict,
  subject_field text not null check (length(btrim(subject_field)) > 0),
  previous_value text,
  new_value text not null check (length(btrim(new_value)) > 0),
  reason text not null check (length(btrim(reason)) > 0),
  amended_by uuid not null references public.app_users(id) on delete restrict,
  created_at timestamptz not null default now(),
  -- An amendment belongs to exactly one register.
  constraint statutory_amendment_subject_ck check (
    (case when birth_record_id is null then 0 else 1 end)
    + (case when death_record_id is null then 0 else 1 end)
    + (case when mlc_intimation_id is null then 0 else 1 end) = 1
  )
);
create index statutory_amendment_birth_idx
  on public.statutory_record_amendments(birth_record_id, created_at desc);
create index statutory_amendment_death_idx
  on public.statutory_record_amendments(death_record_id, created_at desc);
create index statutory_amendment_mlc_idx
  on public.statutory_record_amendments(mlc_intimation_id, created_at desc);

comment on table public.statutory_record_amendments is
  'Append-only correction to a registered statutory fact. The register row is never edited; this records which field changed, from what, to what, why, and who attested it.';

create trigger statutory_birth_set_updated_at
  before update on public.statutory_birth_records
  for each row execute function nodex.tg_set_updated_at();
create trigger statutory_death_set_updated_at
  before update on public.statutory_death_records
  for each row execute function nodex.tg_set_updated_at();
create trigger statutory_mlc_set_updated_at
  before update on public.statutory_mlc_intimations
  for each row execute function nodex.tg_set_updated_at();

-- Hard deletions are blocked at the table as well as by RLS, so an owner-level
-- mistake cannot erase a statutory record either.
create trigger statutory_birth_retain
  before delete on public.statutory_birth_records
  for each row execute function nodex.tg_block_mutation();
create trigger statutory_death_retain
  before delete on public.statutory_death_records
  for each row execute function nodex.tg_block_mutation();
create trigger statutory_mlc_retain
  before delete on public.statutory_mlc_intimations
  for each row execute function nodex.tg_block_mutation();
create trigger statutory_amendment_append_only_update
  before update on public.statutory_record_amendments
  for each row execute function nodex.tg_block_mutation();
create trigger statutory_amendment_append_only_delete
  before delete on public.statutory_record_amendments
  for each row execute function nodex.tg_block_mutation();

-- A birth is edited freely while drafted, and is then frozen: registration, not
-- an edit, is what moves it on, and after that only an amendment changes a fact.
create or replace function nodex.tg_statutory_birth_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status in ('certified','voided') then
    raise exception using
      message = 'NODEX: a closed birth registration is immutable',
      errcode = '42501';
  end if;
  if old.status = 'registered' then
    if new.child_name is distinct from old.child_name
      or new.sex is distinct from old.sex
      or new.birth_at is distinct from old.birth_at
      or new.place_of_birth is distinct from old.place_of_birth
      or new.delivery_type is distinct from old.delivery_type
      or new.plurality is distinct from old.plurality
      or new.weight_grams is distinct from old.weight_grams
      or new.mother_patient_id is distinct from old.mother_patient_id
      or new.mother_name is distinct from old.mother_name
      or new.father_name is distinct from old.father_name
      or new.informant_name is distinct from old.informant_name
      or new.attended_by is distinct from old.attended_by
      or new.registration_number is distinct from old.registration_number
      or new.registration_at is distinct from old.registration_at then
      raise exception using
        message = 'NODEX: a registered birth is corrected by amendment, not by edit',
        errcode = '42501';
    end if;
  end if;
  if new.status = old.status then
    if old.status = 'registered' then
      raise exception using
        message = 'NODEX: a registered birth is corrected by amendment, not by edit',
        errcode = '42501';
    end if;
    return new;
  end if;
  if new.status = 'certified' and auth.uid() is not null
    and not nodex.has_permission(new.tenant_id, 'statutory.certify') then
    raise exception using
      message = 'NODEX: certifying a birth requires statutory.certify',
      errcode = '42501';
  end if;
  if new.status = 'voided' and auth.uid() is not null
    and not nodex.has_permission(new.tenant_id, 'statutory.amend') then
    raise exception using
      message = 'NODEX: voiding a registration requires statutory.amend',
      errcode = '42501';
  end if;
  if (old.status = 'drafted' and new.status in ('registered','voided'))
    or (old.status = 'registered' and new.status in ('certified','voided')) then
    return new;
  end if;
  raise exception using
    message = 'NODEX: a birth registration may not skip a stage',
    errcode = '42501';
end;
$$;
create trigger statutory_birth_guard
  before update on public.statutory_birth_records
  for each row execute function nodex.tg_statutory_birth_guard();

-- The death guard is the birth guard with the coding columns in the frozen set.
create or replace function nodex.tg_statutory_death_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status in ('certified','voided') then
    raise exception using
      message = 'NODEX: a closed death registration is immutable',
      errcode = '42501';
  end if;
  if old.status = 'registered' then
    if new.patient_id is distinct from old.patient_id
      or new.deceased_name is distinct from old.deceased_name
      or new.sex is distinct from old.sex
      or new.age_years is distinct from old.age_years
      or new.death_at is distinct from old.death_at
      or new.place_of_death is distinct from old.place_of_death
      or new.cause_of_death_text is distinct from old.cause_of_death_text
      or new.icd10_code is distinct from old.icd10_code
      or new.manner_of_death is distinct from old.manner_of_death
      or new.is_medico_legal is distinct from old.is_medico_legal
      or new.certifying_clinician is distinct from old.certifying_clinician
      or new.informant_name is distinct from old.informant_name
      or new.informant_relationship is distinct from old.informant_relationship
      or new.registration_number is distinct from old.registration_number
      or new.registration_at is distinct from old.registration_at then
      raise exception using
        message = 'NODEX: a registered death is corrected by amendment, not by edit',
        errcode = '42501';
    end if;
  end if;
  if new.status = old.status then
    if old.status = 'registered' then
      raise exception using
        message = 'NODEX: a registered death is corrected by amendment, not by edit',
        errcode = '42501';
    end if;
    return new;
  end if;
  if new.status = 'certified' and auth.uid() is not null
    and not nodex.has_permission(new.tenant_id, 'statutory.certify') then
    raise exception using
      message = 'NODEX: certifying a death requires statutory.certify',
      errcode = '42501';
  end if;
  if new.status = 'voided' and auth.uid() is not null
    and not nodex.has_permission(new.tenant_id, 'statutory.amend') then
    raise exception using
      message = 'NODEX: voiding a registration requires statutory.amend',
      errcode = '42501';
  end if;
  if (old.status = 'drafted' and new.status in ('registered','voided'))
    or (old.status = 'registered' and new.status in ('certified','voided')) then
    return new;
  end if;
  raise exception using
    message = 'NODEX: a death registration may not skip a stage',
    errcode = '42501';
end;
$$;
create trigger statutory_death_guard
  before update on public.statutory_death_records
  for each row execute function nodex.tg_statutory_death_guard();

-- A medico-legal case advances one stage at a time. The incident facts freeze
-- once the police are told, because that is the point at which they are relied
-- on; the intimation and acknowledgement fields are set by the transition that
-- carries the case forward.
create or replace function nodex.tg_statutory_mlc_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status in ('closed','voided') then
    raise exception using
      message = 'NODEX: a closed medico-legal case is immutable',
      errcode = '42501';
  end if;
  if old.status <> 'reported' then
    if new.case_number is distinct from old.case_number
      or new.patient_id is distinct from old.patient_id
      or new.subject_name is distinct from old.subject_name
      or new.case_type is distinct from old.case_type
      or new.incident_at is distinct from old.incident_at
      or new.reported_at is distinct from old.reported_at
      or new.reporting_clinician is distinct from old.reporting_clinician then
      raise exception using
        message = 'NODEX: an intimated case is corrected by amendment, not by edit',
        errcode = '42501';
    end if;
  end if;
  if new.status = old.status then
    if old.status in ('intimated','acknowledged') then
      raise exception using
        message = 'NODEX: an intimated case is corrected by amendment, not by edit',
        errcode = '42501';
    end if;
    return new;
  end if;
  if new.status = 'voided' and auth.uid() is not null
    and not nodex.has_permission(new.tenant_id, 'statutory.amend') then
    raise exception using
      message = 'NODEX: voiding a case requires statutory.amend',
      errcode = '42501';
  end if;
  if (old.status = 'reported' and new.status in ('intimated','voided'))
    or (old.status = 'intimated' and new.status in ('acknowledged','voided'))
    or (old.status = 'acknowledged' and new.status = 'closed') then
    return new;
  end if;
  raise exception using
    message = 'NODEX: a medico-legal case may not skip a stage',
    errcode = '42501';
end;
$$;
create trigger statutory_mlc_guard
  before update on public.statutory_mlc_intimations
  for each row execute function nodex.tg_statutory_mlc_guard();

alter table public.statutory_birth_records enable row level security;
alter table public.statutory_birth_records force row level security;
alter table public.statutory_death_records enable row level security;
alter table public.statutory_death_records force row level security;
alter table public.statutory_mlc_intimations enable row level security;
alter table public.statutory_mlc_intimations force row level security;
alter table public.statutory_record_amendments enable row level security;
alter table public.statutory_record_amendments force row level security;

create policy statutory_birth_select_member on public.statutory_birth_records for select to authenticated
  using (nodex.has_permission(tenant_id, 'statutory.read'));
create policy statutory_birth_insert_registrar on public.statutory_birth_records for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'statutory.register'));
create policy statutory_birth_update_registrar on public.statutory_birth_records for update to authenticated
  using (nodex.has_permission(tenant_id, 'statutory.register'))
  with check (nodex.has_permission(tenant_id, 'statutory.register'));

create policy statutory_death_select_member on public.statutory_death_records for select to authenticated
  using (nodex.has_permission(tenant_id, 'statutory.read'));
create policy statutory_death_insert_registrar on public.statutory_death_records for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'statutory.register'));
create policy statutory_death_update_registrar on public.statutory_death_records for update to authenticated
  using (nodex.has_permission(tenant_id, 'statutory.register'))
  with check (nodex.has_permission(tenant_id, 'statutory.register'));

create policy statutory_mlc_select_member on public.statutory_mlc_intimations for select to authenticated
  using (nodex.has_permission(tenant_id, 'statutory.read'));
create policy statutory_mlc_insert_registrar on public.statutory_mlc_intimations for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'statutory.register'));
create policy statutory_mlc_update_registrar on public.statutory_mlc_intimations for update to authenticated
  using (nodex.has_permission(tenant_id, 'statutory.register'))
  with check (nodex.has_permission(tenant_id, 'statutory.register'));

-- The amendment log is append-only through RLS as well as through the trigger:
-- there is a select and an insert policy and deliberately no update or delete
-- policy, so PostgreSQL refuses the write even before the trigger fires.
create policy statutory_amendment_select_member on public.statutory_record_amendments for select to authenticated
  using (nodex.has_permission(tenant_id, 'statutory.read'));
create policy statutory_amendment_insert_amender on public.statutory_record_amendments for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'statutory.amend'));

insert into public.permissions (key, display_name, description, module_code, risk_tier, requires_online)
values
  ('statutory.read',     'Read statutory records',     'View the birth and death registers, cause-of-death coding and medico-legal intimations.', 'M34', 'standard', false),
  ('statutory.register', 'Register births and deaths', 'Raise statutory entries, record cause-of-death coding and log medico-legal intimations.', 'M34', 'elevated', false),
  ('statutory.certify',  'Certify statutory records',  'Issue birth and death certificates against a registered entry.', 'M34', 'elevated', true),
  ('statutory.amend',    'Amend statutory records',    'Append a correction to a registered fact and void a withdrawn registration.', 'M34', 'elevated', false)
on conflict (key) do nothing;

insert into public.role_permissions (role_key, permission_key)
values
  ('hospital_super_admin', 'statutory.read'),
  ('hospital_super_admin', 'statutory.register'),
  ('hospital_super_admin', 'statutory.certify'),
  ('hospital_super_admin', 'statutory.amend'),
  ('medical_officer',      'statutory.read'),
  ('medical_officer',      'statutory.register'),
  ('medical_officer',      'statutory.certify'),
  ('medical_officer',      'statutory.amend'),
  ('nursing_staff',        'statutory.read'),
  ('nursing_staff',        'statutory.register'),
  ('auditor',              'statutory.read')
on conflict do nothing;
