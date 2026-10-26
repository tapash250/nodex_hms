-- Module 01: Global Executive Dashboard (AI-Insights)
--
-- The enterprise reading of a facility at a moment: how full it is, how many
-- inpatients it holds, how long the emergency queue is, what the day has
-- collected, how fast beds turn over and how long patients stay. The figures
-- are captured from the operational tables rather than typed by an executive,
-- so the dashboard is a reading of what happened and not a second opinion.
--
-- A snapshot is written once. A correction is a later snapshot with its own
-- timestamp, never an edit of the earlier reading. The AI narrative, when one
-- is eventually approved, is attached to the snapshot that produced it.

create table public.executive_kpi_snapshots (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  facility_id uuid not null references public.facilities(id) on delete restrict,
  snapshot_timestamp timestamptz not null,
  occupancy_rate numeric(5,2) not null
    check (occupancy_rate >= 0 and occupancy_rate <= 100),
  active_inpatients integer not null default 0 check (active_inpatients >= 0),
  er_waiting_count integer not null default 0 check (er_waiting_count >= 0),
  daily_gross_revenue numeric(14,2) not null default 0
    check (daily_gross_revenue >= 0),
  daily_net_revenue numeric(14,2) not null default 0
    check (daily_net_revenue >= 0),
  bed_turnover_rate numeric(8,2) not null default 0
    check (bed_turnover_rate >= 0),
  average_length_of_stay_days numeric(8,2) not null default 0
    check (average_length_of_stay_days >= 0),
  ai_executive_summary jsonb,
  created_at timestamptz not null default now(),
  unique (facility_id, snapshot_timestamp)
);

comment on table public.executive_kpi_snapshots is
  'A facility executive reading at a moment. Written once by nodex.capture_executive_kpi_snapshot and never edited: a corrected figure is a later snapshot.';
comment on column public.executive_kpi_snapshots.daily_gross_revenue is
  'Invoices issued during the facility day, in major currency units. An invoice is attributed to the facility of its encounter bed or, failing that, the facility of the user who created it.';
comment on column public.executive_kpi_snapshots.daily_net_revenue is
  'Gross revenue minus refunds recorded during the same facility day.';
comment on column public.executive_kpi_snapshots.bed_turnover_rate is
  'Released bed assignments in the trailing 24 hours as a percentage of the facility beds that are not under maintenance.';
comment on column public.executive_kpi_snapshots.average_length_of_stay_days is
  'Mean completed length of stay for assignments released in the trailing 30 days; active stays are used when no stay has completed in that window.';
comment on column public.executive_kpi_snapshots.ai_executive_summary is
  'Optional approved narrative. Null until a model has passed evaluation and an executive summary is approved; the four risk points are derived from the figures regardless.';

create index executive_kpi_facility_idx
  on public.executive_kpi_snapshots (tenant_id, facility_id, snapshot_timestamp desc);

-- A snapshot is history. It is never updated or deleted.
create trigger executive_kpi_retain
  before update or delete on public.executive_kpi_snapshots
  for each row execute function nodex.tg_block_mutation();

-- Captures one facility reading. SECURITY DEFINER because the capture runs
-- from a scheduled server job, not from a clinician's session; the function
-- derives every figure from the operational tables.
create or replace function nodex.capture_executive_kpi_snapshot(
  p_tenant_id uuid,
  p_facility_id uuid,
  p_snapshot_timestamp timestamptz default now()
)
returns public.executive_kpi_snapshots
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_day_start timestamptz;
  v_beds integer;
  v_occupied integer;
  v_er_waiting integer;
  v_gross numeric(14,2);
  v_refunds numeric(14,2);
  v_released_24h integer;
  v_occupancy numeric(5,2);
  v_turnover numeric(8,2);
  v_alos numeric(8,2);
  v_row public.executive_kpi_snapshots;
begin
  if not exists (
    select 1 from public.facilities f
    where f.id = p_facility_id and f.tenant_id = p_tenant_id
  ) then
    raise exception using
      message = 'NODEX: executive snapshot needs a facility in the tenant',
      errcode = '23503';
  end if;

  select date_trunc('day', p_snapshot_timestamp at time zone t.timezone)
           at time zone t.timezone
  into v_day_start
  from public.tenants t
  where t.id = p_tenant_id;

  if v_day_start is null then
    raise exception using
      message = 'NODEX: executive snapshot needs a known tenant',
      errcode = '23503';
  end if;

  -- Beds under maintenance are not capacity; an occupied bed is an active
  -- assignment, so the two figures cannot disagree.
  select count(*)
  into v_beds
  from public.beds b
  join public.wards w on w.id = b.ward_id
  where b.tenant_id = p_tenant_id
    and w.facility_id = p_facility_id
    and w.status = 'active'
    and b.status = 'available';

  select count(*)
  into v_occupied
  from public.bed_assignments ba
  join public.beds b on b.id = ba.bed_id
  join public.wards w on w.id = b.ward_id
  where ba.tenant_id = p_tenant_id
    and w.facility_id = p_facility_id
    and w.status = 'active'
    and ba.status = 'active';

  -- An emergency visit belongs to the facility of its bed; a visit without a
  -- bed belongs to the facility of the provider who is seeing it.
  select count(*)
  into v_er_waiting
  from public.er_visits ev
  left join public.beds b on b.id = ev.bed_id
  left join public.wards w on w.id = b.ward_id
  where ev.tenant_id = p_tenant_id
    and ev.status = 'in_progress'
    and coalesce(
      w.facility_id,
      (
        select m.facility_id
        from public.memberships m
        where m.tenant_id = ev.tenant_id
          and m.user_id = ev.provider_id
          and m.facility_id is not null
          and m.status = 'active'
          and m.valid_from <= p_snapshot_timestamp
          and (m.valid_until is null or m.valid_until > p_snapshot_timestamp)
        order by m.valid_from desc
        limit 1
      )
    ) = p_facility_id;

  select coalesce(sum(i.total_minor), 0)::numeric / 100.0
  into v_gross
  from public.invoices i
  where i.tenant_id = p_tenant_id
    and i.status in ('issued', 'settled')
    and i.issued_at >= v_day_start
    and i.issued_at < v_day_start + interval '1 day'
    and (
      exists (
        select 1
        from public.memberships m
        where m.tenant_id = i.tenant_id
          and m.user_id = i.created_by
          and m.facility_id = p_facility_id
          and m.status = 'active'
          and m.valid_from <= p_snapshot_timestamp
          and (m.valid_until is null or m.valid_until > p_snapshot_timestamp)
      )
      or exists (
        select 1
        from public.bed_assignments ba
        join public.beds b on b.id = ba.bed_id
        join public.wards w on w.id = b.ward_id
        where ba.tenant_id = i.tenant_id
          and ba.encounter_id = i.encounter_id
          and w.facility_id = p_facility_id
      )
    );

  select coalesce(sum(r.amount_minor), 0)::numeric / 100.0
  into v_refunds
  from public.refunds r
  join public.invoices i on i.id = r.invoice_id
  where r.tenant_id = p_tenant_id
    and r.refunded_at >= v_day_start
    and r.refunded_at < v_day_start + interval '1 day'
    and (
      exists (
        select 1
        from public.memberships m
        where m.tenant_id = i.tenant_id
          and m.user_id = i.created_by
          and m.facility_id = p_facility_id
          and m.status = 'active'
          and m.valid_from <= p_snapshot_timestamp
          and (m.valid_until is null or m.valid_until > p_snapshot_timestamp)
      )
      or exists (
        select 1
        from public.bed_assignments ba
        join public.beds b on b.id = ba.bed_id
        join public.wards w on w.id = b.ward_id
        where ba.tenant_id = i.tenant_id
          and ba.encounter_id = i.encounter_id
          and w.facility_id = p_facility_id
      )
    );

  select count(*)
  into v_released_24h
  from public.bed_assignments ba
  join public.beds b on b.id = ba.bed_id
  join public.wards w on w.id = b.ward_id
  where ba.tenant_id = p_tenant_id
    and w.facility_id = p_facility_id
    and ba.status = 'released'
    and ba.released_at >= p_snapshot_timestamp - interval '24 hours'
    and ba.released_at <= p_snapshot_timestamp;

  select avg(
    extract(epoch from (ba.released_at - ba.admitted_at)) / 86400.0
  )
  into v_alos
  from public.bed_assignments ba
  join public.beds b on b.id = ba.bed_id
  join public.wards w on w.id = b.ward_id
  where ba.tenant_id = p_tenant_id
    and w.facility_id = p_facility_id
    and ba.status = 'released'
    and ba.released_at >= p_snapshot_timestamp - interval '30 days'
    and ba.released_at <= p_snapshot_timestamp;

  if v_alos is null then
    select avg(
      extract(epoch from (p_snapshot_timestamp - ba.admitted_at)) / 86400.0
    )
    into v_alos
    from public.bed_assignments ba
    join public.beds b on b.id = ba.bed_id
    join public.wards w on w.id = b.ward_id
    where ba.tenant_id = p_tenant_id
      and w.facility_id = p_facility_id
      and ba.status = 'active';
  end if;

  v_occupancy := case
    when v_beds > 0
      then least(round(v_occupied * 100.0 / v_beds, 2), 100.00)
    else 0
  end;
  v_turnover := case
    when v_beds > 0
      then round(v_released_24h * 100.0 / v_beds, 2)
    else 0
  end;

  insert into public.executive_kpi_snapshots (
    tenant_id,
    facility_id,
    snapshot_timestamp,
    occupancy_rate,
    active_inpatients,
    er_waiting_count,
    daily_gross_revenue,
    daily_net_revenue,
    bed_turnover_rate,
    average_length_of_stay_days
  )
  values (
    p_tenant_id,
    p_facility_id,
    p_snapshot_timestamp,
    v_occupancy,
    v_occupied,
    v_er_waiting,
    v_gross,
    greatest(v_gross - v_refunds, 0),
    v_turnover,
    coalesce(round(v_alos, 2), 0)
  )
  on conflict (facility_id, snapshot_timestamp) do nothing
  returning * into v_row;

  if v_row.id is null then
    select *
    into v_row
    from public.executive_kpi_snapshots
    where facility_id = p_facility_id
      and snapshot_timestamp = p_snapshot_timestamp;
  end if;

  return v_row;
end;
$$;

comment on function nodex.capture_executive_kpi_snapshot(uuid, uuid, timestamptz) is
  'Captures one facility executive reading. Idempotent for a facility and timestamp; the caller schedules it, the function derives every figure.';

-- Captures every active facility in one transaction window. A scheduler calls
-- this; the repository deliberately does not depend on pg_cron being present.
create or replace function nodex.capture_all_executive_kpi_snapshots(
  p_snapshot_timestamp timestamptz default now()
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_facility record;
  v_count integer := 0;
begin
  for v_facility in
    select f.tenant_id, f.id
    from public.facilities f
    where f.status = 'active'
    order by f.tenant_id, f.id
  loop
    perform nodex.capture_executive_kpi_snapshot(
      v_facility.tenant_id,
      v_facility.id,
      p_snapshot_timestamp
    );
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

comment on function nodex.capture_all_executive_kpi_snapshots(timestamptz) is
  'Captures an executive reading for every active facility. Intended for a server scheduler; returns the facility count.';

revoke all on function nodex.capture_executive_kpi_snapshot(uuid, uuid, timestamptz)
  from public;
revoke all on function nodex.capture_all_executive_kpi_snapshots(timestamptz)
  from public;
grant execute on function nodex.capture_executive_kpi_snapshot(uuid, uuid, timestamptz)
  to service_role;
grant execute on function nodex.capture_all_executive_kpi_snapshots(timestamptz)
  to service_role;

alter table public.executive_kpi_snapshots enable row level security;
alter table public.executive_kpi_snapshots force row level security;

-- Executives read the facilities they are scoped to. The capture job inserts
-- as postgres; no client role holds an insert policy, because a fabricated
-- snapshot would be indistinguishable from a measured one.
create policy executive_kpi_select_reader
  on public.executive_kpi_snapshots
  for select to authenticated
  using (
    nodex.has_permission(tenant_id, 'executive.read')
    and nodex.has_facility_access(tenant_id, facility_id)
  );
create policy executive_kpi_insert_capture
  on public.executive_kpi_snapshots
  for insert to postgres
  with check (true);

insert into public.permissions
  (key, display_name, description, module_code, risk_tier, requires_online)
values
  ('executive.read', 'Read the executive dashboard',
   'View enterprise KPI snapshots: occupancy, inpatient census, emergency queue, revenue, bed turnover and length of stay.',
   'M01', 'standard', false)
on conflict (key) do nothing;

insert into public.role_permissions (role_key, permission_key)
values
  ('hospital_super_admin', 'executive.read'),
  ('medical_officer',      'executive.read'),
  ('auditor',              'executive.read')
on conflict do nothing;
