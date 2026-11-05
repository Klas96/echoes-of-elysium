# Ranger cabin interior sources

Hard 32×32 pixel art is authored in `build_rooms.py` (Pillow) and exported by
`tools/interiors/assemble_cabin_gen.py` into `tiles/<id>.png`.

The `*.jpg` files here are **legacy soft AI references** and are **not** used by
the assembler. Do not reintroduce LANCZOS→NEAREST downscales for cabin tiles.
