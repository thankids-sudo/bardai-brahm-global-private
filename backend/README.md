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

## Membership workflow (migrations 0001–0002)

```text
apply ──► pending ──► approved ──► (suspended ⇄ approved)
             │  ▲
             │  └── resubmit ◄── correction_requested
             ├──► rejected ──► appeal ──► upheld: back to pending, original reviewer barred
             │                        └─► dismissed: stays rejected
             └──► withdrawn (applicant may apply again)
```

- Secretaries see a review queue for their own chapters only, with a count of possible
  duplicate records (same name, birth year ±1). These are suggestions for human review;
  records are never merged automatically.
- Applicants with no local chapter choose the **global intake** chapter. No intake secretary
  has been appointed; such applications wait until the owner appoints one.
- Appeals are decided by a global administrator who is neither the appellant nor the reviewer.
- A global administrator can disable an account (with a reason), which blocks every action at once.

## Family records (migration 0003, M3)

- **Ownership:** every person record has one owner: the account that claimed it, or else the
  account that entered it. Only the owner edits it. Entering a relative records who entered it
  and the consent basis (`assisted_with_consent` for living adults, `guardian` for minors,
  `deceased_record` for the deceased).
- **Links:** parent→child (biological, adoptive, step, guardian, foster, unknown; label father/
  mother/parent) and spouse (with start/end years, so remarriage works). Siblings, half-siblings,
  grandparents and in-laws are derived from these.
- **Confirmation:** a link touching someone else's record is `pending` until that owner accepts
  or disputes it. When a person claims their record, links others recorded about them return to
  `pending` for their own acceptance.
- **Blocked:** self-links, cycles (anyone becoming their own ancestor), parent born after child,
  more than two biological parents, duplicate links.
- **Family view:** start only from your own record or one you manage, up to 4 steps, both
  parental branches. Living relatives are shown as "private" (no name, code or year) unless you
  own the record, or they have their own account, allow relatives to see them, and every link on
  the way is accepted. Living minors are private except to their owner. Pending links are visible
  only to the two parties. The directory never exposes relationships.
- **Claiming:** the owner of a living adult's record can issue a one-time invitation (valid 14
  days, only its hash stored). Accounts that already have a record cannot claim another, and a
  record that already belongs to an account cannot be taken over (two independent checks).
- **Households:** time-bounded membership; a person is in at most one current household.
  **Residences:** full history with exactly one current residence.
- **Merges:** never automatic. Requested by the owner of one record; reviewed by a global admin or
  the requester's chapter secretary who owns neither record; differing fields must be explicitly
  acknowledged; records belonging to accounts cannot be merged away; merges that would create a
  cycle or a third biological parent are refused.

## Layout

```text
db/migrations/   numbered SQL migrations, applied in order
db/tests/        security tests (synthetic data only); _harness.sql/_report.sql are shared
db/run_tests.sh  per test file: fresh throwaway database, apply migrations, run, drop
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
country/state admin scopes, account holders joining a household from their own account,
relationship finder and PDF export, survey (M4).
