import AppKit
import SwiftUI

/// Calm, trustworthy blues used across the panel, matched to the app icon.
enum Brand {
    static let blue = Color(red: 0.23, green: 0.51, blue: 0.96)
    static let deepBlue = Color(red: 0.12, green: 0.36, blue: 0.86)
    static let lightBlue = Color(red: 0.62, green: 0.80, blue: 1.0)
}

/// King Midas's donkey ears rising from his crown. The app icon (assets/icon/Midas.svg)
/// renders this mark in fur and platinum; here it is a monochrome template glyph for the
/// menu bar and the panel, built from the same curves.
enum EarsArt {
    // Geometry in the icon's 1024-point canvas, y pointing down as in the SVG.
    private static let earLength: CGFloat = 480
    private static let earTilt: CGFloat = 15
    private static let earSpread: CGFloat = 80
    private static let earBaseY: CGFloat = 690
    private static let crownX: CGFloat = 512
    private static let rimY: CGFloat = 636
    private static let rimRadius = CGSize(width: 212, height: 38)
    /// The glyph's band is slimmer than the icon's (100), so at 16 pt it reads as a
    /// circlet rather than a bowl.
    private static let bandHeight: CGFloat = 74

    /// Right ear, upright, base at the origin, tip at y = -1: a start point followed by
    /// (control 1, control 2, end) triples. Broad lance with a sharp, out-flicked tip.
    private static let ear: [CGPoint] = [
        CGPoint(x: 0.100, y: 0.05),
        CGPoint(x: 0.168, y: -0.05), CGPoint(x: 0.228, y: -0.19), CGPoint(x: 0.232, y: -0.36),
        CGPoint(x: 0.236, y: -0.56), CGPoint(x: 0.176, y: -0.80), CGPoint(x: 0.062, y: -1.00),
        CGPoint(x: 0.030, y: -0.93), CGPoint(x: -0.068, y: -0.81), CGPoint(x: -0.134, y: -0.645),
        CGPoint(x: -0.188, y: -0.51), CGPoint(x: -0.202, y: -0.35), CGPoint(x: -0.188, y: -0.22),
        CGPoint(x: -0.174, y: -0.10), CGPoint(x: -0.134, y: -0.01), CGPoint(x: -0.100, y: 0.05),
        CGPoint(x: -0.035, y: 0.08), CGPoint(x: 0.035, y: 0.08), CGPoint(x: 0.100, y: 0.05),
    ]
    /// The ear's opening, running down into the crown.
    private static let opening: [CGPoint] = [
        CGPoint(x: 0.030, y: 0.06),
        CGPoint(x: 0.090, y: -0.06), CGPoint(x: 0.130, y: -0.22), CGPoint(x: 0.134, y: -0.40),
        CGPoint(x: 0.138, y: -0.58), CGPoint(x: 0.098, y: -0.74), CGPoint(x: 0.040, y: -0.84),
        CGPoint(x: 0.004, y: -0.78), CGPoint(x: -0.080, y: -0.66), CGPoint(x: -0.108, y: -0.50),
        CGPoint(x: -0.130, y: -0.36), CGPoint(x: -0.112, y: -0.14), CGPoint(x: -0.060, y: 0.06),
        CGPoint(x: -0.020, y: 0.08), CGPoint(x: 0.000, y: 0.08), CGPoint(x: 0.030, y: 0.06),
    ]
    /// Everything below the ink-dark tip, in ear units: an arch, highest mid-ear, as the
    /// dark fur runs further down the rims. The glyph keeps the ear solid above it, its
    /// stand-in for the icon's dark tips.
    private static let belowInk: [CGPoint] = [
        CGPoint(x: -1, y: 1),
        CGPoint(x: -1, y: 0.4), CGPoint(x: -1, y: -0.58), CGPoint(x: -0.14, y: -0.60),
        CGPoint(x: -0.06, y: -0.74), CGPoint(x: 0.10, y: -0.74), CGPoint(x: 0.18, y: -0.60),
        CGPoint(x: 1, y: -0.58), CGPoint(x: 1, y: 0.4), CGPoint(x: 1, y: 1),
    ]

    private static func bezier(_ points: [CGPoint]) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: points[0])
        for i in stride(from: 1, to: points.count, by: 3) {
            path.curve(to: points[i + 2], controlPoint1: points[i], controlPoint2: points[i + 1])
        }
        path.close()
        return path
    }

    /// Places a shape drawn in ear units onto the right (side 1) or left (side -1) ear.
    private static func earTransform(side: CGFloat) -> AffineTransform {
        var transform = AffineTransform(translationByX: crownX + side * earSpread, byY: earBaseY)
        transform.rotate(byDegrees: side * earTilt)
        transform.scale(x: side * earLength, y: earLength)
        return transform
    }

    /// Lower half of an ellipse from its left to its right end, appended to `path`.
    private static func appendFrontArc(_ path: NSBezierPath, center: CGPoint, radius: CGSize, reversed: Bool = false) {
        let k: CGFloat = 0.5523
        let (rx, ry) = (radius.width, radius.height)
        let left = CGPoint(x: center.x - rx, y: center.y), right = CGPoint(x: center.x + rx, y: center.y)
        let bottom = CGPoint(x: center.x, y: center.y + ry)
        if reversed {
            path.curve(to: bottom, controlPoint1: CGPoint(x: right.x, y: center.y + k * ry), controlPoint2: CGPoint(x: center.x + k * rx, y: bottom.y))
            path.curve(to: left, controlPoint1: CGPoint(x: center.x - k * rx, y: bottom.y), controlPoint2: CGPoint(x: left.x, y: center.y + k * ry))
        } else {
            path.curve(to: bottom, controlPoint1: CGPoint(x: left.x, y: center.y + k * ry), controlPoint2: CGPoint(x: center.x - k * rx, y: bottom.y))
            path.curve(to: right, controlPoint1: CGPoint(x: center.x + k * rx, y: bottom.y), controlPoint2: CGPoint(x: right.x, y: center.y + k * ry))
        }
    }

    /// The crown's front band: a cylinder seen slightly from above, so both edges curve.
    private static func band() -> NSBezierPath {
        let path = NSBezierPath()
        let (rx, ry) = (rimRadius.width, rimRadius.height)
        path.move(to: CGPoint(x: crownX - rx, y: rimY))
        appendFrontArc(path, center: CGPoint(x: crownX, y: rimY), radius: rimRadius)
        path.line(to: CGPoint(x: crownX + rx - 7, y: rimY + bandHeight))
        appendFrontArc(path, center: CGPoint(x: crownX, y: rimY + bandHeight), radius: CGSize(width: rx - 7, height: ry + 7), reversed: true)
        path.close()
        return path
    }

    /// The pointed ornament at the front of the crown, between the ears.
    private static func lancet() -> NSBezierPath {
        let (x, base, w, h) = (crownX, rimY + rimRadius.height + 8, CGFloat(76), CGFloat(132))
        let path = NSBezierPath()
        path.move(to: CGPoint(x: x - w / 2, y: base))
        path.curve(to: CGPoint(x: x, y: base - h), controlPoint1: CGPoint(x: x - w / 2, y: base - h * 0.42), controlPoint2: CGPoint(x: x - w * 0.17, y: base - h * 0.8))
        path.curve(to: CGPoint(x: x + w / 2, y: base), controlPoint1: CGPoint(x: x + w * 0.17, y: base - h * 0.8), controlPoint2: CGPoint(x: x + w / 2, y: base - h * 0.42))
        path.close()
        return path
    }

    /// The mark alone as a template image (menu bar, panel logo); it takes the
    /// surrounding tint.
    static func glyph(size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            guard let context = NSGraphicsContext.current else { return false }
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            let ears = [CGFloat(1), -1].map { side -> (outline: NSBezierPath, hollow: NSBezierPath, uncovered: NSBezierPath) in
                let transform = earTransform(side: side)
                let outline = bezier(ear), hollow = bezier(opening), uncovered = bezier(belowInk)
                [outline, hollow, uncovered].forEach { $0.transform(using: transform) }
                return (outline, hollow, uncovered)
            }
            let front = band(), ornament = lancet()

            // Fit the mark's bounds into the image, centred.
            let bounds = ears.reduce(front.bounds.union(ornament.bounds)) { $0.union($1.outline.bounds) }
            // A little air around the mark, like the system's own menu bar glyphs.
            let scale = min(rect.width / bounds.width, rect.height / bounds.height) * 0.9
            let fit = NSAffineTransform()
            fit.translateX(by: rect.midX - bounds.midX * scale, yBy: rect.midY - bounds.midY * scale)
            fit.scale(by: scale)
            fit.concat()
            // Gaps and details are sized in points, so they stay crisp at 16 pt and refined at 44.
            let gap = min(max(size * 0.055, 0.9), 1.8) / scale
            let detailed = size >= 28

            NSColor.black.setFill()
            for shape in ears {
                shape.outline.fill()
                // Cut the opening, but keep the tip solid: the icon's ink-dark tips.
                NSGraphicsContext.saveGraphicsState()
                shape.uncovered.addClip()
                context.compositingOperation = .destinationOut
                shape.hollow.fill()
                NSGraphicsContext.restoreGraphicsState()
            }
            // A hairline gap sets the band and ornament in front of the ears.
            context.compositingOperation = .destinationOut
            for shape in [front, ornament] {
                shape.lineWidth = gap * 2
                shape.lineJoinStyle = .round
                shape.stroke()
            }
            context.compositingOperation = .sourceOver
            front.fill()
            ornament.fill()

            // Sapphires set into the band (one at small sizes, three when there is room), each
            // riding the band's curve, and the pearl atop the ornament.
            let gems: [(x: CGFloat, r: CGFloat)] = detailed ? [(crownX, 30), (crownX - 150, 19), (crownX + 150, 19)] : [(crownX, 34)]
            context.compositingOperation = .destinationOut
            for gem in gems {
                let across = (gem.x - crownX) / rimRadius.width
                let y = rimY + rimRadius.height * sqrt(1 - across * across) + bandHeight * 0.5 + 2
                NSBezierPath(ovalIn: NSRect(x: gem.x - gem.r, y: y - gem.r * 0.86, width: gem.r * 2, height: gem.r * 1.72)).fill()
            }
            context.compositingOperation = .sourceOver
            let pearl: CGFloat = detailed ? 30 : 40
            NSBezierPath(ovalIn: NSRect(x: crownX - pearl / 2, y: ornament.bounds.minY - pearl * 0.8, width: pearl, height: pearl)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
