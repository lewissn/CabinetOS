import SwiftUI

/// Pill buttons. Amber is the one primary action (ink text on it); ink, paper (on dark surfaces),
/// outline and danger are secondary. Labels never truncate.
public struct PaperPillStyle: ButtonStyle {
    public enum Kind: Sendable { case accent, ink, paper, outline, danger }
    public enum Size: Sendable {
        case compact   // 40 pt, e.g. "Begin"
        case regular   // 48 pt
        case large     // 52 pt, full-width primary
        case floor     // 60 pt: shop-floor actions, used with gloves at arm's length

        var height: CGFloat { switch self { case .compact: 40; case .regular: 48; case .large: 52; case .floor: 60 } }
        var padding: CGFloat { switch self { case .compact: 18; case .regular: 20; case .large: 24; case .floor: 28 } }
    }

    var kind: Kind
    var size: Size
    var fullWidth: Bool

    public init(kind: Kind = .accent, size: Size = .large, fullWidth: Bool = false) {
        self.kind = kind
        self.size = size
        self.fullWidth = fullWidth
    }

    public func makeBody(configuration: Configuration) -> some View {
        PillBody(configuration: configuration, kind: kind, size: size, fullWidth: fullWidth)
    }

    private struct PillBody: View {
        let configuration: Configuration
        let kind: Kind
        let size: Size
        let fullWidth: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .paperType(.button)
                .lineLimit(1)
                .fixedSize(horizontal: !fullWidth, vertical: false)
                .foregroundStyle(foreground)
                .padding(.horizontal, size.padding)
                .frame(minHeight: size.height)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .background(background, in: Capsule())
                .overlay {
                    if kind == .outline || kind == .danger { Capsule().strokeBorder(kind == .danger ? PaperColor.danger.opacity(0.5) : PaperColor.border, lineWidth: 1) }
                }
                .opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.4)
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
                .contentShape(Capsule())
        }

        private var foreground: Color {
            switch kind {
            case .accent: PaperColor.onAccent
            case .ink: PaperColor.paper
            case .paper, .outline: PaperColor.ink
            case .danger: PaperColor.danger
            }
        }

        private var background: Color {
            switch kind {
            case .accent: PaperColor.accent
            case .ink: PaperColor.ink
            case .paper: PaperColor.onInverse
            case .outline, .danger: .clear
            }
        }
    }
}

/// Plain text button with a 44 pt hit target.
public struct PaperTextStyle: ButtonStyle {
    var color: Color
    var style: PaperType
    var weight: BrandWeight?

    public init(color: Color = PaperColor.body, style: PaperType = .subhead, weight: BrandWeight? = nil) {
        self.color = color
        self.style = style
        self.weight = weight
    }

    public func makeBody(configuration: Configuration) -> some View {
        TextBody(configuration: configuration, color: color, style: style, weight: weight)
    }

    private struct TextBody: View {
        let configuration: Configuration
        let color: Color
        let style: PaperType
        let weight: BrandWeight?
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(weight.map { .brand(style.size, $0, relativeTo: style.relativeTo) } ?? style.font)
                .foregroundStyle(color)
                .frame(minHeight: PaperSpace.tap)
                .contentShape(Rectangle())
                .opacity(isEnabled ? (configuration.isPressed ? 0.55 : 1) : 0.35)
        }
    }
}

/// Outlined chip (34 pt, 44 pt hit target). Selected chips are filled ink.
public struct PaperChipStyle: ButtonStyle {
    var selected: Bool

    public init(selected: Bool = false) {
        self.selected = selected
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .paperType(.footnote, numeric: true)
            .lineLimit(1)
            .foregroundStyle(selected ? PaperColor.paper : PaperColor.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: 34)
            .background(selected ? PaperColor.ink : .clear, in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? PaperColor.ink : PaperColor.border, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
            .padding(.vertical, 5)
    }
}

/// Square 44 pt icon button.
public struct PaperIconButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: PaperSpace.tap, height: PaperSpace.tap)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.5 : 1)
    }
}

public extension ButtonStyle where Self == PaperPillStyle {
    /// Full-width amber primary button.
    static var paperPrimary: PaperPillStyle { PaperPillStyle(kind: .accent, size: .large, fullWidth: true) }
    static func paperPill(_ kind: PaperPillStyle.Kind = .accent, _ size: PaperPillStyle.Size = .large, fullWidth: Bool = false) -> PaperPillStyle {
        PaperPillStyle(kind: kind, size: size, fullWidth: fullWidth)
    }
}

public extension ButtonStyle where Self == PaperTextStyle {
    static func paperText(_ color: Color = PaperColor.body, _ style: PaperType = .subhead, weight: BrandWeight? = nil) -> PaperTextStyle {
        PaperTextStyle(color: color, style: style, weight: weight)
    }
}

public extension ButtonStyle where Self == PaperChipStyle {
    static func paperChip(selected: Bool = false) -> PaperChipStyle { PaperChipStyle(selected: selected) }
}

public extension ButtonStyle where Self == PaperIconButtonStyle {
    static var paperIcon: PaperIconButtonStyle { PaperIconButtonStyle() }
}
