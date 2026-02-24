import SwiftUI

struct SlideToCloseView: View {
    let onClose: () -> Void

    @State private var offset: CGFloat = 0
    @State private var isDragging = false

    private let thumbSize: CGFloat = 52
    private let trackHeight: CGFloat = 60
    private let threshold: CGFloat = 0.75

    var body: some View {
        GeometryReader { geometry in
            let maxOffset = geometry.size.width - thumbSize - 12

            ZStack(alignment: .leading) {
                track
                label(maxOffset: maxOffset)
                filledPortion(maxOffset: maxOffset)
                thumb(maxOffset: maxOffset)
            }
        }
        .frame(height: trackHeight)
    }

    private var track: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(.orange.opacity(0.15))
            .frame(height: trackHeight)
    }

    private func label(maxOffset: CGFloat) -> some View {
        Text("Slide to close box")
            .font(.subheadline.bold())
            .foregroundStyle(.orange.opacity(0.6))
            .frame(maxWidth: .infinity)
            .opacity(1 - (offset / maxOffset))
    }

    private func filledPortion(maxOffset: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(.orange.opacity(0.3))
            .frame(width: offset + thumbSize + 12, height: trackHeight)
    }

    private func thumb(maxOffset: CGFloat) -> some View {
        Circle()
            .fill(.orange)
            .frame(width: thumbSize, height: thumbSize)
            .overlay {
                Image(systemName: "lock.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
            }
            .offset(x: offset + 4)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isDragging = true
                        offset = min(max(0, value.translation.width), maxOffset)
                    }
                    .onEnded { _ in
                        isDragging = false
                        if offset >= maxOffset * threshold {
                            withAnimation(.spring(response: 0.3)) {
                                offset = maxOffset
                            }
                            HapticService.medium()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                onClose()
                            }
                        } else {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                offset = 0
                            }
                        }
                    }
            )
    }
}
