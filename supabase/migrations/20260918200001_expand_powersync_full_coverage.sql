-- NODEX Enterprise HMS — full PowerSync replication coverage.
--
-- The initial source-database setup granted SELECT, set REPLICA IDENTITY
-- DEFAULT and published only the 18 tables the first seven streams read. The
-- local schema now has 146 replicated tables, and the sync config reads every
-- one of them. This migration closes that gap without widening any application
-- role: the grant is to the dedicated powersync_role, which already holds
-- REPLICATION and BYPASSRLS and is never used by a client.
--
-- Safe to re-run: grants are repeatable, REPLICA IDENTITY DEFAULT is
-- repeatable, and a table already present in the publication is skipped.
--
-- Prerequisite: powersync/SOURCE_DB_SETUP.sql has created powersync_role. If
-- the publication does not exist yet, this migration creates it empty; the
-- loop below then publishes every table.

do $do$
declare
  t text;
  publication_is_all_tables boolean;
  synced_tables text[] := array[
    'tenants',
    'facilities',
    'departments',
    'directory_contacts',
    'calendar_events',
    'ambulances',
    'ambulance_duty_assignments',
    'ambulance_dispatches',
    'ambulance_tracking_pings',
    'biomedical_assets',
    'biomedical_breakdown_tickets',
    'biomedical_maintenance_records',
    'waste_categories',
    'waste_generation_logs',
    'waste_disposal_certificates',
    'insurance_payers',
    'insurance_policies',
    'pre_authorisation_requests',
    'insurance_claims',
    'consent_templates',
    'consent_records',
    'document_vault_documents',
    'statutory_birth_records',
    'statutory_death_records',
    'statutory_mlc_intimations',
    'statutory_record_amendments',
    'compliance_audits',
    'incident_reports',
    'clinical_indicators',
    'feedback_surveys',
    'feedback_complaints',
    'complaint_routing_events',
    'ward_visiting_windows',
    'visitor_registrations',
    'visitor_passes',
    'visitor_badge_prints',
    'analytics_report_definitions',
    'analytics_rollups',
    'analytics_report_runs',
    'analytics_exports',
    'settings_profiles',
    'branding_assets',
    'department_hierarchies',
    'billing_tariffs',
    'ai_routing_profiles',
    'wards',
    'app_users',
    'roles',
    'permissions',
    'role_permissions',
    'memberships',
    'devices',
    'sync_cursors',
    'ai_model_registry',
    'ai_routing_policies',
    'ai_deployment_profiles',
    'audit_events',
    'patients',
    'patient_allergies',
    'patient_merge_history',
    'clinical_encounters',
    'encounter_amendments',
    'clinical_problems',
    'encounter_scribe_drafts',
    'lab_orders',
    'lab_specimens',
    'lab_results',
    'prescriptions',
    'prescription_items',
    'pharmacy_dispenses',
    'medication_administrations',
    'beds',
    'bed_assignments',
    'invoices',
    'invoice_lines',
    'payments',
    'refunds',
    'patient_accounts',
    'ledger_entries',
    'payment_allocations',
    'stock_items',
    'stock_locations',
    'stock_batches',
    'stock_movements',
    'discharges',
    'patient_portal_links',
    'doctor_assignments',
    'clinical_performance_indices',
    'operational_department_metrics',
    'executive_kpi_snapshots',
    'clinical_threads',
    'clinical_messages',
    'clinical_attachments',
    'work_items',
    'it_tickets',
    'form_templates',
    'form_responses',
    'icd10_codes',
    'triage_assessments',
    'er_visits',
    'icu_beds',
    'icu_vitals',
    'icu_nursing_handover',
    'ventilator_events',
    'transfusion_requests',
    'blood_units',
    'transfusions',
    'ot_bookings',
    'ot_preop_assessments',
    'ot_anesthesia_records',
    'ot_procedure_logs',
    'ot_postop_records',
    'imaging_orders',
    'imaging_studies',
    'imaging_reports',
    'physio_sessions',
    'physio_exercise_plans',
    'physio_recovery_notes',
    'diet_assessments',
    'diet_meal_plans',
    'diet_meal_plan_days',
    'diet_intake_logs',
    'tele_consultations',
    'tele_vitals_overlays',
    'tele_consultation_archives',
    'discharge_clearances',
    'discharge_medication_reconciliations',
    'discharge_medication_reconciliation_items',
    'discharge_settlements',
    'discharge_ai_summaries',
    'ward_rooms',
    'appointments',
    'practitioner_profiles',
    'practitioner_on_calls',
    'staff_shifts',
    'duty_allocations',
    'attendance_logs',
    'hr_employees',
    'hr_leave_requests',
    'hr_holidays',
    'hr_payroll_periods',
    'hr_payslips',
    'ward_vitals',
    'ward_handovers',
    'ward_tasks',
    'hospital_tasks'
  ];
begin
  if not exists (select 1 from pg_roles where rolname = 'powersync_role') then
    raise exception
      'powersync_role is missing; run powersync/SOURCE_DB_SETUP.sql first';
  end if;

  if not exists (select 1 from pg_publication where pubname = 'powersync') then
    execute 'create publication powersync';
  end if;

  select puballtables
    into publication_is_all_tables
    from pg_publication
   where pubname = 'powersync';

  foreach t in array synced_tables loop
    execute format('grant select on table public.%I to powersync_role', t);
    execute format('alter table public.%I replica identity default', t);

    if not publication_is_all_tables
       and not exists (
         select 1
           from pg_publication_tables
          where pubname = 'powersync'
            and schemaname = 'public'
            and tablename = t
       )
    then
      execute format('alter publication powersync add table public.%I', t);
    end if;
  end loop;
end
$do$;

-- Verification: every replicated table must be granted, published and use the
-- primary-key replica identity. The query returns no rows when coverage is
-- complete; run it after applying the migration.
select c.relname
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relkind = 'r'
  and c.relname = any (array[
    'tenants',
    'facilities',
    'departments',
    'directory_contacts',
    'calendar_events',
    'ambulances',
    'ambulance_duty_assignments',
    'ambulance_dispatches',
    'ambulance_tracking_pings',
    'biomedical_assets',
    'biomedical_breakdown_tickets',
    'biomedical_maintenance_records',
    'waste_categories',
    'waste_generation_logs',
    'waste_disposal_certificates',
    'insurance_payers',
    'insurance_policies',
    'pre_authorisation_requests',
    'insurance_claims',
    'consent_templates',
    'consent_records',
    'document_vault_documents',
    'statutory_birth_records',
    'statutory_death_records',
    'statutory_mlc_intimations',
    'statutory_record_amendments',
    'compliance_audits',
    'incident_reports',
    'clinical_indicators',
    'feedback_surveys',
    'feedback_complaints',
    'complaint_routing_events',
    'ward_visiting_windows',
    'visitor_registrations',
    'visitor_passes',
    'visitor_badge_prints',
    'analytics_report_definitions',
    'analytics_rollups',
    'analytics_report_runs',
    'analytics_exports',
    'settings_profiles',
    'branding_assets',
    'department_hierarchies',
    'billing_tariffs',
    'ai_routing_profiles',
    'wards',
    'app_users',
    'roles',
    'permissions',
    'role_permissions',
    'memberships',
    'devices',
    'sync_cursors',
    'ai_model_registry',
    'ai_routing_policies',
    'ai_deployment_profiles',
    'audit_events',
    'patients',
    'patient_allergies',
    'patient_merge_history',
    'clinical_encounters',
    'encounter_amendments',
    'clinical_problems',
    'encounter_scribe_drafts',
    'lab_orders',
    'lab_specimens',
    'lab_results',
    'prescriptions',
    'prescription_items',
    'pharmacy_dispenses',
    'medication_administrations',
    'beds',
    'bed_assignments',
    'invoices',
    'invoice_lines',
    'payments',
    'refunds',
    'patient_accounts',
    'ledger_entries',
    'payment_allocations',
    'stock_items',
    'stock_locations',
    'stock_batches',
    'stock_movements',
    'discharges',
    'patient_portal_links',
    'doctor_assignments',
    'clinical_performance_indices',
    'operational_department_metrics',
    'executive_kpi_snapshots',
    'clinical_threads',
    'clinical_messages',
    'clinical_attachments',
    'work_items',
    'it_tickets',
    'form_templates',
    'form_responses',
    'icd10_codes',
    'triage_assessments',
    'er_visits',
    'icu_beds',
    'icu_vitals',
    'icu_nursing_handover',
    'ventilator_events',
    'transfusion_requests',
    'blood_units',
    'transfusions',
    'ot_bookings',
    'ot_preop_assessments',
    'ot_anesthesia_records',
    'ot_procedure_logs',
    'ot_postop_records',
    'imaging_orders',
    'imaging_studies',
    'imaging_reports',
    'physio_sessions',
    'physio_exercise_plans',
    'physio_recovery_notes',
    'diet_assessments',
    'diet_meal_plans',
    'diet_meal_plan_days',
    'diet_intake_logs',
    'tele_consultations',
    'tele_vitals_overlays',
    'tele_consultation_archives',
    'discharge_clearances',
    'discharge_medication_reconciliations',
    'discharge_medication_reconciliation_items',
    'discharge_settlements',
    'discharge_ai_summaries',
    'ward_rooms',
    'appointments',
    'practitioner_profiles',
    'practitioner_on_calls',
    'staff_shifts',
    'duty_allocations',
    'attendance_logs',
    'hr_employees',
    'hr_leave_requests',
    'hr_holidays',
    'hr_payroll_periods',
    'hr_payslips',
    'ward_vitals',
    'ward_handovers',
    'ward_tasks',
    'hospital_tasks'
  ])
  and (
    c.relreplident <> 'd'
    or not has_table_privilege('powersync_role', c.oid, 'SELECT')
    or not exists (
      select 1
      from pg_publication_tables pt
      where pt.pubname = 'powersync'
        and pt.schemaname = 'public'
        and pt.tablename = c.relname
    )
  )
order by c.relname;
