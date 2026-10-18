import Foundation
import UIKit

/// Number and date formatting that matches the design (en-GB, thin numbers, "–" for unknown).
public enum PaperFormat {
    private static let groupedInt: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        f.locale = Locale(identifier: "en_GB")
        return f
    }()

    /// 1840 → "1,840"
    public static func int(_ value: Double) -> String {
        groupedInt.string(from: NSNumber(value: value.rounded())) ?? "\(Int(value.rounded()))"
    }

    public static func int(_ value: Int) -> String { int(Double(value)) }

    /// No trailing zeros: 20 → "20", 12.5 → "12.5", 1.25 → "1.25".
    public static func trimmed(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        if (rounded * 10).rounded() == rounded * 10 { return String(format: "%.1f", rounded) }
        return String(format: "%.2f", rounded)
    }

    /// Fixed decimals: (70, 1) → "70.0".
    public static func fixed(_ value: Double, _ decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f", value)
    }

    /// 0.4 → "+0.4", −0.25 → "−0.3" (true minus sign).
    public static func signed(_ value: Double, decimals: Int = 1) -> String {
        let s = String(format: "%.\(decimals)f", abs(value))
        if (value * pow(10, Double(decimals))).rounded() == 0 { return s }
        return (value > 0 ? "+" : "−") + s
    }

    /// nil → "–"
    public static func optional(_ value: Double?, _ format: (Double) -> String = int) -> String {
        value.map(format) ?? "–"
    }

    /// 85 → "1:25", 3725 → "1:02:05"
    public static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.down)))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%d:%02d", m, sec)
    }

    /// 3300 → "55 min", 4500 → "1 h 15 min"
    public static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    private static func formatter(_ template: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.setLocalizedDateFormatFromTemplate(template)
        return f
    }

    private static let dayMonthF = formatter("d MMM")
    private static let weekdayDayMonthF = formatter("EEE d MMM")
    private static let longF = formatter("EEEE d MMMM")

    /// "21 Sep"
    public static func dayMonth(_ date: Date) -> String { dayMonthF.string(from: date) }
    /// "Sun 18 Oct" (pair with `.paperType(.label)` for the uppercase header style)
    public static func weekdayDayMonth(_ date: Date) -> String { weekdayDayMonthF.string(from: date).replacingOccurrences(of: ",", with: "") }
    /// "Sunday 18 October"
    public static func long(_ date: Date) -> String { longF.string(from: date).replacingOccurrences(of: ",", with: "") }

    /// "Today", "Yesterday", else "Sun 18 Oct".
    public static func relativeDay(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let y = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: y) { return "Yesterday" }
        return weekdayDayMonth(date)
    }
}

/// Lenient number parsing for text fields ("70,4" and "70.4" both work).
public enum PaperNumber {
    public static func double(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty, let value = Double(cleaned), value.isFinite else { return nil }
        return value
    }

    public static func int(_ text: String) -> Int? {
        let cleaned = text.trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? nil : Int(cleaned)
    }
}

/// Haptics, used sparingly: completing something, saving, a quiet milestone.
@MainActor
public enum PaperHaptics {
    public static func completed() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    public static func saved() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    public static func light() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    /// No confetti: a soft tap.
    public static func milestone() { UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.7) }
    public static func attention() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}
