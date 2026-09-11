-- NODEX Phase 2, Module 10: contact and administrative fields on patients.
--
-- The field-level merge policy names per-column mergeable fields, so those
-- columns must exist. Identity columns (mrn, names, date of birth, gender,
-- national_id_hash, blood_group) stay outside the mergeable set by design:
-- changing who a person is, is a human decision, not a merge.

alter table public.patients
  add column email text,
  add column address text,
  add column next_of_kin text,
  add column occupation text,
  add column marital_status text
    check (marital_status is null or marital_status in
      ('single', 'married', 'divorced', 'widowed', 'other', 'unknown')),
  add column preferred_language text;

comment on column public.patients.email is
  'Contact email. Mergeable under the field-level merge policy when edits are disjoint.';
comment on column public.patients.marital_status is
  'Closed vocabulary so merges compare canonical values rather than free text.';
