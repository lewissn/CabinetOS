import CabinetDesign
import SwiftUI

/// A courier manifest: its boxes, Add box, and Finish manifest once every box
/// is closed. Reads and writes go straight to Supabase, as before.
struct ManualManifestDetailView: View {
    @ObservedObject var viewModel: ManualManifestDetailViewModel
    @State private var boxToDelete: ManualManifestBox?
    @State private var showFinishConfirm = false
    @State private var showReopenConfirm = false

    private var manifest: ManualManifest { viewModel.manifest }

    var body: some View {
        PushedScreen(back: "Packing", scrolls: false) {
            if !manifest.isFinished {
                Button("Add box") {
                    Task { await viewModel.addBox() }
                }
                .buttonStyle(.paperText(PaperColor.ink, .subhead, weight: .semibold))
            }
        } content: {
            List {
                header.paperListRow()

                if viewModel.isLoading && viewModel.boxes.isEmpty {
                    LoadingLine("Loading boxes").paperListRow(top: PaperSpace.xxl)
                } else {
                    Headline(
                        value: PaperFormat.int(viewModel.boxes.count),
                        unit: viewModel.boxes.count == 1 ? "box" : "boxes",
                        detail: viewModel.boxes.isEmpty ? nil : "\(viewModel.closedBoxes.count) closed · \(viewModel.openBoxes.count) open",
                        style: .heroS
                    )
                    .paperListRow(top: PaperSpace.xxl)

                    if let error = viewModel.errorMessage {
                        Notice(text: error, tone: .held).paperListRow(top: PaperSpace.l)
                    }

                    if !viewModel.openBoxes.isEmpty {
                        PaperSectionHeader("Open boxes").paperListRow(top: PaperSpace.section)
                        ForEach(viewModel.openBoxes) { box in
                            ListLinkRow(value: box) { ManualBoxRow(box: box) }
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
                            ListLinkRow(value: box) { ManualBoxRow(box: box) }
                                .paperListRow()
                        }
                    }

                    if viewModel.boxes.isEmpty {
                        PaperEmptyState("No boxes yet", message: "Add a box to start packing this consignment.",
                                        actionTitle: manifest.isFinished ? nil : "Add box") {
                            Task { await viewModel.addBox() }
                        }
                        .paperListRow(top: PaperSpace.l)
                    }

                    actions.paperListRow(top: PaperSpace.section, bottom: 120)
                }
            }
            .paperList()
            .refreshable {
                await viewModel.loadBoxes()
            }
        }
        .navigationDestination(for: ManualManifestBox.self) { box in
            ManualBoxDetailView(
                viewModel: ManualBoxDetailViewModel(
                    box: box,
                    manifestName: viewModel.manifest.manifestName,
                    courierName: viewModel.manifest.courier,
                    isManifestFinished: viewModel.manifest.isFinished
                )
            )
        }
        .alert(boxToDelete.map { "Delete box \($0.boxNumber)?" } ?? "Delete box?", isPresented: .init(
            get: { boxToDelete != nil },
            set: { if !$0 { boxToDelete = nil } }
        )) {
            Button("Keep box", role: .cancel) { boxToDelete = nil }
            Button("Delete box", role: .destructive) {
                if let box = boxToDelete {
                    Task { await viewModel.deleteBox(box) }
                }
                boxToDelete = nil
            }
        } message: {
            Text("The box and everything in it are deleted. This can't be undone.")
        }
        .alert("Finish this manifest?", isPresented: $showFinishConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Finish manifest") {
                Task { await viewModel.finishManifest() }
            }
        } message: {
            Text("This locks the manifest. You can reopen it later if needed.")
        }
        .alert("Reopen this manifest?", isPresented: $showReopenConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Reopen manifest") {
                Task { await viewModel.reopenManifest() }
            }
        } message: {
            Text("This unlocks the manifest for editing.")
        }
        .sheet(isPresented: $viewModel.showSummary) {
            ManualManifestSummaryView(
                manifest: viewModel.manifest,
                boxes: viewModel.boxes
            )
            .paperSheet()
        }
        .overlay(alignment: .bottom) {
            ToastView(message: $viewModel.toastMessage)
        }
        .task {
            await viewModel.loadBoxes()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: PaperSpace.s) {
            HStack(spacing: PaperSpace.s) {
                if let courier = manifest.courier, !courier.isEmpty {
                    Text(courier).paperType(.footnote).foregroundStyle(PaperColor.secondary)
                }
                if let ref = manifest.jobReference, !ref.isEmpty {
                    Code(ref)
                }
            }
            Text(manifest.manifestName)
                .paperType(.largeTitle)
                .foregroundStyle(PaperColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            StatusText(manifest.isFinished ? "Finished" : "Open", tone: manifest.isFinished ? .done : .progress, style: .subhead)
            if let note = manifest.note, !note.isEmpty {
                Text(note)
                    .paperType(.subhead)
                    .foregroundStyle(PaperColor.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, PaperSpace.xs)
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        if manifest.isFinished {
            VStack(spacing: PaperSpace.s) {
                Button("View summary") { viewModel.showSummary = true }
                    .buttonStyle(.paperPill(.ink, .large, fullWidth: true))
                Button("Reopen manifest") { showReopenConfirm = true }
                    .buttonStyle(.paperText(PaperColor.secondary, .subhead, weight: .medium))
            }
        } else {
            VStack(alignment: .leading, spacing: PaperSpace.s) {
                Button("Finish manifest") { showFinishConfirm = true }
                    .buttonStyle(.paperPill(.accent, .floor, fullWidth: true))
                    .disabled(!viewModel.canFinish)
                if !viewModel.canFinish && !viewModel.boxes.isEmpty {
                    Text("Close every box to finish the manifest.")
                        .paperType(.footnote)
                        .foregroundStyle(PaperColor.tertiary)
                }
            }
        }
    }
}

// MARK: - Manual Box Row

struct ManualBoxRow: View {
    let box: ManualManifestBox

    private var detail: String {
        if let dims = box.dimensionsDisplay {
            return [dims, box.weightDisplay].compactMap { $0 }.joined(separator: " · ")
        }
        return box.isOpen ? "No size yet" : "Closed"
    }

    var body: some View {
        RowContainer {
            HStack(alignment: .center, spacing: PaperSpace.m) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Box \(box.boxNumber)").paperType(.body).foregroundStyle(PaperColor.ink)
                    Text(detail).paperType(.footnote, numeric: true).foregroundStyle(PaperColor.secondary).lineLimit(1)
                }
                Spacer(minLength: PaperSpace.m)
                StatusText(box.isClosed ? "Closed" : "Open", tone: box.isClosed ? .done : .progress)
                PaperIcon(.chevronRight, size: 14, color: PaperColor.faint)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
