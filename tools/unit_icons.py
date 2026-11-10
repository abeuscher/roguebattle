"""Draw unit icons from data/units.json.

Usage: python tools/unit_icons.py [--sheet out.svg]

Every class gets data/unit_icons/<class>.svg, built from four sheet columns:
  Icon base   silhouette for the line's origin (human, elf, wolf, dragon, rat...)
  Icon hand   stage 2 symbol, lower right (sword, bow, ember...)
  Icon head   stage 3 symbol, on the head (kettle helm, hood, horns...)
  Icon crest  stage 4 glyph in the top-right badge (shield, flame, crown...)
A unit repeats the symbols of the stages before it, so a stage 4 icon shows all three.
Frame color comes from "Alignment lean", frame style from "Size" (Large = double),
badge color from "Element". Unknown part names are reported, never guessed (exit 1).

Colors: INK and PAPER are swapped at load time for dark UI (ui/unit_icons.gd), so
they must stay the only two uses of these exact hex values.
"""
import json
import math
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "data"
OUT = DATA / "unit_icons"

INK = "#1d1b1a"
PAPER = "#f4efe4"
W = "#fff"
ALIGN = {"Any": "#8a8580", "Holy": "#c9a227", "Evil": "#a61e4d", "Neutral": "#2f9e44"}
ELEMENT = {None: "#3b3b3b", "Fire": "#d9480f", "Lightning": "#d19a00", "Earth": "#7a5c2e",
           "Wind": "#2f9e8f", "Holy": "#c9a227", "Dark": "#5f3dc4", "Ice": "#3b7fc4", "Water": "#1c6fa8"}
CREST = (51, 13)


# ---------- helpers ----------
def st(d, w):
    """A stroked path in part ink; widened in the halo copy."""
    return f'<path d="{d}" fill="none" stroke="@" stroke-width="{w}" stroke-linecap="round" stroke-linejoin="round"/>'


def overlay(ink, detail=""):
    """Part drawn over the figure: a paper-colored halo first so it reads as a separate object."""
    halo = re.sub(r'stroke-width="([\d.]+)"', lambda m: f'stroke-width="{float(m.group(1)) + 3.5:g}"', ink)
    halo = halo.replace('stroke="@"', f'stroke="{PAPER}"')
    return f'<g fill="{PAPER}" stroke="{PAPER}" stroke-width="3.5" stroke-linejoin="round">{halo}</g>' + plain(ink, detail)


def plain(ink, detail=""):
    return f'<g fill="{INK}">{ink.replace(chr(34) + "@" + chr(34), chr(34) + INK + chr(34))}</g>{detail}'


def cut(svg):
    """Detail cut out of the ink in paper color."""
    return svg.replace("#P", PAPER)


def eye(x, y, r=1.8):
    return f'<circle cx="{x}" cy="{y}" r="{r}" fill="{PAPER}"/>'


def star_pts(cx, cy, r1, r2, n=5, rot=-90):
    pts = []
    for i in range(n * 2):
        a = math.radians(rot) + i * math.pi / n
        r = r1 if i % 2 == 0 else r2
        pts.append(f"{cx + r * math.cos(a):.1f},{cy + r * math.sin(a):.1f}")
    return " ".join(pts)


BODY = '<path d="M12 58 Q12 38 28 37 Q44 38 44 58 Z"/>'
HEAD = '<circle cx="28" cy="23" r="9"/>'

# ---------- bases: (svg, head anchor offset for the head slot) ----------
def _human():
    return plain(BODY + HEAD)


BASES = {
    "human": (_human, (0, 0)),
    "elf": (lambda: plain('<path d="M19 22 L11 15 L21 27Z M37 22 L45 15 L35 27Z"/>' + BODY + HEAD), (0, 0)),
    "troll": (lambda: plain('<path d="M7 58 Q7 36 28 35 Q49 36 49 58Z"/><ellipse cx="28" cy="24" rx="11" ry="9.5"/>'
                            '<path d="M19 23 L9 31 L20 30Z"/>',
                            cut('<path d="M22 31 L23.5 26.5 L25 31Z M31 31 L32.5 26.5 L34 31Z" fill="#P"/>') + eye(24, 21, 1.5)), (0, 0)),
    "gnome": (lambda: plain('<path d="M14 58 Q14 42 28 41 Q42 42 42 58Z"/>')
              + overlay('<circle cx="28" cy="27" r="8"/><path d="M19 29 Q28 52 37 29Z"/><ellipse cx="22" cy="29" rx="3.5" ry="2.5"/>',
                        eye(25, 25, 1.3) + eye(31, 25, 1.3) + f'<path d="M20 31.5 Q28 35 36 31.5" stroke="{PAPER}" stroke-width="1.4" fill="none"/>'), (0, 4)),
    "goblin": (lambda: plain('<path d="M15 58 Q15 41 28 40 Q41 41 41 58Z"/><circle cx="28" cy="27" r="8.5"/>'
                             '<path d="M21 25 L5 19 L20 31Z M35 25 L48 19 L36 31Z"/>',
                             eye(24.5, 26, 1.6) + eye(31.5, 26, 1.6)), (0, 4)),
    "wisp": (lambda: plain('<path d="M13 58 L13 30 Q13 11 28 11 Q43 11 43 30 L43 58 L38 52 L33 58 L28 52 L23 58 L18 52Z"/>',
                           cut('<ellipse cx="23" cy="27" rx="2.6" ry="3.6" fill="#P"/><ellipse cx="33" cy="27" rx="2.6" ry="3.6" fill="#P"/>'
                               '<ellipse cx="28" cy="38" rx="3" ry="4" fill="#P"/>')), (0, -3)),
    "tadpole": (lambda: plain('<circle cx="22" cy="32" r="13"/>'
                              '<path d="M33 37 Q44 40 42 48 Q40 55 50 58 Q36 60 34 50 Q33 44 29 42Z"/>',
                              eye(17, 29, 2.4) + eye(26, 28, 2.4)), (-6, 8)),
    "centaur": (lambda: plain('<path d="M6 46 Q6 38 16 38 H40 Q48 38 49 44 L52 50 L49 51 L46 47 V58 H41 V50 H18 V58 H13 V50 Q6 50 6 46Z"/>')
                + overlay('<path d="M11 41 Q11 28 20 27 Q29 28 29 41Z"/><circle cx="20" cy="18" r="7"/>'), (-8, -5)),
    "angel": (lambda: plain('<path d="M14 44 Q1 32 5 12 Q12 26 22 33Z M42 44 Q55 32 51 12 Q44 26 34 33Z"/>')
              + overlay(BODY + HEAD), (0, 0)),
    "imp": (lambda: plain('<path d="M16 42 Q2 40 2 20 L8 26 L9 19 L14 26 L16 20 L21 32Z M40 42 Q54 40 54 20 L48 26 L47 19 L42 26 L40 20 L35 32Z"/>')
            + overlay(BODY + HEAD + '<path d="M22 15 L20 8 L25 14Z M34 15 L36 8 L31 14Z"/>'), (0, 0)),
    "eaglerider": (lambda: plain('<path d="M28 45 Q36 24 55 19 Q51 25 53.5 27 Q47 29 49 33 Q43 35 44 45Z"/>'
                                 '<path d="M3 45 Q4 38 11 38 Q16 38 19 42 L46 44 Q54 44 60 50 Q52 52 46 56 H18 Q12 56 10 51 L6 51 L3 48Z"/>', eye(10, 42.5, 1.4))
                   + overlay('<path d="M18 47 Q18 35 27 34 Q36 35 36 47Z"/><circle cx="27" cy="25" r="6.5"/>'), (-1, 0)),
    "mermaid": (lambda: plain(HEAD + '<path d="M15 44 Q15 33 28 32 Q41 33 41 44 Q41 50 36 53 Q44 54 50 49 L55 42 L55 51 L61 55 L52 56 Q44 60 30 58 Q15 56 15 44Z"/>',
                              f'<path d="M20 49 Q28 52 37 49" stroke="{PAPER}" stroke-width="1.3" fill="none"/>'), (0, 0)),
    "sprite": (lambda: plain('<ellipse cx="13" cy="28" rx="10" ry="6" transform="rotate(-30 13 28)"/><ellipse cx="43" cy="28" rx="10" ry="6" transform="rotate(30 43 28)"/>'
                             '<ellipse cx="15" cy="44" rx="7" ry="4" transform="rotate(25 15 44)"/><ellipse cx="41" cy="44" rx="7" ry="4" transform="rotate(-25 41 44)"/>')
               + overlay('<path d="M19 58 Q19 42 28 41 Q37 42 37 58Z"/><circle cx="28" cy="30" r="7"/>'), (0, 6)),
    "gustling": (lambda: plain('<circle cx="28" cy="21" r="8"/>'
                               '<path d="M13 37 Q13 30 28 30 Q43 30 43 37 Q43 47 31 49 Q24 51 27 58 Q16 54 21 46 Q13 43 13 37Z"/>',
                               f'<path d="M18 38 Q28 42 38 37" fill="none" stroke="{PAPER}" stroke-width="1.6" stroke-linecap="round"/>'), (0, -2)),
    # ----- Large -----
    "dragon": (lambda: plain('<path d="M43 58 Q48 42 38 31 L41 28 L36 27 L38 23 L33 24 Q29 19 21 21 L13 22 Q7 23 5 27 L7 29 L4 31 L18 33 L8 37 L10 41 L24 40 Q29 47 27 58Z"/>'
                             '<path d="M44 52 L50 49 L45 46 L49 42 L43 41 L46 36 L41 36Z"/>', eye(25, 26) + eye(8, 26, 1)), (-2, 0)),
    "wolf": (lambda: plain('<path d="M44 58 Q45 42 41 33 L40 14 L33 23 Q28 22 24 26 L20 30 L7 34 L6 38 L10 41 L23 42 Q27 50 23 58Z"/>', eye(27, 30)), (2, 1)),
    "cat": (lambda: plain('<path d="M12 34 L14 15 L23 23 Q27 21 31 23 L40 15 L42 34 Q42 48 27 50 Q12 48 12 34Z"/><path d="M8 58 Q10 46 27 46 Q44 46 46 58Z"/>',
                          cut('<path d="M18 32 Q21 29 24 32 Q21 35 18 32Z M30 32 Q33 29 36 32 Q33 35 30 32Z" fill="#P"/>')), (-1, 6)),
    "bird": (lambda: plain('<path d="M44 58 L46 50 L41 49 L44 43 L38 41 L40 34 Q40 24 33 19 L40 13 L31 15 L35 9 L27 14 Q18 14 15 21 L8 22 Q4 24 5 29 Q6 33 9 34 L9 29 L14 29 Q14 37 22 42 Q26 49 23 58Z"/>',
                           cut('<path d="M5 27 Q7 24 11 25 L9 29Z" fill="#P"/>') + eye(25, 22)
                           + f'<path d="M21 19 L30 18" stroke="{PAPER}" stroke-width="1.4"/>'), (-1, -4)),
    "squid": (lambda: plain('<ellipse cx="27" cy="25" rx="14" ry="15"/>'
                            + "".join(st(f"M{x} 36 Q{x + w} 47 {x} 58", 4) for x, w in ((17, -5), (23, 4), (31, -4), (37, 5))),
                            eye(21, 27, 2.2) + eye(33, 27, 2.2)), (-1, -2)),
    "goat": (lambda: plain('<path d="M44 58 Q45 42 39 34 L33 22 Q28 20 24 24 L12 38 Q10 42 14 44 L22 42 Q26 50 23 58Z"/><path d="M15 44 L14 51 L19 45Z"/>')
             + overlay('<path d="M33 24 Q38 12 46 16 Q50 22 44 27 Q42 21 37 23Z"/>', eye(28, 29)), (1, 0)),
    "bison": (lambda: plain('<path d="M14 26 Q6 24 7 14 Q10 22 18 22Z M40 26 Q48 24 47 14 Q44 22 36 22Z"/><path d="M15 24 Q27 16 39 24 L37 40 Q27 48 17 40Z"/>'
                            '<path d="M4 58 Q6 40 18 38 H36 Q48 40 50 58Z"/>', eye(21.5, 30, 1.6) + eye(32.5, 30, 1.6)), (-1, 2)),
    "lion": (lambda: plain(f'<polygon points="{star_pts(27, 31, 19, 13, 12)}"/>')
             + f'<circle cx="27" cy="31" r="10.5" fill="{PAPER}"/>'
             + plain('<circle cx="27" cy="31" r="8.5"/><path d="M8 58 Q10 48 27 48 Q44 48 46 58Z"/>', eye(23.5, 29.5, 1.5) + eye(30.5, 29.5, 1.5)), (-1, 6)),
    "golem": (lambda: plain('<rect x="19" y="12" width="17" height="15" rx="2"/><path d="M6 58 L8 32 L18 29 H37 L47 32 L49 58Z"/>',
                            cut('<rect x="22" y="18" width="4" height="3" fill="#P"/><rect x="29" y="18" width="4" height="3" fill="#P"/>')), (0, -4)),
    "yeti": (lambda: plain('<path d="M5 58 Q5 34 17 30 Q16 15 27 15 Q38 15 37 30 Q49 34 49 58Z"/><path d="M17 18 L20 11 L23 16 L27 9 L31 16 L34 11 L37 18Z"/>',
                           cut('<ellipse cx="27" cy="27" rx="6" ry="5" fill="#P"/>')
                           + f'<circle cx="25" cy="26" r="1.2" fill="{INK}"/><circle cx="29" cy="26" r="1.2" fill="{INK}"/>'
                           + f'<path d="M24.5 29.5 Q27 31 29.5 29.5" stroke="{INK}" stroke-width="1" fill="none"/>'), (-1, -6)),
    "lizard": (lambda: plain('<path d="M3 40 Q5 33 14 32 L30 31 Q40 29 46 35 Q52 41 60 38 Q56 48 44 45 L43 52 H37 L37 46 H21 L21 52 H15 V46 Q6 46 3 40Z"/>',
                             eye(11, 36, 1.5)), (-17, 15)),
}

# ---------- tiny bases: two figures, a third joins with head "pack" ----------
def _rat(x, y, s):
    return (f'<g transform="translate({x} {y}) scale({s})">'
            '<path d="M2 18 Q2 6 16 6 Q26 6 28 14 L34 16 L28 19 Q24 22 14 22 Q4 22 2 18Z"/><circle cx="19" cy="6" r="3.5"/>'
            + st("M3 17 Q-6 16 -6 8", 2) + f'</g>')


def _bat(x, y, s):
    return (f'<g transform="translate({x} {y}) scale({s})">'
            '<path d="M16 8 L13 2 L16 5 L19 5 L22 2 L20 8 Q28 4 36 8 Q32 10 31 15 Q27 11 24 15 Q21 12 18 18 Q15 12 12 15 Q9 11 5 15 Q4 10 0 8 Q8 4 16 8Z"/></g>')


TINY = {
    "rat": (lambda third: plain((_rat(25, 2, 0.75) if third else "") + _rat(14, 22, 0.9) + _rat(6, 40, 0.9))),
    "bat": (lambda third: plain((_bat(22, 4, 0.8) if third else "") + _bat(5, 22, 1.0) + _bat(10, 40, 0.9))),
}

# ---------- hand: stage 2, lower right. Each is (ink, detail) ----------
HAND = {
    "sword": ('<g transform="rotate(38 47.5 44)"><path d="M45.5 44 V25 L47.5 20 L49.5 25 V44Z"/><rect x="41" y="43.5" width="13" height="3" rx="1"/>'
              '<rect x="46" y="46" width="3" height="7"/><circle cx="47.5" cy="54.5" r="2"/></g>', ""),
    "lance": ('<g transform="rotate(28 50 42)"><path d="M48.3 59 H51.7 L50 18Z"/><path d="M44 47 Q50 39 56 47Z"/></g>', ""),
    "bow": (st("M45 24 Q62 41 45 58", 3), f'<line x1="45" y1="24" x2="45" y2="58" stroke="{INK}" stroke-width="1.2"/>'),
    "sling": ('<path d="M47.5 59 H51.5 V46 L57.5 32 L54 30.5 L49.5 41 L45 30.5 L41.5 32 L47.5 46Z"/>',
              f'<path d="M43 31.5 Q49.5 38 56 31.5" stroke="{INK}" stroke-width="1.2" fill="none"/><circle cx="49.5" cy="36" r="2" fill="{INK}"/>'),
    "rod": ('<rect x="47" y="30" width="3" height="29" rx="1"/><rect x="42.5" y="27.5" width="12" height="3" rx="1"/>'
            + st("M48.5 27 Q44.5 22 48.5 18.5 Q52.5 22 48.5 27", 2.4), ""),
    "staff": ('<rect x="46.5" y="24" width="3" height="35" rx="1"/><circle cx="48" cy="22" r="4.5"/>', ""),
    "club": ('<path d="M44 58 L48 59 L54 31 Q57 22 51 21 Q45 21 46 30Z"/><path d="M45 27 L41 25 L46 31Z M55 26 L59 23 L55 30Z M52 21 L53 17 L49 21Z"/>', ""),
    "pick": ('<g transform="rotate(25 50 44)"><rect x="48.5" y="27" width="3" height="32" rx="1"/><path d="M39 30 Q50 19 61 30 L60 31.5 Q50 25 40 31.5Z"/></g>', ""),
    "dagger": ('<g transform="rotate(35 48 46)"><path d="M46.5 45 V34 L48 29 L49.5 34 V45Z"/><rect x="43" y="44.5" width="10" height="2.4" rx="1"/>'
               '<rect x="46.8" y="46.5" width="2.4" height="5"/><circle cx="48" cy="53" r="1.7"/></g>', ""),
    "chain": (''.join(f'<ellipse cx="{x}" cy="{y}" rx="3.2" ry="5" fill="none" stroke="@" stroke-width="2.2" transform="rotate(-30 {x} {y})"/>'
                      for x, y in ((44, 28), (48.5, 36), (53, 44))) + '<path d="M51 50 H60 V56 Q55.5 60 51 56Z"/>', ""),
    "lily": ('<ellipse cx="50" cy="51" rx="10" ry="6"/><path d="M50 45 L46 35 L50 39 L54 35Z M50 44 L43 39 L48 45Z M50 44 L57 39 L52 45Z"/>',
             cut('<path d="M50 51 L61 48 L61 53Z" fill="#P"/>')),
    "mushroom": ('<path d="M39 42 Q40 29 50 29 Q60 29 61 42Z"/><path d="M46 42 H54 L55 57 H45Z"/>',
                 eye(45, 36, 1.8) + eye(53, 34, 2.2) + eye(56, 39.5, 1.3)),
    "wing": ('<path d="M38 52 Q44 34 60 30 Q56 36 58 38 Q52 40 54 44 Q47 45 47 52Z"/>', ""),
    "ember": ('<path d="M50 34 Q58 41 56 48 Q55 55 49.5 55 Q44 55 43.5 49.5 Q43 44 48 40 Q47.5 45 50.5 46 Q53 41 50 34Z"/>', ""),
    "barding": ('<path d="M40 38 H58 V46 Q58 54 49 57 Q40 54 40 46Z"/>', f'<path d="M49 42 V52 M44.5 46.5 H53.5" stroke="{PAPER}" stroke-width="1.8"/>'),
    "bone": ('<g transform="rotate(-40 50 46)"><rect x="42" y="44.5" width="16" height="3"/><circle cx="42" cy="44.5" r="2.3"/><circle cx="42" cy="47.5" r="2.3"/>'
             '<circle cx="58" cy="44.5" r="2.3"/><circle cx="58" cy="47.5" r="2.3"/></g>', ""),
    "fang": ('<path d="M42 38 Q50 36 58 38 L52 56 Q50 46 46 44Z"/>', ""),
    "wave": ('<path d="M38 52 Q40 40 50 41 Q58 42 57 48 Q54 44 49 46 Q46 52 54 54 Q58 55 61 51 Q60 59 48 59 Q38 59 38 52Z"/>', ""),
    "shard": ('<path d="M49 25 L56 40 L51 58 L44 43Z"/><path d="M57 43 L61 50 L57 57 L54.5 50Z"/>', ""),
    "claw": (st("M42 30 Q48 42 44 56", 3) + st("M48 28 Q54 40 50 56", 3) + st("M54 28 Q60 40 56 54", 3), ""),
    "shell": ('<path d="M50 57 L39 43 Q41 31 50 31 Q59 31 61 43Z"/>',
              f'<path d="M50 56 L44 35 M50 56 V33 M50 56 L56 35" stroke="{PAPER}" stroke-width="1.4"/>'),
    "anchor": ('<rect x="48.5" y="30" width="3" height="25"/><rect x="44" y="34" width="12" height="2.6" rx="1"/>'
               + st("M41 46 Q42 56 50 56 Q58 56 59 46", 3) + st("M50 23 a3 3 0 1 0 0.1 0", 2.4), ""),
    "gust": (st("M38 36 H52 Q57 36 57 31 Q57 27 53 28", 3) + st("M40 44 H57 Q61 44 60.5 49", 3) + st("M38 52 H51", 3), ""),
    "quake": ('<path d="M38 58 L42 48 L46 52 L50 40 L54 46 L58 33 L61 35 L57 50 L53 46 L49 57Z"/>', ""),
    "rune": ('<path d="M42 30 H58 L60 57 H40Z"/>', f'<path d="M50 34 V53 M50 40 L55 36 M50 46 L45 42" stroke="{PAPER}" stroke-width="2" fill="none" stroke-linecap="round"/>'),
}

# ---------- head: stage 3, drawn around the human head (28,23 r9), moved by the base's anchor ----------
DOME = '<path d="M19 20 Q19 11 28 11 Q37 11 37 20Z"/>'
HEAD_PARTS = {
    "kettle": ('<path d="M18.5 18 Q18.5 8 28 8 Q37.5 8 37.5 18Z"/><ellipse cx="28" cy="18.5" rx="14" ry="3"/>', ""),
    "morion": ('<path d="M13 22 Q28 12 43 22 Q36 18.5 28 18.5 Q20 18.5 13 22Z"/><path d="M20 19.5 Q20 11 28 10 Q36 11 36 19.5Z"/><path d="M23.5 11 Q28 2 32.5 11Z"/>', ""),
    "greathelm": ('<path d="M23 11 Q22 3 14 3.5 Q18 6.5 18.5 11.5Z"/><rect x="18.5" y="11" width="19" height="21" rx="3"/>',
                  cut('<rect x="21" y="19" width="14" height="2.6" fill="#P"/>')),
    "horned": (DOME + '<path d="M19.5 17 Q12 14 13 5 Q16 12 22 13.5Z M36.5 17 Q44 14 43 5 Q40 12 34 13.5Z"/>', ""),
    "pelt": ('<path d="M17 31 Q16 14 21 11 L21 4 L26 9.5 H30 L35 4 L35 11 Q40 14 39 31Z"/>', cut('<circle cx="28" cy="24" r="5.4" fill="#P"/>')),
    "visor": ('<path d="M19 29 Q18 11 28 10 Q38 11 37 29Z"/><path d="M21 17 L9 23 L21 29Z"/>',
              cut('<path d="M13 22 L20 20 M13 24 L20 26" stroke="#P" stroke-width="1.2"/>')),
    "steppe": ('<path d="M20 17 Q22 8 28 4 Q34 8 36 17Z"/><ellipse cx="28" cy="18" rx="11.5" ry="3.8"/>',
               eye(21, 18, 1) + eye(25, 18.7, 1) + eye(29, 18.9, 1) + eye(33, 18.5, 1)),
    "feathercap": ('<path d="M17 20 Q19 11 29 11 Q38 12 39 20Z"/><path d="M33 13 Q38 5 45 3 Q41 9 35 15Z"/>', ""),
    "hood": ('<path d="M17 32 Q16 13 28 7 Q40 13 39 32Z"/>', cut('<circle cx="28" cy="24" r="5.2" fill="#P"/>')),
    "sallet": ('<path d="M18 23 Q18 11 28 11 Q36 11 38 18 L45 23 L38 24Z"/>', cut('<rect x="20" y="19" width="15" height="2.2" fill="#P"/>')),
    "mask": ('<rect x="16" y="19" width="24" height="5" rx="2.5"/><path d="M38 20.5 L46 17 L44 24Z"/>', eye(24, 21.5, 1.5) + eye(32, 21.5, 1.5)),
    "cowl": ('<path d="M17 32 Q16 13 28 12 Q40 13 39 32Z"/><path d="M37 18 L46 21 L38 25Z"/>', cut('<rect x="21" y="21" width="14" height="2.4" rx="1.2" fill="#P"/>')),
    "band": ('<rect x="18.5" y="15.5" width="19" height="4" rx="2"/><path d="M36 16 L45 20 L43 22.5 L36 19.5Z M36 17 L44 25 L41 26 L35 19Z"/>', ""),
    "kasa": ('<path d="M8 21 L28 7 L48 21 Q28 17 8 21Z"/>', ""),
    "mitre": ('<path d="M20 18 V9 Q24 4 28 1 Q32 4 36 9 V18Z"/>', cut('<path d="M28 5 V15 M24.5 9 H31.5" stroke="#P" stroke-width="1.6"/>')),
    "winged": (DOME + '<path d="M20 17 Q11 17 5 8 Q10 10 10 6.5 Q13 10 14 7.5 Q16 12 20 11Z M36 17 Q45 17 51 8 Q46 10 46 6.5 Q43 10 42 7.5 Q40 12 36 11Z"/>', ""),
    "witchhat": ('<ellipse cx="28" cy="16.5" rx="14" ry="3"/><path d="M20 16 Q26 10 28 2 Q34 1 39 7 Q33 5.5 32 9 Q34 13 36 16Z"/>', ""),
    "wizhat": ('<path d="M19.5 16 Q27 10 31 1 Q33 10 36.5 16Z"/><ellipse cx="28" cy="16.5" rx="14" ry="3"/>', ""),
    "shroud": ('<path d="M16 33 Q15 12 28 7 Q41 12 40 33Z"/>', eye(24.5, 23, 1.4) + eye(31.5, 23, 1.4)),
    "circlet": ('<rect x="18" y="16.5" width="20" height="2.6" rx="1.3"/><path d="M28 10.5 L31 14.8 L28 19 L25 14.8Z"/>', ""),
    "nullcrown": ('<rect x="18" y="16.5" width="20" height="2.6" rx="1.3"/>' + st("M28 13 m-4.5 0 a4.5 4.5 0 1 0 9 0 a4.5 4.5 0 1 0 -9 0", 2) + st("M24.8 16.2 L31.2 9.8", 2), ""),
    "falcon": ('<path d="M5 33 Q3 23 9 19 Q11 15 15 16 L19 16 L16 19 Q18 26 13 31 L11 37 L8 33Z"/>', eye(12.5, 19, 1.1)),
    "beret": ('<path d="M17 18 Q16 10 28 10 Q42 10 41 16 Q38 19 28 18 Q20 19 17 18Z"/><path d="M37 12 Q43 6 45 2 Q44 9 39 14Z"/>', ""),
    "miner": ('<path d="M19 19 Q19 9 28 9 Q37 9 37 19Z"/><rect x="15" y="18" width="26" height="3" rx="1.5"/>', eye(28, 14, 2.6)),
    "tricorn": ('<path d="M12 18 Q20 10 28 14 Q36 10 44 18 Q36 20 28 17 Q20 20 12 18Z"/><path d="M20 15 Q22 8 28 8 Q34 8 36 15Z"/>', ""),
    "slouch": ('<path d="M10 21 Q14 14 28 15 Q44 14 48 23 Q40 18 28 19 Q16 19 10 21Z"/><path d="M19 16 Q20 7 29 7 Q37 8 37 16Z"/>', ""),
    "turban": ('<path d="M17 20 Q16 8 28 8 Q40 8 39 20Z"/>',
               f'<path d="M19 17 Q28 10 37 15 M19 13 Q27 16 35 10" stroke="{PAPER}" stroke-width="1.2" fill="none"/>' + eye(28, 13.5, 2.2)),
    "laurel": (st("M18 27 Q15 15 26 12", 2) + st("M38 27 Q41 15 30 12", 2)
               + "".join(f'<ellipse cx="{x}" cy="{y}" rx="2.6" ry="1.4" transform="rotate({r} {x} {y})"/>'
                         for x, y, r in ((15, 22, -60), (17, 16, -30), (22, 12.5, -10), (41, 22, 60), (39, 16, 30), (34, 12.5, 10))), ""),
    "halo": ('<ellipse cx="28" cy="9" rx="9.5" ry="3" fill="none" stroke="@" stroke-width="2.5"/>', ""),
    "crown": ('<path d="M18 18 L18 9 L23 13 L28 6 L33 13 L38 9 L38 18Z"/>', ""),
    "antennae": (st("M24 15 Q21 6 16 5", 1.8) + st("M32 15 Q35 6 40 5", 1.8) + '<circle cx="16" cy="5" r="2.2"/><circle cx="40" cy="5" r="2.2"/>', ""),
    "gnomecap": ('<path d="M18 20 Q22 10 30 4 Q38 1 43 8 Q37 6 35 10 Q37 15 38 20Z"/>', ""),
    "spikehelm": (DOME + '<path d="M26 11 L28 1.5 L30 11Z"/>', ""),
    "headdress": ("".join(f'<ellipse cx="{28 + 12 * math.cos(math.radians(a)):.1f}" cy="{20 + 12 * math.sin(math.radians(a)):.1f}" rx="5" ry="1.9" '
                          f'transform="rotate({a} {28 + 12 * math.cos(math.radians(a)):.1f} {20 + 12 * math.sin(math.radians(a)):.1f})"/>'
                          for a in range(-160, -10, 25)) + '<rect x="18" y="16.5" width="20" height="3" rx="1.5"/>', ""),
    "fin": ('<path d="M20 20 Q22 6 37 5 Q31 10 35 20Z"/>', f'<path d="M25 19 L27 9 M30 19 L31 8" stroke="{PAPER}" stroke-width="1.2"/>'),
    "icecrest": ('<path d="M20 20 L23 9 L26 18 L29 6 L32 18 L35 9 L37 20Z"/>', ""),
    "horns": ('<path d="M30 21 L37 6 L34 20Z M25 21 L28 9 L29 21Z"/>', ""),
    "devil": ('<path d="M24 22 Q19 12 25 6 Q24 14 29 20Z M33 22 Q35 12 42 9 Q38 15 37 22Z"/>', ""),
    "plume": ('<path d="M24 18 Q22 6 34 2 Q30 8 32 18Z"/>', ""),
    "pack": ("", ""),   # tiny lines: a third figure joins (drawn by the base)
}

# ---------- crest: stage 4 glyph in white on the element-colored badge. f(c) -> svg, c = badge color ----------
def _gear(c):
    teeth = "".join(f'<rect x="49.6" y="5.2" width="2.8" height="3.4" fill="{W}" transform="rotate({a} 51 13)"/>' for a in range(0, 360, 45))
    return teeth + f'<circle cx="51" cy="13" r="5.2" fill="{W}"/><circle cx="51" cy="13" r="2" fill="{c}"/>'


def _ws(d, w=1.8):
    return f'<path d="{d}" fill="none" stroke="{W}" stroke-width="{w}" stroke-linecap="round" stroke-linejoin="round"/>'


CRESTS = {
    "shield": lambda c: f'<path d="M51 6.5 L56.5 8.5 Q56.5 16 51 19.5 Q45.5 16 45.5 8.5Z" fill="{W}"/>',
    "star": lambda c: f'<polygon points="{star_pts(51, 13.3, 6, 2.6)}" fill="{W}"/>',
    "sun": lambda c: f'<circle cx="51" cy="13" r="3" fill="{W}"/>' + "".join(
        _ws(f"M{51 + 4.5 * math.cos(i * math.pi / 4):.1f} {13 + 4.5 * math.sin(i * math.pi / 4):.1f} L{51 + 6.5 * math.cos(i * math.pi / 4):.1f} {13 + 6.5 * math.sin(i * math.pi / 4):.1f}", 1.6) for i in range(8)),
    "flame": lambda c: f'<path d="M51 5.5 Q56.5 10.5 55 15 Q54 19.5 51 19.5 Q47.5 19.5 47 16 Q46.5 12 50 9.5 Q49.8 13 51.8 13.5 Q53.5 10 51 5.5Z" fill="{W}"/>',
    "bolt": lambda c: f'<path d="M52.5 5 L46.5 14 L50.5 14 L48.5 21 L55.5 11 L51.5 11Z" fill="{W}"/>',
    "mountain": lambda c: f'<path d="M44.5 18 L48.5 10 L50.5 13 L53 8.5 L57.5 18Z" fill="{W}"/>',
    "wind": lambda c: _ws("M45 11 H53 Q56 11 56 8.5 Q56 6.5 54 6.8") + _ws("M45 15 H55 Q57.5 15 57.5 17.5 Q57.5 19.5 55.5 19"),
    "volley": lambda c: "".join(_ws(f"M{46 + d} 18 L{51 + d} 8 M{49.2 + d} 9.2 L{51 + d} 8 L{51.6 + d} 10", 1.5) for d in (-2.5, 0.5, 3.5)),
    "snow": lambda c: "".join(_ws(f"M51 13 L{51 + 6 * math.cos(i * math.pi / 3):.1f} {13 + 6 * math.sin(i * math.pi / 3):.1f}", 1.7) for i in range(6)),
    "moon": lambda c: f'<path d="M53.5 6.5 A7 7 0 1 0 55.5 18 A5.5 5.5 0 1 1 53.5 6.5Z" fill="{W}"/>',
    "crown": lambda c: f'<path d="M45 17 L45 9 L48.5 12.5 L51 7.5 L53.5 12.5 L57 9 L57 17Z" fill="{W}"/>',
    "drop": lambda c: f'<path d="M51 6 Q56 13 56 15 A5 5 0 0 1 46 15 Q46 13 51 6Z" fill="{W}"/>',
    "wreath": lambda c: _ws("M48 19 Q44 13 48 7", 1.6) + _ws("M54 19 Q58 13 54 7", 1.6) + "".join(
        f'<ellipse cx="{x}" cy="{y}" rx="1.8" ry="1" fill="{W}" transform="rotate({r} {x} {y})"/>'
        for x, y, r in ((45.5, 15, -60), (45.5, 10.5, 60), (56.5, 15, 60), (56.5, 10.5, -60))),
    "claw": lambda c: _ws("M47 8 Q50 13 47 19") + _ws("M51 7 Q54 13 51 19") + _ws("M55 8 Q58 13 55 19"),
    "axe": lambda c: _ws("M48 20 L54 6.5", 1.8) + f'<path d="M52.5 7 Q58.5 6 58.5 12.5 L53.5 11Z" fill="{W}"/>',
    "paw": lambda c: f'<ellipse cx="51" cy="15.5" rx="3.3" ry="2.7" fill="{W}"/>' + "".join(
        f'<circle cx="{x}" cy="{y}" r="1.5" fill="{W}"/>' for x, y in ((46.8, 11.8), (49.4, 9), (52.6, 9), (55.2, 11.8))),
    "spearhead": lambda c: f'<path d="M51 4.5 L55 12 L52 15 V21 H50 V15 L47 12Z" fill="{W}"/>',
    "horsehead": lambda c: f'<path d="M48 20 V14 Q48 7 53 6 L54 4.5 L55 7 L57.5 11 L56.5 13 L54 12.5 Q53 15 54.5 20Z" fill="{W}"/>',
    "target": lambda c: _ws("M51 13 m-6 0 a6 6 0 1 0 12 0 a6 6 0 1 0 -12 0", 1.4) + _ws("M51 13 m-3 0 a3 3 0 1 0 6 0 a3 3 0 1 0 -6 0", 1.4) + f'<circle cx="51" cy="13" r="1" fill="{W}"/>',
    "dagger": lambda c: f'<path d="M51 4.5 L53 14 H49Z" fill="{W}"/><rect x="46.5" y="14" width="9" height="1.8" fill="{W}"/><rect x="50.2" y="15.8" width="1.6" height="4" fill="{W}"/>',
    "crossed": lambda c: _ws("M46 19 L56 7") + _ws("M56 19 L46 7") + _ws("M45.5 15.5 L49.5 18.5", 1.6) + _ws("M56.5 15.5 L52.5 18.5", 1.6),
    "leaf": lambda c: f'<path d="M46 19 Q45 9 56 7 Q57 17 46 19Z" fill="{W}"/><path d="M46.5 18.5 L54 10" stroke="{c}" stroke-width="1"/>',
    "enso": lambda c: _ws("M47.5 8.5 A6 6 0 1 0 54 7.5", 2.2),
    "cross": lambda c: f'<rect x="49.5" y="6" width="3" height="14" fill="{W}"/><rect x="45.5" y="10" width="11" height="3" fill="{W}"/>',
    "note": lambda c: f'<circle cx="48.5" cy="17.5" r="2.4" fill="{W}"/><rect x="50.2" y="6.5" width="1.6" height="11" fill="{W}"/><path d="M51.8 6.5 Q56 8 55 12 Q54 9.5 51.8 9.5Z" fill="{W}"/>',
    "cauldron": lambda c: f'<path d="M45.5 11.5 H56.5 Q57 19.5 51 19.5 Q45 19.5 45.5 11.5Z" fill="{W}"/><rect x="44.5" y="10" width="13" height="2" rx="1" fill="{W}"/>'
                          f'<circle cx="49" cy="7" r="1.3" fill="{W}"/><circle cx="53" cy="6" r="1" fill="{W}"/>',
    "sparkle": lambda c: f'<path d="M51 5 Q52 12 58.5 13 Q52 14 51 21 Q50 14 43.5 13 Q50 12 51 5Z" fill="{W}"/>',
    "skull": lambda c: f'<circle cx="51" cy="11.5" r="5.3" fill="{W}"/><rect x="48.5" y="14.5" width="5" height="4.5" rx="1" fill="{W}"/>'
                       f'<circle cx="49" cy="11.5" r="1.4" fill="{c}"/><circle cx="53" cy="11.5" r="1.4" fill="{c}"/>',
    "spiral": lambda c: _ws("M51 13 a1.5 1.5 0 1 1 1.5 1.5 a3 3 0 1 1 -3 -3 a4.5 4.5 0 1 1 4.5 4.5", 1.5),
    "null": lambda c: _ws("M51 13 m-5.3 0 a5.3 5.3 0 1 0 10.6 0 a5.3 5.3 0 1 0 -10.6 0", 2) + _ws("M47.3 16.7 L54.7 9.3", 2),
    "feather": lambda c: f'<path d="M47 20 Q46 10 55.5 5.5 Q56.5 14 47 20Z" fill="{W}"/><path d="M47 20 L54 9" stroke="{c}" stroke-width="0.9"/>',
    "flag": lambda c: f'<rect x="46.5" y="5.5" width="1.6" height="15" fill="{W}"/><path d="M48 6 H57 L54.5 9.5 L57 13 H48Z" fill="{W}"/>',
    "gear": _gear,
    "wheat": lambda c: _ws("M51 20.5 V6.5", 1.2) + "".join(
        f'<ellipse cx="{51 + s * 2}" cy="{y}" rx="1.9" ry="1" fill="{W}" transform="rotate({s * -40} {51 + s * 2} {y})"/>'
        for y in (9, 12, 15) for s in (-1, 1)) + f'<ellipse cx="51" cy="6.5" rx="1" ry="1.8" fill="{W}"/>',
    "coin": lambda c: f'<circle cx="51" cy="13" r="5.8" fill="{W}"/><rect x="49.4" y="11.4" width="3.2" height="3.2" fill="{c}"/>',
    "card": lambda c: f'<rect x="47" y="6" width="8" height="14" rx="1.2" fill="{W}"/><polygon points="{star_pts(51, 13.2, 2.8, 1.2)}" fill="{c}"/>',
    "eye": lambda c: f'<path d="M44.5 13 Q51 5.5 57.5 13 Q51 20.5 44.5 13Z" fill="{W}"/><circle cx="51" cy="13" r="2.4" fill="{c}"/>',
    "scream": lambda c: f'<ellipse cx="47" cy="13" rx="1.8" ry="2.8" fill="{W}"/>' + _ws("M50.5 9.5 Q52.5 13 50.5 16.5", 1.4)
                        + _ws("M53.5 7.5 Q56.5 13 53.5 18.5", 1.4),
    "trident": lambda c: f'<rect x="50.2" y="9" width="1.6" height="12" fill="{W}"/>' + _ws("M46.5 6 V10.5 Q46.5 13 51 13 Q55.5 13 55.5 10.5 V6", 1.6) + _ws("M51 5 V12", 1.6),
    "fang": lambda c: f'<path d="M46 7 Q51 9 56 7 L52 20 Q51 14 49 11Z" fill="{W}"/>',
    "wing": lambda c: f'<path d="M45 19 Q47 8 57 6 Q55 9 56 11 Q52 11 53 14 Q49 14 49 18Z" fill="{W}"/>',
}


def badge(glyph, element):
    c = ELEMENT.get(element, ELEMENT[None])
    return f'<circle cx="51" cy="13" r="9.5" fill="{c}" stroke="{PAPER}" stroke-width="2.5"/>' + CRESTS[glyph](c)


# ---------- assembly ----------
def icon_svg(unit):
    base, hand, head, crest = (unit.get(k) for k in ("icon_base", "icon_hand", "icon_head", "icon_crest"))
    color = ALIGN.get(unit.get("alignment_lean"), ALIGN["Any"])
    parts = [f'<rect x="2" y="2" width="60" height="60" rx="10" fill="{PAPER}" stroke="{color}" stroke-width="3"/>']
    if unit.get("size") == "Large":  # double frame: takes two squad slots
        parts.append(f'<rect x="6.5" y="6.5" width="51" height="51" rx="6.5" fill="none" stroke="{color}" stroke-width="1.2"/>')
    if base in TINY:
        parts.append(TINY[base](head == "pack"))
        anchor = (0, 0)
    else:
        draw, anchor = BASES[base]
        parts.append(draw())
    if hand:
        parts.append(overlay(*HAND[hand]))
    if head and head != "pack":
        parts.append(f'<g transform="translate({anchor[0]} {anchor[1]})">{overlay(*HEAD_PARTS[head])}</g>')
    if crest:
        parts.append(badge(crest, unit.get("element")))
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="64" height="64">{"".join(parts)}</svg>\n'


def slug(name):
    return re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")


def problems_for(unit):
    out = []
    checks = (("icon_base", {**BASES, **TINY}), ("icon_hand", HAND), ("icon_head", HEAD_PARTS), ("icon_crest", CRESTS))
    for key, table in checks:
        value = unit.get(key)
        if key == "icon_base" and not value:
            out.append(f"{unit['class']}: no Icon base")
        elif value and value not in table:
            out.append(f"{unit['class']}: unknown {key.replace('_', ' ')} '{value}'")
    return out


def contact_sheet(units, path):
    cols, cell = 10, 72
    rows = (len(units) + cols - 1) // cols
    body = []
    for i, u in enumerate(units):
        x, y = (i % cols) * (cell + 34) + 10, (i // cols) * (cell + 26) + 10
        inner = re.sub(r"^<svg[^>]*>|</svg>\n$", "", icon_svg(u))
        body.append(f'<g transform="translate({x} {y}) scale({cell / 64})">{inner}</g>'
                    f'<text x="{x + cell / 2}" y="{y + cell + 14}" text-anchor="middle" font-family="Helvetica,Arial" font-size="11" fill="#333">{u["class"]}</text>')
    w, h = cols * (cell + 34) + 10, rows * (cell + 26) + 10
    path.write_text(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}">'
                    f'<rect width="100%" height="100%" fill="#fff"/>{"".join(body)}</svg>\n', encoding="utf-8")


def main():
    units = json.loads((DATA / "units.json").read_text(encoding="utf-8"))
    problems = [p for u in units for p in problems_for(u)]
    if problems:
        print("\n".join(problems))
        return 1
    OUT.mkdir(exist_ok=True)
    keep = set()
    for u in units:
        name = slug(u["class"]) + ".svg"
        keep.add(name)
        (OUT / name).write_text(icon_svg(u), encoding="utf-8")
    for old in OUT.glob("*.svg"):  # classes removed from the sheet
        if old.name not in keep:
            old.unlink()
    if "--sheet" in sys.argv:
        contact_sheet(units, Path(sys.argv[sys.argv.index("--sheet") + 1]))
    print(f"Wrote {len(units)} icons to {OUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
