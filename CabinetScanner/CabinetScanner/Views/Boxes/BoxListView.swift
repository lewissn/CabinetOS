import SwiftUI

struct BoxListView: View {
    @ObservedObject var viewModel: BoxListViewModel
    @State private var showAddMenu = false
    @State private var boxToDelete: Box?

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.boxes.isEmpty {
                ProgressView("Loading boxes...")
            } else {
                List {
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
                viewModel: BoxDetailViewModel(
                    box: box,
                    manifestId: viewModel.manifestId,
                    consignmentId: viewModel.consignment.id
                )
            )
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        Task { await viewModel.createBox(type: .panel) }
                    } label: {
                        Label("Panel Box", systemImage: "shippingbox")
                    }
                    Button {
                        Task { await viewModel.createBox(type: .fittingKit) }
                    } label: {
                        Label("Fitting Kit Box", systemImage: "wrench.and.screwdriver")
                    }
                    Button {
                        Task { await viewModel.createBox(type: .drawerRunner) }
                    } label: {
                        Label("Drawer Runner Box", systemImage: "line.3.horizontal")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }

            ToolbarItem(placement: .bottomBar) {
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
