import SwiftUI

/// Shows conflicts that the operator must resolve — typically panels that
/// were optimistically accepted offline but the server later reported as
/// already packed in another box.
struct ScanConflictsView: View {
    let boxId: String

    @State private var conflicts: [PendingScan] = []
    private let cache = ScanCacheService.shared

    var body: some View {
        List {
            if conflicts.isEmpty {
                ContentUnavailableView(
                    "No conflicts",
                    systemImage: "checkmark.shield",
                    description: Text("All scans for this box are accepted by the server.")
                )
            } else {
                Section {
                    ForEach(conflicts, id: \.localId) { row(for: $0) }
                } header: {
                    Text("Needs your attention")
                } footer: {
                    Text("These panels were either packed in a different box, removed from the manifest, or scanned into the wrong consignment. Mark each as resolved once you've checked it.")
                }
            }
        }
        .navigationTitle("Scan conflicts")
        .task { await reload() }
        .refreshable { await reload() }
    }

    private func row(for s: PendingScan) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(s.cabinetName) — Part \(s.partNumber)")
                .font(.body.weight(.semibold))
            Text(s.projectName).font(.caption).foregroundStyle(.secondary)
            if let msg = s.errorMessage {
                Text(msg).font(.caption).foregroundStyle(.red)
            }
            if let otherBox = s.alreadyPackedInBoxId {
                Text("Already packed in box \(otherBox.prefix(8))…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Mark resolved") {
                    Task {
                        if let uuid = UUID(uuidString: s.localId) {
                            await cache.resolveConflict(localId: uuid)
                        }
                        await reload()
                    }
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 4)
    }

    private func reload() async {
        conflicts = await cache.pendingScans(forBox: boxId, statuses: [.conflict, .rejected])
    }
}
