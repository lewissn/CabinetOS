import SwiftUI

/// Dark overlay with a transparent scan box cutout and corner markers
struct ScanOverlayView: View {
    let scanBoxSize: CGFloat = 280
    let cornerLength: CGFloat = 30
    let cornerLineWidth: CGFloat = 4

    var body: some View {
        GeometryReader { geometry in
            let rect = CGRect(
                x: (geometry.size.width - scanBoxSize) / 2,
                y: (geometry.size.height - scanBoxSize) / 2 - 40,
                width: scanBoxSize,
                height: scanBoxSize
            )

            ZStack {
                // Dark overlay with cutout
                Rectangle()
                    .fill(.black.opacity(0.5))
                    .reverseMask {
                        RoundedRectangle(cornerRadius: 16)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                    }

                // Corner markers
                ScanBoxCorners(rect: rect, cornerLength: cornerLength, lineWidth: cornerLineWidth)
            }
        }
    }
}

struct ScanBoxCorners: View {
    let rect: CGRect
    let cornerLength: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        Canvas { context, _ in
            let color = Color.white

            // Top-left
            drawCorner(context: &context, x: rect.minX, y: rect.minY, dx: 1, dy: 1, color: color)
            // Top-right
            drawCorner(context: &context, x: rect.maxX, y: rect.minY, dx: -1, dy: 1, color: color)
            // Bottom-left
            drawCorner(context: &context, x: rect.minX, y: rect.maxY, dx: 1, dy: -1, color: color)
            // Bottom-right
            drawCorner(context: &context, x: rect.maxX, y: rect.maxY, dx: -1, dy: -1, color: color)
        }
    }

    private func drawCorner(context: inout GraphicsContext, x: CGFloat, y: CGFloat, dx: CGFloat, dy: CGFloat, color: Color) {
        var hLine = Path()
        hLine.move(to: CGPoint(x: x, y: y))
        hLine.addLine(to: CGPoint(x: x + cornerLength * dx, y: y))

        var vLine = Path()
        vLine.move(to: CGPoint(x: x, y: y))
        vLine.addLine(to: CGPoint(x: x, y: y + cornerLength * dy))

        context.stroke(hLine, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        context.stroke(vLine, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
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
