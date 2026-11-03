import AppKit
import SwiftUI

/// Calm, trustworthy blues used across the panel and the icon.
enum Brand {
    static let blue = Color(red: 0.24, green: 0.52, blue: 0.97)
    static let deepBlue = Color(red: 0.15, green: 0.39, blue: 0.90)
    static let lightBlue = Color(red: 0.62, green: 0.79, blue: 1.0)
}

/// King Midas's famous donkey ears rising from his crown: the app icon, the menu bar
/// glyph and the panel logo all draw this mark.
enum EarsArt {
    /// Bounds of the mark in the 1024-point icon canvas.
    private static let markBounds = NSRect(x: 230, y: 250, width: 564, height: 564)

    /// A donkey ear standing on its base at the origin: broad in the middle, pointed tip.
    private static func earShape(width: CGFloat, length: CGFloat, base: CGFloat = 0) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: -width * 0.36, y: base))
        path.curve(
            to: NSPoint(x: 0, y: length),
            controlPoint1: NSPoint(x: -width * 0.66, y: base + (length - base) * 0.40),
            controlPoint2: NSPoint(x: -width * 0.30, y: base + (length - base) * 0.86))
        path.curve(
            to: NSPoint(x: width * 0.36, y: base),
            controlPoint1: NSPoint(x: width * 0.30, y: base + (length - base) * 0.86),
            controlPoint2: NSPoint(x: width * 0.66, y: base + (length - base) * 0.40))
        path.close()
        return path
    }

    /// Draws the mark in icon-canvas coordinates. With `monochrome`, the ear cavities and
    /// a thin gap around the crown are cut out instead of coloured, for template images.
    private static func drawMark(monochrome: Bool) {
        let ear = monochrome ? NSColor.black : .white
        let cavity = NSColor(srgbRed: 0.74, green: 0.85, blue: 1.0, alpha: 1)
        let tip = NSColor(srgbRed: 0.10, green: 0.20, blue: 0.48, alpha: 1)
        let crown = NSColor(srgbRed: 0.90, green: 0.94, blue: 1.0, alpha: 1)
        let jewel = NSColor(srgbRed: 0.20, green: 0.45, blue: 0.93, alpha: 1)
        let context = NSGraphicsContext.current

        for (baseX, lean) in [(CGFloat(414), CGFloat(18)), (CGFloat(610), CGFloat(-18))] {
            var transform = AffineTransform(translationByX: baseX, byY: 340)
            transform.rotate(byDegrees: lean)
            let outer = earShape(width: 208, length: 500)
            outer.transform(using: transform)
            ear.setFill()
            outer.fill()
            let inner = earShape(width: 100, length: 398, base: 110)
            inner.transform(using: transform)
            if monochrome {
                context?.compositingOperation = .destinationOut
                inner.fill()
                context?.compositingOperation = .sourceOver
            } else {
                cavity.setFill()
                inner.fill()
                // Dark tips: the detail that makes them read as donkey, not rabbit, ears.
                NSGraphicsContext.saveGraphicsState()
                outer.addClip()
                let cap = NSBezierPath(ovalIn: NSRect(x: -122, y: 408, width: 244, height: 200))
                cap.transform(using: transform)
                tip.setFill()
                cap.fill()
                NSGraphicsContext.restoreGraphicsState()
            }
        }

        let crownPath = NSBezierPath()
        crownPath.move(to: NSPoint(x: 296, y: 256))
        for point in [(296, 472), (404, 376), (512, 506), (620, 376), (728, 472), (728, 256)] {
            crownPath.line(to: NSPoint(x: point.0, y: point.1))
        }
        crownPath.close()
        crownPath.lineJoinStyle = .round
        if monochrome {
            context?.compositingOperation = .destinationOut
            crownPath.lineWidth = 44
            crownPath.stroke()
            context?.compositingOperation = .sourceOver
            ear.setFill()
        } else {
            crown.setFill()
        }
        crownPath.fill()
        if !monochrome {
            jewel.setFill()
            for x in [296, 512, 728] {
                let y = x == 512 ? 506 : 472
                NSBezierPath(ovalIn: NSRect(x: x - 26, y: y - 26, width: 52, height: 52)).fill()
            }
            NSBezierPath(rect: NSRect(x: 296, y: 256, width: 432, height: 34)).fill()
        }
    }

    /// The app icon as a PNG: the mark in white on a blue gradient, on macOS's icon grid.
    static func iconPNG(pixels: Int = 1024) -> Data? {
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let scale = NSAffineTransform()
        scale.scale(by: CGFloat(pixels) / 1024)
        scale.concat()

        let body = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
        NSGradient(
            starting: NSColor(srgbRed: 0.33, green: 0.59, blue: 0.99, alpha: 1),
            ending: NSColor(srgbRed: 0.09, green: 0.23, blue: 0.60, alpha: 1)
        )?.draw(in: body, angle: -90)

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
        shadow.shadowBlurRadius = 28
        shadow.shadowOffset = NSSize(width: 0, height: -12)
        shadow.set()
        drawMark(monochrome: false)

        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    /// The mark alone as a template image (menu bar, panel logo); it takes the
    /// surrounding tint.
    static func glyph(size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let fit = min(rect.width / markBounds.width, rect.height / markBounds.height)
            let transform = NSAffineTransform()
            transform.translateX(by: rect.midX - markBounds.midX * fit, yBy: rect.midY - markBounds.midY * fit)
            transform.scale(by: fit)
            transform.concat()
            drawMark(monochrome: true)
            return true
        }
        image.isTemplate = true
        return image
    }
}
