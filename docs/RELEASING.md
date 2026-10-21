# Releasing

Pushing a `vX.Y.Z` tag runs `.github/workflows/release.yml`: signed APK + web build,
GitHub Release, F-Droid repo (Klas96/fdroid), klasholmgren.se, and optionally itch.io.
`workflow_dispatch` is a dry run by default and publishes nothing.

## itch.io (butler)

The `itch` job is skipped until both of these are set (Settings → Secrets and variables → Actions):

- **Variable** `ITCH_GAME` — `user/game`, e.g. `klas96/echoes-of-elysium`.
- **Secret** `BUTLER_API_KEY` — from https://itch.io/user/settings/api-keys (or `butler login`).

It pushes two channels with `--userversion X.Y.Z`:

- `html5` — the web build, with `<base href>` rewritten to `./` (itch serves games from a CDN subpath in an iframe).
- `android` — the signed APK.

One-time setup on the itch.io project page (after the first push):

1. Kind of project: **HTML**. On the `html5` upload tick **"This file will be played in the browser"**;
   tag the `android` upload as Android.
2. Embed options: set a viewport (e.g. 1280×720 or a portrait size), enable the **Fullscreen button**,
   consider "Mobile friendly". Enable **SharedArrayBuffer support** only if a multi-threaded/wasm build needs it
   (it sets COOP/COEP headers and can break external embeds).
3. Limits: itch HTML5 uploads must be ≤ 1 GB extracted, ≤ 1000 files, and each file ≤ 200 MB.
