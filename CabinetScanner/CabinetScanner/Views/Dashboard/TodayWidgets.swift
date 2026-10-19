import CabinetDesign
import SwiftUI

// MARK: - Today, as a dashboard
//
// One screen, no scrolling: a single focal ring for the day that matters,
// three quiet figures, the week's rhythm, and at most one line of news.
// Amber is the brand and means progress; ember (brick red) is kept for the
// few things that need attention. Everything is drawn from the dispatch
// query; before it loads, figures read "–".
//
// Motion is part of reading it: the ring draws in, numbers roll when they
// change, and the bars rise in turn. With Reduce Motion on, all of it simply
// appears.

/// The day the ring is about: today when anything is due today, otherwise
/// the next working day that has jobs. A Monday with nothing due shows
/// Tuesday's load rather than an empty ring.
struct TodayFocus {
    let day: DayLoad?
    let isToday: Bool
    let isTomorrow: Bool

    init(_ intelligence: DispatchIntelligence) {
        let cal = Calendar.london
        let today = cal.startOfDay(for: .now)
        if !intelligence.todayJobs.isEmpty {
            day = DayLoad(date: today, jobs: intelligence.todayJobs)
        } else {
            day = intelligence.workingDays.first { $0.total > 0 }
        }
        isToday = day.map { cal.isDate($0.date, inSameDayAs: today) } ?? false
        isTomorrow = day.map { cal.isDateInTomorrow($0.date) } ?? false
    }

    /// "Today", "Tomorrow", "Thursday"
    var dayName: String {
        guard let day else { return "Next five days" }
        if isToday { return "Today" }
        if isTomorrow { return "Tomorrow" }
        return TodayText.weekdayLong.string(from: day.date)
    }
}

// MARK: Focus ring

struct FocusRing: View {
    let focus: TodayFocus
    let isLoaded: Bool
    let revealed: Bool
    var diameter: CGFloat = 196
    var action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var day: DayLoad? { focus.day }
    private var fraction: Double {
        guard let day, day.total > 0 else { return 0 }
        return Double(day.ready) / Double(day.total)
    }

    /// Scales the type with the ring, so iPad and phone keep the same balance.
    private var scale: CGFloat { diameter / 196 }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().stroke(PaperColor.track, lineWidth: 3)
                Circle()
                    .trim(from: 0, to: max(0, min(1, revealed ? fraction : 0)))
                    .stroke(PaperColor.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : .spring(response: 1.1, dampingFraction: 0.9), value: revealed ? fraction : 0)

                VStack(spacing: 2 * scale) {
                    Text(isLoaded ? focus.dayName : " ")
                        .font(.brand(14 * scale, .regular, relativeTo: .subheadline))
                        .foregroundStyle(PaperColor.secondary)
                    Text(isLoaded ? PaperFormat.int(day?.total ?? 0) : "–")
                        .font(.brand(60 * scale, .light, relativeTo: .largeTitle))
                        .tracking(-1.8 * scale)
                        .monospacedDigit()
                        .foregroundStyle(PaperColor.ink)
                        .contentTransition(.numericText(value: Double(day?.total ?? 0)))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text(packedLine)
                        .font(.brand(13 * scale, .regular, relativeTo: .footnote))
                        .monospacedDigit()
                        .foregroundStyle(PaperColor.tertiary)
                        .contentTransition(.numericText(value: Double(day?.ready ?? 0)))
                }
                .padding(.horizontal, 22 * scale)
                .multilineTextAlignment(.center)
            }
            .frame(width: diameter, height: diameter)
            .padding(3)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(day == nil)
        .animation(reduceMotion ? nil : .snappy(duration: 0.5), value: day?.total)
        .animation(reduceMotion ? nil : .snappy(duration: 0.5), value: day?.ready)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    /// "16 of 28 packed", or the date when the ring is about a later day.
    private var packedLine: String {
        guard isLoaded else { return " " }
        guard let day else { return "nothing due out" }
        let packed = "\(PaperFormat.int(day.ready)) packed"
        return focus.isToday || focus.isTomorrow
            ? packed
            : "\(TodayText.dayMonth.string(from: day.date)) · \(packed)"
    }

    private var accessibilityText: String {
        guard let day else { return "Nothing due out in the next five working days" }
        return "\(focus.dayName): \(Format.count(day.total, "job")) due out, \(day.ready) packed"
    }
}

// MARK: Three quiet figures

struct QuietFigures: View {
    let intelligence: DispatchIntelligence
    let focus: TodayFocus
    let isLoaded: Bool
    let boxesThisWeek: Int?
    var onAPC: (CourierGroup) -> Void
    var onOtherDay: () -> Void
    var onWeek: () -> Void

    private var apcGroup: CourierGroup? {
        intelligence.courierGroups.first { $0.shippingMethod.localizedCaseInsensitiveContains("APC") }
    }

    var body: some View {
        HStack(alignment: .top, spacing: PaperSpace.l) {
            // Ticks over on its own; the rest of the page doesn't redraw for it.
            TimelineView(.periodic(from: .now, by: 30)) { context in
                let cutoff = APCCutoff(now: context.date, jobs: apcGroup?.todayJobs ?? [])
                Figure(label: "APC 14:00",
                       value: isLoaded ? cutoff.headline : "–",
                       caption: isLoaded ? cutoff.caption : " ",
                       colour: cutoff.isUrgent ? PaperColor.ember : PaperColor.ink,
                       marker: cutoff.isUrgent ? PaperColor.ember : nil) {
                    if let apcGroup { onAPC(apcGroup) }
                }
                .disabled(apcGroup == nil)
            }
            otherDay
            Figure(label: "This week",
                   value: boxesThisWeek.map { PaperFormat.int($0) } ?? "–",
                   caption: "boxes packed",
                   action: onWeek)
        }
    }

    /// Whichever of today and tomorrow the ring isn't showing.
    @ViewBuilder
    private var otherDay: some View {
        if focus.isToday {
            Figure(label: "Tomorrow",
                   value: isLoaded ? PaperFormat.int(intelligence.dueTomorrow) : "–",
                   caption: "due out", action: onOtherDay)
        } else {
            Figure(label: "Today",
                   value: isLoaded ? PaperFormat.int(intelligence.todayJobs.count) : "–",
                   caption: intelligence.todayJobs.isEmpty ? "nothing due" : "due out", action: onOtherDay)
                .disabled(intelligence.todayJobs.isEmpty)
        }
    }

    private struct Figure: View {
        let label: String
        let value: String
        let caption: String
        var colour: Color = PaperColor.ink
        var marker: Color? = nil
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                VStack(alignment: .center, spacing: 4) {
                    HStack(spacing: 6) {
                        if let marker {
                            Circle().fill(marker).frame(width: 6, height: 6)
                                .transition(.scale.combined(with: .opacity))
                        }
                        Text(label).paperType(.caption).foregroundStyle(PaperColor.tertiary).lineLimit(1)
                    }
                    Text(value)
                        .font(.brand(24, .regular, relativeTo: .title2))
                        .monospacedDigit()
                        .foregroundStyle(colour)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                    Text(caption)
                        .paperType(.caption, numeric: true)
                        .foregroundStyle(PaperColor.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .animation(.snappy, value: value)
            .accessibilityElement(children: .combine)
        }
    }
}

/// APC's 14:00 collection. Counts only the APC jobs due today that aren't
/// packed yet: a job already packed has made the cut-off.
private struct APCCutoff {
    let headline: String
    let caption: String
    let isUrgent: Bool

    init(now: Date, jobs: [DispatchJob]) {
        let cal = Calendar.london
        let cutoff = cal.date(bySettingHour: 14, minute: 0, second: 0, of: cal.startOfDay(for: now))!
        let toPack = jobs.filter { $0.stage < .packed }.count

        if jobs.isEmpty {
            headline = "–"
            caption = cal.isDateInWeekend(now) ? "no collection" : "none today"
            isUrgent = false
        } else if toPack == 0 {
            headline = "Done"
            caption = "all \(PaperFormat.int(jobs.count)) packed"
            isUrgent = false
        } else if now >= cutoff {
            headline = "Passed"
            caption = "\(PaperFormat.int(toPack)) not packed"
            isUrgent = true
        } else {
            let minutes = Int(cutoff.timeIntervalSince(now) / 60)
            headline = minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(minutes % 60)m"
            caption = "\(PaperFormat.int(toPack)) to pack"
            isUrgent = minutes <= 90
        }
    }
}

// MARK: The week's rhythm

/// Jobs due on each of the next five working days: a slim bar per day, amber
/// for what's packed, the track for the rest. The ring's day is marked.
struct WeekRhythm: View {
    let days: [DayLoad]
    let focusDate: Date?
    let revealed: Bool
    var barWidth: CGFloat = 14
    var onSelect: (DayLoad) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let peak = max(days.map(\.total).max() ?? 0, 1)
        GeometryReader { geo in
            // Room for the count above and the day below; the bar takes the rest.
            let barSpace = max(geo.size.height - 52, 12)
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                    Button { onSelect(day) } label: {
                        column(day, index: index, peak: peak, barSpace: barSpace)
                    }
                    .buttonStyle(.plain)
                    .disabled(day.total == 0)
                    .accessibilityLabel("\(Format.day(day.date)): \(Format.count(day.total, "job")), \(day.ready) packed")
                }
            }
        }
    }

    private func isFocus(_ day: DayLoad) -> Bool {
        focusDate.map { Calendar.london.isDate($0, inSameDayAs: day.date) } ?? false
    }

    private func column(_ day: DayLoad, index: Int, peak: Int, barSpace: CGFloat) -> some View {
        let focused = isFocus(day)
        let full = day.total == 0 ? 0 : max(6, barSpace * CGFloat(day.total) / CGFloat(peak))
        let height = revealed ? full : 0
        let readyShare = day.total == 0 ? 0 : CGFloat(day.ready) / CGFloat(day.total)
        let animation: Animation? = reduceMotion ? nil
            : .spring(response: 0.7, dampingFraction: 0.82).delay(Double(index) * 0.06)

        return VStack(spacing: PaperSpace.xs) {
            Text(day.total == 0 ? " " : PaperFormat.int(day.total))
                .font(.brand(13, focused ? .medium : .regular, relativeTo: .caption))
                .monospacedDigit()
                .foregroundStyle(focused ? PaperColor.ink : PaperColor.tertiary)
                .opacity(revealed ? 1 : 0)
                .animation(animation, value: revealed)
            ZStack(alignment: .bottom) {
                // The baseline every day shares, so an empty day still reads.
                Capsule().fill(PaperColor.hairline).frame(width: barWidth, height: 2)
                Capsule()
                    .fill(PaperColor.track)
                    .frame(width: barWidth, height: height)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(PaperColor.accent)
                            .frame(height: height * readyShare)
                    }
                    .clipShape(Capsule())
                    .animation(animation, value: height)
            }
            .frame(height: barSpace, alignment: .bottom)
            VStack(spacing: 3) {
                Text(TodayText.weekdayShort.string(from: day.date))
                    .font(.brand(12, focused ? .medium : .regular, relativeTo: .caption))
                    .foregroundStyle(focused ? PaperColor.ink : PaperColor.secondary)
                Circle()
                    .fill(focused ? PaperColor.accent : .clear)
                    .frame(width: 4, height: 4)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

// MARK: One line of news

/// The most pressing date change for today or tomorrow, as a single line.
/// The bell and the toast carry the rest.
struct TodayAlertLine: View {
    @ObservedObject private var service = NotificationService.shared
    var onOpen: () -> Void

    private var relevant: [AppNotification] {
        service.noticeBoard.filter { $0.touchesTodayOrTomorrow() }
    }

    var body: some View {
        ZStack {
            if let top = relevant.first {
                line(top)
                    .id(top.id)
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                            removal: .opacity))
            }
        }
        .animation(PaperMotion.spring, value: relevant.first?.id)
    }

    private func line(_ top: AppNotification) -> some View {
        HStack(spacing: PaperSpace.m) {
            Button(action: onOpen) {
                HStack(spacing: PaperSpace.m) {
                    Circle()
                        .fill(top.isUrgent ? PaperColor.ember : PaperColor.accent)
                        .frame(width: 7, height: 7)
                    Text(top.shortTitle)
                        .paperType(.subhead)
                        .foregroundStyle(PaperColor.ink)
                        .lineLimit(1)
                    if let note = top.urgencyNote {
                        Text(note)
                            .paperType(.subhead)
                            .foregroundStyle(top.isUrgent ? PaperColor.ember : PaperColor.secondary)
                            .lineLimit(1)
                    }
                    if relevant.count > 1 {
                        Text("+\(relevant.count - 1)")
                            .paperType(.caption, numeric: true)
                            .foregroundStyle(PaperColor.tertiary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                Task { await service.markRead(top) }
            } label: {
                PaperIcon(.close, size: 11, lineWidth: 2, color: PaperColor.tertiary)
            }
            .buttonStyle(.paperIcon)
            .accessibilityLabel("Dismiss \(top.shortTitle)")
        }
        .frame(minHeight: PaperSpace.tap)
    }
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
            guard let raw, let date = TodayText.isoDay.date(from: String(raw.prefix(10))) else { return false }
            return date >= today && date < dayAfter
        }
        return near(newDate) || near(previousDate)
    }
}

// MARK: - Formatting

enum TodayText {
    private static func formatter(_ format: String, posix: Bool = false) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: posix ? "en_US_POSIX" : "en_GB")
        f.timeZone = TimeZone(identifier: "Europe/London")
        f.dateFormat = format
        return f
    }
    static let weekdayLong = formatter("EEEE")
    static let weekdayShort = formatter("EEE")
    static let dayMonth = formatter("d MMM")
    static let isoDay = formatter("yyyy-MM-dd", posix: true)
}
