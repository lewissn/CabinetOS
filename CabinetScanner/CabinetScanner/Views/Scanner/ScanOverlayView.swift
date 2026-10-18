import CabinetDesign
import SwiftUI

/// Dimmed camera with a clear scan window and the concept's corners, which
/// turn green or red with the result.
struct ScanOverlayView: View {
    var cornerColor: Color = PaperColor.onInverse
    let scanBoxSize: CGFloat = 280

    var body: some View {
        GeometryReader { geometry in
            let rect = CGRect(
                x: (geometry.size.width - scanBoxSize) / 2,
                y: (geometry.size.height - scanBoxSize) / 2 - 40,
                width: scanBoxSize,
                height: scanBoxSize
            )

            ZStack {
                Rectangle()
                    .fill(Color.black.opacity(0.55))
                    .reverseMask {
                        RoundedRectangle(cornerRadius: 16)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                    }

                ScanCorners(color: cornerColor, length: 30, lineWidth: 4)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }
        }
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
