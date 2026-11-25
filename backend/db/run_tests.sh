#!/usr/bin/env bash
# Runs the database security tests against the migrations in supabase/migrations.
#
# Plain PostgreSQL mode (default): for each test file, create a fresh throwaway database,
# apply every migration (each in one transaction), run the test, drop the database.
#   PGHOST=localhost PGPORT=5432 PGUSER=postgres PGPASSWORD=... backend/db/run_tests.sh
#
# Supabase local mode (SUPABASE_LOCAL=1): migrations were already applied by `supabase start`;
# each test runs inside a transaction that is rolled back, so tests never leave data behind.
#   SUPABASE_LOCAL=1 PGHOST=127.0.0.1 PGPORT=54322 PGUSER=postgres PGPASSWORD=postgres backend/db/run_tests.sh
#
# Files starting with "_" are shared includes. Never point this at staging or production.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
migrations="$here/../../supabase/migrations"
: "${PGHOST:?set PGHOST (and PGPORT/PGUSER/PGPASSWORD) for a throwaway server}"

if [ "${SUPABASE_LOCAL:-0}" = "1" ]; then
    for t in "$here"/tests/[!_]*.sql; do
        echo "== $(basename "$t") (rolled back)"
        psql -d postgres -v ON_ERROR_STOP=1 -q -c "begin" -f "$t" -c "rollback"
    done
    echo "all database tests passed"
    exit 0
fi

current=""
cleanup() { [ -n "$current" ] && psql -d postgres -q -c "drop database if exists $current" >/dev/null 2>&1 || true; }
trap cleanup EXIT

for t in "$here"/tests/[!_]*.sql; do
    current="bbg_test_$$_$(basename "$t" .sql | tr -c 'a-z0-9_\n' '_')"
    psql -d postgres -v ON_ERROR_STOP=1 -q -c "create database $current"
    for m in "$migrations"/*.sql; do
        psql -d "$current" -v ON_ERROR_STOP=1 -q --single-transaction -f "$m"
    done
    echo "== $(basename "$t")"
    psql -d "$current" -v ON_ERROR_STOP=1 -q -f "$t"
    psql -d postgres -q -c "drop database $current"
    current=""
done
echo "all database tests passed"
