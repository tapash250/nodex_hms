-- Close the anon execute grant on the snapshot issuance RPC.
--
-- Supabase's default privileges grant EXECUTE on new public-schema functions to
-- anon and authenticated. Snapshot issuance requires an authenticated principal,
-- so the anon grant is removed. The function's own auth.uid() guard already
-- rejects anonymous calls; this removes the reachable surface entirely.

revoke execute on function
  public.issue_authorization_snapshot(uuid, text, text, text, text)
from anon;

-- rls_auto_enable is a project-level event trigger function. Event trigger
-- functions cannot be invoked as RPCs, but the blanket PUBLIC/anon grant is
-- unnecessary API surface.
revoke execute on function public.rls_auto_enable() from anon, authenticated, public;
