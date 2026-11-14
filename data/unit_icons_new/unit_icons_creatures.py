"""Landwar mannequin icons - non-human classes (folk as full figures, monsters as wooden-toy heads).
Usage: python3 beasts.py <units.xlsx> <outdir>
"""
import io, math, os, subprocess, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from unit_icons_humans import *
import unit_icons_humans as gen

ICE = '#BFE6F5'; WATER = '#3F8FD0'; FLAME = ORANGE


def flame(x, y, rot=0, sc=1.0):
    return f'<g transform="translate({x},{y}) rotate({rot}) scale({sc})">{staff_top("flame", None, 0)}</g>'


def poly(pts, c, sw=5):
    return f'<polygon points="{pts}" {S(c, sw)}/>'


def path(d, c, sw=5):
    return f'<path d="{d}" {S(c, sw)}/>'


def circ(x, y, r, c, sw=5):
    return f'<circle cx="{x}" cy="{y}" r="{r}" {S(c, sw)}/>'


def eye(x, y, r, c=YEL, slit=True):
    p = f'<ellipse cx="{x}" cy="{y}" rx="{r * .28:.0f}" ry="{r * .8:.0f}" fill="#1c1c1c"/>' if slit else f'<circle cx="{x - r * .15:.0f}" cy="{y}" r="{r * .5:.0f}" fill="#1c1c1c"/>'
    return circ(x, y, r, c, 4) + p


def mir(s, cx=256):
    return s + f'<g transform="translate({2 * cx},0) scale(-1,1)">{s}</g>'


def neck(c, x=372, y=366):
    return circ(x + 28, y + 86, 34, JOINT) + f'<ellipse cx="{x}" cy="{y}" rx="56" ry="84" transform="rotate(-18 {x} {y})" {S(c)}/>'


def teeth(xs, y, up=False, h=16):
    return ''.join(f'<polygon points="{x},{y} {x + 9},{y + (-h if up else h)} {x + 18},{y}" fill="{CREAM}" stroke="{dark(CREAM)}" stroke-width="3"/>' for x in xs)


# ============ base heads: return (back, main, anchors) ============
def b_wolf(c, c2):
    back = poly('330,172 374,82 394,188', dark(c, .8))
    m = neck(c) + path('M262,298 L150,296 Q136,310 152,320 L258,334 Z', c) + teeth((160, 190, 220), 300, True)
    m += path('M392,236 Q392,152 306,152 Q252,152 220,192 L116,242 Q98,258 116,274 L246,306 Q352,330 392,236 Z', c)
    m += teeth((150, 180, 210), 284) + circ(114, 252, 14, '#2a2a2a', 3) + poly('288,170 318,70 358,172', c) + poly('306,160 320,104 340,162', c2, 3)
    m += circ(300, 312, 12, JOINT, 4) + eye(268, 214, 16)
    return back, m, dict(eye=(268, 214), top=(322, 152), mouth=(128, 296), brow=(240, 188), side=(150, 420))


def b_cat(c, c2, mane=None, stripes=False):
    back = poly('340,168 368,88 396,182', dark(c, .8))
    if mane:
        back = ''.join(circ(330 + 128 * math.cos(math.radians(a)), 256 + 128 * math.sin(math.radians(a)), 50, mane) for a in range(-150, 151, 30)) + circ(330, 256, 130, mane)
    m = neck(c) + path('M266,298 L206,300 Q194,314 208,322 L264,330 Z', c)
    m += path('M392,240 Q392,150 300,150 Q214,150 192,214 Q168,236 180,266 Q194,300 250,304 Q356,322 392,240 Z', c)
    m += poly('290,168 300,76 356,162', c) + poly('304,156 310,108 338,158', c2, 3)
    m += poly('174,238 198,230 192,256', '#D9788A', 3) + f'<path d="M206,262 L120,250 M206,270 L124,282" {LN(dark(c), 3)}/>'
    m += teeth((204, 226), 298, False, 14) + eye(262, 214, 18, '#9BD15A')
    if stripes:
        m += f'<path d="M318,154 L306,196 M350,166 L336,206 M378,200 L352,224 M384,250 L354,256" {LN("#2a2a2a", 8)}/>'
    return back, m, dict(eye=(262, 214), top=(320, 150), mouth=(196, 300), brow=(236, 186), side=(150, 420))


def b_goat(c, c2):
    back = path('M330,160 Q350,112 392,108 Q368,134 364,166 Z', dark(CREAM, .8))
    m = neck(c) + poly('176,330 214,326 202,400', CREAM)
    m += path('M392,230 Q392,152 310,152 Q262,152 236,196 L150,300 Q140,326 164,334 L216,328 Q300,322 340,300 Q392,290 392,230 Z', c)
    m += poly('352,200 432,172 424,210 368,226', c) + path('M296,160 Q310,108 354,100 Q330,130 330,164 Z', CREAM)
    m += f'<path d="M160,316 L210,308" {LN(dark(c), 4)}/><circle cx="160" cy="298" r="4" fill="#2a2a2a"/>'
    m += circ(270, 216, 17, YEL, 4) + '<rect x="258" y="212" width="24" height="8" rx="3" fill="#1c1c1c"/>'
    return back, m, dict(eye=(270, 216), top=(322, 152), mouth=(160, 326), brow=(250, 188), side=(140, 430))


def b_bison(c, c2):
    back = ''.join(circ(400 + 120 * math.cos(math.radians(a)), 250 + 120 * math.sin(math.radians(a)), 46, c2) for a in range(-170, 60, 28)) + circ(400, 250, 124, c2)
    m = circ(400, 452, 34, JOINT) + f'<ellipse cx="392" cy="372" rx="70" ry="80" {S(c2)}/>' + poly('190,344 240,340 222,420', c2)
    m += path('M384,252 Q384,160 300,160 Q230,160 206,220 L170,300 Q160,340 200,348 L260,342 Q344,338 384,252 Z', c)
    m += path('M300,176 Q262,120 296,82 Q300,128 334,164 Z', CREAM)
    m += f'<ellipse cx="190" cy="318" rx="22" ry="16" {S(dark(c, .7), 4)}/><circle cx="184" cy="316" r="4" fill="#111"/>'
    m += eye(262, 238, 12, '#F0E0C0', False)
    return back, m, dict(eye=(262, 238), top=(326, 158), mouth=(176, 336), brow=(246, 200), side=(130, 430))


def b_lizard(c, c2, frill=False, long=False):
    back = ''
    if frill:
        back = path('M380,220 L470,120 L452,210 L500,220 L452,268 L480,330 L390,300 Z', c2)
    m = neck(c, 392, 372)
    m += path('M352,316 L176,330 Q156,352 180,366 L346,360 Z', c2 if frill else c) + teeth((196, 236, 276), 334, True)
    m += path('M400,196 Q382,124 318,142 L130,240 Q108,264 132,286 L300,330 Q390,326 404,262 Z', c)
    m += teeth((176, 216, 256), 298) + circ(356, 340, 14, JOINT, 4) + '<circle cx="152" cy="252" r="6" fill="#1c1c1c"/>'
    m += eye(300, 222, 24)
    return back, m, dict(eye=(300, 222), top=(352, 150), mouth=(150, 334), brow=(250, 196), side=(150, 440))


def b_bird(c, c2):
    back = poly('372,170 440,120 414,196', dark(c, .8)) + poly('384,214 462,196 420,250', dark(c, .8))
    m = neck(c) + circ(310, 240, 94, c2)
    m += path('M240,282 L170,286 Q178,308 240,302 Z', dark(GOLD, .8)) + path('M236,204 L130,236 Q94,262 120,304 Q132,272 172,276 L240,284 Z', GOLD)
    m += '<circle cx="180" cy="246" r="4" fill="#1c1c1c"/>' + eye(272, 216, 18, '#F6D23A', False) + f'<path d="M244,196 L300,188" {LN(dark(c2), 7)}/>'
    return back, m, dict(eye=(272, 216), top=(322, 146), mouth=(132, 280), brow=(250, 180), side=(150, 420))


def b_rat(c, c2, red=False):
    back = circ(372, 176, 40, dark(c, .8))
    m = neck(c) + path('M392,250 Q392,170 310,170 Q262,170 236,206 L132,262 Q112,276 130,292 L250,314 Q350,332 392,250 Z', c)
    m += circ(326, 166, 50, c) + circ(326, 166, 30, '#E0A0A8', 3) + circ(120, 272, 13, '#D9788A', 3)
    m += f'<path d="M160,270 L92,240 M160,280 L88,292" {LN(dark(c), 3)}/>'
    m += f'<rect x="156" y="296" width="12" height="26" {S(CREAM, 3)}/><rect x="170" y="298" width="12" height="26" {S(CREAM, 3)}/>'
    m += circ(270, 228, 12, '#C4281C' if red else '#1c1c1c', 3)
    return back, m, dict(eye=(270, 228), top=(290, 172), mouth=(160, 306), brow=(240, 200), side=(150, 420))


def b_bat(c, c2, red=False):
    back = mir(path('M330,300 Q430,170 500,250 Q478,286 486,330 Q446,308 424,352 Q384,330 340,356 Z', dark(c, .8)))
    m = circ(256, 452, 30, JOINT) + f'<ellipse cx="256" cy="390" rx="50" ry="50" {S(c)}/>'
    m += mir(poly('286,196 346,56 372,226', c) + poly('304,196 344,102 354,214', '#E0A0A8', 3))
    m += circ(256, 270, 92, c) + f'<ellipse cx="256" cy="296" rx="34" ry="26" {S(c2, 4)}/><circle cx="246" cy="290" r="5" fill="#1c1c1c"/><circle cx="266" cy="290" r="5" fill="#1c1c1c"/>'
    m += mir(circ(296, 248, 15, '#C4281C' if red else YEL, 4) + '<circle cx="294" cy="248" r="6" fill="#1c1c1c"/>')
    m += teeth((236, 262), 318, False, 18)
    return back, m, dict(eye=(296, 248), top=(256, 178), mouth=(256, 330), brow=(256, 210), side=(110, 430), front=True)


def b_squid(c, c2, kind='octo'):
    back = ''
    tent = ''
    for d, w in (('M196,330 Q150,400 100,400 Q70,402 76,440', 26), ('M226,340 Q210,420 170,450', 26), ('M256,346 L256,462', 26)):
        tent += mir(curve(d, c, w)) if 'L256' not in d else curve(d, c, w)
    if kind == 'cuttle':
        back = mir(path('M330,150 Q400,200 372,300 Q350,290 340,250 Z', c2))
        mantle = path('M176,270 Q176,110 256,90 Q336,110 336,270 Z', c)
    elif kind == 'kraken':
        back = mir(path('M300,110 L372,60 L352,150 Z', c2))
        mantle = path('M166,270 Q176,120 256,30 Q336,120 346,270 Z', c)
    else:
        mantle = path('M160,270 Q160,90 256,90 Q352,90 352,270 Z', c)
    m = tent + mantle + f'<ellipse cx="256" cy="282" rx="104" ry="64" {S(c)}/>'
    m += mir(circ(300, 272, 24, '#F4F1EA', 4) + '<rect x="286" y="266" width="28" height="12" rx="5" fill="#1c1c1c"/>')
    m += mir(circ(204, 150, 9, c2, 3) + circ(232, 196, 7, c2, 3))
    return back, m, dict(eye=(300, 272), top=(256, 92 if kind != 'kraken' else 60), mouth=(256, 330), brow=(256, 200), side=(96, 380), front=True)


def b_yeti(c, c2):
    fur = ''.join(circ(256 + 118 * math.cos(math.radians(a)), 262 + 118 * math.sin(math.radians(a)), 44, c) for a in range(0, 360, 30))
    m = circ(256, 452, 34, JOINT) + fur + circ(256, 262, 122, c)
    m += f'<ellipse cx="256" cy="286" rx="82" ry="92" {S(c2)}/>'
    m += mir(circ(288, 256, 14, '#9FE0F5', 4) + '<circle cx="288" cy="256" r="5" fill="#1c1c1c"/>') + f'<path d="M206,226 L246,240 M306,226 L266,240" {LN(dark(c2, .6), 9)}/>'
    m += f'<path d="M216,330 Q256,350 296,330" {LN(dark(c2, .5), 7)}/>' + teeth((218, 276), 334, True, 22)
    return '', m, dict(eye=(288, 256), top=(256, 138), mouth=(256, 336), brow=(256, 200), side=(84, 420), front=True)


def b_golem(c, c2, mud=False, glow='#5FE0E8'):
    m = f'<rect x="96" y="392" width="320" height="94" rx="20" {S(c)}/>' + circ(256, 386, 28, JOINT)
    if mud:
        m += path('M150,280 Q140,150 256,140 Q372,150 362,280 Q370,372 300,362 Q290,392 256,366 Q220,392 206,360 Q142,372 150,280 Z', c)
    else:
        m += f'<rect x="152" y="140" width="208" height="228" rx="24" {S(c)}/><rect x="140" y="188" width="232" height="38" rx="8" {S(c2)}/>'
        m += f'<path d="M180,150 l14,26 l-10,12 M330,300 l-16,22 l10,18" {LN(dark(c), 5)}/>'
    m += mir(f'<rect x="282" y="240" width="40" height="22" rx="5" {S(glow, 4)}/>')
    m += f'<rect x="206" y="304" width="100" height="18" rx="4" fill="{dark(c, .45)}"/>'
    return '', m, dict(eye=(302, 250), top=(256, 142), mouth=(256, 314), brow=(256, 176), side=(70, 420), front=True)


def b_wisp(c, c2, kind='wisp'):
    if kind == 'wisp':
        m = path('M256,70 Q350,210 356,330 Q352,470 256,476 Q160,470 156,330 Q162,210 256,70 Z', c)
        m += f'<path d="M256,190 Q310,280 312,350 Q306,430 256,436 Q206,430 200,350 Q202,280 256,190 Z" fill="#ffffff" opacity=".7"/>'
        m += mir('<ellipse cx="286" cy="340" rx="12" ry="18" fill="#26303a"/>')
        top = (256, 110)
    else:
        m = path('M136,476 L136,260 Q136,100 256,100 Q376,100 376,260 L376,476 L336,440 L296,478 L256,440 L216,478 L176,440 Z', c)
        m += mir('<ellipse cx="298" cy="250" rx="20" ry="28" fill="#26303a"/>')
        m += '<ellipse cx="256" cy="330" rx="22" ry="%d" fill="#26303a"/>' % (44 if kind == 'banshee' else 16)
        top = (256, 104)
    return '', m, dict(eye=(298, 250), top=top, mouth=(256, 340), brow=(256, 180), side=(84, 420), front=True)


def b_gust(c, c2):
    puff = ''.join(circ(256 + 92 * math.cos(math.radians(a)), 240 + 80 * math.sin(math.radians(a)), 50, c) for a in range(0, 360, 40))
    m = path('M190,300 Q230,440 316,484 Q280,410 330,300 Z', c) + puff + circ(256, 240, 96, c)
    m += f'<path d="M210,410 Q250,400 262,430" {LN(dark(c, .7), 6)}/>'
    m += mir('<ellipse cx="290" cy="234" rx="13" ry="18" fill="#26303a"/>') + f'<path d="M226,286 Q256,306 286,286" {LN("#26303a", 7)}/>'
    m += f'<path d="M190,200 Q170,170 196,156 Q220,150 222,174" {LN("#ffffff", 7)}/>'
    return '', m, dict(eye=(290, 234), top=(256, 150), mouth=(256, 296), brow=(256, 190), side=(90, 420), front=True)


def b_frog(c, c2, kind='frog'):
    if kind == 'tadpole':
        back = curve('M330,330 Q430,300 470,380 Q430,360 410,420', c, 30)
        m = circ(250, 330, 110, c) + f'<ellipse cx="250" cy="372" rx="70" ry="44" {S(c2, 4)}/>'
        m += mir(circ(296, 296, 30, '#F4F1EA', 4) + '<circle cx="292" cy="300" r="13" fill="#1c1c1c"/>', 250) + f'<path d="M222,376 Q250,392 278,376" {LN(dark(c, .5), 6)}/>'
        return back, m, dict(eye=(296, 296), top=(250, 222), mouth=(250, 380), brow=(250, 250), side=(90, 430), front=True)
    m = f'<ellipse cx="256" cy="430" rx="120" ry="52" {S(c)}/>' + f'<ellipse cx="256" cy="340" rx="156" ry="104" {S(c)}/>'
    m += f'<ellipse cx="256" cy="396" rx="110" ry="50" {S(c2, 4)}/>'
    m += mir(circ(332, 246, 52, c) + circ(332, 242, 32, '#F6E27A', 4) + '<rect x="314" y="236" width="36" height="13" rx="6" fill="#1c1c1c"/>')
    m += f'<path d="M140,350 Q256,400 372,350" {LN(dark(c, .45), 8)}/><circle cx="240" cy="316" r="5" fill="#1c1c1c"/><circle cx="272" cy="316" r="5" fill="#1c1c1c"/>'
    if kind == 'toad':
        m += ''.join(circ(x, y, r, dark(c, .8), 3) for x, y, r in ((176, 300, 12), (214, 268, 9), (300, 272, 10), (350, 316, 12), (256, 286, 7)))
    return '', m, dict(eye=(332, 242), top=(256, 232), mouth=(256, 372), brow=(256, 280), side=(70, 440), front=True)


# ============ features ============
def f_ember(A, c, c2):
    x, y = A['mouth']
    return '', flame(x + 10, y - 6, -84, 1.7) + circ(x - 130, y - 40, 9, FLAME, 3)


def f_barding(A, c, c2):
    bx, by = A['brow']
    s = path('M312,404 Q384,448 448,372 L462,408 Q390,484 300,438 Z', STEEL) + ''.join(circ(x, y, 7, GOLD, 3) for x, y in ((336, 430), (384, 442), (430, 414)))
    s += path(f'M{bx - 56},{by + 22} Q{bx - 10},{by - 40} {bx + 78},{by - 32} L{bx + 70},{by + 4} Q{bx + 6},{by} {bx - 36},{by + 44} Z', STEEL)
    return '', s


def f_claw(A, c, c2, col=None):
    x, y = A['side']
    col = col or c
    s = ''.join(poly(f'{x - 46 + i * 28},{y - 30} {x - 62 + i * 28},{y - 86} {x - 24 + i * 28},{y - 40}', CREAM, 4) for i in range(3))
    return '', s + f'<ellipse cx="{x}" cy="{y}" rx="56" ry="44" {S(col)}/>' + circ(x + 46, y + 30, 16, JOINT, 4)


def f_paw(A, c, c2):
    return f_claw(A, c, c2)


def f_wing(A, c, c2):
    return path('M380,290 Q410,90 520,50 Q500,120 520,170 Q482,170 488,226 Q452,220 446,280 Z', c2) + f'<path d="M392,280 Q430,150 512,70" {LN(dark(c2), 5)}/>', ''


def f_wave(A, c, c2):
    return '', path('M40,440 Q70,370 130,410 Q170,440 210,410 Q250,384 290,420 Q330,452 372,420 L372,486 L40,486 Z', WATER) + f'<path d="M70,430 Q100,404 130,430 M210,432 Q240,410 270,434" {LN("#ffffff", 6)}/>'


def f_shard(A, c, c2):
    x, y = A['side']
    return '', poly(f'{x - 50},{y + 60} {x - 34},{y - 70} {x - 6},{y + 60}', ICE) + poly(f'{x - 10},{y + 60} {x + 18},{y - 110} {x + 44},{y + 60}', ICE) + poly(f'{x + 36},{y + 60} {x + 62},{y - 40} {x + 80},{y + 60}', ICE)


def f_shell(A, c, c2):
    x, y = A['top']
    return '', path(f'M{x - 70},{y + 40} Q{x - 80},{y - 60} {x},{y - 70} Q{x + 80},{y - 60} {x + 70},{y + 40} Z', '#E8C89A') + f'<path d="M{x - 40},{y + 30} Q{x - 46},{y - 30} {x},{y - 36} Q{x + 40},{y - 30} {x + 30},{y + 6} Q{x + 10},{y + 20} {x},{y}" {LN(dark("#E8C89A", .6), 6)}/>'


def f_anchor(A, c, c2):
    x, y = A['side']
    return '', (f'<g transform="translate({x},{y - 40})">' + f'<circle cy="-70" r="16" {LN(dark(IRON), 14)}/><circle cy="-70" r="16" {LN(IRON, 8)}/>'
                + stick(0, -54, 0, 70, IRON, 12) + stick(-34, -30, 34, -30, IRON, 10) + curve('M-56,30 Q-50,84 0,78 Q50,84 56,30', IRON, 12) + '</g>')


def swirl(x, y, sc=1.0, col='#ffffff'):
    return f'<g transform="translate({x},{y}) scale({sc})">' + curve('M-70,10 Q-20,-40 40,-20 Q76,-4 60,26 Q44,46 22,30 Q12,18 24,8', col, 9) + curve('M-80,50 Q-30,40 0,56', col, 8) + '</g>'


def f_gust(A, c, c2):
    x, y = A['mouth']
    return '', swirl(x - 10, y + 90, 1.2)


def f_wind(A, c, c2):
    x, y = A['top']
    return swirl(x + 120, y - 20, 1.5, '#D6F0F5'), swirl(110, 420, 1.1, '#D6F0F5')


def f_quake(A, c, c2):
    x, y = A['side']
    s = ''.join(poly(' '.join(f'{x + dx + px},{y + dy + py}' for px, py in ((-26, 20), (-30, -14), (-4, -30), (26, -18), (30, 14), (6, 28))), '#8C7A60') for dx, dy in ((-30, 20), (40, 40), (10, -40)))
    return '', s + f'<path d="M{x - 70},{y + 66} l40,-16 l30,14 l44,-12 l40,16" {LN("#3a3028", 6)}/>'


def f_rune(A, c, c2):
    x, y = A['brow']
    return '', f'<path d="M{x - 22},{y + 16} L{x},{y - 22} L{x + 22},{y + 16} M{x - 12},{y} L{x + 12},{y} M{x},{y - 22} L{x},{y + 22}" {LN("#5FE0E8", 9)}/>'


def f_bone(A, c, c2):
    x, y = A['mouth']
    return '', stick(x - 70, y - 10, x + 70, y + 10, CREAM, 16) + ''.join(circ(px, py, 13, CREAM, 4) for px, py in ((x - 76, y - 22), (x - 80, y + 2), (x + 80, y - 2), (x + 76, y + 22)))


def f_fang(A, c, c2):
    x, y = A['mouth']
    if A.get('front'):
        return '', mir(poly(f'{x + 12},{y - 16} {x + 26},{y + 70} {x + 44},{y - 16}', CREAM))
    return '', poly(f'{x + 40},{y - 10} {x + 46},{y + 100} {x + 76},{y - 4}', CREAM) + poly(f'{x + 96},{y} {x + 100},{y + 78} {x + 124},{y + 6}', CREAM)


def f_club(A, c, c2):
    x, y = A['side']
    return '', f'<g transform="translate({x},{y + 50}) rotate(-14)">' + path('M-14,0 L14,0 L34,-190 Q0,-224 -34,-190 Z', BROWN) + ''.join(circ(px, py, 8, IRON, 3) for px, py in ((-12, -170), (14, -150), (-6, -120))) + '</g>'


def f_chain(A, c, c2):
    x, y = A['side']
    return '', ''.join(f'<ellipse cx="{x + i * 26}" cy="{y - 60 + i * 34}" rx="16" ry="24" transform="rotate({35 if i % 2 else -35} {x + i * 26} {y - 60 + i * 34})" {LN(dark(IRON), 16)}/><ellipse cx="{x + i * 26}" cy="{y - 60 + i * 34}" rx="16" ry="24" transform="rotate({35 if i % 2 else -35} {x + i * 26} {y - 60 + i * 34})" {LN(STEEL, 8)}/>' for i in range(4))


def f_lily(A, c, c2):
    return f'<ellipse cx="256" cy="462" rx="214" ry="34" {S("#3F8F4A")}/>', ''.join(path(f'M96,440 Q{96 + dx},{370} 96,350 Q{96 - dx},370 96,440 Z', '#F2A6C4', 4) for dx in (44, 16)) + circ(96, 432, 10, YEL, 3)


def f_mushroom(A, c, c2):
    return '', f'<rect x="76" y="380" width="36" height="76" rx="12" {S(CREAM)}/>' + path('M26,392 Q30,306 94,306 Q158,306 162,392 Z', '#C4281C') + ''.join(circ(x, y, r, '#ffffff', 3) for x, y, r in ((70, 350, 12), (112, 340, 9), (128, 372, 10)))


def f_horns(A, c, c2):
    x, y = A['top']
    if A.get('front'):
        return '', mir(path(f'M{x + 50},{y + 30} Q{x + 150},{y + 10} {x + 150},{y - 100} Q{x + 110},{y - 30} {x + 30},{y + 4} Z', CREAM))
    return path(f'M{x + 20},{y + 16} q30,-96 124,-110 q-46,50 -44,124 Z', dark(CREAM, .82)), path(f'M{x - 30},{y + 14} q14,-104 116,-126 q-50,60 -44,134 Z', CREAM)


def f_devil(A, c, c2):
    x, y = A['top']
    col = '#C4281C'
    if A.get('front'):
        return '', mir(path(f'M{x + 40},{y + 30} Q{x + 100},{y - 10} {x + 70},{y - 90} Q{x + 60},{y - 30} {x + 16},{y + 4} Z', col))
    return path(f'M{x + 26},{y + 16} q-10,-70 50,-104 q-10,56 18,96 Z', dark(col, .8)), path(f'M{x - 36},{y + 14} q-24,-78 34,-118 q-8,62 30,104 Z', col)


def f_icecrest(A, c, c2):
    x, y = A['top']
    if A.get('front'):
        return '', poly(f'{x - 70},{y + 30} {x - 50},{y - 60} {x - 20},{y + 16}', ICE) + poly(f'{x - 26},{y + 16} {x},{y - 110} {x + 26},{y + 16}', ICE) + poly(f'{x + 20},{y + 16} {x + 50},{y - 60} {x + 70},{y + 30}', ICE)
    return '', poly(f'{x - 60},{y + 22} {x - 40},{y - 70} {x - 10},{y + 10}', ICE) + poly(f'{x - 14},{y + 10} {x + 24},{y - 110} {x + 40},{y + 14}', ICE) + poly(f'{x + 34},{y + 16} {x + 84},{y - 50} {x + 76},{y + 44}', ICE)


def f_spikehelm(A, c, c2):
    x, y = A['top']
    if A.get('front'):
        return '', poly(f'{x - 16},{y - 20} {x},{y - 90} {x + 16},{y - 20}', STEEL) + path(f'M{x - 96},{y + 50} Q{x - 90},{y - 26} {x},{y - 28} Q{x + 90},{y - 26} {x + 96},{y + 50} Z', STEEL) + f'<rect x="{x - 104}" y="{y + 40}" width="208" height="18" rx="6" {S(STEEL, 4)}/>'
    return '', poly(f'{x - 16},{y - 14} {x + 6},{y - 90} {x + 24},{y - 14}', STEEL) + path(f'M{x - 86},{y + 46} Q{x - 70},{y - 24} {x + 4},{y - 22} Q{x + 66},{y - 18} {x + 76},{y + 56} Z', STEEL) + path(f'M{x - 98},{y + 40} L{x + 84},{y + 48} L{x + 82},{y + 68} L{x - 100},{y + 60} Z', STEEL, 4)


def f_crown(A, c, c2):
    x, y = A['top']
    r = 0 if A.get('front') else -10
    return '', f'<g transform="translate({x},{y + 14}) rotate({r})">' + poly('-62,0 -62,-70 -30,-32 0,-84 30,-32 62,-70 62,0', GOLD) + ''.join(circ(px, -12, 8, cc, 3) for px, cc in ((-34, '#C4281C'), (0, '#3E7FC4'), (34, '#C4281C'))) + '</g>'


def f_fin(A, c, c2):
    x, y = A['top']
    return path(f'M{x - 60},{y + 30} L{x - 30},{y - 96} L{x + 10},{y - 20} L{x + 50},{y - 80} L{x + 70},{y + 10} L{x + 120},{y - 20} L{x + 96},{y + 90} Z', c2), ''


def f_kettle(A, c, c2):
    x, y = A['top']
    return '', path(f'M{x - 86},{y + 50} Q{x - 86},{y - 46} {x},{y - 46} Q{x + 86},{y - 46} {x + 86},{y + 50} Z', STEEL) + f'<ellipse cx="{x}" cy="{y + 50}" rx="136" ry="26" {S(STEEL)}/>'


def f_plume(A, c, c2):
    x, y = A['top']
    return '', path(f'M{x - 10},{y + 10} Q{x - 40},{y - 110} {x + 70},{y - 130} Q{x + 30},{y - 70} {x + 40},{y + 16} Z', '#C4281C') + path(f'M{x - 70},{y + 44} L{x + 60},{y + 30} L{x + 64},{y + 56} L{x - 72},{y + 70} Z', STEEL, 4)


def f_headdress(A, c, c2):
    x, y = A['top']
    cols = ('#C4281C', YEL, '#3E7FC4', YEL, '#C4281C')
    return ''.join(f'<g transform="translate({x},{y + 20}) rotate({a})">' + path('M-18,0 Q-26,-90 0,-140 Q26,-90 18,0 Z', cc) + '</g>' for a, cc in zip((-60, -30, 0, 30, 60), cols)), f'<rect x="{x - 90}" y="{y + 4}" width="180" height="22" rx="8" {S(CREAM, 4)}/>'


def f_flame(A, c, c2):
    x, y = A['top']
    return ''.join(flame(x + dx, y + 60, r, sc) for dx, r, sc in ((-70, -18, 1.9), (10, 0, 2.6), (90, 18, 1.9))), ''


def f_snow(A, c, c2):
    x, y = (A['top'][0] + (0 if A.get('front') else 110), A['top'][1] - 20)
    s = ''
    for a in range(0, 180, 60):
        s += f'<g transform="translate({x},{y}) rotate({a})">' + stick(0, -80, 0, 80, '#E6F6FC', 10) + f'<path d="M-18,-66 L0,-48 L18,-66 M-18,66 L0,48 L18,66" {LN("#7FB6D6", 6)}/>' + '</g>'
    return s, ''


def f_sun(A, c, c2):
    x, y = (A['top'][0] + (0 if A.get('front') else 40), A['top'][1] + 60)
    r = ''.join(f'<polygon points="-16,-150 0,-196 16,-150" transform="translate({x},{y}) rotate({a})" {S(GOLD, 4)}/>' for a in range(-120, 121, 30))
    return r + circ(x, y, 142, '#F2CF55'), ''


def f_moon(A, c, c2):
    x, y = (A['top'][0] + (0 if A.get('front') else 60), A['top'][1] + 40)
    return path(f'M{x + 30},{y - 170} A150 150 0 1 0 {x + 150},{y + 60} A120 120 0 1 1 {x + 30},{y - 170} Z', '#EFE7B8') if False else circ(x, y, 150, '#EFE7B8') + circ(x - 50, y - 40, 22, '#D8CE98', 3) + circ(x + 60, y - 70, 14, '#D8CE98', 3), ''


def drop(x, y, sc=1.0):
    return f'<g transform="translate({x},{y}) scale({sc})">' + path('M0,-40 Q30,6 22,24 Q0,48 -22,24 Q-30,6 0,-40 Z', '#5FB4EA', 4) + '</g>'


def f_drop(A, c, c2):
    x, y = A['top']
    return '', drop(x - 130, y + 20, 1.2) + drop(x - 80, y - 60, .9) + drop(84, 400, 1.3)


def f_sabre(A, c, c2):
    x, y = A['mouth']
    return '', path(f'M{x + 6},{y - 14} Q{x + 2},{y + 90} {x - 20},{y + 140} Q{x + 40},{y + 90} {x + 44},{y - 10} Z', CREAM) + path(f'M{x + 64},{y - 4} Q{x + 62},{y + 70} {x + 48},{y + 110} Q{x + 92},{y + 70} {x + 96},{y} Z', dark(CREAM, .85))


def bolt(x, y, sc=1.0, rot=0):
    return f'<g transform="translate({x},{y}) rotate({rot}) scale({sc})">' + poly('10,-70 -30,0 -6,0 -18,60 34,-20 8,-20 26,-70', YEL, 4) + '</g>'


def f_bolt(A, c, c2):
    x, y = A['top']
    return bolt(x + 120, y - 10, 1.6, 20) + bolt(x - 120, y - 10, 1.6, -20), bolt(90, 410, 1.1, -10)


def f_mountain(A, c, c2):
    x, y = (A['top'][0], A['top'][1] + 110)
    return poly(f'{x - 220},{y} {x - 110},{y - 200} {x - 40},{y - 110} {x + 30},{y - 250} {x + 120},{y - 120} {x + 150},{y - 160} {x + 230},{y}', '#7E8790') + poly(f'{x},{y - 196} {x + 30},{y - 250} {x + 62},{y - 204} {x + 30},{y - 180}', '#F4F6F8', 4), ''


def f_eye(A, c, c2):
    x, y = A['eye']
    r = ''.join(f'<line x1="{x + 44 * math.cos(math.radians(a)):.0f}" y1="{y + 44 * math.sin(math.radians(a)):.0f}" x2="{x + 76 * math.cos(math.radians(a)):.0f}" y2="{y + 76 * math.sin(math.radians(a)):.0f}" {LN(YEL, 9)}/>' for a in range(170, 351, 30))
    return '', r + circ(x, y, 36, YEL) + f'<ellipse cx="{x}" cy="{y}" rx="9" ry="28" fill="#1c1c1c"/>'


def f_trident(A, c, c2):
    x, y = A['side']
    return '', f'<g transform="translate({x},{y + 60}) rotate(-8)">' + stick(0, 0, 0, -240, GOLD, 10) + curve('M-40,-330 L-40,-262 Q0,-236 40,-262 L40,-330 M0,-340 L0,-240', GOLD, 9) + '</g>'


def f_star(A, c, c2):
    x, y = A['top']
    return '', star(x, y - 150, 44)


def f_spiral(A, c, c2):
    return '', '<g transform="translate(96,440)">' + stick(0, 30, 0, -150, BROWN, 9) + staff_top('spiral', None, -150).replace('stroke-width="12"', 'stroke-width="14"') + '</g>'


def f_scream(A, c, c2):
    x, y = A['mouth']
    return '', ''.join(f'<path d="M{x - r},{y + 40 + r * .5} Q{x},{y + 80 + r} {x + r},{y + 40 + r * .5}" {LN("#26303a", 8)}/>' for r in (50, 86))


FEAT = {k[2:]: v for k, v in globals().items() if k.startswith('f_')}
FEAT['fang_crest'] = f_sabre

# ============ monster table ============
# base: (builder, kwargs, class head scale)
BASES = {
    'dragon': b_lizard, 'lizard': b_lizard, 'wolf': b_wolf, 'cat': b_cat, 'lion': b_cat, 'goat': b_goat, 'bison': b_bison,
    'bird': b_bird, 'rat': b_rat, 'bat': b_bat, 'squid': b_squid, 'yeti': b_yeti, 'golem': b_golem, 'wisp': b_wisp,
    'gustling': b_gust, 'tadpole': b_frog,
}
COL = {
    'Drakeling': ('#6FB36A', '#E8D88A'), 'Wyrm': ('#4E9C5E', '#E8D88A'), 'Dragon': ('#3A8656', '#E8D88A'), 'Red Dragon': ('#C0392B', '#F0B24A'),
    'Blue Dragon': ('#3E7FC4', '#BFE6F5'), 'Silver Dragon': ('#B8C2CC', '#F2CF55'), 'Black Dragon': ('#3A3742', '#8E5AA8'),
    'Serpent': ('#2F9AA8', '#9FE0D8'), 'Sea Dragon': ('#267F9A', '#9FE0D8'), 'Leviathan': ('#1F5F8A', '#7FD0E0'),
    'Snow Snake': ('#9CC9E0', '#5F8FB8'), 'Snow Serpent': ('#86BBD8', '#5F8FB8'), 'Kuraokami': ('#D4EAF4', '#4F7FB0'),
    'Wolf': ('#8A8F98', '#C9CED3'), 'Ember Wolf': ('#A8553A', '#E0A070'), 'Hellhound': ('#7A2A22', '#C0503A'), 'Hellmaw': ('#3A2A2E', '#C0392B'),
    'Wolfhound': ('#8A6A48', '#C9A878'), 'Arctic Wolf': ('#A9BFD0', '#E4EEF4'), 'Winter Wolf': ('#DCE8F0', '#8FB0CC'),
    'Bobcat': ('#C9A15A', '#EAD6A8'), 'Hell Cat': ('#B5532E', '#E0A070'), 'Shadow Cat': ('#4A4458', '#8E86A0'), 'Sabretooth': ('#8A5A3A', '#C9A878'),
    'Prowler': ('#B98A4A', '#EAD6A8'), 'War Cat': ('#A87A3E', '#EAD6A8'), 'White Tiger': ('#EDEDE6', '#D9788A'),
    'Cuttlefish': ('#D98A6A', '#F2C0A0'), 'Octopus': ('#C4547A', '#E8A0B8'), 'Battle Octopus': ('#C4547A', '#E8A0B8'), 'Octolord': ('#8E3F8A', '#D090C8'),
    'Kraken': ('#3F6FA0', '#8FB8E0'), 'Electro Kraken': ('#3A5FA8', '#F2E05A'), 'Abyssal Kraken': ('#2A3560', '#F2E05A'),
    'War Bird': ('#8A5E34', '#A8764A'), 'Gryphon': ('#B5823E', '#F2EEE4'), 'Royal Gryphon': ('#B5823E', '#F2EEE4'), 'Sphinx': ('#D9B45A', '#F2DFA0'),
    'Stormhawk': ('#6F86A0', '#A9BCD0'), 'Roc': ('#55657F', '#8FA2BC'), 'Storm Roc': ('#3F4A66', '#7F8FB0'),
    'Bigfoot': ('#7A5A3A', '#4E3A2A'), 'Yeti': ('#A9BCC9', '#51627A'), 'Sasquatch': ('#9FB6C6', '#51627A'), 'Abominable': ('#C9DCE6', '#3F5068'),
    'Goat': ('#D8CDB4', '#B8A888'), 'Battle Goat': ('#D8CDB4', '#B8A888'), 'Battle Ram': ('#B8A888', '#8A7A5E'), 'Chupacabra': ('#6E5A66', '#3A2E36'),
    'Bison': ('#7A563A', '#5A3E28'), 'Battle Bison': ('#7A563A', '#5A3E28'), 'Battle Buffalo': ('#6A4A32', '#4A3222'), 'Earthshaker': ('#5A4636', '#3A2C22'),
    'Lion Cub': ('#DDB565', '#F2DCA8'), 'Lion': ('#D9B060', '#F2DCA8'), 'Pride Lion': ('#D9B060', '#F2DCA8'), 'Golden Lion': ('#EBC548', '#FFF0B0'),
    'Salamander': ('#E08A2A', '#F2C06A'), 'Cinder Lizard': ('#C8502A', '#F2A06A'), 'Magma Lizard': ('#8A2E22', '#E0702A'), 'Basilisk': ('#4B5048', '#E0702A'),
    'Mudling': ('#8A6A4A', '#6A4E36'), 'Stoneguard': ('#9399A0', '#70767E'), 'Monolith': ('#80868E', '#5E646C'), 'Colossus': ('#B8964E', '#8A6E36'),
    'Rat': ('#8E7E72', '#B8A89C'), 'Giant Rat': ('#8E7E72', '#B8A89C'), 'Rat Pack': ('#7E6E64', '#A8988C'), 'Rat King': ('#6A5A52', '#98887C'),
    'Bat': ('#6E5878', '#A890B0'), 'Bat Swarm': ('#6E5878', '#A890B0'), 'Vampire Bats': ('#584466', '#9880A8'), 'Night Terror': ('#3A2E48', '#7A6A90'),
    'Wisp': ('#BFE9F5', '#ffffff'), 'Ghost': ('#EEF2F0', '#ffffff'), 'Spectre': ('#D4E4E8', '#ffffff'), 'Banshee': ('#9FD0C8', '#ffffff'),
    'Tadpole': ('#4A6A7A', '#8FB0BC'), 'Frog': ('#6FAE4A', '#E8E08A'), 'Frog Boy': ('#6FAE4A', '#E8E08A'), 'Frog Man': ('#5E9E3E', '#E8E08A'),
    'Toad': ('#9A7A4A', '#D8C08A'), 'Toad Boy': ('#9A7A4A', '#D8C08A'), 'Toad Shaman': ('#8A6A3E', '#D8C08A'),
    'Gustling': ('#BFE0EA', '#ffffff'), 'Zephyr': ('#9FD0E0', '#ffffff'), 'Djinn': ('#5FA8D0', '#ffffff'),
}
KW = {
    'Drakeling': {}, 'dragon': dict(frill=True), 'lion': {}, 'Lion Cub': {},
    'Cuttlefish': dict(kind='cuttle'), 'Kraken': dict(kind='kraken'), 'Electro Kraken': dict(kind='kraken'), 'Abyssal Kraken': dict(kind='kraken'),
    'Mudling': dict(mud=True, glow='#F2E05A'), 'Colossus': dict(glow='#F2A03A'),
    'Wisp': dict(kind='wisp'), 'Ghost': dict(kind='ghost'), 'Spectre': dict(kind='ghost'), 'Banshee': dict(kind='banshee'),
    'Tadpole': dict(kind='tadpole'), 'Toad': dict(kind='toad'), 'Toad Boy': dict(kind='toad'), 'Toad Shaman': dict(kind='toad'),
    'White Tiger': dict(stripes=True), 'Rat King': dict(red=True), 'Night Terror': dict(red=True), 'Vampire Bats': dict(red=True),
    'Lion': dict(mane='#8A5226'), 'Pride Lion': dict(mane='#8A5226'), 'Golden Lion': dict(mane='#C8862A'),
}
SIZE_SCALE = {'Large': 1.0, 'Small': 0.8, 'Tiny': 0.62}


def turban_big(A, c, c2, col=PUR):
    x, y = A['top']
    return '', path(f'M{x},{y - 20} Q{x + 30},{y - 110} {x + 80},{y - 100} Q{x + 60},{y - 50} {x + 30},{y - 10} Z', CREAM, 4) + f'<ellipse cx="{x}" cy="{y + 20}" rx="120" ry="70" {S(col)}/>' + f'<path d="M{x - 100},{y + 40} Q{x},{y - 40} {x + 100},{y + 40}" {LN(dark(col, .7), 5)}/>' + circ(x, y + 10, 18, GOLD, 4)


def monster(name, base, hand, head, crest):
    c, c2 = COL[name]
    kw = dict(KW.get(name, KW.get(base, {}) if name != 'Drakeling' else {}))
    back, main, A = BASES[base](c, c2, **kw)
    feats = []
    for v in (hand, head, crest):
        if v and v not in ('pack',):
            feats.append(v)
    b2 = f2 = ''
    for i, v in enumerate(feats):
        if v == 'turban':
            fb, ff = turban_big(A, c, c2)
        elif v == 'fang' and v == crest and v != hand:
            fb, ff = f_sabre(A, c, c2)
        elif v == 'crown' and name == 'Frog Man':
            fb, ff = f_crown(A, c, c2)
        else:
            fb, ff = FEAT[v](A, c, c2)
        b2 += fb; f2 += ff
    one = back + main
    if head == 'pack':
        dkb, dkm, _ = BASES[base](dark(c, .8), dark(c2, .8), **kw)
        if A.get('front'):
            one = f'<g transform="translate(-150,-50) scale(.8)">{dkb + dkm}</g><g transform="translate(250,-50) scale(.8)">{dkb + dkm}</g>' + one
        else:
            one = f'<g transform="translate(150,-120) scale(.8)">{dkb + dkm}</g><g transform="translate(190,60) scale(.8)">{dkb + dkm}</g>' + one
    return b2 + one + f2


# ============ folk (full mannequin figures) ============
def ears(kind):
    e = '<polygon points="26,56 66,30 32,80" %s/>' % S(WOOD, 4) if kind == 'elf' else '<polygon points="24,54 92,40 32,84" %s/>' % S(WOOD, 4)
    return e + f'<g transform="scale(-1,1)">{e}</g>'


def wings_feather(c='#F7F4EC', big=1.0):
    w = path('M30,130 Q120,-30 220,20 Q196,60 210,100 Q176,104 186,150 Q150,150 156,200 Q110,196 60,240 Z', c) + f'<path d="M60,150 Q130,60 200,40 M80,190 Q140,120 190,110" {LN(dark(c, .7), 4)}/>'
    return f'<g transform="scale({big})">' + w + f'<g transform="scale(-1,1)">{w}</g></g>'


def wings_bat(c='#5A1F22', big=1.0):
    w = path('M30,140 Q120,10 210,30 Q194,76 216,110 Q180,112 186,160 Q150,156 150,204 Q110,190 50,220 Z', c) + f'<path d="M40,150 Q120,70 200,44" {LN(dark(c, .6), 4)}/>'
    return f'<g transform="translate(0,20) scale({big})">' + w + f'<g transform="scale(-1,1)">{w}</g></g>'


def wings_fly(big=1.0):
    w = f'<ellipse cx="110" cy="110" rx="100" ry="36" transform="rotate(-28 110 110)" {S("#DFF3F8", 4)}/><ellipse cx="100" cy="190" rx="80" ry="28" transform="rotate(16 100 190)" {S("#DFF3F8", 4)}/>'
    return f'<g transform="scale({big})">' + w + f'<g transform="scale(-1,1)">{w}</g></g>'


def halo():
    return f'<ellipse cx="0" cy="6" rx="44" ry="12" {LN(dark(GOLD, .6), 13)}/><ellipse cx="0" cy="6" rx="44" ry="12" {LN(GOLD, 7)}/>'


def fishtail(c):
    return (path('M-40,196 L40,196 Q70,300 20,356 Q-10,392 -70,396 L-134,440 L-118,372 L-170,340 Q-70,356 -44,290 Z', c)
            + f'<path d="M-24,240 q20,14 44,0 M-10,290 q20,14 40,-4 M-30,340 q20,12 40,-8" {LN(dark(c, .7), 5)}/>')


def eagle(c, crown=False):
    o = path('M40,300 Q120,84 252,76 Q216,148 230,198 Q192,204 202,258 Q162,262 150,318 Z', dark(c, .75))
    o += poly('100,326 226,346 220,388 104,374', dark(c, .7))
    o += stick(-30, 380, -38, 428, GOLD, 12) + stick(46, 380, 42, 428, GOLD, 12) + ''.join(poly(f'{x - 22},{444} {x - 2},{424} {x + 22},{444}', GOLD, 4) for x in (-38, 42))
    o += f'<ellipse cx="0" cy="330" rx="125" ry="58" {S(c)}/>'
    o += path('M20,312 Q130,146 264,168 Q228,220 238,262 Q198,262 202,310 Q150,312 130,352 Z', c)
    o += f'<ellipse cx="-108" cy="312" rx="42" ry="48" {S("#F2EEE4")}/>' + circ(-140, 290, 46, '#F2EEE4')
    o += path('M-176,276 L-236,296 Q-254,320 -232,338 Q-226,314 -196,318 L-170,318 Z', GOLD)
    o += f'<circle cx="-152" cy="280" r="8" fill="#1c1c1c"/><path d="M-170,264 L-132,262" {LN("#8a8478", 6)}/>'
    if crown:
        o += '<g transform="translate(-136,250) rotate(-10) scale(.6)">' + poly('-62,0 -62,-70 -30,-32 0,-84 30,-32 62,-70 62,0', GOLD) + '</g>'
    return o


def pick():
    return stick(0, 44, 0, -100, BROWN, 9) + curve('M-58,-78 Q0,-128 58,-78', STEEL, 12)


def clubw():
    return path('M-9,30 L9,30 L26,-110 Q0,-136 -26,-110 Z', BROWN) + ''.join(circ(px, py, 6, IRON, 3) for px, py in ((-8, -96), (10, -80), (-4, -60)))


def glow(c='#FFF2A0'):
    return circ(0, -30, 20, c, 4) + ''.join(f'<line x1="0" y1="-60" x2="0" y2="-74" transform="rotate({a} 0 -30)" {LN(dark(c, .7), 5)}/>' for a in range(0, 360, 45))


def H_icecrest(c):
    return '', poly('-26,48 -18,-2 -4,40', ICE) + poly('-10,40 0,-26 12,40', ICE) + poly('6,42 20,2 28,50', ICE)


def H_gnomecap(c):
    return '', poly('-28,56 6,-44 28,56', '#C4281C') + f'<ellipse cx="0" cy="56" rx="32" ry="8" {S("#C4281C")}/>'


def H_spikehelm(c):
    return '', poly('-7,34 0,0 7,34', STEEL) + DOME(STEEL) + f'<rect x="-30" y="54" width="60" height="10" rx="4" {S(STEEL, 4)}/>'


def H_halo(c):
    return '', halo()


def H_antennae(c):
    a = f'<path d="M10,40 Q20,6 40,-2" {LN(dark(c), 5)}/>' + circ(42, -4, 7, YEL, 3)
    return '', a + f'<g transform="scale(-1,1)">{a}</g>'


def H_devil(c):
    h = path('M12,42 Q16,10 44,-2 Q36,24 30,48 Z', '#2E2B33')
    return '', h + f'<g transform="scale(-1,1)">{h}</g>'


def H_crown(c):
    return '', '<g transform="translate(0,48) scale(.5)">' + poly('-62,0 -62,-70 -30,-32 0,-84 30,-32 62,-70 62,0', GOLD) + '</g>'


def H_hair(c, hair='#E8D27A'):
    return gen.H_circlet(c, hair)[0], ''


for k, v in list(globals().items()):
    if k.startswith('H_'):
        gen.HEADS[k[2:]] = v

ELF = '#3F9C8C'; TROLL = '#7FA6B8'; GOB = '#86AE4E'; IMP = '#C8452F'; GNO = '#3E6FA3'; MER = '#2F9C9A'; ANG = '#DCEBF5'; SPR = '#A6D65A'; CEN = '#E6DCC6'; EAG = '#3F8C8A'


def tusks():
    return poly('-16,92 -10,70 -4,92', CREAM, 3) + poly('4,92 10,70 16,92', CREAM, 3) + circ(0, 74, 9, TROLL, 3)


def beard():
    return poly('-22,84 22,84 14,128 0,146 -14,128', '#F4F1EA', 4)


def FOLK():
    F = {}
    e = ears('elf')
    F['Elfling'] = dict(mantle=ELF, head='hair', front=e, R=(glow('#BFF5E0'), 0), rp='palm', fs=.44, w='ward light')
    F['Elf Squire'] = dict(mantle=ELF, head='hair', front=e, R=(bow(), 0), rp='fwd', legs='brace', w='bow')
    F['Elf'] = dict(g='tabard', c=ELF, head='hood', front=e, R=(bow(), 0), rp='fwd', legs='brace', boots=LEA, w='bow')
    F['Royal Elf'] = dict(g='tabard', c=ELF, head='hood', front=e, R=(bow(), 0), rp='fwd', legs='brace', boots=LEA, back=[quiver(), cape('#F2EEE4')], emb=e_leaf(), w='bow')
    t = dict(g='kilt', c=FUR, skin=TROLL, wide=1.2, front=tusks())
    F['Trollkin'] = dict(fs=.42, legs='stand', lp='down', rp='down', w='-', **t)
    F['Trollboy'] = dict(fs=.45, R=(clubw(), -25), legs='stride', w='club', **t)
    F['Troll'] = dict(fs=.48, R=(clubw(), -25), legs='stride', head='icecrest', w='club', **t)
    F['Big Troll'] = dict(fs=.5, R=(f'<g transform="scale(1.3)">{clubw()}</g>', -25), legs='brace', head='icecrest', back=[cape('#DCEBF5')], w='club', **{**t, 'c': '#C9DCE6'})
    F['Gnomeboy'] = dict(fs=.38, mantle=GNO, legs='stand', rp='down', lp='down', w='-')
    F['Gnome'] = dict(fs=.4, mantle=GNO, front=beard(), R=(pick(), -25), legs='stride', w='pick')
    F['Master Gnome'] = dict(fs=.4, g='tabard', c=GNO, head='gnomecap', front=beard(), R=(pick(), -25), legs='stride', boots=LEA, w='pick')
    F['Mountaineer'] = dict(fs=.42, g='tabard', c=GNO, head='gnomecap', front=beard(), R=(f'<g transform="scale(1.25)">{pick()}</g>', -25), legs='brace', boots=LEA, back=[cape('#7E8790')], L=(staff('rock', None, 150, 60), 8), lp='out', w='pick + stone staff')
    g = dict(skin=GOB, front=ears('gob'), fs=.42)
    F['Goblin'] = dict(mantle='#6B4A6E', legs='stand', rp='down', lp='down', w='-', **g)
    F['Nobgoblin'] = dict(mantle='#6B4A6E', R=(dagger(), -70), rp='fwd', legs='lunge', w='dagger', **g)
    F['Hobgoblin'] = dict(g='tabard', c='#6B4A6E', head='spikehelm', R=(dagger(), -70), rp='fwd', legs='lunge', boots=LEA, w='dagger', **g)
    F['Bobgoblin'] = dict(g='tabard', c='#6B4A6E', head='spikehelm', R=(dagger(), -70), rp='fwd', L=(coinbag(), 0), lp='out', legs='lunge', boots=LEA, w='dagger + coin bag', **{**g, 'fs': .45})
    F['Angel'] = dict(g='robe', c=ANG, head='hair', back=[wings_feather()], R=(glow(), 0), rp='palm', w='light')
    F['Archangel'] = dict(g='robe', c=ANG, head='hair', back=[wings_feather()], front=halo(), R=(glow(), 0), rp='palm', trim=GOLD, w='light')
    F['Seraphim'] = dict(g='robe', c=ANG, head='hair', back=[f'<g transform="translate(0,90)">{wings_feather("#F2DFA0", .8)}</g>', wings_feather()], front=halo(), R=(staff('star', None, 150, 60), 0), rp='plant', L=(glow(), 0), lp='out', w='star staff')
    i = dict(skin=IMP, g='kilt', c=BLK)
    F['Imp'] = dict(fs=.4, back=[wings_bat()], R=(flame(0, -20, 0, .9), 0), rp='palm', w='flame', **i)
    F['Demon'] = dict(fs=.45, back=[wings_bat()], head='devil', R=(flame(0, -20, 0, 1.1), 0), rp='palm', w='flame', **i)
    F['Archdemon'] = dict(fs=.5, back=[wings_bat('#3A1418', 1.08), cape('#3A1418')], head='devil', R=(flame(0, -20, 0, 1.3), 0), rp='palm', L=(flame(0, -20, 0, 1.3), 0), lp='up', w='flames', **i)
    m = dict(g='none', nolegs=True, belt=False, base=440, emb=path('M-44,112 L44,112 L36,170 Q0,182 -36,170 Z', '#E58F6A'))
    F['Mermaid'] = dict(lower=fishtail(MER), head='hair', hkw=dict(hair='#2F6F8A'), R=(spear(120, 70), -30), rp='up', w='harpoon', **m)
    F['Siren'] = dict(lower=fishtail(MER), head='circlet', hkw=dict(hair='#2F6F8A'), hc='#5FB4EA', R=(spear(120, 70), -30), rp='up', L=(lyre(), 0), lp='out', w='harpoon + lyre', **m)
    F['Naiad'] = dict(lower=fishtail('#2A7FB0'), head='circlet', hkw=dict(hair='#1F4F7A'), hc='#5FB4EA', R=(f'<g transform="translate(0,-60)">{stick(0, 180, 0, 0, GOLD, 9)}{curve("M-34,-78 L-34,-22 Q0,0 34,-22 L34,-78 M0,-86 L0,0", GOLD, 8)}</g>', -20), rp='fwd', L=(drop(0, -40, 1.6), 0), lp='out', w='trident + water', **m)
    s = dict(fs=.36, mantle=SPR)
    F['Sprite'] = dict(back=[wings_fly()], R=(wand('star'), -20), rp='up', w='star wand', **s)
    F['Faerie'] = dict(back=[wings_fly(1.15)], head='antennae', R=(wand('star'), -20), rp='up', w='star wand', **{**s, 'fs': .38})
    F['Faerie Queen'] = dict(back=[wings_fly(1.3)], head='crown', R=(wand('star'), -20), rp='up', g='robe', c=SPR, trim=GOLD, w='star wand', **{k: v for k, v in s.items() if k != 'mantle'}, **{'fs': .4} if False else {})
    F['Faerie Queen']['fs'] = .4
    cen = dict(nolegs=True, base=477, fs=.46, g='tabard')
    for n, col, hd, extra in (('Centaur', '#8A5A30', None, {}), ('Spiritaur', '#8A5A30', 'laurel', {}), ('Deitaur', '#DDD6C6', 'laurel', dict(emb=e_sun(), back=[]))):
        F[n] = dict(c=CEN, lower=f'<g transform="translate(95,0)">{horse(col, None, False)}</g>', R=(rod() if n != 'Deitaur' else staff('sun', GOLD, 150, 70), -12), rp='up', w='rod' if n != 'Deitaur' else 'sun staff', **cen, **extra)
        if hd: F[n]['head'] = hd
    for n, g, hd, ec, ex in (('Eagle Rider', 'tabard', None, '#8A5E34', {}), ('Eagle Knight', 'plate', 'greathelm', '#8A5E34', {}), ('Eagle Lord', 'plate', 'greathelm', '#C8962E', dict(hkw=dict(band=GOLD), back=[cape(EAG)]))):
        F[n] = dict(g=g, c=EAG, nolegs=True, base=446, fs=.46, lower=eagle(ec, n == 'Eagle Lord') + rider_leg(LEA), R=(spear(150, 132), -38), rp='fwd', boots=LEA, w='spear', **ex)
        if hd: F[n]['head'] = hd
    return F


FOLK_BASES = {'elf', 'troll', 'gnome', 'goblin', 'angel', 'imp', 'mermaid', 'sprite', 'centaur', 'eaglerider'}


def render_fit(inner, size_class):
    """Fit a monster head: bottom on baseline 244, bbox-centred, scaled by size class."""
    from PIL import Image
    probe = f'<svg xmlns="http://www.w3.org/2000/svg" width="700" height="700" viewBox="-400 -400 1400 1400">{inner}</svg>'
    png = subprocess.run(['rsvg-convert'], input=probe.encode(), capture_output=True, check=True).stdout
    b = Image.open(io.BytesIO(png)).getchannel('A').getbbox()
    l, t, r, bt = [v * 2 - 400 for v in b]
    sc = min(232 / (r - l), 232 / (bt - t)) * SIZE_SCALE[size_class]
    tx = 128 - (l + r) / 2 * sc; ty = 244 - bt * sc
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256"><g transform="translate({tx:.1f},{ty:.1f}) scale({sc:.4f})">{inner}</g></svg>'


def main():
    import openpyxl
    from PIL import Image, ImageDraw, ImageFont
    xlsx, out = sys.argv[1], sys.argv[2]
    ws = openpyxl.load_workbook(xlsx, data_only=True)['Units']
    rows = list(ws.iter_rows(values_only=True)); ix = {n: i for i, n in enumerate(rows[0])}
    units = [r for r in rows[1:] if r[0] and r[ix['Icon base']] != 'human']
    F = FOLK()
    os.makedirs(f'{out}/png', exist_ok=True); os.makedirs(f'{out}/svg', exist_ok=True)
    notes = []
    for r in units:
        n, base, st = r[0], r[ix['Icon base']], r[ix['Stage']]
        hand_, head_, crest_ = r[ix['Icon hand']], r[ix['Icon head']], r[ix['Icon crest']]
        if base in FOLK_BASES:
            u = F[n]; u['stage'] = st
            if 'dxfig' in u:
                u['feetcentre'] = True
            fit = gen.autofit(u)
            if 'dxfig' in u:
                u['dx'] = round(u['dxfig'] * u.get('fs', .5))
            s = gen.svg(u)
            notes.append((n, st, 'figure', hand_, u['w']))
        else:
            s = render_fit(monster(n, base, hand_, head_, crest_), r[ix['Size']])
            notes.append((n, st, 'head', hand_, ', '.join(v for v in (hand_, head_, crest_) if v) or '-'))
        p = f'{out}/svg/{gen.fname(n)}.svg'
        open(p, 'w').write(s)
        subprocess.run(['rsvg-convert', '-w', '256', '-h', '256', p, '-o', f'{out}/png/{gen.fname(n)}.png'], check=True)
        b = Image.open(f'{out}/png/{gen.fname(n)}.png').getchannel('A').getbbox()
        if b[0] < 3 or b[2] > 253 or b[1] < 3 or b[3] > 247: print('OVER', n, b)
    cols = 11; cw, ch = 136, 180
    nrow = math.ceil(len(units) / cols)
    sheet = Image.new('RGB', (cols * cw, nrow * ch), '#E9E2D2'); d = ImageDraw.Draw(sheet)
    f = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', 12)
    for i, r in enumerate(units):
        n = r[0]; im = Image.open(f'{out}/png/{gen.fname(n)}.png').convert('RGBA')
        x, y = (i % cols) * cw, (i // cols) * ch
        big = im.resize((120, 120), Image.LANCZOS); sheet.paste(big, (x + 8, y + 2), big)
        d.rectangle([x + 6, y + 124, x + 66, y + 162], fill='#3B4252')
        for bg, ox in ((1, 10), (0, 72)):
            sm = im.resize((36, 36), Image.LANCZOS); sheet.paste(sm, (x + ox, y + 125), sm)
            sm = im.resize((24, 24), Image.LANCZOS); sheet.paste(sm, (x + ox + 34, y + 134), sm)
        d.text((x + cw / 2, y + 171), f'{n} ({r[ix["Stage"]]})', fill='#222', font=f, anchor='mm')
    sheet.save(f'{out}/contact_sheet_creatures.png')
    with open(f'{out}/creature_notes.md', 'w') as fh:
        fh.write('# Landwar mannequin icons - non-human classes\n\nFolk are full figures; monsters are head-only. "Shown" lists what the figure holds, or which sheet icon parts appear on the head.\n\n| Class | Stage | Type | Sheet Icon hand | Shown |\n|---|---|---|---|---|\n')
        for n, st, ty, sh, w in notes:
            fh.write(f'| {n} | {st} | {ty} | {sh or "-"} | {w} |\n')
    print(len(units), 'icons')


if __name__ == '__main__':
    main()
