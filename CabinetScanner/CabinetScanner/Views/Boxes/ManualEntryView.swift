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
            Group {
                if viewModel.isLoading && viewModel.cabinets.isEmpty {
                    ProgressView("Loading cabinets…")
                } else if viewModel.cabinets.isEmpty {
                    ContentUnavailableView(
                        "No parts list available",
                        systemImage: "tray",
                        description: Text("Open this box once while online so the parts list can be downloaded for offline use.")
                    )
                } else {
                    cabinetList
                }
            }
            .navigationTitle("Add manually")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if viewModel.addedThisSession > 0 {
                        Text("\(viewModel.addedThisSession) added")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                }
            }
            .task { await viewModel.loadCabinets() }
            .refreshable { await viewModel.loadCabinets() }
            .overlay(alignment: .bottom) {
                ToastView(message: $viewModel.infoMessage)
                    .padding(.bottom, 24)
            }
        }
    }

    private var cabinetList: some View {
        List {
            Section {
                ForEach(viewModel.cabinets) { summary in
                    NavigationLink {
                        CabinetPartsView(cabinet: summary, viewModel: viewModel)
                    } label: {
                        cabinetRow(summary)
                    }
                }
            } header: {
                Text("Cabinets for \(viewModel.projectName)")
            } footer: {
                Text("Use this only when a label can't be scanned. Parts you select here go through the same checks as scanned parts.")
            }
        }
    }

    private func cabinetRow(_ s: ScanCacheService.CabinetSummary) -> some View {
        HStack(spacing: 12) {
            Image(systemName: s.isComplete ? "checkmark.circle.fill" : "square.grid.2x2.fill")
                .foregroundStyle(s.isComplete ? .green : .blue)
                .font(.title3)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.cabinetName)
                    .font(.body.weight(.semibold))
                Text("\(s.packedPartCount) / \(s.totalPartCount) packed"
                     + (s.isComplete ? " — complete" : ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if s.unpackedCount > 0 {
                Text("\(s.unpackedCount)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(.blue.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 4)
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
        List {
            Section {
                ForEach(parts) { part in
                    partRow(part)
                }
            } header: {
                Text(cabinet.cabinetName)
            } footer: {
                Text("Tap any unpacked part to select it. Already-packed parts are disabled.")
            }
        }
        .navigationTitle(cabinet.cabinetName)
        .navigationBarTitleDisplayMode(.inline)
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
            HStack(spacing: 12) {
                Image(systemName: checkmarkIcon(isChecked: isChecked, isPacked: part.isPacked))
                    .font(.title3)
                    .foregroundStyle(checkmarkColor(isChecked: isChecked, isPacked: part.isPacked))
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Part \(part.partNumber)")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(isSelectable ? .primary : .secondary)
                    Text(part.dimensionsLabel)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    if isInThisBox {
                        Text("Already in this box")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else if isInOtherBox {
                        Text("Packed in another box")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isSelectable)
    }

    private func checkmarkIcon(isChecked: Bool, isPacked: Bool) -> String {
        if isPacked { return "checkmark.seal.fill" }
        return isChecked ? "checkmark.circle.fill" : "circle"
    }

    private func checkmarkColor(isChecked: Bool, isPacked: Bool) -> Color {
        if isPacked { return .secondary }
        return isChecked ? .blue : .secondary
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
            HStack {
                if isAdding { ProgressView().tint(.white) }
                Text(isAdding
                     ? "Adding…"
                     : "Add \(selected.count) part\(selected.count == 1 ? "" : "s") to box")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(.blue)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding()
        }
        .buttonStyle(.plain)
        .disabled(isAdding)
        .background(.regularMaterial)
    }

    private func reload() async {
        parts = await viewModel.parts(forCabinet: cabinet.cabinetName)
        // Drop any selections that are no longer valid (now packed elsewhere).
        let validUnpackedUids = Set(parts.filter { !$0.isPacked }.map(\.panelUid))
        selected = selected.intersection(validUnpackedUids)
    }
}
