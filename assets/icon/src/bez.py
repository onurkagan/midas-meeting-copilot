# Sampling helpers for cubic Bézier outlines given as [start, (c1, c2, end), ...].
import math

def cubic(p0, p1, p2, p3, t):
    u = 1 - t
    return (u**3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t**3 * p3[0],
            u**3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t**3 * p3[1])

def dcubic(p0, p1, p2, p3, t):
    u = 1 - t
    return (3 * u * u * (p1[0] - p0[0]) + 6 * u * t * (p2[0] - p1[0]) + 3 * t * t * (p3[0] - p2[0]),
            3 * u * u * (p1[1] - p0[1]) + 6 * u * t * (p2[1] - p1[1]) + 3 * t * t * (p3[1] - p2[1]))

def sample(segs, n_per_seg=40):
    """Returns [(point, unit tangent)] along the outline."""
    out, cur = [], segs[0]
    for c1, c2, e in segs[1:]:
        for i in range(n_per_seg):
            t = i / n_per_seg
            p = cubic(cur, c1, c2, e, t)
            dx, dy = dcubic(cur, c1, c2, e, t)
            l = math.hypot(dx, dy) or 1
            out.append((p, (dx / l, dy / l)))
        cur = e
    return out
