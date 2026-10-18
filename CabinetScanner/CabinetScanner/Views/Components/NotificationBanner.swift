import CabinetDesign
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
            HStack(alignment: .center, spacing: PaperSpace.m) {
                PaperIcon(.bell, size: 18, color: PaperColor.onInverse)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(notification.title)
                        .paperType(.callout, numeric: true)
                        .foregroundStyle(PaperColor.onInverse)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)

                    if let urgency = notification.urgencyNote {
                        HStack(spacing: 6) {
                            Circle().fill(notification.tone.color).frame(width: 7, height: 7)
                            Text(urgency)
                                .paperType(.footnote, numeric: true)
                                .foregroundStyle(PaperColor.onInverse)
                        }
                    } else if let body = notification.body {
                        Text(body)
                            .paperType(.footnote, numeric: true)
                            .foregroundStyle(PaperColor.onInverseMuted)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 0)

                Button(action: onDismiss) {
                    PaperIcon(.close, size: 12, lineWidth: 2, color: PaperColor.onInverseMuted)
                }
                .buttonStyle(.paperIcon)
                .accessibilityLabel("Dismiss")
            }
            .padding(.leading, PaperSpace.l)
            .padding(.trailing, PaperSpace.xs)
            .padding(.vertical, PaperSpace.xs)
            .frame(minHeight: 56)
            .background(PaperColor.inverse, in: RoundedRectangle(cornerRadius: 16))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 560)
        .paperMargins()
        .transition(.opacity)
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
            .overlay(alignment: .bottom) {
                if let notification = service.toast {
                    NotificationBanner(
                        notification: notification,
                        onTap: {
                            service.dismissToast()
                            onOpen(notification)
                        },
                        onDismiss: { service.dismissToast() }
                    )
                    .padding(.bottom, PaperSpace.l)
                }
            }
            .animation(PaperMotion.fade, value: service.toast?.id)
    }
}

extension View {
    func notificationBanner(onOpen: @escaping (AppNotification) -> Void) -> some View {
        modifier(NotificationBannerHost(onOpen: onOpen))
    }
}
