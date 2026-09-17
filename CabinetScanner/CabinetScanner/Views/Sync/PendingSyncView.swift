import SwiftUI

/// List of pending / syncing / synced / rejected scans for a single box.
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
        List {
            if !pending.isEmpty {
                Section("Pending sync (\(pending.count))") {
                    ForEach(pending, id: \.localId) { row(for: $0) }
                }
            }
            if !syncing.isEmpty {
                Section("Syncing (\(syncing.count))") {
                    ForEach(syncing, id: \.localId) { row(for: $0) }
                }
            }
            if !rejected.isEmpty {
                Section("Rejected (\(rejected.count))") {
                    ForEach(rejected, id: \.localId) { row(for: $0) }
                        .onDelete(perform: discardRejected)
                }
            }
            if pending.isEmpty && syncing.isEmpty && rejected.isEmpty {
                ContentUnavailableView(
                    "All caught up",
                    systemImage: "checkmark.circle",
                    description: Text("No scans waiting to sync.")
                )
            }
        }
        .navigationTitle("Sync status")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
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
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    private func row(for s: PendingScan) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(s.cabinetName) — Part \(s.partNumber)")
                .font(.body.weight(.semibold))
            Text(s.projectName).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Image(systemName: icon(for: s.status))
                    .foregroundStyle(color(for: s.status))
                Text(label(for: s.status))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(s.scannedAt, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                if let msg = s.errorMessage {
                    Text(msg).font(.caption2).foregroundStyle(.red)
                }
            }
        }
    }

    private func icon(for status: PendingScanStatus) -> String {
        switch status {
        case .pending: return "clock"
        case .syncing: return "arrow.triangle.2.circlepath"
        case .synced: return "checkmark.circle.fill"
        case .conflict: return "exclamationmark.triangle.fill"
        case .rejected: return "xmark.octagon.fill"
        }
    }

    private func color(for status: PendingScanStatus) -> Color {
        switch status {
        case .pending: return .blue
        case .syncing: return .blue
        case .synced: return .green
        case .conflict: return .red
        case .rejected: return .red
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
