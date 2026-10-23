-- Clinical object storage: reads require a clinical permission, not merely a
-- membership.
--
-- The Phase 3 policies gated every SELECT on has_tenant_access() alone. That
-- is the tenancy boundary, not the clinical one: a member with no clinical
-- permission — a portal patient, a payroll clerk — could list and download
-- every DICOM series, clinical PDF and signed encounter image in the tenant.
-- The bucket name is the only thing a caller must know, and the client already
-- knows it.
--
-- Writes already required a module permission; reads were the gap. Each read
-- now names the permission that the corresponding clinical surface uses:
--
--   clinical-images      imaging_order.write or imaging_report.verify
--   clinical-documents   encounter.read
--   clinical-signatures  encounter.read
--
-- A portal account deliberately holds none of these. Its own record reaches
-- it through the patient_portal replication bucket, which selects by link.

drop policy if exists clinical_images_read on storage.objects;
create policy clinical_images_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'clinical-images'
    and nodex.has_tenant_access(nodex.storage_tenant_id(name))
    and (
      nodex.has_permission(nodex.storage_tenant_id(name), 'imaging_order.write')
      or nodex.has_permission(nodex.storage_tenant_id(name), 'imaging_report.verify')
    )
  );

drop policy if exists clinical_documents_read on storage.objects;
create policy clinical_documents_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'clinical-documents'
    and nodex.has_tenant_access(nodex.storage_tenant_id(name))
    and nodex.has_permission(nodex.storage_tenant_id(name), 'encounter.read')
  );

drop policy if exists clinical_signatures_read on storage.objects;
create policy clinical_signatures_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'clinical-signatures'
    and nodex.has_tenant_access(nodex.storage_tenant_id(name))
    and nodex.has_permission(nodex.storage_tenant_id(name), 'encounter.read')
  );
