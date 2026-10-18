import CoreText
import SwiftUI

/// Plus Jakarta Sans (SIL Open Font License 1.1), the website's and Cabinet Lab's typeface. One variable
/// font (the theme's `PlusJakartaSans-latin.woff2`); each weight is a named instance.
public enum BrandWeight: String, CaseIterable, Sendable {
    case light = "PlusJakartaSans-Regular_Light"
    case regular = "PlusJakartaSans-Regular"
    case medium = "PlusJakartaSans-Regular_Medium"
    case semibold = "PlusJakartaSans-Regular_SemiBold"
}

/// Registers the bundled font once. Called automatically the first time a brand font
/// is requested; host apps don't need to touch Info.plist.
public enum PaperFonts {
    private static let registered: Bool = {
        if let url = Bundle.module.url(forResource: "PlusJakartaSans", withExtension: "woff2", subdirectory: "Fonts")
            ?? Bundle.module.url(forResource: "PlusJakartaSans", withExtension: "woff2") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        return true
    }()

    /// Call early (e.g. in your App's init) if you want registration to happen up front.
    @discardableResult
    public static func register() -> Bool { registered }
}

public extension Font {
    /// The brand font at a size that scales with Dynamic Type relative to `style`.
    static func brand(_ size: CGFloat, _ weight: BrandWeight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        PaperFonts.register()
        return .custom(weight.rawValue, size: size, relativeTo: style)
    }

    /// Fixed-size brand font for places that mustn't grow (chart axes, Live Activities).
    static func brandFixed(_ size: CGFloat, _ weight: BrandWeight = .regular) -> Font {
        PaperFonts.register()
        return .custom(weight.rawValue, fixedSize: size)
    }
}

/// The type scale. Sizes in pt, tracking in em. Hero numbers are Light with tight tracking;
/// labels are small and in sentence case; numbers that change use tabular figures.
public enum PaperType: CaseIterable, Sendable {
    case heroXL        // 76 light
    case hero          // 60 light
    case heroM         // 56 light
    case heroInput     // 52 light: big numeric entry
    case heroS         // 44 light
    case largeTitle    // 34 semibold: screen titles
    case greeting      // 26 semibold
    case title         // 24 semibold
    case figure        // 24 regular
    case timer         // 30 light
    case headline      // 20 medium
    case figureS       // 20 regular
    case statFigure    // 22 light
    case bodyL         // 17 regular
    case body          // 16 regular: list rows
    case button        // 15 medium
    case callout       // 15 regular
    case subhead       // 14 regular
    case footnote      // 13 regular
    case caption       // 12 regular
    case label         // 13 medium, sentence case (Cabinet Lab: no uppercase labels)
    case micro         // 10 regular

    public var size: CGFloat {
        switch self {
        case .heroXL: 76
        case .hero: 60
        case .heroM: 56
        case .heroInput: 52
        case .heroS: 44
        case .largeTitle: 32
        case .greeting: 26
        case .title, .figure: 24
        case .timer: 30
        case .headline, .figureS: 20
        case .statFigure: 22
        case .bodyL: 17
        case .body: 16
        case .button, .callout: 15
        case .subhead: 14
        case .footnote: 13
        case .caption: 12
        case .label: 13
        case .micro: 10
        }
    }

    public var weight: BrandWeight {
        switch self {
        case .heroXL, .hero, .heroM, .heroInput, .heroS, .timer, .statFigure: .light
        case .largeTitle, .greeting, .title: .semibold
        case .headline, .button, .label: .medium
        default: .regular
        }
    }

    public var trackingEm: CGFloat {
        switch self {
        case .heroXL, .hero, .heroM, .heroS: -0.035
        case .heroInput: -0.04
        case .largeTitle: -0.025
        case .greeting, .title, .figure, .timer: -0.02
        case .headline: -0.02
        default: 0
        }
    }

    public var relativeTo: Font.TextStyle {
        switch self {
        case .heroXL, .hero, .heroM, .heroInput, .heroS, .largeTitle: .largeTitle
        case .greeting, .title, .figure, .timer: .title
        case .headline, .figureS, .statFigure: .title3
        case .bodyL, .body: .body
        case .button, .callout: .callout
        case .subhead, .footnote: .subheadline
        case .caption: .caption
        case .label, .micro: .caption2
        }
    }

    public var font: Font { .brand(size, weight, relativeTo: relativeTo) }
    public var tracking: CGFloat { trackingEm * size }
}

private struct PaperTypeModifier: ViewModifier {
    let style: PaperType
    let numeric: Bool

    func body(content: Content) -> some View {
        let base = content.font(style.font).tracking(style.tracking)
        if style == .label || numeric {
            base.monospacedDigit()
        } else {
            base
        }
    }
}

public extension View {
    /// Apply a type style. `numeric: true` turns on tabular figures for numbers that change.
    func paperType(_ style: PaperType, numeric: Bool = false) -> some View {
        modifier(PaperTypeModifier(style: style, numeric: numeric))
    }
}

/// Small section label in sentence case, e.g. "Leaving today".
public struct PaperLabel: View {
    let text: String
    let color: Color

    public init(_ text: String, color: Color = PaperColor.secondary) {
        self.text = text
        self.color = color
    }

    public var body: some View {
        Text(text)
            .paperType(.label)
            .foregroundStyle(color)
            .accessibilityAddTraits(.isHeader)
    }
}
