import AppKit
import CoreText
import SwiftUI

/// Tide: calm water and soft glass. The panel follows macOS's appearance: Tide by day,
/// Tide at night in dark mode.
struct Tide {
    let ink: Color  // headings and the strongest text
    let body: Color  // what was said
    let muted: Color  // secondary text and icons
    let faint: Color  // timestamps
    let glassTop: Color  // laid over the blurred desktop, light at the top…
    let glassBottom: Color  // …turning to sea blue at the bottom
    let rim: Color  // the panel's edge
    let divider: Color
    let accent: Color  // the Answer button
    let accentText: Color  // titles and links in the accent
    let foam: Color  // listening, live speech
    let foamText: Color
    let foamFill: Color
    let answerFill: Color
    let answerStroke: Color
    let answerBody: Color
    let field: Color  // text field and secondary buttons
    let fieldStroke: Color
    let fieldText: Color
    let card: Color  // the reminder card and the settings drawer
    let cardStroke: Color
    let quiet: Color  // off the record
    let quietText: Color

    static let light = Tide(
        ink: Color(hex: 0x0E2A3B), body: Color(hex: 0x0E2A3B), muted: Color(hex: 0x44606F), faint: Color(hex: 0x4F6B7A),
        glassTop: Color(hex: 0xF7FBFD, opacity: 0.90), glassBottom: Color(hex: 0xC4DEEC, opacity: 0.90),
        rim: Color.white.opacity(0.75), divider: Color(hex: 0x0E3C5A, opacity: 0.08),
        accent: Color(hex: 0x1F6FB8), accentText: Color(hex: 0x1A5E9E),
        foam: Color(hex: 0x3BB3A6), foamText: Color(hex: 0x136B62), foamFill: Color(hex: 0x3BB3A6, opacity: 0.14),
        answerFill: Color(hex: 0x1F6FB8, opacity: 0.08), answerStroke: Color(hex: 0x1F6FB8, opacity: 0.22),
        answerBody: Color(hex: 0x0E2A3B),
        field: Color.white.opacity(0.85), fieldStroke: Color(hex: 0x0E3C5A, opacity: 0.12), fieldText: Color(hex: 0x1A4A66),
        card: Color.white.opacity(0.62), cardStroke: Color(hex: 0x1F6FB8, opacity: 0.16),
        quiet: Color(hex: 0x0E3C5A, opacity: 0.07), quietText: Color(hex: 0x3C5564))

    static let night = Tide(
        ink: Color(hex: 0xE8F1F7), body: Color(hex: 0xD6E4EE), muted: Color(hex: 0x9FB7C6), faint: Color(hex: 0x8FA8B8),
        glassTop: Color(hex: 0x0E1C27, opacity: 0.92), glassBottom: Color(hex: 0x0C3442, opacity: 0.92),
        rim: Color(hex: 0xA0D2F0, opacity: 0.14), divider: Color(hex: 0xA0D2F0, opacity: 0.10),
        accent: Color(hex: 0x1F6FB8), accentText: Color(hex: 0x8CCBF5),
        foam: Color(hex: 0x5ED1C2), foamText: Color(hex: 0x8EE3D7), foamFill: Color(hex: 0x5ED1C2, opacity: 0.14),
        answerFill: Color(hex: 0x4A9BE0, opacity: 0.12), answerStroke: Color(hex: 0x7CC4F2, opacity: 0.28),
        answerBody: Color(hex: 0xF2F7FA),
        field: Color.white.opacity(0.06), fieldStroke: Color(hex: 0xA0D2F0, opacity: 0.16), fieldText: Color(hex: 0xCFE6F7),
        card: Color.white.opacity(0.05), cardStroke: Color(hex: 0x7CC4F2, opacity: 0.22),
        quiet: Color.white.opacity(0.06), quietText: Color(hex: 0xB5C9D6))

    static func of(_ scheme: ColorScheme) -> Tide { scheme == .dark ? night : light }

    /// The panel's glass: light at the top, sea blue toward the bottom.
    var glass: LinearGradient {
        LinearGradient(colors: [glassTop, glassBottom], startPoint: .top, endPoint: .bottom)
    }

    /// Plus Jakarta Sans, falling back to the system font if it couldn't be loaded.
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        TideFont.available ? .custom(TideFont.name(for: weight), size: size) : .system(size: size, weight: weight)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

private struct TideKey: EnvironmentKey {
    static let defaultValue = Tide.light
}

extension EnvironmentValues {
    var tide: Tide {
        get { self[TideKey.self] }
        set { self[TideKey.self] = newValue }
    }
}

/// Picks Tide by day or at night from the appearance, for everything inside.
struct TideTheme: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content.environment(\.tide, Tide.of(scheme))
    }
}

/// Registers the bundled Plus Jakarta Sans (SIL OFL, assets/fonts) for this process: from the
/// app's Resources, or from the source folder when running bin/midas-overlay.
enum TideFont {
    private(set) static var available = false

    /// The variable font's named instances.
    static func name(for weight: Font.Weight) -> String {
        switch weight {
        case .heavy, .black: "PlusJakartaSans-ExtraBold"
        case .bold: "PlusJakartaSans-Bold"
        case .semibold: "PlusJakartaSans-SemiBold"
        case .medium: "PlusJakartaSans-Medium"
        default: "PlusJakartaSans-Regular"
        }
    }

    static func register() {
        guard !available else { return }
        let executable = Bundle.main.executableURL?.resolvingSymlinksInPath().deletingLastPathComponent()
        let folders = [
            Bundle.main.resourceURL?.appendingPathComponent("fonts"),
            executable?.appendingPathComponent("fonts"),
            executable?.deletingLastPathComponent().appendingPathComponent("assets/fonts"),
        ].compactMap { $0 }
        for folder in folders {
            let font = folder.appendingPathComponent("PlusJakartaSans-Variable.ttf")
            guard FileManager.default.fileExists(atPath: font.path) else { continue }
            var error: Unmanaged<CFError>?
            if CTFontManagerRegisterFontsForURL(font as CFURL, .process, &error) || NSFont(name: "PlusJakartaSans-Regular", size: 12) != nil {
                available = true
                return
            }
        }
    }
}
