-- NODEX Phase 4, Module 32: Health Insurance & TPA.
--
-- Specification scope: "Policy verification, pre-auth, electronic claims."
--
-- This is the payer side of the money: the cover a patient holds, the
-- authorisation a payer gives before treatment, and the claim the hospital
-- submits afterwards. It is a distinct domain from Module 31 (Patient Accounts
-- & Billing), which bills the patient: here the counterparty is an insurer or
-- TPA, the currency of the conversation is an authorisation and a claim
-- reference, and the money is recovered rather than collected.
--
-- Four tables, matching the scope:
--
--   * `insurance_payers` is the payer registry — the insurer, TPA, corporate or
--     government scheme the hospital contracts with. Tenant-scoped governed
--     configuration, deactivated and retained rather than deleted, because
--     policies and claims name it.
--   * `insurance_policies` is the member's cover: the policy number, the plan,
--     the sum insured and the validity window. Verification is a fact recorded
--     on the row (who and when), not a second copy of the policy. Cancellation
--     is one-way and freezes the row.
--   * `pre_authorisation_requests` is the cashless authorisation: a guarded
--     state machine `requested → submitted → approved | partially_approved |
--     rejected`, cancellable from either live stage. The payer's answer is the
--     thing the hospital acts on, so an answered request is frozen.
--   * `insurance_claims` is the electronic claim: a guarded state machine
--     `draft → submitted → under_review → approved | partially_approved |
--     rejected`, then `approved | partially_approved → settled`. Cancellable
--     from any live stage; a decided or settled claim is frozen.
--
-- Two facts are derived rather than stored, because a stored copy drifts from
-- the fact it summarises: the cover state of a policy (expired, expiring,
-- active or cancelled) from the validity window, and the recovery gap of a
-- claim (claimed minus settled). Money is an integer number of minor units in
-- an ISO-4217 currency, exactly as Module 31 stores it, so no float ever
-- reaches a recovery figure.
--
-- The four permissions are granted explicitly because the Phase 1
-- all-permissions seed predates these keys. Verification is separated from
-- registry administration (as Module 29 separates maintenance from the
-- registry) so an insurance desk can verify cover without being able to edit
-- the payer registry, and claims are separated from verification because they
-- are a different desk's work.

create table public.insurance_payers (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  code text not null check (length(btrim(code)) > 0),
  name text not null check (length(btrim(name)) > 0),
  payer_type text not null default 'insurer'
    check (payer_type in ('insurer','tpa','corporate','government','other')),
  claim_portal_ref text check (claim_portal_ref is null or length(btrim(claim_portal_ref)) > 0),
  contact_phone text check (contact_phone is null or length(btrim(contact_phone)) > 0),
  contact_email text check (contact_email is null or length(btrim(contact_email)) > 0),
  is_active boolean not null default true,
  notes text check (notes is null or length(btrim(notes)) > 0),
  created_by uuid not null references public.app_users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, code)
);
create index insurance_payers_tenant_idx
  on public.insurance_payers(tenant_id, is_active);

create trigger insurance_payers_set_updated_at before update on public.insurance_payers
  for each row execute function nodex.tg_set_updated_at();
-- A payer is deactivated, never deleted: policies and claims name it and must
-- stay answerable.
create trigger insurance_payers_retain before delete on public.insurance_payers
  for each row execute function nodex.tg_block_mutation();

-- The member's cover. Verification is recorded here rather than in a second
-- table, because a second record of the same cover is a second thing to
-- disagree with.
create table public.insurance_policies (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  patient_id uuid not null references public.patients(id) on delete restrict,
  payer_id uuid not null references public.insurance_payers(id) on delete restrict,
  policy_no text not null check (length(btrim(policy_no)) > 0),
  member_id text check (member_id is null or length(btrim(member_id)) > 0),
  plan_name text check (plan_name is null or length(btrim(plan_name)) > 0),
  coverage_type text not null default 'cashless'
    check (coverage_type in ('cashless','reimbursement','both')),
  currency text not null default 'BDT' check (currency ~ '^[A-Z]{3}$'),
  sum_insured_minor bigint not null default 0 check (sum_insured_minor >= 0),
  valid_from date not null,
  valid_to date not null,
  status text not null default 'active' check (status in ('active','cancelled')),
  verified_at timestamptz,
  verified_by uuid references public.app_users(id) on delete set null,
  verification_reference text
    check (verification_reference is null or length(btrim(verification_reference)) > 0),
  cancelled_at timestamptz,
  cancellation_reason text
    check (cancellation_reason is null or length(btrim(cancellation_reason)) > 0),
  notes text check (notes is null or length(btrim(notes)) > 0),
  created_by uuid not null references public.app_users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, policy_no),
  constraint insurance_policy_window_ck check (valid_to >= valid_from),
  -- Verification names a person or it does not exist.
  constraint insurance_policy_verified_ck check (
    (verified_at is null and verified_by is null)
    or (verified_at is not null and verified_by is not null)
  ),
  constraint insurance_policy_cancel_ck check (
    status <> 'cancelled'
    or (
      cancelled_at is not null
      and cancellation_reason is not null
      and length(btrim(cancellation_reason)) > 0
    )
  )
);
create index insurance_policies_patient_idx
  on public.insurance_policies(tenant_id, patient_id, valid_to desc);
create index insurance_policies_payer_idx
  on public.insurance_policies(tenant_id, payer_id, status);

create trigger insurance_policies_set_updated_at before update on public.insurance_policies
  for each row execute function nodex.tg_set_updated_at();
create trigger insurance_policies_retain before delete on public.insurance_policies
  for each row execute function nodex.tg_block_mutation();

-- A cancelled policy is terminal and frozen: the payer has withdrawn the cover
-- and the terms it asserted must not be rewritten afterwards.
create or replace function nodex.tg_insurance_policy_lifecycle_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status = 'cancelled' then
    if new.status is distinct from old.status
      or new.policy_no is distinct from old.policy_no
      or new.member_id is distinct from old.member_id
      or new.plan_name is distinct from old.plan_name
      or new.coverage_type is distinct from old.coverage_type
      or new.currency is distinct from old.currency
      or new.sum_insured_minor is distinct from old.sum_insured_minor
      or new.valid_from is distinct from old.valid_from
      or new.valid_to is distinct from old.valid_to
      or new.payer_id is distinct from old.payer_id
      or new.patient_id is distinct from old.patient_id
      or new.verified_at is distinct from old.verified_at
      or new.verified_by is distinct from old.verified_by
      or new.verification_reference is distinct from old.verification_reference
      or new.cancellation_reason is distinct from old.cancellation_reason then
      raise exception using
        message = 'NODEX: a cancelled insurance policy is immutable',
        errcode = '42501';
    end if;
    return new;
  end if;
  if new.status = old.status then
    return new;
  end if;
  if old.status = 'active' and new.status = 'cancelled' then
    return new;
  end if;
  raise exception using
    message = 'NODEX: a cancelled insurance policy cannot be reactivated',
    errcode = '42501';
end;
$$;
create trigger insurance_policies_lifecycle_guard
  before update on public.insurance_policies
  for each row execute function nodex.tg_insurance_policy_lifecycle_guard();

-- The cashless authorisation. The payer answers, and the answer is what the
-- ward acts on.
create table public.pre_authorisation_requests (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  policy_id uuid not null references public.insurance_policies(id) on delete restrict,
  patient_id uuid not null references public.patients(id) on delete restrict,
  facility_id uuid not null references public.facilities(id) on delete restrict,
  encounter_id uuid references public.clinical_encounters(id) on delete set null,
  requested_by uuid not null references public.app_users(id) on delete restrict,
  requested_at timestamptz not null default now(),
  diagnosis text not null check (length(btrim(diagnosis)) > 0),
  procedure_text text not null check (length(btrim(procedure_text)) > 0),
  currency text not null default 'BDT' check (currency ~ '^[A-Z]{3}$'),
  estimated_cost_minor bigint not null check (estimated_cost_minor > 0),
  status text not null default 'requested'
    check (status in ('requested','submitted','approved','partially_approved','rejected','cancelled')),
  payer_reference text check (payer_reference is null or length(btrim(payer_reference)) > 0),
  answered_at timestamptz,
  approved_amount_minor bigint check (approved_amount_minor is null or approved_amount_minor > 0),
  valid_until timestamptz,
  decision_notes text check (decision_notes is null or length(btrim(decision_notes)) > 0),
  cancellation_reason text
    check (cancellation_reason is null or length(btrim(cancellation_reason)) > 0),
  created_by uuid not null references public.app_users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- An approval carries an amount and a time; an approval without either is not
  -- an approval.
  constraint preauth_approval_ck check (
    status not in ('approved','partially_approved')
    or (
      answered_at is not null
      and approved_amount_minor is not null
      and approved_amount_minor > 0
    )
  ),
  -- A rejection must say why: the refusal is what the hospital appeals.
  constraint preauth_rejection_ck check (
    status <> 'rejected'
    or (
      answered_at is not null
      and decision_notes is not null
      and length(btrim(decision_notes)) > 0
    )
  ),
  constraint preauth_cancel_ck check (
    status <> 'cancelled'
    or (
      cancellation_reason is not null
      and length(btrim(cancellation_reason)) > 0
    )
  ),
  constraint preauth_pending_ck check (
    status not in ('requested','submitted')
    or (answered_at is null and approved_amount_minor is null)
  )
);
create index pre_authorisation_policy_idx
  on public.pre_authorisation_requests(tenant_id, policy_id, requested_at desc);
create index pre_authorisation_status_idx
  on public.pre_authorisation_requests(tenant_id, status, requested_at desc);
create index pre_authorisation_patient_idx
  on public.pre_authorisation_requests(tenant_id, patient_id, requested_at desc);

create trigger pre_authorisation_set_updated_at before update on public.pre_authorisation_requests
  for each row execute function nodex.tg_set_updated_at();
create trigger pre_authorisation_retain before delete on public.pre_authorisation_requests
  for each row execute function nodex.tg_block_mutation();

-- One stage at a time; cancellable from either live stage; an answered request
-- is frozen, because the authorisation the ward acted on must stay readable.
create or replace function nodex.tg_pre_authorisation_transition_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status in ('approved','partially_approved','rejected','cancelled') then
    raise exception using
      message = 'NODEX: an answered pre-authorisation request is immutable',
      errcode = '42501';
  end if;
  if new.status = old.status then
    return new;
  end if;
  if new.status = 'cancelled' then
    return new;
  end if;
  if (old.status = 'requested' and new.status = 'submitted')
    or (old.status = 'submitted' and new.status in ('approved','partially_approved','rejected')) then
    return new;
  end if;
  raise exception using
    message = 'NODEX: a pre-authorisation request may not skip a stage',
    errcode = '42501';
end;
$$;
create trigger pre_authorisation_transition_guard
  before update on public.pre_authorisation_requests
  for each row execute function nodex.tg_pre_authorisation_transition_guard();

-- The electronic claim. It recovers what the invoice billed, which is why it
-- may point at the Module 31 invoice and at the authorisation that preceded it,
-- without either being required: a reimbursement claim follows an invoice that
-- was already paid by the patient.
create table public.insurance_claims (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  policy_id uuid not null references public.insurance_policies(id) on delete restrict,
  patient_id uuid not null references public.patients(id) on delete restrict,
  facility_id uuid not null references public.facilities(id) on delete restrict,
  pre_authorisation_id uuid references public.pre_authorisation_requests(id) on delete set null,
  invoice_id uuid references public.invoices(id) on delete set null,
  claim_no text not null check (length(btrim(claim_no)) > 0),
  currency text not null default 'BDT' check (currency ~ '^[A-Z]{3}$'),
  claimed_amount_minor bigint not null check (claimed_amount_minor > 0),
  approved_amount_minor bigint check (approved_amount_minor is null or approved_amount_minor > 0),
  settled_amount_minor bigint check (settled_amount_minor is null or settled_amount_minor > 0),
  status text not null default 'draft'
    check (status in ('draft','submitted','under_review','approved','partially_approved','rejected','settled','cancelled')),
  payer_reference text check (payer_reference is null or length(btrim(payer_reference)) > 0),
  submitted_at timestamptz,
  decided_at timestamptz,
  settled_at timestamptz,
  rejection_reason text check (rejection_reason is null or length(btrim(rejection_reason)) > 0),
  cancellation_reason text
    check (cancellation_reason is null or length(btrim(cancellation_reason)) > 0),
  notes text check (notes is null or length(btrim(notes)) > 0),
  created_by uuid not null references public.app_users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, claim_no),
  -- A claim that leaves the draft must carry the moment it was sent; a draft
  -- that was withdrawn never left, so it owes no submission time.
  constraint claim_submitted_ck check (
    submitted_at is not null or status in ('draft','cancelled')
  ),
  constraint claim_decision_ck check (
    status not in ('approved','partially_approved','settled')
    or (
      decided_at is not null
      and approved_amount_minor is not null
      and approved_amount_minor > 0
    )
  ),
  constraint claim_settled_ck check (
    status <> 'settled'
    or (
      settled_at is not null
      and settled_amount_minor is not null
      and settled_amount_minor > 0
    )
  ),
  constraint claim_rejection_ck check (
    status <> 'rejected'
    or (
      decided_at is not null
      and rejection_reason is not null
      and length(btrim(rejection_reason)) > 0
    )
  ),
  constraint claim_cancel_ck check (
    status <> 'cancelled'
    or (
      cancellation_reason is not null
      and length(btrim(cancellation_reason)) > 0
    )
  ),
  -- A claim cannot be paid more than it was decided at, and cannot be decided
  -- at more than it claimed. The recovery gap is then never negative.
  constraint claim_amounts_ck check (
    (approved_amount_minor is null or approved_amount_minor <= claimed_amount_minor)
    and (settled_amount_minor is null or approved_amount_minor is null
         or settled_amount_minor <= approved_amount_minor)
  )
);
create index insurance_claims_policy_idx
  on public.insurance_claims(tenant_id, policy_id, created_at desc);
create index insurance_claims_status_idx
  on public.insurance_claims(tenant_id, status, created_at desc);
create index insurance_claims_patient_idx
  on public.insurance_claims(tenant_id, patient_id, created_at desc);
create index insurance_claims_invoice_idx
  on public.insurance_claims(tenant_id, invoice_id);

create trigger insurance_claims_set_updated_at before update on public.insurance_claims
  for each row execute function nodex.tg_set_updated_at();
create trigger insurance_claims_retain before delete on public.insurance_claims
  for each row execute function nodex.tg_block_mutation();

-- One stage at a time; settlement requires a decision; a decided or settled
-- claim is frozen so the recovery a finance review turns on cannot be rewritten.
create or replace function nodex.tg_insurance_claim_transition_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status in ('settled','rejected','cancelled') then
    raise exception using
      message = 'NODEX: a closed insurance claim is immutable',
      errcode = '42501';
  end if;
  if new.status = old.status then
    return new;
  end if;
  if new.status = 'cancelled' then
    return new;
  end if;
  if (old.status = 'draft' and new.status = 'submitted')
    or (old.status = 'submitted' and new.status = 'under_review')
    or (old.status = 'under_review'
        and new.status in ('approved','partially_approved','rejected'))
    or (old.status in ('approved','partially_approved') and new.status = 'settled') then
    return new;
  end if;
  raise exception using
    message = 'NODEX: an insurance claim may not skip a stage',
    errcode = '42501';
end;
$$;
create trigger insurance_claims_transition_guard
  before update on public.insurance_claims
  for each row execute function nodex.tg_insurance_claim_transition_guard();

alter table public.insurance_payers enable row level security;
alter table public.insurance_payers force row level security;
alter table public.insurance_policies enable row level security;
alter table public.insurance_policies force row level security;
alter table public.pre_authorisation_requests enable row level security;
alter table public.pre_authorisation_requests force row level security;
alter table public.insurance_claims enable row level security;
alter table public.insurance_claims force row level security;

create policy insurance_payers_select_member on public.insurance_payers for select to authenticated
  using (nodex.has_permission(tenant_id, 'insurance.read'));
create policy insurance_payers_insert_manager on public.insurance_payers for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'insurance.manage'));
create policy insurance_payers_update_manager on public.insurance_payers for update to authenticated
  using (nodex.has_permission(tenant_id, 'insurance.manage'))
  with check (nodex.has_permission(tenant_id, 'insurance.manage'));

create policy insurance_policies_select_member on public.insurance_policies for select to authenticated
  using (nodex.has_permission(tenant_id, 'insurance.read'));
create policy insurance_policies_insert_manager on public.insurance_policies for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'insurance.manage'));
-- Two permissive update policies, so either an insurance desk verifying cover
-- or an administrator cancelling it may update the row. Which of the two may
-- change the status is enforced by the use case tier and recorded in the audit
-- event; the database enforces the shape of the transition itself.
create policy insurance_policies_update_verifier on public.insurance_policies for update to authenticated
  using (nodex.has_permission(tenant_id, 'insurance.verify'))
  with check (nodex.has_permission(tenant_id, 'insurance.verify'));
create policy insurance_policies_update_manager on public.insurance_policies for update to authenticated
  using (nodex.has_permission(tenant_id, 'insurance.manage'))
  with check (nodex.has_permission(tenant_id, 'insurance.manage'));

create policy pre_authorisation_select_member on public.pre_authorisation_requests for select to authenticated
  using (nodex.has_permission(tenant_id, 'insurance.read'));
create policy pre_authorisation_insert_verifier on public.pre_authorisation_requests for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'insurance.verify'));
create policy pre_authorisation_update_verifier on public.pre_authorisation_requests for update to authenticated
  using (nodex.has_permission(tenant_id, 'insurance.verify'))
  with check (nodex.has_permission(tenant_id, 'insurance.verify'));

create policy insurance_claims_select_member on public.insurance_claims for select to authenticated
  using (nodex.has_permission(tenant_id, 'insurance.read'));
create policy insurance_claims_insert_claimant on public.insurance_claims for insert to authenticated
  with check (nodex.has_permission(tenant_id, 'insurance.claim'));
create policy insurance_claims_update_claimant on public.insurance_claims for update to authenticated
  using (nodex.has_permission(tenant_id, 'insurance.claim'))
  with check (nodex.has_permission(tenant_id, 'insurance.claim'));

insert into public.permissions (key, display_name, description, module_code, risk_tier, requires_online)
values
  ('insurance.read',   'Read insurance and TPA',  'View payers, policies, pre-authorisation requests and claims.', 'M32', 'standard', false),
  ('insurance.verify', 'Verify insurance cover',  'Record policy verification and raise and submit pre-authorisation requests.', 'M32', 'elevated', false),
  ('insurance.claim',  'Submit insurance claims', 'Submit electronic claims and record payer decisions and settlements.', 'M32', 'elevated', false),
  ('insurance.manage', 'Manage insurance registry', 'Maintain the payer registry and register or cancel patient policies.', 'M32', 'elevated', false)
on conflict (key) do nothing;

insert into public.role_permissions (role_key, permission_key)
values
  ('hospital_super_admin', 'insurance.read'),
  ('hospital_super_admin', 'insurance.verify'),
  ('hospital_super_admin', 'insurance.claim'),
  ('hospital_super_admin', 'insurance.manage'),
  ('medical_officer',      'insurance.read'),
  ('nursing_staff',        'insurance.read'),
  ('nursing_staff',        'insurance.verify'),
  ('billing_accounts',     'insurance.read'),
  ('billing_accounts',     'insurance.verify'),
  ('billing_accounts',     'insurance.claim'),
  ('auditor',              'insurance.read')
on conflict do nothing;
