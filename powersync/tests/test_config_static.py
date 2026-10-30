"""Static checks for the Nodex PowerSync configuration and remediation.

These checks run without a database, the PowerSync CLI or a Supabase project.
They catch drift between the sync config, the source-database setup, the
authorization migrations, the mutation handler and the synthetic test fixtures.

They do not prove SQL or TypeScript compiles. The parser limitations are
documented in powersync/tests/README.md.

Run: python3 powersync/tests/test_config_static.py
"""

from __future__ import annotations

import re
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]
APP_ROOT = ROOT / "nodex_hms" if (ROOT / "nodex_hms").is_dir() else ROOT
POWERSYNC = ROOT / "powersync"
MIGRATIONS = APP_ROOT / "supabase" / "migrations"
HANDLER = APP_ROOT / "supabase" / "functions" / "mutation-handler" / "index.ts"

SYNC = POWERSYNC / "sync-config.yaml"
SOURCE = POWERSYNC / "SOURCE_DB_SETUP.sql"
LOCAL_SCHEMA = APP_ROOT / "lib" / "core" / "storage" / "local_schema.dart"
SERVICE = POWERSYNC / "service.yaml"
SEED = POWERSYNC / "dev-seed.sql"
AUTHZ = POWERSYNC / "tests" / "authorization.sql"

MIGRATION_A = MIGRATIONS / "20260918160000_phase4_patient_mutation_authorization.sql"
MIGRATION_B = MIGRATIONS / "20260918170000_phase4_membership_expiry.sql"
COVERAGE_MIGRATION = MIGRATIONS / "20260918200001_expand_powersync_full_coverage.sql"

# Tables the original SOURCE_DB_SETUP.sql published. The full-coverage migration
# extends this set to every replicated table in the local schema.
INITIAL_TABLES = {
    "app_users",
    "memberships",
    "devices",
    "tenants",
    "facilities",
    "departments",
    "wards",
    "patients",
    "patient_allergies",
    "clinical_encounters",
    "clinical_problems",
    "encounter_amendments",
    "doctor_assignments",
    "beds",
    "bed_assignments",
}
CATALOG_TABLES = {"roles", "permissions", "role_permissions"}
INITIAL_ALL_TABLES = INITIAL_TABLES | CATALOG_TABLES


def local_tables() -> set[str]:
    """Replicated tables declared in the Dart local schema."""
    text = LOCAL_SCHEMA.read_text(encoding="utf-8")
    constants = dict(
        re.findall(r"static const String (\w+)\s*=\s*\n?\s*'([a-z0-9_]+)';", text)
    )
    return {
        constants[name]
        for name in re.findall(
            r"static const Table _\w+ = Table\(\s*LocalTables\.(\w+)", text
        )
    }


ALL_TABLES = local_tables()

# Sync Streams grammar restrictions. A query that uses one of these fails
# validation before a deploy, so fail here instead.
UNSUPPORTED_SQL = (
    "DISTINCT",
    "GROUP BY",
    "ORDER BY",
    "LIMIT",
    "UNION",
    "INTERSECT",
    "EXCEPT",
    "LEFT JOIN",
    "RIGHT JOIN",
    "FULL JOIN",
    "OUTER JOIN",
    "NOW()",
    "CURRENT_TIMESTAMP",
)


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def check(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def ok(message: str) -> None:
    print(f"ok  {message}")


def stream_queries(config: dict) -> dict[str, list[str]]:
    result: dict[str, list[str]] = {}
    for name, stream in config["streams"].items():
        if not isinstance(stream, dict):
            continue
        queries = stream.get("queries")
        if queries is None:
            queries = [stream["query"]]
        result[name] = [str(query) for query in queries]
    return result


def table_refs(sql: str) -> set[str]:
    return {
        match.group(1).lower()
        for match in re.finditer(r"\b(?:FROM|JOIN)\s+([A-Za-z_][A-Za-z0-9_]*)", sql, re.I)
    }


def duplicate_mapping_keys(text: str) -> list[tuple[str, int, int]]:
    """Return (path, first line, duplicate line) for every duplicate YAML key.

    yaml.safe_load silently keeps the last value, so a duplicated stream name
    would drop the earlier, reviewed definition without any error.
    """
    duplicates: list[tuple[str, int, int]] = []

    def walk(node: yaml.nodes.Node, path: str) -> None:
        if isinstance(node, yaml.nodes.MappingNode):
            seen: dict[str, int] = {}
            for key_node, value_node in node.value:
                key = str(key_node.value)
                line = key_node.start_mark.line + 1
                if key in seen:
                    duplicates.append((f"{path}.{key}", seen[key], line))
                seen[key] = line
                walk(value_node, f"{path}.{key}")
        elif isinstance(node, yaml.nodes.SequenceNode):
            for index, value_node in enumerate(node.value):
                walk(value_node, f"{path}[{index}]")

    walk(yaml.compose(text), "")
    return duplicates


def test_sync_config() -> None:
    text = read(SYNC)
    duplicates = duplicate_mapping_keys(text)
    check(not duplicates, f"sync config has duplicate keys: {duplicates}")
    config = yaml.safe_load(text)
    check(config["config"]["edition"] == 3, "sync config must use edition 3")
    ctes = config["with"]
    queries = stream_queries(config)

    check(len(queries) == 50, f"expected 50 streams, found {len(queries)}")
    for name, stream in config["streams"].items():
        check(stream.get("auto_subscribe") is True, f"{name}: auto_subscribe must be true")

    referenced: set[str] = set()
    for name, statements in queries.items():
        for sql in statements:
            refs = table_refs(sql)
            unknown = refs - ALL_TABLES - set(ctes)
            check(not unknown, f"{name}: unknown table reference(s) {sorted(unknown)}")
            referenced |= refs & ALL_TABLES
            for banned in UNSUPPORTED_SQL:
                check(banned.lower() not in sql.lower(), f"{name}: unsupported SQL {banned!r}")
            source = re.search(
                r"select\s+([a-z_][a-z0-9_]*)\.\*\s+from\s+([a-z_][a-z0-9_]*)"
                r"(?:\s+(?:as\s+)?([a-z_][a-z0-9_]*))?",
                sql,
                re.I,
            )
            alias = source.group(3) if source else None
            if alias and alias.lower() not in {
                "where", "join", "on", "and", "or", "order", "group", "limit",
            }:
                check(
                    alias.lower() == source.group(2).lower(),
                    f"{name}: source alias {alias!r} renames the synced table",
                )
            check(
                "@>" not in sql and "jsonb_build_array" not in sql.lower(),
                f"{name}: jsonb containment is not supported by Sync Streams",
            )
            if re.search(r"\bJOIN\b", sql, re.I):
                check(
                    not re.search(r"SELECT\s+\*\s+FROM", sql, re.I),
                    f"{name}: SELECT * with JOIN selects columns from more than one table",
                )
                for on_clause in re.findall(r"\bON\b(.*?)(?=\bJOIN\b|\bWHERE\b|$)", sql, re.I | re.S):
                    check(
                        not re.search(r"[<>!]=?|\bOR\b", on_clause, re.I),
                        f"{name}: join condition must be equality only",
                    )

    for name, sql in ctes.items():
        refs = table_refs(sql)
        check(
            not (refs & set(ctes)),
            f"CTE {name}: a global CTE cannot reference another CTE",
        )
        check(
            not any(banned.lower() in sql.lower() for banned in UNSUPPORTED_SQL),
            f"CTE {name}: unsupported SQL",
        )

    all_used = referenced | {ref for sql in ctes.values() for ref in table_refs(sql)}
    missing = ALL_TABLES - all_used
    check(not missing, f"sync config does not reference: {sorted(missing)}")
    check(not (all_used - ALL_TABLES), f"sync config references unknown tables: {sorted(all_used - ALL_TABLES)}")
    ok(f"sync config: {len(queries)} streams, edition 3, {len(ALL_TABLES)} tables, supported SQL only")


def test_source_db_setup() -> None:
    sql = read(SOURCE)

    grant_block = re.search(r"grant\s+select\s+on\s+table(.*?)to\s+powersync_role;", sql, re.I | re.S)
    check(grant_block is not None, "SOURCE_DB_SETUP.sql has no grant select block")
    granted = set(re.findall(r"public\.([a-z_0-9]+)", grant_block.group(1), re.I))

    publication_block = re.search(
        r"create\s+publication\s+powersync\s+for\s+table(.*?);", sql, re.I | re.S
    )
    check(publication_block is not None, "SOURCE_DB_SETUP.sql has no publication block")
    published = set(re.findall(r"public\.([a-z_0-9]+)", publication_block.group(1), re.I))

    replica = {
        match.group(1).lower()
        for match in re.finditer(
            r"alter\s+table\s+public\.([a-z_0-9]+)\s+replica\s+identity\s+default;", sql, re.I
        )
    }

    check(granted == INITIAL_ALL_TABLES, f"grant set differs: {sorted(INITIAL_ALL_TABLES ^ granted)}")
    check(published == INITIAL_ALL_TABLES, f"publication set differs: {sorted(INITIAL_ALL_TABLES ^ published)}")
    check(replica == INITIAL_ALL_TABLES, f"replica identity set differs: {sorted(INITIAL_ALL_TABLES ^ replica)}")
    check("replica identity full" not in sql.lower(), "REPLICA IDENTITY FULL must not be used")

    check(
        re.search(r"create\s+role\s+powersync_role\s+with\s+replication\s+bypassrls\s+login", sql, re.I)
        is not None,
        "powersync_role must be a non-superuser replication role with bypassrls",
    )
    check("<GENERATED_PASSWORD>" in sql, "the password placeholder is missing")
    check(
        re.search(r"create\s+role[^;]*\bsuperuser\b", sql, re.I) is None
        and re.search(r"alter\s+role[^;]*\bsuperuser\b", sql, re.I) is None,
        "SOURCE_DB_SETUP.sql must not create a superuser",
    )
    check("grant all" not in sql.lower(), "SOURCE_DB_SETUP.sql must not use GRANT ALL")

    verification = re.search(r"c\.relname\s+in\s*\((.*?)\)", sql, re.I | re.S)
    check(verification is not None, "SOURCE_DB_SETUP.sql has no replica identity verification query")
    verified = {value.lower() for value in re.findall(r"'([a-z_0-9]+)'", verification.group(1), re.I)}
    check(verified == INITIAL_ALL_TABLES, f"verification set differs: {sorted(INITIAL_ALL_TABLES ^ verified)}")
    ok("source setup: 18 initial grants, 18 published tables, DEFAULT replica identity")


def test_full_coverage_migration() -> None:
    sql = read(COVERAGE_MIGRATION)
    block = re.search(
        r"synced_tables\s+text\[\]\s*:=\s*array\[(.*?)\];",
        sql,
        re.I | re.S,
    )
    check(block is not None, "coverage migration has no synced_tables array")
    migrated = set(re.findall(r"'([a-z_0-9]+)'", block.group(1)))
    check(migrated == ALL_TABLES, f"coverage migration set differs: {sorted(ALL_TABLES ^ migrated)}")
    check(len(migrated) == 146, f"expected 146 migrated tables, found {len(migrated)}")

    check(
        "grant select on table public.%I to powersync_role" in sql,
        "coverage migration must grant SELECT to powersync_role",
    )
    check(
        "alter table public.%I replica identity default" in sql,
        "coverage migration must enforce REPLICA IDENTITY DEFAULT",
    )
    check(
        "alter publication powersync add table public.%I" in sql,
        "coverage migration must add each table to the publication",
    )
    check(
        "create publication powersync" in sql,
        "coverage migration must create the publication when it is absent",
    )
    check(
        "replica identity full" not in sql.lower(),
        "coverage migration must not use REPLICA IDENTITY FULL",
    )
    check(
        "has_table_privilege('powersync_role', c.oid, 'SELECT')" in sql,
        "coverage migration verification must check the SELECT grant",
    )
    ok(f"coverage migration: {len(migrated)} grants, published tables, DEFAULT replica identity")


def test_service_config() -> None:
    text = read(SERVICE)
    check(re.search(r"^region:\s*jp\s*$", text, re.M) is not None, "service region must be jp")
    check(re.search(r"^\s*sslmode:\s*verify-full\s*$", text, re.M) is not None,
          "replication sslmode must be verify-full")
    check(re.search(r"^\s*_type:\s*cloud\s*$", text, re.M) is not None, "service must be cloud")

    uri_lines = [line.strip() for line in text.splitlines() if line.strip().startswith("uri:")]
    check(len(uri_lines) == 1, "expected exactly one replication uri")
    check("PS_DATABASE_URI" in uri_lines[0], "the URI must come from PS_DATABASE_URI")
    check("pooler.supabase.com" not in uri_lines[0].lower(), "do not use the Supavisor pooler host")
    check(
        re.search(r"db\.[a-z0-9]+\.supabase\.co:5432", text, re.I) is not None,
        "service config must document the direct Supabase host and port 5432",
    )

    check(re.search(r"^\s*supabase:\s*true\s*$", text, re.M) is not None,
          "client_auth.supabase must be true")
    ok("service config: jp, direct host, verify-full, Supabase auth")


def migration_a_text() -> str:
    return read(MIGRATION_A)


def rule_tables(sql: str) -> list[str]:
    block = re.search(
        r"insert\s+into\s+nodex\.mutation_scope_rules(.*?)on\s+conflict", sql, re.I | re.S
    )
    check(block is not None, "migration A has no mutation_scope_rules insert")
    return re.findall(r"^\s*\('([a-z_0-9]+)',\s*array\[", block.group(1), re.M)


def attach_tables(sql: str) -> list[str]:
    block = re.search(r"foreach\s+t\s+in\s+array\s+array\[(.*?)\]\s+loop", sql, re.I | re.S)
    check(block is not None, "migration A has no trigger attachment loop")
    return re.findall(r"'([a-z_0-9]+)'", block.group(1))


def created_tables() -> set[str]:
    created: set[str] = set()
    for path in MIGRATIONS.glob("*.sql"):
        for match in re.finditer(
            r"create\s+table\s+(?:if\s+not\s+exists\s+)?public\.([a-z_0-9]+)",
            read(path),
            re.I,
        ):
            created.add(match.group(1).lower())
    return created


def test_authorization_migration() -> None:
    sql = migration_a_text()
    rules = rule_tables(sql)
    attached = attach_tables(sql)

    check(len(rules) == 83, f"expected 83 scope rules, found {len(rules)}")
    check(len(set(rules)) == 83, "scope rules contain duplicates")
    check(len(attached) == 83, f"expected 83 trigger attachments, found {len(attached)}")
    check(len(set(attached)) == 83, "trigger attachments contain duplicates")
    check(set(rules) == set(attached), f"rule/trigger mismatch: {sorted(set(rules) ^ set(attached))}")

    missing = set(rules) - created_tables()
    check(not missing, f"scope rules name tables no migration creates: {sorted(missing)}")

    for function in (
        "nodex.resolve_mutation_patient",
        "nodex.assert_patient_chain_consistency",
        "nodex.assert_fk_tenant",
        "nodex.assert_patient_mutation_scope",
        "nodex.tg_patient_mutation_guard",
    ):
        check(function in sql, f"migration A is missing {function}")

    check(sql.lower().count("for share") >= 6, "migration A must lock membership/role/device/patient rows")
    check("clock_timestamp()" in sql, "migration A must use clock_timestamp for exact-instant expiry")
    for helper in (
        "nodex.has_permission(",
        "nodex.has_role(",
        "nodex.has_facility_access(",
        "nodex.has_ward_access(",
    ):
        check(helper not in sql, f"migration A must not call the STABLE helper {helper} in the write guard")
    check("patient_merge_history" in sql, "migration A must authorize both merge patients")
    check("tg_table_name = 'patients'" in sql, "migration A must treat a patient row as its own patient")
    check("current_patient_id" in sql, "migration A must resolve an ICU bed's current patient")
    check("mother_patient_id" in sql, "migration A must resolve a birth record's mother")
    check("'statutory_birth_records'" in sql, "migration A must guard the birth registry")
    check("p_table in ('bed_assignments', 'icu_beds')" in sql,
          "migration A must apply ward scope to ICU beds")
    check("if v_rule.triage_table then" in sql,
          "migration A must allow triage updates before an assignment exists")
    check("'assessed_by'" in sql,
          "migration A must keep the triage assessor immutable")
    check("before insert or update" in sql.lower(), "migration A must guard insert and update")
    check("errcode = '42501'" in sql, "migration A must raise 42501 for authorization failures")
    check("revoke all on function" in sql, "migration A must revoke helper execution")
    ok("authorization migration: 83/83 rule-trigger parity, helpers and locks present")


def test_expiry_migration() -> None:
    sql = read(MIGRATION_B)
    check("'expired'" in sql, "membership status vocabulary must include expired")
    check("create or replace function nodex.expire_memberships" in sql, "expiry sweep function missing")
    check(
        re.search(r"set\s+status\s*=\s*'expired'\s*,\s*updated_at\s*=\s*now\(\)", sql, re.I) is not None,
        "expiry sweep must set status and updated_at",
    )
    check(
        re.search(r"valid_until\s*<=\s*now\(\)", sql, re.I) is not None,
        "expiry sweep must compare valid_until to now()",
    )
    check("'* * * * *'" in sql, "expiry sweep must run every minute")
    check("cron.schedule" in sql, "expiry sweep must be scheduled")
    check("nodex.membership_is_current" in sql, "exact-instant membership helper missing")
    check("clock_timestamp()" in sql, "exact-instant membership helper must use clock_timestamp")
    check("tg_membership_self_guard" in sql, "membership self-escalation guard missing")
    check(
        re.search(r"new\.user_id\s+is\s+distinct\s+from\s+old\.user_id", sql, re.I) is not None,
        "membership subject must be immutable",
    )
    check("a membership cannot be self-granted" in sql, "self-grant refusal missing")
    check("cannot change its own role, scope, status or validity" in sql, "self-extension refusal missing")
    check("revoke all on function" in sql, "expiry helper execution must be revoked")
    ok("expiry migration: WAL sweep, cron, exact-instant guard, self-escalation guard")


def test_handler() -> None:
    text = read(HANDLER)
    check("export function resolveDeviceId" in text, "handler must resolve a device id")
    check("export function classifyApplyError" in text, "handler must classify apply errors")
    check("error.code === '42501'" in text, "handler must map 42501 to forbidden")
    check("error.code === '23P01'" in text, "handler must map 23P01 to conflict")
    check("error.message.includes('NODEX:')" in text, "handler must map NODEX errors to forbidden")
    check("return 'forbidden'" in text and "return 'conflict'" in text, "handler rejection vocabulary missing")
    check("profile.status !== 'active'" in text, "handler must reject an inactive account")
    check(".from('memberships')" in text, "handler must resolve membership")
    check("hasCurrentMembership" in text, "handler must check membership validity")
    check(".from('devices')" in text, "handler must resolve the device")
    check("device.revoked_at !== null" in text, "handler must reject a revoked device")
    check("the device header does not match the mutation body" in text,
          "handler must reject a device header/body mismatch")
    check("ctx.supabase.rest.headers.set('x-device-id', deviceId)" in text,
          "handler must forward the device id to PostgREST")
    check("ctx.supabase.rest.headers.delete('x-device-id')" in text,
          "handler must clear a stale device header")
    check("const table = ctx.supabase.from(m.table)" in text, "handler must apply writes with the user client")
    set_at = text.find("ctx.supabase.rest.headers.set")
    apply_at = text.find("const table = ctx.supabase.from(m.table)")
    check(0 <= set_at < apply_at, "device header must be set before the write")
    ok("handler: tenant, membership, device, error classification and header forwarding wired")


def test_seed() -> None:
    sql = read(SEED)
    check("nodex.dev_seed" in sql, "seed must require the dev_seed opt-in")
    check("raise exception" in sql, "seed must refuse without the opt-in")
    check(re.search(r"^begin;", sql, re.M | re.I) is not None, "seed must open a transaction")
    check(re.search(r"^commit;", sql, re.M | re.I) is not None, "seed must commit its transaction")
    check("truncate" not in sql.lower(), "seed must not truncate tables")
    check("drop " not in sql.lower(), "seed must not drop objects")
    check("d0000000-0000-4000-8000-000000000001" in sql, "seed must use deterministic tenant ids")
    check("request.jwt.claim.role" in sql and "service_role" in sql,
          "seed must use a transaction-local service_role claim")
    check("triage_assessments" in sql, "seed must include a pre-assignment triage fixture")
    ok("seed: opt-in guard, one transaction, deterministic ids, no destructive SQL")


def test_authorization_tests() -> None:
    sql = read(AUTHZ)
    check(re.search(r"^begin;", sql, re.M | re.I) is not None, "authorization test must open a transaction")
    check(re.search(r"^rollback;", sql, re.M | re.I) is not None, "authorization test must roll back")
    check(re.search(r"^commit;", sql, re.M | re.I) is None, "authorization test must not commit")
    check("expect_forbidden" in sql and "expect_ok" in sql and "expect_state" in sql,
          "authorization test helpers missing")
    lower = sql.lower()
    for label in (
        "assigned doctor",
        "unassigned doctor",
        "triage nurse",
        "revoked device",
        "suspended membership",
        "cross-tenant",
        "self-granted",
        "expiry sweep",
        "conflict",
        "merge",
    ):
        check(label in lower, f"authorization test is missing the {label!r} case")
    check("postgres" in sql and "bypasses row-level security" in sql,
          "authorization test must document the postgres/RLS limitation")
    ok("authorization tests: transaction-wrapped, rollback, required cases present")


def main() -> None:
    test_sync_config()
    test_source_db_setup()
    test_full_coverage_migration()
    test_service_config()
    test_authorization_migration()
    test_expiry_migration()
    test_handler()
    test_seed()
    test_authorization_tests()
    print("\nall static assertions passed")


if __name__ == "__main__":
    main()
