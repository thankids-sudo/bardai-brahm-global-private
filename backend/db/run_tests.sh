#!/usr/bin/env bash
# For each test file: create a fresh throwaway database, apply all migrations, run the test,
# drop the database. Files starting with "_" are shared includes, not tests.
# Usage: PGHOST=localhost PGPORT=5432 PGUSER=postgres PGPASSWORD=... backend/db/run_tests.sh
# Standard libpq variables; the user must be allowed to create and drop databases.
# Never point this at a real (staging/production) server.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
: "${PGHOST:?set PGHOST (and PGPORT/PGUSER/PGPASSWORD) for a throwaway server}"

current=""
cleanup() { [ -n "$current" ] && psql -d postgres -q -c "drop database if exists $current" >/dev/null 2>&1 || true; }
trap cleanup EXIT

for t in "$here"/tests/[!_]*.sql; do
    current="bbg_test_$$_$(basename "$t" .sql | tr -c 'a-z0-9_\n' '_')"
    psql -d postgres -v ON_ERROR_STOP=1 -q -c "create database $current"
    for m in "$here"/migrations/*.sql; do
        psql -d "$current" -v ON_ERROR_STOP=1 -q -f "$m"
    done
    echo "== $(basename "$t")"
    psql -d "$current" -v ON_ERROR_STOP=1 -q -f "$t"
    psql -d postgres -q -c "drop database $current"
    current=""
done
echo "all database tests passed"
