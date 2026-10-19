-- NODEX Phase 4: close append-only gaps found in the schema audit.
--
-- Four tables were registered as append-only (or as event ledgers) in the
-- client conflict registry, and carried an UPDATE policy, but had no database
-- guard. A client bug or a direct PostgREST call could therefore rewrite a
-- recorded clinical fact. The database is the authoritative boundary, so the
-- guard belongs here rather than in the client.
--
-- Tables and why each is append-only:
--   * icu_vitals            - a timestamped observation is a fact, not a draft.
--   * icu_nursing_handover  - a handover is a signed transfer of responsibility.
--   * stock_movements       - a movement is a ledger entry; corrections are new
--                             movements, never edits to the original.
--   * ventilator_events     - device event log; a correction is a new event.
--
-- Correction path: insert a new row that supersedes the original. Nothing in
-- this migration removes the existing UPDATE policies; the trigger refuses the
-- write before RLS would have admitted it, which keeps the error legible
-- (42501, append-only violation) instead of a silent zero-row update.

create trigger icu_vitals_append_only
  before update or delete on public.icu_vitals
  for each row execute function nodex.tg_block_mutation();

create trigger icu_nursing_handover_append_only
  before update or delete on public.icu_nursing_handover
  for each row execute function nodex.tg_block_mutation();

create trigger stock_movements_append_only
  before update or delete on public.stock_movements
  for each row execute function nodex.tg_block_mutation();

create trigger ventilator_events_append_only
  before update or delete on public.ventilator_events
  for each row execute function nodex.tg_block_mutation();

comment on trigger icu_vitals_append_only on public.icu_vitals is
  'ICU observations are facts. A correction is a new observation with its own timestamp.';
comment on trigger icu_nursing_handover_append_only on public.icu_nursing_handover is
  'A handover records who accepted responsibility. Rewriting it would erase that acceptance.';
comment on trigger stock_movements_append_only on public.stock_movements is
  'Stock movements are ledger entries. A reversal is a new movement, never an edit.';
comment on trigger ventilator_events_append_only on public.ventilator_events is
  'Ventilator events are a device log. A correction is a new event.';
