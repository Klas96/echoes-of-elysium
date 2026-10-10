# FX sprites

Night light cookies (#35), drawn as holes in NightTint plus an additive glow:

- `lamp_light.png` 96x96 warm amber pool (oval, hard alpha rings);
  `lamp_light_flicker.png` 192x96 = 2 flicker frames (preferred if present).
- `lamp_light_neon.png` / `lamp_light_neon_flicker.png`: cyan variant used by
  City street lamps and Core braziers.

Missing files fall back to a procedural cookie, so art can be swapped in with
no code change.
