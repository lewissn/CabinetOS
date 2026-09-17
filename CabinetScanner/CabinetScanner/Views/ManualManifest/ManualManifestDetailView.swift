import SwiftUI

struct ManualManifestDetailView: View {
    @ObservedObject var viewModel: ManualManifestDetailViewModel
    @State private var boxToDelete: ManualManifestBox?
    @State private var showFinishConfirm = false
    @State private var showReopenConfirm = false

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.boxes.isEmpty {
                ProgressView("Loading boxes...")
            } else {
                List {
                    manifestInfoSection

                    if viewModel.manifest.isFinished {
                        finishedActionsSection
                    } else {
                        actionsSection
                    }

                    if !viewModel.openBoxes.isEmpty {
                        Section("Open Boxes") {
                            ForEach(viewModel.openBoxes) { box in
                                NavigationLink(value: box) {
                                    ManualBoxRow(box: box)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        boxToDelete = box
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }

                    if !viewModel.closedBoxes.isEmpty {
                        Section("Closed Boxes") {
                            ForEach(viewModel.closedBoxes) { box in
                                NavigationLink(value: box) {
                                    ManualBoxRow(box: box)
                                }
                            }
                        }
                    }

                    if viewModel.boxes.isEmpty {
                        ContentUnavailableView(
                            "No Boxes",
                            systemImage: "shippingbox",
                            description: Text("Add a box to start packing")
                        )
                    }
                }
                .refreshable {
                    await viewModel.loadBoxes()
                }
            }
        }
        .navigationTitle(viewModel.manifest.manifestName)
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !viewModel.manifest.isFinished {
                    Button {
                        Task { await viewModel.addBox() }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .alert("Delete Box?", isPresented: .init(
            get: { boxToDelete != nil },
            set: { if !$0 { boxToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { boxToDelete = nil }
            Button("Delete", role: .destructive) {
                if let box = boxToDelete {
                    Task { await viewModel.deleteBox(box) }
                }
                boxToDelete = nil
            }
        } message: {
            Text("This will permanently delete the box and all its contents.")
        }
        .alert("Finish Manifest?", isPresented: $showFinishConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Finish") {
                Task { await viewModel.finishManifest() }
            }
        } message: {
            Text("This will lock the manifest. You can reopen it later if needed.")
        }
        .alert("Reopen Manifest?", isPresented: $showReopenConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Reopen") {
                Task { await viewModel.reopenManifest() }
            }
        } message: {
            Text("This will unlock the manifest for editing.")
        }
        .sheet(isPresented: $viewModel.showSummary) {
            ManualManifestSummaryView(
                manifest: viewModel.manifest,
                boxes: viewModel.boxes
            )
        }
        .overlay(alignment: .bottom) {
            ToastView(message: $viewModel.toastMessage)
        }
        .task {
            await viewModel.loadBoxes()
        }
    }

    private var manifestInfoSection: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    if let courier = viewModel.manifest.courier, !courier.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "truck.box")
                                .foregroundStyle(.blue)
                            Text(courier)
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    if let note = viewModel.manifest.note, !note.isEmpty {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if viewModel.manifest.isFinished {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Finished")
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.green.opacity(0.15))
                    .clipShape(Capsule())
                }
            }
        }
    }

    private var actionsSection: some View {
        Section {
            Button {
                showFinishConfirm = true
            } label: {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Finish Manifest")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(!viewModel.canFinish)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
        }
    }

    private var finishedActionsSection: some View {
        Section {
            Button {
                viewModel.showSummary = true
            } label: {
                HStack {
                    Image(systemName: "doc.text")
                    Text("View Summary")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            .listRowBackground(Color.clear)

            Button {
                showReopenConfirm = true
            } label: {
                HStack {
                    Image(systemName: "lock.open.fill")
                    Text("Reopen Manifest")
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.orange)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
        }
    }
}

// MARK: - Manual Box Row

struct ManualBoxRow: View {
    let box: ManualManifestBox

    var body: some View {
        HStack {
            Image(systemName: "shippingbox")
                .font(.title2)
                .foregroundStyle(box.isClosed ? Color.secondary : Color.blue)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text("Box \(box.boxNumber)")
                    .font(.headline)

                if let dims = box.dimensionsDisplay {
                    HStack(spacing: 8) {
                        Text(dims)
                        if let weight = box.weightDisplay {
                            Text("·")
                            Text(weight)
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                } else {
                    Text(box.isOpen ? "Open" : "Closed")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if box.isClosed {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
