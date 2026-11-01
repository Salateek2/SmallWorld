"""Tidies Michal's Piskel corner sofa (images/28.png) into assets/tavern/sofa_corner.png:
snaps the few off-palette pixels to her six colours and adds cushion seams to the tall seat
to match the one on the bottom seat."""
import sys
from PIL import Image

src, dst = sys.argv[1], sys.argv[2]
im = Image.open(src).convert("RGBA")
px = im.load()
W, H = im.size
PALETTE = [(129, 63, 65), (158, 81, 67), (146, 66, 68), (76, 45, 46), (177, 95, 70), (144, 67, 62)]
SEAT, SEAM = (129, 63, 65, 255), (146, 66, 68, 255)

for y in range(H):
    for x in range(W):
        r, g, b, a = px[x, y]
        if a:
            nearest = min(PALETTE, key=lambda c: (c[0] - r) ** 2 + (c[1] - g) ** 2 + (c[2] - b) ** 2)
            px[x, y] = nearest + (255,)

# Seams across the tall seat (x 10-15), two pixels high like the bottom seat's
for top in (26, 42):
    for y in (top, top + 1):
        for x in range(10, 16):
            if px[x, y] == SEAT:
                px[x, y] = SEAM
im.save(dst)
