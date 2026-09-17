import SwiftUI

// MARK: - Dashboard notice area
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
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Despatch Changes", systemImage: "calendar.badge.exclamationmark")
                        .font(.headline)
                    Spacer()
                    Button("See all") { showingAll = true }
                        .font(.subheadline)
                }

                VStack(spacing: 8) {
                    ForEach(shown) { notification in
                        NoticeCard(notification: notification) {
                            showingAll = true
                        }
                    }
                }

                if service.unreadCount > shown.count {
                    Button {
                        showingAll = true
                    } label: {
                        Text("\(service.unreadCount - shown.count) more")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

/// One notice, sized to be read at arm's length from a bench.
private struct NoticeCard: View {
    let notification: AppNotification
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: notification.systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(notification.accentColour)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(notification.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    if let body = notification.body {
                        Text(body)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)
                    }

                    if let urgency = notification.urgencyNote {
                        Text(urgency)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(notification.accentColour)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    // A date brought forward gets an edge; a postponement does
                    // not. The asymmetry is the message.
                    .strokeBorder(
                        notification.isUrgent ? notification.accentColour.opacity(0.5) : .clear,
                        lineWidth: 1.5
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Bell

/// The dashboard's way through to the full list, with the unread count on it.
struct NotificationBell: View {
    @ObservedObject private var service = NotificationService.shared
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: service.unreadCount > 0 ? "bell.badge.fill" : "bell")
                    .font(.system(size: 20))
                    .foregroundStyle(service.unreadCount > 0 ? .orange : .secondary)

                if service.unreadCount > 0 {
                    Text(service.unreadCount > 99 ? "99+" : "\(service.unreadCount)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.red, in: Capsule())
                        .offset(x: 10, y: -8)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            service.unreadCount > 0
                ? "Despatch alerts, \(service.unreadCount) unread"
                : "Despatch alerts"
        )
    }
}
