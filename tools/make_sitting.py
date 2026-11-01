"""Makes a SITTING animation for the Sunnyside humans from their IDLE animation.

For every IDLE strip (base body and each hairstyle) it writes
Characters/Human/SITTING/<layer>_sitting_strip9.png, the same 9 frames of 96 x 64:
  - the whole character drops one pixel (sitting is lower than standing),
  - on the body, the standing legs are cut off below the belly and replaced with
    a thigh pointing forward (to the right, where the character faces) and a shin
    hanging down with the shoe at its end.
The hair only moves down, so every hairstyle fits the new body without being redrawn.
Run from the project folder:  python tools/make_sitting.py
"""
import os
from PIL import Image

HUMAN = "assets/Sunnyside_World_Assets/Characters/Human"
FRAME_W, FRAME_H = 96, 64
DROP = 1  # pixels the character sinks when sitting

# Colours of the body art
OUTLINE = (23, 20, 36, 255)
PANTS = (55, 68, 100, 255)
PANTS_SHADE = (36, 43, 66, 255)
SHOE = (117, 61, 58, 255)


def is_pants(c):
    return c[3] and c[2] > c[0] + 30 and c[2] > 90  # the light blue of the trousers


def sit_body(frame):
    """frame: one 96 x 64 base frame. Returns the sitting version."""
    px = frame.load()
    # The belly: the first row (from the top) with trouser pixels
    belly = next(y for y in range(FRAME_H) if any(is_pants(px[x, y]) for x in range(FRAME_W)))
    xs = [x for x in range(FRAME_W) if px[x, belly][3]]
    left, right = min(xs), max(xs)  # the outline on both sides (and the hand in front)

    out = Image.new("RGBA", frame.size)
    keep = frame.crop((0, 0, FRAME_W, belly + 1))  # head, torso, hands and belly
    out.alpha_composite(keep, (0, DROP))
    o = out.load()
    y = belly + 1 + DROP  # the thigh row, right under the belly

    def put(x, yy, c):
        o[x, yy] = c

    # Thigh: from the back of the hips forward, just past the body
    knee = right + 1
    for x in range(left + 1, knee):
        put(x, y, PANTS)
    put(left, y, OUTLINE)
    put(knee, y - 1, OUTLINE)
    put(knee, y, OUTLINE)
    # Shin hanging straight down from the knee, then the shoe pointing forward
    for x in range(left, knee - 2):
        put(x, y + 1, OUTLINE)  # underside of the thigh
    put(knee - 2, y + 1, PANTS_SHADE)
    put(knee - 1, y + 1, PANTS)
    put(knee, y + 1, OUTLINE)
    put(knee - 3, y + 2, OUTLINE)
    for x in range(knee - 2, knee + 1):
        put(x, y + 2, SHOE)
    put(knee + 1, y + 2, OUTLINE)
    for x in range(knee - 2, knee + 1):
        put(x, y + 3, OUTLINE)
    return out


def main():
    src_dir = os.path.join(HUMAN, "IDLE")
    dst_dir = os.path.join(HUMAN, "SITTING")
    os.makedirs(dst_dir, exist_ok=True)
    for name in sorted(os.listdir(src_dir)):
        if not name.endswith(".png") or name.startswith("tools_"):
            continue  # nothing in the hands while sitting
        strip = Image.open(os.path.join(src_dir, name)).convert("RGBA")
        frames = strip.width // FRAME_W
        out = Image.new("RGBA", strip.size)
        for i in range(frames):
            frame = strip.crop((i * FRAME_W, 0, (i + 1) * FRAME_W, FRAME_H))
            if name.startswith("base_"):
                frame = sit_body(frame)
            else:
                moved = Image.new("RGBA", frame.size)
                moved.alpha_composite(frame, (0, DROP))
                frame = moved
            out.alpha_composite(frame, (i * FRAME_W, 0))
        layer = name.split("_")[0]
        out.save(os.path.join(dst_dir, "%s_sitting_strip%d.png" % (layer, frames)))
        print("wrote", layer)


main()
