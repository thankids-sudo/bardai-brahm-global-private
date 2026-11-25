# બરડાઈ બ્રહ્મ ગ્લોબલ ફાઉન્ડેશન — Bardai Brahm Global Foundation

Native Android app (Gujarati/English) for a worldwide Bardai Brahm community platform:
membership, family links, chapters, events and community surveys.

The Foundation is being established; legal registration is not yet complete.

## Current status: M1 preview (no live features)

- Bilingual Gujarati/English preview with persistent language choice.
- Preview screens: Welcome, Home, My Family, Chapters, Events, Survey, Profile.
- **No sign-in, no backend, no network permission, no data collection.**
- The supplied Foundation emblem is **not yet installed**; a labelled placeholder is shown.
  See `branding/README.md`.

Details: `docs/PROJECT_STATUS.md`. Full requirements: `docs/IMPLEMENTATION_BRIEF.md`.

## Getting the test APK

1. Open the repository's **Actions** tab → **Android debug build** → latest green run.
2. Download the `bardai-brahm-global-debug-N` artifact (zip) and extract the `.apk`.
3. On the phone, allow "Install unknown apps" for your file manager/browser, then open the APK.

Debug builds are signed with the CI runner's temporary debug key, which can differ
between runs. If an update refuses to install, uninstall the previous debug build first.
Debug APKs are for testing only, not for distribution.

## Building locally

Requirements: JDK 17 and the Android SDK (API 35).

```bash
cd android
./gradlew testDebugUnitTest lintDebug assembleDebug
# APK: android/app/build/outputs/apk/debug/app-debug.apk
```

## Repository layout

```text
android/            Native app (Kotlin, Jetpack Compose, Gradle wrapper)
branding/           Master logo (pending) and resource generation script
docs/               Brief, status
.github/workflows/  CI: tests, lint, debug APK artifact
```

`supabase/` holds the database migrations and local Supabase config; `backend/` holds the
database tests. `admin-web/` comes later. Backend setup: `docs/SUPABASE_SETUP.md`.

## Security rules

Never commit real member data, database dumps, signing keys, keystores or backend
service keys. See `.gitignore`.
