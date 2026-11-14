"""Landwar mannequin unit icons - human classes.
Usage: python3 gen.py <units.xlsx> <outdir>
"""
import math, os, subprocess, sys

WOOD = '#E2BD8A'; JOINT = '#CC9F68'
STEEL = '#C3C9CF'; GOLD = '#DDB640'; LEA = '#5A4030'; BROWN = '#8A5E34'
RED = '#B03A2E'; BLUE = '#2F62A8'; GREEN = '#4E7F3A'; OCH = '#D08A28'
WHT = '#EFE8D8'; PUR = '#6D4BA3'; BUR = '#9C8767'; BLK = '#34303C'
FUR = '#7A5A3A'; CREAM = '#EADFC2'; STRAW = '#DCC578'; IRON = '#5C6470'
PINK = '#E58FB5'; SKY = '#8FC9E0'; YEL = '#E8C93A'; ORANGE = '#E0702A'
EARTH = '#7B6A45'; TEAL = '#2F8C8A'; MAG = '#B0407E'; DKGREEN = '#2F5A34'
GREY = '#5E5A66'; VIOLET = '#4B3A6E'


def dark(h, k=0.5):
    r, g, b = [int(h[i:i + 2], 16) for i in (1, 3, 5)]
    return '#%02x%02x%02x' % (int(r * k), int(g * k), int(b * k))


def S(fill, sw=5):
    return f'fill="{fill}" stroke="{dark(fill)}" stroke-width="{sw}" stroke-linejoin="round" stroke-linecap="round"'


def LN(col, sw):
    return f'fill="none" stroke="{col}" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round"'


def stick(x1, y1, x2, y2, col=BROWN, w=8):
    a = f'x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}"'
    return f'<line {a} {LN(dark(col), w + 5)}/><line {a} {LN(col, w)}/>'


def curve(d, col, w):
    return f'<path d="{d}" {LN(dark(col), w + 5)}/><path d="{d}" {LN(col, w)}/>'


def star(cx, cy, r, col=GOLD, sw=4):
    pts = []
    for i in range(10):
        rr = r if i % 2 == 0 else r * 0.45
        a = math.radians(-90 + i * 36)
        pts.append(f'{cx + rr * math.cos(a):.1f},{cy + rr * math.sin(a):.1f}')
    return f'<polygon points="{" ".join(pts)}" {S(col, sw)}/>'


def mirror(s):
    return s + f'<g transform="scale(-1,1)">{s}</g>'


# ---------------- body ----------------
def hand(x, a, b):
    ra = math.radians(a); rb = math.radians(a + b)
    ex = x - 62 * math.sin(ra); ey = 125 + 62 * math.cos(ra)
    return ex - 60 * math.sin(rb), ey + 60 * math.cos(rb)


def arm(x, a, b, sleeve):
    s = f'<g transform="translate({x},125) rotate({a})"><rect x="-9" y="4" width="18" height="52" rx="9" {S(WOOD)}/><circle cy="62" r="8" {S(JOINT)}/>'
    s += f'<g transform="translate(0,62) rotate({b})"><rect x="-8" y="5" width="16" height="46" rx="8" {S(WOOD)}/><ellipse cy="60" rx="9" ry="12" {S(WOOD)}/></g>'
    if sleeve:
        s += f'<rect x="-12" y="-11" width="24" height="36" rx="10" {S(sleeve)}/>'
    else:
        s += f'<circle r="11" {S(JOINT)}/>'
    return s + '</g>'


def leg(x, a, b, boot):
    c = boot or WOOD
    s = f'<g transform="translate({x},250) rotate({a})"><circle r="9" {S(JOINT)}/><rect x="-11" y="6" width="22" height="66" rx="10" {S(WOOD)}/><circle cy="78" r="9" {S(JOINT)}/>'
    s += f'<g transform="translate(0,78) rotate({b})"><rect x="-10" y="6" width="20" height="60" rx="9" {S(c)}/><ellipse cx="{-3 if x < 0 else 3}" cy="74" rx="17" ry="8" {S(c)}/></g></g>'
    return s


TORSO = (f'<rect x="-8" y="94" width="16" height="22" {S(WOOD)}/>'
         f'<path d="M-42,114 Q0,108 42,114 L28,182 Q0,190 -28,182 Z" {S(WOOD)}/>'
         f'<ellipse cx="0" cy="196" rx="20" ry="12" {S(JOINT)}/>'
         f'<path d="M-28,206 L28,206 L24,246 Q0,256 -24,246 Z" {S(WOOD)}/>')

RPOSE = {'up': (75, 70), 'fwd': (40, 75), 'plant': (45, 90), 'low': (30, 20), 'palm': (50, 100), 'down': (10, 8)}
LPOSE = {'hip': (-35, 75), 'down': (-12, -8), 'shield': (-25, -70), 'rein': (-28, -42), 'out': (-45, -80), 'up': (-75, -70)}
LEGS = {'stand': (4, 0, -6, 2), 'stride': (14, -4, -14, 6), 'brace': (10, -2, -12, 2), 'lunge': (18, -10, -10, 4)}


# ---------------- garments ----------------
def neckline(col=None):
    s = f'<path d="M-12,112 Q0,130 12,112 Z" {S(WOOD)}/>'
    if col:
        s += f'<path d="M-15,113 Q0,134 15,113" {LN(col, 6)}/>'
    return s


def g_tunic(c, sash=None, mantle=None):
    s = f'<path d="M-44,112 L44,112 L40,190 L47,288 Q0,300 -47,288 L-40,190 Z" {S(c)}/>' + neckline()
    if sash:
        s += f'<path d="M-44,112 L-18,112 L40,174 L39,192 L20,192 Z" {S(sash)}/>'
    if mantle:
        s += f'<path d="M-52,112 L52,112 L46,156 Q0,176 -46,156 Z" {S(mantle)}/>' + neckline()
    return s


def g_tabard(c):
    return f'<path d="M-44,112 L44,112 L38,192 L46,274 L10,279 L0,260 L-10,279 L-46,274 L-38,192 Z" {S(c)}/>' + neckline()


def g_robe(c, trim=None):
    s = f'<path d="M-44,112 L44,112 L40,190 L64,390 Q0,404 -64,390 L-40,190 Z" {S(c)}/>' + neckline()
    if trim:
        s += f'<path d="M-61,372 Q0,386 61,372" {LN(trim, 9)}/>'
    return s


def g_plate(c):
    return (g_tabard(c) + f'<path d="M-45,112 L45,112 L38,190 Q0,200 -38,190 Z" {S(STEEL)}/>'
            f'<line x1="0" y1="118" x2="0" y2="190" {LN(dark(STEEL, .7), 4)}/>' + neckline())


def g_kilt(c):
    return (f'<path d="M-40,190 L40,190 L48,270 L30,258 L16,276 L0,258 L-16,276 L-30,258 L-48,270 Z" {S(c)}/>'
            f'<path d="M-40,116 L-26,112 L34,190 L20,192 Z" {S(LEA)}/>')


def g_coat(c):
    s = f'<path d="M-44,112 L44,112 L40,190 L52,330 L8,336 L0,200 L-8,336 L-52,330 L-40,190 Z" {S(c)}/>' + neckline()
    return s + f'<line x1="0" y1="130" x2="0" y2="200" {LN(dark(c), 4)}/>'


def belt(col=LEA, buckle=GOLD):
    return f'<rect x="-41" y="191" width="82" height="11" rx="3" {S(col, 4)}/><rect x="-8" y="188" width="16" height="17" fill="none" stroke="{buckle}" stroke-width="4"/>'


def cape(c):
    return f'<path d="M-48,114 L48,114 L78,336 Q0,356 -78,336 Z" {S(c)}/>'


# ---------------- emblems (chest, centred 0,150) ----------------
def e_chev(c=CREAM):
    return f'<path d="M-16,140 L0,156 L16,140" {LN(c, 7)}/>'


def e_star():
    return star(0, 150, 22)


def e_sun():
    r = ''.join(f'<line x1="{26 * math.cos(math.radians(a)):.1f}" y1="{150 + 26 * math.sin(math.radians(a)):.1f}" x2="{17 * math.cos(math.radians(a)):.1f}" y2="{150 + 17 * math.sin(math.radians(a)):.1f}" {LN(GOLD, 5)}/>' for a in range(0, 360, 45))
    return r + f'<circle cx="0" cy="150" r="13" {S(GOLD, 4)}/>'


def e_ring(c=BLK):
    return f'<path d="M12,134 A20 20 0 1 0 18,146" {LN(c, 7)}/>'


def e_moon():
    return f'<path d="M8,130 A22 22 0 1 0 8,172 A16 16 0 1 1 8,130 Z" {S(CREAM, 4)}/>'


def e_gear():
    t = ''.join(f'<rect x="-5" y="-27" width="10" height="12" transform="translate(0,152) rotate({a})" {S(GOLD, 3)}/>' for a in range(0, 360, 45))
    return t + f'<circle cx="0" cy="152" r="17" {S(GOLD, 4)}/><circle cx="0" cy="152" r="6" fill="{dark(GOLD)}"/>'


def e_paw():
    return (f'<ellipse cx="0" cy="158" rx="14" ry="11" {S(CREAM, 4)}/>' + ''.join(f'<circle cx="{x}" cy="{y}" r="6" {S(CREAM, 3)}/>' for x, y in ((-16, 142), (-5, 134), (7, 134), (17, 142))))


def e_leaf():
    return f'<path d="M0,128 Q24,146 0,176 Q-24,146 0,128 Z" {S("#8FCB5A", 4)}/><line x1="0" y1="134" x2="0" y2="172" {LN(dark(GREEN), 3)}/>'


def e_null():
    return f'<circle cx="0" cy="150" r="20" {LN(CREAM, 7)}/><line x1="-14" y1="164" x2="14" y2="136" {LN(CREAM, 7)}/>'


def e_cross():
    return f'<path d="M0,128 L0,176 M-18,144 L18,144" {LN(GOLD, 9)}/>'


# ---------------- hand items (grip at origin, "up" is -y) ----------------
def sword(n=112, w=6, guard=GOLD):
    return (f'<rect x="-4" y="-6" width="8" height="26" {S(LEA, 4)}/><circle cy="22" r="6" {S(guard, 4)}/>'
            f'<polygon points="{-w},-10 {w},-10 {w},{-n + 16} 0,{-n} {-w},{-n + 16}" {S(STEEL)}/>'
            f'<rect x="-20" y="-15" width="40" height="9" rx="3" {S(guard, 4)}/>')


def dagger():
    return sword(66, 6)


def spear(down=275, up=132, w=8):
    return stick(0, down, 0, -up, BROWN, w) + f'<polygon points="-14,{-up + 6} 0,{-up - 52} 14,{-up + 6}" {S(STEEL)}/>'


def lance(c, down=150, up=136):
    return (stick(0, down, 0, -up, BROWN, 10) + f'<polygon points="-12,{-up + 4} 0,{-up - 44} 12,{-up + 4}" {S(STEEL)}/>'
            f'<path d="M4,{-up + 12} L70,{-up + 30} L4,{-up + 52} Z" {S(c)}/>'
            f'<polygon points="-18,-22 18,-22 6,-56 -6,-56" {S(STEEL)}/>')


def axe(double=False):
    head = f'<path d="M0,-108 Q-58,-122 -52,-50 Q-24,-66 0,-62 Z" {S(STEEL)}/>'
    s = stick(0, 34, 0, -112, BROWN, 9) + head
    if double:
        s += f'<g transform="scale(-1,1)">{head}</g>'
    return s


def bow(arrow=True):
    s = curve('M30,-104 Q-52,0 30,104', BROWN, 9) + f'<line x1="30" y1="-104" x2="30" y2="104" {LN("#5c5346", 3)}/>'
    if arrow:
        s += stick(58, 0, -56, 0, STRAW, 4) + f'<polygon points="-54,-11 -80,0 -54,11" {S(STEEL, 4)}/>'
    return s


def crossbow(heavy=False):
    s = stick(46, 0, -80, 0, BROWN, 13 if heavy else 11)
    s += curve('M-66,-60 Q-104,0 -66,60', STEEL if heavy else BROWN, 9)
    s += f'<path d="M-66,-60 L-14,0 L-66,60" {LN("#5c5346", 3)}/>'
    s += f'<polygon points="-84,-9 -108,0 -84,9" {S(STEEL, 4)}/>'
    return s


def sling():
    return (f'<path d="M-90,-58 A78 78 0 0 1 28,-112" {LN("#ffffff", 5)} opacity=".75"/>'
            + curve('M0,0 Q-34,-40 -26,-92', LEA, 4) + curve('M0,0 Q8,-52 -10,-96', LEA, 4)
            + f'<ellipse cx="-18" cy="-98" rx="17" ry="10" {S(LEA, 4)}/><circle cx="-18" cy="-106" r="11" {S("#9A9A9A", 4)}/>')


def staff_top(kind, c, ty):
    if kind == 'orb':
        return f'<circle cx="0" cy="{ty - 14}" r="20" {S(c)}/><circle cx="-6" cy="{ty - 20}" r="6" fill="#ffffff" opacity=".6"/>'
    if kind == 'flame':
        return (f'<path d="M0,{ty - 66} Q30,{ty - 24} 16,{ty} Q0,{ty + 10} -16,{ty} Q-30,{ty - 24} 0,{ty - 66} Z" {S(ORANGE)}/>'
                f'<path d="M0,{ty - 36} Q12,{ty - 14} 6,{ty - 2} Q0,{ty + 2} -6,{ty - 2} Q-12,{ty - 14} 0,{ty - 36} Z" fill="{YEL}"/>')
    if kind == 'rock':
        return f'<polygon points="-24,{ty} -28,{ty - 26} -8,{ty - 46} 18,{ty - 40} 28,{ty - 16} 16,{ty + 2}" {S("#8C8478")}/>'
    if kind == 'bolt':
        return f'<polygon points="6,{ty - 70} -24,{ty - 22} -4,{ty - 22} -14,{ty + 14} 24,{ty - 38} 4,{ty - 38} 18,{ty - 70}" {S(YEL)}/>'
    if kind == 'swirl':
        return f'<circle cx="0" cy="{ty - 18}" r="24" {S("#D6F0F5")}/><path d="M-12,{ty - 14} Q-10,{ty - 34} 6,{ty - 30} Q16,{ty - 22} 6,{ty - 12} Q-2,{ty - 10} -2,{ty - 18}" {LN(TEAL, 5)}/>'
    if kind == 'skull':
        return (f'<rect x="-11" y="{ty - 14}" width="22" height="16" rx="3" {S(CREAM, 4)}/><circle cx="0" cy="{ty - 26}" r="20" {S(CREAM)}/>'
                f'<circle cx="-8" cy="{ty - 26}" r="6" fill="#2a2a2a"/><circle cx="8" cy="{ty - 26}" r="6" fill="#2a2a2a"/>')
    if kind == 'sun':
        r = ''.join(f'<line x1="{30 * math.cos(math.radians(a)):.1f}" y1="{ty - 18 + 30 * math.sin(math.radians(a)):.1f}" x2="{20 * math.cos(math.radians(a)):.1f}" y2="{ty - 18 + 20 * math.sin(math.radians(a)):.1f}" {LN(dark(GOLD, .8), 6)}/>' for a in range(0, 360, 45))
        return r + f'<circle cx="0" cy="{ty - 18}" r="17" {S(GOLD)}/>'
    if kind == 'star':
        return star(0, ty - 18, 26)
    if kind == 'spiral':
        return curve(f'M0,{ty} Q-30,{ty - 10} -26,{ty - 34} Q-18,{ty - 54} 4,{ty - 48} Q20,{ty - 40} 14,{ty - 24} Q8,{ty - 14} -2,{ty - 22}', MAG, 7)
    return ''


def staff(kind='orb', c=SKY, down=275, up=106):
    return stick(0, down, 0, -up, BROWN, 8) + staff_top(kind, c, -up)


def rod(kind='sun', c=GOLD):
    return staff(kind, c, 48, 74)


def whip():
    return f'<rect x="-5" y="-18" width="10" height="40" rx="4" {S(LEA, 4)}/>' + curve('M0,-18 Q-30,-130 -86,-96 Q-120,-70 -92,-38 Q-78,-26 -66,-40', LEA, 6)


def shovel():
    return stick(0, 44, 0, -110, BROWN, 9) + f'<path d="M-22,-108 L22,-108 L22,-150 Q0,-178 -22,-150 Z" {S(STEEL)}/>'


def hammer():
    return stick(0, 44, 0, -110, BROWN, 10) + f'<rect x="-40" y="-150" width="80" height="46" rx="7" {S(IRON)}/>'


def banner(c, emb=GOLD, down=275):
    return (stick(0, down, 0, -150, BROWN, 8) + f'<path d="M5,-146 L108,-146 L86,-106 L108,-66 L5,-66 Z" {S(c)}/>'
            f'<circle cx="46" cy="-106" r="14" {S(emb, 4)}/><circle cx="0" cy="-156" r="8" {S(GOLD, 4)}/>')


def horn(c):
    return (f'<polygon points="-4,4 8,-8 -66,-74 -92,-70 -104,-104 -70,-92" {S(GOLD)}/>'
            f'<path d="M-20,-20 L-52,-48 L-36,-4 L-18,10 Z" {S(c, 4)}/>')


def sabre():
    return (f'<rect x="-4" y="-6" width="8" height="26" {S(LEA, 4)}/>'
            f'<path d="M-7,-10 Q-12,-84 -46,-124 Q0,-96 9,-10 Z" {S(STEEL)}/>'
            f'<path d="M-16,-12 L16,-12 Q22,8 6,20" {LN(dark(GOLD, .6), 9)}/><path d="M-16,-12 L16,-12 Q22,8 6,20" {LN(GOLD, 5)}/>')


def katana():
    return (f'<rect x="-5" y="-8" width="10" height="40" rx="3" {S(BLK, 4)}/>'
            f'<path d="M-5,-12 L5,-12 Q9,-92 -10,-146 Q-12,-84 -5,-12 Z" {S(STEEL)}/>'
            f'<ellipse cx="0" cy="-12" rx="13" ry="6" {S(GOLD, 4)}/>')


def mace():
    sp = ''.join(f'<polygon points="-6,-22 6,-22 0,-36" transform="translate(0,-104) rotate({a})" {S(IRON, 3)}/>' for a in range(0, 360, 60))
    return stick(0, 34, 0, -84, BROWN, 9) + sp + f'<circle cx="0" cy="-104" r="22" {S(IRON)}/>'


def torch():
    return stick(0, 40, 0, -50, BROWN, 9) + staff_top('flame', None, -50)


def sack():
    return f'<path d="M-10,-4 Q-50,-8 -46,-56 Q-40,-92 0,-90 Q40,-92 46,-56 Q50,-8 10,-4 Z" {S("#C8B48A")}/><path d="M-14,-84 L-6,-104 L8,-104 L14,-84" {S("#C8B48A", 4)}/><line x1="-14" y1="-84" x2="14" y2="-84" {LN(LEA, 5)}/>'


def crate():
    return (f'<rect x="-44" y="-92" width="88" height="84" rx="5" {S("#B98A54")}/>'
            f'<path d="M-44,-64 L44,-64 M-44,-36 L44,-36" {LN(dark("#B98A54"), 4)}/><path d="M-30,-92 L-30,-8 M30,-92 L30,-8" {LN(dark("#B98A54", .7), 6)}/>')


def coinbag():
    return (''.join(f'<circle cx="{x}" cy="{y}" r="11" {S(GOLD, 4)}/>' for x, y in ((-14, -74), (10, -84), (26, -66)))
            + f'<path d="M-8,-4 Q-40,-8 -34,-42 Q-28,-66 0,-64 Q28,-66 34,-42 Q40,-8 8,-4 Z" {S(LEA)}/><circle cx="0" cy="-34" r="10" {S(GOLD, 4)}/>')


def crystal():
    return f'<path d="M-22,-8 L22,-8 L14,-22 L-14,-22 Z" {S(GOLD, 4)}/><circle cx="0" cy="-52" r="34" {S("#BFE6F5")}/><path d="M-18,-66 Q-10,-78 4,-78" {LN("#ffffff", 6)}/>'


def cards():
    return ''.join(f'<g transform="rotate({a})"><rect x="-18" y="-86" width="36" height="56" rx="5" {S(CREAM, 4)}/><rect x="-7" y="-66" width="14" height="14" transform="rotate(45 0 -59)" fill="{c}"/></g>' for a, c in ((-32, RED), (0, BLK), (32, RED)))


def book(c=VIOLET):
    return (f'<polygon points="-50,-58 0,-46 50,-58 50,-6 0,6 -50,-6" {S(c)}/>'
            f'<polygon points="-42,-58 0,-48 42,-58 42,-14 0,-4 -42,-14" {S(CREAM, 4)}/><line x1="0" y1="-48" x2="0" y2="-4" {LN(dark(CREAM), 4)}/>')


def wand(kind='star'):
    return stick(0, 14, 0, -70, CREAM, 5) + staff_top(kind, None, -70)


def broom():
    return stick(0, 275, 0, -96, BROWN, 8) + f'<polygon points="-12,-92 12,-92 40,-176 -40,-176" {S(STRAW)}/><rect x="-14" y="-104" width="28" height="12" rx="3" {S(LEA, 4)}/>'


def flask():
    return (''.join(f'<circle cx="{x}" cy="{y}" r="{r}" {S("#9BE06A", 3)}/>' for x, y, r in ((-6, -96, 7), (10, -112, 9), (-8, -128, 6)))
            + f'<rect x="-9" y="-78" width="18" height="26" {S("#DFF3E0", 4)}/><circle cx="0" cy="-36" r="30" {S("#5CBF4A")}/><rect x="-14" y="-84" width="28" height="8" rx="3" {S("#DFF3E0", 4)}/>')


def lyre():
    return (curve('M-30,-110 Q-44,-24 0,-12 Q44,-24 30,-110', GOLD, 9) + stick(-34, -96, 34, -96, GOLD, 6)
            + ''.join(f'<line x1="{x}" y1="-94" x2="{x * .5}" y2="-18" {LN("#6b5a2a", 3)}/>' for x in (-16, 0, 16)))


def wheat():
    s = ''
    for a in (-24, 0, 24):
        s += f'<g transform="rotate({a})">' + stick(0, 10, 0, -70, STRAW, 4) + ''.join(f'<ellipse cx="{dx}" cy="{y}" rx="7" ry="12" {S(GOLD, 3)}/>' for y in (-78, -98, -118) for dx in (-7, 7)) + '</g>'
    return s + f'<rect x="-16" y="-22" width="32" height="12" rx="4" {S(RED, 4)}/>'


def falcon(big=False):
    s = ''
    if big:
        w = f'<path d="M-10,-52 Q-70,-96 -92,-50 Q-60,-58 -44,-34 Q-28,-40 -10,-26 Z" {S(BROWN)}/>'
        s += mirror(w)
    s += (f'<path d="M-8,-10 L0,10 L8,-10 Z" {S(dark(BROWN, .8), 4)}/><ellipse cx="0" cy="-38" rx="19" ry="30" {S(BROWN)}/>'
          f'<ellipse cx="0" cy="-32" rx="10" ry="18" {S(CREAM, 3)}/><circle cx="-2" cy="-74" r="15" {S(BROWN)}/>'
          f'<polygon points="-14,-76 -30,-70 -14,-66" {S(GOLD, 3)}/><circle cx="-6" cy="-78" r="3" fill="#222"/>')
    return s


def pitchfork():
    return stick(0, 275, 0, -96, BROWN, 8) + curve('M-20,-150 L-20,-108 Q0,-92 20,-108 L20,-150 M0,-150 L0,-100', IRON, 6)


# ---------------- shields (centre 121,190) ----------------
def sh_kite(c, emb=''):
    return f'<g transform="translate(121,190)"><path d="M-36,-56 L36,-56 L36,-4 Q36,40 0,62 Q-36,40 -36,-4 Z" fill="{c}" stroke="{dark(STEEL, .55)}" stroke-width="8" stroke-linejoin="round"/>{emb}</g>'


def sh_round(c, emb='', r=46, rim=STEEL):
    return f'<g transform="translate(121,190)"><circle r="{r}" fill="{c}" stroke="{dark(rim, .7)}" stroke-width="8"/>{emb}</g>'


def sh_rect(c, emb='', h=140, w=80):
    return f'<g transform="translate(121,196)"><rect x="{-w / 2}" y="{-h / 2}" width="{w}" height="{h}" rx="9" fill="{c}" stroke="{dark(STEEL, .55)}" stroke-width="8"/>{emb}</g>'


SE_CHEV = f'<path d="M-18,-22 L0,-4 L18,-22" {LN(CREAM, 8)}/>'
SE_BOSS = f'<circle r="14" {S(GOLD, 4)}/>'
SE_SUN = ''.join(f'<line x1="{32 * math.cos(math.radians(a)):.1f}" y1="{32 * math.sin(math.radians(a)):.1f}" x2="{22 * math.cos(math.radians(a)):.1f}" y2="{22 * math.sin(math.radians(a)):.1f}" {LN(GOLD, 6)}/>' for a in range(0, 360, 45)) + f'<circle r="16" {S(GOLD, 4)}/>'
SE_STRIPE = f'<rect x="-11" y="-66" width="22" height="132" fill="{GREEN}"/>'
SE_SHINE = f'<path d="M-18,-14 Q-8,-26 8,-24" {LN("#ffffff", 7)}/>'

# ---------------- back items ----------------
def quiver():
    return (f'<g transform="translate(34,104) rotate(28)"><rect x="-13" y="-30" width="26" height="110" rx="8" {S(LEA)}/>'
            + ''.join(f'<path d="M{x},-30 L{x},-62 L{x - 8},-50 M{x},-62 L{x + 8},-50" {LN(c, 5)}/>' for x, c in ((-7, RED), (7, CREAM))) + '</g>')


def hussar_wing():
    f = ''.join(f'<path d="M{70 + i * 2},{150 - i * 34} q34,-14 44,-44 q-28,6 -46,26 Z" {S("#F4F1EA", 4)}/>' for i in range(5))
    return curve('M62,190 Q70,60 96,-4', BROWN, 7) + f


def fairy_wings():
    w = f'<path d="M30,130 Q110,60 122,120 Q118,160 40,170 Z" {S("#F9E3F0", 4)}/><path d="M34,176 Q100,176 96,222 Q70,236 36,200 Z" {S("#F9E3F0", 4)}/>'
    return mirror(w)


# ---------------- head items: return (back, front) in head coords ----------------
DOME = lambda c: f'<path d="M-27,62 Q-27,31 0,31 Q27,31 27,62 Z" {S(c)}/>'
HOOD = lambda c: f'<path d="M-31,102 Q-38,28 0,26 Q38,28 31,102 L21,102 Q26,52 0,50 Q-26,52 -21,102 Z" {S(c)}/>'


def H_kettle(c): return '', DOME(STEEL) + f'<ellipse cx="0" cy="62" rx="43" ry="9" {S(STEEL)}/>'


def H_morion(c, crest=None):
    f = ''
    if crest:
        f += f'<path d="M-38,30 Q0,-26 38,30 Q0,12 -38,30 Z" {S(crest)}/>'
    else:
        f += f'<path d="M-8,36 Q0,-6 8,36 Z" {S(STEEL)}/>'
    return '', f + DOME(STEEL) + f'<path d="M-48,46 L-24,58 L24,58 L48,46 L27,72 L-27,72 Z" {S(STEEL)}/>'


def H_greathelm(c, band=None):
    f = f'<rect x="-29" y="32" width="58" height="72" rx="12" {S(STEEL)}/><rect x="-20" y="57" width="40" height="8" rx="3" fill="#26262b"/><line x1="0" y1="66" x2="0" y2="100" {LN(dark(STEEL, .6), 4)}/>'
    if band:
        f += f'<rect x="-29" y="42" width="58" height="9" {S(band, 3)}/>'
    return '', f


def H_horned(c):
    h = f'<path d="M-20,46 Q-54,46 -52,6 Q-38,32 -16,34 Z" {S(CREAM)}/>'
    return '', mirror(h) + DOME(IRON) + f'<rect x="-28" y="54" width="56" height="10" rx="4" {S(IRON, 4)}/>'


def H_pelt(c):
    e = f'<polygon points="-32,42 -28,10 -8,30" {S(FUR)}/>'
    return '', mirror(e) + HOOD(FUR) + f'<circle cx="-10" cy="38" r="3" fill="#222"/><circle cx="10" cy="38" r="3" fill="#222"/>'


def H_visor(c):
    return '', (f'<path d="M0,36 Q18,-6 58,14 Q30,18 12,44 Z" {S(c)}/><ellipse cx="0" cy="68" rx="29" ry="34" {S(STEEL)}/>'
                f'<path d="M-27,58 L27,58 L20,84 L-20,84 Z" {S(dark(STEEL, .85), 4)}/><line x1="-18" y1="66" x2="18" y2="66" {LN("#26262b", 4)}/>')


def H_steppe(c):
    return '', f'<polygon points="-27,54 0,6 27,54" {S(c)}/><circle cx="0" cy="6" r="7" {S(GOLD, 3)}/><rect x="-32" y="46" width="64" height="16" rx="8" {S("#D8C9A8")}/>'


def H_feathercap(c):
    return '', f'<path d="M8,40 Q22,0 54,-6 Q42,22 18,46 Z" {S("#D9483B")}/><path d="M-31,60 Q-14,24 30,44 L48,58 Q0,48 -31,64 Z" {S(c)}/>'


def H_hood(c): return '', HOOD(c)


def H_sallet(c):
    return '', f'<path d="M-29,66 Q-29,29 0,29 Q31,29 31,56 L56,74 L-29,74 Z" {S(STEEL)}/><line x1="-24" y1="60" x2="16" y2="60" {LN("#26262b", 5)}/>'


def H_mask(c):
    return '', (DOME(c) + f'<path d="M-25,78 Q0,70 25,78 Q23,102 0,104 Q-23,102 -25,78 Z" {S(RED)}/>'
                f'<path d="M24,76 L50,70 L44,84 Z" {S(RED, 4)}/>')


def H_cowl(c):
    return '', HOOD(BLK) + f'<ellipse cx="0" cy="70" rx="24" ry="30" fill="{BLK}"/><rect x="-18" y="58" width="36" height="10" rx="5" fill="{WOOD}"/>'


def H_band(c):
    return '', f'<path d="M24,54 L60,42 L52,58 Z" {S(c, 4)}/><path d="M24,60 L58,76 L44,60 Z" {S(c, 4)}/><rect x="-26" y="51" width="52" height="11" rx="3" {S(c, 4)}/>'


def H_slouch(c):
    return '', (f'<path d="M14,34 Q34,2 56,6 Q46,24 26,40 Z" {S(CREAM, 4)}/><ellipse cx="0" cy="56" rx="50" ry="11" {S(c)}/>'
                f'<path d="M-24,54 Q-22,22 0,27 Q22,20 24,54 Z" {S(c)}/>')


def H_kasa(c):
    return '', f'<polygon points="-58,66 0,18 58,66" {S(STRAW)}/><path d="M-30,44 L30,44 M-44,56 L44,56" {LN(dark(STRAW, .75), 3)}/>'


def H_mitre(c):
    return '', f'<path d="M-24,58 L-24,34 L0,-2 L24,34 L24,58 Z" {S(WHT)}/><rect x="-24" y="48" width="48" height="10" {S(GOLD, 3)}/><line x1="0" y1="6" x2="0" y2="48" {LN(GOLD, 6)}/>'


def H_winged(c):
    w = f'<path d="M-24,50 Q-58,42 -56,-2 Q-44,22 -36,20 Q-40,34 -24,38 Z" {S("#F4F1EA")}/>'
    return '', mirror(w) + DOME(STEEL) + f'<rect x="-28" y="54" width="56" height="10" rx="4" {S(GOLD, 4)}/>'


def H_witchhat(c, band=GOLD):
    return '', (f'<path d="M-26,54 Q-12,6 34,-24 Q16,18 26,54 Z" {S(c)}/><ellipse cx="0" cy="55" rx="52" ry="11" {S(c)}/>'
                f'<path d="M-24,46 Q0,52 24,46" {LN(band, 7)}/>')


def H_wizhat(c):
    return '', f'<polygon points="-28,56 0,-30 28,56" {S(c)}/><ellipse cx="0" cy="56" rx="34" ry="8" {S(c)}/>' + star(0, 26, 12, GOLD, 3)


def H_shroud(c):
    return '', HOOD(c) + f'<path d="M-23,50 Q0,42 23,50 L22,74 Q0,82 -22,74 Z" fill="#17151c" opacity=".9"/>'


def H_circlet(c, hair='#6B3F2A'):
    b = f'<path d="M-31,64 Q-38,26 0,26 Q38,26 31,64 L44,150 Q22,150 20,104 L-20,104 Q-22,150 -44,150 Z" {S(hair)}/>'
    return b, f'<path d="M-25,56 Q0,44 25,56" {LN(dark(GOLD, .6), 10)}/><path d="M-25,56 Q0,44 25,56" {LN(GOLD, 6)}/><circle cx="0" cy="49" r="7" {S(c, 3)}/>'


def H_nullcrown(c):
    return '', f'<path d="M-28,58 L-28,30 L-14,46 L0,26 L14,46 L28,30 L28,58 Z" {S(IRON)}/><line x1="-8" y1="48" x2="8" y2="48" {LN("#111", 4)}/>'


def H_cap(c):
    return '', f'<path d="M12,36 Q24,6 46,4 Q38,24 24,42 Z" {S(CREAM, 4)}/>' + DOME(LEA) + f'<path d="M-27,58 L-31,84 L-20,80 Z" {S(LEA, 4)}/><path d="M27,58 L31,84 L20,80 Z" {S(LEA, 4)}/>'


def H_beret(c):
    return '', f'<path d="M20,34 Q40,4 58,8 Q50,26 32,42 Z" {S(CREAM, 4)}/><ellipse cx="6" cy="42" rx="37" ry="16" transform="rotate(-12 6 42)" {S(c)}/><rect x="-25" y="50" width="50" height="9" rx="3" {S(dark(c, .8), 3)}/>'


def H_miner(c):
    return '', (DOME('#C79A3C') + f'<rect x="-32" y="56" width="64" height="9" rx="4" {S("#C79A3C", 4)}/>'
                f'<rect x="-7" y="14" width="14" height="22" rx="2" {S(CREAM, 4)}/><path d="M0,-12 Q12,4 0,16 Q-12,4 0,-12 Z" {S(ORANGE, 3)}/>')


def H_laurel(c):
    lf = ''.join(f'<ellipse cx="{x}" cy="{y}" rx="7" ry="12" transform="rotate({a} {x} {y})" {S("#5E9E3E", 3)}/>' for x, y, a in ((-28, 62, -10), (-27, 46, 20), (-18, 34, 50), (-6, 30, 80)))
    return '', mirror(lf)


def H_tricorn(c):
    return '', f'<polygon points="-52,54 -22,26 0,38 22,26 52,54 0,66" {S(BLK)}/><path d="M-48,54 L-22,30 L0,42 L22,30 L48,54" {LN(GOLD, 4)}/>'


def H_turban(c):
    return '', (f'<path d="M0,26 Q10,-10 30,-8 Q24,10 12,28 Z" {S(CREAM, 4)}/><ellipse cx="0" cy="44" rx="33" ry="22" {S(c)}/>'
                f'<path d="M-28,50 Q0,28 28,50 M-22,36 Q0,60 22,36" {LN(dark(c, .7), 3)}/><circle cx="0" cy="40" r="7" {S(GOLD, 3)}/>')


HEADS = {k[2:]: v for k, v in globals().items() if k.startswith('H_')}


# ---------------- mount ----------------
def horse_head(c, bridle):
    return (f'<polygon points="126,142 134,108 148,136" {S(c)}/>'
            f'<path d="M92,246 L120,150 Q150,116 188,150 L210,190 Q204,208 186,200 L160,184 L142,250 Z" {S(c)}/>'
            f'<path d="M116,160 Q100,196 96,236" {LN(dark(c, .45), 9)}/>'
            f'<circle cx="170" cy="160" r="5" fill="#1c1c1c"/><path d="M176,144 L196,192 M150,178 L186,156" {LN(bridle, 5)}/>')


def horse_stick():
    return stick(108, 236, -76, 394, BROWN, 10) + f'<circle cx="-76" cy="394" r="10" {S(dark(BROWN, .8), 4)}/>'


def limb(pts, col=None, w=20, hoof=None):
    col = col or WOOD
    o = ''
    for (x1, y1), (x2, y2) in zip(pts, pts[1:]):
        o += stick(x1, y1, x2, y2, col, w)
    for x, y in pts[1:-1]:
        o += f'<circle cx="{x}" cy="{y}" r="{w * .55:.0f}" {S(JOINT, 4)}/>'
    if hoof:
        fx, fy = pts[-1]
        o += f'<ellipse cx="{fx - 2}" cy="{fy + 2}" rx="17" ry="10" {S(hoof, 4)}/>'
    return o


def horse(c, cloth=None, neck=True, tailc=None):
    tc = tailc or dark(c, .55)
    dk = dark(WOOD, .8)
    o = curve('M128,300 Q188,312 182,404', tc, 18)
    o += limb([(-70, 360), (-86, 415), (-76, 464)], dk, 20, '#2a2622') + limb([(100, 360), (120, 415), (110, 464)], dk, 20, '#2a2622')
    o += f'<ellipse cx="0" cy="322" rx="135" ry="58" {S(c)}/>'
    if neck:
        o += f'<path d="M-60,282 L-150,236 Q-178,232 -182,256 L-128,345 Z" {S(c)}/>'
        o += f'<polygon points="-168,236 -178,196 -150,228" {S(c)}/>'
        o += f'<path d="M-156,238 Q-182,222 -202,244 L-236,318 Q-240,340 -220,342 L-200,338 L-166,294 Z" {S(c)}/>'
        o += curve('M-150,230 Q-100,248 -58,276', tc, 14)
        o += f'<circle cx="-196" cy="264" r="6" fill="#1c1c1c"/><circle cx="-224" cy="328" r="3" fill="#1c1c1c"/>'
        if cloth:
            o += f'<path d="M-212,296 L-180,284 M-190,246 L-170,290" {LN(cloth, 6)}/>'
    o += limb([(-92, 366), (-110, 420), (-98, 466)], WOOD, 22, '#2a2622') + limb([(92, 366), (114, 420), (100, 466)], WOOD, 22, '#2a2622')
    o += f'<circle cx="-92" cy="362" r="13" {S(JOINT, 4)}/><circle cx="92" cy="362" r="13" {S(JOINT, 4)}/>'
    if cloth:
        o += f'<path d="M-54,266 L54,266 L62,340 Q0,354 -62,340 Z" {S(cloth)}/><path d="M-58,330 Q0,344 58,330" {LN(GOLD, 5)}/>'
    return o


def rider_leg(boot):
    return limb([(-12, 258), (-46, 318), (-36, 384)], WOOD, 21) + f'<circle cx="-12" cy="258" r="11" {S(JOINT, 4)}/><ellipse cx="-42" cy="390" rx="18" ry="9" {S(boot or WOOD)}/>'


# ---------------- figure assembly ----------------
def figure(u):
    c = u.get('c', BUR)
    g = u.get('g', 'tunic')
    st = u['stage']
    trim = GOLD if st == 4 else None
    hb, hf = HEADS[u['head']](u.get('hc', c), **u.get('hkw', {})) if u.get('head') else ('', '')
    HT = 'transform="translate(0,100) scale(1.18) translate(0,-100)"'
    o = ''
    for b in u.get('back', []):
        o += b
    o += f'<g {HT}>{hb}</g>'
    boot = u.get('boots')
    if u.get('horse'):
        o += horse(u['horse'], c) + rider_leg(boot)
    o += u.get('lower', '')
    l = LEGS[u.get('legs', 'stand')]
    if not (u.get('horse') or u.get('nolegs')):
        o += leg(-15, l[0], l[1], boot) + leg(15, l[2], l[3], boot)
    o += TORSO
    sleeve = c
    if g == 'tunic':
        o += g_tunic(BUR, u.get('sash'), u.get('mantle')); sleeve = u.get('mantle') or BUR
    elif g == 'tabard': o += g_tabard(c)
    elif g == 'robe': o += g_robe(c, trim or u.get('trim'))
    elif g == 'plate': o += g_plate(c); sleeve = STEEL
    elif g == 'kilt': o += g_kilt(c); sleeve = None
    elif g == 'coat': o += g_coat(c)
    elif g == 'none': sleeve = None
    if 'sleeve' in u: sleeve = u['sleeve']
    if g not in ('kilt', 'none') and trim:
        o += neckline(GOLD)
    o += u.get('emb', '')
    if u.get('belt', True):
        o += belt(GOLD if st == 4 else LEA, dark(GOLD, .6) if st == 4 else GOLD)
    rp = RPOSE[u.get('rp', 'up')]; lp = LPOSE[u.get('lp', 'hip')]
    if u.get('R'):
        it, ang = u['R']; hx, hy = hand(-50, *rp)
        o += f'<g transform="translate({hx:.1f},{hy:.1f}) rotate({ang})">{it}</g>'
    if u.get('L'):
        it, ang = u['L']; hx, hy = hand(50, *lp)
        o += f'<g transform="translate({hx:.1f},{hy:.1f}) rotate({ang})">{it}</g>'
    o += arm(-50, rp[0], rp[1], sleeve) + arm(50, lp[0], lp[1], sleeve)
    o += u.get('shield', '')
    o += f'<g {HT}><ellipse cx="0" cy="70" rx="24" ry="30" {S(WOOD)}/><ellipse cx="-8" cy="60" rx="5" ry="9" fill="#F0D6AC"/>{hf}</g>'
    o += u.get('front', '')
    return o


def svg(u, size=256, pad=0):
    dx = u.get('dx', 0)
    fs = u.get('fs', 0.46 if u.get('horse') else 0.5)
    base = u.get('base', 477 if u.get('horse') else 412.5)
    wide = u.get('wide', 1)
    body = figure(u)
    if u.get('skin'):
        body = body.replace(S(WOOD), S(u['skin'])).replace(f'fill="{WOOD}"', f'fill="{u["skin"]}"').replace('fill="#F0D6AC"', f'fill="{u["skin"]}"')
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{size + 2 * pad}" height="{size + 2 * pad}" viewBox="{-pad} {-pad} {256 + 2 * pad} {256 + 2 * pad}">'
            f'<g transform="translate({128 + dx},{243.7 - base * fs:.1f}) scale({fs * wide},{fs})">{body}</g></svg>')


def autofit(u):
    """Centre the figure horizontally using its true extents; return (w, top) overflow info."""
    from PIL import Image
    import io
    u['dx'] = 0
    png = subprocess.run(['rsvg-convert'], input=svg(u, 256, 128).encode(), capture_output=True, check=True).stdout
    b = Image.open(io.BytesIO(png)).getchannel('A').getbbox()
    l, t, r, bot = b[0] - 128, b[1] - 128, b[2] - 128, b[3] - 128
    if not u.get('feetcentre'):
        u['dx'] = round(128 - (l + r) / 2)
    return r - l, t, bot, l, r


# ---------------- unit specs ----------------
def U_():
    U = {}
    M = dict(horse='#8A5A30', lp='hip', feetcentre=True)
    # name: (stage auto), drawn weapon label 'w'
    U['Serf'] = dict(R=(pitchfork(), 0), rp='plant', w='pitchfork', dx=10)
    # --- stage 2
    U['Fighter'] = dict(sash=RED, R=(sword(), -30), legs='stride', w='sword', dx=16)
    U['Squire'] = dict(sash=BLUE, c=BLUE, R=(lance(BLUE), -38), rp='fwd', w='lance', **M)
    U['Bowman'] = dict(sash=GREEN, R=(bow(), 0), rp='fwd', legs='brace', w='bow', dx=22)
    U['Slinger'] = dict(sash=OCH, R=(sling(), 0), legs='stride', w='sling', dx=14)
    U['Acolyte'] = dict(mantle=WHT, R=(rod(), -12), rp='up', w='rod', dx=10)
    U['Apprentice'] = dict(mantle=PUR, R=(staff('orb', SKY), 0), rp='plant', w='staff', dx=12)
    # --- line 1
    U['Soldier'] = dict(g='tabard', c=RED, head='kettle', R=(sword(), -62), rp='fwd', legs='lunge', boots=LEA, emb=e_chev(), w='sword', dx=22)
    U['Sentinel'] = dict(g='tabard', c=RED, head='kettle', R=(sword(), -30), legs='brace', boots=LEA, lp='shield', shield=sh_kite(RED, SE_CHEV), sleeve=STEEL, emb=e_chev(), w='sword + kite shield', dx=10)
    U['Champion'] = dict(g='tabard', c=RED, head='kettle', R=(sword(150, 9), -22), rp='up', legs='stride', boots=LEA, back=[cape('#7A1F1A')], emb=e_star(), w='greatsword', dx=18)
    # --- line 2
    U['Spearman'] = dict(g='tabard', c=RED, head='morion', R=(spear(), 0), rp='plant', legs='brace', boots=LEA, emb=e_chev(), w='spear', dx=14)
    U['Centurion'] = dict(g='tabard', c=RED, head='morion', hkw=dict(crest='#D9483B'), R=(spear(), 0), rp='plant', legs='brace', boots=LEA, lp='shield', shield=sh_rect(RED, SE_BOSS), sleeve=STEEL, w='spear + tower shield', dx=4)
    U['Dragonslayer'] = dict(g='tabard', c=RED, head='morion', R=(sword(146, 12), -24), rp='up', legs='lunge', boots=LEA, back=[cape(DKGREEN)], emb=e_chev(GOLD), w='oversized greatsword', dx=18)
    # --- line 3
    U['Knight'] = dict(g='plate', c=WHT, head='greathelm', R=(sword(), -30), legs='stride', boots=IRON, w='sword', dx=16)
    U['Paladin'] = dict(g='plate', c=WHT, head='greathelm', hkw=dict(band=GOLD), R=(sword(), -30), legs='brace', boots=IRON, lp='shield', shield=sh_round(WHT, SE_SUN, rim=GOLD), back=[cape(WHT)], w='sword + sun shield', dx=8)
    # --- line 4
    U['Berserker'] = dict(g='kilt', c=FUR, head='horned', R=(axe(), -28), legs='lunge', boots=FUR, w='axe', dx=16)
    U['Reaver'] = dict(g='kilt', c=BLK, head='horned', R=(axe(True), -24), L=(axe(), 30), lp='up', legs='lunge', boots=BLK, back=[cape('#6E1512')], w='double axe + hand axe', dx=4)
    # --- line 5
    U['Tamer'] = dict(g='tabard', c=FUR, head='pelt', R=(whip(), -10), legs='stride', boots=LEA, w='whip', dx=16)
    U['Beastlord'] = dict(g='tabard', c=FUR, head='pelt', R=(whip(), -10), L=(spear(120, 110), 12), lp='out', legs='brace', boots=LEA, back=[cape('#5B4226')], emb=e_paw(), w='whip + spear', dx=6)
    # --- line 25
    U['Sapper'] = dict(g='tabard', c=RED, head='miner', R=(shovel(), -26), legs='stride', boots=LEA, w='shovel', dx=16)
    U['Siege Engineer'] = dict(g='tabard', c=RED, head='miner', R=(hammer(), -26), legs='brace', boots=LEA, emb=e_gear(), sleeve=LEA, w='sledgehammer', dx=16)
    # --- line 6-8, 24 mounted
    U['Lancer'] = dict(g='tabard', c=BLUE, head='visor', R=(lance(BLUE), -38), rp='fwd', boots=LEA, w='lance', **M)
    U['Dragoon'] = dict(g='plate', c=BLUE, head='visor', R=(lance(GOLD), -38), rp='fwd', boots=IRON, back=[cape(BLUE)], w='lance', **{**M, 'horse': '#3F3F46'})
    U['Horse Archer'] = dict(g='tabard', c=BLUE, head='steppe', R=(bow(), 0), rp='up', boots=LEA, w='bow', **M)
    U['Scythian'] = dict(g='tabard', c=BLUE, head='steppe', R=(bow(), 0), rp='up', boots=LEA, back=[quiver(), cape('#1F4274')], w='bow', **{**M, 'horse': '#CFC6B4'})
    U['Scout'] = dict(g='tabard', c=BLUE, head='feathercap', R=(sabre(), -30), boots=LEA, w='sabre', dx=8, **M)
    U['Hussar'] = dict(g='tabard', c=BLUE, head='feathercap', R=(sabre(), -30), boots=LEA, back=[hussar_wing()], w='sabre', dx=8, **{**M, 'horse': '#CFC6B4'})
    U['Herald'] = dict(g='tabard', c=BLUE, head='beret', R=(horn(BLUE), 10), rp='up', boots=LEA, w='horn', dx=8, **M)
    U['Standard-Bearer'] = dict(g='tabard', c=BLUE, head='beret', R=(banner(BLUE, GOLD, 140), -8), rp='plant', boots=LEA, w='banner', dx=6, **M)
    # --- line 9-12, 23
    U['Archer'] = dict(g='tabard', c=GREEN, head='hood', R=(bow(), 0), rp='fwd', legs='brace', boots=LEA, w='bow', dx=22)
    U['Warbow'] = dict(g='tabard', c=GREEN, head='hood', R=(f'<g transform="scale(1.25)">{bow()}</g>', 0), rp='fwd', legs='brace', boots=LEA, back=[quiver()], w='longbow', dx=26)
    U['Crossbowman'] = dict(g='tabard', c=GREEN, head='sallet', R=(crossbow(), 0), rp='fwd', legs='brace', boots=LEA, w='crossbow', dx=26)
    U['Arbalest'] = dict(g='tabard', c=GREEN, head='sallet', R=(crossbow(True), 0), rp='fwd', legs='brace', boots=LEA, lp='shield', shield=sh_rect(WHT, SE_STRIPE, 150, 84), w='heavy crossbow + pavise', dx=14)
    U['Rogue'] = dict(g='tabard', c=DKGREEN, head='mask', hc=DKGREEN, R=(dagger(), -70), rp='fwd', legs='lunge', boots=LEA, w='dagger', dx=18)
    U['Assassin'] = dict(g='tabard', c=DKGREEN, head='mask', hc=DKGREEN, R=(dagger(), -70), rp='fwd', L=(dagger(), 40), lp='up', legs='lunge', boots=LEA, back=[cape('#1F3A22')], w='twin daggers', dx=8)
    U['Shade'] = dict(g='tabard', c=BLK, head='cowl', R=(katana(), -70), rp='low', legs='lunge', boots=BLK, w='short blade', dx=22)
    U['Nightblade'] = dict(g='tabard', c=BLK, head='cowl', R=(katana(), -70), rp='low', L=(katana(), 8), lp='up', legs='lunge', boots=BLK, emb=e_moon(), w='twin blades', dx=12)
    U['Falconer'] = dict(g='tabard', c=GREEN, head='cap', R=(falcon(), 0), rp='palm', legs='stand', boots=LEA, back=[quiver()], w='falcon', dx=12)
    U['Hawkmaster'] = dict(g='tabard', c=GREEN, head='cap', R=(falcon(True), 0), rp='palm', legs='stand', boots=LEA, back=[quiver(), cape(DKGREEN)], w='hawk', dx=16)
    # --- line 13-15, 22, 27
    U['Swordfighter'] = dict(g='tabard', c=OCH, head='band', hc=RED, R=(sabre(), -62), rp='fwd', legs='lunge', boots=LEA, w='sabre', dx=22)
    U['Swordmaster'] = dict(g='tabard', c=OCH, head='band', hc=RED, R=(sabre(), -62), rp='fwd', L=(sabre(), 38), lp='up', legs='lunge', boots=LEA, w='twin sabres', dx=10)
    U['Skirmisher'] = dict(g='tabard', c=OCH, head='slouch', hc=BROWN, R=(spear(70, 120, 6), -40), rp='up', legs='stride', boots=LEA, lp='shield', shield=sh_round(BROWN, SE_BOSS, 30), w='javelin + buckler', dx=10)
    U['Ranger'] = dict(g='tabard', c=OCH, head='slouch', hc=DKGREEN, R=(spear(70, 120, 6), -40), rp='up', L=(spear(60, 100, 6), 8), lp='out', legs='stride', boots=LEA, back=[cape(DKGREEN)], emb=e_leaf(), w='javelins', dx=8)
    U['Ronin'] = dict(g='robe', c=OCH, head='kasa', R=(katana(), -34), rp='up', w='katana', dx=18)
    U['Kensei'] = dict(g='robe', c=WHT, head='kasa', R=(katana(), -34), rp='up', L=(katana(), 150), lp='down', emb=e_ring(), w='katana pair', dx=14)
    U['Spellbreaker'] = dict(g='tabard', c=OCH, head='nullcrown', R=(mace(), -28), legs='stride', boots=LEA, lp='shield', shield=sh_round('#DCEAF0', SE_SHINE, 36, GOLD), w='mace + mirror shield', dx=10)
    U['Witch Hunter'] = dict(g='coat', c=GREY, head='nullcrown', R=(mace(), -28), L=(torch(), 10), lp='out', legs='stride', boots=LEA, emb=e_null(), w='mace + torch', dx=6)
    U['Smuggler'] = dict(g='coat', c=OCH, head='tricorn', R=(sack(), -20), rp='up', legs='stride', boots=LEA, w='sack', dx=12)
    U['Fence'] = dict(g='coat', c=OCH, head='tricorn', R=(coinbag(), 0), rp='palm', L=(dagger(), 30), lp='out', legs='stand', boots=LEA, w='coin bag + dagger', dx=4)
    # --- line 16-18, 26
    U['Cleric'] = dict(g='robe', c=WHT, head='mitre', R=(rod(), -12), rp='up', trim=GOLD, w='rod', dx=10)
    U['Templar'] = dict(g='robe', c=WHT, head='mitre', R=(staff('sun', GOLD), 0), rp='plant', emb=e_cross(), back=[cape('#D9C27A')], w='sun staff', dx=12)
    U['Valkyrie'] = dict(g='plate', c=WHT, head='winged', R=(spear(150, 132), -38), rp='fwd', boots=IRON, w='spear', **{**M, 'horse': '#DDD6C6'})
    U['Warsinger'] = dict(g='plate', c=WHT, head='winged', R=(lyre(), -10), rp='palm', boots=IRON, back=[cape(SKY)], w='lyre', dx=6, **{**M, 'horse': '#DDD6C6'})
    U['Witch'] = dict(g='robe', c=VIOLET, head='witchhat', R=(broom(), 0), rp='plant', w='broom', dx=12)
    U['Wicked Witch'] = dict(g='robe', c=BLK, head='witchhat', hkw=dict(band='#7BD04A'), R=(broom(), 0), rp='plant', L=(flask(), 0), lp='out', w='broom + potion', dx=6)
    U['Fairy Godmother'] = dict(g='robe', c=PINK, head='witchhat', hkw=dict(band='#ffffff'), R=(wand('star'), -20), rp='up', back=[fairy_wings()], w='star wand', dx=6)
    U['Quartermaster'] = dict(g='tabard', c=WHT, head='laurel', R=(crate(), 0), rp='palm', legs='stride', boots=LEA, w='supply crate', dx=12)
    U['Provisioner'] = dict(g='tabard', c=WHT, head='laurel', R=(crate(), 0), rp='palm', L=(wheat(), 10), lp='out', legs='stride', boots=LEA, w='supply crate + wheat', dx=6)
    # --- line 19-21, 28
    U['Mage'] = dict(g='robe', c=PUR, head='wizhat', R=(staff('orb', SKY), 0), rp='plant', w='staff', dx=12)
    U['Fire Mage'] = dict(g='robe', c='#C43C22', head='wizhat', R=(staff('flame', None), 0), rp='plant', w='flame staff', dx=12)
    U['Wind Mage'] = dict(g='robe', c=SKY, head='wizhat', R=(staff('swirl', None), 0), rp='plant', w='wind staff', dx=12)
    U['Earth Mage'] = dict(g='robe', c=EARTH, head='wizhat', R=(staff('rock', None), 0), rp='plant', w='stone staff', dx=12)
    U['Lightning Mage'] = dict(g='robe', c=YEL, head='wizhat', R=(staff('bolt', None), 0), rp='plant', w='bolt staff', dx=12)
    U['Occultist'] = dict(g='robe', c=GREY, head='shroud', R=(book(), 0), rp='palm', w='tome', dx=10)
    U['Necromancer'] = dict(g='robe', c=BLK, head='shroud', R=(staff('skull', None), 0), rp='plant', L=(book('#5A1F5A'), 0), lp='out', w='skull staff + tome', dx=6)
    U['Enchantress'] = dict(g='robe', c=MAG, head='circlet', R=(wand('spiral'), -20), rp='up', w='wand', dx=10)
    U['Sorceress'] = dict(g='robe', c=MAG, head='circlet', hkw=dict(hair='#2B2030'), R=(wand('spiral'), -20), rp='up', L=(f'<g transform="translate(0,-10) scale(.8)">{crystal()}</g>', 0), lp='out', back=[cape('#6E2450')], w='wand + orb', dx=4)
    U['Seer'] = dict(g='robe', c=TEAL, head='turban', hc=CREAM, R=(crystal(), 0), rp='palm', w='crystal ball', dx=10)
    U['Oracle'] = dict(g='robe', c=TEAL, head='turban', hc=GOLD, R=(crystal(), 0), rp='palm', L=(cards(), 0), lp='out', w='crystal ball + cards', dx=4)
    return U


SHEET_HAND = {'sword': 'sword', 'lance': 'lance', 'bow': 'bow', 'sling': 'sling', 'rod': 'rod', 'staff': 'staff', None: '-'}


def fname(n):
    return n.lower().replace(' ', '_').replace('-', '_')


def main():
    import openpyxl
    from PIL import Image, ImageDraw, ImageFont
    xlsx, out = sys.argv[1], sys.argv[2]
    ws = openpyxl.load_workbook(xlsx, data_only=True)['Units']
    rows = list(ws.iter_rows(values_only=True)); ix = {n: i for i, n in enumerate(rows[0])}
    humans = [r for r in rows[1:] if r[0] and r[ix['Icon base']] == 'human']
    U = U_()
    missing = [r[0] for r in humans if r[0] not in U]
    assert not missing, missing
    os.makedirs(f'{out}/png', exist_ok=True); os.makedirs(f'{out}/svg', exist_ok=True)
    notes = []
    for r in humans:
        n = r[0]; u = U[n]; u['stage'] = r[ix['Stage']]
        fit = autofit(u)
        if fit[3] + u['dx'] < 4 or fit[4] + u['dx'] > 252 or fit[1] < 4 or fit[2] > 246: print('OVER', n, fit)
        p = f'{out}/svg/{fname(n)}.svg'
        open(p, 'w').write(svg(u))
        subprocess.run(['rsvg-convert', '-w', '256', '-h', '256', p, '-o', f'{out}/png/{fname(n)}.png'], check=True)
        sh = r[ix['Icon hand']]
        notes.append((n, r[ix['Stage']], r[ix['Line(s)']], sh, u['w']))
    # contact sheet
    cols = 10; cw, ch = 150, 196
    nrow = math.ceil(len(humans) / cols)
    sheet = Image.new('RGB', (cols * cw, nrow * ch), '#E9E2D2')
    d = ImageDraw.Draw(sheet)
    f = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', 13)
    for i, r in enumerate(humans):
        n = r[0]; im = Image.open(f'{out}/png/{fname(n)}.png').convert('RGBA')
        x, y = (i % cols) * cw, (i // cols) * ch
        big = im.resize((128, 128), Image.LANCZOS); sheet.paste(big, (x + 11, y + 4), big)
        d.rectangle([x + 8, y + 136, x + 142, y + 174], fill='#3B4252')
        for s, ox in ((32, 14), (24, 54)):
            sm = im.resize((s, s), Image.LANCZOS); sheet.paste(sm, (x + ox, y + 139 + (32 - s) // 2), sm)
        d.rectangle([x + 88, y + 138, x + 140, y + 172], fill='#E9E2D2')
        for s, ox in ((32, 90), (24, 118)):
            sm = im.resize((s, s), Image.LANCZOS); sheet.paste(sm, (x + ox, y + 139 + (32 - s) // 2), sm)
        d.text((x + cw / 2, y + 185), f'{n} ({r[ix["Stage"]]})', fill='#222', font=f, anchor='mm')
    sheet.save(f'{out}/contact_sheet_humans.png')
    with open(f'{out}/weapon_notes.md', 'w') as fh:
        fh.write('# Landwar mannequin icons - what each human class holds\n\n')
        fh.write('Rows marked CHANGED hold something other than the sheet\'s `Icon hand` value.\n\n')
        fh.write('| Class | Stage | Sheet Icon hand | Drawn | |\n|---|---|---|---|---|\n')
        for n, st, ln, sh, w in notes:
            base = w.split(' + ')[0]
            same = (sh or 'none') in base or (sh is None and n == 'Serf' and False)
            fh.write(f'| {n} | {st} | {sh or "-"} | {w} | {"" if same else "CHANGED"} |\n')
    print(len(humans), 'icons')


if __name__ == '__main__':
    main()
