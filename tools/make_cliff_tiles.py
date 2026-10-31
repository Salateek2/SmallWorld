"""Draws SmallWorld's cliff tiles: assets/cliffs/cliffs.png (160 x 32).

Run from the project folder:  python tools/make_cliff_tiles.py
(needs Pillow:  pip install pillow)

Layout, 16 px columns, 2 tiles tall (upper and lower half of the cliff face):
  columns 0-3  rocky cliff face, four variants that join seamlessly in order (x % 4)
  column  4    left end (the side rock strip carries on down the face)
  column  5    right end
  column  6    wooden ladder (cleaned up from an AI-made sheet, ladder_source.png)
  columns 7-9  edges of the plateau's top, one piece per direction:
               row 0 = back-left corner, back edge, back-right corner
               row 1 = left side, (unused), right side
               The sides show a strip of rock (the ground drops away there too),
               the back has a dark outline with a light grass highlight.

Rocks are a Voronoi pattern that wraps around left-right, lit from the top-left,
in the Sunnyside tileset's own colours.
"""
import math
import random
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent.parent / "assets" / "cliffs"
random.seed(7)


def hexc(h):
    return (int(h[1:3], 16), int(h[3:5], 16), int(h[5:7], 16), 255)


LINE = hexc("#5e3434")
DARK = hexc("#733e39")
MID = [hexc("#9d573f"), hexc("#ac674d"), hexc("#b76145")]
LIGHT = [hexc("#c1755a"), hexc("#c28569")]
GRASS = hexc("#63c74d")
GRASS_DARK = hexc("#469847")
GRASS_LIGHT = hexc("#7bcf5c")
CLEAR = (0, 0, 0, 0)

W, H = 64, 32  # the four seamless variants


def rock_face():
    # Rocks in three loose rows, wider than tall
    points = []
    for y0, y1 in [(6, 15), (14, 24), (22, 33)]:
        x = random.uniform(0, 10)
        while x < W:
            points.append((x, random.uniform(y0, y1), random.choice(MID)))
            x += random.uniform(9, 15)

    def nearest(x, y):
        best, best_d = 0, 1e9
        for i, (px, py, _) in enumerate(points):
            dx = min(abs(x - px), W - abs(x - px))  # wraps left-right: seamless tiles
            d = dx * dx + ((y - py) * 1.6) ** 2
            if d < best_d:
                best, best_d = i, d
        return best

    cell = [[nearest(x + 0.5, y + 0.5) for x in range(W)] for y in range(H)]
    img = Image.new("RGBA", (W, H))
    for y in range(H):
        for x in range(W):
            c = cell[y][x]
            border = cell[y][(x + 1) % W] != c or (y + 1 < H and cell[y + 1][x] != c)
            col = points[c][2]
            if border:
                col = LINE
            elif (y > 0 and cell[y - 1][x] != c) or cell[y][(x - 1) % W] != c:
                col = random.choice(LIGHT)  # light from the top-left
            elif y + 2 < H and cell[y + 2][x] != c:
                col = DARK  # shade under each rock
            if y > 26 and col != LINE and random.random() < 0.5:
                col = DARK  # darker toward the foot of the cliff
            img.putpixel((x, y), col)
    # Grass lip with a ragged edge hanging over the rock (wraps too)
    for x in range(W):
        edge = 4 + (1 if math.sin(x * 1.3) + math.sin(x * 0.7 + 2) > 1.0 else 0) \
            + (1 if math.sin(x * 2.1 + 1) > 0.85 else 0)
        for y in range(edge + 1):
            img.putpixel((x, y), GRASS if y < edge - 1 else (GRASS_DARK if y == edge else GRASS_LIGHT))
    return img


SIDE = 6  # width of the rock strip along a plateau's sides (outline included)


def side_strip(tile, left, y_from, y_to):
    """The plateau's side wall: dark outline, rock, and a dark seam against the grass."""
    for y in range(y_from, y_to):
        for i in range(SIDE):
            x = i if left else 15 - i
            block = (y + (2 if i > 2 else 0)) % 5  # staggered rock blocks down the side
            if i == 0 or i == SIDE - 1 or block == 0:
                col = LINE
            elif block == 1:
                col = LIGHT[1] if i < SIDE - 2 else MID[1]  # lit top of each block
            elif i == SIDE - 2:
                col = DARK  # shade against the grass above
            else:
                col = MID[(y // 5 + i) % 3]
            tile.putpixel((x, y), col)


def end_piece(face, left):
    """A cliff end: the side rock strip carries on down the face."""
    tile = face.crop((0, 0, 16, H)).copy()
    side_strip(tile, left, 0, H)
    return tile


def grass_tile():
    return Image.new("RGBA", (16, 16), GRASS)


def back_edge():
    tile = grass_tile()
    for x in range(16):
        tile.putpixel((x, 0), LINE)
        tile.putpixel((x, 1), GRASS_LIGHT)
    return tile


def side_edge(left):
    tile = grass_tile()
    side_strip(tile, left, 0, 16)
    x = SIDE if left else 15 - SIDE
    for y in range(16):
        tile.putpixel((x, y), GRASS_LIGHT)  # light grass rim next to the edge
    return tile


def back_corner(left):
    tile = side_edge(left)
    for i in range(16):
        x = i if left else 15 - i
        if i >= SIDE:
            tile.putpixel((x, 0), LINE)
            tile.putpixel((x, 1), GRASS_LIGHT)
    # Rounded outer corner: the outline cuts across, outside it is see-through
    for y in range(3):
        for i in range(3 - y):
            tile.putpixel((i if left else 15 - i, y), CLEAR)
        tile.putpixel(((3 - y) if left else 15 - (3 - y), y), LINE)
    for i in range(1, SIDE):
        tile.putpixel((i if left else 15 - i, 0 if i >= 3 else 3 - i), LINE)
    return tile


face = rock_face()
sheet = Image.new("RGBA", (160, H))
sheet.alpha_composite(face, (0, 0))
sheet.alpha_composite(end_piece(face, True), (64, 0))
sheet.alpha_composite(end_piece(face, False), (80, 0))
sheet.alpha_composite(Image.open(HERE / "ladder_source.png").convert("RGBA"), (96, 0))
sheet.alpha_composite(back_corner(True), (112, 0))
sheet.alpha_composite(back_edge(), (128, 0))
sheet.alpha_composite(back_corner(False), (144, 0))
sheet.alpha_composite(side_edge(True), (112, 16))
sheet.alpha_composite(side_edge(False), (144, 16))
sheet.save(HERE / "cliffs.png")
print("saved", HERE / "cliffs.png")
