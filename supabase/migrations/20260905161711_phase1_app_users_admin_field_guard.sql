-- Guard administrative columns on app_users.
--
-- The app_users_update_self policy lets a user maintain their own profile. It
-- must not become a privilege-escalation path, so status, tenant binding,
-- employee code and professional registration number are frozen unless the
-- caller is the authorized backend or holds user.administer in the tenant.

create or replace function nodex.tg_app_users_guard_admin_fields()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_may_administer boolean := false;
begin
  if nodex.is_service_role() then
    return new;
  end if;

  if old.primary_tenant_id is not null then
    v_may_administer := nodex.has_permission(old.primary_tenant_id, 'user.administer');
  end if;

  if v_may_administer then
    return new;
  end if;

  new.id                := old.id;
  new.primary_tenant_id := old.primary_tenant_id;
  new.employee_code     := old.employee_code;
  new.registration_no   := old.registration_no;
  new.designation       := old.designation;
  new.status            := old.status;
  new.last_login_at     := old.last_login_at;
  new.created_at        := old.created_at;

  return new;
end;
$$;

comment on function nodex.tg_app_users_guard_admin_fields() is
  'Freezes administrative columns on app_users for self-service updates. Prevents the self-update policy becoming a privilege-escalation path.';

create trigger app_users_guard_admin_fields
  before update on public.app_users
  for each row execute function nodex.tg_app_users_guard_admin_fields();
