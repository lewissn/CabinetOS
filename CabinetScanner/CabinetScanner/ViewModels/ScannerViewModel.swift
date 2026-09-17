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
    /// Continuous mode is default-ON: opening a panel box almost always means
    /// scanning more than one panel, and the back-and-forth was a friction
    /// point. Toggle it off in the scanner UI for one-shot scans.
    @Published var continuousMode: Bool = true
    @Published var shouldDismiss = false

    /// Dedicated success-flash banner that is independent of `scanState`.
    /// Set on every successful scan and auto-cleared after ~1s. The previous
    /// design relied on `scanState == .success` for the green confirmation,
    /// but in continuous mode the state flipped back to `.scanning` after
    /// 400 ms so SwiftUI sometimes never rendered the success frame on
    /// slower devices. This published value gives the view a reliable signal.
    @Published var successFlashLabel: String?
    private var successFlashTask: Task<Void, Never>?

    let boxId: String
    let manifestId: String
    let consignmentId: String
    /// The project name of the consignment we're scanning into. Passed to the
    /// ScanAssembler so it can disambiguate the two QR codes on the new label
    /// format (project + cabinet are both QRs). Optional for backwards
    /// compatibility — when nil, the assembler falls back to a length
    /// heuristic and only commits clearly-distinguishable pairs.
    let expectedProjectName: String?
    let cameraService: CameraService
    let assembler: ScanAssembler

    private let api: APIServiceProtocol
    private let appState: AppState
    private let cache: ScanCacheService
    private let queue: ScanQueueService

    private var isProcessing = false

    init(
        boxId: String,
        manifestId: String,
        consignmentId: String,
        appState: AppState,
        expectedProjectName: String? = nil,
        api: APIServiceProtocol = ServiceContainer.shared.api,
        cache: ScanCacheService = ScanCacheService.shared,
        queue: ScanQueueService = ScanQueueService.shared
    ) {
        self.boxId = boxId
        self.manifestId = manifestId
        self.consignmentId = consignmentId
        self.expectedProjectName = expectedProjectName
        self.appState = appState
        self.api = api
        self.cache = cache
        self.queue = queue
        self.cameraService = CameraService()
        self.assembler = ScanAssembler(expectedProjectName: expectedProjectName)
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

        if Configuration.useOfflineQueue {
            await submitTripletOffline(triplet)
        } else {
            await submitTripletLegacy(triplet)
        }
    }

    /// Fast path: validate locally against cached registry, optimistically
    /// record the scan, hand off to the queue for background sync.
    private func submitTripletOffline(_ triplet: ScanTriplet) async {
        let result = await cache.validate(
            boxId: boxId,
            manifestId: manifestId,
            consignmentId: consignmentId,
            triplet: triplet
        )

        switch result {
        case .notInRegistry:
            await showError(
                "Part \"\(triplet.cabinetName) — \(triplet.partNumber)\" is not on this manifest",
                kind: .notOnManifest
            )

        case .alreadyPacked:
            await showError("This part has already been packed", kind: .alreadyPacked)

        case .registryNotCached:
            await showError(
                "Open this box once while online to download its parts list before scanning offline",
                kind: .registryNotCached
            )

        case .ok:
            let now = Date()
            let pending = PendingScan(
                boxId: boxId,
                manifestId: manifestId,
                consignmentId: consignmentId,
                projectName: triplet.projectName,
                cabinetName: triplet.cabinetName,
                partNumber: triplet.partNumber,
                scannedAt: now,
                deviceId: appState.deviceId,
                stationId: appState.stationId,
                operatorName: appState.operatorName.isEmpty ? nil : appState.operatorName
            )
            await cache.recordLocalScan(pending)
            await queue.enqueue(pending)

            HapticService.success()
            HapticService.playTickSound()
            let label = "\(triplet.cabinetName) — Part \(triplet.partNumber)"
            lastSuccessLabel = label
            scanState = .success(label)
            flashSuccess(label: label)

            if continuousMode {
                // Tighter cooldown — operators scan multiple panels in
                // rapid succession; 400ms is enough for the success state
                // to register without slowing them down.
                try? await Task.sleep(nanoseconds: 400_000_000)
                assembler.clearCooldown()
                scanState = .scanning(hint: "Scan next label")
                isProcessing = false
            } else {
                try? await Task.sleep(nanoseconds: 800_000_000)
                stopScanning()
                shouldDismiss = true
            }
        }
    }

    /// Legacy path: per-scan API call. Kept for the staged rollout flag and
    /// for environments where the cache hasn't been pre-warmed yet.
    private func submitTripletLegacy(_ triplet: ScanTriplet) async {
        let request = ScanRequest(
            manifestId: manifestId,
            consignmentId: consignmentId,
            projectName: triplet.projectName,
            cabinetName: triplet.cabinetName,
            partNumber: triplet.partNumber,
            deviceId: appState.deviceId,
            stationId: appState.stationId,
            operator_: appState.operatorName.isEmpty ? nil : appState.operatorName,
            scannedAt: DateFormatters.iso8601.string(from: Date())
        )

        do {
            let response = try await api.scanItem(boxId: boxId, request: request)

            if response.ok {
                HapticService.success()
                HapticService.playTickSound()
                let label = "\(triplet.cabinetName) — Part \(triplet.partNumber)"
                lastSuccessLabel = label
                scanState = .success(label)
                flashSuccess(label: label)

                if continuousMode {
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    assembler.clearCooldown()
                    scanState = .scanning(hint: "Scan next label")
                    isProcessing = false
                } else {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    stopScanning()
                    shouldDismiss = true
                }
            } else {
                let kind: ScanErrorKind = {
                    switch response.code {
                    case "ALREADY_PACKED":      return .alreadyPacked
                    case "NOT_ON_MANIFEST":     return .notOnManifest
                    case "WRONG_CONSIGNMENT":   return .wrongConsignment
                    default:                    return .generic
                    }
                }()
                await showError(response.message ?? "Scan rejected", kind: kind)
            }
        } catch {
            await showError(error.localizedDescription)
        }
    }

    /// Show the dedicated green success banner for ~1.1s. Each call cancels
    /// any in-flight clear task so back-to-back successes refresh the banner
    /// rather than flickering.
    private func flashSuccess(label: String) {
        successFlashTask?.cancel()
        successFlashLabel = label
        successFlashTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.successFlashLabel = nil
            }
        }
    }

    /// Distinct error categories so we can play distinct haptic + audio
    /// patterns. In a noisy warehouse the operator should be able to tell
    /// what kind of fault happened without looking at the screen.
    enum ScanErrorKind {
        case alreadyPacked
        case notOnManifest
        case wrongConsignment
        case registryNotCached
        case generic
    }

    private func showError(_ message: String, kind: ScanErrorKind = .generic) async {
        switch kind {
        case .alreadyPacked:        HapticService.alreadyPacked()
        case .notOnManifest:        HapticService.notOnManifest()
        case .wrongConsignment:     HapticService.wrongConsignment()
        case .registryNotCached:    HapticService.registryNotCached()
        case .generic:              HapticService.error()
        }
        scanState = .error(message)
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        assembler.clearCooldown()
        scanState = .scanning(hint: "Scan label — find QR code")
        isProcessing = false
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
