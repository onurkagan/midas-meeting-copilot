import AppKit
import SwiftUI

/// King Midas's donkey ears rising from his crown: two leaves over a crown, the same
/// curves as the app icon (assets/icon/src/generate.py), here as a monochrome template
/// glyph for the menu bar and the panel. Drawn in the icon's 100-unit box, y pointing down.
enum EarsArt {
    private static func path(_ build: (NSBezierPath) -> Void) -> NSBezierPath {
        let path = NSBezierPath()
        build(path)
        path.close()
        return path
    }

    private static let leftEar = path {
        $0.move(to: CGPoint(x: 44, y: 62))
        $0.curve(to: CGPoint(x: 34, y: 12), controlPoint1: CGPoint(x: 33, y: 50), controlPoint2: CGPoint(x: 29, y: 28))
        $0.curve(to: CGPoint(x: 48, y: 60), controlPoint1: CGPoint(x: 45, y: 22), controlPoint2: CGPoint(x: 50, y: 40))
    }

    private static let rightEar = path {
        $0.move(to: CGPoint(x: 56, y: 62))
        $0.curve(to: CGPoint(x: 66, y: 12), controlPoint1: CGPoint(x: 67, y: 50), controlPoint2: CGPoint(x: 71, y: 28))
        $0.curve(to: CGPoint(x: 52, y: 60), controlPoint1: CGPoint(x: 55, y: 22), controlPoint2: CGPoint(x: 50, y: 40))
    }

    private static let crown = path {
        $0.move(to: CGPoint(x: 28, y: 84))
        for point in [(31, 66), (40, 74), (50, 62), (60, 74), (69, 66), (72, 84)] {
            $0.line(to: CGPoint(x: point.0, y: point.1))
        }
    }

    /// The mark alone as a template image (menu bar, panel logo); it takes the
    /// surrounding tint.
    static func glyph(size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            let shapes = [leftEar, rightEar, crown].map { $0.copy() as! NSBezierPath }
            let bounds = shapes.reduce(shapes[0].bounds) { $0.union($1.bounds) }
            // A little air around the mark, like the system's own menu bar glyphs.
            let scale = min(rect.width / bounds.width, rect.height / bounds.height) * 0.9
            let fit = AffineTransform(translationByX: rect.midX - bounds.midX * scale, byY: rect.midY - bounds.midY * scale)
            NSColor.black.set()
            for shape in shapes {
                shape.transform(using: AffineTransform(scale: scale))
                shape.transform(using: fit)
                shape.fill()
            }
            // Soften the crown's points, as in the icon.
            let crownShape = shapes[2]
            crownShape.lineWidth = max(2.4 * scale, 0.6)
            crownShape.lineJoinStyle = .round
            crownShape.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}
