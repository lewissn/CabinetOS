import Foundation

// MARK: - APC Deadline Job

struct APCDeadlineJob: Identifiable {
    let id: String
    let customer: String
    let salesOrder: String
    let shippingMethod: String
    let dueDate: Date
}

// MARK: - APC Deadline State

struct APCDeadlineState {
    let jobs: [APCDeadlineJob]
    let cutoffDate: Date      // 2pm London today
    let now: Date

    var count: Int { jobs.count }
    var isEmpty: Bool { jobs.isEmpty }

    var minutesRemaining: Int {
        max(0, Int(cutoffDate.timeIntervalSince(now) / 60))
    }

    var isPastCutoff: Bool { now >= cutoffDate }

    var timeRemainingText: String {
        if isPastCutoff { return "OVERDUE" }
        let mins = minutesRemaining
        if mins < 60 { return "\(mins)m remaining" }
        let h = mins / 60
        let m = mins % 60
        if m == 0 { return "\(h)h remaining" }
        return "\(h)h \(m)m remaining"
    }

    var urgencyLevel: APCUrgency {
        if isPastCutoff { return .overdue }
        if minutesRemaining <= 30 { return .critical }
        if minutesRemaining <= 90 { return .warning }
        return .normal
    }

    static let empty = APCDeadlineState(jobs: [], cutoffDate: Date(), now: Date())
}

// MARK: - Urgency Levels

enum APCUrgency {
    case normal      // > 90 min remaining  → orange
    case warning     // 30–90 min remaining → dark orange
    case critical    // < 30 min remaining  → red, pulsing
    case overdue     // past 2pm            → red
}
