"""Draws SmallWorld's path edges: assets/paths/paths.png (256 x 272).

Run from the project folder:  python tools/make_path_tiles.py   (needs Pillow)

The game lays plain dirt tiles for a path, then puts one of these see-through pieces on
top of every path tile so the grass around it creeps in with a wobbly, rounded edge
(like the paths in the Sunnyside example scene) instead of a straight boxy line.

Layout: 16 x 16 px tiles.
  column = which sides have grass next to the path tile:  1 = north, 2 = east, 4 = south, 8 = west
  row    = which corners have grass diagonally (only drawn where both sides there are path):
           1 = north-east, 2 = south-east, 4 = south-west, 8 = north-west
  row 16 = four pebble decorations, scattered on some path tiles.
The wobble repeats every 16 px, so neighbouring edge pieces always join up.
"""
import math
import random
from pathlib import Path

from PIL import Image

OUT = Path(__file__).resolve().parent.parent / "assets" / "paths"
random.seed(3)


def hexc(h):
    return (int(h[1:3], 16), int(h[3:5], 16), int(h[5:7], 16), 255)


GRASS = hexc("#63c74d")
GRASS_EDGE = hexc("#4fa748")  # darker green where the grass meets the dirt
GRASS_TUFT = hexc("#7bcf5c")
DIRT_RIM = hexc("#bc795c")  # the dirt is a little darker right next to the grass
DIRT_SPOT = hexc("#c28569")
DIRT_LIGHT = hexc("#e8b796")
STONE = hexc("#a26955")
CLEAR = (0, 0, 0, 0)

N, E, S, W = 1, 2, 4, 8
NE, SE, SW, NW = 1, 2, 4, 8


def wobble(t, phase):
    """How far the grass reaches in (2-5 px), repeating every 16 px."""
    a = 2 * math.pi * t / 16
    v = 0.9 * math.sin(a + phase) + 0.7 * math.sin(2 * a + phase * 1.7) + 0.5 * math.sin(3 * a + phase * 0.6)
    return 3.2 + v


PHASES = {N: 0.3, E: 1.9, S: 3.1, W: 4.4}


def is_grass(x, y, edges, corners):
    cx, cy = x + 0.5, y + 0.5
    if edges & N and cy < wobble(cx, PHASES[N]):
        return True
    if edges & S and cy > 16 - wobble(cx, PHASES[S]):
        return True
    if edges & W and cx < wobble(cy, PHASES[W]):
        return True
    if edges & E and cx > 16 - wobble(cy, PHASES[E]):
        return True
    # Rounded outer corners where two grass sides meet
    for need, (fx, fy) in [(N | W, (0, 0)), (N | E, (16, 0)), (S | E, (16, 16)), (S | W, (0, 16))]:
        if edges & need == need and abs(cx - fx) + abs(cy - fy) < 8.5:
            return True
    # Little grass bites in inside corners (grass only diagonally)
    for bit, (fx, fy), sides in [(NE, (16, 0), N | E), (SE, (16, 16), S | E), (SW, (0, 16), S | W), (NW, (0, 0), N | W)]:
        if corners & bit and not (edges & sides) and math.hypot(cx - fx, cy - fy) < 3.6:
            return True
    return False


def edge_tile(edges, corners):
    grass = [[is_grass(x, y, edges, corners) for x in range(16)] for y in range(16)]
    tile = Image.new("RGBA", (16, 16), CLEAR)
    rng = random.Random(edges * 31 + corners)
    for y in range(16):
        for x in range(16):
            near = [(x + dx, y + dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))]
            touches_dirt = any(0 <= nx < 16 and 0 <= ny < 16 and not grass[ny][nx] for nx, ny in near)
            touches_grass = any(0 <= nx < 16 and 0 <= ny < 16 and grass[ny][nx] for nx, ny in near)
            if grass[y][x]:
                if touches_dirt:
                    tile.putpixel((x, y), GRASS_EDGE)
                else:
                    tile.putpixel((x, y), GRASS_TUFT if rng.random() < 0.06 else GRASS)
            elif touches_grass:
                tile.putpixel((x, y), DIRT_RIM)  # shade along the edge of the path
    return tile


def pebbles(seed):
    rng = random.Random(seed)
    tile = Image.new("RGBA", (16, 16), CLEAR)
    for _ in range(rng.randint(2, 4)):
        x, y = rng.randint(3, 12), rng.randint(3, 12)
        if rng.random() < 0.5:
            tile.putpixel((x, y), STONE)  # tiny stone with a light top
            tile.putpixel((x, y - 1), DIRT_LIGHT)
        else:
            tile.putpixel((x, y), DIRT_SPOT)
            tile.putpixel((x + 1, y), DIRT_SPOT)
    return tile


OUT.mkdir(parents=True, exist_ok=True)
sheet = Image.new("RGBA", (256, 272), CLEAR)
for edges in range(16):
    for corners in range(16):
        sheet.alpha_composite(edge_tile(edges, corners), (edges * 16, corners * 16))
for i in range(4):
    sheet.alpha_composite(pebbles(i + 11), (i * 16, 256))
sheet.save(OUT / "paths.png")
print("saved", OUT / "paths.png")
