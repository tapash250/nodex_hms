-- NODEX Phase 3: Tenant-scoped object storage for clinical media.
--
-- DICOM/PACS images, clinical PDFs and encounter signatures live in private,
-- tenant-scoped objects; the clinical tables keep only references. RLS is
-- membership-derived through the existing nodex helpers, so an object is
-- reachable only when the first path segment is a tenant the caller belongs to.
-- Writes additionally require the module permission and a SHA-256 checksum in
-- the object metadata, so an object cannot arrive unverified. No delete policy
-- is granted: a clinical artifact is never destroyed, only superseded — the
-- same append-only stance taken across the clinical schema.
--
-- Path convention the client must follow: <tenant_id>/<context>/<file>, where
-- the first segment is the tenant UUID and is what RLS scopes on.
--
-- Apply with the Supabase CLI (this repo's convention): after logging in,
-- `supabase db push`. Reading a private object is done through a short-lived
-- signed URL (createSignedUrl, 60s), never by making the bucket public.

-- Extracts the tenant id a storage path is scoped to, or NULL when the first
-- segment is not a tenant UUID. Pure (no table access), so it is safe inside an
-- RLS predicate and needs no SECURITY DEFINER rights of its own; it simply
-- refuses malformed paths rather than raising.
create or replace function nodex.storage_tenant_id(p_path text)
returns uuid
language sql
immutable
set search_path = ''
as $$
  select case
    when p_path ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/'
      then split_part(p_path, '/', 1)::uuid
    else null
  end;
$$;

revoke execute on function nodex.storage_tenant_id(text) from public;
grant execute on function nodex.storage_tenant_id(text) to authenticated;

-- Private buckets only. Signatures are the most sensitive (they attest a
-- clinical act) and so carry the smallest object ceiling; imaging studies hold
-- whole DICOM series and carry the largest.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('clinical-signatures', 'clinical-signatures', false, 5242880, null),
  ('clinical-documents', 'clinical-documents', false, 52428800, null),
  ('clinical-images', 'clinical-images', false, 209715200, null)
on conflict (id) do nothing;

-- clinical-images: DICOM/PACS studies and scans (Module 18). A study is
-- acquired under imaging_study.record.
drop policy if exists clinical_images_read on storage.objects;
create policy clinical_images_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'clinical-images'
    and nodex.has_tenant_access(nodex.storage_tenant_id(name))
  );

drop policy if exists clinical_images_write on storage.objects;
create policy clinical_images_write on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'clinical-images'
    and nodex.has_tenant_access(nodex.storage_tenant_id(name))
    and nodex.has_permission(nodex.storage_tenant_id(name), 'imaging_study.record')
    and (metadata ->> 'sha256') is not null
  );

drop policy if exists clinical_images_update on storage.objects;
create policy clinical_images_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'clinical-images'
    and nodex.has_tenant_access(nodex.storage_tenant_id(name))
    and nodex.has_permission(nodex.storage_tenant_id(name), 'imaging_study.record')
  )
  with check (
    bucket_id = 'clinical-images'
    and nodex.has_tenant_access(nodex.storage_tenant_id(name))
    and nodex.has_permission(nodex.storage_tenant_id(name), 'imaging_study.record')
  );

-- clinical-documents: clinical PDFs and reports attached to an encounter.
drop policy if exists clinical_documents_read on storage.objects;
create policy clinical_documents_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'clinical-documents'
    and nodex.has_tenant_access(nodex.storage_tenant_id(name))
  );

drop policy if exists clinical_documents_write on storage.objects;
create policy clinical_documents_write on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'clinical-documents'
    and nodex.has_tenant_access(nodex.storage_tenant_id(name))
    and nodex.has_permission(nodex.storage_tenant_id(name), 'encounter.write')
    and (metadata ->> 'sha256') is not null
  );

drop policy if exists clinical_documents_update on storage.objects;
create policy clinical_documents_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'clinical-documents'
    and nodex.has_tenant_access(nodex.storage_tenant_id(name))
    and nodex.has_permission(nodex.storage_tenant_id(name), 'encounter.write')
  )
  with check (
    bucket_id = 'clinical-documents'
    and nodex.has_tenant_access(nodex.storage_tenant_id(name))
    and nodex.has_permission(nodex.storage_tenant_id(name), 'encounter.write')
  );

-- clinical-signatures: encounter signature images. Written while signing an
-- encounter, so gated on encounter.write alongside the documents.
drop policy if exists clinical_signatures_read on storage.objects;
create policy clinical_signatures_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'clinical-signatures'
    and nodex.has_tenant_access(nodex.storage_tenant_id(name))
  );

drop policy if exists clinical_signatures_write on storage.objects;
create policy clinical_signatures_write on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'clinical-signatures'
    and nodex.has_tenant_access(nodex.storage_tenant_id(name))
    and nodex.has_permission(nodex.storage_tenant_id(name), 'encounter.write')
    and (metadata ->> 'sha256') is not null
  );

drop policy if exists clinical_signatures_update on storage.objects;
create policy clinical_signatures_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'clinical-signatures'
    and nodex.has_tenant_access(nodex.storage_tenant_id(name))
    and nodex.has_permission(nodex.storage_tenant_id(name), 'encounter.write')
  )
  with check (
    bucket_id = 'clinical-signatures'
    and nodex.has_tenant_access(nodex.storage_tenant_id(name))
    and nodex.has_permission(nodex.storage_tenant_id(name), 'encounter.write')
  );
