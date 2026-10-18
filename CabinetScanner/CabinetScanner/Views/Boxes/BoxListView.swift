import CabinetDesign
import SwiftUI

/// A consignment's boxes: what's in boxes so far, the boxes themselves,
/// chips to add one by type, and Finish consignment as the floor button.
struct BoxListView: View {
    @StateObject private var viewModel: BoxListViewModel
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var boxToDelete: Box?

    init(consignment: Consignment, manifestId: String, manifestName: String) {
        _viewModel = StateObject(wrappedValue: BoxListViewModel(
            consignment: consignment,
            manifestId: manifestId,
            manifestName: manifestName
        ))
    }

    private var consignment: Consignment { viewModel.consignment }

    /// Panels in this consignment's boxes, from the boxes just fetched.
    private var panelsInBoxes: Int {
        viewModel.boxes.filter { $0.boxType == .panel }.reduce(0) { $0 + $1.itemCount }
    }

    var body: some View {
        PushedScreen(back: "Consignments", scrolls: false) {
            List {
                header.paperListRow()

                if !viewModel.hasLoaded && viewModel.boxes.isEmpty {
                    LoadingLine("Loading boxes").paperListRow(top: PaperSpace.xxl)
                } else {
                    summary.paperListRow(top: PaperSpace.xxl)

                    if let error = viewModel.errorMessage {
                        Notice(text: error, tone: .held).paperListRow(top: PaperSpace.xxl)
                    }

                    if !viewModel.openBoxes.isEmpty {
                        PaperSectionHeader("Open boxes").paperListRow(top: PaperSpace.section)
                        ForEach(viewModel.openBoxes) { box in
                            ListLinkRow(value: box) { BoxRow(box: box) }
                                .paperListRow()
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        boxToDelete = box
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }

                    if !viewModel.closedBoxes.isEmpty {
                        PaperSectionHeader("Closed boxes").paperListRow(top: PaperSpace.section)
                        ForEach(viewModel.closedBoxes) { box in
                            ListLinkRow(value: box) { BoxRow(box: box) }
                                .paperListRow()
                        }
                    }

                    if viewModel.boxes.isEmpty && !failedEmpty {
                        PaperEmptyState("No boxes yet", message: "Add a box below to start packing this consignment.")
                            .paperListRow(top: PaperSpace.l)
                    }

                    addChips.paperListRow(top: PaperSpace.xl)

                    Button {
                        Task { await viewModel.finishConsignment() }
                    } label: {
                        if viewModel.isFinishing {
                            ProgressView().tint(PaperColor.onAccent)
                        } else {
                            Text("Finish consignment")
                        }
                    }
                    .buttonStyle(.paperPill(.accent, .floor, fullWidth: true))
                    .disabled(viewModel.isFinishing)
                    .paperListRow(top: PaperSpace.section, bottom: 120)
                }
            }
            .paperList()
            .refreshable {
                await viewModel.loadBoxes()
            }
        }
        .navigationDestination(for: Box.self) { box in
            BoxDetailView(
                box: box,
                manifestId: viewModel.manifestId,
                consignmentId: viewModel.consignment.id,
                customerName: viewModel.consignment.customerName,
                manifestName: viewModel.manifestName
            )
        }
        .alert(
            boxToDelete.map { "Delete \($0.title.lowercased())?" } ?? "Delete box?",
            isPresented: .init(
                get: { boxToDelete != nil },
                set: { if !$0 { boxToDelete = nil } }
            )
        ) {
            Button("Keep box", role: .cancel) { boxToDelete = nil }
            Button("Delete box", role: .destructive) {
                if let box = boxToDelete {
                    Task { await viewModel.deleteBox(box) }
                }
                boxToDelete = nil
            }
        } message: {
            Text("The box and everything scanned into it are deleted. This can't be undone.")
        }
        .sheet(isPresented: $viewModel.showFinishSheet) {
            MissingItemsSheet(
                missingItems: viewModel.missingItems,
                onDismiss: { viewModel.showFinishSheet = false }
            )
            .paperSheet(detents: [.medium, .large])
        }
        .overlay(alignment: .bottom) {
            ToastView(message: $viewModel.toastMessage)
        }
        .task {
            await viewModel.loadBoxes()
        }
        .onChange(of: viewModel.isComplete) { _, complete in
            if complete {
                Task {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    dismiss()
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: PaperSpace.s) {
            HStack(spacing: PaperSpace.s) {
                if let ref = consignment.jobRef {
                    Code(ref, color: PaperColor.ink, size: 14)
                }
                Text(viewModel.manifestName).paperType(.footnote).foregroundStyle(PaperColor.secondary).lineLimit(1)
            }
            Text(consignment.title)
                .paperType(.largeTitle)
                .foregroundStyle(PaperColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
    }

    /// The boxes didn't load: show nothing as zero.
    private var failedEmpty: Bool { viewModel.errorMessage != nil && viewModel.boxes.isEmpty }

    private var summary: some View {
        VStack(alignment: .leading, spacing: PaperSpace.l) {
            let expected = consignment.expectedItemCount
            Headline(
                value: failedEmpty ? "–" : PaperFormat.int(panelsInBoxes),
                unit: expected > 0 ? "of \(PaperFormat.int(expected)) panels in boxes" : "panels in boxes",
                detail: failedEmpty ? nil : "\(Format.count(viewModel.boxes.count, "box", "boxes")) · \(viewModel.openBoxes.count) open"
            )
            if expected > 0 && !failedEmpty {
                PaperBar(Double(panelsInBoxes) / Double(expected),
                         color: panelsInBoxes >= expected ? PaperColor.success : PaperColor.accent, height: 4)
            }
        }
    }

    private var addChips: some View {
        VStack(alignment: .leading, spacing: PaperSpace.xs) {
            PaperLabel("Add a box")
            PaperFlowLayout(spacing: PaperSpace.s) {
                ForEach(Box.BoxType.allCases, id: \.self) { type in
                    Button("+ \(type.chipLabel)") {
                        Task { await viewModel.createBox(type: type, wrappedBy: appState.operatorName, deviceId: appState.deviceId) }
                    }
                    .buttonStyle(.paperChip())
                    .accessibilityLabel("Add a \(type.label.lowercased())")
                }
            }
            Text("Fitting kit, runner and rail boxes close as they're added.")
                .paperType(.caption).foregroundStyle(PaperColor.tertiary)
        }
    }
}

struct BoxRow: View {
    let box: Box

    private var detail: String {
        if let dims = box.boxType.fixedDimensions {
            return "\(dims.displaySize) · \(dims.displayWeight)"
        }
        return Format.count(box.itemCount, "panel")
    }

    var body: some View {
        RowContainer {
            HStack(alignment: .center, spacing: PaperSpace.m) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(box.title).paperType(.body).foregroundStyle(PaperColor.ink)
                    Text(detail).paperType(.footnote, numeric: true).foregroundStyle(PaperColor.secondary).lineLimit(1)
                }
                Spacer(minLength: PaperSpace.m)
                VStack(alignment: .trailing, spacing: 3) {
                    StatusText(box.isClosed ? "Closed" : "Open", tone: box.isClosed ? .done : .progress)
                    if box.isClosed, let by = box.wrappedBy, !by.isEmpty {
                        Text("Wrapped by \(by)").paperType(.caption).foregroundStyle(PaperColor.tertiary).lineLimit(1)
                    }
                }
                PaperIcon(.chevronRight, size: 14, color: PaperColor.faint)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
