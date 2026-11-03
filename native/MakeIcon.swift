// Renders the 1024 px Midas app icon: a gold rounded square with a waveform.
// Usage: swift MakeIcon.swift out.png

import AppKit

let size = 1024
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// macOS icon grid: an 824 px body centred in the 1024 px canvas.
let body = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
NSGradient(
    starting: NSColor(red: 0.99, green: 0.82, blue: 0.33, alpha: 1),
    ending: NSColor(red: 0.74, green: 0.50, blue: 0.07, alpha: 1)
)!.draw(in: body, angle: -90)

let configuration = NSImage.SymbolConfiguration(pointSize: 400, weight: .semibold)
if let symbol = NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)?
    .withSymbolConfiguration(configuration)
{
    let glyph = NSImage(size: symbol.size, flipped: false) { rect in
        symbol.draw(in: rect)
        NSColor(white: 0.13, alpha: 1).set()
        rect.fill(using: .sourceAtop)
        return true
    }
    let origin = NSPoint(x: (CGFloat(size) - glyph.size.width) / 2, y: (CGFloat(size) - glyph.size.height) / 2)
    glyph.draw(in: NSRect(origin: origin, size: glyph.size))
}

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
