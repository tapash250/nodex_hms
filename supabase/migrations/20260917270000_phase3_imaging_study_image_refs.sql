-- NODEX Phase 3: object-storage references on imaging studies.
--
-- DICOM/PACS images live in the private clinical-images bucket (see
-- 20260917260000_phase3_storage_buckets.sql); the study row carries only the
-- references needed to resolve them. A reference records the full object path
-- (tenant-prefixed, matching storage's own scoping) and the SHA-256 the
-- uploader computed, so a reader can verify what it fetched against what was
-- recorded at acquisition time.
--
-- The column is text holding JSON, not jsonb: the local PowerSync projection
-- stores JSON columns as TEXT for stable round-tripping, and the
-- mutation-handler's json validator decodes it back. Storing it as text here
-- keeps the local projection, this validator and PostgreSQL in agreement —
-- a type disagreement between them drops the column from replication silently.
--
-- Separately: delete is already refused (no storage delete policy), and the
-- study row is append-only once reported, so an image reference cannot be
-- pointed at a replacement object after the fact.

alter table public.imaging_studies
  add column if not exists image_refs text;

comment on column public.imaging_studies.image_refs is
  'JSON array of {path, sha256} for images in the clinical-images bucket. Text rather than jsonb to match the local projection.';
