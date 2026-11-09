"""Makes the beach edges, assets/paths/sand.png, from the path edges (assets/paths/paths.png).

Same layout as paths.png (see make_path_tiles.py): the grass creeps onto the sand with the
same wobbly edge, only the dirt colours become sand colours, and the pebbles become shells.
Run from the project folder after make_path_tiles.py:  python tools/make_sand_tiles.py
"""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent / "assets" / "paths"


def hexc(h):
    return (int(h[1:3], 16), int(h[3:5], 16), int(h[5:7], 16), 255)


# path colour -> beach colour (the beach tile itself is (228, 195, 114))
SWAP = {
    hexc("#bc795c"): (204, 166, 94, 255),  # rim next to the grass: damp, darker sand
    hexc("#c28569"): (214, 178, 102, 255),  # spots
    hexc("#e8b796"): (242, 218, 150, 255),  # light specks
    hexc("#a26955"): (236, 226, 212, 255),  # pebbles -> pale shells
}

image = Image.open(ROOT / "paths.png").convert("RGBA")
px = image.load()
for y in range(image.height):
    for x in range(image.width):
        if px[x, y] in SWAP:
            px[x, y] = SWAP[px[x, y]]
image.save(ROOT / "sand.png")
print("wrote", ROOT / "sand.png")
