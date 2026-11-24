# M2 step 1: backend options

Prepared 25 November 2026 (IST) for the owner's decision. Nothing has been purchased.
Prices are from vendors' official pages (or reputable trackers citing them) in Oct–Nov 2026;
recheck on the day of purchase.

## Basis of the cost figures

- Budget: ₹20,000/year for hosting and online services (brief).
- Exchange rate assumed: **₹95 per US$** (mid-market rates seen Oct–Nov 2026 were ₹94–95).
- **18% GST** added to foreign cloud services billed to an Indian customer without GSTIN
  (DigitalOcean states this explicitly; assume the same for others until an invoice shows otherwise).
- Card foreign-exchange markup is **not** included; cover it from contingency.
- Effective rate used below: US$1 ≈ ₹112.

## What the backend must do (from the brief)

Relational data (persons, relationships, households, chapters, scoped roles, consents,
survey versions, audit log); email verification; server-side authorisation; photo storage
with restricted URLs; backups; separate development/staging/production; India-friendly
hosting region; low ongoing maintenance for volunteers.

## Options

| | A. Supabase Pro | B. Supabase Free | C. Neon + Firebase Auth + serverless API + R2 | D. Own VPS (DigitalOcean Bangalore) + Firebase Auth + R2 | E. Firebase SQL Connect (Cloud SQL) |
|---|---|---|---|---|---|
| Database | Managed Postgres | Managed Postgres, 500 MB | Serverless Postgres (scales to zero) | Postgres we run | Cloud SQL Postgres |
| Email verification | Built in | Built in | Firebase Auth (free ≤ 50k MAU) | Firebase Auth (free ≤ 50k MAU) | Firebase Auth |
| Authorisation | Postgres Row-Level Security | Same | Our API code | Our API code | SQL Connect rules + our code |
| Photos | Supabase Storage | 1 GB | Cloudflare R2 (10 GB free, no egress fee) | Cloudflare R2 | Cloud Storage |
| Backups | Daily, 7-day retention | **None** | Neon restore window (check plan) | DigitalOcean daily backups (+30% of server price) | Cloud SQL backups (extra) |
| Downtime risk | Not paused | **Paused after 1 week of low activity** | Cold start after idle | Single server | Managed |
| Ops burden | Lowest | Low | Medium (4 vendors) | **Highest**: OS/DB patching, monitoring | Medium |
| Est. cost/year incl. GST | **≈ ₹33,600** | ₹0 | ≈ ₹6,700–13,500 (usage-dependent) | **≈ ₹10,500** (1 vCPU/1 GB + daily backups) | ≈ ₹12,600+ after 3-month trial, before backups |
| Fits ₹20,000? | **No** (+₹13,600 alone) | Yes | Yes | Yes, ~₹6,500 headroom after domain/email | Yes, tight |

Workings (US$/year → ₹ at ₹112):
A = $25 × 12 = $300 (Micro compute covered by the plan's $10 credit).
C = Neon Launch has no monthly minimum: $0.106 per compute-unit-hour + $0.35/GB-month;
a small 0.25 CU database active ~6 h/day ≈ $5/month, doubling if busier.
D = $6 droplet + 30% for daily backups = $7.80/month.
E = Cloud SQL from $9.37/month after the trial.

### Notes on each

**A. Supabase Pro.** Best fit for the brief's security requirements with the least custom
code: Postgres, Row-Level Security policies that are testable in SQL, email verification,
storage policies, daily backups, and the app talks to it directly. The free tier can host
development/staging. Problem: costs ~1.7× the annual budget on its own.

**B. Supabase Free.** Fine for development and staging. **Not acceptable for production
member data**: no automatic backups, and projects pause after a week of low activity.

**C. Neon + Firebase Auth + serverless API + R2.** Cheapest at pilot scale and nothing to
patch, but four vendors to wire together and maintain, and cold starts after idle.

**D. Own VPS in Bangalore.** Predictable fixed cost, data held in India, full control.
We would write the API (Kotlin/Ktor, same language as the app) with authorisation enforced
there and tested. Someone must apply security updates and watch the server; on 1 GB RAM there is
no room to grow inside the budget (the 2 GB size plus backups is ≈ ₹21,000/year).

**E. Firebase SQL Connect.** Relational, but young, and the free trial ends after 3 months.
Plain Firestore is not relational and fits genealogy poorly, so it is not offered.

## Recommendation

1. **If the budget can rise to about ₹37,000/year** (Supabase Pro + domain/email):
   choose **A**. It is the safest and most maintainable path for volunteers, with
   development on a free Supabase project. Data region: Mumbai (confirm when creating the project).
2. **If ₹20,000 is firm:** choose **D**, with the API and authorisation tests in this
   repository, Firebase Auth for email verification, R2 for photos, and DigitalOcean
   daily backups plus a weekly off-server database dump. Development uses a local
   Postgres in Docker; production starts only after M2's negative security tests pass.

Either way, the M2 code keeps authorisation server-side and covered by the brief's negative
tests: unverified/pending/suspended users cannot query the directory; a secretary cannot
approve another chapter's members; nobody can self-promote; approvals are audited.

## Decision needed from the owner
- Budget: raise to ~₹37,000 for option A, or keep ₹20,000 and use option D?
- Who will own the hosting account and payment card (Foundation or an individual)?
- Domain name for email and the admin web portal (not yet chosen).

## Sources
- Supabase pricing and free-plan pausing: https://supabase.com/pricing, https://supabase.com/docs/guides/platform/project-pausing
- Neon plans: https://neon.com/docs/introduction/plans
- Firebase pricing (Authentication 50k MAU, SQL Connect): https://firebase.google.com/pricing, https://firebase.google.com/docs/sql-connect/pricing
- DigitalOcean Droplets and backups: https://www.digitalocean.com/pricing/droplets, https://www.digitalocean.com/pricing
- DigitalOcean India GST (18%): https://docs.digitalocean.com/platform/billing/taxes/ind/
- Cloudflare R2: https://developers.cloudflare.com/r2/pricing/
