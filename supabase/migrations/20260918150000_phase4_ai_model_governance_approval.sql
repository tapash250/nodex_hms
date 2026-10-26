-- Module 39: AI model approval and activation guard.
--
-- The registry has carried the governance invariant since Phase 1: a model
-- cannot be APPROVED or ACTIVE without a passed evaluation, a recorded
-- evaluation-set revision and a named approver. Until now only a server-side
-- writer could satisfy it, and no product surface could exercise it.
--
-- This migration opens the narrow client path the governance screen needs and
-- closes it behind three independent gates:
--
--   1. RLS admits UPDATE only to a principal holding `ai_governance.administer`
--      in an active membership. The permission is online-only, so the offline
--      permission subset never contains it.
--   2. The lifecycle trigger admits only forward transitions, freezes model
--      identity and capability, and refuses an approval that does not name the
--      caller as approver.
--   3. The existing activation constraint still refuses APPROVED/ACTIVE without
--      evaluation evidence and approval, whichever path wrote the row.
--
-- A model is configuration, not a clinical record: it has no tenant_id and is
-- replicated to every device as read-only configuration. Approval is therefore
-- checked across the caller's active memberships rather than against one
-- tenant.

-- True when the caller holds the permission in any active membership. Used only
-- for global configuration tables that have no tenant column to scope against.
create or replace function nodex.has_permission_anywhere(p_permission_key text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.memberships m
    join public.role_permissions rp on rp.role_key = m.role_key
    where m.user_id = auth.uid()
      and m.status = 'active'
      and m.valid_from <= now()
      and (m.valid_until is null or m.valid_until > now())
      and rp.permission_key = p_permission_key
  );
$$;

comment on function nodex.has_permission_anywhere(text) is
  'True when the caller holds the permission in any active membership. Reserved for global configuration tables with no tenant column.';

grant execute on function nodex.has_permission_anywhere(text) to authenticated;

-- Governance writes are admitted only to an administrator. The trigger below
-- narrows what an admitted update may change; RLS alone cannot restrict
-- columns.
create policy ai_model_registry_update_governance on public.ai_model_registry
  for update to authenticated
  using (nodex.has_permission_anywhere('ai_governance.administer'))
  with check (nodex.has_permission_anywhere('ai_governance.administer'));

-- The lifecycle gate. Forward-only, evidence-bound, and actor-bound: an
-- approval is a statement by a named person, so the row must name the caller,
-- not a colleague who is not present.
create or replace function nodex.tg_ai_model_governance_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_service boolean := nodex.is_service_role();
begin
  if old.lifecycle_status = 'retired' then
    raise exception using
      message = 'NODEX: a retired model is final; register a new model revision',
      errcode = '42501';
  end if;

  -- What the model is cannot change through a governance transition. A new
  -- capability is a new revision with its own evaluation.
  if new.model_key is distinct from old.model_key
     or new.provider is distinct from old.provider
     or new.provider_model_id is distinct from old.provider_model_id
     or new.model_revision is distinct from old.model_revision
     or new.modality is distinct from old.modality
     or new.clinical_risk_tier is distinct from old.clinical_risk_tier
     or new.privacy_class is distinct from old.privacy_class
     or new.context_window is distinct from old.context_window
     or new.max_output_tokens is distinct from old.max_output_tokens
     or new.supports_structured_json is distinct from old.supports_structured_json
     or new.supports_tool_calling is distinct from old.supports_tool_calling
     or new.supports_vision is distinct from old.supports_vision
     or new.latency_target_ms is distinct from old.latency_target_ms
     or new.memory_requirement_mb is distinct from old.memory_requirement_mb
  then
    raise exception using
      message = 'NODEX: model identity and capability are immutable; register a new revision',
      errcode = '42501';
  end if;

  if new.lifecycle_status is distinct from old.lifecycle_status
     and not (
       (old.lifecycle_status = 'discovered' and new.lifecycle_status = 'evaluating')
       or (old.lifecycle_status = 'evaluating' and new.lifecycle_status = 'approved')
       or (old.lifecycle_status = 'approved' and new.lifecycle_status = 'active')
       or (old.lifecycle_status = 'active' and new.lifecycle_status = 'deprecated')
       or (old.lifecycle_status = 'deprecated' and new.lifecycle_status = 'retired')
     )
  then
    raise exception using
      message = format(
        'NODEX: model lifecycle cannot move from %s to %s',
        old.lifecycle_status,
        new.lifecycle_status
      ),
      errcode = '23514';
  end if;

  -- Once evidence has been accepted it is history. A later evaluation is a
  -- new revision, not an edit of the evidence behind an approval.
  if old.lifecycle_status in ('approved', 'active', 'deprecated', 'retired') then
    if new.evaluation_status is distinct from old.evaluation_status
       or new.evaluation_set_revision is distinct from old.evaluation_set_revision
       or new.approved_by is distinct from old.approved_by
       or new.approved_at is distinct from old.approved_at
    then
      raise exception using
        message = 'NODEX: approval evidence is frozen once a model is approved',
        errcode = '42501';
    end if;
  end if;

  if new.lifecycle_status in ('approved', 'active') then
    if new.evaluation_status <> 'passed'
       or new.evaluation_set_revision is null
       or length(btrim(new.evaluation_set_revision)) = 0
    then
      raise exception using
        message = 'NODEX: a model needs a passed evaluation and a recorded evaluation-set revision before approval',
        errcode = '23514';
    end if;

    if new.approved_by is null or new.approved_at is null then
      raise exception using
        message = 'NODEX: approval must name the approver and the moment',
        errcode = '23514';
    end if;

    if not v_service then
      if not nodex.has_permission_anywhere('ai_governance.administer') then
        raise exception using
          message = 'NODEX: model approval needs ai_governance.administer',
          errcode = '42501';
      end if;

      -- Entering APPROVED is the approval act. The approver is the caller, and
      -- the moment is the server's clock: a device that is minutes fast or
      -- slow must not be able to backdate or postdate its own evidence.
      if old.lifecycle_status = 'evaluating' then
        if v_actor is null or new.approved_by <> v_actor then
          raise exception using
            message = 'NODEX: the approval must name the signed-in administrator',
            errcode = '42501';
        end if;
        new.approved_at := now();
      end if;
    end if;
  end if;

  return new;
end;
$$;

comment on function nodex.tg_ai_model_governance_guard() is
  'BEFORE UPDATE trigger on ai_model_registry: forward-only lifecycle, immutable identity and capability, actor-bound and time-bound approval, frozen evidence after approval.';

create trigger ai_model_governance_guard
  before update on public.ai_model_registry
  for each row execute function nodex.tg_ai_model_governance_guard();
