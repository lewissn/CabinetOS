import CabinetDesign
import SwiftUI

/// A courier manifest: its boxes, Add box, and Finish manifest once every box
/// is closed. Reads and writes go straight to Supabase, as before.
struct ManualManifestDetailView: View {
    @ObservedObject var viewModel: ManualManifestDetailViewModel
    var backLabel = "Packing"
    @State private var boxToDelete: ManualManifestBox?
    @State private var showFinishConfirm = false
    @State private var showReopenConfirm = false
    @State private var showDeleteConfirm = false
    @Environment(\.dismiss) private var dismiss

    private var manifest: ManualManifest { viewModel.manifest }

    var body: some View {
        PushedScreen(back: backLabel, scrolls: false) {
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
                    let failedEmpty = viewModel.errorMessage != nil && viewModel.boxes.isEmpty
                    Headline(
                        value: failedEmpty ? "–" : PaperFormat.int(viewModel.boxes.count),
                        unit: viewModel.boxes.count == 1 ? "box" : "boxes",
                        detail: viewModel.boxes.isEmpty ? nil : "\(viewModel.closedBoxes.count) closed · \(viewModel.openBoxes.count) open",
                        style: .heroS
                    )
                    .paperListRow(top: PaperSpace.xxl)

                    if let error = viewModel.errorMessage {
                        Notice(text: error, tone: .held).paperListRow(top: PaperSpace.l)
                    }

                    if let outcome = viewModel.finishOutcome {
                        FinishStepsOutcome(result: outcome).paperListRow(top: PaperSpace.l)
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

                    if viewModel.boxes.isEmpty && !failedEmpty {
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
            ManualBoxScreen(
                box: box,
                manifestName: viewModel.manifest.manifestName,
                courierName: viewModel.manifest.courier,
                isManifestFinished: viewModel.manifest.isFinished
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
        .alert(manifest.movesAJobOn ? "Finish and complete the job?" : "Finish this manifest?", isPresented: $showFinishConfirm) {
            Button("Cancel", role: .cancel) {}
            Button(manifest.movesAJobOn ? "Finish and complete the job" : "Finish manifest") {
                Task { await viewModel.finishManifest() }
            }
        } message: {
            if manifest.movesAJobOn, manifest.stepsCompletedAt == nil {
                Text("This closes the consignment and completes Pack & Wrap and then Despatch in ShopVOX. Neither can be undone from the app, and completing Despatch drafts the customer's despatch email.")
            } else {
                Text("This locks the manifest. You can reopen it later if needed.")
            }
        }
        .alert("Delete \(manifest.manifestName)?", isPresented: $showDeleteConfirm) {
            Button("Keep consignment", role: .cancel) {}
            Button("Delete consignment", role: .destructive) {
                Task {
                    if await viewModel.deleteManifest() { dismiss() }
                }
            }
        } message: {
            Text(deleteMessage)
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

    /// Says what goes with it, and what deleting can't take back.
    private var deleteMessage: String {
        var parts = [viewModel.boxes.isEmpty
            ? "The consignment is deleted."
            : "The consignment and its \(Format.count(viewModel.boxes.count, "box", "boxes")) are deleted, with everything in them."]
        if manifest.stepsCompletedAt != nil {
            parts.append("The steps it completed in ShopVOX stay completed.")
        }
        parts.append("This can't be undone.")
        return parts.joined(separator: " ")
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            showDeleteConfirm = true
        } label: {
            if viewModel.isDeleting {
                ProgressView().tint(PaperColor.danger)
            } else {
                Text("Delete consignment")
            }
        }
        .buttonStyle(.paperText(PaperColor.danger, .subhead, weight: .medium))
        .disabled(viewModel.isDeleting || viewModel.isFinishing)
        .padding(.top, PaperSpace.l)
    }

    @ViewBuilder
    private var actions: some View {
        VStack(alignment: .leading, spacing: 0) {
            actionButtons
            deleteButton
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        if manifest.isFinished {
            VStack(spacing: PaperSpace.s) {
                Button("View summary") { viewModel.showSummary = true }
                    .buttonStyle(.paperPill(.ink, .large, fullWidth: true))
                Button("Reopen manifest") { showReopenConfirm = true }
                    .buttonStyle(.paperText(PaperColor.secondary, .subhead, weight: .medium))
            }
        } else {
            VStack(alignment: .leading, spacing: PaperSpace.s) {
                Button {
                    showFinishConfirm = true
                } label: {
                    if viewModel.isFinishing {
                        ProgressView().tint(PaperColor.onAccent)
                    } else {
                        Text(manifest.movesAJobOn ? "Finish and complete the job" : "Finish manifest")
                    }
                }
                .buttonStyle(.paperPill(.accent, .floor, fullWidth: true))
                .disabled(!viewModel.canFinish || viewModel.isFinishing)
                if manifest.movesAJobOn {
                    Text("Raised from \(manifest.jobReference ?? "its job"), so finishing it moves the job on in ShopVOX.")
                        .paperType(.footnote)
                        .foregroundStyle(PaperColor.tertiary)
                }
                if !viewModel.canFinish && !viewModel.boxes.isEmpty {
                    Text("Close every box to finish the manifest.")
                        .paperType(.footnote)
                        .foregroundStyle(PaperColor.tertiary)
                }
            }
        }
    }
}

// MARK: - A box's screen, owning its model
//
// The box's view model has to be owned here, as a StateObject. It used to be
// built inline in the destination above and only observed, so whenever this
// screen redrew behind the box (its own box list finishing a refresh, say)
// SwiftUI built a fresh, empty model and the box screen kept that one: the
// items it had loaded vanished and every box read "Nothing was put in this
// box", though the scans were all there.

struct ManualBoxScreen: View {
    @StateObject private var viewModel: ManualBoxDetailViewModel

    init(box: ManualManifestBox, manifestName: String, courierName: String?, isManifestFinished: Bool) {
        _viewModel = StateObject(wrappedValue: ManualBoxDetailViewModel(
            box: box,
            manifestName: manifestName,
            courierName: courierName,
            isManifestFinished: isManifestFinished
        ))
    }

    var body: some View { ManualBoxDetailView(viewModel: viewModel) }
}

// MARK: - What ShopVOX did

/// Shown after a job-linked consignment is finished: each step's result, in
/// the server's words. "Pack & Wrap done, Despatch refused" is the case
/// somebody has to act on.
struct FinishStepsOutcome: View {
    let result: CourierConsignmentFinished

    private var tone: Tone {
        if !result.ok { return .held }
        return result.stepsCompleted == true || result.alreadyCompleted == true ? .done : .soon
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PaperSpace.xs) {
            StatusText(result.message ?? (result.stepsCompleted == true ? "Job moved on in ShopVOX." : "Finished."),
                       tone: tone, style: .subhead, lineLimit: nil)
            ForEach(result.steps ?? []) { step in
                StatusText(step.message, tone: step.ok ? .done : .held, style: .footnote, lineLimit: nil)
            }
        }
        .padding(.horizontal, PaperSpace.l)
        .padding(.vertical, PaperSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone.soft, in: RoundedRectangle(cornerRadius: 12))
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
                FreshSeal(boxId: box.id)
                StatusText(box.isClosed ? "Closed" : "Open", tone: box.isClosed ? .done : .progress)
                PaperIcon(.chevronRight, size: 14, color: PaperColor.faint)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
