# Backend: database layer (M2)

Plain PostgreSQL 16, written to work with either backend option in
`docs/BACKEND_OPTIONS.md` (Supabase or our own server). The backend vendor is **not yet chosen**;
nothing here is deployed and no real data exists.

## Security model

- The API connects as role `bbg_api`, which can only **execute functions in schema `api`**.
  It cannot read or write any table directly.
- Each `api` function checks who is calling (`app.current_account_id()`, set per request by
  the API after it verifies the sign-in token) and whether that person is allowed.
- Email is contact data, not identity. Accounts are keyed by the sign-in provider's user id;
  each person gets an immutable member code (`BBG-0001001`, ...).
- Secretary authority is limited to the **exact chapter** an application was sent to.
  Parent-chapter roles do not inherit authority (brief: needs an explicit policy first).
- Only a global administrator appoints or revokes roles, never for themselves.
- The first global administrator is created once, by the database operator, with
  `select app.bootstrap_global_admin('<designated email>');` and only after that person has
  signed up and verified their email. The app can never call this.
- `audit_events` is append-only and stores ids and action names, never names or emails.
- The directory lists only approved, living members who have opted in, returns no contact
  fields, needs 2+ characters, escapes wildcards and caps results at 50.

## Layout

```text
db/migrations/   numbered SQL migrations, applied in order
db/tests/        security tests (synthetic data only)
db/run_tests.sh  creates a throwaway database, applies migrations, runs tests, drops it
```

## Running the tests

```bash
# Any PostgreSQL 16 you can throw away (Docker example):
docker run --rm -d -p 5432:5432 -e POSTGRES_PASSWORD=dev --name bbg-pg postgres:16
PGHOST=localhost PGPORT=5432 PGUSER=postgres PGPASSWORD=dev backend/db/run_tests.sh
```

Never point `run_tests.sh` at staging or production. CI runs it on every change under `backend/`.

## Not done yet
API server and sign-in integration (depends on the backend choice), the admin web portal,
correction resubmission and appeals flow, duplicate-account review, country/state admin
scopes, household/relationship tables (M3), survey (M4).
