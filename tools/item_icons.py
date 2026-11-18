"""Item and status icons (playtest round 18, user 2026-11-15): one full-colour SVG per item
in data/items.json (consumables and equipment) into data/item_icons/<id>.svg, and one per
battle status in data/battle.json into data/status_icons/<id>.svg. 64 x 64, a dark outline
so they read on the game's dark panels. Plain Python, no other tools needed:

    python tools/item_icons.py

Each new SVG also gets a .svg.import with importer="keep" (the game reads them as text;
test_export_files).
"""
import json
import math
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INK = "#1b1a1f"
W = 3  # outline width

def svg(body):
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="64" height="64">'
            f'<g stroke="{INK}" stroke-width="{W}" stroke-linejoin="round" stroke-linecap="round">{body}</g></svg>\n')

def path(d, fill="none", extra=""):
    return f'<path d="{d}" fill="{fill}" {extra}/>'

def circle(cx, cy, r, fill="none", extra=""):
    return f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{fill}" {extra}/>'

def rect(x, y, w, h, fill, rx=0, extra=""):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{fill}" {extra}/>'

def poly(points, fill, extra=""):
    return f'<polygon points="{" ".join(f"{x:.1f},{y:.1f}" for x, y in points)}" fill="{fill}" {extra}/>'

def star(cx, cy, r1, r2, n=5, rot=-90):
    pts = []
    for i in range(n * 2):
        r = r1 if i % 2 == 0 else r2
        a = math.radians(rot + i * 180 / n)
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts

# --- consumables ------------------------------------------------------------------

def leaf5(fill="#4caf50", vein="#2e7d32"):
    # a five-lobed (palmate) leaf on a short stem: each lobe a rounded point between notches
    cx, cy = 32, 30
    d = ""
    for i in range(5):
        a0 = math.radians(-90 + i * 72 - 36)  # the notch before this lobe
        a1 = math.radians(-90 + i * 72)       # the lobe's tip
        a2 = math.radians(-90 + i * 72 + 36)  # the notch after
        n0 = (cx + 9 * math.cos(a0), cy + 9 * math.sin(a0))
        tip = (cx + 27 * math.cos(a1), cy + 27 * math.sin(a1))
        n2 = (cx + 9 * math.cos(a2), cy + 9 * math.sin(a2))
        side = 0.55
        c1 = (cx + 24 * math.cos(a1 - side), cy + 24 * math.sin(a1 - side))
        c2 = (cx + 24 * math.cos(a1 + side), cy + 24 * math.sin(a1 + side))
        if i == 0:
            d += f"M{n0[0]:.1f} {n0[1]:.1f} "
        d += f"Q{c1[0]:.1f} {c1[1]:.1f} {tip[0]:.1f} {tip[1]:.1f} Q{c2[0]:.1f} {c2[1]:.1f} {n2[0]:.1f} {n2[1]:.1f} "
    body = path("M32 40 L30 60", extra=f'stroke="{vein}" stroke-width="4"')
    body += path(d + "Z", fill)
    for i in range(5):
        a = math.radians(-90 + i * 72)
        body += path(f"M32 30 L{32 + 19 * math.cos(a):.1f} {30 + 19 * math.sin(a):.1f}", extra=f'stroke="{vein}" stroke-width="2"')
    return svg(body)

def flask(liquid, glass="#cfe3ea", neck=True, round_body=True, cork="#a0703c", label=None):
    # a round potion bottle with a cork; the liquid fills the lower part
    body = ""
    if round_body:
        body += circle(32, 40, 18, glass)
        body += path("M15.5 42 A18 18 0 0 0 48.5 42 Z", liquid, 'stroke="none"')
        body += circle(32, 40, 18, "none")
    else:
        body += rect(17, 24, 30, 34, glass, 6)
        body += rect(17, 38, 30, 20, liquid, 6, 'stroke="none"')
        body += rect(17, 24, 30, 34, "none", 6)
    if neck:
        body += rect(26, 10, 12, 16, glass, 2)
        body += rect(24, 4, 16, 9, cork, 3)
    body += path("M24 34 Q22 40 25 46", extra='stroke="#ffffff" stroke-width="3" opacity="0.7"')
    if label:
        body += label
    return svg(body)

def jar(fill, lid="#8d6e63", mark=None):
    body = rect(14, 22, 36, 36, fill, 8)
    body += rect(12, 12, 40, 12, lid, 4)
    if mark:
        body += mark
    return svg(body)

def dropper():
    body = rect(26, 4, 12, 14, "#455a64", 5)
    body += path("M24 18 L40 18 L36 48 L28 48 Z", "#90caf9")
    body += path("M32 52 Q26 60 32 62 Q38 60 32 52 Z", "#42a5f5")
    return svg(body)

def sprig(fill="#9c6ade"):
    body = path("M32 60 Q30 36 34 8", extra='stroke="#5d4037" stroke-width="4"')
    for y, side in [(16, 1), (24, -1), (32, 1), (40, -1), (48, 1)]:
        x2 = 32 + side * 16
        body += path(f"M33 {y} Q{x2} {y - 10} {x2} {y + 2} Q{32 + side * 6} {y + 6} 33 {y} Z", fill)
    return svg(body)

def crystals():
    body = rect(14, 30, 36, 28, "#b0bec5", 6)
    body += poly([(20, 32), (26, 14), (32, 32)], "#eceff1")
    body += poly([(30, 32), (36, 10), (42, 32)], "#ffffff")
    body += poly([(38, 32), (44, 20), (48, 32)], "#e0e0e0")
    return svg(body)

# --- equipment --------------------------------------------------------------------

def blade(length, width, metal="#cfd8dc", hilt="#795548", guard="#8d6e63", glow=None):
    # a diagonal blade from bottom-left hilt to top-right point
    body = ""
    if glow:
        body += circle(36, 28, 24, glow, 'stroke="none" opacity="0.35"')
    tip = 10
    base = 10 + length
    body += f'<g transform="rotate(45 32 32)">'
    body += path(f"M{32 - width} {base} L{32 - width} {tip + 8} L32 {tip} L{32 + width} {tip + 8} L{32 + width} {base} Z", metal)
    body += rect(32 - width - 7, base, width * 2 + 14, 5, guard, 2)
    body += rect(29, base + 5, 6, 12, hilt, 2)
    body += circle(32, base + 19, 3.5, guard)
    body += "</g>"
    return svg(body)

def club(head="#8d6e63", spikes=False, metal=False):
    body = '<g transform="rotate(40 32 32)">'
    body += rect(28, 30, 8, 30, "#6d4c41", 3)
    if metal:
        body += circle(32, 20, 13, "#b0bec5")
        if spikes:
            for i in range(8):
                a = math.radians(i * 45)
                x, y = 32 + 13 * math.cos(a), 20 + 13 * math.sin(a)
                body += poly([(x + 4 * math.cos(a + 1.6), y + 4 * math.sin(a + 1.6)), (32 + 21 * math.cos(a), 20 + 21 * math.sin(a)), (x + 4 * math.cos(a - 1.6), y + 4 * math.sin(a - 1.6))], "#90a4ae")
            body += circle(32, 20, 13, "#b0bec5")
    else:
        body += path("M24 34 Q20 10 32 4 Q44 10 40 34 Z", head)
        body += path("M28 14 L30 18 M36 20 L34 24", extra='stroke-width="2"')
    body += "</g>"
    return svg(body)

def bow(long=False, wood="#8d6e63", string="#eeeeee", bolt=False):
    top, bot = (8, 56) if long else (12, 52)
    body = path(f"M22 {top} Q50 32 22 {bot}", extra=f'stroke="{INK}" stroke-width="9"')
    body += path(f"M22 {top} Q50 32 22 {bot}", extra=f'stroke="{wood}" stroke-width="5"')
    body += path(f"M22 {top} L22 {bot}", extra=f'stroke="{string}" stroke-width="2"')
    body += path("M14 32 L54 32", extra='stroke-width="3"')
    body += poly([(54, 32), (46, 27), (46, 37)], "#b0bec5")
    body += path("M14 32 L10 28 M14 32 L10 36", extra='stroke="#e57373" stroke-width="3"')
    if bolt:
        body += poly([(44, 6), (36, 18), (42, 18), (34, 30), (50, 14), (43, 14), (50, 6)], "#ffeb3b")
    return svg(body)

def armor(metal, trim, scales=False):
    body = path("M14 14 L24 8 Q32 14 40 8 L50 14 L54 28 L46 30 L46 56 L18 56 L18 30 L10 28 Z", metal)
    body += path("M24 8 Q32 18 40 8", extra=f'stroke="{trim}" stroke-width="3"')
    body += path("M32 20 L32 52", extra=f'stroke="{trim}" stroke-width="2"')
    if scales:
        for y in (26, 34, 42, 50):
            for x in (22, 30, 38):
                body += path(f"M{x} {y} q4 5 8 0", extra='stroke-width="2"')
    return svg(body)

def necklace():
    body = path("M14 10 Q32 52 50 10", extra='stroke="#ffd54f" stroke-width="4"')
    body += poly([(32, 36), (40, 46), (32, 58), (24, 46)], "#4fc3f7")
    return svg(body)

def ring():
    body = circle(32, 38, 16, "none", 'stroke="#ffca28" stroke-width="7"')
    body += circle(32, 38, 16, "none", 'stroke-width="1.5"')
    body += poly([(32, 8), (40, 16), (32, 26), (24, 16)], "#e53935")
    return svg(body)

def earring():
    body = circle(32, 12, 6, "none", 'stroke="#ffca28" stroke-width="4"')
    body += path("M32 18 L32 28", extra='stroke="#ffca28" stroke-width="3"')
    body += path("M32 28 Q46 44 32 58 Q18 44 32 28 Z", "#ab47bc")
    return svg(body)

def bracelet():
    body = '<ellipse cx="32" cy="34" rx="22" ry="14" fill="none" stroke="#bdbdbd" stroke-width="9"/>'
    body += '<ellipse cx="32" cy="34" rx="22" ry="14" fill="none" stroke-width="1.5"/>'
    for x in (16, 32, 48):
        body += circle(x, 34 + (10 if x == 32 else 4), 4, "#26a69a")
    return svg(body)

def crown():
    body = path("M10 50 L10 20 L22 34 L32 12 L42 34 L54 20 L54 50 Z", "#ffca28")
    body += rect(10, 46, 44, 10, "#ffb300", 2)
    for x, c in [(20, "#e53935"), (32, "#1e88e5"), (44, "#43a047")]:
        body += circle(x, 51, 3, c)
    return svg(body)

# --- statuses ---------------------------------------------------------------------

def drop(fill, mark=""):
    return svg(path("M32 6 Q50 30 50 42 A18 18 0 0 1 14 42 Q14 30 32 6 Z", fill) + mark)

def flame(outer="#ff7043", inner="#ffca28"):
    body = path("M32 4 Q52 24 48 42 A16 16 0 0 1 16 42 Q12 28 24 18 Q24 30 30 30 Q28 16 32 4 Z", outer)
    body += path("M32 30 Q42 40 40 48 A8 8 0 0 1 24 48 Q24 40 32 30 Z", inner)
    return svg(body)

def snowflake(color="#81d4fa"):
    body = ""
    for i in range(3):
        a = math.radians(90 + i * 60)
        dx, dy = 26 * math.cos(a), 26 * math.sin(a)
        body += path(f"M{32 - dx:.1f} {32 - dy:.1f} L{32 + dx:.1f} {32 + dy:.1f}", extra=f'stroke="{INK}" stroke-width="9"')
    for i in range(3):
        a = math.radians(90 + i * 60)
        dx, dy = 26 * math.cos(a), 26 * math.sin(a)
        body += path(f"M{32 - dx:.1f} {32 - dy:.1f} L{32 + dx:.1f} {32 + dy:.1f}", extra=f'stroke="{color}" stroke-width="5"')
    body += circle(32, 32, 6, "#e1f5fe")
    return svg(body)

def bolt(fill="#ffeb3b"):
    return svg(poly([(38, 4), (16, 36), (30, 36), (24, 60), (48, 26), (34, 26), (42, 4)], fill))

def stone():
    body = poly([(12, 40), (18, 18), (36, 10), (52, 22), (54, 46), (36, 56), (18, 54)], "#9e9e9e")
    body += path("M22 26 L32 34 L28 44 M40 20 L42 32", extra='stroke-width="2"')
    return svg(body)

def zz():
    # "Zz" drawn as strokes (the game's SVG renderer draws no text)
    def z(x, y, w, h, color, width):
        d = f"M{x} {y} L{x + w} {y} L{x} {y + h} L{x + w} {y + h}"
        return path(d, extra=f'stroke="{INK}" stroke-width="{width + 4}"') + path(d, extra=f'stroke="{color}" stroke-width="{width}"')
    return svg(z(8, 26, 26, 28, "#b39ddb", 6) + z(38, 8, 18, 18, "#d1c4e9", 4))

def heart(fill="#f06292", mark=""):
    return svg(path("M32 56 L10 32 A11 11 0 0 1 32 16 A11 11 0 0 1 54 32 Z", fill) + mark)

def eye(cross=True):
    body = path("M4 32 Q32 6 60 32 Q32 58 4 32 Z", "#eceff1")
    body += circle(32, 32, 10, "#5c6bc0")
    body += circle(32, 32, 4, INK)
    if cross:
        body += path("M10 54 L54 10", extra=f'stroke="{INK}" stroke-width="9"')
        body += path("M10 54 L54 10", extra='stroke="#e53935" stroke-width="5"')
    return svg(body)

def bubble_cross():
    body = path("M8 12 L56 12 L56 42 L30 42 L18 54 L20 42 L8 42 Z", "#eceff1")
    body += path("M10 54 L54 6", extra=f'stroke="{INK}" stroke-width="9"')
    body += path("M10 54 L54 6", extra='stroke="#e53935" stroke-width="5"')
    return svg(body)

def broken_star():
    body = poly(star(32, 32, 26, 11), "#ce93d8")
    body += path("M20 10 L34 30 L26 34 L44 56", extra=f'stroke="{INK}" stroke-width="4"')
    return svg(body)

def ghost():
    body = path("M14 58 L14 28 A18 18 0 0 1 50 28 L50 58 L44 52 L38 58 L32 52 L26 58 L20 52 Z", "#eceff1")
    body += '<ellipse cx="25" cy="28" rx="4" ry="6" fill="' + INK + '"/>'
    body += '<ellipse cx="39" cy="28" rx="4" ry="6" fill="' + INK + '"/>'
    body += '<ellipse cx="32" cy="42" rx="5" ry="4" fill="' + INK + '"/>'
    return svg(body)

def shield(fill="#78909c", mark=""):
    return svg(path("M32 4 L54 12 Q54 44 32 60 Q10 44 10 12 Z", fill) + mark)

def crack():
    return path("M30 8 L36 22 L28 32 L36 44 L30 58", extra=f'stroke="{INK}" stroke-width="4"')

def orb(fill="#7e57c2", mark=""):
    body = circle(32, 32, 24, fill)
    body += path("M20 22 Q24 14 32 12", extra='stroke="#ffffff" stroke-width="3" opacity="0.6"')
    return svg(body + mark)

def arrow(up, color):
    if up:
        pts = [(44, 30), (56, 44), (49, 44), (49, 60), (39, 60), (39, 44), (32, 44)]
    else:
        pts = [(44, 60), (56, 46), (49, 46), (49, 30), (39, 30), (39, 46), (32, 46)]
    return poly(pts, color)

UP, DOWN = "#66bb6a", "#ef5350"

def fist(mark):
    body = rect(8, 18, 30, 26, "#ffcc80", 8)
    body += path("M15 18 L15 30 M22 18 L22 30 M29 18 L29 30", extra='stroke-width="2"')
    body += rect(12, 42, 22, 14, "#ffb74d", 3)
    return svg(body + mark)

def boot(mark):
    body = path("M10 8 L28 8 L28 36 L40 42 Q44 48 40 54 L10 54 Z", "#a1887f")
    body += rect(10, 48, 32, 8, "#5d4037", 3)
    return svg(body + mark)

def wings():
    body = path("M32 40 Q14 40 6 18 Q20 22 32 30 Z", "#e0f7fa")
    body += path("M32 40 Q50 40 58 18 Q44 22 32 30 Z", "#e0f7fa")
    for x in (14, 22, 42, 50):
        body += path(f"M{x} 54 L{x + 6} 46", extra='stroke="#4dd0e1" stroke-width="3"')
    return svg(body)

def regen():
    return heart("#ef5350", rect(27, 22, 10, 26, "#ffffff", 2, 'stroke-width="2"') + rect(19, 30, 26, 10, "#ffffff", 2, 'stroke-width="2"'))

def ward():
    body = circle(32, 32, 26, "none", 'stroke="#4fc3f7" stroke-width="5"')
    body += circle(32, 32, 26, "none", 'stroke-width="1.5"')
    body += poly(star(32, 32, 20, 8, 6), "#b3e5fc")
    return svg(body)

def scroll(seal):
    """A rolled scroll (playtest notes, 2026-11-16): one shape, the paper muted, the seal a colour per scroll."""
    paper, edge = "#d9cfb4", "#b8ab8a"
    return svg(rect(14, 14, 36, 36, paper, 3)
            + rect(10, 10, 44, 8, edge, 4) + rect(10, 46, 44, 8, edge, 4)
            + path("M20 26 H44 M20 32 H40 M20 38 H36", extra='stroke-width="2" opacity="0.45"')
            + path("M40 40 L36 58 L41 54 L44 59 L46 41", seal, 'stroke-width="2"')
            + circle(42, 40, 7, seal, 'stroke-width="2.5"'))

ITEMS = {
    "herb": leaf5(),
    "revive": flask("#e91e63"),
    "antidote": flask("#66bb6a", round_body=False),
    "burn_salve": jar("#ffab91", mark=path("M32 30 Q40 40 36 48 A6 6 0 0 1 28 48 Q26 40 32 30 Z", "#ff7043", 'stroke-width="2"')),
    "thaw_tonic": flask("#81d4fa", round_body=False),
    "insulator": jar("#fff59d", mark=poly([(34, 28), (26, 42), (32, 42), (28, 54), (40, 38), (34, 38), (38, 28)], "#ffeb3b", 'stroke-width="2"')),
    "soft_oil": flask("#d4a24c", cork="#6d4c41"),
    "salts": crystals(),
    "eye_drops": dropper(),
    "echo_herb": sprig(),
    "scroll_invisibility": scroll("#7b8fb0"),
    "scroll_decoy": scroll("#b0894f"),
    "scroll_teleport": scroll("#8a6fae"),
    "dagger": blade(22, 4),
    "sword": blade(32, 5),
    "club": club(),
    "mace": club(spikes=True, metal=True),
    "bow": bow(),
    "longbow": bow(long=True, wood="#6d4c41"),
    "bronze": armor("#cd8b4f", "#8d5a2b"),
    "iron": armor("#9e9e9e", "#616161"),
    "steel": armor("#cfd8dc", "#78909c"),
    "necklace": necklace(),
    "ring": ring(),
    "earring": earring(),
    "bracelet": bracelet(),
    "sunblade": blade(34, 6, metal="#fff176", hilt="#ff8f00", guard="#ffb300", glow="#ffeb3b"),
    "stormbow": bow(long=True, wood="#455a64", string="#b3e5fc", bolt=True),
    "dragonscale": armor("#43a047", "#1b5e20", scales=True),
    "crown": crown(),
}

STATUSES = {
    "poison": drop("#8bc34a", circle(26, 40, 3, INK) + circle(38, 40, 3, INK) + path("M26 50 Q32 46 38 50", extra='stroke-width="2"')),
    "burn": flame(),
    "freeze": snowflake(),
    "shock": bolt(),
    "petrify": stone(),
    "sleep": zz(),
    "charm": heart(),
    "blind": eye(),
    "silence": bubble_cross(),
    "dispelled": broken_star(),
    "fear": ghost(),
    "weak_physical": shield("#90a4ae", crack()),
    "weak_magic": orb("#9575cd", crack()),
    "str_down": fist(arrow(False, DOWN)),
    "agi_down": boot(arrow(False, DOWN)),
    "haste": wings(),
    "protect": shield("#42a5f5"),
    "regen": regen(),
    "pdef_up": shield("#78909c", arrow(True, UP)),
    "agi_up": boot(arrow(True, UP)),
    "mdef_up": orb("#7e57c2", arrow(True, UP)),
    "ward": ward(),
}

IMPORT = '[remap]\n\nimporter="keep"\n'

def write(folder, icons, expected):
    out = os.path.join(ROOT, "data", folder)
    os.makedirs(out, exist_ok=True)
    missing = [k for k in expected if k not in icons]
    if missing:
        raise SystemExit(f"{folder}: no icon drawn for {missing}")
    for k, text in icons.items():
        with open(os.path.join(out, k + ".svg"), "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        imp = os.path.join(out, k + ".svg.import")
        if not os.path.exists(imp):
            with open(imp, "w", encoding="utf-8", newline="\n") as f:
                f.write(IMPORT)
    print(f"{folder}: {len(icons)} icons")

if __name__ == "__main__":
    items = json.load(open(os.path.join(ROOT, "data", "items.json"), encoding="utf-8"))
    battle = json.load(open(os.path.join(ROOT, "data", "battle.json"), encoding="utf-8"))
    write("item_icons", ITEMS, list(items["consumables"]) + list(items["items"]))
    statuses = battle.get("statuses") or battle.get("status")
    write("status_icons", STATUSES, list(statuses))
