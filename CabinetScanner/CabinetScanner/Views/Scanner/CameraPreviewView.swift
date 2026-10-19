import SwiftUI
import AVFoundation

/// UIViewRepresentable wrapper for AVCaptureVideoPreviewLayer
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    /// Given the preview layer, so a found code can be located on screen.
    var geometry: PreviewGeometry? = nil

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.session = session
        geometry?.layer = view.layer as? AVCaptureVideoPreviewLayer
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {}
}

final class CameraPreviewUIView: UIView {
    var session: AVCaptureSession? {
        didSet {
            (layer as? AVCaptureVideoPreviewLayer)?.session = session
        }
    }

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let previewLayer = layer as? AVCaptureVideoPreviewLayer else { return }
        previewLayer.videoGravity = .resizeAspectFill
    }
}
