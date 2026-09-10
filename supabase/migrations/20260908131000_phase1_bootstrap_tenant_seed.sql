-- NODEX Phase 1: bootstrap reference tenant.
--
-- Closes the "nothing to sign into" gap: the database had roles and permissions
-- but no tenant, facility or ward, so no invite could even be created.
--
-- IDs are fixed so the tenant is addressable from build configuration and the
-- seed is idempotent on re-push. The slug marks this clearly as the bootstrap
-- tenant: rename or replace it for a real deployment, but do not delete it while
-- any device holds a snapshot bound to it.
--
-- Timezone/locale reflect the deployment context (Bangla/English clinical
-- workflows targeted by the AI speech and vision pipelines).

insert into public.tenants (id, slug, display_name, legal_name, country_code, timezone, locale, status)
values (
  '10000000-0000-4000-8000-000000000001',
  'nodex-bootstrap',
  'NODEX Bootstrap Hospital',
  'NODEX Enterprise HMS Bootstrap Tenant',
  'BD',
  'Asia/Dhaka',
  'en',
  'active'
)
on conflict (slug) do update
  set display_name = excluded.display_name,
      updated_at = now();

insert into public.facilities (id, tenant_id, code, display_name, facility_type, timezone, status)
values (
  '10000000-0000-4000-8000-000000000002',
  '10000000-0000-4000-8000-000000000001',
  'MAIN',
  'Main Hospital Building',
  'hospital',
  'Asia/Dhaka',
  'active'
)
on conflict (tenant_id, code) do update
  set display_name = excluded.display_name,
      updated_at = now();

insert into public.departments (id, tenant_id, facility_id, code, display_name, specialty, status)
values
  (
    '10000000-0000-4000-8000-000000000003',
    '10000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000002',
    'MED',
    'Department of Medicine',
    'Internal Medicine',
    'active'
  ),
  (
    '10000000-0000-4000-8000-000000000004',
    '10000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000002',
    'EMG',
    'Emergency Department',
    'Emergency Medicine',
    'active'
  )
on conflict (tenant_id, facility_id, code) do update
  set display_name = excluded.display_name,
      updated_at = now();

insert into public.wards (id, tenant_id, facility_id, department_id, code, display_name, ward_type, floor_label, bed_capacity, status)
values
  (
    '10000000-0000-4000-8000-000000000005',
    '10000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000002',
    '10000000-0000-4000-8000-000000000003',
    'GEN-M',
    'General Ward (Male)',
    'general',
    'Level 3',
    24,
    'active'
  ),
  (
    '10000000-0000-4000-8000-000000000006',
    '10000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000002',
    '10000000-0000-4000-8000-000000000004',
    'ER-RESUS',
    'Emergency Resuscitation Bay',
    'emergency',
    'Ground Floor',
    6,
    'active'
  )
on conflict (tenant_id, facility_id, code) do update
  set display_name = excluded.display_name,
      updated_at = now();
