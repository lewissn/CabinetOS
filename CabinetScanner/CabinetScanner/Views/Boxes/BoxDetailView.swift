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
    /// Set once the box has closed, so the screen pops after the sheet has
    /// finished going away rather than in the same instant.
    @State private var popAfterSheet = false
    /// Print the box's label as it closes. Remembered on the device.
    @AppStorage("labels.printOnClose") private var printOnClose = true
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
    private var allPanelsPacked: Bool {
        tracksPanels && box.isOpen && !viewModel.items.isEmpty
            && viewModel.jobExpectedCount > 0 && viewModel.jobPackedCount >= viewModel.jobExpectedCount
    }

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
                    .contextMenu {
                        Button {
                            Task {
                                let outcome = await LabelPrinter.shared.printWithOptions([AnyView(label)], jobName: labelJobName)
                                if let message = outcome.message { toaster.show(message) }
                            }
                        } label: { Label("Print with options…", systemImage: "printer.dotmatrix") }
                        Button {
                            LabelPrinter.share([AnyView(label)], fileName: labelJobName)
                        } label: { Label("Share label…", systemImage: "square.and.arrow.up") }
                    }
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

                    // The last panel just went in: say so, and offer the next
                    // step rather than leaving it to be noticed.
                    if allPanelsPacked {
                        Notice(text: "Every panel for this job is packed. Close this box, then finish the consignment.",
                               tone: .done, glyph: .check, action: "Close box") { showCloseSheet = true }
                            .paperListRow(top: PaperSpace.l)
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
        .sheet(isPresented: $showCloseSheet, onDismiss: {
            if popAfterSheet {
                popAfterSheet = false
                dismiss()
            }
        }) {
            CloseBoxSheet(
                box: box,
                count: viewModel.items.count,
                wrappedBy: appState.operatorName,
                missingCount: tracksPanels ? viewModel.missingPanelUids.count : 0,
                missingPreview: tracksPanels ? Array(viewModel.missingPanelLabels.prefix(5)) : [],
                customerName: viewModel.customerName,
                isClosing: isClosing,
                printOnClose: $printOnClose,
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
        // Tabs stay alive, so leaving Packing doesn't make this disappear:
        // stop polling while the tab is hidden and pick up again on return.
        .onTabActiveChange { active in
            if active {
                viewModel.startPolling()
                Task { await viewModel.loadBoxDetail() }
            } else {
                viewModel.stopPolling()
            }
        }
        .task {
            await viewModel.loadBoxDetail()
        }
        // Per-cabinet progress, from the cached parts list only. Nothing is
        // fetched for it: if the list isn't cached, the bars aren't shown.
        .task(id: "\(viewModel.jobPackedCount)/\(viewModel.jobExpectedCount)") {
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
                if viewModel.hasLoaded && !(viewModel.errorMessage != nil && viewModel.items.isEmpty) {
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
        } else if viewModel.items.isEmpty && viewModel.errorMessage != nil {
            Text("The box's contents didn't load. Pull down to try again.")
                .paperType(.subhead)
                .foregroundStyle(PaperColor.secondary)
                .padding(.vertical, PaperSpace.m)
                .paperListRow()
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
            Button {
                Task {
                    let outcome = await LabelPrinter.shared.printWithOptions([AnyView(label)], jobName: labelJobName)
                    if let message = outcome.message { toaster.show(message) }
                }
            } label: {
                Label("Print with options…", systemImage: "printer.dotmatrix")
            }
            Button {
                LabelPrinter.share([AnyView(label)], fileName: labelJobName)
            } label: {
                Label("Share label…", systemImage: "square.and.arrow.up")
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
            // The first time, choose the printer while the sheet is still up,
            // so the picker isn't fighting the screen closing behind it.
            if printOnClose && !LabelPrinter.shared.hasSavedPrinter {
                await LabelPrinter.shared.choosePrinter()
            }
            isClosing = true
            let count = viewModel.items.count
            let number = viewModel.box.boxNumber
            let closingLabel = label
            let jobName = labelJobName
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
            isClosing = false
            toaster.show("Box \(number) closed · \(Format.count(count, "panel"))")
            popAfterSheet = true
            showCloseSheet = false
            if printOnClose {
                let outcome = await LabelPrinter.shared.print([AnyView(closingLabel)], jobName: jobName)
                if let message = outcome.message { toaster.show("Box \(number) closed · \(message.lowercasedFirst)") }
            }
        }
    }

    // MARK: - Label

    private var label: BoxLabel {
        let name = BoxLabel.splitName(viewModel.customerName)
        let contents: String
        if let dims = box.boxType.fixedDimensions {
            contents = "\(dims.displaySize) · \(dims.displayWeight)"
        } else {
            contents = Format.count(viewModel.items.count, "panel")
        }
        return BoxLabel(customer: name.customer, reference: name.reference, boxKind: box.boxType.label,
                        boxNumber: box.boxNumber, contents: contents, courier: viewModel.shippingMethod)
    }

    private var labelJobName: String { "\(viewModel.customerName) box \(box.boxNumber)" }

    /// One tap: straight to the remembered label printer, 4×6" selected.
    private func printBoxLabel() {
        Task {
            let outcome = await LabelPrinter.shared.print([AnyView(label)], jobName: labelJobName)
            if let message = outcome.message { toaster.show(message) }
        }
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
    @Binding var printOnClose: Bool
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
                printOnClose.toggle()
            } label: {
                HStack(spacing: PaperSpace.m) {
                    PaperCheck(printOnClose ? .done : .open, size: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Print its label").paperType(.body).foregroundStyle(PaperColor.ink)
                        Text(LabelPrinter.shared.savedPrinterName.map { "On \($0), 4×6\"" } ?? "Choose the label printer the first time")
                            .paperType(.footnote).foregroundStyle(PaperColor.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: PaperSpace.tap)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(printOnClose ? .isSelected : [])
            .screen()
            .padding(.top, PaperSpace.s)

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
