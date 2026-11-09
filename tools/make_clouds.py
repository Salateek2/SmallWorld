"""Draws the clouds that drift over the sea: assets/clouds/clouds.png.

Four puffy clouds side by side, 64 x 40 px each, in the style of the Sunnyside example
scene: white bumps, a pale blue-grey belly, no outline. Each cloud is a pile of circles,
filled pixel by pixel (no smoothing), so it stays crisp pixel art.
Run from the project folder:  python tools/make_clouds.py
"""
import random
from pathlib import Path

from PIL import Image

OUT = Path(__file__).resolve().parent.parent / "assets" / "clouds"
W, H, COUNT = 64, 40, 4
WHITE = (255, 255, 255, 255)
SHADE = (215, 230, 242, 255)  # the underside
DEEP = (185, 205, 225, 255)  # the very bottom edge
random.seed(7)


def cloud():
    # Big bumps along a base line, smaller ones on top
    circles = []
    x = 10
    while x < W - 10:
        r = random.randint(7, 11)
        circles.append((x, H - 12 - random.randint(0, 3), r))
        x += random.randint(7, 11)
    for _ in range(3):
        circles.append((random.randint(18, W - 18), random.randint(17, 21), random.randint(7, 10)))
    # r * r - r: rounder bumps without single stray pixels at their tops
    inside = [[any((px - cx) ** 2 + (py - cy) ** 2 <= r * r - r for cx, cy, r in circles) and py < H - 6
               for px in range(W)] for py in range(H)]
    img = Image.new("RGBA", (W, H))
    for py in range(H):
        for px in range(W):
            if not inside[py][px]:
                continue
            below = [inside[py + d][px] if py + d < H else False for d in (1, 2, 3, 4)]
            if not below[0] or not below[1]:
                img.putpixel((px, py), DEEP)
            elif not below[2] or not below[3]:
                img.putpixel((px, py), SHADE)
            else:
                img.putpixel((px, py), WHITE)
    return img


sheet = Image.new("RGBA", (W * COUNT, H))
for i in range(COUNT):
    sheet.alpha_composite(cloud(), (i * W, 0))
OUT.mkdir(parents=True, exist_ok=True)
sheet.save(OUT / "clouds.png")
print("wrote", OUT / "clouds.png")
