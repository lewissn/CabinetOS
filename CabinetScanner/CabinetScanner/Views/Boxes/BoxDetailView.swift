import SwiftUI

struct BoxDetailView: View {
    @ObservedObject var viewModel: BoxDetailViewModel
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var showScanner = false
    @State private var showDeleteConfirm = false
    @State private var itemToDelete: BoxItem?
    @State private var sliderValue: Double = 0
    @State private var showCloseConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            if let dims = viewModel.box.boxType.fixedDimensions {
                Spacer()
                fixedBoxInfo(dims)
                Spacer()
            } else if viewModel.items.isEmpty && !viewModel.isLoading {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "barcode.viewfinder")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No items scanned yet")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    if viewModel.box.isOpen {
                        Text("Tap 'Scan Label' to start packing")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
            } else {
                List {
                    ForEach(viewModel.items) { item in
                        BoxItemRow(item: item)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if viewModel.box.isOpen {
                                    Button(role: .destructive) {
                                        itemToDelete = item
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                    }
                }
                .refreshable {
                    await viewModel.loadBoxDetail()
                }
            }

            if viewModel.box.boxType.fixedDimensions == nil {
                VStack(spacing: 12) {
                    if viewModel.box.isOpen {
                        Button {
                            showScanner = true
                        } label: {
                            Label("Scan Label", systemImage: "barcode.viewfinder")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(.blue)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }

                        if !viewModel.items.isEmpty {
                            SlideToCloseView(
                                onClose: {
                                    Task {
                                        let closed = await viewModel.closeBox()
                                        if closed {
                                            // Stay on detail, just update state
                                        }
                                    }
                                }
                            )
                        }
                    } else {
                        HStack {
                            Image(systemName: "lock.fill")
                            Text("Box Closed")
                                .font(.headline)
                        }
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.fill.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding()
            }
        }
        .navigationTitle("\(viewModel.box.boxType.displayName) #\(viewModel.box.boxNumber)")
        .toolbar {
            if viewModel.box.isOpen {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete Box", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .alert("Delete Item?", isPresented: .init(
            get: { itemToDelete != nil },
            set: { if !$0 { itemToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { itemToDelete = nil }
            Button("Delete", role: .destructive) {
                if let item = itemToDelete {
                    Task { await viewModel.deleteItem(item) }
                }
                itemToDelete = nil
            }
        } message: {
            if let item = itemToDelete {
                Text("Remove \(item.displayLabel) from this box?")
            }
        }
        .alert("Delete Box?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    let deleted = await viewModel.deleteBox()
                    if deleted { dismiss() }
                }
            }
        } message: {
            Text("This will permanently delete this box and all its contents.")
        }
        .fullScreenCover(isPresented: $showScanner) {
            ScannerView(
                viewModel: ScannerViewModel(
                    boxId: viewModel.box.id,
                    manifestId: viewModel.manifestId,
                    consignmentId: viewModel.consignmentId,
                    appState: appState
                ),
                onDismiss: {
                    showScanner = false
                    Task { await viewModel.loadBoxDetail() }
                }
            )
        }
        .overlay(alignment: .bottom) {
            ToastView(message: $viewModel.toastMessage)
                .padding(.bottom, 120)
        }
        .onAppear {
            viewModel.startPolling()
        }
        .onDisappear {
            viewModel.stopPolling()
        }
        .task {
            await viewModel.loadBoxDetail()
        }
    }

    private func fixedBoxInfo(_ dims: Box.BoxType.Dimensions) -> some View {
        VStack(spacing: 20) {
            Image(systemName: viewModel.box.boxType.iconName)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text(viewModel.box.boxType.displayName)
                .font(.title2.weight(.bold))

            VStack(spacing: 8) {
                Label(dims.displaySize, systemImage: "ruler")
                Label(dims.displayWeight, systemImage: "scalemass")
            }
            .font(.body)
            .foregroundStyle(.secondary)

            HStack {
                Image(systemName: "lock.fill")
                Text("Completed")
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.green)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.green.opacity(0.15))
            .clipShape(Capsule())
        }
    }
}

struct BoxItemRow: View {
    let item: BoxItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.displayLabel)
                .font(.body.weight(.bold))

            Text(item.projectName)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(item.scannedAt, style: .time)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}
