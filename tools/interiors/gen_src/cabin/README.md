# Ranger cabin interior sources

AI image-gen JPGs in this folder → `assemble_cabin_gen.py`
(`pixelize_gen` with `soft_fit=False` straight to **32×32**) → `tiles/<id>.png`
→ `build_rooms.py`.

Gameplay tiles are **only** `tiles/<id>.png` at 32×32. Soft `_raw_*.png`
intermediates are **not** written or committed — never use a 64/128 sheet as a
single gameplay tile.

Do **not** invent cabin tiles with Pillow drawing. Re-gen art via AI with hard
pixel art in mind, then re-run assemble.
