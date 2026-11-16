"""Makes the icons of the things you can forage: assets/forage/{mushroom,berry,orange,shell}.png.
The mushroom is cut out of the pack's tileset (without its shadow); the berries, the orange and
the seashell are small pixel drawings in the pack's own colours (the pack only has the fruit
on the bushes). Run: python tools/make_forage.py
"""
import os
from PIL import Image

ROOT = os.path.join(os.path.dirname(__file__), "..", "assets")
TILESET = os.path.join(ROOT, "Sunnyside_World_Assets", "Tileset", "spr_tileset_sunnysideworld_16px.png")
OUT = os.path.join(ROOT, "forage")
MUSHROOM_TILE = (49, 7)

COLORS = {
    ".": (0, 0, 0, 0),
    # leaves and stems (the bushes' greens)
    "g": (62, 137, 72, 255),
    "l": (99, 199, 77, 255),
    "s": (115, 63, 58, 255),
    # berries
    "d": (162, 38, 50, 255),
    "r": (227, 58, 68, 255),
    "h": (246, 117, 123, 255),
    # orange
    "e": (191, 75, 48, 255),
    "o": (247, 119, 35, 255),
    "a": (250, 173, 52, 255),
    "y": (252, 231, 97, 255),
    # seashell
    "k": (115, 63, 58, 255),
    "w": (255, 240, 220, 255),
    "p": (246, 170, 150, 255),
    "q": (214, 120, 110, 255),
}

ART = {
    "berry": [
        ".....gg....",
        "....gllg...",
        ".....sg....",
        "..dd.s.dd..",
        ".dhrdsdhrd.",
        ".drrd.drrd.",
        "..dddddd...",
        "...dhrd....",
        "...drrd....",
        "....dd.....",
    ],
    "orange": [
        ".....gg...",
        "....gllg..",
        "....sgg...",
        "...eeee...",
        "..eoaaoe..",
        ".eoayaooe.",
        ".eoaaoooe.",
        ".eooooooe.",
        "..eooooe..",
        "...eeee...",
    ],
    "shell": [
        "...kkkkk...",
        ".kkwpwpwkk.",
        "kwwpwpwpwwk",
        "kwpwwpwwpwk",
        "kwpwwpwwpwk",
        ".kwpwpwpwk.",
        ".kqwpwpwqk.",
        "..kqwpwqk..",
        "...kqqqk...",
        "....kkk....",
    ],
}


def draw(rows: list[str]) -> Image.Image:
    image = Image.new("RGBA", (len(rows[0]), len(rows)))
    for y, row in enumerate(rows):
        for x, key in enumerate(row):
            image.putpixel((x, y), COLORS[key])
    return image


def mushroom() -> Image.Image:
    tiles = Image.open(TILESET).convert("RGBA")
    x, y = MUSHROOM_TILE
    tile = tiles.crop((x * 16, y * 16, x * 16 + 16, y * 16 + 16))
    for py in range(16):
        for px in range(16):
            if tile.getpixel((px, py))[3] < 255:  # the soft shadow under it
                tile.putpixel((px, py), (0, 0, 0, 0))
    return tile.crop(tile.getbbox())


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    mushroom().save(os.path.join(OUT, "mushroom.png"))
    for name, rows in ART.items():
        draw(rows).save(os.path.join(OUT, name + ".png"))
    print("Saved the forage icons to", os.path.normpath(OUT))


if __name__ == "__main__":
    main()
