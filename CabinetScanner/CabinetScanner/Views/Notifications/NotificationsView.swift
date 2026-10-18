import CabinetDesign
import SwiftUI

// MARK: - Notifications
//
// The full list: every despatch-date change this device is meant to know
// about, whether or not the app was open when it happened.
//
// Not a tab. The tab bar is already at five, and a sixth makes iOS collapse
// the last two behind "More" — which would bury Stock and Settings, screens
// the team already relies on. This opens from the bell on Today
// instead, where the unread count is visible anyway.
//
// Read state is per device and lives on the server, so an iPad that was
// switched off during the change still opens to it unread.

struct NotificationsView: View {
    @ObservedObject private var service = NotificationService.shared
    @Environment(\.dismiss) private var dismiss

    /// Set when a row is tapped, so the job opens inside this stack.
    @State private var openJobId: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PaperTopBar(.close, title: "Despatch alerts", onLeading: { dismiss() }) {
                    Button("Mark all read") {
                        Task { await service.markAllRead() }
                    }
                    .buttonStyle(.paperText(PaperColor.ink, .footnote, weight: .semibold))
                    .disabled(service.unreadCount == 0)
                }
                .screen()
                .padding(.top, PaperSpace.s)

                if service.notifications.isEmpty {
                    PaperEmptyState("No despatch changes",
                                    message: "Nothing has moved. When the office changes a job's despatch date, it appears here.")
                        .screen()
                    Spacer()
                } else {
                    list
                }
            }
            .paperBackground()
            .toolbar(.hidden, for: .navigationBar)
            .task { await service.refresh() }
            .navigationDestination(item: $openJobId) { id in
                JobDetailView(jobId: id, backLabel: "Alerts")
            }
        }
    }

    private var list: some View {
        List {
            if let error = service.errorMessage {
                // The list is a record of things that already happened, so a
                // failed refresh leaves it in place rather than emptying it.
                // Say which of the two is on screen.
                Notice(text: "\(error) Showing what was last loaded.", tone: .soon)
                    .paperListRow(top: PaperSpace.l, bottom: PaperSpace.s)
            }

            ForEach(service.notifications) { notification in
                NotificationRow(notification: notification) {
                    Task { await service.markRead(notification) }
                    openJobId = notification.jobId
                }
                .paperListRow()
                .swipeActions(edge: .leading) {
                    if notification.read {
                        Button {
                            Task { await service.markUnread(notification) }
                        } label: {
                            Label("Unread", systemImage: "envelope.badge")
                        }
                        .tint(PaperColor.info)
                    } else {
                        Button {
                            Task { await service.markRead(notification) }
                        } label: {
                            Label("Read", systemImage: "envelope.open")
                        }
                        .tint(PaperColor.muted)
                    }
                }
            }
        }
        .paperList()
        .refreshable { await service.refresh() }
    }
}

// MARK: - Row

/// One change, tappable through to its job.
struct NotificationRow: View {
    let notification: AppNotification
    var onTap: () -> Void = {}

    var body: some View {
        Button(action: onTap) {
            AlertRow(notification: notification, showsChevron: notification.jobId != nil)
        }
        .buttonStyle(.plain)
        .disabled(notification.jobId == nil)
    }
}
