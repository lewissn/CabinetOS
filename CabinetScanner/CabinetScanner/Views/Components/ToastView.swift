import SwiftUI

/// Auto-dismissing toast bound to an external `String?` state.
///
/// Implementation note: the previous version used `DispatchQueue.main.asyncAfter`
/// fired from `.onAppear` to clear the binding 2s later. That closure was
/// uncancellable — if the parent view was dismissed before the 2s elapsed
/// (e.g. closing a box, which triggers a navigation pop ~1s after the toast
/// appears), the closure would write to a `@Binding` whose underlying state
/// had been deallocated. On older devices (iPhone 12 mini and earlier) where
/// the dismiss animation runs slightly slower, this race became deterministic
/// and crashed the app.
///
/// The new implementation uses `.task(id:)` so the auto-dismiss is structured
/// concurrency that automatically cancels when the view disappears or the
/// message changes. No orphaned closures, no dangling binding writes.
struct ToastView: View {
    @Binding var message: String?
    var autoDismissAfter: Duration = .seconds(2)

    var body: some View {
        Group {
            if let text = message {
                Text(text)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.black.opacity(0.8))
                    .clipShape(Capsule())
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 16)
            }
        }
        .animation(.easeOut(duration: 0.25), value: message)
        .task(id: message) {
            guard message != nil else { return }
            do {
                try await Task.sleep(for: autoDismissAfter)
                message = nil
            } catch {
                // Cancelled — view is going away or message changed. Do nothing.
            }
        }
    }
}
