import SwiftUI

struct BoxListView: View {
    @StateObject private var viewModel: BoxListViewModel
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var showAddMenu = false
    @State private var boxToDelete: Box?

    init(consignment: Consignment, manifestId: String, manifestName: String) {
        _viewModel = StateObject(wrappedValue: BoxListViewModel(
            consignment: consignment,
            manifestId: manifestId,
            manifestName: manifestName
        ))
    }

    var body: some View {
        Group {
            if !viewModel.hasLoaded && viewModel.boxes.isEmpty {
                ProgressView("Loading boxes...")
            } else {
                List {
                    Section {
                        Button {
                            Task { await viewModel.finishConsignment() }
                        } label: {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Finish Consignment")
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.isFinishing)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                    }

                    if !viewModel.openBoxes.isEmpty {
                        Section("Open Boxes") {
                            ForEach(viewModel.openBoxes) { box in
                                NavigationLink(value: box) {
                                    BoxRow(box: box)
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
                                    BoxRow(box: box)
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
        .navigationTitle(viewModel.consignment.displayTitle)
        .navigationDestination(for: Box.self) { box in
            BoxDetailView(
                box: box,
                manifestId: viewModel.manifestId,
                consignmentId: viewModel.consignment.id,
                customerName: viewModel.consignment.customerName,
                manifestName: viewModel.manifestName
            )
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        Task { await viewModel.createBox(type: .panel, wrappedBy: appState.operatorName, deviceId: appState.deviceId) }
                    } label: {
                        Label("Panel Box", systemImage: "shippingbox")
                    }
                    Button {
                        Task { await viewModel.createBox(type: .fittingKit, wrappedBy: appState.operatorName, deviceId: appState.deviceId) }
                    } label: {
                        Label("Fitting Kit Box", systemImage: "wrench.and.screwdriver")
                    }
                    Button {
                        Task { await viewModel.createBox(type: .drawerRunner, wrappedBy: appState.operatorName, deviceId: appState.deviceId) }
                    } label: {
                        Label("Drawer Runner Box", systemImage: "line.3.horizontal")
                    }
                    Button {
                        Task { await viewModel.createBox(type: .hangingRail, wrappedBy: appState.operatorName, deviceId: appState.deviceId) }
                    } label: {
                        Label("Hanging Rail Box", systemImage: "line.diagonal")
                    }
                } label: {
                    Image(systemName: "plus")
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
        .sheet(isPresented: $viewModel.showFinishSheet) {
            MissingItemsSheet(
                missingItems: viewModel.missingItems,
                onDismiss: { viewModel.showFinishSheet = false }
            )
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
}

struct BoxRow: View {
    let box: Box

    var body: some View {
        HStack {
            Image(systemName: box.boxType.iconName)
                .font(.title2)
                .foregroundStyle(box.isClosed ? Color.secondary : Color.blue)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(box.boxType.displayName) #\(box.boxNumber)")
                    .font(.headline)

                if let dims = box.boxType.fixedDimensions {
                    Text("\(dims.displaySize) · \(dims.displayWeight)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(box.itemCount) items")
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
