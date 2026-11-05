# FX sprites

Night light cookies (#35), drawn as holes in NightTint plus an additive glow:

- `lamp_light.png` 96x96 warm amber pool (oval, hard alpha rings);
  `lamp_light_flicker.png` 192x96 = 2 flicker frames (preferred if present).
- `lamp_light_neon.png` / `lamp_light_neon_flicker.png`: cyan variant used by
  City street lamps and Core braziers.
- `portal_light.png` 48x48 travel gate: flat cyan ring on a stone pad
  (silhouette is a ground circle — not a purple diamond shard).
  `portal_light_flicker.png` 96x48 = 2 frames.

Missing files fall back to a procedural cookie, so art can be swapped in with
no code change.

Ambient prop loops (#33), played by `AmbientPropFx` by Tiled `ambient` kind,
32x32 frames, metadata in the matching `.json` (frameWidth/frameHeight/frames/
stepTime/loop), drawn with FilterQuality.none:

- `steam_loop.png` (steam) and `steam_loop_cyan.png` (steam on the City map),
- `smoke_loop.png` (smoke), `fire_loop.png` (ember / fire),
- `mist_loop.png` (mist; one placement per prop, does not tile).

A missing sheet falls back to the procedural wisps.

Sentinel arena fight polish (EOE-2 / #65), hard-pixel AI → NN:

- `sentinel_slam_tele.png` 160×160 cracked plaza slam telegraph disc
- `sentinel_sweep_tele.png` 128×128 scanner sweep cone (apex on left)
- `sentinel_ring_tell.png` 64×64 thin expanding ring before the 8-way volley

Companion lockdown tiles live next to the boss sprite (not under `fx/`):

- `../sentinel_fence.png` 32×32 energy fence segment (tiled along the seal)
- `../sentinel_pylon.png` 32×32 corner pylon
- `../sentinel_rim.png` 32×32 floor rim decal on engage

Missing FX fall back to the previous procedural circles/wedges.
