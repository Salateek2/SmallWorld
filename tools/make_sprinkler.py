"""Draws the sprinkler (16x16 pixel art) the pack doesn't have: assets/farm/sprinkler.png.
A small metal post with a round head and a few drops of water. Run: python tools/make_sprinkler.py
"""
import os
from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "farm", "sprinkler.png")

COLORS = {
    ".": (0, 0, 0, 0),
    "o": (38, 43, 68, 255),      # dark outline
    "m": (139, 155, 180, 255),   # metal
    "l": (192, 203, 220, 255),   # metal highlight
    "d": (90, 105, 136, 255),    # metal shadow
    "w": (115, 190, 240, 255),   # water drop
    "h": (190, 230, 255, 255),   # water highlight
    "s": (0, 0, 0, 70),          # soft shadow on the ground
}

ART = [
    "................",
    "..h..........h..",
    ".w....h..h....w.",
    "...w...ww...w...",
    ".....w....w.....",
    "......oooo......",
    ".....ollmmo.....",
    ".....olmmdo.....",
    "......oddo......",
    ".......mo.......",
    "......olmo......",
    "......omdo......",
    ".....oommoo.....",
    "....olmmmmdo....",
    "....oddddddo....",
    ".....ssssss.....",
]


def main() -> None:
    image = Image.new("RGBA", (16, 16))
    for y, row in enumerate(ART):
        for x, key in enumerate(row):
            image.putpixel((x, y), COLORS[key])
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    image.save(OUT)
    print("saved", os.path.normpath(OUT))


if __name__ == "__main__":
    main()
