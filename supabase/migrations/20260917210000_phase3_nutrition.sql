-- NODEX Phase 3, Module 21: Dietetics & Clinical Nutrition.
--
-- Assessment -> meal plan -> approval -> intake. A finalized assessment is
-- immutable; a meal plan is authored as a seven-day cycle and is frozen once
-- approved or rejected, including its day rows. AI-generated plans record
-- their generator and can only take effect through explicit clinical
-- approval. RLS uses membership-derived permissions, and FKs target app_users.

create table public.diet_assessments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  patient_id uuid not null references public.patients(id) on delete restrict,
  encounter_id uuid references public.clinical_encounters(id) on delete restrict,
  assessed_by uuid not null references public.app_users(id) on delete restrict,
  assessment_type text not null check (assessment_type in ('initial','reassessment')),
  weight_kg numeric check (weight_kg is null or (weight_kg > 0 and weight_kg <= 500)),
  height_cm numeric check (height_cm is null or (height_cm > 0 and height_cm <= 260)),
  nutrition_diagnosis text not null check (length(btrim(nutrition_diagnosis)) > 0),
  restrictions text,
  status text not null default 'draft' check (status in ('draft','finalized')),
  assessed_at timestamptz not null default now(),
  finalized_at timestamptz,
  finalized_by uuid references public.app_users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint diet_assessment_finalized_ck check ((status = 'finalized' and finalized_at is not null and finalized_by is not null) or status = 'draft')
);
create index diet_assessments_patient_idx on public.diet_assessments(tenant_id, patient_id, assessed_at desc);

create table public.diet_meal_plans (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  patient_id uuid not null references public.patients(id) on delete restrict,
  assessment_id uuid not null references public.diet_assessments(id) on delete restrict,
  name text not null check (length(btrim(name)) > 0),
  plan_source text not null check (plan_source in ('ai_generated','clinician_authored')),
  cycle_days integer not null default 7 check (cycle_days = 7),
  status text not null default 'draft' check (status in ('draft','approved','rejected')),
  generated_by uuid references public.app_users(id) on delete restrict,
  generated_at timestamptz,
  approved_by uuid references public.app_users(id) on delete restrict,
  approved_at timestamptz,
  rejected_by uuid references public.app_users(id) on delete restrict,
  rejected_at timestamptz,
  rejection_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint diet_plan_generation_ck check (plan_source <> 'ai_generated' or (generated_by is not null and generated_at is not null)),
  constraint diet_plan_approved_ck check ((status = 'approved' and approved_by is not null and approved_at is not null) or status <> 'approved'),
  constraint diet_plan_rejected_ck check ((status = 'rejected' and rejected_by is not null and rejected_at is not null and length(btrim(rejection_reason)) > 0) or status <> 'rejected')
);
create index diet_meal_plans_patient_idx on public.diet_meal_plans(tenant_id, patient_id, created_at desc);
create unique index diet_meal_plans_assessment_uniq on public.diet_meal_plans(tenant_id, assessment_id);

create table public.diet_meal_plan_days (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  meal_plan_id uuid not null references public.diet_meal_plans(id) on delete restrict,
  day_number integer not null check (day_number >= 1 and day_number <= 7),
  breakfast text not null check (length(btrim(breakfast)) > 0),
  lunch text not null check (length(btrim(lunch)) > 0),
  dinner text not null check (length(btrim(dinner)) > 0),
  snacks text,
  calories_kcal integer not null check (calories_kcal > 0 and calories_kcal <= 5000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (meal_plan_id, day_number)
);
create index diet_meal_plan_days_plan_idx on public.diet_meal_plan_days(meal_plan_id, day_number);

create table public.diet_intake_logs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  patient_id uuid not null references public.patients(id) on delete restrict,
  meal_plan_day_id uuid not null references public.diet_meal_plan_days(id) on delete restrict,
  meal_slot text not null check (meal_slot in ('breakfast','lunch','dinner','snacks')),
  portion_consumed_pct integer not null check (portion_consumed_pct >= 0 and portion_consumed_pct <= 100),
  recorded_by uuid not null references public.app_users(id) on delete restrict,
  recorded_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index diet_intake_logs_day_idx on public.diet_intake_logs(meal_plan_day_id, recorded_at);

create trigger diet_assessments_set_updated_at before update on public.diet_assessments for each row execute function nodex.tg_set_updated_at();
create trigger diet_meal_plans_set_updated_at before update on public.diet_meal_plans for each row execute function nodex.tg_set_updated_at();
create trigger diet_meal_plan_days_set_updated_at before update on public.diet_meal_plan_days for each row execute function nodex.tg_set_updated_at();
create trigger diet_intake_logs_set_updated_at before update on public.diet_intake_logs for each row execute function nodex.tg_set_updated_at();

create or replace function nodex.tg_diet_assessment_immutable_after_finalize()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status = 'finalized' then
    if new.tenant_id is distinct from old.tenant_id or new.patient_id is distinct from old.patient_id or new.encounter_id is distinct from old.encounter_id or new.assessed_by is distinct from old.assessed_by or new.assessment_type is distinct from old.assessment_type or new.weight_kg is distinct from old.weight_kg or new.height_cm is distinct from old.height_cm or new.nutrition_diagnosis is distinct from old.nutrition_diagnosis or new.restrictions is distinct from old.restrictions or new.finalized_by is distinct from old.finalized_by or new.finalized_at is distinct from old.finalized_at then
      raise exception using message = 'NODEX: finalized diet assessments are immutable', errcode = '42501';
    end if;
    if new.status <> old.status then
      raise exception using message = 'NODEX: finalized diet assessments are immutable', errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;
create trigger diet_assessments_immutable_after_finalize before update on public.diet_assessments for each row execute function nodex.tg_diet_assessment_immutable_after_finalize();

create or replace function nodex.tg_diet_meal_plan_transition_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status in ('approved','rejected') and new.status <> old.status then
    raise exception using message = 'NODEX: decided meal plans cannot transition', errcode = '42501';
  end if;
  if new.status in ('approved','rejected') and old.status <> 'draft' then
    raise exception using message = 'NODEX: meal plans are approved or rejected from the draft state only', errcode = '42501';
  end if;
  if new.status = 'rejected' and length(btrim(coalesce(new.rejection_reason, ''))) = 0 then
    raise exception using message = 'NODEX: rejecting a meal plan requires a reason', errcode = '22000';
  end if;
  return new;
end;
$$;
create trigger diet_meal_plans_transition_guard before update on public.diet_meal_plans for each row execute function nodex.tg_diet_meal_plan_transition_guard();

create or replace function nodex.tg_diet_meal_plan_days_frozen()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  plan_id uuid;
  plan_status text;
begin
  if tg_op = 'DELETE' then
    plan_id := old.meal_plan_id;
  else
    plan_id := new.meal_plan_id;
  end if;
  select status into plan_status from public.diet_meal_plans where id = plan_id;
  if plan_status is distinct from 'draft' then
    raise exception using message = 'NODEX: meal plan days are frozen once the plan leaves draft', errcode = '42501';
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;
create trigger diet_meal_plan_days_frozen before update or delete on public.diet_meal_plan_days for each row execute function nodex.tg_diet_meal_plan_days_frozen();
create trigger diet_assessments_append_only_delete before delete on public.diet_assessments for each row execute function nodex.tg_block_mutation();
create trigger diet_intake_logs_append_only_delete before delete on public.diet_intake_logs for each row execute function nodex.tg_block_mutation();

alter table public.diet_assessments enable row level security;
alter table public.diet_assessments force row level security;
alter table public.diet_meal_plans enable row level security;
alter table public.diet_meal_plans force row level security;
alter table public.diet_meal_plan_days enable row level security;
alter table public.diet_meal_plan_days force row level security;
alter table public.diet_intake_logs enable row level security;
alter table public.diet_intake_logs force row level security;

create policy diet_assessments_select_member on public.diet_assessments for select to authenticated using (nodex.has_permission(tenant_id,'patient.read'));
create policy diet_assessments_insert_writer on public.diet_assessments for insert to authenticated with check (nodex.has_permission(tenant_id,'diet_assessment.write'));
create policy diet_assessments_update_writer on public.diet_assessments for update to authenticated using (nodex.has_permission(tenant_id,'diet_assessment.write')) with check (nodex.has_permission(tenant_id,'diet_assessment.write'));
-- Plan transitions are approver-gated: authoring inserts, deciding updates.
create policy diet_meal_plans_select_member on public.diet_meal_plans for select to authenticated using (nodex.has_permission(tenant_id,'patient.read'));
create policy diet_meal_plans_insert_writer on public.diet_meal_plans for insert to authenticated with check (nodex.has_permission(tenant_id,'diet_plan.write'));
create policy diet_meal_plans_update_approver on public.diet_meal_plans for update to authenticated using (nodex.has_permission(tenant_id,'diet_plan.approve')) with check (nodex.has_permission(tenant_id,'diet_plan.approve'));
create policy diet_meal_plan_days_select_member on public.diet_meal_plan_days for select to authenticated using (nodex.has_permission(tenant_id,'patient.read'));
create policy diet_meal_plan_days_insert_writer on public.diet_meal_plan_days for insert to authenticated with check (nodex.has_permission(tenant_id,'diet_plan.write'));
create policy diet_meal_plan_days_update_writer on public.diet_meal_plan_days for update to authenticated using (nodex.has_permission(tenant_id,'diet_plan.write')) with check (nodex.has_permission(tenant_id,'diet_plan.write'));
create policy diet_intake_logs_select_member on public.diet_intake_logs for select to authenticated using (nodex.has_permission(tenant_id,'patient.read'));
create policy diet_intake_logs_insert_recorder on public.diet_intake_logs for insert to authenticated with check (nodex.has_permission(tenant_id,'diet_intake.record'));
create policy diet_intake_logs_update_recorder on public.diet_intake_logs for update to authenticated using (nodex.has_permission(tenant_id,'diet_intake.record')) with check (nodex.has_permission(tenant_id,'diet_intake.record'));
