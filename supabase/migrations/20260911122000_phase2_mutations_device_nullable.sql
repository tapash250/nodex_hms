-- NODEX Phase 2: the upload path may not know the device id.
--
-- The mutation-handler Edge Function identifies a mutation by (tenant_id,
-- idempotency_key) plus actor; the originating device is informative, not
-- identity. The Flutter connector submits batches without a device binding
-- (it is constructed before the device identity resolves), so a NOT NULL
-- device_id would reject every ledger insert. Nullable with a comment beats a
-- placeholder UUID that would lie about provenance.

alter table public.mutations alter column device_id drop not null;

comment on column public.mutations.device_id is
  'Originating device when known. Null when the upload path submits without a device binding; identity rests on (tenant_id, idempotency_key) plus actor.';
