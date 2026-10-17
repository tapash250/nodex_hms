-- NODEX Phase 4, Module 30: Bio-Medical Waste Management.
--
-- Specification scope: "Waste categories, generation logs, barcoded disposal
-- certificates, compliance."
--
-- This is the regulated waste estate: what the hospital discards, where it came
-- from, and the certificate that proves it was destroyed lawfully. It is a
-- distinct domain from central inventory (Module 28, consumables) and the
-- equipment registry (Module 29, serialized instruments): waste is a quantity
-- that leaves the building and is accounted for by weight.
--
-- Three tables, matching the scope:
--
--   * `waste_categories` is the governed catalogue — the colour-coded stream
--     (yellow, red, white, blue) with its hazard class and treatment
--     requirement. It is tenant-scoped configuration because the colour codes
--     and retention rules differ by jurisdiction. A category is deactivated, not
--     deleted, so history that names it stays legible.
--   * `waste_generation_logs` is the append-only generation record: this weight
--     of this stream left this place at this time. A correction is a new row.
--   * `waste_disposal_certificates` is the barcoded compliance record: the
--     certificate that a batch was destroyed by a named vendor by a named
--     method. It is issued and may be voided, and voiding is one-way and freezes
--     the row — a certificate that has been declared void must not be quietly
--     resurrected.
--
-- Compliance is *derived*, not stored: the gap between the weight generated and
-- the weight covered by live certificates, per category over a window. Storing a
-- compliance flag would let it drift away from the facts it summarises.
--
-- The three permissions are granted explicitly because the Phase 1
-- all-permissions seed predates these keys.

create table public.waste_categories (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  code text not null check (length(btrim(code)) > 0),
  name text not null check (length(btrim(name)) > 0),
  colour text not null default 'yellow'
    check (colour in ('yellow','red','white','blue','black','green','other')),
  hazard_class text not null default 'infectious'
    check (hazard_class in ('infectious','sharps','pharmaceutical','chemical','radioactive','general','other')),
  requires_treatment boolean not null default true,
  treatment_method text
    check (treatment_method is null or length(btrim(treatment_method)) > 0),
  retention_days integer check (retention_days is null or retention_days >= 0),
  is_active boolean not null default true,
  created_by uuid not null references public.app_users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, code)
);
create index waste_categories_tenant_idx
  on public.waste_categories(tenant_id, is_active);

create trigger waste_categories_set_updated_at before update on public.waste_categories
  for each row execute function nodex.tg_set_updated_at();
-- A category is deactivated, never deleted: generation logs and certificates
-- name it and must stay answerable.
create trigger waste_categories_retain before delete on public.waste_categories
  for each row execute function nodex.tg_block_mutation();

-- The append-only generation record.
create table public.waste_generation_logs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  facility_id uuid not null references public.facilities(id) on delete restrict,
  category_id uuid not null references public.waste_categories(id) on delete restrict,
  department_id uuid references public.departments(id) on delete set null,
  location_label text check (location_label is null or length(btrim(location_label)) > 0),
  weight_grams bigint not null check (weight_grams > 0),
  container_count integer not null default 1 check (container_count >= 0),
  logged_at timestamptz not null default now(),
  logged_by uuid not null references public.app_users(id) on delete restrict,
  notes text check (notes is null or length(btrim(notes)) > 0),
  created_at timestamptz not null default now()
);
create index waste_generation_category_idx
  on public.waste_generation_logs(tenant_id, category_id, logged_at desc);
create index waste_generation_facility_idx
  on public.waste_generation_logs(tenant_id, facility_id, logged_at desc);
create trigger waste_generation_append_only
  before update or delete on public.waste_generation_logs
  for each row execute function nodex.tg_block_mutation();

-- The barcoded disposal certificate.
create table public.waste_disposal_certificates (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  facility_id uuid not null references public.facilities(id) on delete restrict,
  category_id uuid not null references public.waste_categories(id) on delete restrict,
  certificate_no text not null check (length(btrim(certificate_no)) > 0),
  barcode text not null check (length(btrim(barcode)) > 0),
  disposal_vendor text not null check (length(btrim(disposal_vendor)) > 0),
  vendor_licence text check (vendor_licence is null or length(btrim(vendor_licence)) > 0),
  method text not null
    check (method in ('incineration','autoclave','chemical','microwave','landfill','recycling','other')),
  disposed_at timestamptz not null,
  weight_grams bigint not null check (weight_grams > 0),
  manifest_reference text
    check (manifest_reference is null or length(btrim(manifest_reference)) > 0),
  status text not null default 'issued' check (status in ('issued','voided')),
  void_reason text check (void_reason is null or length(btrim(void_reason)) > 0),
  issued_by uuid not null references public.app_users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, certificate_no),
  unique (tenant_id, barcode),
  -- A certificate is voided with a reason; the reason is what an audit asks for.
  constraint waste_certificate_void_ck check (
    status <> 'voided'
    or (void_reason is not null and length(btrim(void_reason)) > 0)
  )
);
create index waste_certificates_category_idx
  on public.waste_disposal_certificates(tenant_id, category_id, disposed_at desc);
create index waste_certificates_status_idx
  on public.waste_disposal_certificates(tenant_id, status, disposed_at desc);

create trigger waste_certificates_set_updated_at before update on public.waste_disposal_certificates
  for each row execute function nodex.tg_set_updated_at();
create trigger waste_certificates_retain before delete on public.waste_disposal_certificates
  for each row execute function nodex.tg_block_mutation();

-- Voiding is one-way and terminal. A voided certificate is frozen so a
-- compliance statement that relied on its withdrawal cannot be rewritten.
create or replace function nodex.tg_waste_certificate_lifecycle_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status = 'voided' then
    if new.status is distinct from old.status
      or new.certificate_no is distinct from old.certificate_no
      or new.barcode is distinct from old.barcode
      or new.disposal_vendor is distinct from old.disposal_vendor
      or new.vendor_licence is distinct from old.vendor_licence
      or new.method is distinct from old.method
      or new.disposed_at is distinct from old.disposed_at
      or new.weight_grams is distinct from old.weight_grams
      or new.manifest_reference is distinct from old.manifest_reference
      or new.void_reason is distinct from old.void_reason
      or new.category_id is distinct from old.category_id
      or new.facility_id is distinct from old.facility_id then
      raise exception using
        message = 'NODEX: a voided disposal certificate is immutable',
        errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;
create trigger waste_certificates_lifecycle_guard
  before update on public.waste_disposal_certificates
  for each row execute function nodex.tg_waste_certificate_lifecycle_guard();

alter table public.waste_categories enable row level security;
alter table public.waste_categories force row level security;
alter table public.waste_generation_logs enable row level security;
alter table public.waste_generation_logs force row level security;
alter table public.waste_disposal_certificates enable row level security;
alter table public.waste_disposal_certificates force row level security;

create policy waste_categories_select_member on public.waste_categories for select to authenticated
  using (nodex.has_permission(tenant_id, 'waste.read'));
create policy waste_categories_insert_manager on public.waste_categories for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'waste.manage'));
create policy waste_categories_update_manager on public.waste_categories for update to authenticated
  using (nodex.has_permission(tenant_id, 'waste.manage'))
  with check (nodex.has_permission(tenant_id, 'waste.manage'));

create policy waste_generation_select_member on public.waste_generation_logs for select to authenticated
  using (nodex.has_permission(tenant_id, 'waste.read'));
create policy waste_generation_insert_recorder on public.waste_generation_logs for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'waste.record'));

create policy waste_certificates_select_member on public.waste_disposal_certificates for select to authenticated
  using (nodex.has_permission(tenant_id, 'waste.read'));
create policy waste_certificates_insert_manager on public.waste_disposal_certificates for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'waste.manage'));
create policy waste_certificates_update_manager on public.waste_disposal_certificates for update to authenticated
  using (nodex.has_permission(tenant_id, 'waste.manage'))
  with check (nodex.has_permission(tenant_id, 'waste.manage'));

insert into public.permissions (key, display_name, description, module_code, risk_tier, requires_online)
values
  ('waste.read',   'Read biomedical waste',   'View waste categories, generation logs and disposal certificates.', 'M30', 'standard', false),
  ('waste.record', 'Log waste generation',    'Record the weight and containers of waste generated.', 'M30', 'elevated', false),
  ('waste.manage', 'Manage biomedical waste', 'Maintain waste categories and issue or void disposal certificates.', 'M30', 'elevated', false)
on conflict (key) do nothing;

insert into public.role_permissions (role_key, permission_key)
values
  ('hospital_super_admin', 'waste.read'),
  ('hospital_super_admin', 'waste.record'),
  ('hospital_super_admin', 'waste.manage'),
  ('medical_officer',      'waste.read'),
  ('nursing_staff',        'waste.read'),
  ('nursing_staff',        'waste.record'),
  ('lab_technician',       'waste.read'),
  ('lab_technician',       'waste.record'),
  ('auditor',              'waste.read')
on conflict do nothing;
