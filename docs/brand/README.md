# Echoes of Elysium — brand

## Spec

See [`spec.md`](spec.md) for the required deliverables:

- Logo / app icon on black and white
- 3 accent colours (HEX, RGB, HSL)
- 2 typefaces
- HTML `h1`–`h6` sizes
- Icon package
- PDF output

## Graphical profile

- Source: `echoes_of_elysium_graphical_profile.tex`
- Output: `echoes_of_elysium_graphical_profile.pdf`
- Version: 2.0 (aligned to `spec.md`)

Rebuild:

```bash
cd docs/brand
xelatex echoes_of_elysium_graphical_profile.tex
```

Requires XeLaTeX plus system fonts Comfortaa and DejaVu. App icon is loaded from `assets/icon/app_icon.png`.
