import CabinetDesign
import SwiftUI

/// List of pending / syncing / rejected scans for a single box.
/// Includes a "Re-sync parts list" action to force-refresh the cached registry.
struct PendingSyncView: View {
    let boxId: String
    let manifestId: String
    let projectName: String

    @State private var pending: [PendingScan] = []
    @State private var syncing: [PendingScan] = []
    @State private var rejected: [PendingScan] = []

    private let cache = ScanCacheService.shared
    private let queue = ScanQueueService.shared

    var body: some View {
        PushedScreen(back: "Box", scrolls: false) {
            Menu {
                Button {
                    Task { await queue.flush() }
                } label: {
                    Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
                }
                Button {
                    Task {
                        await cache.loadRegistry(manifestId: manifestId, projectName: projectName, force: true)
                    }
                } label: {
                    Label("Re-sync parts list", systemImage: "arrow.down.circle")
                }
            } label: {
                PaperIcon(.more, size: 22)
                    .frame(width: PaperSpace.tap, height: PaperSpace.tap)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Sync options")
        } content: {
            List {
                ScreenTitle("Sync status").paperListRow()

                if pending.isEmpty && syncing.isEmpty && rejected.isEmpty {
                    PaperEmptyState("All caught up", message: "No scans are waiting to sync.")
                        .paperListRow(top: PaperSpace.l)
                }
                if !pending.isEmpty {
                    PaperSectionHeader("Waiting to sync") { count(pending) }.paperListRow(top: PaperSpace.xxl)
                    ForEach(pending, id: \.localId) { row(for: $0).paperListRow() }
                }
                if !syncing.isEmpty {
                    PaperSectionHeader("Syncing") { count(syncing) }.paperListRow(top: PaperSpace.xxl)
                    ForEach(syncing, id: \.localId) { row(for: $0).paperListRow() }
                }
                if !rejected.isEmpty {
                    PaperSectionHeader("Rejected") { count(rejected) }.paperListRow(top: PaperSpace.xxl)
                    ForEach(rejected, id: \.localId) { row(for: $0).paperListRow() }
                        .onDelete(perform: discardRejected)
                    Text("Swipe left on a rejected scan to discard it.")
                        .paperType(.footnote).foregroundStyle(PaperColor.tertiary)
                        .padding(.top, PaperSpace.m)
                        .paperListRow()
                }
            }
            .paperList()
            .refreshable { await reload() }
        }
        .task { await reload() }
    }

    private func count(_ rows: [PendingScan]) -> some View {
        Text("\(rows.count)").paperType(.footnote, numeric: true).foregroundStyle(PaperColor.tertiary)
    }

    private func row(for s: PendingScan) -> some View {
        RowContainer {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: PaperSpace.m) {
                    Code(s.cabinetName, color: PaperColor.ink, size: 14)
                    Text("Part \(s.partNumber)").paperType(.body).foregroundStyle(PaperColor.ink)
                    Spacer(minLength: PaperSpace.m)
                    StatusText(label(for: s.status), tone: tone(for: s.status))
                }
                Text("\(s.projectName) · \(Format.time(s.scannedAt))")
                    .paperType(.footnote, numeric: true)
                    .foregroundStyle(PaperColor.secondary)
                if let msg = s.errorMessage {
                    Text(msg).paperType(.footnote).foregroundStyle(Tone.held.textColor)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func tone(for status: PendingScanStatus) -> Tone {
        switch status {
        case .pending, .syncing: .progress
        case .synced: .done
        case .conflict, .rejected: .held
        }
    }

    private func label(for status: PendingScanStatus) -> String {
        switch status {
        case .pending: return "Waiting"
        case .syncing: return "Syncing"
        case .synced: return "Synced"
        case .conflict: return "Conflict"
        case .rejected: return "Rejected"
        }
    }

    private func reload() async {
        pending = await cache.pendingScans(forBox: boxId, statuses: [.pending])
        syncing = await cache.pendingScans(forBox: boxId, statuses: [.syncing])
        rejected = await cache.pendingScans(forBox: boxId, statuses: [.rejected])
    }

    private func discardRejected(at offsets: IndexSet) {
        let toDiscard = offsets.map { rejected[$0] }
        Task {
            for s in toDiscard {
                if let uuid = UUID(uuidString: s.localId) {
                    await cache.resolveConflict(localId: uuid)
                }
            }
            await reload()
        }
    }
}
