import CabinetDesign
import SwiftUI

// MARK: - Packing home
//
// The warehouse's own work first: carry on with the last box, then the
// manifests for the chosen type. BJS and courier manifests sit under one
// segmented control rather than behind two tiles.

struct PackagingHomeView: View {
    @StateObject private var viewModel = PackagingHomeViewModel()
    @StateObject private var apcVM = APCDeadlineViewModel()
    @StateObject private var bjs = ManifestListViewModel()
    @StateObject private var courier = ManualManifestListViewModel()
    @EnvironmentObject var appState: AppState
    @State private var resumeTarget: ResumeTarget?
    @AppStorage("packing.mode") private var mode: PackagingSection = .bjs

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenTitle("Packing") {
                    BarIcon(glyph: .station, label: "Station setup") {
                        appState.isStationConfigured = false
                    }
                }
                stationLine

                if let resume = viewModel.resume {
                    resumeButton(resume)
                        .section(top: PaperSpace.xxl)
                }

                if apcVM.shouldShow {
                    APCDeadlineBannerView(viewModel: apcVM)
                        .section(top: PaperSpace.xxl)
                }

                PaperSegmented([(PackagingSection.bjs, "BJS manifests"), (.courier, "Courier")],
                               selection: $mode, accessibilityLabel: "Manifest type")
                    .section(top: PaperSpace.xxl)

                Group {
                    switch mode {
                    case .bjs: BJSManifestList(viewModel: bjs)
                    case .courier: CourierManifestList(viewModel: courier)
                    }
                }
                .section(top: PaperSpace.xxl)
            }
            .screen()
            .padding(.bottom, 120)
        }
        .paperRootScreen()
        // Through holders that own their view model, so this screen
        // re-rendering (the APC countdown ticks every 30 s) never hands a
        // pushed screen a fresh, empty one.
        .navigationDestination(for: Manifest.self) { manifest in
            ConsignmentListScreen(manifest: manifest)
        }
        .navigationDestination(for: ManualManifest.self) { manifest in
            ManualManifestScreen(manifest: manifest)
        }
        .navigationDestination(item: $resumeTarget) { target in
            BoxDetailView(
                box: target.box,
                manifestId: target.activity.manifestId,
                consignmentId: target.activity.consignmentId,
                customerName: target.activity.customerName,
                manifestName: target.activity.manifestName
            )
        }
        .sheet(isPresented: $courier.showCreateSheet) {
            CreateManualManifestSheet { name, courierName, note in
                Task { await courier.createManifest(name: name, courier: courierName, note: note) }
            }
            .paperSheet(detents: [.large])
        }
        .overlay(alignment: .bottom) {
            ToastView(message: $courier.toastMessage)
        }
        .refreshable {
            await refreshAll()
        }
        .task {
            await refreshAll()
            apcVM.startCountdown()
        }
        .onAppear {
            // Coming back from a box: the resume target may have changed.
            viewModel.refreshResume()
        }
        .onDisappear {
            apcVM.stopCountdown()
        }
        // Every tab is alive from launch: coming back to Packing is when it
        // reloads, and the countdown only runs while it's on screen.
        .onTabActiveChange { active in
            if active {
                apcVM.startCountdown()
                Task { await refreshAll() }
            } else {
                apcVM.stopCountdown()
            }
        }
    }

    private func refreshAll() async {
        viewModel.refreshResume()
        async let a: () = apcVM.refresh()
        async let b: () = bjs.loadManifests()
        async let c: () = courier.loadManifests()
        _ = await (a, b, c)
    }

    private var stationLine: some View {
        Text(appState.operatorName.isEmpty
             ? "\(appState.stationId.prefix(1).uppercased() + appState.stationId.dropFirst()) station"
             : "\(appState.operatorName) · \(appState.stationId) station")
            .paperType(.footnote)
            .foregroundStyle(PaperColor.secondary)
            .padding(.top, PaperSpace.xxs)
    }

    // MARK: - Resume: the screen's one primary action

    private func resumeButton(_ activity: RecentBoxActivity) -> some View {
        Button {
            resumeTarget = ResumeTarget(activity: activity)
        } label: {
            HStack(spacing: PaperSpace.l) {
                PaperIcon(.scan, size: 26, color: PaperColor.onAccent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Resume packing").paperType(.headline).foregroundStyle(PaperColor.onAccent)
                    Text("\(activity.customerName) · \(activity.boxType.label.lowercased()) \(activity.boxNumber)")
                        .paperType(.footnote, numeric: true)
                        .foregroundStyle(PaperColor.onAccent.opacity(0.75))
                        .lineLimit(1)
                }
                Spacer(minLength: PaperSpace.s)
                PaperIcon(.arrowRight, size: 18, color: PaperColor.onAccent)
            }
            .padding(.horizontal, PaperSpace.xxl)
            .frame(minHeight: 72)
            .background(PaperColor.accent, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Resume packing, \(activity.customerName), box \(activity.boxNumber)")
    }
}

// MARK: - Destination holders

private struct ConsignmentListScreen: View {
    @StateObject private var viewModel: ConsignmentListViewModel

    init(manifest: Manifest) {
        _viewModel = StateObject(wrappedValue: ConsignmentListViewModel(manifestId: manifest.id, manifestName: manifest.name))
    }

    var body: some View { ConsignmentListView(viewModel: viewModel) }
}

private struct ManualManifestScreen: View {
    @StateObject private var viewModel: ManualManifestDetailViewModel

    init(manifest: ManualManifest) {
        _viewModel = StateObject(wrappedValue: ManualManifestDetailViewModel(manifest: manifest))
    }

    var body: some View { ManualManifestDetailView(viewModel: viewModel) }
}

// MARK: - Navigation enum

enum PackagingSection: String, Hashable {
    case bjs
    case courier
}

/// Hashable wrapper so the Resume tile can drive a navigationDestination.
/// Re-derives a `Box` from the persisted `RecentBoxActivity` so we can push
/// straight into BoxDetailView without an extra round-trip.
struct ResumeTarget: Hashable, Identifiable {
    let activity: RecentBoxActivity

    var id: String { activity.boxId }

    var box: Box {
        Box(
            id: activity.boxId,
            consignmentId: activity.consignmentId,
            boxNumber: activity.boxNumber,
            boxType: activity.boxType,
            status: .open,
            itemCount: 0,
            createdAt: activity.openedAt,
            closedAt: nil,
            wrappedAt: nil,
            wrappedBy: nil,
            wrappedByDevice: nil,
            wrapReworkCount: 0
        )
    }

    static func == (lhs: ResumeTarget, rhs: ResumeTarget) -> Bool {
        lhs.activity.boxId == rhs.activity.boxId
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(activity.boxId)
    }
}

// MARK: - ViewModel

@MainActor
final class PackagingHomeViewModel: ObservableObject {
    @Published var resume: RecentBoxActivity?

    /// Read the resume target from UserDefaults — instant. Hide it after 24
    /// hours of inactivity (probably a finished session).
    func refreshResume() {
        if let activity = RecentActivityService.current(),
           Date().timeIntervalSince(activity.openedAt) < 24 * 60 * 60 {
            resume = activity
        } else {
            resume = nil
        }
    }
}
