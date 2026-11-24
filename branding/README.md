# Branding

**Status: supplied emblem not yet in the repository.** The app currently shows a plain
navy/gold placeholder frame captioned "Official emblem will appear here". This is not a
substitute logo.

To install the supplied emblem (`1001606100.png` from the owner):

1. Save it unchanged as `branding/logo-master.png` (keep this master under version control).
2. Run `python3 branding/generate_android_assets.py branding/logo-master.png`.
3. Commit the generated files in `android/app/src/main/res/`.

Emblem elements to preserve: navy/gold circular border, green banyan tree, seated
white-clad figure, Foundation name, and the wording `SANT TRIKAMACHARY MAHARAJ`.
UI palette: navy `#1B2A4A`, gold `#C9A227`, banyan green `#2E6B34`, warm white `#FFF8EC`.
