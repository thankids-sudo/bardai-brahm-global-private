# Working instructions

Authoritative requirements: `docs/IMPLEMENTATION_BRIEF.md`. Status: `docs/PROJECT_STATUS.md`.
Keep the status file updated after every change.

- Owner: Dhaval Thanki (`thankids-sudo`). Address as Dhavalbhai.
- Every user-facing string goes in both `values/strings.xml` and `values-gu/strings.xml`;
  `ResourceAndPrivacyGuardTest` enforces parity.
- Never show invented membership counts, live data, or working login/chat/video placeholders.
- Internet is the only permission. Network calls go only to the configured Supabase backend;
  without `SUPABASE_URL`/`SUPABASE_PUBLISHABLE_KEY` at build time the app stays offline (preview).
- Never log tokens, passwords or personal data. The refresh token is stored only encrypted (Android Keystore).
- Authorisation is enforced server-side; never grant roles in client code
  (including for the designated global admin email).
- No secrets, keystores, member data or production dumps in git.
- Preview fixtures live in `preview/`, separate from `data/` contracts.
- Never claim a build, push or deployment happened without a run URL / commit SHA.
- Don't invent dependency versions; check official docs when upgrading.
- Work on feature branches with reviewable commits.
