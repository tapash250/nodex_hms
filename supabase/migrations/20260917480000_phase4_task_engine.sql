-- Module 41: Clinical & Administrative Task Engine
--
-- Micro-task delegation across departments: specimen transport, sanitization
-- requests, nursing reminders and STAT clinical errands. These are not ward
-- nursing tasks: the ward task board is owned by a ward and closed by whoever
-- is on the ward. A hospital task is raised by one department for another, so
-- it carries its own requested-by, an explicit origin and destination, and a
-- priority ladder that starts at the request rather than at the assignment.

create table public.hospital_tasks (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  task_code text not null check (length(btrim(task_code)) > 0),
  title text not null check (length(btrim(title)) > 0),
  detail text check (detail is null or length(btrim(detail)) > 0),
  category text not null default 'other'
    check (category in ('specimen_transport','sanitization','nursing_reminder',
                        'stat_errand','equipment_retrieval','document_delivery',
                        'other')),
  priority text not null default 'medium'
    check (priority in ('low','medium','urgent','stat')),
  status text not null default 'open'
    check (status in ('open','claimed','in_progress','completed','cancelled')),
  patient_id uuid references public.patients(id) on delete set null,
  encounter_id uuid references public.clinical_encounters(id) on delete restrict,
  from_location text check (from_location is null or length(btrim(from_location)) > 0),
  to_location text check (to_location is null or length(btrim(to_location)) > 0),
  requested_by uuid not null references public.app_users(id) on delete restrict,
  assigned_to uuid references public.app_users(id) on delete set null,
  due_at timestamptz,
  claimed_at timestamptz,
  started_at timestamptz,
  completed_by uuid references public.app_users(id) on delete set null,
  completed_at timestamptz,
  completion_note text
    check (completion_note is null or length(btrim(completion_note)) > 0),
  cancellation_reason text
    check (cancellation_reason is null or length(btrim(cancellation_reason)) > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, task_code),
  -- A task is closed by somebody who says what they did. A completion without
  -- a note is indistinguishable from a task somebody ticked to clear a board.
  constraint hospital_task_completion_ck check (
    (status = 'completed' and completed_by is not null
      and completed_at is not null and completion_note is not null)
    or (status <> 'completed' and completed_at is null
      and completed_by is null and completion_note is null)
  ),
  -- The same rule for cancellation: a cancelled errand carries its reason, so
  -- a STAT task that never happened can be explained later.
  constraint hospital_task_cancellation_ck check (
    (status = 'cancelled' and cancellation_reason is not null)
    or (status <> 'cancelled' and cancellation_reason is null)
  ),
  -- Claimed means somebody owns it. The claimer is recorded when the claim
  -- happens, not when the task was written.
  constraint hospital_task_claim_ck check (
    (status in ('claimed','in_progress') and assigned_to is not null
      and claimed_at is not null)
    or (status in ('open','completed','cancelled'))
  )
);

comment on table public.hospital_tasks is
  'Cross-department micro-tasks: specimen transport, sanitization, nursing reminders and STAT errands. Priority is set by the requester and never downgraded by the assignee; a STAT task that cannot be done is cancelled with a reason rather than quietly chilled.';

create index hospital_tasks_board_idx
  on public.hospital_tasks (tenant_id, status, priority, due_at);
create index hospital_tasks_assignee_idx
  on public.hospital_tasks (assigned_to, status, due_at);
create index hospital_tasks_requester_idx
  on public.hospital_tasks (requested_by, created_at desc);
create index hospital_tasks_patient_idx
  on public.hospital_tasks (patient_id)
  where patient_id is not null;

create trigger hospital_tasks_set_updated_at before update on public.hospital_tasks
  for each row execute function nodex.tg_set_updated_at();

-- Tasks are deleted by nobody. A request that was made and then abandoned is
-- part of the record of what the hospital was asked to do.
create trigger hospital_tasks_retain before delete on public.hospital_tasks
  for each row execute function nodex.tg_block_mutation();

-- ---------------------------------------------------------------------------
-- Transition guard
-- ---------------------------------------------------------------------------

create or replace function nodex.tg_hospital_task_transition_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if new.status <> 'open' then
      raise exception using
        message = 'NODEX: a hospital task is raised open',
        errcode = '22000';
    end if;
    if new.assigned_to is not null then
      raise exception using
        message = 'NODEX: a hospital task is claimed, not assigned at creation',
        errcode = '22000';
    end if;
    return new;
  end if;

  -- What the request is cannot change after it was made. A different patient
  -- or a different errand is a different request, not an edit.
  if new.task_code is distinct from old.task_code
     or new.category is distinct from old.category
     or new.patient_id is distinct from old.patient_id
     or new.encounter_id is distinct from old.encounter_id
     or new.requested_by is distinct from old.requested_by
     or new.tenant_id is distinct from old.tenant_id then
    raise exception using
      message = 'NODEX: the substance of a hospital task is immutable',
      errcode = '42501';
  end if;

  if old.status = new.status then
    return new;
  end if;

  if old.status in ('completed', 'cancelled') then
    raise exception using
      message = 'NODEX: a closed hospital task is immutable',
      errcode = '42501';
  end if;

  -- Priority may be raised (a waiting errand became urgent) but never lowered:
  -- the requester's clinical judgement outranks the assignee's workload.
  if new.priority <> old.priority then
    if case old.priority
         when 'low' then 1
         when 'medium' then 2
         when 'urgent' then 3
         else 4
       end
       > case new.priority
           when 'low' then 1
           when 'medium' then 2
           when 'urgent' then 3
           else 4
         end then
      raise exception using
        message = 'NODEX: a hospital task priority is raised, never lowered',
        errcode = '42501';
    end if;
  end if;

  if new.status = 'claimed' and old.status <> 'open' then
    raise exception using
      message = 'NODEX: only an open task may be claimed',
      errcode = '42501';
  end if;
  if new.status = 'in_progress' and old.status <> 'claimed' then
    raise exception using
      message = 'NODEX: only a claimed task may be started',
      errcode = '42501';
  end if;
  if new.status = 'completed' and old.status not in ('claimed', 'in_progress') then
    raise exception using
      message = 'NODEX: only a claimed or started task may be completed',
      errcode = '42501';
  end if;
  if new.status = 'cancelled' and old.status not in ('open', 'claimed', 'in_progress') then
    raise exception using
      message = 'NODEX: only an open or running task may be cancelled',
      errcode = '42501';
  end if;

  -- The claim is stamped when it happens, so a board can say how long a STAT
  -- errand waited before anybody picked it up.
  if new.status = 'claimed' and new.claimed_at is null then
    new.claimed_at := now();
  end if;
  if new.status = 'in_progress' and new.started_at is null then
    new.started_at := now();
  end if;
  if new.status = 'completed' and new.completed_at is null then
    new.completed_at := now();
  end if;

  -- A cancelled task may never carry a completion, and vice versa: the two
  -- endings are exclusive.
  if new.status = 'cancelled' then
    new.completed_at := null;
    new.completed_by := null;
    new.completion_note := null;
  end if;
  if new.status = 'completed' then
    new.cancellation_reason := null;
  end if;

  return new;
end;
$$;

create trigger hospital_tasks_transition_guard
  before insert or update on public.hospital_tasks
  for each row execute function nodex.tg_hospital_task_transition_guard();

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table public.hospital_tasks enable row level security;
alter table public.hospital_tasks force row level security;

-- Reading the board is what scopes the sync bucket: a device that cannot read
-- tasks never replicates one. Writing covers raising a task, claiming it and
-- closing it, because a porter who cannot claim is not a delegation system.
create policy hospital_tasks_select_member on public.hospital_tasks
  for select to authenticated
  using (nodex.has_permission(tenant_id, 'tasks.read'));
create policy hospital_tasks_insert_writer on public.hospital_tasks
  for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'tasks.manage'));
create policy hospital_tasks_update_writer on public.hospital_tasks
  for update to authenticated
  using (nodex.has_permission(tenant_id, 'tasks.manage'))
  with check (nodex.has_permission(tenant_id, 'tasks.manage'));

-- ---------------------------------------------------------------------------
-- Permissions
-- ---------------------------------------------------------------------------

-- Both stay available offline: an errand is raised at the bedside or in a
-- corridor, and a porter claims it in a lift where there is no signal. The
-- server arbitrates the claim when the mutation arrives, which is why the
-- conflict policy for a task is server-authoritative rather than last-write.
insert into public.permissions
  (key, display_name, description, module_code, risk_tier, requires_online)
values
  ('tasks.read', 'Read the task board',
   'View cross-department hospital tasks: transport, sanitization, reminders and STAT errands.',
   'M41', 'standard', false),
  ('tasks.manage', 'Manage hospital tasks',
   'Raise, claim, reprioritise and close cross-department hospital tasks.',
   'M41', 'standard', false)
on conflict (key) do nothing;

insert into public.role_permissions (role_key, permission_key)
values
  ('hospital_super_admin', 'tasks.read'),
  ('hospital_super_admin', 'tasks.manage'),
  ('medical_officer',      'tasks.read'),
  ('medical_officer',      'tasks.manage'),
  ('nursing_staff',        'tasks.read'),
  ('nursing_staff',        'tasks.manage'),
  ('lab_technician',       'tasks.read'),
  ('lab_technician',       'tasks.manage'),
  ('pharmacist',           'tasks.read'),
  ('pharmacist',           'tasks.manage'),
  ('billing_accounts',     'tasks.read'),
  ('auditor',              'tasks.read')
on conflict do nothing;
