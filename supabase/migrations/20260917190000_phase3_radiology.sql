-- NODEX Phase 3, Module 18: Radiology & PACS Imaging (RIS).
--
-- Order -> study acquisition -> draft report -> verified report. A verified
-- report is immutable; DICOM/PACS identifiers travel as metadata references
-- only, with images themselves in encrypted object storage. RLS uses
-- membership-derived permissions, and FKs target app_users.

create table public.imaging_orders (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  patient_id uuid not null references public.patients(id) on delete restrict,
  encounter_id uuid references public.clinical_encounters(id) on delete restrict,
  ordered_by uuid not null references public.app_users(id) on delete restrict,
  order_code text not null check (length(btrim(order_code)) > 0),
  modality text not null check (modality in ('xray','ct','mri','ultrasound')),
  body_region text not null check (length(btrim(body_region)) > 0),
  priority text not null default 'routine' check (priority in ('routine','urgent','stat')),
  status text not null default 'ordered' check (status in ('ordered','completed','cancelled')),
  clinical_indication text,
  ordered_at timestamptz not null default now(),
  cancelled_at timestamptz,
  cancelled_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, order_code),
  constraint imaging_order_cancel_ck check ((status = 'cancelled' and cancelled_at is not null and cancelled_reason is not null) or status <> 'cancelled')
);
create index imaging_orders_patient_idx on public.imaging_orders(tenant_id, patient_id, ordered_at desc);
create index imaging_orders_status_idx on public.imaging_orders(tenant_id, status, priority, ordered_at);

create table public.imaging_studies (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  imaging_order_id uuid not null references public.imaging_orders(id) on delete restrict,
  study_uid text not null check (length(btrim(study_uid)) > 0),
  modality text not null check (modality in ('xray','ct','mri','ultrasound')),
  body_region text not null check (length(btrim(body_region)) > 0),
  performed_by uuid not null references public.app_users(id) on delete restrict,
  performed_at timestamptz not null default now(),
  acquisition_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, study_uid)
);
create index imaging_studies_order_idx on public.imaging_studies(imaging_order_id, created_at);

create table public.imaging_reports (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  imaging_order_id uuid not null references public.imaging_orders(id) on delete restrict,
  study_id uuid not null references public.imaging_studies(id) on delete restrict,
  findings text not null check (length(btrim(findings)) > 0),
  impression text not null check (length(btrim(impression)) > 0),
  status text not null default 'draft' check (status in ('draft','verified')),
  entered_by uuid not null references public.app_users(id) on delete restrict,
  entered_at timestamptz not null default now(),
  verified_by uuid references public.app_users(id) on delete restrict,
  verified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint imaging_report_verified_ck check ((status = 'verified' and verified_by is not null and verified_at is not null) or status = 'draft')
);
create unique index imaging_reports_order_uniq on public.imaging_reports(tenant_id, imaging_order_id);

create trigger imaging_orders_set_updated_at before update on public.imaging_orders for each row execute function nodex.tg_set_updated_at();
create trigger imaging_studies_set_updated_at before update on public.imaging_studies for each row execute function nodex.tg_set_updated_at();
create trigger imaging_reports_set_updated_at before update on public.imaging_reports for each row execute function nodex.tg_set_updated_at();

create or replace function nodex.tg_imaging_order_transition_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status in ('cancelled','completed') and new.status <> old.status then
    raise exception using message = 'NODEX: terminal imaging orders cannot transition', errcode = '42501';
  end if;
  if new.status = 'completed' and old.status <> 'ordered' then
    raise exception using message = 'NODEX: imaging orders complete only from the ordered state', errcode = '42501';
  end if;
  if new.status = 'cancelled' and (new.cancelled_at is null or new.cancelled_reason is null) then
    raise exception using message = 'NODEX: cancelling an imaging order requires timestamp and reason', errcode = '22000';
  end if;
  return new;
end;
$$;
create trigger imaging_orders_transition_guard before update on public.imaging_orders for each row execute function nodex.tg_imaging_order_transition_guard();

create or replace function nodex.tg_imaging_report_immutable_after_verify()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status = 'verified' then
    if new.tenant_id is distinct from old.tenant_id or new.imaging_order_id is distinct from old.imaging_order_id or new.study_id is distinct from old.study_id or new.findings is distinct from old.findings or new.impression is distinct from old.impression or new.entered_by is distinct from old.entered_by or new.entered_at is distinct from old.entered_at or new.verified_by is distinct from old.verified_by or new.verified_at is distinct from old.verified_at then
      raise exception using message = 'NODEX: verified imaging reports are immutable', errcode = '42501';
    end if;
    if new.status <> old.status then
      raise exception using message = 'NODEX: verified imaging reports are immutable', errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;
create trigger imaging_reports_immutable_after_verify before update on public.imaging_reports for each row execute function nodex.tg_imaging_report_immutable_after_verify();
create trigger imaging_reports_append_only_delete before delete on public.imaging_reports for each row execute function nodex.tg_block_mutation();

alter table public.imaging_orders enable row level security;
alter table public.imaging_orders force row level security;
alter table public.imaging_studies enable row level security;
alter table public.imaging_studies force row level security;
alter table public.imaging_reports enable row level security;
alter table public.imaging_reports force row level security;

create policy imaging_orders_select_member on public.imaging_orders for select to authenticated using (nodex.has_permission(tenant_id,'patient.read'));
create policy imaging_orders_insert_writer on public.imaging_orders for insert to authenticated with check (nodex.has_permission(tenant_id,'imaging_order.write'));
create policy imaging_orders_update_writer on public.imaging_orders for update to authenticated using (nodex.has_permission(tenant_id,'imaging_order.write')) with check (nodex.has_permission(tenant_id,'imaging_order.write'));
create policy imaging_studies_select_member on public.imaging_studies for select to authenticated using (nodex.has_permission(tenant_id,'patient.read'));
create policy imaging_studies_insert_recorder on public.imaging_studies for insert to authenticated with check (nodex.has_permission(tenant_id,'imaging_study.record'));
create policy imaging_studies_update_recorder on public.imaging_studies for update to authenticated using (nodex.has_permission(tenant_id,'imaging_study.record')) with check (nodex.has_permission(tenant_id,'imaging_study.record'));
create policy imaging_reports_select_member on public.imaging_reports for select to authenticated using (nodex.has_permission(tenant_id,'patient.read'));
create policy imaging_reports_insert_writer on public.imaging_reports for insert to authenticated with check (nodex.has_permission(tenant_id,'imaging_report.enter'));
create policy imaging_reports_update_verifier on public.imaging_reports for update to authenticated using (nodex.has_permission(tenant_id,'imaging_report.verify')) with check (nodex.has_permission(tenant_id,'imaging_report.verify'));
