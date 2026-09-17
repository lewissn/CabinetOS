import SwiftUI

// MARK: - Arriving notification banner
//
// The brief calls for "a brief toast when a new notification arrives while the
// app is open". This is that, and it is deliberately a different component
// from ToastView: that one is a two-second confirmation of something the
// person just did, and this is an interruption about something somebody else
// did, on a different job, that may need acting on.
//
// So it is tappable, it says which job, and a date brought forward holds the
// screen for longer than a postponement — the one case where an extra couple
// of seconds is worth spending.

struct NotificationBanner: View {
    let notification: AppNotification
    let onTap: () -> Void
    let onDismiss: () -> Void

    private var displayDuration: Duration {
        notification.isUrgent ? .seconds(8) : .seconds(5)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: notification.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(notification.accentColour, in: RoundedRectangle(cornerRadius: 9))

                VStack(alignment: .leading, spacing: 2) {
                    Text(notification.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)

                    if let urgency = notification.urgencyNote {
                        Text(urgency)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(notification.accentColour)
                    } else if let body = notification.body {
                        Text(body)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 0)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(notification.accentColour.opacity(0.35))
            )
            .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .transition(.move(edge: .top).combined(with: .opacity))
        // `.task(id:)` rather than a timer: structured concurrency cancels it
        // when the banner goes away, so nothing writes to state that has
        // already gone. ToastView carries the scar from getting this wrong.
        .task(id: notification.id) {
            do {
                try await Task.sleep(for: displayDuration)
                onDismiss()
            } catch {
                // Cancelled — replaced or dismissed. Nothing to do.
            }
        }
    }
}

// MARK: - Host

/// Puts the banner above whatever is on screen, without each screen having to
/// know about it.
struct NotificationBannerHost: ViewModifier {
    @ObservedObject private var service = NotificationService.shared
    let onOpen: (AppNotification) -> Void

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let notification = service.toast {
                    NotificationBanner(
                        notification: notification,
                        onTap: {
                            service.dismissToast()
                            onOpen(notification)
                        },
                        onDismiss: { service.dismissToast() }
                    )
                    .padding(.top, 4)
                }
            }
            .animation(.spring(duration: 0.35), value: service.toast?.id)
    }
}

extension View {
    func notificationBanner(onOpen: @escaping (AppNotification) -> Void) -> some View {
        modifier(NotificationBannerHost(onOpen: onOpen))
    }
}
