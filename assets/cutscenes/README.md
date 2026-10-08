# Cutscenes

Each cutscene lives in its own folder: `assets/cutscenes/<id>/<id>.json` plus
its stills. The folder must be listed under `flutter: assets:` in
`pubspec.yaml`. Ship stills as **WebP only** (1280x720, ~q90, no text in the
image); never commit the source PNGs.

Played by `CutscenePlayer` (`lib/cyberpunk_space_rpg/ui/cutscene_player.dart`);
`Cutscenes.route(id: ..., then: ...)` (`ui/cutscenes.dart`) plays one before a
screen and stores the story flag `cutscene:<id>` in the save when it ends or
is skipped (`once: true` skips it if already seen).

Preview while authoring (any panel can be frozen for screenshots):

    flutter run -d chrome -t tools/cutscene_preview.dart
    # URL: ?id=coalition  |  ?id=awakening&panel=2&t=4  |  ?panel=4&title=1  |  &typing=1

## JSON format

Designer's files work as-is. Unknown keys (`trigger`, `note`, `pan_format`)
are ignored; a malformed optional field falls back to its default.

```json
{
  "id": "awakening",
  "size": [1280, 720],            // art size; its aspect drives letterboxing
  "panelDuration": 7.0,           // optional default seconds per panel (7)
  "crossfade": 0.8,               // optional seconds (0.8)
  "speakers": {                   // optional; defaults below
    "N":    {"narrator": true},                       // italic, no name
    "GAIA": {"name": "GAIA", "color": "#00FF88"}
  },
  "panels": [
    {
      "image": "awakening_p1.webp",                   // relative to this folder
      "duration": 7.0,                                // optional, overrides panelDuration
      "pan": {"from": [1.0, 0.5, 0.5], "to": [1.08, 0.45, 0.5]},  // [zoom >= 1, centreX 0-1, centreY 0-1]
      "fx": "brighten green over 1.5 s",              // or a list of objects, see below
      "lines": [
        {"speaker": "N", "text": "Elysium Colony. Year 2387."},
        {"speaker": "GAIA", "text": "...Who are you?", "delay": 1.6, "hold": 3}
      ],
      "then": "title card ECHOES OF ELYSIUM over the upper sky"
    }
  ]
}
```

- **lines**: shown one at a time over the bottom fifth of the picture
  (portrait phones: in the band under the picture), typewriter at 38 chars/s.
  `speaker` "N" = narrator. Built-in colours (matching the in-game dialogue):
  GAIA green, KAELA cyan, VOSS red, ASHA amber, AETHERIAN / ECHO-7 violet,
  ARCHIVIST gold; any other name shows in cyan. `delay` = seconds before the
  line appears (0.5), `hold` = seconds after it's fully typed (default from
  length, 1.8-6 s; longer when `voice` is set so the VO can finish).
  Optional `voice`: asset path under `audio/voices/` played when the line
  appears (regenerate with `tools/gen_cutscene_voices.py`). A plain string is
  a narrator line. `"lines": []` = a silent panel. A panel stays at least
  `duration`, longer if its lines need it.
- **Input**: tap/click/Space/Enter finishes the typing, then goes to the next
  line/panel. SKIP button or Esc ends the cutscene.
- **pan**: Ken Burns move, eased, over the panel's running time. Only `from`
  or `to` = hold still. Centres are clamped so the view never leaves the image.
- **fx**: shorthand string or object(s)
  `{"type": "brighten", "color": "#00FF88", "start": 0.4, "duration": 1.5, "strength": 0.35}`.
  Types: `brighten` (colour light ramps in and stays), `pulse` (slow
  repeating glow; `duration` = one breath), `flash` (bright then fades),
  `darken` (multiply towards the colour). Shorthand understands those words
  plus "glow"; colours: `#RRGGBB` or green, cyan, teal, blue, purple, red,
  amber, orange, gold, white. New types: add to `CutsceneEffect.types` and
  `_applyEffect` in the player.
- **Local effects** (any fx type):
  - `"mask": "coalition_p4_glow.webp"`: the effect only shows through the
    mask's alpha. Same size as the panel (1280x720), white/any colour where
    the effect goes, transparent elsewhere, soft edges welcome; it is
    stretched over the panel and pans with it. Relative to this folder, WebP.
    Masked effects default to `strength` 0.6 (whole-frame ones 0.22-0.4).
    Example: `{"type": "pulse", "color": "#00FF88", "mask": "coalition_p4_glow.webp"}`.
  - `"center": [0.58, 0.63], "radius": 0.22`: a soft round spot instead of
    a mask image (centre as fractions of the panel, radius as a fraction of
    its width). The shorthand `"pulse green glow on the seed (x0.58, y0.63)"`
    does the same.
- **Title card**: `"then": "title card <TEXT> over the upper sky"` (upper/sky,
  lower, otherwise centre) or explicitly
  `"titleCard": {"text": "ECHOES OF ELYSIUM", "subtitle": "", "position": [0.5, 0.3], "color": "#00FFCC", "fadeIn": 1.4, "hold": 4}`.
  Shown after the panel's lines, then the scene fades to black. Can be on
  any panel, not just the last.
