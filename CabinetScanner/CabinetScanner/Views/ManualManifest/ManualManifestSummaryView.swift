import CabinetDesign
import SwiftUI

/// A finished courier manifest, box by box, ready to copy or share.
struct ManualManifestSummaryView: View {
    let manifest: ManualManifest
    let boxes: [ManualManifestBox]

    @State private var boxItems: [String: [ManualManifestItem]] = [:]
    @State private var isLoading = true
    @State private var copiedMessage: String?
    @State private var expandedBoxes: Set<String> = []

    private let service = ManualManifestService()

    var body: some View {
        SheetScreen("Summary") {
            Menu {
                Button {
                    copyToClipboard()
                } label: {
                    Label("Copy summary", systemImage: "doc.on.doc")
                }
                Button {
                    shareSummary()
                } label: {
                    Label("Share summary", systemImage: "square.and.arrow.up")
                }
            } label: {
                Text("Share")
                    .font(.brand(15, .semibold, relativeTo: .callout))
                    .foregroundStyle(PaperColor.ink)
                    .frame(minHeight: PaperSpace.tap)
            }
            .disabled(isLoading)
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: PaperSpace.s) {
                    if let courier = manifest.courier, !courier.isEmpty {
                        Text(courier).paperType(.footnote).foregroundStyle(PaperColor.secondary)
                    }
                    Text(manifest.manifestName)
                        .paperType(.title)
                        .foregroundStyle(PaperColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    PaperFigure(PaperFormat.int(boxes.count), unit: boxes.count == 1 ? "box" : "boxes", style: .heroS)
                        .padding(.top, PaperSpace.s)
                }
                .padding(.top, PaperSpace.l)

                if isLoading {
                    LoadingLine("Loading the boxes").section(top: PaperSpace.xxl)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        PaperSectionHeader("Boxes")
                        ForEach(sortedBoxes) { box in
                            boxRow(box)
                        }
                    }
                    .section()
                }
            }
        }
        .overlay(alignment: .bottom) {
            ToastView(message: $copiedMessage)
        }
        .task {
            await loadAllItems()
        }
    }

    private var sortedBoxes: [ManualManifestBox] {
        boxes.sorted { $0.boxNumber < $1.boxNumber }
    }

    // MARK: - Box row

    private func boxRow(_ box: ManualManifestBox) -> some View {
        let items = boxItems[box.id] ?? []
        let isExpanded = expandedBoxes.contains(box.id)
        let detail = [box.dimensionsDisplay, box.weightDisplay].compactMap { $0 }.joined(separator: " · ")

        return VStack(alignment: .leading, spacing: PaperSpace.s) {
            HStack(alignment: .firstTextBaseline, spacing: PaperSpace.m) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Box \(box.boxNumber)").paperType(.body).foregroundStyle(PaperColor.ink)
                    Text(detail.isEmpty ? "No size or weight" : detail)
                        .paperType(.footnote, numeric: true)
                        .foregroundStyle(PaperColor.secondary)
                }
                Spacer(minLength: PaperSpace.m)
                StatusText(box.isClosed ? "Closed" : "Open", tone: box.isClosed ? .done : .progress)
            }

            if !items.isEmpty {
                Button {
                    withAnimation(PaperMotion.fade) {
                        if isExpanded { expandedBoxes.remove(box.id) } else { expandedBoxes.insert(box.id) }
                    }
                } label: {
                    HStack(spacing: PaperSpace.xs) {
                        PaperIcon(isExpanded ? .chevronDown : .chevronRight, size: 12, color: PaperColor.secondary)
                        Text(Format.count(items.count, "item")).paperType(.footnote, numeric: true)
                    }
                    .foregroundStyle(PaperColor.secondary)
                }
                .buttonStyle(.plain)
                .frame(minHeight: PaperSpace.tap)

                if isExpanded {
                    VStack(alignment: .leading, spacing: PaperSpace.xs) {
                        ForEach(items) { item in
                            Text(item.isManual
                                 ? "\(item.manualItemName ?? "–") × \(item.qty)"
                                 : "\(item.projectName ?? "–") / \(item.cabinetName ?? "–") / part \(item.partNumber ?? "–") × \(item.qty)")
                                .paperType(.footnote, numeric: true)
                                .foregroundStyle(PaperColor.body)
                        }
                    }
                    .padding(.leading, PaperSpace.l)
                }
            }
        }
        .padding(.vertical, PaperSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { PaperHairline(color: PaperColor.hairlineSoft) }
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
        copiedMessage = "Copied to the clipboard"
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
