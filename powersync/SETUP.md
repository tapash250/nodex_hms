# PowerSync instance setup checklist

Complete in order. Steps 1–2 happen in the PowerSync dashboard; steps 3–5 are
SQL against the linked Supabase project; step 6 is CI configuration.

## 1. Create the instance

PowerSync dashboard → create instance → **Supabase** integration → select this
project. Note the instance URL; it becomes `NODEX_POWERSYNC_URL`.

## 2. Deploy the sync rules

Paste `sync-rules.yaml` into the instance's sync rules editor and deploy.
Do not connect a client yet: the reader role (next step) cannot yet read the
tables, and a first sync against unreadable tables fails with empty buckets.

## 3. Reader role grants

PowerSync connects to PostgreSQL with a dedicated login role (commonly
`supabase_powersync`) created during the integration. The sync rules queries run
as that role. It needs:

```sql
-- The reader must see rows the sync rules themselves select. RLS policies in
-- this database are written TO authenticated; a reader without BYPASSRLS gets
-- zero rows from every FORCE'd table, which would silently produce empty
-- buckets. The rules do the scoping — this grant lets them run at all.
alter role supabase_powersync bypassrls;

grant usage on schema public to supabase_powersync;
grant select on all tables in schema public to supabase_powersync;
alter default privileges in schema public
  grant select on tables to supabase_powersync;
```

### Why BYPASSRLS is the correct call here

- Ten tables carry `force row level security`, so even the table owner sees
  only policy rows — and no policy in this database targets the reader role.
  Without BYPASSRLS every bucket returns empty and the failure is silent.
- The sync rules derive all scope from the JWT via `request.user_id()` and the
  membership graph, the same way `nodex.has_tenant_access` does. They are the
  Tier 2 boundary, reviewed like code.
- The reader role is not a login a human or client can assume; it exists for the
  PowerSync service connection, authenticated with the instance's own secret.

### What BYPASSRLS does NOT permit

It bypasses RLS for the reader only, on SELECT, only through the PowerSync
service. It grants nothing to `anon`, `authenticated`, or any client build, and
the service-role key remains absent from all client binaries.

## 4. Publication and logical replication

The Supabase integration enables `wal_level = logical` and creates its
publication. After the first rules deploy, verify the tables the rules
reference are in the publication:

```sql
select schemaname, tablename from pg_publication_tables
where pubname = 'supabase_realtime';  -- or the publication the integration created
```

If any referenced table is missing, add it:

```sql
alter publication <pubname> add table public.memberships;
```

## 5. Smoke-test the bucket queries

Before shipping a client build, run each rule's parameter query and one data
query as `supabase_powersync` with a real user id substituted. Expect: master
data for that user's tenants only; zero rows from any other tenant.

## 6. CI configuration

Add the instance URL as a repository secret `NODEX_POWERSYNC_URL`. Debug builds
without it intentionally run local-only — that behaviour is asserted in
`nodex_environment_test.dart`.

## Adding a clinical module

A module's stream is approved only alongside its RLS policies in the same
change, and acceptance inspects the device database, not the interface:

1. Write the bucket query so it reproduces exactly the scope its RLS helper
   enforces (`nodex.has_ward_access` and friends).
2. Add the table to the publication.
3. Grant the reader `select` on the table (default privileges cover new tables).
4. Test with a ward-scoped user: rows for that ward only, verified by querying
   the local SQLite database directly.
5. Verify a different tenant's user receives zero rows from the bucket.
