import SwiftUI

// MARK: - Provenance Badge
//
// The visual contract for the whole job-index feature: no record is shown
// without saying where it came from. A ShopVOX-confirmed status and a guess
// assembled from a manifest must never look alike.

extension JobDataSource {
    var tint: Color {
        switch self {
        case .live:     return .green
        case .derived:  return .blue
        case .imported: return .indigo
        case .local:    return .purple
        case .inferred: return .orange
        }
    }

    var systemImage: String {
        switch self {
        case .live:     return "dot.radiowaves.left.and.right"
        case .derived:  return "doc.text"
        case .imported: return "tray.and.arrow.down"
        case .local:    return "iphone"
        case .inferred: return "questionmark.circle"
        }
    }
}

struct ProvenanceBadge: View {
    let source: JobDataSource
    var isStale: Bool = false
    var compact: Bool = false

    private var tint: Color { isStale ? .orange : source.tint }

    private var text: String {
        if isStale { return compact ? "Stale" : "May be out of date" }
        return compact ? source.shortLabel : source.label
    }

    private var icon: String {
        isStale ? "clock.badge.exclamationmark" : source.systemImage
    }

    var body: some View {
        Label(text, systemImage: icon)
            .font(compact ? .caption2 : .caption)
            .fontWeight(.medium)
            .foregroundStyle(tint)
            .padding(.horizontal, compact ? 6 : 8)
            .padding(.vertical, compact ? 2 : 4)
            .background(tint.opacity(0.12), in: Capsule())
            // The colour alone is not the message — it is repeated in the
            // label, so this reads correctly without colour vision too.
            .accessibilityLabel(isStale ? "May be out of date" : source.label)
    }
}

// MARK: - Step state chip

struct StepStateChip: View {
    let step: JobStep

    private var tint: Color {
        if step.isComplete { return .green }
        if step.isActive { return .blue }
        if step.isHalted { return .orange }
        return .secondary
    }

    private var icon: String {
        if step.isComplete { return "checkmark.circle.fill" }
        if step.isActive { return "play.circle.fill" }
        if step.isHalted { return "pause.circle.fill" }
        return "circle"
    }

    var body: some View {
        Label(step.displayState, systemImage: icon)
            .font(.caption)
            .foregroundStyle(tint)
            .labelStyle(.titleAndIcon)
    }
}

// MARK: - Due date

/// Renders a due date with its urgency, and never without saying that it is an
/// ORDER due date rather than a scheduled production date.
struct DueDateLabel: View {
    let isoDate: String?
    var isOverdue: Bool = false
    var showsBasis: Bool = false

    var body: some View {
        if let isoDate, let date = JobDateFormatting.parse(isoDate) {
            HStack(spacing: 4) {
                Image(systemName: isOverdue ? "exclamationmark.circle.fill" : "calendar")
                    .font(.caption2)
                Text(JobDateFormatting.medium(date))
                    .font(.caption)
                    .fontWeight(isOverdue ? .semibold : .regular)
                    // A wrapped date reads as two dates. Never wrap it, and
                    // never let it be the element that gets squeezed.
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                if showsBasis {
                    Text("order due")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(isOverdue ? Color.red : Color.secondary)
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
