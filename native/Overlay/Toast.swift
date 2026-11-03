import AppKit

/// A short-lived hint bubble, hidden from screen sharing like the panel.
enum Toast {
    static func show(_ text: String, over frame: NSRect) {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        let size = label.fittingSize
        let rect = NSRect(
            x: frame.midX - size.width / 2 - 14, y: frame.maxY - size.height - 40,
            width: size.width + 28, height: size.height + 16)
        let window = NSPanel(
            contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.sharingType = .none
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: rect.size))
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 10
        label.frame = NSRect(x: 14, y: 8, width: size.width, height: size.height)
        background.addSubview(label)
        window.contentView = background
        window.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.4
                window.animator().alphaValue = 0
            } completionHandler: {
                window.orderOut(nil)
            }
        }
    }
}
