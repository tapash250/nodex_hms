-- NODEX Phase 4, Module 33: Documents & Biometric E-Consent Vault.
--
-- Specification scope: "Procedure and surgical consent forms, high-resolution
-- stylus signature capture, biometric thumbprint capture, and PDF vault."
-- Security: "Generated documents are cryptographically signed, hashed
-- (SHA-256), and stored in tenant-isolated encrypted storage buckets."
--
-- This is the documentary estate: the moment a patient agrees to a procedure,
-- and the artefact that proves it. It is distinct from the clinical record it
-- attests (Module 07 encounters hold the treatment; a consent authorises it) and
-- from the object storage that holds the bytes (Phase 3 buckets; this module
-- owns the index and the permissions under which those bytes may be written).
--
-- Three tables, matching the scope:
--
--   * `consent_templates` is the governed catalogue of consent text. A template
--     version is immutable once written — the words a patient signed must never
--     change under it — so a correction is a new version, not an edit, and a
--     retired version is deactivated and retained rather than deleted.
--   * `consent_records` is the patient's decision: which template they were
--     shown, what procedure it covers, the stylus signature digest, the
--     biometric attestation if one was captured, the witness, and the vaulted
--     artefact that carries the signature. It is a guarded state machine
--     `drafted → awaiting_signature → signed`, declined from either live stage,
--     and `signed → revoked` one-way. A signed consent accepts no change other
--     than a revocation, because what it attests is the record of an act.
--   * `document_vault_documents` is the index of the vault: for each artefact
--     its bucket, path, MIME type, byte size, SHA-256 digest, detached signature
--     when the platform signer supplies one, and its lifecycle
--     `issued → superseded | voided`. Both endings are one-way: a superseded
--     document names its replacement, a voided one says why.
--
-- Two facts are derived rather than stored, because a stored copy drifts from
-- the fact it summarises: the validity of a consent (pending, awaiting
-- signature, signed, expired, declined or revoked) from its status and its
-- expiry, and what is still missing before a consent may be signed (signature,
-- biometric, witness, vaulted artefact) from the template's requirements and the
-- attestations captured so far.
--
-- The SHA-256 digest is mandatory on every vaulted document, and the storage
-- bucket policies require the same digest in the object metadata, so an
-- artefact cannot be indexed without the hash that makes tampering detectable.
-- The detached signature is optional: it is recorded when a platform signer
-- supplies one, and the triple (signature, algorithm, key id) is validated
-- together or not at all. NODEX does not fabricate a signature it cannot verify.
--
-- The four permissions are granted explicitly because the Phase 1
-- all-permissions seed predates these keys. Capturing a consent and indexing the
-- vault are separated (as Module 29 separates maintenance from the registry), so
-- a ward nurse can take a signature at the bedside without being able to
-- register or retire what the vault holds, and reading is separated from both
-- because an auditor reads the documentary estate without writing to it.

create table public.consent_templates (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  code text not null check (length(btrim(code)) > 0),
  title text not null check (length(btrim(title)) > 0),
  procedure_category text
    check (procedure_category is null or length(btrim(procedure_category)) > 0),
  body_text text not null check (length(btrim(body_text)) > 0),
  version integer not null default 1 check (version >= 1),
  requires_witness boolean not null default false,
  requires_biometric boolean not null default false,
  validity_days integer check (validity_days is null or validity_days > 0),
  is_active boolean not null default true,
  created_by uuid not null references public.app_users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, code, version)
);
create index consent_templates_code_idx
  on public.consent_templates(tenant_id, code, is_active);
create index consent_templates_active_idx
  on public.consent_templates(tenant_id, is_active);

create trigger consent_templates_set_updated_at before update on public.consent_templates
  for each row execute function nodex.tg_set_updated_at();
-- A version is retired, never deleted: a signed consent names it.
create trigger consent_templates_retain before delete on public.consent_templates
  for each row execute function nodex.tg_block_mutation();

-- Only activation changes: the words a patient signed must stay exactly as they
-- were when the signature was taken, so a correction is a new version.
create or replace function nodex.tg_consent_template_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.tenant_id is distinct from old.tenant_id
    or new.code is distinct from old.code
    or new.title is distinct from old.title
    or new.procedure_category is distinct from old.procedure_category
    or new.body_text is distinct from old.body_text
    or new.version is distinct from old.version
    or new.requires_witness is distinct from old.requires_witness
    or new.requires_biometric is distinct from old.requires_biometric
    or new.validity_days is distinct from old.validity_days then
    raise exception using
      message = 'NODEX: a consent template version is immutable',
      errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger consent_templates_guard
  before update on public.consent_templates
  for each row execute function nodex.tg_consent_template_guard();

-- The index of the vault. Created before the consent record so the record can
-- reference the artefact that carries the signature; the reverse reference is
-- added below.
create table public.document_vault_documents (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  patient_id uuid references public.patients(id) on delete restrict,
  encounter_id uuid references public.clinical_encounters(id) on delete set null,
  consent_id uuid,
  kind text not null
    check (kind in ('consent_form','consent_signature','report','other')),
  title text not null check (length(btrim(title)) > 0),
  bucket text not null check (length(btrim(bucket)) > 0),
  object_path text not null check (length(btrim(object_path)) > 0),
  mime_type text not null check (length(btrim(mime_type)) > 0),
  size_bytes bigint not null check (size_bytes >= 0),
  sha256 text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  signature text check (signature is null or length(btrim(signature)) > 0),
  signature_algorithm text not null default 'none'
    check (signature_algorithm in ('none','hmac_sha256','ed25519','rsa_pss_sha256')),
  signing_key_id text
    check (signing_key_id is null or length(btrim(signing_key_id)) > 0),
  status text not null default 'issued'
    check (status in ('issued','superseded','voided')),
  issued_by uuid not null references public.app_users(id) on delete restrict,
  issued_at timestamptz not null default now(),
  superseded_at timestamptz,
  superseded_by uuid references public.document_vault_documents(id) on delete set null,
  voided_at timestamptz,
  void_reason text check (void_reason is null or length(btrim(void_reason)) > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- One artefact per object path: a path is a location, not a version.
  unique (tenant_id, object_path),
  -- A detached signature is recorded as a coherent triple or not at all.
  constraint vault_signature_ck check (
    (signature is null and signing_key_id is null and signature_algorithm = 'none')
    or (signature is not null and signing_key_id is not null
        and signature_algorithm <> 'none')
  ),
  constraint vault_superseded_ck check (
    status <> 'superseded'
    or (superseded_at is not null and superseded_by is not null
        and superseded_by <> id)
  ),
  constraint vault_voided_ck check (
    status <> 'voided'
    or (voided_at is not null and void_reason is not null
        and length(btrim(void_reason)) > 0)
  )
);
create index document_vault_tenant_idx
  on public.document_vault_documents(tenant_id, status, issued_at desc);
create index document_vault_patient_idx
  on public.document_vault_documents(tenant_id, patient_id, issued_at desc);
create index document_vault_consent_idx
  on public.document_vault_documents(tenant_id, consent_id);

create trigger document_vault_set_updated_at before update on public.document_vault_documents
  for each row execute function nodex.tg_set_updated_at();
create trigger document_vault_retain before delete on public.document_vault_documents
  for each row execute function nodex.tg_block_mutation();

-- The digest is the anchor: a document's content address must not move, and its
-- lifecycle has two one-way endings.
create or replace function nodex.tg_document_vault_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.tenant_id is distinct from old.tenant_id
    or new.bucket is distinct from old.bucket
    or new.object_path is distinct from old.object_path
    or new.sha256 is distinct from old.sha256
    or new.size_bytes is distinct from old.size_bytes
    or new.mime_type is distinct from old.mime_type then
    raise exception using
      message = 'NODEX: a vaulted document address and digest are immutable',
      errcode = '42501';
  end if;
  if old.status <> 'issued' then
    raise exception using
      message = 'NODEX: a retired vault document is immutable',
      errcode = '42501';
  end if;
  if new.status = old.status then
    return new;
  end if;
  if new.status in ('superseded','voided') then
    return new;
  end if;
  raise exception using
    message = 'NODEX: a vault document is superseded, voided or left alone',
    errcode = '42501';
end;
$$;
create trigger document_vault_guard
  before update on public.document_vault_documents
  for each row execute function nodex.tg_document_vault_guard();

-- The patient's decision. Verification of what was captured is a fact on the
-- row (the digests and the times), not a second copy of the artefact.
create table public.consent_records (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  patient_id uuid not null references public.patients(id) on delete restrict,
  facility_id uuid not null references public.facilities(id) on delete restrict,
  encounter_id uuid references public.clinical_encounters(id) on delete set null,
  template_id uuid not null references public.consent_templates(id) on delete restrict,
  procedure_text text not null check (length(btrim(procedure_text)) > 0),
  status text not null default 'drafted'
    check (status in ('drafted','awaiting_signature','signed','declined','revoked')),
  signer_name text check (signer_name is null or length(btrim(signer_name)) > 0),
  signer_relationship text
    check (signer_relationship is null
           or signer_relationship in ('patient','guardian','relative','other')),
  signature_sha256 text
    check (signature_sha256 is null or signature_sha256 ~ '^[0-9a-f]{64}$'),
  signature_point_count integer not null default 0
    check (signature_point_count >= 0),
  signature_captured_at timestamptz,
  biometric_method text not null default 'none'
    check (biometric_method in ('none','thumbprint','fingerprint_sensor','face')),
  biometric_template_sha256 text
    check (biometric_template_sha256 is null
           or biometric_template_sha256 ~ '^[0-9a-f]{64}$'),
  biometric_captured_at timestamptz,
  biometric_quality integer
    check (biometric_quality is null or biometric_quality between 0 and 100),
  witnessed_by uuid references public.app_users(id) on delete set null,
  witnessed_at timestamptz,
  document_id uuid,
  signed_at timestamptz,
  expires_at timestamptz,
  declined_at timestamptz,
  decline_reason text check (decline_reason is null or length(btrim(decline_reason)) > 0),
  revoked_at timestamptz,
  revocation_reason text
    check (revocation_reason is null or length(btrim(revocation_reason)) > 0),
  created_by uuid not null references public.app_users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- A signed consent names who signed, how they signed and which artefact
  -- carries the signature; without all four there is no signature.
  constraint consent_signed_ck check (
    status <> 'signed'
    or (signer_name is not null and signer_relationship is not null
        and signature_sha256 is not null and signed_at is not null
        and document_id is not null)
  ),
  constraint consent_declined_ck check (
    status <> 'declined'
    or (declined_at is not null and decline_reason is not null
        and length(btrim(decline_reason)) > 0)
  ),
  constraint consent_revoked_ck check (
    status <> 'revoked'
    or (revoked_at is not null and revocation_reason is not null
        and length(btrim(revocation_reason)) > 0)
  ),
  -- A biometric attestation is a method, a digest and a time, together.
  constraint consent_biometric_ck check (
    (biometric_method = 'none' and biometric_template_sha256 is null
     and biometric_captured_at is null)
    or (biometric_method <> 'none' and biometric_template_sha256 is not null
        and biometric_captured_at is not null)
  ),
  -- A witness is a person and a moment, or neither.
  constraint consent_witness_ck check (
    (witnessed_by is null and witnessed_at is null)
    or (witnessed_by is not null and witnessed_at is not null)
  ),
  -- Only a signed consent carries a signature; a live one may be prepared.
  constraint consent_unsigned_ck check (
    status in ('drafted','awaiting_signature') or signature_sha256 is not null
  )
);
create index consent_records_patient_idx
  on public.consent_records(tenant_id, patient_id, created_at desc);
create index consent_records_status_idx
  on public.consent_records(tenant_id, status, created_at desc);
create index consent_records_template_idx
  on public.consent_records(tenant_id, template_id);

alter table public.document_vault_documents
  add constraint document_vault_consent_fk
  foreign key (consent_id) references public.consent_records(id)
  on delete set null;

alter table public.consent_records
  add constraint consent_document_fk
  foreign key (document_id) references public.document_vault_documents(id)
  on delete set null;

create trigger consent_records_set_updated_at before update on public.consent_records
  for each row execute function nodex.tg_set_updated_at();
create trigger consent_records_retain before delete on public.consent_records
  for each row execute function nodex.tg_block_mutation();

-- One stage at a time; declined from either live stage; a signed consent accepts
-- nothing but a revocation, and a closed one accepts nothing at all.
create or replace function nodex.tg_consent_record_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status in ('declined','revoked') then
    raise exception using
      message = 'NODEX: a closed consent record is immutable',
      errcode = '42501';
  end if;
  if old.status = 'signed' then
    if new.status <> 'revoked' then
      raise exception using
        message = 'NODEX: a signed consent is revoked or left alone',
        errcode = '42501';
    end if;
    if new.signer_name is distinct from old.signer_name
      or new.signer_relationship is distinct from old.signer_relationship
      or new.signature_sha256 is distinct from old.signature_sha256
      or new.signature_captured_at is distinct from old.signature_captured_at
      or new.document_id is distinct from old.document_id
      or new.signed_at is distinct from old.signed_at
      or new.template_id is distinct from old.template_id
      or new.procedure_text is distinct from old.procedure_text then
      raise exception using
        message = 'NODEX: what a signed consent attests is immutable',
        errcode = '42501';
    end if;
    return new;
  end if;
  if new.status = old.status then
    return new;
  end if;
  if (old.status = 'drafted'
      and new.status in ('awaiting_signature','signed','declined'))
    or (old.status = 'awaiting_signature'
        and new.status in ('signed','declined')) then
    return new;
  end if;
  raise exception using
    message = 'NODEX: a consent record may not skip a stage',
    errcode = '42501';
end;
$$;
create trigger consent_records_guard
  before update on public.consent_records
  for each row execute function nodex.tg_consent_record_guard();

alter table public.consent_templates enable row level security;
alter table public.consent_templates force row level security;
alter table public.document_vault_documents enable row level security;
alter table public.document_vault_documents force row level security;
alter table public.consent_records enable row level security;
alter table public.consent_records force row level security;

create policy consent_templates_select_member on public.consent_templates for select to authenticated
  using (nodex.has_permission(tenant_id, 'documents.read'));
create policy consent_templates_insert_manager on public.consent_templates for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'documents.manage'));
create policy consent_templates_update_manager on public.consent_templates for update to authenticated
  using (nodex.has_permission(tenant_id, 'documents.manage'))
  with check (nodex.has_permission(tenant_id, 'documents.manage'));

create policy consent_records_select_member on public.consent_records for select to authenticated
  using (nodex.has_permission(tenant_id, 'documents.read'));
create policy consent_records_insert_capturer on public.consent_records for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'documents.consent'));
create policy consent_records_update_capturer on public.consent_records for update to authenticated
  using (nodex.has_permission(tenant_id, 'documents.consent'))
  with check (nodex.has_permission(tenant_id, 'documents.consent'));

create policy document_vault_select_member on public.document_vault_documents for select to authenticated
  using (nodex.has_permission(tenant_id, 'documents.read'));
create policy document_vault_insert_issuer on public.document_vault_documents for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'documents.vault'));
create policy document_vault_update_issuer on public.document_vault_documents for update to authenticated
  using (nodex.has_permission(tenant_id, 'documents.vault'))
  with check (nodex.has_permission(tenant_id, 'documents.vault'));

-- The bytes behind a consent. The Phase 3 signature and document buckets already
-- gate writes on encounter.write; these additional permissive policies let a
-- consent capture be written under documents.consent instead, so the ward that
-- takes a bedside signature does not need the encounter write tier to store it.
-- The SHA-256 metadata requirement is repeated, so a consent artefact cannot
-- arrive unhashed either.
drop policy if exists clinical_signatures_write_consent on storage.objects;
create policy clinical_signatures_write_consent on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'clinical-signatures'
    and nodex.has_tenant_access(nodex.storage_tenant_id(name))
    and nodex.has_permission(nodex.storage_tenant_id(name), 'documents.consent')
    and (metadata ->> 'sha256') is not null
  );

drop policy if exists clinical_signatures_update_consent on storage.objects;
create policy clinical_signatures_update_consent on storage.objects
  for update to authenticated
  using (
    bucket_id = 'clinical-signatures'
    and nodex.has_tenant_access(nodex.storage_tenant_id(name))
    and nodex.has_permission(nodex.storage_tenant_id(name), 'documents.consent')
  )
  with check (
    bucket_id = 'clinical-signatures'
    and nodex.has_tenant_access(nodex.storage_tenant_id(name))
    and nodex.has_permission(nodex.storage_tenant_id(name), 'documents.consent')
  );

drop policy if exists clinical_documents_write_consent on storage.objects;
create policy clinical_documents_write_consent on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'clinical-documents'
    and nodex.has_tenant_access(nodex.storage_tenant_id(name))
    and nodex.has_permission(nodex.storage_tenant_id(name), 'documents.consent')
    and (metadata ->> 'sha256') is not null
  );

drop policy if exists clinical_documents_update_consent on storage.objects;
create policy clinical_documents_update_consent on storage.objects
  for update to authenticated
  using (
    bucket_id = 'clinical-documents'
    and nodex.has_tenant_access(nodex.storage_tenant_id(name))
    and nodex.has_permission(nodex.storage_tenant_id(name), 'documents.consent')
  )
  with check (
    bucket_id = 'clinical-documents'
    and nodex.has_tenant_access(nodex.storage_tenant_id(name))
    and nodex.has_permission(nodex.storage_tenant_id(name), 'documents.consent')
  );

insert into public.permissions (key, display_name, description, module_code, risk_tier, requires_online)
values
  ('documents.read',    'Read consent and vault records', 'View consent templates, consent records and the document vault index.', 'M33', 'standard', false),
  ('documents.consent', 'Capture patient consent',        'Raise consent records, capture stylus and biometric attestations, sign, decline and revoke.', 'M33', 'elevated', false),
  ('documents.vault',   'Index the document vault',       'Register vaulted artefacts, and supersede or void them.', 'M33', 'elevated', false),
  ('documents.manage',  'Manage consent templates',       'Publish consent template versions and activate or retire them.', 'M33', 'elevated', false)
on conflict (key) do nothing;

insert into public.role_permissions (role_key, permission_key)
values
  ('hospital_super_admin', 'documents.read'),
  ('hospital_super_admin', 'documents.consent'),
  ('hospital_super_admin', 'documents.vault'),
  ('hospital_super_admin', 'documents.manage'),
  ('medical_officer',      'documents.read'),
  ('medical_officer',      'documents.consent'),
  ('medical_officer',      'documents.vault'),
  ('nursing_staff',        'documents.read'),
  ('nursing_staff',        'documents.consent'),
  ('auditor',              'documents.read')
on conflict do nothing;
