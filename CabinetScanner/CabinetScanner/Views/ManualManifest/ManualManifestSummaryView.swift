import SwiftUI

struct ManualManifestSummaryView: View {
    let manifest: ManualManifest
    let boxes: [ManualManifestBox]

    @Environment(\.dismiss) private var dismiss
    @State private var boxItems: [String: [ManualManifestItem]] = [:]
    @State private var isLoading = true
    @State private var showCopied = false
    @State private var expandedBoxes: Set<String> = []

    private let service = ManualManifestService()

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading summary...")
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            headerCard
                            ForEach(sortedBoxes) { box in
                                boxCard(box)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            copyToClipboard()
                        } label: {
                            Label("Copy Summary", systemImage: "doc.on.doc")
                        }

                        Button {
                            shareSummary()
                        } label: {
                            Label("Share Summary", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if showCopied {
                    Text("Copied to clipboard")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(.black.opacity(0.8))
                        .clipShape(Capsule())
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 16)
                }
            }
            .task {
                await loadAllItems()
            }
        }
    }

    private var sortedBoxes: [ManualManifestBox] {
        boxes.sorted { $0.boxNumber < $1.boxNumber }
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(manifest.manifestName)
                .font(.title2.weight(.bold))

            if let courier = manifest.courier, !courier.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "truck.box")
                        .foregroundStyle(.blue)
                    Text(courier)
                        .font(.subheadline.weight(.semibold))
                }
            }

            Text("Boxes: \(boxes.count)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Box Card

    private func boxCard(_ box: ManualManifestBox) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Box \(box.boxNumber)")
                    .font(.headline)
                Spacer()
                if box.isClosed {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
            }

            HStack(spacing: 16) {
                if let dims = box.dimensionsDisplay {
                    Label(dims, systemImage: "ruler")
                        .font(.subheadline)
                }
                if let weight = box.weightDisplay {
                    Label(weight, systemImage: "scalemass")
                        .font(.subheadline)
                }
            }
            .foregroundStyle(.secondary)

            let items = boxItems[box.id] ?? []
            if !items.isEmpty {
                let isExpanded = expandedBoxes.contains(box.id)
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if isExpanded {
                            expandedBoxes.remove(box.id)
                        } else {
                            expandedBoxes.insert(box.id)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                        Text("\(items.count) items")
                            .font(.caption)
                    }
                    .foregroundStyle(.blue)
                }

                if isExpanded {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(items) { item in
                            HStack {
                                if item.isManual {
                                    Text("\(item.manualItemName ?? "?") (x\(item.qty))")
                                        .font(.caption)
                                } else {
                                    Text("\(item.projectName ?? "?") / \(item.cabinetName ?? "?") / Part \(item.partNumber ?? "?") (x\(item.qty))")
                                        .font(.caption)
                                }
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.leading, 8)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Data loading

    private func loadAllItems() async {
        var result: [String: [ManualManifestItem]] = [:]
        for box in boxes {
            do {
                result[box.id] = try await service.fetchItems(boxId: box.id)
            } catch {
                result[box.id] = []
            }
        }
        boxItems = result
        isLoading = false
    }

    // MARK: - Summary text generation

    private func buildSummaryText() -> String {
        var lines: [String] = []
        lines.append("Manifest: \(manifest.manifestName)")
        if let courier = manifest.courier, !courier.isEmpty {
            lines.append("Courier: \(courier)")
        }
        lines.append("Boxes: \(boxes.count)")
        lines.append("")

        for box in sortedBoxes {
            let dims = box.dimensionsDisplay ?? "—"
            let weight = box.weightDisplay ?? "—"
            lines.append("\(box.boxNumber). \(dims) — \(weight)")

            let items = boxItems[box.id] ?? []
            for item in items {
                if item.isManual {
                    lines.append("  • \(item.manualItemName ?? "?") (x\(item.qty))")
                } else {
                    lines.append("  • \(item.projectName ?? "?") / \(item.cabinetName ?? "?") / Part \(item.partNumber ?? "?") (x\(item.qty))")
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    private func copyToClipboard() {
        UIPasteboard.general.string = buildSummaryText()
        HapticService.success()
        withAnimation(.easeInOut) { showCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeOut) { showCopied = false }
        }
    }

    private func shareSummary() {
        let text = buildSummaryText()
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first,
              let rootVC = windowScene.windows.first?.rootViewController else { return }

        let activityVC = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        activityVC.popoverPresentationController?.sourceView = rootVC.view
        rootVC.present(activityVC, animated: true)
    }
}
