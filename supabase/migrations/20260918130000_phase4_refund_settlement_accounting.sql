-- Phase 4, refund settlement accounting: invoices.settled_minor is net
-- collections, not gross settlement.
--
-- A refund is a financial event, not a rewrite. It arrives through the
-- append-only refunds table and reduces the invoice's settled amount. The
-- projection is marked explicitly so the settled-invoice immutability guard
-- can tell a refund-driven projection from any other attempted update.

alter table public.invoices
  drop constraint invoice_settled_ck;

alter table public.invoices
  add constraint invoice_settled_ck check (
    (status <> 'settled') OR (settled_at IS NOT NULL AND settled_minor >= 0)
  );

create or replace function nodex.tg_invoice_transition_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.status in ('settled','cancelled') and new.status <> old.status then
    raise exception using message = 'NODEX: closed invoices cannot transition', errcode = '42501';
  end if;
  if new.status <> old.status and new.status = 'issued' and old.status = 'draft' and new.issued_at is null then
    raise exception using message = 'NODEX: issuing an invoice requires a timestamp', errcode = '22000';
  end if;
  if new.status <> old.status and new.status = 'settled' and (new.settled_minor < new.total_minor or new.settled_at is null) then
    raise exception using message = 'NODEX: settling an invoice requires full payment', errcode = '22000';
  end if;
  if new.status = 'cancelled' and (new.closed_at is null or new.closure_reason is null) then
    raise exception using message = 'NODEX: cancelling an invoice requires timestamp and reason', errcode = '22000';
  end if;
  if new.status <> old.status and new.status = 'settled' and auth.uid() is not null and not nodex.has_permission(new.tenant_id, 'billing.settle') then
    raise exception using message = 'NODEX: invoice settlement requires billing.settle', errcode = '42501';
  end if;
  if old.status = 'settled' then
    if new.total_minor is distinct from old.total_minor
      or new.settled_minor is distinct from old.settled_minor
      or new.currency is distinct from old.currency
      or new.issued_at is distinct from old.issued_at
      or new.settled_at is distinct from old.settled_at
      or new.patient_id is distinct from old.patient_id
    then
      if current_setting('nodex.refund_projection', true) <> 'on' then
        raise exception using message = 'NODEX: settled invoices are immutable', errcode = '42501';
      end if;
    end if;
  end if;
  return new;
end;
$$;

create or replace function nodex.tg_refund_reduce_settled()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform set_config('nodex.refund_projection', 'on', true);
  update public.invoices
     set settled_minor = greatest(settled_minor - new.amount_minor, 0)
   where id = new.invoice_id;
  perform set_config('nodex.refund_projection', 'off', true);
  return new;
end;
$$;

create trigger refunds_reduce_settled
  after insert on public.refunds
  for each row execute function nodex.tg_refund_reduce_settled();
