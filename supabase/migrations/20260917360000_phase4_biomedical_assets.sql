-- NODEX Phase 4, Module 29: Biomedical Assets & Calibration.
--
-- Specification scope: "Equipment registry, maintenance, breakdown tickets,
-- calibration, lifecycle."
--
-- This is the equipment estate behind the clinical work: the monitor, the
-- ventilator, the infusion pump, the analyser. It is a distinct domain from
-- central inventory (Module 28), which holds consumable stock: an asset is a
-- serialized, individually accountable instrument with a location, a lifecycle
-- and a calibration obligation, not a quantity on a shelf.
--
-- Three tables, matching the three moving parts of the scope:
--
--   * `biomedical_assets` is the registry: the instrument, its location and its
--     lifecycle status. It is a living record while in service and freezes when
--     decommissioned. An asset with an open breakdown ticket may not be
--     decommissioned — a broken instrument that is still in the estate is not
--     safely retirable out from under the work order that names it.
--   * `biomedical_breakdown_tickets` is the fault report. It is a guarded state
--     machine (reported -> acknowledged -> in_repair -> resolved, or cancelled
--     from any live stage) because "this instrument failed, was taken out of
--     service and was returned to service at this time" is an assertion a
--     safety review is audited on. Terminal tickets freeze.
--   * `biomedical_maintenance_records` is the append-only service history that
--     covers both maintenance and calibration: a calibration, a preventive
--     service, a repair, a safety test or an inspection. It carries the next
--     due date, so the calibration-due state is *derived* from the latest
--     record rather than stored twice and allowed to drift.
--
-- The three permissions are granted explicitly because the Phase 1
-- all-permissions seed predates these keys.

create table public.biomedical_assets (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  facility_id uuid not null references public.facilities(id) on delete restrict,
  department_id uuid references public.departments(id) on delete set null,
  asset_tag text not null check (length(btrim(asset_tag)) > 0),
  name text not null check (length(btrim(name)) > 0),
  category text check (category is null or length(btrim(category)) > 0),
  manufacturer text check (manufacturer is null or length(btrim(manufacturer)) > 0),
  model_no text check (model_no is null or length(btrim(model_no)) > 0),
  serial_no text check (serial_no is null or length(btrim(serial_no)) > 0),
  criticality text not null default 'medium'
    check (criticality in ('low','medium','high','life_support')),
  status text not null default 'in_service'
    check (status in ('in_service','out_of_service','under_repair','decommissioned')),
  commissioned_on date,
  warranty_until date,
  notes text check (notes is null or length(btrim(notes)) > 0),
  created_by uuid not null references public.app_users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, asset_tag)
);
create index biomedical_assets_facility_idx
  on public.biomedical_assets(tenant_id, facility_id, status);
create index biomedical_assets_department_idx
  on public.biomedical_assets(tenant_id, department_id);

create trigger biomedical_assets_set_updated_at before update on public.biomedical_assets
  for each row execute function nodex.tg_set_updated_at();

-- The estate lifecycle. A unit is routinely moved between service, out of
-- service and repair. Decommissioning is terminal and freezes the whole row, so
-- the tag and serial a maintenance record names cannot be rewritten. A unit
-- with an open breakdown ticket may not be decommissioned.
create or replace function nodex.tg_biomedical_asset_lifecycle_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status = 'decommissioned' then
    if new.status is distinct from old.status
      or new.asset_tag is distinct from old.asset_tag
      or new.name is distinct from old.name
      or new.category is distinct from old.category
      or new.manufacturer is distinct from old.manufacturer
      or new.model_no is distinct from old.model_no
      or new.serial_no is distinct from old.serial_no
      or new.criticality is distinct from old.criticality
      or new.commissioned_on is distinct from old.commissioned_on
      or new.warranty_until is distinct from old.warranty_until
      or new.notes is distinct from old.notes
      or new.facility_id is distinct from old.facility_id
      or new.department_id is distinct from old.department_id then
      raise exception using
        message = 'NODEX: a decommissioned asset is immutable',
        errcode = '42501';
    end if;
  end if;

  if new.status = 'decommissioned' and old.status <> 'decommissioned' then
    if exists (
      select 1 from public.biomedical_breakdown_tickets t
      where t.asset_id = new.id and t.status in ('reported','acknowledged','in_repair')
    ) then
      raise exception using
        message = 'NODEX: an asset with an open breakdown ticket cannot be decommissioned',
        errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;
create trigger biomedical_assets_lifecycle_guard before update on public.biomedical_assets
  for each row execute function nodex.tg_biomedical_asset_lifecycle_guard();
create trigger biomedical_assets_retain before delete on public.biomedical_assets
  for each row execute function nodex.tg_block_mutation();

-- The fault report.
create table public.biomedical_breakdown_tickets (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  asset_id uuid not null references public.biomedical_assets(id) on delete restrict,
  facility_id uuid not null references public.facilities(id) on delete restrict,
  reported_by uuid not null references public.app_users(id) on delete restrict,
  reported_at timestamptz not null default now(),
  priority text not null default 'medium'
    check (priority in ('low','medium','high','critical')),
  symptom text not null check (length(btrim(symptom)) > 0),
  status text not null default 'reported'
    check (status in ('reported','acknowledged','in_repair','resolved','cancelled')),
  acknowledged_at timestamptz,
  resolved_at timestamptz,
  resolution_notes text
    check (resolution_notes is null or length(btrim(resolution_notes)) > 0),
  cancellation_reason text
    check (cancellation_reason is null or length(btrim(cancellation_reason)) > 0),
  created_by uuid not null references public.app_users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- Resolving a fault is an audited assertion: it needs a time and a reason.
  constraint biomedical_ticket_resolution_ck check (
    status <> 'resolved'
    or (resolved_at is not null
        and resolution_notes is not null
        and length(btrim(resolution_notes)) > 0)
  )
);
create index biomedical_tickets_asset_idx
  on public.biomedical_breakdown_tickets(tenant_id, asset_id, reported_at desc);
create index biomedical_tickets_open_idx
  on public.biomedical_breakdown_tickets(tenant_id, status, priority);

create trigger biomedical_tickets_set_updated_at before update on public.biomedical_breakdown_tickets
  for each row execute function nodex.tg_set_updated_at();
create trigger biomedical_tickets_retain before delete on public.biomedical_breakdown_tickets
  for each row execute function nodex.tg_block_mutation();

-- The fault state machine. A ticket advances one stage at a time and may be
-- cancelled from any live stage; a terminal ticket is frozen so the times a
-- safety review turns on cannot be rewritten. Fault details may be corrected
-- while the ticket is live.
create or replace function nodex.tg_biomedical_ticket_transition_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status in ('resolved', 'cancelled') then
    raise exception using
      message = 'NODEX: a closed breakdown ticket is immutable',
      errcode = '42501';
  end if;
  if new.status = old.status then
    return new;
  end if;
  if new.status = 'cancelled' then
    return new;
  end if;
  if (old.status = 'reported' and new.status = 'acknowledged')
    or (old.status = 'acknowledged' and new.status = 'in_repair')
    or (old.status = 'in_repair' and new.status = 'resolved') then
    return new;
  end if;
  raise exception using
    message = 'NODEX: a breakdown ticket may not skip a stage',
    errcode = '42501';
end;
$$;
create trigger biomedical_tickets_transition_guard
  before update on public.biomedical_breakdown_tickets
  for each row execute function nodex.tg_biomedical_ticket_transition_guard();

-- The append-only service history: maintenance and calibration alike. A service
-- event is a thing that happened; a second service is a second row.
create table public.biomedical_maintenance_records (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  asset_id uuid not null references public.biomedical_assets(id) on delete restrict,
  ticket_id uuid references public.biomedical_breakdown_tickets(id) on delete set null,
  kind text not null
    check (kind in ('calibration','preventive','repair','safety_test','inspection')),
  result text not null check (result in ('pass','pass_adjusted','fail')),
  performed_at timestamptz not null default now(),
  performed_by uuid references public.app_users(id) on delete set null,
  provider text check (provider is null or length(btrim(provider)) > 0),
  next_due_at timestamptz,
  reference text check (reference is null or length(btrim(reference)) > 0),
  notes text check (notes is null or length(btrim(notes)) > 0),
  created_at timestamptz not null default now(),
  constraint biomedical_maintenance_due_ck check (
    next_due_at is null or next_due_at > performed_at
  )
);
create index biomedical_maintenance_asset_idx
  on public.biomedical_maintenance_records(tenant_id, asset_id, performed_at desc);
create index biomedical_maintenance_due_idx
  on public.biomedical_maintenance_records(tenant_id, next_due_at);
create trigger biomedical_maintenance_append_only
  before update or delete on public.biomedical_maintenance_records
  for each row execute function nodex.tg_block_mutation();

alter table public.biomedical_assets enable row level security;
alter table public.biomedical_assets force row level security;
alter table public.biomedical_breakdown_tickets enable row level security;
alter table public.biomedical_breakdown_tickets force row level security;
alter table public.biomedical_maintenance_records enable row level security;
alter table public.biomedical_maintenance_records force row level security;

create policy biomedical_assets_select_member on public.biomedical_assets for select to authenticated
  using (nodex.has_permission(tenant_id, 'biomedical.read'));
create policy biomedical_assets_insert_manager on public.biomedical_assets for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'biomedical.manage'));
create policy biomedical_assets_update_manager on public.biomedical_assets for update to authenticated
  using (nodex.has_permission(tenant_id, 'biomedical.manage'))
  with check (nodex.has_permission(tenant_id, 'biomedical.manage'));

create policy biomedical_tickets_select_member on public.biomedical_breakdown_tickets for select to authenticated
  using (nodex.has_permission(tenant_id, 'biomedical.read'));
create policy biomedical_tickets_insert_maintainer on public.biomedical_breakdown_tickets for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'biomedical.maintain'));
create policy biomedical_tickets_update_maintainer on public.biomedical_breakdown_tickets for update to authenticated
  using (nodex.has_permission(tenant_id, 'biomedical.maintain'))
  with check (nodex.has_permission(tenant_id, 'biomedical.maintain'));

create policy biomedical_maintenance_select_member on public.biomedical_maintenance_records for select to authenticated
  using (nodex.has_permission(tenant_id, 'biomedical.read'));
create policy biomedical_maintenance_insert_maintainer on public.biomedical_maintenance_records for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'biomedical.maintain'));

insert into public.permissions (key, display_name, description, module_code, risk_tier, requires_online)
values
  ('biomedical.read',     'Read biomedical assets',  'View the equipment registry, breakdown tickets and service history.', 'M29', 'standard', false),
  ('biomedical.maintain', 'Maintain biomedical equipment', 'Raise and progress breakdown tickets and record maintenance and calibration.', 'M29', 'elevated', false),
  ('biomedical.manage',   'Manage biomedical registry', 'Register, update and decommission equipment.', 'M29', 'elevated', false)
on conflict (key) do nothing;

insert into public.role_permissions (role_key, permission_key)
values
  ('hospital_super_admin', 'biomedical.read'),
  ('hospital_super_admin', 'biomedical.maintain'),
  ('hospital_super_admin', 'biomedical.manage'),
  ('medical_officer',      'biomedical.read'),
  ('nursing_staff',        'biomedical.read'),
  ('nursing_staff',        'biomedical.maintain'),
  ('lab_technician',       'biomedical.read'),
  ('lab_technician',       'biomedical.maintain'),
  ('auditor',              'biomedical.read')
on conflict do nothing;
