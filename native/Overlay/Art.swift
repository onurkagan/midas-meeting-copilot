import AppKit
import SwiftUI

/// The bubble from the app icon (assets/icon/src/generate.py): a ring of glass holding a
/// sound wave. The same curves as the icon, in its 1024-unit canvas with y pointing down,
/// drawn here as the menu bar's template glyph and inside the panel's mark.
enum BubbleArt {
    private static let center = CGPoint(x: 512, y: 512)
    private static let radius: CGFloat = 276
    /// Line widths of the monochrome glyph, in icon units.
    private static let ringWidth: CGFloat = 40
    private static let waveWidth: CGFloat = 44
    /// The ring's outer edge: what gets fitted into the box.
    private static let extent = radius + ringWidth / 2

    private static let wave: CGPath = {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 300, y: 512))
        let curves: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (330, 512, 340, 452, 362, 452),
            (390, 452, 392, 588, 420, 588),
            (450, 588, 452, 380, 482, 380),
            (512, 380, 514, 644, 544, 644),
            (574, 644, 576, 420, 604, 420),
            (632, 420, 634, 560, 662, 560),
            (686, 560, 696, 512, 724, 512),
        ]
        for c in curves {
            path.addCurve(to: CGPoint(x: c.4, y: c.5), control1: CGPoint(x: c.0, y: c.1), control2: CGPoint(x: c.2, y: c.3))
        }
        return path
    }()

    /// The bubble scaled so the ring's outer edge spans `fill` of `rect`, centred in it.
    struct Fitted {
        let disc: CGPath
        let wave: CGPath
        let ringWidth: CGFloat
        let waveWidth: CGFloat
    }

    static func fitted(in rect: CGRect, fill: CGFloat) -> Fitted {
        let scale = min(rect.width, rect.height) * fill / (extent * 2)
        var transform = CGAffineTransform(translationX: rect.midX, y: rect.midY)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -center.x, y: -center.y)
        let box = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        return Fitted(
            disc: CGPath(ellipseIn: box, transform: &transform),
            wave: wave.copy(using: &transform) ?? wave,
            ringWidth: ringWidth * scale,
            waveWidth: waveWidth * scale)
    }

    /// The ring and wave as a template image (menu bar); it takes the surrounding tint.
    static func glyph(size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            // A little air around the ring, like the system's own menu bar glyphs.
            let art = fitted(in: rect, fill: 0.9)
            context.setStrokeColor(NSColor.black.cgColor)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.setLineWidth(art.ringWidth)
            context.addPath(art.disc)
            context.strokePath()
            context.setLineWidth(art.waveWidth)
            context.addPath(art.wave)
            context.strokePath()
            return true
        }
        image.isTemplate = true
        return image
    }
}
