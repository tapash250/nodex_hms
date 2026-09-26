-- NODEX Phase 3, Module 26: blood bank and transfusion management.
--
-- Blood unit registration, crossmatch workflow, issue and transfusion outcomes.
-- Requests flow pending -> crossmatched -> approved -> completed; units flow
-- available -> reserved -> issued with quarantine and expiry. Approval records
-- an approver and requires transfusion.finalize.
-- RLS uses membership-derived permissions; FKs target app_users.

create table public.transfusion_requests (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  patient_id uuid not null references public.patients(id) on delete restrict,
  encounter_id uuid references public.clinical_encounters(id) on delete restrict,
  requested_by uuid not null references public.app_users(id) on delete restrict,
  requested_blood_group text not null check (requested_blood_group in ('A+','A-','B+','B-','AB+','AB-','O+','O-')),
  component text not null check (component in ('whole_blood','red_cells','platelets','plasma','cryoprecipitate','double_red_cells')),
  units_requested int not null check (units_requested > 0),
  indication text check (indication is null or length(btrim(indication)) > 0),
  urgency text not null default 'routine' check (urgency in ('routine','urgent','emergency')),
  status text not null default 'pending' check (status in ('pending','crossmatched','approved','rejected','cancelled','completed')),
  crossmatch_result text not null default 'pending' check (crossmatch_result in ('pending','compatible','incompatible')),
  requested_at timestamptz not null default now(),
  approved_by uuid references public.app_users(id) on delete set null,
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index transfusion_requests_tenant_status_idx on public.transfusion_requests(tenant_id, status);
create index transfusion_requests_patient_idx on public.transfusion_requests(tenant_id, patient_id, requested_at desc);

create table public.blood_units (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  unit_number text not null check (length(btrim(unit_number)) > 0),
  blood_group text not null check (blood_group in ('A+','A-','B+','B-','AB+','AB-','O+','O-')),
  component text not null check (component in ('whole_blood','red_cells','platelets','plasma','cryoprecipitate','double_red_cells')),
  volume_ml int check (volume_ml > 0),
  collected_at timestamptz not null default now(),
  expires_at timestamptz not null,
  status text not null default 'available' check (status in ('available','reserved','issued','quarantined','expired','discarded')),
  location_id uuid references public.stock_locations(id) on delete set null,
  patient_id uuid references public.patients(id) on delete set null,
  transfusion_request_id uuid references public.transfusion_requests(id) on delete set null,
  created_by uuid not null references public.app_users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, unit_number),
  check (expires_at > collected_at)
);
create index blood_units_tenant_status_idx on public.blood_units(tenant_id, status);
create index blood_units_group_status_idx on public.blood_units(tenant_id, blood_group, status);
create index blood_units_patient_idx on public.blood_units(tenant_id, patient_id);

create table public.transfusions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  transfusion_request_id uuid not null references public.transfusion_requests(id) on delete restrict,
  blood_unit_id uuid not null references public.blood_units(id) on delete restrict,
  patient_id uuid not null references public.patients(id) on delete restrict,
  recorded_by uuid not null references public.app_users(id) on delete restrict,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  status text not null default 'started' check (status in ('started','transfused','stopped','returned','reaction')),
  volume_ml int check (volume_ml > 0),
  reaction_notes text check (reaction_notes is null or length(btrim(reaction_notes)) > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index transfusions_tenant_idx on public.transfusions(tenant_id, started_at desc);
create index transfusions_patient_idx on public.transfusions(patient_id, started_at desc);
create index transfusions_unit_idx on public.transfusions(blood_unit_id);

create trigger transfusion_requests_set_updated_at before update on public.transfusion_requests for each row execute function nodex.tg_set_updated_at();
create trigger blood_units_set_updated_at before update on public.blood_units for each row execute function nodex.tg_set_updated_at();
create trigger transfusions_set_updated_at before update on public.transfusions for each row execute function nodex.tg_set_updated_at();

-- A transfusion request is frozen once terminal. Approval records an approver
-- and timestamp and is restricted to transfusion.finalize. A null auth.uid()
-- (service-role server path) is trusted, as with RLS.
create or replace function nodex.tg_transfusion_request_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  approving boolean;
begin
  if TG_OP = 'UPDATE' then
    if old.status in ('completed','cancelled','rejected') and new.status <> old.status then
      raise exception using message = 'NODEX: closed transfusion requests cannot transition', errcode = '42501';
    end if;
    approving := new.status <> old.status and new.status = 'approved';
  else
    approving := new.status = 'approved';
  end if;
  if approving then
    if new.approved_by is null or new.approved_at is null then
      raise exception using message = 'NODEX: approving a transfusion request requires approver and timestamp', errcode = '22000';
    end if;
    if auth.uid() is not null and not nodex.has_permission(new.tenant_id, 'transfusion.finalize') then
      raise exception using message = 'NODEX: transfusion approval requires transfusion.finalize', errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;
create trigger transfusion_requests_guard before insert or update on public.transfusion_requests for each row execute function nodex.tg_transfusion_request_guard();

-- Blood units freeze once discarded or expired; quarantine stays releasable.
create or replace function nodex.tg_blood_unit_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status in ('discarded','expired') and new.status <> old.status then
    raise exception using message = 'NODEX: discarded or expired blood units cannot transition', errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger blood_units_guard before update on public.blood_units for each row execute function nodex.tg_blood_unit_guard();

alter table public.transfusion_requests enable row level security;
alter table public.transfusion_requests force row level security;
alter table public.blood_units enable row level security;
alter table public.blood_units force row level security;
alter table public.transfusions enable row level security;
alter table public.transfusions force row level security;

create policy transfusion_requests_select_member on public.transfusion_requests for select to authenticated using (nodex.has_permission(tenant_id,'patient.read'));
create policy transfusion_requests_insert_requester on public.transfusion_requests for insert to authenticated with check (nodex.has_permission(tenant_id,'transfusion.request'));
create policy transfusion_requests_update_requester on public.transfusion_requests for update to authenticated using (nodex.has_permission(tenant_id,'transfusion.request')) with check (nodex.has_permission(tenant_id,'transfusion.request'));
create policy transfusion_requests_update_bloodbank on public.transfusion_requests for update to authenticated using (nodex.has_permission(tenant_id,'blood_unit.write')) with check (nodex.has_permission(tenant_id,'blood_unit.write'));
create policy transfusion_requests_update_administer on public.transfusion_requests for update to authenticated using (nodex.has_permission(tenant_id,'transfusion.administer')) with check (nodex.has_permission(tenant_id,'transfusion.administer'));

create policy blood_units_select_member on public.blood_units for select to authenticated using (nodex.has_permission(tenant_id,'patient.read'));
create policy blood_units_insert_writer on public.blood_units for insert to authenticated with check (nodex.has_permission(tenant_id,'blood_unit.write'));
create policy blood_units_update_writer on public.blood_units for update to authenticated using (nodex.has_permission(tenant_id,'blood_unit.write')) with check (nodex.has_permission(tenant_id,'blood_unit.write'));

create policy transfusions_select_member on public.transfusions for select to authenticated using (nodex.has_permission(tenant_id,'patient.read'));
create policy transfusions_insert_writer on public.transfusions for insert to authenticated with check (nodex.has_permission(tenant_id,'transfusion.administer'));
create policy transfusions_update_writer on public.transfusions for update to authenticated using (nodex.has_permission(tenant_id,'transfusion.administer')) with check (nodex.has_permission(tenant_id,'transfusion.administer'));
