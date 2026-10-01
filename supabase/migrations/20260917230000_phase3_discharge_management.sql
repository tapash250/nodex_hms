-- NODEX Phase 3, Module 23: Discharge management.
--
-- Extends the discharge record built in Phase 2 with the artifacts the
-- specification requires before a patient may leave: clinical clearance,
-- medication reconciliation, billing settlement and a reviewed AI summary.
--
-- A discharge cannot be finalized until clearance is granted, medication
-- reconciliation is complete and the episode invoice is settled. Clearance
-- cannot be granted while outstanding items remain. A reconciliation cannot
-- complete with no reviewed medications. An AI summary is optional, but once
-- generated it must be reviewed before it counts as the discharge narrative.
--
-- RLS uses membership-derived permissions, and FKs target app_users. Billing
-- settlement deliberately reuses the billing.settle permission rather than
-- minting a discharge-specific financial authority.

create table public.discharge_clearances (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  discharge_id uuid not null references public.discharges(id) on delete restrict,
  reviewed_by uuid not null references public.app_users(id) on delete restrict,
  status text not null default 'pending' check (status in ('pending','cleared')),
  outstanding_items integer not null default 0 check (outstanding_items >= 0),
  notes text,
  cleared_by uuid references public.app_users(id) on delete restrict,
  cleared_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, discharge_id),
  constraint discharge_clearance_cleared_ck check ((status = 'cleared' and cleared_by is not null and cleared_at is not null) or status = 'pending')
);
create index discharge_clearances_discharge_idx on public.discharge_clearances(discharge_id);

create table public.discharge_medication_reconciliations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  discharge_id uuid not null references public.discharges(id) on delete restrict,
  status text not null default 'pending' check (status in ('pending','reconciled')),
  medications_reviewed integer not null default 0 check (medications_reviewed >= 0),
  discrepancies_found integer not null default 0 check (discrepancies_found >= 0),
  reviewed_by uuid references public.app_users(id) on delete restrict,
  reviewed_at timestamptz,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, discharge_id),
  constraint discharge_reconciliation_reviewed_ck check ((status = 'reconciled' and reviewed_by is not null and reviewed_at is not null and medications_reviewed > 0) or status = 'pending')
);
create index discharge_reconciliations_discharge_idx on public.discharge_medication_reconciliations(discharge_id);

create table public.discharge_medication_reconciliation_items (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  reconciliation_id uuid not null references public.discharge_medication_reconciliations(id) on delete restrict,
  medication_name text not null check (length(btrim(medication_name)) > 0),
  action text not null check (action in ('continue','stop','change','hold')),
  discrepancy boolean not null default false,
  detail text,
  recorded_by uuid not null references public.app_users(id) on delete restrict,
  recorded_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index discharge_reconciliation_items_parent_idx on public.discharge_medication_reconciliation_items(reconciliation_id, recorded_at);

create table public.discharge_settlements (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  discharge_id uuid not null references public.discharges(id) on delete restrict,
  invoice_id uuid not null references public.invoices(id) on delete restrict,
  amount_minor bigint not null check (amount_minor >= 0),
  settled_by uuid not null references public.app_users(id) on delete restrict,
  settled_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, discharge_id)
);
create index discharge_settlements_discharge_idx on public.discharge_settlements(discharge_id);

create table public.discharge_ai_summaries (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  discharge_id uuid not null references public.discharges(id) on delete restrict,
  model_id text not null check (length(btrim(model_id)) > 0),
  summary_text text not null check (length(btrim(summary_text)) > 0),
  status text not null default 'pending_review' check (status in ('pending_review','accepted','rejected')),
  safety_decision text not null check (length(btrim(safety_decision)) > 0),
  requested_by uuid not null references public.app_users(id) on delete restrict,
  reviewed_by uuid references public.app_users(id) on delete restrict,
  reviewed_at timestamptz,
  rejection_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, discharge_id),
  constraint discharge_ai_summary_reviewed_ck check ((status in ('accepted','rejected') and reviewed_by is not null and reviewed_at is not null) or status = 'pending_review'),
  constraint discharge_ai_summary_rejected_ck check ((status = 'rejected' and rejection_reason is not null and length(btrim(rejection_reason)) > 0) or status <> 'rejected')
);
create index discharge_ai_summaries_discharge_idx on public.discharge_ai_summaries(discharge_id);

create trigger discharge_clearances_set_updated_at before update on public.discharge_clearances for each row execute function nodex.tg_set_updated_at();
create trigger discharge_reconciliations_set_updated_at before update on public.discharge_medication_reconciliations for each row execute function nodex.tg_set_updated_at();
create trigger discharge_reconciliation_items_set_updated_at before update on public.discharge_medication_reconciliation_items for each row execute function nodex.tg_set_updated_at();
create trigger discharge_settlements_set_updated_at before update on public.discharge_settlements for each row execute function nodex.tg_set_updated_at();
create trigger discharge_ai_summaries_set_updated_at before update on public.discharge_ai_summaries for each row execute function nodex.tg_set_updated_at();

-- Clearance freezes once granted, and a discharge that has been authorized can
-- no longer accrue discharge-management artifacts.
create or replace function nodex.tg_discharge_clearance_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  parent_status text;
begin
  if old.status = 'cleared' and new.status <> old.status then
    raise exception using message = 'NODEX: granted discharge clearance cannot be withdrawn', errcode = '42501';
  end if;
  if new.status = 'cleared' and new.outstanding_items > 0 then
    raise exception using message = 'NODEX: clearance cannot be granted with outstanding items', errcode = '22000';
  end if;
  select status into parent_status from public.discharges where id = new.discharge_id;
  if parent_status in ('finalized','cancelled') then
    raise exception using message = 'NODEX: a closed discharge cannot be cleared', errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger discharge_clearances_guard before update on public.discharge_clearances for each row execute function nodex.tg_discharge_clearance_guard();
create trigger discharge_clearances_parent_guard before insert on public.discharge_clearances for each row execute function nodex.tg_discharge_clearance_guard();

create or replace function nodex.tg_discharge_reconciliation_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  parent_status text;
  item_count integer;
begin
  if old.status = 'reconciled' and new.status <> old.status then
    raise exception using message = 'NODEX: a completed reconciliation cannot be reopened', errcode = '42501';
  end if;
  if new.status = 'reconciled' then
    select count(*) into item_count
      from public.discharge_medication_reconciliation_items
      where reconciliation_id = new.id;
    if item_count = 0 then
      raise exception using message = 'NODEX: reconciliation requires at least one reviewed medication', errcode = '22000';
    end if;
    if new.medications_reviewed <> item_count then
      raise exception using message = 'NODEX: reviewed count must match the recorded medications', errcode = '22000';
    end if;
  end if;
  select status into parent_status from public.discharges where id = new.discharge_id;
  if parent_status in ('finalized','cancelled') then
    raise exception using message = 'NODEX: a closed discharge cannot be reconciled', errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger discharge_reconciliations_guard before update on public.discharge_medication_reconciliations for each row execute function nodex.tg_discharge_reconciliation_guard();
create trigger discharge_reconciliations_parent_guard before insert on public.discharge_medication_reconciliations for each row execute function nodex.tg_discharge_reconciliation_guard();

-- Reconciliation items are part of the reviewed set: once the reconciliation
-- completes, the medication decisions freeze with it.
create or replace function nodex.tg_discharge_reconciliation_items_frozen()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  parent_id uuid;
  parent_status text;
begin
  if tg_op = 'DELETE' then
    parent_id := old.reconciliation_id;
  else
    parent_id := new.reconciliation_id;
  end if;
  select status into parent_status from public.discharge_medication_reconciliations where id = parent_id;
  if parent_status is distinct from 'pending' then
    raise exception using message = 'NODEX: medication decisions freeze once reconciliation completes', errcode = '42501';
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;
create trigger discharge_reconciliation_items_frozen before insert or update or delete on public.discharge_medication_reconciliation_items for each row execute function nodex.tg_discharge_reconciliation_items_frozen();

create or replace function nodex.tg_discharge_settlement_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  parent_status text;
  reconciliation_status text;
begin
  if tg_op <> 'DELETE' then
    select status into parent_status from public.discharges where id = new.discharge_id;
    if parent_status in ('finalized','cancelled') then
      raise exception using message = 'NODEX: a closed discharge cannot be settled', errcode = '42501';
    end if;
    select r.status into reconciliation_status
      from public.discharge_medication_reconciliations r
      where r.discharge_id = new.discharge_id;
    if reconciliation_status is distinct from 'reconciled' then
      raise exception using message = 'NODEX: settle only after medication reconciliation completes', errcode = '42501';
    end if;
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;
create trigger discharge_settlements_guard before insert or update on public.discharge_settlements for each row execute function nodex.tg_discharge_settlement_guard();
create trigger discharge_settlements_append_only_delete before delete on public.discharge_settlements for each row execute function nodex.tg_block_mutation();

-- The AI summary may only be generated for a discharge that has cleared
-- clinical review, and a reviewed summary never rewrites itself.
create or replace function nodex.tg_discharge_ai_summary_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  parent_status text;
  clearance_status text;
begin
  if old.status in ('accepted','rejected') and new.status <> old.status then
    raise exception using message = 'NODEX: a reviewed discharge summary cannot change decision', errcode = '42501';
  end if;
  if old.status in ('accepted','rejected')
    and (new.summary_text is distinct from old.summary_text
      or new.model_id is distinct from old.model_id
      or new.safety_decision is distinct from old.safety_decision) then
    raise exception using message = 'NODEX: a reviewed discharge summary is immutable', errcode = '42501';
  end if;
  if tg_op = 'INSERT' then
    select status into parent_status from public.discharges where id = new.discharge_id;
    if parent_status in ('finalized','cancelled') then
      raise exception using message = 'NODEX: a closed discharge cannot receive a generated summary', errcode = '42501';
    end if;
    select status into clearance_status from public.discharge_clearances where discharge_id = new.discharge_id;
    if clearance_status is distinct from 'cleared' then
      raise exception using message = 'NODEX: generate a summary only after clinical clearance', errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;
create trigger discharge_ai_summaries_guard before insert or update on public.discharge_ai_summaries for each row execute function nodex.tg_discharge_ai_summary_guard();

-- The discharge authorization itself: finalizing now additionally requires the
-- three discharge-management artifacts to be in place. Clearance, medication
-- reconciliation and settlement are what make leaving safe, so the server
-- refuses to authorize a discharge that skips them.
create or replace function nodex.tg_discharge_readiness_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  clearance_status text;
  reconciliation_status text;
  settlement_count integer;
begin
  if new.status = 'finalized' and old.status = 'draft' then
    select status into clearance_status from public.discharge_clearances where discharge_id = new.id;
    if clearance_status is distinct from 'cleared' then
      raise exception using message = 'NODEX: discharge clearance is required before finalizing', errcode = '42501';
    end if;
    select status into reconciliation_status from public.discharge_medication_reconciliations where discharge_id = new.id;
    if reconciliation_status is distinct from 'reconciled' then
      raise exception using message = 'NODEX: medication reconciliation is required before finalizing', errcode = '42501';
    end if;
    select count(*) into settlement_count from public.discharge_settlements where discharge_id = new.id;
    if settlement_count = 0 then
      raise exception using message = 'NODEX: billing settlement is required before finalizing', errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;
create trigger discharges_readiness_guard before update on public.discharges for each row execute function nodex.tg_discharge_readiness_guard();

alter table public.discharge_clearances enable row level security;
alter table public.discharge_clearances force row level security;
alter table public.discharge_medication_reconciliations enable row level security;
alter table public.discharge_medication_reconciliations force row level security;
alter table public.discharge_medication_reconciliation_items enable row level security;
alter table public.discharge_medication_reconciliation_items force row level security;
alter table public.discharge_settlements enable row level security;
alter table public.discharge_settlements force row level security;
alter table public.discharge_ai_summaries enable row level security;
alter table public.discharge_ai_summaries force row level security;

create policy discharge_clearances_select_member on public.discharge_clearances for select to authenticated using (nodex.has_permission(tenant_id,'patient.read'));
create policy discharge_clearances_insert_writer on public.discharge_clearances for insert to authenticated with check (nodex.has_permission(tenant_id,'discharge_clearance.write'));
create policy discharge_clearances_update_writer on public.discharge_clearances for update to authenticated using (nodex.has_permission(tenant_id,'discharge_clearance.write')) with check (nodex.has_permission(tenant_id,'discharge_clearance.write'));
create policy discharge_reconciliations_select_member on public.discharge_medication_reconciliations for select to authenticated using (nodex.has_permission(tenant_id,'patient.read'));
create policy discharge_reconciliations_insert_writer on public.discharge_medication_reconciliations for insert to authenticated with check (nodex.has_permission(tenant_id,'discharge_reconciliation.write'));
create policy discharge_reconciliations_update_writer on public.discharge_medication_reconciliations for update to authenticated using (nodex.has_permission(tenant_id,'discharge_reconciliation.write')) with check (nodex.has_permission(tenant_id,'discharge_reconciliation.write'));
create policy discharge_reconciliation_items_select_member on public.discharge_medication_reconciliation_items for select to authenticated using (nodex.has_permission(tenant_id,'patient.read'));
create policy discharge_reconciliation_items_insert_writer on public.discharge_medication_reconciliation_items for insert to authenticated with check (nodex.has_permission(tenant_id,'discharge_reconciliation.write'));
create policy discharge_reconciliation_items_update_writer on public.discharge_medication_reconciliation_items for update to authenticated using (nodex.has_permission(tenant_id,'discharge_reconciliation.write')) with check (nodex.has_permission(tenant_id,'discharge_reconciliation.write'));
-- Settling the episode bill is a financial action and rides on billing.settle.
create policy discharge_settlements_select_member on public.discharge_settlements for select to authenticated using (nodex.has_permission(tenant_id,'patient.read'));
create policy discharge_settlements_insert_settler on public.discharge_settlements for insert to authenticated with check (nodex.has_permission(tenant_id,'billing.settle'));
create policy discharge_settlements_update_settler on public.discharge_settlements for update to authenticated using (nodex.has_permission(tenant_id,'billing.settle')) with check (nodex.has_permission(tenant_id,'billing.settle'));
-- Accepting machine-authored clinical narrative is reviewer-gated.
create policy discharge_ai_summaries_select_member on public.discharge_ai_summaries for select to authenticated using (nodex.has_permission(tenant_id,'patient.read'));
create policy discharge_ai_summaries_insert_writer on public.discharge_ai_summaries for insert to authenticated with check (nodex.has_permission(tenant_id,'discharge_clearance.write'));
create policy discharge_ai_summaries_update_reviewer on public.discharge_ai_summaries for update to authenticated using (nodex.has_permission(tenant_id,'discharge_summary.review')) with check (nodex.has_permission(tenant_id,'discharge_summary.review'));
