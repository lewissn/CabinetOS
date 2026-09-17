import SwiftUI

struct ScannerView: View {
    @ObservedObject var viewModel: ScannerViewModel
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            // Camera preview
            CameraPreviewView(session: viewModel.cameraService.captureSession)
                .ignoresSafeArea()

            // Dark overlay with cutout
            ScanOverlayView()
                .ignoresSafeArea()

            // Reliable success flash banner — top of screen so it's never
            // covered by the scan reticle or status pill. Independent of
            // `scanState` so rapid state transitions in continuous mode
            // can't suppress it.
            VStack {
                if let flashLabel = viewModel.successFlashLabel {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                        Text("Added \(flashLabel)")
                            .font(.subheadline.weight(.bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(.green.opacity(0.95))
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 80)
                }
                Spacer()
            }
            .animation(.easeOut(duration: 0.18), value: viewModel.successFlashLabel)
            .allowsHitTesting(false)

            // UI controls
            VStack {
                // Top bar
                HStack {
                    Button {
                        viewModel.stopScanning()
                        onDismiss()
                    } label: {
                        Text("Done")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                    }

                    Spacer()

                    // Continuous mode toggle
                    Button {
                        viewModel.continuousMode.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: viewModel.continuousMode ? "repeat" : "1.circle")
                            Text(viewModel.continuousMode ? "Continuous" : "Single")
                                .font(.caption)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                    }

                    // Torch
                    Button {
                        viewModel.cameraService.toggleTorch()
                    } label: {
                        Image(systemName: viewModel.cameraService.isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                }
                .padding()

                Spacer()

                // Status area below the scan box
                VStack(spacing: 12) {
                    // Scan status
                    ScanStatusView(state: viewModel.scanState)

                    // Last success
                    if let lastLabel = viewModel.lastSuccessLabel {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Last: \(lastLabel)")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                    }
                }
                .padding(.bottom, 60)
            }
        }
        .onAppear {
            viewModel.startScanning()
        }
        .onDisappear {
            viewModel.stopScanning()
        }
        .onChange(of: viewModel.shouldDismiss) { _, dismiss in
            if dismiss { onDismiss() }
        }
        .statusBarHidden()
    }
}

struct ScanStatusView: View {
    let state: ScannerViewModel.ScanState

    var body: some View {
        HStack(spacing: 8) {
            statusIcon
            statusText
        }
        .font(.subheadline.weight(.bold))
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(statusBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch state {
        case .scanning:
            Image(systemName: "viewfinder")
                .foregroundStyle(.white)
        case .validating:
            ProgressView()
                .tint(.white)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.white)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.white)
        case .cooldown:
            Image(systemName: "clock")
                .foregroundStyle(.white)
        }
    }

    @ViewBuilder
    private var statusText: some View {
        switch state {
        case .scanning(let hint):
            Text(hint)
                .foregroundStyle(.white)
        case .validating(let triplet):
            Text("Validating \(triplet.cabinetName)-\(triplet.partNumber)...")
                .foregroundStyle(.white)
        case .success(let label):
            Text("Added \(label)")
                .foregroundStyle(.white)
        case .error(let msg):
            Text(msg)
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        case .cooldown:
            Text("Ready...")
                .foregroundStyle(.white)
        }
    }

    private var statusBackground: some ShapeStyle {
        switch state {
        case .scanning: return AnyShapeStyle(.ultraThinMaterial)
        case .validating: return AnyShapeStyle(.blue.opacity(0.8))
        case .success: return AnyShapeStyle(.green.opacity(0.85))
        case .error: return AnyShapeStyle(.red.opacity(0.85))
        case .cooldown: return AnyShapeStyle(.ultraThinMaterial)
        }
    }
}
