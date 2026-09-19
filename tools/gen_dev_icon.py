"""Generate the `dev` target's launcher icon from the production icon.

Only ONE thing differs from the production icon: a small yellow "DEV" badge
stamped into the empty area below the logo mark. The artwork and the tile
colour are left completely untouched, so the dev build still reads as the
same app at launcher size.

Input  (production, AppScope/resources/base/media/):
    foreground.png  -> the rounded-square tile with the logo mark on top

Output (AppScope/resources/base/media/):
    foreground_dev.png     -> production foreground + "DEV" badge
    layered_icon_dev.json  -> layered-image descriptor; reuses the production
                              $media:background and points at foreground_dev

Usage:
    python tools/gen_dev_icon.py
"""

from __future__ import annotations

import json
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MEDIA = os.path.join(ROOT, "AppScope", "resources", "base", "media")

SRC_BACKGROUND = os.path.join(MEDIA, "background.png")
SRC_FOREGROUND = os.path.join(MEDIA, "foreground.png")

DST_FOREGROUND = os.path.join(MEDIA, "foreground_dev.png")
DST_LAYERED = os.path.join(MEDIA, "layered_icon_dev.json")

# --- badge config ----------------------------------------------------------
# The logo mark occupies y 47..154, so the strip below it is empty. Keep the
# badge small: it only needs to be recognisable, not loud.
BADGE_W = 72
BADGE_H = 26
BADGE_CX = 108
BADGE_CY = 177
BADGE_RADIUS = BADGE_H / 2  # fully rounded ends
BADGE_FILL = (255, 210, 0, 255)  # yellow
BADGE_TEXT = "DEV"
BADGE_TEXT_COLOR = (32, 28, 10, 255)
BADGE_TEXT_MAX_W = 50
BADGE_TEXT_HEIGHT_RATIO = 0.74
# --------------------------------------------------------------------------

SS = 4  # supersampling factor, keeps the badge edges clean

FONT_CANDIDATES = [
    r"C:\Windows\Fonts\segoeuib.ttf",
    r"C:\Windows\Fonts\arialbd.ttf",
    r"C:\Windows\Fonts\verdanab.ttf",
]


def load_bold_font(size: int) -> ImageFont.FreeTypeFont:
    for path in FONT_CANDIDATES:
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    raise SystemExit("no bold font found; add one to FONT_CANDIDATES")


def draw_badge(base: Image.Image) -> Image.Image:
    """Stamp the DEV badge onto a copy of `base`."""
    w, h = base.size
    overlay = Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)

    draw.rounded_rectangle(
        [
            (BADGE_CX - BADGE_W / 2) * SS,
            (BADGE_CY - BADGE_H / 2) * SS,
            (BADGE_CX + BADGE_W / 2) * SS,
            (BADGE_CY + BADGE_H / 2) * SS,
        ],
        radius=BADGE_RADIUS * SS,
        fill=BADGE_FILL,
    )

    size = int(BADGE_H * BADGE_TEXT_HEIGHT_RATIO)
    while size > 6:
        font = load_bold_font(size * SS)
        left, top, right, bottom = draw.textbbox((0, 0), BADGE_TEXT, font=font)
        if (right - left) <= BADGE_TEXT_MAX_W * SS:
            break
        size -= 1

    draw.text(
        (BADGE_CX * SS - (left + right) / 2, BADGE_CY * SS - (top + bottom) / 2),
        BADGE_TEXT,
        font=font,
        fill=BADGE_TEXT_COLOR,
    )

    return Image.alpha_composite(base, overlay.resize((w, h), Image.LANCZOS))


def mark_mask() -> np.ndarray:
    """Pixels where the production foreground differs from the bare tile."""
    bg = np.asarray(Image.open(SRC_BACKGROUND).convert("RGBA")).astype(float)
    fg = np.asarray(Image.open(SRC_FOREGROUND).convert("RGBA")).astype(float)
    return np.abs(bg[..., :3] - fg[..., :3]).sum(axis=2) > 120


def main() -> None:
    src_fg = Image.open(SRC_FOREGROUND).convert("RGBA")
    src_bg = Image.open(SRC_BACKGROUND).convert("RGBA")
    if src_fg.size != src_bg.size:
        raise SystemExit("background/foreground size mismatch")

    fg_dev = draw_badge(src_fg)
    fg_dev.save(DST_FOREGROUND)

    with open(DST_LAYERED, "w", encoding="utf-8", newline="\n") as fp:
        json.dump(
            {
                "layered-image": {
                    "background": "$media:background",
                    "foreground": "$media:foreground_dev",
                }
            },
            fp,
            indent=2,
            ensure_ascii=False,
        )
        fp.write("\n")

    # --- sanity checks -----------------------------------------------------
    mask = mark_mask()
    badge_pad = 3  # supersampled edges bleed ~1-2px past the layout box

    out = np.asarray(fg_dev)
    src = np.asarray(src_fg)
    changed = np.abs(out[..., :3].astype(int) - src[..., :3].astype(int)).sum(axis=2) > 0

    ys, xs = np.where(changed)
    cbox = (int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max()))
    bbox = (
        int(BADGE_CX - BADGE_W / 2) - badge_pad,
        int(BADGE_CY - BADGE_H / 2) - badge_pad,
        int(BADGE_CX + BADGE_W / 2) + badge_pad,
        int(BADGE_CY + BADGE_H / 2) + badge_pad,
    )
    covered = (
        cbox[0] >= bbox[0] and cbox[1] >= bbox[1]
        and cbox[2] <= bbox[2] and cbox[3] <= bbox[3]
    )

    badge_zone = np.zeros(mask.shape, dtype=bool)
    badge_zone[bbox[1]: bbox[3] + 1, bbox[0]: bbox[2] + 1] = True

    print(f"canvas                 : {src_fg.size[0]}x{src_fg.size[1]}")
    print(f"badge                  : {BADGE_W}x{BADGE_H} @ ({BADGE_CX}, {BADGE_CY})  text={BADGE_TEXT!r}")
    print(f"changed pixel bbox     : {cbox}  (must sit inside {bbox})")
    print(f"badge zone over artwork: {int((badge_zone & mask).sum())} px (must be 0)")
    print(f"changes only in badge  : {covered}")
    print(f"alpha unchanged        : {bool((out[..., 3] == src[..., 3]).all())}")
    print("wrote", os.path.relpath(DST_FOREGROUND, ROOT))
    print("wrote", os.path.relpath(DST_LAYERED, ROOT))


if __name__ == "__main__":
    main()
