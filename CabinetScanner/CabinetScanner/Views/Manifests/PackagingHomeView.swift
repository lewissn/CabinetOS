import SwiftUI

// MARK: - Packaging Home (tile-based landing page)

struct PackagingHomeView: View {
    @StateObject private var viewModel = PackagingHomeViewModel()
    @StateObject private var apcVM = APCDeadlineViewModel()
    @EnvironmentObject var appState: AppState
    @State private var resumeTarget: ResumeTarget?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                APCDeadlineBannerView(viewModel: apcVM)
                if let resume = viewModel.resume {
                    resumeTile(resume)
                }
                tilesSection
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Packaging")
        .navigationDestination(for: PackagingSection.self) { section in
            switch section {
            case .bjs:
                ManifestListView()
            case .courier:
                ManualManifestListView()
            }
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    appState.isStationConfigured = false
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .refreshable {
            await viewModel.refresh()
            await apcVM.refresh()
        }
        .task {
            await viewModel.refresh()
            await apcVM.refresh()
            apcVM.startCountdown()
        }
        .onDisappear {
            apcVM.stopCountdown()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Packaging")
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text("Choose a manifest type to begin")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 16)
    }

    // MARK: - Resume tile

    @ViewBuilder
    private func resumeTile(_ activity: RecentBoxActivity) -> some View {
        Button {
            resumeTarget = ResumeTarget(activity: activity)
        } label: {
            HStack(spacing: 16) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.green)
                    .frame(width: 52, height: 52)
                    .background(.green.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Resume packing")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("Box \(activity.boxNumber) · \(activity.customerName)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.green.opacity(0.35), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tiles

    private var tilesSection: some View {
        VStack(spacing: 16) {
            NavigationLink(value: PackagingSection.bjs) {
                PackagingTile(
                    icon: "doc.text.fill",
                    iconColor: .blue,
                    title: "BJS Manifests",
                    subtitle: viewModel.bjsSummary,
                    accentColor: .blue,
                    isLoading: viewModel.isLoading
                )
            }
            .buttonStyle(.plain)

            NavigationLink(value: PackagingSection.courier) {
                PackagingTile(
                    icon: "truck.box.fill",
                    iconColor: .orange,
                    title: "Courier Manifests",
                    subtitle: viewModel.courierSummary,
                    accentColor: .orange,
                    isLoading: viewModel.isLoading
                )
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Navigation enum

enum PackagingSection: Hashable {
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

// MARK: - Tile Component (Apple Fitness style)

private struct PackagingTile: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let accentColor: Color
    let isLoading: Bool

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(iconColor)
                .frame(width: 52, height: 52)
                .background(iconColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                if isLoading {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.quaternary)
                        .frame(width: 120, height: 14)
                } else {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
    }
}

// MARK: - ViewModel

@MainActor
final class PackagingHomeViewModel: ObservableObject {
    @Published var bjsCount: Int = 0
    @Published var courierOpenCount: Int = 0
    @Published var courierFinishedCount: Int = 0
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var resume: RecentBoxActivity?

    private let api: APIServiceProtocol = ServiceContainer.shared.api
    private let manualService = ManualManifestService()

    var bjsSummary: String {
        if bjsCount == 0 { return "No active manifests" }
        return "\(bjsCount) active manifest\(bjsCount == 1 ? "" : "s")"
    }

    var courierSummary: String {
        let total = courierOpenCount + courierFinishedCount
        if total == 0 { return "No manifests" }
        var parts: [String] = []
        if courierOpenCount > 0 { parts.append("\(courierOpenCount) open") }
        if courierFinishedCount > 0 { parts.append("\(courierFinishedCount) finished") }
        return parts.joined(separator: " · ")
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil

        // Read the resume target synchronously from UserDefaults — instant.
        // Hide it after 24 hours of inactivity (probably a finished session).
        if let activity = RecentActivityService.current(),
           Date().timeIntervalSince(activity.openedAt) < 24 * 60 * 60 {
            resume = activity
        } else {
            resume = nil
        }

        do {
            async let bjsTask = api.fetchManifests()
            async let manualTask = manualService.fetchManifests()

            let bjs = try await bjsTask
            let manual = try await manualTask

            bjsCount = bjs.filter { $0.status == .active }.count
            courierOpenCount = manual.filter { !$0.isFinished }.count
            courierFinishedCount = manual.filter { $0.isFinished }.count
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
