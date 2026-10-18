import CabinetDesign
import SwiftUI

// MARK: - Manual entry — fallback when label barcodes are too damaged to scan
//
// The operator picks the cabinet, then the parts within it, then taps "Add".
// Each manually-added panel goes through the same pipeline as a scanned panel
// — local cache validation, optimistic mirror update, queued for batch sync.
// All the existing dedup/conflict/progress plumbing therefore just works.

@MainActor
final class ManualEntryViewModel: ObservableObject {
    @Published var cabinets: [ScanCacheService.CabinetSummary] = []
    @Published var isLoading = false
    @Published var addedThisSession: Int = 0
    @Published var infoMessage: String?

    let boxId: String
    let manifestId: String
    let consignmentId: String
    let projectName: String

    private let appState: AppState
    private let cache: ScanCacheService
    private let queue: ScanQueueService

    init(
        boxId: String,
        manifestId: String,
        consignmentId: String,
        projectName: String,
        appState: AppState,
        cache: ScanCacheService = ScanCacheService.shared,
        queue: ScanQueueService = ScanQueueService.shared
    ) {
        self.boxId = boxId
        self.manifestId = manifestId
        self.consignmentId = consignmentId
        self.projectName = projectName
        self.appState = appState
        self.cache = cache
        self.queue = queue
    }

    func loadCabinets() async {
        isLoading = true
        defer { isLoading = false }
        // Make sure the cache is warm — usually already is from BoxDetailVM,
        // but if the user opened this sheet very fast (or after relaunch),
        // it's free to retry.
        await cache.loadRegistry(manifestId: manifestId, projectName: projectName)
        await cache.loadPackedPanels(consignmentId: consignmentId)
        cabinets = await cache.cabinets(
            manifestId: manifestId,
            projectName: projectName,
            consignmentId: consignmentId
        )
    }

    func parts(forCabinet cabinetName: String) async -> [ScanCacheService.CabinetPartEntry] {
        await cache.parts(
            manifestId: manifestId,
            projectName: projectName,
            cabinetName: cabinetName,
            consignmentId: consignmentId
        )
    }

    /// Validate + record + enqueue every selected part. Returns the number of
    /// parts that were successfully accepted (skipping anything the cache
    /// flags as already-packed or off-manifest).
    @discardableResult
    func addParts(_ entries: [ScanCacheService.CabinetPartEntry]) async -> Int {
        var added = 0
        for entry in entries {
            let triplet = ScanTriplet(
                projectName: projectName,
                cabinetName: entry.cabinetName,
                partNumber: entry.partNumber
            )
            let result = await cache.validate(
                boxId: boxId,
                manifestId: manifestId,
                consignmentId: consignmentId,
                triplet: triplet
            )
            switch result {
            case .ok:
                let pending = PendingScan(
                    boxId: boxId,
                    manifestId: manifestId,
                    consignmentId: consignmentId,
                    projectName: projectName,
                    cabinetName: entry.cabinetName,
                    partNumber: entry.partNumber,
                    scannedAt: .now,
                    deviceId: appState.deviceId,
                    stationId: appState.stationId,
                    operatorName: appState.operatorName.isEmpty ? nil : appState.operatorName
                )
                await cache.recordLocalScan(pending)
                await queue.enqueue(pending)
                added += 1
            case .alreadyPacked, .notInRegistry, .registryNotCached:
                // Skip silently — UI already disables these rows; this is a
                // safety net in case state changed mid-selection.
                continue
            }
        }
        addedThisSession += added
        if added > 0 {
            HapticService.success()
            infoMessage = "Added \(added) part\(added == 1 ? "" : "s") to box"
            // Refresh the cabinet list so packed counts reflect the new state.
            await loadCabinets()
        } else {
            HapticService.warning()
            infoMessage = "Nothing was added — items may already be packed elsewhere."
        }
        return added
    }
}

// MARK: - Cabinet picker (root of the manual-entry sheet)

struct ManualEntryView: View {
    @StateObject private var viewModel: ManualEntryViewModel
    @Environment(\.dismiss) private var dismiss

    init(
        boxId: String,
        manifestId: String,
        consignmentId: String,
        projectName: String,
        appState: AppState
    ) {
        _viewModel = StateObject(wrappedValue: ManualEntryViewModel(
            boxId: boxId,
            manifestId: manifestId,
            consignmentId: consignmentId,
            projectName: projectName,
            appState: appState
        ))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PaperTopBar(.close, title: "Add by hand", onLeading: { dismiss() }) {
                    if viewModel.addedThisSession > 0 {
                        StatusText("\(viewModel.addedThisSession) added", tone: .done)
                    }
                }
                .screen()
                .padding(.top, PaperSpace.s)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("For a label that won't scan. Parts you pick go through the same checks as scanned ones.")
                            .paperType(.subhead)
                            .foregroundStyle(PaperColor.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, PaperSpace.s)

                        if viewModel.isLoading && viewModel.cabinets.isEmpty {
                            LoadingLine("Loading cabinets").section(top: PaperSpace.xxl)
                        } else if viewModel.cabinets.isEmpty {
                            PaperEmptyState("No parts list on this device",
                                            message: "Open this box once while online so the parts list can be downloaded.",
                                            actionTitle: "Try again") {
                                Task { await viewModel.loadCabinets() }
                            }
                            .section(top: PaperSpace.xxl)
                        } else {
                            cabinetList.section(top: PaperSpace.xxl)
                        }
                    }
                    .screen()
                    .padding(.bottom, PaperSpace.section)
                }
                .refreshable { await viewModel.loadCabinets() }
            }
            .paperBackground()
            .toolbar(.hidden, for: .navigationBar)
            .task { await viewModel.loadCabinets() }
            .overlay(alignment: .bottom) {
                ToastView(message: $viewModel.infoMessage, glyph: viewModel.infoMessage?.hasPrefix("Nothing") == true ? nil : .check)
            }
        }
    }

    private var cabinetList: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaperSectionHeader("Cabinets") {
                Text(viewModel.projectName).paperType(.footnote).foregroundStyle(PaperColor.tertiary).lineLimit(1)
            }
            ForEach(viewModel.cabinets) { summary in
                NavigationLink {
                    CabinetPartsView(cabinet: summary, viewModel: viewModel)
                } label: {
                    cabinetRow(summary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func cabinetRow(_ s: ScanCacheService.CabinetSummary) -> some View {
        RowContainer(minHeight: 56) {
            HStack(spacing: PaperSpace.m) {
                Code(s.cabinetName, color: PaperColor.ink, size: 15)
                Spacer(minLength: PaperSpace.m)
                VStack(alignment: .trailing, spacing: 3) {
                    if s.isComplete {
                        StatusText("All packed", tone: .done)
                    } else {
                        StatusText("\(s.unpackedCount) to pack", tone: s.packedPartCount > 0 ? .progress : .neutral)
                    }
                    Text("\(s.packedPartCount) of \(s.totalPartCount) packed")
                        .paperType(.caption, numeric: true)
                        .foregroundStyle(PaperColor.tertiary)
                }
                PaperIcon(.chevronRight, size: 14, color: PaperColor.faint)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Cabinet parts (multi-select)

private struct CabinetPartsView: View {
    let cabinet: ScanCacheService.CabinetSummary
    @ObservedObject var viewModel: ManualEntryViewModel

    @State private var parts: [ScanCacheService.CabinetPartEntry] = []
    @State private var selected: Set<String> = []
    @State private var isAdding = false

    var body: some View {
        PushedScreen(back: "Cabinets", title: cabinet.cabinetName) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Tap the parts to add. Parts already packed can't be picked.")
                    .paperType(.subhead)
                    .foregroundStyle(PaperColor.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, PaperSpace.s)
                VStack(spacing: 0) {
                    ForEach(parts) { part in
                        partRow(part)
                    }
                }
                .padding(.top, PaperSpace.l)
            }
            .screen()
        }
        .safeAreaInset(edge: .bottom) {
            if !selected.isEmpty {
                addButton
            }
        }
        .task { await reload() }
    }

    private func partRow(_ part: ScanCacheService.CabinetPartEntry) -> some View {
        let isInThisBox = part.packedInBoxId == viewModel.boxId
        let isInOtherBox = part.isPacked && !isInThisBox
        let isSelectable = !part.isPacked
        let isChecked = selected.contains(part.panelUid)

        return Button {
            guard isSelectable else { return }
            if isChecked {
                selected.remove(part.panelUid)
            } else {
                selected.insert(part.panelUid)
            }
        } label: {
            RowContainer(minHeight: 56) {
                HStack(spacing: PaperSpace.m) {
                    PaperCheck(part.isPacked ? .mutedDone : (isChecked ? .done : .open), size: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Part \(part.partNumber)")
                            .paperType(.body)
                            .foregroundStyle(isSelectable ? PaperColor.ink : PaperColor.secondary)
                        Text(part.dimensionsLabel)
                            .paperType(.footnote, numeric: true)
                            .foregroundStyle(PaperColor.tertiary)
                    }
                    Spacer(minLength: PaperSpace.m)
                    if isInThisBox {
                        StatusText("In this box", tone: .done, style: .caption)
                    } else if isInOtherBox {
                        StatusText("In another box", tone: .neutral, style: .caption)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!isSelectable)
        .accessibilityAddTraits(isChecked ? .isSelected : [])
    }

    private var addButton: some View {
        Button {
            Task {
                isAdding = true
                let toAdd = parts.filter { selected.contains($0.panelUid) }
                _ = await viewModel.addParts(toAdd)
                selected.removeAll()
                await reload()
                isAdding = false
            }
        } label: {
            if isAdding {
                ProgressView().tint(PaperColor.onAccent)
            } else {
                Text("Add \(Format.count(selected.count, "part")) to the box")
            }
        }
        .buttonStyle(.paperPill(.accent, .floor, fullWidth: true))
        .disabled(isAdding)
        .screen()
        .padding(.vertical, PaperSpace.m)
        .background(PaperColor.paper.ignoresSafeArea(edges: .bottom))
    }

    private func reload() async {
        parts = await viewModel.parts(forCabinet: cabinet.cabinetName)
        // Drop any selections that are no longer valid (now packed elsewhere).
        let validUnpackedUids = Set(parts.filter { !$0.isPacked }.map(\.panelUid))
        selected = selected.intersection(validUnpackedUids)
    }
}
