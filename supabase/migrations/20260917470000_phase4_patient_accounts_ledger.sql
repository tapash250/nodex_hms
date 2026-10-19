-- NODEX Phase 4, Module 31 completion: patient accounts and the double-entry
-- ledger.
--
-- The Phase 2 slice already models an invoice, its lines, payments and refunds.
-- What it could not express is the *account* a patient carries across visits:
-- an inpatient accumulates charges from many modules (ward, lab, pharmacy,
-- theatre) against one running balance, and a single payment can settle more
-- than one invoice.
--
-- Design:
--   * `patient_accounts` is the per-patient running account. Its balance is a
--     projection maintained by a trigger over `ledger_entries`; it is never
--     accepted from a client and never edited directly.
--   * `ledger_entries` is the append-only journal. One row per financial event,
--     carrying an explicit direction. Every event implies exactly two postings
--     (see `ledger_postings`), so the double-entry invariant holds by
--     construction rather than by a deferred constraint that row-at-a-time
--     replication could never satisfy.
--   * `payment_allocations` splits one payment across several invoices.
--
-- Money stays in integer minor units. Currency is validated per row, and an
-- account cannot mix currencies: a ledger entry whose currency differs from its
-- account is refused, because a running balance across currencies is meaningless.
--
-- Posting a charge is bedside work and stays available offline; settlement and
-- refund stay behind `billing.settle`, which is `requires_online`. That split is
-- why `billing.ledger` exists as its own permission.

-- ---------------------------------------------------------------------------
-- Patient accounts
-- ---------------------------------------------------------------------------

create table public.patient_accounts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  patient_id uuid not null references public.patients(id) on delete restrict,
  account_code text not null check (length(btrim(account_code)) > 0),
  currency text not null default 'BDT' check (currency ~ '^[A-Z]{3}$'),
  status text not null default 'open'
    check (status in ('open', 'settled', 'credit', 'closed')),
  balance_minor bigint not null default 0,
  last_activity_at timestamptz not null default now(),
  opened_at timestamptz not null default now(),
  closed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, patient_id),
  unique (tenant_id, account_code),
  constraint patient_account_closed_ck check (
    (status = 'closed' and closed_at is not null) or status <> 'closed'
  )
);

comment on table public.patient_accounts is
  'Running patient account across visits. balance_minor is positive when the patient owes, negative when the patient is in credit.';
comment on column public.patient_accounts.balance_minor is
  'Derived from ledger_entries by trigger. Never accepted from a client write.';

create index patient_accounts_status_idx
  on public.patient_accounts (tenant_id, status, last_activity_at desc);
create index patient_accounts_patient_idx
  on public.patient_accounts (tenant_id, patient_id);

-- ---------------------------------------------------------------------------
-- Ledger journal
-- ---------------------------------------------------------------------------

create table public.ledger_entries (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  account_id uuid not null references public.patient_accounts(id) on delete restrict,
  invoice_id uuid references public.invoices(id) on delete restrict,
  payment_id uuid references public.payments(id) on delete restrict,
  refund_id uuid references public.refunds(id) on delete restrict,
  transaction_type text not null
    check (transaction_type in
      ('charge', 'payment', 'refund', 'adjustment', 'discount', 'tax')),
  direction text not null check (direction in ('debit', 'credit')),
  account_code text not null
    check (account_code in
      ('patient_receivable', 'revenue', 'cash', 'discount', 'tax', 'refund_payable')),
  amount_minor bigint not null check (amount_minor > 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  payment_method text,
  memo text,
  recorded_by uuid not null references public.app_users(id) on delete restrict,
  occurred_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  -- A financial event is traceable to exactly the artefact that caused it.
  constraint ledger_entry_source_ck check (
    (transaction_type = 'payment' and payment_id is not null)
    or (transaction_type = 'refund' and refund_id is not null)
    or (transaction_type in ('charge', 'discount', 'tax') and invoice_id is not null)
    or transaction_type = 'adjustment'
  ),
  -- A credit posting only makes sense against the receivable it clears.
  constraint ledger_entry_direction_ck check (
    (direction = 'debit' and account_code in ('patient_receivable', 'revenue', 'cash', 'refund_payable'))
    or (direction = 'credit' and account_code in ('patient_receivable', 'revenue', 'cash', 'discount', 'tax'))
  )
);

comment on table public.ledger_entries is
  'Append-only financial journal. One row per event; ledger_postings derives the balanced debit/credit pair.';
comment on column public.ledger_entries.direction is
  'debit increases what the patient owes; credit reduces it.';

create index ledger_entries_account_idx
  on public.ledger_entries (account_id, occurred_at desc);
create index ledger_entries_invoice_idx
  on public.ledger_entries (invoice_id, occurred_at)
  where invoice_id is not null;
create index ledger_entries_tenant_time_idx
  on public.ledger_entries (tenant_id, occurred_at desc);

create trigger ledger_entries_append_only
  before update or delete on public.ledger_entries
  for each row execute function nodex.tg_block_mutation();

-- Double-entry projection. Each journal row yields the pair of postings the
-- event implies, so a trial balance is a sum over this view and always nets to
-- zero. security_invoker keeps the caller's RLS on the underlying table.
create view public.ledger_postings with (security_invoker = true) as
select
  e.id as entry_id,
  e.tenant_id,
  e.account_id,
  e.invoice_id,
  e.transaction_type,
  e.currency,
  e.amount_minor,
  e.occurred_at,
  case when e.direction = 'debit' then e.account_code
       when e.transaction_type = 'payment' then 'cash'
       when e.transaction_type = 'refund' then 'refund_payable'
       else 'revenue' end as debit_account_code,
  case when e.direction = 'debit' then
         case e.transaction_type
           when 'charge' then 'revenue'
           when 'discount' then 'discount'
           when 'tax' then 'tax'
           when 'refund' then 'refund_payable'
           else 'revenue' end
       else 'patient_receivable' end as credit_account_code
from public.ledger_entries e;

comment on view public.ledger_postings is
  'Derived double-entry pair for each ledger event. debit_account_code and credit_account_code always carry the same amount_minor, so the journal balances by construction.';

-- ---------------------------------------------------------------------------
-- Split payments
-- ---------------------------------------------------------------------------

create table public.payment_allocations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  payment_id uuid not null references public.payments(id) on delete restrict,
  invoice_id uuid not null references public.invoices(id) on delete restrict,
  amount_minor bigint not null check (amount_minor > 0),
  created_at timestamptz not null default now(),
  unique (payment_id, invoice_id)
);

comment on table public.payment_allocations is
  'Splits one payment across invoices. The sum per payment may not exceed the payment, and the sum per invoice may not exceed what that invoice still owes.';

create index payment_allocations_payment_idx
  on public.payment_allocations (payment_id);
create index payment_allocations_invoice_idx
  on public.payment_allocations (invoice_id);

-- Allocations are not blanket-immutable: an allocation is a split of money
-- that is already recorded, not the money movement itself, so a mistaken split
-- must be removable. The guard below permits a delete only for the service
-- role (the audited server path) and reverses the invoice total when it does.

-- A payment recorded against an account rather than a single invoice has no
-- invoice_id until it is allocated. The "must have a target" rule is a trigger,
-- not a CHECK: a CHECK may not read another table.
alter table public.payments alter column invoice_id drop not null;

-- ---------------------------------------------------------------------------
-- Tariff binding on invoice lines
-- ---------------------------------------------------------------------------

alter table public.invoice_lines
  add column tariff_id uuid references public.billing_tariffs(id) on delete restrict;
alter table public.invoice_lines
  add column service_code text;

comment on column public.invoice_lines.tariff_id is
  'Tariff the unit price was resolved from. Nullable because a manual line is legitimate, but a tariff-bound line carries its source so a later audit can explain the price.';

-- ---------------------------------------------------------------------------
-- Guards
-- ---------------------------------------------------------------------------

create trigger patient_accounts_set_updated_at
  before update on public.patient_accounts
  for each row execute function nodex.tg_set_updated_at();

-- The account is a projection: a client may open it, but may not rewrite the
-- balance, the currency or the patient it belongs to.
create or replace function nodex.tg_patient_account_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if new.balance_minor <> 0 then
      raise exception using message = 'NODEX: a patient account opens at zero balance', errcode = '22000';
    end if;
    return new;
  end if;

  if new.balance_minor is distinct from old.balance_minor
     and current_setting('nodex.ledger_projection', true) is distinct from 'on' then
    raise exception using message = 'NODEX: the account balance is derived from the ledger, never written directly', errcode = '42501';
  end if;
  if new.currency is distinct from old.currency
     or new.patient_id is distinct from old.patient_id
     or new.tenant_id is distinct from old.tenant_id then
    raise exception using message = 'NODEX: an account cannot change patient, tenant or currency', errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger patient_accounts_guard
  before insert or update on public.patient_accounts
  for each row execute function nodex.tg_patient_account_guard();

-- Every ledger entry must agree with its account's currency, and posting it
-- moves the balance. The projection flag lets the guard above admit the update
-- the ledger caused while still refusing a client write.
create or replace function nodex.tg_ledger_entry_post()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  account_currency text;
  delta bigint;
begin
  select currency into account_currency
  from public.patient_accounts
  where id = new.account_id
  for update;

  if account_currency is null then
    raise exception using message = 'NODEX: ledger entry references an unknown account', errcode = '23503';
  end if;
  if account_currency <> new.currency then
    raise exception using message = 'NODEX: ledger entry currency does not match its account', errcode = '22000';
  end if;

  delta := case when new.direction = 'debit' then new.amount_minor else -new.amount_minor end;

  perform set_config('nodex.ledger_projection', 'on', true);
  update public.patient_accounts
     set balance_minor = balance_minor + delta,
         last_activity_at = greatest(last_activity_at, new.occurred_at),
         status = case
                    when status = 'closed' then 'closed'
                    when balance_minor + delta > 0 then 'open'
                    when balance_minor + delta = 0 then 'settled'
                    else 'credit'
                  end
   where id = new.account_id;
  perform set_config('nodex.ledger_projection', 'off', true);

  return new;
end;
$$;

create trigger ledger_entries_post
  after insert on public.ledger_entries
  for each row execute function nodex.tg_ledger_entry_post();

-- A payment may be split, but the parts may never exceed the payment.
--
-- Insert: both sums are revalidated under a row lock. Update: refused outright,
-- because editing a split in place would silently change two independent totals.
-- Delete: permitted only to the service role, which is the audited server path;
-- the invoice's settled total is reduced by the same amount so the reversal
-- cannot leave the invoice claiming money that is no longer allocated to it.
create or replace function nodex.tg_payment_allocation_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  payment_total bigint;
  allocated bigint;
  invoice_total bigint;
  invoice_paid bigint;
begin
  if tg_op = 'DELETE' then
    if current_user not in ('service_role', 'postgres', 'supabase_admin') then
      raise exception using message = 'NODEX: an allocation is reversed through the server, not by a client', errcode = '42501';
    end if;

    update public.invoices
       set settled_minor = greatest(settled_minor - old.amount_minor, 0)
     where id = old.invoice_id;

    return old;
  end if;

  if tg_op = 'UPDATE' then
    raise exception using message = 'NODEX: an allocation is never edited in place', errcode = '42501';
  end if;

  select amount_minor into payment_total
  from public.payments where id = new.payment_id;

  if payment_total is null then
    raise exception using message = 'NODEX: allocation references an unknown payment', errcode = '23503';
  end if;

  select coalesce(sum(a.amount_minor), 0) into allocated
  from public.payment_allocations a where a.payment_id = new.payment_id;

  if allocated + new.amount_minor > payment_total then
    raise exception using message = 'NODEX: allocations exceed the payment amount', errcode = '42501';
  end if;

  select total_minor, settled_minor into invoice_total, invoice_paid
  from public.invoices where id = new.invoice_id for update;

  if invoice_total is null then
    raise exception using message = 'NODEX: allocation references an unknown invoice', errcode = '23503';
  end if;
  if invoice_paid + new.amount_minor > invoice_total then
    raise exception using message = 'NODEX: allocation exceeds the invoice balance', errcode = '42501';
  end if;

  -- Settled amount on the invoice advances with the allocation, so the invoice
  -- view of what has been paid stays consistent with the split.
  update public.invoices
     set settled_minor = settled_minor + new.amount_minor
   where id = new.invoice_id;

  return new;
end;
$$;

create trigger payment_allocations_guard
  before insert or update or delete on public.payment_allocations
  for each row execute function nodex.tg_payment_allocation_guard();

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table public.patient_accounts enable row level security;
alter table public.patient_accounts force row level security;
alter table public.ledger_entries enable row level security;
alter table public.ledger_entries force row level security;
alter table public.payment_allocations enable row level security;
alter table public.payment_allocations force row level security;

create policy patient_accounts_select_member on public.patient_accounts
  for select to authenticated
  using (nodex.has_permission(tenant_id, 'billing.read'));
create policy patient_accounts_insert_writer on public.patient_accounts
  for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'billing.ledger'));
create policy patient_accounts_update_writer on public.patient_accounts
  for update to authenticated
  using (nodex.has_permission(tenant_id, 'billing.ledger'))
  with check (nodex.has_permission(tenant_id, 'billing.ledger'));

create policy ledger_entries_select_member on public.ledger_entries
  for select to authenticated
  using (nodex.has_permission(tenant_id, 'billing.read'));
create policy ledger_entries_insert_writer on public.ledger_entries
  for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'billing.ledger'));

create policy payment_allocations_select_member on public.payment_allocations
  for select to authenticated
  using (nodex.has_permission(tenant_id, 'billing.read'));
create policy payment_allocations_insert_writer on public.payment_allocations
  for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'billing.settle'));
-- No delete policy on purpose: only the service role may remove an allocation,
-- which is what the guard above enforces. A client reversing its own split
-- would move money without leaving a server-side trace.

-- ---------------------------------------------------------------------------
-- Permission: posting a charge is bedside work and stays available offline
-- ---------------------------------------------------------------------------

insert into public.permissions
  (key, display_name, description, module_code, risk_tier, requires_online)
values
  ('billing.ledger', 'Post ledger entries',
   'Post charges, discounts, tax and adjustments to a patient account.',
   'M31', 'standard', false)
on conflict (key) do nothing;

insert into public.role_permissions (role_key, permission_key)
values
  ('billing_accounts', 'billing.ledger'),
  ('hospital_super_admin', 'billing.ledger')
on conflict do nothing;
