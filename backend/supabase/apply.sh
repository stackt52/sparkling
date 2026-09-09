#!/usr/bin/env bash
# Applies backend/supabase/migrations/*.sql in order, then seed.sql (ENG-006).
#
# Usage:
#   SUPABASE_DB_URL='postgresql://postgres.<ref>:<password>@aws-0-<region>.pooler.supabase.com:5432/postgres' \
#     backend/supabase/apply.sh [--no-seed] [--dry-run]
#
# Requires psql (https://www.postgresql.org/download/). Migration 0001 drops and
# recreates the public schema — only run against a project you intend to reset.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIGRATIONS_DIR="$HERE/migrations"
SEED_FILE="$HERE/seed.sql"
NO_SEED=0
DRY_RUN=0

for arg in "$@"; do
  case "$arg" in
    --no-seed) NO_SEED=1 ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help)
      sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

if [[ -z "${SUPABASE_DB_URL:-}" ]]; then
  cat >&2 <<'MSG'
error: SUPABASE_DB_URL is not set.

  Find it in the Supabase dashboard → Project Settings → Database → Connection string
  (use the "Session" pooler or direct connection; URI form), e.g.

    export SUPABASE_DB_URL='postgresql://postgres.uicqczgpiqkczwyssdft:<password>@aws-0-eu-central-1.pooler.supabase.com:5432/postgres'

MSG
  exit 1
fi

if ! command -v psql >/dev/null 2>&1; then
  echo "error: psql not found on PATH (install PostgreSQL client tools)." >&2
  exit 1
fi

shopt -s nullglob
MIGRATIONS=("$MIGRATIONS_DIR"/*.sql)
if [[ ${#MIGRATIONS[@]} -eq 0 ]]; then
  echo "error: no migrations found in $MIGRATIONS_DIR" >&2
  exit 1
fi
IFS=$'\n' MIGRATIONS=($(printf '%s\n' "${MIGRATIONS[@]}" | sort)); unset IFS

run_sql() {
  local file="$1"
  echo "==> applying $(basename "$file")"
  if [[ $DRY_RUN -eq 1 ]]; then return 0; fi
  psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -X -q -f "$file"
}

for f in "${MIGRATIONS[@]}"; do
  run_sql "$f"
done

if [[ $NO_SEED -eq 1 ]]; then
  echo "==> skipping seed (--no-seed)"
elif [[ -f "$SEED_FILE" ]]; then
  run_sql "$SEED_FILE"
else
  echo "warn: $SEED_FILE not found; skipping seed" >&2
fi

echo "done."
