import CabinetDesign
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
    /// The check suits a confirmation; pass nil for a toast that reports
    /// something that didn't happen ("Nothing was added").
    var glyph: PaperGlyph? = .check

    var body: some View {
        Group {
            if let text = message {
                HStack(spacing: PaperSpace.s) {
                    if let glyph {
                        PaperIcon(glyph, size: 16, lineWidth: 2.2, color: PaperColor.onInverse)
                    }
                    Text(text)
                        .paperType(.callout, numeric: true)
                        .foregroundStyle(PaperColor.onInverse)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }
                .padding(.horizontal, PaperSpace.xl)
                .padding(.vertical, PaperSpace.s)
                .frame(minHeight: 48)
                .background(PaperColor.inverse, in: Capsule())
                .paperMargins()
                .transition(.opacity)
                .padding(.bottom, PaperSpace.l)
                .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .animation(PaperMotion.fade, value: message)
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
