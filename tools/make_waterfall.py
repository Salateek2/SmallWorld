"""Draws the waterfall that pours over a cliff: assets/water/waterfall.png (64 x 32).

Two rows like the cliff face (row 0 = the top, where the water tips over the edge;
row 1 = the bottom, where it splashes into the water below), 4 animation frames side by
side, so the streaks run downwards. Same blue as the tileset's water.
Run from the project folder:  python tools/make_waterfall.py
"""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
tiles = Image.open(ROOT / "assets/Sunnyside_World_Assets/Tileset/spr_tileset_sunnysideworld_16px.png").convert("RGBA")
WATER = tiles.getpixel((4 * 16 + 8, 1 * 16 + 8))  # plain water (4, 1)
LIGHT = (min(WATER[0] + 60, 255), min(WATER[1] + 70, 255), min(WATER[2] + 30, 255), 255)
FOAM = (235, 245, 255, 255)
DARK = (max(WATER[0] - 25, 0), max(WATER[1] - 30, 0), max(WATER[2] - 20, 0), 255)
FRAMES = 4
STREAKS = [(1, 0), (4, 5), (6, 11), (9, 2), (11, 8), (14, 13)]  # x, phase

sheet = Image.new("RGBA", (16 * FRAMES, 32), WATER)
for f in range(FRAMES):
    for y in range(32):
        for x in range(16):
            px = (f * 16 + x, y)
            if x in (0, 15):
                sheet.putpixel(px, DARK)  # the water's edges against the rock
                continue
            for sx, phase in STREAKS:
                if x == sx and (y - f * 4 + phase) % 8 < 4:
                    sheet.putpixel(px, LIGHT)  # streaks running down
            if y < 2:
                sheet.putpixel(px, LIGHT if y == 1 else FOAM)  # the lip where it tips over
            if y >= 28 and (x + y + f) % 3 != 0:
                sheet.putpixel(px, FOAM)  # splash at the bottom
(ROOT / "assets/water").mkdir(parents=True, exist_ok=True)
sheet.save(ROOT / "assets/water/waterfall.png")
print("wrote", ROOT / "assets/water/waterfall.png")
