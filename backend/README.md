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

## Survey and statistics (migration 0004, M4)

- **Questionnaires:** separate individual and household surveys, versioned, every prompt and
  option in Gujarati and English. Version 1 is seeded. A new version starts new responses;
  statistics never mix versions.
- **Answers:** optional unless marked required (only household size is). "Prefer not to
  disclose" is stored as *declined*; an unanswered question has no row. Neither becomes zero.
  No Aadhaar, bank, exact-income or DNA questions.
- **Income:** a band within a currency and reporting year. Only INR 2026 bands exist, marked
  **PROPOSED, pending owner approval**. Other currencies cannot record income until a method is
  agreed. Currencies are never pooled.
- **Households:** one response per household per version, so income is counted once.
- **Consent:** approved members only, after giving survey consent. Withdrawing consent removes
  their responses from every statistic; members can delete their own responses.
- **Statistics:** counts only, no row-level data.
  - Members: member country, age group, education, work status, household size.
  - Planning users (planning analyst on the global chapter, or a global admin) also see income,
    housing and support needs.
  - Counts from 1 to 4 are hidden (setting `min_cell_size`, default 5). If only one cell is
    hidden, the next smallest is hidden too, so it cannot be worked out by subtraction.
  - A country filter is refused when the country, or the rest of the world, is below 5.
  - Each breakdown reports *declined* and *not answered* separately, and a denominator.
  - The overview keeps accounts, approved members, person records, households, surveyed
    individuals, surveyed households and pending duplicate reviews as separate measures.

## Directory, events and photos (migration 0005, M5)

- **Contact details:** released one member at a time, only to approved members, only the fields
  that member consented to (email and phone are separate choices, effective immediately). Each
  release is logged (which fields, never the values) and limited per day (`contact_reveals_per_day`,
  default 20). Searches are limited per hour (`directory_searches_per_hour`, default 60).
- **Events:** created and managed by an admin or secretary of exactly that chapter. Times are
  entered in the organiser's local time and IANA zone; listings return event-local and
  viewer-local times using PostgreSQL's time zone rules (daylight-saving aware). Local times
  that are skipped by a clock change are refused. Online links must be https.
- **RSVP:** approved members worldwide; capacity counts guests; over capacity is waitlisted and
  promoted in order when places free up. Participant names and attendance are visible only to
  the organising chapter.
- **Announcements:** bilingual, chapter-scoped, removable by that chapter or a global admin.
- **Photos:** only an admin of the event's chapter registers photos, already compressed
  (JPEG/WebP, ≤ 2 MB, ≤ 2560 px). Storage keys are checked against path traversal; the API
  layer issues short-lived signed URLs. Members can report a photo; the chapter admin or a
  global admin removes it with a reason, which resolves the reports.

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
relationship finder and PDF export, survey entry on behalf of others by survey volunteers,
publishing new questionnaire versions from the admin portal, event reminders (notification
service), moderated chat and built-in video (after pilot, per brief).
