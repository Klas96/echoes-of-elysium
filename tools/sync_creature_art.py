#!/usr/bin/env python3
"""Copy the Designer's creature + obstacle art into the game assets, and draw
clearly-marked placeholders for anything not drawn yet.

    python3 tools/sync_creature_art.py [ART_DIR]      (default /workspace/echoes/art)
    (needs Pillow)

Every file keeps the Designer's name, so when real art lands, re-running this
script swaps it in with no code change. Placeholders are listed in
assets/images/creatures/PLACEHOLDERS.txt (and printed).

Creature sheets: 288x128, 32x32 frames, 9 cols x 4 rows (down, up, right,
left); cols 0-3 walk 8 fps, 4-5 idle 2 fps, 6-8 happy 6 fps; <name>_sheet.json
has the frame ranges and the flying flag. Portraits 96x96 (befriended /
sketch / silhouette), shadow 16x6. puffcap_hide.png: 3 frames of 32x32
(hidden, peek, out). river_pebble_sparkle.png: 2 frames of 16x16;
moonflower_glow.png: 2 frames of 16x24 (each with a .json sidecar).
"""
import json, os, shutil, sys
from PIL import Image, ImageDraw, ImageOps

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = sys.argv[1] if len(sys.argv) > 1 else "/workspace/echoes/art"
CRE = os.path.join(ROOT, "assets", "images", "creatures")
OBS = os.path.join(ROOT, "assets", "images", "obstacles")
os.makedirs(CRE, exist_ok=True); os.makedirs(OBS, exist_ok=True)

ABILITY = ["glowmoth", "vinefox", "stoneturtle"]          # art/creatures/
AMBIENT = ["puffcap", "brookling", "hushdeer"]            # art/creatures/ambient/
PER_SPECIES = ["_sheet.png", "_sheet.json", "_shadow.png", "_portrait.png",
               "_portrait_sketch.png", "_portrait_silhouette.png"]
# placeholder recolours: species -> (base species, hue shift 0-255, saturation x, brightness x)
RECOLOUR = {"puffcap": ("stoneturtle", 230, 1.6, 1.05), "brookling": ("vinefox", 150, 0.7, 0.85),
            "hushdeer": ("vinefox", 190, 0.35, 1.25)}
placeholders = []

def recolour(im, hue, sat, val):
    im = im.convert("RGBA"); a = im.getchannel("A")
    h, s, v = im.convert("RGB").convert("HSV").split()
    h = h.point(lambda p: (p + hue) % 256)
    s = s.point(lambda p: min(255, int(p * sat)))
    v = v.point(lambda p: min(255, int(p * val)))
    out = Image.merge("HSV", (h, s, v)).convert("RGBA"); out.putalpha(a)
    return out

def copy(src, dst):
    shutil.copyfile(src, dst)

def species(name, folder):
    for suf in PER_SPECIES:
        src = os.path.join(folder, name + suf); dst = os.path.join(CRE, name + suf)
        if os.path.exists(src):
            copy(src, dst); continue
        base, hue, sat, val = RECOLOUR[name]
        bsrc = os.path.join(CRE, base + suf)
        if suf.endswith(".json"):
            j = json.load(open(bsrc)); j["flying"] = False; j["ambient"] = True; j["placeholder"] = True
            json.dump(j, open(dst, "w"))
        elif suf in ("_portrait_silhouette.png", "_shadow.png"):
            copy(bsrc, dst)
        else:
            recolour(Image.open(bsrc), hue, sat, val).save(dst)
        placeholders.append(name + suf)

def strip(name, frames, fw, fh, draw):
    """placeholder strip of fw x fh frames"""
    dst = os.path.join(CRE, name)
    im = Image.new("RGBA", (fw * frames, fh), (0, 0, 0, 0))
    for i in range(frames): draw(ImageDraw.Draw(im), i * fw, i)
    im.save(dst); placeholders.append(name)

def extra(name, make):
    for folder in (os.path.join(ART, "creatures", "ambient"), os.path.join(ART, "creatures")):
        src = os.path.join(folder, name)
        if os.path.exists(src):
            copy(src, os.path.join(CRE, name))
            j = os.path.splitext(src)[0] + ".json"
            if os.path.exists(j): copy(j, os.path.join(CRE, os.path.basename(j)))
            return
    make()

def puffcap_hide():
    # hidden (cap only), peeking (eyes under the cap), out (sheet idle frame)
    im = Image.new("RGBA", (96, 32), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    for f in range(2):
        x = f * 32
        d.ellipse([x + 5, 13, x + 27, 31], fill=(70, 50, 40, 255))                 # stem shadow
        d.pieslice([x + 3, 8 - f * 2, x + 29, 34 - f * 2], 180, 360, fill=(214, 72, 84, 255), outline=(6, 8, 18, 255))
        for (sx, sy) in ((9, 14), (16, 11), (23, 14)):
            d.ellipse([x + sx - 2, sy - 2 - f * 2, x + sx + 2, sy + 2 - f * 2], fill=(250, 240, 230, 255))
        if f == 1:
            d.rectangle([x + 11, 22, x + 13, 24], fill=(20, 20, 30, 255)); d.rectangle([x + 19, 22, x + 21, 24], fill=(20, 20, 30, 255))
    sheet = Image.open(os.path.join(CRE, "puffcap_sheet.png")).convert("RGBA")
    im.alpha_composite(sheet.crop((4 * 32, 0, 5 * 32, 32)), (64, 0))
    im.save(os.path.join(CRE, "puffcap_hide.png")); placeholders.append("puffcap_hide.png")

def pebble(d, x, i):
    d.ellipse([x + 3, 6, x + 13, 13], fill=(120, 150, 190, 255), outline=(6, 8, 18, 255))
    d.ellipse([x + 5, 7, x + 8, 9], fill=(230, 245, 255, 255))
    if i == 1: d.point([(x + 12, 4), (x + 13, 3), (x + 11, 3), (x + 12, 2), (x + 12, 5)], fill=(255, 255, 255, 255))

def moonflower(d, x, i):
    d.line([x + 8, 23, x + 8, 10], fill=(60, 140, 90, 255))
    c = (230, 225, 255, 255) if i == 0 else (255, 255, 255, 255)
    for (dx, dy) in ((0, -3), (3, 0), (0, 3), (-3, 0)):
        d.ellipse([x + 8 + dx - 2, 9 + dy - 2, x + 8 + dx + 2, 9 + dy + 2], fill=c)
    d.ellipse([x + 7, 8, x + 9, 10], fill=(255, 230, 140, 255))

for n in ABILITY: species(n, os.path.join(ART, "creatures"))
for n in AMBIENT: species(n, os.path.join(ART, "creatures", "ambient"))
extra("puffcap_hide.png", puffcap_hide)
# pickups/decor: 16x16 pebble (+2-frame glint strip), 16x24 moonflower (+2-frame glow strip)
extra("river_pebble.png", lambda: strip("river_pebble.png", 1, 16, 16, pebble))
extra("river_pebble_sparkle.png", lambda: strip("river_pebble_sparkle.png", 2, 16, 16, pebble))
extra("moonflower.png", lambda: strip("moonflower.png", 1, 16, 24, moonflower))
extra("moonflower_glow.png", lambda: strip("moonflower_glow.png", 2, 16, 24, moonflower))

# obstacles (README in art/obstacles); glyph tablet from the calm set
for f in ("boulder.png", "boulder_2x2.png", "boulder_push_anim.png", "darkness_overlay.png", "light_mask.png",
          "shimmer.png", "shimmer_anim.png", "chest_plain.png", "fetch_sparkle_anim.png"):
    copy(os.path.join(ART, "obstacles", f), os.path.join(OBS, f))
glyph = os.path.join(os.path.dirname(ART), "art_v2", "calm", "glyph.png")
if os.path.exists(glyph): copy(glyph, os.path.join(OBS, "glyph.png"))

# journal UI kit (README in art/ui): 9-slice book halves + entry card, tab/currency icons (@2x only)
UI = os.path.join(ROOT, "assets", "images", "ui")
os.makedirs(UI, exist_ok=True)
for f in ("book_left@2x.png", "book_right@2x.png", "entry_card@2x.png"):
    copy(os.path.join(ART, "ui", f), os.path.join(UI, f))
for f in ("tab_paw_32@2x.png", "tab_moon_32@2x.png", "crystal_16@2x.png"):
    copy(os.path.join(ART, "ui", "icons", f), os.path.join(UI, f))

# the vine fox's sweetroot stump: the woods tileset stump (tile 194) for now
placeholders += ["../obstacles/stump.png (woods tileset stump)", "../obstacles/bramble.png (woods tileset bush)"]
ts = Image.open(os.path.join(ROOT, "tools", "tilesets", "woods.png")).convert("RGBA")
tile = lambda i: ts.crop((i % 16 * 32, i // 16 * 32, i % 16 * 32 + 32, i // 16 * 32 + 32))
tile(194).save(os.path.join(OBS, "stump.png"))
# brambles over the SCENT hidden path: the woods bush (tile 173) until the
# Designer draws a thicket; the path itself shows Designer's shimmer.png
tile(173).save(os.path.join(OBS, "bramble.png"))

with open(os.path.join(CRE, "PLACEHOLDERS.txt"), "w") as f:
    f.write("# Generated by tools/sync_creature_art.py: stand-ins until the Designer's art lands.\n")
    for p in placeholders: f.write(p + "\n")
print("placeholders:", ", ".join(placeholders) or "none")
