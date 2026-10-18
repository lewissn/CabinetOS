import CabinetDesign
import SwiftUI

// MARK: - Today's status strip
//
// Three things the bench looks for first, under the search field: how much of
// today is ready, how long until APC collects, and how much is due tomorrow.
// Each opens the jobs behind it. Every figure comes from the dispatch query;
// before it loads they read "–".

struct TodayStatusStrip: View {
    let intelligence: DispatchIntelligence
    let isLoaded: Bool
    var onToday: () -> Void
    var onAPC: (CourierGroup) -> Void
    var onTomorrow: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            todayCell
            divider
            apcCell
            divider
            tomorrowCell
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(PaperColor.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(PaperColor.border, lineWidth: 1))
    }

    private var divider: some View {
        Rectangle().fill(PaperColor.hairline).frame(width: 1).padding(.vertical, PaperSpace.m)
    }

    // MARK: Today

    private var todayJobs: [DispatchJob] { intelligence.todayJobs }
    private var ready: Int { todayJobs.filter { $0.stage >= .packed }.count }

    private var todayCell: some View {
        Cell(label: "Today", action: onToday) {
            HStack(spacing: PaperSpace.s) {
                if isLoaded && !todayJobs.isEmpty {
                    PaperRing(Double(ready) / Double(todayJobs.count),
                              color: ready == todayJobs.count ? PaperColor.success : PaperColor.accent,
                              lineWidth: 4)
                        .frame(width: 26, height: 26)
                }
                Text(isLoaded ? (todayJobs.isEmpty ? "0" : "\(ready)/\(todayJobs.count)") : "–")
                    .font(.brand(22, .medium, relativeTo: .title3))
                    .monospacedDigit()
                    .foregroundStyle(PaperColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        } caption: {
            Text(!isLoaded ? " " : todayJobs.isEmpty ? "due out" : "ready to go")
        }
    }

    // MARK: APC cut-off

    private var apcGroup: CourierGroup? {
        intelligence.courierGroups.first { $0.shippingMethod.localizedCaseInsensitiveContains("APC") }
    }

    private var apcCell: some View {
        // Ticks over on its own; the rest of the page doesn't redraw for it.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let cutoff = APCCutoff(now: context.date, jobs: apcGroup?.todayJobs ?? [])
            Cell(label: "APC 14:00", action: { if let apcGroup { onAPC(apcGroup) } }) {
                Text(isLoaded ? cutoff.headline : "–")
                    .font(.brand(22, .medium, relativeTo: .title3))
                    .monospacedDigit()
                    .foregroundStyle(cutoff.tone.textColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            } caption: {
                Text(isLoaded ? cutoff.caption : " ")
            }
            .disabled(apcGroup == nil)
        }
    }

    // MARK: Tomorrow

    private var tomorrowCell: some View {
        Cell(label: "Tomorrow", action: onTomorrow) {
            Text(isLoaded ? PaperFormat.int(intelligence.dueTomorrow) : "–")
                .font(.brand(22, .medium, relativeTo: .title3))
                .monospacedDigit()
                .foregroundStyle(PaperColor.ink)
        } caption: {
            let readyTomorrow = intelligence.tomorrowJobs.filter { $0.stage >= .packed }.count
            Text(!isLoaded ? " " : readyTomorrow > 0 ? "\(PaperFormat.int(readyTomorrow)) already packed" : "due out")
        }
    }

    // MARK: Cell

    private struct Cell<Value: View, Caption: View>: View {
        let label: String
        let action: () -> Void
        @ViewBuilder var value: () -> Value
        @ViewBuilder var caption: () -> Caption

        var body: some View {
            Button(action: action) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(label)
                        .paperType(.caption)
                        .foregroundStyle(PaperColor.secondary)
                        .lineLimit(1)
                    value()
                        .frame(minHeight: 28, alignment: .leading)
                    caption()
                        .paperType(.caption, numeric: true)
                        .foregroundStyle(PaperColor.tertiary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, PaperSpace.m)
                .padding(.vertical, PaperSpace.m)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
        }
    }
}

/// APC's 14:00 collection, for the strip. Counts only the APC jobs due today
/// that aren't packed yet: a job already packed has made the cut-off.
private struct APCCutoff {
    let headline: String
    let caption: String
    let tone: Tone

    init(now: Date, jobs: [DispatchJob]) {
        let cal = Calendar.london
        let cutoff = cal.date(bySettingHour: 14, minute: 0, second: 0, of: cal.startOfDay(for: now))!
        let toPack = jobs.filter { $0.stage < .packed }.count

        if jobs.isEmpty {
            headline = "–"
            caption = cal.isDateInWeekend(now) ? "No collection" : "No APC today"
            tone = .neutral
        } else if toPack == 0 {
            headline = "Done"
            caption = "All \(PaperFormat.int(jobs.count)) packed"
            tone = .done
        } else if now >= cutoff {
            headline = "Passed"
            caption = "\(PaperFormat.int(toPack)) not packed"
            tone = .held
        } else {
            let minutes = Int(cutoff.timeIntervalSince(now) / 60)
            headline = minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(minutes % 60)m"
            caption = "\(PaperFormat.int(toPack)) to pack"
            tone = minutes <= 30 ? .held : (minutes <= 90 ? .soon : .neutral)
        }
    }
}

// MARK: - Coming up
//
// Jobs due on each of the next five working days, as bars: green is packed or
// gone, amber is being packed, the rest still to pack. Tap a day for its jobs.

struct ComingUpChart: View {
    let days: [DayLoad]
    var onSelect: (DayLoad) -> Void

    private let barHeight: CGFloat = 96

    var body: some View {
        let peak = max(days.map(\.total).max() ?? 0, 1)
        VStack(alignment: .leading, spacing: PaperSpace.m) {
            HStack(alignment: .bottom, spacing: PaperSpace.s) {
                ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                    Button { onSelect(day) } label: {
                        column(day, isFirst: index == 0, peak: peak)
                    }
                    .buttonStyle(.plain)
                    .disabled(day.total == 0)
                    .accessibilityLabel("\(Format.day(day.date)): \(Format.count(day.total, "job")), \(day.ready) packed")
                }
            }
            HStack(spacing: PaperSpace.l) {
                legend(PaperColor.success, "Packed")
                legend(PaperColor.accent, "Packing")
                legend(PaperColor.dot, "To pack")
            }
        }
    }

    private func column(_ day: DayLoad, isFirst: Bool, peak: Int) -> some View {
        let height = day.total == 0 ? 3 : max(8, barHeight * CGFloat(day.total) / CGFloat(peak))
        let total = CGFloat(max(day.total, 1))
        let toPack = day.total - day.ready - day.packing
        return VStack(spacing: 6) {
            Text(PaperFormat.int(day.total))
                .font(.brand(15, isFirst ? .semibold : .medium, relativeTo: .subheadline))
                .monospacedDigit()
                .foregroundStyle(day.total == 0 ? PaperColor.faint : PaperColor.ink)
            // Stacked from the bottom: what's ready is the solid base.
            VStack(spacing: 0) {
                Rectangle().fill(PaperColor.dot).frame(height: height * CGFloat(toPack) / total)
                Rectangle().fill(PaperColor.accent).frame(height: height * CGFloat(day.packing) / total)
                Rectangle().fill(PaperColor.success).frame(height: height * CGFloat(day.ready) / total)
            }
            .frame(height: height, alignment: .bottom)
            .frame(maxWidth: .infinity)
            .background(day.total == 0 ? PaperColor.track : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .frame(height: barHeight, alignment: .bottom)
            VStack(spacing: 1) {
                Text(isFirst && Calendar.london.isDateInToday(day.date) ? "Today" : Self.weekday.string(from: day.date))
                    .font(.brand(12, isFirst ? .semibold : .regular, relativeTo: .caption))
                    .foregroundStyle(isFirst ? PaperColor.ink : PaperColor.secondary)
                Text(Self.dayNumber.string(from: day.date))
                    .font(.brand(11, .regular, relativeTo: .caption2))
                    .monospacedDigit()
                    .foregroundStyle(PaperColor.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private func legend(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(label).paperType(.caption).foregroundStyle(PaperColor.secondary)
        }
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.timeZone = TimeZone(identifier: "Europe/London")
        f.dateFormat = format
        return f
    }
    private static let weekday = formatter("EEE")
    private static let dayNumber = formatter("d MMM")
}

// MARK: - Which date changes belong on Today

extension AppNotification {
    /// A change that moves a job into today or tomorrow, or out of them.
    /// Everything else waits behind the bell: ShopVOX moves dates often, and
    /// a job going from the 30th to the 6th doesn't change today's work.
    func touchesTodayOrTomorrow(now: Date = .now) -> Bool {
        let cal = Calendar.london
        let today = cal.startOfDay(for: now)
        guard let dayAfter = cal.date(byAdding: .day, value: 2, to: today) else { return false }
        func near(_ raw: String?) -> Bool {
            guard let raw, let date = Self.dayFormatter.date(from: String(raw.prefix(10))) else { return false }
            return date >= today && date < dayAfter
        }
        return near(newDate) || near(previousDate)
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/London")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
