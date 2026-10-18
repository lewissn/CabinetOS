import CabinetDesign
import SwiftUI

/// Shows conflicts that the operator must resolve — typically panels that
/// were optimistically accepted offline but the server later reported as
/// already packed in another box.
struct ScanConflictsView: View {
    let boxId: String

    @State private var conflicts: [PendingScan] = []
    private let cache = ScanCacheService.shared

    var body: some View {
        PushedScreen(back: "Box", onRefresh: { await reload() }) {
            VStack(alignment: .leading, spacing: 0) {
                ScreenTitle("Scans to check")

                if conflicts.isEmpty {
                    PaperEmptyState("Nothing to check", message: "Every scan for this box was accepted by the server.")
                        .padding(.top, PaperSpace.l)
                } else {
                    Text("These panels were packed in a different box, removed from the manifest, or scanned into the wrong consignment. Mark each one resolved once you've checked it.")
                        .paperType(.subhead)
                        .foregroundStyle(PaperColor.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, PaperSpace.s)

                    VStack(alignment: .leading, spacing: 0) {
                        PaperSectionHeader("Needs your attention") {
                            Text("\(conflicts.count)").paperType(.footnote, numeric: true).foregroundStyle(PaperColor.tertiary)
                        }
                        ForEach(conflicts, id: \.localId) { row(for: $0) }
                    }
                    .section(top: PaperSpace.xxl)
                }
            }
            .screen()
        }
        .task { await reload() }
    }

    private func row(for s: PendingScan) -> some View {
        VStack(alignment: .leading, spacing: PaperSpace.xs) {
            HStack(alignment: .firstTextBaseline, spacing: PaperSpace.m) {
                Circle().fill(Tone.held.color).frame(width: 7, height: 7)
                Code(s.cabinetName, color: PaperColor.ink, size: 14)
                Text("Part \(s.partNumber)").paperType(.body).foregroundStyle(PaperColor.ink)
            }
            Text(s.projectName).paperType(.footnote).foregroundStyle(PaperColor.secondary)
            if let msg = s.errorMessage {
                Text(msg).paperType(.footnote).foregroundStyle(Tone.held.textColor)
            }
            if let otherBox = s.alreadyPackedInBoxId {
                Text("Already packed in box \(otherBox.prefix(8))…")
                    .paperType(.footnote)
                    .foregroundStyle(PaperColor.secondary)
            }
            Button("Mark resolved") {
                Task {
                    if let uuid = UUID(uuidString: s.localId) {
                        await cache.resolveConflict(localId: uuid)
                    }
                    await reload()
                }
            }
            .buttonStyle(.paperPill(.outline, .compact))
            .padding(.top, PaperSpace.xs)
        }
        .padding(.vertical, PaperSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { PaperHairline(color: PaperColor.hairlineSoft) }
    }

    private func reload() async {
        conflicts = await cache.pendingScans(forBox: boxId, statuses: [.conflict, .rejected])
    }
}
