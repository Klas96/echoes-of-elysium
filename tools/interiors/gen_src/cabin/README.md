# Ranger cabin interior sources

AI image-gen JPGs in this folder → `assemble_cabin_gen.py`
(`pixelize_gen` with `soft_fit=False` straight to **32×32**) → `tiles/<id>.png`
→ `build_rooms.py`.

Gameplay tiles are **only** `tiles/<id>.png` at 32×32. Soft `_raw_*.png`
intermediates are **not** written or committed — never use a 64/128 sheet as a
single gameplay tile.

Interior pixel-art lessons applied here:
- shared texel density (walls / floor / props)
- limited local palettes + 1px dark outlines
- baked contact shadows on prop feet
- wall face = upper logs + darker rail/wainscot (not a flat fill)
- floor = horizontal plank variants
- quiet props + one wall focal (hearth) + rug pattern focal
- continuous `cabin_bed_full.jpg` → hard NN 32×64 → head/foot split

Do **not** invent cabin tiles with Pillow drawing. Re-gen art via AI with hard
pixel art in mind, then re-run assemble.
