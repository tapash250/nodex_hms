-- Module 05 follow-up: the patient role reads nothing outside its own record.
--
-- Phase 1 seeded the patient role with patient.read, encounter.read,
-- appointment.read, appointment.write and billing.read. Those permissions were
-- written for staff, and every clinical table gates its SELECT on one of them.
-- Granting them to the patient role therefore let any portal account read
-- every patient's encounters, results, prescriptions and invoices in the
-- tenant. The same five grants also admitted the patient to twenty-two staff
-- replication buckets, because a bucket parameter checks the permission and
-- not the role.
--
-- Module 05 stated the boundary it needs: the portal reads through its own
-- bucket, which selects only the linked patient's rows, and "no clinical read
-- permission is granted to it". This migration makes the seed match that
-- design. The patient role keeps portal.access, which is the only key the
-- portal bucket checks.
--
-- The role-scope guard below is deliberate: a future re-grant of one of these
-- five keys would reopen the whole staff surface, and the failure would be
-- silent. A new portal capability should arrive as a new portal-scoped
-- permission, not as a staff read.

delete from public.role_permissions
where role_key = 'patient'
  and permission_key in (
    'patient.read',
    'encounter.read',
    'appointment.read',
    'appointment.write',
    'billing.read'
  );

-- The one path back: a staff grant made to the patient role would restore
-- cross-patient reads in RLS and in every staff bucket at once. Refuse it at
-- the table rather than trusting review of every future seed.
create or replace function nodex.tg_patient_role_scope_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.role_key = 'patient'
     and new.permission_key in (
       'patient.read',
       'encounter.read',
       'appointment.read',
       'appointment.write',
       'billing.read'
     ) then
    raise exception using
      message = 'NODEX: the patient role reads its own record through the portal bucket, never through staff permissions',
      errcode = '42501';
  end if;
  return new;
end;
$$;

comment on function nodex.tg_patient_role_scope_guard() is
  'Refuses to grant a staff clinical permission to the patient role. The portal path is portal.access plus a live patient_portal_links row.';

create trigger role_permissions_patient_scope
  before insert or update on public.role_permissions
  for each row execute function nodex.tg_patient_role_scope_guard();
