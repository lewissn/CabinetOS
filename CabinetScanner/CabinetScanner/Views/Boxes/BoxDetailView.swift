import SwiftUI

struct BoxDetailView: View {
    @StateObject private var viewModel: BoxDetailViewModel
    @EnvironmentObject var appState: AppState
    @ObservedObject private var network = NetworkMonitor.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showScanner = false
    @State private var showDeleteConfirm = false
    @State private var itemToDelete: BoxItem?
    @State private var sliderValue: Double = 0
    @State private var showCloseConfirm = false
    @State private var showPendingSync = false
    @State private var showConflicts = false
    @State private var showCloseWarning = false
    @State private var showManualEntry = false
    @State private var wrapReward: WrapReward?

    init(box: Box, manifestId: String, consignmentId: String, customerName: String, manifestName: String) {
        _viewModel = StateObject(wrappedValue: BoxDetailViewModel(
            box: box,
            manifestId: manifestId,
            consignmentId: consignmentId,
            customerName: customerName,
            manifestName: manifestName
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            if let dims = viewModel.box.boxType.fixedDimensions {
                Spacer()
                fixedBoxInfo(dims)
                Spacer()
            } else if !viewModel.hasLoaded {
                Spacer()
                ProgressView("Loading items...")
                Spacer()
            } else if viewModel.items.isEmpty {
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
                    if Configuration.useOfflineQueue && !network.isOnline {
                        OfflineBannerView()
                    }

                    if Configuration.useOfflineQueue && (viewModel.pendingCount > 0 || viewModel.conflictCount > 0) {
                        HStack(spacing: 12) {
                            if viewModel.pendingCount > 0 {
                                Button { showPendingSync = true } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "arrow.triangle.2.circlepath")
                                        Text("\(viewModel.pendingCount) pending sync")
                                            .font(.footnote.weight(.medium))
                                    }
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(.blue.opacity(0.12))
                                    .foregroundStyle(.blue)
                                    .clipShape(Capsule())
                                }
                            }
                            if viewModel.conflictCount > 0 {
                                Button { showConflicts = true } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                        Text("\(viewModel.conflictCount) conflicts")
                                            .font(.footnote.weight(.medium))
                                    }
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(.red.opacity(0.12))
                                    .foregroundStyle(.red)
                                    .clipShape(Capsule())
                                }
                            }
                        }
                    }

                    if !viewModel.items.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("\(viewModel.items.count) items scanned")
                                .font(.subheadline.weight(.semibold))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.green.opacity(0.1))
                        .clipShape(Capsule())
                    }

                    // Job-level progress: panels packed across all boxes of this
                    // consignment vs. expected from the manifest registry.
                    if Configuration.useOfflineQueue
                        && viewModel.box.boxType == .panel
                        && viewModel.jobExpectedCount > 0 {
                        VStack(spacing: 6) {
                            HStack {
                                Text("Job progress")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(viewModel.jobPackedCount) of \(viewModel.jobExpectedCount)")
                                    .font(.caption.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(.primary)
                            }
                            ProgressView(
                                value: Double(viewModel.jobPackedCount),
                                total: Double(max(viewModel.jobExpectedCount, 1))
                            )
                            .tint(viewModel.jobPackedCount >= viewModel.jobExpectedCount ? .green : .blue)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }

                    if viewModel.box.isClosed {
                        Button {
                            Task { await viewModel.reopenBox(deviceId: appState.deviceId) }
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

                    // Manual fallback for damaged / illegible labels. Kept
                    // small + secondary so it doesn't compete with the
                    // primary scan action.
                    if Configuration.useOfflineQueue && viewModel.box.isOpen && viewModel.box.boxType == .panel {
                        Button {
                            showManualEntry = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "hand.tap")
                                Text("Can't scan? Add manually")
                            }
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.blue)
                            .padding(.vertical, 4)
                        }
                    }

                    if viewModel.box.isOpen && !viewModel.items.isEmpty {
                        SlideToCloseView(
                            onClose: {
                                if Configuration.useOfflineQueue
                                    && viewModel.box.boxType == .panel
                                    && !viewModel.missingPanelUids.isEmpty {
                                    showCloseWarning = true
                                } else {
                                    performClose()
                                }
                            }
                        )
                    }
                }
                .padding()
            }
        }
        .navigationTitle(viewModel.items.isEmpty
            ? "\(viewModel.box.boxType.displayName) #\(viewModel.box.boxNumber)"
            : "\(viewModel.box.boxType.displayName) #\(viewModel.box.boxNumber) (\(viewModel.items.count))"
        )
        .toolbar {
            if Configuration.useOfflineQueue {
                ToolbarItem(placement: .topBarTrailing) {
                    SyncBadgeView(
                        pendingCount: viewModel.pendingCount,
                        conflictCount: viewModel.conflictCount,
                        isOnline: network.isOnline
                    )
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        printBoxLabel()
                    } label: {
                        Label("Print Label", systemImage: "printer")
                    }

                    if viewModel.box.isClosed && viewModel.box.boxType.fixedDimensions == nil {
                        Button {
                            Task { await viewModel.reopenBox(deviceId: appState.deviceId) }
                        } label: {
                            Label("Reopen Box", systemImage: "lock.open.fill")
                        }
                    }
                    if Configuration.useOfflineQueue && (viewModel.pendingCount > 0 || viewModel.conflictCount > 0) {
                        Button { showPendingSync = true } label: {
                            Label("Sync status", systemImage: "arrow.triangle.2.circlepath")
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
        .navigationDestination(isPresented: $showPendingSync) {
            PendingSyncView(
                boxId: viewModel.box.id,
                manifestId: viewModel.manifestId,
                projectName: viewModel.projectName
            )
        }
        .navigationDestination(isPresented: $showConflicts) {
            ScanConflictsView(boxId: viewModel.box.id)
        }
        .confirmationDialog(
            "This job still has missing panels",
            isPresented: $showCloseWarning,
            titleVisibility: .visible
        ) {
            Button("Close box anyway", role: .destructive) {
                performClose()
            }
            Button("Keep open", role: .cancel) {}
        } message: {
            let count = viewModel.missingPanelUids.count
            let preview = viewModel.missingPanelLabels.prefix(5).joined(separator: "\n")
            let extra = count > 5 ? "\n…and \(count - 5) more" : ""
            Text("\(count) panel\(count == 1 ? "" : "s") for \(viewModel.customerName) haven't been packed yet:\n\n\(preview)\(extra)")
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
        .sheet(isPresented: $showManualEntry, onDismiss: {
            Task { await viewModel.loadBoxDetail() }
        }) {
            ManualEntryView(
                boxId: viewModel.box.id,
                manifestId: viewModel.manifestId,
                consignmentId: viewModel.consignmentId,
                projectName: viewModel.projectName,
                appState: appState
            )
        }
        .fullScreenCover(isPresented: $showScanner) {
            ScannerView(
                viewModel: ScannerViewModel(
                    boxId: viewModel.box.id,
                    manifestId: viewModel.manifestId,
                    consignmentId: viewModel.consignmentId,
                    appState: appState,
                    expectedProjectName: viewModel.projectName
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
        .overlay {
            if let wrapReward {
                Color.black.opacity(0.25).ignoresSafeArea()
                WrapRewardView(reward: wrapReward)
            }
        }
        .animation(.easeOut(duration: 0.2), value: wrapReward == nil)
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

    private func performClose() {
        Task {
            guard let reward = await viewModel.closeBox(
                wrappedBy: appState.operatorName,
                deviceId: appState.deviceId
            ) else { return }

            wrapReward = reward
            if reward.isNewPersonalBest || reward.isMilestone {
                HapticService.celebrate()
            }

            // Hold the reward on screen long enough to read before the view
            // pops. Clearing local state first avoids a race where an
            // auto-dismiss task writes into deallocated state on slower devices.
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            viewModel.stopPolling()
            viewModel.toastMessage = nil
            wrapReward = nil
            dismiss()
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

        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first,
              let rootVC = windowScene.windows.first?.rootViewController else { return }

        let activityVC = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        activityVC.popoverPresentationController?.sourceView = rootVC.view
        rootVC.present(activityVC, animated: true)
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
