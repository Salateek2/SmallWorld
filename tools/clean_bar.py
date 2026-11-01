"""Tidies Michal's Piskel bar counter (images/26.png) into assets/tavern/bar_corner.png:
removes stray pixels, joins the right side strip to the counter, and adds wood grain
to the counter top."""
import sys
from PIL import Image

src, dst = sys.argv[1], sys.argv[2]
im = Image.open(src).convert("RGBA")
px = im.load()
W, H = im.size
CLEAR = (0, 0, 0, 0)

# Stray pixels: the lone greys inside the L, the mark left of it, the line along the bottom
for x, y in [(66, 20), (70, 37), (13, 38), (13, 39), (13, 40)]:
    px[x, y] = CLEAR
for x in range(W):
    px[x, 78] = CLEAR
for x in range(W):  # a dot under the counter that isn't part of a leg
    if px[x, 73][3] and not px[x, 74][3] and not px[x - 1, 73][3] and not px[x + 1, 73][3]:
        px[x, 73] = CLEAR

# The side strip (x 90-91) had a one-pixel gap from the counter's front: fill it
SIDE = (140, 103, 80, 255)
for y in range(56, 64):
    if not px[89, y][3]:
        px[89, y] = SIDE

# Wood grain on the top: staggered plank seams, a shade darker than the wood
TOP = (100, 61, 45, 255)
GRAIN = (86, 52, 40, 255)
SHINE = (122, 82, 60, 255)
def grain(x, y, colour):
    if px[x, y] == TOP:
        px[x, y] = colour
for y, start in [(46, 0), (49, 9)]:  # front arm: two long seams with gaps
    for x in range(15, 88):
        if (x + start) % 24 not in (0, 1):
            grain(x, y, GRAIN)
for x, start in [(79, 0), (84, 7)]:  # back arm: seams running up
    for y in range(3, 45):
        if (y + start) % 18 not in (0, 1):
            grain(x, y, GRAIN)
for x, y in [(20, 44), (21, 44), (40, 47), (41, 47), (62, 51), (63, 51), (77, 10), (77, 11), (87, 30), (87, 31)]:
    grain(x, y, SHINE)  # polished spots
im.save(dst)
