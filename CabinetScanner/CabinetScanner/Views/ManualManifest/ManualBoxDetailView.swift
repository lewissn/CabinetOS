import CabinetDesign
import SwiftUI

/// A box on a courier manifest: what's in it, Scan / Add item, and Close
/// box; once closed, its size and weight. Writes go straight to Supabase.
struct ManualBoxDetailView: View {
    @ObservedObject var viewModel: ManualBoxDetailViewModel
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var showScanner = false
    @State private var showManualItemSheet = false
    @State private var showCloseBoxConfirm = false
    @State private var showDimensionsSheet = false
    @State private var itemToDelete: ManualManifestItem?

    private var box: ManualManifestBox { viewModel.box }
    private var canEdit: Bool { box.isOpen && !viewModel.isManifestFinished }

    var body: some View {
        PushedScreen(back: "Manifest", scrolls: false) {
            BarIcon(glyph: .printer, label: "Print label") { printBoxLabel() }
            if box.isClosed && !viewModel.isManifestFinished {
                Menu {
                    Button {
                        showDimensionsSheet = true
                    } label: {
                        Label(box.dimensionsDisplay != nil ? "Change size and weight" : "Add size and weight", systemImage: "ruler")
                    }
                    Button {
                        Task { await viewModel.reopenBox() }
                    } label: {
                        Label("Reopen box", systemImage: "lock.open")
                    }
                } label: {
                    PaperIcon(.more, size: 22)
                        .frame(width: PaperSpace.tap, height: PaperSpace.tap)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("More")
            }
        } content: {
            List {
                header.paperListRow()

                PaperFigure(PaperFormat.int(viewModel.items.reduce(0) { $0 + $1.qty }), unit: "in this box", style: .heroS)
                    .paperListRow(top: PaperSpace.xxl)

                if canEdit {
                    openBoxActions.paperListRow(top: PaperSpace.xxl)
                } else if box.isClosed {
                    closedBoxInfo.paperListRow(top: PaperSpace.xxl)
                }

                PaperSectionHeader("In the box").paperListRow(top: PaperSpace.section)
                if viewModel.items.isEmpty {
                    Text(viewModel.isLoading ? "Loading" : (canEdit ? "Nothing yet. Scan a label or add an item." : "Nothing was put in this box."))
                        .paperType(.subhead)
                        .foregroundStyle(PaperColor.secondary)
                        .padding(.vertical, PaperSpace.m)
                        .paperListRow()
                } else {
                    ForEach(viewModel.items) { item in
                        ManualItemRow(item: item)
                            .paperListRow()
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if canEdit {
                                    Button(role: .destructive) {
                                        itemToDelete = item
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                    }
                }

                if canEdit {
                    Button("Close box \(box.boxNumber)") { showCloseBoxConfirm = true }
                        .buttonStyle(.paperPill(.ink, .floor, fullWidth: true))
                        .paperListRow(top: PaperSpace.section, bottom: 120)
                } else {
                    Color.clear.frame(height: 120).paperListRow()
                }
            }
            .paperList()
            .refreshable {
                await viewModel.loadItems()
            }
        }
        .alert("Remove this item?", isPresented: .init(
            get: { itemToDelete != nil },
            set: { if !$0 { itemToDelete = nil } }
        )) {
            Button("Keep it", role: .cancel) { itemToDelete = nil }
            Button("Remove item", role: .destructive) {
                if let item = itemToDelete {
                    Task { await viewModel.deleteItem(item) }
                }
                itemToDelete = nil
            }
        } message: {
            if let item = itemToDelete {
                Text("\(item.displayName) comes out of this box.")
            }
        }
        .fullScreenCover(isPresented: $showScanner) {
            ManualBoxScannerView(
                onScan: { triplet in
                    Task { await viewModel.addScannedItem(triplet: triplet) }
                },
                onDismiss: {
                    showScanner = false
                }
            )
        }
        .sheet(isPresented: $showManualItemSheet) {
            AddManualItemSheet { name, qty in
                Task { await viewModel.addManualItem(name: name, quantity: qty) }
            }
            .paperSheet(detents: [.medium])
        }
        .sheet(isPresented: $showDimensionsSheet) {
            DimensionsSheet(
                initialLength: box.lengthMM,
                initialWidth: box.widthMM,
                initialHeight: box.heightMM,
                initialWeight: box.weightKG
            ) { length, width, height, weight in
                Task { await viewModel.updateDimensions(lengthMM: length, widthMM: width, heightMM: height, weightKG: weight) }
            }
            .paperSheet(detents: [.medium, .large])
        }
        .alert("Close box \(box.boxNumber)?", isPresented: $showCloseBoxConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Close box") {
                Task {
                    let closed = await viewModel.closeBoxSimple()
                    if closed {
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        dismiss()
                    }
                }
            }
        } message: {
            Text("You can add its size and weight afterwards.")
        }
        .overlay(alignment: .bottom) {
            ToastView(message: $viewModel.toastMessage, glyph: viewModel.toastMessage?.hasPrefix("Duplicate") == true ? nil : .check)
        }
        .task {
            await viewModel.loadItems()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: PaperSpace.s) {
            Text(viewModel.manifestName).paperType(.footnote).foregroundStyle(PaperColor.secondary).lineLimit(1)
            Text("Box \(box.boxNumber)")
                .paperType(.largeTitle)
                .foregroundStyle(PaperColor.ink)
                .accessibilityAddTraits(.isHeader)
            StatusText(box.isClosed ? "Closed" : "Open", tone: box.isClosed ? .done : .progress, style: .subhead)
        }
    }

    // MARK: - Open box actions

    private var openBoxActions: some View {
        HStack(spacing: PaperSpace.m) {
            Button {
                showScanner = true
            } label: {
                Label { Text("Scan label") } icon: { PaperIcon(.scan, size: 20, color: PaperColor.onAccent) }
            }
            .buttonStyle(.paperPill(.accent, .floor, fullWidth: true))

            Button("Add item") { showManualItemSheet = true }
                .buttonStyle(.paperPill(.outline, .floor))
        }
    }

    // MARK: - Closed box info

    @ViewBuilder
    private var closedBoxInfo: some View {
        if box.dimensionsDisplay != nil || box.weightDisplay != nil {
            VStack(alignment: .leading, spacing: 0) {
                if let dims = box.dimensionsDisplay { FactRow(label: "Size", value: dims) }
                if let weight = box.weightDisplay { FactRow(label: "Weight", value: weight) }
            }
        } else if !viewModel.isManifestFinished {
            Button("Add size and weight") { showDimensionsSheet = true }
                .buttonStyle(.paperPill(.accent, .large, fullWidth: true))
        }
    }

    // MARK: - Print

    private func printBoxLabel() {
        let totalBoxes = 0 // Could be passed from parent if needed
        let labelView = ManualBoxLabelView(
            manifestName: viewModel.manifestName,
            boxNumber: viewModel.box.boxNumber,
            totalBoxes: totalBoxes,
            dimensions: viewModel.box.dimensionsDisplay,
            weight: viewModel.box.weightDisplay,
            courier: viewModel.courierName
        )

        let mmToPoints: CGFloat = 72.0 / 25.4
        let widthPt = 100.0 * mmToPoints
        let heightPt = 150.0 * mmToPoints

        let renderer = ImageRenderer(content:
            labelView
                .frame(width: widthPt, height: heightPt)
                .background(.white)
        )
        renderer.scale = 3.0

        guard let image = renderer.uiImage else { return }
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first,
              let rootVC = windowScene.windows.first?.rootViewController else { return }

        let activityVC = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        activityVC.popoverPresentationController?.sourceView = rootVC.view
        rootVC.present(activityVC, animated: true)
    }
}

// MARK: - Manual Item Row

struct ManualItemRow: View {
    let item: ManualManifestItem

    var body: some View {
        RowContainer {
            HStack(alignment: .firstTextBaseline, spacing: PaperSpace.m) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: PaperSpace.s) {
                        Text(item.displayName).paperType(.body).foregroundStyle(PaperColor.ink)
                        if item.isManual {
                            Text("added by hand").paperType(.caption).foregroundStyle(PaperColor.tertiary)
                        }
                    }
                    if let detail = item.detailLine {
                        Text(detail).paperType(.footnote, numeric: true).foregroundStyle(PaperColor.secondary)
                    }
                }
                Spacer(minLength: PaperSpace.m)
                Text("× \(item.qty)").paperType(.subhead, numeric: true).foregroundStyle(PaperColor.body)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Scanner coordinator (class-based to satisfy CameraServiceDelegate: AnyObject)

@MainActor
final class ManualBoxScannerCoordinator: ObservableObject, CameraServiceDelegate {
    let cameraService = CameraService()
    let assembler = ScanAssembler()
    var onScan: ((ScanTriplet) -> Void)?
    var onDismiss: (() -> Void)?

    @Published var scanHint = "Position label in the scan area"
    @Published var lastScanned: String?

    func start() {
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
            let status = assembler.addDetections(detections)
            switch status {
            case .searching(let hint):
                self.scanHint = hint
            case .assembled(let triplet):
                self.onScan?(triplet)
                self.stop()
                self.onDismiss?()
            case .cooldown:
                break
            }
        }
    }
}

// MARK: - Scanner wrapper for manual box (reuses ScanAssembler)

struct ManualBoxScannerView: View {
    let onScan: (ScanTriplet) -> Void
    let onDismiss: () -> Void

    @StateObject private var coordinator = ManualBoxScannerCoordinator()

    var body: some View {
        ZStack {
            PaperColor.inverse.ignoresSafeArea()

            CameraPreviewView(session: coordinator.cameraService.captureSession)
                .ignoresSafeArea()

            ScanOverlayView()
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                HStack {
                    Button("Cancel") {
                        coordinator.stop()
                        onDismiss()
                    }
                    .buttonStyle(.paperPill(.paper, .compact))

                    Spacer()

                    ManualTorchButton(camera: coordinator.cameraService)
                }
                .paperMargins()
                .padding(.top, PaperSpace.l)

                Spacer()

                ResultBand(outcome: .ready(hint: coordinator.scanHint))
                    .frame(maxWidth: 560)
                    .paperMargins()
                    .padding(.bottom, PaperSpace.section)
            }
        }
        .onAppear {
            coordinator.onScan = onScan
            coordinator.onDismiss = onDismiss
            coordinator.start()
        }
        .onDisappear {
            coordinator.stop()
        }
        .statusBarHidden()
    }
}

private struct ManualTorchButton: View {
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

// MARK: - Add Manual Item Sheet

struct AddManualItemSheet: View {
    let onAdd: (String, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var itemName = ""
    @State private var quantity = 1

    var body: some View {
        SheetScreen("Add an item") {
            VStack(alignment: .leading, spacing: PaperSpace.xxl) {
                PaperUnderlineField("Item", text: $itemName, placeholder: "For example, hinge pack")
                    .textInputAutocapitalization(.words)
                    .padding(.top, PaperSpace.l)

                VStack(alignment: .leading, spacing: PaperSpace.s) {
                    PaperLabel("Quantity")
                    HStack(spacing: PaperSpace.l) {
                        stepButton(.minus, label: "One fewer") { quantity = max(1, quantity - 1) }
                        Text("\(quantity)").paperType(.figure, numeric: true).foregroundStyle(PaperColor.ink)
                            .frame(minWidth: 48)
                            .contentTransition(.numericText())
                        stepButton(.plus, label: "One more") { quantity = min(9999, quantity + 1) }
                    }
                }

                Button("Add to box") {
                    onAdd(itemName, quantity)
                    dismiss()
                }
                .buttonStyle(.paperPill(.accent, .large, fullWidth: true))
                .disabled(itemName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func stepButton(_ glyph: PaperGlyph, label: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy) { action() }
        } label: {
            PaperIcon(glyph, size: 18, lineWidth: 2)
                .frame(width: 44, height: 44)
                .overlay(Circle().strokeBorder(PaperColor.border, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Dimensions Sheet

struct DimensionsSheet: View {
    let initialLength: Int?
    let initialWidth: Int?
    let initialHeight: Int?
    let initialWeight: Double?
    let onSave: (Int, Int, Int, Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var lengthStr = ""
    @State private var widthStr = ""
    @State private var heightStr = ""
    @State private var weightStr = ""

    private var isValid: Bool {
        guard let l = Int(lengthStr), l > 0,
              let w = Int(widthStr), w > 0,
              let h = Int(heightStr), h > 0,
              let wt = Double(weightStr), wt > 0 else { return false }
        return true
    }

    var body: some View {
        SheetScreen("Size and weight") {
            VStack(alignment: .leading, spacing: PaperSpace.xxl) {
                HStack(spacing: PaperSpace.l) {
                    PaperUnderlineField("Length", text: $lengthStr, placeholder: "–", unit: "mm", keyboard: .numberPad)
                    PaperUnderlineField("Width", text: $widthStr, placeholder: "–", unit: "mm", keyboard: .numberPad)
                    PaperUnderlineField("Height", text: $heightStr, placeholder: "–", unit: "mm", keyboard: .numberPad)
                }
                .padding(.top, PaperSpace.l)

                PaperUnderlineField("Weight", text: $weightStr, placeholder: "–", unit: "kg", keyboard: .decimalPad)

                Button("Save") {
                    guard let l = Int(lengthStr),
                          let w = Int(widthStr),
                          let h = Int(heightStr),
                          let wt = Double(weightStr) else { return }
                    onSave(l, w, h, wt)
                    dismiss()
                }
                .buttonStyle(.paperPill(.accent, .large, fullWidth: true))
                .disabled(!isValid)
            }
        }
        .onAppear {
            if let l = initialLength { lengthStr = "\(l)" }
            if let w = initialWidth { widthStr = "\(w)" }
            if let h = initialHeight { heightStr = "\(h)" }
            if let wt = initialWeight {
                weightStr = wt.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(wt))" : String(format: "%.1f", wt)
            }
        }
    }
}

// MARK: - Box Label for printing (100mm x 150mm)

private struct ManualBoxLabelView: View {
    let manifestName: String
    let boxNumber: Int
    let totalBoxes: Int
    let dimensions: String?
    let weight: String?
    let courier: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image("CabinetLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 40)
                Spacer()
            }
            .padding(.bottom, 16)

            Spacer()

            VStack(spacing: 12) {
                Text(manifestName)
                    .font(.system(size: 28, weight: .bold))
                    .multilineTextAlignment(.center)

                if totalBoxes > 0 {
                    Text("Box \(boxNumber)/\(totalBoxes)")
                        .font(.system(size: 22, weight: .bold))
                } else {
                    Text("Box \(boxNumber)")
                        .font(.system(size: 22, weight: .bold))
                }

                if let dims = dimensions {
                    Text(dims)
                        .font(.system(size: 16))
                }

                if let w = weight {
                    Text(w)
                        .font(.system(size: 16))
                }
            }

            Spacer()

            if let courier, !courier.isEmpty {
                Text(courier)
                    .font(.system(size: 24, weight: .bold))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(20)
        .foregroundStyle(.black)
    }
}
