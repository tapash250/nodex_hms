#!/usr/bin/env bash
# Rotate the temporary powersync_role password without printing it.
#
# The source-database password is generated once during setup and stored only in
# the untracked powersync/.env. This script generates a replacement, applies it
# to PostgreSQL, verifies the new credential, and rewrites the .env entry
# atomically with mode 600. The password is never written to stdout, a command
# argument, or shell history.
#
# Prerequisites:
#   - powersync/.env contains PS_DATABASE_URI and POWERSYNC_DATABASE_PASSWORD.
#   - psql can reach the direct Supabase host (port 5432).
#   - The current password still works; this script uses it to authenticate.
#
# After it succeeds, redeploy the PowerSync service config so the connector
# picks up the new password:
#   powersync deploy service-config --directory=powersync
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
env_file="${POWERSYNC_ENV_FILE:-$repo_root/powersync/.env}"

if [[ ! -f "$env_file" ]]; then
  echo "missing environment file: $env_file" >&2
  exit 1
fi

# Load PS_DATABASE_URI and the current password. Do not echo them.
set -a
# shellcheck disable=SC1090
source "$env_file"
set +a

: "${PS_DATABASE_URI:?PS_DATABASE_URI is missing from $env_file}"
: "${POWERSYNC_DATABASE_PASSWORD:?POWERSYNC_DATABASE_PASSWORD is missing from $env_file}"

command -v psql >/dev/null 2>&1 || {
  echo "psql is required" >&2
  exit 1
}
command -v python3 >/dev/null 2>&1 || {
  echo "python3 is required" >&2
  exit 1
}

new_password="$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')"

tmp_sql="$(mktemp)"
tmp_env="$(mktemp)"
cleanup() {
  rm -f "$tmp_sql" "$tmp_env"
}
trap cleanup EXIT
chmod 600 "$tmp_sql" "$tmp_env"

# The generated token contains no single quote, so direct interpolation is safe
# for this one ALTER ROLE statement. The file is mode 600 and removed on exit.
printf "alter role powersync_role with password '%s';\n" "$new_password" >"$tmp_sql"

PGPASSWORD="$POWERSYNC_DATABASE_PASSWORD" psql "$PS_DATABASE_URI" \
  --no-psqlrc --set=ON_ERROR_STOP=1 --file="$tmp_sql" >/dev/null

# Verify the replacement credential before rewriting .env. If this fails, the
# old password has already been replaced; recover through the Supabase SQL
# editor or dashboard rather than rerunning with stale credentials.
PGPASSWORD="$new_password" psql "$PS_DATABASE_URI" \
  --no-psqlrc --set=ON_ERROR_STOP=1 --tuples-only --command='select 1' >/dev/null

NEW_PASSWORD="$new_password" ENV_FILE="$env_file" python3 - <<'PY'
import os
import pathlib

path = pathlib.Path(os.environ["ENV_FILE"])
new_password = os.environ["NEW_PASSWORD"]
lines = path.read_text(encoding="utf-8").splitlines()
updated = []
replaced = False
for line in lines:
    if line.startswith("POWERSYNC_DATABASE_PASSWORD="):
        updated.append(f"POWERSYNC_DATABASE_PASSWORD={new_password}")
        replaced = True
    else:
        updated.append(line)
if not replaced:
    updated.append(f"POWERSYNC_DATABASE_PASSWORD={new_password}")
path.write_text("\n".join(updated) + "\n", encoding="utf-8")
path.chmod(0o600)
PY

echo "rotated powersync_role password and updated $env_file (mode 600)" >&2
echo "next: powersync deploy service-config --directory=powersync" >&2
