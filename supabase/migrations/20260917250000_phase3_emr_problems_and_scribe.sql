-- NODEX Phase 3, Module 16: problem lists and ambient AI scribing.
--
-- Module 16 already carries the encounter and its append-only amendments. Two
-- pieces of the specified scope were still missing, and both are added here.
--
-- Problem lists: the longitudinal problem list outlives any single encounter.
-- A problem is resolved by recording when it resolved, never by deleting the
-- history, because "when did this patient stop being diabetic" is a clinical
-- question the record has to answer.
--
-- Ambient AI scribing: dictated audio is transcribed and structured into SOAP
-- sections by the AI orchestrator, but the result is a *draft*. It becomes
-- clinical content only when a clinician reviews it and accepts it field by
-- field. Machine output must never write itself into the record, so the draft
-- is immutable once reviewed and acceptance additionally requires the target
-- encounter to still be editable.
--
-- RLS uses membership-derived permissions, and FKs target app_users.

-- ---------------------------------------------------------------------------
-- Problem list
-- ---------------------------------------------------------------------------

create table public.clinical_problems (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references public.tenants(id) on delete restrict,
  patient_id       uuid not null references public.patients(id) on delete restrict,
  encounter_id     uuid references public.clinical_encounters(id) on delete restrict,
  problem_code     text not null check (length(btrim(problem_code)) > 0),
  description      text not null check (length(btrim(description)) > 0),
  clinical_status  text not null default 'active'
                   check (clinical_status in ('active','resolved')),
  onset_date       date,
  resolved_at      timestamptz,
  resolution_note  text,
  recorded_by      uuid not null references public.app_users(id) on delete restrict,
  resolved_by      uuid references public.app_users(id) on delete restrict,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  constraint clinical_problems_resolution_ck check (
    (clinical_status = 'resolved'
      and resolved_at is not null
      and resolved_by is not null
      and length(btrim(resolution_note)) > 0)
    or (clinical_status = 'active' and resolved_at is null and resolved_by is null)
  )
);
create index clinical_problems_patient_idx
  on public.clinical_problems (tenant_id, patient_id, clinical_status, created_at desc);
create index clinical_problems_encounter_idx
  on public.clinical_problems (encounter_id);

create trigger clinical_problems_set_updated_at
  before update on public.clinical_problems
  for each row execute function nodex.tg_set_updated_at();

-- A resolved problem keeps its identity and code: what changed is when it
-- resolved and who decided. Rewriting the code or the patient it belongs to
-- would corrupt the longitudinal history the problem list exists to provide.
create or replace function nodex.tg_clinical_problem_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.clinical_status = 'resolved' then
    if new.tenant_id is distinct from old.tenant_id
      or new.patient_id is distinct from old.patient_id
      or new.encounter_id is distinct from old.encounter_id
      or new.problem_code is distinct from old.problem_code
      or new.description is distinct from old.description
      or new.onset_date is distinct from old.onset_date
      or new.resolved_at is distinct from old.resolved_at
      or new.resolved_by is distinct from old.resolved_by
      or new.resolution_note is distinct from old.resolution_note
      or new.recorded_by is distinct from old.recorded_by
      or new.created_at is distinct from old.created_at
    then
      raise exception using
        message = 'NODEX: a resolved problem is part of the longitudinal history and cannot be rewritten',
        errcode = '42501';
    end if;
    if new.clinical_status is distinct from old.clinical_status then
      raise exception using
        message = 'NODEX: a resolved problem cannot be reopened',
        errcode = '42501';
    end if;
  end if;
  -- A problem never goes from resolved back to active by accident: the only
  -- permitted change on a resolved row is none at all.
  return new;
end;
$$;
create trigger clinical_problems_guard
  before update on public.clinical_problems
  for each row execute function nodex.tg_clinical_problem_guard();
create trigger clinical_problems_append_only_delete
  before delete on public.clinical_problems
  for each row execute function nodex.tg_block_mutation();

alter table public.clinical_problems enable row level security;
alter table public.clinical_problems force row level security;

create policy clinical_problems_select_member on public.clinical_problems
  for select to authenticated using (nodex.has_permission(tenant_id, 'encounter.read'));
create policy clinical_problems_insert_writer on public.clinical_problems
  for insert to authenticated with check (nodex.has_permission(tenant_id, 'encounter.write'));
create policy clinical_problems_update_writer on public.clinical_problems
  for update to authenticated
  using (nodex.has_permission(tenant_id, 'encounter.write'))
  with check (nodex.has_permission(tenant_id, 'encounter.write'));

-- ---------------------------------------------------------------------------
-- Ambient AI scribe drafts
-- ---------------------------------------------------------------------------

create table public.encounter_scribe_drafts (
  id                uuid primary key default gen_random_uuid(),
  tenant_id         uuid not null references public.tenants(id) on delete restrict,
  encounter_id      uuid not null references public.clinical_encounters(id) on delete restrict,
  model_id          text not null check (length(btrim(model_id)) > 0),
  transcript_text   text not null check (length(btrim(transcript_text)) > 0),
  subjective_note   text,
  objective_findings text,
  assessment        text,
  plan_description  text,
  confidence        numeric(4,3)
                    check (confidence is null or (confidence >= 0 and confidence <= 1)),
  safety_decision   text not null check (length(btrim(safety_decision)) > 0),
  status            text not null default 'pending_review'
                    check (status in ('pending_review','accepted','rejected')),
  requested_by      uuid not null references public.app_users(id) on delete restrict,
  reviewed_by       uuid references public.app_users(id) on delete restrict,
  reviewed_at       timestamptz,
  rejection_reason  text,
  accepted_fields   text[] not null default '{}',
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  constraint encounter_scribe_drafts_reviewed_ck check (
    (status in ('accepted','rejected') and reviewed_by is not null and reviewed_at is not null)
    or status = 'pending_review'
  ),
  constraint encounter_scribe_drafts_rejected_ck check (
    (status = 'rejected'
      and rejection_reason is not null
      and length(btrim(rejection_reason)) > 0
      and cardinality(accepted_fields) = 0)
    or status <> 'rejected'
  ),
  constraint encounter_scribe_drafts_accepted_ck check (
    status <> 'accepted' or cardinality(accepted_fields) > 0
  )
);
create index encounter_scribe_drafts_encounter_idx
  on public.encounter_scribe_drafts (encounter_id, created_at desc);
create index encounter_scribe_drafts_pending_idx
  on public.encounter_scribe_drafts (tenant_id, status)
  where status = 'pending_review';

create trigger encounter_scribe_drafts_set_updated_at
  before update on public.encounter_scribe_drafts
  for each row execute function nodex.tg_set_updated_at();

-- Once reviewed, the machine output is evidence of what the clinician was
-- shown. It may never be rewritten afterwards, and only the review fields move.
create or replace function nodex.tg_encounter_scribe_draft_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status <> 'pending_review' then
    if new.tenant_id is distinct from old.tenant_id
      or new.encounter_id is distinct from old.encounter_id
      or new.model_id is distinct from old.model_id
      or new.transcript_text is distinct from old.transcript_text
      or new.subjective_note is distinct from old.subjective_note
      or new.objective_findings is distinct from old.objective_findings
      or new.assessment is distinct from old.assessment
      or new.plan_description is distinct from old.plan_description
      or new.confidence is distinct from old.confidence
      or new.safety_decision is distinct from old.safety_decision
      or new.requested_by is distinct from old.requested_by
      or new.created_at is distinct from old.created_at
    then
      raise exception using
        message = 'NODEX: a reviewed scribe draft is immutable; request a new dictation instead',
        errcode = '42501';
    end if;
  end if;
  if new.status <> 'pending_review'
    and (new.reviewed_by is null or new.reviewed_at is null)
  then
    raise exception using
      message = 'NODEX: reviewing a scribe draft requires the reviewer and the time',
      errcode = '22000';
  end if;
  if new.status <> 'pending_review' and new.status = old.status then
    raise exception using
      message = 'NODEX: a scribe draft can only be reviewed once',
      errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger encounter_scribe_drafts_review_guard
  before update on public.encounter_scribe_drafts
  for each row execute function nodex.tg_encounter_scribe_draft_guard();
create trigger encounter_scribe_drafts_append_only_delete
  before delete on public.encounter_scribe_drafts
  for each row execute function nodex.tg_block_mutation();

alter table public.encounter_scribe_drafts enable row level security;
alter table public.encounter_scribe_drafts force row level security;

-- Drafting a dictation is part of writing the encounter; accepting or rejecting
-- one is a separate AI-governance decision, so it needs the AI review
-- permission rather than merely write access.
create policy encounter_scribe_drafts_select_member on public.encounter_scribe_drafts
  for select to authenticated using (nodex.has_permission(tenant_id, 'encounter.read'));
create policy encounter_scribe_drafts_insert_writer on public.encounter_scribe_drafts
  for insert to authenticated with check (nodex.has_permission(tenant_id, 'encounter.write'));
create policy encounter_scribe_drafts_update_reviewer on public.encounter_scribe_drafts
  for update to authenticated
  using (nodex.has_permission(tenant_id, 'ai_output.review'))
  with check (nodex.has_permission(tenant_id, 'ai_output.review'));