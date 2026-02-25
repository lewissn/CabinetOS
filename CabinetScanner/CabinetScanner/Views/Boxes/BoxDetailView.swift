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
                                Button(role: .destructive) {
                                    itemToDelete = item
                                } label: {
                                    Label("Delete", systemImage: "trash")
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
                    if viewModel.box.isClosed {
                        Button {
                            Task { await viewModel.reopenBox() }
                        } label: {
                            Label("Reopen Box", systemImage: "lock.open.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(.orange)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }

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

                    if viewModel.box.isOpen && !viewModel.items.isEmpty {
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
                }
                .padding()
            }
        }
        .navigationTitle("\(viewModel.box.boxType.displayName) #\(viewModel.box.boxNumber)")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        printBoxLabel()
                    } label: {
                        Label("Print Label", systemImage: "printer")
                    }

                    if viewModel.box.isClosed && viewModel.box.boxType.fixedDimensions == nil {
                        Button {
                            Task { await viewModel.reopenBox() }
                        } label: {
                            Label("Reopen Box", systemImage: "lock.open.fill")
                        }
                    }
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

    private func printBoxLabel() {
        let labelView = BoxLabelView(
            customerName: viewModel.customerName,
            boxType: viewModel.box.boxType.displayName,
            boxNumber: viewModel.box.boxNumber,
            shippingMethod: viewModel.shippingMethod
        )

        let mmToPoints: CGFloat = 72.0 / 25.4
        let widthPt = 100.0 * mmToPoints
        let heightPt = 150.0 * mmToPoints

        let renderer = ImageRenderer(content:
            labelView
                .frame(width: widthPt, height: heightPt)
                .background(.white)
        )
        renderer.scale = 3.0

        guard let image = renderer.uiImage else { return }

        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.jobName = "Box Label"
        printInfo.outputType = .grayscale

        let controller = UIPrintInteractionController.shared
        controller.printInfo = printInfo
        controller.printingItem = image
        controller.present(animated: true)
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

// MARK: - Box Label (100mm x 150mm thermal print layout)

private struct BoxLabelView: View {
    let customerName: String
    let boxType: String
    let boxNumber: Int
    let shippingMethod: String

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image("CabinetLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 40)
                Spacer()
            }
            .padding(.bottom, 16)

            Spacer()

            VStack(spacing: 12) {
                Text(customerName)
                    .font(.system(size: 28, weight: .bold))
                    .multilineTextAlignment(.center)

                Text("\(boxType) #\(boxNumber)")
                    .font(.system(size: 22, weight: .bold))
                    .multilineTextAlignment(.center)
            }

            Spacer()

            Text(shippingMethod)
                .font(.system(size: 20, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(20)
        .foregroundStyle(.black)
    }
}
