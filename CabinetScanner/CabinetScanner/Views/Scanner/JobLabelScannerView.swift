import CabinetDesign
import SwiftUI

// MARK: - Scan a job label
//
// Opens a job from the QR code on its label. The labels the Ops website
// prints carry "<sales order>-<box>" (e.g. "9731-1"), which its own despatch
// scanner reads as a box; here it means "sales order 9731". Job links
// (https://ops…/jobs/<id>, cabinetscanner://job/<id>) and "job:9731" work too.

/// What a job label's QR code points at.
enum JobLabelTarget: Hashable {
    case jobId(String)
    case salesOrder(String)

    init?(payload: String) {
        let value = payload.trimmingCharacters(in: .whitespacesAndNewlines)

        // Only something with "://" is a link; "job:9731" also parses as a URL.
        if value.contains("://"), let url = URL(string: value) {
            if let link = DeepLink.parse(url), case .job(let id) = link {
                self = .jobId(id)
                return
            }
            // https://<ops host>/jobs/<sales order>: the website resolves a
            // number in that position, so the app does too.
            if let host = url.host?.lowercased(), DeepLink.knownHosts.contains(host) {
                let parts = url.pathComponents.filter { $0 != "/" }
                if parts.count == 2, parts[0].lowercased() == "jobs", Self.isNumber(parts[1]) {
                    self = .salesOrder(parts[1])
                    return
                }
            }
            return nil
        }

        let lower = value.lowercased()
        if lower.hasPrefix("job:"), Self.isNumber(String(value.dropFirst(4))) {
            self = .salesOrder(String(value.dropFirst(4)))
        } else if Self.isNumber(value) {
            self = .salesOrder(value)
        } else if let dash = value.lastIndex(of: "-"),
                  Self.isNumber(String(value[..<dash])),
                  Self.isNumber(String(value[value.index(after: dash)...])) {
            // "9731-1": sales order, then box number.
            self = .salesOrder(String(value[..<dash]))
        } else {
            return nil
        }
    }

    private static func isNumber(_ s: String) -> Bool {
        !s.isEmpty && s.count <= 9 && s.allSatisfy(\.isNumber)
    }
}

@MainActor
final class JobLabelScanCoordinator: ObservableObject, CameraServiceDelegate {
    let cameraService = CameraService()
    let geometry = PreviewGeometry()
    @Published var hint = "Hold the job label's QR code in the frame"
    /// Where the found label is on screen, for the corners to close on.
    @Published var lock: CGRect?
    var onFound: ((JobLabelTarget) -> Void)?
    private var found = false

    func start() {
        found = false
        lock = nil
        cameraService.delegate = self
        Task {
            await cameraService.checkPermission()
            cameraService.configure()
            cameraService.start()
        }
    }

    func stop() {
        cameraService.stop()
        cameraService.delegate = nil
    }

    nonisolated func cameraService(_ service: CameraService, didDetect detections: [ScanAssembler.Detection]) {
        Task { @MainActor in
            guard !found else { return }
            let codes = detections.filter { $0.symbology == .qr }
            if let code = codes.first(where: { JobLabelTarget(payload: $0.payload) != nil }),
               let target = JobLabelTarget(payload: code.payload) {
                found = true
                HapticService.success()
                // Hold the frame with the corners on the label for a beat,
                // then open the job.
                lock = geometry.rect(forVisionBox: code.boundingBox) ?? .zero
                switch target {
                case .salesOrder(let number): hint = "Found sales order \(number)"
                case .jobId: hint = "Found the job"
                }
                try? await Task.sleep(for: .seconds(UIAccessibility.isReduceMotionEnabled ? 0.2 : 0.5))
                stop()
                onFound?(target)
            } else if !codes.isEmpty {
                hint = "That QR isn't a job label. Panel labels are scanned from a box in Packing."
            }
        }
    }
}

struct JobLabelScannerView: View {
    let onFound: (JobLabelTarget) -> Void
    let onCancel: () -> Void

    @StateObject private var coordinator = JobLabelScanCoordinator()

    var body: some View {
        ZStack {
            PaperColor.inverse.ignoresSafeArea()

            CameraPreviewView(session: coordinator.cameraService.captureSession, geometry: coordinator.geometry)
                .ignoresSafeArea()

            ScanOverlayView(lock: coordinator.lock)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                HStack {
                    Button("Cancel") {
                        coordinator.stop()
                        onCancel()
                    }
                    .buttonStyle(.paperPill(.paper, .compact))
                    Spacer()
                }
                .paperMargins()
                .padding(.top, PaperSpace.l)

                Spacer()

                ResultBand(outcome: .ready(hint: coordinator.hint))
                    .frame(maxWidth: 560)
                    .paperMargins()
                    .padding(.bottom, PaperSpace.section)
            }
        }
        .onAppear {
            coordinator.onFound = onFound
            coordinator.start()
        }
        .onDisappear {
            coordinator.stop()
        }
        .statusBarHidden()
    }
}
