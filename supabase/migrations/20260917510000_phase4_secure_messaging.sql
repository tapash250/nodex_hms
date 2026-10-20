-- Module 43: Secure Clinical Email & Messaging
--
-- Intra-facility clinical discussion: a thread is a conversation between
-- clinicians about a patient or a case, and the messages in it are the record
-- of what was said and when.
--
-- Access is by participation, not by role: a message is readable by the people
-- in the thread, and the server enforces that on every read. Attachments are
-- held in the clinical storage bucket and reached through short-lived signed
-- links, so a link that is copied into a chat elsewhere stops working.
--
-- The payloads are replicated, because a clinician reading a thread on a ward
-- with no signal still has to read it. That is a deliberate trade: the device
-- holds the conversation, and the conversation is reachable only by the people
-- who were in it.

create table public.clinical_threads (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  subject text not null check (length(btrim(subject)) > 0),
  patient_id uuid references public.patients(id) on delete set null,
  encounter_id uuid references public.clinical_encounters(id) on delete restrict,
  created_by uuid not null references public.app_users(id) on delete restrict,
  participants jsonb not null default '[]'::jsonb
    check (jsonb_typeof(participants) = 'array'),
  status text not null default 'open' check (status in ('open', 'archived')),
  last_message_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.clinical_threads is
  'A clinical discussion thread. The participants array is the access list: a message in a thread is readable by the people in the thread and by nobody else.';

create index clinical_threads_tenant_idx
  on public.clinical_threads (tenant_id, status, last_message_at desc);
create index clinical_threads_patient_idx
  on public.clinical_threads (patient_id, last_message_at desc)
  where patient_id is not null;
create index clinical_threads_participants_idx
  on public.clinical_threads using gin (participants);

create trigger clinical_threads_set_updated_at before update on public.clinical_threads
  for each row execute function nodex.tg_set_updated_at();

create or replace function nodex.tg_clinical_thread_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if not (new.participants @> jsonb_build_array(auth.uid()::text)) then
      raise exception using
        message = 'NODEX: the author of a thread is one of its participants',
        errcode = '42501';
    end if;
    return new;
  end if;

  if new.tenant_id is distinct from old.tenant_id
     or new.created_by is distinct from old.created_by then
    raise exception using
      message = 'NODEX: the identity of a thread is immutable',
      errcode = '42501';
  end if;

  -- The participant list can grow but never shrink: a person who was in a
  -- clinical discussion stays in it, because what they were told cannot be
  -- un-told.
  if jsonb_array_length(new.participants) < jsonb_array_length(old.participants) then
    raise exception using
      message = 'NODEX: a participant cannot be removed from a thread',
      errcode = '42501';
  end if;

  if new.status = 'archived' and old.status <> 'archived' then
    new.last_message_at := coalesce(new.last_message_at, now());
  end if;

  return new;
end;
$$;

create trigger clinical_threads_guard
  before insert or update on public.clinical_threads
  for each row execute function nodex.tg_clinical_thread_guard();

create table public.clinical_messages (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  thread_id uuid not null references public.clinical_threads(id) on delete cascade,
  sender_id uuid not null references public.app_users(id) on delete restrict,
  body text not null check (length(btrim(body)) > 0),
  is_urgent boolean not null default false,
  created_at timestamptz not null default now()
);

comment on table public.clinical_messages is
  'A message in a clinical thread. Immutable: a message that could be edited after the fact is not a record of what was said.';

create index clinical_messages_thread_idx
  on public.clinical_messages (thread_id, created_at);

create trigger clinical_messages_retain before delete on public.clinical_messages
  for each row execute function nodex.tg_block_mutation();

create table public.clinical_attachments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  message_id uuid not null references public.clinical_messages(id) on delete cascade,
  file_name text not null check (length(btrim(file_name)) > 0),
  content_type text not null,
  size_bytes bigint not null check (size_bytes >= 0),
  storage_path text not null check (length(btrim(storage_path)) > 0),
  created_at timestamptz not null default now()
);

comment on table public.clinical_attachments is
  'A file attached to a clinical message. The path points into the clinical storage bucket; the file itself is reached through a short-lived signed link, never through a public URL.';

create index clinical_attachments_message_idx
  on public.clinical_attachments (message_id);

create trigger clinical_attachments_retain before delete on public.clinical_attachments
  for each row execute function nodex.tg_block_mutation();

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table public.clinical_threads enable row level security;
alter table public.clinical_threads force row level security;
alter table public.clinical_messages enable row level security;
alter table public.clinical_messages force row level security;
alter table public.clinical_attachments enable row level security;
alter table public.clinical_attachments force row level security;

-- A thread is readable by the people in it. Somebody who was not asked is
-- not shown the discussion, however senior they are.
create policy clinical_threads_select_participant on public.clinical_threads
  for select to authenticated
  using (
    nodex.has_permission(tenant_id, 'messaging.read')
    and participants @> jsonb_build_array(auth.uid()::text)
  );
create policy clinical_threads_insert_writer on public.clinical_threads
  for insert to authenticated
  with check (
    nodex.has_permission(tenant_id, 'messaging.send')
    and participants @> jsonb_build_array(auth.uid()::text)
  );
create policy clinical_threads_update_writer on public.clinical_threads
  for update to authenticated
  using (
    nodex.has_permission(tenant_id, 'messaging.send')
    and participants @> jsonb_build_array(auth.uid()::text)
  )
  with check (
    nodex.has_permission(tenant_id, 'messaging.send')
    and participants @> jsonb_build_array(auth.uid()::text)
  );

create policy clinical_messages_select_participant on public.clinical_messages
  for select to authenticated
  using (
    exists (
      select 1 from public.clinical_threads t
      where t.id = thread_id
        and t.participants @> jsonb_build_array(auth.uid()::text)
    )
  );
create policy clinical_messages_insert_participant on public.clinical_messages
  for insert to authenticated
  with check (
    nodex.has_permission(tenant_id, 'messaging.send')
    and exists (
      select 1 from public.clinical_threads t
      where t.id = thread_id
        and t.participants @> jsonb_build_array(auth.uid()::text)
    )
  );

create policy clinical_attachments_select_participant
  on public.clinical_attachments
  for select to authenticated
  using (
    exists (
      select 1
      from public.clinical_messages m
      join public.clinical_threads t on t.id = m.thread_id
      where m.id = message_id
        and t.participants @> jsonb_build_array(auth.uid()::text)
    )
  );

-- ---------------------------------------------------------------------------
-- Permissions
-- ---------------------------------------------------------------------------

insert into public.permissions
  (key, display_name, description, module_code, risk_tier, requires_online)
values
  ('messaging.read', 'Read clinical messages',
   'Read the clinical discussion threads the signed-in clinician takes part in.',
   'M43', 'high', false),
  ('messaging.send', 'Send clinical messages',
   'Start a clinical discussion thread and post to the threads you take part in.',
   'M43', 'high', false)
on conflict (key) do nothing;

insert into public.role_permissions (role_key, permission_key)
values
  ('hospital_super_admin', 'messaging.read'),
  ('hospital_super_admin', 'messaging.send'),
  ('medical_officer',      'messaging.read'),
  ('medical_officer',      'messaging.send'),
  ('nursing_staff',        'messaging.read'),
  ('nursing_staff',        'messaging.send'),
  ('pharmacist',           'messaging.read'),
  ('pharmacist',           'messaging.send'),
  ('lab_technician',       'messaging.read'),
  ('lab_technician',       'messaging.send'),
  ('billing_accounts',     'messaging.read')
on conflict do nothing;
