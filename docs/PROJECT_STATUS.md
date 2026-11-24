# Project status

Updated: 25 November 2026 (IST)

## Milestone M1: bilingual branded Android preview

| Item | State |
|---|---|
| Android project (Kotlin 2.1.0, Compose BOM 2024.12.01, AGP 8.7.3, Gradle 8.11.1 wrapper, compile/target SDK 35, min SDK 26) | Implemented |
| Gujarati/English switch, persisted via AppCompat per-app locales (system setting on Android 13+) | Implemented, **not yet run on a device** |
| Welcome, Home, My Family, Chapters, Events, Survey, Profile previews | Implemented |
| Preview labelling on every screen; no counts, no login, survey button disabled | Implemented |
| Loading / empty / error states (Chapters, Events) | Implemented |
| No INTERNET permission, backups disabled | Implemented |
| Unit tests: language mapping, string parity, placeholders, Gujarati coverage, no-network guard, no invented records | Written, **not yet executed** |
| GitHub Actions: wrapper validation, tests, lint, debug APK artifact (14-day retention), manual trigger | Written, **not yet run** |
| Supplied emblem | **Blocked**: logo file not provided in this session; placeholder shown |
| Push to GitHub | **Blocked**: write access to the repository not granted to this session |

### Not verified
The workspace had no Android SDK and no access to Google/Maven repositories, so the project
was not compiled locally. The first CI run is the first real compile. Fix any failure there
before calling M1 complete.

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
Owner grants repository write access and attaches the emblem → push `feature/m1-preview`,
run CI, install the APK on a device, then open M2 (backend comparison + identity slice).
