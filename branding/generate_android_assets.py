#!/usr/bin/env python3
"""Generate Android resources from the supplied Foundation emblem.

Usage (from repository root):
    pip install pillow
    python3 branding/generate_android_assets.py branding/logo-master.jpg

What it does, without altering the artwork:
  * drawable-nodpi/emblem.webp       full emblem for Welcome/Profile (max 1024 px)
  * drawable-nodpi/ic_launcher_foreground.png
        emblem scaled into the adaptive-icon 66/108 safe zone on a transparent canvas
  * removes the placeholder vector drawables and sets emblem_is_placeholder=false

If small-size lettering is illegible on the launcher icon, propose a compact
alternate icon for owner review; keep the full emblem untouched here.
"""
import pathlib
import re
import sys

from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parent.parent
RES = ROOT / "android/app/src/main/res"


def main(src: str) -> None:
    logo = Image.open(src).convert("RGBA")
    if Image.open(src).mode != "RGBA":
        # Round emblem supplied on a square white canvas (e.g. JPEG): make only the corners
        # outside the inscribed circle transparent. Pixels inside the circle are untouched.
        mask = Image.new("L", logo.size, 0)
        ImageDraw.Draw(mask).ellipse((0, 0, logo.width - 1, logo.height - 1), fill=255)
        logo.putalpha(mask)
    nodpi = RES / "drawable-nodpi"
    nodpi.mkdir(exist_ok=True)

    full = logo.copy()
    full.thumbnail((1024, 1024), Image.LANCZOS)
    (nodpi / "emblem.png").unlink(missing_ok=True)
    full.save(nodpi / "emblem.webp", quality=92, method=6)  # WebP with alpha: API 18+

    canvas_px = 432  # 108 dp at xxxhdpi
    safe_px = int(canvas_px * 66 / 108)  # keep entire emblem inside the mask-safe circle
    icon = logo.copy()
    icon.thumbnail((safe_px, safe_px), Image.LANCZOS)
    canvas = Image.new("RGBA", (canvas_px, canvas_px), (0, 0, 0, 0))
    canvas.paste(icon, ((canvas_px - icon.width) // 2, (canvas_px - icon.height) // 2), icon)
    canvas.save(nodpi / "ic_launcher_foreground.png", optimize=True)

    for name in ("emblem.xml", "ic_launcher_foreground.xml"):
        (RES / "drawable" / name).unlink(missing_ok=True)

    # Full-colour emblem is unsuitable as a themed monochrome icon; drop that layer.
    launcher = RES / "mipmap-anydpi/ic_launcher.xml"
    launcher.write_text(re.sub(r"\s*<monochrome[^>]*/>", "", launcher.read_text()))

    branding = RES / "values/branding.xml"
    branding.write_text(branding.read_text().replace(">true<", ">false<"))
    print("Installed emblem and launcher icon from", src)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
