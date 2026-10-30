"""Offline scope tests for the Nodex PowerSync sync config.

Builds an in-memory SQLite database with the columns the streams reference,
seeds synthetic tenants/users/patients/beds, then runs every stream query with
auth.user_id() replaced by a literal. This tests the scope logic, not the
PowerSync service.

The config uses composite (tenant_id, patient_id) scope CTEs. SQLite executes
the same join predicates, so a regression that drops the tenant half of a join
fails here before a deploy.

Run: python3 powersync/tests/test_sync_scope.py
"""

from __future__ import annotations

import sqlite3
from pathlib import Path

import yaml

CONFIG = Path(__file__).resolve().parents[1] / "sync-config.yaml"

T1 = "00000000-0000-0000-0000-000000000001"
T2 = "00000000-0000-0000-0000-000000000002"
F1 = "10000000-0000-0000-0000-000000000001"
F2 = "10000000-0000-0000-0000-000000000002"
F3 = "10000000-0000-0000-0000-000000000003"
W1 = "20000000-0000-0000-0000-000000000001"
W2 = "20000000-0000-0000-0000-000000000002"
W3 = "20000000-0000-0000-0000-000000000003"
W4 = "20000000-0000-0000-0000-000000000004"

D = "30000000-0000-0000-0000-00000000000d"
N = "30000000-0000-0000-0000-00000000000e"
B = "30000000-0000-0000-0000-00000000000b"
P = "30000000-0000-0000-0000-00000000000f"
DU = "30000000-0000-0000-0000-000000000010"
DX = "30000000-0000-0000-0000-000000000011"
DEXP = "30000000-0000-0000-0000-000000000012"
DSUS = "30000000-0000-0000-0000-000000000013"
DPRESWEEP = "30000000-0000-0000-0000-000000000014"

PA = "40000000-0000-0000-0000-00000000000a"
PB = "40000000-0000-0000-0000-00000000000b"
PC = "40000000-0000-0000-0000-00000000000c"
PD = "40000000-0000-0000-0000-00000000000d"
PE = "40000000-0000-0000-0000-00000000000e"
PX = "40000000-0000-0000-0000-00000000000f"
PY = "40000000-0000-0000-0000-000000000010"

BED1 = "50000000-0000-0000-0000-000000000001"
BED2 = "50000000-0000-0000-0000-000000000002"
BED3 = "50000000-0000-0000-0000-000000000003"
BA1 = "60000000-0000-0000-0000-000000000001"
BA2 = "60000000-0000-0000-0000-000000000002"
BA3 = "60000000-0000-0000-0000-000000000003"
BA4 = "60000000-0000-0000-0000-000000000004"

DA1 = "70000000-0000-0000-0000-000000000001"
DA2 = "70000000-0000-0000-0000-000000000002"
DA3 = "70000000-0000-0000-0000-000000000003"
DA4 = "70000000-0000-0000-0000-000000000004"
DA5 = "70000000-0000-0000-0000-000000000005"
DA6 = "70000000-0000-0000-0000-000000000006"
DA7 = "70000000-0000-0000-0000-000000000007"
DA8 = "70000000-0000-0000-0000-000000000008"

DDL = """
create table tenants (id text primary key, slug text, display_name text, legal_name text,
  country_code text, timezone text, locale text, status text, settings text, created_at text, updated_at text);
create table facilities (id text primary key, tenant_id text, code text, display_name text,
  facility_type text, timezone text, address text, status text, created_at text, updated_at text);
create table departments (id text primary key, tenant_id text, facility_id text, code text,
  display_name text, specialty text, head_user_id text, status text, created_at text, updated_at text);
create table wards (id text primary key, tenant_id text, facility_id text, department_id text,
  code text, display_name text, ward_type text, floor_label text, bed_capacity integer,
  status text, created_at text, updated_at text);
create table app_users (id text primary key, primary_tenant_id text, employee_code text,
  full_name text, display_name text, email text, phone text, designation text,
  registration_no text, status text, locale text, avatar_path text, last_login_at text,
  created_at text, updated_at text);
create table memberships (id text primary key, tenant_id text, user_id text, role_key text,
  facility_id text, department_id text, ward_id text, status text, valid_from text,
  valid_until text, granted_by text, created_at text, updated_at text);
create table devices (id text primary key, tenant_id text, device_fingerprint text,
  display_name text, platform text, form_factor text, os_version text, app_version text,
  enrolled_by text, assigned_user_id text, assigned_facility_id text, status text,
  offline_window_minutes integer, last_seen_at text, last_sync_at text, revoked_at text,
  revoked_reason text, wipe_requested_at text, wipe_confirmed_at text, created_at text, updated_at text);
create table patients (id text primary key, tenant_id text, mrn text, national_id_hash text,
  first_name text, last_name text, date_of_birth text, gender text, blood_group text,
  phone_number text, is_active integer, created_by text, created_at text, updated_at text,
  email text, address text, next_of_kin text, occupation text, marital_status text,
  preferred_language text);
create table patient_merge_history (id text primary key, tenant_id text,
  surviving_patient_id text, merged_patient_id text, merged_by text, reason text,
  field_choices text, created_at text);
create table patient_allergies (id text primary key, tenant_id text, patient_id text,
  substance text, reaction text, severity text, status text, retired_reason text,
  recorded_by text, recorded_at text, retired_at text, created_at text);
create table clinical_encounters (id text primary key, tenant_id text, patient_id text,
  attending_physician_id text, encounter_type text, status text, subjective_note text,
  objective_findings text, assessment text, plan_description text, diagnoses text,
  signed_at text, created_by text, created_at text, updated_at text);
create table clinical_problems (id text primary key, tenant_id text, patient_id text,
  encounter_id text, problem_code text, description text, clinical_status text,
  onset_date text, resolved_at text, resolution_note text, recorded_by text,
  resolved_by text, created_at text, updated_at text);
create table encounter_amendments (id text primary key, tenant_id text, encounter_id text,
  amendment_type text, reason text, field_changes text, amended_by text, created_at text);
create table doctor_assignments (id text primary key, tenant_id text, doctor_id text,
  patient_id text, assignment_type text, status text, assigned_at text, concluded_at text,
  created_at text, updated_at text);
create table beds (id text primary key, tenant_id text, ward_id text, bed_code text,
  bed_type text, status text, created_at text, updated_at text);
create table bed_assignments (id text primary key, tenant_id text, bed_id text, patient_id text,
  encounter_id text, assigned_by text, status text, admitted_at text, released_at text,
  release_reason text, created_at text, updated_at text);
create table roles (key text primary key, display_name text, description text, role_class text,
  is_privileged integer, offline_capable integer);
create table permissions (key text primary key, display_name text, description text,
  module_code text, risk_tier text, requires_online integer);
create table role_permissions (role_key text, permission_key text, created_at text,
  primary key (role_key, permission_key));
"""

SEED = [
    ("insert into tenants (id, display_name, status) values (?, 'Tenant A', 'active')", (T1,)),
    ("insert into tenants (id, display_name, status) values (?, 'Tenant B', 'active')", (T2,)),
    ("insert into facilities (id, tenant_id, display_name, status) values (?, ?, 'F1', 'active')", (F1, T1)),
    ("insert into facilities (id, tenant_id, display_name, status) values (?, ?, 'F2', 'active')", (F2, T1)),
    ("insert into facilities (id, tenant_id, display_name, status) values (?, ?, 'F3', 'active')", (F3, T2)),
    ("insert into wards (id, tenant_id, facility_id, display_name, status) values (?, ?, ?, 'W1', 'active')", (W1, T1, F1)),
    ("insert into wards (id, tenant_id, facility_id, display_name, status) values (?, ?, ?, 'W2', 'active')", (W2, T1, F2)),
    ("insert into wards (id, tenant_id, facility_id, display_name, status) values (?, ?, ?, 'W3', 'active')", (W3, T2, F3)),
    ("insert into wards (id, tenant_id, facility_id, display_name, status) values (?, ?, ?, 'W4', 'active')", (W4, T1, F2)),
    ("insert into app_users (id, primary_tenant_id, full_name, status) values (?, ?, 'Doctor', 'active')", (D, T1)),
    ("insert into app_users (id, primary_tenant_id, full_name, status) values (?, ?, 'Nurse', 'active')", (N, T1)),
    ("insert into app_users (id, primary_tenant_id, full_name, status) values (?, ?, 'Billing', 'active')", (B, T1)),
    ("insert into app_users (id, primary_tenant_id, full_name, status) values (?, ?, 'Portal', 'active')", (P, T1)),
    ("insert into app_users (id, primary_tenant_id, full_name, status) values (?, ?, 'Unassigned', 'active')", (DU, T1)),
    ("insert into app_users (id, primary_tenant_id, full_name, status) values (?, ?, 'Doctor B', 'active')", (DX, T2)),
    ("insert into app_users (id, primary_tenant_id, full_name, status) values (?, ?, 'Expired', 'active')", (DEXP, T1)),
    ("insert into app_users (id, primary_tenant_id, full_name, status) values (?, ?, 'Suspended', 'active')", (DSUS, T1)),
    ("insert into app_users (id, primary_tenant_id, full_name, status) values (?, ?, 'Pre-sweep', 'active')", (DPRESWEEP, T1)),
    ("insert into memberships (id, tenant_id, user_id, role_key, facility_id, ward_id, status, valid_until) values ('m-d', ?, ?, 'medical_officer', null, null, 'active', null)", (T1, D)),
    ("insert into memberships (id, tenant_id, user_id, role_key, facility_id, ward_id, status, valid_until) values ('m-n', ?, ?, 'nursing_staff', ?, ?, 'active', null)", (T1, N, F1, W1)),
    ("insert into memberships (id, tenant_id, user_id, role_key, facility_id, ward_id, status, valid_until) values ('m-b', ?, ?, 'billing_accounts', null, null, 'active', null)", (T1, B)),
    ("insert into memberships (id, tenant_id, user_id, role_key, facility_id, ward_id, status, valid_until) values ('m-p', ?, ?, 'patient', null, null, 'active', null)", (T1, P)),
    ("insert into memberships (id, tenant_id, user_id, role_key, facility_id, ward_id, status, valid_until) values ('m-du', ?, ?, 'medical_officer', ?, ?, 'active', null)", (T1, DU, F2, W4)),
    ("insert into memberships (id, tenant_id, user_id, role_key, facility_id, ward_id, status, valid_until) values ('m-dx', ?, ?, 'medical_officer', null, null, 'active', null)", (T2, DX)),
    ("insert into memberships (id, tenant_id, user_id, role_key, facility_id, ward_id, status, valid_until) values ('m-dexp', ?, ?, 'medical_officer', null, null, 'expired', '2020-01-01T00:00:00Z')", (T1, DEXP)),
    ("insert into memberships (id, tenant_id, user_id, role_key, facility_id, ward_id, status, valid_until) values ('m-dsus', ?, ?, 'medical_officer', null, null, 'suspended', null)", (T1, DSUS)),
    ("insert into memberships (id, tenant_id, user_id, role_key, facility_id, ward_id, status, valid_until) values ('m-dpresweep', ?, ?, 'medical_officer', null, null, 'active', '2020-01-01T00:00:00Z')", (T1, DPRESWEEP)),
    ("insert into roles values ('medical_officer', 'Medical Officer', null, 'clinical', 1, 1)", ()),
    ("insert into roles values ('nursing_staff', 'Nursing Staff', null, 'nursing', 0, 1)", ()),
    ("insert into roles values ('billing_accounts', 'Billing', null, 'financial', 1, 1)", ()),
    ("insert into roles values ('patient', 'Patient', null, 'patient', 0, 1)", ()),
    ("insert into roles values ('hospital_super_admin', 'Admin', null, 'administrative', 1, 0)", ()),
    ("insert into permissions values ('patient.read', 'Read patients', null, 'M01', 'standard', 0)", ()),
    ("insert into permissions values ('encounter.read', 'Read encounters', null, 'M02', 'standard', 0)", ()),
    ("insert into permissions values ('portal.access', 'Portal access', null, 'M40', 'standard', 0)", ()),
    ("insert into role_permissions values ('medical_officer', 'patient.read', null)", ()),
    ("insert into role_permissions values ('medical_officer', 'encounter.read', null)", ()),
    ("insert into role_permissions values ('nursing_staff', 'patient.read', null)", ()),
    ("insert into role_permissions values ('nursing_staff', 'encounter.read', null)", ()),
    ("insert into role_permissions values ('billing_accounts', 'patient.read', null)", ()),
    ("insert into role_permissions values ('patient', 'portal.access', null)", ()),
    ("insert into devices (id, tenant_id, assigned_user_id, status, revoked_at) values ('dev-d-active', ?, ?, 'active', null)", (T1, D)),
    ("insert into devices (id, tenant_id, assigned_user_id, status, revoked_at) values ('dev-d-revoked', ?, ?, 'revoked', '2020-01-01T00:00:00Z')", (T1, D)),
    ("insert into devices (id, tenant_id, assigned_user_id, status, revoked_at) values ('dev-n', ?, ?, 'active', null)", (T1, N)),
    ("insert into patients (id, tenant_id, first_name, is_active) values (?, ?, 'PA', 1)", (PA, T1)),
    ("insert into patients (id, tenant_id, first_name, is_active) values (?, ?, 'PB', 1)", (PB, T1)),
    ("insert into patients (id, tenant_id, first_name, is_active) values (?, ?, 'PC', 1)", (PC, T1)),
    ("insert into patients (id, tenant_id, first_name, is_active) values (?, ?, 'PD', 1)", (PD, T1)),
    ("insert into patients (id, tenant_id, first_name, is_active) values (?, ?, 'PE', 1)", (PE, T1)),
    ("insert into patients (id, tenant_id, first_name, is_active) values (?, ?, 'PX', 1)", (PX, T2)),
    ("insert into patients (id, tenant_id, first_name, is_active) values (?, ?, 'PY', 1)", (PY, T2)),
    ("insert into beds (id, tenant_id, ward_id, bed_code, status) values (?, ?, ?, 'B1', 'available')", (BED1, T1, W1)),
    ("insert into beds (id, tenant_id, ward_id, bed_code, status) values (?, ?, ?, 'B2', 'available')", (BED2, T1, W2)),
    ("insert into beds (id, tenant_id, ward_id, bed_code, status) values (?, ?, ?, 'B3', 'available')", (BED3, T2, W3)),
    ("insert into bed_assignments (id, tenant_id, bed_id, patient_id, status) values (?, ?, ?, ?, 'active')", (BA1, T1, BED1, PB)),
    ("insert into bed_assignments (id, tenant_id, bed_id, patient_id, status) values (?, ?, ?, ?, 'active')", (BA2, T1, BED2, PA)),
    ("insert into bed_assignments (id, tenant_id, bed_id, patient_id, status) values (?, ?, ?, ?, 'active')", (BA3, T2, BED3, PX)),
    # A malformed cross-tenant assignment: tenant A names a tenant B bed and
    # patient. The tenant-equality joins must exclude it everywhere.
    ("insert into bed_assignments (id, tenant_id, bed_id, patient_id, status) values (?, ?, ?, ?, 'active')", (BA4, T1, BED3, PX)),
    ("insert into doctor_assignments (id, tenant_id, doctor_id, patient_id, status) values (?, ?, ?, ?, 'active')", (DA1, T1, D, PA)),
    ("insert into doctor_assignments (id, tenant_id, doctor_id, patient_id, status) values (?, ?, ?, ?, 'concluded')", (DA2, T1, D, PD)),
    ("insert into doctor_assignments (id, tenant_id, doctor_id, patient_id, status) values (?, ?, ?, ?, 'active')", (DA3, T2, DX, PX)),
    ("insert into doctor_assignments (id, tenant_id, doctor_id, patient_id, status) values (?, ?, ?, ?, 'active')", (DA4, T1, D, PX)),
    ("insert into doctor_assignments (id, tenant_id, doctor_id, patient_id, status) values (?, ?, ?, ?, 'active')", (DA5, T1, DEXP, PA)),
    ("insert into doctor_assignments (id, tenant_id, doctor_id, patient_id, status) values (?, ?, ?, ?, 'active')", (DA6, T1, DSUS, PA)),
    ("insert into doctor_assignments (id, tenant_id, doctor_id, patient_id, status) values (?, ?, ?, ?, 'active')", (DA7, T1, DU, PB)),
    ("insert into doctor_assignments (id, tenant_id, doctor_id, patient_id, status) values (?, ?, ?, ?, 'active')", (DA8, T1, DPRESWEEP, PA)),
    ("insert into clinical_encounters (id, tenant_id, patient_id, attending_physician_id, status) values ('e-a', ?, ?, ?, 'in_progress')", (T1, PA, D)),
    ("insert into clinical_encounters (id, tenant_id, patient_id, attending_physician_id, status) values ('e-b', ?, ?, ?, 'in_progress')", (T1, PB, DU)),
    ("insert into clinical_encounters (id, tenant_id, patient_id, attending_physician_id, status) values ('e-c', ?, ?, ?, 'planned')", (T1, PC, D)),
    ("insert into clinical_encounters (id, tenant_id, patient_id, attending_physician_id, status) values ('e-d', ?, ?, ?, 'signed_and_locked')", (T1, PD, DU)),
    ("insert into clinical_encounters (id, tenant_id, patient_id, attending_physician_id, status) values ('e-e', ?, ?, ?, 'in_progress')", (T1, PE, D)),
    ("insert into clinical_encounters (id, tenant_id, patient_id, attending_physician_id, status) values ('e-f', ?, ?, ?, 'signed_and_locked')", (T1, PD, D)),
    ("insert into clinical_encounters (id, tenant_id, patient_id, attending_physician_id, status) values ('e-x', ?, ?, ?, 'in_progress')", (T2, PX, DX)),
    # A tenant A encounter naming a tenant B patient. The patient join must
    # reject it because patients.tenant_id does not match the encounter tenant.
    ("insert into clinical_encounters (id, tenant_id, patient_id, attending_physician_id, status) values ('e-spoof', ?, ?, ?, 'in_progress')", (T1, PX, D)),
    ("insert into patient_allergies (id, tenant_id, patient_id, substance) values ('al-a', ?, ?, 'A')", (T1, PA)),
    ("insert into patient_allergies (id, tenant_id, patient_id, substance) values ('al-b', ?, ?, 'B')", (T1, PB)),
    ("insert into patient_allergies (id, tenant_id, patient_id, substance) values ('al-c', ?, ?, 'C')", (T1, PC)),
    ("insert into patient_allergies (id, tenant_id, patient_id, substance) values ('al-d', ?, ?, 'D')", (T1, PD)),
    ("insert into patient_allergies (id, tenant_id, patient_id, substance) values ('al-e', ?, ?, 'E')", (T1, PE)),
    ("insert into patient_allergies (id, tenant_id, patient_id, substance) values ('al-x', ?, ?, 'X')", (T2, PX)),
    ("insert into clinical_problems (id, tenant_id, patient_id) values ('pr-a', ?, ?)", (T1, PA)),
    ("insert into clinical_problems (id, tenant_id, patient_id) values ('pr-b', ?, ?)", (T1, PB)),
    ("insert into clinical_problems (id, tenant_id, patient_id) values ('pr-c', ?, ?)", (T1, PC)),
    ("insert into clinical_problems (id, tenant_id, patient_id) values ('pr-d', ?, ?)", (T1, PD)),
    ("insert into clinical_problems (id, tenant_id, patient_id) values ('pr-e', ?, ?)", (T1, PE)),
    ("insert into clinical_problems (id, tenant_id, patient_id) values ('pr-x', ?, ?)", (T2, PX)),
    ("insert into encounter_amendments (id, tenant_id, encounter_id) values ('am-a', ?, 'e-a')", (T1,)),
    ("insert into encounter_amendments (id, tenant_id, encounter_id) values ('am-b', ?, 'e-b')", (T1,)),
    ("insert into encounter_amendments (id, tenant_id, encounter_id) values ('am-c', ?, 'e-c')", (T1,)),
    ("insert into encounter_amendments (id, tenant_id, encounter_id) values ('am-d', ?, 'e-d')", (T1,)),
    ("insert into encounter_amendments (id, tenant_id, encounter_id) values ('am-e', ?, 'e-e')", (T1,)),
    ("insert into encounter_amendments (id, tenant_id, encounter_id) values ('am-f', ?, 'e-f')", (T1,)),
    ("insert into encounter_amendments (id, tenant_id, encounter_id) values ('am-x', ?, 'e-x')", (T2,)),
]


def load_config() -> dict:
    with CONFIG.open("r", encoding="utf-8") as handle:
        return yaml.safe_load(handle)


def build_db(config: dict) -> sqlite3.Connection:
    db = sqlite3.connect(":memory:")
    db.executescript(DDL)
    for statement, params in SEED:
        db.execute(statement, params)
    return db


def query_list(stream: dict) -> list[str]:
    return stream.get("queries") or [stream["query"]]


def run_rows(db: sqlite3.Connection, config: dict, query: str, user_id: str) -> list[sqlite3.Row]:
    cte_sql = ", ".join(
        f"{name} AS ({sql.strip()})" for name, sql in config["with"].items()
    )
    sql = f"WITH {cte_sql} {query}".replace("auth.user_id()", f"'{user_id}'")
    db.row_factory = sqlite3.Row
    return db.execute(sql).fetchall()


def run_ids(db: sqlite3.Connection, config: dict, query: str, user_id: str) -> list[str]:
    return sorted({str(row[0]) for row in run_rows(db, config, query, user_id)})


def stream_ids(db: sqlite3.Connection, config: dict, stream_name: str, user_id: str) -> list[str]:
    found: set[str] = set()
    for query in query_list(config["streams"][stream_name]):
        found.update(run_ids(db, config, query, user_id))
    return sorted(found)


def check(name: str, actual: list[str], expected: list[str]) -> None:
    if actual != sorted(expected):
        raise AssertionError(f"{name}: expected {sorted(expected)}, got {actual}")
    print(f"ok  {name}")


def main() -> None:
    config = load_config()
    db = build_db(config)

    # Identity. The revoked device stays in the stream on purpose so the client
    # can learn that it was revoked.
    identity = query_list(config["streams"]["identity"])
    check("D own app_user", run_ids(db, config, identity[0], D), [D])
    check("D own membership", run_ids(db, config, identity[1], D), ["m-d"])
    device_rows = run_rows(db, config, identity[2], D)
    check(
        "D devices include revoked status",
        sorted(f"{row['id']}:{row['status']}" for row in device_rows),
        ["dev-d-active:active", "dev-d-revoked:revoked"],
    )
    check("P own app_user", run_ids(db, config, identity[0], P), [P])

    # Tenant master data.
    check("D tenant master", stream_ids(db, config, "tenant_master", D), [T1, F1, F2, W1, W2, W4])
    check("DX tenant master", stream_ids(db, config, "tenant_master", DX), [T2, F3, W3])
    check("facility-scoped nurse tenant master", stream_ids(db, config, "tenant_master", N), [T1, F1, W1])
    check("facility-scoped doctor tenant master", stream_ids(db, config, "tenant_master", DU), [T1, F2, W2, W4])
    check("expired membership tenant master", stream_ids(db, config, "tenant_master", DEXP), [])
    check("suspended membership tenant master", stream_ids(db, config, "tenant_master", DSUS), [])

    # Patients: assignment, active encounter, and ward/bed scope, all tenant-paired.
    check("doctor patients", stream_ids(db, config, "patients", D), [PA, PB, PC, PE])
    check("ward nurse patients", stream_ids(db, config, "patients", N), [PB])
    check("billing patients", stream_ids(db, config, "patients", B), [PA, PB])
    check("portal patients", stream_ids(db, config, "patients", P), [])
    check("tenant B doctor patients", stream_ids(db, config, "patients", DX), [PX])
    check("expired membership patients", stream_ids(db, config, "patients", DEXP), [])
    check("suspended membership patients", stream_ids(db, config, "patients", DSUS), [])
    check("unassigned doctor patients", stream_ids(db, config, "patients", DU), [PB])
    # A pre-sweep membership is still status=active; the sweep is what removes
    # the scope. The write guard still blocks at the exact expiry instant.
    check("pre-sweep membership patients", stream_ids(db, config, "patients", DPRESWEEP), [PA, PB])
    db.execute("update memberships set status = 'expired' where id = 'm-dpresweep'")
    check("post-sweep membership patients", stream_ids(db, config, "patients", DPRESWEEP), [])
    db.execute("update memberships set status = 'active' where id = 'm-dpresweep'")

    # Cross-tenant spoofing. D holds a tenant A assignment to tenant B's PX,
    # and tenant A's bed assignment points at tenant B's bed. Neither may grant
    # scope, and PX must not appear through the tenant A encounter either.
    check("doctor excludes cross-tenant spoof patient", stream_ids(db, config, "patients", D), [PA, PB, PC, PE])
    check("tenant B patient not leaked to A", stream_ids(db, config, "patients", DX), [PX])

    # Clinical records follow the patient scope and the encounter.read gate.
    clinical = query_list(config["streams"]["patient_clinical"])
    allergies = clinical[0:3]
    encounters = clinical[3:6]
    problems = clinical[6:9]
    amendments = clinical[9:12]

    check("doctor allergies", sorted({x for q in allergies for x in run_ids(db, config, q, D)}),
          ["al-a", "al-b", "al-c", "al-e"])
    check("nurse allergies", sorted({x for q in allergies for x in run_ids(db, config, q, N)}), ["al-b"])
    check("billing allergies", sorted({x for q in allergies for x in run_ids(db, config, q, B)}), [])
    check("portal allergies", sorted({x for q in allergies for x in run_ids(db, config, q, P)}), [])

    check("doctor encounters", sorted({x for q in encounters for x in run_ids(db, config, q, D)}),
          ["e-a", "e-b", "e-c", "e-e"])
    check("nurse encounters", sorted({x for q in encounters for x in run_ids(db, config, q, N)}), ["e-b"])
    check("billing encounters", sorted({x for q in encounters for x in run_ids(db, config, q, B)}), [])
    check("portal encounters", sorted({x for q in encounters for x in run_ids(db, config, q, P)}), [])

    check("doctor problems", sorted({x for q in problems for x in run_ids(db, config, q, D)}),
          ["pr-a", "pr-b", "pr-c", "pr-e"])
    check("nurse problems", sorted({x for q in problems for x in run_ids(db, config, q, N)}), ["pr-b"])
    check("billing problems", sorted({x for q in problems for x in run_ids(db, config, q, B)}), [])
    check("portal problems", sorted({x for q in problems for x in run_ids(db, config, q, P)}), [])

    check("doctor amendments", sorted({x for q in amendments for x in run_ids(db, config, q, D)}),
          ["am-a", "am-b", "am-c", "am-e"])
    check("nurse amendments", sorted({x for q in amendments for x in run_ids(db, config, q, N)}), ["am-b"])
    check("billing amendments", sorted({x for q in amendments for x in run_ids(db, config, q, B)}), [])
    check("portal amendments", sorted({x for q in amendments for x in run_ids(db, config, q, P)}), [])

    # Signed encounter does not grant scope after the assignment is concluded.
    check("signed encounter excluded", stream_ids(db, config, "patients", D), [PA, PB, PC, PE])

    # Doctor assignments. The patient join rejects the cross-tenant DA4 row.
    check("doctor own assignments", stream_ids(db, config, "doctor_assignments", D), [DA1])
    check("tenant B doctor assignments", stream_ids(db, config, "doctor_assignments", DX), [DA3])
    check("nurse own assignments", stream_ids(db, config, "doctor_assignments", N), [])

    # Ward census.
    census = query_list(config["streams"]["ward_census"])
    check("doctor beds", run_ids(db, config, census[0], D), [BED1, BED2])
    check("nurse beds", run_ids(db, config, census[0], N), [BED1])
    check("billing beds", run_ids(db, config, census[0], B), [BED1, BED2])
    check("portal beds", run_ids(db, config, census[0], P), [])
    check("tenant B doctor beds", run_ids(db, config, census[0], DX), [BED3])

    # Bed assignments. BA4 is the cross-tenant spoof and must never appear.
    check("doctor bed assignments", run_ids(db, config, census[1], D), [BA1, BA2])
    check("nurse bed assignments", run_ids(db, config, census[1], N), [BA1])
    check("billing bed assignments", run_ids(db, config, census[1], B), [BA1, BA2])
    check("tenant B doctor bed assignments", run_ids(db, config, census[1], DX), [BA3])

    # Catalog IDs are synthetic and deterministic.
    catalog = query_list(config["streams"]["catalog"])
    check("catalog roles", run_ids(db, config, catalog[0], D),
          ["billing_accounts", "hospital_super_admin", "medical_officer",
           "nursing_staff", "patient"])
    check("catalog permissions", run_ids(db, config, catalog[1], D),
          ["encounter.read", "patient.read", "portal.access"])
    check("catalog role grants", run_ids(db, config, catalog[2], D),
          ["billing_accounts:patient.read", "medical_officer:encounter.read",
           "medical_officer:patient.read", "nursing_staff:encounter.read",
           "nursing_staff:patient.read", "patient:portal.access"])

    # Suspended and expired memberships lose all scope.
    db.execute("update memberships set status = 'suspended' where id = 'm-n'")
    check("suspended nurse patients", stream_ids(db, config, "patients", N), [])
    check("suspended nurse beds", stream_ids(db, config, "ward_census", N), [])
    check("suspended nurse encounters", sorted({x for q in encounters for x in run_ids(db, config, q, N)}), [])
    db.execute("update memberships set status = 'active' where id = 'm-n'")

    # A revoked role grant removes scope immediately.
    db.execute("delete from role_permissions where role_key = 'nursing_staff' and permission_key = 'patient.read'")
    check("revoked grant nurse patients", stream_ids(db, config, "patients", N), [])
    check("revoked grant nurse beds", stream_ids(db, config, "ward_census", N), [])
    db.execute("insert into role_permissions values ('nursing_staff', 'patient.read', null)")
    check("restored grant nurse patients", stream_ids(db, config, "patients", N), [PB])

    print("\nall scope assertions passed")


if __name__ == "__main__":
    main()
