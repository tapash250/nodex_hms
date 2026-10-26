-- Module 47: Advanced Clinical Forms Builder
--
-- A form is a template plus a response. The template is a JSON schema the
-- clinical team authors; the response is what a clinician filled in and is
-- immutable once written, because a form that can be edited after the fact is
-- not evidence that the clinician asked what the form says they asked.
--
-- Templates are versioned rather than edited in place: a published template
-- is frozen, and a change is a new version, so a response can always be read
-- against the schema that was in force when it was filled.

create table public.form_templates (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  template_code text not null check (length(btrim(template_code)) > 0),
  title text not null check (length(btrim(title)) > 0),
  description text check (description is null or length(btrim(description)) > 0),
  version integer not null default 1 check (version > 0),
  schema_json jsonb not null check (jsonb_typeof(schema_json) = 'object'),
  status text not null default 'draft'
    check (status in ('draft', 'published', 'retired')),
  created_by uuid not null references public.app_users(id) on delete restrict,
  published_at timestamptz,
  retired_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, template_code, version)
);

comment on table public.form_templates is
  'JSON-schema form templates. A published template is frozen: a change is a new version, so a response can always be read against the schema that was in force when it was filled.';

create index form_templates_tenant_idx
  on public.form_templates (tenant_id, status, title);
create index form_templates_code_idx
  on public.form_templates (tenant_id, template_code, version desc);

create trigger form_templates_set_updated_at before update on public.form_templates
  for each row execute function nodex.tg_set_updated_at();

-- ---------------------------------------------------------------------------
-- Template lifecycle
-- ---------------------------------------------------------------------------

create or replace function nodex.tg_form_template_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if new.status <> 'draft' then
      raise exception using
        message = 'NODEX: a form template is drafted before it is published',
        errcode = '22000';
    end if;
    if new.published_at is not null or new.retired_at is not null then
      raise exception using
        message = 'NODEX: a new form template has neither published nor retired',
        errcode = '22000';
    end if;
    return new;
  end if;

  -- The identity of a template never changes: the code, the version and the
  -- tenant are what a response points at.
  if new.template_code is distinct from old.template_code
     or new.version is distinct from old.version
     or new.tenant_id is distinct from old.tenant_id then
    raise exception using
      message = 'NODEX: the identity of a form template is immutable',
      errcode = '42501';
  end if;

  if old.status = 'published' then
    -- A published template is frozen. It may be retired, and it may carry a
    -- clarifying description, but its schema is what the responses were
    -- filled against and it cannot be quietly rewritten.
    if new.status not in ('published', 'retired') then
      raise exception using
        message = 'NODEX: a published form template cannot be unpublished',
        errcode = '42501';
    end if;
    if new.schema_json is distinct from old.schema_json then
      raise exception using
        message = 'NODEX: a published form template is frozen; publish a new version',
        errcode = '42501';
    end if;
    if new.status = 'retired' and old.status <> 'retired' then
      new.retired_at := coalesce(new.retired_at, now());
    end if;
    return new;
  end if;

  if old.status = 'retired' then
    raise exception using
      message = 'NODEX: a retired form template is immutable',
      errcode = '42501';
  end if;

  if new.status = 'published' and old.status = 'draft' then
    new.published_at := coalesce(new.published_at, now());
    new.retired_at := null;
  end if;
  if new.status = 'retired' then
    new.retired_at := coalesce(new.retired_at, now());
  end if;
  return new;
end;
$$;

create trigger form_templates_guard
  before insert or update on public.form_templates
  for each row execute function nodex.tg_form_template_guard();

-- ---------------------------------------------------------------------------
-- Responses
-- ---------------------------------------------------------------------------

create table public.form_responses (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  template_id uuid not null references public.form_templates(id) on delete restrict,
  template_version integer not null check (template_version > 0),
  patient_id uuid references public.patients(id) on delete set null,
  encounter_id uuid references public.clinical_encounters(id) on delete restrict,
  submitted_by uuid not null references public.app_users(id) on delete restrict,
  values_json jsonb not null check (jsonb_typeof(values_json) = 'object'),
  submitted_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

comment on table public.form_responses is
  'A filled clinical form. Immutable: a form that can be edited after the fact is not evidence that the clinician asked what the form says they asked.';

create index form_responses_template_idx
  on public.form_responses (tenant_id, template_id, submitted_at desc);
create index form_responses_patient_idx
  on public.form_responses (patient_id, submitted_at desc)
  where patient_id is not null;

-- A response is a record of what was asked and answered. It is never edited
-- and never deleted; a mistake is answered by a new response.
create trigger form_responses_retain before delete on public.form_responses
  for each row execute function nodex.tg_block_mutation();

create or replace function nodex.tg_form_response_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.template_id is not null then
    -- The version recorded on the response is the version the clinician
    -- actually filled in, and it must be the version that was published.
    if not exists (
      select 1 from public.form_templates t
      where t.id = new.template_id
        and t.version = new.template_version
        and t.status in ('published', 'retired')
    ) then
      raise exception using
        message = 'NODEX: a form response must name a published template version',
        errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;

create trigger form_responses_guard
  before insert on public.form_responses
  for each row execute function nodex.tg_form_response_guard();

-- ---------------------------------------------------------------------------
-- ICD-10 reference
-- ---------------------------------------------------------------------------

create table public.icd10_codes (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[A-Z][0-9]{2}(\.[0-9A-Z]{1,4})?$'),
  description text not null check (length(btrim(description)) > 0),
  category text,
  is_billable boolean not null default true,
  created_at timestamptz not null default now()
);

comment on table public.icd10_codes is
  'ICD-10 diagnosis catalogue used for autocomplete and coding checks. Reference data, not patient data: readable by any authenticated principal.';

create index icd10_codes_description_idx
  on public.icd10_codes (description);

-- The catalogue is reference data rather than patient data, so it is readable
-- by any signed-in member of staff; the codes themselves are not PHI.
alter table public.icd10_codes enable row level security;
alter table public.icd10_codes force row level security;

create policy icd10_codes_select_all on public.icd10_codes
  for select to authenticated using (true);

-- A seed of the diagnoses a ward, clinic or emergency department meets most
-- often. The catalogue is extensible: a hospital adds the codes its own
-- coders use.
insert into public.icd10_codes (code, description, category, is_billable) values
  ('A09', 'Infectious intestinal disease, unspecified', 'Infectious', true),
  ('A16.9', 'Respiratory tuberculosis, unspecified', 'Infectious', true),
  ('B34.9', 'Viral infection, unspecified', 'Infectious', true),
  ('D50.9', 'Iron deficiency anaemia, unspecified', 'Blood', true),
  ('D64.9', 'Anaemia, unspecified', 'Blood', true),
  ('E11.9', 'Type 2 diabetes mellitus without complications', 'Endocrine', true),
  ('E14.9', 'Unspecified diabetes mellitus without complications', 'Endocrine', true),
  ('E78.5', 'Hyperlipidaemia, unspecified', 'Endocrine', true),
  ('F32.9', 'Depressive episode, unspecified', 'Mental', true),
  ('F41.9', 'Anxiety disorder, unspecified', 'Mental', true),
  ('G20', 'Parkinson''s disease', 'Neurological', true),
  ('G40.9', 'Epilepsy, unspecified', 'Neurological', true),
  ('G43.9', 'Migraine, unspecified', 'Neurological', true),
  ('I10', 'Essential (primary) hypertension', 'Circulatory', true),
  ('I21.9', 'Acute myocardial infarction, unspecified', 'Circulatory', true),
  ('I48.9', 'Paroxysmal atrial fibrillation, unspecified', 'Circulatory', true),
  ('I50.9', 'Heart failure, unspecified', 'Circulatory', true),
  ('J18.9', 'Pneumonia, unspecified organism', 'Respiratory', true),
  ('J20.9', 'Acute bronchitis, unspecified', 'Respiratory', true),
  ('J44.1', 'Chronic obstructive pulmonary disease with exacerbation', 'Respiratory', true),
  ('J45.9', 'Asthma, unspecified', 'Respiratory', true),
  ('K21.9', 'Gastro-esophageal reflux disease without oesophagitis', 'Digestive', true),
  ('K29.7', 'Gastritis, unspecified', 'Digestive', true),
  ('K80.2', 'Gallstone without cholecystitis', 'Digestive', true),
  ('K92.2', 'Haemorrhage of stomach and duodenum', 'Digestive', true),
  ('L03.1', 'Cellulitis of other parts of limb', 'Skin', true),
  ('L89', 'Pressure ulcer', 'Skin', true),
  ('M54.5', 'Low back pain', 'Musculoskeletal', true),
  ('M79.3', 'Periarthritis of shoulder', 'Musculoskeletal', true),
  ('N39.0', 'Urinary tract infection, site not specified', 'Genitourinary', true),
  ('N63', 'Unspecified lump in breast', 'Genitourinary', false),
  ('O80', 'Spontaneous vertex delivery', 'Obstetric', true),
  ('R07.9', 'Chest pain, unspecified', 'Symptoms', true),
  ('R10.9', 'Unspecified abdominal pain', 'Symptoms', true),
  ('R50.9', 'Fever, unspecified', 'Symptoms', true),
  ('R55', 'Syncope and collapse', 'Symptoms', true),
  ('S06.0', 'Concussion', 'Injury', true),
  ('T14.9', 'Injury, unspecified', 'Injury', true),
  ('Z00.0', 'General adult medical examination', 'Factors', true),
  ('Z51.11', 'Encounter for antineoplastic chemotherapy', 'Factors', true),
  ('Z72.0', 'Tobacco use', 'Factors', true);

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table public.form_templates enable row level security;
alter table public.form_templates force row level security;
alter table public.form_responses enable row level security;
alter table public.form_responses force row level security;

-- Reading a template is what scopes the sync bucket. Writing one is authoring
-- a clinical instrument, which is a separate permission from filling one in.
create policy form_templates_select_reader on public.form_templates
  for select to authenticated
  using (nodex.has_permission(tenant_id, 'forms.read'));
create policy form_templates_insert_writer on public.form_templates
  for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'forms.manage'));
create policy form_templates_update_writer on public.form_templates
  for update to authenticated
  using (nodex.has_permission(tenant_id, 'forms.manage'))
  with check (nodex.has_permission(tenant_id, 'forms.manage'));

create policy form_responses_select_reader on public.form_responses
  for select to authenticated
  using (nodex.has_permission(tenant_id, 'forms.read'));
create policy form_responses_insert_writer on public.form_responses
  for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'forms.submit'));

-- ---------------------------------------------------------------------------
-- Permissions
-- ---------------------------------------------------------------------------

-- Reading and filling a form stay available offline: a form is filled at the
-- bedside, in a corridor, in a lift. The response is written locally and
-- uploaded when the device is back in reach of a network.
insert into public.permissions
  (key, display_name, description, module_code, risk_tier, requires_online)
values
  ('forms.read', 'Read clinical forms',
   'View published form templates and the responses recorded against them.',
   'M47', 'standard', false),
  ('forms.manage', 'Author clinical forms',
   'Create, version and publish form templates.',
   'M47', 'standard', false),
  ('forms.submit', 'Fill in clinical forms',
   'Record a response to a clinical form against a patient.',
   'M47', 'standard', false)
on conflict (key) do nothing;

insert into public.role_permissions (role_key, permission_key)
values
  ('hospital_super_admin', 'forms.read'),
  ('hospital_super_admin', 'forms.manage'),
  ('hospital_super_admin', 'forms.submit'),
  ('medical_officer',      'forms.read'),
  ('medical_officer',      'forms.submit'),
  ('nursing_staff',        'forms.read'),
  ('nursing_staff',        'forms.submit'),
  ('pharmacist',           'forms.read'),
  ('pharmacist',           'forms.submit'),
  ('lab_technician',       'forms.read'),
  ('auditor',              'forms.read')
on conflict do nothing;
