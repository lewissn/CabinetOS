import Foundation

// MARK: - Reporting Period

enum ReportingPeriod: String, CaseIterable, Identifiable, Codable {
    case today = "Today"
    case thisWeek = "This Week"
    case thisMonth = "This Month"
    case allTime = "All Time"

    var id: String { rawValue }

    /// Returns (start, end) dates in London timezone.
    func dateRange() -> (start: Date, end: Date) {
        let cal = Calendar.london
        let now = Date()
        let todayStart = cal.startOfDay(for: now)

        switch self {
        case .today:
            let end = cal.date(byAdding: .day, value: 1, to: todayStart)!
            return (todayStart, end)
        case .thisWeek:
            let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
            let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart)!
            return (weekStart, weekEnd)
        case .thisMonth:
            let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now))!
            let monthEnd = cal.date(byAdding: .month, value: 1, to: monthStart)!
            return (monthStart, monthEnd)
        case .allTime:
            // Before the first scan (26 Feb 2026); per-day figures count from
            // the first day with data, not from here. See ReportingService.
            let start = cal.date(from: DateComponents(year: 2020, month: 1, day: 1))!
            let end = cal.date(byAdding: .day, value: 1, to: todayStart)!
            return (start, end)
        }
    }

    /// Number of working days in the period (for "per day" calculations).
    var workingDays: Int {
        let (start, end) = dateRange()
        return Self.workingDays(from: start, to: end)
    }

    /// Weekdays from `start` up to `end` or today, whichever is earlier.
    static func workingDays(from start: Date, to end: Date) -> Int {
        let cal = Calendar.london
        var count = 0
        var date = start
        while date < end && date <= Date() {
            let weekday = cal.component(.weekday, from: date)
            if weekday != 1 && weekday != 7 { count += 1 } // skip Sun & Sat
            date = cal.date(byAdding: .day, value: 1, to: date)!
        }
        return max(count, 1)
    }
}

// MARK: - Stat Groups

struct PackingSpeedStats: Codable {
    let averageCompletionMinutes: Double
    let itemsScannedInPeriod: Int
    let averageItemsPerDay: Double
}

struct CompletionRateStats: Codable {
    let completedConsignments: Int
    let openConsignments: Int
    let totalConsignments: Int
    let completionPercentage: Double
    let totalBoxesPacked: Int
    let averageBoxesPerConsignment: Double
}

struct VolumeStats: Codable {
    let totalConsignments: Int
    let totalBoxes: Int
    let totalItemsScanned: Int
}

// MARK: - Wrap Scoring

/// The single source of truth for wrap points, shared by the instant
/// close-moment reward and the server-backed reports so the two can never
/// disagree.
enum WrapScoring {
    static func points(for boxType: Box.BoxType) -> Int {
        switch boxType {
        case .panel:                      return 3
        case .drawerRunner, .hangingRail: return 2
        case .fittingKit:                 return 1
        }
    }

    static func points(forRawType raw: String) -> Int {
        guard let type = Box.BoxType(rawValue: raw) else { return 1 }
        return points(for: type)
    }

    /// Every tenth box of the day gets a louder celebration.
    static let milestoneInterval = 10
}

// MARK: - Wrap League

/// Quality-first wrapping stats. Points are only awarded for a box that was
/// never reworked, so rushing a box closed never improves a score.
struct WrapLeagueStats: Codable {
    let wrappedBoxes: Int
    let cleanWrappedBoxes: Int
    let cleanWrapPercentage: Double
    /// Consecutive boxes wrapped by anyone without needing a downstream fix.
    let teamCleanStreak: Int
    let cleanWrapPoints: Int
    let standings: [WrapperStanding]
    /// This device's own row, if it wrapped anything in the period.
    let you: WrapperStanding?

    var hasStandings: Bool { !standings.isEmpty }
}

/// Keyed by device rather than typed name — the operator name is free text, so
/// "Dave" and "dave " would otherwise split into two competing rows.
struct WrapperStanding: Identifiable, Codable {
    let deviceId: String
    let name: String
    let wrappedBoxes: Int
    let cleanWrappedBoxes: Int
    let cleanWrapPercentage: Double
    let points: Int

    var id: String { deviceId }
}

// MARK: - Combined Summary

struct ReportingSummary: Codable {
    let period: ReportingPeriod
    let packingSpeed: PackingSpeedStats
    let completionRates: CompletionRateStats
    let volume: VolumeStats
    let wrapLeague: WrapLeagueStats

    static let empty = ReportingSummary(
        period: .today,
        packingSpeed: PackingSpeedStats(
            averageCompletionMinutes: 0,
            itemsScannedInPeriod: 0,
            averageItemsPerDay: 0
        ),
        completionRates: CompletionRateStats(
            completedConsignments: 0,
            openConsignments: 0,
            totalConsignments: 0,
            completionPercentage: 0,
            totalBoxesPacked: 0,
            averageBoxesPerConsignment: 0
        ),
        volume: VolumeStats(
            totalConsignments: 0,
            totalBoxes: 0,
            totalItemsScanned: 0
        ),
        wrapLeague: WrapLeagueStats(
            wrappedBoxes: 0,
            cleanWrappedBoxes: 0,
            cleanWrapPercentage: 0,
            teamCleanStreak: 0,
            cleanWrapPoints: 0,
            standings: [],
            you: nil
        )
    )
}
