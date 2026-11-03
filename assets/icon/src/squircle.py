# Continuous-curvature rounded rectangle (Apple "squircle"), as an SVG path.
K = (1.52866483, 1.08849323, 0.86840689, 0.63149399, 0.07491176, 0.37282392, 0.16905168)

def squircle(x, y, w, h, r):
    a, b, c, d, e, f, g = (k * r for k in K)
    R, B = x + w, y + h
    f2 = lambda v: f"{v:.3f}".rstrip("0").rstrip(".")
    P = lambda px, py: f"{f2(px)} {f2(py)}"
    return " ".join([
        f"M{P(x + a, y)}", f"L{P(R - a, y)}",
        f"C{P(R - b, y)} {P(R - c, y)} {P(R - d, y + e)}",
        f"C{P(R - f, y + g)} {P(R - g, y + f)} {P(R - e, y + d)}",
        f"C{P(R, y + c)} {P(R, y + b)} {P(R, y + a)}",
        f"L{P(R, B - a)}",
        f"C{P(R, B - b)} {P(R, B - c)} {P(R - e, B - d)}",
        f"C{P(R - g, B - f)} {P(R - f, B - g)} {P(R - d, B - e)}",
        f"C{P(R - c, B)} {P(R - b, B)} {P(R - a, B)}",
        f"L{P(x + a, B)}",
        f"C{P(x + b, B)} {P(x + c, B)} {P(x + d, B - e)}",
        f"C{P(x + f, B - g)} {P(x + g, B - f)} {P(x + e, B - d)}",
        f"C{P(x, B - c)} {P(x, B - b)} {P(x, B - a)}",
        f"L{P(x, y + a)}",
        f"C{P(x, y + b)} {P(x, y + c)} {P(x + e, y + d)}",
        f"C{P(x + g, y + f)} {P(x + f, y + g)} {P(x + d, y + e)}",
        f"C{P(x + c, y)} {P(x + b, y)} {P(x + a, y)}Z",
    ])

if __name__ == "__main__":
    import sys
    for r in map(float, sys.argv[2:]):
        with open(f"{sys.argv[1]}/sq_{r:g}.svg", "w") as fh:
            fh.write(f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024"><path d="{squircle(100, 100, 824, 824, r)}" fill="#000"/></svg>')
