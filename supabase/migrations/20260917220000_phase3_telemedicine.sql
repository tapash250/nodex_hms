-- NODEX Phase 3, Module 22: Telemedicine & Virtual Care (WebRTC).
--
-- Scheduling -> waiting room -> in call -> completed, with no-show and
-- cancellation as terminal exits. Live vitals overlays are observations taken
-- while the call is in progress, and a completed consultation is archived with
-- recorded consent; recording media lives in encrypted object storage and only
-- a reference is stored here. RLS uses membership-derived permissions, and FKs
-- target app_users.

create table public.tele_consultations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  patient_id uuid not null references public.patients(id) on delete restrict,
  encounter_id uuid references public.clinical_encounters(id) on delete restrict,
  clinician_id uuid not null references public.app_users(id) on delete restrict,
  booked_by uuid not null references public.app_users(id) on delete restrict,
  visit_code text not null check (length(btrim(visit_code)) > 0),
  channel text not null check (channel in ('audio','video')),
  status text not null default 'scheduled' check (status in ('scheduled','waiting','in_call','completed','cancelled','no_show')),
  reason text,
  scheduled_at timestamptz not null,
  waiting_at timestamptz,
  started_at timestamptz,
  completed_at timestamptz,
  cancelled_at timestamptz,
  cancellation_reason text,
  no_show_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, visit_code),
  constraint tele_consultation_cancel_ck check ((status = 'cancelled' and cancelled_at is not null and cancellation_reason is not null) or status <> 'cancelled'),
  constraint tele_consultation_no_show_ck check ((status = 'no_show' and no_show_at is not null) or status <> 'no_show')
);
create index tele_consultations_patient_idx on public.tele_consultations(tenant_id, patient_id, scheduled_at desc);
create index tele_consultations_status_idx on public.tele_consultations(tenant_id, status, scheduled_at);

create table public.tele_vitals_overlays (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  consultation_id uuid not null references public.tele_consultations(id) on delete restrict,
  observed_by uuid not null references public.app_users(id) on delete restrict,
  heart_rate_bpm integer check (heart_rate_bpm is null or (heart_rate_bpm >= 20 and heart_rate_bpm <= 250)),
  spo2_pct numeric check (spo2_pct is null or (spo2_pct >= 50 and spo2_pct <= 100)),
  temperature_c numeric check (temperature_c is null or (temperature_c >= 30 and temperature_c <= 45)),
  respiratory_rate integer check (respiratory_rate is null or (respiratory_rate >= 4 and respiratory_rate <= 60)),
  notes text,
  observed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index tele_vitals_overlays_consultation_idx on public.tele_vitals_overlays(consultation_id, observed_at);

create table public.tele_consultation_archives (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  consultation_id uuid not null references public.tele_consultations(id) on delete restrict,
  archived_by uuid not null references public.app_users(id) on delete restrict,
  duration_seconds integer not null check (duration_seconds > 0 and duration_seconds <= 28800),
  recording_reference text check (recording_reference is null or length(btrim(recording_reference)) > 0),
  transcript_reference text check (transcript_reference is null or length(btrim(transcript_reference)) > 0),
  consent_recorded boolean not null default false,
  archived_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, consultation_id),
  constraint tele_archive_consent_ck check (consent_recorded)
);
create index tele_consultation_archives_consultation_idx on public.tele_consultation_archives(consultation_id, archived_at desc);

create trigger tele_consultations_set_updated_at before update on public.tele_consultations for each row execute function nodex.tg_set_updated_at();
create trigger tele_vitals_overlays_set_updated_at before update on public.tele_vitals_overlays for each row execute function nodex.tg_set_updated_at();
create trigger tele_consultation_archives_set_updated_at before update on public.tele_consultation_archives for each row execute function nodex.tg_set_updated_at();

create or replace function nodex.tg_tele_consultation_transition_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status in ('completed','cancelled','no_show') and new.status <> old.status then
    raise exception using message = 'NODEX: closed telemedicine consultations cannot transition', errcode = '42501';
  end if;
  if new.status = 'waiting' and old.status <> 'scheduled' then
    raise exception using message = 'NODEX: the waiting room admits only scheduled consultations', errcode = '42501';
  end if;
  if new.status = 'in_call' and old.status <> 'waiting' then
    raise exception using message = 'NODEX: a call starts only from the waiting room', errcode = '42501';
  end if;
  if new.status = 'completed' and old.status <> 'in_call' then
    raise exception using message = 'NODEX: a consultation completes only from an in-call state', errcode = '42501';
  end if;
  if new.status = 'no_show' and old.status not in ('scheduled','waiting') then
    raise exception using message = 'NODEX: a no-show is recorded only before the call starts', errcode = '42501';
  end if;
  if new.status = 'cancelled' and (new.cancelled_at is null or new.cancellation_reason is null) then
    raise exception using message = 'NODEX: cancelling a telemedicine consultation requires timestamp and reason', errcode = '22000';
  end if;
  return new;
end;
$$;
create trigger tele_consultations_transition_guard before update on public.tele_consultations for each row execute function nodex.tg_tele_consultation_transition_guard();

create or replace function nodex.tg_tele_vitals_requires_in_call()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  consultation_status text;
begin
  select status into consultation_status from public.tele_consultations where id = new.consultation_id;
  if consultation_status is distinct from 'in_call' then
    raise exception using message = 'NODEX: live vitals are observed only while the call is in progress', errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger tele_vitals_overlays_requires_in_call before insert or update on public.tele_vitals_overlays for each row execute function nodex.tg_tele_vitals_requires_in_call();

create or replace function nodex.tg_tele_archive_requires_completed()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  consultation_status text;
begin
  select status into consultation_status from public.tele_consultations where id = new.consultation_id;
  if consultation_status is distinct from 'completed' then
    raise exception using message = 'NODEX: only a completed consultation can be archived', errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger tele_consultation_archives_requires_completed before insert or update on public.tele_consultation_archives for each row execute function nodex.tg_tele_archive_requires_completed();
create trigger tele_consultation_archives_append_only_delete before delete on public.tele_consultation_archives for each row execute function nodex.tg_block_mutation();

alter table public.tele_consultations enable row level security;
alter table public.tele_consultations force row level security;
alter table public.tele_vitals_overlays enable row level security;
alter table public.tele_vitals_overlays force row level security;
alter table public.tele_consultation_archives enable row level security;
alter table public.tele_consultation_archives force row level security;

create policy tele_consultations_select_member on public.tele_consultations for select to authenticated using (nodex.has_permission(tenant_id,'patient.read'));
create policy tele_consultations_insert_writer on public.tele_consultations for insert to authenticated with check (nodex.has_permission(tenant_id,'tele_consultation.write'));
create policy tele_consultations_update_writer on public.tele_consultations for update to authenticated using (nodex.has_permission(tenant_id,'tele_consultation.write')) with check (nodex.has_permission(tenant_id,'tele_consultation.write'));
create policy tele_vitals_overlays_select_member on public.tele_vitals_overlays for select to authenticated using (nodex.has_permission(tenant_id,'patient.read'));
create policy tele_vitals_overlays_insert_recorder on public.tele_vitals_overlays for insert to authenticated with check (nodex.has_permission(tenant_id,'tele_vitals.record'));
create policy tele_vitals_overlays_update_recorder on public.tele_vitals_overlays for update to authenticated using (nodex.has_permission(tenant_id,'tele_vitals.record')) with check (nodex.has_permission(tenant_id,'tele_vitals.record'));
create policy tele_consultation_archives_select_member on public.tele_consultation_archives for select to authenticated using (nodex.has_permission(tenant_id,'patient.read'));
create policy tele_consultation_archives_insert_archivist on public.tele_consultation_archives for insert to authenticated with check (nodex.has_permission(tenant_id,'tele_archive.write'));
create policy tele_consultation_archives_update_archivist on public.tele_consultation_archives for update to authenticated using (nodex.has_permission(tenant_id,'tele_archive.write')) with check (nodex.has_permission(tenant_id,'tele_archive.write'));
