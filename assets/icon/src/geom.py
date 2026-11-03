# Geometry helpers: paths built from anchors with explicit handles (smooth Béziers).
import math

def fmt(v):
    s = f"{v:.2f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s

def pt(p):
    return f"{fmt(p[0])} {fmt(p[1])}"

def path_from(segments, close=True):
    """segments: [start, (c1, c2, end), (c1, c2, end), ...] in one coordinate space."""
    d = [f"M{pt(segments[0])}"]
    for c1, c2, e in segments[1:]:
        d.append(f"C{pt(c1)} {pt(c2)} {pt(e)}")
    if close:
        d.append("Z")
    return " ".join(d)

def xform(points, sx=1.0, sy=1.0, rot_deg=0.0, tx=0.0, ty=0.0):
    """Scale, then rotate (degrees, clockwise on screen), then translate."""
    a = math.radians(rot_deg)
    ca, sa = math.cos(a), math.sin(a)
    out = []
    for x, y in points:
        x, y = x * sx, y * sy
        out.append((x * ca - y * sa + tx, x * sa + y * ca + ty))
    return out

def seg_points(segments):
    pts = [segments[0]]
    for s in segments[1:]:
        pts.extend(s)
    return pts

def rebuild(segments, flat):
    out = [flat[0]]
    for i in range(1, len(segments)):
        out.append(tuple(flat[1 + (i - 1) * 3: 1 + i * 3]))
    return out

def transform_segments(segments, **kw):
    return rebuild(segments, xform(seg_points(segments), **kw))
