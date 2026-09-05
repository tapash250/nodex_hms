-- NODEX Phase 1: prevent privilege escalation through self-service profile edits.
--
-- The app_users_update_self policy lets a user maintain their own profile. This
-- trigger freezes the administrative fields so a user cannot activate a
-- suspended account, move themselves to another tenant, or forge a professional
-- registration number.

create or replace function nodex.tg_app_user_self_update_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Backend/administrative paths bypass the guard.
  if nodex.is_service_role() then
    return new;
  end if;

  if auth.uid() is not null
     and old.id = auth.uid()
     and not nodex.has_permission(coalesce(old.primary_tenant_id, new.primary_tenant_id), 'user.administer')
  then
    new.id                := old.id;
    new.primary_tenant_id := old.primary_tenant_id;
    new.employee_code     := old.employee_code;
    new.registration_no   := old.registration_no;
    new.designation        := old.designation;
    new.status            := old.status;
    new.created_at        := old.created_at;
    new.last_login_at     := old.last_login_at;
  end if;

  return new;
end;
$$;

comment on function nodex.tg_app_user_self_update_guard() is
  'Freezes administrative app_users columns during self-service profile updates. Prevents privilege escalation via the update-self policy.';

create trigger app_users_self_update_guard
  before update on public.app_users
  for each row execute function nodex.tg_app_user_self_update_guard();
