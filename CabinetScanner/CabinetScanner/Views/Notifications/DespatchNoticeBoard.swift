import CabinetDesign
import SwiftUI

// MARK: - Today's alerts
//
// The unread despatch changes, on the screen the bench already has open.
//
// Deliberately not a full list. It shows the three that matter most — dates
// brought forward first, then most recent — and a way through to the rest. A
// dashboard section that grows without limit stops being read, and the whole
// point is that the top item is seen.

struct DespatchNoticeBoard: View {
    @ObservedObject private var service = NotificationService.shared
    @Binding var showingAll: Bool

    private let maximumShown = 3

    private var shown: [AppNotification] {
        Array(service.noticeBoard.prefix(maximumShown))
    }

    var body: some View {
        if !shown.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                PaperSectionHeader("Alerts") {
                    Button("See all") { showingAll = true }
                        .buttonStyle(.paperText(PaperColor.secondary, .footnote))
                }

                ForEach(shown) { notification in
                    Button { showingAll = true } label: {
                        AlertRow(notification: notification)
                    }
                    .buttonStyle(.plain)
                }

                if service.unreadCount > shown.count {
                    Button("\(service.unreadCount - shown.count) more") { showingAll = true }
                        .buttonStyle(.paperText(PaperColor.secondary, .footnote))
                }
            }
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
