# Ranger cabin interior sources

AI image-gen JPGs in this folder → `assemble_cabin_gen.py`
(`pixelize_gen` with `soft_fit=False` straight to **32×32**) → `tiles/<id>.png`
→ `build_rooms.py`.

Gameplay tiles are **only** `tiles/<id>.png` at 32×32. Soft `_raw_*.png`
intermediates are **not** written or committed — never use a 64/128 sheet as a
single gameplay tile.

Full playbook (for the next interior redesign): store
`docs/interior-pixel-art-lessons.md`.

## Walls (locked recipe — cabin proving ground)

- `cabin_wall_strip.jpg` — **continuous** back-wall strip (full face), hard NN
  to a 12×3 grid, slice so **log** rows align across tiles
- Material matches the exterior cabin prop (stacked horizontal logs / wood) —
  refs teach cutaway presentation, not a forced stone palette
- Thin top edge, dark baseboard + floor-contact shadow band
  (`trim_floor_below_baseboard`)
- Window/hearth **inset** in the face; seat the full window into one mid tile
  (`_seat_window_tile`) so strip columns do not half-cut it
- Hearth: grey-stone mouth detect + capped baseboard seat
  (`_lower_hearth_column`) — do not treat log grooves as a firebox
- `cabin_side_strip.jpg` — void + thin rim via `scale_side_cutaway` (never
  stretch into dark columns); corners meet the face
- Door jambs: `cabin_door_jamb.jpg` (opaque wood), not the side void
- Tall N face (~3 tiles) vs Kaela; room bake is **12×10**
- Strip slices: top `80–91`, mid `92–103`, base `104–115`; sides `72/116/117`

## Props / floor

- shared texel density; limited palettes + 1px dark outlines
- baked contact shadows on prop feet
- floor = horizontal plank variants
- quiet props + one wall focal + rug pattern focal
- doormat via `mat_tile` (opaque) — clearing alpha reads as black entrance tiles
- continuous `cabin_bed_full.jpg` → hard NN 32×64 → head/foot split

## Exterior boundary

Do **not** remake `assets/images/maps/buildings/ranger_cabin.png` while
iterating this interior. Match its material in wall strips only.

Do **not** invent cabin tiles with Pillow drawing. Re-gen art via AI with hard
pixel art in mind, then re-run assemble.
