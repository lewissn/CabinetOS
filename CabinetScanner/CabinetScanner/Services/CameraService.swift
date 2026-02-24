import AVFoundation
import Vision
import UIKit

protocol CameraServiceDelegate: AnyObject {
    func cameraService(_ service: CameraService, didDetect detections: [ScanAssembler.Detection])
}

final class CameraService: NSObject, ObservableObject {
    weak var delegate: CameraServiceDelegate?

    let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let processingQueue = DispatchQueue(label: "com.cabinet.scanner.processing", qos: .userInitiated)

    @Published var isTorchOn = false
    @Published var isRunning = false
    @Published var permissionGranted = false

    private var device: AVCaptureDevice?

    // MARK: - Setup

    func checkPermission() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permissionGranted = true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            permissionGranted = granted
        default:
            permissionGranted = false
        }
    }

    func configure() {
        guard permissionGranted else { return }

        captureSession.beginConfiguration()
        captureSession.sessionPreset = .hd1920x1080

        // Camera input
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            captureSession.commitConfiguration()
            return
        }
        self.device = camera

        do {
            // Optimize camera for barcode scanning
            try camera.lockForConfiguration()
            if camera.isFocusModeSupported(.continuousAutoFocus) {
                camera.focusMode = .continuousAutoFocus
            }
            if camera.isAutoFocusRangeRestrictionSupported {
                camera.autoFocusRangeRestriction = .near
            }
            camera.unlockForConfiguration()

            let input = try AVCaptureDeviceInput(device: camera)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            }
        } catch {
            captureSession.commitConfiguration()
            return
        }

        // Video output
        videoOutput.setSampleBufferDelegate(self, queue: processingQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }

        captureSession.commitConfiguration()
    }

    func start() {
        guard !captureSession.isRunning else { return }
        processingQueue.async { [weak self] in
            self?.captureSession.startRunning()
            DispatchQueue.main.async {
                self?.isRunning = true
            }
        }
    }

    func stop() {
        guard captureSession.isRunning else { return }
        processingQueue.async { [weak self] in
            self?.captureSession.stopRunning()
            DispatchQueue.main.async {
                self?.isRunning = false
            }
        }
    }

    func toggleTorch() {
        guard let device = device, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            isTorchOn.toggle()
            device.torchMode = isTorchOn ? .on : .off
            device.unlockForConfiguration()
        } catch {}
    }
}

// MARK: - Video Frame Processing

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let request = VNDetectBarcodesRequest { [weak self] request, error in
            guard let self = self, error == nil,
                  let results = request.results as? [VNBarcodeObservation] else { return }

            let now = Date()
            var detections: [ScanAssembler.Detection] = []

            for barcode in results {
                guard let payload = barcode.payloadStringValue else { continue }

                let symbology: ScanAssembler.DetectedSymbology?
                switch barcode.symbology {
                case .qr:
                    symbology = .qr
                case .code128:
                    symbology = .code128
                default:
                    symbology = nil
                }

                guard let sym = symbology else { continue }

                let bounds = barcode.boundingBox
                let center = CGPoint(
                    x: bounds.midX,
                    y: bounds.midY
                )

                detections.append(ScanAssembler.Detection(
                    payload: payload,
                    symbology: sym,
                    centerPosition: center,
                    timestamp: now
                ))
            }

            if !detections.isEmpty {
                self.delegate?.cameraService(self, didDetect: detections)
            }
        }

        // Restrict to QR and Code128 only
        request.symbologies = [.qr, .code128]

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try? handler.perform([request])
    }
}
