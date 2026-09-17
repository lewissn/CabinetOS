import SwiftUI

// MARK: - Reporting View
//
// Pushed via NavigationLink from DashboardView. Shows packing stats
// for a selectable time period (Today / This Week / This Month).

struct ReportingView: View {
    @StateObject private var vm = ReportingViewModel()
    @EnvironmentObject var appState: AppState
    @ObservedObject private var wrapStats = WrapStatsService.shared

    private let gridColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                periodPicker

                if vm.isLoading {
                    loadingPlaceholder
                } else if let error = vm.errorMessage {
                    errorCard(error)
                } else {
                    wrapLeagueSection
                    packingSpeedSection
                    completionRatesSection
                    volumeSection
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Reports")
        .refreshable { await vm.refresh() }
        .task {
            vm.deviceId = appState.deviceId
            await vm.refresh()
        }
    }

    // MARK: - Wrap League

    private var wrapLeagueSection: some View {
        let league = vm.summary.wrapLeague

        return VStack(alignment: .leading, spacing: 12) {
            Label("Wrap League", systemImage: "trophy.fill")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.orange)

            yourDayCard

            if league.wrappedBoxes == 0 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No wraps recorded yet")
                        .font(.subheadline.weight(.semibold))
                    Text("Wrap and close a box to start the team's clean streak.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                HStack(spacing: 12) {
                    WrapLeagueHero(
                        title: "Team clean streak",
                        value: "\(league.teamCleanStreak)",
                        subtitle: "boxes with no fix needed",
                        icon: "flame.fill",
                        color: .orange
                    )
                    WrapLeagueHero(
                        title: "Clean rate",
                        value: String(format: "%.0f%%", league.cleanWrapPercentage),
                        subtitle: "\(league.cleanWrappedBoxes) of \(league.wrappedBoxes) wrapped",
                        icon: "checkmark.seal.fill",
                        color: .green
                    )
                }

                if league.hasStandings {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Stations")
                            .font(.subheadline.weight(.semibold))

                        ForEach(Array(league.standings.enumerated()), id: \.element.id) { index, wrapper in
                            WrapperStandingRow(
                                rank: index + 1,
                                wrapper: wrapper,
                                isYou: wrapper.deviceId == appState.deviceId
                            )
                        }
                    }
                    .padding(16)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
                }

                Text("Panel boxes 3 pts, long boxes 2 pts, fitting kits 1 pt. Reopening your own box to fix it costs nothing — only a box someone else has to reopen loses its points.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
    }

    /// Local to this phone and always available, even offline.
    private var yourDayCard: some View {
        HStack(spacing: 12) {
            WrapLeagueHero(
                title: "Your boxes today",
                value: "\(wrapStats.boxesToday)",
                subtitle: wrapStats.bestDayBoxes > 0 ? "best day \(wrapStats.bestDayBoxes)" : "first day",
                icon: "shippingbox.fill",
                color: .blue
            )
            WrapLeagueHero(
                title: "Your points today",
                value: "\(wrapStats.pointsToday)",
                subtitle: vm.summary.wrapLeague.you.map { "\($0.points) pts this \(vm.selectedPeriod == .today ? "day" : "period")" } ?? "not on the board yet",
                icon: "star.fill",
                color: .yellow
            )
        }
    }

    // MARK: - Period Picker

    private var periodPicker: some View {
        Picker("Period", selection: $vm.selectedPeriod) {
            ForEach(ReportingPeriod.allCases) { period in
                Text(period.rawValue).tag(period)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Packing Speed

    private var packingSpeedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Packing Speed", systemImage: "gauge.with.dots.needle.33percent")
                .font(.title3)
                .fontWeight(.semibold)

            LazyVGrid(columns: gridColumns, spacing: 12) {
                ReportStatCard(
                    title: "Avg Completion",
                    value: formatMinutes(vm.summary.packingSpeed.averageCompletionMinutes),
                    subtitle: "per consignment",
                    accentColor: .blue
                )

                ReportStatCard(
                    title: "Items Scanned",
                    value: "\(vm.summary.packingSpeed.itemsScannedInPeriod)",
                    subtitle: vm.selectedPeriod.rawValue.lowercased(),
                    accentColor: .blue
                )
            }

            ReportStatCard(
                title: "Items Per Day",
                value: String(format: "%.0f", vm.summary.packingSpeed.averageItemsPerDay),
                subtitle: "average",
                accentColor: .blue
            )
        }
    }

    // MARK: - Completion Rates

    private var completionRatesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Completion Rates", systemImage: "checkmark.circle")
                .font(.title3)
                .fontWeight(.semibold)

            // Completion percentage bar
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Completion")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.0f%%", vm.summary.completionRates.completionPercentage))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.green)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.quaternary)
                            .frame(height: 12)

                        RoundedRectangle(cornerRadius: 6)
                            .fill(.green)
                            .frame(
                                width: geo.size.width * min(vm.summary.completionRates.completionPercentage / 100.0, 1.0),
                                height: 12
                            )
                    }
                }
                .frame(height: 12)
            }
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 8, y: 4)

            LazyVGrid(columns: gridColumns, spacing: 12) {
                ReportStatCard(
                    title: "Completed",
                    value: "\(vm.summary.completionRates.completedConsignments)",
                    subtitle: "consignments",
                    accentColor: .green
                )

                ReportStatCard(
                    title: "Open",
                    value: "\(vm.summary.completionRates.openConsignments)",
                    subtitle: "consignments",
                    accentColor: .orange
                )

                ReportStatCard(
                    title: "Boxes Packed",
                    value: "\(vm.summary.completionRates.totalBoxesPacked)",
                    subtitle: "total",
                    accentColor: .green
                )

                ReportStatCard(
                    title: "Avg Boxes",
                    value: String(format: "%.1f", vm.summary.completionRates.averageBoxesPerConsignment),
                    subtitle: "per consignment",
                    accentColor: .green
                )
            }
        }
    }

    // MARK: - Volume

    private var volumeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Volume", systemImage: "chart.bar.fill")
                .font(.title3)
                .fontWeight(.semibold)

            LazyVGrid(columns: gridColumns, spacing: 12) {
                ReportStatCard(
                    title: "Consignments",
                    value: "\(vm.summary.volume.totalConsignments)",
                    subtitle: vm.selectedPeriod.rawValue.lowercased(),
                    accentColor: .purple
                )

                ReportStatCard(
                    title: "Boxes",
                    value: "\(vm.summary.volume.totalBoxes)",
                    subtitle: vm.selectedPeriod.rawValue.lowercased(),
                    accentColor: .purple
                )
            }

            ReportStatCard(
                title: "Items Scanned",
                value: "\(vm.summary.volume.totalItemsScanned)",
                subtitle: vm.selectedPeriod.rawValue.lowercased(),
                accentColor: .purple
            )
        }
    }

    // MARK: - Helpers

    private var loadingPlaceholder: some View {
        VStack(spacing: 16) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.quaternary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 100)
            }
        }
    }

    private func errorCard(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") { Task { await vm.refresh() } }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func formatMinutes(_ minutes: Double) -> String {
        if minutes == 0 { return "—" }
        if minutes < 60 { return String(format: "%.0fm", minutes) }
        let h = Int(minutes) / 60
        let m = Int(minutes) % 60
        if m == 0 { return "\(h)h" }
        return "\(h)h \(m)m"
    }
}

// MARK: - Wrap League Components

private struct WrapLeagueHero: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct WrapperStandingRow: View {
    let rank: Int
    let wrapper: WrapperStanding
    let isYou: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text("\(rank)")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(rank == 1 ? .orange : .secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(wrapper.name)
                        .font(.subheadline.weight(.semibold))
                    if isYou {
                        Text("YOU")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.18), in: Capsule())
                            .foregroundStyle(.blue)
                    }
                }
                Text("\(wrapper.cleanWrappedBoxes) clean of \(wrapper.wrappedBoxes) wrapped · \(Int(wrapper.cleanWrapPercentage.rounded()))% quality")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(wrapper.points) pts")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.orange)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            isYou ? Color.blue.opacity(0.08) : Color.clear,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }
}

// MARK: - Stat Card (local to Reports)

private struct ReportStatCard: View {
    let title: String
    let value: String
    let subtitle: String
    var accentColor: Color = .blue

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(accentColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
    }
}
