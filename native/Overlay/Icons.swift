import SwiftUI

/// Tide's icons: thin, rounded line drawings on a 24-unit grid, as in the design (instead
/// of SF Symbols, whose filled and semibold shapes read heavy on the glass).
enum TideIcon {
    case pause, play, minimize, settings, sparkle, lock, send, waves, copy, check, close
    case refresh, arrowDown, folder, power, chat, radio, map

    fileprivate func draw(_ p: inout Path) {
        switch self {
        case .pause:
            p.move(to: pt(9, 5)); p.addLine(to: pt(9, 19))
            p.move(to: pt(15, 5)); p.addLine(to: pt(15, 19))
        case .play:
            p.move(to: pt(8, 5.5)); p.addLine(to: pt(18.5, 12)); p.addLine(to: pt(8, 18.5)); p.closeSubpath()
        case .minimize:
            p.move(to: pt(6, 12)); p.addLine(to: pt(18, 12))
        case .settings:
            let lines: [((Double, Double), (Double, Double))] = [((4, 7), (14, 7)), ((18, 7), (20, 7)), ((4, 17), (8, 17)), ((12, 17), (20, 17))]
            for (from, to) in lines {
                p.move(to: pt(from.0, from.1)); p.addLine(to: pt(to.0, to.1))
            }
            p.addEllipse(in: CGRect(x: 14, y: 5, width: 4, height: 4))
            p.addEllipse(in: CGRect(x: 8, y: 15, width: 4, height: 4))
        case .sparkle:
            for (from, to) in [((12, 3), (12, 7)), ((12, 17), (12, 21)), ((3, 12), (7, 12)), ((17, 12), (21, 12)),
                               ((6, 6), (8.5, 8.5)), ((15.5, 15.5), (18, 18)), ((6, 18), (8.5, 15.5)), ((15.5, 8.5), (18, 6))] {
                p.move(to: pt(from.0, from.1)); p.addLine(to: pt(to.0, to.1))
            }
        case .lock:
            p.addRoundedRect(in: CGRect(x: 5, y: 11, width: 14, height: 9), cornerSize: CGSize(width: 2, height: 2))
            p.move(to: pt(8, 11)); p.addLine(to: pt(8, 8))
            p.addCurve(to: pt(12, 4), control1: pt(8, 5.8), control2: pt(9.8, 4))
            p.addCurve(to: pt(16, 8), control1: pt(14.2, 4), control2: pt(16, 5.8))
            p.addLine(to: pt(16, 11))
        case .send:
            p.move(to: pt(7, 17)); p.addLine(to: pt(17, 7))
            p.move(to: pt(9, 7)); p.addLine(to: pt(17, 7)); p.addLine(to: pt(17, 15))
        case .waves:
            for y in [10.0, 15.0] {
                p.move(to: pt(3, y))
                p.addCurve(to: pt(12, y), control1: pt(6, y - 2), control2: pt(8, y + 2))
                p.addCurve(to: pt(21, y), control1: pt(16, y - 2), control2: pt(18, y - 2))
            }
        case .copy:
            p.addRoundedRect(in: CGRect(x: 9, y: 9, width: 11, height: 11), cornerSize: CGSize(width: 2, height: 2))
            p.move(to: pt(15, 9)); p.addLine(to: pt(15, 6))
            p.addQuadCurve(to: pt(13, 4), control: pt(15, 4))
            p.addLine(to: pt(6, 4))
            p.addQuadCurve(to: pt(4, 6), control: pt(4, 4))
            p.addLine(to: pt(4, 13))
            p.addQuadCurve(to: pt(6, 15), control: pt(4, 15))
            p.addLine(to: pt(9, 15))
        case .check:
            p.move(to: pt(5, 12.5)); p.addLine(to: pt(10, 17)); p.addLine(to: pt(19, 7.5))
        case .close:
            p.move(to: pt(6.5, 6.5)); p.addLine(to: pt(17.5, 17.5))
            p.move(to: pt(17.5, 6.5)); p.addLine(to: pt(6.5, 17.5))
        case .refresh:
            p.addArc(center: pt(12, 12), radius: 7, startAngle: .degrees(-40), endAngle: .degrees(270), clockwise: false)
            p.move(to: pt(17.6, 3.6)); p.addLine(to: pt(17.4, 7.6)); p.addLine(to: pt(13.4, 7.4))
        case .arrowDown:
            p.move(to: pt(12, 5)); p.addLine(to: pt(12, 19))
            p.move(to: pt(6.5, 13.5)); p.addLine(to: pt(12, 19)); p.addLine(to: pt(17.5, 13.5))
        case .folder:
            p.move(to: pt(3.5, 17))
            p.addLine(to: pt(3.5, 7.5))
            p.addQuadCurve(to: pt(5.5, 5.5), control: pt(3.5, 5.5))
            p.addLine(to: pt(9.5, 5.5)); p.addLine(to: pt(11.5, 7.5)); p.addLine(to: pt(18.5, 7.5))
            p.addQuadCurve(to: pt(20.5, 9.5), control: pt(20.5, 7.5))
            p.addLine(to: pt(20.5, 17))
            p.addQuadCurve(to: pt(18.5, 19), control: pt(20.5, 19))
            p.addLine(to: pt(5.5, 19))
            p.addQuadCurve(to: pt(3.5, 17), control: pt(3.5, 19))
        case .power:
            p.move(to: pt(12, 3.5)); p.addLine(to: pt(12, 11))
            p.addArc(center: pt(12, 13), radius: 7, startAngle: .degrees(-50), endAngle: .degrees(230), clockwise: false)
        case .chat:
            p.move(to: pt(6.5, 5))
            p.addLine(to: pt(17.5, 5))
            p.addQuadCurve(to: pt(19, 6.5), control: pt(19, 5))
            p.addLine(to: pt(19, 14.5))
            p.addQuadCurve(to: pt(17.5, 16), control: pt(19, 16))
            p.addLine(to: pt(11, 16)); p.addLine(to: pt(7, 19.5)); p.addLine(to: pt(7, 16)); p.addLine(to: pt(6.5, 16))
            p.addQuadCurve(to: pt(5, 14.5), control: pt(5, 16))
            p.addLine(to: pt(5, 6.5))
            p.addQuadCurve(to: pt(6.5, 5), control: pt(5, 5))
        case .radio:
            p.addEllipse(in: CGRect(x: 4.5, y: 4.5, width: 15, height: 15))
        case .map:
            // The meeting in the middle, three topics around it.
            p.addEllipse(in: CGRect(x: 9, y: 9, width: 6, height: 6))
            for (x, y) in [(5.0, 5.5), (19.0, 7.0), (7.0, 19.0)] {
                p.addEllipse(in: CGRect(x: x - 2, y: y - 2, width: 4, height: 4))
            }
            p.move(to: pt(9.6, 10.2)); p.addLine(to: pt(6.6, 6.9))
            p.move(to: pt(14.8, 11.0)); p.addLine(to: pt(17.1, 8.0))
            p.move(to: pt(10.3, 14.6)); p.addLine(to: pt(8.4, 17.3))
        }
    }

    private func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }
}

private struct IconShape: Shape {
    let icon: TideIcon

    func path(in rect: CGRect) -> Path {
        var path = Path()
        icon.draw(&path)
        return path.applying(CGAffineTransform(scaleX: rect.width / 24, y: rect.height / 24).translatedBy(x: rect.minX, y: rect.minY))
    }
}

/// One of Tide's line icons. `weight` is the stroke in the 24-unit grid; `filled` adds a dot
/// in the middle (a selected radio button).
struct Icon: View {
    let icon: TideIcon
    var size: CGFloat = 14
    var weight: CGFloat = 1.8
    var filled = false

    init(_ icon: TideIcon, size: CGFloat = 14, weight: CGFloat = 1.8, filled: Bool = false) {
        self.icon = icon
        self.size = size
        self.weight = weight
        self.filled = filled
    }

    var body: some View {
        IconShape(icon: icon)
            .stroke(style: StrokeStyle(lineWidth: weight * size / 24, lineCap: .round, lineJoin: .round))
            .overlay {
                if filled { Circle().frame(width: size * 0.3, height: size * 0.3) }
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
