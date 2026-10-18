import SwiftUI

/// Line glyphs on a 24 × 24 grid, drawn with a 1.6 stroke and round caps (like the SVG
/// sources they came from). Add your own by extending the enum's `path(in:)` switch.
public enum PaperGlyph: Sendable, CaseIterable {
    case target, barbell, clock, trend
    case plus, close, chevronDown, chevronLeft, chevronRight, arrowRight, arrowUp
    case swap, search, scan, check
    // Workshop glyphs (CabinetOS concept)
    case today, job, box, truck, printer, bell, station, stock, pause, play, alert, qr, settings, keyboard, minus
    // Added for the CabinetScanner refresh
    case torch, more, offline, sync, trash

    public func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let o = CGPoint(x: rect.midX - 12 * s, y: rect.midY - 12 * s)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o.x + x * s, y: o.y + y * s) }
        func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> CGRect {
            CGRect(x: o.x + (cx - r) * s, y: o.y + (cy - r) * s, width: 2 * r * s, height: 2 * r * s)
        }
        var path = Path()
        switch self {
        case .target:
            path.addEllipse(in: circle(12, 12, 8)); path.addEllipse(in: circle(12, 12, 3))
        case .barbell:
            path.move(to: p(3, 12)); path.addLine(to: p(5, 12))
            path.move(to: p(19, 12)); path.addLine(to: p(21, 12))
            path.move(to: p(7, 8)); path.addLine(to: p(7, 16))
            path.move(to: p(17, 8)); path.addLine(to: p(17, 16))
            path.move(to: p(7, 12)); path.addLine(to: p(17, 12))
        case .clock:
            path.addEllipse(in: circle(12, 12, 8))
            path.move(to: p(12, 4)); path.addLine(to: p(12, 12)); path.addLine(to: p(18, 16))
        case .trend:
            path.move(to: p(4, 20)); path.addLine(to: p(20, 20))
            path.move(to: p(6, 16)); path.addLine(to: p(10, 11)); path.addLine(to: p(13, 14)); path.addLine(to: p(18, 7))
        case .plus:
            path.move(to: p(12, 5)); path.addLine(to: p(12, 19)); path.move(to: p(5, 12)); path.addLine(to: p(19, 12))
        case .close:
            path.move(to: p(6, 6)); path.addLine(to: p(18, 18)); path.move(to: p(18, 6)); path.addLine(to: p(6, 18))
        case .chevronDown:
            path.move(to: p(6, 9)); path.addLine(to: p(12, 15)); path.addLine(to: p(18, 9))
        case .chevronLeft:
            path.move(to: p(15, 6)); path.addLine(to: p(9, 12)); path.addLine(to: p(15, 18))
        case .chevronRight:
            path.move(to: p(9, 6)); path.addLine(to: p(15, 12)); path.addLine(to: p(9, 18))
        case .arrowRight:
            path.move(to: p(5, 12)); path.addLine(to: p(19, 12))
            path.move(to: p(13, 6)); path.addLine(to: p(19, 12)); path.addLine(to: p(13, 18))
        case .arrowUp:
            path.move(to: p(12, 19)); path.addLine(to: p(12, 5))
            path.move(to: p(5, 12)); path.addLine(to: p(12, 5)); path.addLine(to: p(19, 12))
        case .swap:
            path.move(to: p(7, 7)); path.addLine(to: p(18, 7)); path.addLine(to: p(15, 4))
            path.move(to: p(17, 17)); path.addLine(to: p(6, 17)); path.addLine(to: p(9, 20))
        case .search:
            path.addEllipse(in: circle(11, 11, 6)); path.move(to: p(20, 20)); path.addLine(to: p(15.5, 15.5))
        case .scan:
            path.move(to: p(4, 8)); path.addLine(to: p(4, 5)); path.addLine(to: p(7, 5))
            path.move(to: p(17, 5)); path.addLine(to: p(20, 5)); path.addLine(to: p(20, 8))
            path.move(to: p(20, 16)); path.addLine(to: p(20, 19)); path.addLine(to: p(17, 19))
            path.move(to: p(7, 19)); path.addLine(to: p(4, 19)); path.addLine(to: p(4, 16))
            for x in [CGFloat(9), 12, 15] { path.move(to: p(x, 9)); path.addLine(to: p(x, 15)) }
        case .check:
            path.move(to: p(5, 12)); path.addLine(to: p(10, 17)); path.addLine(to: p(19, 7))
        case .today:
            path.addEllipse(in: circle(12, 12, 4))
            for (a, b, c, d) in [(12.0, 2.5, 12.0, 4.5), (12, 19.5, 12, 21.5), (2.5, 12, 4.5, 12), (19.5, 12, 21.5, 12),
                                 (5.3, 5.3, 6.7, 6.7), (17.3, 17.3, 18.7, 18.7), (5.3, 18.7, 6.7, 17.3), (17.3, 6.7, 18.7, 5.3)] {
                path.move(to: p(a, b)); path.addLine(to: p(c, d))
            }
        case .job:
            path.addRoundedRect(in: CGRect(x: o.x + 5 * s, y: o.y + 4 * s, width: 14 * s, height: 17 * s), cornerSize: CGSize(width: 2 * s, height: 2 * s))
            path.move(to: p(9, 4)); path.addLine(to: p(9, 6)); path.addLine(to: p(15, 6)); path.addLine(to: p(15, 4))
            path.move(to: p(8.5, 11)); path.addLine(to: p(15.5, 11))
            path.move(to: p(8.5, 15)); path.addLine(to: p(13, 15))
        case .box:
            path.move(to: p(12, 3)); path.addLine(to: p(20, 7.5)); path.addLine(to: p(20, 16.5)); path.addLine(to: p(12, 21))
            path.addLine(to: p(4, 16.5)); path.addLine(to: p(4, 7.5)); path.closeSubpath()
            path.move(to: p(4, 7.5)); path.addLine(to: p(12, 12)); path.addLine(to: p(20, 7.5))
            path.move(to: p(12, 12)); path.addLine(to: p(12, 21))
        case .truck:
            path.move(to: p(2.5, 6)); path.addLine(to: p(14, 6)); path.addLine(to: p(14, 16)); path.addLine(to: p(2.5, 16)); path.closeSubpath()
            path.move(to: p(14, 9)); path.addLine(to: p(18, 9)); path.addLine(to: p(21.5, 12.5)); path.addLine(to: p(21.5, 16)); path.addLine(to: p(14, 16))
            path.addEllipse(in: circle(7, 17.5, 1.8)); path.addEllipse(in: circle(17.5, 17.5, 1.8))
        case .printer:
            path.move(to: p(7, 9)); path.addLine(to: p(7, 4)); path.addLine(to: p(17, 4)); path.addLine(to: p(17, 9))
            path.addRoundedRect(in: CGRect(x: o.x + 3.5 * s, y: o.y + 9 * s, width: 17 * s, height: 8 * s), cornerSize: CGSize(width: 2 * s, height: 2 * s))
            path.move(to: p(7, 14)); path.addLine(to: p(7, 20)); path.addLine(to: p(17, 20)); path.addLine(to: p(17, 14)); path.closeSubpath()
        case .bell:
            path.move(to: p(6, 16.5)); path.addLine(to: p(6, 11))
            path.addCurve(to: p(18, 11), control1: p(6, 4.5), control2: p(18, 4.5))
            path.addLine(to: p(18, 16.5)); path.addLine(to: p(19.5, 18)); path.addLine(to: p(4.5, 18)); path.closeSubpath()
            path.move(to: p(10, 20.5)); path.addLine(to: p(14, 20.5))
        case .station:
            path.addEllipse(in: circle(12, 12, 7.5)); path.addEllipse(in: circle(12, 12, 2))
            for a in stride(from: 0.0, to: 360.0, by: 60.0) {
                let r = a * .pi / 180
                path.move(to: p(12 + 2 * cos(r), 12 + 2 * sin(r))); path.addLine(to: p(12 + 7.5 * cos(r + 0.5), 12 + 7.5 * sin(r + 0.5)))
            }
        case .stock:
            path.move(to: p(12, 4)); path.addLine(to: p(21, 8.5)); path.addLine(to: p(12, 13)); path.addLine(to: p(3, 8.5)); path.closeSubpath()
            path.move(to: p(3, 12.5)); path.addLine(to: p(12, 17)); path.addLine(to: p(21, 12.5))
            path.move(to: p(3, 16.5)); path.addLine(to: p(12, 21)); path.addLine(to: p(21, 16.5))
        case .pause:
            path.move(to: p(9, 6)); path.addLine(to: p(9, 18)); path.move(to: p(15, 6)); path.addLine(to: p(15, 18))
        case .play:
            path.move(to: p(8, 5.5)); path.addLine(to: p(18.5, 12)); path.addLine(to: p(8, 18.5)); path.closeSubpath()
        case .alert:
            path.move(to: p(12, 3.5)); path.addLine(to: p(21, 19.5)); path.addLine(to: p(3, 19.5)); path.closeSubpath()
            path.move(to: p(12, 9.5)); path.addLine(to: p(12, 13.5)); path.move(to: p(12, 16.5)); path.addLine(to: p(12, 16.6))
        case .qr:
            for (x, y) in [(4.0, 4.0), (14, 4), (4, 14)] {
                path.addRect(CGRect(x: o.x + x * s, y: o.y + y * s, width: 6 * s, height: 6 * s))
            }
            path.move(to: p(14, 14)); path.addLine(to: p(17, 14)); path.move(to: p(20, 14)); path.addLine(to: p(20, 17))
            path.move(to: p(14, 17)); path.addLine(to: p(14, 20)); path.addLine(to: p(20, 20)); path.move(to: p(17, 17)); path.addLine(to: p(17, 17.1))
        case .settings:
            path.move(to: p(4, 7)); path.addLine(to: p(20, 7)); path.move(to: p(4, 12)); path.addLine(to: p(20, 12)); path.move(to: p(4, 17)); path.addLine(to: p(20, 17))
            path.addEllipse(in: circle(9, 7, 1.8)); path.addEllipse(in: circle(15, 12, 1.8)); path.addEllipse(in: circle(8, 17, 1.8))
        case .keyboard:
            path.addRoundedRect(in: CGRect(x: o.x + 2.5 * s, y: o.y + 6 * s, width: 19 * s, height: 12 * s), cornerSize: CGSize(width: 2 * s, height: 2 * s))
            for x in [6.0, 9.5, 13, 16.5] { path.move(to: p(x, 10)); path.addLine(to: p(x + 0.1, 10)) }
            path.move(to: p(8, 14)); path.addLine(to: p(16, 14))
        case .minus:
            path.move(to: p(5, 12)); path.addLine(to: p(19, 12))
        case .torch:
            path.move(to: p(7, 3.5)); path.addLine(to: p(17, 3.5)); path.addLine(to: p(17, 7)); path.addLine(to: p(14.5, 11))
            path.addLine(to: p(14.5, 20.5)); path.addLine(to: p(9.5, 20.5)); path.addLine(to: p(9.5, 11)); path.addLine(to: p(7, 7)); path.closeSubpath()
            path.move(to: p(7, 7)); path.addLine(to: p(17, 7))
            path.move(to: p(12, 13.5)); path.addLine(to: p(12, 15.5))
        case .more:
            for x in [CGFloat(6), 12, 18] { path.addEllipse(in: circle(x, 12, 0.9)) }
        case .offline:
            path.addArc(center: p(12, 19), radius: 4 * s, startAngle: .degrees(225), endAngle: .degrees(315), clockwise: false)
            path.move(to: p(12 + 8.5 * cos(.pi * 1.25), 19 + 8.5 * sin(.pi * 1.25)))
            path.addArc(center: p(12, 19), radius: 8.5 * s, startAngle: .degrees(225), endAngle: .degrees(315), clockwise: false)
            path.move(to: p(12, 19)); path.addLine(to: p(12, 19.1))
            path.move(to: p(4, 4)); path.addLine(to: p(20, 20))
        case .sync:
            path.addArc(center: p(12, 12), radius: 7 * s, startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false)
            path.move(to: p(18.6, 5.6)); path.addLine(to: p(18.6, 9.6)); path.addLine(to: p(14.8, 9.6))
            path.move(to: p(12 + 7 * cos(.pi / 9), 12 + 7 * sin(.pi / 9)))
            path.addArc(center: p(12, 12), radius: 7 * s, startAngle: .degrees(20), endAngle: .degrees(160), clockwise: false)
            path.move(to: p(5.4, 18.4)); path.addLine(to: p(5.4, 14.4)); path.addLine(to: p(9.2, 14.4))
        case .trash:
            path.move(to: p(4.5, 7)); path.addLine(to: p(19.5, 7))
            path.move(to: p(9.5, 7)); path.addLine(to: p(9.5, 4.5)); path.addLine(to: p(14.5, 4.5)); path.addLine(to: p(14.5, 7))
            path.move(to: p(6.5, 7)); path.addLine(to: p(7.5, 20)); path.addLine(to: p(16.5, 20)); path.addLine(to: p(17.5, 7))
            path.move(to: p(10.5, 11)); path.addLine(to: p(10.5, 16)); path.move(to: p(13.5, 11)); path.addLine(to: p(13.5, 16))
        }
        return path
    }
}

public struct PaperGlyphShape: Shape {
    let glyph: PaperGlyph
    public init(_ glyph: PaperGlyph) { self.glyph = glyph }
    public func path(in rect: CGRect) -> Path { glyph.path(in: rect) }
}

/// A glyph at a size. `lineWidth` is in 24-unit glyph space, like an SVG stroke-width.
public struct PaperIcon: View {
    let glyph: PaperGlyph
    let size: CGFloat
    let lineWidth: CGFloat
    let color: Color

    public init(_ glyph: PaperGlyph, size: CGFloat = 18, lineWidth: CGFloat = 1.6, color: Color = PaperColor.ink) {
        self.glyph = glyph
        self.size = size
        self.lineWidth = lineWidth
        self.color = color
    }

    public var body: some View {
        PaperGlyphShape(glyph)
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth * size / 24, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
