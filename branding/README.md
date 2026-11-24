# Branding

**Status: supplied emblem installed** (25 Nov 2026).

- Master: `branding/logo-master.jpg`, the owner's file exactly as received (sent as
  `1001606313.jpg`, 2048 x 2048 JPEG). The brief mentioned `1001606100.png`; this is the
  emblem the owner supplied in its place. Do not edit the master.
- Generated: `android/app/src/main/res/drawable-nodpi/emblem.webp` (Welcome/Profile, max 1024 px)
  and `ic_launcher_foreground.png` (launcher icon, emblem inside the 66/108 mask-safe zone on a
  warm-white background).
- The JPEG has square white corners. The script makes only the pixels outside the inscribed
  circle transparent; nothing inside the emblem is altered.

To regenerate after the owner supplies a new master:

```bash
pip install pillow
python3 branding/generate_android_assets.py branding/logo-master.jpg
```

## Open item for owner review
At launcher size (about 48 dp) the lettering is too small to read. The full emblem is kept
as supplied. A compact alternate icon (for example, the banyan tree or seated figure alone)
can be proposed for owner approval; nothing has been redesigned.

Emblem elements to preserve: navy/gold circular border, green banyan tree, seated
white-clad figure, Foundation name, and the wording `SANT TRIKAMACHARY MAHARAJ`.
UI palette: navy `#1B2A4A`, gold `#C9A227`, banyan green `#2E6B34`, warm white `#FFF8EC`.
