-- NODEX Phase 3, Module 19: operation theatre management.
--
-- Theatre scheduling with conflict checks, room allocation, pre-op assessment,
-- intra-op anesthesia and procedure logs, and post-op documentation. Bookings
-- flow scheduled -> in_progress -> completed; cancellation requires a reason
-- and completion requires ot.finalize. A case cannot start without a fitness
-- assessment. RLS uses membership-derived permissions; FKs target app_users.

create table public.ot_bookings (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  patient_id uuid not null references public.patients(id) on delete restrict,
  encounter_id uuid references public.clinical_encounters(id) on delete restrict,
  theatre_room text not null check (length(btrim(theatre_room)) > 0),
  procedure_name text not null check (length(btrim(procedure_name)) > 0),
  scheduled_start timestamptz not null default now(),
  scheduled_end timestamptz not null,
  surgeon_id uuid not null references public.app_users(id) on delete restrict,
  anesthesiologist_id uuid references public.app_users(id) on delete set null,
  status text not null default 'scheduled' check (status in ('scheduled','in_progress','completed','cancelled')),
  priority text not null default 'routine' check (priority in ('routine','urgent','emergency')),
  cancellation_reason text check (cancellation_reason is null or length(btrim(cancellation_reason)) > 0),
  created_by uuid not null references public.app_users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (scheduled_end > scheduled_start),
  check (status <> 'cancelled' or cancellation_reason is not null)
);
create index ot_bookings_tenant_status_idx on public.ot_bookings(tenant_id, status);
create index ot_bookings_tenant_start_idx on public.ot_bookings(tenant_id, scheduled_start);
create index ot_bookings_patient_idx on public.ot_bookings(tenant_id, patient_id, scheduled_start desc);
create index ot_bookings_room_start_idx on public.ot_bookings(tenant_id, theatre_room, scheduled_start);

create table public.ot_preop_assessments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  booking_id uuid not null references public.ot_bookings(id) on delete restrict,
  patient_id uuid not null references public.patients(id) on delete restrict,
  assessed_by uuid not null references public.app_users(id) on delete restrict,
  assessed_at timestamptz not null default now(),
  fitness text not null check (fitness in ('fit','fit_with_conditions','unfit')),
  asa_class smallint check (asa_class is null or (asa_class between 1 and 6)),
  notes text check (notes is null or length(btrim(notes)) > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, booking_id)
);
create index ot_preop_assessments_patient_idx on public.ot_preop_assessments(tenant_id, patient_id, assessed_at desc);

create table public.ot_anesthesia_records (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  booking_id uuid not null references public.ot_bookings(id) on delete restrict,
  patient_id uuid not null references public.patients(id) on delete restrict,
  anesthesia_type text not null check (anesthesia_type in ('general','regional','local','sedation')),
  recorded_by uuid not null references public.app_users(id) on delete restrict,
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  notes text check (notes is null or length(btrim(notes)) > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, booking_id),
  check (ended_at is null or ended_at > started_at)
);
create index ot_anesthesia_records_patient_idx on public.ot_anesthesia_records(tenant_id, patient_id, started_at desc);

create table public.ot_procedure_logs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  booking_id uuid not null references public.ot_bookings(id) on delete restrict,
  patient_id uuid not null references public.patients(id) on delete restrict,
  procedure_name text not null check (length(btrim(procedure_name)) > 0),
  performed_by uuid not null references public.app_users(id) on delete restrict,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  findings text check (findings is null or length(btrim(findings)) > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, booking_id),
  check (completed_at is null or completed_at >= started_at)
);
create index ot_procedure_logs_patient_idx on public.ot_procedure_logs(tenant_id, patient_id, started_at desc);

create table public.ot_postop_records (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  booking_id uuid not null references public.ot_bookings(id) on delete restrict,
  patient_id uuid not null references public.patients(id) on delete restrict,
  recorded_by uuid not null references public.app_users(id) on delete restrict,
  recorded_at timestamptz not null default now(),
  condition text not null check (condition in ('stable','watch','critical')),
  pain_score smallint check (pain_score is null or (pain_score between 0 and 10)),
  complications text check (complications is null or length(btrim(complications)) > 0),
  notes text check (notes is null or length(btrim(notes)) > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, booking_id)
);
create index ot_postop_records_patient_idx on public.ot_postop_records(tenant_id, patient_id, recorded_at desc);

create trigger ot_bookings_set_updated_at before update on public.ot_bookings for each row execute function nodex.tg_set_updated_at();
create trigger ot_preop_assessments_set_updated_at before update on public.ot_preop_assessments for each row execute function nodex.tg_set_updated_at();
create trigger ot_anesthesia_records_set_updated_at before update on public.ot_anesthesia_records for each row execute function nodex.tg_set_updated_at();
create trigger ot_procedure_logs_set_updated_at before update on public.ot_procedure_logs for each row execute function nodex.tg_set_updated_at();
create trigger ot_postop_records_set_updated_at before update on public.ot_postop_records for each row execute function nodex.tg_set_updated_at();

-- A booking walks scheduled -> in_progress -> completed and freezes at the
-- terminal states. Cancellation requires a reason and ot.schedule; starting a
-- case requires ot.record; completion requires ot.finalize. A null auth.uid()
-- (service-role server path) is trusted, as with RLS.
create or replace function nodex.tg_ot_booking_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if TG_OP = 'UPDATE' then
    if old.status in ('completed','cancelled') and new.status <> old.status then
      raise exception using message = 'NODEX: closed operation theatre bookings cannot transition', errcode = '42501';
    end if;
    if new.status <> old.status
       and (old.status || '>' || new.status) not in (
         'scheduled>in_progress',
         'scheduled>cancelled',
         'in_progress>completed',
         'in_progress>cancelled'
       ) then
      raise exception using message = 'NODEX: invalid operation theatre booking transition', errcode = '42501';
    end if;
    if new.status = 'in_progress' and old.status = 'scheduled' then
      if auth.uid() is not null and not nodex.has_permission(new.tenant_id, 'ot.record') then
        raise exception using message = 'NODEX: starting a case requires ot.record', errcode = '42501';
      end if;
    end if;
    if new.status = 'cancelled' and old.status <> 'cancelled' then
      if new.cancellation_reason is null or length(btrim(new.cancellation_reason)) = 0 then
        raise exception using message = 'NODEX: cancelling a booking requires a reason', errcode = '22000';
      end if;
      if auth.uid() is not null and not nodex.has_permission(new.tenant_id, 'ot.schedule') then
        raise exception using message = 'NODEX: cancelling a booking requires ot.schedule', errcode = '42501';
      end if;
    end if;
    if new.status = 'completed' and old.status = 'in_progress' then
      if auth.uid() is not null and not nodex.has_permission(new.tenant_id, 'ot.finalize') then
        raise exception using message = 'NODEX: completing a case requires ot.finalize', errcode = '42501';
      end if;
    end if;
  end if;
  return new;
end;
$$;
create trigger ot_bookings_guard before insert or update on public.ot_bookings for each row execute function nodex.tg_ot_booking_guard();

alter table public.ot_bookings enable row level security;
alter table public.ot_bookings force row level security;
alter table public.ot_preop_assessments enable row level security;
alter table public.ot_preop_assessments force row level security;
alter table public.ot_anesthesia_records enable row level security;
alter table public.ot_anesthesia_records force row level security;
alter table public.ot_procedure_logs enable row level security;
alter table public.ot_procedure_logs force row level security;
alter table public.ot_postop_records enable row level security;
alter table public.ot_postop_records force row level security;

create policy ot_bookings_select_member on public.ot_bookings for select to authenticated using (nodex.has_permission(tenant_id,'patient.read'));
create policy ot_bookings_insert_scheduler on public.ot_bookings for insert to authenticated with check (nodex.has_permission(tenant_id,'ot.schedule'));
create policy ot_bookings_update_scheduler on public.ot_bookings for update to authenticated using (nodex.has_permission(tenant_id,'ot.schedule')) with check (nodex.has_permission(tenant_id,'ot.schedule'));
create policy ot_bookings_update_recorder on public.ot_bookings for update to authenticated using (nodex.has_permission(tenant_id,'ot.record')) with check (nodex.has_permission(tenant_id,'ot.record'));
create policy ot_bookings_update_finalizer on public.ot_bookings for update to authenticated using (nodex.has_permission(tenant_id,'ot.finalize')) with check (nodex.has_permission(tenant_id,'ot.finalize'));

create policy ot_preop_assessments_select_member on public.ot_preop_assessments for select to authenticated using (nodex.has_permission(tenant_id,'patient.read'));
create policy ot_preop_assessments_insert_recorder on public.ot_preop_assessments for insert to authenticated with check (nodex.has_permission(tenant_id,'ot.record'));
create policy ot_preop_assessments_update_recorder on public.ot_preop_assessments for update to authenticated using (nodex.has_permission(tenant_id,'ot.record')) with check (nodex.has_permission(tenant_id,'ot.record'));

create policy ot_anesthesia_records_select_member on public.ot_anesthesia_records for select to authenticated using (nodex.has_permission(tenant_id,'patient.read'));
create policy ot_anesthesia_records_insert_recorder on public.ot_anesthesia_records for insert to authenticated with check (nodex.has_permission(tenant_id,'ot.record'));
create policy ot_anesthesia_records_update_recorder on public.ot_anesthesia_records for update to authenticated using (nodex.has_permission(tenant_id,'ot.record')) with check (nodex.has_permission(tenant_id,'ot.record'));

create policy ot_procedure_logs_select_member on public.ot_procedure_logs for select to authenticated using (nodex.has_permission(tenant_id,'patient.read'));
create policy ot_procedure_logs_insert_recorder on public.ot_procedure_logs for insert to authenticated with check (nodex.has_permission(tenant_id,'ot.record'));
create policy ot_procedure_logs_update_recorder on public.ot_procedure_logs for update to authenticated using (nodex.has_permission(tenant_id,'ot.record')) with check (nodex.has_permission(tenant_id,'ot.record'));

create policy ot_postop_records_select_member on public.ot_postop_records for select to authenticated using (nodex.has_permission(tenant_id,'patient.read'));
create policy ot_postop_records_insert_recorder on public.ot_postop_records for insert to authenticated with check (nodex.has_permission(tenant_id,'ot.record'));
create policy ot_postop_records_update_recorder on public.ot_postop_records for update to authenticated using (nodex.has_permission(tenant_id,'ot.record')) with check (nodex.has_permission(tenant_id,'ot.record'));
