import Foundation
import Combine

@MainActor
final class ScannerViewModel: ObservableObject {
    enum ScanState: Equatable {
        case scanning(hint: String)
        case validating(ScanTriplet)
        case success(String)
        case error(String)
        case cooldown
    }

    @Published var scanState: ScanState = .scanning(hint: "Scan label — find QR code")
    @Published var lastSuccessLabel: String?
    @Published var continuousMode: Bool = true

    let boxId: String
    let manifestId: String
    let consignmentId: String
    let cameraService: CameraService
    let assembler: ScanAssembler

    private let api: APIServiceProtocol
    private let appState: AppState

    private var isProcessing = false

    init(
        boxId: String,
        manifestId: String,
        consignmentId: String,
        appState: AppState,
        api: APIServiceProtocol = ServiceContainer.shared.api
    ) {
        self.boxId = boxId
        self.manifestId = manifestId
        self.consignmentId = consignmentId
        self.appState = appState
        self.api = api
        self.cameraService = CameraService()
        self.assembler = ScanAssembler()
    }

    func startScanning() {
        cameraService.delegate = self
        Task {
            await cameraService.checkPermission()
            cameraService.configure()
            cameraService.start()
        }
    }

    func stopScanning() {
        cameraService.stop()
        cameraService.delegate = nil
    }

    func resetScanner() {
        assembler.reset()
        isProcessing = false
        scanState = .scanning(hint: "Scan label — find QR code")
    }

    // MARK: - API submission

    private func submitTriplet(_ triplet: ScanTriplet) async {
        guard !isProcessing else { return }
        isProcessing = true
        scanState = .validating(triplet)

        let formatter = ISO8601DateFormatter()
        let request = ScanRequest(
            manifestId: manifestId,
            consignmentId: consignmentId,
            projectName: triplet.projectName,
            cabinetName: triplet.cabinetName,
            partNumber: triplet.partNumber,
            deviceId: appState.deviceId,
            stationId: appState.stationId,
            operator_: appState.operatorName.isEmpty ? nil : appState.operatorName,
            scannedAt: formatter.string(from: Date())
        )

        do {
            let response = try await api.scanItem(boxId: boxId, request: request)

            if response.ok {
                HapticService.success()
                HapticService.playTickSound()
                let label = "\(triplet.cabinetName) — Part \(triplet.partNumber)"
                lastSuccessLabel = label
                scanState = .success(label)

                // After brief success display, return to scanning
                if continuousMode {
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    assembler.clearCooldown()
                    scanState = .scanning(hint: "Scan next label")
                    isProcessing = false
                }
            } else {
                HapticService.error()
                let msg = response.message ?? "Scan rejected"
                scanState = .error(msg)

                // Return to scanning after showing error
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                assembler.clearCooldown()
                scanState = .scanning(hint: "Scan label — find QR code")
                isProcessing = false
            }
        } catch {
            HapticService.error()
            scanState = .error(error.localizedDescription)

            try? await Task.sleep(nanoseconds: 2_000_000_000)
            assembler.clearCooldown()
            scanState = .scanning(hint: "Scan label — find QR code")
            isProcessing = false
        }
    }
}

// MARK: - CameraServiceDelegate

extension ScannerViewModel: CameraServiceDelegate {
    nonisolated func cameraService(_ service: CameraService, didDetect detections: [ScanAssembler.Detection]) {
        Task { @MainActor in
            guard !isProcessing else { return }

            let status = assembler.addDetections(detections)

            switch status {
            case .searching(let hint):
                scanState = .scanning(hint: hint)
            case .assembled(let triplet):
                await submitTriplet(triplet)
            case .cooldown:
                break
            }
        }
    }
}
