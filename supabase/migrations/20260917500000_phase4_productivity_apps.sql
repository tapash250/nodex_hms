-- Module 44: Productivity Apps Ecosystem
--
-- The tools people use between the clinical modules: a board of work they can
-- move across lanes, a scratchpad they write for themselves, and a ticket to
-- the people who keep the building running.
--
-- A scratchpad is deliberately not a server table. A clinician's private
-- notes are not hospital data, are not replicated, and never leave the
-- device — so the scratchpad lives in the device's own database and the
-- server never hears of it.

create table public.work_items (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  board_key text not null check (length(btrim(board_key)) > 0),
  title text not null check (length(btrim(title)) > 0),
  detail text check (detail is null or length(btrim(detail)) > 0),
  lane text not null default 'todo'
    check (lane in ('todo', 'doing', 'blocked', 'done')),
  position integer not null default 0,
  priority text not null default 'medium'
    check (priority in ('low', 'medium', 'high')),
  patient_id uuid references public.patients(id) on delete set null,
  ward_id uuid references public.wards(id) on delete set null,
  department_id uuid references public.departments(id) on delete set null,
  created_by uuid not null references public.app_users(id) on delete restrict,
  assigned_to uuid references public.app_users(id) on delete set null,
  due_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.work_items is
  'Cards on a working board: ward handovers, departmental work and anything else a team moves across lanes. A card is not a clinical record — it points at the clinical record it concerns.';

create index work_items_board_idx
  on public.work_items (tenant_id, board_key, lane, position);
create index work_items_assignee_idx
  on public.work_items (assigned_to, lane, due_at)
  where assigned_to is not null;

create trigger work_items_set_updated_at before update on public.work_items
  for each row execute function nodex.tg_set_updated_at();

-- A card that was completed stays completed: the work did not become
-- unfinished, and a card is never deleted because a board is tidied.
create trigger work_items_retain before delete on public.work_items
  for each row execute function nodex.tg_block_mutation();

create or replace function nodex.tg_work_item_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if new.completed_at is not null then
      raise exception using
        message = 'NODEX: a new work item is not already completed',
        errcode = '22000';
    end if;
    return new;
  end if;

  if new.tenant_id is distinct from old.tenant_id
     or new.board_key is distinct from old.board_key
     or new.created_by is distinct from old.created_by then
    raise exception using
      message = 'NODEX: the identity of a work item is immutable',
      errcode = '42501';
  end if;

  if old.lane = 'done' and new.lane <> 'done' then
    raise exception using
      message = 'NODEX: a completed work item does not go back to the board',
      errcode = '42501';
  end if;

  if new.lane = 'done' and old.lane <> 'done' and new.completed_at is null then
    new.completed_at := now();
  end if;
  if new.lane <> 'done' then
    new.completed_at := null;
  end if;

  return new;
end;
$$;

create trigger work_items_guard
  before insert or update on public.work_items
  for each row execute function nodex.tg_work_item_guard();

-- ---------------------------------------------------------------------------
-- Internal IT ticketing
-- ---------------------------------------------------------------------------

create table public.it_tickets (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  ticket_code text not null check (length(btrim(ticket_code)) > 0),
  title text not null check (length(btrim(title)) > 0),
  detail text check (detail is null or length(btrim(detail)) > 0),
  category text not null default 'general'
    check (category in ('general', 'device', 'network', 'printer', 'access', 'billing_system')),
  priority text not null default 'medium'
    check (priority in ('low', 'medium', 'high', 'urgent')),
  status text not null default 'open'
    check (status in ('open', 'in_progress', 'waiting', 'resolved', 'closed')),
  reported_by uuid not null references public.app_users(id) on delete restrict,
  assigned_to uuid references public.app_users(id) on delete set null,
  resolution_note text
    check (resolution_note is null or length(btrim(resolution_note)) > 0),
  opened_at timestamptz not null default now(),
  closed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, ticket_code)
);

comment on table public.it_tickets is
  'Internal service requests to the hospital IT team: a device that will not charge, a printer that is out of paper, an account that will not open.';

create index it_tickets_status_idx
  on public.it_tickets (tenant_id, status, priority, opened_at desc);
create index it_tickets_reporter_idx
  on public.it_tickets (reported_by, opened_at desc);

create trigger it_tickets_set_updated_at before update on public.it_tickets
  for each row execute function nodex.tg_set_updated_at();

create trigger it_tickets_retain before delete on public.it_tickets
  for each row execute function nodex.tg_block_mutation();

create or replace function nodex.tg_it_ticket_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if new.status <> 'open' then
      raise exception using
        message = 'NODEX: a new ticket is opened',
        errcode = '22000';
    end if;
    return new;
  end if;

  if new.tenant_id is distinct from old.tenant_id
     or new.ticket_code is distinct from old.ticket_code
     or new.reported_by is distinct from old.reported_by then
    raise exception using
      message = 'NODEX: the identity of a ticket is immutable',
      errcode = '42501';
  end if;

  if old.status in ('resolved', 'closed') and new.status <> old.status then
    raise exception using
      message = 'NODEX: a closed ticket is immutable',
      errcode = '42501';
  end if;

  if new.status in ('resolved', 'closed') then
    if new.resolution_note is null then
      raise exception using
        message = 'NODEX: a resolved ticket states what was done',
        errcode = '23514';
    end if;
    if new.closed_at is null then
      new.closed_at := now();
    end if;
  else
    new.closed_at := null;
  end if;

  return new;
end;
$$;

create trigger it_tickets_guard
  before insert or update on public.it_tickets
  for each row execute function nodex.tg_it_ticket_guard();

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table public.work_items enable row level security;
alter table public.work_items force row level security;
alter table public.it_tickets enable row level security;
alter table public.it_tickets force row level security;

-- A board is visible to the staff who work on it; a ticket is visible to the
-- person who raised it, to the person it is assigned to, and to the IT team
-- that answers them.
create policy work_items_select_member on public.work_items
  for select to authenticated
  using (nodex.has_permission(tenant_id, 'workitems.read'));
create policy work_items_insert_writer on public.work_items
  for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'workitems.manage'));
create policy work_items_update_writer on public.work_items
  for update to authenticated
  using (nodex.has_permission(tenant_id, 'workitems.manage'))
  with check (nodex.has_permission(tenant_id, 'workitems.manage'));

create policy it_tickets_select_member on public.it_tickets
  for select to authenticated
  using (
    nodex.has_permission(tenant_id, 'tickets.read')
    or reported_by = auth.uid()
    or assigned_to = auth.uid()
  );
create policy it_tickets_insert_writer on public.it_tickets
  for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'tickets.submit'));
create policy it_tickets_update_writer on public.it_tickets
  for update to authenticated
  using (
    nodex.has_permission(tenant_id, 'tickets.manage')
    or reported_by = auth.uid()
    or assigned_to = auth.uid()
  )
  with check (
    nodex.has_permission(tenant_id, 'tickets.manage')
    or reported_by = auth.uid()
    or assigned_to = auth.uid()
  );

-- ---------------------------------------------------------------------------
-- Permissions
-- ---------------------------------------------------------------------------

insert into public.permissions
  (key, display_name, description, module_code, risk_tier, requires_online)
values
  ('workitems.read', 'Read working boards',
   'View the cards on the ward handover and departmental boards.',
   'M44', 'standard', false),
  ('workitems.manage', 'Manage working boards',
   'Add cards, move them between lanes and close them.',
   'M44', 'standard', false),
  ('tickets.read', 'Read service requests',
   'View the internal IT tickets raised by the staff of this tenant.',
   'M44', 'standard', false),
  ('tickets.submit', 'Raise a service request',
   'Open an internal IT ticket about a device, a network or an account.',
   'M44', 'standard', false),
  ('tickets.manage', 'Work on service requests',
   'Assign, progress and resolve internal IT tickets.',
   'M44', 'standard', false)
on conflict (key) do nothing;

insert into public.role_permissions (role_key, permission_key)
values
  ('hospital_super_admin', 'workitems.read'),
  ('hospital_super_admin', 'workitems.manage'),
  ('hospital_super_admin', 'tickets.read'),
  ('hospital_super_admin', 'tickets.submit'),
  ('hospital_super_admin', 'tickets.manage'),
  ('medical_officer',      'workitems.read'),
  ('medical_officer',      'workitems.manage'),
  ('medical_officer',      'tickets.read'),
  ('medical_officer',      'tickets.submit'),
  ('nursing_staff',        'workitems.read'),
  ('nursing_staff',        'workitems.manage'),
  ('nursing_staff',        'tickets.read'),
  ('nursing_staff',        'tickets.submit'),
  ('lab_technician',       'workitems.read'),
  ('lab_technician',       'tickets.read'),
  ('lab_technician',       'tickets.submit'),
  ('pharmacist',           'workitems.read'),
  ('pharmacist',           'tickets.read'),
  ('pharmacist',           'tickets.submit'),
  ('billing_accounts',     'workitems.read'),
  ('billing_accounts',     'tickets.read'),
  ('billing_accounts',     'tickets.submit'),
  ('integration_service',  'tickets.read'),
  ('integration_service',  'tickets.manage')
on conflict do nothing;
