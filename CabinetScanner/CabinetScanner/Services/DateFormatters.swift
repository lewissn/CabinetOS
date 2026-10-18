import Foundation

/// Cached `ISO8601DateFormatter` instances. Creating a formatter is expensive
/// (`NSCalendar`/`NSLocale` setup) and we previously instantiated a new one
/// per scan and per decoded JSON row. Reusing a single instance is safe —
/// `ISO8601DateFormatter` is documented as thread-safe for use after
/// configuration.
enum DateFormatters {
    /// Default ISO 8601 (e.g. "2026-04-30T13:25:14Z"). Matches the server's
    /// `Date.toISOString()` output and Postgres `TIMESTAMPTZ` rendering.
    static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// ISO 8601 with fractional seconds (e.g. "2026-04-30T13:25:14.123Z").
    /// Some upstream timestamps include milliseconds — try this if `iso8601`
    /// returns nil.
    static let iso8601WithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Robust parse: try the plain formatter first, then the fractional one.
    static func parseISO8601(_ s: String) -> Date? {
        iso8601.date(from: s) ?? iso8601WithFractional.date(from: s)
    }
}
