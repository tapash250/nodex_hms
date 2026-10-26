-- Phase 4, storage immutability: clinical media is write-once.
--
-- The Phase 3 storage policies allowed an authenticated member with the
-- module permission to UPDATE an existing clinical object. The clinical
-- contract is supersede-by-new-path: a corrected image, document or signature
-- is a new object at a new path, never a rewrite of the prior fact. The client
-- already uploads with INSERT only, so dropping the UPDATE policies closes the
-- write-side residual without changing the read boundary.
--
-- No delete policy was granted in Phase 3; this migration does not add one.

drop policy if exists clinical_images_update on storage.objects;
drop policy if exists clinical_documents_update on storage.objects;
drop policy if exists clinical_signatures_update on storage.objects;
