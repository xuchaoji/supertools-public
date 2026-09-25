"""Regenerate the AppScope layered icon at 1024x1024 to pass AppGallery review.

AppGallery flagged the layered icon ("layered_icon" -> background + foreground):

    1. foreground is 216x216            -> must be 1024x1024
    2. background is 216x216            -> must be 1024x1024
    3. background has rounded corners   -> must be square (方角)
    4. background has transparent pixels -> must be fully opaque

Design reconstruction (keeps the icon visually identical):

  * background.png    1024x1024, fully opaque, square corners.
      The production tile is a rounded square made of a dark-blue interior
      with a light rim (42,42,74). We upscale the 216px tile (background.png)
      to 1024 and fill its rounded transparent corners with the rim colour so
      the whole canvas becomes opaque. The launcher re-applies the corner mask
      at render time, so the final look is unchanged.

  * foreground.png    1024x1024, transparent canvas + the logo mark only.
      icon.png is the same design already rasterised at 1024 (it equals the
      upscaled tile + the logo). The logo is recovered as the pixels where
      icon.png differs from the upscaled tile; everything else stays
      transparent.

  * foreground_dev.png 1024x1024 = foreground.png + a small yellow "DEV" badge
      (the 216px badge layout from the old gen_dev_icon.py, scaled x4.74).

Inputs  (AppScope/resources/base/media/):
    background.png   216x216 tile WITHOUT logo   (original asset)
    foreground.png   216x216 tile + logo          (cross-check only)
    icon.png         1024x1024 tile + logo        (high-res logo source)

Outputs (overwritten in AppScope/resources/base/media/):
    background.png   1024x1024 opaque square tile
    foreground.png   1024x1024 transparent + logo
    foreground_dev.png 1024x1024 transparent + logo + DEV badge

NOTE: this is a one-time migration from the old 216px assets. If you ever need
to run it again, restore the original 216px assets first, e.g.:

    git checkout -- AppScope/resources/base/media/background.png \
                    AppScope/resources/base/media/foreground.png \
                    AppScope/resources/base/media/foreground_dev.png

Usage:
    python tools/gen_icon_1024.py
"""

from __future__ import annotations

import json
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MEDIA = os.path.join(ROOT, "AppScope", "resources", "base", "media")

SRC_BACKGROUND = os.path.join(MEDIA, "background.png")     # 216 tile, no logo
SRC_FOREGROUND = os.path.join(MEDIA, "foreground.png")     # 216 tile + logo
SRC_ICON = os.path.join(MEDIA, "icon.png")                 # 1024 tile + logo

DST_BACKGROUND = os.path.join(MEDIA, "background.png")
DST_FOREGROUND = os.path.join(MEDIA, "foreground.png")
DST_FOREGROUND_DEV = os.path.join(MEDIA, "foreground_dev.png")

CANVAS = 1024
RIM_COLOR = (42, 42, 74)  # light rim around the tile, used to fill the corners

# logo extraction: a pixel belongs to the logo when its RGB differs from the
# upscaled tile by more than LOGO_DIFF_THRESHOLD (sum of abs channel diffs).
# The tile's own rim/interior never differs by more than ~30, and the logo's
# softest edge pixels start around ~40.
LOGO_DIFF_THRESHOLD = 35

# --- DEV badge (scaled from the old 216px layout) ---------------------------
# old: W=72 H=26 CX=108 CY=177  ->  * CANVAS/216
SCALE = CANVAS / 216.0
BADGE_W = 72 * SCALE
BADGE_H = 26 * SCALE
BADGE_CX = 108 * SCALE
BADGE_CY = 177 * SCALE
BADGE_RADIUS = BADGE_H / 2
BADGE_FILL = (255, 210, 0, 255)  # yellow
BADGE_TEXT = "DEV"
BADGE_TEXT_COLOR = (32, 28, 10, 255)
BADGE_TEXT_MAX_W = 50 * SCALE
BADGE_TEXT_HEIGHT_RATIO = 0.74
SS = 4  # supersampling for clean badge edges

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


def load_rgba(path: str) -> np.ndarray:
    return np.asarray(Image.open(path).convert("RGBA")).astype(np.int16)


def build_background(tile_216: np.ndarray) -> Image.Image:
    """1024x1024 opaque square tile."""
    img = Image.fromarray(tile_216.astype(np.uint8), "RGBA").resize(
        (CANVAS, CANVAS), Image.LANCZOS
    )
    arr = np.asarray(img).astype(np.int16)
    # fill the rounded transparent corners with the rim colour
    opaque = arr[..., 3] >= 128
    arr[..., 3] = 255                                  # everything opaque
    arr[..., :3] = np.where(opaque[..., None], arr[..., :3], RIM_COLOR)
    # save as RGB (no alpha channel) so the background is unambiguously opaque
    return Image.fromarray(arr[..., :3].astype(np.uint8), "RGB")


def build_foreground(icon: np.ndarray, tile_216: np.ndarray) -> Image.Image:
    """1024x1024 transparent canvas + the logo mark."""
    bg = np.asarray(
        Image.fromarray(tile_216.astype(np.uint8), "RGBA").resize(
            (CANVAS, CANVAS), Image.LANCZOS
        )
    ).astype(np.int16)

    icon_opaque = icon[..., 3] >= 128
    diff = np.abs(icon[..., :3] - bg[..., :3]).sum(axis=2)
    logo = icon_opaque & (diff >= LOGO_DIFF_THRESHOLD)

    out = np.zeros((CANVAS, CANVAS, 4), dtype=np.uint8)
    out[logo] = icon[logo].astype(np.uint8)
    out[..., 3] = np.where(logo, 255, 0)
    return Image.fromarray(out, "RGBA")


def draw_badge(base: Image.Image) -> Image.Image:
    """Stamp the DEV badge onto a copy of `base` (1024 coordinates)."""
    overlay = Image.new("RGBA", (CANVAS * SS, CANVAS * SS), (0, 0, 0, 0))
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
    return Image.alpha_composite(base, overlay.resize((CANVAS, CANVAS), Image.LANCZOS))


def main() -> None:
    tile_216 = load_rgba(SRC_BACKGROUND)
    icon = load_rgba(SRC_ICON)
    if tile_216.shape[:2] != (216, 216):
        raise SystemExit("background.png must be the original 216x216 tile (restore from git)")
    if icon.shape[:2] != (CANVAS, CANVAS):
        raise SystemExit(f"icon.png must be {CANVAS}x{CANVAS}")

    background = build_background(tile_216)
    foreground = build_foreground(icon, tile_216)
    foreground_dev = draw_badge(foreground)

    background.save(DST_BACKGROUND)
    foreground.save(DST_FOREGROUND)
    foreground_dev.save(DST_FOREGROUND_DEV)

    # --- verification -----------------------------------------------------
    bg = np.asarray(background.convert("RGBA")).astype(int)
    fg = np.asarray(foreground).astype(int)
    fgd = np.asarray(foreground_dev).astype(int)

    def bbox(mask: np.ndarray):
        ys, xs = np.where(mask)
        return (int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max()))

    logo_mask = fg[..., 3] > 0
    logo_bbox = bbox(logo_mask)

    # composite = background + foreground  ->  should equal icon.png (corners aside)
    comp = bg.copy()
    comp[fg[..., 3] > 0] = fg[fg[..., 3] > 0]
    comp_np = comp.astype(int)
    icon_np = icon.astype(int)
    both_opaque = (comp_np[..., 3] > 200) & (icon_np[..., 3] > 200)
    maxdiff = int(np.abs(comp_np[..., :3] - icon_np[..., :3]).sum(axis=2)[both_opaque].max())

    print(f"background  : {background.size}  alpha extrema={bg[...,3].min()},{bg[...,3].max()}  "
          f"cornerTL alpha={bg[0,0,3]} cornerBR alpha={bg[-1,-1,3]}")
    print(f"foreground  : {foreground.size}  logo px={int(logo_mask.sum())}  "
          f"logo bbox={logo_bbox}")
    print(f"  safe zone check (content within 170..854): "
          f"{'OK' if logo_bbox[0] >= 170 and logo_bbox[1] >= 170 and logo_bbox[2] <= 854 and logo_bbox[3] <= 854 else 'OUT'}")
    print(f"foreground_dev: {foreground_dev.size}  changed px vs foreground={int((fgd[...,:3] != fg[...,:3]).any(axis=2).sum())}")
    print(f"composite vs icon.png max RGB diff (opaque area) = {maxdiff}  (0 = pixel-identical)")
    print()
    print("wrote", os.path.relpath(DST_BACKGROUND, ROOT))
    print("wrote", os.path.relpath(DST_FOREGROUND, ROOT))
    print("wrote", os.path.relpath(DST_FOREGROUND_DEV, ROOT))


if __name__ == "__main__":
    main()
