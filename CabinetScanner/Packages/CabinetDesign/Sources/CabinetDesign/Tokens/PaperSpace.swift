import SwiftUI

/// Spacing scale (pt). Side margins are 28 pt everywhere.
public enum PaperSpace {
    public static let xxs: CGFloat = 4
    public static let xs: CGFloat = 6
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
    public static let l: CGFloat = 16
    public static let xl: CGFloat = 20
    public static let xxl: CGFloat = 24
    public static let section: CGFloat = 32
    public static let margin: CGFloat = 28
    /// Minimum hit target.
    public static let tap: CGFloat = 44
}

/// 1 px hairline: the only separator (no cards, no shadows).
public struct PaperHairline: View {
    let color: Color

    public init(color: Color = PaperColor.hairline) {
        self.color = color
    }

    public var body: some View {
        Rectangle()
            .fill(color)
            .frame(height: 1 / UIScreen.main.scale)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}

public extension View {
    /// Standard 28 pt side margins.
    func paperMargins() -> some View {
        padding(.horizontal, PaperSpace.margin)
    }

    /// Paper background filling the screen, including behind the safe areas.
    func paperBackground() -> some View {
        background(PaperColor.paper.ignoresSafeArea())
    }

    /// Paper band behind the status bar so scrolled content never shows through it. Put this
    /// on your root view when you hide the navigation bar.
    func paperStatusBarBackdrop() -> some View {
        overlay(alignment: .top) {
            Color.clear.frame(height: 0).background(PaperColor.paper.ignoresSafeArea(edges: .top))
        }
    }
}

/// Motion: one gentle spring for shared-element transitions; Reduce Motion gets a crossfade.
public enum PaperMotion {
    public static let spring = Animation.spring(response: 0.5, dampingFraction: 0.88)
    public static let fade = Animation.easeInOut(duration: 0.25)

    public static func transition(reduceMotion: Bool) -> Animation {
        reduceMotion ? fade : spring
    }
}

public extension View {
    /// `matchedGeometryEffect` that can be switched off (pass `!reduceMotion`).
    @ViewBuilder
    func paperMatched(_ id: String, in ns: Namespace.ID, enabled: Bool) -> some View {
        if enabled { matchedGeometryEffect(id: id, in: ns) } else { self }
    }
}
