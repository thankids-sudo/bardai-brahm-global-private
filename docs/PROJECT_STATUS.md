# Project status

Updated: 25 November 2026 (IST)

## Milestone M1: bilingual branded Android preview

| Item | State |
|---|---|
| Android project (Kotlin 2.1.0, Compose BOM 2024.12.01, AGP 8.7.3, Gradle 8.11.1 wrapper, compile/target SDK 35, min SDK 26) | Implemented |
| Gujarati/English switch, persisted via AppCompat per-app locales (system setting on Android 13+) | Implemented; builds. **Not yet run on a device** |
| Welcome, Home, My Family, Chapters, Events, Survey, Profile previews | Implemented |
| Preview labelling on every screen; no counts, no login, survey button disabled | Implemented |
| Loading / empty / error states (Chapters, Events) | Implemented |
| No INTERNET permission, backups disabled | Implemented |
| Unit tests: language mapping, string parity, placeholders, Gujarati coverage, no-network guard, no invented records | Passed in CI run 45469303135 |
| GitHub Actions: wrapper validation, tests, lint, debug APK artifact (14-day retention), manual trigger | Passed: run 45469303135 (commit 5787f61), APK artifact `bardai-brahm-global-debug-1`, ~10 MB |
| Supplied emblem | Installed from owner's `1001606313.jpg` (master `branding/logo-master.jpg`); full emblem on Welcome/Profile, launcher icon uncropped. Lettering illegible at icon size: compact icon pending owner review |
| Push to GitHub | Done: branch `feature/m1-preview` (no PR yet: `main` is empty) |

### Verified
Clean GitHub runner, 25 Nov 2026: `testDebugUnitTest`, `lintDebug` (abortOnError) and
`assembleDebug` all BUILD SUCCESSFUL.
https://github.com/thankids-sudo/bardai-brahm-global-private/actions/runs/45469303135

### Not verified
Install/launch on a device or emulator, the language switch persisting after restart, and
how the emblem looks on a real screen. These are M1 acceptance checks for the owner's phone.

### Proposed (not owner decisions)
- Application ID `org.bardaibrahmglobal.app` (becomes permanent on Play; confirm before release).
- Min SDK 26 (Android 8.0) to use adaptive icons without legacy bitmaps.
- Neutral greeting "Namaste / નમસ્તે" on Home; owner may prefer a community greeting.
- Six bottom-navigation tabs; can drop Survey to Home-only if labels feel crowded.

### Deferred
Release signing workflow (only after signing is configured), backend, admin web, real data.

### Repository notes
Repository visibility was **public** on 25 Nov 2026 despite its name. Owner to decide.

## Next concrete step
Owner installs the APK and confirms launch, language persistence and emblem display. Then M2: backend comparison and the identity slice.

## Milestone M2: identity and membership (started 25 Nov 2026)

| Item | State |
|---|---|
| `main` fast-forwarded to M1 (`aef4625`) | Done |
| Backend comparison (`docs/BACKEND_OPTIONS.md`) | Written; **awaiting owner decision** on budget/option |
| Email verification, applications, chapter routing, admin bootstrap, secretary approval | Not started (blocked on backend choice) |

Next concrete step: owner chooses option A (Supabase Pro, ~₹37k/yr) or D (own VPS, within ₹20k).
