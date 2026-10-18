import CabinetDesign
import SwiftUI

/// A box: how many panels are in it, the job's progress by cabinet, the
/// scanner, what's been scanned, and Close box. The scanning itself happens
/// in ScannerView, full screen, exactly as before.
struct BoxDetailView: View {
    @StateObject private var viewModel: BoxDetailViewModel
    @EnvironmentObject var appState: AppState
    @EnvironmentObject private var toaster: Toaster
    @ObservedObject private var network = NetworkMonitor.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showScanner = false
    @State private var showDeleteConfirm = false
    @State private var itemToDelete: BoxItem?
    @State private var showPendingSync = false
    @State private var showConflicts = false
    @State private var showCloseSheet = false
    @State private var showManualEntry = false
    @State private var isClosing = false
    @State private var cabinets: [ScanCacheService.CabinetSummary] = []

    init(box: Box, manifestId: String, consignmentId: String, customerName: String, manifestName: String) {
        _viewModel = StateObject(wrappedValue: BoxDetailViewModel(
            box: box,
            manifestId: manifestId,
            consignmentId: consignmentId,
            customerName: customerName,
            manifestName: manifestName
        ))
    }

    private var box: Box { viewModel.box }
    private var tracksPanels: Bool { Configuration.useOfflineQueue && box.boxType == .panel }

    var body: some View {
        PushedScreen(back: "Boxes", scrolls: false) {
            HStack(spacing: 0) {
                if Configuration.useOfflineQueue && box.boxType.fixedDimensions == nil {
                    SyncBadgeView(
                        pendingCount: viewModel.pendingCount,
                        conflictCount: viewModel.conflictCount,
                        isOnline: network.isOnline
                    )
                    .padding(.trailing, PaperSpace.xs)
                }
                if Configuration.useOfflineQueue && box.isOpen && box.boxType == .panel {
                    BarIcon(glyph: .keyboard, label: "Add a panel by hand") { showManualEntry = true }
                }
                BarIcon(glyph: .printer, label: "Print label") { printBoxLabel() }
                moreMenu
            }
        } content: {
            List {
                header.paperListRow()

                if let dims = box.boxType.fixedDimensions {
                    fixedBoxInfo(dims).paperListRow(top: PaperSpace.xxl, bottom: 120)
                } else {
                    figures.paperListRow(top: PaperSpace.xxl)

                    if Configuration.useOfflineQueue && !network.isOnline {
                        OfflineBannerView().paperListRow(top: PaperSpace.xl)
                    }
                    if Configuration.useOfflineQueue && (viewModel.pendingCount > 0 || viewModel.conflictCount > 0) {
                        syncRows.paperListRow(top: PaperSpace.l)
                    }
                    if let error = viewModel.errorMessage {
                        Notice(text: error, tone: .held).paperListRow(top: PaperSpace.l)
                    }

                    actions.paperListRow(top: PaperSpace.xxl)

                    items
                }
            }
            .paperList()
            .refreshable {
                await viewModel.loadBoxDetail()
            }
        }
        .navigationDestination(isPresented: $showPendingSync) {
            PendingSyncView(
                boxId: viewModel.box.id,
                manifestId: viewModel.manifestId,
                projectName: viewModel.projectName
            )
        }
        .navigationDestination(isPresented: $showConflicts) {
            ScanConflictsView(boxId: viewModel.box.id)
        }
        .alert("Remove this panel?", isPresented: .init(
            get: { itemToDelete != nil },
            set: { if !$0 { itemToDelete = nil } }
        )) {
            Button("Keep it", role: .cancel) { itemToDelete = nil }
            Button("Remove panel", role: .destructive) {
                if let item = itemToDelete {
                    Task { await viewModel.deleteItem(item) }
                }
                itemToDelete = nil
            }
        } message: {
            if let item = itemToDelete {
                Text("\(item.cabinetName) part \(item.partNumber) comes out of this box.")
            }
        }
        .alert("Delete \(box.title.lowercased())?", isPresented: $showDeleteConfirm) {
            Button("Keep box", role: .cancel) {}
            Button("Delete box", role: .destructive) {
                Task {
                    let deleted = await viewModel.deleteBox()
                    if deleted { dismiss() }
                }
            }
        } message: {
            Text("The box and everything scanned into it are deleted. This can't be undone.")
        }
        .sheet(isPresented: $showCloseSheet) {
            CloseBoxSheet(
                box: box,
                count: viewModel.items.count,
                wrappedBy: appState.operatorName,
                missingCount: tracksPanels ? viewModel.missingPanelUids.count : 0,
                missingPreview: tracksPanels ? Array(viewModel.missingPanelLabels.prefix(5)) : [],
                customerName: viewModel.customerName,
                isClosing: isClosing,
                onClose: performClose
            )
            .paperSheet(detents: [.medium, .large])
        }
        .sheet(isPresented: $showManualEntry, onDismiss: {
            Task { await viewModel.loadBoxDetail() }
        }) {
            ManualEntryView(
                boxId: viewModel.box.id,
                manifestId: viewModel.manifestId,
                consignmentId: viewModel.consignmentId,
                projectName: viewModel.projectName,
                appState: appState
            )
            .paperSheet()
        }
        .fullScreenCover(isPresented: $showScanner) {
            ScannerView(
                viewModel: ScannerViewModel(
                    boxId: viewModel.box.id,
                    manifestId: viewModel.manifestId,
                    consignmentId: viewModel.consignmentId,
                    appState: appState,
                    expectedProjectName: viewModel.projectName
                ),
                onDismiss: {
                    showScanner = false
                    Task { await viewModel.loadBoxDetail() }
                }
            )
        }
        .overlay(alignment: .bottom) {
            ToastView(message: $viewModel.toastMessage)
        }
        .onAppear {
            viewModel.startPolling()
        }
        .onDisappear {
            viewModel.stopPolling()
        }
        .task {
            await viewModel.loadBoxDetail()
        }
        // Per-cabinet progress, from the cached parts list only. Nothing is
        // fetched for it: if the list isn't cached, the bars aren't shown.
        .task(id: viewModel.jobPackedCount) {
            guard tracksPanels else { return }
            cabinets = await ScanCacheService.shared.cabinets(
                manifestId: viewModel.manifestId,
                projectName: viewModel.projectName,
                consignmentId: viewModel.consignmentId
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: PaperSpace.s) {
            Text(viewModel.customerName).paperType(.footnote).foregroundStyle(PaperColor.secondary).lineLimit(1)
            Text(box.title)
                .paperType(.largeTitle)
                .foregroundStyle(PaperColor.ink)
                .accessibilityAddTraits(.isHeader)
            StatusText(box.isClosed ? closedLine : "Open", tone: box.isClosed ? .done : .progress, style: .subhead)
        }
    }

    private var closedLine: String {
        var line = "Closed"
        if let by = box.wrappedBy, !by.isEmpty { line += " · wrapped by \(by)" }
        if let at = box.closedAt { line += " · \(Format.when(at))" }
        return line
    }

    // MARK: - Figures

    private var figures: some View {
        VStack(alignment: .leading, spacing: PaperSpace.l) {
            HStack(alignment: .firstTextBaseline) {
                if viewModel.hasLoaded {
                    PaperFigure(PaperFormat.int(viewModel.items.count), unit: "in this box", style: .heroS)
                } else {
                    PaperFigure("–", unit: "in this box", style: .heroS)
                }
                Spacer(minLength: PaperSpace.m)
                if tracksPanels && viewModel.jobExpectedCount > 0 {
                    Text("\(PaperFormat.int(viewModel.jobPackedCount)) of \(PaperFormat.int(viewModel.jobExpectedCount)) for the job")
                        .paperType(.subhead, numeric: true)
                        .foregroundStyle(PaperColor.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
            if tracksPanels && !cabinets.isEmpty {
                cabinetBars
            } else if tracksPanels && viewModel.jobExpectedCount > 0 {
                PaperBar(Double(viewModel.jobPackedCount) / Double(viewModel.jobExpectedCount),
                         color: viewModel.jobPackedCount >= viewModel.jobExpectedCount ? PaperColor.success : PaperColor.accent,
                         height: 4)
            }
        }
    }

    /// "12 of 16" per cabinet with a bar, never a percentage.
    private var cabinetBars: some View {
        VStack(spacing: PaperSpace.s) {
            ForEach(cabinets) { c in
                HStack(spacing: PaperSpace.m) {
                    Code(c.cabinetName, color: PaperColor.ink)
                        .frame(minWidth: 44, maxWidth: 96, alignment: .leading)
                    PaperBar(Double(c.packedPartCount) / Double(max(c.totalPartCount, 1)),
                             color: c.isComplete ? PaperColor.success : PaperColor.accent, height: 4)
                    Text("\(c.packedPartCount) of \(c.totalPartCount)")
                        .paperType(.footnote, numeric: true)
                        .foregroundStyle(PaperColor.secondary)
                        .frame(minWidth: 60, alignment: .trailing)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(c.cabinetName), \(c.packedPartCount) of \(c.totalPartCount) packed")
            }
        }
    }

    // MARK: - Sync

    private var syncRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            if viewModel.pendingCount > 0 {
                Button { showPendingSync = true } label: {
                    RowContainer {
                        HStack {
                            StatusText("\(Format.count(viewModel.pendingCount, "scan")) waiting to sync", tone: .progress, style: .subhead)
                            Spacer()
                            PaperIcon(.chevronRight, size: 14, color: PaperColor.faint)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            if viewModel.conflictCount > 0 {
                Button { showConflicts = true } label: {
                    RowContainer {
                        HStack {
                            StatusText("\(Format.count(viewModel.conflictCount, "scan")) need\(viewModel.conflictCount == 1 ? "s" : "") checking", tone: .held, style: .subhead)
                            Spacer()
                            PaperIcon(.chevronRight, size: 14, color: PaperColor.faint)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: PaperSpace.s) {
            if box.isOpen {
                Button {
                    showScanner = true
                } label: {
                    Label { Text("Scan labels") } icon: { PaperIcon(.scan, size: 20, color: PaperColor.onAccent) }
                }
                .buttonStyle(.paperPill(.accent, .floor, fullWidth: true))

                // Manual fallback for damaged / illegible labels. Kept
                // small + secondary so it doesn't compete with the
                // primary scan action.
                if Configuration.useOfflineQueue && box.boxType == .panel {
                    Button("Can't scan a label? Add it by hand") { showManualEntry = true }
                        .buttonStyle(.paperText(PaperColor.secondary, .subhead))
                }
            } else {
                Button {
                    Task { await viewModel.reopenBox(deviceId: appState.deviceId) }
                } label: {
                    Text("Reopen box")
                }
                .buttonStyle(.paperPill(.outline, .floor, fullWidth: true))

                Button("Scan labels") { showScanner = true }
                    .buttonStyle(.paperText(PaperColor.secondary, .subhead))
            }
        }
    }

    // MARK: - Items

    @ViewBuilder private var items: some View {
        PaperSectionHeader("In the box").paperListRow(top: PaperSpace.section)

        if !viewModel.hasLoaded {
            LoadingLine("Loading panels").paperListRow()
        } else if viewModel.items.isEmpty {
            Text(box.isOpen ? "Nothing yet. Scan a panel's label to add it." : "Nothing was scanned into this box.")
                .paperType(.subhead)
                .foregroundStyle(PaperColor.secondary)
                .padding(.vertical, PaperSpace.m)
                .paperListRow()
        } else {
            ForEach(viewModel.items) { item in
                BoxItemRow(item: item)
                    .paperListRow()
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            itemToDelete = item
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }

        if box.isOpen && !viewModel.items.isEmpty {
            Button("Close box \(box.boxNumber)") { showCloseSheet = true }
                .buttonStyle(.paperPill(.ink, .floor, fullWidth: true))
                .paperListRow(top: PaperSpace.section, bottom: 120)
        } else {
            Color.clear.frame(height: 120).paperListRow()
        }
    }

    private var moreMenu: some View {
        Menu {
            Button {
                printBoxLabel()
            } label: {
                Label("Print label", systemImage: "printer")
            }

            if viewModel.box.isClosed && viewModel.box.boxType.fixedDimensions == nil {
                Button {
                    Task { await viewModel.reopenBox(deviceId: appState.deviceId) }
                } label: {
                    Label("Reopen box", systemImage: "lock.open")
                }
            }
            if Configuration.useOfflineQueue && (viewModel.pendingCount > 0 || viewModel.conflictCount > 0) {
                Button { showPendingSync = true } label: {
                    Label("Sync status", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Delete box", systemImage: "trash")
            }
        } label: {
            PaperIcon(.more, size: 22)
                .frame(width: PaperSpace.tap, height: PaperSpace.tap)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More")
    }

    private func performClose() {
        Task {
            isClosing = true
            let count = viewModel.items.count
            let number = viewModel.box.boxNumber
            guard await viewModel.closeBox(
                wrappedBy: appState.operatorName,
                deviceId: appState.deviceId
            ) != nil else {
                isClosing = false
                showCloseSheet = false
                return
            }
            // A quiet confirmation that outlives this screen, then straight
            // back to the boxes. The view model has already played the haptic.
            viewModel.stopPolling()
            viewModel.toastMessage = nil
            showCloseSheet = false
            isClosing = false
            toaster.show("Box \(number) closed · \(Format.count(count, "panel"))")
            dismiss()
        }
    }

    private func printBoxLabel() {
        let labelView = BoxLabelView(
            customerName: viewModel.customerName,
            boxType: viewModel.box.boxType.displayName,
            boxNumber: viewModel.box.boxNumber,
            shippingMethod: viewModel.shippingMethod
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

    private func fixedBoxInfo(_ dims: Box.BoxType.Dimensions) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PaperSectionHeader("This box")
            FactRow(label: "Size", value: dims.displaySize)
            FactRow(label: "Weight", value: dims.displayWeight)
            Text("Fitting kit, runner and rail boxes are a set size and close as they're added.")
                .paperType(.footnote)
                .foregroundStyle(PaperColor.tertiary)
                .padding(.top, PaperSpace.l)
        }
    }
}

struct BoxItemRow: View {
    let item: BoxItem

    var body: some View {
        RowContainer {
            HStack(alignment: .firstTextBaseline, spacing: PaperSpace.m) {
                Code(item.cabinetName, color: PaperColor.ink, size: 14)
                Text("Part \(item.partNumber)").paperType(.body).foregroundStyle(PaperColor.ink)
                Spacer(minLength: PaperSpace.m)
                Text(Format.time(item.scannedAt)).paperType(.footnote, numeric: true).foregroundStyle(PaperColor.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Close box

/// The confirmation for closing a box: what's in it, what the job is still
/// missing, and the one amber action.
struct CloseBoxSheet: View {
    let box: Box
    let count: Int
    let wrappedBy: String
    let missingCount: Int
    let missingPreview: [String]
    let customerName: String
    let isClosing: Bool
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetScreen("Close box \(box.boxNumber)") {
                VStack(alignment: .leading, spacing: 0) {
                    PaperFigure(PaperFormat.int(count),
                                unit: wrappedBy.isEmpty ? (count == 1 ? "panel" : "panels") : "\(count == 1 ? "panel" : "panels"), wrapped by \(wrappedBy)",
                                style: .heroS)
                        .padding(.top, PaperSpace.l)

                    if missingCount > 0 {
                        Notice(
                            text: "\(Format.count(missingCount, "panel")) for \(customerName) \(missingCount == 1 ? "isn't" : "aren't") packed yet. That's fine if another box is coming.",
                            tone: .soon
                        )
                        .section(top: PaperSpace.xxl)

                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(missingPreview, id: \.self) { label in
                                RowContainer(minHeight: 0) {
                                    Text(label).paperType(.subhead).foregroundStyle(PaperColor.body)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            if missingCount > missingPreview.count {
                                Text("and \(missingCount - missingPreview.count) more")
                                    .paperType(.footnote, numeric: true)
                                    .foregroundStyle(PaperColor.tertiary)
                                    .padding(.top, PaperSpace.s)
                            }
                        }
                        .padding(.top, PaperSpace.s)
                    }
                }
            }
            Button {
                onClose()
            } label: {
                if isClosing {
                    ProgressView().tint(PaperColor.onAccent)
                } else {
                    Text(missingCount > 0 ? "Close box anyway" : "Close box \(box.boxNumber)")
                }
            }
            .buttonStyle(.paperPill(.accent, .floor, fullWidth: true))
            .disabled(isClosing)
            .screen()
            .padding(.vertical, PaperSpace.l)
        }
        .paperBackground()
    }
}

// MARK: - Box Label (100mm x 150mm thermal print layout)

private struct BoxLabelView: View {
    let customerName: String
    let boxType: String
    let boxNumber: Int
    let shippingMethod: String

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
                Text(customerName)
                    .font(.system(size: 28, weight: .bold))
                    .multilineTextAlignment(.center)

                Text("\(boxType) #\(boxNumber)")
                    .font(.system(size: 22, weight: .bold))
                    .multilineTextAlignment(.center)
            }

            Spacer()

            Text(shippingMethod)
                .font(.system(size: 20, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(20)
        .foregroundStyle(.black)
    }
}
