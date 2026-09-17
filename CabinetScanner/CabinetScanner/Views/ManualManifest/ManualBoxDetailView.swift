import SwiftUI

struct ManualBoxDetailView: View {
    @ObservedObject var viewModel: ManualBoxDetailViewModel
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var showScanner = false
    @State private var showManualItemSheet = false
    @State private var showCloseBoxConfirm = false
    @State private var showDimensionsSheet = false
    @State private var itemToDelete: ManualManifestItem?

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.items.isEmpty && !viewModel.isLoading {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "barcode.viewfinder")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No items yet")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    if viewModel.box.isOpen && !viewModel.isManifestFinished {
                        Text("Scan labels or add items manually")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
            } else {
                List {
                    ForEach(viewModel.items) { item in
                        ManualItemRow(item: item)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if viewModel.box.isOpen && !viewModel.isManifestFinished {
                                    Button(role: .destructive) {
                                        itemToDelete = item
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                    }
                }
                .refreshable {
                    await viewModel.loadItems()
                }
            }

            if viewModel.box.isOpen && !viewModel.isManifestFinished {
                openBoxActions
            } else if viewModel.box.isClosed {
                closedBoxInfo
            }
        }
        .navigationTitle("Box \(viewModel.box.boxNumber)")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        printBoxLabel()
                    } label: {
                        Label("Print Label", systemImage: "printer")
                    }

                    if viewModel.box.isClosed && !viewModel.isManifestFinished {
                        Button {
                            showDimensionsSheet = true
                        } label: {
                            Label(
                                viewModel.box.dimensionsDisplay != nil ? "Edit Dimensions" : "Add Dimensions",
                                systemImage: "ruler"
                            )
                        }

                        Button {
                            Task { await viewModel.reopenBox() }
                        } label: {
                            Label("Reopen Box", systemImage: "lock.open.fill")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("Delete Item?", isPresented: .init(
            get: { itemToDelete != nil },
            set: { if !$0 { itemToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { itemToDelete = nil }
            Button("Delete", role: .destructive) {
                if let item = itemToDelete {
                    Task { await viewModel.deleteItem(item) }
                }
                itemToDelete = nil
            }
        } message: {
            if let item = itemToDelete {
                Text("Remove \(item.displayName) from this box?")
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
        }
        .sheet(isPresented: $showDimensionsSheet) {
            DimensionsSheet(
                initialLength: viewModel.box.lengthMM,
                initialWidth: viewModel.box.widthMM,
                initialHeight: viewModel.box.heightMM,
                initialWeight: viewModel.box.weightKG
            ) { length, width, height, weight in
                Task { await viewModel.updateDimensions(lengthMM: length, widthMM: width, heightMM: height, weightKG: weight) }
            }
        }
        .alert("Close Box?", isPresented: $showCloseBoxConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Close") {
                Task {
                    let closed = await viewModel.closeBoxSimple()
                    if closed {
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        dismiss()
                    }
                }
            }
        } message: {
            Text("This will close the box. You can add dimensions and weight afterwards.")
        }
        .overlay(alignment: .bottom) {
            ToastView(message: $viewModel.toastMessage)
                .padding(.bottom, 120)
        }
        .task {
            await viewModel.loadItems()
        }
    }

    // MARK: - Open box action buttons

    private var openBoxActions: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    showScanner = true
                } label: {
                    Label("Scan Label", systemImage: "barcode.viewfinder")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Button {
                    showManualItemSheet = true
                } label: {
                    Label("Add Item", systemImage: "plus.circle")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.green)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }

            Button {
                showCloseBoxConfirm = true
            } label: {
                Label("Close Box", systemImage: "lock.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.orange)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding()
    }

    // MARK: - Closed box info

    private var closedBoxInfo: some View {
        VStack(spacing: 8) {
            if viewModel.box.dimensionsDisplay != nil || viewModel.box.weightDisplay != nil {
                HStack {
                    if let dims = viewModel.box.dimensionsDisplay {
                        Label(dims, systemImage: "ruler")
                            .font(.subheadline)
                    }
                    Spacer()
                    if let weight = viewModel.box.weightDisplay {
                        Label(weight, systemImage: "scalemass")
                            .font(.subheadline)
                    }
                }
                .foregroundStyle(.secondary)
            } else if !viewModel.isManifestFinished {
                Button {
                    showDimensionsSheet = true
                } label: {
                    Label("Add Dimensions & Weight", systemImage: "ruler")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .tint(.blue)
            }

            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                Text("Box Closed")
            }
            .font(.headline)
            .foregroundStyle(.green)
        }
        .padding()
        .background(.green.opacity(0.08))
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
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.displayName)
                        .font(.body.weight(.bold))

                    if item.isManual {
                        Text("Manual")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.purple.opacity(0.15))
                            .foregroundStyle(.purple)
                            .clipShape(Capsule())
                    }
                }

                if let detail = item.detailLine {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text("×\(item.qty)")
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
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
            CameraPreviewView(session: coordinator.cameraService.captureSession)
                .ignoresSafeArea()

            ScanOverlayView()
                .ignoresSafeArea()

            VStack {
                HStack {
                    Button {
                        coordinator.stop()
                        onDismiss()
                    } label: {
                        Text("Cancel")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                    }

                    Spacer()

                    Button {
                        coordinator.cameraService.toggleTorch()
                    } label: {
                        Image(systemName: coordinator.cameraService.isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                }
                .padding()

                Spacer()

                HStack(spacing: 8) {
                    Image(systemName: "viewfinder")
                    Text(coordinator.scanHint)
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.bottom, 60)
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

// MARK: - Add Manual Item Sheet

struct AddManualItemSheet: View {
    let onAdd: (String, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var itemName = ""
    @State private var quantity = 1

    var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    TextField("Item name (e.g. Hinge pack)", text: $itemName)
                        .textInputAutocapitalization(.words)
                    Stepper("Quantity: \(quantity)", value: $quantity, in: 1...9999)
                }
            }
            .navigationTitle("Add Manual Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(itemName, quantity)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(itemName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
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
        NavigationStack {
            Form {
                Section("Dimensions (mm)") {
                    HStack {
                        Text("Length")
                        Spacer()
                        TextField("mm", text: $lengthStr)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                    HStack {
                        Text("Width")
                        Spacer()
                        TextField("mm", text: $widthStr)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                    HStack {
                        Text("Height")
                        Spacer()
                        TextField("mm", text: $heightStr)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                }

                Section("Weight") {
                    HStack {
                        Text("Weight (kg)")
                        Spacer()
                        TextField("kg", text: $weightStr)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                }
            }
            .navigationTitle("Dimensions & Weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let l = Int(lengthStr),
                              let w = Int(widthStr),
                              let h = Int(heightStr),
                              let wt = Double(weightStr) else { return }
                        onSave(l, w, h, wt)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!isValid)
                }
            }
        }
        .presentationDetents([.medium])
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
