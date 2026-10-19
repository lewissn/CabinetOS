import CabinetDesign
import SwiftUI

/// Dimmed camera with a clear scan window and the concept's corners, which
/// turn green or red with the result.
///
/// Given a `lock`, the window and its corners snap onto the code that was
/// found and flash amber: the label is seen to be caught before the screen
/// moves on. `.zero` means "found, but not where": the window closes in place.
struct ScanOverlayView: View {
    var cornerColor: Color = PaperColor.onInverse
    var lock: CGRect? = nil
    let scanBoxSize: CGFloat = 280

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flash: Double = 0

    var body: some View {
        GeometryReader { geometry in
            let window = CGRect(
                x: (geometry.size.width - scanBoxSize) / 2,
                y: (geometry.size.height - scanBoxSize) / 2 - 40,
                width: scanBoxSize,
                height: scanBoxSize
            )
            let rect = target(window: window)

            ZStack {
                Rectangle()
                    .fill(Color.black.opacity(lock == nil ? 0.55 : 0.68))
                    .reverseMask {
                        RoundedRectangle(cornerRadius: lock == nil ? 16 : 10)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                    }

                RoundedRectangle(cornerRadius: 10)
                    .fill(PaperColor.accent.opacity(flash))
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)

                CornersShape(length: lock == nil ? 30 : 20)
                    .stroke(lock == nil ? cornerColor : PaperColor.accent,
                            style: StrokeStyle(lineWidth: lock == nil ? 4 : 5, lineCap: .round, lineJoin: .round))
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .animation(PaperMotion.fade, value: cornerColor)
            }
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.72), value: lock)
        }
        .onChange(of: lock) { _, new in
            guard new != nil else { return }
            flash = 0.32
            withAnimation(.easeOut(duration: 0.5)) { flash = 0 }
        }
        .accessibilityHidden(true)
    }

    /// The window, or the code it caught: a little larger than the code and
    /// never smaller than a thumb's width.
    private func target(window: CGRect) -> CGRect {
        guard let lock else { return window }
        guard lock != .zero else { return window.insetBy(dx: window.width * 0.16, dy: window.height * 0.16) }
        let side = max(max(lock.width, lock.height) + 28, 96)
        return CGRect(x: lock.midX - side / 2, y: lock.midY - side / 2, width: side, height: side)
    }
}

// MARK: - Reverse mask modifier

extension View {
    func reverseMask<Mask: View>(@ViewBuilder _ mask: () -> Mask) -> some View {
        self.mask(
            ZStack {
                Rectangle()
                mask()
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
        )
    }
}
