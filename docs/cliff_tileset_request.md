# Cliff tileset request (paste this to the image AI, together with cliff_tileset_template.png)

Please create a pixel-art **cliff / plateau tileset** for a cozy top-down farming game.

## Format (very important)
- One PNG, exactly **128 × 112 pixels**: a grid of **8 columns × 7 rows of 16×16 tiles**.
- Each tile goes in the cell shown in the attached template (A1 = top-left cell, etc.).
  Empty cells in the template stay fully transparent.
- **Transparent background** (real alpha, no white or checkerboard).
- True pixel art: every pixel exactly 1 pixel, hard edges, **no anti-aliasing, no blur, no gradients**.
- Everything must line up with the 16-pixel grid so tiles join seamlessly when placed side by side.
- **No black outlines.** Use darker shades of the same colour for edges and shading.
- Light comes from the top-left.

## Style and colours
Soft, cozy, colourful pixel art (like Stardew Valley). Use only these colours (or very close):
- Grass: #63c74d (main), #7bcf5c and #87cf5e (light), #51ac69 and #469847 (dark edges)
- Cliff earth/rock: #9d573f, #ac674d, #b86f50, #b76145, #c28569, #c1755a
- Darkest cliff shadow: #733e39, #ab3520
- Wood (stairs, ladder): #e8b796, #de9f6e, #c58a63, #b86f50, #8e574a

## What each tile is
The plateau is raised ground; its **front (south) side is a cliff that is 2 tiles tall**.
Seen from the front at a slight top-down angle.

**Top surface (rows A–C)** — grass on top of the plateau:
- A1, A2, A3: back edge of the plateau (top-left corner, straight top edge, top-right corner).
  The part outside the plateau is transparent. Rounded outer corners.
- B1, B3: left and right side edges. B2: plain grass top (fills the middle).
- A4, A5, B4, B5: inner (concave) corners, for L-shaped plateaus.
- C1, C2, C3: front edge, where the grass ends and the cliff drops down
  (a grass lip hanging slightly over the rock). C1/C3 are the rounded front corners.

**Cliff face (rows D–E)** — the rock wall below the front edge, 2 tiles tall:
- D = upper row of the face, E = lower row (where the rock meets the ground below).
- D1/E1 = left end, D4/E4 = right end (rounded, shaded), D2/E2 and D3/E3 = middle pieces
  (two variants that tile seamlessly next to each other, chunky rocky texture).
- The bottom of E tiles should have a little grass/darker shadow where the rock meets the ground.

**Extras (rows F–G)**:
- F1: grass with a soft darker shadow, placed on the ground right below a cliff.
- F2, F3, F4: a **wooden staircase** cut into the cliff, 1 tile wide, top to bottom
  (F2 replaces the front edge tile, F3 and F4 replace the two face tiles).
- G1, G2: a **wooden ladder** leaning on the cliff face (upper and lower half), with
  transparent background so the cliff behind shows through.

Please do not copy any existing game's art; create original tiles in this style.
