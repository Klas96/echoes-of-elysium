# Ranger cabin interior sources

AI image-gen JPGs in this folder → `assemble_cabin_gen.py`
(`pixelize_gen` with `soft_fit=False` straight to **32×32**) → `tiles/<id>.png`
→ `build_rooms.py`.

Gameplay tiles are **only** `tiles/<id>.png` at 32×32. Soft `_raw_*.png`
intermediates are **not** written or committed — never use a 64/128 sheet as a
single gameplay tile.

## Walls (locked recipe — cabin proving ground)

- `cabin_wall_strip.jpg` — **continuous** back-wall strip (full face), then
  hard NN to a 12×3 grid and slice so masonry rows align across tiles
- Large readable masonry/panels, sparse accent bricks, thin top edge,
  dark baseboard + floor-contact shadow band
- Door/window/hearth/map **inset** in the face (same texel density)
- `cabin_side_strip.jpg` — cutaway thickness (rim + dark inner); corners meet
- Tall N face (~3 tiles) vs Kaela; room bake is **12×10**
- Strip slices: top `80–91`, mid `92–103`, base `104–115`; sides `72/116/117`

## Props / floor

- shared texel density; limited palettes + 1px dark outlines
- baked contact shadows on prop feet
- floor = horizontal plank variants
- quiet props + one wall focal (hearth) + rug pattern focal
- continuous `cabin_bed_full.jpg` → hard NN 32×64 → head/foot split

Do **not** invent cabin tiles with Pillow drawing. Re-gen art via AI with hard
pixel art in mind, then re-run assemble.
