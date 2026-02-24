import SwiftUI

struct ToastView: View {
    @Binding var message: String?

    var body: some View {
        if let text = message {
            Text(text)
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.black.opacity(0.8))
                .clipShape(Capsule())
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        withAnimation(.easeOut(duration: 0.3)) {
                            message = nil
                        }
                    }
                }
                .padding(.bottom, 16)
        }
    }
}
