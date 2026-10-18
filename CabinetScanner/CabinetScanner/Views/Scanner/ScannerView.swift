import CabinetDesign
import SwiftUI

/// The full-screen scanner over a box. The camera, the assembler and the
/// view model's states and timing are as they were; this is the frame
/// around them: corners that take the result's colour, and the result band.
struct ScannerView: View {
    @ObservedObject var viewModel: ScannerViewModel
    let onDismiss: () -> Void

    private var outcome: ScanOutcome {
        ScanOutcome(state: viewModel.scanState, flash: viewModel.successFlashLabel)
    }

    var body: some View {
        ZStack {
            PaperColor.inverse.ignoresSafeArea()

            // Camera preview
            CameraPreviewView(session: viewModel.cameraService.captureSession)
                .ignoresSafeArea()

            // Dimmed camera with the scan window
            ScanOverlayView(cornerColor: outcome.isResult ? outcome.tone.color : PaperColor.onInverse)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                topBar
                Spacer()
                VStack(alignment: .leading, spacing: PaperSpace.m) {
                    ResultBand(outcome: outcome)
                    lastAdded
                }
                .frame(maxWidth: 560)
                .paperMargins()
                .padding(.bottom, PaperSpace.xxl)
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

    private var topBar: some View {
        HStack(spacing: PaperSpace.m) {
            Button("Done") {
                viewModel.stopScanning()
                onDismiss()
            }
            .buttonStyle(.paperPill(.paper, .compact))

            Spacer()

            // Continuous mode toggle
            Button {
                viewModel.continuousMode.toggle()
            } label: {
                Text(viewModel.continuousMode ? "Continuous" : "One at a time")
                    .paperType(.footnote)
                    .foregroundStyle(PaperColor.onInverse)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 34)
                    .overlay(Capsule().strokeBorder(PaperColor.onInverseMuted, lineWidth: 1))
                    .contentShape(Capsule())
                    .frame(minHeight: PaperSpace.tap)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(viewModel.continuousMode ? "Continuous scanning, on" : "Continuous scanning, off")

            // Torch
            TorchButton(camera: viewModel.cameraService)
        }
        .paperMargins()
        .padding(.top, PaperSpace.l)
    }

    @ViewBuilder private var lastAdded: some View {
        // Always the same height, so the band above never moves.
        HStack(spacing: PaperSpace.s) {
            if let lastLabel = viewModel.lastSuccessLabel {
                PaperIcon(.check, size: 14, lineWidth: 2.2, color: PaperColor.onInverseMuted)
                Text("Last added: \(lastLabel)")
                    .paperType(.footnote, numeric: true)
                    .foregroundStyle(PaperColor.onInverse)
                    .lineLimit(1)
            }
        }
        .frame(height: 20, alignment: .leading)
        .padding(.horizontal, PaperSpace.xs)
    }
}

/// Observes the camera so the torch shows whether it's on.
private struct TorchButton: View {
    @ObservedObject var camera: CameraService

    var body: some View {
        Button {
            camera.toggleTorch()
        } label: {
            PaperIcon(.torch, size: 22, color: camera.isTorchOn ? PaperColor.onAccent : PaperColor.onInverse)
                .frame(width: 44, height: 44)
                .background(camera.isTorchOn ? PaperColor.accent : .clear, in: Circle())
        }
        .buttonStyle(.paperIcon)
        .accessibilityLabel(camera.isTorchOn ? "Torch, on" : "Torch, off")
    }
}
