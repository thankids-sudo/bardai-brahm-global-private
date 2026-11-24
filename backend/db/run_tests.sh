#!/usr/bin/env bash
# Applies all migrations to a fresh, throwaway database and runs every test file.
# Usage: PGHOST=localhost PGPORT=5432 PGUSER=postgres PGPASSWORD=... backend/db/run_tests.sh
# Standard libpq variables; the user must be allowed to create and drop databases.
# Never point this at a real (staging/production) server.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
: "${PGHOST:?set PGHOST (and PGPORT/PGUSER/PGPASSWORD) for a throwaway server}"
db="bbg_test_$$"

psql -d postgres -v ON_ERROR_STOP=1 -q -c "create database $db"
trap 'psql -d postgres -q -c "drop database if exists $db" >/dev/null 2>&1 || true' EXIT

for f in "$here"/migrations/*.sql; do
    echo "apply $(basename "$f")"
    psql -d "$db" -v ON_ERROR_STOP=1 -q -f "$f"
done
for f in "$here"/tests/*.sql; do
    echo "test  $(basename "$f")"
    psql -d "$db" -v ON_ERROR_STOP=1 -q -f "$f"
done
echo "all database tests passed"
