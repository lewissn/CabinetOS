import CabinetDesign
import SwiftUI

// MARK: - Provenance Badge
//
// The visual contract for the whole job-index feature: no record is shown
// without saying where it came from. A ShopVOX-confirmed status and a guess
// assembled from a manifest must never look alike. Drawn quietly: a small
// dot and words, so it informs without competing with the job.

extension JobDataSource {
    /// Only a guess is coloured (orange: check it). Green is kept for done.
    var tone: Tone { self == .inferred ? .soon : .neutral }
}

struct ProvenanceBadge: View {
    let source: JobDataSource
    var isStale: Bool = false
    var compact: Bool = false

    private var tone: Tone { isStale ? .soon : source.tone }

    private var dotColor: Color { tone == .soon ? PaperColor.warning : PaperColor.muted }
    private var isHollow: Bool { tone != .soon && (source == .derived || source == .imported) }

    private var text: String {
        if isStale { return compact ? "Stale" : "May be out of date" }
        return compact ? source.shortLabel : source.label
    }

    var body: some View {
        HStack(spacing: 5) {
            // Filled for a confirmed or tracked record, hollow for one taken
            // from an export or an order, orange for a guess or a stale one.
            Circle()
                .strokeBorder(dotColor, lineWidth: 1.2)
                .background(Circle().fill(isHollow ? .clear : dotColor))
                .frame(width: 6, height: 6)
            Text(text)
                .paperType(compact ? .caption : .footnote)
                .foregroundStyle(PaperColor.tertiary)
                .lineLimit(1)
        }
        // The colour alone is not the message — it is repeated in the
        // label, so this reads correctly without colour vision too.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isStale ? "May be out of date" : source.label)
    }
}

// MARK: - Step state

extension JobStep {
    /// ShopVOX may mark a step skipped; drawn hatched on the track.
    var isSkipped: Bool { state == "skipped" }

    var tone: Tone {
        if isComplete { return .done }
        if isActive || isHalted { return .progress }
        return .neutral
    }
}

struct StepStateChip: View {
    let step: JobStep

    var body: some View {
        StatusText(step.displayState, tone: step.tone)
    }
}

// MARK: - Due date

/// How a due date reads: "Late · Tue 14 Oct" in red, "Due today" in orange,
/// else "Due Thu 23 Oct". Always the ORDER due date, never a schedule.
enum DueLine {
    static func make(isoDate: String?, isOverdue: Bool = false, now: Date = .now) -> (text: String, tone: Tone)? {
        guard let isoDate, let date = JobDateFormatting.parse(isoDate) else { return nil }
        let cal = Calendar.london
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: date)).day ?? 0
        let day = JobDateFormatting.medium(date)
        if isOverdue || days < 0 { return ("Late · \(day)", .held) }
        if days == 0 { return ("Due today", .soon) }
        if days == 1 { return ("Due tomorrow", .neutral) }
        return ("Due \(day)", .neutral)
    }
}

extension DueLine {
    /// For beside a date that's already shown: "2 days late", "Today",
    /// "Tomorrow", "In 5 days".
    static func relative(isoDate: String?, now: Date = .now) -> (text: String, tone: Tone)? {
        guard let isoDate, let date = JobDateFormatting.parse(isoDate) else { return nil }
        let cal = Calendar.london
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: date)).day ?? 0
        switch days {
        case ..<0: return ("\(Format.count(-days, "day")) late", .held)
        case 0: return ("Today", .soon)
        case 1: return ("Tomorrow", .neutral)
        default: return ("In \(Format.count(days, "day"))", .neutral)
        }
    }
}

/// Renders a due date with its urgency, and never without saying that it is an
/// ORDER due date rather than a scheduled production date.
struct DueDateLabel: View {
    let isoDate: String?
    var isOverdue: Bool = false
    var showsBasis: Bool = false

    var body: some View {
        if let line = DueLine.make(isoDate: isoDate, isOverdue: isOverdue) {
            HStack(spacing: 4) {
                StatusText(line.text, tone: line.tone)
                    // A wrapped date reads as two dates. Never wrap it, and
                    // never let it be the element that gets squeezed.
                    .fixedSize(horizontal: true, vertical: false)
                if showsBasis {
                    Text("order due")
                        .paperType(.caption)
                        .foregroundStyle(PaperColor.tertiary)
                        .lineLimit(1)
                }
            }
            .layoutPriority(1)
        }
    }
}

// MARK: - Date helpers

enum JobDateFormatting {
    /// The API sends plain YYYY-MM-DD. Parsed in Europe/London so a date never
    /// shifts a day when the device is set to another timezone.
    static func parse(_ iso: String) -> Date? {
        formatter.date(from: iso)
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_GB")
        f.timeZone = TimeZone(identifier: "Europe/London")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let display: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.timeZone = TimeZone(identifier: "Europe/London")
        f.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return f
    }()

    static func medium(_ date: Date) -> String { display.string(from: date) }

    /// "3 days ago" for a capture timestamp, so freshness is legible at a glance.
    static func relative(fromISO8601 iso: String?) -> String? {
        guard let iso, let date = iso8601.date(from: iso) else { return nil }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: date, relativeTo: Date())
    }

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
