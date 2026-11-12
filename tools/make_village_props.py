"""Draws SmallWorld's village props: assets/village/props.png (160 x 48, 16 px tiles).

Run from the project folder:  python tools/make_village_props.py
(needs Pillow:  pip install pillow)

Layout (column, row):
  (0-1, 0-2)  round leafy tree (the pack's spr_deco_tree_01, first frame)
  (2-3, 0-2)  the same tree mirrored, so a grove doesn't look stamped
  (4-5, 0-1)  the town bulletin board: two posts, a cork board with notes
  (6, 0-1)    shop sign on a post: sprout (seed shop)
  (7, 0-1)    basket (general store)
  (8, 0-1)    milk bottle (ranch)
  (9, 0-1)    hammer (smithy)
  (4-5, 2)    hay bale
  (6, 2)      grain sack

Signs use the pack's own item icons and its wood colours, so they sit in with the tileset.
"""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent / "assets"
PACK = ROOT / "Sunnyside_World_Assets"
OUT = ROOT / "village"


def hexc(h, a=255):
    return (int(h[1:3], 16), int(h[3:5], 16), int(h[5:7], 16), a)


LINE = hexc("#9a5a43")
WOOD = hexc("#c7714b")
WOOD_MID = hexc("#d08250")
WOOD_LIGHT = hexc("#de9f6e")
BOARD = hexc("#e2b78a")
SHADOW = hexc("#181425", 70)
PAPER = hexc("#f6ead0")
PAPER_LINE = hexc("#b89a78")
HAY = hexc("#f2cf6a")
HAY_DARK = hexc("#d9a441")
HAY_LIGHT = hexc("#fbe59a")
SACK = hexc("#e2c9a0")
SACK_DARK = hexc("#c2a078")

sheet = Image.new("RGBA", (160, 48))


def rect(x0, y0, x1, y1, col):
    for y in range(y0, y1):
        for x in range(x0, x1):
            sheet.putpixel((x, y), col)


def framed(x0, y0, x1, y1, fill):
    """A rounded box: outline with the corner pixels left out."""
    rect(x0, y0, x1, y1, LINE)
    rect(x0 + 1, y0 + 1, x1 - 1, y1 - 1, fill)
    for x, y in [(x0, y0), (x1 - 1, y0), (x0, y1 - 1), (x1 - 1, y1 - 1)]:
        sheet.putpixel((x, y), (0, 0, 0, 0))


# --- Trees -------------------------------------------------------------------------
strip = Image.open(PACK / "Elements/Plants/spr_deco_tree_01_strip4.png").convert("RGBA")
tree = strip.crop((0, 0, 32, 34))
sheet.alpha_composite(tree, (0, 48 - 34))
sheet.alpha_composite(tree.transpose(Image.FLIP_LEFT_RIGHT), (32, 48 - 34))

# --- Bulletin board (32 x 32 at x = 64) ---------------------------------------------
bx = 64
rect(bx + 4, 29, bx + 28, 31, SHADOW)
for px in (bx + 5, bx + 24):  # posts
    rect(px, 6, px + 3, 30, LINE)
    rect(px + 1, 6, px + 2, 29, WOOD_LIGHT)
framed(bx + 1, 4, bx + 31, 23, WOOD)
rect(bx + 3, 6, bx + 29, 21, WOOD_MID)
rect(bx + 2, 2, bx + 30, 5, LINE)  # a little cap along the top
rect(bx + 3, 2, bx + 29, 4, WOOD_LIGHT)
for nx, ny, w, h in [(5, 7, 7, 8), (14, 8, 6, 6), (22, 7, 6, 9), (13, 15, 8, 5)]:  # pinned notes
    rect(bx + nx, ny, bx + nx + w, ny + h, PAPER)
    for ly in range(ny + 2, ny + h - 1, 2):
        rect(bx + nx + 1, ly, bx + nx + w - 1, ly + 1, PAPER_LINE)
    sheet.putpixel((bx + nx + w // 2, ny), hexc("#e43b44"))  # the pin

# --- Signs on posts (16 x 32 each from x = 96) ----------------------------------------
icons = ["UI/plant.png", "UI/basket.png", "Elements/Crops/milk.png", "UI/hammer.png"]
for i, name in enumerate(icons):
    sx = 96 + i * 16
    rect(sx + 5, 29, sx + 12, 31, SHADOW)
    rect(sx + 6, 14, sx + 10, 30, LINE)  # post
    rect(sx + 7, 14, sx + 9, 29, WOOD_LIGHT)
    framed(sx, 0, sx + 16, 16, BOARD)
    rect(sx + 1, 14, sx + 15, 15, WOOD_LIGHT)  # shaded bottom edge of the board
    icon = Image.open(PACK / name).convert("RGBA")
    box = icon.getbbox()
    icon = icon.crop(box)
    sheet.alpha_composite(icon, (sx + (16 - icon.width) // 2, 1 + (13 - icon.height) // 2))

# --- Hay bale (32 x 16 at 64, 32) ---------------------------------------------------
hx, hy = 64, 32
rect(hx + 4, hy + 13, hx + 29, hy + 15, SHADOW)
framed(hx + 3, hy + 2, hx + 29, hy + 14, HAY)
rect(hx + 4, hy + 3, hx + 28, hy + 5, HAY_LIGHT)
rect(hx + 4, hy + 11, hx + 28, hy + 13, HAY_DARK)
for x in range(hx + 6, hx + 27, 3):  # straw
    rect(x, hy + 6, x + 1, hy + 10, HAY_DARK)
for x in (hx + 10, hx + 21):  # twine
    rect(x, hy + 2, x + 1, hy + 14, LINE)

# --- Grain sack (16 x 16 at 96, 32) ---------------------------------------------------
sx, sy = 96, 32
rect(sx + 3, sy + 13, sx + 14, sy + 15, SHADOW)
framed(sx + 3, sy + 4, sx + 13, sy + 14, SACK)
rect(sx + 4, sy + 11, sx + 12, sy + 13, SACK_DARK)
rect(sx + 5, sy + 2, sx + 11, sy + 5, LINE)  # tied neck
rect(sx + 6, sy + 2, sx + 10, sy + 4, SACK)
rect(sx + 5, sy + 4, sx + 11, sy + 5, LINE)

OUT.mkdir(exist_ok=True)
sheet.save(OUT / "props.png")
print("saved", OUT / "props.png")
