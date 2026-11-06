# Tea house interior sources

AI image-gen JPGs → `assemble_tea_gen.py` (hard NN 32×32) → `tiles/<id>.png`
→ `build_rooms.py`.

Gameplay tiles are **only** `tiles/<id>.png` at 32×32. Soft `_raw_*.png`
intermediates are **not** written. Playbook:
`docs/interior-pixel-art-lessons.md` (store).

## Walls (EOE-70 — cabin recipe rolled here)

- `tea_wall_strip.jpg` — continuous back-wall face (warm wood posts + cream
  paper panels matching the exterior tea house timber), hard NN to **16×3**,
  slice so rows align
- Glowing windows stay in the mid strip cells (often span 2 cols — do not scrub
  neighbors into cream blocks)
- `tea_side_strip.jpg` — void + thin wood rim via `scale_side_cutaway`
- `tea_door_jamb.jpg` — opaque wood posts (not the void rim)
- Opaque doormat via `mat_tile`
- Tall N face (rows 0–2), room bake **16×10**
- Strip ids: top `128–143`, mid `144–159`, base `160–175`; sides `70/176/177`
  (+ east flips `178–181`)

## Floor / props

- `tea_floor_sheet.jpg` — warm honey oak planks (full-bleed; assemble fills
  gutters so tiles have no black seams)
- Props (hard NN): counter, urn, table, cushion, screen, nightstand, rug, mat
- **Keep** continuous bed (`tea_bed_full.jpg`) and cabin plant (48) — tea does
  not emit plant tiles
- Rug (63): tea loads after cabin in `build_rooms` so the hub rug wins

## Exterior boundary

Do **not** remake `assets/images/maps/buildings/tea_house.png` while iterating
this interior. Match its wood material in wall strips only.

Do **not** Pillow-invent tiles. Re-gen AI sources, then re-run assemble.
