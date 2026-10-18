import Foundation

/// What the packer is shown the instant a box is closed.
struct WrapReward {
    let points: Int
    let boxesToday: Int
    let pointsToday: Int
    /// Today just overtook the best day this device has ever had.
    let isNewPersonalBest: Bool
    /// Hit a round number of boxes for the day.
    let isMilestone: Bool
    let bestDayBoxes: Int

    /// Boxes still needed to match the best day, once it is within reach.
    var boxesToBeatBest: Int? {
        let remaining = bestDayBoxes - boxesToday
        return (remaining > 0 && remaining <= 5) ? remaining : nil
    }
}

/// Tracks this device's wrapping tally locally so the close-moment reward is
/// instant and survives being offline. Quality figures (streaks, rework) are
/// deliberately not kept here — those need server truth and live in Reports.
@MainActor
final class WrapStatsService: ObservableObject {
    static let shared = WrapStatsService()

    @Published private(set) var boxesToday: Int = 0
    @Published private(set) var pointsToday: Int = 0
    @Published private(set) var bestDayBoxes: Int = 0

    /// Snapshot of the record as it stood this morning, so "new personal best"
    /// fires once when it is overtaken rather than on every box after it.
    private var bestAtDayStart: Int = 0

    private let defaults: UserDefaults

    private enum Key {
        static let day = "wrapStats.dayKey"
        static let boxesToday = "wrapStats.boxesToday"
        static let pointsToday = "wrapStats.pointsToday"
        static let bestDayBoxes = "wrapStats.bestDayBoxes"
        static let bestAtDayStart = "wrapStats.bestAtDayStart"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        bestDayBoxes = defaults.integer(forKey: Key.bestDayBoxes)
        bestAtDayStart = defaults.integer(forKey: Key.bestAtDayStart)
        boxesToday = defaults.integer(forKey: Key.boxesToday)
        pointsToday = defaults.integer(forKey: Key.pointsToday)
        rollOverDayIfNeeded()
    }

    func recordWrap(boxType: Box.BoxType) -> WrapReward {
        rollOverDayIfNeeded()

        let earned = WrapScoring.points(for: boxType)
        boxesToday += 1
        pointsToday += earned

        let beatRecord = bestAtDayStart > 0 && boxesToday == bestAtDayStart + 1
        bestDayBoxes = max(bestDayBoxes, boxesToday)

        persist()

        return WrapReward(
            points: earned,
            boxesToday: boxesToday,
            pointsToday: pointsToday,
            isNewPersonalBest: beatRecord,
            isMilestone: boxesToday % WrapScoring.milestoneInterval == 0,
            bestDayBoxes: bestDayBoxes
        )
    }

    private func rollOverDayIfNeeded() {
        let today = Self.dayKey()
        guard defaults.string(forKey: Key.day) != today else { return }

        defaults.set(today, forKey: Key.day)
        boxesToday = 0
        pointsToday = 0
        bestAtDayStart = bestDayBoxes
        persist()
    }

    private func persist() {
        defaults.set(boxesToday, forKey: Key.boxesToday)
        defaults.set(pointsToday, forKey: Key.pointsToday)
        defaults.set(bestDayBoxes, forKey: Key.bestDayBoxes)
        defaults.set(bestAtDayStart, forKey: Key.bestAtDayStart)
    }

    private static func dayKey(for date: Date = Date()) -> String {
        let c = Calendar.london.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }
}
