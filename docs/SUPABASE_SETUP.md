# Supabase setup: owner checklist

Decision (25 Nov 2026): backend option **A, Supabase Pro**, about ₹37,000/year including domain
and email (see `docs/BACKEND_OPTIONS.md`). Nothing has been purchased by the developer. Every step
below that creates an account, spends money or handles a password is for the owner.

**Never paste passwords, access tokens or database passwords into chat, email or git.**
Put them only in a password manager and in GitHub environment secrets.

## 1. Account and project (owner)

1. Create a Supabase account and an organisation named *Bardai Brahm Global Foundation*.
   Upgrade the organisation to **Pro** (US$25/month).
2. Create a project:
   - Name: `bardai-brahm-global`
   - Region: **South Asia (Mumbai)**
   - Database password: generate a long random one; save it in a password manager.
3. Note the **project reference** (Project Settings → General). It is not secret, but keep it with the others.

## 2. Project settings (owner, in the dashboard)

| Where | Setting |
|---|---|
| Project Settings → API (Data API) → Exposed schemas | **only `api`**. Remove `public` and `graphql_public`. |
| Authentication → Sign In / Providers → Email | Confirm email **on**. Minimum password length **10**. Leaked password protection **on** (Pro). |
| Authentication → URL Configuration | Site URL and redirect URL: `org.bardaibrahmglobal.app://auth-callback` |
| Authentication → Emails → SMTP | **Custom SMTP is required before real members sign up.** Supabase's built-in sender is for testing only, reaches only project team members and is limited to a few emails per hour. Needs a domain and an email provider: **not yet chosen**. |
| Storage | Nothing to do: the migration creates the private `event-photos` bucket and its policies. |

## 3. GitHub (owner)

1. Repository → Settings → Environments → **New environment** `production`.
   Add yourself as **Required reviewer**. Allow deployments from `main` only.
2. In that environment add three secrets:
   - `SUPABASE_ACCESS_TOKEN`: Supabase → Account → Access Tokens → generate (name it "GitHub deploy").
   - `SUPABASE_DB_PASSWORD`: the database password from step 1.
   - `SUPABASE_PROJECT_ID`: the project reference.
3. For the Android build later, add repository secrets `SUPABASE_URL` (`https://<ref>.supabase.co`)
   and `SUPABASE_PUBLISHABLE_KEY` (Project Settings → API Keys). The publishable key is designed to be
   public inside apps; security comes from the database rules, not from hiding it.

## 4. First deployment

1. Merge the Supabase pull request into `main` after its checks pass.
2. Actions → **Deploy database to Supabase (production)** → Run workflow → type `DEPLOY` → approve.
3. The log shows each migration applied. Re-running is safe: applied migrations are skipped.

## 5. Create the Global Administrator (owner, once)

1. Sign up as `Thankids@gmail.com` (in the app once the sign-in screen ships, or Authentication →
   Users → Add user → "Auto confirm" if you do it before then) and confirm the email.
2. In the dashboard SQL Editor run, once:
   ```sql
   select app.bootstrap_global_admin('Thankids@gmail.com');
   ```
   It refuses if the email is unverified, unknown, or if a global administrator already exists.
   The app itself can never call this.

## 6. Create the first chapters (owner or developer, SQL Editor)

There is no chapter admin screen yet. Example (edit names; Gujarati names are required):

```sql
insert into app.chapters (level, parent_id, name_en, name_gu, accepts_applications)
values ('global', null, 'Global', 'વૈશ્વિક', false)
returning id;   -- use this id as parent below

insert into app.chapters (level, parent_id, name_en, name_gu, accepts_applications, is_global_intake)
values ('country', '<global id>', 'Global intake (no local chapter)', 'વૈશ્વિક પ્રવેશ (સ્થાનિક શાખા નથી)', true, true);
```

Then appoint secretaries with `api.grant_role` from the admin account (admin portal comes later).

## What is verified, and how

On every change, GitHub Actions starts a throwaway local Supabase (same Auth, Storage and API
gateway), applies all migrations, runs every database security test (333) and an HTTP end-to-end
check (sign-up, confirmation gate, sign-in, API calls and refusals). None of this touches the
production project.
