import CabinetDesign
import SwiftUI

// MARK: - Today's alerts
//
// Only the date changes that alter today's or tomorrow's work: a job moved
// into either day, or moved out of one. ShopVOX moves dates constantly, and
// the rest are news the bell and the toast already carry, so they stay
// behind the bell rather than on the bench's screen.
//
// At most three, each dismissable, with a way through to the full list.

struct DespatchNoticeBoard: View {
    @ObservedObject private var service = NotificationService.shared
    @Binding var showingAll: Bool

    private let maximumShown = 3

    /// Brought forward first (the server's own ranking), then most recent.
    private var relevant: [AppNotification] {
        service.noticeBoard.filter { $0.touchesTodayOrTomorrow() }
    }

    private var shown: [AppNotification] { Array(relevant.prefix(maximumShown)) }

    var body: some View {
        if !shown.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                PaperSectionHeader("Date changes for today and \(WorkingDay.name() == "Tomorrow" ? "tomorrow" : WorkingDay.name())") {
                    Button("See all") { showingAll = true }
                        .buttonStyle(.paperText(PaperColor.secondary, .footnote))
                }

                ForEach(shown) { notification in
                    HStack(alignment: .top, spacing: 0) {
                        Button { showingAll = true } label: {
                            AlertRow(notification: notification)
                        }
                        .buttonStyle(.plain)
                        // Read, so it leaves Today; still in the full list.
                        Button {
                            Task { await service.markRead(notification) }
                        } label: {
                            PaperIcon(.close, size: 12, lineWidth: 2, color: PaperColor.secondary)
                        }
                        .buttonStyle(.paperIcon)
                        .padding(.top, PaperSpace.xs)
                        .accessibilityLabel("Dismiss \(notification.shortTitle)")
                    }
                    .transition(.opacity)
                }

                if relevant.count > shown.count {
                    Button("\(relevant.count - shown.count) more") { showingAll = true }
                        .buttonStyle(.paperText(PaperColor.secondary, .footnote))
                }
            }
            .animation(PaperMotion.fade, value: shown.map(\.id))
        }
    }
}

/// One alert: a status dot, the change, and when. Sized to be read at arm's
/// length from a bench.
struct AlertRow: View {
    let notification: AppNotification
    var showsChevron = false

    var body: some View {
        RowContainer {
            HStack(alignment: .firstTextBaseline, spacing: PaperSpace.m) {
                Circle()
                    .fill(notification.read ? Color.clear : notification.tone.color)
                    .overlay(Circle().strokeBorder(notification.read ? PaperColor.dot : .clear, lineWidth: 1))
                    .frame(width: 7, height: 7)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] }

                VStack(alignment: .leading, spacing: 3) {
                    // Unread is carried by weight and the dot rather than a
                    // background colour.
                    Text(notification.title)
                        .font(.brand(16, notification.read ? .regular : .medium, relativeTo: .body))
                        .monospacedDigit()
                        .foregroundStyle(PaperColor.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    if let body = notification.body {
                        Text(body)
                            .paperType(.footnote, numeric: true)
                            .foregroundStyle(PaperColor.secondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // "That is tomorrow." Only ever present on a date moving
                    // towards us, so it's the one line in the act-soon colour.
                    if let urgency = notification.urgencyNote {
                        Text(urgency)
                            .paperType(.footnote)
                            .foregroundStyle(Tone.soon.textColor)
                    }

                    HStack(spacing: 6) {
                        if let when = JobDateFormatting.relative(fromISO8601: notification.detectedAt) {
                            Text(when)
                        }
                        if notification.detectionSource == "poll" {
                            // Worth distinguishing: a change found by the sweep
                            // rather than announced by ShopVOX may have
                            // happened some time before it was noticed.
                            Text("· found by check")
                        }
                    }
                    .paperType(.caption)
                    .foregroundStyle(PaperColor.tertiary)
                }

                Spacer(minLength: 0)

                if showsChevron {
                    PaperIcon(.chevronRight, size: 14, color: PaperColor.faint)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Bell

/// Today's way through to the full list, with the unread count on it.
struct NotificationBell: View {
    @ObservedObject private var service = NotificationService.shared
    let action: () -> Void

    var body: some View {
        BarIcon(glyph: .bell, badge: service.unreadCount, label: "Despatch alerts", action: action)
    }
}
