import SwiftUI

// MARK: - Notifications
//
// The full list: every despatch-date change this device is meant to know
// about, whether or not the app was open when it happened.
//
// Not a tab. The tab bar is already at five, and a sixth makes iOS collapse
// the last two behind "More" — which would bury Stock and Settings, screens
// the team already relies on. This opens from the bell on the dashboard
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
            Group {
                if service.notifications.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Despatch Alerts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Mark all read") {
                        Task { await service.markAllRead() }
                    }
                    .disabled(service.unreadCount == 0)
                }
            }
            .refreshable { await service.refresh() }
            .task { await service.refresh() }
            .navigationDestination(item: $openJobId) { id in
                JobDetailView(jobId: id)
            }
        }
    }

    private var list: some View {
        List {
            if let error = service.errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } footer: {
                    // The list is a record of things that already happened, so
                    // a failed refresh leaves it in place rather than emptying
                    // it. Say which of the two is on screen.
                    Text("Showing what was last loaded.")
                }
            }

            ForEach(service.notifications) { notification in
                NotificationRow(notification: notification) {
                    Task { await service.markRead(notification) }
                    openJobId = notification.jobId
                }
                .swipeActions(edge: .leading) {
                    if notification.read {
                        Button {
                            Task { await service.markUnread(notification) }
                        } label: {
                            Label("Unread", systemImage: "envelope.badge")
                        }
                        .tint(.blue)
                    } else {
                        Button {
                            Task { await service.markRead(notification) }
                        } label: {
                            Label("Read", systemImage: "envelope.open")
                        }
                        .tint(.gray)
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Despatch Changes", systemImage: "calendar.badge.checkmark")
        } description: {
            Text("Nothing has moved. When the office changes a job's despatch date, it appears here.")
        }
    }
}

// MARK: - Row

/// One change.
///
/// Unread is carried by weight and a dot rather than a background colour: a
/// row is already colour-coded by direction, and stacking two colour meanings
/// on one row makes neither readable across a workshop.
struct NotificationRow: View {
    let notification: AppNotification
    var onTap: () -> Void = {}

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: notification.systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(notification.accentColour)
                        .frame(width: 32, height: 32)
                        .background(
                            notification.accentColour.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 8)
                        )

                    if !notification.read {
                        Circle()
                            .fill(notification.accentColour)
                            .frame(width: 8, height: 8)
                            .offset(x: 3, y: -3)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(notification.title)
                        .font(.subheadline.weight(notification.read ? .regular : .semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    if let body = notification.body {
                        Text(body)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // "That is tomorrow." Only ever present on a date moving
                    // towards us, which is why it gets the accent weight.
                    if let urgency = notification.urgencyNote {
                        Text(urgency)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(notification.accentColour)
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
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 0)

                if notification.jobId != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(notification.jobId == nil)
    }
}
