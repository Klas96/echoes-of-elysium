#!/usr/bin/env python3.11
"""Generate pixel art sprites for Echoes of Elysium using Pillow only."""

from PIL import Image, ImageDraw
import os

OUT_DIR = "assets/images/sprites"
os.makedirs(OUT_DIR, exist_ok=True)

def save(img, name):
    path = f"{OUT_DIR}/{name}.png"
    img.save(path)
    print(f"  {name}.png ({img.width}x{img.height})")

def shadow(draw, size, alpha=70):
    w = size
    draw.ellipse([int(w*0.15), int(w*0.72), int(w*0.85), int(w*0.95)], fill=(0,0,0,alpha))

# ── Player ─────────────────────────────────────────────────────────────────────
def make_player():
    S = 32
    img = Image.new('RGBA', (S, S), (0,0,0,0))
    d = ImageDraw.Draw(img)
    shadow(d, S)
    # Legs
    d.ellipse([8, 21, 14, 28], fill=(0, 95, 90))
    d.ellipse([18, 21, 24, 28], fill=(0, 95, 90))
    # Body
    d.ellipse([5, 13, 27, 26], fill=(0, 155, 145))
    # Chest plate
    d.ellipse([10, 15, 22, 24], fill=(0, 190, 180))
    # Arms
    d.ellipse([1, 13, 9, 22], fill=(0, 130, 122))
    d.ellipse([23, 13, 31, 22], fill=(0, 130, 122))
    # Weapon on left arm
    d.rectangle([0, 16, 4, 19], fill=(0, 80, 200))
    # Head
    d.ellipse([9, 3, 23, 16], fill=(0, 118, 110))
    # Visor
    d.ellipse([11, 6, 21, 14], fill=(0, 230, 230))
    d.ellipse([12, 7, 18, 12], fill=(180, 255, 255, 200))
    # Core glow
    d.ellipse([13, 17, 19, 22], fill=(0, 255, 220, 210))
    return img

# ── NPC Gaia ───────────────────────────────────────────────────────────────────
def make_npc_gaia():
    S = 30
    img = Image.new('RGBA', (S, S), (0,0,0,0))
    d = ImageDraw.Draw(img)
    shadow(d, S)
    # Wide green robes
    d.ellipse([3, 13, 27, 27], fill=(25, 118, 50))
    d.ellipse([6, 15, 24, 25], fill=(38, 152, 65))
    # Staff
    d.rectangle([23, 7, 26, 23], fill=(148, 98, 48))
    d.ellipse([20, 3, 29, 12], fill=(80, 210, 90))
    d.ellipse([22, 5, 27, 10], fill=(160, 255, 160, 200))
    # Head
    d.ellipse([9, 3, 21, 14], fill=(220, 175, 135))
    # Silver hair
    d.ellipse([7, 0, 23, 10], fill=(208, 212, 222))
    d.ellipse([8, 1, 22, 9],  fill=(228, 232, 240))
    # Eyes (glowing green)
    d.ellipse([11, 6, 14, 9], fill=(50, 235, 95))
    d.ellipse([16, 6, 19, 9], fill=(50, 235, 95))
    # Robe symbol
    d.ellipse([12, 17, 18, 23], fill=(80, 255, 80, 200))
    return img

# ── NPC Asha ───────────────────────────────────────────────────────────────────
def make_npc_asha():
    S = 30
    img = Image.new('RGBA', (S, S), (0,0,0,0))
    d = ImageDraw.Draw(img)
    shadow(d, S)
    # Armour body
    d.ellipse([4, 12, 26, 26], fill=(138, 28, 28))
    d.ellipse([8, 14, 22, 24], fill=(175, 42, 42))
    # Arms
    d.ellipse([1, 13, 8, 22], fill=(118, 22, 22))
    d.ellipse([22, 13, 29, 22], fill=(118, 22, 22))
    # Gun (right)
    d.rectangle([24, 12, 30, 15], fill=(78, 82, 90))
    # Head
    d.ellipse([9, 3, 21, 14], fill=(200, 155, 120))
    # Short dark hair
    d.ellipse([9, 2, 21, 10], fill=(58, 38, 28))
    # Eyes
    d.ellipse([11, 6, 14, 9], fill=(90, 65, 42))
    d.ellipse([16, 6, 19, 9], fill=(90, 65, 42))
    # Chest triangle detail
    d.polygon([(15,15),(11,21),(19,21)], fill=(205, 55, 55))
    return img

# ── NPC Echo-7 ─────────────────────────────────────────────────────────────────
def make_npc_echo7():
    S = 30
    img = Image.new('RGBA', (S, S), (0,0,0,0))
    d = ImageDraw.Draw(img)
    shadow(d, S)
    # Android body
    d.ellipse([4, 12, 26, 26], fill=(215, 220, 228))
    d.ellipse([8, 14, 22, 24], fill=(238, 242, 248))
    # Arms
    d.ellipse([1, 13, 8, 22], fill=(198, 202, 210))
    d.ellipse([22, 13, 29, 22], fill=(198, 202, 210))
    # Circuit lines
    d.line([(10,17),(20,17)], fill=(0, 200, 222), width=1)
    d.line([(10,20),(20,20)], fill=(0, 200, 222), width=1)
    d.line([(15,14),(15,24)], fill=(0, 200, 222), width=1)
    # Core
    d.ellipse([12, 17, 18, 23], fill=(0, 228, 255, 210))
    # Head
    d.ellipse([8, 3, 22, 15], fill=(212, 218, 226))
    # Cyan eyes
    d.ellipse([10, 6, 14, 10], fill=(0, 238, 255))
    d.ellipse([16, 6, 20, 10], fill=(0, 238, 255))
    d.ellipse([11, 7, 13, 9], fill=(210, 255, 255, 210))
    d.ellipse([17, 7, 19, 9], fill=(210, 255, 255, 210))
    return img

# ── NPC Archivist ──────────────────────────────────────────────────────────────
def make_npc_archivist():
    S = 30
    img = Image.new('RGBA', (S, S), (0,0,0,0))
    d = ImageDraw.Draw(img)
    shadow(d, S)
    # Dark robes
    d.ellipse([3, 11, 27, 27], fill=(58, 18, 98))
    d.ellipse([6, 13, 24, 25], fill=(78, 28, 128))
    # Hood
    d.ellipse([6, 2, 24, 16],  fill=(48, 13, 82))
    d.ellipse([8, 3, 22, 14],  fill=(68, 20, 112))
    # Face shadow
    d.ellipse([10, 5, 20, 13], fill=(28, 8, 48))
    # Glowing purple eyes
    d.ellipse([11, 7, 14, 10], fill=(178, 98, 255))
    d.ellipse([16, 7, 19, 10], fill=(178, 98, 255))
    # Floating book
    d.rectangle([22, 7, 28, 14], fill=(198, 178, 128))
    d.line([(24, 7),(24, 14)], fill=(98, 78, 48), width=1)
    # Robe glyph
    d.ellipse([12, 16, 18, 22], fill=(138, 58, 218, 210))
    return img

# ── NPC Voss ───────────────────────────────────────────────────────────────────
def make_npc_voss():
    S = 30
    img = Image.new('RGBA', (S, S), (0,0,0,0))
    d = ImageDraw.Draw(img)
    shadow(d, S)
    # Heavy body
    d.ellipse([3, 11, 27, 27], fill=(78, 83, 88))
    d.ellipse([7, 13, 23, 25], fill=(98, 103, 108))
    # Shoulder pads
    d.ellipse([0, 10, 10, 20], fill=(68, 73, 78))
    d.ellipse([20, 10, 30, 20], fill=(68, 73, 78))
    # Head helmet
    d.ellipse([8, 3, 22, 15], fill=(73, 78, 83))
    # Red visor
    d.ellipse([10, 5, 20, 12], fill=(178, 28, 28))
    d.ellipse([11, 6, 19, 11], fill=(218, 40, 40, 180))
    # UEC badge
    d.rectangle([12, 16, 18, 22], fill=(178, 28, 28))
    d.line([(15,15),(15,23)], fill=(218, 42, 42), width=1)
    # Scratch marks
    d.line([(5, 14),(8, 17)], fill=(48, 53, 58), width=1)
    return img

# ── UEC Drone ──────────────────────────────────────────────────────────────────
def make_uec_drone():
    S = 24
    img = Image.new('RGBA', (S, S), (0,0,0,0))
    d = ImageDraw.Draw(img)
    shadow(d, S, alpha=55)
    # Rotor discs
    for (x, y) in [(0,0),(17,0),(0,17),(17,17)]:
        d.ellipse([x, y, x+7, y+7], fill=(38, 42, 52))
        d.ellipse([x+1, y+1, x+6, y+6], fill=(68, 73, 82))
    # Main body
    d.ellipse([4, 4, 20, 20], fill=(50, 55, 65))
    d.ellipse([6, 6, 18, 18], fill=(65, 70, 80))
    # Red sensor
    d.ellipse([8, 8, 16, 16], fill=(195, 28, 28))
    d.ellipse([9, 9, 15, 15], fill=(252, 48, 48))
    d.ellipse([10, 10, 14, 14], fill=(255, 148, 148, 220))
    return img

# ── Sentinel Boss ──────────────────────────────────────────────────────────────
def make_sentinel_boss():
    S = 48
    img = Image.new('RGBA', (S, S), (0,0,0,0))
    d = ImageDraw.Draw(img)
    shadow(d, S)
    # Shoulder pauldrons
    d.ellipse([0, 12, 16, 30],  fill=(118, 18, 18))
    d.ellipse([32, 12, 48, 30], fill=(118, 18, 18))
    # Body
    d.ellipse([6, 14, 42, 40], fill=(138, 23, 23))
    d.ellipse([10, 17, 38, 37], fill=(165, 33, 33))
    # Armoured head
    d.ellipse([12, 4, 36, 22], fill=(128, 18, 18))
    d.ellipse([14, 5, 34, 21], fill=(152, 28, 28))
    # Helmet visor (orange)
    d.ellipse([16, 7, 32, 17], fill=(252, 138, 0))
    d.ellipse([17, 8, 31, 16], fill=(255, 178, 48, 210))
    # Glowing core
    d.ellipse([17, 21, 31, 35], fill=(252, 98, 0))
    d.ellipse([19, 23, 29, 33], fill=(255, 158, 0))
    d.ellipse([21, 25, 27, 31], fill=(255, 220, 100, 230))
    # Arm cannons
    d.rectangle([1, 18, 7, 28],  fill=(98, 13, 13))
    d.rectangle([0, 20, 4, 26],  fill=(78, 80, 88))
    d.rectangle([41, 18, 47, 28], fill=(98, 13, 13))
    d.rectangle([44, 20, 48, 26], fill=(78, 80, 88))
    # Armour trim lines
    d.line([(18, 18),(30, 18)], fill=(198, 48, 48), width=1)
    d.line([(18, 38),(30, 38)], fill=(198, 48, 48), width=1)
    return img

# ── Fragment pickup ────────────────────────────────────────────────────────────
def make_fragment():
    S = 20
    img = Image.new('RGBA', (S, S), (0,0,0,0))
    d = ImageDraw.Draw(img)
    cx = S // 2
    # Outer glow
    d.polygon([(cx,1),(cx+7,cx),(cx,S-1),(cx-7,cx)], fill=(178, 48, 252, 100))
    # Crystal
    d.polygon([(cx,2),(cx+5,cx),(cx,S-2),(cx-5,cx)], fill=(158, 38, 238))
    # Inner face
    d.polygon([(cx,4),(cx+3,cx-1),(cx,cx+4),(cx-3,cx-1)], fill=(198, 98, 255))
    # Sparkle centre
    d.ellipse([cx-2, cx-2, cx+2, cx+2], fill=(228, 178, 255))
    d.line([(cx, 3),(cx, 7)],   fill=(255,255,255,200), width=1)
    d.line([(cx-3,cx),(cx+3,cx)], fill=(255,255,255,200), width=1)
    return img

# ── Health pickup ──────────────────────────────────────────────────────────────
def make_health_pickup():
    S = 20
    img = Image.new('RGBA', (S, S), (0,0,0,0))
    d = ImageDraw.Draw(img)
    # Outer glow
    d.ellipse([1, 1, S-1, S-1], fill=(0, 198, 48, 80))
    # Orb
    d.ellipse([2, 2, S-2, S-2], fill=(0, 178, 38))
    d.ellipse([3, 3, S-3, S-3], fill=(0, 208, 58))
    # White cross
    d.rectangle([8, 5, 12, 15], fill=(255, 255, 255))
    d.rectangle([5, 8, 15, 12], fill=(255, 255, 255))
    # Highlight
    d.ellipse([5, 4, 10, 9], fill=(148, 255, 148, 180))
    return img

# ── Run ────────────────────────────────────────────────────────────────────────
print("Generating sprites...")
sprites = {
    "player":        make_player(),
    "npc_gaia":      make_npc_gaia(),
    "npc_asha":      make_npc_asha(),
    "npc_echo7":     make_npc_echo7(),
    "npc_archivist": make_npc_archivist(),
    "npc_voss":      make_npc_voss(),
    "uec_drone":     make_uec_drone(),
    "sentinel_boss": make_sentinel_boss(),
    "fragment":      make_fragment(),
    "health_pickup": make_health_pickup(),
}
for name, img in sprites.items():
    save(img, name)
print(f"\nAll {len(sprites)} sprites saved to {OUT_DIR}/")
