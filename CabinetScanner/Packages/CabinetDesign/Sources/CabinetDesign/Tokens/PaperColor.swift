import SwiftUI
import UIKit

/// Colour tokens: Paper's structure with Cabinet Lab's values
/// (TheHub `apps/web/src/app/globals.css`, warmer light theme from decision #205, and its dark theme).
///
/// Rules of use:
/// - `accent` amber is for the one primary action and the current place, never text. Amber text
///   uses `accentInk`; text on an amber surface is `onAccent` (ink).
/// - Status colours carry Cabinet Lab's meanings: success = done, progress (amber) = ours and moving or
///   paused, warning = act soon, danger = held up, late or a wrong scan, info = the customer's move.
/// - No cards: separate sections with whitespace and `hairline` rules.
public enum PaperColor {
    // Surfaces
    public static let paper = Color(light: 0xF3F1EC, dark: 0x121211)
    public static let surface = Color(light: 0xFFFDFA, dark: 0x1B1B1A)
    public static let raised = Color(light: 0xFFFDFA, dark: 0x2A2927)       // selected segment
    public static let segment = Color(light: 0xE9E6DF, dark: 0x242422)      // segmented control track
    public static let inverse = Color(light: 0x1B1B1A, dark: 0x242422)      // dark bars (viewfinder, timers)
    public static let onInverse = Color(light: 0xF3F1EC, dark: 0xF1F0EC)
    public static let onInverseMuted = Color(light: 0xA3A09A, dark: 0xA09E98)
    public static let inverseTrack = Color(light: 0x3A3936, dark: 0x43413D)

    // Text
    public static let ink = Color(light: 0x1B1B1A, dark: 0xF1F0EC)
    public static let body = Color(light: 0x4D4C49, dark: 0xC7C5BF)
    public static let secondary = Color(light: 0x63625E, dark: 0xA09E98)
    public static let tertiary = Color(light: 0x75736E, dark: 0x8E8C86)
    public static let faint = Color(light: 0x9A978F, dark: 0x6E6C66)

    // Lines and tracks
    public static let hairline = Color(light: 0xE2DDD3, dark: 0x2F2E2B)
    public static let hairlineSoft = Color(light: 0xEAE6DE, dark: 0x262523)
    public static let track = Color(light: 0xE6E1D8, dark: 0x2F2E2B)
    public static let dot = Color(light: 0xCFC9BE, dark: 0x4A4844)
    public static let border = Color(light: 0xD8D2C7, dark: 0x43413D)
    public static let borderStrong = Color(light: 0xBDB7AC, dark: 0x5C5850)
    public static let muted = Color(light: 0x8C877E, dark: 0x8C877E)

    // Accent (the brand amber: one primary action, the current place)
    public static let accent = Color(light: 0xFAC05E, dark: 0xFAC05E)
    public static let accentHover = Color(light: 0xF5B23F, dark: 0xF5B23F)
    public static let accentSoft = Color(light: 0xFEF4E0, dark: 0x3A2D12)
    public static let accentInk = Color(light: 0x6A4705, dark: 0xF7CF85)
    public static let onAccent = Color(light: 0x1B1B1A, dark: 0x1B1B1A)

    // Ember: the second brand colour, a brick red that sits with the amber.
    // Kept for attention: a deadline closing in, a date pulled forward. Text
    // safe on paper (4.7:1 light, 6.9:1 dark).
    public static let ember = Color(light: 0xB8462B, dark: 0xF07C5E)
    public static let emberSoft = Color(light: 0xFBEAE4, dark: 0x33190F)

    // Status
    public static let success = Color(light: 0x17754A, dark: 0x62CC94)
    public static let successSoft = Color(light: 0xE9F5EE, dark: 0x15291E)
    public static let warning = Color(light: 0xA84C07, dark: 0xF0A861)
    public static let warningSoft = Color(light: 0xFDF0E3, dark: 0x2F2114)
    public static let danger = Color(light: 0xB42318, dark: 0xF58A7F)
    public static let dangerSoft = Color(light: 0xFDECEA, dark: 0x341A17)
    public static let info = Color(light: 0x2B5C9E, dark: 0x8DB4EF)
    public static let infoSoft = Color(light: 0xEDF2FA, dark: 0x17233A)

    /// Four tints of the amber, for composition bars (strongest → palest).
    public static let series: [Color] = [
        Color(light: 0xFAC05E, dark: 0xFAC05E),
        Color(light: 0xC98A1C, dark: 0xD9A040),
        Color(light: 0xFCD996, dark: 0x8A6420),
        Color(light: 0x8A5E0F, dark: 0xF7CF85),
    ]
}

public extension Color {
    /// A colour that switches between two hex values with the trait collection's interface style
    /// (so `.preferredColorScheme` overrides work).
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(paperHex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

public extension UIColor {
    convenience init(paperHex hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
