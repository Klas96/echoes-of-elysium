# FX sprites

Night light cookies (#35), drawn as holes in NightTint plus an additive glow:

- `lamp_light.png` 96x96 warm amber pool (oval, hard alpha rings);
  `lamp_light_flicker.png` 192x96 = 2 flicker frames (preferred if present).
- `lamp_light_neon.png` / `lamp_light_neon_flicker.png`: cyan variant used by
  City street lamps and Core braziers.

Missing files fall back to a procedural cookie, so art can be swapped in with
no code change.

Ambient prop loops (#33), played by `AmbientPropFx` by Tiled `ambient` kind,
32x32 frames, metadata in the matching `.json` (frameWidth/frameHeight/frames/
stepTime/loop), drawn with FilterQuality.none:

- `steam_loop.png` (steam) and `steam_loop_cyan.png` (steam on the City map),
- `smoke_loop.png` (smoke), `fire_loop.png` (ember / fire),
- `mist_loop.png` (mist; one placement per prop, does not tile).

A missing sheet falls back to the procedural wisps.
