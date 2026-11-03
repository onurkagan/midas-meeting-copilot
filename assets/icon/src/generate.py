# Midas app icon generator (final design).
#
# King Midas's crown with his donkey ears rising out of it: soft silver-grey fur with
# ink-dark tips and margins and a pale fringe lining the openings (the cues that make them
# donkey, not rabbit, ears), set in a polished platinum circlet with sapphires, on a calm
# azure-to-navy squircle. Lit from above.
#
# Usage: python3 generate.py out.svg [key=value ...]  (or ./build.sh to also render the PNG)
import sys, math, random
from squircle import squircle
from geom import path_from, transform_segments
from bez import sample

P = dict(L=480.0, TILT=15.0, DX=80.0, BY=690.0, RT=636.0, RX=212.0, RY=38.0, H=100.0)
for kv in sys.argv[2:]:
    k, v = kv.split("=")
    P[k] = float(v)

L, TILT, DX, BY = P["L"], P["TILT"], P["DX"], P["BY"]
CX, RT, RX, RY, H = 512.0, P["RT"], P["RX"], P["RY"], P["H"]
X0, X1 = CX - RX, CX + RX
W = 0.6 * L
BODY = squircle(100, 100, 824, 824, 185.4)


def f(v, nd=2):
    s = f"{v:.{nd}f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


# ---------------------------------------------------------------- geometry
# Right ear, upright, base centre at the origin, tip at y = -1 (normalised by length).
# Outer edge: one long convex sweep, widest at ~36%, straightening into a sharp tip.
# Inner edge: a slight S, so the tip flicks outward like a donkey's.
EAR = [
    (0.100, 0.05),
    ((0.168, -0.05), (0.228, -0.19), (0.232, -0.36)),
    ((0.236, -0.56), (0.176, -0.80), (0.062, -1.00)),
    ((0.030, -0.93), (-0.068, -0.81), (-0.134, -0.645)),
    ((-0.188, -0.51), (-0.202, -0.35), (-0.188, -0.22)),
    ((-0.174, -0.10), (-0.134, -0.01), (-0.100, 0.05)),
    ((-0.035, 0.08), (0.035, 0.08), (0.100, 0.05)),
]
# The opening runs down into the crown like a funnel; the outer rim stays broader.
HOLLOW = [
    (0.030, 0.06),
    ((0.090, -0.06), (0.130, -0.22), (0.134, -0.40)),
    ((0.138, -0.58), (0.098, -0.74), (0.040, -0.84)),
    ((0.004, -0.78), (-0.080, -0.66), (-0.108, -0.50)),
    ((-0.130, -0.36), (-0.112, -0.14), (-0.060, 0.06)),
    ((-0.020, 0.08), (0.000, 0.08), (0.030, 0.06)),
]
ear = path_from(transform_segments(EAR, sx=L, sy=L))
hollow = path_from(transform_segments(HOLLOW, sx=L, sy=L))


def ear_tf(side):
    return f"translate({f(CX + side * DX)} {f(BY)}) rotate({f(side * TILT)}) scale({side} 1)"


def front(t, dy=0.0):
    """Point on the front arc of the crown's top rim, t in [0, 1] from left to right."""
    a = math.pi * (1 - t)
    return CX + RX * math.cos(a), RT + RY * math.sin(a) + dy


def rim(inset=0.0, ry_shrink=0.0):
    x0, x1, rx, ry = X0 + inset, X1 - inset, RX - inset, RY - ry_shrink
    return f"M{f(x0)} {f(RT)} A{f(rx)} {f(ry)} 0 0 1 {f(x1)} {f(RT)} A{f(rx)} {f(ry)} 0 0 1 {f(x0)} {f(RT)}Z"


def front_arc(dy=0.0):
    return f"M{f(X0)} {f(RT + dy)} A{f(RX)} {f(RY)} 0 0 0 {f(X1)} {f(RT + dy)}"


BAND = (f"M{f(X0)} {f(RT)} A{f(RX)} {f(RY)} 0 0 0 {f(X1)} {f(RT)} L{f(X1 - 7)} {f(RT + H)} "
        f"A{f(RX - 7)} {f(RY + 7)} 0 0 1 {f(X0 + 7)} {f(RT + H)}Z")


def lancet(x, y, w, h):
    return (f"M{f(x - w / 2)} {f(y)} C{f(x - w / 2)} {f(y - h * 0.42)} {f(x - w * 0.17)} {f(y - h * 0.8)} {f(x)} {f(y - h)} "
            f"C{f(x + w * 0.17)} {f(y - h * 0.8)} {f(x + w / 2)} {f(y - h * 0.42)} {f(x + w / 2)} {f(y)}Z")


def lancet_left(x, y, w, h):
    return (f"M{f(x - w / 2)} {f(y)} C{f(x - w / 2)} {f(y - h * 0.42)} {f(x - w * 0.17)} {f(y - h * 0.8)} {f(x)} {f(y - h)} "
            f"L{f(x)} {f(y)}Z")


def pear(x, top, w, h):
    r = w / 2
    return (f"M{f(x)} {f(top)} C{f(x + w * 0.12)} {f(top + h * 0.22)} {f(x + r)} {f(top + h * 0.42)} {f(x + r)} {f(top + h - r)} "
            f"A{f(r)} {f(r)} 0 0 1 {f(x - r)} {f(top + h - r)} C{f(x - r)} {f(top + h * 0.42)} {f(x - w * 0.12)} {f(top + h * 0.22)} {f(x)} {f(top)}Z")


# ---------------------------------------------------------------- svg helpers
def stops(*s):
    return "".join(f'<stop offset="{o}" stop-color="{c}"' + (f' stop-opacity="{a}"' if a != 1 else "") + "/>" for o, c, a in s)


def lin(id, x1, y1, x2, y2, *s, units="userSpaceOnUse"):
    return f'<linearGradient id="{id}" x1="{f(x1)}" y1="{f(y1)}" x2="{f(x2)}" y2="{f(y2)}" gradientUnits="{units}">{stops(*s)}</linearGradient>\n'


def rad(id, cx, cy, r, *s, units="userSpaceOnUse"):
    return f'<radialGradient id="{id}" cx="{f(cx)}" cy="{f(cy)}" r="{f(r)}" gradientUnits="{units}">{stops(*s)}</radialGradient>\n'


def blur(id, sd, region=30):
    return f'<filter id="{id}" x="-{region}%" y="-{region}%" width="{100 + 2 * region}%" height="{100 + 2 * region}%"><feGaussianBlur stdDeviation="{f(sd)}"/></filter>\n'


def hairs(shape, seed, inward, y_lo, y_hi, per, len_lo, len_hi, color, a_lo, a_hi, w_lo, w_hi, up_lo, up_hi, start_in=0.012):
    """Short curved hairs rooted along an outline, growing inward (into it) or outward,
    leaning upward. Seeded, so the artwork is reproducible."""
    rnd = random.Random(seed)
    segs = transform_segments(shape, sx=L, sy=L)
    out = []
    for (x, y), (tx, ty) in sample(segs, 60):
        if y > y_lo * L or y < y_hi * L:
            continue
        nx, ny = (-ty, tx) if inward else (ty, -tx)
        for _ in range(per):
            ln = rnd.uniform(len_lo, len_hi) * L
            up = rnd.uniform(up_lo, up_hi)
            dx, dy = nx * (1 - up), ny * (1 - up) - up
            k = math.hypot(dx, dy) or 1
            dx, dy = dx / k, dy / k
            back = rnd.uniform(0, start_in) * L
            sx, sy = x - nx * back, y - ny * back
            ex, ey = sx + dx * ln, sy + dy * ln
            cx, cy = sx + dx * ln * 0.5 - nx * ln * 0.12, sy + dy * ln * 0.5 - ny * ln * 0.12
            out.append(f'<path d="M{f(sx, 1)} {f(sy, 1)}Q{f(cx, 1)} {f(cy, 1)} {f(ex, 1)} {f(ey, 1)}" '
                       f'stroke="{color}" stroke-opacity="{rnd.uniform(a_lo, a_hi):.2f}" stroke-width="{rnd.uniform(w_lo, w_hi):.1f}"/>')
    return "".join(out)


def fur_texture(seed):
    """Fine strands along the ear's length, lighter and darker."""
    rnd = random.Random(seed * 7)
    out = []
    for _ in range(70):
        u = rnd.uniform(-0.2, 0.24)
        y0 = rnd.uniform(-0.1, -0.85)
        ln = rnd.uniform(0.05, 0.14)
        x1 = u * (1 - 0.6 * max(0, -y0 - 0.4))
        col = "#FFFFFF" if rnd.random() < 0.6 else "#45578A"
        out.append(f'<path d="M{f(x1 * L, 1)} {f(y0 * L, 1)}q{f(-u * 0.08 * L, 1)} {f(-ln * 0.5 * L, 1)} {f(-u * 0.12 * L, 1)} {f(-ln * L, 1)}" '
                   f'stroke="{col}" stroke-opacity="{rnd.uniform(0.15, 0.45):.2f}" stroke-width="{rnd.uniform(0.8, 1.6):.1f}"/>')
    return "".join(out)


# ---------------------------------------------------------------- defs
defs = ""
defs += blur("bodyShadow", 11, 10)
defs += lin("bodyFill", 0, 100, 0, 924, (0, "#5CA9FF", 1), (0.48, "#2367E4", 1), (1, "#0D2B7C", 1))
defs += rad("bodyGlow", 512, 360, 470, (0, "#D9ECFF", 0.62), (0.45, "#A8D0FF", 0.22), (1, "#A8D0FF", 0))
defs += rad("bodyVignette", 512, 470, 560, (0.6, "#061A52", 0), (1, "#061A52", 0.22))
defs += blur("cast", 20) + blur("contact", 9) + blur("soft06", 0.6) + blur("soft2", 2.2) + blur("soft4", 4) + blur("soft8", 8)
# Ears
defs += lin("furFill", -0.20 * L, 0, 0.236 * L, 0, (0, "#7A8CB6", 1), (0.16, "#B4C2DE", 1), (0.38, "#DCE4F2", 1),
            (0.62, "#C4D0E7", 1), (0.86, "#94A6CB", 1), (1, "#6C7EA9", 1))
defs += lin("furBase", 0, 0.05 * L, 0, -L, (0, "#132864", 0.65), (0.28, "#132864", 0), (1, "#132864", 0))
defs += lin("furSheen", 0, -0.9 * L, 0, -0.1 * L, (0, "#FFFFFF", 0), (0.35, "#FFFFFF", 0.75), (0.8, "#FFFFFF", 0.3), (1, "#FFFFFF", 0))
defs += lin("margin", 0, -L, 0, -0.30 * L, (0, "#081029", 1), (0.5, "#0A1330", 0.6), (1, "#0A1330", 0))
defs += lin("opening", 0, -0.84 * L, 0, 0.06 * L, (0, "#1C2A5C", 1), (0.32, "#41588F", 1), (0.66, "#3A5089", 1), (1, "#12204F", 1))
defs += rad("canal", 0.5, 0.5, 0.5, (0, "#081236", 0.75), (1, "#081236", 0), units="objectBoundingBox")
defs += rad("lift", 0.5, 0.5, 0.5, (0, "#7D93C9", 0.35), (1, "#7D93C9", 0), units="objectBoundingBox")
defs += lin("inkTip", 0, -L, 0, -0.60 * L, (0, "#04081A", 1), (0.38, "#060C22", 0.98), (0.62, "#0A1330", 0.7), (0.82, "#0E1838", 0.28), (1, "#0E1838", 0))
defs += lin("earOcclusion", 0, 0.02 * L, 0, -0.30 * L, (0, "#0A1A4A", 0.85), (0.5, "#0A1A4A", 0.3), (1, "#0A1A4A", 0))
defs += ('<filter id="openingShade" x="-25%" y="-25%" width="150%" height="150%">'
         '<feFlood flood-color="#040A24" flood-opacity="0.7"/><feComposite in2="SourceAlpha" operator="out"/>'
         f'<feGaussianBlur stdDeviation="{f(0.02 * L)}"/><feOffset dx="{f(0.004 * L)}" dy="{f(0.024 * L)}"/>'
         '<feComposite in2="SourceAlpha" operator="in" result="shade"/>'
         '<feMerge><feMergeNode in="SourceGraphic"/><feMergeNode in="shade"/></feMerge></filter>\n')
# Soft fur on the silhouette, and hair-like streaks where the ink tip fades out.
defs += ('<filter id="furEdge" x="-10%" y="-10%" width="120%" height="120%">'
         '<feTurbulence type="fractalNoise" baseFrequency="0.9 0.12" numOctaves="2" seed="11"/>'
         '<feDisplacementMap in="SourceGraphic" scale="3.5" xChannelSelector="R" yChannelSelector="G"/></filter>\n')
defs += ('<filter id="furStreaks" x="-10%" y="-10%" width="120%" height="120%">'
         '<feTurbulence type="fractalNoise" baseFrequency="0.22 0.018" numOctaves="3" seed="4"/>'
         '<feDisplacementMap in="SourceGraphic" scale="34" xChannelSelector="R" yChannelSelector="G"/>'
         '<feGaussianBlur stdDeviation="0.6"/></filter>\n')
defs += f'<clipPath id="earClip"><path d="{ear}"/></clipPath>\n<clipPath id="openingClip"><path d="{hollow}"/></clipPath>\n'
# Crown
defs += lin("crownInside", 0, RT - RY, 0, RT + RY, (0, "#40568C", 1), (0.6, "#0E1D4C", 1), (1, "#081236", 1))
defs += lin("crownRim", 0, RT - RY, 0, RT + RY, (0, "#9FB0D2", 1), (0.5, "#E8EEF8", 1), (1, "#FFFFFF", 1))
defs += lin("bandTurn", X0, 0, X1, 0, (0, "#0E1E4A", 0.62), (0.16, "#0E1E4A", 0.1), (0.3, "#0E1E4A", 0),
            (0.7, "#0E1E4A", 0), (0.84, "#0E1E4A", 0.12), (1, "#0E1E4A", 0.68))
defs += lin("lancetLit", 0, RT - 110, 0, RT + RY + 10, (0, "#FFFFFF", 1), (1, "#B3C1DC", 1))
defs += lin("lancetShade", 0, RT - 110, 0, RT + RY + 10, (0, "#C9D3E8", 1), (1, "#7C8FB6", 1))
defs += rad("sapphire", 0.36, 0.30, 0.78, (0, "#D9EDFF", 1), (0.22, "#5D96F7", 1), (0.6, "#1440A8", 1), (1, "#06164F", 1), units="objectBoundingBox")
defs += rad("sapphireFire", 0.5, 0.85, 0.5, (0, "#7FB4FF", 0.75), (1, "#7FB4FF", 0), units="objectBoundingBox")
defs += rad("platinumBead", 0.35, 0.3, 0.75, (0, "#FFFFFF", 1), (0.5, "#C6D1E6", 1), (1, "#6B7EA8", 1), units="objectBoundingBox")
defs += f'<clipPath id="bandClip"><path d="{BAND}"/></clipPath>\n'


# ---------------------------------------------------------------- layers
def ear_layer(side):
    s = 5 + side
    o = f'<g id="{"ear-right" if side == 1 else "ear-left"}" transform="{ear_tf(side)}">\n'
    o += f'<path d="{ear}" fill="url(#furFill)" filter="url(#furEdge)"/>\n'
    o += f'<g clip-path="url(#earClip)"><rect x="{f(-W)}" y="{f(-1.1 * L)}" width="{f(2 * W)}" height="{f(1.2 * L)}" fill="url(#furBase)"/>'
    o += (f'<path d="{ear}" fill="none" stroke="url(#furSheen)" stroke-width="{f(0.05 * L)}" opacity="0.8" filter="url(#soft8)" '
          f'transform="translate({f(0.03 * L)} {f(0.012 * L)}) scale(0.9 0.98)"/></g>\n')
    o += f'<g clip-path="url(#earClip)" opacity="0.5" fill="none" stroke-linecap="round">{fur_texture(s)}</g>\n'
    # Dark margins down the rims, then the opening with its pale fringe.
    o += f'<g clip-path="url(#earClip)" filter="url(#furEdge)"><path d="{ear}" fill="none" stroke="url(#margin)" stroke-width="{f(0.045 * L)}"/></g>\n'
    o += f'<path d="{hollow}" fill="url(#opening)" filter="url(#openingShade)"/>\n'
    o += (f'<g clip-path="url(#openingClip)"><ellipse cx="0" cy="{f(0.02 * L)}" rx="{f(0.16 * L)}" ry="{f(0.36 * L)}" fill="url(#canal)"/>'
          f'<ellipse cx="{f(0.03 * L)}" cy="{f(-0.5 * L)}" rx="{f(0.09 * L)}" ry="{f(0.22 * L)}" fill="url(#lift)"/>'
          f'<g fill="none" stroke-linecap="round">{hairs(HOLLOW, s + 40, True, -0.05, -0.72, 1, 0.08, 0.16, "#C8D6F2", 0.10, 0.28, 0.8, 1.4, 0.8, 0.95, 0.03)}</g>'
          f'<path d="{hollow}" fill="none" stroke="#E8F0FF" stroke-opacity="0.5" stroke-width="{f(0.032 * L)}" filter="url(#soft4)"/></g>\n')
    o += f'<g filter="url(#soft06)" fill="none" stroke-linecap="round">{hairs(HOLLOW, s, True, -0.03, -0.80, 3, 0.022, 0.075, "#F5F8FF", 0.35, 0.95, 1.1, 2.4, 0.35, 0.8)}</g>\n'
    # Ink-dark tip fading down in hair-like streaks.
    o += f'<g clip-path="url(#earClip)"><rect x="{f(-W)}" y="{f(-1.15 * L)}" width="{f(2 * W)}" height="{f(0.6 * L)}" fill="url(#inkTip)" filter="url(#furStreaks)"/></g>\n'
    # Guard hairs catching the light on the silhouette; rim light; occlusion at the crown.
    o += f'<g filter="url(#soft06)" fill="none" stroke-linecap="round">{hairs(EAR, s + 20, False, -0.12, -0.93, 1, 0.008, 0.02, "#C9D5EC", 0.3, 0.7, 1.0, 1.8, 0.5, 0.9, 0.004)}</g>\n'
    o += (f'<g clip-path="url(#earClip)"><path d="{ear}" fill="none" stroke="#FFFFFF" stroke-opacity="0.55" stroke-width="5" '
          f'transform="translate(-3 4)" filter="url(#soft4)"/>'
          f'<rect x="{f(-W)}" y="{f(-0.35 * L)}" width="{f(2 * W)}" height="{f(0.5 * L)}" fill="url(#earOcclusion)"/></g>\n')
    return o + "</g>\n"


ox, oy = front(0.5)
ORN_W, ORN_H = 62.0, 104.0
orn = lancet(ox, oy + 8, ORN_W, ORN_H + 8)

svg = ['<?xml version="1.0" encoding="UTF-8"?>\n',
       '<!-- Midas app icon (1024 x 1024 master). King Midas\'s crown with his donkey ears:\n'
       '     silver-grey fur, ink tips and pale fringed openings, in a platinum circlet with\n'
       '     sapphires, on Apple\'s macOS icon grid (824 pt continuous-corner body, standard\n'
       '     shadow). Generated; render with a full SVG renderer (filters are used). -->\n',
       '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">\n',
       "<defs>\n", defs, "</defs>\n"]

svg.append('<g id="body">\n'
           f'<path d="{BODY}" transform="translate(0 10)" fill="#000" opacity="0.3" filter="url(#bodyShadow)"/>\n'
           f'<path d="{BODY}" fill="url(#bodyFill)"/>\n<path d="{BODY}" fill="url(#bodyGlow)"/>\n<path d="{BODY}" fill="url(#bodyVignette)"/>\n'
           "</g>\n")
mark = (f'<g transform="{ear_tf(1)}"><path d="{ear}"/></g><g transform="{ear_tf(-1)}"><path d="{ear}"/></g>'
        f'<path d="{BAND}"/><path d="{rim()}"/><path d="{orn}"/>')
bx, by = front(0.5, dy=H)
svg.append('<g id="shadow">\n'
           f'<g filter="url(#cast)" opacity="0.5" transform="translate(0 30)" fill="#04123E">{mark}</g>\n'
           f'<ellipse cx="512" cy="{f(by + 6)}" rx="{f(RX * 0.9)}" ry="18" fill="#030D30" opacity="0.55" filter="url(#contact)"/>\n'
           "</g>\n")
svg.append(f'<g id="crown-inside">\n<path d="{rim()}" fill="url(#crownRim)"/>\n<path d="{rim(12, 8)}" fill="url(#crownInside)"/>\n</g>\n')
svg.append(ear_layer(1))
svg.append(ear_layer(-1))

# Centre ornament: a lancet point echoing the ears, holding a pear-cut sapphire.
gtop, gw, gh = oy - 66, 30.0, 56.0
svg.append('<g id="ornament">\n'
           f'<path d="{orn}" fill="url(#lancetShade)"/>\n'
           f'<path d="{lancet_left(ox, oy + 8, ORN_W, ORN_H + 8)}" fill="url(#lancetLit)"/>\n'
           f'<path d="{pear(ox, gtop - 5, gw + 10, gh + 9)}" fill="url(#platinumBead)"/>\n'
           f'<path d="{pear(ox, gtop, gw, gh)}" fill="url(#sapphire)"/>\n'
           f'<ellipse cx="{f(ox)}" cy="{f(gtop + gh * 0.72)}" rx="{f(gw * 0.3)}" ry="{f(gh * 0.16)}" fill="url(#sapphireFire)"/>\n'
           f'<ellipse cx="{f(ox - gw * 0.16)}" cy="{f(gtop + gh * 0.5)}" rx="{f(gw * 0.12)}" ry="{f(gh * 0.14)}" fill="#FFFFFF" opacity="0.85"/>\n'
           f'<circle cx="{f(ox)}" cy="{f(oy - ORN_H - 6)}" r="12" fill="url(#platinumBead)"/>\n'
           "</g>\n")

# Band: polished platinum whose reflections follow the cylinder (stacked arcs); the ends
# turn away into shade; milgrain beading; sapphires foreshortened by the curve.
BAND_STOPS = [(0.00, (255, 255, 255)), (0.05, (226, 233, 245)), (0.20, (186, 199, 223)), (0.34, (126, 145, 185)),
              (0.45, (233, 239, 248)), (0.53, (255, 255, 255)), (0.70, (189, 201, 224)), (0.88, (132, 150, 188)), (1.0, (92, 110, 152))]


def band_color(t):
    for (a, ca), (b, cb) in zip(BAND_STOPS, BAND_STOPS[1:]):
        if a <= t <= b:
            k = (t - a) / (b - a)
            return "#%02X%02X%02X" % tuple(round(ca[i] + (cb[i] - ca[i]) * k) for i in range(3))
    return "#5C6E98"


band = ['<g id="crown-band">\n<g clip-path="url(#bandClip)">\n<g fill="none">']
N = 64
for i in range(N + 1):
    t = i / N
    band.append(f'<path d="{front_arc(t * (H + 8) - 2)}" stroke="{band_color(t)}" stroke-width="{f((H + 8) / N + 1.4)}"/>')
band.append("</g>\n")
band.append(f'<path d="{BAND}" fill="url(#bandTurn)"/>\n<g fill="url(#platinumBead)">')
for dy in (14.0, H - 12.0):
    n = 44
    for j in range(1, n):
        t = j / n
        x, y = front(t, dy)
        band.append(f'<ellipse cx="{f(x, 1)}" cy="{f(y, 1)}" rx="{f(3.6 * max(math.sin(math.pi * t), 0.35), 1)}" ry="3.6"/>')
band.append("</g>\n</g>\n")
band.append(f'<path d="{front_arc()}" fill="none" stroke="#FFFFFF" stroke-width="4"/>\n')
for t, r in ((0.5, 31.0), (0.25, 17.0), (0.75, 17.0)):
    x, y = front(t, H * 0.5 + 2)
    sx = math.sin(math.pi * t)
    rx, ry = r * sx, r * 0.84
    band.append(f'<ellipse cx="{f(x)}" cy="{f(y + 1.5)}" rx="{f(rx + 8)}" ry="{f(ry + 7)}" fill="#3A4C7C" opacity="0.35" filter="url(#soft2)"/>'
                f'<ellipse cx="{f(x)}" cy="{f(y)}" rx="{f(rx + 6.5)}" ry="{f(ry + 6)}" fill="url(#platinumBead)"/>'
                f'<ellipse cx="{f(x)}" cy="{f(y)}" rx="{f(rx)}" ry="{f(ry)}" fill="url(#sapphire)"/>'
                f'<ellipse cx="{f(x)}" cy="{f(y + ry * 0.35)}" rx="{f(rx * 0.6)}" ry="{f(ry * 0.45)}" fill="url(#sapphireFire)"/>'
                f'<ellipse cx="{f(x - rx * 0.32)}" cy="{f(y - ry * 0.42)}" rx="{f(rx * 0.32)}" ry="{f(ry * 0.2)}" fill="#FFFFFF" opacity="0.9"/>\n')
band.append("</g>\n")
svg.extend(band)
svg.append("</svg>\n")
open(sys.argv[1], "w").write("".join(svg))
