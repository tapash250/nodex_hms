-- NODEX Phase 3, Module 20: Physiotherapy & Rehabilitation.
--
-- Session scheduling drives the workflow: schedule -> start -> complete, or
-- cancel with a reason. Exercise regimens are prescribed per patient, and
-- recovery notes document progress against a session. RLS uses
-- membership-derived permissions, and FKs target app_users.

create table public.physio_sessions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  patient_id uuid not null references public.patients(id) on delete restrict,
  encounter_id uuid references public.clinical_encounters(id) on delete restrict,
  physiotherapist_id uuid not null references public.app_users(id) on delete restrict,
  session_code text not null check (length(btrim(session_code)) > 0),
  session_type text not null check (session_type in ('assessment','therapy','reassessment')),
  body_area text not null check (length(btrim(body_area)) > 0),
  status text not null default 'scheduled' check (status in ('scheduled','in_progress','completed','cancelled')),
  scheduled_at timestamptz not null,
  started_at timestamptz,
  completed_at timestamptz,
  cancelled_at timestamptz,
  cancellation_reason text,
  equipment_used text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, session_code),
  constraint physio_session_cancel_ck check ((status = 'cancelled' and cancelled_at is not null and cancellation_reason is not null) or status <> 'cancelled')
);
create index physio_sessions_patient_idx on public.physio_sessions(tenant_id, patient_id, scheduled_at desc);
create index physio_sessions_status_idx on public.physio_sessions(tenant_id, status, scheduled_at);

create table public.physio_exercise_plans (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  patient_id uuid not null references public.patients(id) on delete restrict,
  session_id uuid references public.physio_sessions(id) on delete restrict,
  prescribed_by uuid not null references public.app_users(id) on delete restrict,
  exercise_name text not null check (length(btrim(exercise_name)) > 0),
  sets_count integer not null default 3 check (sets_count > 0 and sets_count <= 100),
  reps_count integer not null check (reps_count > 0 and reps_count <= 1000),
  frequency_per_week integer not null check (frequency_per_week > 0 and frequency_per_week <= 7),
  duration_weeks integer not null check (duration_weeks > 0 and duration_weeks <= 52),
  instructions text,
  status text not null default 'active' check (status in ('active','completed','stopped')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index physio_exercise_plans_patient_idx on public.physio_exercise_plans(tenant_id, patient_id, created_at desc);

create table public.physio_recovery_notes (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  session_id uuid not null references public.physio_sessions(id) on delete restrict,
  recorded_by uuid not null references public.app_users(id) on delete restrict,
  content text not null check (length(btrim(content)) > 0),
  pain_score integer check (pain_score is null or (pain_score >= 0 and pain_score <= 10)),
  recorded_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index physio_recovery_notes_session_idx on public.physio_recovery_notes(session_id, recorded_at);

create trigger physio_sessions_set_updated_at before update on public.physio_sessions for each row execute function nodex.tg_set_updated_at();
create trigger physio_exercise_plans_set_updated_at before update on public.physio_exercise_plans for each row execute function nodex.tg_set_updated_at();
create trigger physio_recovery_notes_set_updated_at before update on public.physio_recovery_notes for each row execute function nodex.tg_set_updated_at();

create or replace function nodex.tg_physio_session_transition_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status in ('cancelled','completed') and new.status <> old.status then
    raise exception using message = 'NODEX: terminal physiotherapy sessions cannot transition', errcode = '42501';
  end if;
  if new.status = 'in_progress' and old.status <> 'scheduled' then
    raise exception using message = 'NODEX: physiotherapy sessions start only from the scheduled state', errcode = '42501';
  end if;
  if new.status = 'completed' and old.status <> 'in_progress' then
    raise exception using message = 'NODEX: physiotherapy sessions complete only from the in-progress state', errcode = '42501';
  end if;
  if new.status = 'cancelled' and (new.cancelled_at is null or new.cancellation_reason is null) then
    raise exception using message = 'NODEX: cancelling a physiotherapy session requires timestamp and reason', errcode = '22000';
  end if;
  return new;
end;
$$;
create trigger physio_sessions_transition_guard before update on public.physio_sessions for each row execute function nodex.tg_physio_session_transition_guard();

create or replace function nodex.tg_physio_plan_terminal_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status in ('completed','stopped') and new.status <> old.status then
    raise exception using message = 'NODEX: finished exercise plans cannot transition', errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger physio_exercise_plans_terminal_guard before update on public.physio_exercise_plans for each row execute function nodex.tg_physio_plan_terminal_guard();
create trigger physio_recovery_notes_append_only_delete before delete on public.physio_recovery_notes for each row execute function nodex.tg_block_mutation();

alter table public.physio_sessions enable row level security;
alter table public.physio_sessions force row level security;
alter table public.physio_exercise_plans enable row level security;
alter table public.physio_exercise_plans force row level security;
alter table public.physio_recovery_notes enable row level security;
alter table public.physio_recovery_notes force row level security;

create policy physio_sessions_select_member on public.physio_sessions for select to authenticated using (nodex.has_permission(tenant_id,'patient.read'));
create policy physio_sessions_insert_writer on public.physio_sessions for insert to authenticated with check (nodex.has_permission(tenant_id,'physio_session.write'));
create policy physio_sessions_update_writer on public.physio_sessions for update to authenticated using (nodex.has_permission(tenant_id,'physio_session.write')) with check (nodex.has_permission(tenant_id,'physio_session.write'));
create policy physio_exercise_plans_select_member on public.physio_exercise_plans for select to authenticated using (nodex.has_permission(tenant_id,'patient.read'));
create policy physio_exercise_plans_insert_writer on public.physio_exercise_plans for insert to authenticated with check (nodex.has_permission(tenant_id,'physio_exercise.write'));
create policy physio_exercise_plans_update_writer on public.physio_exercise_plans for update to authenticated using (nodex.has_permission(tenant_id,'physio_exercise.write')) with check (nodex.has_permission(tenant_id,'physio_exercise.write'));
create policy physio_recovery_notes_select_member on public.physio_recovery_notes for select to authenticated using (nodex.has_permission(tenant_id,'patient.read'));
create policy physio_recovery_notes_insert_writer on public.physio_recovery_notes for insert to authenticated with check (nodex.has_permission(tenant_id,'physio_note.write'));
create policy physio_recovery_notes_update_writer on public.physio_recovery_notes for update to authenticated using (nodex.has_permission(tenant_id,'physio_note.write')) with check (nodex.has_permission(tenant_id,'physio_note.write'));
